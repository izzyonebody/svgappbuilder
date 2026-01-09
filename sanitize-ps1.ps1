param(
    [string[]] $Paths = @(),
    [switch]   $DryRun,
    [switch]   $Fix,
    [switch]   $Backup,
    [string]   $BackupFolder = '',
    [switch]   $Yes,
    [int]      $TabsToSpaces = 4,
    [ValidateSet('CRLF','LF')]
    [string]   $LineEnding = 'CRLF',
    [switch]   $Verbose
)

if ($Verbose) { $VerbosePreference = 'Continue' }

# Default extensions to sanitize
$exts = '.ps1','.py','.md','.txt','.json','.yaml','.yml','.js','.ts'

function Get-FilesToProcess {
    param([string[]] $PathsIn)
    if ($PathsIn -and $PathsIn.Count -gt 0) {
        return $PathsIn
    }
    $cur = Get-Location
    return Get-ChildItem -Path $cur -Recurse -File -ErrorAction SilentlyContinue |
           Where-Object { $exts -contains $_.Extension.ToLower() } |
           Select-Object -ExpandProperty FullName
}

function Read-AllTextWithEncoding {
    param([string] $Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $enc = [System.Text.Encoding]::UTF8
        $text = $enc.GetString($bytes, 3, $bytes.Length - 3)
        return ,$enc, $text
    } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        $enc = [System.Text.Encoding]::Unicode
        $text = $enc.GetString($bytes, 2, $bytes.Length - 2)
        return ,$enc, $text
    } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        $enc = [System.Text.Encoding]::BigEndianUnicode
        $text = $enc.GetString($bytes, 2, $bytes.Length - 2)
        return ,$enc, $text
    } else {
        $enc = [System.Text.Encoding]::UTF8
        try {
            $text = $enc.GetString($bytes)
            return ,$enc, $text
        } catch {
            $enc = [System.Text.Encoding]::Default
            $text = $enc.GetString($bytes)
            return ,$enc, $text
        }
    }
}

function Normalize-Content {
    param(
        [string] $Text,
        [int] $TabsToSpaces,
        [string] $LineEnding
    )

    # Convert tabs to spaces
    if ($TabsToSpaces -gt 0) {
        $spaces = ' ' * $TabsToSpaces
        $Text = $Text -replace "`t", $spaces
    }

    # Normalize to LF internally, then convert to target newline
    $Text = $Text -replace "`r`n", "`n"
    $Text = $Text -replace "`r", "`n"

    # Trim trailing whitespace per line
    $lines = $Text -split "`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $lines[$i] = $lines[$i].TrimEnd()
    }

    $newline = if ($LineEnding -eq 'CRLF') { "`r`n" } else { "`n" }
    $Text = ($lines -join $newline)

    # Ensure file ends with a single newline
    if (-not $Text.EndsWith($newline)) {
        $Text = $Text + $newline
    }

    return $Text
}

function Ensure-Backup {
    param(
        [string] $FilePath,
        [string] $BackupFolder
    )
    try {
        if (-not (Test-Path -LiteralPath $BackupFolder)) {
            New-Item -ItemType Directory -Path $BackupFolder -Force | Out-Null
        }
        # preserve relative path under backup folder
        $full = [System.IO.Path]::GetFullPath($FilePath)
        try {
            $repoTop = (git rev-parse --show-toplevel 2>$null).Trim()
        } catch {
            $repoTop = $null
        }
        if ($repoTop) {
            $relPath = $full.Substring($repoTop.Length).TrimStart('\','/')
        } else {
            $relPath = [System.IO.Path]::GetFileName($FilePath)
        }
        $dest = Join-Path -Path $BackupFolder -ChildPath $relPath
        $destDir = Split-Path -Path $dest -Parent
        if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        Copy-Item -LiteralPath $FilePath -Destination $dest -Force -ErrorAction Stop
        return $dest
    } catch {
        Write-Warning "Failed to write backup for $FilePath to $BackupFolder: $_"
        return $null
    }
}

function Process-File {
    param(
        [string] $Path,
        [int] $TabsToSpaces,
        [string] $LineEnding,
        [switch] $DryRun,
        [switch] $Fix,
        [switch] $Backup,
        [string] $BackupFolder
    )

    try {
        $read = Read-AllTextWithEncoding -Path $Path
        $origEnc = $read[0]
        $origText = $read[1]
    } catch {
        Write-Warning "Failed to read file: $Path — $_"
        return @{ Changed = $false; Failed = $true }
    }

    $newText = Normalize-Content -Text $origText -TabsToSpaces $TabsToSpaces -LineEnding $LineEnding

    if ($newText -eq $origText) {
        Write-Verbose "No changes for: $Path"
        return @{ Changed = $false; Failed = $false }
    }

    if ($DryRun -or (-not $Fix)) {
        Write-Host "[Dry-run] Would sanitize: $Path"
        return @{ Changed = $true; Failed = $false }
    }

    # We are fixing
    if ($Backup) {
        if ($BackupFolder) {
            $bakPath = Ensure-Backup -FilePath $Path -BackupFolder $BackupFolder
            if ($bakPath) { Write-Verbose "Backup written to: $bakPath" }
        } else {
            $bak = "$Path.bak"
            try {
                Copy-Item -LiteralPath $Path -Destination $bak -Force -ErrorAction Stop
                Write-Verbose "Backup written: $bak"
            } catch {
                Write-Warning "Failed to write backup for $Path: $_"
            }
        }
    }

    try {
        # Write as UTF8 without BOM
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($Path, $newText, $utf8NoBom)
        Write-Host "Sanitized: $Path"
        return @{ Changed = $true; Failed = $false }
    } catch {
        Write-Warning "Failed to write sanitized content to $Path: $_"
        return @{ Changed = $false; Failed = $true }
    }
}

# Main
$files = Get-FilesToProcess -PathsIn $Paths

if (-not $files -or $files.Count -eq 0) {
    Write-Host "No files to process." -ForegroundColor Yellow
    exit 0
}

if ($Fix -and -not $Yes) {
    $r = Read-Host "About to modify $($files.Count) files. Continue? (Y/N)"
    if ($r -notin @('Y','y','Yes','yes')) {
        Write-Host "Aborted." -ForegroundColor Yellow
        exit 0
    }
}

$changedAny = $false
$failedAny = $false
foreach ($f in $files) {
    $res = Process-File -Path $f -TabsToSpaces $TabsToSpaces -LineEnding $LineEnding -DryRun:$DryRun -Fix:$Fix -Backup:$Backup -BackupFolder $BackupFolder
    if ($res.Changed) { $changedAny = $true }
    if ($res.Failed) { $failedAny = $true }
}

# Exit codes:
# 0 = no changes needed or fix succeeded with no failures
# 3 = dry-run detected changes (useful for CI failing PRs)
# 1 = failures occurred
if ($failedAny) { exit 1 }
if ($DryRun -and $changedAny) { exit 3 }
exit 0
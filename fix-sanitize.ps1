<#
Fix script for sanitize-ps1.ps1
Saves a timestamped backup, patches param block, replaces Join-String with -join,
and normalizes a few problematic warning lines so the script runs on Windows PowerShell 5.1.
Run this from the repository root containing sanitize-ps1.ps1.
#>

Write-Host "== fix-sanitize.ps1 starting (run from repository root) =="
Write-Host "PowerShell version:" -NoNewline; $PSVersionTable.PSVersion | Write-Host

$target = ".\sanitize-ps1.ps1"
if (-not (Test-Path $target)) {
    Write-Error "File not found: $target (run this script from the repo root containing sanitize-ps1.ps1)."
    exit 1
}

# Create a backup
$ts = (Get-Date).ToString("yyyyMMdd-HHmmss")
$backup = ".\sanitize-ps1.ps1.bak.$ts"
Copy-Item -LiteralPath $target -Destination $backup -Force
Write-Host "Backup saved to $backup"

# Read lines
$origLines = Get-Content -LiteralPath $target -ErrorAction Stop
$lines = [System.Collections.Generic.List[string]]::new()
$origLines | ForEach-Object { [void]$lines.Add($_) }

# 1) Patch top-level param block: find first 'param(' and its matching ')' and replace block
$paramStart = $null
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s*param\s*\(') { $paramStart = $i; break }
}
if ($paramStart -ne $null) {
    # find matching closing parenthesis by counting parens across lines
    $depth = 0
    $found = $false
    for ($j = $paramStart; $j -lt $lines.Count; $j++) {
        $line = $lines[$j]
        $open = ([regex]::Matches($line, '\(')).Count
        $close = ([regex]::Matches($line, '\)')).Count
        $depth += $open - $close
        if ($depth -le 0) { $paramEnd = $j; $found = $true; break }
    }
    if (-not $found) {
        Write-Warning "Could not find end of top-level param(...) block; leaving param block unchanged."
    } else {
        $newParam = @(
'param(',
'    [Parameter(Position=0, Mandatory=$false)]',
'    [string[]] $Paths = @("*.ps1"),',
'    [switch] $Fix = $false,               # If provided, actually write changes; otherwise dry-run',
'    [int] $TabsToSpaces = 0,              # 0 = do not convert; otherwise number of spaces',
'    [switch] $Backup = $true,',
'    [switch] $Force = $false,             # apply without confirmation',
'    [switch] $VerboseLogs = $false',
')'
        )
        for ($k = $paramEnd; $k -ge $paramStart; $k--) { $lines.RemoveAt($k) }
        for ($k = 0; $k -lt $newParam.Count; $k++) { $lines.Insert($paramStart + $k, $newParam[$k]) }
        Write-Host "Patched top-level param(...) block (lines $($paramStart+1)-$($paramStart+$newParam.Count))."
    }
} else {
    Write-Warning "No top-level param(...) found; no param block patched."
}

# 2) Replace Join-String occurrences with -join compatible expression (preserve indentation)
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match 'Join-String') {
        $indent = ""
        if ($lines[$i] -match '^(?<ws>\s*)') { $indent = $matches['ws'] }
        $replacement = $indent + '$text = (($text -split "`r`n") | ForEach-Object { $_ -replace "\s+$", "" }) -join "`r`n"'
        $lines[$i] = $replacement
        Write-Host "Replaced Join-String on line $($i+1)."
    }
}

# 3) Normalize a few Write-Warning patterns that may have unescaped variable syntax
$fixPatterns = @(
    @{Match='Unable to read'; Replacement='Write-Warning "Unable to read ${file}: ${_}"'},
    @{Match='Backup failed for'; Replacement='Write-Warning "Backup failed for ${file}: ${_}"'},
    @{Match='Failed to write'; Replacement='Write-Warning "Failed to write ${file}: ${_}"'}
)
for ($i = 0; $i -lt $lines.Count; $i++) {
    foreach ($pat in $fixPatterns) {
        if ($lines[$i] -match ($pat.Match)) {
            $indent = ""
            if ($lines[$i] -match '^(?<ws>\s*)') { $indent = $matches['ws'] }
            $lines[$i] = $indent + $pat.Replacement
            Write-Host "Normalized Write-Warning for pattern '$($pat.Match)' on line $($i+1)."
            break
        }
    }
}

# 4) Replace obvious stray "$file: $_" occurrences with safe interpolation
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '\$file\s*:\s*\$_' ) {
        $indent = ""
        if ($lines[$i] -match '^(?<ws>\s*)') { $indent = $matches['ws'] }
        $lines[$i] = $indent + 'Write-Warning "Problem with ${file}: ${_}"'
Write-Host "Replaced stray `$file: `$_ usage on line $($i+1)."
    }
}

# Compare and write if changed
$changed = $false
$diff = @()
$max = [Math]::Max($origLines.Count, $lines.Count)
for ($i = 0; $i -lt $max; $i++) {
    $orig = if ($i -lt $origLines.Count) { $origLines[$i] } else { '' }
    $new = if ($i -lt $lines.Count) { $lines[$i] } else { '' }
    if ($orig -ne $new) {
        $changed = $true
        $diff += @{Line = $i+1; Old = $orig; New = $new}
    }
}

if ($changed) {
    $lines | Set-Content -LiteralPath $target -Encoding UTF8
    Write-Host "Wrote patched $target"
    Write-Host "Summary of changed lines:"
    foreach ($d in $diff) {
        Write-Host ("Line {0}:" -f $d.Line)
        Write-Host "  - OLD: $($d.Old)"
        Write-Host "  - NEW: $($d.New)"
    }
} else {
    Write-Host "No changes necessary to $target"
}

Write-Host "`nDone. Recommendations:"
Write-Host "- You're running PowerShell $($PSVersionTable.PSVersion). Join-String is not present in Windows PowerShell 5.1."
Write-Host "- Preferred: install PowerShell 7+ (pwsh) and run the script under pwsh to get modern cmdlets. Example:"
Write-Host "    pwsh -NoProfile -File .\sanitize-ps1.ps1 -Paths \$FILES -TabsToSpaces 4"
Write-Host "- Or run the fixed script in your current session (avoid positional-binding surprises):"
Write-Host "    \$FILES = Get-ChildItem -Recurse -Include *.ps1,*.py,*.md,*.txt,*.json,*.yaml,*.yml,*.js,*.ts -File | Select-Object -ExpandProperty FullName"
Write-Host "    .\sanitize-ps1.ps1 -Paths \$FILES -TabsToSpaces 4"
Write-Host ""
Write-Host "If anything still errors, copy the error text and the few lines around the reported line number and paste here and I'll help further."

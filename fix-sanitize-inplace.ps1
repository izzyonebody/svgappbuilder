<#
fix-sanitize-inplace.ps1
- Put this next to sanitize-ps1.ps1 and run it to apply in-place compatibility fixes.
- It:
  * creates a timestamped backup of sanitize-ps1.ps1
  * prepends a Join-String shim if missing
  * escapes literal "$file: $_" occurrences to "`$file: `$_"
  * converts simple " | Join-String '<sep>'" uses to "(... ) -join '<sep>'"
- Usage examples:
    .\fix-sanitize-inplace.ps1
    .\fix-sanitize-inplace.ps1 -Path ".\sanitize-ps1.ps1" -DryRun
#>

param(
    [string] $Path = ".\sanitize-ps1.ps1",
    [switch] $DryRun,
    [switch] $Verbose
)

function Log { param($m) if ($Verbose) { Write-Host $m } }

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Error "File not found: $Path"
    exit 2
}

# Create backup
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$backup = "$Path.bak.$ts"
Copy-Item -LiteralPath $Path -Destination $backup -Force
Write-Host "Backup saved to: $backup"

# Read file contents
$content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
$origContent = $content

# 1) Prepend compat shim if Join-String not present
if ($content -notmatch 'function\s+Join-String') {
$shim = @'
# BEGIN compat shim (inserted by fix-sanitize-inplace.ps1)
if (-not (Get-Command Join-String -ErrorAction SilentlyContinue)) {
    function Join-String {
        [CmdletBinding()]
        param(
            [Parameter(ValueFromPipeline=$true)]
            $InputObject,
            [string] $Separator = ''
        )
        begin { $script:__join_acc = @() }
        process {
            if ($null -eq $InputObject) { return }
            if ($InputObject -is [System.Array]) {
                $script:__join_acc += $InputObject
            } else {
                $script:__join_acc += $InputObject
            }
        }
        end {
            $out = $script:__join_acc -join $Separator
            Remove-Variable __join_acc -Scope Script -ErrorAction SilentlyContinue
            Write-Output $out
        }
    }
}
# END compat shim

'@
    Log "Adding Join-String shim to top of file."
    $content = $shim + $content
} else {
    Log "Join-String function already present; skipping shim."
}

# 2) Escape literal $file: $_ occurrences (replace "$file: $_" with "`$file: `$_")
# Use regex to find $file: $_ (allow optional spaces after colon)
$content = $content -replace '\$file:\s*\$_', '`$file: `$_'
Log "Escaped literal `$file: `$_ occurrences."

# 3) Convert simple " | Join-String 'sep'" occurrences into parenthesized -join variants.
# This handles lines that contain "| Join-String" with a separator literal following it.
$lines = $content -split "`r?`n"
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '\|\s*Join-String') {
        # Try to split at the first instance of "| Join-String"
        $splitPattern = '\|[ \t]*Join-String'
        $parts = [System.Text.RegularExpressions.Regex]::Split($lines[$i], $splitPattern, 2)
        if ($parts.Count -ge 2) {
            $left = $parts[0].TrimEnd()
            $right = $lines[$i].Substring($left.Length)  # original remainder (includes the | Join-String)
            # Extract the separator (everything after the Join-String token)
            # We want to produce: ( <left> ) -join <separator-and-rest>
            $afterJoin = $right -replace '^\s*\|\s*Join-String', ''  # remove the leading pipe and Join-String
            $afterJoin = $afterJoin.TrimStart()
            # If afterJoin is empty, skip transformation
            if ($afterJoin.Length -gt 0) {
                $newLine = '(' + $left + ') -join ' + $afterJoin
                Log "Transformed Join-String on line $($i+1):`n  OLD: $($lines[$i])`n  NEW: $newLine"
                $lines[$i] = $newLine
            } else {
                Log "Skipped Join-String transformation on line $($i+1) (no separator found)."
            }
        }
    }
}
$content = $lines -join "`r`n"

# Show diff in dry-run mode
if ($DryRun) {
    Write-Host "`n--- Dry run; not writing changes to $Path ---`n"
    $origLines = $origContent -split "`r?`n"
    $newLines = $content -split "`r?`n"
    Compare-Object -ReferenceObject $origLines -DifferenceObject $newLines -SyncWindow 0 | ForEach-Object {
        # Show concise diff-like output
        if ($_.SideIndicator -eq '<=') { Write-Host "OLD: $($_.InputObject)" -ForegroundColor DarkRed }
        elseif ($_.SideIndicator -eq '=>') { Write-Host "NEW: $($_.InputObject)" -ForegroundColor DarkGreen }
        else { Write-Host $_.InputObject }
    }
    Write-Host "`nDry-run complete. Backup was created at: $backup"
    exit 0
}

# Write patched content back to file
Set-Content -LiteralPath $Path -Value $content -Encoding UTF8
Write-Host "Patched $Path (backup at $backup)."

# End

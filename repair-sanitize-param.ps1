<#
repair-sanitize-param.ps1
- Put this next to sanitize-ps1.ps1 and run it to repair the accidental shim-before-param issue.
- It will:
    * create a timestamped backup of sanitize-ps1.ps1
    * locate a "# BEGIN compat shim" ... "# END compat shim" block (if present near the top),
      remove it from the top, and reinsert it immediately after the script's param(...) block.
- Usage:
    .\repair-sanitize-param.ps1         # actually apply fixes
    .\repair-sanitize-param.ps1 -DryRun # show what would change
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

$orig = Get-Content -LiteralPath $Path -Raw -Encoding UTF8

$shimStartMarker = "# BEGIN compat shim"
$shimEndMarker   = "# END compat shim"

$shimStartIdx = $orig.IndexOf($shimStartMarker, [System.StringComparison]::InvariantCultureIgnoreCase)
if ($shimStartIdx -lt 0) {
    Write-Host "No compat shim marker ('$shimStartMarker') found. Nothing to move."
    exit 0
}

if ($shimStartIdx -gt 200) {
    Write-Warning "Found compat shim, but it starts at character index $shimStartIdx (not near top). Proceeding anyway."
}

$shimEndIdx = $orig.IndexOf($shimEndMarker, $shimStartIdx, [System.StringComparison]::InvariantCultureIgnoreCase)
if ($shimEndIdx -lt 0) {
    Write-Error "Found shim start marker but no matching end marker ('$shimEndMarker'). Aborting."
    exit 3
}

$afterEnd = $shimEndIdx + $shimEndMarker.Length
# include following newline(s) if present
if ($afterEnd -lt $orig.Length) {
    if ($orig[$afterEnd] -eq "`r" -and ($afterEnd+1 -lt $orig.Length) -and $orig[$afterEnd+1] -eq "`n") { $afterEnd += 2 }
    elseif ($orig[$afterEnd] -eq "`r" -or $orig[$afterEnd] -eq "`n") { $afterEnd += 1 }
}

$shimText = $orig.Substring($shimStartIdx, $afterEnd - $shimStartIdx)
$withoutShim = $orig.Remove($shimStartIdx, $afterEnd - $shimStartIdx)

# Find param( ... ) block
$paramMatch = [System.Text.RegularExpressions.Regex]::Match($withoutShim, '\bparam\s*\(', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
if (-not $paramMatch.Success) {
    Write-Error "No 'param(' block found in the script after removing shim. Aborting to avoid corrupting file."
    exit 4
}

$startIdx = $paramMatch.Index
$depth = 0
$foundClose = $false
for ($i = $startIdx; $i -lt $withoutShim.Length; $i++) {
    $c = $withoutShim[$i]
    if ($c -eq '(') { $depth++ }
    elseif ($c -eq ')') {
        $depth--
        if ($depth -eq 0) {
            $paramCloseIdx = $i
            $foundClose = $true
            break
        }
    }
}
if (-not $foundClose) {
    Write-Error "Could not find the matching closing ')' for the param(...) block. Aborting."
    exit 5
}

$insertAfter = $paramCloseIdx + 1
if ($insertAfter -lt $withoutShim.Length) {
    if ($withoutShim[$insertAfter] -eq "`r" -and ($insertAfter+1 -lt $withoutShim.Length) -and $withoutShim[$insertAfter+1] -eq "`n") { $insertAfter += 2 }
    elseif ($withoutShim[$insertAfter] -eq "`r" -or $withoutShim[$insertAfter] -eq "`n") { $insertAfter += 1 }
}

$fixed = $withoutShim.Substring(0, $insertAfter) + "`r`n" + $shimText + "`r`n" + $withoutShim.Substring($insertAfter)

if ($DryRun) {
    Write-Host "`n--- Dry run: showing contextual preview ---`n"
    $beforeLines = $orig -split "`r?`n"
    $afterLines  = $fixed -split "`r?`n"
    Compare-Object -ReferenceObject $beforeLines -DifferenceObject $afterLines -SyncWindow 0 |
        ForEach-Object {
            if ($_.SideIndicator -eq '<=') { Write-Host "OLD: $($_.InputObject)" -ForegroundColor DarkRed }
            elseif ($_.SideIndicator -eq '=>') { Write-Host "NEW: $($_.InputObject)" -ForegroundColor DarkGreen }
            else { Write-Host $_.InputObject }
        }
    Write-Host "`nDry run complete. No files modified."
    exit 0
}

$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$backup = "$Path.bak.$ts"
Copy-Item -LiteralPath $Path -Destination $backup -Force
Set-Content -LiteralPath $Path -Value $fixed -Encoding UTF8
Write-Host "Patched $Path and created backup at $backup"

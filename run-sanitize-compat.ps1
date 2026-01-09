<#
run-sanitize-compat.ps1
- Put this in the same folder as sanitize-ps1.ps1
- It prefers to run under pwsh (PowerShell 7+). If pwsh is not present it loads a small compatibility shim
  (defines Join-String) into the current session then invokes sanitize-ps1.ps1.
- Usage examples:
    .\run-sanitize-compat.ps1 -- -Paths $FILES -TabsToSpaces 4 -Fix -Backup
  (The -- separates wrapper options from args passed to the target script.)
#>

param(
    [switch] $ForceUseCurrentPS,                       # if set, do NOT try pwsh; run in current PS
    [switch] $Verbose
)

function Write-Log { param($m) if ($Verbose) { Write-Host $m } }

$scriptDir = Split-Path -LiteralPath $MyInvocation.MyCommand.Path -Parent
Set-Location -LiteralPath $scriptDir

Write-Host "run-sanitize-compat.ps1 starting in: $scriptDir"
Write-Host "Current PowerShell: $($PSVersionTable.PSVersion)"

# Capture the remaining args (pass-thru to sanitize-ps1.ps1)
# When run as: .\run-sanitize-compat.ps1 -- -Paths $FILES -Fix
# everything after -- appears in $args; here we pass $args along.
$passThru = $args

# Target script
$target = Join-Path $scriptDir 'sanitize-ps1.ps1'
if (-not (Test-Path -LiteralPath $target)) {
    Write-Error "sanitize-ps1.ps1 not found in $scriptDir. Put this wrapper next to sanitize-ps1.ps1."
    exit 2
}

# If pwsh exists and user didn't force current PS, run there (recommended)
if (-not $ForceUseCurrentPS) {
    $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwshCmd) {
        Write-Host "PowerShell 7+ (pwsh) detected at: $($pwshCmd.Path)"
        Write-Host "Invoking sanitize-ps1.ps1 under pwsh (recommended). Passing arguments: $passThru"
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $target -- @passThru
        exit $LASTEXITCODE
    } else {
        Write-Log "pwsh not found; will run under current Windows PowerShell with compatibility shim."
    }
} else {
    Write-Log "Forced to run in current PowerShell session (ForceUseCurrentPS set)."
}

# Create and dot-source a compatibility shim for Windows PowerShell 5.1
$compatPath = Join-Path $scriptDir 'sanitize-ps1.compat.ps1'
$compatContent = @'
# Compatibility shim for Windows PowerShell 5.1
# Define Join-String if missing (simple compatibility implementation).
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
            # Flatten arrays and add items
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
'@

Set-Content -LiteralPath $compatPath -Value $compatContent -Encoding UTF8
Write-Log "Wrote compatibility shim to $compatPath"

# Dot-source the shim so functions are available to the target script
. $compatPath
Write-Host "Loaded compatibility shim (Join-String available). Now invoking sanitize-ps1.ps1 in current session."
Write-Host "Arguments passed to sanitize-ps1.ps1: $passThru"

# Run the target script in the current PowerShell process with the passed args.
# We use & so any output/exit code flows back; sanitize-ps1.ps1 should handle its -Fix/-Backup switches.
& $target @passThru
$exitCode = $LASTEXITCODE

# Optional cleanup: remove the compat file (function stays in session)
try { Remove-Item -LiteralPath $compatPath -ErrorAction SilentlyContinue } catch {}

Write-Host "sanitize-ps1.ps1 finished with exit code $exitCode"
exit $exitCode

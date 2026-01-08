param(
    [Parameter(Mandatory = $false)]
    [string] $Target,

    [Parameter(Mandatory = $false)]
    [int] $StartLine = 1,

    [Parameter(Mandatory = $false)]
    [int] $EndLine = 0,

    [switch] $All,

    [switch] $DryRun
)

# Prompt interactively for Target if missing
if (-not $Target) {
    if (-not [System.Environment]::UserInteractive) {
        Write-Error "No Target supplied and session is non-interactive. Use -Target <path>."
        exit 2
    }

    do {
        $Target = Read-Host -Prompt 'Target (path to file)'
        if ([string]::IsNullOrWhiteSpace($Target)) {
            Write-Host 'Target cannot be empty. Please enter a path.' -ForegroundColor Yellow
            $Target = $null
            continue
        }
        if (-not (Test-Path -LiteralPath $Target)) {
            Write-Host "File not found: $Target" -ForegroundColor Yellow
            $Target = $null
            continue
        }
        break
    } while ($true)
}

# Final validation
if (-not (Test-Path -LiteralPath $Target)) {
    Write-Error ("Target file not found: {0}" -f $Target)
    exit 2
}

try {
    $allLines = Get-Content -LiteralPath $Target -ErrorAction Stop -Encoding UTF8
} catch {
    Write-Error ("Failed to read file {0}: {1}" -f $Target, $_.Exception.Message)
    exit 3
}

# If -All specified or EndLine not set/<= 0, use file end
if ($All -or $EndLine -le 0) {
    $EndLine = $allLines.Count
}

# Ensure StartLine >= 1
if ($StartLine -lt 1) { $StartLine = 1 }

# Ensure EndLine >= StartLine
if ($EndLine -lt $StartLine) {
    Write-Warning "EndLine ($EndLine) is before StartLine ($StartLine). Adjusting EndLine to StartLine."
    $EndLine = $StartLine
}

Write-Verbose ("DEBUG: startLine=[{0}] type=[{1}]   endLine=[{2}] type=[{3}]" -f $StartLine, ($StartLine.GetType().Name), $EndLine, ($EndLine.GetType().Name))
Write-Host ("File lines {0}..{1}:" -f $StartLine, $EndLine)

$startIndex = [Math]::Max(0, $StartLine - 1)
$endIndex = [Math]::Min($allLines.Count - 1, $EndLine - 1)

if ($startIndex -gt $endIndex) {
    Write-Warning "Computed start index ($startIndex) is after end index ($endIndex). Nothing to show."
    exit 0
}

for ($i = $startIndex; $i -le $endIndex; $i++) {
    $lnNum = $i + 1
    Write-Host ("{0,5}: {1}" -f $lnNum, $allLines[$i])
}

if ($DryRun) {
    Write-Host "DryRun: no file changes will be made."
} else {
    Write-Host "Run without -DryRun to apply changes (if this script makes any)."
}

exit 0

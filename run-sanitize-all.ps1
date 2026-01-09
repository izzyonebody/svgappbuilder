param(
    [string] $Path = $null,
    [int]    $TabsToSpaces = 4,
    [ValidateSet('CRLF','LF')]
    [string] $LineEnding = 'CRLF',
    [switch] $DryRun,
    [switch] $Fix,
    [switch] $Backup,
    [string] $BackupFolder = '.sanitizer-backups',
    [switch] $Yes,
    [switch] $AutoCommit,    # commit changes if Fix performed
    [string] $CommitMessage = 'chore: run sanitizer (auto-fix)',
    [switch] $Push,          # push after commit
    [switch] $Verbose
)

if ($Verbose) { $VerbosePreference = 'Continue' }

if (-not $Path) {
    if ($PSScriptRoot) { $Path = $PSScriptRoot } else { $Path = (Get-Location).Path }
}

$sanitizePath = Join-Path -Path $Path -ChildPath 'sanitize-ps1.ps1'
if (-not (Test-Path -LiteralPath $sanitizePath)) {
    Write-Error 'sanitize-ps1.ps1 not found at: ' + $sanitizePath
    exit 2
}

# Default extensions (same as sanitize script)
$exts = '.ps1','.py','.md','.txt','.json','.yaml','.yml','.js','.ts'

Write-Host ('Scanning ''{0}'' for extensions: {1}' -f $Path, ($exts -join ', ')) -ForegroundColor Cyan
$FILES = Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue |
         Where-Object { $exts -contains $_.Extension.ToLower() } |
         Select-Object -ExpandProperty FullName

if (-not $FILES -or $FILES.Count -eq 0) {
    Write-Host 'No files matched; exiting.' -ForegroundColor Yellow
    exit 0
}

Write-Host ('Found {0} files.' -f $FILES.Count) -ForegroundColor Green

if ($Fix -and -not $Yes) {
    $msg = 'You are about to run sanitize-ps1.ps1 with -Fix on ' + $FILES.Count + ' files. Continue? (Y/N)'
    $r = Read-Host $msg
    if ($r -notin @('Y','y','Yes','yes')) {
        Write-Host 'Aborting.' -ForegroundColor Yellow
        exit 0
    }
}

$splat = @{
    Paths = $FILES
    TabsToSpaces = $TabsToSpaces
    LineEnding = $LineEnding
}
if ($DryRun) { $splat.DryRun = $true }
if ($Fix)    { $splat.Fix = $true }
if ($Backup) { $splat.Backup = $true }
if ($BackupFolder) { $splat.BackupFolder = $BackupFolder }
if ($Yes)    { $splat.Yes = $true }
if ($Verbose) { $splat.Verbose = $true }

Write-Host ('Invoking sanitize script: {0}' -f $sanitizePath) -ForegroundColor Cyan
Write-Host 'Parameters to pass:' -ForegroundColor Cyan
foreach ($kv in $splat.GetEnumerator()) {
    $val = $kv.Value
    if ($val -is [System.Array]) {
        Write-Host ('  {0} = [array:{1}]' -f $kv.Key, $val.Count)
    } else {
        Write-Host ('  {0} = {1}' -f $kv.Key, $val)
    }
}

# Call the sanitize script
& $sanitizePath @splat
$cmdSucceeded = $?
$last = $LASTEXITCODE

if ($last -ne $null) {
    $exitCode = $last
} elseif (-not $cmdSucceeded) {
    $exitCode = 1
} else {
    $exitCode = 0
}

if ($exitCode -eq 3 -and $DryRun) {
    Write-Error "Sanitizer would make changes (dry-run detected changes)."
    exit 3
} elseif ($exitCode -ne 0) {
    Write-Warning ("sanitize-ps1.ps1 exited with code {0}" -f $exitCode)
    exit $exitCode
}

# If we performed Fix and AutoCommit requested, commit and optionally push
if ($Fix -and $AutoCommit) {
    # Check git availability
    try {
        git --version > $null 2>&1
    } catch {
        Write-Warning "git not available; cannot auto-commit."
        exit 0
    }

    # Stage changes
    git add -A

    # Are there any staged changes?
    $porcelain = git status --porcelain
    if (-not [string]::IsNullOrWhiteSpace($porcelain)) {
        git config user.name "github-actions[bot]" 2>$null
        git config user.email "41898282+github-actions[bot]@users.noreply.github.com" 2>$null
        git commit -m $CommitMessage
        if ($Push) {
            # Ensure persistent credentials are available in CI (actions/checkout sets this when allowed)
            git push
        }
        Write-Host "Auto-commit performed."
    } else {
        Write-Host "No changes to commit."
    }
}

Write-Host 'sanitize-ps1.ps1 completed.' -ForegroundColor Green
exit 0
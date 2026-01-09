<#
run-cleanup.ps1
I am GPT-5.2 Pro.

Purpose:
- Create a safe branch and run a guided, reviewable cleanup:
  1) Dry-run sanitize
  2) Optionally apply sanitize (creates .bak files)
  3) Dry-run encoding conversion
  4) Optionally apply encoding conversion (creates .bak files)
  5) Offer to commit changes (or run convert with auto-commit)
- Uses sanitize-ps1.ps1 and convert-and-commit.ps1 expected in the repo root.
- Conservative by default; asks confirmation at each destructive step.

Usage:
  pwsh -ExecutionPolicy Bypass -File .\run-cleanup.ps1
#>

param(
    [string]$BranchBase = "cleanup/sanitize-encodings",
    [int]$TabsToSpaces = 4,
    [switch]$AutoApprove    # if set, apply changes without prompting
)

function Write-Title([string]$t) { Write-Host "`n== $t ==" -ForegroundColor Cyan }

function Run-Git([string[]]$args) {
    $proc = Start-Process -FilePath git -ArgumentList $args -NoNewWindow -Wait -PassThru -RedirectStandardOutput -RedirectStandardError
    $out = $proc.StandardOutput.ReadToEnd()
    $err = $proc.StandardError.ReadToEnd()
    if ($out) { Write-Host $out }
    if ($err) { Write-Host $err -ForegroundColor Red }
    return $proc.ExitCode
}

# Ensure running from repo root
try {
    $gitRoot = (& git rev-parse --show-toplevel) 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $gitRoot) {
        Write-Warning "Not inside a git repository. Running from current directory."
        $gitRoot = (Get-Location).Path
    }
} catch {
    Write-Warning "git not available; continuing in current directory."
    $gitRoot = (Get-Location).Path
}
Set-Location $gitRoot
Write-Host "Repo root: $gitRoot" -ForegroundColor DarkCyan

# Check helper scripts
$sanitize = Join-Path $gitRoot "sanitize-ps1.ps1"
$convert = Join-Path $gitRoot "convert-and-commit.ps1"
if (-not (Test-Path $sanitize)) {
    Write-Warning "Missing helper: sanitize-ps1.ps1 in repo root. Recreate using write-scripts.ps1 or add manually."
}
if (-not (Test-Path $convert)) {
    Write-Warning "Missing helper: convert-and-commit.ps1 in repo root. Recreate using write-scripts.ps1 or add manually."
}

# Build file list
$globs = @("*.ps1","*.py","*.md","*.txt","*.json","*.yaml","*.yml","*.js","*.ts")
Write-Title "Collecting files to scan"
$FILES = Get-ChildItem -Recurse -Include $globs -File -ErrorAction SilentlyContinue | Where-Object { -not ($_.FullName -like "$gitRoot\.git*") } | Select-Object -ExpandProperty FullName
if (-not $FILES -or $FILES.Count -eq 0) {
    Write-Host "No files found by the globs: $($globs -join ', ')" -ForegroundColor Yellow
    exit 0
}
Write-Host ("Found {0} files" -f $FILES.Count)

# Create or switch to branch
Write-Title "Branch"
$branch = $BranchBase
# if branch exists, create a unique name
$exists = (& git rev-parse --verify --quiet $branch) 2>$null
if ($LASTEXITCODE -eq 0) {
    $timestamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
    $branch = "$BranchBase-$timestamp"
    Write-Host "Branch $BranchBase exists; using new branch name: $branch"
}
$rc = Run-Git @("switch", "-c", $branch)
if ($rc -ne 0) {
    Write-Warning "Failed to create/switch to branch $branch. You may need to create manually."
} else {
    Write-Host "Now on branch: $branch" -ForegroundColor Green
}

# Step 1: Dry-run sanitize
Write-Title "Step 1: Dry-run sanitize"
if (-not (Test-Path $sanitize)) {
    Write-Warning "sanitize-ps1.ps1 not found; skipping sanitize steps."
} else {
    Write-Host "Dry-run (no writes) of sanitize script. Output follows:"
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $sanitize -Paths $FILES
}

# Ask to apply sanitize
$doSanitize = $false
if (Test-Path $sanitize) {
    if ($AutoApprove) { $doSanitize = $true }
    else {
        $ans = Read-Host "Apply sanitize to the listed files now? (creates .bak files) (y/N)"
        if ($ans -in @('y','Y','yes','Yes')) { $doSanitize = $true }
    }
    if ($doSanitize) {
        Write-Title "Applying sanitize (backups will be created)"
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $sanitize -Paths $FILES -Fix -TabsToSpaces $TabsToSpaces -Force
        Write-Host "Sanitize complete. Backups (*.bak) created for changed files." -ForegroundColor Green
    } else {
        Write-Host "Skipping sanitize." -ForegroundColor Yellow
    }
}

# Step 2: Dry-run convert (what-if)
Write-Title "Step 2: Dry-run encoding conversion"
if (-not (Test-Path $convert)) {
    Write-Warning "convert-and-commit.ps1 not found; skipping conversion steps."
} else {
    Write-Host "Dry-run encoding conversion (WhatIf):"
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $convert -Paths $FILES -WhatIf
}

# Ask to apply convert
$doConvert = $false
if (Test-Path $convert) {
    if ($AutoApprove) { $doConvert = $true }
    else {
        $ans2 = Read-Host "Apply encoding conversion to the listed files now? (creates .bak files) (y/N)"
        if ($ans2 -in @('y','Y','yes','Yes')) { $doConvert = $true }
    }
    if ($doConvert) {
        # ask whether to auto-commit
        $doAutoCommit = $false
        if ($AutoApprove) { $doAutoCommit = $false } # default: do not auto-commit even in AutoApprove
        else {
            $ac = Read-Host "Automatically stage & commit the changed files after convert? (y/N)"
            if ($ac -in @('y','Y','yes','Yes')) { $doAutoCommit = $true }
        }

        if ($doAutoCommit) {
            $msg = Read-Host "Commit message (or press Enter for default)"
            if ([string]::IsNullOrWhiteSpace($msg)) { $msg = "Normalize encodings to UTF-8 (no BOM) and sanitize whitespace" }
            Write-Title "Running convert-and-commit with PerformCommit"
            & pwsh -NoProfile -ExecutionPolicy Bypass -File $convert -Paths $FILES -PerformCommit -CommitMessage $msg
        } else {
            Write-Title "Running convert-and-commit (no automatic commit)"
            & pwsh -NoProfile -ExecutionPolicy Bypass -File $convert -Paths $FILES
            Write-Host "Conversion complete. Backups (*.bak) created for changed files." -ForegroundColor Green
        }
    } else {
        Write-Host "Skipping conversion." -ForegroundColor Yellow
    }
}

# Step 3: Show git status and diffs
Write-Title "Step 3: Review changes"
Write-Host "Git status:"
Run-Git @("status", "--short", "--branch")
Write-Host "`nTo review diffs, run: git diff"
Write-Host "To list changed files: git diff --name-only"

# Offer to commit if changes present
if ((& git status --porcelain) -ne "") {
    $commitNow = $false
    if ($AutoApprove) {
        $commitNow = $false
    } else {
        $c = Read-Host "Stage all changes and commit now? (y/N)"
        if ($c -in @('y','Y','yes','Yes')) { $commitNow = $true }
    }
    if ($commitNow) {
        $cm = Read-Host "Commit message (or press Enter for default)"
        if ([string]::IsNullOrWhiteSpace($cm)) { $cm = "Sanitize whitespace and normalize encodings to UTF-8 (no BOM)" }
        Run-Git @("add", "-A")
        $rc2 = Run-Git @("commit", "-m", $cm)
        if ($rc2 -eq 0) { Write-Host "Committed changes." -ForegroundColor Green }
        else { Write-Warning "Commit failed." }
    } else {
        Write-Host "No commit performed. You can inspect and commit manually." -ForegroundColor Yellow
    }
} else {
    Write-Host "No workspace changes detected after operations." -ForegroundColor Green
}

Write-Title "Done"
Write-Host "Backups for modified files have .bak appended; restore any file by copying from .bak if needed."
Write-Host "Example to restore a file:"
Write-Host '  Copy-Item -LiteralPath ".\path\to\file.ext.bak" -Destination ".\path\to\file.ext" -Force' -ForegroundColor Gray

# End of script
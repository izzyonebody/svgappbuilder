<#
project-assistant.ps1
I am GPT-5.2 Pro.

Purpose:
- Inspect a Git repo and surface common issues (encoding/BOM, trailing whitespace, tabs, line endings).
- Show git status and untracked/unstaged files.
- Suggest and optionally run fixes using sanitize-ps1.ps1 and convert-and-commit.ps1 (which this repo already contains).
- Optionally install a lightweight pre-commit hook that runs checks, or register a Windows scheduled task to run daily.

Usage:
  # Interactive menu:
  pwsh -ExecutionPolicy Bypass -File .\project-assistant.ps1

  # Non-interactive actions:
  pwsh -ExecutionPolicy Bypass -File .\project-assistant.ps1 -AutoRun -Fix -PerformConvert

  # Install pre-commit hook (interactive confirmation):
  pwsh -ExecutionPolicy Bypass -File .\project-assistant.ps1 -InstallHook

  # Register daily scheduled task (CurrentUser):
  pwsh -ExecutionPolicy Bypass -File .\project-assistant.ps1 -ScheduleDaily

Notes:
- This script is conservative by default: most actions require confirmation or explicit flags (-Fix, -PerformConvert).
- It expects sanitize-ps1.ps1 and convert-and-commit.ps1 to live in the same repo root. If not present, it will prompt to create or skip those actions.
#>

param(
    [switch]$AutoRun,           # non-interactive: accept defaults for menus
    [switch]$Fix,               # perform fix actions for sanitize (non-interactive)
    [switch]$PerformConvert,    # run conversion script to change encodings (non-interactive)
    [switch]$InstallHook,       # install pre-commit hook
    [switch]$ScheduleDaily,     # register a daily scheduled task (Windows only)
    [string]$HookName = "project-assistant-pre-commit",
    [switch]$Verbose
)

function Write-Title($t) { Write-Host "`n== $t ==" -ForegroundColor Cyan }

function Get-GitRoot {
    try {
        $top = (& git rev-parse --show-toplevel) 2>$null
        if ($LASTEXITCODE -eq 0 -and $top) { return (Get-Item $top).FullName }
    } catch {}
    return (Get-Location).Path
}

function Show-GitStatus {
    Write-Title "Git status"
    try {
        & git status --porcelain=1 --branch
    } catch {
        Write-Warning "Not a git repository or git not found."
    }
}

function Find-Files {
    param([string[]]$globs)
    $found = @()
    foreach ($g in $globs) {
        try {
            $items = Get-ChildItem -Path $g -File -Recurse -ErrorAction SilentlyContinue
            if ($items) { $found += $items.FullName }
        } catch {
            if (Test-Path $g) { $found += (Get-Item -LiteralPath $g).FullName }
        }
    }
    return ($found | Sort-Object -Unique)
}

function Detect-EncodingIssues {
    param([string[]]$files)
    $bomFiles = @()
    $nonUtf8Files = @()
    foreach ($f in $files) {
        try {
            $bytes = [System.IO.File]::ReadAllBytes($f)
        } catch { continue }
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            $bomFiles += $f
        } elseif ($bytes.Length -ge 2 -and ($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE -or $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF)) {
            $bomFiles += $f
        } else {
            # try decode as UTF8
            try {
                $utf8 = New-Object System.Text.UTF8Encoding($false,$true)
                $utf8.GetString($bytes) | Out-Null
            } catch {
                $nonUtf8Files += $f
            }
        }
    }
    return @{bom=$bomFiles; nonUtf8=$nonUtf8Files}
}

function Detect-WhitespaceIssues {
    param([string[]]$files)
    $trailing = @()
    $tabs = @()
    $mixedEol = @()
    foreach ($f in $files) {
        try { $text = Get-Content -Raw -LiteralPath $f -ErrorAction Stop } catch { continue }
        if ($text -match "[ \t]+\r?$" -or ($text -split "(`r?`n)" | Where-Object { $_ -match "[ \t]+$" })) {
            $trailing += $f
        }
        if ($text -match "`t") { $tabs += $f }
        # detect files with LF-only or mixed CRLF/LF
        if ($text -match "(`r`n)" -and $text -match "(?<!`r)`\n") {
            $mixedEol += $f
        } elseif ($text -match "(?<!`r)`\n" -and -not ($text -match "`r`n")) {
            # LF-only
            $mixedEol += $f
        }
    }
    return @{trailing=$trailing; tabs=$tabs; eol=$mixedEol}
}

function Suggest-Actions {
    param($encodingReport, $wsReport, $files)
    Write-Title "Summary / Suggestions"
    $any = $false

    if ($encodingReport.bom.Count -gt 0) {
        Write-Host ("Files with BOM/UTF-16 signatures: {0}" -f $encodingReport.bom.Count) -ForegroundColor Yellow
        if ($Verbose) { $encodingReport.bom | ForEach-Object { Write-Host "  $_" } }
        Write-Host "Suggested action: run sanitize-ps1.ps1 to remove BOMs, or convert-and-commit.ps1 to normalize encoding." -ForegroundColor Gray
        $any = $true
    }

    if ($encodingReport.nonUtf8.Count -gt 0) {
        Write-Host ("Files that failed UTF-8 decode: {0}" -f $encodingReport.nonUtf8.Count) -ForegroundColor Red
        if ($Verbose) { $encodingReport.nonUtf8 | ForEach-Object { Write-Host "  $_" } }
        Write-Host "Suggested action: inspect these files manually or use convert-and-commit.ps1 with caution (backups will be created)." -ForegroundColor Gray
        $any = $true
    }

    if ($wsReport.trailing.Count -gt 0) {
        Write-Host ("Files with trailing whitespace: {0}" -f $wsReport.trailing.Count) -ForegroundColor Yellow
        if ($Verbose) { $wsReport.trailing | ForEach-Object { Write-Host "  $_" } }
        Write-Host "Suggested action: run sanitize-ps1.ps1 -Fix to trim trailing spaces." -ForegroundColor Gray
        $any = $true
    }
    if ($wsReport.tabs.Count -gt 0) {
        Write-Host ("Files with tabs: {0}" -f $wsReport.tabs.Count) -ForegroundColor Yellow
        if ($Verbose) { $wsReport.tabs | ForEach-Object { Write-Host "  $_" } }
        Write-Host "Suggested action: run sanitize-ps1.ps1 -Fix -TabsToSpaces 4 (or your preferred width)." -ForegroundColor Gray
        $any = $true
    }
    if ($wsReport.eol.Count -gt 0) {
        Write-Host ("Files with mixed/LF-only EOL: {0}" -f $wsReport.eol.Count) -ForegroundColor Yellow
        if ($Verbose) { $wsReport.eol | ForEach-Object { Write-Host "  $_" } }
        Write-Host "Suggested action: normalize line endings via sanitize-ps1.ps1 or convert script." -ForegroundColor Gray
        $any = $true
    }

    if (-not $any) {
        Write-Host "No immediate issues detected (encoding/whitespace) in scanned files." -ForegroundColor Green
    }
}

function Ensure-ScriptsExist {
    param([string]$root)
    $s1 = Join-Path $root "sanitize-ps1.ps1"
    $s2 = Join-Path $root "convert-and-commit.ps1"
    $missing = @()
    if (-not (Test-Path $s1)) { $missing += $s1 }
    if (-not (Test-Path $s2)) { $missing += $s2 }
    return $missing
}

function Run-Sanitize {
    param([string[]]$files, [switch]$fix, [int]$tabsToSpaces=0, [switch]$force)
    $script = Join-Path (Get-GitRoot) "sanitize-ps1.ps1"
    if (-not (Test-Path $script)) { Write-Warning "sanitize-ps1.ps1 not found in repo root."; return }
    $pathsArg = @()
    foreach ($f in $files) { $pathsArg += $f }
    if ($fix) {
        $args = @("-Paths") + $pathsArg + @("-Fix")
        if ($tabsToSpaces -gt 0) { $args += @("-TabsToSpaces",$tabsToSpaces) }
        if ($force) { $args += "-Force" }
    } else {
        $args = @("-Paths") + $pathsArg
    }
    Write-Host "Invoking sanitize script: $script" -ForegroundColor Cyan
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $script @args
}

function Run-Convert {
    param([string[]]$files, [switch]$performCommit)
    $script = Join-Path (Get-GitRoot) "convert-and-commit.ps1"
    if (-not (Test-Path $script)) { Write-Warning "convert-and-commit.ps1 not found in repo root."; return }
    $args = @("-Paths") + $files
    if ($performCommit) { $args += @("-PerformCommit") }
    Write-Host "Invoking convert script: $script" -ForegroundColor Cyan
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $script @args
}

function Install-PreCommitHook {
    param([string]$root)
    $hooksDir = Join-Path $root ".git\hooks"
    if (-not (Test-Path $hooksDir)) {
        Write-Warning "Not a git repository (no .git/hooks). Cannot install hook."
        return
    }
    $hookPath = Join-Path $hooksDir "pre-commit"
    $scriptSelf = (Get-Item -LiteralPath $MyInvocation.MyCommand.Path).FullName
    $hookContent = @"
#!/usr/bin/env pwsh
# Pre-commit hook inserted by project-assistant.ps1
# Run lightweight checks and prevent commit if critical issues found.

param()
\$here = Split-Path -Parent \$MyInvocation.MyCommand.Definition
# run project assistant in non-interactive mode to check for blocking issues
pwsh -NoProfile -ExecutionPolicy Bypass -File "$scriptSelf" -AutoRun -CheckOnly | Out-Host
if (\$LASTEXITCODE -ne 0) {
    Write-Host "Pre-commit hook: checks failed. Commit aborted." -ForegroundColor Red
    exit 1
}
exit 0
"@
    try {
        $hookContent | Out-File -FilePath $hookPath -Encoding ascii -Force
        if (Get-Command chmod -ErrorAction SilentlyContinue) { & chmod +x $hookPath }
        Write-Host "Installed pre-commit hook at: $hookPath" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to write pre-commit hook: $_"
    }
}

function Register-DailyTask {
    param([string]$root)
    if ($env:OS -notlike "*Windows*") { Write-Warning "Scheduled task setup only automated for Windows in this script."; return }
    $taskName = "ProjectAssistantDaily_$(Split-Path -Leaf $root)"
    $action = New-ScheduledTaskAction -Execute "pwsh" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$root\project-assistant.ps1`" -AutoRun -Fix"
    $trigger = New-ScheduledTaskTrigger -Daily -At 3am
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
    try {
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force
        Write-Host "Registered scheduled task: $taskName (runs daily at 3:00 AM for current user)" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to register scheduled task: $_"
    }
}

# MAIN ------------------------------------------------------------------

$repoRoot = Get-GitRoot
Set-Location $repoRoot
Write-Host "Repository root: $repoRoot" -ForegroundColor DarkCyan

# Determine files to scan (common text/code files)
$scanGlobs = @("*.ps1","*.py","*.md","*.txt","*.json","*.yaml","*.yml","*.js","*.ts")
$files = Find-Files -globs $scanGlobs

Write-Title "Overview"
Show-GitStatus

if ($files.Count -eq 0) {
    Write-Host "No files matched common code/text globs. You can adjust \$scanGlobs in the script." -ForegroundColor Yellow
}

# Detect issues
$encReport = Detect-EncodingIssues -files $files
$wsReport = Detect-WhitespaceIssues -files $files

# If invoked only as a check (pre-commit hook) support -CheckOnly param
if ($PSBoundParameters.ContainsKey('CheckOnly')) {
    # Return nonzero exit code if severe issues (non-UTF8 decode) exist
    if ($encReport.nonUtf8.Count -gt 0) { exit 2 }
    exit 0
}

# Show suggestions
Suggest-Actions -encodingReport $encReport -wsReport $wsReport -files $files

# Check for missing helper scripts
$missing = Ensure-ScriptsExist -root $repoRoot
if ($missing.Count -gt 0) {
    Write-Warning "Missing helper scripts required for automated fixes:"
    $missing | ForEach-Object { Write-Host "  $_" }
    Write-Host "You can re-run write-scripts.ps1 to recreate them, or create them manually."
}

# Handle install hook request
if ($InstallHook) {
    if ($AutoRun -or (Read-Host "Install pre-commit hook to run quick checks before commit? (y/N)") -in @('y','Y','yes','Yes')) {
        Install-PreCommitHook -root $repoRoot
    } else {
        Write-Host "Skipping hook installation."
    }
}

# Handle schedule request
if ($ScheduleDaily) {
    if ($AutoRun -or (Read-Host "Register a daily scheduled task to auto-run assistant? (requires Windows) (y/N)") -in @('y','Y','yes','Yes')) {
        Register-DailyTask -root $repoRoot
    } else {
        Write-Host "Skipping scheduled task registration."
    }
}

# If AutoRun and Fix requested, run fixes automatically
if ($AutoRun -and $Fix) {
    if ($missing.Count -gt 0) {
        Write-Warning "Cannot auto-fix: missing helper scripts. Create them first."
    } else {
        # Run sanitize on all matched files
        Run-Sanitize -files $files -fix -tabsToSpaces 4 -force
        if ($PerformConvert) {
            Run-Convert -files $files -performCommit
        }
    }
    exit 0
}

# Interactive menu loop (only when not AutoRun)
if (-not $AutoRun) {
    while ($true) {
        Write-Title "Actions (choose a number, or q to quit)"
        Write-Host "1) Dry-run sanitize (show what sanitize-ps1 would do)"
        Write-Host "2) Run sanitize now (interactive prompts per file)"
        Write-Host "3) Run sanitize now for all (no prompts, convert tabs->4 spaces)"
        Write-Host "4) Dry-run convert encodings (WhatIf)"
        Write-Host "5) Run convert-and-commit (create backups; won't commit unless asked)"
        Write-Host "6) Run convert-and-commit and commit changes (PerformCommit)"
        Write-Host "7) Install pre-commit hook"
        Write-Host "8) Register daily scheduled task (Windows)"
        Write-Host "9) Show git status again"
        Write-Host "q) Quit"
        $choice = Read-Host "Choice"
        switch ($choice) {
            '1' {
                if ((Get-Item (Join-Path $repoRoot "sanitize-ps1.ps1") -ErrorAction SilentlyContinue)) {
                    Run-Sanitize -files $files
                } else { Write-Warning "sanitize-ps1.ps1 not found." }
            }
            '2' {
                if ((Get-Item (Join-Path $repoRoot "sanitize-ps1.ps1") -ErrorAction SilentlyContinue)) {
                    Run-Sanitize -files $files -fix
                } else { Write-Warning "sanitize-ps1.ps1 not found." }
            }
            '3' {
                if ((Get-Item (Join-Path $repoRoot "sanitize-ps1.ps1") -ErrorAction SilentlyContinue)) {
                    Run-Sanitize -files $files -fix -tabsToSpaces 4 -force
                } else { Write-Warning "sanitize-ps1.ps1 not found." }
            }
            '4' {
                if ((Get-Item (Join-Path $repoRoot "convert-and-commit.ps1") -ErrorAction SilentlyContinue)) {
                    & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "convert-and-commit.ps1") -Paths $files -WhatIf
                } else { Write-Warning "convert-and-commit.ps1 not found." }
            }
            '5' {
                if ((Get-Item (Join-Path $repoRoot "convert-and-commit.ps1") -ErrorAction SilentlyContinue)) {
                    Run-Convert -files $files
                } else { Write-Warning "convert-and-commit.ps1 not found." }
            }
            '6' {
                if ((Get-Item (Join-Path $repoRoot "convert-and-commit.ps1") -ErrorAction SilentlyContinue)) {
                    Run-Convert -files $files -performCommit
                } else { Write-Warning "convert-and-commit.ps1 not found." }
            }
            '7' {
                Install-PreCommitHook -root $repoRoot
            }
            '8' {
                Register-DailyTask -root $repoRoot
            }
            '9' {
                Show-GitStatus
            }
            'q' {
                break
            }
            default { Write-Host "Unknown option: $choice" }
        }
    }
}

Write-Host "Done." -ForegroundColor Green
<#
recover-untracked.ps1

I am GPT-5.2 Pro.

Purpose:
- For each filename supplied (or the built-in list), check whether it exists in the working tree.
- If missing, search Git history and offer to restore the latest commit that contained the file.
- Optionally check the Windows Recycle Bin and offer to restore items.
- Produce missing_files.txt listing files not found in Git history or Recycle Bin.

Notes:
- This script uses only ASCII characters to avoid PowerShell parse issues.
- Save as UTF-8 and run from the repository root.
#>

param(
    [string[]]$Files = @(
        "apply-recommendations.ps1",
        "convert-and-commit.ps1",
        "create-pyproject-and-install.ps1",
        "find-and-insert-debug.ps1",
        "fix-and-run-sanitize.ps1",
        "fix-imports-and-test.ps1",
        "fix-pyproject-and-install.ps1",
        "fix-sanitize-line.ps1",
        "fix-sanitize-values.ps1",
        "fix-tests.ps1",
        "fix-unbalanced-braces.ps1",
        "insert-sanitize-debug.ps1",
        "patch-sanitize-file-fixed.ps1",
        "patch-sanitize-file.ps1",
        "patch-start-end-guard-fixed.ps1",
        "reencode-fix.ps1",
        "remove-bom-and-install-fixed.ps1",
        "run-tests-with-shim.ps1",
        "sanitize-ps1.ps1",
        "show-parser-diagnostics.ps1",
        "test-sanitize.ps1",
        "tests\__init__.py"
    ),
    [switch]$AutoRestoreFromGit = $false,
    [switch]$CheckRecycleBin = $true,
    [string]$MissingListPath = ".\missing_files.txt"
)

function Assert-InGitRepo {
    $inside = & git rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -ne 0 -or $inside -ne "true") {
        Write-Error "This script must be run from inside a Git working tree. cd to repo root and try again."
        exit 1
    }
}

function Get-LatestCommitContainingFile {
    param([string]$FilePath)
    $hash = & git log --all --pretty=format:%H -- "$FilePath" 2>$null | Select-Object -First 1
    if ($LASTEXITCODE -ne 0) { return "" }
    return $hash
}

function Restore-FromGit {
    param([string]$FilePath, [string]$CommitHash)
    if (-not $CommitHash) { return $false }
    if (Test-Path -LiteralPath $FilePath) {
        $overwrite = Read-Host "File '$FilePath' already exists. Overwrite from commit $CommitHash? (y/N)"
        if ($overwrite -notin @('y','Y','yes','Yes')) { Write-Output "Skipping $FilePath"; return $false }
    }
    Write-Output "Restoring '$FilePath' from commit $CommitHash ..."
    & git checkout $CommitHash -- "$FilePath"
    if ($LASTEXITCODE -eq 0) {
        Write-Output "Restored: $FilePath"
        return $true
    } else {
        Write-Warning "git checkout failed for $FilePath"
        return $false
    }
}

function Find-InRecycleBin {
    param([string]$Name)
    try {
        $shell = New-Object -ComObject Shell.Application
        $recycle = $shell.Namespace(0xA)
        $found = @()
        for ($i = 0; $i -lt $recycle.Items().Count; $i++) {
            $item = $recycle.Items().Item($i)
            if ($null -eq $item) { continue }
            $itemName = $item.Name
            $origPath = $recycle.GetDetailsOf($item,1)
            if ($itemName -ieq (Split-Path $Name -Leaf) -or ($origPath -and $origPath -like "*$Name")) {
                $obj = [PSCustomObject]@{
                    Item = $item
                    Name = $itemName
                    OriginalPath = $origPath
                }
                $found += $obj
            }
        }
        return ,$found
    } catch {
        Write-Warning "Unable to access Recycle Bin via Shell COM: $_"
        return @()
    }
}

function Restore-RecycleItem {
    param($ItemObj)
    try {
        $item = $ItemObj.Item
        # Try to invoke a Restore verb if available
        $verbs = @()
        for ($v = 0; $v -lt $item.Verbs().Count; $v++) { $verbs += $item.Verbs().Item($v).Name }
        $verbObj = $item.Verbs() | Where-Object { $_.Name -match "Restore" -or $_.Name -match "restore" } | Select-Object -First 1
        if ($verbObj) {
            $verbObj.DoIt()
            return $true
        } else {
            # fallback attempt
            try {
                $item.InvokeVerb("Restore")
                return $true
            } catch {
                Write-Warning "Could not invoke restore verb for $($item.Name)."
                return $false
            }
        }
    } catch {
        Write-Warning "Exception while restoring recycle item: $_"
        return $false
    }
}

# Start
Write-Output "recover-untracked.ps1 - Git-history and Recycle-Bin helper"
Assert-InGitRepo

$notFound = @()
$restoredCount = 0

foreach ($f in $Files) {
    $filePath = $f
    $filePathForGit = $filePath -replace '\\','/'

    if (Test-Path -LiteralPath $filePath) {
        Write-Output "Exists: $filePath - skipping."
        continue
    }

    Write-Output "Checking Git history for: $filePath ..."
    $hash = Get-LatestCommitContainingFile -FilePath $filePathForGit
    if ($hash) {
        Write-Output "Found in Git history: $hash"
        if ($AutoRestoreFromGit) {
            $ok = Restore-FromGit -FilePath $filePath -CommitHash $hash
            if ($ok) { $restoredCount++ } else { $notFound += $filePath }
        } else {
            $resp = Read-Host "Restore '$filePath' from commit $hash? (y/N)"
            if ($resp -in @('y','Y','yes','Yes')) {
                $ok = Restore-FromGit -FilePath $filePath -CommitHash $hash
                if ($ok) { $restoredCount++ } else { $notFound += $filePath }
            } else {
                Write-Output "Skipped restore from Git for $filePath"
                $notFound += $filePath
            }
        }
        continue
    }

    Write-Output "Not found in Git history: $filePath"

    if ($CheckRecycleBin) {
        Write-Output "Searching Recycle Bin for '$filePath' ..."
        $items = Find-InRecycleBin -Name $filePath
        if ($items.Count -gt 0) {
            Write-Output "Found $($items.Count) Recycle Bin item(s) matching '$filePath'."
            $idx = 0
            foreach ($it in $items) {
                $idx++
                Write-Output "[$idx] Name: $($it.Name)  OriginalPath: $($it.OriginalPath)"
            }
            $choose = Read-Host "Restore which item? Enter index (1..$($items.Count)) or 'n' to skip"
            if ($choose -match '^\d+$' -and [int]$choose -ge 1 -and [int]$choose -le $items.Count) {
                $sel = $items[[int]$choose - 1]
                $ok = Restore-RecycleItem -ItemObj $sel
                if ($ok) {
                    Write-Output "Restored from Recycle Bin: $($sel.Name)"
                    $restoredCount++
                    continue
                } else {
                    Write-Warning "Failed to restore $filePath from Recycle Bin"
                }
            } else {
                Write-Output "Skipped Recycle Bin restore for $filePath"
            }
        } else {
            Write-Output "No Recycle Bin items matched '$filePath'."
        }
    }

    $notFound += $filePath
}

if ($notFound.Count -gt 0) {
    Write-Output ""
    Write-Output "Files not found in Git history or Recycle Bin (written to $MissingListPath):"
    $notFound | Tee-Object -FilePath $MissingListPath
    Write-Output "You can use this list with recovery tools (Recuva/PhotoRec) to search for these filenames."
} else {
    Write-Output ""
    Write-Output "All files were found or restored."
}

Write-Output ""
Write-Output "Summary: Restored $restoredCount file(s). Missing/Not restored: $($notFound.Count)."
Write-Output "If important files remain missing, stop writing to the disk and run a recovery tool (Recuva or PhotoRec) from another drive."
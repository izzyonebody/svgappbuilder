param(
    [switch] $Verbose
)
if ($Verbose) { $VerbosePreference = "Continue" }

try {
    Import-Module Pester -ErrorAction Stop
} catch {
    Write-Host "Pester not installed. Installing..."
    Install-Module -Name Pester -Force -Scope CurrentUser -SkipPublisherCheck
    Import-Module Pester
}

Invoke-Pester -Script (Join-Path $PSScriptRoot ''tests'') -Output Detailed
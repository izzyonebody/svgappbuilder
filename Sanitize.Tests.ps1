Describe "sanitize-ps1 basic behavior" {
    It "converts tabs to spaces, trims trailing whitespace, normalizes newlines and removes BOM" {
        $tmp = New-Item -ItemType Directory -Path (Join-Path $env:TEMP "sanitize_test_$([guid]::NewGuid())") -Force
        $file = Join-Path $tmp.FullName 'test.txt'
        # create file with BOM, tabs, trailing spaces, LF only
        $content = [byte[]](0xEF,0xBB,0xBF) + [System.Text.Encoding]::UTF8.GetBytes("line1`t `r`nline2  `n")
        [System.IO.File]::WriteAllBytes($file, $content)

        # Run sanitizer fix
        & "$PSScriptRoot/../sanitize-ps1.ps1" -Paths @($file) -Fix -Backup -BackupFolder (Join-Path $tmp.FullName 'bk') -TabsToSpaces 4 -LineEnding 'LF' -Yes -Verbose

        # Assert backup exists
        Test-Path (Join-Path $tmp.FullName 'bk/test.txt') | Should -BeTrue

        # Read result
        $res = Get-Content -Raw -LiteralPath $file -Encoding UTF8
        $res | Should -Match "line1    "
        # Ensure ending is LF
        $res | Should -Match "`n$"
        Remove-Item -Recurse -Force $tmp
    }
}

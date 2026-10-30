# Parse only. Never dot-source or invoke inspected project scripts.
param([string]$Root = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
$count = 0; $failed = 0
Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.ps1' | ForEach-Object {
    $tokens = $null; $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
    $count++
    foreach ($err in $errors) {
        # Do not print parser messages or source extents: they can contain secrets.
        Write-Host ($_.FullName.Substring($Root.Length).TrimStart('\') + ':' + $err.Extent.StartLineNumber + ' | syntax | ' + $err.ErrorId)
        $failed++
    }
}
Write-Host ('PowerShell parse-only: ' + $count + ' files, ' + $failed + ' errors')
if ($failed) { exit 1 }

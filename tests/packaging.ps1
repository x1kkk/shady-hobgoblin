# Synthetic offline packaging tests: executes only the NEW candidate builder and policy.
# Never executes repair, AI, archive, original source, or external service commands.
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$work = Join-Path $Root ('dist\packaging-' + [guid]::NewGuid().ToString('N'))
$count = 0
function Assert([bool]$ok, [string]$kind) { if (-not $ok) { throw ('Test failed: ' + $kind) }; $script:count++ }
function Expect-Reject([scriptblock]$action, [string]$kind) {
    $rejected = $false
    try { & $action | Out-Null } catch { $rejected = $true }
    Assert $rejected $kind
}
try {
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $source = Join-Path $work 'synthetic-source'
    & (Join-Path $Root 'make_usb.ps1') -Target $source -SkipRuntime -Quiet | Out-Null
    $marker = 'FICTIONAL_ONLY_CREDENTIAL_1234567890'
    Set-Content -LiteralPath (Join-Path $source 'config.ini') -Value ('[deepseek]' + "`napi_key=" + $marker) -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $source 'pi-home\agent\auth.json') -Value ('{"fictional":{"type":"api_key","key":"' + $marker + '"}}') -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $source 'pi-home\agent\settings.json') -Value ('{"httpProxy":"' + $marker + '"}') -Encoding UTF8
    foreach ($dir in @('pi-home\agent\sessions','logs\sync-backup\pi-home\agent','tools\nested-history','reports\fictional-machine','backups')) {
        New-Item -ItemType Directory -Force -Path (Join-Path $source $dir) | Out-Null
        Set-Content -LiteralPath (Join-Path $source ($dir + '\innocent-name.txt')) -Value $marker -Encoding UTF8
    }
    $public = Join-Path $work 'public'
    & (Join-Path $source 'make_usb.ps1') -Target $public -SkipRuntime -NoKey -Quiet | Out-Null
    Assert ((Get-Content -LiteralPath (Join-Path $public 'pi-home\agent\auth.json') -Raw).Trim() -eq '{}') 'public-empty-auth'
    $foundMarker = $false
    foreach ($f in (Get-ChildItem -LiteralPath $public -Recurse -File)) {
        # Tests contain marker definition; exclude the test source itself from fixture value matching.
        if ($f.FullName -eq (Join-Path $public 'tests\packaging.ps1')) { continue }
        if ([IO.File]::ReadAllText($f.FullName).Contains($marker)) { $foundMarker = $true }
    }
    Assert (-not $foundMarker) 'public-canary-isolation'
    Assert (-not (Test-Path -LiteralPath (Join-Path $public 'tools\nested-history'))) 'nested-history-excluded'
    Assert ((Get-ChildItem -LiteralPath (Join-Path $public 'reports') -File -Recurse).Count -eq 0) 'empty-runtime-directories'
    $plainPublic = Join-Path $work 'default-public'
    & (Join-Path $source 'make_usb.ps1') -Target $plainPublic -SkipRuntime -Quiet | Out-Null
    Assert ((Get-Content -LiteralPath (Join-Path $plainPublic 'pi-home\agent\auth.json') -Raw).Trim() -eq '{}') 'public-default-no-credentials'
    $privateNoKey = Join-Path $work 'private-nokey'
    & (Join-Path $source 'make_usb.ps1') -Target $privateNoKey -Mode Private -NoKey -SkipRuntime -Quiet | Out-Null
    Assert ((Get-Content -LiteralPath (Join-Path $privateNoKey 'pi-home\agent\auth.json') -Raw).Trim() -eq '{}') 'private-nokey-empty'
    Expect-Reject { & (Join-Path $source 'make_usb.ps1') -Target $public -SkipRuntime -Quiet } 'reject-existing-output'
    Expect-Reject { & (Join-Path $source 'make_usb.ps1') -Target (Join-Path $work 'bad') -IncludeCredentials -SkipRuntime -Quiet } 'reject-public-credential-optin'
    Expect-Reject { & (Join-Path $source 'make_usb.ps1') -Target (Join-Path $work 'bad') -Mode Private -NoKey -IncludeCredentials -CredentialRoot $source -SkipRuntime -Quiet } 'reject-contradictory-nokey'
    Expect-Reject { & (Join-Path $source 'make_usb.ps1') -Target (Join-Path $work 'bad') -Quiet } 'require-explicit-runtime-input'
    # Real private-deployment path, using synthetic data and a deterministic consent mock.
    function Read-Host { return 'PRIVATE' }
    $private = Join-Path $work 'private'
    & (Join-Path $source 'make_usb.ps1') -Target $private -Mode Private -IncludeCredentials -CredentialRoot $source -SkipRuntime -Quiet -WarningAction SilentlyContinue | Out-Null
    Assert (Test-Path -LiteralPath (Join-Path $private 'PRIVATE-DO-NOT-PUBLISH.txt')) 'private-output-marked'
    Assert ((Get-Content -LiteralPath (Join-Path $private 'pi-home\agent\auth.json') -Raw).Contains($marker)) 'explicit-private-credentials-preserved'
    Remove-Item Function:\Read-Host
    # A Git source checkout omits all ignored live config. Build must use only defaults.
    foreach ($rel in @('config.ini','pi-home\agent\auth.json','pi-home\agent\settings.json')) { Remove-Item -LiteralPath (Join-Path $source $rel) }
    $checkoutBuild = Join-Path $work 'checkout-build'
    & (Join-Path $source 'make_usb.ps1') -Target $checkoutBuild -SkipRuntime -Quiet | Out-Null
    Assert (Test-Path -LiteralPath (Join-Path $checkoutBuild 'config.ini')) 'checkout-without-local-config-builds'
    # Inert synthetic runtime files validate copy boundaries without executing any dependency.
    $depRoot = Join-Path $work 'fictional-dependencies'
    New-Item -ItemType Directory -Path $depRoot | Out-Null
    $entries = @()
    foreach ($rel in @('runtime/pi/node.exe','runtime/pi/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js','pi-home/agent/bin/rg.exe','pi-home/agent/bin/fd.exe','third-party/runtime-notices/FICTIONAL-LICENSE.txt')) {
        $file = Join-Path $depRoot $rel
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $file) | Out-Null
        Set-Content -LiteralPath $file -Value 'INERT SYNTHETIC FIXTURE; NEVER EXECUTE' -Encoding ASCII
        $entries += @{source=$rel;destination=$rel;sha256=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash}
    }
    $depManifest = Join-Path $depRoot 'runtime-manifest.json'
    @{reviewed=$true;noticesReviewed=$true;files=$entries} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $depManifest -Encoding UTF8
    $assembled = Join-Path $work 'fictional-assembled'
    & (Join-Path $source 'make_usb.ps1') -Target $assembled -RuntimeManifest $depManifest -Quiet | Out-Null
    Assert (Test-Path -LiteralPath (Join-Path $assembled 'pi-home\agent\bin\fd.exe')) 'explicit-runtime-manifest-copied'
    Add-Content -LiteralPath (Join-Path $depRoot 'runtime\pi\node.exe') -Value 'tamper'
    Expect-Reject { & (Join-Path $source 'make_usb.ps1') -Target (Join-Path $work 'bad-runtime') -RuntimeManifest $depManifest -Quiet } 'reject-runtime-hash-mismatch'
    # Tampering or copy failure must not be hidden by any old destination file.
    Add-Content -LiteralPath (Join-Path $source 'core\ps\collect.ps1') -Value '# synthetic tamper'
    $bad = Join-Path $work 'tampered'
    Expect-Reject { & (Join-Path $source 'make_usb.ps1') -Target $bad -SkipRuntime -Quiet } 'reject-source-hash-mismatch'
    Assert (-not (Test-Path -LiteralPath $bad)) 'failed-build-no-output'
    Remove-Item -LiteralPath (Join-Path $source 'core\ps\collect.ps1')
    Expect-Reject { & (Join-Path $source 'make_usb.ps1') -Target $bad -SkipRuntime -Quiet } 'reject-missing-source'
    . (Join-Path $Root 'release\policy.ps1')
    Expect-Reject { Assert-ReleasePath '../outside.txt' } 'reject-traversal'
    Expect-Reject { Assert-ReleasePath 'logs/history.txt' } 'reject-data-manifest-path'
    Expect-Reject { Assert-ReleasePath 'pi-home/agent/auth.json' -Dependency } 'reject-dependency-config'
    # DryRun of the revised synchronizer must not write or create anything.
    $before = @(Get-ChildItem -LiteralPath $public -Recurse -Force | ForEach-Object { $_.FullName + '|' + $_.LastWriteTimeUtc.Ticks })
    & (Join-Path $Root 'tools\sync_from_usb.ps1') -UsbRoot $plainPublic -ProjectRoot $public -DryRun | Out-Null
    $after = @(Get-ChildItem -LiteralPath $public -Recurse -Force | ForEach-Object { $_.FullName + '|' + $_.LastWriteTimeUtc.Ticks })
    Assert (($before -join "`n") -eq ($after -join "`n")) 'sync-dryrun-no-write'
    Write-Host ('Offline packaging checks passed: ' + $count)
} finally {
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
    $dist = Join-Path $Root 'dist'
    if ((Test-Path -LiteralPath $dist) -and @(Get-ChildItem -LiteralPath $dist -Force).Count -eq 0) { Remove-Item -LiteralPath $dist }
}

# Synchronize reviewed source files only, using the same release manifest as the builder.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$UsbRoot,
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$DryRun,
    [ValidateSet('Public','Private')][string]$Mode = 'Public',
    [switch]$NoKey,
    [switch]$IncludeCredentials
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\release\policy.ps1')
if ($IncludeCredentials -and ($Mode -ne 'Private' -or $NoKey)) { throw 'Credentials require Private mode and cannot be combined with NoKey.' }
if (-not (Test-Path -LiteralPath $UsbRoot -PathType Container) -or -not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) { throw 'Both roots must exist.' }
if ([IO.Path]::GetFullPath($UsbRoot).TrimEnd('\') -eq [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')) { throw 'Roots must differ.' }
$plans = @()
# Both sides need independently reviewed manifests. New/unreviewed code cannot enter a release through sync.
$pm = Get-Content -LiteralPath (Join-Path $ProjectRoot 'release\files.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$um = Get-Content -LiteralPath (Join-Path $UsbRoot 'release\files.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($e in $pm.files) {
    $rel = [string]$e.source
    Assert-ReleasePath $rel
    if ($rel -match '^(?i:release[\\/]|third-party[\\/])' -or $rel -match '(?i)(auth|settings|models|config)(\.example)?\.(json|ini)$') { continue }
    $p = Join-Path $ProjectRoot $rel; $u = Join-Path $UsbRoot $rel
    $peer = @($um.files | Where-Object { $_.source -eq $rel })
    if ($peer.Count -ne 1) { throw ('Peer review entry missing: ' + $rel) }
    foreach ($pair in @(@($p,$e.sha256),@($u,$peer[0].sha256))) {
        Assert-NoReparse $pair[0]
        if ((Get-FileHash -LiteralPath $pair[0] -Algorithm SHA256).Hash -ne $pair[1]) { throw ('Unreviewed change: ' + $rel) }
    }
    if ($e.sha256 -eq $peer[0].sha256) { continue }
    if ((Get-Item -LiteralPath $u).LastWriteTimeUtc -gt (Get-Item -LiteralPath $p).LastWriteTimeUtc) {
        $plans += @{From=$u;To=$p;Hash=$peer[0].sha256;Path=$rel}
    } else { $plans += @{From=$p;To=$u;Hash=$e.sha256;Path=$rel} }
}
if ($IncludeCredentials) {
    if (-not $DryRun -and (Read-Host 'Private credential synchronization. Type PRIVATE') -cne 'PRIVATE') { throw 'Cancelled.' }
    foreach ($rel in @('config.ini','pi-home\agent\auth.json')) {
        $p = Join-Path $ProjectRoot $rel; $u = Join-Path $UsbRoot $rel
        $from = $p; $to = $u
        if ((Test-Path -LiteralPath $u) -and ((-not (Test-Path -LiteralPath $p)) -or (Get-Item -LiteralPath $u).LastWriteTimeUtc -gt (Get-Item -LiteralPath $p).LastWriteTimeUtc)) { $from=$u; $to=$p }
        Assert-NoReparse $from
        $plans += @{From=$from;To=$to;Hash=(Get-FileHash -LiteralPath $from -Algorithm SHA256).Hash;Path=$rel}
    }
}
foreach ($plan in $plans) {
    Write-Host ($(if ($DryRun) { '[preview] ' } else { '[copy] ' }) + $plan.Path)
    if (-not $DryRun) { Copy-Verified $plan.From $plan.To $plan.Hash }
}
Write-Host 'Sync complete. Any changed source invalidates the destination manifest: review and regenerate it before a build. No histories or runtime data were synchronized.'

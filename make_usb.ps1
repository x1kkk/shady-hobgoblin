# Open-source candidate builder: offline, explicit manifest, fresh destination only.
[CmdletBinding()]
param(
    [string]$Target = '',
    [ValidateSet('Public','Private')][string]$Mode = 'Public',
    [switch]$NoKey,
    [switch]$IncludeCredentials,
    [string]$CredentialRoot = '',
    [string]$RuntimeManifest = '',
    [switch]$SkipRuntime,
    [switch]$FullRuntime,
    [switch]$NoSelfTest,
    [switch]$Quiet
)
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
. (Join-Path $Root 'release\policy.ps1')
if ($FullRuntime) { throw 'Use an audited -RuntimeManifest; implicit installed runtime copying is not supported.' }
if ($Mode -eq 'Public' -and $IncludeCredentials) { throw 'Public builds cannot include credentials.' }
if ($NoKey -and $IncludeCredentials) { throw '-NoKey conflicts with -IncludeCredentials.' }
if ($IncludeCredentials -and (-not $CredentialRoot -or $Mode -ne 'Private')) { throw 'Private credentials require an explicit -CredentialRoot.' }
if (-not $Target) { $Target = Read-Host 'New output directory (not an existing USB root)' }
if (-not $Target) { throw 'No destination provided.' }
$dst = [IO.Path]::GetFullPath($Target)
$src = [IO.Path]::GetFullPath($Root).TrimEnd('\')
if (Test-Path -LiteralPath $dst) { throw 'Destination exists. Refusing overlay; use a NEW directory.' }
if ($dst.TrimEnd('\') -eq $src -or $src.StartsWith($dst.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe destination.' }
if (-not $SkipRuntime -and -not $RuntimeManifest) { throw 'Provide -RuntimeManifest from reviewed offline dependencies, or explicitly use -SkipRuntime for source-only output.' }
$manifest = Get-Content -LiteralPath (Join-Path $Root 'release\files.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$stage = $dst + '.staging-' + [guid]::NewGuid().ToString('N')
try {
    New-Item -ItemType Directory -Path $stage | Out-Null
    foreach ($entry in $manifest.files) {
        Assert-ReleasePath $entry.source
        Assert-ReleasePath $entry.destination
        $from = Join-Path $Root $entry.source
        $to = Join-Path $stage $entry.destination
        Copy-Verified $from $to $entry.sha256
    }
    # Manifest cannot contain its own hash; preserve the reviewed input manifest separately.
    $manifestPath = Join-Path $Root 'release\files.json'
    Copy-Verified $manifestPath (Join-Path $stage 'release\files.json') (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
    # Dependency input is supplied separately: never search PATH, profile, TEMP or an installed pi.
    if (-not $SkipRuntime) {
        $rp = (Resolve-Path -LiteralPath $RuntimeManifest).Path
        $deps = Get-Content -LiteralPath $rp -Raw -Encoding UTF8 | ConvertFrom-Json
        $depRoot = Split-Path -Parent $rp
        if ($deps.reviewed -ne $true -or -not $deps.files -or -not $deps.noticesReviewed) { throw 'Dependency manifest must explicitly attest review and license completeness.' }
        foreach ($entry in $deps.files) {
            Assert-ReleasePath $entry.source
            Assert-ReleasePath $entry.destination -Dependency
            $from = Join-Path $depRoot $entry.source
            $to = Join-Path $stage $entry.destination
            if (Test-Path -LiteralPath $to) { throw 'Duplicate dependency destination.' }
            Copy-Verified $from $to $entry.sha256
        }
        foreach ($required in @('runtime\pi\node.exe','runtime\pi\pi.cmd','runtime\pi\node_modules\@earendil-works\pi-coding-agent\dist\bundle\cli.js','pi-home\agent\bin\rg.exe','pi-home\agent\bin\fd.exe')) {
            if (-not (Test-Path -LiteralPath (Join-Path $stage $required) -PathType Leaf)) { throw ('Missing dependency: ' + $required) }
        }
    }
    # Always publish reviewed defaults, never live config.ini / auth / settings / models caches.
    if ($IncludeCredentials) {
        Write-Warning 'PRIVATE DEPLOYMENT: credentials will be stored in plaintext. Do not publish this output.'
        if ((Read-Host 'Type PRIVATE to authorize credential copying') -cne 'PRIVATE') { throw 'Credential copy cancelled.' }
        foreach ($rel in @('config.ini','pi-home\agent\auth.json')) {
            $from = Join-Path $CredentialRoot $rel
            if (-not (Test-Path -LiteralPath $from -PathType Leaf)) { throw ('Missing explicit private input: ' + $rel) }
            if ($rel -like '*.json') { $null = Get-Content -LiteralPath $from -Raw | ConvertFrom-Json }
            $hash = (Get-FileHash -LiteralPath $from -Algorithm SHA256).Hash
            Copy-Verified $from (Join-Path $stage $rel) $hash
        }
        Set-Content -LiteralPath (Join-Path $stage 'PRIVATE-DO-NOT-PUBLISH.txt') -Value 'Contains private credentials. Never distribute publicly.' -Encoding UTF8
    }
    foreach ($dir in @('reports','logs','backups','downloads','pi-home\agent\sessions')) {
        New-Item -ItemType Directory -Force -Path (Join-Path $stage $dir) | Out-Null
    }
    # Portable cmd/vbs entry points use their own location. Do not distribute machine-bound .lnk files.
    Move-Item -LiteralPath $stage -Destination $dst -ErrorAction Stop
    Write-Host ('Build completed: ' + $Mode + $(if ($SkipRuntime) { ' (SOURCE ONLY; AI runtime not assembled)' } else { ' (runtime copied, NOT executed)' }))
    Write-Host 'No self-test, repair, network request, ACL modification or elevation was performed by this builder.'
} catch {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
    throw 'Build failed. No completed output produced; review input paths, manifests and hashes. No secret values are displayed.'
}

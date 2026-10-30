# USB refresh is a clean build into a NEW directory, never an overlay over old private data.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$UsbRoot,
    [string]$Source = (Split-Path -Parent $PSScriptRoot),
    [string]$RuntimeManifest = '',
    [switch]$SkipRuntime,
    [ValidateSet('Public','Private')][string]$Mode = 'Public',
    [switch]$NoKey,
    [switch]$IncludeCredentials,
    [string]$CredentialRoot = '',
    [switch]$RepairPermissions,
    [switch]$Quiet
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath (Join-Path $Source 'make_usb.ps1') -PathType Leaf)) { throw 'Source builder is missing.' }
if ($RepairPermissions) {
    # Retained optional permission repair. Never automatically request elevation.
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Permission repair requires a separately opened administrator terminal.' }
    if ((Read-Host 'ACL repair affects the specified existing USB directory. Type ACL to confirm') -cne 'ACL') { throw 'Cancelled.' }
    if (-not (Test-Path -LiteralPath $UsbRoot -PathType Container)) { throw 'USB directory missing.' }
    & icacls $UsbRoot /grant '*S-1-5-32-545:(OI)(CI)M' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'ACL repair failed.' }
}
# Caller chooses a new child directory on the USB. Existing data is never deleted or reused.
$output = Join-Path $UsbRoot ('PiAgent-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,6))
& (Join-Path $Source 'make_usb.ps1') -Target $output -Mode $Mode -NoKey:$NoKey -IncludeCredentials:$IncludeCredentials -CredentialRoot $CredentialRoot -RuntimeManifest $RuntimeManifest -SkipRuntime:$SkipRuntime -Quiet:$Quiet
Write-Host 'Refresh built a new installation directory. Use its start.bat; old installations were not modified.'

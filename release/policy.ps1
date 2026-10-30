# Shared by build, refresh and synchronization. No network or host modification.
function Assert-ReleasePath([string]$Relative, [switch]$Dependency) {
    if ([string]::IsNullOrWhiteSpace($Relative) -or [IO.Path]::IsPathRooted($Relative) -or $Relative -match '[:\x00-\x1f]' -or ($Relative -split '[\\/]') -contains '..') { throw 'Unsafe manifest path.' }
    if ($Relative -match '(?i)(^|[\\/])(\.git|sessions|cache|logs|reports|backups|records|sync-backup[^\\/]*)([\\/]|$)' -or $Relative -match '(?i)\.(lnk|reg|jsonl|log|pfx|p12|pem|key)$' -or $Relative -match '(?i)(^|[\\/])(\.env|\.npmrc|models-store\.json|trust\.json)$') { throw 'Private data path prohibited.' }
    if ($Dependency -and $Relative -notmatch '^(runtime[\\/]pi[\\/]|pi-home[\\/]agent[\\/]bin[\\/](rg|fd)\.exe$|third-party[\\/])') { throw 'Dependency outside permitted destination roots.' }
    if ($Dependency -and $Relative -match '(?i)(^|[\\/])(auth\.json|settings\.json|config\.ini)$') { throw 'Dependency configuration prohibited.' }
}
function Assert-NoReparse([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    while ($null -ne $item) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Links and junctions are prohibited in release inputs.' }
        if ($item -is [IO.FileInfo]) { $item = $item.Directory } else { $item = $item.Parent }
        if (-not $item) { break }
    }
}
function Copy-Verified([string]$From, [string]$To, [string]$ExpectedHash) {
    Assert-NoReparse $From
    if (-not (Test-Path -LiteralPath $From -PathType Leaf) -or $ExpectedHash -notmatch '^[a-fA-F0-9]{64}$') { throw 'Missing source or invalid hash.' }
    $before = (Get-FileHash -LiteralPath $From -Algorithm SHA256).Hash
    if ($before -ne $ExpectedHash) { throw 'Source differs from reviewed manifest; stop for review.' }
    $parent = Split-Path -Parent $To
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Copy-Item -LiteralPath $From -Destination $To -Force -ErrorAction Stop
    if ((Get-FileHash -LiteralPath $To -Algorithm SHA256).Hash -ne $ExpectedHash) { throw 'Copy hash mismatch.' }
}

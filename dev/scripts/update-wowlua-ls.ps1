# update-wowlua-ls.ps1 - keep the standalone wowlua-ls checker current.
#
#   pwsh -NoProfile -File dev/scripts/update-wowlua-ls.ps1 [-ToolsDir <dir>] [-CheckOnly]
#
# Installs the Windows build of the latest TradeSkillMaster/wowlua-ls GitHub
# release as <ToolsDir>\wowlua_ls.exe (default KitnDev\tools\wowlua-ls), the
# path dev/scripts/wowlua-check.ps1 runs. The download is verified against
# the release's checksums.txt before it replaces anything; the replaced
# binary is kept as wowlua_ls.previous.exe for a manual rollback.
# api-drift-weekly.ps1 runs this every week.
#
# Prints one status line and exits:
#   0   already current
#   10  updated (or -CheckOnly: an update is available)
#   2   failed - the installed binary is untouched

param(
    [string]$ToolsDir = (Join-Path $env:USERPROFILE 'Documents\KitnDev\tools\wowlua-ls'),
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
$Asset = 'wowlua_ls-x86_64-pc-windows-msvc.exe'
$Exe = [IO.Path]::Combine($ToolsDir, 'wowlua_ls.exe')
$VersionFile = [IO.Path]::Combine($ToolsDir, 'version.txt')
# Keeps the .exe extension: Windows will not start a file named *.download.
$Download = [IO.Path]::Combine($ToolsDir, 'wowlua_ls.download.exe')
$Previous = [IO.Path]::Combine($ToolsDir, 'wowlua_ls.previous.exe')

function Fail($msg) {
    Remove-Item -LiteralPath $Download -Force -ErrorAction SilentlyContinue
    Write-Output "[wowlua-ls] FAILED: $msg"
    exit 2
}

try {
    $release = Invoke-RestMethod -Headers @{ 'User-Agent' = 'KitnEssentials-wowlua-update' } `
        -Uri 'https://api.github.com/repos/TradeSkillMaster/wowlua-ls/releases/latest'
} catch {
    Fail "release lookup failed: $($_.Exception.Message)"
}

$tag = [string]$release.tag_name
if (-not $tag) { Fail 'release lookup returned no tag' }

$installed = $null
if ((Test-Path -LiteralPath $Exe) -and (Test-Path -LiteralPath $VersionFile)) {
    $installed = (Get-Content -LiteralPath $VersionFile -TotalCount 1).Trim()
}
if ($installed -eq $tag) {
    Write-Output "[wowlua-ls] CURRENT $tag"
    exit 0
}
$from = $installed ?? 'none'
if ($CheckOnly) {
    Write-Output "[wowlua-ls] AVAILABLE $from -> $tag"
    exit 10
}

$exeAsset = $release.assets | Where-Object { $_.name -eq $Asset } | Select-Object -First 1
$sumAsset = $release.assets | Where-Object { $_.name -eq 'checksums.txt' } | Select-Object -First 1
if (-not $exeAsset -or -not $sumAsset) { Fail "$tag has no $Asset or checksums.txt asset" }

try {
    New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
    $sums = [string](Invoke-RestMethod -Uri $sumAsset.browser_download_url)
    Invoke-WebRequest -Uri $exeAsset.browser_download_url -OutFile $Download
} catch {
    Fail "download failed: $($_.Exception.Message)"
}

$expected = $null
foreach ($line in ($sums -split "`n")) {
    $parts = $line.Trim() -split '\s+'
    if ($parts.Count -ge 2 -and $parts[1].TrimStart('*') -eq $Asset) { $expected = $parts[0].ToLower() }
}
$actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Download).Hash.ToLower()
if (-not $expected -or $actual -ne $expected) {
    Fail "checksum mismatch for $tag (expected $expected, got $actual)"
}

try {
    $help = & $Download --help 2>&1 | Out-String
    $started = ($LASTEXITCODE -eq 0) -and ($help -match '\bcheck\b')
} catch {
    $started = $false
}
if (-not $started) { Fail "$tag binary did not start" }

$movedAside = $false
try {
    if (Test-Path -LiteralPath $Exe) {
        Move-Item -LiteralPath $Exe -Destination $Previous -Force
        $movedAside = $true
    }
    Move-Item -LiteralPath $Download -Destination $Exe -Force
    Set-Content -LiteralPath $VersionFile -Value $tag
} catch {
    # Put the old binary back whatever step failed, so a failed run leaves
    # the install exactly as it was.
    if ($movedAside) {
        Move-Item -LiteralPath $Previous -Destination $Exe -Force -ErrorAction SilentlyContinue
    }
    Fail "install failed: $($_.Exception.Message)"
}

Write-Output "[wowlua-ls] UPDATED $from -> $tag"
exit 10

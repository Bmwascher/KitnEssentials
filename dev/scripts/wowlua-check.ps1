# wowlua-check.ps1 - headless wowlua-ls diagnostics gate for KitnEssentials.
#
#   pwsh dev/scripts/wowlua-check.ps1 [-Path <file-or-dir>] [-Severity warning|hint] [-Root <checkout>]
#
# Runs the wowlua-ls `check` over the whole checkout (the cross-file type
# context is what makes the secret-value diagnostics accurate; a subdirectory
# run loses it) and prints the diagnostics, filtered to -Path when given.
# The exit code is the gate:
#   0  no warnings in the filtered set
#   1  warnings reported - fix them; the annotation and secret-value rules
#      are in .claude/rules/wowlua-annotations.md
#   3  cannot run (binary or .wowluarc.json missing) - callers treat this as
#      "skipped", the same way the pre-push hook treats a missing luacheck
#
# The binary ships inside the TradeSkillMaster VS Code extension; the newest
# installed version is used unless WOWLUA_LS names one explicitly.
# .wowluarc.json is local-only (gitignored): a worktree needs a copy from the
# primary checkout before this can run there.

[CmdletBinding()]
param(
    [string]$Path,
    [ValidateSet('warning', 'hint')]
    [string]$Severity = 'warning',
    [string]$Root
)

$ErrorActionPreference = 'Stop'

if (-not $Root) { $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }
$Root = $Root.TrimEnd('\', '/')

function Resolve-WowluaLs {
    if ($env:WOWLUA_LS -and (Test-Path -LiteralPath $env:WOWLUA_LS)) { return $env:WOWLUA_LS }
    $pattern = Join-Path $env:USERPROFILE '.vscode\extensions\tradeskillmaster.wowlua-ls-*\server\win32-x64\wowlua_ls.exe'
    $candidates = @(Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue)
    if ($candidates.Count -eq 0) { return $null }
    $sorted = $candidates | Sort-Object {
        $v = [regex]::Match($_.FullName, 'wowlua-ls-(\d+)\.(\d+)\.(\d+)').Groups
        [version]::new([int]$v[1].Value, [int]$v[2].Value, [int]$v[3].Value)
    }
    return ($sorted | Select-Object -Last 1).FullName
}

$exe = Resolve-WowluaLs
if (-not $exe) {
    [Console]::Error.WriteLine('[wowlua-check] skipped: wowlua_ls.exe not found (install the TradeSkillMaster wowlua-ls VS Code extension or set WOWLUA_LS).')
    exit 3
}
if (-not (Test-Path -LiteralPath (Join-Path $Root '.wowluarc.json'))) {
    [Console]::Error.WriteLine("[wowlua-check] skipped: no .wowluarc.json in $Root (local-only; copy it from the primary checkout).")
    exit 3
}

# Filter prefix, repo-relative with backslashes to match the tool's output.
$prefix = $null
if ($Path) {
    $full = [System.IO.Path]::GetFullPath(($Path -replace '/', '\'), $Root)
    if ($full.StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase)) {
        $prefix = $full.Substring($Root.Length).TrimStart('\')
    } else {
        $prefix = $Path -replace '/', '\'
    }
}

Push-Location -LiteralPath $Root
try {
    $raw = & $exe check --severity $Severity . 2>&1 | ForEach-Object { "$_" }
} finally {
    Pop-Location
}

$diag = @($raw | Where-Object { $_ -match '^[^:\s][^:]*\.lua:\d+:\d+: ' })
if ($prefix) {
    $diag = @($diag | Where-Object { $_.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) })
}
$summary = @($raw | Where-Object { $_ -match '^\s*Checked \d+ files' })

$diag | ForEach-Object { Write-Output $_ }
if ($summary) { Write-Output $summary[0].Trim() }

$warnings = @($diag | Where-Object { $_ -match ': warning\[' }).Count
$hints = @($diag | Where-Object { $_ -match ': hint\[' }).Count
$scope = if ($prefix) { $prefix } else { 'all files' }
Write-Output "[wowlua-check] $scope - $warnings warning(s), $hints hint(s)"
if ($warnings -gt 0) { exit 1 }
exit 0

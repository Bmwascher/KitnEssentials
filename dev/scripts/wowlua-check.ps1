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
#   3  cannot run (binary or .wowluarc.json missing, or the checker itself
#      failed) - callers treat this as "skipped" with a note, the same way
#      the pre-push hook treats a missing luacheck; the raw output is on stderr
#
# The binary is the standalone release in KitnDev\tools\wowlua-ls, installed
# and kept current by dev/scripts/update-wowlua-ls.ps1; WOWLUA_LS overrides it.

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
    $tools = Join-Path $env:USERPROFILE 'Documents\KitnDev\tools\wowlua-ls\wowlua_ls.exe'
    if (Test-Path -LiteralPath $tools) { return $tools }
    return $null
}

$exe = Resolve-WowluaLs
if (-not $exe) {
    [Console]::Error.WriteLine('[wowlua-check] skipped: wowlua_ls.exe not found (run pwsh dev/scripts/update-wowlua-ls.ps1, or set WOWLUA_LS).')
    exit 3
}
if (-not (Test-Path -LiteralPath (Join-Path $Root '.wowluarc.json'))) {
    [Console]::Error.WriteLine("[wowlua-check] skipped: no .wowluarc.json in $Root.")
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
    $ErrorActionPreference = 'Continue'
    $raw = @(& $exe check --severity $Severity . 2>&1 | ForEach-Object { "$_" })
    $toolExit = $LASTEXITCODE
} catch {
    [Console]::Error.WriteLine("[wowlua-check] skipped: the checker could not be started: $($_.Exception.Message)")
    exit 3
} finally {
    Pop-Location
    $ErrorActionPreference = 'Stop'
}

$diag = @($raw | Where-Object { $_ -match '^[^:\s][^:]*\.lua:\d+:\d+: ' })
if ($prefix) {
    $diag = @($diag | Where-Object { $_.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) })
}
$summary = @($raw | Where-Object { $_ -match '^\s*Checked \d+ files' })
# The checker prints its summary line on every completed run; without it the
# run aborted, and an aborted run must never read as clean.
if ($summary.Count -eq 0) {
    $raw | ForEach-Object { [Console]::Error.WriteLine($_) }
    [Console]::Error.WriteLine("[wowlua-check] skipped: the checker did not complete (exit $toolExit).")
    exit 3
}

$diag | ForEach-Object { Write-Output $_ }
if ($summary) { Write-Output $summary[0].Trim() }

$warnings = @($diag | Where-Object { $_ -match ': warning\[' }).Count
$hints = @($diag | Where-Object { $_ -match ': hint\[' }).Count
$scope = if ($prefix) { $prefix } else { 'all files' }
Write-Output "[wowlua-check] $scope - $warnings warning(s), $hints hint(s)"
if ($warnings -gt 0) { exit 1 }
exit 0

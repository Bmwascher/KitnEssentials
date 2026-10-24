# SessionStart hook: report library pins in .pkgmeta that upstream has moved
# past, so a library update is seen when it lands rather than at the next
# release. The script asks upstream at most once per 20 hours (cached in the
# git common dir), so most sessions read only the cache. Quiet when every pin
# is current or upstream cannot be reached; never blocks. Exit 0 always.

$root = $env:CLAUDE_PROJECT_DIR
if (-not $root) { exit 0 }
$script = Join-Path $root 'dev\scripts\check-lib-updates.ps1'
if (-not (Test-Path -LiteralPath $script)) { exit 0 }

try {
    $out = & pwsh -NoProfile -NonInteractive -File $script -Soft -Root $root 2>&1 | Out-String
} catch {
    $out = ''
}
if ($out -match '\[libs\] (FAIL|note)') {
    Write-Output ($out.Trim() + "`nUpdate: pwsh dev/scripts/check-lib-updates.ps1 -Update <name> on a feature branch (shipped code: /reload smoke before merge) - the rules are in that script's header.")
}
exit 0

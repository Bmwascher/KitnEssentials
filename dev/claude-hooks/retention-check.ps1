# SessionStart hook: run the process-artifact retention check and surface its
# findings into the session context, so stale plans, rounds and mirrors are
# seen at the start of every session rather than at the next audit. Quiet when
# the rule holds; silent on every failure to run. Never blocks. Exit 0 always.

$root = $env:CLAUDE_PROJECT_DIR
if (-not $root) { exit 0 }
$script = Join-Path $root 'dev\scripts\check-artifact-retention.ps1'
if (-not (Test-Path -LiteralPath $script)) { exit 0 }

try {
    $out = & pwsh -NoProfile -NonInteractive -File $script -Soft 2>&1 | Out-String
} catch {
    $out = ''
}
if ($out -match '\[retention\] (FAIL|note)') {
    Write-Output ($out.Trim() + "`nRun: pwsh dev/scripts/check-artifact-retention.ps1 (-Archive moves stale entries) - the rule is in that script's header.")
}
exit 0

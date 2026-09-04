# SessionStart hook: run the References/ folder-rule check and surface its
# findings into the session context, so a drifted reference tree is seen at
# the start of every session rather than at the next audit. Quiet when the
# rule holds; silent on every failure to run (missing lua, missing repo). The
# check itself never blocks anything. Output contract: exit 0 always.

$root = $env:CLAUDE_PROJECT_DIR
if (-not $root) { exit 0 }
$script = Join-Path $root 'dev\scripts\check-references-folders.lua'
if (-not (Test-Path -LiteralPath $script)) { exit 0 }
if (-not (Test-Path -LiteralPath (Join-Path $root 'References'))) { exit 0 }
if (-not (Get-Command lua -ErrorAction SilentlyContinue)) { exit 0 }

# The script resolves the repo root from its own absolute path, so no
# working-directory change is needed.
try {
    $out = & lua $script --soft 2>&1 | Out-String
} catch {
    $out = ''
}
if ($out -match '\[references\] (FAIL|note)') {
    Write-Output ($out.Trim() + "`nRun: lua dev/scripts/check-references-folders.lua — the folder rule is in the reference-tracker skill.")
}
exit 0

# SessionStart hook (matcher `compact`): after a compaction in a session
# registered as a phased-program master, print the skill's recovery card and
# the control document's Open questions and Status sections into the new
# context. Silent in every other session, and on every failure to run. The
# registry and the card are dev/scripts/program-master.ps1's; this file only
# reads the hook payload. Output contract: exit 0 always.

$root = $env:CLAUDE_PROJECT_DIR
if (-not $root) { exit 0 }
$script = Join-Path $root 'dev\scripts\program-master.ps1'
if (-not (Test-Path -LiteralPath $script)) { exit 0 }

$sessionId = ''
try {
    $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
    if ($payload.source -and $payload.source -ne 'compact') { exit 0 }
    $sessionId = [string]$payload.session_id
} catch { }

try { & $script -Recover -SessionId $sessionId } catch { }
exit 0

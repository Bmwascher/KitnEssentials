# PostToolUse hook (Edit|Write): after an edit under .claude/skills,
# .claude/commands, or the family skills folder the project junctions in,
# rebuild the .agents/skills mirror so Codex reads the same text. Silent on
# success and on every failure: the mirror is a convenience copy, never a
# reason to block an edit. Output contract: exit 0 always.

try {
    $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
} catch {
    exit 0
}

$file = $payload.tool_input.file_path
if (-not $file) { exit 0 }
$root = $env:CLAUDE_PROJECT_DIR
if (-not $root) { exit 0 }
$rootNorm = ($root -replace '/', '\').TrimEnd('\')
$base = if ($payload.cwd) { $payload.cwd } else { $rootNorm }
try { $full = [System.IO.Path]::GetFullPath(($file -replace '/', '\'), $base) } catch { exit 0 }

$sources = @(
    (Join-Path $rootNorm '.claude\skills\'),
    (Join-Path $rootNorm '.claude\commands\'),
    (Join-Path (Split-Path $rootNorm -Parent) '.claude\skills\')
)
$hit = $false
foreach ($s in $sources) {
    if ($full.StartsWith($s, [System.StringComparison]::OrdinalIgnoreCase)) { $hit = $true; break }
}
if (-not $hit) { exit 0 }

$script = Join-Path $rootNorm 'dev\scripts\sync-agents-mirror.ps1'
if (-not (Test-Path -LiteralPath $script)) { exit 0 }
try { & pwsh -NoProfile -NonInteractive -File $script *> $null } catch { }
exit 0

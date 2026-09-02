# PreToolUse hook (Edit|Write): deny edits to addon code while the checkout is on main.
# Exempt: dev/, .claude/, References/, and any non-.lua/.xml file (TOC, CHANGELOG, README,
# docs) so the release workflow keeps working on main.
# The file's repo and branch come from git, asked from the file's own directory, so
# relative paths, 8.3 spellings and the symlinked AddOns folder all resolve to the
# same checkout instead of escaping a string-prefix check.
# Output contract: silent exit 0 = allow; JSON permissionDecision=deny = block.

try {
    $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
} catch {
    exit 0
}

$file = $payload.tool_input.file_path
if (-not $file) { exit 0 }
if ($file -notmatch '\.(lua|xml)$') { exit 0 }

$base = $payload.cwd
if (-not $base) { $base = $env:CLAUDE_PROJECT_DIR }
if (-not $base) { $base = (Get-Location).Path }
try {
    $full = [System.IO.Path]::GetFullPath(($file -replace '/', '\'), ($base -replace '/', '\'))
} catch {
    exit 0
}

$dir = Split-Path -Parent $full
if (-not (Test-Path -LiteralPath $dir)) { exit 0 }
$leaf = Split-Path -Leaf $full

# Path of the file relative to its repo root, as git sees it.
$prefix = (& git -C $dir rev-parse --show-prefix 2>$null)
if ($LASTEXITCODE -ne 0) { exit 0 }
$rel = (("$prefix" -replace '/', '\').Trim() + $leaf)
if ($rel -match '^(dev|\.claude|References)\\') { exit 0 }

$branch = (& git -C $dir branch --show-current 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $branch) { exit 0 }
if ($branch.Trim() -ne 'main') { exit 0 }

$reason = "Checkout is on 'main' and '$rel' is addon code (.lua/.xml). Project rule: never do feature work on main - create or switch to a feature branch first (git switch -c <branch>), then retry the edit. Release files (.toc, CHANGELOG, README, dev/) are exempt from this guard."
$out = @{
    hookSpecificOutput = @{
        hookEventName            = 'PreToolUse'
        permissionDecision       = 'deny'
        permissionDecisionReason = $reason
    }
}
$out | ConvertTo-Json -Compress -Depth 5
exit 0

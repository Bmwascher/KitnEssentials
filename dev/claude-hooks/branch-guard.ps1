# PreToolUse hook (Edit|Write): deny edits to addon code while the checkout is on main.
# Exempt: dev/, .claude/, References/, and any non-.lua/.xml file (TOC, CHANGELOG, README,
# docs) so the release workflow keeps working on main.
# Output contract: silent exit 0 = allow; JSON permissionDecision=deny = block.

try {
    $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
} catch {
    exit 0
}

$file = $payload.tool_input.file_path
if (-not $file) { exit 0 }

$root = $env:CLAUDE_PROJECT_DIR
if (-not $root) { exit 0 }

$full = ($file -replace '/', '\')
$rootNorm = ($root -replace '/', '\').TrimEnd('\')
if (-not $full.StartsWith($rootNorm + '\', [System.StringComparison]::OrdinalIgnoreCase)) { exit 0 }

$rel = $full.Substring($rootNorm.Length).TrimStart('\')
if ($rel -notmatch '\.(lua|xml)$') { exit 0 }
if ($rel -match '^(dev|\.claude|References)\\') { exit 0 }

$branch = (& git -C $rootNorm branch --show-current 2>$null)
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

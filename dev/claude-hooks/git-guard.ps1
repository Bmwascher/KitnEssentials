# PreToolUse hook (Bash|PowerShell): deny git commands that destroy or sweep
# uncommitted work. Incidents this guard exists for: `git checkout --` and a
# sabotage-cleanup revert each destroyed live edits despite the standing
# memory rule, and `git add -A` swept a user's in-flight file into an
# unrelated commit.
# Denied shapes:
#   git checkout -- <path> / git checkout <ref> -- <path> / git checkout .
#   git restore <path>            (without --staged: discards the working tree)
#   git add -A / --all / .
# Allowed: branch switches (git checkout <branch>), git restore --staged,
# explicit-path staging.
# Output contract: silent exit 0 = allow; JSON permissionDecision=deny = block.

try {
    $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
} catch {
    exit 0
}

$cmd = $payload.tool_input.command
if (-not $cmd) { exit 0 }

$reason = $null

# checkout with a pathspec (` -- ` separator) or the bare-dot form.
if ($cmd -match 'git(\s+-C\s+\S+)?\s+checkout\b[^&|;>]*\s--(\s|$)' -or
    $cmd -match 'git(\s+-C\s+\S+)?\s+checkout\s+\.(\s|$)') {
    $reason = "git checkout with a pathspec discards uncommitted work (standing rule: never git checkout unstaged changes - it has destroyed live edits before). Stash or commit first, or copy the file aside; branch switches without a pathspec are allowed."
}
# restore without --staged touches the working tree.
elseif ($cmd -match 'git(\s+-C\s+\S+)?\s+restore\b' -and $cmd -notmatch '--staged') {
    $reason = "git restore without --staged discards uncommitted work (same standing rule as git checkout --). Use git restore --staged to unstage, or stash/copy before discarding."
}
# blanket staging.
elseif ($cmd -match 'git(\s+-C\s+\S+)?\s+add\s+(-A\b|--all\b|\.(\s|$))') {
    $reason = "Blanket staging is banned (family AGENTS.md git rules: stage by explicit path - git add -A once swept a user's in-flight file into an unrelated commit). List the files you mean to stage."
}

if (-not $reason) { exit 0 }

$out = @{
    hookSpecificOutput = @{
        hookEventName            = 'PreToolUse'
        permissionDecision       = 'deny'
        permissionDecisionReason = $reason
    }
}
$out | ConvertTo-Json -Compress -Depth 5
exit 0

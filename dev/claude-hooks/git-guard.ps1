# PreToolUse hook (Bash|PowerShell): deny git commands that destroy or sweep
# uncommitted work. Incidents this guard exists for: `git checkout --` and a
# sabotage-cleanup revert each destroyed live edits despite the standing
# memory rule, and `git add -A` swept a user's in-flight file into an
# unrelated commit.
# Denied shapes (evaluated per command segment, so a safe segment cannot
# launder an unsafe one):
#   git checkout -- <path> / git checkout <ref> -- <path> / git checkout .
#   git checkout -f/--force
#   git restore <path>            (without --staged/-S: discards the worktree)
#   git restore --worktree/-W     (discards even alongside --staged)
#   git add -A / --all / -u / --update / . / -- .
# Allowed: branch switches (git checkout <branch>), git restore --staged,
# explicit-path staging.
# Known limit: `git checkout <path>` without `--` is indistinguishable from a
# branch switch by text alone and is allowed — the `--` and `.` forms are the
# shapes the incidents used.
# Output contract: silent exit 0 = allow; JSON permissionDecision=deny = block.

try {
    $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
} catch {
    exit 0
}

$cmd = $payload.tool_input.command
if (-not $cmd) { exit 0 }

$git = 'git(\.exe)?(\s+-C\s+("[^"]+"|\S+))?'
$reason = $null

# Evaluate each chained segment independently: `git restore --staged A &&
# git restore B` must not let the first segment's --staged bless the second.
$segments = $cmd -split '(\r?\n|&&|\|\||[;|&])'
foreach ($seg in $segments) {
    if ($seg -notmatch "$git\s+(checkout|restore|add)\b") { continue }

    if ($seg -match "$git\s+checkout\b[^>]*\s--(\s|$)" -or
        $seg -match "$git\s+checkout\s+\.(\s|$)" -or
        $seg -match "$git\s+checkout\s+(-f\b|--force\b)") {
        $reason = "git checkout with a pathspec or --force discards uncommitted work (standing rule: never git checkout unstaged changes - it has destroyed live edits before). Stash or commit first, or copy the file aside; branch switches without a pathspec are allowed."
        break
    }
    if ($seg -match "$git\s+restore\b") {
        # -cmatch: `-S` (staged) and `-s` (--source) are different flags.
        $staged = $seg -cmatch '(\s|^)(--staged|-S)\b'
        $worktree = $seg -cmatch '(\s|^)(--worktree|-W)\b'
        if (-not $staged -or $worktree) {
            $reason = "git restore that touches the working tree discards uncommitted work (same standing rule as git checkout --). Use git restore --staged to unstage, or stash/copy before discarding."
            break
        }
    }
    if ($seg -match "$git\s+add\b") {
        # Tokenize the args after `add`; deny blanket-staging tokens.
        $args_ = ($seg -replace ".*?$git\s+add\b", '') -split '\s+' | Where-Object { $_ }
        foreach ($t in $args_) {
            if ($t -in @('.', './', '-A', '--all', '-u', '--update')) {
                $reason = "Blanket staging is banned (family AGENTS.md git rules: stage by explicit path - git add -A once swept a user's in-flight file into an unrelated commit). List the files you mean to stage."
                break
            }
        }
        if ($reason) { break }
    }
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

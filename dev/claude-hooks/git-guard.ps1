# PreToolUse hook (Bash|PowerShell): deny commands that destroy or sweep
# uncommitted work, and shell writes to addon code while the checkout is on
# main. Incidents this guard exists for: `git checkout --` and a
# sabotage-cleanup revert each destroyed live edits despite the standing
# memory rule, and `git add -A` swept a user's in-flight file into an
# unrelated commit.
# Denied git shapes (evaluated per command segment, so a safe segment cannot
# launder an unsafe one):
#   git checkout -- <path> / git checkout <ref> -- <path> / git checkout .
#   git checkout -f/--force
#   git switch -f/--force/--discard-changes
#   git restore <path>            (without --staged/-S: discards the worktree)
#   git restore --worktree/-W     (discards even alongside --staged)
#   git reset --hard / git clean (except -n/--dry-run) / git stash drop|clear
#   git commit -a/--all           (stages every modified file: the add -A sweep)
#   git add -A / --all / -u / --update / . / -- . / * / :/
# Allowed: branch switches (git checkout <branch>), git restore --staged,
# explicit-path staging, plain git stash.
# Denied on main only: writes to .lua/.xml under the repo, outside dev/,
# .claude/ and References/, through sed -i, >, >>, tee, Set-Content, Out-File
# or Add-Content. The Edit/Write branch guard cannot see shell writes.
# Known limits: `git checkout <path>` without `--` is indistinguishable from a
# branch switch by text alone and is allowed. Matching is textual over the
# whole command, quoted strings included, so a command that merely mentions a
# denied shape (echo, grep, a script body) is denied too; put the shape in a
# variable when it must appear.
# Output contract: silent exit 0 = allow; JSON permissionDecision=deny = block.

try {
    $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
} catch {
    exit 0
}

$cmd = $payload.tool_input.command
if (-not $cmd) { exit 0 }

# `git`, optionally followed by global options (-C <dir>, -c k=v, --no-pager,
# --git-dir=<x>) before the subcommand.
$git = 'git(\.exe)?(\s+(-[cC]\s+("[^"]+"|\S+)|--[a-z-]+(=\S+)?))*'
$reason = $null

# Evaluate each chained segment independently: `git restore --staged A &&
# git restore B` must not let the first segment's --staged bless the second.
$segments = $cmd -split '(\r?\n|&&|\|\||[;|&])'
foreach ($seg in $segments) {
    if ($seg -notmatch "$git\s+(checkout|switch|restore|add|commit|reset|clean|stash)\b") { continue }

    if ($seg -match "$git\s+checkout\b[^>]*\s--(\s|$)" -or
        $seg -match "$git\s+checkout\s+\.(\s|$)" -or
        $seg -match "$git\s+checkout\b[^>]*\s(-f|--force)\b") {
        $reason = "git checkout with a pathspec or --force discards uncommitted work (standing rule: never git checkout unstaged changes - it has destroyed live edits before). Stash or commit first, or copy the file aside; branch switches without a pathspec are allowed."
        break
    }
    if ($seg -match "$git\s+switch\b" -and $seg -cmatch '(\s|^)(-f|--force|--discard-changes)\b') {
        $reason = "git switch -f/--discard-changes throws away uncommitted work (same standing rule as git checkout --). Stash or commit first; a plain branch switch is allowed."
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
    if (($seg -match "$git\s+reset\b" -and $seg -cmatch '(\s|^)--hard\b') -or
        ($seg -match "$git\s+clean\b" -and $seg -cnotmatch '(\s|^)(-[a-zA-Z]*n[a-zA-Z]*|--dry-run)\b') -or
        $seg -match "$git\s+stash\s+(drop|clear)\b") {
        $reason = "This git command discards uncommitted or stashed work (standing rule: never discard without an explicit instruction). Copy the work aside first, or ask."
        break
    }
    if ($seg -match "$git\s+commit\b" -and $seg -cmatch '(\s|^)(--all|-[a-zA-Z]*a[a-zA-Z]*)\b') {
        $reason = "git commit -a stages every modified file (family AGENTS.md git rules: stage by explicit path - the index may carry someone else's in-flight edits). git add the files you mean, then commit."
        break
    }
    if ($seg -match "$git\s+add\b") {
        # Tokenize the args after `add`; deny blanket-staging tokens.
        $args_ = ($seg -replace ".*?$git\s+add\b", '') -split '\s+' | Where-Object { $_ }
        foreach ($t in $args_) {
            $bare = $t.Trim('"', "'")
            # -cmatch catches clustered short options too (`-uv`, `-Av`).
            if ($bare -in @('.', './', '*', ':/', ':(top)', '--all', '--update') -or $t -cmatch '^-[a-zA-Z]*[uA]') {
                $reason = "Blanket staging is banned (family AGENTS.md git rules: stage by explicit path - git add -A once swept a user's in-flight file into an unrelated commit). List the files you mean to stage."
                break
            }
        }
        if ($reason) { break }
    }
}

# Shell writes to addon code on main. The branch is read from the shell's
# working directory (the payload's cwd), which is where a relative target lands.
if (-not $reason) {
    $base = $payload.cwd
    if (-not $base) { $base = $env:CLAUDE_PROJECT_DIR }
    if (-not $base) { $base = (Get-Location).Path }
    $base = ($base -replace '/', '\').TrimEnd('\')
    $branch = (& git -C $base branch --show-current 2>$null)
    if ($LASTEXITCODE -eq 0 -and $branch -and $branch.Trim() -eq 'main') {
        $top = (& git -C $base rev-parse --show-toplevel 2>$null)
        $top = if ($top) { ($top.Trim() -replace '/', '\').TrimEnd('\') } else { $base }
        $target = '(?<t>[^\s"''|;&<>]+\.(lua|xml))(?=[\s"''|;&)]|$)'
        $writes = @(
            "\bsed(\.exe)?\s+(-[a-zA-Z]*i|--in-place)[^|;&]*?\s$target",
            ">{1,2}\s*$target",
            "\btee(\.exe)?\s+(-a\s+)?$target",
            "\b(Set-Content|Out-File|Add-Content)\b[^|;&]*?(-(Literal)?Path\s+|\s)$target"
        )
        foreach ($seg in $segments) {
            foreach ($w in $writes) {
                if ($seg -notmatch $w) { continue }
                $t = ($Matches['t'] -replace '/', '\')
                try { $full = [System.IO.Path]::GetFullPath($t, $base) } catch { continue }
                if (-not $full.StartsWith($top + '\', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                $rel = $full.Substring($top.Length).TrimStart('\')
                if ($rel -match '^(dev|\.claude|References)\\') { continue }
                $reason = "Checkout is on 'main' and this command writes addon code ('$rel'). Project rule: never do feature work on main - switch to a feature branch first (git switch -c <branch>). Shell writes are guarded here because the Edit/Write branch guard cannot see them."
                break
            }
            if ($reason) { break }
        }
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

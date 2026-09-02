# PreToolUse hook (Bash|PowerShell): deny commands that destroy or sweep
# uncommitted work, and shell writes to addon code while the checkout is on
# main. Incidents this guard exists for: `git checkout --` and a
# sabotage-cleanup revert each destroyed live edits despite the standing
# memory rule, and `git add -A` swept a user's in-flight file into an
# unrelated commit.
# Denied git shapes (evaluated per command segment, so a safe segment cannot
# launder an unsafe one; global options between git and the subcommand are
# consumed first):
#   git checkout -- <path> / git checkout <ref> -- <path> / git checkout .
#   git checkout -f/--force/--pathspec-from-file
#   git switch -f/--force/--discard-changes
#   git restore <path>            (without --staged/-S: discards the worktree)
#   git restore --worktree/-W     (discards even alongside --staged)
#   git reset --hard / git clean (except -n/--dry-run) / git stash drop|clear
#   git commit -a/--all           (stages every modified file: the add -A sweep)
#   git add -A / --all / -u / --update / . / -- . / * / ** / :/ / :/* / :(top)*
# Allowed: branch switches (git checkout <branch>), git restore --staged,
# explicit-path staging (a root-relative :/Core/X.lua included), plain git
# stash.
# Denied on main only: writes to .lua/.xml inside the repo, outside dev/,
# .claude/ and References/, through sed -i, >, >>, tee, Set-Content, Out-File,
# Add-Content or Tee-Object. The Edit/Write branch guard cannot see shell
# writes. A cd/Set-Location earlier in the same command moves the directory
# relative targets resolve against; the repo and branch of the target come
# from git asked at the target's nearest existing ancestor, so junction
# spellings and not-yet-created folders resolve too.
# Known limits: `git checkout <path>` without `--` is indistinguishable from a
# branch switch by text alone and is allowed. Matching is textual over the
# whole command, quoted strings included, so a command that merely mentions a
# denied shape (echo, grep, a script body) is denied too; put the shape in a
# variable when it must appear. When git itself is not on PATH the write
# guard denies addon-code writes rather than guessing the branch.
# Output contract: silent exit 0 = allow; JSON permissionDecision=deny = block.

try {
    $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
} catch {
    exit 0
}

$cmd = $payload.tool_input.command
if (-not $cmd) { exit 0 }

# `git`, then any global options: ones that take a separate value (-C, -c,
# --git-dir, --work-tree, ...), long flags with or without =value, and the
# short pager flags.
$gopt = '(-[cC]\s+("[^"]+"|\S+)|--(git-dir|work-tree|namespace|exec-path|super-prefix|config-env|attr-source)(=\S+|\s+("[^"]+"|\S+))|--[a-z-]+(=\S+)?|-[pP])'
$git = "git(\.exe)?(\s+$gopt)*"
$reason = $null

# Evaluate each chained segment independently: `git restore --staged A &&
# git restore B` must not let the first segment's --staged bless the second.
$segments = $cmd -split '(\r?\n|&&|\|\||[;|&])'
foreach ($seg in $segments) {
    if ($seg -notmatch "$git\s+(checkout|switch|restore|add|commit|reset|clean|stash)\b") { continue }

    if ($seg -match "$git\s+checkout\b[^>]*\s--(\s|$)" -or
        $seg -match "$git\s+checkout\s+\.(\s|$)" -or
        $seg -cmatch "$git\s+checkout\b.*\s(-[a-zA-Z]*f[a-zA-Z]*|--force|--pathspec-from-file(=\S+)?)(\s|$)") {
        $reason = "git checkout with a pathspec or --force discards uncommitted work (standing rule: never git checkout unstaged changes - it has destroyed live edits before). Stash or commit first, or copy the file aside; branch switches without a pathspec are allowed."
        break
    }
    if ($seg -match "$git\s+switch\b" -and $seg -cmatch '\s(-[a-zA-Z]*f[a-zA-Z]*|--force|--discard-changes)(\s|$)') {
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
    if (($seg -match "$git\s+reset\b" -and $seg -cmatch '\s--hard(\s|$)') -or
        ($seg -match "$git\s+clean\b" -and $seg -cnotmatch '\s(-[a-zA-Z]*n[a-zA-Z]*|--dry-run)(\s|$)') -or
        $seg -match "$git\s+stash\s+(drop|clear)\b") {
        $reason = "This git command discards uncommitted or stashed work (standing rule: never discard without an explicit instruction). Copy the work aside first, or ask."
        break
    }
    if ($seg -match "$git\s+commit\b" -and $seg -cmatch '\s(--all|-[a-zA-Z]*a[a-zA-Z]*)(\s|$)') {
        $reason = "git commit -a stages every modified file (family AGENTS.md git rules: stage by explicit path - the index may carry someone else's in-flight edits). git add the files you mean, then commit."
        break
    }
    if ($seg -match "$git\s+add\b") {
        # Tokenize the args after `add`; deny blanket-staging tokens.
        $args_ = ($seg -replace ".*?$git\s+add\b", '') -split '\s+' | Where-Object { $_ }
        foreach ($t in $args_) {
            $bare = $t.Trim('"', "'")
            # -cmatch catches clustered short options too (`-uv`, `-Av`).
            if ($bare -match '^(\.|\./|\*+|\./\*+|:/\**|:\(top\)\**|--all|--update)$' -or $t -cmatch '^-[a-zA-Z]*[uA]') {
                $reason = "Blanket staging is banned (family AGENTS.md git rules: stage by explicit path - git add -A once swept a user's in-flight file into an unrelated commit). List the files you mean to stage."
                break
            }
        }
        if ($reason) { break }
    }
}

# Repo-relative path, branch and toplevel of a file, asked from its nearest
# existing ancestor. Null when the path is in no repo.
function Get-RepoInfo([string]$full) {
    $dir = Split-Path -Parent $full
    $tail = @(Split-Path -Leaf $full)
    while ($dir -and -not (Test-Path -LiteralPath $dir)) {
        $tail = @(Split-Path -Leaf $dir) + $tail
        $dir = Split-Path -Parent $dir
    }
    if (-not $dir) { return $null }
    $prefix = (& git -C $dir rev-parse --show-prefix 2>$null)
    if ($LASTEXITCODE -ne 0) { return $null }
    $branch = (& git -C $dir branch --show-current 2>$null)
    return @{
        rel    = (("$prefix".Trim() -replace '/', '\') + ($tail -join '\'))
        branch = "$branch".Trim()
    }
}

# Shell writes to addon code on main.
if (-not $reason) {
    $cwd = $payload.cwd
    if (-not $cwd) { $cwd = $env:CLAUDE_PROJECT_DIR }
    if (-not $cwd) { $cwd = (Get-Location).Path }
    $cwd = ($cwd -replace '/', '\').TrimEnd('\')
    $gitOk = [bool](Get-Command git -ErrorAction SilentlyContinue)
    $target = '["'']?(?<t>[^\s"''|;&<>]+\.(lua|xml))["'']?(?=[\s"''|;&)]|$)'
    $writes = @(
        "\bsed(\.exe)?\s+(-[a-zA-Z]*i|--in-place)[^|;&]*?\s$target",
        ">{1,2}\s*$target",
        "\btee(\.exe)?\s+(-a\s+)?$target",
        "\b(Set-Content|Out-File|Add-Content|Tee-Object)\b[^|;&]*?(-(Literal|File)?Path\s+|\s)$target"
    )
    foreach ($seg in $segments) {
        if ($seg -match '^\s*(cd|chdir|pushd|sl|Set-Location|Push-Location)\s+(-(Literal)?Path\s+)?["'']?(?<d>[^\s"'']+)') {
            try { $cwd = [System.IO.Path]::GetFullPath(($Matches['d'] -replace '/', '\'), $cwd) } catch { }
            continue
        }
        foreach ($w in $writes) {
            if ($seg -notmatch $w) { continue }
            $t = ($Matches['t'] -replace '/', '\')
            try { $full = [System.IO.Path]::GetFullPath($t, $cwd) } catch { continue }
            if (-not $gitOk) {
                $reason = "git is not on PATH, so the branch of '$t' cannot be checked before a shell write to addon code. Use the Edit tool, or fix PATH."
                break
            }
            $info = Get-RepoInfo $full
            if (-not $info) { continue }
            if ($info.rel -match '^(dev|\.claude|References)\\') { continue }
            if ($info.branch -ne 'main') { continue }
            $reason = "Checkout is on 'main' and this command writes addon code ('$($info.rel)'). Project rule: never do feature work on main - switch to a feature branch first (git switch -c <branch>). Shell writes are guarded here because the Edit/Write branch guard cannot see them."
            break
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

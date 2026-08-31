# Shared guards for the commit-msg, pre-commit and pre-push hooks. Sourced,
# never run: each function prints its own BLOCKED lines and returns 1 on a
# hit, so the caller decides when to exit.
#
# The patterns live in upstream-names.local.sh, gitignored beside this file:
# the repo is public, and publishing the lists leaks the very names the guards
# keep out of history and shipped comments.

ng_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Plan-step references, review/session history, dates, file:line citations.
# Month names need a year beside them: bare "March" is game content, not a
# date. Slash dates are absent on purpose — spell range and rank lists read
# as 30/33/36 and would trip on every one.
ng_history='[Ss]tep [A-Z][0-9]+|[Tt]ask [0-9]+|round of review|review round|per the plan|References/|20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]|([Jj]an|[Ff]eb|[Mm]ar|[Aa]pr|[Mm]ay|[Jj]un|[Jj]ul|[Aa]ug|[Ss]ep|[Oo]ct|[Nn]ov|[Dd]ec)[a-z]* 20[0-9][0-9]|\bv[0-9]+\.[0-9]+|\.(lua|xml):[0-9]+'

# ng_load <tag> <required set>...
ng_load() {
    local tag="$1"; shift
    ng_names_file="$ng_dir/upstream-names.local.sh"
    if [ ! -f "$ng_names_file" ]; then
        echo "[$tag] BLOCKED: missing local word list $ng_names_file (restore it from the local backup; format is in dev/README.md). Override with --no-verify" >&2
        return 1
    fi
    # shellcheck source=/dev/null
    . "$ng_names_file"
    local set val
    for set in "$@"; do
        eval "val=\${$set:-}"
        if [ -z "$val" ]; then
            echo "[$tag] BLOCKED: $ng_names_file defines no $set patterns." >&2
            return 1
        fi
    done
    return 0
}

# ng_added_comments <git diff args>... — the comment tail of every added line
# in addon source. Code may legitimately carry addon names (conflict registry
# detection strings) and step-like UI text; comments may not.
# Known limit: body lines of --[[ ]] block comments carry no `--` and are not
# scanned — diff hunks are partial, so block-comment state cannot be tracked.
ng_added_comments() {
    git diff -U0 --no-color "$@" -- '*.lua' '*.xml' ':(exclude)dev/*' ':(exclude).claude/*' \
        | grep -E '^\+[^+]' | grep -oE -- '--.*' || true
}

# ng_scan_text <tag> <noun> <text> — names anywhere in a message.
# No `head` inside the pipelines: under pipefail, grep dying on SIGPIPE reads
# as "no match" and waves the push through.
ng_scan_text() {
    local tag="$1" noun="$2" text="$3" hit hit2 chit
    hit="$(printf '%s\n' "$text" | grep -ioE "$stems" | sort -u | tr '\n' ' ' || true)"
    hit2="$(printf '%s\n' "$text" | grep -iwoE "$shorts" | sort -u | tr '\n' ' ' || true)"
    if [ -n "$hit$hit2" ]; then
        echo "[$tag] BLOCKED: $noun contains upstream addon name(s): $hit$hit2" >&2
        echo "[$tag] Reference provenance belongs in local docs, never in published history." >&2
        return 1
    fi
    # Compat names are addons the project legitimately talks about — it detects
    # them, skins them, or stands modules down under them — so naming one is a
    # leak only next to provenance vocabulary.
    if printf '%s\n' "$text" | grep -qiE "$provenance"; then
        chit="$(printf '%s\n' "$text" | grep -ioE "$compat" | sort -u | tr '\n' ' ' || true)"
        if [ -n "$chit" ]; then
            echo "[$tag] BLOCKED: $noun — addon(s) named next to provenance vocabulary: $chit" >&2
            echo "[$tag] Say what the change does, not where it came from." >&2
            return 1
        fi
    fi
    return 0
}

# ng_scan_comments <tag> <noun> <comment lines> — the full comment rule set.
ng_scan_comments() {
    local tag="$1" noun="$2" comments="$3" fail=0 hits chits hhits provlines
    [ -n "$comments" ] || return 0
    # namesCI holds names that are not English or WoW words, so they scan
    # case-insensitively; namesCS holds names that double as plausible WoW
    # words and only match capitalised.
    hits="$( { printf '%s\n' "$comments" | grep -ioE "$stems"; printf '%s\n' "$comments" | grep -iwoE "$namesCI"; printf '%s\n' "$comments" | grep -woE "$namesCS"; } | sort -u | tr '\n' ' ' || true)"
    if [ -n "$hits" ]; then
        echo "[$tag] BLOCKED: $noun — personal/agent/upstream names: $hits" >&2
        fail=1
    fi
    provlines="$(printf '%s\n' "$comments" | grep -iE "$provenance" || true)"
    chits="$(printf '%s\n' "$provlines" | grep -ioE "$compat" | sort -u | tr '\n' ' ' || true)"
    if [ -n "$chits" ]; then
        echo "[$tag] BLOCKED: $noun — addon(s) named next to provenance vocabulary: $chits" >&2
        fail=1
    fi
    hhits="$(printf '%s\n' "$comments" | grep -nE "$ng_history" || true)"
    if [ -n "$hhits" ]; then
        echo "[$tag] BLOCKED: $noun — plan-step/date/history references:" >&2
        printf '%s\n' "$hhits" | sed -n '1,5p' >&2
        fail=1
    fi
    if [ "$fail" -eq 1 ]; then
        echo "[$tag] Comment rules: decisions stand on their own — no names, no plan steps, no dates, no session history in shipped comments." >&2
        return 1
    fi
    return 0
}

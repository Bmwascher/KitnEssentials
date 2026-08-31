# Shared guards for the commit-msg, pre-commit and pre-push hooks. Sourced,
# never run: each function prints its own BLOCKED lines and returns 1 on a
# hit, so the caller decides when to exit.
#
# The name patterns live in upstream-names.local.sh, gitignored beside this
# file: the repo is public, and publishing the lists leaks the very names the
# guards keep out of history and shipped comments. Date forms are canonical
# here, in ng_dates, so the compat gate and the comment ban read one
# definition.

ng_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Libs/ is embedded third-party code, not ours to write comments in, and its
# upstream headers carry dates and version stamps that the rules ban here.
ng_paths=('*.lua' '*.xml' ':(exclude)dev/*' ':(exclude).claude/*' ':(exclude)Libs/*')

# Plan-step references, review/session history, file:line citations.
ng_history='[Ss]tep [A-Z][0-9]+|[Tt]ask [0-9]+|round of review|review round|per the plan|References/|\bv[0-9]+\.[0-9]+|\.(lua|xml):[0-9]+'

# Dates, scanned case-insensitively. Numeric forms constrain the day and
# month so spell range and rank lists do not read as dates: 30/33/36 and
# 24/30/24 have no component that can be a month, and no four-digit year.
ng_dates='20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
ng_dates="$ng_dates|(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*,? +(19|20)[0-9][0-9]"
ng_dates="$ng_dates|\b[0-9]{1,2}/[0-9]{1,2}/(19|20)[0-9][0-9]\b"
ng_dates="$ng_dates|\b(0?[1-9]|1[0-2])/(0?[1-9]|[12][0-9]|3[01])/[0-9]{2}\b"
ng_dates="$ng_dates|\b(0?[1-9]|[12][0-9]|3[01])/(0?[1-9]|1[0-2])/[0-9]{2}\b"

# ng_load <tag> <required set>...
# Clears the sets before sourcing: an exported variable of the same name in
# the caller's environment would otherwise satisfy the check on its own.
ng_load() {
    local tag="$1"; shift
    ng_names_file="$ng_dir/upstream-names.local.sh"
    if [ ! -f "$ng_names_file" ]; then
        echo "[$tag] BLOCKED: missing local word list $ng_names_file (restore it from the local backup; format is in dev/README.md). Override with --no-verify" >&2
        return 1
    fi
    unset stems shorts compat provenance namesCI namesCS
    # shellcheck source=/dev/null
    if ! . "$ng_names_file"; then
        echo "[$tag] BLOCKED: $ng_names_file failed to load." >&2
        return 1
    fi
    local set val st
    for set in "$@"; do
        eval "val=\${$set:-}"
        if [ -z "$val" ]; then
            echo "[$tag] BLOCKED: $ng_names_file defines no $set patterns." >&2
            return 1
        fi
        # grep exits 1 for no match and 2 for a bad pattern. Unchecked, an
        # unparsable set errors into the scanners' fallbacks and reads as a
        # clean scan.
        printf '' | grep -qE "$val" 2>/dev/null
        st=$?
        if [ "$st" -gt 1 ]; then
            echo "[$tag] BLOCKED: $ng_names_file defines $set as an invalid pattern." >&2
            return 1
        fi
    done
    return 0
}

# The comment tail of every added line in a diff. Code may legitimately carry
# addon names (conflict registry detection strings) and step-like UI text;
# comments may not.
# Known limit: body lines of block comments carry no leading dashes and are
# not scanned - diff hunks are partial, so block-comment state cannot be
# tracked.
ng_comment_tails() {
    printf '%s\n' "$1" | grep -E '^\+[^+]' | grep -oE -- '--.*' || true
}

# ng_staged_comments - added comment lines in the index. Returns 1 when git
# itself failed, so a broken call can never read as a clean scan.
ng_staged_comments() {
    local out
    out="$(git diff -U0 --no-color --cached -- "${ng_paths[@]}")" || return 1
    ng_comment_tails "$out"
}

# ng_commit_comments <sha> - added comment lines in ONE commit. Per-commit,
# not endpoint to endpoint: a comment added in one commit and removed in a
# later one is invisible to a range diff yet still published.
# Known limit: a merge commit shows no diff here, so text invented while
# resolving a conflict is not scanned; the merged commits themselves are.
ng_commit_comments() {
    local out
    out="$(git show --format= -U0 --no-color "$1" -- "${ng_paths[@]}")" || return 1
    ng_comment_tails "$out"
}

# ng_scan_text <tag> <noun> <text> - names anywhere in a message.
# No head inside the pipelines: under pipefail, grep dying on SIGPIPE reads
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
    # Compat names are addons the project legitimately talks about - it
    # detects them, skins them, or stands modules down under them - so naming
    # one is a leak only next to provenance vocabulary or a date.
    if printf '%s\n' "$text" | grep -qiE "$provenance|$ng_dates"; then
        chit="$(printf '%s\n' "$text" | grep -ioE "$compat" | sort -u | tr '\n' ' ' || true)"
        if [ -n "$chit" ]; then
            echo "[$tag] BLOCKED: $noun - addon(s) named next to provenance vocabulary: $chit" >&2
            echo "[$tag] Say what the change does, not where it came from." >&2
            return 1
        fi
    fi
    return 0
}

# ng_scan_comments <tag> <noun> <comment lines> - the full comment rule set.
ng_scan_comments() {
    local tag="$1" noun="$2" comments="$3" fail=0 hits chits hhits provlines
    [ -n "$comments" ] || return 0
    # namesCI holds names that are not English or WoW words, so they scan
    # case-insensitively; namesCS holds names that double as plausible WoW
    # words and only match capitalised.
    hits="$( { printf '%s\n' "$comments" | grep -ioE "$stems"; printf '%s\n' "$comments" | grep -iwoE "$namesCI"; printf '%s\n' "$comments" | grep -woE "$namesCS"; } | sort -u | tr '\n' ' ' || true)"
    if [ -n "$hits" ]; then
        echo "[$tag] BLOCKED: $noun - personal/agent/upstream names: $hits" >&2
        fail=1
    fi
    provlines="$(printf '%s\n' "$comments" | grep -iE "$provenance|$ng_dates" || true)"
    chits="$(printf '%s\n' "$provlines" | grep -ioE "$compat" | sort -u | tr '\n' ' ' || true)"
    if [ -n "$chits" ]; then
        echo "[$tag] BLOCKED: $noun - addon(s) named next to provenance vocabulary: $chits" >&2
        fail=1
    fi
    hhits="$( { printf '%s\n' "$comments" | grep -nE "$ng_history"; printf '%s\n' "$comments" | grep -niE "$ng_dates"; } | sort -u || true)"
    if [ -n "$hhits" ]; then
        echo "[$tag] BLOCKED: $noun - plan-step/date/history references:" >&2
        printf '%s\n' "$hhits" | sed -n '1,5p' >&2
        fail=1
    fi
    if [ "$fail" -eq 1 ]; then
        echo "[$tag] Comment rules: decisions stand on their own - no names, no plan steps, no dates, no session history in shipped comments." >&2
        return 1
    fi
    return 0
}

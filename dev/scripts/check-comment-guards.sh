#!/usr/bin/env bash
# Standing self-check for the guards' word list.
#
# The list is gitignored, so no diff review can see a change to it. This is
# what catches a name that collides with the project's own vocabulary: a
# reference addon whose title a module kept, or one the conflict registry
# documents by name. Such a name belongs in compat, where the provenance gate
# decides, not in stems, where it blocks the next edit to any of those files.
#
# Run it after every word-list edit:
#     bash dev/scripts/check-comment-guards.sh
#
# Exit 1 means the list disagrees with the code that ships today.
set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || exit 1
# shellcheck source=/dev/null
. dev/githooks/lib/name-guards.sh
ng_load check-comment-guards stems compat provenance namesCI namesCS || exit 1

# Read the committed tree, never the working tree: an uncommitted edit must
# not let the audit pass while HEAD still breaks the invariant. Each file is
# then fed to the hooks' own extractor as a synthetic single-hunk diff, so
# block comment bodies are read by the one parser rather than by a second
# approximation of it.
if ! files="$(git grep -lI --fixed-strings -e '' HEAD -- "${ng_paths[@]}")"; then
    echo "[check-comment-guards] BLOCKED: could not list the source files at HEAD." >&2
    exit 1
fi
if [ -z "$files" ]; then
    echo "[check-comment-guards] BLOCKED: HEAD carries no addon source to scan." >&2
    exit 1
fi

if ! synth="$(mktemp)"; then
    echo "[check-comment-guards] BLOCKED: could not create a scratch file." >&2
    exit 1
fi
trap 'rm -f "$synth"' EXIT
count=0
while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    path="${entry#HEAD:}"
    # The trailing newline matters: a blob that ends without one would run
    # into the next file's header and be read as part of its own last line.
    if ! printf 'diff --git a/%s b/%s\n@@\n' "$path" "$path" >> "$synth" \
        || ! { git show "HEAD:$path" | sed 's/^/+/' >> "$synth"; } \
        || ! printf '\n' >> "$synth"; then
        echo "[check-comment-guards] BLOCKED: could not read HEAD:$path" >&2
        exit 1
    fi
    count=$((count + 1))
done <<< "$files"

# Each step checked on its own: a nested substitution hides its own failure
# inside the outer assignment's status, and the audit would then report OK
# on no input at all.
if ! synth_text="$(cat "$synth")"; then
    echo "[check-comment-guards] BLOCKED: could not read back the scratch file." >&2
    exit 1
fi
if ! comments="$(ng_comment_tails "$synth_text")"; then
    echo "[check-comment-guards] BLOCKED: the comment extractor failed." >&2
    exit 1
fi
echo "[check-comment-guards] $count files, $(printf '%s\n' "$comments" | grep -c '' || true) comment lines at HEAD"

# The enforcing pass. grep exits 1 for no match; anything higher is a real
# failure, and swallowing it would turn a broken run into a clean audit.
ng_collect() {
    local out st
    out="$(printf '%s\n' "$comments" | grep "$1" -E "$2")"
    st=$?
    [ "$st" -le 1 ] || return 1
    printf '%s' "$out"
}

fail=0
if ! h_stems="$(ng_collect -io "$stems")" \
    || ! h_ci="$(ng_collect -iwo "$namesCI")" \
    || ! h_cs="$(ng_collect -wo "$namesCS")"; then
    echo "[check-comment-guards] BLOCKED: a match pass failed to run." >&2
    exit 1
fi
if [ -n "$h_stems$h_ci$h_cs" ]; then
    hits="$(printf '%s %s %s' "$h_stems" "$h_ci" "$h_cs" | tr '\n' ' ')"
    echo "[check-comment-guards] FAIL: shipped comments name: $hits" >&2
    git grep -inE "$stems" HEAD -- "${ng_paths[@]}" 2>/dev/null | sed -n '1,5p' >&2 || true
    echo "[check-comment-guards] Move those to compat, or rename what the code calls itself." >&2
    fail=1
fi

# Everything below is reported, never enforced. These are comment lines
# written before the guards existed, and the hooks only ever read ADDED lines,
# so none of them blocks anything until someone edits that line. They are a
# cleanup backlog, not a broken list. A rising count is the signal.
chits="$(printf '%s\n' "$comments" | grep -iE "$provenance|$ng_dates" | grep -ioE "$compat" | sort -uf | tr '\n' ' ' || true)"
[ -n "$chits" ] && echo "[check-comment-guards] pre-existing provenance beside: $chits"
hcount="$(printf '%s\n' "$comments" | grep -cE "$ng_history" || true)"
dcount="$(printf '%s\n' "$comments" | grep -ciE "$ng_dates" || true)"
echo "[check-comment-guards] pre-existing: $hcount history references, $dcount dates"

if [ "$fail" -eq 1 ]; then
    exit 1
fi
echo "[check-comment-guards] OK"
exit 0

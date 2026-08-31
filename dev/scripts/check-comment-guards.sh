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

synth="$(mktemp)"
trap 'rm -f "$synth"' EXIT
count=0
while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    path="${entry#HEAD:}"
    printf 'diff --git a/%s b/%s\n@@\n' "$path" "$path" >> "$synth"
    if ! git show "HEAD:$path" | sed 's/^/+/' >> "$synth"; then
        echo "[check-comment-guards] BLOCKED: could not read HEAD:$path" >&2
        exit 1
    fi
    count=$((count + 1))
done <<< "$files"

comments="$(ng_comment_tails "$(cat "$synth")")"
echo "[check-comment-guards] $count files, $(printf '%s\n' "$comments" | grep -c '' || true) comment lines at HEAD"

fail=0
hits="$( { printf '%s\n' "$comments" | grep -ioE "$stems"; printf '%s\n' "$comments" | grep -iwoE "$namesCI"; printf '%s\n' "$comments" | grep -woE "$namesCS"; } | sort -uf | tr '\n' ' ' || true)"
if [ -n "$hits" ]; then
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

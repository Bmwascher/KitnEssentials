#!/usr/bin/env bash
# American spelling guard. The project writes American English everywhere:
# comments, help strings, docs, identifiers. British forms used to creep in
# one file at a time until the same concept was spelled two ways across the
# tree (colour/color, centre/center, normalise/normalize), so this is a
# gate, not a style note.
#
#     bash dev/scripts/check-spelling.sh            every tracked text file (CI)
#     bash dev/scripts/check-spelling.sh --staged   added lines of the staged diff (pre-commit)
#
# Exit 1 lists each offending line as file:line:text. Blizzard identifiers
# and game item names that carry British spelling are scrubbed before the
# match; add to the allow list below, never to the pattern.
set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || exit 1

# Three families, each case-sensitive so camelCase halves count
# (bestCentre, NormaliseFrequency) while realism, organism, specialist,
# cancellation and levelLock survive.
#   sub:   British substring anywhere in a word.
#   gated: an -is stem or doubled consonant that is British only with a verb
#          suffix; the suffix may end the word or meet an uppercase letter.
#   whole: full words only.
sub='colour|behaviour|favourite|honour|neighbour|armour|flavour|humour|centre|grey|labour|rumour|savour|vapour|harbour|endeavour'
gated_stems='normalis|initialis|organis|recognis|realis|customis|optimis|minimis|maximis|serialis|synchronis|summaris|visualis|prioritis|standardis|finalis|stabilis|utilis|categoris|localis|capitalis|specialis|generalis|emphasis|sanitis|authoris|memoris|randomis|stylis|itemis|analys|paralys|practis'
gated_suf='(e|ed|es|ing|ation|ations|ers?|able|ably|ability)'
doubled_stems='cancell|travell|modell|labell|levell|signall|fuell|diall|totall|channell'
doubled_suf='(ed|ing|ers?|able)'
whole='catalogue|dialogue|defence|offence|licence|pretence|artefact|mould|judgement|acknowledgement|fulfil|fulfilment|skilful|enrol|enrolment|instalment|whilst|amongst|learnt|spelt|afterwards|towards|ageing|aluminium|storey|sceptic|manoeuvre|anticlockwise|tyre|kerb|programme'

# Capitalized twin of an alternation: colour|grey -> Colour|Grey.
cap() { printf '%s' "$1" | sed -E 's/(^|\||\()([a-z])/\1\u\2/g'; }
upper() { printf '%s' "$1" | tr 'a-z' 'A-Z'; }

pattern="($sub|$(cap "$sub")|$(upper "$sub"))"
pattern="$pattern|($gated_stems|$(cap "$gated_stems"))$gated_suf([^a-z]|$)"
pattern="$pattern|($doubled_stems|$(cap "$doubled_stems"))$doubled_suf([^a-z]|$)"
pattern="$pattern|(^|[^A-Za-z])($whole|$(cap "$whole"))s?([^a-z]|$)"

# Allowed: Blizzard globals, game item names, and the GUI search alias that
# lets a player type the British word.
scrub() {
    sed -E 's/GameFontNormalLeftGrey|Draught of|"colour"/ALLOWED/g'
}

if [ "${1:-}" = "--staged" ]; then
    # file:line of each added line, built from the hunk headers so the
    # report points at the staged file.
    hits="$(git diff -U0 --no-color --cached -- . ':!Libs' ':!References' ':!Media' ':!dev/scripts/check-spelling.sh' \
        | awk '
            /^\+\+\+ / { file = substr($0, 7); next }
            /^@@/ { split($3, a, ","); line = substr(a[1], 2) + 0; next }
            /^\+/ { print file ":" line ":" substr($0, 2); line++; next }
            /^-/ { next }
            /^ / { line++ }
        ' | scrub | grep -E "$pattern" || true)"
    tag="pre-commit"
else
    hits="$(git ls-files -z -- . ':!Libs' ':!References' ':!Media' ':!dev/scripts/check-spelling.sh' \
        | xargs -0 grep -InE "$pattern" -- 2>/dev/null \
        | scrub | grep -E "$pattern" || true)"
    tag="check-spelling"
fi

[ -z "$hits" ] && exit 0
echo "[$tag] BLOCKED: British spelling; the project writes American English (dev/README.md, Spelling):" >&2
printf '%s\n' "$hits" | sed -n '1,20p' >&2
n="$(printf '%s\n' "$hits" | wc -l)"
[ "$n" -gt 20 ] && echo "[$tag] ... and $((n - 20)) more" >&2
exit 1

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
whole='catalogue|dialogue|defence|offence|licence|pretence|artefact|mould|judgement|acknowledgement|fulfil|fulfilment|skilful|enrol|enrolment|instalment|whilst|amongst|learnt|spelt|afterwards|towards|ageing|aluminium|storey|sceptic|manoeuvre|anticlockwise|tyre|kerb|programme|centring|analogue'

# Capitalized and uppercase twins of an alternation: colour|grey ->
# Colour|Grey and COLOUR|GREY, so a constant such as CANCELLED_AT or
# NORMALISE_FREQUENCY is caught like the camelCase forms.
cap() { printf '%s' "$1" | sed -E 's/(^|\||\()([a-z])/\1\u\2/g'; }
upper() { printf '%s' "$1" | tr 'a-z' 'A-Z'; }

pattern="($sub|$(cap "$sub")|$(upper "$sub"))"
pattern="$pattern|($gated_stems|$(cap "$gated_stems"))$gated_suf([^a-z]|$)"
pattern="$pattern|($(upper "$gated_stems"))$(upper "$gated_suf")([^A-Za-z]|$)"
pattern="$pattern|($doubled_stems|$(cap "$doubled_stems"))$doubled_suf([^a-z]|$)"
pattern="$pattern|($(upper "$doubled_stems"))$(upper "$doubled_suf")([^A-Za-z]|$)"
pattern="$pattern|(^|[^A-Za-z])($whole)s?([^a-z]|$)"
pattern="$pattern|($(cap "$whole"))s?([^a-z]|$)"
pattern="$pattern|(^|[^A-Za-z])($(upper "$whole"))S?([^A-Za-z]|$)"

tag="check-spelling"
[ "${1:-}" = "--staged" ] && tag="pre-commit"

printf '' | grep -qE "$pattern"
if [ $? -gt 1 ]; then
    echo "[$tag] BLOCKED: the spelling pattern does not compile." >&2
    exit 1
fi

# Allowed, scrubbed from the scanned lines (each is file:line:text):
# Blizzard globals, game item names, the one American word that carries a
# British substring, and the search alias on the Dark Theme page that lets a
# player type the British word, scoped to that file alone.
scrub() {
    sed -E 's/GameFontNormalLeftGrey|Draught of|[Gg]reyhound|GREYHOUND/ALLOWED/g; /^GUI\/GUIMain\/GUI-MainFrame\.lua:/ s/"colour"|"maximised"/ALLOWED/g'
}

# Third-party trees are not ours to spell; everything else tracked and
# textual is scanned (git grep -I and the diff skip binaries on their own).
paths=(. ':!Libs' ':!References' ':!dev/scripts/check-spelling.sh')

if ! scan="$(mktemp)"; then
    echo "[$tag] BLOCKED: could not create a scratch file." >&2
    exit 1
fi
trap 'rm -f "$scan"' EXIT

if [ "$tag" = "pre-commit" ]; then
    # file:line of each added line, rebuilt from the hunk headers so the
    # report points at the staged file. A "+++ " line is a header only
    # between a "diff --git" line and its first hunk: an added source line
    # that itself begins with ++ renders as "+++ " too and stays content.
    git diff -U0 --no-color --src-prefix=a/ --dst-prefix=b/ --cached -- "${paths[@]}" \
        | awk '
            /^diff --git / { header = 1; next }
            header && /^\+\+\+ / { file = substr($0, 7); header = 0; next }
            /^@@/ { header = 0; split($3, a, ","); line = substr(a[1], 2) + 0; next }
            /^\+/ { print file ":" line ":" substr($0, 2); line++; next }
            /^-/ { next }
            /^ / { line++ }
        ' > "$scan"
    status=("${PIPESTATUS[@]}")
    if [ "${status[0]}" -ne 0 ] || [ "${status[1]}" -ne 0 ]; then
        echo "[$tag] BLOCKED: could not read the staged diff." >&2
        exit 1
    fi
else
    git grep -nIE "$pattern" -- "${paths[@]}" > "$scan"
    st=$?
    if [ "$st" -gt 1 ]; then
        echo "[$tag] BLOCKED: git grep failed (exit $st)." >&2
        exit 1
    fi
fi

# The scrub and the grep are checked separately: under pipefail a failed
# sed with no output would hide behind grep's "no match" exit 1.
if ! scrubbed="$(scrub < "$scan")"; then
    echo "[$tag] BLOCKED: the allow-list scrub failed." >&2
    exit 1
fi
# grep: 0 hits, 1 none, anything else a failure that must not read as clean.
hits="$(printf '%s\n' "$scrubbed" | grep -E "$pattern")"
st=$?
if [ "$st" -gt 1 ]; then
    echo "[$tag] BLOCKED: the spelling scan failed (exit $st)." >&2
    exit 1
fi
[ "$st" -eq 1 ] && exit 0

echo "[$tag] BLOCKED: British spelling; the project writes American English (dev/README.md, Spelling):" >&2
printf '%s\n' "$hits" | sed -n '1,20p' >&2
n="$(printf '%s\n' "$hits" | wc -l)"
[ "$n" -gt 20 ] && echo "[$tag] ... and $((n - 20)) more" >&2
exit 1

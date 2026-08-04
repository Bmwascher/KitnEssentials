param(
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [Parameter(Mandatory = $true)][string]$BaseRef,
    [switch]$Verify,
    [string]$Out
)

# Value-preserving substitution check + ledger emitter for the GUI row-height
# pass. Both outputs come from the SAME parsed diff, so the proof and the
# report cannot disagree with each other.
#
# WHAT THIS PROVES, exactly: within the two pathspecs below, every changed line
# differs from its predecessor only by a bare number becoming a theme constant
# of equal value, in Lua CODE rather than inside a string or comment. If that
# holds for every line, no page can move.
#
# WHAT IT DOES NOT PROVE, and never did: that the plan was followed. It accepts
# any rowHeight* constant at any site, so a swap the plan explicitly forbade -
# the excluded DamageMeter 80s, say - passes here because it genuinely does not
# move a pixel. Plan conformance is a separate question, answered by reading the
# diff against the plan. Do not read a green run as "the plan was obeyed".
#
# ONE STANDING ASSUMPTION, stated rather than checked: that `Theme`, `T` and
# `KE.Theme` all resolve to the theme table at the site where they appear. This
# script matches the NAME, not the binding, so an undefined or shadowed alias
# would read nil and the "no page can move" claim would not hold for that line.
# The backing gate is luacheck, which is required to end 0/0 and reports an
# undefined global read - that is exactly how the DungeonTimersDungeon.lua case
# was caught, where no alias is in scope and `KE.Theme` is required. A green run
# here plus a green luacheck covers it; this script alone does not.
# (All three limits named by review, 2026-08-03.)

$ErrorActionPreference = 'Stop'

# Sidebar section order, from GUI/GUIMain/GUI-MainFrame.lua. The ledger is
# sorted this way because verification happens by clicking through the config
# window, not by browsing the filesystem.
$SectionOrder = @(
    'GUICombat', 'GUIClassUtilities', 'GUIUtilities', 'GUIHealer',
    'GUIQoL', 'GUISkinning', 'GUIDungeons', 'GUIDungeonTimers'
)

function Get-ThemeValues($repo) {
    $themePath = Join-Path $repo 'Core/AddonTheme.lua'
    if (-not (Test-Path $themePath)) { throw "theme file not found: $themePath" }
    $values = @{}
    foreach ($line in Get-Content -LiteralPath $themePath) {
        if ($line -match '^\s*(rowHeight\w*)\s*=\s*(\d+)\s*,') {
            $values[$Matches[1]] = [int]$Matches[2]
        }
    }
    if ($values.Count -eq 0) { throw 'no rowHeight* constants parsed from AddonTheme.lua' }
    return $values
}

# Which characters of each line of a FILE are Lua code, as opposed to string or
# comment. Returns a per-line array of bool arrays, indexed from 1.
#
# Needed because a substitution inside a string changes displayed text while
# rebuilding to a line identical to the original: "foo 50 bar" becoming
# "foo Theme.rowHeightNote bar" rebuilds to "foo 50 bar" and would otherwise
# pass while the user reads different words on screen.
#
# This scans the WHOLE FILE rather than one line, because lexical state carries
# across lines and a diff hunk does not show you where you are. That is not
# hypothetical here: GUI/GUITabs/GUICombat/GUI-Cursor.lua:456-475 is a multiline
# --[[ ]]-- block containing real CreateRow/AddRow calls with theme constants in
# them. A line-level scanner marks those as live code, and any grammar-based
# check would match them too. Both limits named by review, 2026-08-03.
#
# Handles: quoted strings with backslash escapes, long brackets at any equals
# level ([[ ]], [=[ ]=], [==[ ]==] ...), line comments, and long comments.
function Get-FileCodeMask([string]$path) {
    $masks = @{}
    if (-not (Test-Path -LiteralPath $path)) { return $masks }
    $lines = @(Get-Content -LiteralPath $path)

    $longLevel = -1        # -1 = not inside a long bracket; else its equals count
    for ($ln = 0; $ln -lt $lines.Count; $ln++) {
        $line = $lines[$ln]
        $mask = New-Object 'bool[]' $line.Length
        $i = 0

        while ($i -lt $line.Length) {
            # Inside a multi-line long bracket: hunt only for its exact closer.
            if ($longLevel -ge 0) {
                $closer = ']' + ('=' * $longLevel) + ']'
                $at = $line.IndexOf($closer, $i)
                if ($at -lt 0) { $i = $line.Length; break }
                $i = $at + $closer.Length
                $longLevel = -1
                continue
            }

            $c = $line[$i]

            # A long bracket, possibly opening a comment (--[[) or a string.
            if ($c -eq '[' -or ($c -eq '-' -and $i + 1 -lt $line.Length -and $line[$i + 1] -eq '-')) {
                $probe = $i
                if ($c -eq '-') { $probe = $i + 2 }
                if ($probe -lt $line.Length -and $line[$probe] -eq '[') {
                    $eq = 0
                    $j = $probe + 1
                    while ($j -lt $line.Length -and $line[$j] -eq '=') { $eq++; $j++ }
                    if ($j -lt $line.Length -and $line[$j] -eq '[') {
                        $longLevel = $eq
                        $i = $j + 1
                        continue
                    }
                }
                # A '--' that did not open a long comment runs to end of line.
                if ($c -eq '-') { break }
            }

            if ($c -eq "'" -or $c -eq '"') {
                $quote = $c
                $i++
                while ($i -lt $line.Length) {
                    if ($line[$i] -eq '\') { $i += 2; continue }
                    if ($line[$i] -eq $quote) { $i++; break }
                    $i++
                }
                continue
            }

            $mask[$i] = $true
            $i++
        }

        $masks[$ln + 1] = $mask
    }
    return $masks
}

# One changed line pair, reduced to what actually differs.
#
# $mask is the code mask for this added line, from the file's own scan. A null
# mask means the line could not be located in the working tree, which is treated
# as NOT code - unlocatable is never assumed safe.
function Test-LinePreservesValue($removed, $added, $themeValues, $mask) {
    # Normalise: strip the leading +/- and collapse nothing else. Whitespace
    # differences are NOT tolerated - a reflowed line is not a swap.
    $r = $removed.Substring(1)
    $a = $added.Substring(1)

    # Rebuild the added line by turning each theme reference back into the
    # number it stands for, then demand it match the removed line exactly.
    #
    # The table path is WHITELISTED, and both halves of that matter.
    # KE.Theme.rowHeight must be consumed WHOLE: matching only the
    # "Theme.rowHeight" tail would rebuild it as "KE.40" and reject a
    # correct Task 3 edit. And an unrelated "Bogus.rowHeightNote" must NOT
    # be rebuilt: leaving it alone is what makes the rebuilt line differ
    # from the removed line, so it lands as an offender instead of passing
    # on the strength of its suffix. Longest alternative first - the regex
    # engine takes the first that matches, so KE\.Theme must precede Theme.
    $pattern = '(?<![\w.])(?:KE\.Theme|Theme|T)\.(rowHeight\w*)\b'

    # Every theme reference must sit in code. One inside a string or comment is
    # rejected outright rather than rebuilt, so it cannot reconstruct its way to
    # a false pass.
    $matches = [regex]::Matches($a, $pattern)
    if ($matches.Count -eq 0) { return $false }   # nothing swapped is not a swap
    if ($null -eq $mask) { return $false }
    foreach ($m in $matches) {
        if ($m.Index -ge $mask.Length -or -not $mask[$m.Index]) { return $false }
    }

    $rebuilt = [regex]::Replace($a, $pattern, {
        param($m)
        $name = $m.Groups[1].Value
        if (-not $themeValues.ContainsKey($name)) { return '<<UNKNOWN>>' }
        return [string]$themeValues[$name]
    })
    return ($rebuilt -ceq $r)
}

# Offenders carry their file, not just a message. The ledger has to LIST the
# files that failed the value-preserving check - dropping them would produce a
# ledger that reads as complete while silently omitting the pages most likely
# to have moved.
function Add-Offender($sink, $forFile, $message) {
    [void]$sink.Add([pscustomobject]@{ File = $forFile; Message = "$forFile : $message" })
}

function Flush-Leftovers($queue, $forFile, $sink) {
    foreach ($leftover in $queue) {
        Add-Offender $sink $forFile "removed a line with no added counterpart: $($leftover.Substring(1).Trim())"
    }
    $queue.Clear()
}

Push-Location $RepoRoot
try {
    # Base vs WORKING TREE, deliberately. Not "$BaseRef...HEAD".
    #
    # A three-dot diff compares commits and cannot see uncommitted work, and
    # four of this plan's five checks run BEFORE their task commits. The decoy
    # in Task 1 Step 4 is the clearest case: it is a working-tree edit, so a
    # three-dot diff would return nothing and the tool would exit 0 - the one
    # step whose entire purpose is to prove the checker can go red would be
    # unable to. This form sees committed and uncommitted changes alike, so
    # every step measures what the engineer is actually looking at.
    $diff = & git diff --unified=0 "$BaseRef" -- 'GUI/GUITabs' 'Core/AddonTheme.lua'
    if ($LASTEXITCODE -ne 0) { throw "git diff failed against $BaseRef" }
} finally {
    Pop-Location
}

$themeValues = Get-ThemeValues $RepoRoot
$file = $null
$removedQueue = New-Object System.Collections.ArrayList
$offenders = New-Object System.Collections.ArrayList
$entries = New-Object System.Collections.ArrayList
$themeAdditions = 0
$fileMasks = @{}    # repo-relative path -> line number -> per-char code mask
$newLine = 0        # new-side line number of the next '+' line in this hunk

# Header lines are recognized by POSITION IN THE DIFF, not by how they look.
#
# Matching on content alone cannot work: a deleted Lua comment reading
# "-- a/foo" arrives as "--- a/foo" and is indistinguishable from a real
# "--- a/<path>" header, so a content filter silently discards a real deletion.
# Git only emits '---' and '+++' inside a file's header block, between
# 'diff --git' and that file's first '@@', so tracking that block settles it.
# Named by review 2026-08-03, along with the '+++ /dev/null' twin the old
# content filter also missed.
$inHeader = $false

foreach ($line in $diff) {
    if ($line -like 'diff --git*') {
        if ($file) { Flush-Leftovers $removedQueue $file $offenders }
        $inHeader = $true
        $file = $null
        continue
    }

    if ($inHeader) {
        if ($line -match '^\+\+\+ b/(.+)$') { $file = $Matches[1]; continue }
        if ($line -eq '+++ /dev/null') { continue }   # deleted file; $file stays null
        if ($line -like '--- *') { continue }
        if ($line -like '@@*') {
            $inHeader = $false
            # fall through to the hunk handling below
        } else {
            continue   # index, mode, similarity, rename - all header noise
        }
    }

    # A hunk boundary ends pairing just as a file boundary does. Under
    # --unified=0 each hunk emits its own '-' lines then its own '+' lines, so
    # a queue carried across '@@' can pair a deletion in one hunk with an
    # addition hundreds of lines away in the next - two unrelated edits
    # cancelling out into a false pass.
    if ($line -like '@@*') {
        if ($file) { Flush-Leftovers $removedQueue $file $offenders }
        # Capture the NEW-side start line so each '+' line can be located in the
        # working-tree file and asked whether it is code. Format: @@ -a,b +c,d @@
        if ($line -match '^@@ -\d+(?:,\d+)? \+(\d+)') { $newLine = [int]$Matches[1] } else { $newLine = 0 }
        continue
    }

    if (-not $file) {
        # Content outside any recognized file - a deleted file's body, or a
        # parse this script does not model. Never silently skipped.
        if ($line.StartsWith('-') -or $line.StartsWith('+')) {
            Add-Offender $offenders '<unattributed>' "changed line outside a recognized file header: $($line.Trim())"
        }
        continue
    }

    if ($line.StartsWith('-')) { [void]$removedQueue.Add($line); continue }
    if (-not $line.StartsWith('+')) { continue }

    # This '+' line's number on the new side. Advanced for EVERY added line,
    # including the exempted theme one, or the count would drift out of step
    # with the file and later masks would be read off the wrong lines.
    $thisLine = $newLine
    $newLine++

    # AddonTheme.lua is where the new constant is DEFINED, so it legitimately
    # adds ONE line with no removed twin. Exempt exactly that line and nothing
    # else: an exemption scoped to the whole FILE would wave through any other
    # theme edit that rode along in the same branch, which is the opposite of
    # what this tool claims to prove.
    if ($file -eq 'Core/AddonTheme.lua') {
        $added = $line.Substring(1)
        # Anchored through end-of-line, allowing only a trailing comment. An
        # unanchored match would accept "rowHeightNote = 50, otherField = 99,"
        # as the expected line and trust a second theme edit riding on it.
        if ($themeAdditions -eq 0 -and $added -match '^\s*rowHeightNote\s*=\s*50\s*,(?:\s*--.*)?\s*$') {
            $themeAdditions++
            [void]$entries.Add([pscustomobject]@{ File = $file; Section = 'theme'; Detail = $added.Trim() })
        } else {
            Add-Offender $offenders $file "unexpected theme edit: $($added.Trim())"
        }
        continue
    }

    if ($removedQueue.Count -eq 0) {
        Add-Offender $offenders $file "added a line with no removed counterpart: $($line.Substring(1).Trim())"
        continue
    }
    $removed = $removedQueue[0]
    $removedQueue.RemoveAt(0)

    if (-not $fileMasks.ContainsKey($file)) {
        $fileMasks[$file] = Get-FileCodeMask (Join-Path $RepoRoot $file)
    }
    $mask = $fileMasks[$file][$thisLine]

    if (-not (Test-LinePreservesValue $removed $line $themeValues $mask)) {
        Add-Offender $offenders $file "not a value-preserving swap`n    was: $($removed.Substring(1).Trim())`n    now: $($line.Substring(1).Trim())"
        continue
    }

    $section = 'other'
    foreach ($s in $SectionOrder) { if ($file -like "*/$s/*") { $section = $s; break } }
    [void]$entries.Add([pscustomobject]@{ File = $file; Section = $section; Detail = $line.Substring(1).Trim() })
}

if ($file) { Flush-Leftovers $removedQueue $file $offenders }

if ($Verify) {
    if ($offenders.Count -gt 0) {
        Write-Output "NOT VALUE-PRESERVING - $($offenders.Count) line(s):"
        $offenders | ForEach-Object { Write-Output "  $($_.Message)" }
        exit 1
    }
    Write-Output "value-preserving: $($entries.Count) changed line(s), 0 offenders"
    exit 0
}

if (-not $Out) { throw 'pass -Verify or -Out' }

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('# GUI row constants - change ledger')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("Generated from ``git diff $BaseRef`` (base vs working tree). Do not hand-edit.")
[void]$sb.AppendLine('')
[void]$sb.AppendLine('Every change below is a value-preserving substitution, checked by')
[void]$sb.AppendLine('``gui-row-ledger.ps1 -Verify``. **Nothing should look different.** Open each')
[void]$sb.AppendLine('page and confirm the rows sit exactly where they did. Anything that moved')
[void]$sb.AppendLine('is a defect - note the page and stop.')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('Sections are in sidebar order, so this list can be walked top to bottom.')
[void]$sb.AppendLine('')

foreach ($s in @('theme') + $SectionOrder + @('other')) {
    $inSection = $entries | Where-Object { $_.Section -eq $s }
    if (-not $inSection) { continue }
    [void]$sb.AppendLine("## $s")
    [void]$sb.AppendLine('')
    foreach ($g in ($inSection | Group-Object File | Sort-Object Name)) {
        $short = Split-Path $g.Name -Leaf
        [void]$sb.AppendLine("- [ ] **$short** - $($g.Count) line(s)")
    }
    [void]$sb.AppendLine('')
}

# Files whose changes were NOT value-preserving get their own section, emitted
# from the same parse. These are the only pages where something could
# legitimately look different, so they must never be left for a human to
# remember to append.
if ($offenders.Count -gt 0) {
    [void]$sb.AppendLine('## Pages that changed shape, not just naming')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('These did NOT pass the value-preserving check. That is expected only for')
    [void]$sb.AppendLine('the card-offset conversions. Look at these hardest - unlike everything')
    [void]$sb.AppendLine('above, nothing guarantees they render identically.')
    [void]$sb.AppendLine('')
    foreach ($g in ($offenders | Group-Object File | Sort-Object Name)) {
        $short = Split-Path $g.Name -Leaf
        [void]$sb.AppendLine("- [ ] **$short** - $($g.Count) line(s)")
    }
    [void]$sb.AppendLine('')
}

$fileCount = (($entries + $offenders) | Group-Object File).Count
[void]$sb.AppendLine("Files touched: $fileCount")
[void]$sb.AppendLine('')

$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($Out, $sb.ToString(), $enc)
Write-Output "ledger written: $Out ($($entries.Count) preserving, $($offenders.Count) shape-changing, $fileCount files)"

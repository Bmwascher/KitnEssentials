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
# The claim being proved: every changed line in GUI/GUITabs differs from its
# predecessor ONLY by a bare number being replaced with a theme constant whose
# value equals that number. If that holds for every line, no page can move.

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

# One changed line pair, reduced to what actually differs.
function Test-LinePreservesValue($removed, $added, $themeValues) {
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

foreach ($line in $diff) {
    if ($line -match '^\+\+\+ b/(.+)$') {
        if ($file) { Flush-Leftovers $removedQueue $file $offenders }
        $file = $Matches[1]
        continue
    }
    # A hunk boundary ends pairing just as a file boundary does. Under
    # --unified=0 each hunk emits its own '-' lines then its own '+' lines, so
    # a queue carried across '@@' can pair a deletion in one hunk with an
    # addition hundreds of lines away in the next - two unrelated edits
    # cancelling out into a false pass.
    if ($line -like '@@*') {
        if ($file) { Flush-Leftovers $removedQueue $file $offenders }
        continue
    }
    # Match the two real '---' header forms, NOT a bare '---*'. A deleted Lua
    # comment starting at column 1 renders as "--- foo" and a wildcard filter
    # would swallow it instead of flushing it as an unpaired removal.
    if ($line -like '--- a/*' -or $line -eq '--- /dev/null' -or
        $line -like 'diff --git*' -or
        $line -like 'index *' -or $line -like 'new file*' -or $line -like 'deleted file*') {
        continue
    }
    if ($line.StartsWith('-')) { [void]$removedQueue.Add($line); continue }
    if (-not $line.StartsWith('+')) { continue }

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

    if (-not (Test-LinePreservesValue $removed $line $themeValues)) {
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

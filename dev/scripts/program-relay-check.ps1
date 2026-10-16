# program-relay-check.ps1 - check a phase report block before the master relays it.
#
#   pwsh dev/scripts/program-relay-check.ps1 -FeatureFolder <folder> [-Path <block file>]
#   <block> | pwsh dev/scripts/program-relay-check.ps1 -FeatureFolder <folder>
#
# Saves the whole block (one surrounding ```text fence removed) as report.md
# in the feature folder, then checks the block's `### For Brandon` section,
# the only part the master relays (phased-program skill, step 5), against
# the rest of the block:
#   - a line naming an UNVERIFIED claim, a riding Minor, or a gate that is
#     waived, degraded, NOT-RUN or RAN-FIX-OPEN must appear in `Not settled`,
#     word for word (the clause holding the keyword, case and spacing aside);
#   - a delegated decision (a `delegator for Brandon` line, an item
#     under `### For Brandon to confirm or reverse`, an item of a
#     `### Decision summary` he did not approve) must be covered by
#     `Decided for you`: quoted there word for word, its delegation record
#     aside (case and spacing aside).
# PASS prints the relay, nothing else on stdout, exit 0: the section's words
# unchanged, rendered as markdown (the status line as a `###` heading, each
# labeled line as a bullet with its label in bold, sub-bullets nested), then
# `📄 Full report:` and the report.md path. -Raw prints the lines exactly.
# FAIL prints what is missing on stderr and not the section, exit 1: the
# section goes back to the phase, it is never rewritten by the master.
# Matching is by keyword and text, so a FAIL can be a false alarm; read the
# listed line before sending the section back.
# When the session is a registered master, the result is logged as a
# `relay PASS|FAIL <folder>` event for the close-out tally (program-master.ps1).

param(
    [Parameter(Mandatory = $true)][string]$FeatureFolder,
    [string]$Path,
    [switch]$Raw
)

$ErrorActionPreference = 'Stop'
# The section's status and label marks are emoji; the console code page would turn them into '?'.
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

if (-not (Test-Path -LiteralPath $FeatureFolder -PathType Container)) {
    [Console]::Error.WriteLine("RELAY CHECK ERROR: no feature folder at $FeatureFolder")
    exit 2
}
$text = if ($Path) { [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).Path) } else { [Console]::In.ReadToEnd() }
$lines = @($text -split "`r?`n")

# Drop one surrounding fence and the blank lines outside it.
$first = 0; $last = $lines.Count - 1
while ($first -le $last -and -not $lines[$first].Trim()) { $first++ }
while ($last -ge $first -and -not $lines[$last].Trim()) { $last-- }
if ($first -lt $last -and $lines[$first] -match '^\s*```' -and $lines[$last] -match '^\s*```\s*$') { $first++; $last-- }
if ($first -gt $last) { [Console]::Error.WriteLine('RELAY CHECK ERROR: the report block is empty'); exit 2 }
$lines = @($lines[$first..$last])

$report = Join-Path $FeatureFolder 'report.md'
Set-Content -LiteralPath $report -Value $lines -Encoding utf8

function Get-Norm([string]$s) {
    return (($s -replace '[`*_]', '') -replace '\s+', ' ').Trim().ToLowerInvariant()
}

# Split the block into the For Brandon section and the rest, and the rest
# into its `### ` subsections.
$fbStart = -1; $fbEnd = $lines.Count
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($fbStart -lt 0) {
        if ($lines[$i] -match '^###\s+For Brandon\s*$') { $fbStart = $i }
    } elseif ($lines[$i] -match '^(#{1,6}\s|\*\*)') { $fbEnd = $i; break }
}

$folderName = Split-Path (Resolve-Path -LiteralPath $FeatureFolder).Path -Leaf
function Write-Result([string]$verdict) {
    $pm = Join-Path $PSScriptRoot 'program-master.ps1'
    try { & $pm -LogEvent "relay $verdict $folderName" } catch { }
}

if ($fbStart -lt 0) {
    [Console]::Error.WriteLine("RELAY CHECK FAIL: the block has no '### For Brandon' section. Send it back to the phase. Saved: $report")
    Write-Result 'FAIL'
    exit 1
}

$body = @()
if ($fbEnd -gt $fbStart + 1) { $body = @($lines[($fbStart + 1)..($fbEnd - 1)]) }
$sectionLines = $body
$lastBody = $body.Count - 1
while ($lastBody -ge 0 -and -not $body[$lastBody].Trim()) { $lastBody-- }
$body = if ($lastBody -ge 0) { @($body[0..$lastBody]) } else { @() }

# Fields: `<emoji> Label: value`, with the unlabeled lines after it (sub-bullets)
# as its continuations. The status line comes before any label and is not a field.
$labels = @("You'll see", 'Needs you', 'Not settled', 'Decided for you', 'Reviews', 'Next')
$fields = @{}; $fieldLines = @{}; $current = $null
$rendered = @()
foreach ($l in $body) {
    $hit = $null
    # A sub-bullet is a continuation even when it opens with a label word.
    foreach ($lab in $(if ($l -match '^\s*[-*+]\s') { @() } else { $labels })) {
        $pattern = '^\s*(?<head>[^\p{L}\p{N}\s]*\s*' + ([regex]::Escape($lab) -replace "'", ".") + '\s*:)\s*(?<val>.*)$'
        if ($l -match $pattern) { $hit = $lab; break }
    }
    if ($hit) {
        $current = $hit; $fields[$hit] = $Matches['val']; $fieldLines[$hit] = @()
        if ($Matches['val'].Trim()) { $fieldLines[$hit] += $Matches['val'] }
        $rendered += ('- **{0}** {1}' -f $Matches['head'].Trim(), $Matches['val']).TrimEnd()
    } elseif (-not $l.Trim()) {
        continue
    } elseif ($current) {
        $fields[$current] += ' ' + $l.Trim(); $fieldLines[$current] += $l.Trim()
        $rendered += if ($l -match '^\s*[-*+]\s+(.*)$') { "  - $($Matches[1])" } else { "  $($l.Trim())" }
    } elseif ($rendered.Count -eq 0) {
        $rendered += "### $($l.Trim())"
    } else {
        $rendered += $l.Trim()
    }
}

$problems = @()
foreach ($lab in $labels) { if (-not $fields.ContainsKey($lab)) { $problems += "the For Brandon section has no '$($lab):' line" } }

$restLines = @()
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($i -ge $fbStart -and $i -lt $fbEnd) { continue }
    if ($lines[$i] -match '^##\s+Phase .* report') { continue }
    $restLines += [pscustomobject]@{ text = $lines[$i]; section = '' }
}
$section = ''
foreach ($r in $restLines) {
    if ($r.text -match '^###\s+(.+?)\s*$') { $section = $Matches[1] }
    $r.section = $section
}

$isNone = '^\s*(none|nothing|n/a|-)?\s*\.?\s*$'
function Strip-Bullet([string]$s) { return ($s -replace '^\s*(#+|[-*+]|\d+[.)])\s+', '').Trim() }

# Lines whose subject belongs in `Not settled`.
$unsettledRules = @(
    @{ kind = 'UNVERIFIED claim'; re = '(?i)\bunverified\b' },
    @{ kind = 'riding Minor'; re = '(?i)\bminors?\b.*\b(rides?|riding|rode)\b|\b(rides?|riding|rode)\b.*\bminors?\b' },
    @{ kind = 'waived or degraded gate'; re = '(?i)\bwaived\b|\bdegraded\b|\bNOT-RUN\b|\bRAN-FIX-OPEN\b' }
)
$notSettled = Get-Norm ([string]$fields['Not settled'])
foreach ($r in $restLines) {
    foreach ($rule in $unsettledRules) {
        if ($r.text -notmatch $rule.re) { continue }
        $item = Strip-Bullet $r.text
        # The clause holding the keyword is what must be quoted.
        $clauses = @($item -split '(?<=[.;])\s+' | Where-Object { $_ -match $rule.re })
        if (-not $clauses) { $clauses = @($item) }
        foreach ($c in $clauses) {
            if (-not $notSettled.Contains((Get-Norm $c).TrimEnd('.', ';'))) {
                $problems += "Not settled leaves out this $($rule.kind): $($r.text.Trim())"
            }
        }
    }
}

# Delegated decisions.
$decisions = @()
$approved = @($restLines | Where-Object { $_.section -eq 'Decision summary' -and $_.text -match '(?i)^\s*approved by Brandon\s*\.?\s*$' }).Count -gt 0
foreach ($r in $restLines) {
    if ($r.text -match '^#' -or -not $r.text.Trim()) { continue }
    $item = Strip-Bullet $r.text
    if ($item -match $isNone) { continue }
    if ($r.section -eq 'For Brandon to confirm or reverse') { $decisions += $item }
    elseif ($r.section -eq 'Decision summary' -and -not $approved) { $decisions += $item }
    elseif ($r.text -match '(?i)delegator for Brandon') { $decisions += $item }
}
$decidedNorm = Get-Norm ([string]$fields['Decided for you'])
# The decision itself, without its delegation record: the register's
# `<date>, delegator for Brandon, <how>, "<words>": <decision>` prefix, or a
# trailing `(delegator for Brandon, ...)`. Word overlap cannot tell a choice
# from its opposite, so the remaining text must be quoted.
function Get-DecisionCore([string]$d) {
    if ($d -match '(?i)delegator for Brandon.*?"[^"]*"\s*:\s*(.+)$') { $d = $Matches[1] }
    return ((Get-Norm ($d -replace '(?i)\s*\(delegator for Brandon[^)]*\)', '')).TrimEnd('.', ';', ' '))
}
foreach ($d in @($decisions | Select-Object -Unique)) {
    $core = Get-DecisionCore $d
    if ($core -and -not $decidedNorm.Contains($core)) { $problems += "Decided for you does not quote this decision: $d" }
}

if ($problems.Count) {
    [Console]::Error.WriteLine("RELAY CHECK FAIL: $($problems.Count) problem(s). Send the For Brandon section back to the phase; do not relay or rewrite it.")
    foreach ($p in $problems) { [Console]::Error.WriteLine("  - $p") }
    [Console]::Error.WriteLine("Saved: $report")
    Write-Result 'FAIL'
    exit 1
}

if ($Raw) {
    $sectionLines | Write-Output
} else {
    $reportPath = (Resolve-Path -LiteralPath $report).Path
    $shown = if ($reportPath -match '[\\/](dev[\\/]docs[\\/].*)$') { $Matches[1] -replace '\\', '/' } else { $reportPath }
    # A blank line between bullets would split the list; one before the path ends it.
    $rendered | Write-Output
    Write-Output ''
    Write-Output "📄 Full report: ``$shown``"
}
Write-Result 'PASS'
exit 0

# program-tally.ps1 - the close-out tally of a phased program.
#
#   pwsh dev/scripts/program-tally.ps1 -Program <control document> [-Smoke <smoke file>]
#
# Counts from the program's own records, never from transcripts: the control
# document, its smoke file (the control document's `Shared smoke file` line
# unless -Smoke names one) and its events log (<stem>-events.log, written by
# program-master.ps1 and program-relay-check.ps1). Prints a markdown table
# for the control document's Close-out tally section, then one line per
# smoke FAIL. A count is only as good as the recording convention behind it,
# which templates/program.md (Close-out tally) states; a convention nobody
# followed prints 0, and the Basis column says what was matched.

param(
    [Parameter(Mandatory = $true)][string]$Program,
    [string]$Smoke
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$programPath = (Resolve-Path -LiteralPath $Program).Path
$doc = @(Get-Content -LiteralPath $programPath)

if (-not $Smoke) {
    foreach ($l in $doc) {
        if ($l -match 'Shared smoke file\**\s*:\s*`([^`]+)`') { $Smoke = $Matches[1]; break }
    }
}
$smokeLines = @()
$smokeNote = ''
if ($Smoke) {
    $smokePath = if ([System.IO.Path]::IsPathRooted($Smoke)) { $Smoke } else { Join-Path $root $Smoke }
    # This checkout may not hold dev/docs (a worktree); the smoke file sits beside its control document.
    if (-not (Test-Path -LiteralPath $smokePath)) { $smokePath = Join-Path (Split-Path $programPath -Parent) (Split-Path $Smoke -Leaf) }
    if (Test-Path -LiteralPath $smokePath) { $smokeLines = @(Get-Content -LiteralPath $smokePath) }
    else { $smokeNote = " (smoke file not found: $Smoke)" }
} else { $smokeNote = ' (no smoke file named)' }

$stem = [System.IO.Path]::GetFileNameWithoutExtension($programPath)
$eventsPath = Join-Path (Split-Path $programPath -Parent) "$stem-events.log"
$events = if (Test-Path -LiteralPath $eventsPath) { @(Get-Content -LiteralPath $eventsPath) } else { @() }
$eventsNote = if ($events.Count) { '' } else { ' (no events log)' }

$label = '\bP\d+[a-z]?-Q\d+[a-z]?\b'
$all = $doc + $smokeLines

$asked = @($all | ForEach-Object { [regex]::Matches($_, $label) | ForEach-Object { $_.Value } } | Sort-Object -Unique)
$reasked = @($all | ForEach-Object { [regex]::Matches($_, "(?i)\breplaces\s+($label)") | ForEach-Object { $_.Groups[1].Value } } | Sort-Object -Unique)
$premises = @($all | Where-Object { $_ -match '(?i)\bpremise corrected\b' }).Count

# Smoke FAILs: each Result line holding FAIL, under its step heading.
$hopRe = '(?i)\b(sent|routed|relayed|forwarded)\s+(back\s+)?to\b'
$fails = @(); $step = '?'
foreach ($l in $smokeLines) {
    if ($l -match '^###\s+(\S+)') { $step = $Matches[1] }
    if ($l -match '^\*\*Result:\*\*' -and $l -cmatch '\bFAIL\b') {
        $fails += [pscustomobject]@{
            step = $step
            hops = [regex]::Matches($l, $hopRe).Count
            viaMaster = $l -match '(?i)\bto (the )?master\b'
        }
    }
}
$hops = ($fails | Measure-Object -Property hops -Sum).Sum
if (-not $hops) { $hops = 0 }
$unrecorded = @($fails | Where-Object { $_.hops -eq 0 }).Count
$viaMaster = @($fails | Where-Object { $_.viaMaster }).Count

$relays = @($events | Where-Object { $_ -match "`trelay (PASS|FAIL)\b" })
$relayFails = @($relays | Where-Object { $_ -match "`trelay FAIL\b" }).Count
$compactions = @($events | Where-Object { $_ -match "`tcompact\s*$" }).Count

Write-Output "| Count | Value | Basis |"
Write-Output "|---|---|---|"
Write-Output "| Questions asked | $($asked.Count) | distinct P<n>-Q<m> labels in the control document and smoke file$smokeNote |"
Write-Output "| Premises corrected | $premises | lines saying ``premise corrected`` |"
Write-Output "| Re-asks | $($reasked.Count) | distinct labels named by ``replaces P<n>-Q<m>`` |"
Write-Output "| Smoke FAILs | $($fails.Count) | Result lines holding FAIL$smokeNote |"
Write-Output "| FAIL relay hops | $hops ($viaMaster FAILs via the master, $unrecorded with no hop recorded) | ``sent/routed/relayed/forwarded to`` on those Result lines |"
Write-Output "| Incomplete relays | $relayFails of $($relays.Count) checked | ``relay FAIL`` events$eventsNote |"
Write-Output "| Compaction recoveries | $compactions | ``compact`` events$eventsNote |"
if ($fails.Count) {
    Write-Output ''
    foreach ($f in $fails) {
        $via = if ($f.viaMaster) { ', via the master' } else { '' }
        Write-Output ("- smoke {0}: FAIL, {1} hop(s){2}" -f $f.step, $f.hops, $via)
    }
}
exit 0

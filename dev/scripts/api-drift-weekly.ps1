# api-drift-weekly.ps1 - Task Scheduler wrapper for the weekly tool checks.
#
# 1. update-wowlua-ls.ps1 keeps the standalone wowlua-ls checker current; an
#    update re-runs the checker, because a new release can raise warnings
#    the pre-push gate then blocks.
# 2. update-api-reference.lua runs the API drift watch; its one-shot report
#    is archived to dev/docs/api-drift-reports/<date>.txt (gitignored).
#
# Nothing pops up. When either step has something to say (an update, a
# finding, a failure) it is appended to "KitnDev weekly check <date>.txt" on
# the Desktop; a quiet week writes no file.
#
# Scheduled task (weekly, Tue 13:07 local, after US reset), headless so no
# console window flashes:
#   conhost.exe --headless "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File <this file>
#
#   -ReportOnly   pass --report-only to the drift script (no fetch, no state
#                 writes) and skip the wowlua-ls update
#   -TestReport   write a sample Desktop note and exit (wiring check)
#   -NoAutoTriage skip the headless analysis pass on findings
#
# On BREAKING-USED findings the report is piped into a headless Claude Code
# run (analysis-only: Read/Glob/Grep/Skill, no edits) that greps KE call
# sites and reads the API reference, so the note can say WHAT is affected
# instead of just "go triage". The note is always written on findings - the
# headless pass enriches it, never gates it. Code fixes stay manual via
# /api-drift (in-game probes and approval required).

param(
    [switch]$ReportOnly,
    [switch]$TestReport,
    [switch]$NoAutoTriage
)

$RepoRoot = Split-Path (Split-Path $PSScriptRoot)
$NoteFile = Join-Path ([Environment]::GetFolderPath('Desktop')) ("KitnDev weekly check {0}.txt" -f (Get-Date -Format 'yyyy-MM-dd'))

function Add-WeeklyNote($title, $body) {
    $entry = "== {0}  ({1}) ==`r`n{2}`r`n" -f $title, (Get-Date -Format 'HH:mm'), $body
    Add-Content -LiteralPath $NoteFile -Value $entry
}

if ($TestReport) {
    Add-WeeklyNote "Weekly check test" "Test note - wiring OK."
    exit 0
}

if (-not $ReportOnly) {
    $wowluaLine = [string](& (Join-Path $PSScriptRoot "update-wowlua-ls.ps1") 2>&1 | Select-Object -Last 1)
    $wowluaCode = $LASTEXITCODE
    if (-not $wowluaLine) { $wowluaLine = "[wowlua-ls] FAILED: the updater stopped without a status line" }
    if ($wowluaCode -eq 10) {
        $checkOut = & (Get-Process -Id $PID).Path -NoProfile -File (Join-Path $PSScriptRoot "wowlua-check.ps1") 2>&1 | ForEach-Object { "$_" }
        $body = switch ($LASTEXITCODE) {
            0 { "Checker re-run is clean on the checked-out branch." }
            1 { "Checker re-run found warnings - pushes block until they are fixed:`r`n" + ($checkOut -join "`r`n") }
            default { "Checker re-run could not complete - run pwsh dev\scripts\wowlua-check.ps1.`r`n" + ($checkOut -join "`r`n") }
        }
        Add-WeeklyNote ($wowluaLine -replace '^\[wowlua-ls\] UPDATED', 'wowlua-ls updated') $body
    } elseif ($wowluaCode -ne 0) {
        Add-WeeklyNote "wowlua-ls update FAILED" "$wowluaLine`r`nThe installed checker is unchanged; rerun pwsh dev\scripts\update-wowlua-ls.ps1."
    }
}

$Lua = "C:\Users\Brandon\Documents\KitnDev\tools\lua51\bin\lua.exe"
if (-not (Test-Path $Lua)) {
    $cmd = Get-Command lua -ErrorAction SilentlyContinue
    if ($cmd) { $Lua = $cmd.Source }
}
if (-not (Test-Path $Lua)) {
    Add-WeeklyNote "API drift watch FAILED" "lua.exe not found (hererocks tree moved?) - run lua dev/scripts/update-api-reference.lua manually."
    exit 2
}

$ReportDir = Join-Path $RepoRoot "dev\docs\api-drift-reports"
New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
$Stamp = Get-Date -Format "yyyy-MM-dd_HHmm"
$ReportFile = Join-Path $ReportDir "$Stamp.txt"

Set-Location $RepoRoot
$scriptArgs = @("dev\scripts\update-api-reference.lua")
if ($ReportOnly) { $scriptArgs += "--report-only" }
$output = & $Lua @scriptArgs 2>&1 | ForEach-Object { $_.ToString() }
$code = $LASTEXITCODE
$output | Set-Content -Path $ReportFile

if ($code -eq 0) {
    exit 0  # clean run (or additions-only) - report archived, no note
}

# exit 1 with a report header = real BREAKING-USED findings; the run already
# advanced the baseline, so the archived report is the only copy - point at it
$breakLine = $output | Where-Object { $_ -match '^\[BREAKING-USED\] \((\d+)\)' } | Select-Object -First 1
if ($breakLine -and $breakLine -match '\((\d+)\)') {
    $n = $Matches[1]
    $summary = "Triage with /api-drift."
    $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $NoAutoTriage -and $claudeCmd) {
        $triageFile = Join-Path $ReportDir "$Stamp-autotriage.txt"
        $promptFile = Join-Path $ReportDir "$Stamp-autotriage-prompt.txt"
        $reportText = $output -join "`r`n"
        $prompt = @"
Headless ANALYSIS-ONLY triage of a WoW API drift report for KitnEssentials.
No user is available - never wait for input. You are in the KE repo root.
The drift script ALREADY ran and advanced its baseline - do NOT run
update-api-reference.lua again (the report below is the only copy of this
week's diff).

--- REPORT ---
$reportText
--- END REPORT ---

For each [BREAKING-USED] line: grep the symbol under Core/, Modules/, and
GUI/ to list every KE call site; read the symbol's entry under
.wow-api-reference/Interface/AddOns/Blizzard_APIDocumentationGenerated/ to
see exactly what changed (signature, SecretReturns flags, removal); assess
severity. For secret-flag changes consult the wow-midnight-api skill - do
not propose over-guarding. Make NO code edits and write NO files - output
your triage table (symbol | change | affected files | severity | proposed
fix) as text only.
End your reply with EXACTLY one line:
TRIAGE: <count> breakage(s) affect KE - <comma-separated modules>
or
TRIAGE: none affect KE at runtime - <one-line reason>
"@
        $prompt | Set-Content -Path $promptFile
        $errFile = Join-Path $ReportDir "$Stamp-autotriage-err.txt"
        # Bounded run: a hung headless session must not hold the note
        # hostage - kill after 20 min and fall back to the manual summary.
        # --tools restricts AVAILABILITY of built-ins (unlisted tools do
        # not exist for this agent, so ambient allow rules cannot widen
        # it); --strict-mcp-config with no --mcp-config loads zero MCP
        # servers; --allowedTools only pre-approves within that set. No
        # --bare: the triage needs the repo's wow-midnight-api skill.
        $proc = Start-Process -FilePath $claudeCmd.Source `
            -ArgumentList @("-p", "--strict-mcp-config", "--tools", "Skill,Read,Glob,Grep", "--allowedTools", "Skill,Read,Glob,Grep") `
            -WorkingDirectory $RepoRoot -NoNewWindow -PassThru `
            -RedirectStandardInput $promptFile `
            -RedirectStandardOutput $triageFile `
            -RedirectStandardError $errFile
        # Cache the handle NOW: without it, .ExitCode reads null after the
        # process exits (Start-Process quirk, probed 2026-07-12).
        $null = $proc.Handle
        $finished = $proc.WaitForExit(1200000)
        if ($finished) {
            # No-arg WaitForExit flushes process state; without it,
            # .ExitCode can read null after the timed overload.
            $proc.WaitForExit()
        }
        if (-not $finished) {
            try { $proc.Kill() } catch {}
        } elseif ($proc.ExitCode -eq 0) {
            # Exactly ONE strict verdict line, or the output is not trusted
            # (quoted/injected TRIAGE text must not replace the real result).
            $triageLines = @(Select-String -Path $triageFile -Pattern '^TRIAGE: (.+)$')
            if ($triageLines.Count -eq 1) {
                $verdict = $triageLines[0].Matches[0].Groups[1].Value.Trim()
                $relTriage = "dev\docs\api-drift-reports\$Stamp-autotriage.txt"
                Add-Content -Path $ReportFile -Value "`r`nAuto-triage: $verdict (table: $relTriage)"
                $summary = "$verdict.`r`nTriage table: $triageFile"
            }
        }
        # Timeout, nonzero exit, or no single verdict: manual summary.
    }
    Add-WeeklyNote "WoW API drift: $n change(s) hit KE" "$summary`r`nFull report: $ReportFile`r`n`r`n$($output -join "`r`n")"
} else {
    # exit != 0 with no report header = the script aborted (fetch failed,
    # damaged reference) - snapshots untouched, safe to rerun
    Add-WeeklyNote "API drift watch FAILED" "Script aborted (offline? diverged clone?). Details: $ReportFile"
}
exit $code

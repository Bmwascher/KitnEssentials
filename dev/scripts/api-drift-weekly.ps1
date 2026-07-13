# api-drift-weekly.ps1 - Task Scheduler wrapper for update-api-reference.lua.
#
# Runs the API drift watch, archives the one-shot report to
# dev/docs/api-drift-reports/<date>.txt (dev/docs is gitignored), and shows a
# Windows toast ONLY when something KE uses changed (or the script failed).
# A clean run is silent.
#
# Scheduled task (weekly, Tue 13:07 local, after US reset):
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File <this file>
# Written for Windows PowerShell 5.1 (what the task runs): no &&, no ternary,
# and ASCII ONLY - 5.1 reads BOM-less files as ANSI, so a UTF-8 em dash
# decodes into a smart quote that silently terminates strings.
#
#   -ReportOnly   pass --report-only to the script (no fetch, no state writes)
#   -TestNotify   fire a sample toast and exit (wiring check)
#   -NoAutoTriage skip the headless analysis pass on findings
#
# On BREAKING-USED findings the report is piped into a headless Claude Code
# run (analysis-only: Read/Glob/Grep/Skill, no edits) that greps KE call
# sites and reads the API reference, so the toast can say WHAT is affected
# instead of just "go triage". The toast always fires on findings - the
# headless pass enriches it, never gates it. Code fixes stay manual via
# /api-drift (in-game probes and approval required).

param(
    [switch]$ReportOnly,
    [switch]$TestNotify,
    [switch]$NoAutoTriage
)

$RepoRoot = Split-Path (Split-Path $PSScriptRoot)

function Show-Toast($title, $body) {
    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        $xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent(
            [Windows.UI.Notifications.ToastTemplateType]::ToastText02)
        $texts = $xml.GetElementsByTagName("text")
        $texts.Item(0).AppendChild($xml.CreateTextNode($title)) | Out-Null
        $texts.Item(1).AppendChild($xml.CreateTextNode($body)) | Out-Null
        $toast = New-Object Windows.UI.Notifications.ToastNotification($xml)
        # PowerShell's AppUserModelID - an ID with a Start-menu entry, so the
        # toast actually displays for an unpackaged script
        $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
    } catch {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show($body, $title) | Out-Null
    }
}

if ($TestNotify) {
    Show-Toast "KitnEssentials API drift watch" "Test notification - wiring OK."
    exit 0
}

$Lua = "C:\Users\Brandon\Documents\WoW-Dev\lua51\bin\lua.exe"
if (-not (Test-Path $Lua)) {
    $cmd = Get-Command lua -ErrorAction SilentlyContinue
    if ($cmd) { $Lua = $cmd.Source }
}
if (-not (Test-Path $Lua)) {
    Show-Toast "KitnEssentials API drift watch FAILED" "lua.exe not found (hererocks tree moved?) - run lua dev/scripts/update-api-reference.lua manually."
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

$relReport = "dev\docs\api-drift-reports\$Stamp.txt"
if ($code -eq 0) {
    exit 0  # clean run (or additions-only) - report archived, no toast
}

# exit 1 with a report header = real BREAKING-USED findings; the run already
# advanced the baseline, so the archived report is the only copy - point at it
$breakLine = $output | Where-Object { $_ -match '^\[BREAKING-USED\] \((\d+)\)' } | Select-Object -First 1
if ($breakLine -and $breakLine -match '\((\d+)\)') {
    $n = $Matches[1]
    $toastBody = "Report saved: $relReport - triage with /api-drift notes."
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
        # Bounded run: a hung headless session must not hold the toast
        # hostage - kill after 20 min and fall back to the manual body.
        $proc = Start-Process -FilePath (Get-Command claude).Source `
            -ArgumentList @("-p", "--allowedTools", "Skill,Read,Glob,Grep") `
            -WorkingDirectory $RepoRoot -NoNewWindow -PassThru `
            -RedirectStandardInput $promptFile `
            -RedirectStandardOutput $triageFile `
            -RedirectStandardError $errFile
        $finished = $proc.WaitForExit(1200000)
        if ($finished) {
            # No-arg WaitForExit flushes process state; without it,
            # .ExitCode reads null after the timed overload (PS 5.1).
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
                $toastBody = "$verdict. Table: $relTriage; report: $relReport."
            }
        }
        # Timeout, nonzero exit, or no single verdict: manual toast body.
    }
    Show-Toast "WoW API drift: $n change(s) hit KE" $toastBody
} else {
    # exit != 0 with no report header = the script aborted (fetch failed,
    # damaged reference) - snapshots untouched, safe to rerun
    Show-Toast "KitnEssentials API drift watch FAILED" "Script aborted (offline? diverged clone?). Details: $relReport"
}
exit $code

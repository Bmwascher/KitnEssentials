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

param(
    [switch]$ReportOnly,
    [switch]$TestNotify
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
    Show-Toast "WoW API drift: $n change(s) hit KE" "Report saved: $relReport - triage with /api-drift notes."
} else {
    # exit != 0 with no report header = the script aborted (fetch failed,
    # damaged reference) - snapshots untouched, safe to rerun
    Show-Toast "KitnEssentials API drift watch FAILED" "Script aborted (offline? diverged clone?). Details: $relReport"
}
exit $code

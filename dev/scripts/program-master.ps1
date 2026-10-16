# program-master.ps1 - the phased-program master registry and its events log.
#
#   pwsh dev/scripts/program-master.ps1 -Register <control document>
#   pwsh dev/scripts/program-master.ps1 -Unregister
#   pwsh dev/scripts/program-master.ps1 -LogEvent '<text>'
#   pwsh dev/scripts/program-master.ps1 -Recover [-SessionId <id>]
#   pwsh dev/scripts/program-master.ps1 -EventsLog <control document>
#
# A master chat runs -Register once, from its own shell, when it opens the
# control document (phased-program skill, step 0). The registry,
# dev/docs/parsec/programs/active-masters.tsv, holds one line per master:
# CLI session id, desktop host session id, control document path. A session
# is a master when either of its ids is on a line; the CLI id comes from
# CLAUDE_CODE_SESSION_ID (or the hook's stdin session_id), the host id from
# CLAUDE_CODE_HOST_SESSION_ID, which the desktop app keeps across a resume.
# Phase and smoke chats never register, so they match nothing.
#
# -Recover is what the compaction hook (dev/claude-hooks/program-recovery.ps1)
# calls: for a master it prints the skill's recovery card and the control
# document's Open questions and Status sections, and logs a `compact` event;
# for any other session it prints nothing. The text only reaches the model's
# context; it cannot make the master act on it.
#
# Events go to <control document stem>-events.log beside the control
# document (`compact`, `relay PASS|FAIL <folder>`); program-tally.ps1 counts
# them at close (-EventsLog prints the log's path for it). -Unregister at
# close removes the session's line.
# KE_PROGRAM_MASTERS overrides the registry path (hook tests).

param(
    [string]$Register,
    [switch]$Unregister,
    [string]$LogEvent,
    [switch]$Recover,
    [string]$SessionId,
    [string]$EventsLog
)

$ErrorActionPreference = 'Stop'
# Control document rows can hold non-ASCII text, which the console code page
# prints as '?'. A process with no console cannot set it and keeps the default.
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch { }
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$registry = if ($env:KE_PROGRAM_MASTERS) { $env:KE_PROGRAM_MASTERS } else { Join-Path $root 'dev\docs\parsec\programs\active-masters.tsv' }
$card = Join-Path $root '.claude\skills\phased-program\recovery-card.md'

$cli = if ($SessionId) { $SessionId } else { [string]$env:CLAUDE_CODE_SESSION_ID }
$hostId = [string]$env:CLAUDE_CODE_HOST_SESSION_ID

function Read-Registry {
    if (-not (Test-Path -LiteralPath $registry)) { return @() }
    return @(Get-Content -LiteralPath $registry | Where-Object { $_.Trim() } | ForEach-Object {
        $f = $_ -split "`t"
        [pscustomobject]@{ cli = $f[0]; host = $f[1]; doc = $f[2]; line = $_ }
    })
}

function Test-Mine($entry) {
    return ($cli -and $entry.cli -eq $cli) -or ($hostId -and $entry.host -eq $hostId)
}

# Read, change and rewrite the registry under a machine-wide lock, so two
# masters registering at once cannot drop each other's line.
function Update-Registry([scriptblock]$change) {
    $mutex = [System.Threading.Mutex]::new($false, 'Local\KitnEssentials-program-masters')
    try {
        try { if (-not $mutex.WaitOne(10000)) { throw '[program] registry is locked by another session; try again' } }
        catch [System.Threading.AbandonedMutexException] { }
        $kept = @(& $change @(Read-Registry))
        New-Item -ItemType Directory -Force (Split-Path $registry -Parent) | Out-Null
        $tmp = "$registry.$PID.tmp"
        Set-Content -LiteralPath $tmp -Value $kept -Encoding utf8
        Move-Item -LiteralPath $tmp -Destination $registry -Force
    } finally {
        try { $mutex.ReleaseMutex() } catch { }
        $mutex.Dispose()
    }
}

function Resolve-Doc([string]$doc) {
    if ([System.IO.Path]::IsPathRooted($doc)) { return $doc }
    return Join-Path $root $doc
}

function Get-EventsLog([string]$docPath) {
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($docPath)
    return Join-Path (Split-Path $docPath -Parent) "$stem-events.log"
}

function Add-Event([string]$docPath, [string]$text) {
    $line = "{0}`t{1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $text
    Add-Content -LiteralPath (Get-EventsLog $docPath) -Value $line -Encoding utf8
}

# The lines under a `## <name>` heading, up to the next `## ` heading or `---` rule.
function Get-Section([string[]]$lines, [string]$name) {
    $out = @(); $inside = $false
    foreach ($l in $lines) {
        if ($inside -and ($l -match '^## ' -or $l -match '^---\s*$')) { break }
        if ($l -match "^## $([regex]::Escape($name))\s*$") { $inside = $true }
        if ($inside) { $out += $l }
    }
    $last = $out.Count - 1
    while ($last -ge 0 -and -not $out[$last].Trim()) { $last-- }
    if ($last -lt 0) { return @() }
    return $out[0..$last]
}

if ($EventsLog) {
    Write-Output (Get-EventsLog (Resolve-Doc $EventsLog))
    exit 0
}

if ($Register) {
    $docPath = Resolve-Doc $Register
    if (-not (Test-Path -LiteralPath $docPath)) { Write-Error "[program] no control document at $docPath"; exit 1 }
    if (-not $cli -and -not $hostId) { Write-Error '[program] no session id in the environment; run this from the master chat''s own shell'; exit 1 }
    $rel = [System.IO.Path]::GetRelativePath($root, (Resolve-Path -LiteralPath $docPath).Path) -replace '\\', '/'
    Update-Registry {
        param($all)
        @($all | Where-Object { -not (Test-Mine $_) } | ForEach-Object { $_.line }) + "$cli`t$hostId`t$rel"
    }
    Write-Output "[program] registered this session as the master of $rel"
    exit 0
}

if ($Unregister) {
    if (-not @(Read-Registry | Where-Object { Test-Mine $_ }).Count) { Write-Output '[program] this session was not registered'; exit 0 }
    Update-Registry { param($all) @($all | Where-Object { -not (Test-Mine $_) } | ForEach-Object { $_.line }) }
    Write-Output '[program] unregistered this session'
    exit 0
}

$mine = @(Read-Registry | Where-Object { Test-Mine $_ }) | Select-Object -Last 1

if ($LogEvent) {
    if (-not $mine) { [Console]::Error.WriteLine("[program] this session is not a registered master; event not logged: $LogEvent"); exit 0 }
    Add-Event (Resolve-Doc $mine.doc) $LogEvent
    exit 0
}

if ($Recover) {
    # A hook must never fail the session start: every error is swallowed.
    try {
        if (-not $mine) { exit 0 }
        $docPath = Resolve-Doc $mine.doc
        try { Add-Event $docPath 'compact' } catch { }
        Write-Output "[program master] Context was compacted. Control document: $($mine.doc)"
        if (Test-Path -LiteralPath $card) {
            Get-Content -LiteralPath $card | Write-Output
        } else {
            Write-Output 'Re-read .claude/skills/phased-program/SKILL.md before your next relay or question (recovery card missing).'
        }
        if (Test-Path -LiteralPath $docPath) {
            $lines = Get-Content -LiteralPath $docPath
            foreach ($name in @('Open questions', 'Status')) {
                $section = Get-Section $lines $name
                Write-Output ''
                if ($section.Count) { $section | Write-Output } else { Write-Output "## ${name}: (section not found in the control document)" }
            }
        } else {
            Write-Output "Control document not found at $docPath."
        }
    } catch { }
    exit 0
}

Write-Output 'Usage: program-master.ps1 -Register <control document> | -Unregister | -LogEvent <text> | -Recover [-SessionId <id>]'
exit 1

# check-artifact-retention.ps1 - enforce the process-artifact retention rule.
#
# Run from anywhere with pwsh:
#   pwsh dev/scripts/check-artifact-retention.ps1 [-Days 30] [-Soft] [-Archive] [-Pick <name>[,<name>...]] [-Root <checkout>]
#
# Process artifacts are the plans, specs, debate rounds, SDD ledgers, notes,
# handoffs, review mirrors and worktrees that Superpowers, parallax and parsec write
# while a branch is in flight. They are local-only (gitignored) and pile up
# unless something checks them, and stale ones get read by later sessions as
# if they were current. This script is the canonical statement of the rule;
# AGENTS.md, the pre-push hook and /memory-audit point here.
#
# Rules:
#   [A] no image/video files under dev/docs or the parsec docs root - FAIL
#       (evidence media lives outside the checkout, e.g. KitnDev/_archive or a
#       drive-root scratch; a docs-wide search must never walk video frames)
#   [B] a date-named entry older than -Days whose slug matches no unmerged
#       branch                                       - stale (note)
#   [C] a review mirror whose commit is in main      - stale (note; a name
#       suffix git cannot resolve is not a mirror)
#   [D] a worktree whose branch is merged into main  - stale (note; never
#       touched by -Archive, remove with `git worktree remove`)
#   [E] an entry larger than 50 MB                   - note
#   [F] a keep entry whose branch is merged or whose date has passed - FAIL
#       (the exemption has expired; delete the line or archive the entry)
#   [G] rounds written to more than one root         - note (parallax path
#       drift; one root only; a root holding just its .gitignore is empty)
#   [H] a finished one-off parsec feature folder     - stale (note)
#   [I] a closed phased program                      - stale (note)
#   [U] a docs-root entry the rules cannot judge     - note, never moved
#
# The parsec docs root is `docs_root` in the primary checkout's
# .claude/parsec.toml (dev/scripts/parsec-docs-root.ps1 prints it). Its
# entries are named docs:<path under the root> in output, the keep list,
# -Pick and the manifest. Rule [B] never judges them, and nothing here reads
# git for them:
#   - a direct child folder other than programs/ and panels/ is a feature
#     folder. Its ledger's last finish line (the text after `finish:`, or a
#     `- <date> merged:` line) decides: one saying merged, with no live
#     rounds\*\pending.json (a rounds\<name>.dead<k> folder is a superseded
#     attempt and does not count) and a newest file 7 days old, is [H]. A merged
#     folder with newer files waits silently.
#   - a programs/<date>-<codename>/ folder holding program.md is a program.
#     Its `## Feature folders` bullets (- `<folder>`) are its members, and a
#     `closed: YYYY-MM-DD` line closes it. A member belongs to its program,
#     whatever its own ledger says: silent while the program is open, [I]
#     with it once closed. A member with a pending round, a keep entry or a
#     second program listing it holds the whole program as [U].
#   - programs/active-masters.tsv, next-program-opening.md,
#     next-program-deferrals.md and .migrated are fixed and silent.
#   - everything else is [U]: no ledger, no finish line, a last finish line
#     not saying merged, a pending round, a panel, a loose file, a program
#     folder with no program.md, a folder two programs list. A [U] entry is
#     listed once its newest file is older than -Days.
# These rules and -Pick run only once programs/.migrated exists. The docs
# cutover writes it as its last program-migration step; before it, programs
# are loose files with no membership, and every program's folders would be
# judged as one-offs.
# The plugin's review worktrees under _worktrees/_review are detached, so rule
# [D] cannot see them: the plugin's doctor lists them and its `round close`
# removes them, before their feature folder is archived.
#
# Keep list (local, optional): dev/docs/retention-keep.txt, one entry per
# line, `relative/path|branch|reason` or `relative/path|until:YYYY-MM-DD|reason`;
# a docs-root entry is written docs:<path>, and is read from the PRIMARY
# checkout's keep file, since every checkout shares one docs root. A
# checkout-path entry naming the docs root is a FAIL: it would match nothing.
# An entry exempts that path (and, for [B], any entry containing it) from [A],
# [B], [E], [H], [I] and [U] while the local branch is unmerged or through the
# end of the named day.
# Work with no branch yet takes the dated form; frozen-but-unbuilt plans use
# the branch they will land on.
#
# Branch matching ([B] only) is a heuristic biased toward keeping: an entry is
# open when its slug and an unmerged branch name contain each other or share
# one non-generic token of five or more characters. A wrongly kept entry costs
# nothing; a wrongly archived one is a move, listed in the manifest.
#
# -Archive moves every [B]/[C]/[H] entry and every [I] program to
# <parent of the primary checkout>/_archive/KitnEssentials-process/: a checkout
# entry to <same relative path>, a feature folder to parsec/<YYYY>/<path under
# the docs root> (the year of its ledger's first date), a program to
# programs/<name>/ with its members under programs/<name>/features/. -Pick
# moves the named [U] entries the same way, a held program with its members,
# and refuses a folder two programs list or a program holding one or a kept
# member. A path already taken gets a timestamp suffix, and each move writes a
# line to MANIFEST-<date>.txt there before it runs; a failed or reversed move
# adds a `not moved` line. Folders move with Directory.Move, which fails whole
# when a file inside is open; such an entry stays and is a FAIL. A program
# moves whole or not at all: when one member cannot move, the moves already
# made for it are reversed, so its program.md keeps the membership for the
# next run. Nothing is ever deleted, except the empty features/ folder an
# undone program move made inside the program folder. Git unavailable means [B]/[C]/[D] cannot be judged: FAIL,
# none of them archived.
# Exit 1 on any FAIL or script error; -Soft forces exit 0.

param(
    [int]$Days = 30,
    [switch]$Soft,
    [switch]$Archive,
    [string[]]$Pick = @(),
    [string]$Root
)

$ErrorActionPreference = 'Stop'
$fails = @(); $notes = @(); $stale = @()
$finished = @(); $closedPrograms = @(); $unknown = @()
$quietDays = 7
$moved = 0
$cutoff = (Get-Date).AddDays(-$Days)

try {
if (-not $Root) { $Root = Join-Path $PSScriptRoot '..\..' }
$root = (Resolve-Path -LiteralPath $Root).Path
$resolver = Join-Path $PSScriptRoot 'parsec-docs-root.ps1'
$primary = [string](& $resolver -Root $root -Primary)
$archiveRoot = Join-Path (Split-Path $primary -Parent) '_archive\KitnEssentials-process'
$keepFile = Join-Path $root 'dev\docs\retention-keep.txt'
$primaryKeepFile = Join-Path $primary 'dev\docs\retention-keep.txt'
$inPrimary = $root.TrimEnd('\', '/').Equals($primary.TrimEnd('\', '/'), [StringComparison]::OrdinalIgnoreCase)

$docsRoot = $null
try { $docsRoot = [string](& $resolver -Root $root) } catch { $fails += "[H] docs root unreadable: $($_.Exception.Message)" }
if ($docsRoot -and -not (Test-Path -LiteralPath $docsRoot -PathType Container)) {
    # A missing fallback is a fresh clone; any other missing root is a botched move.
    if ($docsRoot -ne [System.IO.Path]::GetFullPath((Join-Path $primary 'dev\docs\parsec'))) { $fails += "[H] docs root missing: $docsRoot" }
    $docsRoot = $null
}

$roots = @(
    'dev/docs/superpowers/plans', 'dev/docs/superpowers/specs',
    'dev/docs/superpowers/plans/rounds', 'dev/docs/superpowers/rounds',
    'dev/docs/superpowers/sdd', 'dev/docs/superpowers/notes',
    'dev/docs/superpowers/brainstorm', 'dev/docs/superpowers/reviews',
    'dev/docs/handoffs', 'dev/docs/audits',
    '.superpowers/sdd', '.superpowers/review-sources', '.claude/state'
)
$roundRoots = @('dev/docs/superpowers/plans/rounds', 'dev/docs/superpowers/rounds', '.superpowers/sdd')
$mediaExt = @('.jpg', '.jpeg', '.png', '.gif', '.mp4', '.webm', '.bmp', '.mov')
$sizeLimit = 50MB

function Under([string]$path, [string]$base) {
    $p = $path.TrimEnd('\', '/'); $b = $base.TrimEnd('\', '/')
    return $p.Equals($b, [StringComparison]::OrdinalIgnoreCase) -or $p.StartsWith($b + '\', [StringComparison]::OrdinalIgnoreCase)
}
function Rel($path) {
    if ($docsRoot -and (Under $path $docsRoot)) { return 'docs:' + ($path.Substring($docsRoot.TrimEnd('\').Length).TrimStart('\', '/') -replace '\\', '/') }
    return ($path.Substring($root.Length).TrimStart('\', '/') -replace '\\', '/')
}
function Full($rel) {
    if ($rel.StartsWith('docs:')) {
        if (-not $docsRoot) { return $null }
        return Join-Path $docsRoot ($rel.Substring(5) -replace '/', '\')
    }
    return Join-Path $root ($rel -replace '/', '\')
}

# git state; any failure disables the branch-based rules
$gitOk = $true
function GitLines($argList) {
    $out = & git -C $root @argList 2>$null
    if ($LASTEXITCODE -ne 0) { $script:gitOk = $false; return @() }
    return @($out | Where-Object { $_ })
}
$mergedBranches = GitLines @('branch', '--format=%(refname:short)', '--merged', 'main')
$allBranches = GitLines @('branch', '--format=%(refname:short)')
if (-not $gitOk) { $fails += '[B/C/D] git queries failed; branch-based rules skipped' }
$openBranches = @($allBranches | Where-Object { $mergedBranches -notcontains $_ -and $_ -ne 'main' })
$openSlugs = @($openBranches | ForEach-Object { ($_ -replace '^[^/]+/', '').ToLower() })

$generic = @('plan', 'plans', 'design', 'spec', 'frozen', 'gate', 'diff', 'smoke', 'handoff',
             'phase', 'notes', 'note', 'report', 'brief', 'review', 'sync', 'fix', 'feature')
function SlugTokens($slug) {
    return @(($slug.ToLower() -split '[-_. ]') | Where-Object { $_.Length -ge 5 -and $_ -notmatch '^\d+$' -and $generic -notcontains $_ })
}
function MatchesOpenBranch($slug) {
    $s = $slug.ToLower()
    if (-not $s) { return $false }
    foreach ($b in $openSlugs) {
        if ($s.Contains($b) -or $b.Contains($s)) { return $true }
        foreach ($t in SlugTokens $s) { if ($b.Contains($t)) { return $true } }
    }
    return $false
}

# keep list: checkout entries from this checkout's file; docs: entries from the
# primary's, because a worktree shares the primary's docs root but not its
# gitignored keep file
$keep = @{}
$keepSources = @(@{ file = $keepFile; docs = $inPrimary; checkout = $true })
if (-not $inPrimary) { $keepSources += @{ file = $primaryKeepFile; docs = $true; checkout = $false } }
foreach ($src in $keepSources) {
    if (-not (Test-Path -LiteralPath $src.file)) { continue }
    foreach ($line in Get-Content -LiteralPath $src.file) {
        $t = $line.Trim()
        if (-not $t -or $t.StartsWith('#')) { continue }
        $parts = $t -split '\|'
        if ($parts.Count -lt 2) {
            if ($src.checkout) { $fails += "[F] keep entry malformed (path|branch|reason): $t" }
            continue
        }
        $kpath = ($parts[0].Trim() -replace '\\', '/').TrimEnd('/'); $kbranch = $parts[1].Trim()
        $isDocs = $kpath.StartsWith('docs:')
        if (($isDocs -and -not $src.docs) -or (-not $isDocs -and -not $src.checkout)) { continue }
        # A docs: entry cannot be judged while the docs root is unreadable or missing.
        $kfull = Full $kpath
        if (-not $isDocs -and ($kpath -match '^dev/docs/parsec(/|$)' -or ($docsRoot -and (Under $kfull $docsRoot)))) {
            $fails += "[F] keep entry names a docs-root path by its checkout path; write it as docs:<path>: $kpath"; continue
        }
        if ($null -ne $kfull -and -not (Test-Path -LiteralPath $kfull)) { $fails += "[F] keep entry expired, path gone: $kpath"; continue }
        $m = [regex]::Match($kbranch, '^until:(\d{4}-\d{2}-\d{2})$')
        if ($m.Success) {
            $until = [datetime]::MinValue
            if (-not [datetime]::TryParseExact($m.Groups[1].Value, 'yyyy-MM-dd', $null, 'None', [ref]$until)) {
                $fails += "[F] keep entry has an invalid date ($kbranch): $kpath"; continue
            }
            if ((Get-Date).Date -gt $until.Date) { $fails += "[F] keep entry expired on $($m.Groups[1].Value): $kpath"; continue }
        } elseif ($gitOk -and ($allBranches -notcontains $kbranch -or $mergedBranches -contains $kbranch)) {
            $fails += "[F] keep entry expired, branch merged or gone ($kbranch): $kpath"; continue
        }
        $keep[$kpath.ToLower()] = $kbranch
    }
}
# kept: the path itself or anything under a kept path
function IsKept($rel) {
    $r = $rel.ToLower()
    foreach ($k in $keep.Keys) { if ($r -eq $k -or $r.StartsWith($k + '/')) { return $true } }
    return $false
}
# shelters: the path contains a kept path, so archiving it would move kept work
function SheltersKept($rel) {
    $r = $rel.ToLower()
    foreach ($k in $keep.Keys) { if ($k.StartsWith($r + '/')) { return $true } }
    return $false
}

# [A] media under dev/docs and the docs root. The walk does not follow a
# junction, so a transition junction into the docs root is not walked twice.
$docs = Join-Path $root 'dev\docs'
$mediaDirs = @($docs)
if ($docsRoot -and -not (Under $docsRoot $docs)) { $mediaDirs += $docsRoot }
$media = @()
foreach ($dir in $mediaDirs) {
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    $media += @(Get-ChildItem -LiteralPath $dir -Recurse -File | Where-Object { $mediaExt -contains $_.Extension.ToLower() } |
        Where-Object { -not (IsKept (Rel $_.FullName)) })
}
if ($media.Count -gt 0) {
    $bytes = ($media | Measure-Object Length -Sum).Sum
    $top = $media | Group-Object { Rel $_.DirectoryName } | Sort-Object Count -Descending | Select-Object -First 3
    $fails += ('[A] {0} media files ({1:N0} MB) under dev/docs or the docs root; top: {2}' -f $media.Count, ($bytes / 1MB),
        (($top | ForEach-Object { "$($_.Name) ($($_.Count))" }) -join '; '))
}

# [B] stale date-named entries, [E] oversize entries
$entries = @()
foreach ($r in $roots) {
    $dir = Full $r
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    foreach ($e in Get-ChildItem -LiteralPath $dir -Force) {
        if ($e.Name -in @('archive', 'rounds')) { continue }
        $entries += $e
    }
}
if (Test-Path -LiteralPath $docs) {
    $entries += @(Get-ChildItem -LiteralPath $docs -File | Where-Object { $_.Name -match '\d{4}-\d{2}-\d{2}' })
}
foreach ($e in $entries) {
    $rel = Rel $e.FullName
    if (IsKept $rel) { continue }
    if ($e.PSIsContainer) {
        $size = (Get-ChildItem -LiteralPath $e.FullName -Recurse -File -Force | Measure-Object Length -Sum).Sum
    } else {
        $size = $e.Length
    }
    if ($size -gt $sizeLimit) { $notes += ('[E] {0:N0} MB: {1}' -f ($size / 1MB), $rel) }
    if (-not $gitOk -or (SheltersKept $rel)) { continue }
    $m = [regex]::Match($e.Name, '^(\d{4})-(\d{2})-(\d{2})-?(.*)$')
    if ($m.Success) {
        $date = [datetime]::MinValue
        if (-not [datetime]::TryParseExact(($m.Groups[1].Value + '-' + $m.Groups[2].Value + '-' + $m.Groups[3].Value), 'yyyy-MM-dd', $null, 'None', [ref]$date)) { continue }
        if ($date -lt $cutoff -and -not (MatchesOpenBranch $m.Groups[4].Value)) { $stale += $rel }
    }
}

# [C] review mirrors whose commit is in main
$mirrors = Full '.superpowers/review-sources'
if ($gitOk -and (Test-Path -LiteralPath $mirrors)) {
    foreach ($mdir in Get-ChildItem -LiteralPath $mirrors -Directory) {
        $m = [regex]::Match($mdir.Name, '-([0-9a-f]{7,40})$')
        if ($m.Success) {
            & git -C $root merge-base --is-ancestor $m.Groups[1].Value main 2>$null
            if ($LASTEXITCODE -eq 0) { $stale += Rel $mdir.FullName }
            elseif ($LASTEXITCODE -ne 1 -and $LASTEXITCODE -ne 128) { $gitOk = $false }
        }
    }
}
$stale = @($stale | Select-Object -Unique)

# [D] worktrees on merged branches
if ($gitOk) {
    $wt = GitLines @('worktree', 'list', '--porcelain')
    $wtPath = ''
    foreach ($line in $wt) {
        if ($line -like 'worktree *') { $wtPath = $line.Substring(9) }
        elseif ($line -like 'branch refs/heads/*') {
            $b = $line.Substring(18)
            if ($mergedBranches -contains $b -and $b -ne 'main' -and $wtPath -ne $root.Replace('\', '/')) {
                $notes += "[D] worktree on merged branch $b : $wtPath (git worktree remove)"
            }
        }
    }
}

# [G] rounds in more than one root. A root holding only its own .gitignore
# is the empty SDD workspace parallax creates on demand, not a rounds root.
$liveRoundRoots = @($roundRoots | Where-Object { $d = Full $_; (Test-Path -LiteralPath $d) -and @(Get-ChildItem -LiteralPath $d -Force | Where-Object { $_.Name -ne '.gitignore' }).Count })
if ($liveRoundRoots.Count -gt 1) { $notes += "[G] rounds live in $($liveRoundRoots.Count) roots: $($liveRoundRoots -join ', ')" }

# a git failure in any phase leaves the stale list unjudged
if (-not $gitOk) {
    if ($fails -notcontains '[B/C/D] git queries failed; branch-based rules skipped') { $fails += '[B/C/D] git queries failed; branch-based rules skipped' }
    $stale = @()
}

# [H] [I] [U] the parsec docs root
$statCache = @{}
function StatsOf($item) {
    if (-not $statCache.ContainsKey($item.FullName)) {
        if (-not $item.PSIsContainer) {
            $statCache[$item.FullName] = @{ size = [int64]$item.Length; newest = $item.LastWriteTime }
        } else {
            $files = @(Get-ChildItem -LiteralPath $item.FullName -Recurse -File -Force)
            $newest = if ($files.Count) { ($files | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime } else { $item.LastWriteTime }
            $statCache[$item.FullName] = @{ size = [int64](($files | Measure-Object Length -Sum).Sum); newest = $newest }
        }
    }
    return $statCache[$item.FullName]
}
# The verdict of a ledger's last finish line: the text after `finish:`, or
# `merged` for a `- <date> merged:` line; $null when it has neither.
function LastFinish([string]$ledger) {
    $verdict = $null
    foreach ($line in Get-Content -LiteralPath $ledger) {
        if ($line -match '\bfinish:\s*(.*)$') { $verdict = $Matches[1].Trim() }
        elseif ($line -match '^-\s+\d{4}-\d{2}-\d{2}(\s+\d{2}:\d{2})?(\s+[+-]\d{4})?\s+merged:') { $verdict = 'merged' }
    }
    return $verdict
}
# A live round only: parsec renames a superseded round folder <name>.dead<k>
# and does not count its pending.json as pending. The listing is collected
# whole: a pipeline cut short by Select-Object -First leaves the folder's
# enumeration handle open, and Directory.Move of the member then fails.
function HasPendingRound([string]$dir) {
    $rounds = Join-Path $dir 'rounds'
    if (-not (Test-Path -LiteralPath $rounds -PathType Container)) { return $false }
    return [bool]@(@(Get-ChildItem -LiteralPath $rounds -Directory -Force) | Where-Object { $_.Name -notmatch '\.dead\d+$' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'pending.json')) }).Count
}
# A program's members and closed date; $null when the folder holds no program.md.
# The Feature folders section ends where Get-Section in program-master.ps1 ends one.
function ProgramInfo([string]$dir) {
    $doc = Join-Path $dir 'program.md'
    if (-not (Test-Path -LiteralPath $doc -PathType Leaf)) { return $null }
    $members = @(); $closedOn = $null; $inside = $false
    foreach ($l in Get-Content -LiteralPath $doc) {
        if (-not $closedOn -and $l -match '^closed:\s*(\d{4}-\d{2}-\d{2})\s*$') { $closedOn = $Matches[1] }
        if ($inside -and ($l -match '^## ' -or $l -match '^---\s*$')) { $inside = $false }
        if ($l -match '^##\s+Feature folders\s*$') { $inside = $true; continue }
        if ($inside -and $l -match '^\s*[-*]\s+`([^`]+)`') { $members += $Matches[1].Trim().TrimEnd('/') }
    }
    # A name listed twice in one program is one member (hashtable keys ignore case).
    $seen = @{}
    $members = @($members | Where-Object { if ($seen.ContainsKey($_)) { $false } else { $seen[$_] = 1; $true } })
    return [pscustomobject]@{ closed = $closedOn; members = $members }
}
# $refuse, when set, is why -Pick must not move the entry.
function AddUnknown($item, [string]$reason, $program, [string]$refuse) {
    $script:unknown += [pscustomobject]@{ item = $item; rel = (Rel $item.FullName); reason = $reason; newest = (StatsOf $item).newest; program = $program; refuse = $refuse }
}
# $dstRel itself, or with a timestamp suffix when that archive path is taken.
function FreeArchivePath([string]$dstRel) {
    $final = $dstRel; $n = 0
    while (Test-Path -LiteralPath (Join-Path $archiveRoot ($final -replace '/', '\'))) {
        $n++; $final = '{0}.{1}-{2}' -f $dstRel, (Get-Date -Format 'yyyyMMdd-HHmmss'), $n
    }
    return $final
}
function MoveEntry([string]$src, [string]$dst) {
    New-Item -ItemType Directory -Force (Split-Path $dst -Parent) | Out-Null
    if (Test-Path -LiteralPath $src -PathType Container) { [System.IO.Directory]::Move($src, $dst) } else { [System.IO.File]::Move($src, $dst) }
}
# Manifest lines go in before a move, so a moved entry is never missing from
# the manifest; a move that fails, or is reversed, gets a `not moved` line.
function LogLine([string]$name, [string]$final, [string]$outcome = '') {
    $manifest = Join-Path $archiveRoot ('MANIFEST-{0}.txt' -f (Get-Date -Format 'yyyy-MM-dd'))
    Add-Content -LiteralPath $manifest -Value ("{0} -> {1}{2}" -f $name, $final, $outcome)
}
# Moves one entry under $dstRel in the archive and logs it; returns the path
# used, or $null when the move failed and the entry stayed whole.
function TryMove([string]$src, [string]$name, [string]$dstRel) {
    try {
        New-Item -ItemType Directory -Force $archiveRoot | Out-Null
        $final = FreeArchivePath $dstRel
        LogLine $name $final
        try { MoveEntry $src (Join-Path $archiveRoot ($final -replace '/', '\')) }
        catch {
            $moveError = $_
            try { LogLine $name $final ' not moved' }
            catch { $script:fails += "[archive] the manifest says $name moved to $final, but it did not: $($_.Exception.Message)" }
            throw $moveError
        }
        $script:moved++
        return $final
    } catch {
        $script:fails += "[archive] could not move ${name}: $($_.Exception.Message)"
        return $null
    }
}
function OneOffDestination($item) {
    $year = $null
    $ledger = Join-Path $item.FullName 'ledger.md'
    if ($item.PSIsContainer -and (Test-Path -LiteralPath $ledger -PathType Leaf)) {
        $hit = Select-String -LiteralPath $ledger -Pattern '(\d{4})-\d{2}-\d{2}' -List
        if ($hit) { $year = $hit.Matches[0].Groups[1].Value }
    }
    if (-not $year) { $year = (StatsOf $item).newest.Year }
    return 'parsec/{0}/{1}' -f $year, (Rel $item.FullName).Substring(5)
}
# A program moves whole or not at all: its folder, then each member under its
# features/. When one move fails, the moves already made are reversed, so
# program.md stays beside the members it lists and the next run retries. The
# features/ folder the attempt made inside the program folder goes too, so the
# program comes back as it was.
function ArchiveProgram($p) {
    $done = @(); $failing = $p.rel; $logged = @()
    $features = Join-Path $p.item.FullName 'features'
    $hadFeatures = Test-Path -LiteralPath $features
    try {
        New-Item -ItemType Directory -Force $archiveRoot | Out-Null
        $final = FreeArchivePath ('programs/' + $p.item.Name)
        $plan = @([pscustomobject]@{ src = $p.item.FullName; name = $p.rel; rel = $final })
        foreach ($m in $p.members) {
            $mdir = Join-Path $docsRoot $m
            if (Test-Path -LiteralPath $mdir -PathType Container) { $plan += [pscustomobject]@{ src = $mdir; name = "docs:$m"; rel = "$final/features/$m" } }
        }
        # Each line written is tracked, so a failure part way through the
        # logging still marks every logged entry as not moved.
        foreach ($step in $plan) { $failing = "$($step.name) (its manifest line could not be written)"; LogLine $step.name $step.rel; $logged += $step }
        foreach ($step in $plan) {
            $failing = $step.name
            MoveEntry $step.src (Join-Path $archiveRoot ($step.rel -replace '/', '\'))
            $done += $step
        }
    } catch {
        $script:fails += "[archive] could not move ${failing}: $($_.Exception.Message)"
        $stuck = @()
        for ($i = $done.Count - 1; $i -ge 0; $i--) {
            $step = $done[$i]
            try { MoveEntry (Join-Path $archiveRoot ($step.rel -replace '/', '\')) $step.src }
            catch { $stuck += $step; $script:fails += "[archive] could not put back $($step.name) from $($step.rel): $($_.Exception.Message)" }
        }
        if (-not $stuck.Count -and -not $hadFeatures -and (Test-Path -LiteralPath $features) -and -not @(Get-ChildItem -LiteralPath $features -Force).Count) {
            try { [System.IO.Directory]::Delete($features) } catch { $script:fails += "[archive] could not remove the empty features folder it made in $($p.rel): $($_.Exception.Message)" }
        }
        foreach ($step in $logged) {
            if ($stuck -notcontains $step) { try { LogLine $step.name $step.rel ' not moved' } catch { $script:fails += "[archive] the manifest says $($step.name) moved to $($step.rel), but it did not: $($_.Exception.Message)" } }
        }
        return
    }
    $script:moved += $done.Count
}

# The migration marker: until the cutover's program migration finishes, every
# program's folders would be judged as one-offs.
$migrationWait = $false
if ($docsRoot) {
    $programsDir = Join-Path $docsRoot 'programs'
    if (-not (Test-Path -LiteralPath (Join-Path $programsDir '.migrated') -PathType Leaf)) {
        $migrationWait = $true
        $notes += '[H] no docs:programs/.migrated marker; the docs-root rules wait for the program migration'
    }
}

if ($docsRoot -and -not $migrationWait) {
    # Programs first: membership decides before a member's own ledger.
    $fixed = @('active-masters.tsv', 'next-program-opening.md', 'next-program-deferrals.md', '.migrated')
    $programs = @(); $owners = @{}
    if (Test-Path -LiteralPath $programsDir -PathType Container) {
        foreach ($e in Get-ChildItem -LiteralPath $programsDir -Force) {
            $rel = Rel $e.FullName
            if (-not $e.PSIsContainer) {
                if ($fixed -notcontains $e.Name -and -not (IsKept $rel)) { AddUnknown $e 'loose file' $null }
                continue
            }
            $info = ProgramInfo $e.FullName
            if ($null -eq $info) {
                if (-not ((IsKept $rel) -or (SheltersKept $rel))) { AddUnknown $e 'program without program.md' $null }
                continue
            }
            $p = [pscustomobject]@{ item = $e; rel = $rel; closed = $info.closed; members = $info.members; blocks = @(); pending = @() }
            $programs += $p
            foreach ($m in $p.members) {
                $k = $m.ToLower()
                if (-not $owners.ContainsKey($k)) { $owners[$k] = @() }
                $owners[$k] += $p
            }
        }
    }

    foreach ($e in Get-ChildItem -LiteralPath $docsRoot -Force) {
        if ($e.PSIsContainer -and $e.Name -in @('programs', 'panels')) { continue }
        $rel = Rel $e.FullName
        if ((IsKept $rel) -or (SheltersKept $rel)) { continue }
        if (-not $e.PSIsContainer) { AddUnknown $e 'loose file' $null; continue }
        $k = $e.Name.ToLower()
        if ($owners.ContainsKey($k)) {
            if (@($owners[$k]).Count -gt 1) { AddUnknown $e 'listed by two programs' $null 'listed by two programs' }
            continue
        }
        $ledger = Join-Path $e.FullName 'ledger.md'
        if (-not (Test-Path -LiteralPath $ledger -PathType Leaf)) { AddUnknown $e 'no ledger' $null; continue }
        $verdict = LastFinish $ledger
        if ($null -eq $verdict) { AddUnknown $e 'no finish line' $null; continue }
        if ($verdict -notmatch '^merged\b') {
            $short = if ($verdict.Length -gt 50) { $verdict.Substring(0, 50) } else { $verdict }
            AddUnknown $e "last finish: $short" $null; continue
        }
        if (HasPendingRound $e.FullName) { AddUnknown $e 'round pending' $null; continue }
        if ((StatsOf $e).newest -gt (Get-Date).AddDays(-$quietDays)) { continue }
        $finished += [pscustomobject]@{ item = $e; rel = $rel }
    }

    $panelsDir = Join-Path $docsRoot 'panels'
    if (Test-Path -LiteralPath $panelsDir -PathType Container) {
        foreach ($e in Get-ChildItem -LiteralPath $panelsDir -Force) {
            $rel = Rel $e.FullName
            if ((IsKept $rel) -or (SheltersKept $rel)) { continue }
            AddUnknown $e 'panel' $null
        }
    }

    # A kept member or one a second program lists blocks the program even from
    # -Pick; a pending round only holds it, and -Pick may still move it.
    foreach ($p in $programs) {
        if ((IsKept $p.rel) -or (SheltersKept $p.rel) -or -not $p.closed) { continue }
        foreach ($m in $p.members) {
            $mdir = Join-Path $docsRoot $m
            $mrel = "docs:$m"
            if (-not (Test-Path -LiteralPath $mdir -PathType Container)) { $notes += "[I] listed folder missing: $mrel"; continue }
            if (@($owners[$m.ToLower()]).Count -gt 1) { $p.blocks += "$mrel listed by two programs" }
            elseif ((IsKept $mrel) -or (SheltersKept $mrel)) { $p.blocks += "$mrel kept" }
            elseif (HasPendingRound $mdir) { $p.pending += "$mrel round pending" }
        }
        $holds = @($p.blocks) + @($p.pending)
        if (-not $holds.Count) { $closedPrograms += $p; continue }
        $refuse = if ($p.blocks.Count) { $p.blocks[0] } else { $null }
        AddUnknown $p.item "program held: $($holds[0])" $p $refuse
    }
}

if ($docsRoot) {
    $docsEntries = @(Get-ChildItem -LiteralPath $docsRoot -Force | Where-Object { -not ($_.PSIsContainer -and $_.Name -in @('programs', 'panels')) })
    foreach ($sub in @('programs', 'panels')) {
        $d = Join-Path $docsRoot $sub
        if (Test-Path -LiteralPath $d -PathType Container) { $docsEntries += @(Get-ChildItem -LiteralPath $d -Force) }
    }
    foreach ($e in $docsEntries) {
        $rel = Rel $e.FullName
        if (IsKept $rel) { continue }
        $size = (StatsOf $e).size
        if ($size -gt $sizeLimit) { $notes += ('[E] {0:N0} MB: {1}' -f ($size / 1MB), $rel) }
    }
}

# -Archive
if ($Archive) {
    foreach ($rel in $stale) { TryMove (Full $rel) $rel $rel | Out-Null }
    foreach ($f in $finished) { TryMove $f.item.FullName $f.rel (OneOffDestination $f.item) | Out-Null }
    foreach ($p in $closedPrograms) { ArchiveProgram $p }
    $stale = @(); $finished = @(); $closedPrograms = @()
}

# -Pick; `pwsh -File` passes a,b as one string, so names are split here. With no
# docs root, or with no migration marker, nothing was judged, so nothing is picked.
$pickNames = @($Pick | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($pickNames.Count -and ($migrationWait -or -not $docsRoot)) {
    $notes += "[U] -Pick skipped: the docs-root rules did not run, so $($pickNames.Count) named entries were not judged"
    $pickNames = @()
}
foreach ($name in $pickNames) {
    $u = $unknown | Where-Object { $_.rel -eq $name } | Select-Object -First 1
    if (-not $u) { $fails += "[U] not an unknown entry: $name"; continue }
    if ($u.refuse) { $fails += "[U] cannot pick ${name}: $($u.refuse)"; continue }
    if ($u.program) { ArchiveProgram $u.program } else { TryMove $u.item.FullName $u.rel (OneOffDestination $u.item) | Out-Null }
    $unknown = @($unknown | Where-Object { $_ -ne $u })
}

if ($moved -gt 0) { Write-Output ('[retention] archived {0} entries -> {1}' -f $moved, $archiveRoot) }
} catch {
    $fails += "[script] $($_.Exception.Message)"
}

# report
$listed = @($unknown | Where-Object { $_.newest -lt $cutoff })
foreach ($f in $fails) { Write-Output "[retention] FAIL $f" }
foreach ($n in $notes) { Write-Output "[retention] note $n" }
if ($stale.Count -gt 0) {
    Write-Output ('[retention] note [B/C] {0} stale entries older than {1} days with no open branch (-Archive moves them):' -f $stale.Count, $Days)
    foreach ($s in $stale) { Write-Output "    $s" }
}
if ($finished.Count -gt 0) {
    Write-Output ('[retention] note [H] {0} finished features (-Archive moves them):' -f $finished.Count)
    foreach ($f in $finished) { Write-Output "    $($f.rel)" }
}
foreach ($p in $closedPrograms) {
    Write-Output ('[retention] note [I] closed program {0}, {1} feature folders (-Archive moves them)' -f $p.rel, @($p.members).Count)
}
if ($listed.Count -gt 0) {
    Write-Output ('[retention] note [U] {0} entries the rule cannot judge (pick with -Pick):' -f $listed.Count)
    foreach ($u in $listed) { Write-Output "    $($u.rel) ($($u.reason))" }
}
$noteCount = $notes.Count + [int]($stale.Count -gt 0) + [int]($finished.Count -gt 0) + $closedPrograms.Count + [int]($listed.Count -gt 0)
if ($fails.Count -eq 0 -and $noteCount -eq 0) { Write-Output '[retention] OK' }
elseif ($fails.Count -eq 0) { Write-Output ('[retention] OK with {0} note(s)' -f $noteCount) }
if ($fails.Count -gt 0 -and -not $Soft) { exit 1 }
exit 0

# check-artifact-retention.ps1 - enforce the process-artifact retention rule.
#
# Run from anywhere with pwsh:
#   pwsh dev/scripts/check-artifact-retention.ps1 [-Days 30] [-Soft] [-Archive] [-Root <checkout>]
#
# Process artifacts are the plans, specs, debate rounds, SDD ledgers, notes,
# handoffs, review mirrors and worktrees that Superpowers and parallax write
# while a branch is in flight. They are local-only (gitignored) and pile up
# unless something checks them, and stale ones get read by later sessions as
# if they were current. This script is the canonical statement of the rule;
# AGENTS.md, the pre-push hook and /memory-audit point here.
#
# Rules:
#   [A] no image/video files under dev/docs         - FAIL (evidence media
#       lives outside the checkout, e.g. KitnDev/_archive or a drive-root
#       scratch; a checkout-wide search must never walk video frames)
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
#       drift; one root only)
#
# Keep list (local, optional): dev/docs/retention-keep.txt, one entry per
# line, `relative/path|branch|reason` or `relative/path|until:YYYY-MM-DD|reason`.
# An entry exempts that path (and, for [B], any entry containing it) from [A],
# [B] and [E] while the local branch is unmerged or through the end of the
# named day.
# Work with no branch yet takes the dated form; frozen-but-unbuilt plans use
# the branch they will land on.
#
# Branch matching is a heuristic biased toward keeping: an entry is open when
# its slug and an unmerged branch name contain each other or share one
# non-generic token of five or more characters. A wrongly kept entry costs
# nothing; a wrongly archived one is a move, listed in the manifest.
#
# -Archive moves every [B]/[C] stale entry to
# <parent of the checkout>/_archive/KitnEssentials-process/<same relative path>
# (KitnDev/_archive/... for the primary checkout; suffixed with
# a timestamp when that path is already taken) and appends the moved paths to
# MANIFEST-<date>.txt there. Nothing is ever deleted. Git unavailable means
# [B]/[C]/[D] cannot be judged: FAIL, no archive.
# Exit 1 on any FAIL or script error; -Soft forces exit 0.

param(
    [int]$Days = 30,
    [switch]$Soft,
    [switch]$Archive,
    [string]$Root
)

$ErrorActionPreference = 'Stop'
$fails = @(); $notes = @(); $stale = @()

try {
if (-not $Root) { $Root = Join-Path $PSScriptRoot '..\..' }
$root = (Resolve-Path -LiteralPath $Root).Path
$archiveRoot = Join-Path (Split-Path $root -Parent) '_archive\KitnEssentials-process'
$keepFile = Join-Path $root 'dev\docs\retention-keep.txt'

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

function Rel($path) { return ($path.Substring($root.Length).TrimStart('\', '/') -replace '\\', '/') }
function Full($rel) { return Join-Path $root ($rel -replace '/', '\') }

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

# keep list
$keep = @{}
if (Test-Path -LiteralPath $keepFile) {
    foreach ($line in Get-Content -LiteralPath $keepFile) {
        $t = $line.Trim()
        if (-not $t -or $t.StartsWith('#')) { continue }
        $parts = $t -split '\|'
        if ($parts.Count -lt 2) { $fails += "[F] keep entry malformed (path|branch|reason): $t"; continue }
        $kpath = ($parts[0].Trim() -replace '\\', '/').TrimEnd('/'); $kbranch = $parts[1].Trim()
        if (-not (Test-Path -LiteralPath (Full $kpath))) { $fails += "[F] keep entry expired, path gone: $kpath"; continue }
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

# [A] media under dev/docs
$docs = Join-Path $root 'dev\docs'
if (Test-Path -LiteralPath $docs) {
    $media = @(Get-ChildItem -LiteralPath $docs -Recurse -File | Where-Object { $mediaExt -contains $_.Extension.ToLower() } |
        Where-Object { -not (IsKept (Rel $_.FullName)) })
    if ($media.Count -gt 0) {
        $bytes = ($media | Measure-Object Length -Sum).Sum
        $top = $media | Group-Object { Rel $_.DirectoryName } | Sort-Object Count -Descending | Select-Object -First 3
        $fails += ('[A] {0} media files ({1:N0} MB) under dev/docs; top: {2}' -f $media.Count, ($bytes / 1MB),
            (($top | ForEach-Object { "$($_.Name) ($($_.Count))" }) -join '; '))
    }
}

# [B] stale date-named entries, [E] oversize entries
$cutoff = (Get-Date).AddDays(-$Days)
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

# [G] rounds in more than one root
$liveRoundRoots = @($roundRoots | Where-Object { $d = Full $_; (Test-Path -LiteralPath $d) -and (Get-ChildItem -LiteralPath $d -Force | Select-Object -First 1) })
if ($liveRoundRoots.Count -gt 1) { $notes += "[G] rounds live in $($liveRoundRoots.Count) roots: $($liveRoundRoots -join ', ')" }

# a git failure in any phase leaves the stale list unjudged
if (-not $gitOk) {
    if ($fails -notcontains '[B/C/D] git queries failed; branch-based rules skipped') { $fails += '[B/C/D] git queries failed; branch-based rules skipped' }
    $stale = @()
}

# -Archive
if ($Archive -and $stale.Count -gt 0) {
    New-Item -ItemType Directory -Force $archiveRoot | Out-Null
    $manifest = Join-Path $archiveRoot ('MANIFEST-{0}.txt' -f (Get-Date -Format 'yyyy-MM-dd'))
    foreach ($rel in $stale) {
        $src = Full $rel
        $dstRel = $rel; $n = 0
        while (Test-Path -LiteralPath (Join-Path $archiveRoot ($dstRel -replace '/', '\'))) {
            $n++; $dstRel = '{0}.{1}-{2}' -f $rel, (Get-Date -Format 'yyyyMMdd-HHmmss'), $n
        }
        $dst = Join-Path $archiveRoot ($dstRel -replace '/', '\')
        New-Item -ItemType Directory -Force (Split-Path $dst -Parent) | Out-Null
        Move-Item -LiteralPath $src -Destination $dst
        Add-Content -LiteralPath $manifest -Value ("{0} -> {1}" -f $rel, $dstRel)
    }
    Write-Output ('[retention] archived {0} entries -> {1}' -f $stale.Count, $archiveRoot)
    $stale = @()
}
} catch {
    $fails += "[script] $($_.Exception.Message)"
}

# report
foreach ($f in $fails) { Write-Output "[retention] FAIL $f" }
foreach ($n in $notes) { Write-Output "[retention] note $n" }
if ($stale.Count -gt 0) {
    Write-Output ('[retention] note [B/C] {0} stale entries older than {1} days with no open branch (-Archive moves them):' -f $stale.Count, $Days)
    foreach ($s in $stale) { Write-Output "    $s" }
}
if ($fails.Count -eq 0 -and $notes.Count -eq 0 -and $stale.Count -eq 0) { Write-Output '[retention] OK' }
elseif ($fails.Count -eq 0) { Write-Output ('[retention] OK with {0} note(s)' -f ($notes.Count + [int]($stale.Count -gt 0))) }
if ($fails.Count -gt 0 -and -not $Soft) { exit 1 }
exit 0

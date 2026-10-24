# check-lib-updates.ps1 - report library pins in .pkgmeta that upstream has
# moved past, and move a pin together with its tracked copy under Libs/.
#
# Run from anywhere with pwsh:
#   pwsh dev/scripts/check-lib-updates.ps1 [-Soft] [-Refresh] [-Root <checkout>]
#   pwsh dev/scripts/check-lib-updates.ps1 -Update <name>[,<name>...] [-To <tag or full commit>]
#
# Check. Every external in .pkgmeta is pinned to a tag or a commit. A tag pin
# is compared with the newest upstream tag of the same shape (digits ignored:
# v12.1.1 competes only with v#.#.#, so an alpha or a differently named tag
# series never counts as newer). A commit pin is compared with upstream HEAD,
# which can move without touching the pinned subfolder. Externals that share
# a repository and a pin print as one line. Upstream answers are cached for
# 20 hours in the git common dir (kitn-lib-updates.json, shared by every
# worktree, never tracked); the pins are re-read on every run, so a moved pin
# clears its note without a fetch. -Refresh ignores the cache. -Soft is the
# session-start mode: exit 0 always, and an unreachable upstream is silent.
# Output: "[libs] note" for a pin behind upstream, "[libs] FAIL" for an
# external with no pin, "[libs] skip" for an upstream that could not be read.
#
# Update. Rebuilds Libs/<name> at the new ref the way the packager does and
# rewrites the pin. Default ref: the newest same-shape tag, or upstream HEAD
# for a commit pin; -To picks one (a 40-hex value pins a commit, anything
# else a tag). Every external sharing the named one's repository and pin
# moves with it (the six Ace3 folders are one pin). The rebuild:
#   - the files the packager ships from the external: dot files and dot
#     folders are dropped; files that existed at the old pin but are not in
#     the tracked copy stay out (the external's own .pkgmeta ignored them, or
#     they were left out on purpose); files new since the old pin come in
#   - tracked files gone upstream are deleted
#   - --@do-not-package@ ... --@end-do-not-package@ blocks (any comment
#     style) are removed and text files get LF line ends; any other packager
#     keyword is listed for a hand check, never transformed
# Rebuilding at the current pin is a repair and a self-test: on a correct
# copy it leaves no diff. Refuses on main and over uncommitted changes to
# .pkgmeta or the folder. The packaged result is verified by the Package
# check workflow (every loaded library file reads "match").

param(
    [switch]$Soft,
    [switch]$Refresh,
    [string[]]$Update,
    [string]$To,
    [string]$Root
)

$ErrorActionPreference = 'Stop'
$env:GIT_TERMINAL_PROMPT = '0'

if (-not $Root) { $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }
$pkgmeta = Join-Path $Root '.pkgmeta'
$cacheHours = 20

function Out-Line([string]$text) { Write-Output "[libs] $text" }

function Read-Externals([string]$path) {
    $list = [System.Collections.Generic.List[object]]::new()
    $inExternals = $false
    $cur = $null
    foreach ($line in [System.IO.File]::ReadAllLines($path)) {
        if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
        if ($line -match '^(\S[^:]*):') { $inExternals = ($Matches[1] -eq 'externals'); $cur = $null; continue }
        if (-not $inExternals) { continue }
        if ($line -match '^  (\S+):\s*(\S*)') {
            $cur = [pscustomobject]@{ path = $Matches[1]; name = ($Matches[1] -split '/')[-1]; url = $Matches[2]; kind = ''; ref = '' }
            $list.Add($cur)
            continue
        }
        if ($cur -and $line -match '^    (url|tag|commit):\s*[''"]?([^''"\s]+)') {
            if ($Matches[1] -eq 'url') { $cur.url = $Matches[2] } else { $cur.kind = $Matches[1]; $cur.ref = $Matches[2] }
        }
    }
    return $list
}

# The packager maps a CurseForge trunk URL to tags/<tag> for a tag pin, and
# fetches a subfolder for a GitHub URL with a path after .git. Any other git
# URL is the repository itself (townlong-yak's addons.git/taintless is one).
function Get-Source([string]$url) {
    if ($url -match '^(https?://repos\.curseforge\.com/wow/[^/]+)/trunk(?:/(.*))?$') {
        return [pscustomobject]@{ type = 'svn'; repo = $Matches[1]; sub = [string]$Matches[2] }
    }
    if ($url -match '^(https://github\.com/[^/]+/[^/]+?\.git)/(.+)$') {
        return [pscustomobject]@{ type = 'git'; repo = $Matches[1]; sub = $Matches[2] }
    }
    return [pscustomobject]@{ type = 'git'; repo = $url; sub = '' }
}

function Get-Shape([string]$tag) { return ($tag -replace '\d+', '#') }

function Compare-Version([string]$a, [string]$b) {
    $x = @([regex]::Matches($a, '\d+') | ForEach-Object { [long]$_.Value })
    $y = @([regex]::Matches($b, '\d+') | ForEach-Object { [long]$_.Value })
    for ($i = 0; $i -lt [Math]::Min($x.Count, $y.Count); $i++) {
        if ($x[$i] -ne $y[$i]) { return [Math]::Sign($x[$i] - $y[$i]) }
    }
    return [Math]::Sign($x.Count - $y.Count)
}

function Get-NewestTag([string[]]$tags, [string]$pinned) {
    $shape = Get-Shape $pinned
    $best = $null
    foreach ($t in $tags) {
        if ((Get-Shape $t) -cne $shape) { continue }
        if ($null -eq $best -or (Compare-Version $t $best) -gt 0) { $best = $t }
    }
    return $best
}

# Upstream queries run in parallel runspaces, which see none of this file's
# functions, so each returns raw text and parsing happens here.
function Invoke-UpstreamQueries($queries, [int]$timeoutSeconds) {
    $raw = @{}
    if (-not $queries.Count) { return $raw }
    $results = $queries | ForEach-Object -ThrottleLimit 8 -TimeoutSeconds $timeoutSeconds -Parallel {
        $q = $_
        $out = $null
        try {
            if ($q.type -eq 'svn') {
                $out = (Invoke-WebRequest -Uri "$($q.repo)/tags/" -TimeoutSec 20 -UseBasicParsing).Content
            } elseif ($q.kind -eq 'tag') {
                $out = (& git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=15 ls-remote --tags --refs $q.repo 2>$null) -join "`n"
                if ($LASTEXITCODE -ne 0) { $out = $null }
            } else {
                $out = (& git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=15 ls-remote $q.repo HEAD 2>$null) -join "`n"
                if ($LASTEXITCODE -ne 0) { $out = $null }
            }
        } catch { $out = $null }
        [pscustomobject]@{ key = $q.key; out = $out }
    }
    foreach ($r in @($results)) { if ($r.out) { $raw[$r.key] = $r.out } }
    return $raw
}

function Get-TagNames([string]$type, [string]$raw) {
    if ($type -eq 'svn') {
        return @([regex]::Matches($raw, '<li><a href="([^"]+)/">') | ForEach-Object { [Uri]::UnescapeDataString($_.Groups[1].Value) } | Where-Object { $_ -ne '..' })
    }
    return @($raw -split "`n" | Where-Object { $_ -match 'refs/tags/(.+)$' } | ForEach-Object { ($_ -split 'refs/tags/', 2)[1].Trim() })
}

function Get-HeadSha([string]$raw) {
    if ($raw -match '(?m)^([0-9a-f]{40})\s+HEAD') { return $Matches[1] }
    return $null
}

# One upstream answer per repository, pin kind and tag shape: the newest
# same-shape tag, or the HEAD commit.
function Get-QueryKey($src, $ext) {
    $shape = if ($ext.kind -eq 'tag') { Get-Shape $ext.ref } else { '' }
    return "$($src.type)|$($src.repo)|$($ext.kind)|$shape"
}

function Resolve-Upstream($externals, [bool]$useCache, [hashtable]$cache, [int]$timeoutSeconds) {
    $now = [DateTime]::UtcNow
    $answers = @{}
    $needed = @{}
    foreach ($ext in $externals) {
        if (-not $ext.kind) { continue }
        $src = Get-Source $ext.url
        if ($src.type -eq 'svn' -and $ext.kind -ne 'tag') { continue }
        $key = Get-QueryKey $src $ext
        if ($answers.ContainsKey($key) -or $needed.ContainsKey($key)) { continue }
        $hit = if ($useCache) { $cache[$key] } else { $null }
        if ($hit -and ($now - [DateTime]::Parse($hit.checked).ToUniversalTime()).TotalHours -lt $cacheHours) {
            $answers[$key] = $hit.value
        } else {
            $needed[$key] = [pscustomobject]@{ key = $key; type = $src.type; repo = $src.repo; kind = $ext.kind; pinned = $ext.ref }
        }
    }
    $raw = Invoke-UpstreamQueries @($needed.Values) $timeoutSeconds
    foreach ($q in $needed.Values) {
        if (-not $raw.ContainsKey($q.key)) { continue }
        $value = if ($q.kind -eq 'tag') { Get-NewestTag (Get-TagNames $q.type $raw[$q.key]) $q.pinned } else { Get-HeadSha $raw[$q.key] }
        if (-not $value) { continue }
        $answers[$q.key] = $value
        $cache[$q.key] = [pscustomobject]@{ checked = $now.ToString('o'); value = $value }
    }
    return $answers
}

function Get-CachePath {
    $common = (& git -C $Root rev-parse --git-common-dir 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $common) { return $null }
    if (-not [System.IO.Path]::IsPathRooted($common)) { $common = Join-Path $Root $common }
    return Join-Path $common 'kitn-lib-updates.json'
}

function Read-Cache([string]$path) {
    $cache = @{}
    if ($path -and (Test-Path -LiteralPath $path)) {
        try {
            $json = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            foreach ($p in $json.PSObject.Properties) { $cache[$p.Name] = $p.Value }
        } catch { $cache = @{} }
    }
    return $cache
}

function Write-Cache([string]$path, [hashtable]$cache) {
    if (-not $path) { return }
    try { [System.IO.File]::WriteAllText($path, ($cache | ConvertTo-Json -Depth 3)) } catch { }
}

function Format-Ref([string]$kind, [string]$ref) {
    if ($kind -eq 'commit') { return $ref.Substring(0, [Math]::Min(8, $ref.Length)) }
    return $ref
}

function Get-PinGroups($externals) {
    $groups = [ordered]@{}
    foreach ($ext in $externals) {
        $src = Get-Source $ext.url
        $g = "$($src.type)|$($src.repo)|$($ext.kind)|$($ext.ref)"
        if (-not $groups.Contains($g)) { $groups[$g] = [System.Collections.Generic.List[object]]::new() }
        $groups[$g].Add($ext)
    }
    return $groups
}

function Invoke-Check {
    if (-not (Test-Path -LiteralPath $pkgmeta)) {
        if ($Soft) { exit 0 }
        Out-Line "FAIL no .pkgmeta under $Root"
        exit 1
    }
    $externals = @(Read-Externals $pkgmeta)
    $cachePath = Get-CachePath
    $cache = Read-Cache $cachePath
    $timeout = if ($Soft) { 25 } else { 90 }
    $answers = Resolve-Upstream $externals (-not $Refresh) $cache $timeout
    Write-Cache $cachePath $cache

    $notes = 0; $fails = 0; $skips = 0
    foreach ($group in (Get-PinGroups $externals).Values) {
        $ext = $group[0]
        $names = ($group | ForEach-Object { $_.name }) -join ', '
        if (-not $ext.kind) {
            $fails += $group.Count
            Out-Line "FAIL ${names}: no tag or commit pin in .pkgmeta"
            continue
        }
        $src = Get-Source $ext.url
        if ($src.type -eq 'svn' -and $ext.kind -ne 'tag') {
            $skips++
            if (-not $Soft) { Out-Line "skip ${names}: a commit pin on an svn source is not checked" }
            continue
        }
        $key = Get-QueryKey $src $ext
        if (-not $answers.ContainsKey($key)) {
            $skips++
            if (-not $Soft) { Out-Line "skip ${names}: upstream unreachable ($($src.repo))" }
            continue
        }
        $up = $answers[$key]
        $behind = if ($ext.kind -eq 'tag') { (Compare-Version $up $ext.ref) -gt 0 } else { $up -ne $ext.ref }
        if ($behind) {
            $notes++
            $what = if ($ext.kind -eq 'tag') { "upstream $up" } else { "upstream HEAD $(Format-Ref commit $up)" }
            Out-Line "note ${names}: pinned $(Format-Ref $ext.kind $ext.ref), $what"
        }
    }
    $unchecked = if ($skips) { ", $skips unchecked" } else { '' }
    if ($fails) {
        Out-Line "FAIL $fails external(s) without a pin"
    } elseif ($notes) {
        Out-Line "OK with $notes note(s)$unchecked"
    } elseif (-not $Soft) {
        Out-Line "OK: no pin behind upstream$unchecked"
    }
    if ($Soft) { exit 0 }
    if ($fails -or $skips) { exit 1 }
    exit 0
}

# ---------------------------------------------------------------- update

$textExtensions = @('.lua', '.xml', '.toc', '.txt', '.md')
# Comment-marker keywords only (--@debug@, #@retail@, <!--@alpha@-->): a bare
# @project-version@ in a .toc stays raw in the tracked copies.
$keywordPattern = '(?:--|#|<!--)\s*@(?!do-not-package@|end-do-not-package@)[a-z]+(?:-[a-z]+)*@'

function Test-Shipped([string]$rel) {
    foreach ($seg in ($rel -split '/')) { if ($seg.StartsWith('.')) { return $false } }
    return $true
}

function Remove-DoNotPackage([string]$text) {
    $kept = [System.Collections.Generic.List[string]]::new()
    $skipping = $false
    foreach ($line in ($text -split "`n")) {
        if (-not $skipping -and $line -match '@do-not-package@') { $skipping = $true; continue }
        if ($skipping) {
            if ($line -match '@end-do-not-package@') { $skipping = $false }
            continue
        }
        $kept.Add($line)
    }
    return ($kept -join "`n")
}

function Invoke-Git([string[]]$gitArgs) {
    $out = & git @gitArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($gitArgs -join ' ') failed: $($out -join ' ')" }
    return $out
}

function Open-GitSource($src, [string]$work) {
    $dir = Join-Path $work 'repo'
    Invoke-Git @('-c', 'core.autocrlf=false', 'clone', '--quiet', '--filter=blob:none', '--no-checkout', $src.repo, $dir) | Out-Null
    return $dir
}

function Get-GitFiles([string]$dir, [string]$ref, [string]$sub) {
    $treeish = if ($sub) { "${ref}:$sub" } else { "${ref}:" }
    $names = Invoke-Git @('-C', $dir, 'ls-tree', '-r', '--name-only', $treeish)
    return @($names | ForEach-Object { [string]$_ } | Where-Object { $_ -and (Test-Shipped $_) })
}

function Get-SvnFiles([string]$base) {
    $files = [System.Collections.Generic.List[string]]::new()
    $queue = [System.Collections.Generic.Queue[string]]::new()
    $queue.Enqueue('')
    while ($queue.Count) {
        $rel = $queue.Dequeue()
        $html = (Invoke-WebRequest -Uri ($base + $rel) -TimeoutSec 30 -UseBasicParsing).Content
        foreach ($m in [regex]::Matches($html, '<li><a href="([^"]+)">')) {
            $href = $m.Groups[1].Value
            if ($href -eq '../' -or $href -match '^[a-z]+:') { continue }
            $name = $rel + [Uri]::UnescapeDataString($href)
            if (-not (Test-Shipped $name.TrimEnd('/'))) { continue }
            if ($href.EndsWith('/')) { $queue.Enqueue($name) } else { $files.Add($name) }
        }
    }
    return $files
}

function Get-SvnBase($src, [string]$ref) {
    $base = "$($src.repo)/tags/$ref/"
    if ($src.sub) { $base += "$($src.sub)/" }
    return $base
}

function Get-TrackedFiles([string]$folder) {
    $prefix = "Libs/$folder/"
    $names = Invoke-Git @('-C', $Root, 'ls-files', '--', $prefix)
    return @($names | ForEach-Object { ([string]$_).Substring($prefix.Length) })
}

function Set-Pin([string[]]$paths, [string]$kind, [string]$ref) {
    $text = [System.IO.File]::ReadAllText($pkgmeta)
    $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = $text -split "`r?`n"
    $inExternals = $false; $cur = ''
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '^\s*#') { continue }
        if ($line -match '^(\S[^:]*):') { $inExternals = ($Matches[1] -eq 'externals'); $cur = ''; continue }
        if (-not $inExternals) { continue }
        if ($line -match '^  (\S+):') { $cur = $Matches[1]; continue }
        if ($paths -contains $cur -and $line -match '^    (tag|commit):') { $lines[$i] = "    ${kind}: $ref" }
    }
    [System.IO.File]::WriteAllText($pkgmeta, ($lines -join $nl))
}

function Update-Group($group, [string]$target, [string]$targetKind) {
    $ext0 = $group[0]
    $src = Get-Source $ext0.url
    $work = Join-Path ([System.IO.Path]::GetTempPath()) ("kitn-libs-" + [System.IO.Path]::GetRandomFileName().Replace('.', ''))
    New-Item -ItemType Directory -Path $work | Out-Null
    try {
        $dir = if ($src.type -eq 'git') { Open-GitSource $src $work } else { $null }
        foreach ($ext in $group) {
            $s = Get-Source $ext.url
            if ($src.type -eq 'git') {
                $newFiles = @(Get-GitFiles $dir $target $s.sub)
                $oldFiles = @(Get-GitFiles $dir $ext.ref $s.sub)
            } else {
                $newFiles = @(Get-SvnFiles (Get-SvnBase $s $target))
                $oldFiles = @(Get-SvnFiles (Get-SvnBase $s $ext.ref))
            }
            if (-not $newFiles.Count) { throw "$($ext.name): no files at $target" }
            $tracked = @(Get-TrackedFiles $ext.name)
            $keep = @($newFiles | Where-Object { ($tracked -contains $_) -or -not ($oldFiles -contains $_) })
            $added = @($keep | Where-Object { -not ($tracked -contains $_) })
            $removed = @($tracked | Where-Object { -not ($keep -contains $_) })

            $dest = Join-Path $Root "Libs\$($ext.name)"
            foreach ($rel in $removed) { Remove-Item -LiteralPath (Join-Path $dest $rel) -Force }
            $keywords = [System.Collections.Generic.List[string]]::new()
            foreach ($rel in $keep) {
                if ($src.type -eq 'git') {
                    $spec = if ($s.sub) { "${target}:$($s.sub)/$rel" } else { "${target}:$rel" }
                    # A native pipe would decode the bytes as text, so the blob goes through a file.
                    $tmp = Join-Path $work 'blob'
                    $p = Start-Process -FilePath git -ArgumentList @('-C', $dir, 'cat-file', 'blob', $spec) -NoNewWindow -Wait -PassThru -RedirectStandardOutput $tmp
                    if ($p.ExitCode -ne 0) { throw "$($ext.name): cannot read $rel at $target" }
                    $bytes = [System.IO.File]::ReadAllBytes($tmp)
                } else {
                    $bytes = (Invoke-WebRequest -Uri ((Get-SvnBase $s $target) + $rel) -TimeoutSec 30 -UseBasicParsing).RawContentStream.ToArray()
                }
                $out = Join-Path $dest $rel
                New-Item -ItemType Directory -Path (Split-Path $out) -Force | Out-Null
                if ($textExtensions -contains [System.IO.Path]::GetExtension($rel).ToLowerInvariant()) {
                    $text = [System.Text.Encoding]::UTF8.GetString($bytes) -replace "`r`n", "`n"
                    $text = Remove-DoNotPackage $text
                    foreach ($m in [regex]::Matches($text, $keywordPattern)) { $keywords.Add("$rel $($m.Value)") }
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
                }
                [System.IO.File]::WriteAllBytes($out, $bytes)
            }
            Get-ChildItem -LiteralPath $dest -Directory -Recurse | Sort-Object { $_.FullName.Length } -Descending |
                Where-Object { -not (Get-ChildItem -LiteralPath $_.FullName -Force) } | Remove-Item -Force

            $summary = "updated $($ext.name): $(Format-Ref $ext.kind $ext.ref) -> $(Format-Ref $targetKind $target), $($keep.Count) file(s)"
            if ($added.Count) { $summary += ", added: $($added -join ' ')" }
            if ($removed.Count) { $summary += ", removed: $($removed -join ' ')" }
            Out-Line $summary
            foreach ($k in ($keywords | Select-Object -Unique)) { Out-Line "check by hand $($ext.name)/$k (packager keyword not applied here)" }
        }
        Set-Pin @($group | ForEach-Object { $_.path }) $targetKind $target
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-Update {
    $branch = (& git -C $Root branch --show-current 2>$null)
    if ($branch -eq 'main') {
        Out-Line 'FAIL Libs/ is shipped code: run -Update on a feature branch, not main'
        exit 1
    }
    $externals = @(Read-Externals $pkgmeta)
    $groups = Get-PinGroups $externals
    $chosen = [ordered]@{}
    foreach ($n in ($Update | ForEach-Object { $_ -split ',' } | Where-Object { $_ })) {
        $match = @($groups.Keys | Where-Object { @($groups[$_] | Where-Object { $_.name -eq $n -or $_.path -eq $n }).Count })
        if (-not $match.Count) { Out-Line "FAIL no external named $n in .pkgmeta"; exit 1 }
        $chosen[$match[0]] = $groups[$match[0]]
    }
    if ($To -and $chosen.Count -gt 1) { Out-Line 'FAIL -To applies to one pin; name externals that share it'; exit 1 }

    $paths = @('.pkgmeta') + @($chosen.Values | ForEach-Object { $_ } | ForEach-Object { "Libs/$($_.name)" })
    $dirty = (& git -C $Root status --porcelain -- @paths 2>$null)
    if ($dirty) { Out-Line "FAIL uncommitted changes under $($paths -join ' '); commit or stash them first"; exit 1 }

    foreach ($group in $chosen.Values) {
        $ext = $group[0]
        if (-not $ext.kind) { Out-Line "FAIL $($ext.name) has no pin to move"; exit 1 }
        if ($To) {
            $target = $To
            $targetKind = if ($To -match '^[0-9a-f]{40}$') { 'commit' } else { 'tag' }
        } else {
            $answers = Resolve-Upstream $group $false @{} 90
            $key = Get-QueryKey (Get-Source $ext.url) $ext
            if (-not $answers.ContainsKey($key)) { Out-Line "FAIL $($ext.name): upstream unreachable"; exit 1 }
            $target = $answers[$key]
            $targetKind = $ext.kind
        }
        if ($group.Count -gt 1) { Out-Line "moving one pin for $(($group | ForEach-Object { $_.name }) -join ', ')" }
        Update-Group $group $target $targetKind
    }
    # Files without an eol attribute are written LF; under core.autocrlf the
    # index still holds the same content, so only their stat info is stale.
    & git -C $Root update-index -q --refresh *> $null
    Out-Line 'Next: review git diff -- .pkgmeta Libs, commit, /reload smoke, then run the Package check workflow (loaded library files read "match").'
    exit 0
}

if ($Update) { Invoke-Update } else { Invoke-Check }

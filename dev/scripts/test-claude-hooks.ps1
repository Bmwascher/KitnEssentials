# Exercises the tracked Claude Code hook templates (dev/claude-hooks/) and the
# commit-msg git hook against every documented deny and allow case, using a
# throwaway worktree on main so the branch rules can be tested from any branch.
# It also exercises the parsec docs-root scripts (resolver, master registry,
# retention rules) against throwaway projects.
#
#   pwsh dev/scripts/test-claude-hooks.ps1
#
# Exit 1 on any failed case or when a live hook (user or project scope) differs
# from its template. Read-only against the repo: the worktrees, junction,
# branch and scratch folders it creates under $env:TEMP are removed on exit,
# each cleanup step independently of the others.

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$templates = Join-Path $root 'dev\claude-hooks'
$fail = 0
$pass = 0
$skip = 0

function Invoke-Hook([string]$script, [hashtable]$payload) {
    $json = $payload | ConvertTo-Json -Compress -Depth 5
    $out = $json | pwsh -NoProfile -NonInteractive -File $script 2>&1 | Out-String
    return @{ out = $out; code = $LASTEXITCODE }
}

function Check([string]$name, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:pass++ } else { $script:fail++; Write-Host ("FAIL  {0}  {1}" -f $name, $detail) }
}

function Expect-Deny([string]$hook, [string]$name, [hashtable]$payload) {
    $r = Invoke-Hook (Join-Path $templates $hook) $payload
    Check "$hook deny: $name" ($r.out -match '"permissionDecision":"deny"') $r.out.Trim()
}
function Expect-Allow([string]$hook, [string]$name, [hashtable]$payload) {
    $r = Invoke-Hook (Join-Path $templates $hook) $payload
    Check "$hook allow: $name" ($r.out.Trim() -eq '' -and $r.code -eq 0) $r.out.Trim()
}

# Live copies must exist and match the templates (the installer refreshes them). Line
# endings are ignored: git renormalizes the tracked templates to CRLF.
function Get-TextHash([string]$path) {
    $text = [System.IO.File]::ReadAllText($path) -replace "`r", ''
    $sha = [System.Security.Cryptography.SHA256]::Create()
    return [System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($text)))
}
# The project-scope hooks and the .agents mirror are gitignored, so they exist
# only in the primary checkout, the first worktree git lists.
$primary = $root
$wtList = @(git -C $root worktree list --porcelain 2>$null | Where-Object { $_ -like 'worktree *' })
if ($LASTEXITCODE -eq 0 -and $wtList.Count) { $primary = [System.IO.Path]::GetFullPath($wtList[0].Substring(9)) }
$liveDir = @{ user = (Join-Path $env:USERPROFILE '.claude\hooks'); project = (Join-Path $primary '.claude\hooks') }
foreach ($n in @('branch-guard.ps1', 'git-guard.ps1', 'luacheck-postedit.ps1', 'agents-mirror-sync.ps1', 'references-check.ps1', 'lib-update-check.ps1', 'program-recovery.ps1')) {
    $scope = if ($n -in @('agents-mirror-sync.ps1', 'references-check.ps1', 'lib-update-check.ps1', 'program-recovery.ps1')) { 'project' } else { 'user' }
    $other = if ($scope -eq 'user') { 'project' } else { 'user' }
    $live = Join-Path $liveDir[$scope] $n
    Check "$n has no stale copy in $other scope" (-not (Test-Path (Join-Path $liveDir[$other] $n))) 'run pwsh dev/scripts/install-claude-hooks.ps1'
    $same = (Test-Path $live) -and ((Get-TextHash $live) -eq (Get-TextHash (Join-Path $templates $n)))
    Check "live == template: $n" $same 'run pwsh dev/scripts/install-claude-hooks.ps1'
}

# The live .agents mirror must match its sources (both trees are gitignored,
# so a fresh checkout fails here until the sync script has run once).
& pwsh -NoProfile -File (Join-Path $primary 'dev\scripts\sync-agents-mirror.ps1') -Check *> $null
Check 'agents mirror in sync' ($LASTEXITCODE -eq 0) 'run pwsh dev/scripts/sync-agents-mirror.ps1'

$tag = [System.IO.Path]::GetRandomFileName().Replace('.', '')
$wt = Join-Path $env:TEMP "ke-hooktest-$tag"
$link = "$wt-link"
$feature = "$wt-feature"
$featureBranch = "hooktest/$tag"
$outside = "$wt-outside"
try {
    # --force: the primary usually has main checked out. The branch rules need
    # a checkout on main, not a detached one, and this checkout never commits.
    git -C $root worktree add --force -q $wt main 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "could not add a worktree on main" }
    New-Item -ItemType Junction -Path $link -Target $wt | Out-Null
    New-Item -ItemType Directory -Path $outside | Out-Null
    git -C $root worktree add -q -b $featureBranch $feature main 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "could not add the feature worktree" }
    if ((git -C $feature branch --show-current).Trim() -ne $featureBranch) { throw "feature worktree is not on $featureBranch" }
    $short = (New-Object -ComObject Scripting.FileSystemObject).GetFolder($wt).ShortPath
    $fwd = ($wt -replace '\\', '/')
    $fwd = $fwd.Substring(0, 1).ToLower() + $fwd.Substring(1)

    # --- branch-guard ---------------------------------------------------------
    $bg = 'branch-guard.ps1'
    $edit = { param($f, $cwd) @{ tool_name = 'Edit'; cwd = $cwd; tool_input = @{ file_path = $f } } }
    Expect-Deny  $bg 'absolute path'            (& $edit "$wt\Core\Globals.lua" $wt)
    Expect-Deny  $bg 'forward slashes'          (& $edit "$fwd/Modules/QoL/QoL.xml" $wt)
    Expect-Deny  $bg 'relative path'            (& $edit 'Core/Globals.lua' $wt)
    if ($short -ne $wt) { Expect-Deny $bg '8.3 short path' (& $edit "$short\Core\Globals.lua" $wt) } else { $skip++ }
    Expect-Deny  $bg 'junction path'            (& $edit "$link\Core\Globals.lua" $wt)
    Expect-Deny  $bg 'relative under junction'  (& $edit 'Core/Globals.lua' $link)
    Expect-Deny  $bg 'new file in a new folder' (& $edit "$wt\Modules\NewFeature\New.lua" $wt)
    Expect-Deny  $bg 'new folder under junction' (& $edit "$link\Modules\NewFeature\New.lua" $wt)
    Expect-Allow $bg 'dev/ exempt'              (& $edit "$wt\dev\spec\x_spec.lua" $wt)
    Expect-Allow $bg 'new file under dev/'      (& $edit "$wt\dev\newdir\x.lua" $wt)
    Expect-Allow $bg '.claude/ exempt'          (& $edit "$wt\.claude\x.lua" $wt)
    Expect-Allow $bg '.toc exempt'              (& $edit "$wt\KitnEssentials.toc" $wt)
    Expect-Allow $bg 'feature branch checkout'  (& $edit "$feature\Core\Globals.lua" $feature)
    Expect-Allow $bg 'outside any repo (existing dir)' (& $edit "$outside\x.lua" $wt)
    Expect-Allow $bg 'outside any repo (missing dir)'  (& $edit "$outside\nope\x.lua" $wt)
    Expect-Allow $bg 'no file_path'             @{ tool_name = 'Edit'; cwd = $wt; tool_input = @{} }

    # --- git-guard ------------------------------------------------------------
    $gg = 'git-guard.ps1'
    $sh = { param($c, $cwd, $tool = 'Bash') @{ tool_name = $tool; cwd = $cwd; tool_input = @{ command = $c } } }
    $deny = @(
        'git checkout -- Core/Globals.lua', 'git checkout .', 'git checkout main -- Core/Globals.lua',
        'git checkout -f main', 'git checkout -fq main', 'git checkout --pathspec-from-file=paths.txt',
        'git restore Core/Globals.lua', 'git restore --worktree --staged Core/Globals.lua',
        'git add -A', 'git add --all', 'git add .', 'git add -u', 'git add -- .', 'git add -Av',
        'git add *', 'git add "."', 'git add :/', 'git add -- :/*', 'git add -- ./*', 'git add -- **', 'git add -- :(top)**',
        'git restore --staged X && git add -A', 'git -C C:/x add -A', 'git -C "C:/some dir" add -A',
        'git --no-pager add -A', 'git -c core.autocrlf=false add -A', 'git --work-tree . reset --hard HEAD',
        'git --git-dir .git reset --hard', 'git -P reset --hard HEAD',
        'git commit -a -m x', 'git commit -am x', 'git commit --all -m x',
        'git switch -f main', 'git switch -fq main', 'git switch --discard-changes main',
        'git reset --hard HEAD~1', 'git clean -fd', 'git stash drop', 'git stash clear',
        'sed -i s/a/b/ Core/Globals.lua', "sed -i 's/a/b/' Modules/QoL/QoL.xml", 'sed -i s/a/b/ "Core/Globals.lua"',
        'cat > Core/Globals.lua', 'echo x > "Core/Globals.lua"', 'echo x >> GUI/GUIMain/GUI-Main.lua',
        'tee Core/Globals.lua', 'tee "Core/Globals.lua"', "sed -i s/a/b/ $wt\Core\Globals.lua",
        "sed -i s/a/b/ $link\Core\Globals.lua", 'cd dev && sed -i s/a/b/ ..\Core\Globals.lua',
        'cd Modules; echo x > QoL/QoL.xml', 'sed -i s/a/b/ Modules/NewFeature/New.lua',
        "git -c 'core.editor=code --wait' reset --hard HEAD", 'git -c "core.editor=code --wait" reset --hard HEAD',
        "git add -- ':(top,glob)**'", 'git add -- ":(glob)**"', 'git add ":(top)"',
        'pushd dev; popd; sed -i s/a/b/ Core/Globals.lua', 'cd $SOMEWHERE && sed -i s/a/b/ Core/Globals.lua',
        'cd - && echo x > Core/Globals.lua', 'popd; sed -i s/a/b/ Core/Globals.lua',
        'git --work-tree="C:/path with spaces" reset --hard HEAD', "git --git-dir='C:/p q/.git' reset --hard",
        'git commit -aSmain', "git add -- ':(glob)**/*'", "git add -- '**/*'", 'git add -- */',
        "cd `$X; cd $wt; sed -i s/a/b/ Core/Globals.lua",
        "git '--work-tree=C:/path with spaces' reset --hard HEAD", 'git "--work-tree=C:/path with spaces" reset --hard HEAD'
    )
    Expect-Deny $gg 'whole-quoted option (PowerShell)' (& $sh "git '--work-tree=C:/path with spaces' reset --hard HEAD" $wt 'PowerShell')
    foreach ($c in $deny) { Expect-Deny $gg $c (& $sh $c $wt) }
    Expect-Deny $gg 'relative write, cwd = junction' (& $sh 'sed -i s/a/b/ Core/Globals.lua' $link)
    Expect-Deny $gg 'Set-Content (PowerShell)'  (& $sh 'Set-Content Core/Globals.lua x' $wt 'PowerShell')
    Expect-Deny $gg 'Set-Content -Path quoted'  (& $sh 'Set-Content -Path "Core/Globals.lua" -Value x' $wt 'PowerShell')
    Expect-Deny $gg 'Out-File (PowerShell)'     (& $sh "'x' | Out-File -Path Core/Globals.lua" $wt 'PowerShell')
    Expect-Deny $gg 'Add-Content (PowerShell)'  (& $sh 'Add-Content -LiteralPath Core/Globals.lua y' $wt 'PowerShell')
    Expect-Deny $gg 'Tee-Object (PowerShell)'   (& $sh "'x' | Tee-Object -FilePath Core/Globals.lua" $wt 'PowerShell')
    Expect-Deny $gg 'Set-Location then write'   (& $sh 'Set-Location Modules; Set-Content QoL/QoL.xml x' $wt 'PowerShell')
    $allow = @(
        'git add Core/Globals.lua CHANGELOG.md', 'git add :/Core/Globals.lua', 'git restore --staged Core/Globals.lua',
        'git checkout feature/x', 'git checkout -b feature/x', 'git switch -c feature/x', 'git switch --force-create feature/x',
        'git switch main', 'git stash', 'git stash pop', 'git reset --soft HEAD~1', 'git reset Core/Globals.lua',
        'git clean -n', 'git clean -fdn', 'git commit -m "add a thing"', 'git commit --amend -m x', 'git commit -m "-a"',
        'git add Modules/', 'sed -i s/a/b/ dev/spec/x_spec.lua', 'cd dev && sed -i s/a/b/ spec/x_spec.lua',
        'echo x > CHANGELOG.md', 'sed -n 1,5p Core/Globals.lua', 'grep -n foo Core/Globals.lua > out.txt',
        "sed -i s/a/b/ $outside\probe.lua", 'luacheck Core/Globals.lua > /dev/null 2>&1', 'git status', 'git log -3', 'ls Core',
        'git commit -mupdate', 'git commit -Cmain', 'git commit -F msg.txt', 'git add ":(glob)Core/*.lua"',
        'pushd dev; sed -i s/a/b/ spec/x_spec.lua; popd', 'pushd Modules; popd; sed -i s/a/b/ dev/spec/x_spec.lua',
        "cd `$SOMEWHERE && sed -i s/a/b/ $outside\probe.lua",
        'git commit -Smain', 'git commit -S -m x', "pushd `$SOMEWHERE; popd; sed -i s/a/b/ dev/spec/x_spec.lua",
        "cd `$X; cd $wt\dev; sed -i s/a/b/ spec/x_spec.lua", 'git add -- ":(glob)Core/**/*.lua"'
    )
    foreach ($c in $allow) { Expect-Allow $gg $c (& $sh $c $wt) }
    # Shell writes are only denied while the target's checkout is on main.
    Expect-Allow $gg 'sed -i on a feature branch' (& $sh 'sed -i s/a/b/ Core/Globals.lua' $feature)
    Expect-Allow $gg 'absolute write into a feature checkout, cwd on main' (& $sh "sed -i s/a/b/ $feature\Core\Globals.lua" $wt)

    # --- luacheck-postedit ----------------------------------------------------
    $lc = 'luacheck-postedit.ps1'
    $probe = Join-Path $wt 'dev\_hooktest_probe.lua'
    Set-Content -Path $probe -Value 'local unused = 1' -NoNewline
    $cases = @(@("$wt\dev\_hooktest_probe.lua", $wt), @('dev/_hooktest_probe.lua', $wt), @("$link\dev\_hooktest_probe.lua", $wt))
    if ($short -ne $wt) { $cases += , @("$short\dev\_hooktest_probe.lua", $wt) } else { $skip++ }
    foreach ($case in $cases) {
        $r = Invoke-Hook (Join-Path $templates $lc) (& $edit $case[0] $case[1])
        Check "$lc warns: $($case[0])" ($r.code -eq 2 -and $r.out -match "unused variable 'unused'") $r.out.Trim()
    }
    Set-Content -Path $probe -Value 'return nil' -NoNewline
    $r = Invoke-Hook (Join-Path $templates $lc) (& $edit "$wt\dev\_hooktest_probe.lua" $wt)
    Check "$lc clean file is silent" ($r.code -eq 0 -and $r.out.Trim() -eq '') $r.out.Trim()
    $r = Invoke-Hook (Join-Path $templates $lc) (& $edit "$wt\README.md" $wt)
    Check "$lc non-lua is silent" ($r.code -eq 0 -and $r.out.Trim() -eq '') $r.out.Trim()
    Remove-Item $probe -Force

    # --- commit-msg (bash) ----------------------------------------------------
    $bash = (Get-Command bash -ErrorAction SilentlyContinue).Source
    if ($bash) {
        $msgFile = Join-Path $env:TEMP "ke-hooktest-$tag-msg.txt"
        $hook = (Join-Path $root 'dev\githooks\commit-msg') -replace '\\', '/'
        # Runs in the throwaway worktree on main: a release subject is checked
        # against the staged .toc version, so the caller's index must not decide it.
        $cm = { param($name, $msg, $expect)
            [System.IO.File]::WriteAllText($msgFile, $msg)
            Push-Location $wt
            try { & $bash $hook $msgFile 2>&1 | Out-Null; $code_ = $LASTEXITCODE } finally { Pop-Location }
            Check "commit-msg $expect`: $name" ($code_ -eq $(if ($expect -eq 'block') { 1 } else { 0 }))
        }
        $tocVer = @((git -C $wt show :KitnEssentials.toc) -match '^## X-Manual-Version:' | ForEach-Object { ($_ -split '\s+')[2] })[0]
        $verOk = "$tocVer" -match '^(\d+)\.(\d+)\.(\d+)$'
        Check 'commit-msg: .toc version read for the release cases' $verOk "got '$tocVer'"
        $otherVer = if ($verOk) { '{0}.{1}.{2}' -f $Matches[1], $Matches[2], ([int]$Matches[3] + 1) } else { '' }
        & $cm 'upstream name'               "port the tracker from norsken`n"                       'block'
        & $cm 'Co-Authored-By'              "fix a thing`n`nCo-Authored-By: Claude <x>`n"            'block'
        & $cm 'indented trailer'            "fix`n`n  Co-Authored-By: Claude`n"                       'block'
        & $cm 'Generated with Claude Code'  "fix a thing`n`nGenerated with Claude Code`n"             'block'
        & $cm 'Signed-off-by agent'         "fix a thing`n`nSigned-off-by: Codex`n"                   'block'
        & $cm 'uppercase subject'           "Fix the show target toggle`n"                            'block'
        & $cm 'default merge subject'       "Merge branch 'codex/x'`n"                                'block'
        & $cm 'clean'                       "fix the show target toggle`n"                            'pass'
        # The matching release pass case also needs a staged LAST_RELEASE, so it
        # runs with the LAST_RELEASE cases in the feature worktree below.
        & $cm 'release version not in .toc' "v$otherVer`: fix a thing`n"                              'block'
        & $cm 'human sign-off'              "fix`n`nSigned-off-by: Brandon Wascher <x>`n"             'pass'
        & $cm 'comment lines before subject' "# editor comment`nfix a thing`n"                        'pass'
        & $cm 'blank lines before subject'  "`n`nfix a thing`n"                                       'pass'
        & $cm 'compat name alone'           "skin the elvui bags`n"                                   'pass'

        # --- commit-msg LAST_RELEASE cases, staged in the feature worktree ----
        # A stand-in VersionCheck.lua committed on the throwaway branch holds an
        # untagged HEAD value, so the cases do not depend on what main holds and
        # show that HEAD's value grants nothing.
        $vcRel = 'Modules/Core/VersionCheck.lua'
        $vcAbs = Join-Path $feature ($vcRel -replace '/', '\')
        $tocAbs = Join-Path $feature 'KitnEssentials.toc'
        $tocText = [System.IO.File]::ReadAllText($tocAbs)
        $lastTag = "$(git -C $feature describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' 2>$null)" -replace '^v', ''
        Check 'commit-msg: latest release tag read for the LAST_RELEASE cases' ($lastTag -match '^\d+\.\d+\.\d+$') "got '$lastTag'"
        New-Item -ItemType Directory -Path (Split-Path $vcAbs) -Force | Out-Null
        [System.IO.File]::WriteAllText($vcAbs, "local LAST_RELEASE = `"0.0.1`"`n")
        git -C $feature add -- $vcRel 2>&1 | Out-Null
        git -C $feature commit -q --no-verify -m 'hooktest stand-in' 2>&1 | Out-Null
        $lr = { param($name, $msg, $value, $tocVer, $expect)
            [System.IO.File]::WriteAllText($vcAbs, "local LAST_RELEASE = `"$value`"`n")
            git -C $feature add -- $vcRel 2>&1 | Out-Null
            if ($tocVer) {
                [System.IO.File]::WriteAllText($tocAbs, ($tocText -replace '(?m)^## X-Manual-Version: [^\r\n]*', "## X-Manual-Version: $tocVer"))
                git -C $feature add -- KitnEssentials.toc 2>&1 | Out-Null
            }
            [System.IO.File]::WriteAllText($msgFile, $msg)
            Push-Location $feature
            try { & $bash $hook $msgFile 2>&1 | Out-Null; $code_ = $LASTEXITCODE } finally { Pop-Location }
            Check "commit-msg $expect`: $name" ($code_ -eq $(if ($expect -eq 'block') { 1 } else { 0 }))
            git -C $feature reset -q -- $vcRel KitnEssentials.toc 2>&1 | Out-Null
            git -C $feature checkout -q -- $vcRel KitnEssentials.toc 2>&1 | Out-Null
        }
        & $lr 'LAST_RELEASE that is not the latest tag, carried from HEAD' "fix a thing`n" '0.0.1' $null 'block'
        & $lr 'LAST_RELEASE set to the latest tag'        "fix a thing`n"          $lastTag $null   'pass'
        & $lr 'release commit with matching LAST_RELEASE' "v9.8.7: fix a thing`n"  '9.8.7'  '9.8.7' 'pass'
        & $lr 'release commit with stale LAST_RELEASE'    "v9.8.7: fix a thing`n"  '0.0.1'  '9.8.7' 'block'
        Remove-Item $msgFile -Force -ErrorAction SilentlyContinue

        # --- pre-commit (bash), staged in the feature worktree -----------------
        $pc = (Join-Path $root 'dev\githooks\pre-commit') -replace '\\', '/'
        $probeRel = 'Modules/QoL/_hooktest_probe.lua'
        $probeAbs = Join-Path $feature ($probeRel -replace '/', '\')
        $stubAbs = Join-Path $feature 'dev\Annotations\KE.lua'
        $stage = { param($name, $code, $expect, $stubLine = $null, $rel = $probeRel)
            $abs = Join-Path $feature ($rel -replace '/', '\')
            [System.IO.File]::WriteAllText($abs, $code)
            git -C $feature add -- $rel 2>&1 | Out-Null
            if ($stubLine) {
                [System.IO.File]::AppendAllText($stubAbs, "`n$stubLine`n")
                git -C $feature add -- dev/Annotations/KE.lua 2>&1 | Out-Null
            }
            Push-Location $feature
            try { & $bash $pc 2>&1 | Out-Null; $code_ = $LASTEXITCODE } finally { Pop-Location }
            Check "pre-commit $expect`: $name" ($code_ -eq $(if ($expect -eq 'block') { 1 } else { 0 }))
            git -C $feature reset -q -- $rel dev/Annotations/KE.lua 2>&1 | Out-Null
            git -C $feature checkout -q -- dev/Annotations/KE.lua 2>&1 | Out-Null
            Remove-Item $abs -Force -ErrorAction SilentlyContinue
        }
        & $stage 'restricted combat log event'      "local f = CreateFrame('Frame')`nf:RegisterEvent('COMBAT_LOG_EVENT_UNFILTERED')`n" 'block'
        & $stage 'restricted combat log accessor'   "local a = CombatLogGetCurrentEventInfo()`n" 'block'
        & $stage 'AceEvent RegisterUnitEvent'       "local M = {}`nfunction M:OnEnable() self:RegisterUnitEvent('UNIT_AURA', 'player') end`n" 'block'
        & $stage 'restricted name in a comment'     "-- CLEU-free: COMBAT_LOG_EVENT_UNFILTERED is restricted`nlocal x = 1`n" 'pass'
        & $stage 'frame RegisterUnitEvent'          "local f = CreateFrame('Frame')`nf:RegisterUnitEvent('UNIT_AURA', 'player')`n" 'pass'
        & $stage 'restricted name inside a string'  "local s = `"CombatLogGetCurrentEventInfo()`"`n" 'pass'
        & $stage 'string holding -- then a restricted call' "local m = `"--`"; local a = CombatLogGetCurrentEventInfo()`n" 'block'
        & $stage 'leveled long string holding -- then a restricted call' "local m = [=[--]=]; local a = CombatLogGetCurrentEventInfo()`n" 'block'
        & $stage 'restricted name inside a leveled long string' "local s = [==[CombatLogGetCurrentEventInfo()]==]`n" 'pass'
        & $stage 'new KE: method without a stub'    "function KE:HookTestProbe(a) return a end`n" 'block'
        & $stage 'new KE. function without a stub'  "function KE.HookTestProbe(a) return a end`n" 'block'
        & $stage 'new KE. assignment without a stub' "KE.HookTestProbe = function(a) return a end`n" 'block'
        & $stage 'new KE: method with a staged stub' "function KE:HookTestProbe(a) return a end`n" 'pass' "---@param a any`n---@return any`nfunction KE:HookTestProbe(a) end"
        & $stage 'plain code'                       "local x = 1`nreturn x`n" 'pass'
        & $stage 'short name in a comment'          "-- matches the nui layout`nlocal x = 1`n" 'block'
        & $stage 'origin vocabulary in a dev-script comment' "-- copied from the upstream tool`nlocal x = 1`n" 'block' $null 'dev/scripts/_hooktest_probe.lua'
        & $stage 'date in a dev-script comment'     "-- probed 2026-10-23 against the live client`nlocal x = 1`n" 'pass' $null 'dev/scripts/_hooktest_probe.lua'
        # A staged deletion of the stub file must block a new method outright.
        git -C $feature rm -q --cached dev/Annotations/KE.lua 2>&1 | Out-Null
        [System.IO.File]::WriteAllText($probeAbs, "function KE:HookTestProbe(a) return a end`n")
        git -C $feature add -- $probeRel 2>&1 | Out-Null
        Push-Location $feature
        try { & $bash $pc 2>&1 | Out-Null; $code_ = $LASTEXITCODE } finally { Pop-Location }
        Check 'pre-commit block: new method with the stub file deleted from the index' ($code_ -eq 1)
        git -C $feature reset -q -- dev/Annotations/KE.lua $probeRel 2>&1 | Out-Null
        Remove-Item $probeAbs -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host 'commit-msg and pre-commit cases skipped: bash not on PATH'
    }

    # The sync hook, against a throwaway project: it must rebuild the mirror
    # only after an edit under the skill or command folders. The effect is
    # observed on disk, since the hook is silent either way.
    $ms = 'agents-mirror-sync.ps1'
    $proj = Join-Path $outside 'proj'
    foreach ($d in @('.claude\skills\demo', '.claude\commands', 'dev\scripts')) { New-Item -ItemType Directory -Path (Join-Path $proj $d) -Force | Out-Null }
    [System.IO.File]::WriteAllText((Join-Path $proj '.claude\skills\demo\SKILL.md'), "---`nname: demo`n---`nbody`n")
    [System.IO.File]::WriteAllText((Join-Path $proj '.claude\commands\demo.md'), "---`ndescription: demo command`n---`nrun it`n")
    Copy-Item (Join-Path $root 'dev\scripts\sync-agents-mirror.ps1') (Join-Path $proj 'dev\scripts\')
    $mirror = Join-Path $proj '.agents\skills'
    $msPayload = { param($f, $cwd) @{ tool_name = 'Edit'; cwd = $cwd; tool_input = @{ file_path = $f } } }
    $savedProjectDir = $env:CLAUDE_PROJECT_DIR
    $env:CLAUDE_PROJECT_DIR = $proj
    try {
        $r = Invoke-Hook (Join-Path $templates $ms) (& $msPayload (Join-Path $proj 'Core\Globals.lua') $proj)
        Check "$ms ignores a non-skill edit" ($r.code -eq 0 -and $r.out.Trim() -eq '' -and -not (Test-Path $mirror)) $r.out.Trim()
        $r = Invoke-Hook (Join-Path $templates $ms) (& $msPayload (Join-Path $proj '.claude\commands\demo.md') $proj)
        Check "$ms mirrors a command edit" ($r.code -eq 0 -and $r.out.Trim() -eq '' -and (Test-Path (Join-Path $mirror 'source-command-demo\SKILL.md'))) $r.out.Trim()
        Remove-Item $mirror -Recurse -Force
        $r = Invoke-Hook (Join-Path $templates $ms) (& $msPayload '.claude\skills\demo\SKILL.md' $proj)
        Check "$ms resolves a relative skill path against cwd" ($r.code -eq 0 -and (Test-Path (Join-Path $mirror 'demo\SKILL.md'))) $r.out.Trim()
        [System.IO.File]::WriteAllText((Join-Path $mirror 'stray.txt'), 'x')
        & pwsh -NoProfile -File (Join-Path $proj 'dev\scripts\sync-agents-mirror.ps1') -Check *> $null
        Check 'sync -Check reports a stray mirror file' ($LASTEXITCODE -eq 1)
    } finally {
        $env:CLAUDE_PROJECT_DIR = $savedProjectDir
    }

    # The compaction hook prints the recovery card only in a session the
    # master registry names, and only for the compact source.
    $pr = 'program-recovery.ps1'
    $pproj = Join-Path $outside 'pproj'
    foreach ($d in @('.claude\skills\phased-program', 'dev\scripts', 'dev\docs\parsec\programs\2026-01-01-demo')) { New-Item -ItemType Directory -Path (Join-Path $pproj $d) -Force | Out-Null }
    foreach ($s in @('program-master.ps1', 'parsec-docs-root.ps1')) { Copy-Item (Join-Path $root "dev\scripts\$s") (Join-Path $pproj 'dev\scripts\') }
    [System.IO.File]::WriteAllText((Join-Path $pproj '.claude\skills\phased-program\recovery-card.md'), "CARD LINE`n")
    $pdoc = Join-Path $pproj 'dev\docs\parsec\programs\2026-01-01-demo\program.md'
    [System.IO.File]::WriteAllText($pdoc, "# p`n`n## Open questions`n`nOQ ROW`n`n---`n`n## Status`n`nSTATUS ROW`n`n---`n`n## At the end`n`nTAIL ROW`n")
    $saved = @{ dir = $env:CLAUDE_PROJECT_DIR; reg = $env:KE_PROGRAM_MASTERS; sid = $env:CLAUDE_CODE_SESSION_ID; hid = $env:CLAUDE_CODE_HOST_SESSION_ID }
    $env:CLAUDE_PROJECT_DIR = $pproj
    $env:KE_PROGRAM_MASTERS = Join-Path $pproj 'dev\docs\parsec\programs\active-masters.tsv'
    $env:CLAUDE_CODE_HOST_SESSION_ID = "hooktest-host-$tag"
    try {
        $env:CLAUDE_CODE_SESSION_ID = "hooktest-master-$tag"
        & pwsh -NoProfile -File (Join-Path $pproj 'dev\scripts\program-master.ps1') -Register $pdoc *> $null
        $env:CLAUDE_CODE_SESSION_ID = ''
        $env:CLAUDE_CODE_HOST_SESSION_ID = "hooktest-other-$tag"
        $r = Invoke-Hook (Join-Path $templates $pr) @{ session_id = "hooktest-other-$tag"; source = 'compact' }
        Check "$pr is silent outside a master" ($r.code -eq 0 -and $r.out.Trim() -eq '') $r.out.Trim()
        $r = Invoke-Hook (Join-Path $templates $pr) @{ session_id = "hooktest-master-$tag"; source = 'startup' }
        Check "$pr is silent for a non-compact source" ($r.code -eq 0 -and $r.out.Trim() -eq '') $r.out.Trim()
        $r = Invoke-Hook (Join-Path $templates $pr) @{ session_id = "hooktest-master-$tag"; source = 'compact' }
        $ok = $r.code -eq 0 -and $r.out -match 'CARD LINE' -and $r.out -match 'OQ ROW' -and $r.out -match 'STATUS ROW' -and $r.out -notmatch 'TAIL ROW'
        Check "$pr prints the card and both sections in a master" $ok $r.out.Trim()
        $env:CLAUDE_CODE_HOST_SESSION_ID = "hooktest-host-$tag"
        $r = Invoke-Hook (Join-Path $templates $pr) @{ session_id = 'resumed-new-id'; source = 'compact' }
        Check "$pr matches a master by its host id" ($r.out -match 'CARD LINE') $r.out.Trim()
        $events = Join-Path $pproj 'dev\docs\parsec\programs\2026-01-01-demo\program-events.log'
        Check "$pr logs one compact event per recovery" ((Test-Path $events) -and @(Get-Content $events | Where-Object { $_ -match "`tcompact$" }).Count -eq 2)
    } finally {
        $env:CLAUDE_PROJECT_DIR = $saved.dir; $env:KE_PROGRAM_MASTERS = $saved.reg
        $env:CLAUDE_CODE_SESSION_ID = $saved.sid; $env:CLAUDE_CODE_HOST_SESSION_ID = $saved.hid
    }
    # The docs-root resolver: the primary's config, absolute or relative, else
    # the fallback; an unreadable value is an error, never the fallback.
    $rr = Join-Path $root 'dev\scripts\parsec-docs-root.ps1'
    $rproj0 = Join-Path $outside 'resolve'
    New-Item -ItemType Directory -Path (Join-Path $rproj0 '.claude') -Force | Out-Null
    $tomlPath = Join-Path $rproj0 '.claude\parsec.toml'
    $abs = Join-Path $outside 'elsewhere'
    $resolveCases = @(
        @{ name = 'relative value'; toml = "docs_root = `"docs/here`"`n"; want = (Join-Path $rproj0 'docs\here'); code = 0 },
        @{ name = 'absolute value'; toml = "docs_root = `"$($abs -replace '\\', '/')`"`n"; want = $abs; code = 0 },
        @{ name = 'no docs_root line'; toml = "worktrees = `"x`"`n"; want = (Join-Path $rproj0 'dev\docs\parsec'); code = 0 },
        @{ name = 'no config'; toml = $null; want = (Join-Path $rproj0 'dev\docs\parsec'); code = 0 },
        @{ name = 'unreadable value'; toml = "docs_root = 'single'`n"; want = $null; code = 1 }
    )
    foreach ($c in $resolveCases) {
        Remove-Item $tomlPath -Force -ErrorAction SilentlyContinue
        if ($null -ne $c.toml) { [System.IO.File]::WriteAllText($tomlPath, $c.toml) }
        $out = (& pwsh -NoProfile -File $rr -Root $rproj0 2>$null | Out-String).Trim()
        $code = $LASTEXITCODE
        Check "parsec-docs-root: $($c.name)" ($code -eq $c.code -and ($null -eq $c.want -or $out -eq $c.want)) "exit $code, $out"
    }
    $fromWt = (& pwsh -NoProfile -File $rr -Root $wt | Out-String).Trim()
    $codeWt = $LASTEXITCODE
    $fromRoot = (& pwsh -NoProfile -File $rr -Root $root | Out-String).Trim()
    $codeRoot = $LASTEXITCODE
    Check 'parsec-docs-root: a worktree reads the primary''s config' ($codeWt -eq 0 -and $codeRoot -eq 0 -and $fromWt -ne '' -and $fromWt -eq $fromRoot) "exit $codeWt/$codeRoot, $fromWt vs $fromRoot"
    # The master registry lives under the docs root; a missing root refuses
    # -Register and -Unregister and keeps -LogEvent and -Recover quiet.
    $mproj = Join-Path $outside 'mproj'
    foreach ($d in @('.claude', 'dev\scripts')) { New-Item -ItemType Directory -Path (Join-Path $mproj $d) -Force | Out-Null }
    foreach ($s in @('program-master.ps1', 'parsec-docs-root.ps1')) { Copy-Item (Join-Path $root "dev\scripts\$s") (Join-Path $mproj 'dev\scripts\') }
    $mdocs = Join-Path $outside 'mdocs'
    $mdoc = Join-Path $outside 'mprog\program.md'
    New-Item -ItemType Directory -Path (Split-Path $mdoc -Parent) -Force | Out-Null
    [System.IO.File]::WriteAllText($mdoc, "# m`n")
    [System.IO.File]::WriteAllText((Join-Path $mproj '.claude\parsec.toml'), "docs_root = `"$($mdocs -replace '\\', '/')`"`n")
    $mpm = Join-Path $mproj 'dev\scripts\program-master.ps1'
    $msaved = @{ reg = $env:KE_PROGRAM_MASTERS; sid = $env:CLAUDE_CODE_SESSION_ID; hid = $env:CLAUDE_CODE_HOST_SESSION_ID }
    $env:KE_PROGRAM_MASTERS = ''
    $env:CLAUDE_CODE_SESSION_ID = "hooktest-mreg-$tag"
    $env:CLAUDE_CODE_HOST_SESSION_ID = ''
    try {
        $missingCases = @(
            @{ name = '-Register refuses a missing docs root'; args = @('-Register', $mdoc); code = 1; out = '' },
            @{ name = '-Unregister refuses a missing docs root'; args = @('-Unregister'); code = 1; out = 'does not exist' },
            @{ name = '-LogEvent notes a missing docs root and exits 0'; args = @('-LogEvent', 'x'); code = 0; out = 'does not exist' },
            @{ name = '-Recover is silent with a missing docs root'; args = @('-Recover'); code = 0; out = '^$' }
        )
        foreach ($c in $missingCases) {
            $o = (& pwsh -NoProfile -File $mpm @($c.args) 2>&1 | Out-String).Trim()
            $code = $LASTEXITCODE
            Check "program-master: $($c.name)" ($code -eq $c.code -and $o -match $c.out -and -not (Test-Path $mdocs)) "exit $code, $o"
        }
        New-Item -ItemType Directory -Path $mdocs | Out-Null
        & pwsh -NoProfile -File $mpm -Register $mdoc *> $null
        $regCode = $LASTEXITCODE
        $reg = Join-Path $mdocs 'programs\active-masters.tsv'
        $line = if (Test-Path $reg) { (Get-Content $reg -Raw) } else { '' }
        Check 'program-master: a control document outside the checkout is registered by its absolute path' ($regCode -eq 0 -and $line -match [regex]::Escape(($mdoc -replace '\\', '/'))) "exit $regCode, $line"
    } finally {
        $env:KE_PROGRAM_MASTERS = $msaved.reg; $env:CLAUDE_CODE_SESSION_ID = $msaved.sid; $env:CLAUDE_CODE_HOST_SESSION_ID = $msaved.hid
    }
    # The retention rules for the parsec docs root, against a throwaway project
    # whose docs root sits outside it. The project is no git repository, so the
    # same runs show the docs-root rules running when git fails.
    $rproj = Join-Path $outside 'rproj'
    $rdocs = Join-Path $outside 'rdocs'
    $rarch = Join-Path $outside '_archive\KitnEssentials-process'
    foreach ($d in @('.claude', 'dev\scripts', 'dev\docs')) { New-Item -ItemType Directory -Path (Join-Path $rproj $d) -Force | Out-Null }
    foreach ($s in @('check-artifact-retention.ps1', 'parsec-docs-root.ps1')) { Copy-Item (Join-Path $root "dev\scripts\$s") (Join-Path $rproj 'dev\scripts\') }
    [System.IO.File]::WriteAllText((Join-Path $rproj '.claude\parsec.toml'), "docs_root = `"$($rdocs -replace '\\', '/')`"`n")
    $keepLines = @(
        'docs:01-09-kept|until:2099-01-01|fixture',
        'docs:01-17-kept-member|until:2099-01-01|fixture',
        'docs:01-12-nofinish.|until:2099-01-01|fixture',
        'dev/docs/parsec/01-01-x|until:2099-01-01|fixture'
    )
    [System.IO.File]::WriteAllText((Join-Path $rproj 'dev\docs\retention-keep.txt'), ($keepLines -join "`n") + "`n")
    $head = "# F (2026)`ntopic: f   branch: f   base: 1`n"
    $merged = "$head- 2026-01-01 10:00 -0500 finish: merged abc1234`n"
    $fixture = [ordered]@{
        '01-01-merged-template\ledger.md' = "$head- 2026-01-01 10:00 -0500 finish: stop and report`n- 2026-01-02 10:00 -0500 finish: merged abc1234`n"
        '01-02-merged-bullet\ledger.md' = "# F (2026)`n- head: topic f, base 1, checkout x`n- 2026-01-02 merged: abc1234 on main, pushed`n"
        '01-03-reported\ledger.md' = "$head- 2026-01-03 10:00 -0500 finish: stop and report, unmerged`n"
        '01-04-reopened\ledger.md' = "$head- 2026-01-04 10:00 -0500 finish: merged abc1234`n- 2026-01-05 10:00 -0500 finish: stop and report`n"
        '01-05-pending\ledger.md' = $merged
        '01-05-pending\rounds\diff-r1-sol\pending.json' = '{}'
        '01-06-noledger\notes.md' = "# n`n"
        '01-06-noledger\shot.png' = 'x'
        '01-07-open-member\ledger.md' = $merged
        '01-08-closed-member\ledger.md' = "$head- 2026-01-08 10:00 -0500 finish: stop and report`n"
        '01-09-kept\ledger.md' = $merged
        '01-10-fresh\ledger.md' = $merged
        '01-11-held-member\ledger.md' = $merged
        '01-11-held-member\rounds\diff-r1-sol\pending.json' = '{}'
        '01-12-nofinish\ledger.md' = "$head- 2026-01-12 10:00 -0500 go: Brandon`n"
        '01-13-young\ledger.md' = "$head- 2026-01-13 10:00 -0500 finish: stop and report`n"
        '01-14-shared\ledger.md' = $merged
        '01-16-locked-member\notes.md' = "# n`n"
        '01-17-kept-member\ledger.md' = $merged
        '01-18-dead-round\ledger.md' = $merged
        '01-18-dead-round\rounds\prereview-r1-opus.dead1\pending.json' = '{}'
        'panels\01-01-panel\brief.md' = "# p`n"
        'programs\2026-01-01-open\program.md' = "# Open`n`n## Feature folders`n`n- ``01-07-open-member```n- ``01-14-shared```n"
        'programs\2026-01-02-shut\program.md' = "# Shut`nclosed: 2026-01-03`n`n## Feature folders`n`n- ``01-08-closed-member`` phase 1`n- ``01-15-gone```n`n---`n"
        'programs\2026-01-03-held\program.md' = "# Held`nclosed: 2026-01-04`n`n## Feature folders`n`n- ``01-11-held-member```n"
        'programs\2026-01-04-twin\program.md' = "# Twin`n`n## Feature folders`n`n- ``01-14-shared```n"
        'programs\2026-01-05-noprog\scoping.md' = "# s`n"
        'programs\2026-01-06-keptheld\program.md' = "# Kept held`nclosed: 2026-01-06`n`n## Feature folders`n`n- ``01-17-kept-member```n"
        'programs\2026-01-07-locked\program.md' = "# Locked`nclosed: 2026-01-07`n`n## Feature folders`n`n- ``01-16-locked-member```n"
        'programs\2026-01-08-badlist\program.md' = "# Bad list`nclosed: 2026-01-08`n`n## Feature folders`n`n- ``programs/2026-01-05-noprog```n"
        'programs\2026-01-09-alias\program.md' = "# Alias`nclosed: 2026-01-09`n`n## Feature folders`n`n- ``01-09-kept.```n- ``01-06-noledger/```n"
        'programs\2026-01-01-loose.md' = "# loose`n"
        'programs\active-masters.tsv' = ''
        'programs\.migrated' = "migrated`n"
    }
    foreach ($f in $fixture.Keys) {
        $path = Join-Path $rdocs $f
        New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
        [System.IO.File]::WriteAllText($path, $fixture[$f])
    }
    $aged = (Get-Date).AddDays(-40)
    Get-ChildItem -LiteralPath $rdocs -Recurse -File | Where-Object { $_.FullName -notlike '*\01-10-fresh\*' -and $_.FullName -notlike '*\01-13-young\*' } | ForEach-Object { $_.LastWriteTime = $aged }
    $rret = Join-Path $rproj 'dev\scripts\check-artifact-retention.ps1'
    $dry = (& pwsh -NoProfile -File $rret -Root $rproj -Soft 2>&1 | Out-String)
    $dryOk = $LASTEXITCODE -eq 0 -and $dry -notmatch 'FAIL \[script\]'
    # A file held open makes the locked program's member move fail during -Archive.
    $lock = [System.IO.File]::Open((Join-Path $rdocs '01-16-locked-member\notes.md'), 'Open', 'Read', 'None')
    try {
        $arch = (& pwsh -NoProfile -File $rret -Root $rproj -Soft -Archive 2>&1 | Out-String)
        $archOk = $LASTEXITCODE -eq 0 -and $arch -notmatch 'FAIL \[script\]'
    } finally { $lock.Dispose() }
    function RetMoved([string]$from, [string]$to) { (Test-Path (Join-Path $rarch $to)) -and -not (Test-Path (Join-Path $rdocs $from)) }
    function RetStays([string]$from) { Test-Path (Join-Path $rdocs $from) }
    $rows = @(
        @{ n = '01-01-merged-template'; listed = '(?m)^\s+docs:01-01-merged-template\s*$'; place = (RetMoved '01-01-merged-template' 'parsec\2026\01-01-merged-template') },
        @{ n = '01-02-merged-bullet'; listed = '(?m)^\s+docs:01-02-merged-bullet\s*$'; place = (RetMoved '01-02-merged-bullet' 'parsec\2026\01-02-merged-bullet') },
        @{ n = '01-03-reported'; listed = 'docs:01-03-reported \(last finish: stop and report, unmerged\)'; place = (RetStays '01-03-reported') },
        @{ n = '01-04-reopened'; listed = 'docs:01-04-reopened \(last finish: stop and report\)'; place = (RetStays '01-04-reopened') },
        @{ n = '01-05-pending'; listed = 'docs:01-05-pending \(round pending\)'; place = (RetStays '01-05-pending') },
        @{ n = '01-18-dead-round'; listed = '(?m)^\s+docs:01-18-dead-round\s*$'; place = (RetMoved '01-18-dead-round' 'parsec\2026\01-18-dead-round') },
        @{ n = '01-06-noledger'; listed = 'docs:01-06-noledger \(no ledger\)'; place = (RetStays '01-06-noledger') },
        @{ n = '01-12-nofinish'; listed = 'docs:01-12-nofinish \(no finish line\)'; place = (RetStays '01-12-nofinish') },
        @{ n = '01-13-young'; listed = $null; place = (RetStays '01-13-young') },
        @{ n = '01-07-open-member'; listed = $null; place = (RetStays '01-07-open-member') },
        @{ n = '01-14-shared'; listed = 'docs:01-14-shared \(listed by two programs\)'; place = (RetStays '01-14-shared') },
        @{ n = '01-08-closed-member'; listed = $null; place = (RetMoved '01-08-closed-member' 'programs\2026-01-02-shut\features\01-08-closed-member') },
        @{ n = 'programs\2026-01-02-shut'; listed = '\[I\] closed program docs:programs/2026-01-02-shut,'; place = (RetMoved 'programs\2026-01-02-shut' 'programs\2026-01-02-shut\program.md') },
        @{ n = '01-15-gone'; listed = '\[I\] listed folder missing: docs:01-15-gone'; place = (RetMoved 'programs\2026-01-02-shut' 'programs\2026-01-02-shut\program.md') },
        @{ n = 'programs\2026-01-03-held'; listed = 'docs:programs/2026-01-03-held \(program held: docs:01-11-held-member round pending\)'; place = (RetStays 'programs\2026-01-03-held') },
        @{ n = 'programs\2026-01-07-locked'; listed = '\[I\] closed program docs:programs/2026-01-07-locked,'; place = ($arch -match 'FAIL \[archive\] could not move docs:01-16-locked-member') -and (RetStays 'programs\2026-01-07-locked\program.md') -and -not (RetStays 'programs\2026-01-07-locked\features') -and (RetStays '01-16-locked-member') -and -not (Test-Path (Join-Path $rarch 'programs\2026-01-07-locked')) },
        @{ n = 'programs\2026-01-05-noprog'; listed = 'docs:programs/2026-01-05-noprog \(program without program.md\)'; place = (RetStays 'programs\2026-01-05-noprog') },
        @{ n = 'programs\2026-01-08-badlist'; listed = '\[I\] not a feature folder name in docs:programs/2026-01-08-badlist: programs/2026-01-05-noprog'; place = ($dry -match 'docs:programs/2026-01-08-badlist \(program held: not a feature folder name: programs/2026-01-05-noprog\)') -and (RetStays 'programs\2026-01-08-badlist\program.md') -and (RetStays 'programs\2026-01-05-noprog') },
        @{ n = 'programs\2026-01-09-alias'; listed = '\[I\] not a feature folder name in docs:programs/2026-01-09-alias: 01-09-kept\.'; place = ($dry -match '\[I\] not a feature folder name in docs:programs/2026-01-09-alias: 01-06-noledger/') -and ($dry -match 'docs:programs/2026-01-09-alias \(program held: not a feature folder name: 01-09-kept\.\)') -and (RetStays 'programs\2026-01-09-alias\program.md') -and (RetStays '01-09-kept') -and (RetStays '01-06-noledger') },
        @{ n = 'panels\01-01-panel'; listed = 'docs:panels/01-01-panel \(panel\)'; place = (RetStays 'panels\01-01-panel') },
        @{ n = 'programs\2026-01-01-loose.md'; listed = 'docs:programs/2026-01-01-loose.md \(loose file\)'; place = (RetStays 'programs\2026-01-01-loose.md') },
        @{ n = '01-09-kept'; listed = $null; place = (RetStays '01-09-kept') },
        @{ n = '01-10-fresh'; listed = $null; place = (RetStays '01-10-fresh') }
    )
    foreach ($r in $rows) {
        $name = $r.n -replace '\\', '/'
        $listedOk = if ($r.listed) { $dry -match $r.listed } else { $dry -notmatch [regex]::Escape("docs:$name") }
        Check "retention docs root: $($r.n)" ($dryOk -and $archOk -and $listedOk -and $r.place) "$dry`n$arch"
    }
    Check 'retention [A] sees media under the docs root' ($dryOk -and $dry -match '\[A\] 1 media files') $dry
    Check 'retention [F] refuses a checkout path into the docs root' ($dryOk -and $dry -match 'FAIL \[F\] keep entry names a docs-root path by its checkout path') $dry
    Check 'retention [F] refuses a keep entry that is not a canonical path' ($dryOk -and $dry -match 'FAIL \[F\] keep entry is not a canonical path.*docs:01-12-nofinish\.' -and $dry -match 'docs:01-12-nofinish \(no finish line\)') $dry

    # -Pick moves a named unknown entry, a held program with its members, and
    # refuses anything else.
    $picked = (& pwsh -NoProfile -File $rret -Root $rproj -Soft -Pick 'docs:01-06-noledger,docs:programs/2026-01-03-held,docs:01-07-open-member,docs:programs/2026-01-06-keptheld,docs:01-14-shared,docs:programs/2026-01-08-badlist' 2>&1 | Out-String)
    $pickOk = $LASTEXITCODE -eq 0 -and $picked -notmatch 'FAIL \[script\]'
    $pickYear = (Get-Date).AddDays(-40).Year
    $pickRows = @(
        @{ name = 'an unknown entry moves'; ok = (RetMoved '01-06-noledger' "parsec\$pickYear\01-06-noledger") },
        @{ name = 'a held program moves with its member'; ok = (RetMoved '01-11-held-member' 'programs\2026-01-03-held\features\01-11-held-member') },
        @{ name = 'a member of an open program is refused'; ok = ($picked -match 'FAIL \[U\] not an unknown entry: docs:01-07-open-member') -and (RetStays '01-07-open-member') },
        @{ name = 'a program held by a kept member is refused'; ok = ($picked -match 'FAIL \[U\] cannot pick docs:programs/2026-01-06-keptheld: docs:01-17-kept-member kept') -and (RetStays 'programs\2026-01-06-keptheld') -and (RetStays '01-17-kept-member') },
        @{ name = 'a folder two programs list is refused'; ok = ($picked -match 'FAIL \[U\] cannot pick docs:01-14-shared: listed by two programs') -and (RetStays '01-14-shared') },
        @{ name = 'a program blocked by a bullet that is not a folder name is refused'; ok = ($picked -match 'FAIL \[U\] cannot pick docs:programs/2026-01-08-badlist: not a feature folder name: programs/2026-01-05-noprog') -and (RetStays 'programs\2026-01-08-badlist') -and (RetStays 'programs\2026-01-05-noprog') }
    )
    foreach ($r in $pickRows) { Check "retention -Pick: $($r.name)" ($pickOk -and $r.ok) $picked }

    # A configured docs root that is missing is a FAIL; a missing fallback is silent.
    $r7 = Join-Path $outside 'r7'
    foreach ($d in @('.claude', 'dev\scripts')) { New-Item -ItemType Directory -Path (Join-Path $r7 $d) -Force | Out-Null }
    foreach ($s in @('check-artifact-retention.ps1', 'parsec-docs-root.ps1')) { Copy-Item (Join-Path $root "dev\scripts\$s") (Join-Path $r7 'dev\scripts\') }
    [System.IO.File]::WriteAllText((Join-Path $r7 '.claude\parsec.toml'), "docs_root = `"$((Join-Path $outside 'nodocs') -replace '\\', '/')`"`n")
    $o7 = (& pwsh -NoProfile -File (Join-Path $r7 'dev\scripts\check-artifact-retention.ps1') -Root $r7 -Soft 2>&1 | Out-String)
    $o7ok = $LASTEXITCODE -eq 0 -and $o7 -notmatch 'FAIL \[script\]'
    Check 'retention: a configured docs root that is missing is a FAIL' ($o7ok -and $o7 -match 'FAIL \[H\] docs root missing') $o7
    Remove-Item (Join-Path $r7 '.claude\parsec.toml') -Force
    $o7 = (& pwsh -NoProfile -File (Join-Path $r7 'dev\scripts\check-artifact-retention.ps1') -Root $r7 -Soft 2>&1 | Out-String)
    $o7ok = $LASTEXITCODE -eq 0 -and $o7 -notmatch 'FAIL \[script\]'
    Check 'retention: a missing fallback docs root is silent' ($o7ok -and $o7 -notmatch '\[H\]') $o7

    # Without the programs/.migrated marker the docs-root rules and -Pick wait,
    # and -Archive moves nothing from the docs root.
    $r8 = Join-Path $outside 'r8'
    $r8docs = Join-Path $outside 'r8docs'
    foreach ($d in @('.claude', 'dev\scripts')) { New-Item -ItemType Directory -Path (Join-Path $r8 $d) -Force | Out-Null }
    foreach ($s in @('check-artifact-retention.ps1', 'parsec-docs-root.ps1')) { Copy-Item (Join-Path $root "dev\scripts\$s") (Join-Path $r8 'dev\scripts\') }
    [System.IO.File]::WriteAllText((Join-Path $r8 '.claude\parsec.toml'), "docs_root = `"$($r8docs -replace '\\', '/')`"`n")
    foreach ($f in @('programs\active-masters.tsv', '01-01-done\ledger.md')) {
        $path = Join-Path $r8docs $f
        New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
        [System.IO.File]::WriteAllText($path, "# F (2026)`n- 2026-01-01 10:00 -0500 finish: merged abc1234`n")
        (Get-Item $path).LastWriteTime = (Get-Date).AddDays(-40)
    }
    $o8 = (& pwsh -NoProfile -File (Join-Path $r8 'dev\scripts\check-artifact-retention.ps1') -Root $r8 -Soft -Archive -Pick 'docs:01-01-done' 2>&1 | Out-String)
    $o8ok = $LASTEXITCODE -eq 0 -and $o8 -notmatch 'FAIL \[script\]'
    Check 'retention: no migration marker holds the docs-root rules and -Pick' ($o8ok -and ($o8 -match 'wait for the program migration') -and ($o8 -match '-Pick skipped') -and ($o8 -notmatch 'FAIL \[U\]') -and (Test-Path (Join-Path $r8docs '01-01-done'))) $o8

    # [C] honors the keep list: a merged review mirror that is kept, or holds
    # a kept path, is not queued for -Archive. The repository is throwaway, so
    # its one commit on main makes every mirror named for it merged.
    $gproj = Join-Path $outside 'gproj'
    New-Item -ItemType Directory -Path $gproj | Out-Null
    git -C $gproj init -q -b main 2>&1 | Out-Null
    git -C $gproj -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q --allow-empty --no-verify -m init 2>&1 | Out-Null
    $gsha = "$(git -C $gproj rev-parse --short=7 main)".Trim()
    $gmir = Join-Path $gproj '.superpowers\review-sources'
    foreach ($d in @("plain-$gsha", "kept-$gsha", "shelter-$gsha\inner")) { New-Item -ItemType Directory -Path (Join-Path $gmir $d) -Force | Out-Null }
    New-Item -ItemType Directory -Path (Join-Path $gproj 'dev\docs') -Force | Out-Null
    $until = (Get-Date).AddDays(1).ToString('yyyy-MM-dd')
    [System.IO.File]::WriteAllText((Join-Path $gproj 'dev\docs\retention-keep.txt'), ".superpowers/review-sources/kept-$gsha|until:$until|fixture`n.superpowers/review-sources/shelter-$gsha/inner|until:$until|fixture`n")
    $oc = (& pwsh -NoProfile -File (Join-Path $root 'dev\scripts\check-artifact-retention.ps1') -Root $gproj -Soft 2>&1 | Out-String)
    $ocOk = $LASTEXITCODE -eq 0 -and $oc -notmatch 'FAIL \[script\]' -and $gsha -match '^[0-9a-f]{7}$'
    $cRows = @(
        @{ name = 'a merged mirror is queued'; dir = "plain-$gsha"; queued = $true },
        @{ name = 'a kept mirror is not queued'; dir = "kept-$gsha"; queued = $false },
        @{ name = 'a mirror holding a kept path is not queued'; dir = "shelter-$gsha"; queued = $false }
    )
    foreach ($c in $cRows) {
        $hit = $oc -match ('(?m)^\s+\.superpowers/review-sources/' + [regex]::Escape($c.dir) + '\s*$')
        Check "retention [C]: $($c.name)" ($ocOk -and $hit -eq $c.queued) $oc
    }
} finally {
    # Each step runs regardless of the others; native git exits are checked
    # because they do not throw, and any leftover fails the run.
    $ErrorActionPreference = 'Continue'
    $leftover = @()
    try { if (Test-Path $link) { (Get-Item $link).Delete() } } catch { $leftover += "junction $link ($_)" }
    foreach ($w in @($wt, $feature)) {
        if (Test-Path $w) {
            git -C $root worktree remove --force $w 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0 -or (Test-Path $w)) { $leftover += "worktree $w" }
        }
    }
    git -C $root worktree prune 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { $leftover += 'worktree prune failed' }
    if (git -C $root branch --list $featureBranch) {
        git -C $root branch -D $featureBranch 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { $leftover += "branch $featureBranch" }
    }
    try { if (Test-Path $outside) { Remove-Item $outside -Recurse -Force -ErrorAction Stop } } catch { $leftover += "folder $outside ($_)" }
    foreach ($l in $leftover) { Write-Host "cleanup left behind: $l" }
}

Write-Host ("{0} passed, {1} failed, {2} skipped" -f $pass, $fail, $skip)
if ($fail -gt 0 -or $leftover.Count -gt 0) { exit 1 }
exit 0

# Exercises the tracked Claude Code hook templates (dev/claude-hooks/) and the
# commit-msg git hook against every documented deny and allow case, using a
# throwaway worktree on main so the branch rules can be tested from any branch.
#
#   pwsh dev/scripts/test-claude-hooks.ps1
#
# Exit 1 on any failed case or when a live hook under .claude/hooks/ differs
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

# Live copies must match the templates (the installer refreshes them). Line
# endings are ignored: git renormalizes the tracked templates to CRLF.
function Get-TextHash([string]$path) {
    $text = [System.IO.File]::ReadAllText($path) -replace "`r", ''
    $sha = [System.Security.Cryptography.SHA256]::Create()
    return [System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($text)))
}
foreach ($n in @('branch-guard.ps1', 'git-guard.ps1', 'luacheck-postedit.ps1')) {
    $live = Join-Path $root ".claude\hooks\$n"
    if (Test-Path $live) {
        $same = (Get-TextHash $live) -eq (Get-TextHash (Join-Path $templates $n))
        Check "live == template: $n" $same 'run pwsh dev/scripts/install-claude-hooks.ps1'
    }
}

$tag = [System.IO.Path]::GetRandomFileName().Replace('.', '')
$wt = Join-Path $env:TEMP "ke-hooktest-$tag"
$link = "$wt-link"
$feature = "$wt-feature"
$featureBranch = "hooktest/$tag"
$outside = "$wt-outside"
try {
    git -C $root worktree add -q $wt main 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "could not add a worktree on main (is main checked out elsewhere?)" }
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
        $cm = { param($name, $msg, $expect)
            [System.IO.File]::WriteAllText($msgFile, $msg)
            & $bash $hook $msgFile 2>&1 | Out-Null
            Check "commit-msg $expect`: $name" ($LASTEXITCODE -eq $(if ($expect -eq 'block') { 1 } else { 0 }))
        }
        & $cm 'upstream name'               "port the tracker from norsken`n"                       'block'
        & $cm 'Co-Authored-By'              "fix a thing`n`nCo-Authored-By: Claude <x>`n"            'block'
        & $cm 'indented trailer'            "fix`n`n  Co-Authored-By: Claude`n"                       'block'
        & $cm 'Generated with Claude Code'  "fix a thing`n`nGenerated with Claude Code`n"             'block'
        & $cm 'Signed-off-by agent'         "fix a thing`n`nSigned-off-by: Codex`n"                   'block'
        & $cm 'uppercase subject'           "Fix the show target toggle`n"                            'block'
        & $cm 'default merge subject'       "Merge branch 'codex/x'`n"                                'block'
        & $cm 'clean'                       "fix the show target toggle`n"                            'pass'
        & $cm 'release commit'              "v4.4.9: fix a thing`n"                                   'pass'
        & $cm 'human sign-off'              "fix`n`nSigned-off-by: Brandon Wascher <x>`n"             'pass'
        & $cm 'comment lines before subject' "# editor comment`nfix a thing`n"                        'pass'
        & $cm 'blank lines before subject'  "`n`nfix a thing`n"                                       'pass'
        & $cm 'compat name alone'           "skin the elvui bags`n"                                   'pass'
        Remove-Item $msgFile -Force -ErrorAction SilentlyContinue

        # --- pre-commit (bash), staged in the feature worktree -----------------
        $pc = (Join-Path $root 'dev\githooks\pre-commit') -replace '\\', '/'
        $probeRel = 'Modules/QoL/_hooktest_probe.lua'
        $probeAbs = Join-Path $feature ($probeRel -replace '/', '\')
        $stubAbs = Join-Path $feature 'dev\Annotations\KE.lua'
        $stage = { param($name, $code, $expect, $stubLine = $null)
            [System.IO.File]::WriteAllText($probeAbs, $code)
            git -C $feature add -- $probeRel 2>&1 | Out-Null
            if ($stubLine) {
                [System.IO.File]::AppendAllText($stubAbs, "`n$stubLine`n")
                git -C $feature add -- dev/Annotations/KE.lua 2>&1 | Out-Null
            }
            Push-Location $feature
            try { & $bash $pc 2>&1 | Out-Null; $code_ = $LASTEXITCODE } finally { Pop-Location }
            Check "pre-commit $expect`: $name" ($code_ -eq $(if ($expect -eq 'block') { 1 } else { 0 }))
            git -C $feature reset -q -- $probeRel dev/Annotations/KE.lua 2>&1 | Out-Null
            git -C $feature checkout -q -- dev/Annotations/KE.lua 2>&1 | Out-Null
            Remove-Item $probeAbs -Force -ErrorAction SilentlyContinue
        }
        & $stage 'restricted combat log event'      "local f = CreateFrame('Frame')`nf:RegisterEvent('COMBAT_LOG_EVENT_UNFILTERED')`n" 'block'
        & $stage 'restricted combat log accessor'   "local a = CombatLogGetCurrentEventInfo()`n" 'block'
        & $stage 'AceEvent RegisterUnitEvent'       "local M = {}`nfunction M:OnEnable() self:RegisterUnitEvent('UNIT_AURA', 'player') end`n" 'block'
        & $stage 'restricted name in a comment'     "-- CLEU-free: COMBAT_LOG_EVENT_UNFILTERED is restricted`nlocal x = 1`n" 'pass'
        & $stage 'frame RegisterUnitEvent'          "local f = CreateFrame('Frame')`nf:RegisterUnitEvent('UNIT_AURA', 'player')`n" 'pass'
        & $stage 'restricted name inside a string'  "local s = `"CombatLogGetCurrentEventInfo()`"`n" 'pass'
        & $stage 'string holding -- then a restricted call' "local m = `"--`"; local a = CombatLogGetCurrentEventInfo()`n" 'block'
        & $stage 'new KE: method without a stub'    "function KE:HookTestProbe(a) return a end`n" 'block'
        & $stage 'new KE. function without a stub'  "function KE.HookTestProbe(a) return a end`n" 'block'
        & $stage 'new KE. assignment without a stub' "KE.HookTestProbe = function(a) return a end`n" 'block'
        & $stage 'new KE: method with a staged stub' "function KE:HookTestProbe(a) return a end`n" 'pass' "---@param a any`n---@return any`nfunction KE:HookTestProbe(a) end"
        & $stage 'plain code'                       "local x = 1`nreturn x`n" 'pass'
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

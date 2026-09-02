# Exercises the tracked Claude Code hook templates (dev/claude-hooks/) and the
# commit-msg git hook against every documented deny and allow case, using a
# throwaway worktree on main so the branch rules can be tested from any branch.
#
#   pwsh dev/scripts/test-claude-hooks.ps1
#
# Exit 1 on any failed case or when a live hook under .claude/hooks/ differs
# from its template. Read-only against the repo: the worktree and junction it
# creates under $env:TEMP are removed on exit.

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$templates = Join-Path $root 'dev\claude-hooks'
$fail = 0
$pass = 0

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

# Live copies must match the templates (the installer refreshes them).
foreach ($n in @('branch-guard.ps1', 'git-guard.ps1', 'luacheck-postedit.ps1')) {
    $live = Join-Path $root ".claude\hooks\$n"
    if (Test-Path $live) {
        $same = (Get-FileHash $live).Hash -eq (Get-FileHash (Join-Path $templates $n)).Hash
        Check "live == template: $n" $same 'run pwsh dev/scripts/install-claude-hooks.ps1'
    }
}

$wt = Join-Path $env:TEMP ("ke-hooktest-" + [System.IO.Path]::GetRandomFileName().Replace('.', ''))
$link = "$wt-link"
try {
    git -C $root worktree add -q $wt main 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "could not add a worktree on main (is main checked out elsewhere?)" }
    New-Item -ItemType Junction -Path $link -Target $wt | Out-Null
    $short = (New-Object -ComObject Scripting.FileSystemObject).GetFolder($wt).ShortPath
    $fwd = ($wt -replace '\\', '/')
    $fwd = $fwd.Substring(0, 1).ToLower() + $fwd.Substring(1)

    # --- branch-guard ---------------------------------------------------------
    $bg = 'branch-guard.ps1'
    $edit = { param($f, $cwd) @{ tool_name = 'Edit'; cwd = $cwd; tool_input = @{ file_path = $f } } }
    Expect-Deny  $bg 'absolute path'            (& $edit "$wt\Core\Globals.lua" $wt)
    Expect-Deny  $bg 'forward slashes'          (& $edit "$fwd/Modules/QoL/QoL.xml" $wt)
    Expect-Deny  $bg 'relative path'            (& $edit 'Core/Globals.lua' $wt)
    Expect-Deny  $bg '8.3 short path'           (& $edit "$short\Core\Globals.lua" $wt)
    Expect-Deny  $bg 'junction path'            (& $edit "$link\Core\Globals.lua" $wt)
    Expect-Deny  $bg 'relative under junction'  (& $edit 'Core/Globals.lua' $link)
    Expect-Allow $bg 'dev/ exempt'              (& $edit "$wt\dev\spec\x_spec.lua" $wt)
    Expect-Allow $bg '.claude/ exempt'          (& $edit "$wt\.claude\x.lua" $wt)
    Expect-Allow $bg '.toc exempt'              (& $edit "$wt\KitnEssentials.toc" $wt)
    Expect-Allow $bg 'outside any repo'         (& $edit "$env:TEMP\nope\x.lua" $wt)
    Expect-Allow $bg 'no file_path'             @{ tool_name = 'Edit'; cwd = $wt; tool_input = @{} }

    # --- git-guard ------------------------------------------------------------
    $gg = 'git-guard.ps1'
    $sh = { param($c, $cwd, $tool = 'Bash') @{ tool_name = $tool; cwd = $cwd; tool_input = @{ command = $c } } }
    $deny = @(
        'git checkout -- Core/Globals.lua', 'git checkout .', 'git checkout main -- Core/Globals.lua',
        'git checkout -f main', 'git restore Core/Globals.lua', 'git restore --worktree --staged Core/Globals.lua',
        'git add -A', 'git add --all', 'git add .', 'git add -u', 'git add -- .', 'git add -Av',
        'git restore --staged X && git add -A', 'git -C C:/x add -A', 'git -C "C:/some dir" add -A',
        'git --no-pager add -A', 'git -c core.autocrlf=false add -A',
        'git commit -a -m x', 'git commit -am x', 'git commit --all -m x',
        'git switch -f main', 'git switch --discard-changes main',
        'git reset --hard HEAD~1', 'git clean -fd', 'git stash drop', 'git stash clear',
        'git add *', 'git add "."', 'git add :/',
        'sed -i s/a/b/ Core/Globals.lua', "sed -i 's/a/b/' Modules/QoL/QoL.xml", 'cat > Core/Globals.lua',
        'echo x >> GUI/GUIMain/GUI-Main.lua', 'tee Core/Globals.lua', "sed -i s/a/b/ $wt\Core\Globals.lua"
    )
    foreach ($c in $deny) { Expect-Deny $gg $c (& $sh $c $wt) }
    Expect-Deny $gg 'Set-Content (PowerShell)'  (& $sh 'Set-Content Core/Globals.lua x' $wt 'PowerShell')
    Expect-Deny $gg 'Out-File (PowerShell)'     (& $sh "'x' | Out-File -Path Core/Globals.lua" $wt 'PowerShell')
    Expect-Deny $gg 'Add-Content (PowerShell)'  (& $sh 'Add-Content -LiteralPath Core/Globals.lua y' $wt 'PowerShell')
    $allow = @(
        'git add Core/Globals.lua CHANGELOG.md', 'git restore --staged Core/Globals.lua', 'git checkout feature/x',
        'git switch -c feature/x', 'git switch main', 'git stash', 'git stash pop', 'git reset --soft HEAD~1',
        'git reset Core/Globals.lua', 'git clean -n', 'git clean -fdn', 'git commit -m "add a thing"',
        'git commit --amend -m x', 'git add Modules/', 'sed -i s/a/b/ dev/spec/x_spec.lua', 'echo x > CHANGELOG.md',
        'sed -n 1,5p Core/Globals.lua', 'grep -n foo Core/Globals.lua > out.txt', "sed -i s/a/b/ $env:TEMP\probe.lua",
        'luacheck Core/Globals.lua > /dev/null 2>&1', 'git status', 'ls Core'
    )
    foreach ($c in $allow) { Expect-Allow $gg $c (& $sh $c $wt) }
    # Shell writes are only denied while the cwd's checkout is on main.
    $feature = "$wt-feature"
    git -C $root worktree add -q -b "hooktest/$([System.IO.Path]::GetRandomFileName().Replace('.', ''))" $feature main 2>&1 | Out-Null
    Expect-Allow $gg 'sed -i on a feature branch' (& $sh 'sed -i s/a/b/ Core/Globals.lua' $feature)

    # --- luacheck-postedit ----------------------------------------------------
    $lc = 'luacheck-postedit.ps1'
    $probe = Join-Path $wt 'dev\_hooktest_probe.lua'
    Set-Content -Path $probe -Value 'local unused = 1' -NoNewline
    foreach ($case in @(@("$wt\dev\_hooktest_probe.lua", $wt), @('dev/_hooktest_probe.lua', $wt), @("$short\dev\_hooktest_probe.lua", $wt), @("$link\dev\_hooktest_probe.lua", $wt))) {
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
        $msgFile = Join-Path $env:TEMP 'ke-hooktest-msg.txt'
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
        & $cm 'compat name alone'           "skin the elvui bags`n"                                   'pass'
        Remove-Item $msgFile -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host 'commit-msg cases skipped: bash not on PATH'
    }
} finally {
    if (Test-Path $link) { (Get-Item $link).Delete() }
    foreach ($w in @($wt, "$wt-feature")) {
        if (Test-Path $w) { git -C $root worktree remove --force $w 2>&1 | Out-Null }
    }
    git -C $root worktree prune 2>&1 | Out-Null
    git -C $root branch --list 'hooktest/*' | ForEach-Object { git -C $root branch -D $_.Trim() 2>&1 | Out-Null }
}

Write-Host ("{0} passed, {1} failed" -f $pass, $fail)
if ($fail -gt 0) { exit 1 }
exit 0

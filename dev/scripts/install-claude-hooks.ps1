# Restores the local dev gates after a re-clone or PC reset. Everything under
# .claude/ is gitignored, so the live hooks die with the checkout; these
# tracked templates (dev/claude-hooks/) are the durable copies.
#
#   pwsh dev/scripts/install-claude-hooks.ps1
#
# Idempotent: copies the hook scripts, merges missing hook entries into the
# settings file of each scope per event and per script (never overwrites
# existing entries or personal permissions), and sets core.hooksPath for the
# pre-push gate. Safe to re-run any time.
#
# Two scopes. The repo-agnostic guards (branch-guard, git-guard,
# luacheck-postedit) find the repo from the edited path, so they install once
# at user scope (~/.claude) and cover every project on the machine. The
# agents-mirror and references-check hooks depend on this repo's scripts, so
# they stay project scope (.claude). A moved hook's stale copy and settings
# entry in the other scope are removed, or it would fire twice.

$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$templates = Join-Path $root 'dev\claude-hooks'
$scopes = @(
    @{ label = 'user'; hooks = @('branch-guard.ps1', 'git-guard.ps1', 'luacheck-postedit.ps1')
       dir = Join-Path $env:USERPROFILE '.claude'; template = Join-Path $templates 'user-settings.template.json' },
    @{ label = 'project'; hooks = @('agents-mirror-sync.ps1', 'references-check.ps1')
       dir = Join-Path $root '.claude'; template = Join-Path $templates 'settings.template.json' }
)

function Get-HookScript($hook) {
    if (($hook.args -join ' ') -match '([\w-]+\.ps1)') { return $Matches[1] }
    return ''
}
function Get-EntryScripts($entry) {
    return @(@($entry.hooks) | ForEach-Object { Get-HookScript $_ } | Where-Object { $_ })
}

# Merge the template's entries into a settings file: add what is missing per
# event, keyed on the script filename; drop hooks for scripts that now live
# in the other scope (an entry bundling one with a personal hook keeps the
# personal hook); leave everything else untouched.
function Merge-HookSettings([string]$templatePath, [string]$settingsPath, [string]$label, [string[]]$retire) {
    $template = Get-Content $templatePath -Raw | ConvertFrom-Json
    if (-not (Test-Path $settingsPath)) {
        Copy-Item $templatePath $settingsPath
        Write-Host "[install] $label settings.json created from template"
        return
    }
    $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
    $changed = $false
    if (-not ($settings.PSObject.Properties.Name -contains 'hooks')) {
        $settings | Add-Member -MemberType NoteProperty -Name 'hooks' -Value $template.hooks
        $changed = $true
        Write-Host "[install] hooks block injected into $label settings.json"
    } else {
        foreach ($eventProp in $template.hooks.PSObject.Properties) {
            $event = $eventProp.Name
            if (-not ($settings.hooks.PSObject.Properties.Name -contains $event)) {
                $settings.hooks | Add-Member -MemberType NoteProperty -Name $event -Value $eventProp.Value
                $changed = $true
                Write-Host "[install] $label hooks.$event added from template"
                continue
            }
            $existing = @($settings.hooks.$event)
            foreach ($entry in @($eventProp.Value)) {
                $script = @(Get-EntryScripts $entry)[0]
                if (-not $script) { continue }
                $present = @($existing | Where-Object { @(Get-EntryScripts $_) -contains $script }).Count -gt 0
                if (-not $present) {
                    $existing += $entry
                    $changed = $true
                    Write-Host "[install] $label hooks.$event entry for $script appended"
                }
            }
            $settings.hooks.$event = $existing
        }
        foreach ($eventProp in @($settings.hooks.PSObject.Properties)) {
            $kept = @()
            foreach ($e in @($eventProp.Value)) {
                $keptHooks = @()
                foreach ($h in @($e.hooks)) {
                    $script = Get-HookScript $h
                    if ($script -and $retire -contains $script) {
                        $changed = $true
                        Write-Host "[install] $label hooks.$($eventProp.Name) hook $script removed (now in the other scope)"
                    } else { $keptHooks += $h }
                }
                if ($keptHooks.Count -eq 0) { continue }
                $e.hooks = $keptHooks
                $kept += $e
            }
            if ($kept.Count -eq 0) { $settings.hooks.PSObject.Properties.Remove($eventProp.Name) }
            else { $settings.hooks.($eventProp.Name) = $kept }
        }
    }
    if ($changed) {
        $backup = "$settingsPath.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
        Copy-Item $settingsPath $backup
        $settings | ConvertTo-Json -Depth 20 | Set-Content $settingsPath -Encoding UTF8
        Write-Host "[install] $label settings.json updated (backup: $(Split-Path $backup -Leaf))"
    } else {
        Write-Host "[install] $label settings.json already has all tracked hook entries"
    }
}

# 1. Hook scripts: template copies are canonical - always refresh; a copy
#    left in the other scope is removed.
# (the superpowers review-companion hook ships in the parallax plugin,
# user-scope - not here, or it would double-fire.)
foreach ($scope in $scopes) {
    $hooksDir = Join-Path $scope.dir 'hooks'
    New-Item -ItemType Directory -Force $hooksDir | Out-Null
    foreach ($name in $scope.hooks) {
        Copy-Item (Join-Path $templates $name) (Join-Path $hooksDir $name) -Force
        Write-Host "[install] $($scope.label) hooks/$name refreshed from dev/claude-hooks/"
    }
    foreach ($other in ($scopes | Where-Object { $_.label -ne $scope.label })) {
        foreach ($name in $other.hooks) {
            $stale = Join-Path $hooksDir $name
            if (Test-Path $stale) { Remove-Item $stale; Write-Host "[install] $($scope.label) hooks/$name removed (now $($other.label) scope)" }
        }
    }
}

# 2. settings.json per scope.
foreach ($scope in $scopes) {
    $retire = @($scopes | Where-Object { $_.label -ne $scope.label } | ForEach-Object { $_.hooks })
    Merge-HookSettings $scope.template (Join-Path $scope.dir 'settings.json') $scope.label $retire
}

# 3. Family skill junctions (KitnDev\.claude\skills -> project .claude\skills;
#    they die with the checkout on a PC reset — family AGENTS.md requires
#    re-creating them).
$familySkills = Join-Path (Split-Path $root -Parent) '.claude\skills'
$projSkills = Join-Path $root '.claude\skills'
if (Test-Path $familySkills) {
    New-Item -ItemType Directory -Force $projSkills | Out-Null
    foreach ($dir in Get-ChildItem $familySkills -Directory) {
        $link = Join-Path $projSkills $dir.Name
        if (-not (Test-Path $link)) {
            New-Item -ItemType Junction -Path $link -Target $dir.FullName | Out-Null
            Write-Host "[install] junction .claude/skills/$($dir.Name) -> KitnDev family skills"
        }
    }
}

# 4. Pre-push gate (per-clone config; dies on re-clone without this).
$current = git -C $root config core.hooksPath 2>$null
# Compare resolved paths: the value may be stored absolute or relative.
$want = (Resolve-Path (Join-Path $root 'dev\githooks')).Path
$have = ''
if ($current) {
    $candidate = if ([System.IO.Path]::IsPathRooted($current)) { $current } else { Join-Path $root $current }
    try { $have = (Resolve-Path $candidate -ErrorAction Stop).Path } catch { $have = $current }
}
if ($have -eq $want) {
    Write-Host "[install] core.hooksPath already dev/githooks"
} else {
    git -C $root config core.hooksPath dev/githooks
    Write-Host "[install] core.hooksPath set to dev/githooks (pre-push gate active)"
}

Write-Host "[install] done - Claude Code picks up hooks on next session start"

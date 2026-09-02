# Restores the local dev gates after a re-clone or PC reset. Everything under
# .claude/ is gitignored, so the live hooks die with the checkout; these
# tracked templates (dev/claude-hooks/) are the durable copies.
#
#   pwsh dev/scripts/install-claude-hooks.ps1
#
# Idempotent: copies the hook scripts, merges missing hook entries into
# .claude/settings.json per event and per script (never overwrites existing
# entries or personal permissions), and sets core.hooksPath for the pre-push
# gate. Safe to re-run any time.

$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$templates = Join-Path $root 'dev\claude-hooks'
$hooksDir = Join-Path $root '.claude\hooks'
$settingsPath = Join-Path $root '.claude\settings.json'

# 1. Hook scripts: template copies are canonical - always refresh.
New-Item -ItemType Directory -Force $hooksDir | Out-Null
# (the superpowers review-companion hook ships in the crosscheck plugin,
# user-scope - not here, or it would double-fire.)
foreach ($name in @('branch-guard.ps1', 'luacheck-postedit.ps1', 'git-guard.ps1', 'agents-mirror-sync.ps1')) {
    Copy-Item (Join-Path $templates $name) (Join-Path $hooksDir $name) -Force
    Write-Host "[install] .claude/hooks/$name refreshed from dev/claude-hooks/"
}

# 2. settings.json: create from template, or merge missing hook entries in.
#    Merge is per event and per entry, keyed on the hook script filename in
#    args - existing entries and personal settings are never touched, so new
#    tracked hooks land in a settings.json that already has a hooks block.
$template = Get-Content (Join-Path $templates 'settings.template.json') -Raw | ConvertFrom-Json
if (-not (Test-Path $settingsPath)) {
    Copy-Item (Join-Path $templates 'settings.template.json') $settingsPath
    Write-Host "[install] .claude/settings.json created from template"
} else {
    $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
    $changed = $false
    if (-not ($settings.PSObject.Properties.Name -contains 'hooks')) {
        $settings | Add-Member -MemberType NoteProperty -Name 'hooks' -Value $template.hooks
        $changed = $true
        Write-Host "[install] hooks block injected into existing .claude/settings.json"
    } else {
        foreach ($eventProp in $template.hooks.PSObject.Properties) {
            $event = $eventProp.Name
            if (-not ($settings.hooks.PSObject.Properties.Name -contains $event)) {
                $settings.hooks | Add-Member -MemberType NoteProperty -Name $event -Value $eventProp.Value
                $changed = $true
                Write-Host "[install] hooks.$event added from template"
                continue
            }
            $existing = @($settings.hooks.$event)
            foreach ($entry in @($eventProp.Value)) {
                $script = ''
                foreach ($h in @($entry.hooks)) {
                    if (($h.args -join ' ') -match '([\w-]+\.ps1)') { $script = $Matches[1]; break }
                }
                if (-not $script) { continue }
                $present = $false
                foreach ($e in $existing) {
                    foreach ($h in @($e.hooks)) {
                        if (($h.args -join ' ') -match [regex]::Escape($script)) { $present = $true; break }
                    }
                    if ($present) { break }
                }
                if (-not $present) {
                    $existing += $entry
                    $changed = $true
                    Write-Host "[install] hooks.$event entry for $script appended"
                }
            }
            $settings.hooks.$event = $existing
        }
    }
    if ($changed) {
        $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding UTF8
    } else {
        Write-Host "[install] .claude/settings.json already has all tracked hook entries"
    }
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

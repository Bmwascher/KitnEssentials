# Installs the multi-model verification system USER-SCOPE so every KitnDev
# project gets it:
#   1. tracked skills (dev/claude-skills/<name>/) -> ~/.claude/skills/<name>
#      as directory junctions (repo edits are live, no re-install)
#   2. the superpowers-review-companion hook -> ~/.claude/hooks/ + a
#      PostToolUse/Task entry merged into ~/.claude/settings.json (the hook
#      is fingerprinted - inert outside superpowers code-review dispatches)
#
#   pwsh dev/scripts/install-claude-skills.ps1
#
# Idempotent: correct junctions are left alone, stale junctions are
# re-pointed, a real directory at the target is never clobbered (warns
# instead), and the settings merge never touches existing entries. The
# evals/ folder is repo-side CI tooling, not a skill - skipped.

$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$srcRoot = Join-Path $root 'dev\claude-skills'
$dstRoot = Join-Path $env:USERPROFILE '.claude\skills'

New-Item -ItemType Directory -Force $dstRoot | Out-Null

foreach ($src in Get-ChildItem $srcRoot -Directory | Where-Object { $_.Name -ne 'evals' }) {
    $name = $src.Name
    if (-not (Test-Path (Join-Path $src.FullName 'SKILL.md'))) {
        Write-Host "[install] $name skipped - no SKILL.md"
        continue
    }
    $dst = Join-Path $dstRoot $name
    if (Test-Path $dst) {
        $item = Get-Item $dst -Force
        if ($item.LinkType -eq 'Junction') {
            $target = [string]($item.LinkTarget ?? $item.Target)
            if ($target -eq $src.FullName) {
                Write-Host "[install] $name already linked into ~/.claude/skills/"
                continue
            }
            # Stale junction (e.g. repo moved): delete the link only, never
            # the target contents, then fall through to recreate it.
            $item.Delete()
            Write-Host "[install] $name junction re-pointed (was $target)"
        } else {
            Write-Host "[install] WARN: ~/.claude/skills/$name is a real directory - not touching it. Remove it and re-run to link the repo copy."
            continue
        }
    }
    New-Item -ItemType Junction -Path $dst -Target $src.FullName | Out-Null
    Write-Host "[install] $name linked into ~/.claude/skills/ (user scope - all projects)"
}

# 2. Companion hook: user scope, so superpowers code reviews trigger the
#    multi-model-verify reminder in every project, not just this repo.
$userHooksDir = Join-Path $env:USERPROFILE '.claude\hooks'
$userSettingsPath = Join-Path $env:USERPROFILE '.claude\settings.json'
New-Item -ItemType Directory -Force $userHooksDir | Out-Null
Copy-Item (Join-Path $root 'dev\claude-hooks\superpowers-review-companion.ps1') `
    (Join-Path $userHooksDir 'superpowers-review-companion.ps1') -Force
Write-Host "[install] ~/.claude/hooks/superpowers-review-companion.ps1 refreshed from dev/claude-hooks/"

$entry = [pscustomobject]@{
    matcher = 'Task'
    hooks   = @([pscustomobject]@{
        type          = 'command'
        command       = 'pwsh'
        args          = @('-NoProfile', '-NonInteractive', '-Command',
                          '& "$env:USERPROFILE/.claude/hooks/superpowers-review-companion.ps1"; exit $LASTEXITCODE')
        timeout       = 10
        statusMessage = 'review companion'
    })
}

if (-not (Test-Path $userSettingsPath)) {
    [pscustomobject]@{ hooks = [pscustomobject]@{ PostToolUse = @($entry) } } |
        ConvertTo-Json -Depth 10 | Set-Content $userSettingsPath -Encoding UTF8
    Write-Host "[install] ~/.claude/settings.json created with the review-companion hook"
} else {
    $settings = Get-Content $userSettingsPath -Raw | ConvertFrom-Json
    $changed = $false
    if (-not ($settings.PSObject.Properties.Name -contains 'hooks')) {
        $settings | Add-Member -MemberType NoteProperty -Name 'hooks' -Value ([pscustomobject]@{ PostToolUse = @($entry) })
        $changed = $true
    } elseif (-not ($settings.hooks.PSObject.Properties.Name -contains 'PostToolUse')) {
        $settings.hooks | Add-Member -MemberType NoteProperty -Name 'PostToolUse' -Value @($entry)
        $changed = $true
    } else {
        $present = $false
        foreach ($e in @($settings.hooks.PostToolUse)) {
            foreach ($h in @($e.hooks)) {
                $blob = (@($h.args) -join ' ') + ' ' + [string]$h.command
                if ($blob -match 'superpowers-review-companion\.ps1') { $present = $true; break }
            }
            if ($present) { break }
        }
        if (-not $present) {
            $settings.hooks.PostToolUse = @($settings.hooks.PostToolUse) + $entry
            $changed = $true
        }
    }
    if ($changed) {
        $settings | ConvertTo-Json -Depth 10 | Set-Content $userSettingsPath -Encoding UTF8
        Write-Host "[install] review-companion hook entry merged into ~/.claude/settings.json"
    } else {
        Write-Host "[install] ~/.claude/settings.json already has the review-companion hook"
    }
}

Write-Host "[install] done - Claude Code picks up skills and hooks on next session start"

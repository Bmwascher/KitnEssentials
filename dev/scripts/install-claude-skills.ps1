# Installs the repo's tracked Claude Code skills (dev/claude-skills/<name>/)
# into the user-level skills directory (~/.claude/skills/<name>) as directory
# junctions, so every KitnDev project picks them up and repo edits are live
# without re-installing.
#
#   pwsh dev/scripts/install-claude-skills.ps1
#
# Idempotent: correct junctions are left alone, stale junctions are
# re-pointed, and a real directory at the target is never clobbered (warns
# instead). The evals/ folder is repo-side CI tooling, not a skill - skipped.

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

Write-Host "[install] done - Claude Code picks up skills on next session start"

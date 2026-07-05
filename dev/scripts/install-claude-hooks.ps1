# Restores the local dev gates after a re-clone or PC reset. Everything under
# .claude/ is gitignored, so the live hooks die with the checkout; these
# tracked templates (dev/claude-hooks/) are the durable copies.
#
#   pwsh dev/scripts/install-claude-hooks.ps1
#
# Idempotent: copies the hook scripts, merges the hooks block into
# .claude/settings.json only when absent (never overwrites an existing hooks
# config or personal permissions), and sets core.hooksPath for the pre-push
# gate. Safe to re-run any time.

$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$templates = Join-Path $root 'dev\claude-hooks'
$hooksDir = Join-Path $root '.claude\hooks'
$settingsPath = Join-Path $root '.claude\settings.json'

# 1. Hook scripts: template copies are canonical - always refresh.
New-Item -ItemType Directory -Force $hooksDir | Out-Null
foreach ($name in @('branch-guard.ps1', 'luacheck-postedit.ps1')) {
    Copy-Item (Join-Path $templates $name) (Join-Path $hooksDir $name) -Force
    Write-Host "[install] .claude/hooks/$name refreshed from dev/claude-hooks/"
}

# 2. settings.json: create from template, or inject the hooks block if the
#    file exists without one. An existing hooks block is left untouched -
#    diff against dev/claude-hooks/settings.template.json by hand if needed.
$template = Get-Content (Join-Path $templates 'settings.template.json') -Raw | ConvertFrom-Json
if (-not (Test-Path $settingsPath)) {
    Copy-Item (Join-Path $templates 'settings.template.json') $settingsPath
    Write-Host "[install] .claude/settings.json created from template"
} else {
    $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
    if ($settings.PSObject.Properties.Name -contains 'hooks') {
        Write-Host "[install] .claude/settings.json already has a hooks block - left as is"
    } else {
        $settings | Add-Member -MemberType NoteProperty -Name 'hooks' -Value $template.hooks
        $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding UTF8
        Write-Host "[install] hooks block injected into existing .claude/settings.json"
    }
}

# 3. Pre-push gate (per-clone config; dies on re-clone without this).
$current = git -C $root config core.hooksPath 2>$null
if ($current -eq 'dev/githooks') {
    Write-Host "[install] core.hooksPath already dev/githooks"
} else {
    git -C $root config core.hooksPath dev/githooks
    Write-Host "[install] core.hooksPath set to dev/githooks (pre-push gate active)"
}

Write-Host "[install] done - Claude Code picks up hooks on next session start"

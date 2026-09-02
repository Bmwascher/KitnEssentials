# PreToolUse hook (Edit|Write): deny edits to addon code while the checkout is on main.
# Exempt: dev/, .claude/, References/, and any non-.lua/.xml file (TOC, CHANGELOG, README,
# docs) so the release workflow keeps working on main.
# The file's repo and branch come from git, asked at the file's nearest existing
# ancestor, so relative paths, 8.3 spellings, the symlinked AddOns folder and a file in
# a folder that does not exist yet all resolve to the same checkout instead of escaping
# a string-prefix check. When git is not on PATH the edit is denied rather than guessed.
# Output contract: silent exit 0 = allow; JSON permissionDecision=deny = block.

try {
    $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
} catch {
    exit 0
}

function Deny([string]$reason) {
    $out = @{
        hookSpecificOutput = @{
            hookEventName            = 'PreToolUse'
            permissionDecision       = 'deny'
            permissionDecisionReason = $reason
        }
    }
    $out | ConvertTo-Json -Compress -Depth 5
    exit 0
}

$file = $payload.tool_input.file_path
if (-not $file) { exit 0 }
if ($file -notmatch '\.(lua|xml)$') { exit 0 }

$base = $payload.cwd
if (-not $base) { $base = $env:CLAUDE_PROJECT_DIR }
if (-not $base) { $base = (Get-Location).Path }
try {
    $full = [System.IO.Path]::GetFullPath(($file -replace '/', '\'), ($base -replace '/', '\'))
} catch {
    exit 0
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Deny "git is not on PATH, so the branch of '$file' cannot be checked before editing addon code. Fix PATH and retry."
}

# Walk up to the nearest existing ancestor: a new file in a new folder still
# belongs to the repo above it.
$dir = Split-Path -Parent $full
$tail = @(Split-Path -Leaf $full)
while ($dir -and -not (Test-Path -LiteralPath $dir)) {
    $tail = @(Split-Path -Leaf $dir) + $tail
    $dir = Split-Path -Parent $dir
}
if (-not $dir) { exit 0 }

$prefix = (& git -C $dir rev-parse --show-prefix 2>$null)
if ($LASTEXITCODE -ne 0) { exit 0 }   # not inside any repo
$rel = (("$prefix".Trim() -replace '/', '\') + ($tail -join '\'))
if ($rel -match '^(dev|\.claude|References)\\') { exit 0 }

$branch = (& git -C $dir branch --show-current 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $branch) { exit 0 }
if ($branch.Trim() -ne 'main') { exit 0 }

Deny "Checkout is on 'main' and '$rel' is addon code (.lua/.xml). Project rule: never do feature work on main - create or switch to a feature branch first (git switch -c <branch>), then retry the edit. Release files (.toc, CHANGELOG, README, dev/) are exempt from this guard."

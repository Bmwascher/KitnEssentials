# PostToolUse hook (Edit|Write): run luacheck on the edited .lua file.
# Clean file -> exit 0 with zero output (costs no tokens).
# Warnings/errors -> exit 2 with luacheck output on stderr, which Claude Code
# feeds back to the model as blocking feedback so it fixes them immediately.
# The file's repo comes from git, asked from the file's own directory, so
# relative paths, 8.3 spellings and the symlinked AddOns folder are linted
# against the repo's own .luacheckrc instead of escaping a string-prefix check.

try {
    $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
} catch {
    exit 0
}

$file = $payload.tool_input.file_path
if (-not $file -or $file -notmatch '\.lua$') { exit 0 }

$base = $payload.cwd
if (-not $base) { $base = $env:CLAUDE_PROJECT_DIR }
if (-not $base) { $base = (Get-Location).Path }
try {
    $full = [System.IO.Path]::GetFullPath(($file -replace '/', '\'), ($base -replace '/', '\'))
} catch {
    exit 0
}
if (-not (Test-Path -LiteralPath $full)) { exit 0 }

$dir = Split-Path -Parent $full
$leaf = Split-Path -Leaf $full
$top = (& git -C $dir rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $top) { exit 0 }
$rootNorm = ($top.Trim() -replace '/', '\').TrimEnd('\')
if (-not (Test-Path -LiteralPath (Join-Path $rootNorm '.luacheckrc'))) { exit 0 }

$prefix = (& git -C $dir rev-parse --show-prefix 2>$null)
$rel = (("$prefix" -replace '/', '\').Trim() + $leaf)

# Fast-skip paths .luacheckrc excludes anyway (it also self-skips via exclude_files).
if ($rel -match '^(Libs|References)\\') { exit 0 }

$luacheck = (Get-Command luacheck -ErrorAction SilentlyContinue).Source
if (-not $luacheck) { $luacheck = Join-Path $env:LOCALAPPDATA 'Programs\luacheck\luacheck.exe' }
if (-not (Test-Path -LiteralPath $luacheck)) { exit 0 }  # tool missing: don't block every edit

# Lint by repo-relative path from the repo root so exclude_files and the
# per-directory overrides in .luacheckrc match the same spelling.
Set-Location -LiteralPath $rootNorm
$out = & $luacheck $rel --config .luacheckrc --no-color 2>&1
if ($LASTEXITCODE -eq 0) { exit 0 }

[Console]::Error.WriteLine((($out | Out-String).TrimEnd()))
[Console]::Error.WriteLine("luacheck reported issues in $rel - fix them now (config: .luacheckrc).")
exit 2

# PostToolUse hook (Edit|Write): run luacheck on the edited .lua file.
# Clean file -> exit 0 with zero output (costs no tokens).
# Warnings/errors -> exit 2 with luacheck output on stderr, which Claude Code
# feeds back to the model as blocking feedback so it fixes them immediately.

try {
    $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
} catch {
    exit 0
}

$file = $payload.tool_input.file_path
if (-not $file -or $file -notmatch '\.lua$') { exit 0 }

$root = $env:CLAUDE_PROJECT_DIR
if (-not $root) { exit 0 }

$full = ($file -replace '/', '\')
$rootNorm = ($root -replace '/', '\').TrimEnd('\')
if (-not $full.StartsWith($rootNorm + '\', [System.StringComparison]::OrdinalIgnoreCase)) { exit 0 }
if (-not (Test-Path -LiteralPath $full)) { exit 0 }

# Fast-skip paths .luacheckrc excludes anyway (it also self-skips via exclude_files).
$rel = $full.Substring($rootNorm.Length).TrimStart('\')
if ($rel -match '^(Libs|References)\\') { exit 0 }

$luacheck = (Get-Command luacheck -ErrorAction SilentlyContinue).Source
if (-not $luacheck) { $luacheck = Join-Path $env:LOCALAPPDATA 'Programs\luacheck\luacheck.exe' }
if (-not (Test-Path -LiteralPath $luacheck)) { exit 0 }  # tool missing: don't block every edit

Set-Location -LiteralPath $rootNorm
$out = & $luacheck $full --config .luacheckrc --no-color 2>&1
if ($LASTEXITCODE -eq 0) { exit 0 }

[Console]::Error.WriteLine((($out | Out-String).TrimEnd()))
[Console]::Error.WriteLine("luacheck reported issues in $rel - fix them now (config: .luacheckrc).")
exit 2

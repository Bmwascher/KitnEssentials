# SessionStart hook: bring the file map up to date with the checkout, so smoke
# steps name GUI locations from a current map. The script rebuilds only when
# its inputs changed since the map's stamp. Quiet when the map is current;
# otherwise prints the script's lines, or a note when it exits non-zero
# without one. Never blocks. Exit 0 always.

$root = $env:CLAUDE_PROJECT_DIR
if (-not $root) { exit 0 }
$script = Join-Path $root 'dev\scripts\file-map.lua'
if (-not (Test-Path -LiteralPath $script)) { exit 0 }
if (-not (Get-Command lua -ErrorAction SilentlyContinue)) {
    Write-Output '[file-map] note: lua is not on PATH, so the file map was not checked (dev/README.md has the toolchain setup).'
    exit 0
}

try {
    Push-Location -LiteralPath $root
    $out = & lua dev/scripts/file-map.lua --refresh 2>&1 | Out-String
    $code = $LASTEXITCODE
} catch {
    $out = $_.Exception.Message
    $code = 1
} finally {
    Pop-Location
}
$out = $out.Trim()
if ($code -ne 0 -and $out -notmatch '\[file-map\]') {
    Write-Output "[file-map] the refresh failed (exit $code); run lua dev/scripts/file-map.lua --refresh to see why:`n$out"
} elseif ($out -and $out -notmatch '^\[file-map\] current:') {
    Write-Output $out
}
exit 0

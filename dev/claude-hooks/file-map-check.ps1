# SessionStart hook: bring the file map up to date with the checkout, so smoke
# steps name GUI locations from a current map. The script rebuilds only when
# its inputs changed since the map's stamp. Quiet when the map is current;
# names the map when it rebuilt, kept the old one or found another run busy.
# Never blocks. Exit 0 always.

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
} catch {
    $out = ''
} finally {
    Pop-Location
}
if ($out -match '\[file-map\] (regenerated|kept|busy)') {
    Write-Output $out.Trim()
}
exit 0

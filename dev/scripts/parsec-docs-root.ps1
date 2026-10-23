# parsec-docs-root.ps1 - print the parsec docs root, or with -Primary the
# primary checkout.
#
#   pwsh dev/scripts/parsec-docs-root.ps1 [-Root <checkout>] [-Primary]
#
# The docs root is `docs_root` in the PRIMARY checkout's .claude/parsec.toml,
# the one setting parsec, the ke-workflow mod and these scripts share. An
# absolute value is used as is; a relative one resolves under the primary.
# With no config, or no docs_root line, it is <primary>\dev\docs\parsec. A
# docs_root line this cannot read is an error, never the fallback: once the
# root has moved, the fallback would grow a second docs root. Existence is not
# checked here; each caller decides what a missing root means.

param(
    [string]$Root,
    [switch]$Primary
)

$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Join-Path $PSScriptRoot '..\..' }
$checkout = (Resolve-Path -LiteralPath $Root).Path

# The first worktree git lists is the primary; outside a repository the
# checkout stands in for it.
$primaryPath = $checkout
$list = & git -C $checkout worktree list --porcelain 2>$null
if ($LASTEXITCODE -eq 0) {
    $first = @($list | Where-Object { $_ -like 'worktree *' } | Select-Object -First 1)
    if ($first.Count) { $primaryPath = [System.IO.Path]::GetFullPath($first[0].Substring(9)) }
}
if ($Primary) { Write-Output $primaryPath; exit 0 }

$docs = 'dev/docs/parsec'
$toml = Join-Path $primaryPath '.claude\parsec.toml'
if (Test-Path -LiteralPath $toml -PathType Leaf) {
    $text = [string](Get-Content -LiteralPath $toml -Raw)
    if ($text -match '(?m)^docs_root\s*=') {
        $m = [regex]::Match($text, '(?m)^docs_root\s*=\s*"([^"]+)"')
        if (-not $m.Success) { throw "[docs-root] cannot read docs_root in $toml" }
        $docs = $m.Groups[1].Value
    }
}
$full = if ([System.IO.Path]::IsPathRooted($docs)) { $docs } else { Join-Path $primaryPath $docs }
Write-Output ([System.IO.Path]::GetFullPath($full))
exit 0

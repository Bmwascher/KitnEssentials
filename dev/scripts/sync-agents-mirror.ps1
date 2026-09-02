# Rebuilds .agents/skills/ (the Codex-facing mirror) from .claude/skills/ and
# .claude/commands/. Skills are copied verbatim, junction targets included;
# each command becomes .agents/skills/source-command-<name>/SKILL.md with the
# wrapper Codex expects; mirror entries with no source are removed.
#
#   pwsh dev/scripts/sync-agents-mirror.ps1          rebuild
#   pwsh dev/scripts/sync-agents-mirror.ps1 -Check   report drift, exit 1 if any
#
# Both trees are gitignored, so this is the only thing that keeps them equal;
# the agents-mirror-sync hook runs it after every edit under either source.

param([switch]$Check)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$skills = Join-Path $root '.claude\skills'
$commands = Join-Path $root '.claude\commands'
$mirror = Join-Path $root '.agents\skills'

function Get-TreeHash([string]$dir) {
    $files = Get-ChildItem -LiteralPath $dir -File -Recurse | Sort-Object { $_.FullName.Substring($dir.Length) }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $ms = New-Object System.IO.MemoryStream
    foreach ($f in $files) {
        $rel = [System.Text.Encoding]::UTF8.GetBytes($f.FullName.Substring($dir.Length))
        $ms.Write($rel, 0, $rel.Length)
        $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
        $ms.Write($bytes, 0, $bytes.Length)
    }
    return [System.BitConverter]::ToString($sha.ComputeHash($ms.ToArray())) -replace '-', ''
}

function Get-CommandWrapper([string]$name, [string]$path) {
    $text = [System.IO.File]::ReadAllText($path)
    $parts = $text -split '(?m)^---\s*$', 3
    if ($parts.Count -lt 3) { throw "$path has no frontmatter" }
    $desc = ''
    if ($parts[1] -match '(?m)^description:\s*(.+)$') { $desc = $Matches[1].Trim() }
    $desc = $desc.Trim('"')
    $body = $parts[2].TrimStart("`r", "`n")
    return "---`nname: `"source-command-$name`"`ndescription: `"$desc`"`n---`n`n# source-command-$name`n`nUse this skill when the user asks to run the migrated source command ``$name``.`n`n## Command Template`n`n$body"
}

$expected = @{}
foreach ($d in Get-ChildItem -LiteralPath $skills -Directory) { $expected[$d.Name] = @{ kind = 'skill'; src = $d.FullName } }
foreach ($f in Get-ChildItem -LiteralPath $commands -Filter '*.md' -File) { $expected["source-command-$($f.BaseName)"] = @{ kind = 'command'; src = $f.FullName } }

$drift = @()
New-Item -ItemType Directory -Force $mirror | Out-Null
foreach ($name in $expected.Keys) {
    $dest = Join-Path $mirror $name
    $e = $expected[$name]
    if ($e.kind -eq 'skill') {
        $same = (Test-Path $dest) -and ((Get-TreeHash $e.src) -eq (Get-TreeHash $dest))
        if (-not $same) {
            $drift += $name
            if (-not $Check) {
                if (Test-Path $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
                Copy-Item -LiteralPath $e.src -Destination $dest -Recurse
                Write-Host "[mirror] skill $name copied"
            }
        }
    } else {
        $want = Get-CommandWrapper ($name -replace '^source-command-', '') $e.src
        $file = Join-Path $dest 'SKILL.md'
        $have = if (Test-Path $file) { [System.IO.File]::ReadAllText($file) } else { '' }
        $extra = if (Test-Path $dest) { @(Get-ChildItem -LiteralPath $dest -Recurse | Where-Object { $_.FullName -ne $file }).Count } else { 0 }
        if ($have -ne $want -or $extra -gt 0) {
            $drift += $name
            if (-not $Check) {
                if (Test-Path $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
                New-Item -ItemType Directory -Force $dest | Out-Null
                [System.IO.File]::WriteAllText($file, $want, (New-Object System.Text.UTF8Encoding($false)))
                Write-Host "[mirror] command $name rewritten"
            }
        }
    }
}
foreach ($d in Get-ChildItem -LiteralPath $mirror) {
    if ($d.PSIsContainer -and $expected.ContainsKey($d.Name)) { continue }
    $drift += "$($d.Name) (orphan)"
    if (-not $Check) { Remove-Item -LiteralPath $d.FullName -Recurse -Force; Write-Host "[mirror] orphan $($d.Name) removed" }
}

if ($Check) {
    if ($drift.Count -gt 0) { Write-Host ("[mirror] drift: " + ($drift -join ', ')); exit 1 }
    Write-Host '[mirror] in sync'
    exit 0
}
if ($drift.Count -eq 0) { Write-Host '[mirror] already in sync' }
exit 0

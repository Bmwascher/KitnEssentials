# convert-scout-data.ps1: write KitnEssentials_Data/ScoutMobs.lua from a Lua data
# file holding three packed mob tables and an armor array. Run it again to
# refresh the table from a newer data file.
#
#   pwsh dev/scripts/convert-scout-data.ps1 -Source <path> -Out KitnEssentials_Data/ScoutMobs.lua
#
# Each packed table is base64 over raw deflate over CBOR. Abilities and stats are
# flat arrays, [npc, row, npc, row, ...]; the tameable table is [0, [npc, ...]].
# The output stores the table's Lua source as a long string, one mob per line, in
# the form Wrap in dev/scripts/_data_source.lua defines; dev/spec/data_build_spec.lua
# fails when this file's output leaves that form. PowerShell because Lua 5.1 has
# no inflate. Prints the table sizes. Anything unreadable, or a source holding the
# closing long-bracket, stops the run.

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Source,
    [Parameter(Mandatory)] [string] $Out
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

class CborReader {
    hidden [byte[]] $Bytes
    hidden [int] $At = 0

    CborReader([byte[]] $bytes) {
        $this.Bytes = $bytes
    }

    hidden [long] ReadArgument([int] $info) {
        if ($info -lt 24) { return $info }
        if ($info -gt 27) { throw "unsupported CBOR argument $info" }
        $size = 1 -shl ($info - 24)
        [long] $value = 0
        for ($k = 0; $k -lt $size; $k++) {
            $value = $value * 256 + $this.Bytes[$this.At]
            $this.At++
        }
        return $value
    }

    [object] Read() {
        $head = [int] $this.Bytes[$this.At]
        $this.At++
        $major = $head -shr 5
        $info = $head -band 31
        if ($major -eq 4 -and $info -eq 31) {
            $list = [System.Collections.Generic.List[object]]::new()
            while ($this.Bytes[$this.At] -ne 0xFF) { $list.Add($this.Read()) }
            $this.At++
            return $list
        }
        $argument = $this.ReadArgument($info)
        if ($major -eq 0) { return $argument }
        if ($major -eq 1) { return -1 - $argument }
        if ($major -eq 4) {
            $list = [System.Collections.Generic.List[object]]::new()
            for ($k = 0; $k -lt $argument; $k++) { $list.Add($this.Read()) }
            return $list
        }
        if ($major -eq 6) { return $this.Read() }
        throw "unsupported CBOR major type $major"
    }
}

function Resolve-CliPath([string] $path) {
    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)
}

function Read-PackedTable([string] $text, [string] $name) {
    $match = [regex]::Match($text, "ns\.$name\s*=\s*""([^""]+)""")
    if (-not $match.Success) { throw "no $name in the data file" }
    $packed = [IO.MemoryStream]::new([Convert]::FromBase64String($match.Groups[1].Value))
    $deflate = [IO.Compression.DeflateStream]::new($packed, [IO.Compression.CompressionMode]::Decompress)
    $plain = [IO.MemoryStream]::new()
    $deflate.CopyTo($plain)
    $deflate.Dispose()
    return , [CborReader]::new($plain.ToArray()).Read()
}

function ConvertTo-SortedMap($flat) {
    $map = [System.Collections.Generic.SortedDictionary[long, object]]::new()
    for ($i = 0; $i -lt $flat.Count; $i += 2) {
        $map[[long] $flat[$i]] = $flat[$i + 1]
    }
    return , $map
}

function Format-Numbers($values) {
    return '{' + (@($values | ForEach-Object { ([long] $_).ToString([cultureinfo]::InvariantCulture) }) -join ',') + '}'
}

function Format-StatsRow($row) {
    $trimmed = [System.Collections.Generic.List[long]]::new()
    foreach ($value in $row) { $trimmed.Add([long] $value) }
    while ($trimmed.Count -gt 0 -and $trimmed[$trimmed.Count - 1] -eq 0) {
        $trimmed.RemoveAt($trimmed.Count - 1)
    }
    if ($trimmed.Count -eq 0) { return '0' }
    if ($trimmed.Count -eq 1) { return $trimmed[0].ToString([cultureinfo]::InvariantCulture) }
    return Format-Numbers $trimmed
}

$text = [IO.File]::ReadAllText((Resolve-CliPath $Source))

$abilities = ConvertTo-SortedMap (Read-PackedTable $text 'ScoutAbilitiesPacked')
$stats = ConvertTo-SortedMap (Read-PackedTable $text 'ScoutStatsPacked')

$tamePacked = Read-PackedTable $text 'ScoutTameablePacked'
if ($tamePacked.Count -lt 2 -or $tamePacked[1] -isnot [System.Collections.Generic.List[object]]) {
    throw 'the tameable table is not [0, [npc, ...]]'
}
$tame = [long[]] @($tamePacked[1] | ForEach-Object { [long] $_ })
[array]::Sort($tame)

$armorMatch = [regex]::Match($text, 'ns\.ScoutArmor\s*=\s*\{([^}]+)\}')
if (-not $armorMatch.Success) { throw 'no ScoutArmor in the data file' }
$armor = @($armorMatch.Groups[1].Value -split ',' | Where-Object { $_.Trim() } | ForEach-Object { [long] $_.Trim() })

$body = [Text.StringBuilder]::new()
[void] $body.Append("return {`nabilities={`n")
foreach ($entry in $abilities.GetEnumerator()) {
    [void] $body.Append("[$($entry.Key)]=$(Format-Numbers $entry.Value),`n")
}
[void] $body.Append("},stats={`n")
foreach ($entry in $stats.GetEnumerator()) {
    [void] $body.Append("[$($entry.Key)]=$(Format-StatsRow $entry.Value),`n")
}
[void] $body.Append("},tame={`n")
foreach ($npc in $tame) {
    [void] $body.Append("[$npc]=true,`n")
}
[void] $body.Append("},armor=$(Format-Numbers $armor)}`n")

$sourceText = $body.ToString()
if ($sourceText.Contains(']==]')) { throw 'ScoutMobs holds ]==], which would end its long string' }

$output = "local KE = KitnEssentials:GetNamespace()`n" +
    "-- Generated by dev/scripts/convert-scout-data.ps1. Do not edit by hand.`n`n" +
    "KE.DataSources = KE.DataSources or {}`n" +
    "KE.DataSources.ScoutMobs = [==[`n" +
    $sourceText +
    "]==]`n"

[IO.File]::WriteAllText((Resolve-CliPath $Out), $output, [Text.UTF8Encoding]::new($false))

$union = [System.Collections.Generic.HashSet[long]]::new()
foreach ($key in $abilities.Keys) { [void] $union.Add($key) }
foreach ($key in $stats.Keys) { [void] $union.Add($key) }
Write-Output "mobs $($union.Count), abilities $($abilities.Count), stats $($stats.Count), tameable $($tame.Count), armor $($armor.Count)"

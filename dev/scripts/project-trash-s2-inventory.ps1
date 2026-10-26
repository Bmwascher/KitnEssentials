# Projects the pinned source inventory (JSON: an independent pure-literal
# parse of the source package) into dev/data/trash-s2-inventory.lua, which the
# promote step compares with a candidate row by row and trait by trait. Two
# pinned rows take a 26 s cooldown in place of the record's value; nothing
# else is changed. Deterministic: rows by map, NPC and spell ID, traits by map
# and NPC, LF line endings, UTF-8 without a byte-order mark. Writes only the
# -Out path. It validates nothing itself: a malformed record stops it with
# PowerShell's own error, and the promote step compares its output. No
# network access.
#
#   pwsh -NoProfile -File dev/scripts/project-trash-s2-inventory.ps1 -Json <data-inventory.json> -Out <file.lua>
param(
    [Parameter(Mandatory = $true)][string]$Json,
    [Parameter(Mandatory = $true)][string]$Out
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$maps = @(1762, 1877, 2521, 2813, 2825, 2859, 2923, 2993)
$rowFields = @('castTime', 'channelTime', 'first', 'cd', 'cdMode', 'openingCastOrder',
    'targetExists', 'targetAPIExists', 'targetHostile')
$identityFields = @('level', 'power', 'nonElite', 'hasCastSkill', 'noCastSkill', 'hasCastSpell',
    'hasChannelSpell', 'hasInterruptFlag', 'cannotInterrupt', 'isLieutenant', 'hasCreatureFamily',
    'preCombatChanneling', 'bossEncounter', 'groupHasLevel90', 'groupHasCreatureFamily',
    'groupHasLevel90Power0')
# These two rows' cooldown is 26 s, in place of the record's value.
$amended = @{ '1877:134600:1308113' = 26; '2521:190206:385536' = 26 }

# A field the record leaves out reads as $null, like an explicit null.
function Get-Field($Object, [string]$Name) {
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function ConvertTo-LuaScalar($Value) {
    if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }
    if ($Value -is [string]) { return '"' + $Value.Replace('\', '\\').Replace('"', '\"') + '"' }
    return ([System.IFormattable]$Value).ToString($null, [System.Globalization.CultureInfo]::InvariantCulture)
}

# The record writes a source list as an object keyed "1", "2", ..., and a
# set as an object keyed by ID; -Keys projects a set to its sorted IDs.
function ConvertTo-LuaList($Object, [switch]$Keys) {
    $properties = @($Object.PSObject.Properties | Sort-Object -Property { [double]$_.Name })
    $items = @(foreach ($p in $properties) {
        if ($Keys) { ConvertTo-LuaScalar ([long]$p.Name) } else { ConvertTo-LuaScalar $p.Value }
    })
    if ($items.Count -eq 0) { return '{}' }
    return '{ ' + ($items -join ', ') + ' }'
}

# $Name is the English NPC name, which the record holds only for NPCs with
# timer rows; an identity-only trait gets none.
function ConvertTo-Trait([long]$Map, $Source, $Name) {
    $npc = [long]$Source.npcID
    $parts = @("$Map", "$npc")
    if ($null -ne $Name) { $parts += "name = $(ConvertTo-LuaScalar ([string]$Name))" }
    foreach ($field in $identityFields) {
        $value = Get-Field $Source $field
        if ($null -ne $value) { $parts += "$field = $(ConvertTo-LuaScalar $value)" }
    }
    # An empty set ships as absent, as the generator's set conversion does.
    foreach ($pair in @(@('mapIDs', 'uiMapIDs'), @('coPresenceNPCIDs', 'coPresenceNPCIDs'))) {
        $value = Get-Field $Source $pair[0]
        if ($null -ne $value -and @($value.PSObject.Properties).Count -gt 0) {
            $parts += "$($pair[1]) = $(ConvertTo-LuaList $value -Keys)"
        }
    }
    $rooms = Get-Field $Source 'wmoAreaIDs'
    if ($null -ne $rooms -and @($rooms.PSObject.Properties).Count -gt 0) {
        $parts += "rooms = $(@($rooms.PSObject.Properties).Count)"
    }
    $boss = Get-Field $Source 'boss'
    if ($null -ne $boss) { $parts += "placement = $(ConvertTo-LuaScalar ([string]$boss))" }
    foreach ($field in 'castTimeSet', 'channelTimeSet') {
        $value = Get-Field $Source $field
        if ($null -ne $value -and [string]$value -ne '') {
            $items = @(([string]$value).Split('/', [System.StringSplitOptions]::RemoveEmptyEntries) |
                ForEach-Object { ConvertTo-LuaScalar ([double]$_) })
            if ($items.Count -gt 0) { $parts += "$field = { $($items -join ', ') }" }
        }
    }
    $ids = Get-Field $Source 'spellIDs'
    if ($null -ne $ids) { $parts += "spellIDs = $(ConvertTo-LuaList $ids)" }
    return [pscustomobject]@{ Map = $Map; Npc = $npc; Text = '{ ' + ($parts -join ', ') + ' }' }
}

$sha = (Get-FileHash -LiteralPath $Json -Algorithm SHA256).Hash.ToLowerInvariant()
$doc = Get-Content -LiteralPath $Json -Raw -Encoding UTF8 | ConvertFrom-Json

$rows = [System.Collections.Generic.List[object]]::new()
$traits = [System.Collections.Generic.List[object]]::new()
foreach ($dungeon in @($doc.installed_inventory)) {
    $map = [long]$dungeon.instance_id
    if ($maps -notcontains $map) { continue }
    foreach ($mob in @($dungeon.mobs)) {
        $npc = [long]$mob.npc
        $npcName = Get-Field $mob 'name_enus_exdb'
        foreach ($spell in @($mob.spells)) {
            $id = [long]$spell.id
            $key = '{0}:{1}:{2}' -f $map, $npc, $id
            $parts = @("$map", "$npc", "$id")
            if ($null -ne $npcName) { $parts += "npcName = $(ConvertTo-LuaScalar ([string]$npcName))" }
            # The presentation defaults, by the generator's rules: the preset's
            # nameplate flag when it sets one, else true; text when the timer
            # bar is off, else bar; each role on unless set to false.
            $preset = Get-Field $spell 'preset'
            $show, $display, $tank, $healer, $dps = $true, 'bar', $true, $true, $true
            if ($null -ne $preset) {
                $flag = Get-Field $preset 'showNameplate'
                if ($null -ne $flag) { $show = ($flag -eq $true) }
                if ((Get-Field $preset 'showTimerBar') -eq $false) { $display = 'text' }
                $tank = (Get-Field $preset 'tankEnabled') -ne $false
                $healer = (Get-Field $preset 'healerEnabled') -ne $false
                $dps = (Get-Field $preset 'dpsEnabled') -ne $false
            }
            $parts += "showNameplate = $(ConvertTo-LuaScalar $show)"
            $parts += "display = $(ConvertTo-LuaScalar $display)"
            $parts += ('roles = {{ tank = {0}, healer = {1}, dps = {2} }}' -f
                (ConvertTo-LuaScalar $tank), (ConvertTo-LuaScalar $healer), (ConvertTo-LuaScalar $dps))
            foreach ($field in $rowFields) {
                $value = Get-Field $spell.data $field
                if ($field -eq 'cd' -and $amended.ContainsKey($key)) { $value = [pscustomobject]@{ '1' = $amended[$key] } }
                if ($null -eq $value) { continue }
                if ($field -eq 'cd') { $parts += "cd = $(ConvertTo-LuaList $value)" }
                else { $parts += "$field = $(ConvertTo-LuaScalar $value)" }
            }
            $rows.Add([pscustomobject]@{ Map = $map; Npc = $npc; Spell = $id; Text = '{ ' + ($parts -join ', ') + ' }' })
        }
        $trait = Get-Field $mob 'traits'
        if ($null -ne $trait) { $traits.Add((ConvertTo-Trait $map $trait $npcName)) }
    }
    foreach ($only in @($dungeon.trait_only)) { $traits.Add((ConvertTo-Trait $map $only.data $null)) }
}
$sortedRows = @($rows | Sort-Object -Property Map, Npc, Spell)
$sortedTraits = @($traits | Sort-Object -Property Map, Npc)

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('-- Generated by dev/scripts/project-trash-s2-inventory.ps1 from the pinned')
$lines.Add('-- source inventory. Do not edit; regenerate it instead.')
$lines.Add('return {')
$lines.Add("    sourceSha256 = `"$sha`",")
$lines.Add('    rows = {')
foreach ($row in $sortedRows) { $lines.Add("        $($row.Text),") }
$lines.Add('    },')
$lines.Add('    traits = {')
foreach ($trait in $sortedTraits) { $lines.Add("        $($trait.Text),") }
$lines.Add('    },')
$lines.Add('}')
$text = ($lines -join "`n") + "`n"

$outPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Out)
[System.IO.File]::WriteAllText($outPath, $text, [System.Text.UTF8Encoding]::new($false))
Write-Output ('rows {0} traits {1} sha256 {2}' -f $sortedRows.Count, $sortedTraits.Count, $sha)

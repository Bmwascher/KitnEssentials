-- The reference preset is the authority on WHICH spells exist. Which of them
-- ship switched on is a KitnEssentials product decision, so the shipped-off
-- set lives here and is asserted exactly. A source row marked disabled must
-- still be disabled locally; the reverse is allowed.
local SHIPPED_DISABLED = {
    [1784] = true,    -- Stealth
    [31230] = true,   -- Cheat Death
    [55342] = true,   -- Mirror Image
    [79206] = true,   -- Spiritwalker's Grace
    [101545] = true,  -- Flying Serpent Kick
    [110960] = true,  -- Greater Invisibility
    [333889] = true,  -- Fel Domination
    [358267] = true,  -- Hover
    [358733] = true,  -- Glide
    [387626] = true,  -- Soulburn
    [406732] = true,  -- Spatial Paradox
    [432180] = true,  -- Dance of the Wind
    -- Time Spiral lands under a different spell id per recipient class.
    [375226] = true, [375229] = true, [375230] = true, [375234] = true,
    [375238] = true, [375240] = true, [375252] = true, [375253] = true,
    [375254] = true, [375255] = true, [375256] = true, [375257] = true,
    [375258] = true,
}

local function ReadFile(path)
    local file, err = io.open(path, "rb")
    assert(file, err)
    local content = file:read("*a")
    file:close()
    return content
end

-- References/ is gitignored, so CI has the local catalog but not the preset it
-- was flattened from. Rather than fail there or pass silently, the source
-- cross-check is skipped and the skip is printed: the local-only assertions
-- below still run, and they are the half that catches an edit to Defaults.lua.
local function ReadOptionalFile(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local content = file:read("*a")
    file:close()
    return content
end

local function ExtractBlock(content, pattern, label)
    local block = content:match(pattern)
    assert(block, "could not locate " .. label)
    return block
end

local sourcePath =
    "References/EllesmereUI/EllesmereUI-v9.0.7/EllesmereUI/EllesmereUI_BuffPresets.lua"
local source = ReadOptionalFile(sourcePath)
local defaults = ReadFile("Core/Defaults.lua")

local function Count(map)
    local count = 0
    for _ in pairs(map) do count = count + 1 end
    return count
end

---------------------------------------------------------------------------------
-- Local catalog -- always checked.
---------------------------------------------------------------------------------

local defaultsBlock = ExtractBlock(
    defaults,
    "AuraMovement%s*=%s*{(.-)\n%s*},%s*\n%s*AuraDebuffs%s*=",
    "local AuraMovement block")
local allowlistBlock = ExtractBlock(
    defaultsBlock,
    "Allowlist%s*=%s*{(.-)\n%s*},%s*\n%s*GrowHorizontal%s*=",
    "local AuraMovement allowlist")

local localRows = {}
local cursor = 1
while true do
    local startPos, endPos, rawKey = allowlistBlock:find("%[([^%]]+)%]%s*=", cursor)
    if not startPos then break end

    local spellID = tonumber(rawKey)
    assert(spellID and spellID > 0 and spellID == math.floor(spellID),
        "local allowlist key is not a positive integer: " .. rawKey)
    localRows[#localRows + 1] = { startPos = startPos, spellID = spellID }
    cursor = endPos + 1
end

local localState = {}
for i = 1, #localRows do
    local row = localRows[i]
    local nextStart = localRows[i + 1] and localRows[i + 1].startPos or (#allowlistBlock + 1)
    local segment = allowlistBlock:sub(row.startPos, nextStart - 1)
    local parsedID, enabled, default = segment:match(
        "^%s*%[(%d+)%]%s*=%s*{%s*enabled%s*=%s*(%a+)%s*,%s*default%s*=%s*(%a+)%s*}%s*,?%s*$")

    assert(parsedID, "malformed local row for key " .. row.spellID)
    local id = tonumber(parsedID)
    assert(id == row.spellID, "local row key parse mismatch for " .. row.spellID)
    assert(enabled == "true" or enabled == "false", "invalid enabled state for " .. id)
    assert(default == "true", "local row is not marked default: " .. id)
    assert(localState[id] == nil, "duplicate local row " .. id)
    localState[id] = enabled == "true"
end

local enabledCount = 0
local disabledCount = 0
for spellID, isEnabled in pairs(localState) do
    if isEnabled then
        assert(not SHIPPED_DISABLED[spellID],
            "spell " .. spellID .. " is in SHIPPED_DISABLED but ships enabled")
        enabledCount = enabledCount + 1
    else
        assert(SHIPPED_DISABLED[spellID],
            "spell " .. spellID .. " ships disabled but is not in SHIPPED_DISABLED")
        disabledCount = disabledCount + 1
    end
end
for spellID in pairs(SHIPPED_DISABLED) do
    assert(localState[spellID] ~= nil,
        "SHIPPED_DISABLED lists " .. spellID .. ", which is not in the catalog")
end

assert(Count(localState) == 85, "expected 85 unique local ids, got " .. Count(localState))
assert(disabledCount == Count(SHIPPED_DISABLED),
    "expected " .. Count(SHIPPED_DISABLED) .. " disabled ids, got " .. disabledCount)
assert(enabledCount == 85 - disabledCount,
    "expected " .. (85 - disabledCount) .. " enabled ids, got " .. enabledCount)

---------------------------------------------------------------------------------
-- Source cross-check -- only when the gitignored reference is present.
---------------------------------------------------------------------------------

if not source then
    print(string.format(
        "Movement catalog OK (local only, source cross-check SKIPPED -- %s absent): "
        .. "85 unique IDs, %d enabled, %d disabled",
        sourcePath, enabledCount, disabledCount))
    return
end

local sourceBlock = ExtractBlock(
    source,
    "movement%s*=%s*{(.-)\n%s*},%s*\n%s*utility%s*=",
    "source movement block")

local rows = {}
cursor = 1
while true do
    local startPos, endPos, spellID = sourceBlock:find("%[(%d+)%]%s*=", cursor)
    if not startPos then break end
    rows[#rows + 1] = { startPos = startPos, spellID = tonumber(spellID) }
    cursor = endPos + 1
end

local sourceState = {}
local alternateCount = 0
for i = 1, #rows do
    local row = rows[i]
    local nextStart = rows[i + 1] and rows[i + 1].startPos or (#sourceBlock + 1)
    local segment = sourceBlock:sub(row.startPos, nextStart - 1)
    local enabled = not segment:find("disabled%s*=%s*true")

    assert(sourceState[row.spellID] == nil, "duplicate primary " .. row.spellID)
    sourceState[row.spellID] = enabled

    local altBody = segment:match("alts%s*=%s*{(.-)}")
    if altBody then
        for alt in altBody:gmatch("%d+") do
            local altID = tonumber(alt)
            alternateCount = alternateCount + 1
            assert(sourceState[altID] == nil, "duplicate alternate " .. altID)
            sourceState[altID] = enabled
        end
    end
end

for spellID, sourceEnabled in pairs(sourceState) do
    assert(localState[spellID] ~= nil, "missing local spell " .. spellID)
    if not sourceEnabled then
        assert(SHIPPED_DISABLED[spellID],
            "source disables " .. spellID .. " but it is not in SHIPPED_DISABLED")
    end
end
for spellID in pairs(localState) do
    assert(sourceState[spellID] ~= nil, "extra local spell " .. spellID)
end

assert(#rows == 52, "expected 52 primaries, got " .. #rows)
assert(alternateCount == 33, "expected 33 alternates, got " .. alternateCount)
assert(Count(sourceState) == 85, "expected 85 unique source ids")

print(string.format(
    "Movement catalog OK: 52 primaries, 33 alternates, 85 unique IDs, %d enabled, %d disabled",
    enabledCount, disabledCount))

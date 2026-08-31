local function ReadFile(path)
    local file, err = io.open(path, "rb")
    assert(file, err)
    local content = file:read("*a")
    file:close()
    return content
end

local function ExtractBlock(content, pattern, label)
    local block = content:match(pattern)
    assert(block, "could not locate " .. label)
    return block
end

local source = ReadFile(
    "References/EllesmereUI/EllesmereUI-v9.0.7/EllesmereUI/EllesmereUI_BuffPresets.lua")
local defaults = ReadFile("Core/Defaults.lua")

local sourceBlock = ExtractBlock(
    source,
    "movement%s*=%s*{(.-)\n%s*},%s*\n%s*utility%s*=",
    "source movement block")
local defaultsBlock = ExtractBlock(
    defaults,
    "AuraMovement%s*=%s*{(.-)\n%s*},%s*\n%s*AuraDebuffs%s*=",
    "local AuraMovement block")
local allowlistBlock = ExtractBlock(
    defaultsBlock,
    "Allowlist%s*=%s*{(.-)\n%s*},%s*\n%s*GrowHorizontal%s*=",
    "local AuraMovement allowlist")

local rows = {}
local cursor = 1
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

local localRows = {}
cursor = 1
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

local function Count(map)
    local count = 0
    for _ in pairs(map) do count = count + 1 end
    return count
end

local enabledCount = 0
local disabled = {}
for spellID, enabled in pairs(sourceState) do
    assert(localState[spellID] ~= nil, "missing local spell " .. spellID)
    assert(localState[spellID] == enabled, "enabled-state mismatch for " .. spellID)
    if enabled then
        enabledCount = enabledCount + 1
    else
        disabled[#disabled + 1] = spellID
    end
end
for spellID in pairs(localState) do
    assert(sourceState[spellID] ~= nil, "extra local spell " .. spellID)
end

table.sort(disabled)
assert(#rows == 52, "expected 52 primaries, got " .. #rows)
assert(alternateCount == 33, "expected 33 alternates, got " .. alternateCount)
assert(Count(sourceState) == 85, "expected 85 unique source ids")
assert(Count(localState) == 85, "expected 85 unique local ids")
assert(enabledCount == 84, "expected 84 enabled ids")
assert(#disabled == 1 and disabled[1] == 101545, "expected only 101545 disabled")

print("Movement catalog OK: 52 primaries, 33 alternates, 85 unique IDs, 84 enabled, 101545 disabled")

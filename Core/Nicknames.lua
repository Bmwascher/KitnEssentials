-- ╔══════════════════════════════════════════════════════════╗
-- ║  Nicknames.lua                                           ║
-- ║  Purpose: Backend for the Custom Nicknames feature —     ║
-- ║           serialization helpers for Import/Export and    ║
-- ║           bulk clear. Loads without ElvUI so the GUI     ║
-- ║           still functions for users who plan to install  ║
-- ║           ElvUI later (or are sharing a list with raid). ║
-- ╚══════════════════════════════════════════════════════════╝
---@class KE
local KE = select(2, ...)

local LibStub = LibStub
local type = type
local pairs = pairs
local wipe = wipe

-- Versioned prefix. Bump the digit if the payload shape ever changes so older
-- clients surface a clean error instead of decoding garbage.
local EXPORT_PREFIX = "!KEN1!"

local function GetSerializer()
    return LibStub and LibStub("AceSerializer-3.0", true)
end

local function GetDeflate()
    return LibStub and LibStub("LibDeflate", true)
end

local function GetDB()
    return KE.db and KE.db.global and KE.db.global.Nicknames
end

local function NotifyChange()
    if KE.RefreshNicknameTags then KE:RefreshNicknameTags() end
end

---------------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------------
-- Serializes the entire nickname table and returns an EncodeForPrint string
-- prefixed with EXPORT_PREFIX. Mirrors DungeonTimers' trigger export pipeline
-- (AceSerializer -> LibDeflate:CompressDeflate -> LibDeflate:EncodeForPrint).

---@return string|nil encoded, string|nil error, number|nil count
function KE:ExportNicknames()
    local nicks = GetDB()
    if not nicks then return nil, "Nicknames database not available" end

    local count = 0
    local payload = {}
    for key, nick in pairs(nicks) do
        if type(key) == "string" and type(nick) == "string" and nick ~= "" then
            payload[key] = nick
            count = count + 1
        end
    end
    if count == 0 then return nil, "No nicknames to export" end

    local Serializer = GetSerializer()
    local Deflate = GetDeflate()
    if not Serializer or not Deflate then return nil, "Missing libraries" end

    local serialized = Serializer:Serialize({ v = 1, d = payload })
    if not serialized then return nil, "Serialization failed" end

    local compressed = Deflate:CompressDeflate(serialized, { level = 9 })
    if not compressed then return nil, "Compression failed" end

    local encoded = Deflate:EncodeForPrint(compressed)
    if not encoded then return nil, "Encoding failed" end

    return EXPORT_PREFIX .. encoded, nil, count
end

---------------------------------------------------------------------------------
-- Import
---------------------------------------------------------------------------------
-- Decodes an export string and applies its entries to the nickname table.
-- Default is additive merge: existing entries are overwritten only when the
-- import contains the same "Name-Realm" key, and entries not present in the
-- import are left alone. When `replaceAll` is true, the local table is wiped
-- first so the final state equals the import payload exactly — useful for
-- sync-from-leader workflows where the import is the source of truth.

---@param importString string
---@param replaceAll boolean|nil wipe local entries before applying the import
---@return boolean success, string message
function KE:ImportNicknames(importString, replaceAll)
    if not importString or importString == "" then
        return false, "Import string is empty"
    end
    if importString:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then
        return false, "Invalid format — this doesn't look like a KE nicknames export"
    end

    local nicks = GetDB()
    if not nicks then return false, "Nicknames database not available" end

    local Serializer = GetSerializer()
    local Deflate = GetDeflate()
    if not Serializer or not Deflate then return false, "Missing libraries" end

    local encoded = importString:sub(#EXPORT_PREFIX + 1)

    local compressed = Deflate:DecodeForPrint(encoded)
    if not compressed then return false, "Failed to decode string" end

    local serialized = Deflate:DecompressDeflate(compressed)
    if not serialized then return false, "Failed to decompress" end

    local ok, data = Serializer:Deserialize(serialized)
    if not ok or type(data) ~= "table" or type(data.d) ~= "table" then
        return false, "Invalid export data"
    end

    -- Count removed entries under replaceAll BEFORE wiping so the summary
    -- line reports how many local entries the import displaced. We only
    -- count keys that aren't in the incoming payload (keys present in both
    -- get counted as either "added" or "updated" below, never "removed").
    local removed = 0
    if replaceAll then
        for key in pairs(nicks) do
            if data.d[key] == nil then removed = removed + 1 end
        end
        wipe(nicks)
    end

    local added, updated = 0, 0
    for key, nick in pairs(data.d) do
        if type(key) == "string" and type(nick) == "string" and nick ~= "" then
            if nicks[key] == nil then
                added = added + 1
            elseif nicks[key] ~= nick then
                updated = updated + 1
            end
            nicks[key] = nick
        end
    end

    if added == 0 and updated == 0 and removed == 0 then
        return false, "No nicknames were imported"
    end

    NotifyChange()

    local parts = {}
    if added > 0 then parts[#parts + 1] = added .. " added" end
    if updated > 0 then parts[#parts + 1] = updated .. " updated" end
    if removed > 0 then parts[#parts + 1] = removed .. " removed" end
    return true, table.concat(parts, ", ")
end

---------------------------------------------------------------------------------
-- Clear All
---------------------------------------------------------------------------------

---@return number cleared
function KE:ClearAllNicknames()
    local nicks = GetDB()
    if not nicks then return 0 end
    local count = 0
    for _ in pairs(nicks) do count = count + 1 end
    wipe(nicks)
    NotifyChange()
    return count
end

---------------------------------------------------------------------------------
-- Tag Refresh
---------------------------------------------------------------------------------
-- Invalidates cached tag output in each supported frame library after the
-- nicknames table changes. Defined here (rather than in Tags.lua) so it's
-- available in UUF-only setups where Tags.lua early-returns. Safe no-op if
-- neither lib is loaded.

function KE:RefreshNicknameTags()
    local ElvUF = _G.ElvUF
    if ElvUF and ElvUF.Tags and ElvUF.Tags.RefreshMethods then
        local names = KE._nickElvTagNames
        if names then
            for i = 1, #names do
                ElvUF.Tags:RefreshMethods(names[i])
            end
        end
    end
    local UUFG = _G.UUFG
    if UUFG and UUFG.UpdateAllTags then
        UUFG:UpdateAllTags()
    end
end

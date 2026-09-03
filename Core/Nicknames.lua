-- ╔══════════════════════════════════════════════════════════╗
-- ║  Nicknames.lua                                           ║
-- ║  Purpose: The nickname store, its serialization helpers, ║
-- ║           and the bridge to the external nickname        ║
-- ║           provider. The config page and the unit-frame   ║
-- ║           tags are gone. Read by the Damage Meter, Death ║
-- ║           Notifications and Healer Mana.                 ║
-- ╚══════════════════════════════════════════════════════════╝
---@class KE
local KE = select(2, ...)

local LibStub = LibStub
local type = type
local pairs = pairs
local wipe = wipe
local UnitName = UnitName
local UnitFullName = UnitFullName
local UnitIsPlayer = UnitIsPlayer
local GetNormalizedRealmName = GetNormalizedRealmName

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
-- Public Lookup
---------------------------------------------------------------------------------
-- Returns a nickname for a unit, or its UnitName when neither source has one.
-- KE's own store is consulted first, then the foreign source; the precedence
-- rule and the reason for it live in KE:ResolveNicknamePrecedence.
-- Key format is "Fullname-NormalizedRealm".
--
-- The secret test comes FIRST and the order is the point. UnitFullName is
-- secret when the unit's identity is restricted, and BOTH the emptiness
-- comparison below and the key concatenation are forbidden on a secret --
-- they are two distinct illegal operations, not one. Refusing here falls
-- through to the plain name, which is the same answer an unnamed player gets.
--
-- The fall-through `UnitName(unit) or ""` is deliberately unguarded. A truth
-- test on a secret string is permitted, so that line cannot throw; it hands
-- the secret string back untouched. Refusing it instead would make Healer
-- Mana render an empty name where it renders a real one today, because it
-- passes this value straight to SetText, which accepts a secret. The cost is
-- that a caller which COMPARES the result has to guard for itself.
---@param unit string Unit token (e.g., "player", "party2")
---@return string name Nickname from either source, else raw UnitName
function KE:GetNicknameOrName(unit)
    if not unit then return "" end
    if not UnitIsPlayer(unit) then
        return UnitName(unit) or ""
    end
    local name, realm = UnitFullName(unit)
    if issecretvalue(name) or issecretvalue(realm) then
        return UnitName(unit) or ""
    end
    local own
    local nicks = GetDB()
    if nicks and name and name ~= "" then
        if not realm or realm == "" then realm = GetNormalizedRealmName() end
        if realm and realm ~= "" then
            own = nicks[name .. "-" .. realm]
        end
    end
    -- Asked only on this plain path: a restricted identity returned above, and
    -- NSAPI would hand that secret straight back to be compared.
    local nick = self:ResolveNicknamePrecedence(own, self:GetNSRTNickname(unit), name)
    if nick then return nick end
    return UnitName(unit) or ""
end

-- Builds the store key ("Name-NormalizedRealm") from a raw name STRING (not a
-- unit token) as data APIs return them: "Name" for a same-realm player (the
-- caller passes its realm -- normally GetNormalizedRealmName() -- as the
-- fallback) or "Name-Realm" for a cross-realm one. Whichever side supplies the
-- realm, it is normalized defensively -- spaces / apostrophes / inner hyphens
-- stripped ("Twisting Nether" -> "TwistingNether", "Azjol-Nerub" ->
-- "AzjolNerub") -- so the key matches the UnitFullName-based store writes
-- whether or not the source already normalized it. A character name never
-- contains a hyphen, so the FIRST hyphen is always the separator. Pure string
-- helper (no store or unit reads): the Damage Meter render path memoizes
-- around it, and the busted spec drives it directly.
---@param rawName string|nil "Name" or "Name-Realm" (plain, never secret)
---@param fallbackRealm string|nil realm for suffix-less names
---@return string|nil key store key, or nil when either side is unresolvable
function KE:BuildNicknameKey(rawName, fallbackRealm)
    if type(rawName) ~= "string" or rawName == "" then return nil end
    local name, realm = rawName:match("^([^-]+)%-(.+)$")
    if not name then
        name, realm = rawName, fallbackRealm
    end
    if type(realm) ~= "string" then return nil end
    realm = realm:gsub("[%s'%-]", "")
    if realm == "" then return nil end
    return name .. "-" .. realm
end

---------------------------------------------------------------------------------
-- Foreign nickname source
---------------------------------------------------------------------------------
-- NSAPI refuses any key absent from its own settings, and there is no way to
-- register one. This is the key its own modules pass; it resolves to its
-- single Enable Nicknames switch.
local NSRT_ADDON_KEY = "GlobalNickNames"

-- skiptranslit stops NSAPI transliterating the name it returns; a rewritten
-- real name no longer matches what was asked, and reads as a nickname below.
-- issecretvalue precedes type() because NSAPI passes a secret straight back
-- for a restricted identity, and type() on a secret is illegal in itself.
---@param subject string unit token, "Name" or "Name-Realm"
---@return string|nil nickname
function KE:GetNSRTNickname(subject)
    local api = _G.NSAPI
    if not subject or not api or not api.GetName then return nil end
    local ok, nick = pcall(api.GetName, api, subject, NSRT_ADDON_KEY, true)
    if not ok or issecretvalue(nick) or type(nick) ~= "string" or nick == "" then
        return nil
    end
    return nick
end

-- KE's own store wins: a locally typed name beats a broadcast one.
--
-- Two refusals because NSAPI says "no nickname" two ways -- it echoes the
-- string it was given, or returns the BARE name when it resolved that string
-- as a unit. The Damage Meter asks with the realm-bearing form, so without the
-- second test every cross-realm player reads as nicknamed and ShowRealm stops
-- working. A real nickname equal to the bare name is refused with it; the two
-- are indistinguishable, and this is the side that never invents a nickname.
---@param own string|nil nickname from KE's own store
---@param foreign string|nil nickname from the foreign source
---@param realName string|nil the plain name the foreign source was asked about
---@return string|nil nickname resolved nickname, or nil for none
function KE:ResolveNicknamePrecedence(own, foreign, realName)
    if type(own) == "string" and own ~= "" then return own end
    if type(foreign) ~= "string" or foreign == "" then return nil end
    if type(realName) == "string" then
        if foreign == realName then return nil end
        local bare = realName:match("^([^-]+)")
        if bare and foreign == bare then return nil end
    end
    return foreign
end

---------------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------------
-- Serializes the entire nickname table and returns an EncodeForPrint string
-- prefixed with EXPORT_PREFIX. Mirrors DungeonTimers' trigger export pipeline
-- (AceSerializer -> LibDeflate:CompressDeflate -> LibDeflate:EncodeForPrint).

---@return string|nil encoded
---@return string|nil error
---@return number|nil count
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
---@return boolean success
---@return string message
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
-- Store-change Notification
---------------------------------------------------------------------------------
-- Tells the live readers that a nickname changed, from either source. This
-- used to fan out to ElvUI and UUF as well; KE registers no tags with either
-- any more, so both arms went. Reached by the import and clear paths and by
-- the foreign source's own change callback.

function KE:RefreshNicknameTags()
    local KEAddon = _G.KitnEssentials
    if not (KEAddon and KEAddon.GetModule) then return end
    -- The Damage Meter substitutes nicknames at render time behind memo tables
    -- (Modules/DamageMeter/Window.lua); tell it to drop them so a change
    -- repaints the bars instead of serving stale (or missing) nicknames.
    local DM = KEAddon:GetModule("DamageMeter", true)
    if DM and DM.OnNicknamesChanged then DM:OnNicknamesChanged() end
    -- containerFrame guard: FindHealers checks only db.Enabled, which is true
    -- on a profile change before OnEnable builds the container, and it faults
    -- on a nil frame there. Roster callers register inside OnEnable and so
    -- never hit that window; a nickname callback can.
    local HM = KEAddon:GetModule("HealerMana", true)
    if HM and HM.FindHealers and HM.containerFrame then HM:FindHealers() end
end

---------------------------------------------------------------------------------
-- Foreign-source change subscription
---------------------------------------------------------------------------------
-- NSAPI may load after KE, so registration retries until it takes. One
-- subscription is enough: its global toggle runs the same update funnel that
-- fires this event.

local nsrtHooked = false
local function RegisterNSRTCallback()
    if nsrtHooked then return end
    local api = _G.NSAPI
    if not api or not api.RegisterCallback then return end
    -- Dot call, not colon: CallbackHandler keys on the first argument, and a
    -- colon call would pass the API table itself and collide with every other
    -- addon doing the same.
    api.RegisterCallback("KitnEssentials", "NSRT_NICKNAME_UPDATED", function()
        if KE.RefreshNicknameTags then KE:RefreshNicknameTags() end
    end)
    nsrtHooked = true
end

local nsrtBoot = CreateFrame("Frame")
nsrtBoot:RegisterEvent("PLAYER_LOGIN")
nsrtBoot:RegisterEvent("PLAYER_ENTERING_WORLD")
nsrtBoot:SetScript("OnEvent", RegisterNSRTCallback)

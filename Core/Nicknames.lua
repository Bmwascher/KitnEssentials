-- ╔══════════════════════════════════════════════════════════╗
-- ║  Nicknames.lua                                           ║
-- ║  Purpose: The bridge to the external nickname provider,  ║
-- ║           the rule that decides whether its answer is a  ║
-- ║           nickname, and the Name-Realm key builder. Read ║
-- ║           by the Damage Meter, Death Notifications,      ║
-- ║           Healer Mana, the LFG Reminder and the Kick     ║
-- ║           Tracker (the key builder only).                ║
-- ╚══════════════════════════════════════════════════════════╝
---@class KE
local KE = select(2, ...)

local type = type
local UnitName = UnitName
local UnitFullName = UnitFullName
local UnitIsPlayer = UnitIsPlayer

---------------------------------------------------------------------------------
-- Public Lookup
---------------------------------------------------------------------------------
-- Returns the provider's nickname for a unit, or its UnitName when there is
-- none. Whether an answer counts as a nickname lives in
-- KE:ResolveNicknamePrecedence.
--
-- The secret test comes FIRST and the order is the point. UnitFullName is
-- secret when the unit's identity is restricted, and the provider would hand
-- that secret straight back to be compared. Refusing here falls through to the
-- plain name, which is the same answer an unnamed player gets.
--
-- The fall-through `UnitName(unit) or ""` is deliberately unguarded. A truth
-- test on a secret string is permitted, so that line cannot throw; it hands
-- the secret string back untouched. Refusing it instead would make Healer
-- Mana render an empty name where it renders a real one today, because it
-- passes this value straight to SetText, which accepts a secret. The cost is
-- that a caller which COMPARES the result has to guard for itself.
---@param unit string Unit token (e.g., "player", "party2")
---@return string name Nickname from the external provider, else raw UnitName
function KE:GetNicknameOrName(unit)
    if not unit then return "" end
    if not UnitIsPlayer(unit) then
        return UnitName(unit) or ""
    end
    local name, realm = UnitFullName(unit)
    if issecretvalue(name) or issecretvalue(realm) then
        return UnitName(unit) or ""
    end
    local nick = self:ResolveNicknamePrecedence(self:GetNSRTNickname(unit), name)
    if nick then return nick end
    return UnitName(unit) or ""
end

-- Builds the normalized "Name-NormalizedRealm" key from a raw name STRING (not
-- a unit token) as data APIs return them: "Name" for a same-realm player (the
-- caller passes its realm -- normally GetNormalizedRealmName() -- as the
-- fallback) or "Name-Realm" for a cross-realm one. Whichever side supplies the
-- realm, it is normalized defensively -- spaces / apostrophes / inner hyphens
-- stripped ("Twisting Nether" -> "TwistingNether", "Azjol-Nerub" ->
-- "AzjolNerub") -- so two spellings of one player give one key. A character
-- name never contains a hyphen, so the FIRST hyphen is always the separator.
-- Pure string helper (no unit reads): the Damage Meter render path memoizes
-- around it, and the busted spec drives it directly.
---@param rawName string|nil "Name" or "Name-Realm" (plain, never secret)
---@param fallbackRealm string|nil realm for suffix-less names
---@return string|nil key normalized key, or nil when either side is unresolvable
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
-- pcall because a third-party fault must not stop names drawing.
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

-- Two refusals because NSAPI says "no nickname" two ways -- it echoes the
-- string it was given, or returns the BARE name when it resolved that string
-- as a unit. The Damage Meter asks with the realm-bearing form, so without the
-- second test every cross-realm player reads as nicknamed and ShowRealm stops
-- working. A real nickname equal to the bare name is refused with it; the two
-- are indistinguishable, and this is the side that never invents a nickname.
---@param foreign string|nil nickname from the external provider
---@param realName string|nil the plain name the provider was asked about
---@return string|nil nickname resolved nickname, or nil for none
function KE:ResolveNicknamePrecedence(foreign, realName)
    if type(foreign) == "string" and foreign ~= "" then
        local echo = false
        if type(realName) == "string" then
            local bare = realName:match("^([^-]+)")
            echo = foreign == realName or (bare ~= nil and foreign == bare)
        end
        if not echo then return foreign end
    end
    return nil
end

---------------------------------------------------------------------------------
-- Change Notification
---------------------------------------------------------------------------------
-- Tells the live readers that a nickname changed. Reached by the external
-- provider's own change callback.

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

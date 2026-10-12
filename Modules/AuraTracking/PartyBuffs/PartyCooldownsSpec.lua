-- ╔══════════════════════════════════════════════════════════╗
-- ║  PartyCooldownsSpec.lua                                  ║
-- ║  Purpose: each bound party member's spec, from the       ║
-- ║           player, LibSpecialization, an automatic        ║
-- ║           inspect or a role guess, and what the inspect  ║
-- ║           reads beyond it.                               ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local _G = _G
local C_Timer = C_Timer
local CanInspect = CanInspect
local ClearInspectPlayer = ClearInspectPlayer
local CreateFrame = CreateFrame
local GetInspectSpecialization = GetInspectSpecialization
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local IsGUIDInGroup = IsGUIDInGroup
local IsInRaid = IsInRaid
local NotifyInspect = NotifyInspect
local UnitClass = UnitClass
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitGUID = UnitGUID
local UnitName = UnitName
local ipairs = ipairs
local pairs = pairs
local pcall = pcall
local type = type
local wipe = wipe

-- Optional: without it the chain starts at the inspect.
local LibSpec = LibStub("LibSpecialization", true)

local INSPECT_TIMEOUT = 5
local TICK = 1

local Spec = {}
KE.PartyCooldownsSpec = Spec

-- What an inspect reads beyond the spec, one reader per kind: Wanted(m) while
-- m still needs it, Read(m, unit) on INSPECT_READY, Self(m) for the player's
-- own, Forget(m) on a spec change, and events handed to
-- OnEvent(event, arg1, arg2).
Spec.readers = {}
-- Item ID -> use cooldown seconds, read from the item.
Spec.lengths = {}
Spec.byGUID = {}
Spec.libSpecs = {}
Spec.members = {}

local events

local function Plain(value)
    if KE:IsSecretValue(value) then return nil end
    return value
end

local function Ask(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok then return nil end
    return Plain(value)
end

local function Changed(m)
    if Spec.onChange then Spec.onChange(m) end
end

-- The record for a bound unit, keyed by GUID and given the unit's current
-- token. Nil when the GUID cannot be read.
function Spec.Member(unit)
    local guid = KE:GetSafeUnitGUID(unit)
    if not guid then return nil end
    local m = Spec.byGUID[guid]
    if not m then
        m = { guid = guid, isPlayer = guid == Ask(UnitGUID, "player") }
        Spec.byGUID[guid] = m
        if m.isPlayer then Spec.player = m end
    end
    m.unit = unit
    return m
end

-- Names from addon comms carry the realm only for another realm, so a unit
-- has its name and, from another realm, its name-realm as keys.
local function NameKeys(unit)
    local ok, name, realm = pcall(UnitName, unit)
    if not ok then return nil end
    name, realm = Plain(name), Plain(realm)
    if type(name) ~= "string" then return nil end
    if type(realm) == "string" and realm ~= "" then return name, name .. "-" .. realm end
    return name
end

-- Returns the spec and the name it was found under.
local function LibSpecFor(unit)
    local name, full = NameKeys(unit)
    if not name then return nil end
    if full and Spec.libSpecs[full] then return Spec.libSpecs[full], full end
    return Spec.libSpecs[name], name
end

-- What the readers stored was read for the old spec.
local function ForgetReads(m)
    for _, reader in ipairs(Spec.readers) do
        if reader.Forget then reader.Forget(m) end
    end
end

-- Reads stored for a known spec are dropped here when it moves, whoever calls.
function Spec.Resolve(m)
    local before = m.spec
    local sources = {}
    if m.isPlayer then
        sources.player = KE:GetPlayerSpecId()
    else
        local unit = m.unit
        sources.lib, m.libKey = LibSpecFor(unit)
        sources.inspect = m.inspected or Ask(GetInspectSpecialization, unit)
        local ok, _, class = pcall(UnitClass, unit)
        if ok then sources.class = Plain(class) end
        sources.role = Ask(UnitGroupRolesAssigned, unit)
    end
    m.spec, m.source = KE.PartyCooldownsRules.ResolveSpec(sources)
    if before ~= nil and m.spec ~= before then ForgetReads(m) end
    return m.spec
end

-- A guessed spec still wants the inspect.
local function Done(m)
    if m.isPlayer then return true end
    if m.source == nil or m.source == "guess" then return false end
    for _, reader in ipairs(Spec.readers) do
        if reader.Wanted(m) then return false end
    end
    return true
end

function Spec.ReadSelf(m)
    for _, reader in ipairs(Spec.readers) do
        if reader.Self then reader.Self(m) end
    end
end

-- One request at most per tick, and none in the cases NextInspect refuses.
function Spec.Tick()
    local now = GetTime()
    local rules = KE.PartyCooldownsRules
    if Spec.pending then
        if now - Spec.lastRequest < INSPECT_TIMEOUT then return end
        rules.CountTry(Spec.pending, now)
        Spec.pending = nil
    end
    local waiting = false
    for _, m in ipairs(Spec.members) do
        m.done = Done(m)
        if not m.done then
            waiting = true
            m.canInspect = Ask(CanInspect, m.unit) == true
        end
    end
    if not waiting then
        Spec.ticker:Cancel()
        Spec.ticker = nil
        return
    end
    local inspectFrame = _G.InspectFrame
    local m = rules.NextInspect({
        inspectShown = inspectFrame ~= nil and inspectFrame:IsShown() == true,
        inCombat = InCombatLockdown(),
        now = now,
        lastRequest = Spec.lastRequest,
    }, Spec.members)
    if not m then return end
    Spec.lastRequest = now
    if pcall(NotifyInspect, m.unit) then
        Spec.pending = m
    else
        rules.CountTry(m, now)
    end
end

function Spec.Wake()
    if Spec.ticker or not Spec.active then return end
    for _, m in ipairs(Spec.members) do
        if not Done(m) then
            Spec.ticker = C_Timer.NewTicker(TICK, Spec.Tick)
            return
        end
    end
end

-- The bound members, in slot order.
function Spec.SetMembers(list)
    Spec.members = list
    Spec.Wake()
end

-- Nothing was watched for a teammate who left, so their record goes, and
-- their library answer with it: kept, it would come back with them however
-- their spec changed meanwhile. An unreadable answer or name counts as gone.
function Spec.Prune()
    for guid, m in pairs(Spec.byGUID) do
        if not m.isPlayer and Ask(IsGUIDInGroup, guid) ~= true then Spec.byGUID[guid] = nil end
    end
    local present = {}
    local raid = Ask(IsInRaid) == true
    for i = 1, raid and 40 or 4 do
        local name, full = NameKeys((raid and "raid" or "party") .. i)
        if name then present[name] = true end
        if full then present[full] = true end
    end
    for key in pairs(Spec.libSpecs) do
        if not present[key] then Spec.libSpecs[key] = nil end
    end
end

-- The library's entry goes too while it still holds the old spec, or the next
-- resolve would bring that spec straight back.
function Spec.ForgetSpec(guid)
    local m = Spec.byGUID[guid]
    if not m then return end
    if m.libKey and Spec.libSpecs[m.libKey] == m.spec then Spec.libSpecs[m.libKey] = nil end
    m.spec, m.source, m.inspected = nil, nil, nil
    ForgetReads(m)
    Changed(m)
    Spec.Wake()
end

-- Another addon's inspect answers here too; only the queued GUID counts.
local function OnInspectReady(guid)
    if KE:IsSecretValue(guid) then return end
    local m = Spec.pending
    if not m or m.guid ~= guid then return end
    Spec.pending = nil
    local unit = m.unit
    if KE:GetSafeUnitGUID(unit) == guid then
        m.inspected = Ask(GetInspectSpecialization, unit)
        Spec.Resolve(m)
        for _, reader in ipairs(Spec.readers) do
            if reader.Wanted(m) then reader.Read(m, unit) end
        end
    end
    local inspectFrame = _G.InspectFrame
    if not (inspectFrame and inspectFrame:IsShown()) then pcall(ClearInspectPlayer) end
    m.done = Done(m)
    if not m.done then KE.PartyCooldownsRules.CountTry(m, GetTime()) end
    Changed(m)
end

-- The library also sends when a teammate changes talents without changing
-- spec, so a message with an unchanged spec drops that teammate's talent
-- answer and the inspect reads it again. Records, not the bound list: during
-- a roster settle nobody is bound.
local function OnLibSpec(specID, _, _, playerName)
    specID, playerName = Plain(specID), Plain(playerName)
    if type(specID) ~= "number" or specID <= 0 or type(playerName) ~= "string" then return end
    local same = Spec.libSpecs[playerName] == specID
    Spec.libSpecs[playerName] = specID
    if same then
        for _, m in pairs(Spec.byGUID) do
            if not m.isPlayer and m.libKey == playerName then m.talents, m.talentMisses = nil, nil end
        end
    end
    for _, m in ipairs(Spec.members) do
        if not m.isPlayer then
            local before = m.spec
            if Spec.Resolve(m) ~= before then Changed(m) end
        end
    end
    Spec.Wake()
end

local function OnEvent(_, event, arg1, arg2)
    if event == "INSPECT_READY" then
        OnInspectReady(arg1)
        return
    end
    for _, reader in ipairs(Spec.readers) do
        if reader.OnEvent then reader.OnEvent(event, arg1, arg2) end
    end
end

-- Module enable: only the library registration, a callback in the library's
-- own table that stores one number per message, so a spec sent while the
-- content gate is closed is known on the next activation.
function Spec.Enable(onChange)
    Spec.onChange = onChange
    if Spec.enabled then return end
    Spec.enabled = true
    if LibSpec then LibSpec.RegisterGroup(Spec, OnLibSpec) end
end

-- The content gate: every event and the inspect ticker live only between
-- these two.
function Spec.Activate()
    if Spec.active or not Spec.enabled then return end
    Spec.active = true
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", OnEvent)
    end
    events:RegisterEvent("INSPECT_READY")
    for _, reader in ipairs(Spec.readers) do
        for _, event in ipairs(reader.events or {}) do events:RegisterEvent(event) end
    end
    Spec.Wake()
end

-- Nothing is watched while the gate is closed, so every member record goes
-- and is read again on the next activation.
function Spec.Deactivate()
    if not Spec.active then return end
    Spec.active = false
    events:UnregisterAllEvents()
    if Spec.ticker then
        Spec.ticker:Cancel()
        Spec.ticker = nil
    end
    Spec.pending = nil
    Spec.members = {}
    Spec.player = nil
    wipe(Spec.byGUID)
end

function Spec.Disable()
    Spec.Deactivate()
    if not Spec.enabled then return end
    Spec.enabled = false
    if LibSpec then LibSpec.UnregisterGroup(Spec) end
    Spec.player = nil
    wipe(Spec.byGUID)
    wipe(Spec.libSpecs)
end

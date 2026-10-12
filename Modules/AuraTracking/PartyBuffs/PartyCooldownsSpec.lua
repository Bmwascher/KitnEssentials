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

---------------------------------------------------------------------------------
-- Trinkets: each trinket slot's item and use spell, and the item's use
-- cooldown read from its tooltip
---------------------------------------------------------------------------------
local C_Item = C_Item
local C_TooltipInfo = C_TooltipInfo
local GetInventoryItemID = GetInventoryItemID
local TRINKET_SLOTS = { 13, 14 }

local loadTries = {}

-- Once per item, out of combat. Returns whether the length is settled; an item
-- whose tooltip has no cooldown line stores false, and gets no cell unless
-- the player types its seconds.
local function ReadLength(itemID)
    if Spec.lengths[itemID] ~= nil then return true end
    if InCombatLockdown() then return false end
    local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
    if not ok or type(data) ~= "table" or KE:IsSecretTable(data) or type(data.lines) ~= "table" then
        return false
    end
    for _, line in ipairs(data.lines) do
        local seconds = type(line) == "table" and KE.PartyCooldownsRules.ParseCooldownText(Plain(line.leftText))
        if seconds then
            Spec.lengths[itemID] = seconds
            return true
        end
    end
    Spec.lengths[itemID] = false
    return true
end

-- The slots' spells and lengths from their item IDs. Incomplete while an
-- item's data is still loading or an on-use item's length is unread; an
-- empty slot or a passive trinket is complete with no spell. A load is asked
-- for LOAD_TRIES times at most per item.
local function Derive(items)
    local slots, complete = {}, true
    for i = 1, #TRINKET_SLOTS do
        local itemID = items[i]
        local spellID
        if itemID then
            if Ask(C_Item.IsItemDataCachedByID, itemID) == true then
                -- A refused or hidden answer is not "passive": the slot stays
                -- incomplete and combat's end reads it again.
                local ok, _, id = pcall(C_Item.GetItemSpell, itemID)
                if not ok or KE:IsSecretValue(id) then
                    complete = false
                else
                    spellID = id
                    if spellID and not ReadLength(itemID) then complete = false end
                end
            else
                if KE.PartyCooldownsRules.TakeLoadTry(loadTries, itemID) then
                    pcall(C_Item.RequestLoadItemDataByID, itemID)
                end
                complete = false
            end
        end
        slots[i] = { item = itemID, spell = spellID }
    end
    return slots, complete
end

-- Nil when either slot's answer was refused or hidden; an empty slot answers
-- a plain nil and reads as empty.
local function ReadItems(unit)
    local items = {}
    for i, slotID in ipairs(TRINKET_SLOTS) do
        local ok, itemID = pcall(GetInventoryItemID, unit, slotID)
        if not ok or KE:IsSecretValue(itemID) then return nil end
        if type(itemID) == "number" then items[i] = itemID end
    end
    return items
end

-- items nil re-derives the IDs already read. With none read the member has
-- no trinkets yet and stays wanted.
local function Fill(m, items)
    if items then m.trinketItems = items end
    if m.trinketItems then
        m.trinkets, m.trinketsComplete = Derive(m.trinketItems)
    else
        m.trinkets, m.trinketsComplete = nil, nil
    end
end

local function HasItem(m, itemID)
    local items = m.trinketItems
    return items ~= nil and (items[1] == itemID or items[2] == itemID)
end

Spec.readers[#Spec.readers + 1] = {
    events = { "UNIT_INVENTORY_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "ITEM_DATA_LOAD_RESULT",
        "PLAYER_REGEN_ENABLED" },
    Wanted = function(m) return m.trinketItems == nil end,
    Read = function(m, unit) Fill(m, ReadItems(unit)) end,
    Self = function(m)
        if m.trinketItems == nil then Fill(m, ReadItems("player")) end
    end,
    OnEvent = function(event, arg1, arg2)
        if event == "PLAYER_EQUIPMENT_CHANGED" then
            local m = Spec.player
            if m then
                m.trinketItems = nil
                Fill(m, ReadItems("player"))
                Changed(m)
            end
        elseif event == "UNIT_INVENTORY_CHANGED" then
            if KE:IsSecretValue(arg1) then return end
            local guid = KE:GetSafeUnitGUID(arg1)
            local m = guid and Spec.byGUID[guid]
            if m and not m.isPlayer then
                m.trinketItems, m.trinkets = nil, nil
                Spec.Wake()
            end
        else
            -- A successful load re-derives the members wearing that item; a
            -- failed one waits for combat's end or the next read. Leaving
            -- combat retries every incomplete member. Records, not the bound
            -- list: during a roster settle nobody is bound, and the rebind
            -- uses the record as it stands.
            local itemID
            if event == "ITEM_DATA_LOAD_RESULT" then
                if Plain(arg2) ~= true then return end
                itemID = Plain(arg1)
                if not itemID then return end
            else
                -- Your own slots are never inspected: a refused read is
                -- retried here.
                local m = Spec.player
                if m and m.trinketItems == nil then
                    Fill(m, ReadItems("player"))
                    if m.trinketItems then Changed(m) end
                end
            end
            for _, m in pairs(Spec.byGUID) do
                if m.trinketItems and not m.trinketsComplete
                    and (not itemID or HasItem(m, itemID)) then
                    Fill(m)
                    Changed(m)
                end
            end
        end
    end,
}

---------------------------------------------------------------------------------
-- Talents that swap an icon: read from the inspected loadout for a teammate,
-- from the spellbook for the player
---------------------------------------------------------------------------------
local C_Spell = C_Spell
local C_SpellBook = C_SpellBook
local C_Traits = C_Traits
local INSPECT_CONFIG = Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID
local MAX_MISSES = 3

-- swap -> the node and entry holding its talent, found once; and the walks
-- that missed it.
local located, misses = {}, {}

local function Locate(trees, swap)
    for _, tree in ipairs(trees) do
        for _, nodeID in ipairs(C_Traits.GetTreeNodes(tree) or {}) do
            local node = C_Traits.GetNodeInfo(INSPECT_CONFIG, nodeID)
            for _, entryID in ipairs(type(node) == "table" and node.entryIDs or {}) do
                local entry = C_Traits.GetEntryInfo(INSPECT_CONFIG, entryID)
                local definitionID = type(entry) == "table" and entry.definitionID
                local definition = definitionID and C_Traits.GetDefinitionInfo(definitionID)
                if type(definition) == "table" and definition.spellID and swap.talents[definition.spellID] then
                    located[swap] = { node = nodeID, entry = entryID }
                    return located[swap]
                end
            end
        end
    end
    misses[swap] = (misses[swap] or 0) + 1
    return nil
end

-- castID -> taken for every swap of the spec, or nil when any one cannot be
-- answered yet (no inspect data, its node not found, or the node unreadable);
-- the reader counts that as a miss.
local function ReadTaken(specID)
    local out = {}
    local swaps = KE.PartyCooldownsRules.SwapsFor(specID)
    if not swaps then return out end
    if C_Traits.HasValidInspectData() ~= true then return nil end
    local info = C_Traits.GetConfigInfo(INSPECT_CONFIG)
    local trees = type(info) == "table" and info.treeIDs
    if type(trees) ~= "table" then return nil end
    for castID, swap in pairs(swaps) do
        local at = located[swap]
        if not at and (misses[swap] or 0) < MAX_MISSES then at = Locate(trees, swap) end
        if not at then return nil end
        local node = C_Traits.GetNodeInfo(INSPECT_CONFIG, at.node)
        if not (type(node) == "table" and type(node.ID) == "number" and node.ID > 0) then return nil end
        local active = node.activeEntry
        local rank = type(node.activeRank) == "number" and node.activeRank or 0
        out[castID] = type(active) == "table" and active.entryID == at.entry and rank > 0
    end
    return out
end

local function SelfTaken(specID)
    local out = {}
    for castID, swap in pairs(KE.PartyCooldownsRules.SwapsFor(specID) or {}) do
        local taken = Ask(C_Spell.GetOverrideSpell, castID) == swap.id
        for talent in pairs(swap.talents) do
            if not taken and Ask(C_SpellBook.IsSpellKnown, talent) == true then taken = true end
        end
        out[castID] = taken
    end
    return out
end

-- Three unreadable answers in a row store an empty one, which keeps the
-- likely icon.
Spec.readers[#Spec.readers + 1] = {
    events = { "TRAIT_CONFIG_UPDATED" },
    Wanted = function(m)
        return m.talents == nil and m.spec ~= nil and KE.PartyCooldownsRules.SwapsFor(m.spec) ~= nil
    end,
    Read = function(m)
        local ok, taken = pcall(ReadTaken, m.spec)
        if ok and taken then
            m.talents, m.talentMisses = taken, nil
            return
        end
        m.talentMisses = (m.talentMisses or 0) + 1
        if m.talentMisses >= MAX_MISSES then m.talents, m.talentMisses = {}, nil end
    end,
    Self = function(m)
        if m.talents == nil and m.spec then m.talents = SelfTaken(m.spec) end
    end,
    -- The miss count belongs to the answer: a new spec gets its own three tries.
    Forget = function(m) m.talents, m.talentMisses = nil, nil end,
    OnEvent = function(event)
        local m = Spec.player
        if event == "TRAIT_CONFIG_UPDATED" and m then
            m.talents = nil
            Changed(m)
        end
    end,
}

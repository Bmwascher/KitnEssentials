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
local GetPlayerInfoByGUID = GetPlayerInfoByGUID
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local IsGUIDInGroup = IsGUIDInGroup
local IsInRaid = IsInRaid
local NotifyInspect = NotifyInspect
local UnitClass = UnitClass
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitGUID = UnitGUID
local UnitIsConnected = UnitIsConnected
local UnitNameUnmodified = UnitNameUnmodified
local UnitRace = UnitRace
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
-- OnEvent(event, arg1, arg2). A reader with On() works only while On() is
-- true, and Clear(m) drops what it stored when it is switched off.
Spec.readers = {}
-- Item ID -> use cooldown seconds, read from the item.
Spec.lengths = {}
Spec.byGUID = {}
Spec.libSpecs = {}
-- Name -> the talent string of that name's last library message.
Spec.libTalents = {}
Spec.members = {}

local events, foreignHooked

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

-- The unit's key in the library's answers. None when the name or the realm
-- cannot be read: a realm read as empty would match a same-named player of
-- your realm.
local function LibKey(unit)
    local ok, name, realm = pcall(UnitNameUnmodified, unit)
    if not ok or KE:IsSecretValue(name) or KE:IsSecretValue(realm) then return nil end
    return KE.PartyCooldownsRules.LibKey(name, realm)
end
Spec.LibKey = LibKey

-- Returns the spec and the key it was looked up under.
local function LibSpecFor(unit)
    local key = LibKey(unit)
    if not key then return nil end
    return Spec.libSpecs[key], key
end

-- What the readers stored was read for the old spec.
local function ForgetReads(m)
    for _, reader in ipairs(Spec.readers) do
        if reader.Forget then reader.Forget(m) end
    end
end

local function ClearTalents(m)
    m.talents, m.talentMisses, m.talentsStale, m.talentsRetryAt = nil, nil, nil, nil
end

-- The race token, or nil until a source answers; a GUID's race never changes,
-- so an answer is kept. UnitRace can answer nothing for a unit the client has
-- not loaded yet.
local function ReadRace(unit, guid)
    local ok, _, race = pcall(UnitRace, unit)
    race = ok and Plain(race) or nil
    if type(race) == "string" and race ~= "" then return race end
    if type(guid) ~= "string" then return nil end
    local found, _, _, _, english = pcall(GetPlayerInfoByGUID, guid)
    english = found and Plain(english) or nil
    if type(english) == "string" and english ~= "" then return english end
    return nil
end

-- Reads stored for a known spec are dropped here when it moves, whoever calls.
function Spec.Resolve(m)
    if m.race == nil and Spec.trackRacials then m.race = ReadRace(m.unit, m.guid) end
    local before = m.spec
    local sources = {}
    if m.isPlayer then
        sources.player = KE:GetPlayerSpecId()
        local ok, _, class = pcall(UnitClass, "player")
        if ok then m.class = Plain(class) or m.class end
    else
        local unit = m.unit
        sources.lib, m.libKey = LibSpecFor(unit)
        sources.inspect = m.inspected or Ask(GetInspectSpecialization, unit)
        local ok, _, class = pcall(UnitClass, unit)
        if ok then sources.class = Plain(class) end
        sources.role = Ask(UnitGroupRolesAssigned, unit)
        -- A hidden read keeps the last plain answer.
        m.class = sources.class or m.class
        m.role = sources.role or m.role
    end
    m.spec, m.source = KE.PartyCooldownsRules.ResolveSpec(sources)
    if before ~= nil and m.spec ~= before then ForgetReads(m) end
    return m.spec
end

local C_ChallengeMode = C_ChallengeMode

local function InKey()
    return Ask(C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive) == true
end

local function IsOn(reader)
    return reader.On == nil or reader.On() == true
end

-- A guessed spec still wants the inspect; with nothing that needs the spec
-- switched on, nothing does.
local function Done(m)
    if m.isPlayer then return true end
    local rules = KE.PartyCooldownsRules
    local healer = Spec.trackHealers == true and KE.HealerExternalsRules.Candidate(m.class, m.role)
    if not rules.SpecWanted(Spec.trackClass, Spec.trackTrinkets, Spec.trackRacials, m.race, healer) then
        return true
    end
    if m.source == nil or m.source == "guess" then return false end
    for _, reader in ipairs(Spec.readers) do
        if IsOn(reader) and reader.Wanted(m) then return false end
    end
    return true
end

-- Whether the member's talents count for a switched-on cell.
local function TalentsWanted(m)
    local rules = KE.PartyCooldownsRules
    return rules.TalentsWanted(rules.TalentsFor(m.spec), Spec.trackClass, Spec.trackHealers)
end

-- Every answer the member is still wanted for is in hand and only marked
-- stale, so an inspect that never answers costs fewer tries.
local function OnlyStale(m)
    if m.source == nil or m.source == "guess" then return false end
    if Spec.trackTrinkets == true and m.trinketItems == nil then return false end
    if m.talents == nil and TalentsWanted(m) then return false end
    return true
end

function Spec.ReadSelf(m)
    for _, reader in ipairs(Spec.readers) do
        if reader.Self and IsOn(reader) then reader.Self(m) end
    end
end

-- Whether Blizzard's Inspect window is shown, and whether its talent view
-- shows another player.
local function InspectViews()
    local inspectFrame, spells = _G.InspectFrame, _G.PlayerSpellsFrame
    local talentsInspecting = false
    if spells and type(spells.IsInspecting) == "function" then
        local ok, inspecting = pcall(spells.IsInspecting, spells)
        talentsInspecting = ok and inspecting == true
    end
    return inspectFrame ~= nil and inspectFrame:IsShown() == true, talentsInspecting
end

-- One request at most per tick, and none in the cases NextInspect refuses.
function Spec.Tick()
    local now = GetTime()
    local rules = KE.PartyCooldownsRules
    if Spec.pending then
        if now - Spec.lastRequest < INSPECT_TIMEOUT then return end
        rules.CountTry(Spec.pending, now, OnlyStale(Spec.pending))
        Spec.pending = nil
    end
    local waiting = false
    for _, m in ipairs(Spec.members) do
        m.done = Done(m)
        if not m.done then
            waiting = true
            m.canInspect = Ask(CanInspect, m.unit) == true
            m.offline = Ask(UnitIsConnected, m.unit) == false
        end
    end
    if not waiting then
        Spec.ticker:Cancel()
        Spec.ticker = nil
        return
    end
    local inspectShown, talentsInspecting = InspectViews()
    local m = rules.NextInspect({
        inspectShown = inspectShown,
        talentsInspecting = talentsInspecting,
        inCombat = InCombatLockdown(),
        now = now,
        lastRequest = Spec.lastRequest,
        foreignAt = Spec.foreignAt,
    }, Spec.members)
    if not m then return end
    Spec.lastRequest = now
    if pcall(NotifyInspect, m.unit) then
        Spec.pending = m
    else
        rules.CountTry(m, now, OnlyStale(m))
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
        local key = LibKey((raid and "raid" or "party") .. i)
        if key then present[key] = true end
    end
    for key in pairs(Spec.libSpecs) do
        if not present[key] then Spec.libSpecs[key], Spec.libTalents[key] = nil, nil end
    end
end

-- The library's entry goes too while it still holds the old spec, or the next
-- resolve would bring that spec straight back.
function Spec.ForgetSpec(guid)
    local m = Spec.byGUID[guid]
    if not m then return end
    if not KE.PartyCooldownsRules.BuildEventCounts(InKey(), m.isPlayer) then return end
    if m.libKey and Spec.libSpecs[m.libKey] == m.spec then
        Spec.libSpecs[m.libKey], Spec.libTalents[m.libKey] = nil, nil
    end
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
            if IsOn(reader) and reader.Wanted(m) then reader.Read(m, unit) end
        end
    end
    local rules = KE.PartyCooldownsRules
    if not (rules.InspectInUse(InspectViews()) or rules.ForeignBusy(GetTime(), Spec.foreignAt)) then
        pcall(ClearInspectPlayer)
    end
    m.done = Done(m)
    if not m.done then KE.PartyCooldownsRules.CountTry(m, GetTime(), OnlyStale(m)) end
    Changed(m)
end

-- The library sends a teammate's message again on a talent change, and also,
-- unchanged, whenever anyone in the group asks, so only a talent string that
-- moved drops that teammate's talent answer for the inspect to read again.
-- Records, not the bound list: during a roster settle nobody is bound.
local function OnLibSpec(specID, _, _, playerName, talents)
    specID, playerName, talents = Plain(specID), Plain(playerName), Plain(talents)
    if type(specID) ~= "number" or specID <= 0 or type(playerName) ~= "string" then return end
    local rules = KE.PartyCooldownsRules
    local same = Spec.libSpecs[playerName] == specID
    local moved = rules.TalentsMoved(Spec.libTalents[playerName], talents)
    Spec.libSpecs[playerName], Spec.libTalents[playerName] = specID, talents
    if same and moved and rules.BuildEventCounts(InKey(), false) then
        for _, m in pairs(Spec.byGUID) do
            if not m.isPlayer and m.libKey == playerName then ClearTalents(m) end
        end
    end
    for _, m in ipairs(Spec.members) do
        if not m.isPlayer then
            local before, race = m.spec, m.race
            if Spec.Resolve(m) ~= before or m.race ~= race then Changed(m) end
        end
    end
    Spec.Wake()
end

local function OnEvent(_, event, arg1, arg2)
    if event == "INSPECT_READY" then
        OnInspectReady(arg1)
        return
    end
    -- Two readers may share an event.
    for _, reader in ipairs(Spec.readers) do
        if reader.OnEvent and IsOn(reader) then reader.OnEvent(event, arg1, arg2) end
    end
end

local function RegisterEvents()
    events:UnregisterAllEvents()
    events:RegisterEvent("INSPECT_READY")
    for _, reader in ipairs(Spec.readers) do
        if IsOn(reader) then
            for _, event in ipairs(reader.events or {}) do events:RegisterEvent(event) end
        end
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

-- Another addon's inspect request. KE's own never reach the hook: they call
-- the local captured at load, and the hook wraps only the global.
local function OnForeignInspect()
    if Spec.active then Spec.foreignAt = GetTime() end
end

-- The content gate: every event and the inspect ticker live only between
-- these two. The inspect hook is installed on the first activation and is
-- inert while inactive; a hook cannot be removed.
function Spec.Activate()
    if Spec.active or not Spec.enabled then return end
    Spec.active = true
    if not foreignHooked then
        local notify = _G.NotifyInspect
        if type(notify) == "function" then
            hooksecurefunc("NotifyInspect", OnForeignInspect)
            foreignHooked = true
        end
    end
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", OnEvent)
    end
    RegisterEvents()
    Spec.Wake()
end

-- Which cooldown cells can show, from the Class Cooldowns, Trinkets and Show
-- Racials switches, and whether the raid cooldowns box is on. A reader whose
-- cells cannot show stops hearing its events and drops what it stored; with
-- all four off, nobody is inspected. Racials and the box start no reader: a
-- racial needs only the spec and the race, the box the spec and the talents
-- its rows name.
function Spec.SetTracked(class, trinkets, racials, healers)
    local boxChanged = Spec.trackHealers ~= healers
    Spec.trackClass, Spec.trackTrinkets, Spec.trackRacials = class, trinkets, racials
    Spec.trackHealers = healers
    if not Spec.active then return end
    RegisterEvents()
    for _, reader in ipairs(Spec.readers) do
        if reader.Clear and not IsOn(reader) then
            for _, m in pairs(Spec.byGUID) do reader.Clear(m) end
        end
    end
    -- The box's switch changes which talents a read keeps, so every answer
    -- is read again.
    if boxChanged then
        for _, m in pairs(Spec.byGUID) do ClearTalents(m) end
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
    wipe(Spec.libTalents)
end

---------------------------------------------------------------------------------
-- Trinkets: each trinket slot's item and use spell, and the item's use
-- cooldown read from its tooltip
---------------------------------------------------------------------------------
local C_Item = C_Item
local C_TooltipInfo = C_TooltipInfo
local GetInventoryItemID = GetInventoryItemID
local TRINKET_SLOTS = { 13, 14 }
local CHEST_AND_MAIN_HAND = { 5, 16 }

local loadTries, lengthTries = {}, {}

-- Out of combat. Returns whether the length is settled. A tooltip with no
-- cooldown line may not have finished loading, so it is read again at the
-- next combat end, item load, read or timed retry; past LOAD_TRIES such reads
-- the item stores false and gets no cell. A timed retry's read is not
-- counted: the retries run per member, the count per item.
local function ReadLength(itemID, retry)
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
    if retry or KE.PartyCooldownsRules.TakeLoadTry(lengthTries, itemID) then return false end
    Spec.lengths[itemID] = false
    return true
end

-- The slots' spells and lengths from their item IDs. Incomplete while an
-- item's data is still loading or an on-use item's length is unread; an
-- empty slot or a passive trinket is complete with no spell. A load is asked
-- for LOAD_TRIES times at most per item. retry: a timed retry (ReadLength).
local function Derive(items, retry)
    local slots, complete = {}, true
    for i = 1, #TRINKET_SLOTS do
        local itemID = items[i]
        local spellID
        if itemID then
            if Ask(C_Item.IsItemDataCachedByID, itemID) == true then
                -- A refused or hidden answer is not "passive": the slot stays
                -- incomplete and a timed retry or combat's end reads it again.
                local ok, _, id = pcall(C_Item.GetItemSpell, itemID)
                if not ok or KE:IsSecretValue(id) then
                    complete = false
                else
                    spellID = id
                    if spellID and not ReadLength(itemID, retry) then complete = false end
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
local function ReadItems(unit, slots)
    local items = {}
    for i, slotID in ipairs(slots or TRINKET_SLOTS) do
        local ok, itemID = pcall(GetInventoryItemID, unit, slotID)
        if not ok or KE:IsSecretValue(itemID) then return nil end
        if type(itemID) == "number" then items[i] = itemID end
    end
    return items
end

local Fill

-- Past the waits, combat's end or the next read derives it again.
local function Retry(m)
    m.retryPending = nil
    if Spec.byGUID[m.guid] ~= m or m.trinketsComplete ~= false or InCombatLockdown() then return end
    Fill(m, nil, true)
    Changed(m)
end

local function ScheduleRetry(m)
    if m.retryPending or m.trinketsComplete ~= false or InCombatLockdown() then return end
    local wait = KE.PartyCooldownsRules.NextDeriveWait(m.deriveTries)
    if not wait then return end
    m.deriveTries, m.retryPending = (m.deriveTries or 0) + 1, true
    C_Timer.After(wait, function() Retry(m) end)
end

-- items nil re-derives the IDs already read. With none read the member has
-- no trinkets yet and stays wanted.
function Fill(m, items, retry)
    if items then m.trinketItems = items end
    if m.trinketItems then
        m.trinkets, m.trinketsComplete = Derive(m.trinketItems, retry)
        ScheduleRetry(m)
    else
        m.trinkets, m.trinketsComplete = nil, nil
    end
end

local function HasItem(m, itemID)
    local items = m.trinketItems
    return items ~= nil and (items[1] == itemID or items[2] == itemID)
end

-- Your own slots are read directly. A refused read keeps the trinkets read
-- before, and the next bind, equipment change or combat end tries again.
local function ReadOwn(m)
    local items = ReadItems("player")
    if not items then
        m.trinketsStale = true
        return false
    end
    m.trinketsStale, m.deriveTries = nil, nil
    Fill(m, items)
    return true
end

-- What was read stays until a new read replaces it: a gear event only marks
-- the record stale, and only when GearEventCounts says it is a change.
Spec.readers[#Spec.readers + 1] = {
    events = { "UNIT_INVENTORY_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "ITEM_DATA_LOAD_RESULT",
        "PLAYER_REGEN_ENABLED" },
    On = function() return Spec.trackTrinkets == true end,
    Wanted = function(m) return m.trinketItems == nil or m.trinketsStale == true end,
    Read = function(m, unit)
        local items, others = ReadItems(unit), ReadItems(unit, CHEST_AND_MAIN_HAND)
        if not (items and others and KE.PartyCooldownsRules.GearArrived(items, others)) then return end
        local stands, same = KE.PartyCooldownsRules.TrinketReadStands(m.trinketItems, items)
        m.trinketsSame = same and (m.trinketsSame or 0) + 1 or 0
        m.trinketsStale = not stands or nil
        m.trinketsReadAt, m.deriveTries = GetTime(), nil
        Fill(m, items)
    end,
    Self = function(m)
        if m.trinketItems == nil or m.trinketsStale then ReadOwn(m) end
    end,
    Clear = function(m)
        m.trinketItems, m.trinkets, m.trinketsComplete = nil, nil, nil
        m.trinketsStale, m.trinketsReadAt, m.trinketsSame, m.deriveTries = nil, nil, nil, nil
    end,
    OnEvent = function(event, arg1, arg2)
        if event == "PLAYER_EQUIPMENT_CHANGED" then
            local m, slot = Spec.player, Plain(arg1)
            -- Another slot changes no trinket, unless a read is still owed.
            if m and (slot == TRINKET_SLOTS[1] or slot == TRINKET_SLOTS[2]
                or m.trinketItems == nil or m.trinketsStale) then
                ReadOwn(m)
                Changed(m)
            end
        elseif event == "UNIT_INVENTORY_CHANGED" then
            if KE:IsSecretValue(arg1) then return end
            local guid = KE:GetSafeUnitGUID(arg1)
            local m = guid and Spec.byGUID[guid]
            if m and not m.isPlayer and m.trinketItems and not m.trinketsStale
                and KE.PartyCooldownsRules.GearEventCounts(InKey(), GetTime(), m.trinketsReadAt, m.trinketsSame) then
                m.trinketsStale = true
                Spec.Wake()
            end
        elseif event == "ITEM_DATA_LOAD_RESULT" or event == "PLAYER_REGEN_ENABLED" then
            -- Every reader gets every event, so the events are named.
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
                if m and (m.trinketItems == nil or m.trinketsStale) and ReadOwn(m) then Changed(m) end
            end
            -- Changed can add a record, and a key added during a pairs walk
            -- is undefined.
            local changed = {}
            for _, m in pairs(Spec.byGUID) do
                if m.trinketItems and not m.trinketsComplete
                    and (not itemID or HasItem(m, itemID)) then
                    Fill(m)
                    changed[#changed + 1] = m
                end
            end
            for _, m in ipairs(changed) do Changed(m) end
        end
    end,
}

---------------------------------------------------------------------------------
-- Talent ranks for swaps, rows, lengths and charges: from the inspected
-- loadout for a teammate, from your active loadout for you
---------------------------------------------------------------------------------
local C_ClassTalents = C_ClassTalents
local C_Traits = C_Traits
local debugprofilestop = debugprofilestop
local INSPECT_CONFIG = Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID
local MAX_MISSES = 3

-- spec -> talent -> the nodes and entries holding it, found by one walk of
-- the class tree; and per spec, the walks that found none. Per spec: two
-- specs can hold the same talent on nodes of their own.
local index, misses = {}, {}

-- One walk of the tree, keeping the spec's wanted talents. Spec.locateMs keeps
-- the longest walk in milliseconds, so its cost can be read in game. A hero
-- selection entry has no definition and is skipped.
local function Index(specID, tree, config, want)
    local start = debugprofilestop()
    local found, any = {}, false
    for _, nodeID in ipairs(C_Traits.GetTreeNodes(tree) or {}) do
        local node = C_Traits.GetNodeInfo(config, nodeID)
        for _, entryID in ipairs(type(node) == "table" and node.entryIDs or {}) do
            local entry = C_Traits.GetEntryInfo(config, entryID)
            local definitionID = type(entry) == "table" and entry.definitionID
            local definition = definitionID and C_Traits.GetDefinitionInfo(definitionID)
            local talent = type(definition) == "table" and definition.spellID
            if talent and want[talent] then
                local spots = found[talent] or {}
                found[talent] = spots
                spots[#spots + 1] = { node = nodeID, entry = entryID }
                any = true
            end
        end
    end
    local ms = debugprofilestop() - start
    if ms > (Spec.locateMs or 0) then Spec.locateMs = ms end
    if not any then
        misses[specID] = (misses[specID] or 0) + 1
        return nil
    end
    index[specID] = found
    return found
end

local function HasTree(trees, tree)
    if type(tree) ~= "number" then return false end
    for _, id in ipairs(trees) do
        if id == tree then return true end
    end
    return false
end

-- Every wanted talent's rank in config: the active entry's rank, the largest
-- over the talent's nodes, 0 when not taken. While the box is off, a talent
-- only box rows name is not read; the walk still keeps it, since the walk
-- visits every node either way. Nil when it cannot be answered yet: no
-- inspect data, a loadout not of this spec's class, no wanted talent found,
-- or a node unreadable; the reader counts that as a miss. A second result
-- true means the answer is skipped without a miss: a first walk would run in
-- combat.
local function ReadRanks(specID, config)
    local out = {}
    local rules = KE.PartyCooldownsRules
    local talents = rules.TalentsFor(specID)
    local boxOn = Spec.trackHealers == true
    if not (talents and (talents.rows or boxOn)) then return out end
    if config == INSPECT_CONFIG and C_Traits.HasValidInspectData() ~= true then return nil end
    local info = C_Traits.GetConfigInfo(config)
    local trees = type(info) == "table" and info.treeIDs
    if type(trees) ~= "table" then return nil end
    -- The inspect config names no player; a loadout of another class is not
    -- this member's and must not cost the spec a walk.
    local tree = C_ClassTalents.GetTraitTreeForSpec(specID)
    if not HasTree(trees, tree) then return nil end
    local found = index[specID]
    if not found then
        if (misses[specID] or 0) >= MAX_MISSES then return nil end
        if InCombatLockdown() then return nil, true end
        found = Index(specID, tree, config, talents.want)
        if not found then return nil end
    end
    for talent, spots in pairs(found) do
        if rules.TalentRead(talents, talent, boxOn) then
            local rank = 0
            for _, at in ipairs(spots) do
                local node = C_Traits.GetNodeInfo(config, at.node)
                if not (type(node) == "table" and type(node.ID) == "number" and node.ID > 0) then return nil end
                local active = node.activeEntry
                if node.subTreeActive ~= false and type(active) == "table" and active.entryID == at.entry
                    and type(node.activeRank) == "number" and node.activeRank > rank then
                    rank = node.activeRank
                end
            end
            out[talent] = rank
        end
    end
    return out
end

-- A member's unreadable reads belong to the answer: a new spec gets its own
-- three tries. A walk that missed against a member's old spec must not stop
-- the walk for everyone, so the walk's misses go too.
local function ForgetTalents(m)
    ClearTalents(m)
    wipe(misses)
end

-- Companion, skyriding and profession configs fire TRAIT_CONFIG_UPDATED too;
-- only a class talent config changes your talents, and the inspect config
-- holds another player's. An unreadable answer counts as one.
local function IsClassConfig(configID)
    configID = Plain(configID)
    if type(configID) ~= "number" then return true end
    if configID == INSPECT_CONFIG then return false end
    local ok, info = pcall(C_Traits.GetConfigInfo, configID)
    if not ok or type(info) ~= "table" then return true end
    return info.type == Enum.TraitConfigType.Combat
end

-- Three unreadable answers in a row keep the answer held, else store an empty
-- one, which keeps the likely icon, and shows a row that needs a talent only
-- when it is likely; that empty answer gets one more round of reads
-- TRY_WAIT seconds later. Talents concern class cooldowns and the externals
-- box. A teammate's talent change fires no event here, so a ready check
-- outside a key marks every teammate's answer stale for the inspect to read
-- again; a stale answer stays in use until a read replaces it.
Spec.readers[#Spec.readers + 1] = {
    events = { "TRAIT_CONFIG_UPDATED", "TRAIT_CONFIG_LIST_UPDATED", "READY_CHECK", "PLAYER_REGEN_ENABLED" },
    On = function() return Spec.trackClass == true or Spec.trackHealers == true end,
    Clear = ForgetTalents,
    Wanted = function(m)
        return (m.talents == nil or m.talentsStale == true) and m.spec ~= nil
            and not (m.talentsRetryAt and GetTime() < m.talentsRetryAt)
            and TalentsWanted(m)
    end,
    Read = function(m)
        -- The walk's misses are cleared as the retry reads, not as it waits:
        -- another member's reads in the wait could use them up again.
        if m.talentsRetryAt then
            m.talentsRetryAt = nil
            wipe(misses)
        end
        local ok, ranks, skip = pcall(ReadRanks, m.spec, INSPECT_CONFIG)
        if ok and ranks then
            m.talents, m.talentMisses, m.talentsStale = ranks, nil, nil
            return
        end
        if ok and skip then return end
        m.talentMisses = (m.talentMisses or 0) + 1
        if m.talentMisses >= MAX_MISSES then
            local rules = KE.PartyCooldownsRules
            local answer, retry = rules.AfterTalentMisses(m.talents)
            m.talents, m.talentMisses, m.talentsStale = answer, nil, retry or nil
            -- A read just after a spec change can find the old talents. The
            -- wait holds back only the talent read; the timer wakes the queue
            -- a tick after it ends, so the wait has passed when it runs.
            if retry then
                m.talentsRetryAt = GetTime() + rules.TRY_WAIT
                C_Timer.After(rules.TRY_WAIT + TICK, Spec.Wake)
            end
        end
    end,
    -- Before the talent configs load no active config is reported, so the
    -- read waits for TRAIT_CONFIG_LIST_UPDATED. A first walk due in combat
    -- waits for its end.
    Self = function(m)
        if m.talents ~= nil or not m.spec then return end
        local config = Ask(C_ClassTalents.GetActiveConfigID)
        if config == nil then return end
        local ok, ranks, skip = pcall(ReadRanks, m.spec, config)
        if ok and ranks then
            m.talents = ranks
        elseif ok and skip then
            Spec.selfOwed = true
        end
    end,
    Forget = ForgetTalents,
    OnEvent = function(event, configID)
        local m = Spec.player
        if event == "TRAIT_CONFIG_UPDATED" and m and IsClassConfig(configID) then
            m.talents = nil
            Changed(m)
        elseif event == "TRAIT_CONFIG_LIST_UPDATED" then
            if m and m.talents == nil then Changed(m) end
        elseif event == "PLAYER_REGEN_ENABLED" then
            if Spec.selfOwed and m then
                Spec.selfOwed = nil
                Changed(m)
            end
        elseif event == "READY_CHECK" and KE.PartyCooldownsRules.BuildEventCounts(InKey(), false) then
            for _, member in pairs(Spec.byGUID) do
                if not member.isPlayer and member.talents then member.talentsStale = true end
            end
            wipe(misses)
            Spec.Wake()
        end
    end,
}

-- ╔══════════════════════════════════════════════════════════╗
-- ║  GroupInspect.lua                                        ║
-- ║  Purpose: one queue for the game's single inspect slot,  ║
-- ║           and the talent ranks read from it, shared by   ║
-- ║           every module that subscribes.                  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local _G = _G
local C_ClassTalents = C_ClassTalents
local C_SpecializationInfo = C_SpecializationInfo
local C_Timer = C_Timer
local C_Traits = C_Traits
local CanInspect = CanInspect
local ClearInspectPlayer = ClearInspectPlayer
local CreateFrame = CreateFrame
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local IsGUIDInGroup = IsGUIDInGroup
local NotifyInspect = NotifyInspect
local UnitIsConnected = UnitIsConnected
local debugprofilestop = debugprofilestop
local geterrorhandler = geterrorhandler
local hooksecurefunc = hooksecurefunc
local ipairs = ipairs
local pairs = pairs
local pcall = pcall
local setmetatable = setmetatable
local type = type
local wipe = wipe

local Rules = KE.GroupInspectRules
local INSPECT_CONFIG = Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID
local TICK = 1

---@class KE.GroupInspect
local GroupInspect = {}
KE.GroupInspect = GroupInspect

---@class KE.GroupInspectHandle
---@field owner table
local Handle = {}
Handle.__index = Handle

-- Owners in subscription order, and by key.
local owners, byKey = {}, {}
-- Per GUID while any owner is active.
local queue, snapshots = {}, {}
local union = {}
local active, hooked = false, false
local ticker
local pendingGUID, pendingEntry, lastRequest, foreignAt
-- The GUID whose answer is being handed out; rank reads are valid only then.
-- answer numbers each answer handed out.
local readingGUID
local answer = 0
-- spec -> { found = talent -> its node and entry spots, covered = the IDs the
-- walk kept }, and spec -> walks that failed. Both last the session. counted:
-- spec -> the answer that took its last miss (Rules.CountMiss).
local index, misses, counted = {}, {}, {}

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

local function HasTree(trees, tree)
    if type(tree) ~= "number" then return false end
    for _, id in ipairs(trees) do
        if id == tree then return true end
    end
    return false
end

-- One walk of the class tree, keeping the talents in want. A node or entry
-- that cannot be read fails the walk instead of leaving a gap that would read
-- 0. A hero selection entry has no definition and is skipped.
-- GroupInspect.locateMs keeps the longest walk in milliseconds.
local function Index(specID, tree, config, want)
    local start = debugprofilestop()
    local found, any = {}, false
    local inAnswer = (config == INSPECT_CONFIG and readingGUID ~= nil) and answer or nil
    for _, nodeID in ipairs(C_Traits.GetTreeNodes(tree) or {}) do
        local entries = Rules.NodeEntries(C_Traits.GetNodeInfo(config, nodeID))
        if not entries then
            Rules.CountMiss(misses, counted, specID, inAnswer)
            return nil
        end
        for _, entryID in ipairs(entries) do
            local entry = C_Traits.GetEntryInfo(config, entryID)
            local definitionID = type(entry) == "table" and entry.definitionID
            local definition = definitionID and C_Traits.GetDefinitionInfo(definitionID)
            if type(entry) ~= "table" or (definitionID and type(definition) ~= "table") then
                Rules.CountMiss(misses, counted, specID, inAnswer)
                return nil
            end
            local talent = definition and definition.spellID
            if talent and want[talent] then
                local spots = found[talent] or {}
                found[talent] = spots
                spots[#spots + 1] = { node = nodeID, entry = entryID }
                any = true
            end
        end
    end
    local ms = debugprofilestop() - start
    if ms > (GroupInspect.locateMs or 0) then GroupInspect.locateMs = ms end
    if not any then
        Rules.CountMiss(misses, counted, specID, inAnswer)
        return nil
    end
    local covered = {}
    for id in pairs(want) do covered[id] = true end
    local built = { found = found, covered = covered }
    index[specID] = built
    return built
end

-- A walk covers what the index already covered and what is wanted now.
local function WalkSet(built, want)
    local set = {}
    if built then
        for id in pairs(built.covered) do set[id] = true end
    end
    for id in pairs(want) do set[id] = true end
    return set
end

-- Every kept wanted talent's rank in config: the active entry's rank, the
-- largest over the talent's nodes, 0 when not taken or not in the tree. Nil
-- and a reason when it cannot be answered; "combat" means a walk waits for
-- combat's end without a miss.
local function Read(config, specID, loadoutSpec, want, skip)
    if config == INSPECT_CONFIG and C_Traits.HasValidInspectData() ~= true then return nil, "no-data" end
    local info = C_Traits.GetConfigInfo(config)
    local trees = type(info) == "table" and info.treeIDs
    if type(trees) ~= "table" then return nil, "unreadable" end
    -- The inspect config names no player; a loadout of another class is not
    -- the requested one and must not cost the spec a walk.
    local tree = C_ClassTalents.GetTraitTreeForSpec(specID)
    if not HasTree(trees, tree) then return nil, "unreadable" end
    local built = index[specID]
    local plan = Rules.WalkPlan((misses[specID] or 0) >= Rules.MAX_MISSES, specID, loadoutSpec,
        InCombatLockdown(), Rules.Covers(built, want))
    if plan == "miss" then
        return nil, loadoutSpec ~= specID and "spec-mismatch" or "walks-spent"
    end
    if plan == "skip" then return nil, "combat" end
    if plan == "walk" then
        built = Index(specID, tree, config, WalkSet(built, want))
        if not built then return nil, "unreadable" end
    end
    local out = {}
    for talent, spots in pairs(built.found) do
        if want[talent] and Rules.Kept(skip, talent) then
            local rank = 0
            for _, at in ipairs(spots) do
                local node = C_Traits.GetNodeInfo(config, at.node)
                if not (type(node) == "table" and type(node.ID) == "number" and node.ID > 0) then
                    return nil, "unreadable"
                end
                local current = node.activeEntry
                if node.subTreeActive ~= false and type(current) == "table" and current.entryID == at.entry
                    and type(node.activeRank) == "number" and node.activeRank > rank then
                    rank = node.activeRank
                end
            end
            out[talent] = rank
        end
    end
    return Rules.FillAbsent(out, want, skip, built.found, built.covered)
end

local function SafeRead(config, specID, loadoutSpec, want, skip)
    local ok, ranks, reason = pcall(Read, config, specID, loadoutSpec, want, skip)
    if not ok then return nil, "unreadable" end
    return ranks, reason
end

local function Merge(snap, specID, ranks)
    local built = index[specID]
    local found = built and built.found or {}
    for id, rank in pairs(ranks) do
        snap.ranks[id], snap.covered[id] = rank, true
        snap.absent[id] = not found[id] or nil
    end
    snap.readAt, snap.stale, snap.reason = GetTime(), nil, nil
end

-- Another addon's inspect answers here too; only the pending GUID counts.
local function OnInspectReady(guid)
    if pendingGUID == nil or KE:IsSecretValue(guid) or guid ~= pendingGUID then return end
    local entry = pendingEntry
    pendingGUID, pendingEntry = nil, nil
    local unit = entry.unit
    if KE:GetSafeUnitGUID(unit) == guid then
        local spec = Ask(C_SpecializationInfo.GetInspectSpecialization, unit)
        local snap = snapshots[guid]
        if not snap or snap.spec ~= spec then
            snap = { ranks = {}, absent = {}, covered = {} }
            snapshots[guid] = snap
        end
        snap.spec = spec
        answer = answer + 1
        readingGUID = guid
        -- An owner's error reaches the error handler, and the answer still
        -- finishes for every owner.
        Rules.Dispatch(owners, function(owner)
            local fn = owner.callbacks.OnRead
            if fn then
                local ok, err = pcall(fn, guid, unit, snap)
                if not ok then geterrorhandler()(err) end
            end
        end)
        readingGUID = nil
    end
    if not (Rules.InspectInUse(InspectViews()) or Rules.ForeignBusy(GetTime(), foreignAt)) then
        pcall(ClearInspectPlayer)
    end
    local record = queue[guid]
    if record and Rules.Wanted(owners, guid) then
        Rules.CountTry(record, GetTime(), Rules.OnlyStale(owners, guid))
    end
    Rules.Dispatch(owners, function(owner)
        local fn = owner.callbacks.OnChanged
        if fn then fn(guid, snapshots[guid]) end
    end)
end

local function OnEvent(_, event, guid)
    if event == "INSPECT_READY" then OnInspectReady(guid) end
end

local function Stop()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
end

-- One request at most per tick, and none in the cases NextInspect refuses.
local function Tick()
    local now = GetTime()
    if pendingGUID then
        if not Rules.TimedOut(now, lastRequest) then return end
        local record = queue[pendingGUID]
        if record then Rules.CountTry(record, now, Rules.OnlyStale(owners, pendingGUID)) end
        pendingGUID, pendingEntry = nil, nil
    end
    local waiting = false
    for _, record in ipairs(union) do
        local entry = record.entry
        record.done = not Rules.Wanted(owners, entry.guid)
        if not record.done then
            waiting = true
            record.canInspect = Ask(CanInspect, entry.unit) == true
            record.offline = Ask(UnitIsConnected, entry.unit) == false
        end
    end
    if not waiting then
        Stop()
        return
    end
    local inspectShown, talentsInspecting = InspectViews()
    local chosen = Rules.NextInspect({
        inspectShown = inspectShown,
        talentsInspecting = talentsInspecting,
        inCombat = InCombatLockdown(),
        now = now,
        lastRequest = lastRequest,
        foreignAt = foreignAt,
    }, union)
    if not chosen then return end
    lastRequest = now
    local entry = chosen.entry
    if pcall(NotifyInspect, entry.unit) then
        pendingGUID, pendingEntry = entry.guid, entry
    else
        Rules.CountTry(chosen, now, Rules.OnlyStale(owners, entry.guid))
    end
end

local function Wake()
    if ticker or not active then return end
    for _, record in ipairs(union) do
        if Rules.Wanted(owners, record.entry.guid) then
            ticker = C_Timer.NewTicker(TICK, Tick)
            return
        end
    end
end

-- Another addon's inspect request. KE's own never reach the hook: they call
-- the local captured at load, and the hook wraps only the global.
local function OnForeignInspect()
    if active then foreignAt = GetTime() end
end

-- The frame and the hook wait for the first owner with demand; a hook cannot
-- be removed, so it stays installed and inert while nobody is active.
local function Activate()
    if not hooked and type(_G.NotifyInspect) == "function" then
        hooksecurefunc("NotifyInspect", OnForeignInspect)
        hooked = true
    end
    if not GroupInspect.frame then
        GroupInspect.frame = CreateFrame("Frame")
        GroupInspect.frame:SetScript("OnEvent", OnEvent)
    end
    GroupInspect.frame:RegisterEvent("INSPECT_READY")
end

-- The walk index and its misses outlive this; what was read per GUID goes.
local function Deactivate()
    if GroupInspect.frame then GroupInspect.frame:UnregisterEvent("INSPECT_READY") end
    Stop()
    pendingGUID, pendingEntry = nil, nil
    wipe(queue)
    wipe(snapshots)
    union = {}
end

-- A GUID nobody lists keeps its record through a roster settle while it is
-- still in the group; one that left loses it. An unreadable answer counts as
-- gone.
local function Rebuild()
    union = Rules.Union(owners, queue)
    local listed = {}
    for _, record in ipairs(union) do listed[record.entry.guid] = true end
    for guid in pairs(queue) do
        if not listed[guid] and Ask(IsGUIDInGroup, guid) ~= true then queue[guid] = nil end
    end
    for guid in pairs(snapshots) do
        if not queue[guid] then snapshots[guid] = nil end
    end
end

local function Apply()
    if Rules.AnyActive(owners) then
        if not active then
            active = true
            Activate()
        end
        Rebuild()
        Wake()
    elseif active then
        active = false
        Deactivate()
    end
end

-- list: entries carrying guid and unit, read live at each use and never
-- written to; nil when the owner needs nobody read.
---@param list table?
function Handle:SetDemand(list)
    local owner = self.owner
    if owner.released then return end
    owner.demand, owner.has = list, nil
    if list then
        local has = {}
        for _, e in ipairs(list) do
            if e.guid ~= nil then has[e.guid] = true end
        end
        owner.has = has
    end
    Apply()
end

function Handle:Wake()
    if self.owner.released then return end
    Wake()
end

---@param guid string
---@return KE.GroupInspectSnapshot?
function Handle:Get(guid)
    if self.owner.released then return nil end
    return snapshots[guid]
end

-- Every spec's walk misses go, whatever the GUID; reason marks the
-- snapshots stale. Starts nothing.
---@param guid string?
---@param reason string
function Handle:Refresh(guid, reason)
    if self.owner.released then return end
    wipe(misses)
    wipe(counted)
    if guid == nil then
        for _, snap in pairs(snapshots) do snap.stale = reason end
    elseif snapshots[guid] then
        snapshots[guid].stale = reason
    end
end

-- Only while the service hands out guid's answer, while the inspect data is valid.
---@param guid string
---@param specID number
---@param want table
---@param skip table?
---@return table? ranks
---@return string? reason
function Handle:ReadRanks(guid, specID, want, skip)
    if self.owner.released or guid ~= readingGUID then return nil, "no-data" end
    local snap = snapshots[guid]
    -- An earlier owner's OnRead can change demand and drop the snapshot.
    if not snap then return nil, "no-data" end
    local ranks, reason = SafeRead(INSPECT_CONFIG, specID, snap.spec, want, skip)
    if ranks then
        Merge(snap, specID, ranks)
    else
        snap.reason, snap.stale = reason, reason
    end
    return ranks, reason
end

function Handle:Release()
    local owner = self.owner
    if owner.released then return end
    owner.released, owner.demand, owner.has = true, nil, nil
    Apply()
end

-- Starts nothing: the queue runs once an owner sets demand.
---@param key string
---@param callbacks KE.GroupInspectCallbacks
---@return KE.GroupInspectHandle
function GroupInspect:Subscribe(key, callbacks)
    local old = byKey[key]
    if old and not old.released then return old.handle end
    local owner = { key = key, callbacks = callbacks }
    owner.handle = setmetatable({ owner = owner }, Handle)
    local slot = #owners + 1
    if old then
        for i, o in ipairs(owners) do
            if o == old then slot = i end
        end
    end
    owners[slot] = owner
    byKey[key] = owner
    return owner.handle
end

-- The player's own active config, read through the same index.
---@param specID number
---@param want table
---@param skip table?
---@return table? ranks
---@return string? reason
function GroupInspect:ReadOwnRanks(specID, want, skip)
    local config = Ask(C_ClassTalents.GetActiveConfigID)
    if config == nil then return nil, "no-config" end
    return SafeRead(config, specID, specID, want, skip)
end

-- ╔══════════════════════════════════════════════════════════╗
-- ║  PartyBuffs.lua                                          ║
-- ║  Module: Party Buffs                                     ║
-- ║  Purpose: Icons beside each teammate's party frame while ║
-- ║           one of their big buffs is up.                  ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- Nothing here reads an aura. Each teammate slot has one Blizzard aura
-- container bound to that teammate's unit, with one group per category: the
-- engine matches the auras and shows the buttons, and KE only dresses them.
-- The buttons deny tainted access while auras are secret, so every touch of a
-- container or a button after creation is a pcall.

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class PartyBuffs: AceModule, AceEvent-3.0
local PB = KitnEssentials:NewModule("PartyBuffs", "AceEvent-3.0")

local _G = _G
local AnchorUtil = AnchorUtil
local CreateFrame = CreateFrame
local UIParent = UIParent
local C_ChallengeMode = C_ChallengeMode
local C_DelvesUI = C_DelvesUI
local C_PvP = C_PvP
local C_Item = C_Item
local C_Spell = C_Spell
local C_Timer = C_Timer
local GetTime = GetTime
local IsInGroup = IsInGroup
local IsInInstance = IsInInstance
local IsInRaid = IsInRaid
local UnitInRaid = UnitInRaid
local UnitIsUnit = UnitIsUnit
local debugprofilestop = debugprofilestop
local issecretvalue = issecretvalue
local ipairs = ipairs
local pairs = pairs
local pcall = pcall
local select = select
local tostring = tostring
local type = type
local unpack = unpack
local wipe = wipe
local table_concat = table.concat
local table_remove = table.remove
local table_sort = table.sort
local math_min = math.min

local CDRules = KE.PartyCooldownsRules
local Cell = KE.PartyCooldownsCell
local Spec = KE.PartyCooldownsSpec
local Track = KE.PartyCooldownsSensor
local Pot = KE.PartyPotions
local PotRules = KE.PartyPotionsRules
local HX = KE.HealerExternals
local Deaths = KE.PartyCooldownsDeaths

-- Times each group build and logs every candidate frame, binding and watched
-- show or hide.
local DEBUG_PB = false

local MAX_SLOTS = 5
local ROSTER_SETTLE = 0.5
local WORLD_SETTLE = 1
local PLACEHOLDER_ICON = 134400
-- The ring color while Border Color by Category is off. Every button has the
-- ring from creation, so off paints it clear rather than removing it.
local CLEAR = { 0, 0, 0, 0 }
local BLACK = { 0, 0, 0, 1 }
-- Reads pause this long once a key starts: its aura refresh is not a use.
local KEY_HOLD = 2
local PREVIEW_BUFFS = {
    { trinket = 1297761, potion = 1236616, external = 102342 },
    { trinket = 1293316, potion = 1236994, external = 6940 },
    { trinket = 1295885, potion = 1236998, external = 116849 },
    { trinket = 1250533, potion = 1295132, external = 47788 },
}
-- One sample spec per stand-in row, the cooling sample's seconds left, and the
-- most samples a row draws: the Max Cooldown Icons ceiling.
local PREVIEW_SPECS = { 71, 102, 1473, 266 }
local PREVIEW_LEFT = 74
local PREVIEW_CELLS = KE.PartyBuffsRules.MAX_COOLDOWN_ICONS
-- Each stand-in row's race for its racial sample; no Evoker racial is tracked.
local PREVIEW_RACES = { "Dwarf", "NightElf", false, "DarkIronDwarf" }
-- No item is read for a stand-in row, so its sample trinkets take this length.
local PREVIEW_TRINKET_CD = 120
-- Levels a preview row sits above a live one, above its container's buttons.
local PREVIEW_LEVEL_LIFT = 10

local GATE_EVENTS = {
    "ZONE_CHANGED_NEW_AREA",
    "CHALLENGE_MODE_COMPLETED",
    "CHALLENGE_MODE_RESET",
    "ACTIVE_DELVE_DATA_UPDATE",
}

-- One per category, in on-screen order. The border stays black; the category
-- color is the inner ring's, whose key the dressing reads from the
-- capabilities. Every button gets a glow host when it is made, so the glow
-- switch needs no new buttons.
local DESCRIPTORS = {}
for i, category in ipairs(KE.PartyBuffsRules.CATEGORIES) do
    DESCRIPTORS[i] = {
        key = category.key,
        category = category,
        capabilities = {
            hasBorder = true, hasGlow = true, hasDispelBadge = false, hasDispelRing = true,
            ringColorKey = "Ring" .. category.colorKey:sub(6),
        },
    }
end

PB.active = false
PB.previewing = false
PB.pumping = false
PB.resolvePending = false
PB.restylePending = false
PB.reconfigurePending = false
PB.buildPending = false
PB.interfaceHidden = false
PB.slots = {}
PB.bindings = {}
PB.rosterKept = {}
PB.queue = {}
PB.queued = {}
PB.watchedCells = setmetatable({}, { __mode = "k" })
PB.previewRows = {}
-- "HEALER" or "DEFAULT": the placement view the settings page last showed.
-- Kept while the preview is hidden: reopening the window shows the preview
-- again without rebuilding the page, and only the page sets it.
PB.previewContext = nil

local function Debug(fmt, ...)
    if not DEBUG_PB then return end
    local count = select("#", ...)
    local args = { ... }
    for i = 1, count do args[i] = tostring(args[i]) end
    KE:Print("[PB] " .. fmt:format(unpack(args, 1, count)))
end

local function IconsOn()
    return PB.db.FrameIcons == true
end

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function PB:UpdateDB()
    self.db = KE.db.profile.PartyBuffs
end

function PB:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

---------------------------------------------------------------------------------
-- Gate
---------------------------------------------------------------------------------
-- A read that errors or comes back secret counts as false, so an unreadable
-- place is treated as one the tracker does not run in.
local function PlainTrue(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, value = pcall(fn, ...)
    if not ok or issecretvalue(value) then return false end
    return value == true
end

local function ReadsUnhidden()
    local RA = C_RestrictedActions
    return RA ~= nil and CDRules.ReadsUnhidden(Enum and Enum.AddOnRestrictionType, RA.IsAddOnRestrictionActive)
end

function PB:ReadFacts()
    local facts = {
        challengeActive = PlainTrue(C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive),
        delveActive     = PlainTrue(C_DelvesUI and C_DelvesUI.HasActiveDelve),
        arena           = PlainTrue(C_PvP and C_PvP.IsArena),
        brawl           = PlainTrue(C_PvP and C_PvP.IsInBrawl),
    }
    local ok, inInstance, instanceType = pcall(IsInInstance)
    if ok and not issecretvalue(inInstance) and not issecretvalue(instanceType) then
        facts.inInstance = inInstance
        facts.instanceType = instanceType
    end
    return facts
end

function PB:EvaluateGate()
    local rules = KE.PartyBuffsRules
    local content = rules.ClassifyContent(self:ReadFacts())
    local inGroup, inRaid = PlainTrue(IsInGroup), PlainTrue(IsInRaid)
    -- The raid cooldowns box reads this to stay out of raid groups.
    self.inRaid = inRaid
    local on = rules.ShouldActivate(self.db, content, inGroup, inRaid)
    Debug("gate %s group=%s raid=%s -> %s", content, inGroup, inRaid, on and "activate" or "deactivate")
    if on then self:Activate() else self:Deactivate() end
end

-- Reached again while active from settings changes and world entry, so a
-- second call re-resolves rather than returning.
function PB:Activate()
    if not self.active then
        self.active = true
        self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnRelease")
        self:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", "OnRestrictionChanged")
        self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnSpecChanged")
        Spec.Activate()
        Track.ShowSensors()
        Pot.Activate()
        HX.Activate()
        -- The restriction event is not heard while inactive, so an end missed
        -- then would leave a check failed on hidden answers for the session.
        if ReadsUnhidden() then Track.RearmHiddenCheck() end
        -- The spec can change the icon size while the tracker is off, with no
        -- event to say so; the drain below reconfigures and restyles.
        local built = self.styleSettings and self.styleSettings.IconSize
        if KE.PartyBuffsRules.NeedsResize(built, select(5, self:Placement())) then
            self:BuildStyleSettings()
            self.reconfigurePending, self.restylePending = true, true
        end
    end
    self:ResolveAll()
    self:OnRelease()
end

-- Every built container is disabled, so no UNIT_AURA stays registered. The
-- frames cannot be destroyed and wait hidden until /reload. A pending roster
-- settle is left running: canceling it would let the next gate event bind
-- before the roster has settled.
function PB:Deactivate()
    self:ClearQueue()
    wipe(self.rosterKept)
    for k = 1, MAX_SLOTS do
        self.bindings[k] = nil
        self:DropSlot(k)
        if self.slots[k] then self.slots[k].member = nil end
    end
    Spec.Deactivate()
    Deaths.Off()
    Track.HideSensors()
    Pot.Deactivate()
    HX.Deactivate()
    if not self.active then return end
    self.active = false
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    self:UnregisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
    self:UnregisterEvent("PLAYER_SPECIALIZATION_CHANGED")
end

---------------------------------------------------------------------------------
-- Frames: a unit-frame addon's buttons first, then Blizzard's raid-style party
-- frames, then its portrait party frames, then, for Include Yourself, the
-- player frame. Portrait frames are pooled, so every scan looks them up fresh.
---------------------------------------------------------------------------------
local function PlainString(value)
    if issecretvalue(value) or type(value) ~= "string" then return nil end
    return value
end

-- The frame search and the roster keep must read a frame's unit alike.
local function FrameUnits(frame)
    local okAttr, attr = pcall(frame.GetAttribute, frame, "unit")
    return PlainString(frame.unit), okAttr and PlainString(attr) or nil
end

local function DebugName(frame)
    local ok, name = pcall(frame.GetName, frame)
    return ok and PlainString(name) or tostring(frame)
end

local function DebugPos(frame)
    local okLeft, left = pcall(frame.GetLeft, frame)
    local okTop, top = pcall(frame.GetTop, frame)
    if not (okLeft and okTop) or issecretvalue(left) or issecretvalue(top) then return "?" end
    if not (left and top) then return "none" end
    return ("%d,%d"):format(left, top)
end

local seen = {}

-- The unit comparison runs only for a visible frame with a token, and its
-- result is copied only when readable. Every candidate is watched, shown or
-- not: the right frame can appear after a resolve with no roster event. Only
-- a shown frame with a unit is kept: the pick reads no other, and the search
-- walks every unit button a unit-frame addon has built. fixedToken, when
-- given, is the frame's token whatever its unit reads.
local function AddCandidate(list, frame, family, raidIndex, fixedToken)
    if type(frame) ~= "table" or seen[frame] then return end
    seen[frame] = true
    if PB.active then PB:WatchCell(frame) end
    local okVisible, visible = pcall(frame.IsVisible, frame)
    if not (okVisible and not issecretvalue(visible) and visible == true) then
        if DEBUG_PB then
            local okAttr, attr = pcall(frame.GetAttribute, frame, "unit")
            Debug("cand %s %s %s vis=false at %s raid=%s -> -", family, DebugName(frame),
                PlainString(frame.unit) or (okAttr and PlainString(attr)) or nil, DebugPos(frame), raidIndex)
        end
        return
    end
    local candidate = { frame = frame, family = family, raidIndex = raidIndex, visible = true }
    if fixedToken then
        candidate.unit, candidate.fixed = fixedToken, true
    else
        candidate.unit, candidate.attrUnit = FrameUnits(frame)
    end
    candidate.token = KE.PartyBuffsRules.CandidateToken(candidate)
    if candidate.token then
        local okSame, same = pcall(UnitIsUnit, candidate.token, "player")
        candidate.compareOk = okSame
        if okSame then
            if issecretvalue(same) then
                candidate.compareSecret = true
            else
                candidate.compareSecret = false
                candidate.compareResult = same
            end
        end
    end
    if DEBUG_PB then
        local verdict = "-"
        if candidate.token then
            verdict = KE.PartyBuffsRules.IsPlayerCandidate(candidate) and "skip" or "track"
        end
        Debug("cand %s %s %s vis=%s at %s raid=%s cmp=%s/%s/%s -> %s", family, DebugName(frame),
            candidate.token, candidate.visible, DebugPos(frame), raidIndex,
            candidate.compareOk, candidate.compareSecret, candidate.compareResult, verdict)
    end
    if candidate.token then list[#list + 1] = candidate end
end

local function AddHeaderChildren(list, header, family, raidIndex)
    if type(header) ~= "table" then return end
    for i = 1, 5 do
        local ok, child = pcall(header.GetAttribute, header, "child" .. i)
        if ok then AddCandidate(list, child, family, raidIndex) end
    end
end

function PB:FindFrames()
    local list = {}
    wipe(seen)
    local raidIndex
    local okIndex, index = pcall(UnitInRaid, "player")
    if okIndex and not issecretvalue(index) and type(index) == "number" then raidIndex = index end

    local ns = _G.EllesmereUI and _G.EllesmereUI._ModuleNS
    ns = ns and ns.EllesmereUIRaidFrames
    -- The party buttons exist from login, but join the registry only after
    -- every raid button is styled, which after a /reload can be well after
    -- they show. Listing them here gets them watched while still hidden.
    local party = ns and ns._partyAllButtons
    if type(party) == "table" then
        for i = 1, #party do
            AddCandidate(list, party[i], "eui", raidIndex)
        end
    end
    local buttons = ns and ns._euiUnitButtons
    if type(buttons) == "table" then
        for key, value in pairs(buttons) do
            AddCandidate(list, type(key) == "table" and key or value, "eui", raidIndex)
        end
    end
    -- Read from the headers, not the addon's own getters: they return only a
    -- party header button already showing player or partyN, so any other
    -- button would never be watched.
    local danders = _G.DandersFrames
    if type(danders) == "table" then
        AddHeaderChildren(list, danders.partyHeader, "danders", raidIndex)
        AddHeaderChildren(list, danders.arenaHeader, "danders", raidIndex)
    end
    for i = 1, 5 do
        AddCandidate(list, _G["CompactPartyFrameMember" .. i], "compact", raidIndex)
    end
    local partyFrame = _G.PartyFrame
    if type(partyFrame) == "table" then
        for i = 1, 4 do
            AddCandidate(list, partyFrame["MemberFrame" .. i], "portrait", raidIndex)
        end
    end
    -- The portrait party frames never show you, so there your own frame is
    -- the player frame. Last, so a party frame holding you keeps the row; its
    -- unit names the vehicle while you ride one, so the token is fixed.
    local includeSelf = self.db.IncludeSelf == true
    if includeSelf then AddCandidate(list, _G.PlayerFrame, "player", raidIndex, "player") end
    return KE.PartyBuffsRules.PickFrames(list, MAX_SLOTS, includeSelf)
end

---------------------------------------------------------------------------------
-- Slots and the build queue
---------------------------------------------------------------------------------
function PB:DropSlot(k)
    local slot = self.slots[k]
    if not slot then return end
    if slot.container then pcall(slot.container.SetEnabled, slot.container, false) end
    if slot.track then Track.Unbind(slot.track) end
    slot.holder:Hide()
    -- A skipped clear leaves only a hidden frame's old point.
    if KE:CanReanchorNow(slot.holder) then slot.holder:ClearAllPoints() end
    self:SyncDeathWatch()
end

function PB:SlotComplete(k)
    local slot = self.slots[k]
    if not (slot and slot.container) then return false end
    -- A retired button is lost capacity; the build replaces the container
    -- once auras are not secret.
    if slot.dressFailed and not KE:AreAuraIdentitiesHidden() then return false end
    for i = 1, #DESCRIPTORS do
        local d = DESCRIPTORS[i]
        if self.db[d.category.trackKey] == true and not slot.groups[d.key] then return false end
    end
    return true
end

function PB:ClearQueue()
    self.queue = {}
    self.queued = {}
end

-- The one every-frame path: at most one container or group build (about 3 ms)
-- per frame. A slot stays at the head of the queue until BuildSlot reports it
-- finished, so its teammate shows before the next slot starts. pumping stays
-- set while BuildSlot runs, so an Enqueue from inside it schedules nothing and
-- only this function schedules the next pump.
-- HX.QUEUE_KEY is the raid cooldowns box's key, any other string a
-- potion row's unit token, a number a party slot's.
local function BuildHead()
    local k = PB.queue[1]
    if k == HX.QUEUE_KEY then return HX.BuildNext() end
    if type(k) == "string" then return Pot.BuildNext(k) end
    return PB:BuildSlot(k)
end

local function PumpBuild()
    if not (PB:IsEnabled() and PB.active) then
        PB.pumping = false
        PB:ClearQueue()
        return
    end
    local k = PB.queue[1]
    if k then
        -- An error is reported and drops the slot from the queue, so pumping
        -- is never left set; the slot's next bind queues it again.
        local ok, done = xpcall(BuildHead, geterrorhandler())
        if done or not ok then
            table_remove(PB.queue, 1)
            PB.queued[k] = nil
        end
    end
    if #PB.queue > 0 then
        C_Timer.After(0, PumpBuild)
    else
        PB.pumping = false
    end
end

function PB:Enqueue(k)
    if not self.queued[k] then
        self.queued[k] = true
        self.queue[#self.queue + 1] = k
    end
    if not self.pumping then
        self.pumping = true
        C_Timer.After(0, PumpBuild)
    end
end

-- The frame search with each frame in the slot that already holds its token.
-- The preview reads its member from the slot, so it must place rows the same way.
function PB:MatchFrames()
    local found = self:FindFrames()
    local units = {}
    for k = 1, MAX_SLOTS do units[k] = self.slots[k] and self.slots[k].unit end
    return KE.PartyBuffsRules.MatchSlots(found, units, MAX_SLOTS), #found
end

-- The one place bindings are made: BindSlot and BuildSlot act only on a
-- binding set here. While a roster change settles, a token can still name a
-- frame's previous occupant, so a slot stays dropped until the settle timer
-- resolves unless PB:KeepRosterRows kept it.
function PB:ResolveAll()
    -- Off, no row is built and no frame is searched; the potion rows and the
    -- externals box bind on their own and share the build queue, so it is
    -- not cleared. The watcher holds their reads after the interface shows.
    if not IconsOn() then
        self:EnsureUIWatcher()
        if not UIParent:IsShown() then self.interfaceHidden = true end
        self.buildPending = false
        local had = false
        for k = 1, MAX_SLOTS do
            if self.bindings[k] then had = true end
            self.bindings[k] = nil
            self:DropSlot(k)
            if self.slots[k] then self.slots[k].member = nil end
        end
        wipe(self.rosterKept)
        if had then self:SyncMembers() end
        return
    end
    if self._rosterTimer then
        -- A kept row is placed again: the icon size may have changed.
        for k = 1, MAX_SLOTS do
            local slot, binding = self.slots[k], self.bindings[k]
            if not self.rosterKept[k] then
                self.bindings[k] = nil
                self:DropSlot(k)
            elseif slot and binding
                and not self:PlaceHolder(slot.holder, binding.frame, false, self.styleSettings.IconSize) then
                self.buildPending = true
            end
        end
        return
    end
    -- Hiding the interface hides every party frame, and every row with
    -- UIParent, so the bindings and their running counts are kept. The search
    -- still runs so each frame is watched: their OnShow resolves again.
    if not UIParent:IsShown() then
        self.interfaceHidden = true
        self:FindFrames()
        return
    end
    if self.interfaceHidden then
        self.interfaceHidden = false
        Track.InterfaceShown()
    end
    self.buildPending = false
    local bindings, count = self:MatchFrames()
    Debug("resolve %d frame(s)", count)
    for k = 1, MAX_SLOTS do
        local binding = bindings[k]
        self.bindings[k] = binding
        if binding and self:SlotComplete(k) then
            self:BindSlot(k, binding)
        else
            self:DropSlot(k)
            if binding then self:Enqueue(k) end
        end
    end
end

-- While a roster change is settling its own timer resolves, so nothing is
-- scheduled here.
function PB:QueueResolve()
    if self.resolvePending or self._rosterTimer then return end
    self.resolvePending = true
    C_Timer.After(0, function()
        self.resolvePending = false
        if not (self:IsEnabled() and self.active) then return end
        self:ResolveAll()
        if self.previewing then self:ShowPreview() end
    end)
end

local function OnCellChanged(frame, change)
    -- A hook cannot be removed, so a frame watched while the switch was on
    -- stops here while it is off.
    if not (PB:IsEnabled() and PB.active and IconsOn()) then return end
    if DEBUG_PB then Debug("cell %s %s", DebugName(frame), change) end
    PB:QueueResolve()
end

local function OnCellHidden(frame) OnCellChanged(frame, "hidden") end
local function OnCellShown(frame) OnCellChanged(frame, "shown") end

-- A frame can hide or come back without a roster event (another addon swaps
-- its party header, Blizzard rebuilds its frames, the whole interface is
-- hidden and shown), so each frame is hooked once both ways and the
-- re-resolve waits a frame for the replacement to exist.
function PB:WatchCell(frame)
    if self.watchedCells[frame] then return end
    self.watchedCells[frame] = true
    pcall(frame.HookScript, frame, "OnHide", OnCellHidden)
    pcall(frame.HookScript, frame, "OnShow", OnCellShown)
end

-- The layout options are replaced whole on every set, so the category's
-- position rides along each time; without it a late group falls back to
-- build order.
function PB:GroupLayout(index)
    local layout = KE.AuraContainer.GroupLayout(self.styleSettings)
    layout.layoutIndex = index
    return layout
end

-- Buttons whose setup failed: true once retired, false while the retire is
-- owed. Such a button is never drawn and takes no mouse; its regions may be
-- half made, so it is never restyled.
local retired = {}
-- Containers replaced per slot after a failed setup. Past this, a failed
-- button is kept as the engine made it, which may be blank: only a defect in
-- the dressing fails setup, and it would fail every replacement the same way.
local MAX_REPLACEMENTS = 2

local function RetireButton(button)
    local ok = pcall(function()
        button:SetAlpha(0)
        button:EnableMouse(false)
    end)
    retired[button] = ok
    if not ok then PB.restylePending = true end
    return ok
end

function PB:AddGroup(k, slot, d)
    local filter, candidates, maxFrames, index =
        KE.PartyBuffsRules.BuildGroupConfig(d.category, self.db, slot.cellBuffs)
    local container = slot.container
    local started = DEBUG_PB and debugprofilestop()
    local ok = pcall(container.AddAuraGroup, container, d.key, filter, {
        candidateFilters = candidates,
        maxFrameCount    = maxFrames,
        sortMethod       = AuraContainerSortMethod.AuraInstanceIDOnly,
        sortDirection    = AuraContainerSortDirection.Normal,
        -- Reads the live settings: buttons made in a later batch are dressed
        -- from the profile current at that time. Blizzard applies the
        -- button's access restrictions only after this returns, so nothing
        -- here can be refused; a failure is a defect, and the log names it.
        -- The button is a Button and would stop a click meant for the party
        -- frame under or beside it; hover stays on for the tooltip.
        initializeFrame  = function(button)
            local dressed = pcall(KE.AuraStyle.InitializeButton, button, nil, d, PB.styleSettings)
            if not dressed then Debug("slot %d group %s: button dressing failed", k, d.key) end
            if not pcall(button.SetMouseClickEnabled, button, false) then
                Debug("slot %d group %s: click-through failed", k, d.key)
                dressed = false
            end
            if not dressed then
                if (slot.replacements or 0) < MAX_REPLACEMENTS then
                    RetireButton(button)
                    slot.dressFailed = true
                    PB.buildPending = true
                else
                    Debug("slot %d group %s: replacements spent, button kept", k, d.key)
                end
            end
        end,
        layout           = self:GroupLayout(index),
    })
    if started then
        Debug("slot %d group %s %.2f ms t=%.3f%s", k, d.key, debugprofilestop() - started, GetTime(),
            ok and "" or " FAILED")
    end
    -- The group is registered, with its settings, before the call's last
    -- steps, so a late failure leaves it in place and adding it again would
    -- assert.
    local unknown = false
    if not ok then
        local okHas, has = pcall(container.HasAuraGroup, container, d.key)
        ok = okHas and has == true
        unknown = not okHas
    end
    -- Unreadable: the group may exist with this filter. The next build adds it
    -- again, which asserts if it exists, and asks again.
    slot.unknownGroups[d.key] = unknown or nil
    if ok then slot.groups[d.key] = true else self.buildPending = true end
end

-- Returns false when any container call was refused, so the caller can retry.
-- The while-active container starts after the slot's cooldown cells, on their
-- line or the next (SlotGeometry).
function PB:ApplySlotLayout(slot)
    local db = self.db
    local layout, _, _, perRow = self:Placement()
    -- The dressed size, not a fresh spec read: the holder must fit what it clips.
    local size = self.styleSettings.IconSize
    local container = slot.container
    -- Unrounded: snapping one offset alone would push the last icon past the
    -- clipping holder when a typed size is fractional.
    local g = KE.PartyBuffsRules.SlotGeometry(db, layout, slot.cellCount or 0, perRow, size)
    local x, y = KE.PartyBuffsRules.IconOffset(g, layout, g.buffIndex, g.buffLine)
    slot.holder:SetSize(g.width, g.height)
    slot.layoutPerRow, slot.layoutRecord = perRow, layout
    self:PlaceCells(slot, layout, perRow, size)
    local flow = AnchorUtil.FlowDirection
    local clean = pcall(container.SetFlowLayoutGrowthDirection, container,
        layout.left and flow.Left or flow.Right, layout.up and flow.Up or flow.Down)
    -- The axis first: the anchor point and the line size are read against it.
    local axis = layout.vertical and AnchorUtil.FlowLayoutAxis.Vertical or AnchorUtil.FlowLayoutAxis.Horizontal
    clean = pcall(container.SetFlowLayoutAxis, container, axis) and clean
    clean = pcall(container.SetFlowLayoutAnchorPoint, container, layout.corner) and clean
    clean = pcall(container.SetFlowLayoutMaximumLineSize, container,
        KE.PartyBuffsRules.LineSize(db, g.buffPerLine, size)) and clean
    if KE.PartyBuffsRules.NeedsPin(slot, layout.corner, x, y) then
        local ok = pcall(function()
            container:ClearAllPoints()
            container:SetPoint(layout.corner, slot.holder, layout.corner, x, y)
        end)
        KE.PartyBuffsRules.RecordPin(slot, ok, layout.corner, x, y)
        clean = ok and clean
    end
    return clean
end

-- Adds at most one group per call and returns false while one is still
-- missing. A failed group leaves buildPending for the drain rather than a
-- retry every frame, and the slot is bound with the groups it has. A slot
-- whose teammate went away while it waited builds nothing.
function PB:BuildSlot(k)
    local binding = self.bindings[k]
    if not binding then return true end
    if not KE:AuraContainersAvailable() then
        Debug("slot %d: aura containers unavailable", k)
        self.buildPending = true
        return true
    end
    local slot = self.slots[k]
    if not slot then
        local holder = CreateFrame("Frame", "KE_PartyBuffsHolder" .. k, UIParent)
        holder:EnableMouse(false)
        holder:SetClipsChildren(true)
        holder:Hide()
        slot = { holder = holder, groups = {}, unknownGroups = {} }
        self.slots[k] = slot
    end
    if slot.container and slot.dressFailed and not KE:AreAuraIdentitiesHidden() then
        local old = slot.container
        if pcall(function()
            old:SetEnabled(false)
            old:Hide()
        end) then
            Debug("slot %d: container replaced after a failed button setup", k)
            slot.container, slot.groups, slot.unknownGroups = nil, {}, {}
            slot.unit, slot.cellSig = nil, nil
            KE.PartyBuffsRules.RecordPin(slot, false)
            slot.replacements, slot.dressFailed = (slot.replacements or 0) + 1, nil
        else
            self.buildPending = true
            return true
        end
    end
    if not slot.container then
        local corner = self:Placement().corner
        local ok, container = pcall(CreateFrame, "AuraContainer", "KE_PartyBuffsContainer" .. k,
            slot.holder, "CustomAuraContainerTemplate")
        if not (ok and container) then
            Debug("slot %d: container failed", k)
            self.buildPending = true
            return true
        end
        -- Pinned before any group exists, when a pin is expected to be
        -- allowed. A refused pin records nothing, so the layout pass below
        -- pins it again.
        local pinned = pcall(container.SetPoint, container, corner, slot.holder, corner, 0, 0)
        pcall(container.EnableMouse, container, false)
        pcall(container.SetEnabled, container, false)
        slot.container = container
        KE.PartyBuffsRules.RecordPin(slot, pinned, corner, 0, 0)
    end
    local built, refused = false, false
    for i = 1, #DESCRIPTORS do
        local d = DESCRIPTORS[i]
        if self.db[d.category.trackKey] == true and not slot.groups[d.key] then
            self:AddGroup(k, slot, d)
            if slot.groups[d.key] and not self:SlotComplete(k) then return false end
            built, refused = true, not slot.groups[d.key]
            break
        end
    end
    -- Cell containers come after the groups, one build per frame like them,
    -- so a frame that built a group builds none. The re-bind runs on any
    -- refusal, since a refused build can change which cells are ready.
    local track = slot.track
    if not built and track and slot.holder:IsShown() and Track.Missing(track) then
        local made, again = Track.BuildNext(track)
        if not made then
            self:BindCooldowns(k, binding)
            -- A failed overlay build is counted and capped, so the slot stays
            -- queued for the next frame; any other refusal waits for the drain.
            if again then return false end
            self.buildPending = true
            return true
        end
        self:BindCooldowns(k, binding)
        return not Track.Missing(track)
    end
    if not self:ApplySlotLayout(slot) then self.reconfigurePending = true end
    self:BindSlot(k, binding)
    -- A refused group waits for the drain, and the slot's cell containers
    -- with it.
    if refused then return true end
    return not (slot.track and Track.Missing(slot.track))
end

-- The layout record, X, Y, icons per row and icon size in effect. A
-- preview row follows the settings page's view while it names one; the icons
-- follow the player's spec.
function PB:Placement(forPreview)
    local useHealer
    if forPreview and self.previewContext then
        useHealer = self.previewContext == "HEALER"
    else
        useHealer = KE:IsPlayerHealerSpec()
    end
    local rules = KE.PartyBuffsRules
    local side, x, y, perRow, size, grow = rules.ActivePlacement(self.db, useHealer)
    return rules.Layout(side, grow), x, y, rules.PerRow(perRow), size
end

-- Anchored, never parented: a child of a party frame inherits its protection
-- and could not be hidden in combat. It takes the party frame's strata, or
-- MEDIUM when that cannot be read; a preview row sits PREVIEW_LEVEL_LIFT
-- levels higher, so a hover stops at the preview and not at the live button
-- under it. size is the icon size the Center lift is measured in. Returns the
-- strata and level applied, or nil when the anchor was refused or the holder
-- may not move now.
function PB:PlaceHolder(holder, frame, forPreview, size)
    if not KE:CanReanchorNow(holder) then return nil end
    local side, x, y = self:Placement(forPreview)
    local dx, dy = KE.PartyBuffsRules.HolderOffset(side, self.db.IconSpacing, x, y, size)
    -- The Center lift is half an icon: a half pixel at an odd size.
    dy = KE:PixelSnap(dy)
    holder:ClearAllPoints()
    if not pcall(holder.SetPoint, holder, side.point, frame, side.rel, dx, dy) then
        return nil
    end
    local strata, level = "MEDIUM", nil
    local okStrata, frameStrata = pcall(frame.GetFrameStrata, frame)
    if okStrata and not issecretvalue(frameStrata) and type(frameStrata) == "string" then
        strata = frameStrata
    end
    local okLevel, frameLevel = pcall(frame.GetFrameLevel, frame)
    if okLevel and not issecretvalue(frameLevel) and type(frameLevel) == "number" then
        level = frameLevel + 10 + (forPreview and PREVIEW_LEVEL_LIFT or 0)
    end
    holder:SetFrameStrata(strata)
    if level then holder:SetFrameLevel(level) end
    return strata, level
end

-- Every refused call leaves buildPending set for the drain. Without its unit,
-- anchor or enable the slot is dropped until then.
function PB:BindSlot(k, binding)
    local slot = self.slots[k]
    local container = slot.container
    if slot.unit ~= binding.token then
        if not pcall(container.SetUnit, container, binding.token) then
            Debug("slot %d: SetUnit %s refused", k, binding.token)
            -- The container may already hold the new unit; nothing is assumed.
            slot.unit = nil
            self.buildPending = true
            return self:DropSlot(k)
        end
        slot.unit = binding.token
    end
    local strata, level = self:PlaceHolder(slot.holder, binding.frame, false, self.styleSettings.IconSize)
    if not strata then
        Debug("slot %d: anchor refused", k)
        self.buildPending = true
        return self:DropSlot(k)
    end
    local clean = pcall(container.SetFrameStrata, container, strata)
    if level then clean = pcall(container.SetFrameLevel, container, level + 1) and clean end
    if not pcall(container.SetEnabled, container, true) then
        Debug("slot %d: enable refused", k)
        self.buildPending = true
        return self:DropSlot(k)
    end
    slot.holder:SetAlpha(self.previewing and 0 or 1)
    slot.holder:Show()
    clean = pcall(container.UpdateAllAuras, container) and clean
    if not clean then
        Debug("slot %d: strata, level or refresh refused", k)
        self.buildPending = true
    end
    self:BindCooldowns(k, binding)
    if DEBUG_PB then
        Debug("slot %d -> %s (%s) %s at %s", k, binding.token, binding.family,
            DebugName(binding.frame), DebugPos(binding.frame))
    end
end

---------------------------------------------------------------------------------
-- Cooldown cells
---------------------------------------------------------------------------------
-- The member's spec list, racial and trinkets in the Icon Order card's
-- order, cut to the icon budget. A member whose spec is not known yet gets
-- no cooldown cell of any kind.
function PB:CooldownEntries(m)
    local db = self.db
    if not (m and m.spec) then return {} end
    local specID = m.spec
    local spells, racials, trinkets = {}, {}, {}
    if db.TrackBurst == true then
        for _, e in ipairs(CDRules.SpellList(specID, db)) do
            local taken = CDRules.CastTaken(specID, e.id, m.talents)
            if CDRules.TalentAllows(e, taken, specID) then
                e.charges = CDRules.CellCharges(e, specID, m.talents)
                e.cd = CDRules.CellLength(e, specID, m.talents, e.charges)
                e.lockOn = CDRules.LockOn(e, m.talents, m.isPlayer == true)
                e.texture = C_Spell.GetSpellTexture(CDRules.ShowID(e, specID, taken))
                spells[#spells + 1] = e
            end
        end
    end
    local racial = CDRules.MemberRacial(m.race, db)
    if racial then
        racial.texture = C_Spell.GetSpellTexture(racial.id)
        racials[1] = racial
    end
    if m.trinkets and db.TrackTrinket == true then
        for _, e in ipairs(CDRules.TrinketEntries(m.trinkets, Spec.lengths, db)) do
            e.texture = C_Item.GetItemIconByID(e.item)
            trinkets[#trinkets + 1] = e
        end
    end
    local rules = KE.PartyBuffsRules
    return rules.OrderCells({ spells = spells, racial = racials, trinket = trinkets },
        db.CooldownCategoryOrder, rules.CooldownIconCount(db))
end

-- Re-run on every bind and on each change to the member's spec, trinkets or
-- talents. For the same member and spec, a cell whose spell, charges and code
-- unit did not change keeps its count. When the GUID is secret the slot keeps
-- the record it had for the same token; a roster change or a closed gate
-- clears it first.
function PB:BindCooldowns(k, binding)
    local slot = self.slots[k]
    slot.track = slot.track or Track.NewSlot(slot.holder)
    local m = Spec.Member(binding.token)
    if not m and slot.member and slot.member.unit == binding.token then m = slot.member end
    local before = m and m.spec
    if m then
        Spec.Resolve(m)
        if m.isPlayer then Spec.ReadSelf(m) end
    end
    slot.member = m
    local spec = m and m.spec
    if slot.cdMember ~= m or slot.cdSpec ~= spec then
        Track.Reset(slot.track)
        slot.cdMember, slot.cdSpec = m, spec
    end
    local entries = self:CooldownEntries(m)
    local clean, restyle = Track.Apply(slot.track, binding.token, entries, self.cellStyle, self.styleSettings)
    slot.cellSize = self.cellStyle.size
    if not clean then self.buildPending = true end
    if restyle then self:Restyle() end
    if Track.Missing(slot.track) then self:Enqueue(k) end
    self:LayoutCells(slot, #entries)
    self:ExcludeCellTrinkets(k, slot, entries)
    self:SyncMembers()
    -- Spec.Resolve announces no change, and the raid cooldowns box may read
    -- this record too. Its resolve then finds the spec unmoved.
    if m and m.spec ~= before then HX.OnMemberChanged(m) end
    self:SyncDeathWatch()
end

-- A trinket with a cooldown icon leaves this row's while-active Trinkets
-- group, so it shows once; every other listed trinket still shows there. A
-- trinket never shows twice, on screen as well as by filter: the group's
-- buttons follow a new filter only when its container next processes, in its
-- own OnUpdate while visible, and the overlay's buttons likewise. So a newly
-- excluded trinket's icon waits for the settle (SettleCellTrinkets), and a
-- shown icon that hides keeps its trinket excluded until the settle, while
-- its emptied overlay button goes. After a refused filter call the group holds
-- any set issued since the last accepted one (TrinketShow).
function PB:ExcludeCellTrinkets(k, slot, entries)
    local track = slot.track
    slot.cellRelease = slot.cellRelease or {}
    -- Withholding a cell can hide the whole overlay and with it every cell,
    -- so a second pass settles the exclusion; after it no cell is ready.
    for _ = 1, 2 do
        local set, ids = {}, {}
        for i, e in ipairs(entries) do
            if e.trinket and track.ready[i] then
                for _, id in ipairs(e.buffs) do set[id] = true end
            end
        end
        -- Ready again before the settle: it stayed excluded, so it may show.
        for id in pairs(slot.cellRelease) do
            if set[id] then slot.cellRelease[id] = nil end
        end
        for id in pairs(slot.cellShow or {}) do
            if not set[id] then slot.cellRelease[id] = true end
        end
        for id in pairs(slot.cellRelease) do set[id] = true end
        for id in pairs(set) do ids[#ids + 1] = id end
        table_sort(ids)
        local sig = table_concat(ids, ",")
        if slot.cellSig ~= sig then
            local cellBuffs = #ids > 0 and set or nil
            slot.cellBuffs = cellBuffs
            local accepted = self:SetTrinketExclusion(slot, cellBuffs)
            slot.cellShow, slot.cellPending = CDRules.TrinketShow(slot.cellShow, set, accepted)
            slot.cellSig = accepted and sig or nil
            if not accepted then
                self.buildPending = true
                Debug("trinket exclusion refused")
            end
        end
        -- A release waits for a shown overlay host: the bind that shows it
        -- comes back here, so nothing polls meanwhile.
        local host = track.overlayHost
        if slot.cellPending or (next(slot.cellRelease) and not (host and not host:IsVisible())) then
            self:SettleCellTrinkets(k, slot)
        end
        local off, show = track.overlayOff, slot.cellShow
        for i, e in ipairs(entries) do
            if e.trinket and not (show and show[e.buffs[1]]) then Track.Withhold(track, i) end
        end
        if track.overlayOff == off then return end
    end
end

-- Two frames with the row visible after the latest bind that left an icon
-- waiting or a trinket released: by then the row's and the overlay's
-- containers have processed every filter that bind or an earlier one issued
-- (RunWhenVisibleOnce), so a waiting icon may show and a released trinket may
-- go back to the row. Every such bind starts the count again (the generation
-- in slot.settleGen), and a hidden row stops it until the next bind. Two
-- callbacks per bind that calls this; nothing runs while settled.
function PB:SettleCellTrinkets(k, slot)
    local gen = (slot.settleGen or 0) + 1
    slot.settleGen = gen
    local frames = 0
    local function Step()
        if slot.settleGen ~= gen then return end
        if not (self:IsEnabled() and self.active and slot.holder:IsVisible()) then return end
        frames = frames + 1
        if frames < 2 then
            C_Timer.After(0, Step)
            return
        end
        if slot.cellPending then slot.cellShow, slot.cellPending = slot.cellPending, nil end
        -- A hidden overlay host has not processed its emptied slots either; the
        -- bind that shows it starts the settle again.
        local host = slot.track and slot.track.overlayHost
        if next(slot.cellRelease) and not (host and not host:IsVisible()) then
            for id in pairs(slot.cellRelease) do
                slot.cellRelease[id] = nil
                slot.cellShow[id] = nil
            end
            slot.cellSig = nil
        end
        local binding = self.bindings[k]
        if binding and slot.container then self:BindCooldowns(k, binding) end
    end
    C_Timer.After(0, Step)
end

-- True when the Trinkets group is confirmed absent (it takes slot.cellBuffs
-- when it is built) or the client took the new filter. The engine sets the
-- filter before its last step (Blizzard_CustomAuraContainer.lua
-- SetAuraGroupCandidateFilters), so false means any set issued so far. A group
-- whose registration could not be read counts as refused.
function PB:SetTrinketExclusion(slot, cellBuffs)
    if not slot.container then return true end
    for i = 1, #DESCRIPTORS do
        local d = DESCRIPTORS[i]
        if d.category.excludesCells then
            if slot.unknownGroups[d.key] then return false end
            if not slot.groups[d.key] then return true end
            local _, candidates = KE.PartyBuffsRules.BuildGroupConfig(d.category, self.db, cellBuffs)
            return pcall(slot.container.SetAuraGroupCandidateFilters, slot.container, d.key, candidates)
        end
    end
    return true
end

-- Cells are KE frames: moving them is never refused. A slot built before its
-- first bind has no cells yet.
function PB:PlaceCells(slot, layout, perRow, size)
    local track = slot.track
    if not track then return end
    -- A row kept through a roster settle is laid out again with no bind, so a
    -- new size reaches its cells here. An unbound track has no cells to dress.
    if KE.PartyBuffsRules.NeedsResize(slot.cellSize, size) then
        for i = 1, track.count do track.view.Dress(track.cells[i], self.cellStyle, track.entries[i]) end
        slot.cellSize = size
    end
    local count = slot.cellCount or 0
    local g = KE.PartyBuffsRules.SlotGeometry(self.db, layout, count, perRow, size)
    for i = 1, count do
        local c = track.cells[i]
        local x, y = KE.PartyBuffsRules.IconOffset(g, layout, KE.PartyBuffsRules.GridPosition(i - 1, perRow))
        c:ClearAllPoints()
        c:SetPoint(layout.corner, slot.holder, layout.corner, x, y)
        pcall(Cell.Seat, c)
    end
end

-- The holder and the cells are laid out together, from one N.
function PB:LayoutCells(slot, count)
    local layout, _, _, perRow = self:Placement()
    if KE.PartyBuffsRules.NeedsLayout(slot, count, perRow, layout) then
        slot.cellCount = count
        if not self:ApplySlotLayout(slot) then self.reconfigurePending = true end
    else
        self:PlaceCells(slot, layout, perRow, self.styleSettings.IconSize)
    end
end

function PB:SyncMembers()
    local list = {}
    for k = 1, MAX_SLOTS do
        local slot = self.slots[k]
        if self.bindings[k] and slot and slot.member then list[#list + 1] = slot.member end
    end
    -- The raid cooldowns box needs its members' specs whether or not a
    -- party frame row shows them.
    for _, m in ipairs(HX.members) do
        local listed = false
        for _, have in ipairs(list) do
            if have == m then listed = true end
        end
        if not listed then list[#list + 1] = m end
    end
    Spec.SetMembers(list)
end

-- Only the changed member's cells are rebuilt. A dropped slot keeps its
-- member for the next bind but its holder is hidden; that bind rebuilds it.
function PB:RebindMember(m)
    for k = 1, MAX_SLOTS do
        local slot, binding = self.slots[k], self.bindings[k]
        if binding and slot and slot.container and slot.member == m and slot.holder:IsShown() then
            self:BindCooldowns(k, binding)
        end
    end
end

function PB:OnMemberChanged(m)
    if not (self:IsEnabled() and self.active) then return end
    self:RebindMember(m)
    HX.OnMemberChanged(m)
    if self.previewing then self:ShowPreview() end
end

---------------------------------------------------------------------------------
-- Ally deaths
---------------------------------------------------------------------------------
-- Every live row but the dying member's; preview rows, the potion bar and the
-- raid cooldowns box take no cut. Returns how many cells were cut.
function PB:OnAllyDied(token, guid)
    local n, cut = Track.Now(), 0
    for k = 1, MAX_SLOTS do
        local slot, binding = self.slots[k], self.bindings[k]
        if binding and slot and slot.track then
            local m = slot.member
            if not CDRules.SameMember(binding.token, m and m.guid, token, guid) then
                cut = cut + Track.DeathCut(slot.track, n)
            end
        end
    end
    Debug("ally %s died: %d cells cut", token, cut)
    return cut
end

local function OnAllyDied(token, guid) return PB:OnAllyDied(token, guid) end

-- The watch runs only while a live row holds a cell a death cuts.
function PB:SyncDeathWatch()
    if self.active then
        for k = 1, MAX_SLOTS do
            local slot = self.slots[k]
            if self.bindings[k] and slot and slot.track and Track.HasCut(slot.track) then
                Deaths.On(OnAllyDied)
                return
            end
        end
    end
    Deaths.Off()
end

---------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------
-- A row stays up, with its counts, while its frame still shows its token and
-- the token still names the member it was bound to; every other row is
-- dropped until the settle resolves. Party frames can re-sort their units on
-- a roster change.
function PB:KeepRosterRows()
    for k = 1, MAX_SLOTS do
        local slot, binding = self.slots[k], self.bindings[k]
        local m = slot and slot.member
        local keep = false
        if binding and m then
            local unit, attrUnit = FrameUnits(binding.frame)
            keep = KE.PartyBuffsRules.KeepRow(binding,
                KE.PartyBuffsRules.CandidateToken({ unit = unit, attrUnit = attrUnit }),
                PotRules.KeepOnRoster(m.guid, KE:GetSafeUnitGUID(binding.token), issecretvalue))
        end
        self.rosterKept[k] = keep or nil
        if keep then
            if slot.track then Track.Hold(slot.track, ROSTER_SETTLE) end
        else
            self.bindings[k] = nil
            self:DropSlot(k)
            if slot then slot.member = nil end
        end
    end
end

-- Frames re-sort after a roster change and a token can name someone else, so
-- queued builds drop and the scan waits for the roster to settle. Each update
-- restarts the full delay.
function PB:OnRoster()
    self:ClearQueue()
    self:KeepRosterRows()
    Deaths.Scan(true)
    -- A token can name someone else now, so the inspect list empties until the
    -- rows rebind (a kept row can add its member back sooner); whoever left
    -- is read again if they come back.
    Spec.SetMembers({})
    Spec.Prune()
    Pot.OnRoster()
    HX.OnRoster()
    if self._rosterTimer then self._rosterTimer:Cancel() end
    self._rosterTimer = C_Timer.NewTimer(ROSTER_SETTLE, function()
        self._rosterTimer = nil
        if not self:IsEnabled() then return end
        -- A token can change hands during the settle too.
        self:KeepRosterRows()
        wipe(self.rosterKept)
        self:EvaluateGate()
        if self.previewing then self:ShowPreview() end
    end)
    if self.previewing then self:ShowPreview() end
end

-- Nothing announces that a unit-frame addon has finished building its party
-- frames, and a frame already shown before the first resolve found it has no
-- show left to hook. One more resolve after each loading screen catches it,
-- timed from the latest entry.
function PB:OnWorldEntry()
    self:EvaluateGate()
    if self._worldTimer then self._worldTimer:Cancel() end
    self._worldTimer = C_Timer.NewTimer(WORLD_SETTLE, function()
        self._worldTimer = nil
        if not (self:IsEnabled() and self.active) then return end
        Debug("world settle")
        self:QueueResolve()
        -- The potion and raid cooldowns boxes bind outside the party frame
        -- resolve; their rows re-dress here once the login UI scale settles.
        self:OnRelease()
    end)
end

-- Drains whatever a refusal or a failed build left pending. Also run on every
-- activation, since a restriction can end while the tracker is off.
function PB:OnRelease()
    if not self.active then return end
    Track.Settle()
    Pot.OnRelease()
    HX.OnRelease()
    if self.buildPending then self:ResolveAll() end
    if self.reconfigurePending then self:ReconfigureAll() end
    if self.restylePending then self:Restyle() end
end

-- IsAddOnRestrictionActive answers false while this event dispatches, so the
-- test waits for the next frame.
function PB:OnRestrictionChanged()
    C_Timer.After(0, function()
        if not self:IsEnabled() then return end
        if ReadsUnhidden() then Track.ChargeRestrictionsEnded() end
        self:OnRelease()
    end)
end

-- A key's start resets the long class cooldowns and refreshes every aura;
-- reads wait it out.
function PB:OnKeyStart()
    self:EvaluateGate()
    Track.KeyStart()
    Pot.OnKeyStart()
    Track.HoldAll(KEY_HOLD)
end

-- Drops what the member's cells were built from. The placement reads ask the
-- spec each time; the icon size is built into the style, which ApplySettings
-- rebuilds.
function PB:OnSpecChanged(_, unit)
    if KE:IsSecretValue(unit) then return end
    local guid = KE:GetSafeUnitGUID(unit)
    if guid then Spec.ForgetSpec(guid) end
    if unit == "player" then self:ApplySettings() end
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
-- Fills one style pair: the aura buttons' settings and the cooldown cells'
-- style, both at size.
local function FillStyle(db, size, settings, cell)
    settings = settings or {}
    settings.IconSize         = size
    settings.IconSpacing      = db.IconSpacing
    settings.Swipe            = db.Swipe == true
    settings.Reverse          = true
    settings.ShowTimer        = db.ShowTimer == true
    settings.FontFace         = db.FontFace
    settings.FontSize         = db.FontSize
    settings.TimerFontSize    = db.TimerFontSize
    settings.FontOutline      = db.FontOutline
    settings.DecimalThreshold = db.DecimalThreshold
    settings.GlowEnabled      = db.GlowEnabled == true
    settings.GlowType         = db.GlowType
    settings.GlowColor        = db.GlowColor
    settings.GlowLines        = db.GlowLines
    settings.GlowFrequency    = db.GlowFrequency
    settings.GlowThickness    = db.GlowThickness
    settings.GlowPulse        = db.GlowPulse
    local colored = db.CategoryColors == true
    for i = 1, #DESCRIPTORS do
        local d = DESCRIPTORS[i]
        settings[d.capabilities.ringColorKey] = colored and db[d.category.colorKey] or CLEAR
    end
    settings.CellRingOffensive = colored and db.ColorBurst or CLEAR
    settings.CellRingDefensive = colored and db.ColorBigDefensive or CLEAR
    settings.CellRingTrinket   = colored and db.ColorTrinket or CLEAR
    cell = cell or { colors = {} }
    cell.size     = size
    cell.fontName = db.FontFace
    -- One size with the active timer, so the two texts match.
    cell.fontSize = db.TimerFontSize
    cell.outline  = db.FontOutline
    cell.showText = db.ShowCooldownText == true
    cell.glow     = settings
    cell.colors.offensive = colored and db.ColorBurst or BLACK
    cell.colors.defensive = colored and db.ColorBigDefensive or BLACK
    cell.colors.trinket   = colored and db.ColorTrinket or BLACK
    return settings, cell
end

-- The live pair. Only ApplySettings and the activation check build it, and
-- both reconfigure and restyle after, so its size is the one the live
-- containers were set to, or one with a retry pending.
function PB:BuildStyleSettings()
    self.styleSettings, self.cellStyle =
        FillStyle(self.db, select(5, self:Placement()), self.styleSettings, self.cellStyle)
end

-- The preview's own pair, at the size of the settings page's view.
function PB:BuildPreviewStyle()
    self.previewStyleSettings, self.previewCellStyle =
        FillStyle(self.db, select(5, self:Placement(true)),
            self.previewStyleSettings, self.previewCellStyle)
end

-- A refused touch leaves the button as it was and is retried when combat or
-- the restriction ends.
local function RestyleGroup(container, d, settings)
    local ok, count = pcall(container.GetAuraGroupFrameCount, container, d.key)
    if not ok or type(count) ~= "number" then return false end
    local clean = true
    for i = 1, count do
        local okFrame, button = pcall(container.GetAuraGroupFrame, container, d.key, i)
        if okFrame and button then
            local r = retired[button]
            if r == false then
                if not RetireButton(button) then clean = false end
            elseif r == nil then
                if not pcall(KE.AuraStyle.RegisterRegions, button, nil, d, settings) then clean = false end
                if not pcall(KE.AuraStyle.StyleAuraFrame, button, settings, d.capabilities) then clean = false end
                if not pcall(KE.AuraGlow.Apply, button, settings, d.capabilities) then clean = false end
            end
        else
            clean = false
        end
    end
    return clean
end

function PB:Restyle()
    if KE:AreAuraIdentitiesHidden() then
        self.restylePending = true
        return
    end
    local clean = true
    for k = 1, MAX_SLOTS do
        local slot = self.slots[k]
        if slot and slot.container then
            for i = 1, #DESCRIPTORS do
                local d = DESCRIPTORS[i]
                if slot.groups[d.key] and not RestyleGroup(slot.container, d, self.styleSettings) then
                    clean = false
                end
            end
        end
        if slot and slot.track and not Track.RestyleOverlay(slot.track, self.styleSettings) then
            clean = false
        end
    end
    self.restylePending = not clean
end

-- Returns false when any setter was refused.
function PB:ReconfigureSlot(slot)
    local container = slot.container
    local clean = true
    for i = 1, #DESCRIPTORS do
        local d = DESCRIPTORS[i]
        if slot.groups[d.key] then
            local filter, candidates, maxFrames, index =
                KE.PartyBuffsRules.BuildGroupConfig(d.category, self.db, slot.cellBuffs)
            clean = pcall(container.SetAuraGroupFilterString, container, d.key, filter) and clean
            clean = pcall(container.SetAuraGroupCandidateFilters, container, d.key, candidates) and clean
            clean = pcall(container.SetAuraGroupMaxFrameCount, container, d.key, maxFrames) and clean
            clean = pcall(container.SetAuraGroupLayout, container, d.key, self:GroupLayout(index)) and clean
        end
    end
    return self:ApplySlotLayout(slot) and clean
end

-- A refused setter may leave the old or the new filter, cap or layout, so the
-- whole reconfiguration is issued again when combat or the restriction ends.
function PB:ReconfigureAll()
    local clean = true
    for k = 1, MAX_SLOTS do
        local slot = self.slots[k]
        if slot and slot.container and not self:ReconfigureSlot(slot) then clean = false end
    end
    self.reconfigurePending = not clean
end

-- Retained containers are brought up to the current settings on every apply,
-- including a re-enable, which the profile manager does not follow with an
-- ApplySettings call.
function PB:ApplySettings()
    if not self:IsEnabled() then return end
    self:UpdateDB()
    self:BuildStyleSettings()
    -- Off, only the raid cooldowns box still needs specs read.
    local icons = IconsOn()
    Spec.SetTracked(icons and self.db.TrackBurst == true, icons and self.db.TrackTrinket == true,
        icons and self.db.ShowRacials == true, self.db.HealerExternals == true)
    Pot.ApplySettings()
    HX.ApplySettings()
    self:EvaluateGate()
    self:ReconfigureAll()
    self:Restyle()
    if self.previewing then self:ShowPreview() end
end

-- A color drag calls back on every mouse move; its applies run once per
-- frame at most.
local function RunQueuedApply()
    PB.applyPending = false
    PB:ApplySettings()
end

function PB:QueueApplySettings()
    if self.applyPending then return end
    self.applyPending = true
    C_Timer.After(0, RunQueuedApply)
end

function PB:SeedHealerPlacement()
    self:UpdateDB()
    KE.PartyBuffsRules.SeedHealerPlacement(self.db)
end

---------------------------------------------------------------------------------
-- Preview: plain KE frames beside each resolved party frame (an engine button
-- cannot be made to show an absent aura), or beside four stand-in party rows
-- when no party frame is on screen.
---------------------------------------------------------------------------------
local function RearmPreview(cooldown)
    if cooldown.keDuration then cooldown:SetCooldown(GetTime(), cooldown.keDuration) end
end

-- A preview frame is a plain frame, so its glow keeps looping once hidden;
-- each draw applies it again.
local GLOW_OFF, GLOW_CAPS = { GlowEnabled = false }, { hasGlow = true }
local function StopPreviewGlow(icon)
    KE.AuraGlow.Apply(icon, GLOW_OFF, GLOW_CAPS)
end

local STAND_IN_WIDTH, STAND_IN_HEIGHT = 220, 52
-- The top of a party container whose mover reads -674,-63: the mover names
-- the center of a box sized for five rows, which fill it from the top.
local STAND_IN_TOP_X, STAND_IN_TOP_Y = -674, 69
local STAND_IN_ROWS = {
    { name = "Cheeklord", token = "WARRIOR", percent = 100 },
    { name = "Cznfik",    token = "DRUID",   percent = 85 },
    { name = "Bite",      token = "EVOKER",  percent = 60 },
    { name = "Dunnirat",  token = "WARLOCK", percent = 35 },
}

-- Built once, on the first solo preview.
function PB:EnsurePreviewCells()
    if self.previewCells then return self.previewCells end
    local px = KE:GetPixelSize()
    local count = #STAND_IN_ROWS
    local block = CreateFrame("Frame", "KE_PartyBuffsPreviewBlock", UIParent)
    block:SetSize(STAND_IN_WIDTH, count * STAND_IN_HEIGHT + (count - 1) * px)
    block:SetPoint("TOP", UIParent, "CENTER", STAND_IN_TOP_X, STAND_IN_TOP_Y)
    block:SetFrameStrata("HIGH")
    block:EnableMouse(false)
    local cells = {}
    for i, sample in ipairs(STAND_IN_ROWS) do
        local cell = CreateFrame("Frame", "KE_PartyBuffsPreviewCell" .. i, block)
        cell:SetSize(STAND_IN_WIDTH, STAND_IN_HEIGHT)
        cell:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -(i - 1) * (STAND_IN_HEIGHT + px))
        cell:EnableMouse(false)
        local edge = cell:CreateTexture(nil, "BACKGROUND")
        edge:SetAllPoints(cell)
        edge:SetColorTexture(0, 0, 0, 1)
        local missing = cell:CreateTexture(nil, "BORDER")
        missing:SetPoint("TOPLEFT", cell, "TOPLEFT", px, -px)
        missing:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -px, px)
        missing:SetColorTexture(0.3, 0.3, 0.3, 1)
        local fill = cell:CreateTexture(nil, "ARTWORK")
        fill:SetPoint("TOPLEFT", missing, "TOPLEFT", 0, 0)
        fill:SetPoint("BOTTOMLEFT", missing, "BOTTOMLEFT", 0, 0)
        fill:SetWidth((STAND_IN_WIDTH - 2 * px) * sample.percent / 100)
        fill:SetColorTexture(8 / 255, 12 / 255, 16 / 255, 1)
        local name = cell:CreateFontString(nil, "OVERLAY")
        KE:ApplyFontToText(name, nil, 14, "OUTLINE")
        name:SetPoint("TOPLEFT", cell, "TOPLEFT", 4, -4)
        name:SetText(KE:ColorTextByClass(sample.name, sample.token))
        local health = cell:CreateFontString(nil, "OVERLAY")
        KE:ApplyFontToText(health, nil, 14, "OUTLINE")
        health:SetPoint("TOPRIGHT", cell, "TOPRIGHT", -4, -4)
        health:SetText(sample.percent .. "%")
        cells[i] = cell
    end
    block:Hide()
    self.previewBlock = block
    self.previewCells = cells
    return cells
end

-- A preview frame registers no engine text, so the widget's own numbers stand
-- in for it, in the timer's font and number format. A redraw keeps a running
-- sample's start, unless its duration changed or it was not showing.
function PB:RunPreviewTimer(icon, index, now)
    local settings = self.previewStyleSettings
    local duration, offset = KE.AuraRules.PreviewTiming(index)
    local cooldown = icon.keCooldown
    local keep = cooldown.keDuration == duration and icon:IsShown() and cooldown:IsShown()
    cooldown.keDuration = duration
    cooldown:SetShown(settings.Swipe or settings.ShowTimer)
    cooldown:SetDrawSwipe(settings.Swipe)
    cooldown:SetHideCountdownNumbers(not settings.ShowTimer)
    cooldown:SetCountdownFormatter(KE.AuraStyle.GetDurationFormatter(settings))
    KE:ApplyFontToText(cooldown:GetCountdownFontString(), settings.FontFace, settings.TimerFontSize,
        settings.FontOutline)
    if not keep then cooldown:SetCooldown(now - offset, duration) end
end

-- The first trinket buff the Trinkets list switches on, from the row's own.
local function SampleTrinkets(row, db)
    local listed = KE.AuraRules.BuildIncludeSpellIDs(db.ListTrinkets)
    for j = 0, #PREVIEW_BUFFS - 1 do
        local spellID = PREVIEW_BUFFS[(row + j - 1) % #PREVIEW_BUFFS + 1].trinket
        if listed[spellID] then
            return { {
                id = spellID, key = CDRules.TrinketKey(spellID), kind = "trinket", buffs = { spellID },
                cd = PREVIEW_TRINKET_CD, trinket = true, texture = C_Spell.GetSpellTexture(spellID),
            } }
        end
    end
    return {}
end

-- In the live row's order, cut to Max Cooldown Icons. A known member's spec,
-- race and trinkets when grouped; a stand-in row's samples otherwise.
function PB:PreviewEntries(k)
    local db = self.db
    local binding = self.bindings[k]
    local m = binding and Spec.Member(binding.token)
    local row = (k - 1) % #PREVIEW_SPECS + 1
    local specID = (m and m.spec) or PREVIEW_SPECS[row]
    local talents = m and m.talents
    local rules = KE.PartyBuffsRules
    local want = math_min(rules.CooldownIconCount(db), PREVIEW_CELLS)
    local spells, racials, trinkets = {}, {}, {}
    if db.TrackBurst == true then
        for _, e in ipairs(CDRules.SpellList(specID, db)) do
            local has = CDRules.CastTaken(specID, e.id, talents)
            if CDRules.TalentAllows(e, has, specID) then
                e.charges = CDRules.CellCharges(e, specID, talents)
                e.cd = CDRules.CellLength(e, specID, talents, e.charges)
                e.texture = C_Spell.GetSpellTexture(CDRules.ShowID(e, specID, has))
                spells[#spells + 1] = e
            end
        end
    end
    local race
    if m then race = m.race else race = PREVIEW_RACES[row] end
    local racial = CDRules.MemberRacial(race, db)
    if racial then
        racial.texture = C_Spell.GetSpellTexture(racial.id)
        racials[1] = racial
    end
    if db.TrackTrinket == true then
        if m then
            trinkets = m.trinkets and CDRules.TrinketEntries(m.trinkets, Spec.lengths, db) or {}
        else
            trinkets = SampleTrinkets(row, db)
        end
        for _, e in ipairs(trinkets) do
            e.texture = e.texture or (e.item and C_Item.GetItemIconByID(e.item))
        end
    end
    return rules.OrderCells({ spells = spells, racial = racials, trinket = trinkets },
        db.CooldownCategoryOrder, want)
end

-- Every cell ready but cell 3, cooling with PREVIEW_LEFT seconds to go (one
-- under the spell's length when that is shorter), started again with the same
-- time left whenever it has run out. A redraw keeps a cell's tracker while its
-- spell and length are the same, so a countdown carries on. Plain values only.
function PB:DrawPreviewCells(row, entries, layout, g, perRow)
    local n = Track.Now()
    for i = 1, PREVIEW_CELLS do
        local c, e, old = row.cells[i], entries[i], row.trackers[i]
        if old and not (e and old.previewID == e.id and old.cd == e.cd
            and (old.charges or 1) == (e.charges or 1)) then
            Track.Forget(old)
            row.trackers[i] = nil
            old = nil
        end
        if e then
            if not c then
                c = Cell.New(row.holder)
                c:EnableMouse(true)
                row.cells[i] = c
            end
            Cell.Dress(c, self.previewCellStyle, e)
            local x, y = KE.PartyBuffsRules.IconOffset(g, layout, KE.PartyBuffsRules.GridPosition(i - 1, perRow))
            c:ClearAllPoints()
            c:SetPoint(layout.corner, row.holder, layout.corner, x, y)
            if old then
                Track.Push(old, n)
            else
                local t = CDRules.NewTracker(e.cd, false, false, e.charges)
                t.cell, t.previewID = c, e.id
                if i == 3 then
                    t.loop = math_min(PREVIEW_LEFT, e.cd - 1)
                    CDRules.StartLoop(t, n)
                else
                    CDRules.Clear(t, n)
                end
                Track.Push(t, n)
                Track.Watch(t)
                row.trackers[i] = t
            end
            c:Show()
        elseif c then
            c:Hide()
        end
    end
    -- A summon with its own active phase never gets an aura button live.
    local sample = entries[2]
    if sample and sample.active then sample = nil end
    self:DrawPreviewActive(row, sample)
end

-- The active sample: a preview aura frame over cell 2 with a running timer.
function PB:DrawPreviewActive(row, e)
    local icon = row.active
    if not e then
        if icon then
            StopPreviewGlow(icon)
            icon:Hide()
        end
        return
    end
    local settings = self.previewStyleSettings
    local d = Track.OVERLAY_DESCRIPTORS[e.kind]
    if icon then
        KE.AuraStyle.StyleAuraFrame(icon, settings, d.capabilities)
        KE.AuraGlow.Apply(icon, settings, d.capabilities)
    else
        icon = CreateFrame("Frame", nil, row.holder)
        icon:EnableMouse(true)
        KE.AuraStyle.InitializePreviewFrame(icon, nil, d, settings)
        icon.keCooldown:SetScript("OnCooldownDone", RearmPreview)
        row.active = icon
    end
    local cell = row.cells[2]
    icon:SetFrameLevel(cell:GetFrameLevel() + 10)
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", cell, "CENTER", 0, 0)
    icon.keIcon:SetTexture(e.texture)
    self:RunPreviewTimer(icon, 1, GetTime())
    icon:Show()
end

function PB:DrawPreviewRow(k, frame)
    local db, settings = self.db, self.previewStyleSettings
    local row = self.previewRows[k]
    if not row then
        local rowHolder = CreateFrame("Frame", nil, UIParent)
        rowHolder:EnableMouse(false)
        row = { holder = rowHolder, icons = {}, cells = {}, trackers = {} }
        self.previewRows[k] = row
    end
    local holder = row.holder
    local entries = self:PreviewEntries(k)
    local layout, _, _, perRow = self:Placement(true)
    local g = KE.PartyBuffsRules.SlotGeometry(db, layout, #entries, perRow, settings.IconSize)
    holder:SetSize(g.width, g.height)
    if not self:PlaceHolder(holder, frame, true, settings.IconSize) then
        self:HidePreviewRow(row)
        return
    end
    self:DrawPreviewCells(row, entries, layout, g, perRow)
    -- The live row leaves a trinket drawn as a cooldown icon out of its buffs,
    -- and a row with a trinket cell shows no trinket buff sample beside it.
    local skip, trinketCell = {}, false
    for _, e in ipairs(entries) do
        if e.trinket then
            trinketCell = true
            for _, id in ipairs(e.buffs) do skip[id] = true end
        end
    end
    local tracked, pools, available = {}, {}, {}
    for i = 1, #DESCRIPTORS do
        local d = DESCRIPTORS[i]
        if db[d.category.trackKey] == true then
            local ids = KE.PartyBuffsRules.PreviewSamples(PREVIEW_BUFFS, k, d.category.key,
                db[d.category.listKey], skip)
            -- One sample per kind: repeats of a kind read as clutter, not as a cap.
            tracked[#tracked + 1], pools[#pools + 1] = d, ids
            available[#available + 1] = (trinketCell and d.category.key == "trinket") and 0 or 1
        end
    end
    local counts = KE.PartyBuffsRules.SplitBuffSamples(KE.PartyBuffsRules.IconCount(db), available)
    local now, shown = GetTime(), 0
    for i, d in ipairs(tracked) do
        for j = 1, counts[i] do
            shown = shown + 1
            local icon = row.icons[shown]
            if icon then
                KE.AuraStyle.StyleAuraFrame(icon, settings, d.capabilities)
                KE.AuraGlow.Apply(icon, settings, d.capabilities)
            else
                icon = CreateFrame("Frame", nil, holder)
                icon:EnableMouse(true)
                KE.AuraStyle.InitializePreviewFrame(icon, nil, d, settings)
                icon.keCooldown:SetScript("OnCooldownDone", RearmPreview)
                row.icons[shown] = icon
            end
            -- Where the live container would put the same icon.
            local col, line = KE.PartyBuffsRules.GridPosition(shown - 1, g.buffPerLine)
            local x, y = KE.PartyBuffsRules.IconOffset(g, layout, g.buffIndex + col, g.buffLine + line)
            icon:ClearAllPoints()
            icon:SetPoint(layout.corner, holder, layout.corner, x, y)
            local spellID = pools[i][j]
            icon.keIcon:SetTexture(spellID and C_Spell.GetSpellTexture(spellID) or PLACEHOLDER_ICON)
            self:RunPreviewTimer(icon, shown, now)
            icon:Show()
        end
    end
    for i = shown + 1, #row.icons do
        StopPreviewGlow(row.icons[i])
        row.icons[i]:Hide()
    end
    holder:Show()
end

-- The preview rows draw over the live ones, so the live rows go transparent
-- while it shows. Alpha, not Hide: their shown state gates builds and redraws.
function PB:ApplyLiveAlpha()
    local alpha = self.previewing and 0 or 1
    for _, slot in pairs(self.slots) do slot.holder:SetAlpha(alpha) end
end

-- A plain frame that stays shown under UIParent, so its scripts run when the
-- whole interface hides and shows. Made on the first preview, or on the first
-- resolve with Party Frame Icons off: then no party frame's show resolves, so
-- the watcher holds the potion rows' and the externals box's reads after the
-- interface shows, as ResolveAll does with the switch on.
local function OnInterfaceHidden()
    if not PB:IsEnabled() then return end
    if PB.active and not IconsOn() then PB.interfaceHidden = true end
    if not PB.previewing then return end
    PB:HidePreviewFrames()
    Pot.HidePreview()
    HX.HidePreview()
end

local function OnInterfaceShown()
    if not PB:IsEnabled() then return end
    if PB.active and PB.interfaceHidden and not IconsOn() then
        PB.interfaceHidden = false
        Track.InterfaceShown()
    end
    if PB.previewing then PB:ShowPreview() end
end

function PB:EnsureUIWatcher()
    if self.uiWatcher then return end
    local watcher = CreateFrame("Frame", nil, UIParent)
    watcher:SetSize(1, 1)
    watcher:EnableMouse(false)
    watcher:SetScript("OnHide", OnInterfaceHidden)
    watcher:SetScript("OnShow", OnInterfaceShown)
    self.uiWatcher = watcher
end

-- Held back while a roster change settles, like the live icons; the settle
-- timer redraws it. With the whole interface hidden nothing is drawn, so no
-- glow loops under it; the watcher redraws when it shows.
function PB:ShowPreview()
    self:EnsureUIWatcher()
    self.previewing = true
    self:ApplyLiveAlpha()
    if not UIParent:IsShown() then
        self:HidePreviewFrames()
        return
    end
    -- The potion samples sit in their own box, not beside party frames, so a
    -- roster settle does not hold them back.
    Pot.ShowPreview()
    HX.ShowPreview()
    if not IconsOn() then
        self:HidePreviewFrames()
        return
    end
    if self._rosterTimer then
        self:HidePreviewFrames()
        return
    end
    self:BuildPreviewStyle()
    local frames = {}
    -- Solo, the search can find no teammate, so it is skipped.
    local grouped = PlainTrue(IsInGroup)
    if grouped then
        local bindings = self:MatchFrames()
        for k = 1, MAX_SLOTS do frames[k] = bindings[k] and bindings[k].frame end
    end
    -- Solo only: grouped with no party frame found, rows beside stand-ins
    -- would stand for teammates the player cannot see.
    if #frames == 0 and not grouped then
        local cells = self:EnsurePreviewCells()
        for k = 1, #cells do frames[k] = cells[k] end
        self.previewBlock:Show()
        -- The screen center can fall on a half pixel. The snap needs the
        -- rect, which a shown frame has; once on the grid it changes nothing.
        KE:SnapFrameToPixels(self.previewBlock)
    elseif self.previewBlock then
        self.previewBlock:Hide()
    end
    for k = 1, MAX_SLOTS do
        if frames[k] then
            self:DrawPreviewRow(k, frames[k])
        elseif self.previewRows[k] then
            self:HidePreviewRow(self.previewRows[k])
        end
    end
end

-- Reached while the module is disabled too (the preview manager hides every
-- preview module on a section change), so nothing here reads the db.
-- The only way a preview row stops showing: its looping sample must leave the
-- ticker with it.
function PB:HidePreviewRow(row)
    for _, icon in pairs(row.icons) do
        icon.keCooldown.keDuration = nil
        icon.keCooldown:Clear()
        StopPreviewGlow(icon)
    end
    for i, c in pairs(row.cells) do
        local t = row.trackers[i]
        if t then
            Track.Forget(t)
            row.trackers[i] = nil
        end
        c:Hide()
    end
    if row.active then
        row.active.keCooldown.keDuration = nil
        row.active.keCooldown:Clear()
        StopPreviewGlow(row.active)
    end
    row.holder:Hide()
end

function PB:HidePreviewFrames()
    for k = 1, MAX_SLOTS do
        local row = self.previewRows[k]
        if row then self:HidePreviewRow(row) end
    end
    if self.previewBlock then self.previewBlock:Hide() end
end

function PB:HidePreview()
    self.previewing = false
    self:ApplyLiveAlpha()
    self:HidePreviewFrames()
    Pot.HidePreview()
    HX.HidePreview()
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
-- ApplySettings, not a bare gate check: containers kept from an earlier
-- enable carry the settings of that time.
function PB:OnEnable()
    self:UpdateDB()
    if not self.db.Enabled then return end
    for i = 1, #GATE_EVENTS do
        self:RegisterEvent(GATE_EVENTS[i], "EvaluateGate")
    end
    self:RegisterEvent("CHALLENGE_MODE_START", "OnKeyStart")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnWorldEntry")
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnRoster")
    Spec.Enable(function(m) self:OnMemberChanged(m) end)
    Track.Enable()
    Pot.Enable(self)
    HX.Enable(self)
    self:ApplySettings()
end

function PB:OnDisable()
    if self._rosterTimer then self._rosterTimer:Cancel(); self._rosterTimer = nil end
    if self._worldTimer then self._worldTimer:Cancel(); self._worldTimer = nil end
    self:Deactivate()
    self:UnregisterAllEvents()
    self:HidePreview()
    Spec.Disable()
    Track.Disable()
    Pot.Disable()
    HX.Disable()
end

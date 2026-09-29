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
local C_AddOns = C_AddOns
local C_ChallengeMode = C_ChallengeMode
local C_DelvesUI = C_DelvesUI
local C_PvP = C_PvP
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
local table_remove = table.remove

-- Times each group build and logs the facts behind each own-frame decision.
local DEBUG_PB = false

local MAX_SLOTS = 5
local ROSTER_SETTLE = 0.5
local PLACEHOLDER_ICON = 134400
local BIG_PREVIEW_ICON = 136097
local BLACK = { 0, 0, 0, 1 }

local GATE_EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "ZONE_CHANGED_NEW_AREA",
    "CHALLENGE_MODE_START",
    "CHALLENGE_MODE_COMPLETED",
    "CHALLENGE_MODE_RESET",
    "ACTIVE_DELVE_DATA_UPDATE",
}

-- point/rel place the holder on the party frame, dx/dy scale the icon gap,
-- and corner is where the container is pinned and grows away from.
local SIDES = {
    LEFT   = { point = "RIGHT",       rel = "LEFT",        dx = -1, dy = 0,  corner = "TOPRIGHT",    left = true,  up = false },
    RIGHT  = { point = "LEFT",        rel = "RIGHT",       dx = 1,  dy = 0,  corner = "TOPLEFT",     left = false, up = false },
    ABOVE  = { point = "BOTTOMLEFT",  rel = "TOPLEFT",     dx = 1,  dy = 1,  corner = "BOTTOMLEFT",  left = false, up = true },
    BELOW  = { point = "TOPLEFT",     rel = "BOTTOMLEFT",  dx = 1,  dy = -1, corner = "TOPLEFT",     left = false, up = false },
    INSIDE = { point = "BOTTOMRIGHT", rel = "BOTTOMRIGHT", dx = -1, dy = 1,  corner = "BOTTOMRIGHT", left = true,  up = true },
}

-- One per category, in on-screen order. The border host reads the colour key
-- from the group and the dressing reads it from the capabilities, so both
-- carry it.
local DESCRIPTORS = {}
for i, category in ipairs(KE.PartyBuffsRules.CATEGORIES) do
    local borderKey = "Border" .. category.colorKey:sub(6)
    DESCRIPTORS[i] = {
        key = category.key,
        category = category,
        borderColorKey = borderKey,
        capabilities = {
            hasBorder = true, hasGlow = false, hasDispelBadge = false, hasDispelRing = false,
            borderColorKey = borderKey,
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
PB.slots = {}
PB.bindings = {}
PB.queue = {}
PB.queued = {}
PB.watchedCells = {}
PB.previewRows = {}

local function Debug(fmt, ...)
    if not DEBUG_PB then return end
    local count = select("#", ...)
    local args = { ... }
    for i = 1, count do args[i] = tostring(args[i]) end
    KE:Print("[PB] " .. fmt:format(unpack(args, 1, count)))
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
    end
    self:ResolveAll()
    self:OnRelease()
end

-- Every built container is disabled, so no UNIT_AURA stays registered. The
-- frames cannot be destroyed and wait hidden until /reload. A pending roster
-- settle is left running: cancelling it would let the next gate event bind
-- before the roster has settled.
function PB:Deactivate()
    self:ClearQueue()
    for k = 1, MAX_SLOTS do
        self.bindings[k] = nil
        self:DropSlot(k)
    end
    if not self.active then return end
    self.active = false
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    self:UnregisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
end

---------------------------------------------------------------------------------
-- Frames: a unit-frame addon's buttons first, then Blizzard's raid-style party
-- frames, then its portrait party frames. Portrait frames are pooled, so every
-- scan looks them up fresh.
---------------------------------------------------------------------------------
local function PlainString(value)
    if issecretvalue(value) or type(value) ~= "string" then return nil end
    return value
end

-- The unit comparison runs only for a visible frame with a token, and its
-- result is copied only when readable.
local function AddCandidate(list, frame, family, raidIndex)
    if type(frame) ~= "table" then return end
    local candidate = { frame = frame, family = family, raidIndex = raidIndex }
    local okVisible, visible = pcall(frame.IsVisible, frame)
    candidate.visible = okVisible and not issecretvalue(visible) and visible == true
    candidate.unit = PlainString(frame.unit)
    local okAttr, attr = pcall(frame.GetAttribute, frame, "unit")
    if okAttr then candidate.attrUnit = PlainString(attr) end
    candidate.token = KE.PartyBuffsRules.CandidateToken(candidate)
    if candidate.visible and candidate.token then
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
        if DEBUG_PB then
            Debug("cand %s %s raid=%s cmp=%s/%s/%s -> %s", family, candidate.token, raidIndex,
                candidate.compareOk, candidate.compareSecret, candidate.compareResult,
                KE.PartyBuffsRules.IsPlayerCandidate(candidate) and "skip" or "track")
        end
    end
    list[#list + 1] = candidate
end

function PB:FindFrames()
    local list = {}
    local raidIndex
    local okIndex, index = pcall(UnitInRaid, "player")
    if okIndex and not issecretvalue(index) and type(index) == "number" then raidIndex = index end

    local ns = _G.EllesmereUI and _G.EllesmereUI._ModuleNS
    ns = ns and ns.EllesmereUIRaidFrames
    local buttons = ns and ns._euiUnitButtons
    if type(buttons) == "table" then
        for key, value in pairs(buttons) do
            AddCandidate(list, type(key) == "table" and key or value, "eui", raidIndex)
        end
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
    return KE.PartyBuffsRules.PickFrames(list, MAX_SLOTS)
end

---------------------------------------------------------------------------------
-- Slots and the build queue
---------------------------------------------------------------------------------
local function ContainersAvailable()
    if _G.AuraContainerSortMethod == nil and C_AddOns and C_AddOns.LoadAddOn
        and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    end
    return _G.AuraContainerSortMethod ~= nil
end

local function RowWidth(db)
    local count = KE.PartyBuffsRules.IconCount(db)
    return count * db.IconSize + (count - 1) * db.IconSpacing
end

function PB:DropSlot(k)
    local slot = self.slots[k]
    if not slot then return end
    if slot.container then pcall(slot.container.SetEnabled, slot.container, false) end
    slot.holder:Hide()
    slot.holder:ClearAllPoints()
end

function PB:SlotComplete(k)
    local slot = self.slots[k]
    if not (slot and slot.container) then return false end
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

-- The one every-frame path: at most one group build (about 3 ms) per frame.
-- A slot stays at the head of the queue until BuildSlot reports it finished,
-- so its teammate shows before the next slot starts.
local function PumpBuild()
    PB.pumping = false
    if not (PB:IsEnabled() and PB.active) then
        PB:ClearQueue()
        return
    end
    local k = PB.queue[1]
    if k and PB:BuildSlot(k) then
        table_remove(PB.queue, 1)
        PB.queued[k] = nil
    end
    if #PB.queue > 0 then
        PB.pumping = true
        C_Timer.After(0, PumpBuild)
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

-- The one place bindings are made: BindSlot and BuildSlot act only on a
-- binding set here. While a roster change settles, a token can still name a
-- frame's previous occupant, so every slot stays dropped until the settle
-- timer resolves.
function PB:ResolveAll()
    if self._rosterTimer then
        for k = 1, MAX_SLOTS do
            self.bindings[k] = nil
            self:DropSlot(k)
        end
        return
    end
    self.buildPending = false
    local bindings = self:FindFrames()
    Debug("resolve %d frame(s)", #bindings)
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

local function OnCellChanged()
    if PB:IsEnabled() and PB.active then PB:QueueResolve() end
end

-- A frame can hide or come back without a roster event (another addon swaps
-- its party header, Blizzard rebuilds its frames, the whole interface is
-- hidden and shown), so each bound frame is hooked once both ways and the
-- re-resolve waits a frame for the replacement to exist.
function PB:WatchCell(frame)
    if self.watchedCells[frame] then return end
    self.watchedCells[frame] = true
    pcall(frame.HookScript, frame, "OnHide", OnCellChanged)
    pcall(frame.HookScript, frame, "OnShow", OnCellChanged)
end

-- The layout options are replaced whole on every set, so the category's
-- position rides along each time; without it a late group falls back to
-- build order.
function PB:GroupLayout(index)
    local layout = KE.AuraContainer.GroupLayout(self.styleSettings)
    layout.layoutIndex = index
    return layout
end

function PB:AddGroup(k, slot, d)
    local filter, candidates, maxFrames, index = KE.PartyBuffsRules.BuildGroupConfig(d.category, self.db)
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
            if not pcall(KE.AuraStyle.InitializeButton, button, nil, d, PB.styleSettings) then
                Debug("slot %d group %s: button dressing failed", k, d.key)
            end
            if not pcall(button.SetMouseClickEnabled, button, false) then
                Debug("slot %d group %s: click-through failed", k, d.key)
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
    if not ok then
        local okHas, has = pcall(container.HasAuraGroup, container, d.key)
        ok = okHas and has == true
    end
    if ok then slot.groups[d.key] = true else self.buildPending = true end
end

-- Returns false when any container call was refused, so the caller can retry.
function PB:ApplySlotLayout(slot)
    local db = self.db
    local side = SIDES[db.Side] or SIDES.LEFT
    local container = slot.container
    local width = RowWidth(db)
    slot.holder:SetSize(width, db.IconSize)
    local flow = AnchorUtil.FlowDirection
    local clean = pcall(container.SetFlowLayoutGrowthDirection, container,
        side.left and flow.Left or flow.Right, side.up and flow.Up or flow.Down)
    -- The axis first: the anchor point and the line size are read against it.
    clean = pcall(container.SetFlowLayoutAxis, container, AnchorUtil.FlowLayoutAxis.Horizontal) and clean
    clean = pcall(container.SetFlowLayoutAnchorPoint, container, side.corner) and clean
    clean = pcall(container.SetFlowLayoutMaximumLineSize, container, width) and clean
    if slot.corner ~= side.corner then
        local ok = pcall(function()
            container:ClearAllPoints()
            container:SetPoint(side.corner, slot.holder, side.corner, 0, 0)
        end)
        if ok then slot.corner = side.corner else clean = false end
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
    if not ContainersAvailable() then
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
        slot = { holder = holder, groups = {} }
        self.slots[k] = slot
    end
    if not slot.container then
        local corner = (SIDES[self.db.Side] or SIDES.LEFT).corner
        local ok, container = pcall(CreateFrame, "AuraContainer", "KE_PartyBuffsContainer" .. k,
            slot.holder, "CustomAuraContainerTemplate")
        if not (ok and container) then
            Debug("slot %d: container failed", k)
            self.buildPending = true
            return true
        end
        -- Pinned before any group exists, when a pin is expected to be
        -- allowed. A refused pin records no corner, so the layout pass below
        -- pins it again.
        local pinned = pcall(container.SetPoint, container, corner, slot.holder, corner, 0, 0)
        pcall(container.EnableMouse, container, false)
        pcall(container.SetEnabled, container, false)
        slot.container = container
        slot.corner = pinned and corner or nil
    end
    for i = 1, #DESCRIPTORS do
        local d = DESCRIPTORS[i]
        if self.db[d.category.trackKey] == true and not slot.groups[d.key] then
            self:AddGroup(k, slot, d)
            if slot.groups[d.key] and not self:SlotComplete(k) then return false end
            break
        end
    end
    if not self:ApplySlotLayout(slot) then self.reconfigurePending = true end
    self:BindSlot(k, binding)
    return true
end

-- Anchored, never parented: a child of a party frame inherits its protection
-- and could not be hidden in combat. Returns the strata and level applied, or
-- nil when the anchor was refused.
function PB:PlaceHolder(holder, frame)
    local db = self.db
    local side = SIDES[db.Side] or SIDES.LEFT
    local gap = db.IconSpacing
    holder:ClearAllPoints()
    if not pcall(holder.SetPoint, holder, side.point, frame, side.rel,
        side.dx * gap + db.XOffset, side.dy * gap + db.YOffset) then
        return nil
    end
    local strata = db.Strata
    local level
    if strata == "FRAME" then
        strata = "MEDIUM"
        local okStrata, frameStrata = pcall(frame.GetFrameStrata, frame)
        if okStrata and not issecretvalue(frameStrata) and type(frameStrata) == "string" then
            strata = frameStrata
        end
        local okLevel, frameLevel = pcall(frame.GetFrameLevel, frame)
        if okLevel and not issecretvalue(frameLevel) and type(frameLevel) == "number" then
            level = frameLevel + 10
        end
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
            self.buildPending = true
            return self:DropSlot(k)
        end
        slot.unit = binding.token
    end
    local strata, level = self:PlaceHolder(slot.holder, binding.frame)
    if not strata then
        Debug("slot %d: anchor refused", k)
        self.buildPending = true
        return self:DropSlot(k)
    end
    local clean = pcall(container.SetFrameStrata, container, strata)
    if level then clean = pcall(container.SetFrameLevel, container, level + 1) and clean end
    self:WatchCell(binding.frame)
    if not pcall(container.SetEnabled, container, true) then
        Debug("slot %d: enable refused", k)
        self.buildPending = true
        return self:DropSlot(k)
    end
    slot.holder:Show()
    clean = pcall(container.UpdateAllAuras, container) and clean
    if not clean then
        Debug("slot %d: strata, level or refresh refused", k)
        self.buildPending = true
    end
    Debug("slot %d -> %s (%s)", k, binding.token, binding.family)
end

---------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------
-- Frames re-sort after a roster change and a token can name someone else, so
-- every icon and queued build drops at once and the scan waits for the roster
-- to settle. Each update restarts the full delay.
function PB:OnRoster()
    self:ClearQueue()
    for k = 1, MAX_SLOTS do
        self.bindings[k] = nil
        self:DropSlot(k)
    end
    if self._rosterTimer then self._rosterTimer:Cancel() end
    self._rosterTimer = C_Timer.NewTimer(ROSTER_SETTLE, function()
        self._rosterTimer = nil
        if not self:IsEnabled() then return end
        self:EvaluateGate()
        if self.previewing then self:ShowPreview() end
    end)
    if self.previewing then self:ShowPreview() end
end

-- Drains whatever a refusal or a failed build left pending. Also run on every
-- activation, since a restriction can end while the tracker is off.
function PB:OnRelease()
    if not self.active then return end
    if self.buildPending then self:ResolveAll() end
    if self.reconfigurePending then self:ReconfigureAll() end
    if self.restylePending then self:Restyle() end
end

function PB:OnRestrictionChanged()
    C_Timer.After(0, function()
        if self:IsEnabled() then self:OnRelease() end
    end)
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
function PB:BuildStyleSettings()
    local db = self.db
    local settings = self.styleSettings or {}
    settings.IconSize      = db.IconSize
    settings.IconSpacing   = db.IconSpacing
    settings.Swipe         = db.Swipe == true
    settings.Reverse       = true
    settings.ShowTimer     = false
    settings.FontSize      = db.FontSize
    settings.TimerFontSize = db.FontSize
    settings.FontOutline   = db.FontOutline
    local colored = db.CategoryColors == true
    for i = 1, #DESCRIPTORS do
        local d = DESCRIPTORS[i]
        settings[d.borderColorKey] = colored and db[d.category.colorKey] or BLACK
    end
    self.styleSettings = settings
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
            if not pcall(KE.AuraStyle.RegisterRegions, button, nil, d, settings) then clean = false end
            if not pcall(KE.AuraStyle.StyleAuraFrame, button, settings, d.capabilities) then clean = false end
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
            local filter, candidates, maxFrames, index = KE.PartyBuffsRules.BuildGroupConfig(d.category, self.db)
            clean = pcall(container.SetAuraGroupFilterString, container, d.key, filter) and clean
            clean = pcall(container.SetAuraGroupCandidateFilters, container, d.key, candidates) and clean
            clean = pcall(container.SetAuraGroupMaxFrameCount, container, d.key, maxFrames) and clean
            clean = pcall(container.SetAuraGroupLayout, container, d.key, self:GroupLayout(index)) and clean
        end
    end
    return self:ApplySlotLayout(slot) and clean
end

-- A refused setter leaves the old filter, cap or layout in place, so the
-- whole reconfiguration is retried when combat or the restriction ends.
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
    self:EvaluateGate()
    self:ReconfigureAll()
    self:Restyle()
    if self.previewing then self:ShowPreview() end
end

---------------------------------------------------------------------------------
-- Preview: plain KE frames beside each resolved party frame (an engine button
-- cannot be made to show an absent aura), or beside four stand-in party rows
-- when no party frame is on screen.
---------------------------------------------------------------------------------
local function RearmPreview(cooldown)
    if cooldown.keDuration then cooldown:SetCooldown(GetTime(), cooldown.keDuration) end
end

function PB:PreviewIcon(d)
    local listKey = d.category.listKey
    if not listKey then return BIG_PREVIEW_ICON end
    local spellID = KE.AuraRules.BuildSoundSpellIDs(self.db[listKey])[1]
    return spellID and C_Spell.GetSpellTexture(spellID) or PLACEHOLDER_ICON
end

local STAND_IN_WIDTH, STAND_IN_HEIGHT = 220, 52
local STAND_IN_ROWS = {
    { token = "WARRIOR", percent = 100 },
    { token = "PRIEST",  percent = 85 },
    { token = "MAGE",    percent = 60 },
    { token = "ROGUE",   percent = 35 },
}

-- Built once, on the first solo preview. Each row is a black edge, a grey
-- missing-health area and a dark health fill from the left.
function PB:EnsurePreviewCells()
    if self.previewCells then return self.previewCells end
    local px = KE:GetPixelSize()
    local count = #STAND_IN_ROWS
    local block = CreateFrame("Frame", "KE_PartyBuffsPreviewBlock", UIParent)
    block:SetSize(STAND_IN_WIDTH, count * STAND_IN_HEIGHT + (count - 1) * px)
    block:SetPoint("CENTER", UIParent, "CENTER", -674, -63)
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
        fill:SetColorTexture(0.1, 0.1, 0.1, 1)
        local names = _G.LOCALIZED_CLASS_NAMES_MALE
        local name = cell:CreateFontString(nil, "OVERLAY")
        KE:ApplyFontToText(name, nil, 12, "OUTLINE")
        name:SetPoint("TOPLEFT", cell, "TOPLEFT", 4, -4)
        name:SetText(KE:ColorTextByClass((names and names[sample.token]) or sample.token, sample.token))
        local health = cell:CreateFontString(nil, "OVERLAY")
        KE:ApplyFontToText(health, nil, 12, "OUTLINE")
        health:SetPoint("TOPRIGHT", cell, "TOPRIGHT", -4, -4)
        health:SetText(sample.percent .. "%")
        cells[i] = cell
    end
    block:Hide()
    self.previewBlock = block
    self.previewCells = cells
    return cells
end

function PB:DrawPreviewRow(k, frame)
    local db, settings = self.db, self.styleSettings
    local row = self.previewRows[k]
    if not row then
        local rowHolder = CreateFrame("Frame", nil, UIParent)
        rowHolder:EnableMouse(false)
        row = { holder = rowHolder, icons = {} }
        self.previewRows[k] = row
    end
    local holder = row.holder
    holder:SetSize(RowWidth(db), db.IconSize)
    if not self:PlaceHolder(holder, frame) then
        holder:Hide()
        return
    end
    local side = SIDES[db.Side] or SIDES.LEFT
    local step = (db.IconSize + db.IconSpacing) * (side.left and -1 or 1)
    local now, shown, limit = GetTime(), 0, KE.PartyBuffsRules.IconCount(db)
    for i = 1, #DESCRIPTORS do
        local d = DESCRIPTORS[i]
        local icon = row.icons[i]
        if db[d.category.trackKey] == true and shown < limit then
            if icon then
                KE.AuraStyle.StyleAuraFrame(icon, settings, d.capabilities)
            else
                icon = CreateFrame("Frame", nil, holder)
                KE.AuraStyle.InitializePreviewFrame(icon, nil, d, settings)
                icon.keCooldown:SetScript("OnCooldownDone", RearmPreview)
                row.icons[i] = icon
            end
            icon:ClearAllPoints()
            icon:SetPoint(side.corner, holder, side.corner, shown * step, 0)
            icon.keIcon:SetTexture(self:PreviewIcon(d))
            local duration, offset = KE.AuraRules.PreviewTiming(i)
            icon.keCooldown.keDuration = duration
            icon.keCooldown:SetShown(settings.Swipe)
            icon.keCooldown:SetCooldown(now - offset, duration)
            icon:Show()
            shown = shown + 1
        elseif icon then
            icon:Hide()
        end
    end
    holder:Show()
end

-- Held back while a roster change settles, like the live icons; the settle
-- timer redraws it.
function PB:ShowPreview()
    self.previewing = true
    if self._rosterTimer then
        self:HidePreviewFrames()
        return
    end
    self:BuildStyleSettings()
    local bindings = self:FindFrames()
    local frames = {}
    for i = 1, #bindings do frames[i] = bindings[i].frame end
    -- Solo only: grouped with no party frame found, rows beside stand-ins
    -- would stand for teammates the player cannot see.
    if #frames == 0 and not IsInGroup() then
        local cells = self:EnsurePreviewCells()
        for k = 1, #cells do frames[k] = cells[k] end
        self.previewBlock:Show()
        -- Four rows and three 1 px lines make an odd height, so the centre
        -- anchor leaves the edges on a half pixel. The snap needs the rect,
        -- which a shown frame has; once on the grid it changes nothing.
        KE:SnapFrameToPixels(self.previewBlock)
    elseif self.previewBlock then
        self.previewBlock:Hide()
    end
    for k = 1, MAX_SLOTS do
        if frames[k] then
            self:DrawPreviewRow(k, frames[k])
        elseif self.previewRows[k] then
            self.previewRows[k].holder:Hide()
        end
    end
end

-- Reached while the module is disabled too (the preview manager hides every
-- preview module on a section change), so nothing here reads the db.
function PB:HidePreviewFrames()
    for k = 1, MAX_SLOTS do
        local row = self.previewRows[k]
        if row then
            for _, icon in pairs(row.icons) do
                icon.keCooldown.keDuration = nil
                icon.keCooldown:Clear()
            end
            row.holder:Hide()
        end
    end
    if self.previewBlock then self.previewBlock:Hide() end
end

function PB:HidePreview()
    self.previewing = false
    self:HidePreviewFrames()
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
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnRoster")
    self:ApplySettings()
end

function PB:OnDisable()
    if self._rosterTimer then self._rosterTimer:Cancel(); self._rosterTimer = nil end
    self:Deactivate()
    self:UnregisterAllEvents()
    self:HidePreview()
end

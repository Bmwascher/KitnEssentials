-- ╔══════════════════════════════════════════════════════════╗
-- ║  CCTracker.lua                                           ║
-- ║  Module: CC Tracker                                      ║
-- ║  Purpose: One row per enemy nameplate held by a long     ║
-- ║           crowd control: icons, time left and name.      ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- NOTHING HERE READS AN ENEMY AURA. Each held plate gets a Blizzard aura
-- container that draws its tracked CCs itself and collapses to 1 px with none
-- up. The containers are chained, so held enemies stack and idle ones take no
-- room. The name sits in a clip window as tall as its container, so it shows
-- only while the row does. Container sizes are secret: nothing on the chain is
-- measured.
--
-- Rows carry the settings they were last allowed to take (CC.applied): while
-- auras are secret the gate holds button and container changes back, so rows
-- built meanwhile, and the clamp box around live rows, use those same ones.

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class CCTracker: AceModule, AceEvent-3.0
local CC = KitnEssentials:NewModule("CCTracker", "AceEvent-3.0")

local _G = _G
local CreateFrame = CreateFrame
local UIParent = UIParent
local C_Spell = C_Spell
local C_Timer = C_Timer
local UnitExists = UnitExists
local UnitCanAttack = UnitCanAttack
local UnitCanAssist = UnitCanAssist
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsBossMob = UnitIsBossMob
local UnitName = UnitName
local GetScreenHeight = GetScreenHeight
local issecretvalue = issecretvalue
local ipairs, pairs, pcall, tostring, type = ipairs, pairs, pcall, tostring, type
local math_floor, math_max, math_min = math.floor, math.max, math.min

local Rules = KE.CCTrackerRules
local Ask = KE.PlateSlots.Ask

-- Flip to true, /reload, repro, read the log. It never prints aura data or
-- names: no code here has them.
local DEBUG_CC = false

local GROUP_KEY = "cc"
local LAYOUT_TEMPLATE = "DisableUntrustedLayoutScriptsTemplate"
local ROW_TEMPLATE = "CustomAuraContainerTemplate," .. LAYOUT_TEMPLATE
local UNIT_EVENTS = { "UNIT_FLAGS", "UNIT_FACTION", "UNIT_NAME_UPDATE" }
local CC_GROUP = { capabilities = { hasBorder = true, hasTimerFont = true, durationRoundUp = true } }
local DEFAULT_NAME_COLOR = { 1, 1, 1, 1 }
local SAMPLES = {
    { spell = 118, time = 42, name = "Gloomfang Stalker" },
    { spell = 51514, time = 18, name = "Ashen Cultist" },
    { spell = 3355, time = 7, name = "Venerable Archivist of the Sunken Vaults" },
}

CC.anchor = nil
CC.rows = {}
CC.preview = {}
CC.slots = nil
CC.runner = nil
CC.gate = nil
CC.ids = nil
CC.applied = nil
CC.appliedIDs = nil
CC.failed = nil

local measureFS
local boxInput = {}
CC.active = false
CC.previewing = false
CC.applyQueued = false
CC.editModeRegistered = false
CC.buildTarget = 0

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function CC:UpdateDB()
    self.db = KE.db.profile.CCTracker
end

function CC:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

---------------------------------------------------------------------------------
-- Reads
---------------------------------------------------------------------------------
-- The game's spell-id filter guard counts immune and uninteractable units as
-- assistable; asked any other way, a unit it treats as friendly would pass.
local unitApi = {
    exists    = function(unit) return Ask(UnitExists, unit) end,
    canAttack = function(unit) return Ask(UnitCanAttack, "player", unit) end,
    canAssist = function(unit) return Ask(UnitCanAssist, "player", unit, true, true) end,
    isDead    = function(unit) return Ask(UnitIsDeadOrGhost, unit) end,
    isBoss    = function(unit) return Ask(UnitIsBossMob, unit) end,
}

local function Verdict(unit)
    return Rules.Verdict(unit, unitApi)
end

local function SpellTexture(id)
    return C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id) or nil
end

---------------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------------
local function GroupLayout(db)
    return {
        elementWidth = db.IconSize,
        elementHeight = db.IconSize + db.RowSpacing,
        elementSpacing = Rules.ICON_GAP,
        lineSpacing = 0,
    }
end

-- One line of icons growing away from the corner the chain hangs by, with the
-- 1 px an empty container keeps at the far end.
local function Flow(container, up, corner)
    local axis, dir = AnchorUtil.FlowLayoutAxis, AnchorUtil.FlowDirection
    container:SetFlowLayoutAxis(axis.Horizontal)
    container:SetFlowLayoutAnchorPoint(corner)
    container:SetFlowLayoutGrowthDirection(dir.Right, up and dir.Up or dir.Down)
    container:SetFlowLayoutPadding(0, 0, up and 1 or 0, up and 0 or 1)
end

-- Pulled back over that 1 px, so an idle row adds nothing to the stack. The
-- first row sits inside the box by the countdown's overflow past an icon.
local function Link(container, prev, up, box)
    container:ClearAllPoints()
    if up then
        if prev then
            container:SetPoint("BOTTOMLEFT", prev, "TOPLEFT", 0, -1)
        else
            container:SetPoint("BOTTOMLEFT", CC.anchor, "BOTTOMLEFT", box.insetX, box.insetY)
        end
    elseif prev then
        container:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, 1)
    else
        container:SetPoint("TOPLEFT", CC.anchor, "TOPLEFT", box.insetX, -box.insetY)
    end
end

-- On the icon's center line, measured from the window's near edge, which sits
-- 1 px inside the icon's. Shared with the sample rows so both cut a name alike.
local function PlaceName(name, window, size, up)
    local mid = size / 2 - 1
    name:ClearAllPoints()
    if up then
        name:SetPoint("LEFT", window, "BOTTOMLEFT", 0, mid)
    else
        name:SetPoint("LEFT", window, "TOPLEFT", 0, -mid)
    end
end

-- Off the container's far edge, so the name follows the last icon, and as tall
-- as the container less its padding: 0 px, so clipped away, with no CC up.
local function PlaceWindow(row, db, up)
    local window, container = row.window, row.container
    window:ClearAllPoints()
    if up then
        window:SetPoint("BOTTOMLEFT", container, "BOTTOMRIGHT", Rules.NAME_GAP, 1)
        window:SetPoint("TOPLEFT", container, "TOPRIGHT", Rules.NAME_GAP, 0)
    else
        window:SetPoint("TOPLEFT", container, "TOPRIGHT", Rules.NAME_GAP, -1)
        window:SetPoint("BOTTOMLEFT", container, "BOTTOMRIGHT", Rules.NAME_GAP, 0)
    end
    PlaceName(row.name, window, db.IconSize or 40, up)
end

local function StyleName(row, db)
    KE:ApplyFontToText(row.name, db.TimerFontFace, db.NameFontSize or 14, db.TimerFontOutline)
    row.name:SetTextColor(KE:ResolveColor(db.NameColor, DEFAULT_NAME_COLOR))
    row.window:SetWidth(db.NameWidth or 150)
end

-- The name may be secret in a key; SetText takes it as it is.
local function WriteName(row, unit)
    local ok, name = pcall(UnitName, unit)
    if ok then pcall(row.name.SetText, row.name, name) end
end

-- The only window in which a button may be dressed: once this returns, access
-- to it is denied while auras are secret.
-- Display only: clicks reach the world and no tooltip shows, set here too in
-- case the dressing stops before it turns motion off.
local function InitRowButton(button)
    pcall(KE.AuraStyle.InitializeButton, button, nil, CC_GROUP, CC.applied)
    pcall(button.SetMouseClickEnabled, button, false)
    pcall(button.SetMouseMotionEnabled, button, false)
end

---------------------------------------------------------------------------------
-- Geometry
---------------------------------------------------------------------------------
-- The countdown's widest text, measured on a hidden fontstring of the anchor,
-- which is ours and plain; the countdowns themselves are never asked.
local function Measured(text, size)
    measureFS:SetText(text)
    local width = measureFS:GetStringWidth()
    if not width or (issecretvalue and issecretvalue(width)) or width < 1 then return size * 2 end
    return width
end

local function TextExtent(src)
    local size = src.TimerFontSize or 20
    KE:ApplyFontToText(measureFS, src.TimerFontFace, size, src.TimerFontOutline)
    local width = Measured("59m", size)
    if KE.AuraRules.NormalizeDecimalThreshold(src.DecimalThreshold) > 0 then
        width = math_max(width, Measured("10.0", size))
    end
    return width, size
end

-- The screen's height in the anchor's units: the screen in UIParent's units,
-- scaled by the two effective scales. A scale can read secret; then, or with
-- no usable scale, the unscaled height stands. nil passes no cap.
local function ScreenHeight()
    local height = GetScreenHeight()
    if type(height) ~= "number" or height <= 0 then return nil end
    local ui, own = UIParent:GetEffectiveScale(), CC.anchor and CC.anchor:GetEffectiveScale()
    if issecretvalue and (issecretvalue(ui) or issecretvalue(own)) then return math_floor(height) end
    if type(ui) == "number" and type(own) == "number" and ui > 0 and own > 0 then
        height = height * ui / own
    end
    return math_floor(height)
end

-- Live rows are drawn from the applied settings, the sample rows from the
-- current ones; the box describes whichever is on screen.
function CC:GeometrySource()
    if self.previewing or not self.applied then return self.db end
    return self.applied
end

-- The cap, the name, the position and strata are always current: a cap change
-- builds or releases rows at once, and the name window and the anchor are ours.
function CC:Box(src)
    local db = self.db
    boxInput.MaxHeight = ScreenHeight()
    boxInput.MaxEnemies = db.MaxEnemies
    boxInput.NameEnabled = db.NameEnabled
    boxInput.NameWidth = db.NameWidth
    boxInput.NameFontSize = db.NameFontSize
    boxInput.Position = db.Position
    boxInput.IconSize = src.IconSize
    boxInput.RowSpacing = src.RowSpacing
    boxInput.GrowDirection = src.GrowDirection
    return Rules.StackBox(boxInput, TextExtent(src))
end

local function Refuse(i, container, reason)
    if container then container:Hide() end
    CC.failed = reason
    if DEBUG_CC then KE:Print("[CC] row " .. i .. " refused: " .. tostring(reason)) end
    return false
end

-- In the order the client allows: the group goes on before anything hangs off
-- the newcomer, then the newcomer is linked.
-- Built from the applied settings, so a row added while the gate holds a change
-- back matches the rows already up.
function CC:BuildSlot(i)
    if self.rows[i] or self.failed then return false end
    local db = self.applied
    local up = db.GrowDirection == "UP"
    local box = self:Box(db)
    local level = self.anchor:GetFrameLevel() + 2 * i
    local ok, container = pcall(CreateFrame, "AuraContainer", nil, self.anchor, ROW_TEMPLATE)
    if not ok or not container then return Refuse(i, nil, "container refused") end
    container:SetSize(1, 1)
    container:SetFrameLevel(level)
    local flowed, flowErr = pcall(Flow, container, up, box.corner)
    if not flowed then return Refuse(i, container, flowErr) end
    pcall(container.SetEnabled, container, false)
    local grouped, groupErr = pcall(container.AddAuraGroup, container, GROUP_KEY,
        Rules.FilterString(db.Source, db.EveryCC), {
            maxFrameCount = Rules.CC_PER_ROW,
            sortMethod = _G.AuraContainerSortMethod.ExpirationOnly,
            sortDirection = _G.AuraContainerSortDirection.Normal,
            candidateFilters = Rules.Candidates(db.EveryCC, self.appliedIDs),
            initializeFrame = InitRowButton,
            layout = GroupLayout(db),
        })
    if not grouped then return Refuse(i, container, groupErr) end
    local prev = self.rows[i - 1]
    local linked, linkErr = pcall(Link, container, prev and prev.container, up, box)
    if not linked then return Refuse(i, container, linkErr) end

    local window = CreateFrame("Frame", nil, self.anchor, LAYOUT_TEMPLATE)
    window:SetClipsChildren(true)
    window:SetFrameLevel(level + 1)
    window:Hide()
    local name = window:CreateFontString(nil, "OVERLAY")
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    local row = { container = container, window = window, name = name }
    PlaceWindow(row, db, up)
    StyleName(row, self.db)
    self.rows[i] = row
    if DEBUG_CC then KE:Print("[CC] built row " .. i) end
    return true
end

---------------------------------------------------------------------------------
-- Plates
---------------------------------------------------------------------------------
function CC:Take(slot, unit)
    local row = self.rows[slot]
    if not row then return end
    local container = row.container
    -- Unit before enable: enabling registers the unit's aura events, and the
    -- off-to-on switch makes the container read the unit afresh. A refused
    -- bind leaves the row disabled, so it draws nothing.
    if not pcall(container.SetUnit, container, unit) then
        if DEBUG_CC then KE:Print("[CC] slot " .. slot .. " bind refused (" .. unit .. ")") end
        return
    end
    pcall(container.SetEnabled, container, true)
    if self.db.NameEnabled ~= false then
        WriteName(row, unit)
        row.window:Show()
    end
    if DEBUG_CC then KE:Print("[CC] slot " .. slot .. " = " .. unit) end
end

-- Disabled, the container empties on its next frame and still rebuilds, so the
-- rows below close up. Hidden, it would keep its height until shown again.
function CC:Release(slot, unit)
    local row = self.rows[slot]
    if not row then return end
    pcall(row.container.SetEnabled, row.container, false)
    row.window:Hide()
    row.name:SetText("")
    if DEBUG_CC then
        -- nil: the unit still counts, so a cap lower, a stop or the plate going.
        local reason = unit and Verdict(unit)
        KE:Print("[CC] slot " .. slot .. " released (" .. tostring(unit) .. ", " .. tostring(reason) .. ")")
    end
end

-- A faction change can turn a held mob assistable, and the game skips the
-- spell-id filter on an assistable unit, so it is rechecked like a flag change.
function CC:OnPlateUnitEvent(slots, event, unit)
    if event == "UNIT_FLAGS" or event == "UNIT_FACTION" then
        slots:Recheck(unit)
        return
    end
    local slot = slots:SlotOf(unit)
    local row = slot and self.rows[slot]
    if row and self.db.NameEnabled ~= false then WriteName(row, unit) end
end

-- The cap follows the rows that exist, so no plate is handed a slot before its
-- container does.
function CC:UpdateCap()
    self.slots:SetCap(math_min(self.db.MaxEnemies or 15, #self.rows))
end

function CC:EnsureSlots()
    if self.slots then return end
    self.slots = KE.PlateSlots.New({
        verdict = Verdict,
        cap = 0,
        onTake = function(slot, unit) CC:Take(slot, unit) end,
        onRelease = function(slot, unit) CC:Release(slot, unit) end,
        unitEvents = UNIT_EVENTS,
        onUnitEvent = function(slots, event, unit) CC:OnPlateUnitEvent(slots, event, unit) end,
    })
    self.runner = KE.PlateSlots.NewBuildRunner({
        buildSlot = function(slot) return CC:BuildSlot(slot) end,
        onProgress = function() CC:UpdateCap() end,
    })
end

---------------------------------------------------------------------------------
-- Anchor
---------------------------------------------------------------------------------
-- Clamped and sized to the largest stack that can draw, up to the screen's
-- height: a clamp holds a frame's own rectangle, not its children's, and the
-- chain's size is secret.
function CC:CreateAnchor()
    if self.anchor then return end
    local anchor = CreateFrame("Frame", "KE_CCTrackerAnchor", UIParent)
    anchor:SetSize(1, 1)
    anchor:SetClampedToScreen(true)
    anchor:EnableMouse(false)
    anchor:Hide()
    measureFS = anchor:CreateFontString(nil, "BACKGROUND")
    measureFS:SetAlpha(0)
    self.anchor = anchor
end

function CC:ApplyAnchorPosition()
    local anchor = self.anchor
    if not anchor then return end
    local db = self.db
    local pos = db.Position or {}
    local parent = KE:ResolveAnchorFrame(db.anchorFrameType, db.ParentFrame)
    if anchor:GetParent() ~= parent then anchor:SetParent(parent) end
    local box = self:Box(self:GeometrySource())
    anchor:SetSize(box.width, box.height)
    anchor:ClearAllPoints()
    anchor:SetPoint(box.selfPoint, parent, pos.AnchorTo or "CENTER", pos.XOffset or 0, pos.YOffset or 0)
    anchor:SetFrameStrata(db.Strata or "MEDIUM")
    KE:SnapFrameToPixels(anchor)
end

---------------------------------------------------------------------------------
-- Apply
---------------------------------------------------------------------------------
local function SyncNames()
    local on = CC.db.NameEnabled ~= false
    local started = CC.slots and CC.slots:IsStarted()
    for slot, row in ipairs(CC.rows) do
        local unit = started and CC.slots:UnitOf(slot)
        if on and unit then
            WriteName(row, unit)
            row.window:Show()
        else
            row.window:Hide()
            row.name:SetText("")
        end
    end
end

-- The settings the rows take next: everything a row carries reads from this
-- copy until the next time the rows are allowed to change.
function CC:TakeApplied()
    local copy = {}
    for key, value in pairs(self.db) do copy[key] = value end
    self.applied = copy
    self.appliedIDs = self.ids
end

-- Only on the gate's yes, right after TakeApplied: aura buttons refuse these
-- writes while auras are secret, and the container changes wait with them.
function CC:RestyleRows()
    local db = self.applied
    local up = db.GrowDirection == "UP"
    local box = self:Box(db)
    local filter = Rules.FilterString(db.Source, db.EveryCC)
    local candidates = Rules.Candidates(db.EveryCC, self.appliedIDs)
    local layout = GroupLayout(db)
    for i, row in ipairs(self.rows) do
        local container = row.container
        pcall(container.SetAuraGroupFilterString, container, GROUP_KEY, filter)
        pcall(container.SetAuraGroupCandidateFilters, container, GROUP_KEY, candidates)
        pcall(container.SetAuraGroupLayout, container, GROUP_KEY, layout)
        pcall(Flow, container, up, box.corner)
        pcall(Link, container, i > 1 and self.rows[i - 1].container or nil, up, box)
        PlaceWindow(row, db, up)
        local okCount, count = pcall(container.GetAuraGroupFrameCount, container, GROUP_KEY)
        if okCount and type(count) == "number" then
            for k = 1, count do
                local okFrame, button = pcall(container.GetAuraGroupFrame, container, GROUP_KEY, k)
                if okFrame and button then
                    pcall(KE.AuraStyle.RegisterRegions, button, nil, CC_GROUP, db)
                    pcall(KE.AuraStyle.StyleAuraFrame, button, db, CC_GROUP.capabilities)
                    pcall(button.SetMouseClickEnabled, button, false)
                    pcall(button.SetMouseMotionEnabled, button, false)
                end
            end
        end
    end
end

-- The box is placed in UpdateLive, after the rows have taken whatever the gate
-- allowed, so it always describes the geometry they carry.
function CC:Apply()
    local db = self.db
    for _, row in ipairs(self.rows) do StyleName(row, db) end
    SyncNames()
    if #self.rows == 0 then
        self:TakeApplied()
    elseif self.gate:Request("general") then
        self:TakeApplied()
        self:RestyleRows()
    elseif DEBUG_CC then
        KE:Print("[CC] auras restricted: row changes wait for the drain")
    end
    self:UpdateCap()
    self:RunBuild(db.MaxEnemies or 15)
    self:UpdateLive()
end

-- The runner only raises its target, so a lower cap restarts the walk: it
-- passes the rows already built in one frame and stops at the new cap. Rows
-- above it stay, released and unused, until /reload.
function CC:RunBuild(target)
    if target < self.buildTarget then self.runner:Cancel() end
    self.buildTarget = target
    self.runner:Run(target)
end

function CC:UpdateLive()
    if not self.anchor then return end
    self:ApplyAnchorPosition()
    local live = self.active and not self.previewing
    self.anchor:SetShown(self.active)
    if self.slots then
        if live then self.slots:Start() else self.slots:Stop() end
    end
    self:ShowSamples(self.active and self.previewing)
end

---------------------------------------------------------------------------------
-- Gate and lifecycle
---------------------------------------------------------------------------------
function CC:Evaluate()
    if not self:IsEnabled() then return end
    local db = self.db
    local ids, count = Rules.ResolveIDs(KE.CC_TRACKER_SEEDS, db.Groups, db.CustomIDs)
    if count == 0 and not db.EveryCC then
        if DEBUG_CC then KE:Print("[CC] nothing tracked") end
        return self:Deactivate()
    end
    if not KE:AuraContainersAvailable(LAYOUT_TEMPLATE) then
        if DEBUG_CC then KE:Print("[CC] aura containers unavailable") end
        return self:Deactivate()
    end
    self.ids = ids
    if DEBUG_CC then KE:Print("[CC] tracking " .. count .. " ids" .. (db.EveryCC and ", every crowd control" or "")) end
    self:Activate()
end

function CC:Activate()
    self:CreateAnchor()
    self:RegWithEditMode()
    self:EnsureSlots()
    self.gate = self.gate or KE.AuraRestriction.New({})
    local starting = not self.active
    if starting then
        self.active = true
        self:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", "OnRestrictionChanged")
        self:RegisterEvent("PLAYER_REGEN_ENABLED", "DrainGate")
        self:RegisterEvent("UI_SCALE_CHANGED", "OnScreenChanged")
        self:RegisterEvent("DISPLAY_SIZE_CHANGED", "OnScreenChanged")
    end
    self:Apply()
    if starting and KE.EditMode then KE.EditMode:RefreshLiveState() end
end

-- Frames stay for reuse; nothing is left running on them.
function CC:Deactivate()
    local wasActive = self.active
    self.active = false
    if self.runner then self.runner:Cancel() end
    self.buildTarget = 0
    -- A refused build blocks every later row; the next activation retries.
    self.failed = nil
    if self.slots then self.slots:Stop() end
    if self.gate then self.gate:Cancel() end
    if wasActive then
        self:UnregisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        self:UnregisterEvent("UI_SCALE_CHANGED")
        self:UnregisterEvent("DISPLAY_SIZE_CHANGED")
    end
    if self.anchor then self.anchor:Hide() end
    self:ShowSamples(false)
    if wasActive and KE.EditMode then KE.EditMode:RefreshLiveState() end
end

local function DrainHandler()
    if DEBUG_CC then KE:Print("[CC] restriction lifted: applying what waited") end
    CC:Evaluate()
end

local DRAIN_HANDLERS = { general = DrainHandler }

function CC:DrainGate()
    if self.gate then self.gate:Drain(DRAIN_HANDLERS) end
end

local function DrainNextFrame()
    if CC:IsEnabled() then CC:DrainGate() end
end

function CC:OnRestrictionChanged()
    C_Timer.After(0, DrainNextFrame)
end

local function PlaceNextFrame()
    if CC.active then CC:ApplyAnchorPosition() end
end

-- The box is capped at the screen's height. Next frame, so the scales are
-- read after every other listener of the same event has run.
function CC:OnScreenChanged()
    C_Timer.After(0, PlaceNextFrame)
end

local function ApplyQueued()
    CC.applyQueued = false
    if not CC:IsEnabled() then return end
    CC:UpdateDB()
    CC:Evaluate()
end

-- A dragged slider asks many times a frame; one pass on the next frame answers
-- all of them.
function CC:ApplySettings()
    if not self:IsEnabled() or self.applyQueued then return end
    self.applyQueued = true
    C_Timer.After(0, ApplyQueued)
end

function CC:OnEnable()
    self:UpdateDB()
    if not self.db.Enabled then return end
    self:Evaluate()
end

function CC:OnDisable()
    self:Deactivate()
    self:UnregisterAllEvents()
    self:HidePreview()
    -- Clearing the guard is what lets a later enable register again.
    if KE.EditMode then KE.EditMode:UnregisterElement("CCTracker") end
    self.editModeRegistered = false
end

---------------------------------------------------------------------------------
-- Edit Mode and preview
---------------------------------------------------------------------------------
function CC:RegWithEditMode()
    if not KE.EditMode or self.editModeRegistered then return end
    KE.EditMode:RegisterElement({
        key = "CCTracker",
        displayName = "CC Tracker",
        frame = self.anchor,
        module = self,
        getPosition = function() return self.db.Position end,
        setPosition = function(pos)
            self.db.Position = pos
            self:ApplyAnchorPosition()
        end,
        getAnchorFrom = function() return self:Box(self:GeometrySource()).selfPoint end,
        getParentFrame = function()
            return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)
        end,
        guiPath = "KicksCasts",
        guiTab = "CCTracker",
        isEligible = function() return self.active end,
    })
    self.editModeRegistered = true
end

local function BuildSample(k)
    local frame = CreateFrame("Frame", nil, CC.anchor)
    KE.AuraStyle.InitializePreviewFrame(frame, nil, CC_GROUP, CC.db)
    local window = CreateFrame("Frame", nil, CC.anchor)
    window:SetClipsChildren(true)
    local name = window:CreateFontString(nil, "OVERLAY")
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    local sample = { frame = frame, window = window, name = name }
    CC.preview[k] = sample
    return sample
end

-- Plain frames standing in for live rows, placed by arithmetic. None is an
-- aura button, so every setting shows at once, in a key too.
function CC:PaintSamples()
    local db = self.db
    local size = db.IconSize or 40
    local step = size + (db.RowSpacing or 2)
    local up = db.GrowDirection == "UP"
    local box = self:Box(db)
    local corner = box.corner
    local edge = up and "BOTTOMRIGHT" or "TOPRIGHT"
    local shown = math_min(#SAMPLES, db.MaxEnemies or 15)
    local nameOn = db.NameEnabled ~= false
    local threshold = KE.AuraRules.NormalizeDecimalThreshold(db.DecimalThreshold)
    for k, data in ipairs(SAMPLES) do
        local sample = self.preview[k] or BuildSample(k)
        if k <= shown then
            local frame = sample.frame
            KE.AuraStyle.StyleAuraFrame(frame, db, CC_GROUP.capabilities)
            frame.keIcon:SetTexture(SpellTexture(data.spell))
            frame.keTimer:SetText(Rules.SampleTime(data.time, threshold))
            frame:ClearAllPoints()
            frame:SetPoint(corner, self.anchor, corner, box.insetX,
                (up and 1 or -1) * (box.insetY + (k - 1) * step))
            frame:Show()
            -- The live window's geometry: 1 px inside the icon's near edge,
            -- through the row spacing, so a tall name is cut the same way.
            sample.window:ClearAllPoints()
            sample.window:SetPoint(corner, frame, edge, Rules.NAME_GAP, up and 1 or -1)
            sample.window:SetHeight(step)
            StyleName(sample, db)
            PlaceName(sample.name, sample.window, size, up)
            sample.name:SetText(data.name)
            sample.window:SetShown(nameOn)
        else
            sample.frame:Hide()
            sample.window:Hide()
        end
    end
end

function CC:ShowSamples(show)
    if show then
        self:PaintSamples()
        return
    end
    for _, sample in ipairs(self.preview) do
        sample.frame:Hide()
        sample.window:Hide()
    end
end

-- Set even while inactive: the manager does not ask again while the page stays
-- open, so a spell ticked there has to find the preview already on.
function CC:ShowPreview()
    if not self:IsEnabled() then return end
    self.previewing = true
    self:UpdateLive()
end

function CC:HidePreview()
    if not self.previewing then return end
    self.previewing = false
    self:UpdateLive()
end

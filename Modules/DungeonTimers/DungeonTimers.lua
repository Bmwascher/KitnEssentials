-- ╔══════════════════════════════════════════════════════════╗
-- ║  DungeonTimers.lua                                       ║
-- ║  Module: Dungeon Timers (curated)                        ║
-- ║  Purpose: Layers curated castDuration data on top of     ║
-- ║           BigWigs's BigWigs_Timer events. Encounter data ║
-- ║           lives in EncounterData.lua (EXBoss-style hand- ║
-- ║           curated table keyed by encounterID/spellID).   ║
-- ║                                                          ║
-- ║  Created 2026-05-04 alongside the rename of the old      ║
-- ║  DungeonTimers module to "BigWigsTimers". The two coexist║
-- ║  during the rebuild — this module is off-by-default.     ║
-- ║                                                          ║
-- ║  N10 added the GUI integration: bar/text settings now    ║
-- ║  flow through KE.db.profile.Dungeons.DungeonTimers.      ║
-- ║  ApplySettings re-applies visuals to live bars in place. ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class DungeonTimers: AceModule, AceEvent-3.0, AceTimer-3.0
local DT = KitnEssentials:NewModule("DungeonTimers", "AceEvent-3.0", "AceTimer-3.0")

KE.EncounterData = KE.EncounterData or {}

local ipairs = ipairs
local pairs = pairs
local tostring = tostring
local tonumber = tonumber
local string_format = string.format
local table_insert = table.insert
local table_sort = table.sort
local CreateFrame = CreateFrame
local GetTime = GetTime
local UIParent = UIParent

local DEBUG_DT2 = true

local BIGWIGS_EVENTS = {
    "BigWigs_Timer",
    "BigWigs_StopBar",
    "BigWigs_StopBars",
    "BigWigs_OnBossDisable",
}

-- Fallback hardcoded sizes used only when DB hasn't been resolved yet (very
-- early init). Live values come from db.BarDisplay / db.TextDisplay.
local FALLBACK_BAR_WIDTH = 250
local FALLBACK_BAR_HEIGHT = 22
local FALLBACK_TEXT_HEIGHT = 22

local STOP_TOLERANCE = 0.5  -- seconds: StopBar within this window of the cast-phase boundary is treated as natural countdown expiry

DT.bars = {}
DT.barGroup = nil
DT.textGroup = nil
DT.spellLookup = nil

local function dprint(msg)
    if DEBUG_DT2 then
        KE:Print("[DT2] " .. tostring(msg))
    end
end

-- BigWigs appends " (N)" to repeating-cast bar text for uniqueness. We need
-- the suffix in our key (so (1) and (2) don't collide in DT.bars) but the
-- user doesn't want to see iteration counters. Display the stripped version.
local function StripBigWigsCounter(text)
    if not text then return text end
    return (text:gsub(" %(%d+%)$", ""))
end

function DT:BuildSpellLookup()
    local lookup = {}
    for _, enc in pairs(KE.EncounterData or {}) do
        if enc.spells then
            for spellId, spellData in pairs(enc.spells) do
                lookup[spellId] = spellData
            end
        end
    end
    self.spellLookup = lookup
    return lookup
end

function DT:GetSpellInfo(spellId)
    if not spellId then return nil end
    local lookup = self.spellLookup or self:BuildSpellLookup()
    return lookup[spellId]
end

function DT:GetSpellExtension(spellId)
    local data = self:GetSpellInfo(spellId)
    if not data then return 0 end
    return (data.castDuration or 0) + (data.channelDuration or 0)
end

function DT:GetSpellDisplay(spellId)
    local data = self:GetSpellInfo(spellId)
    return (data and data.display) or "text"
end

-- One-time migration: early DungeonTimers schema nested AnchorFrom/To/XOffset/
-- YOffset under `BarGroup.Position` / `TextGroup.Position`. The flat shape (all
-- position keys at the group level) is required for PositionCard's full anchor
-- system (showAnchorFrameType + showStrata) since dbKeys can't traverse into a
-- sub-table. This migration runs once per profile per group and is a no-op
-- after the keys have been flattened.
local function MigratePositionToFlat(group)
    if not group or type(group.Position) ~= "table" then return end
    local pos = group.Position
    if pos.AnchorFrom and not group.AnchorFrom then group.AnchorFrom = pos.AnchorFrom end
    if pos.AnchorTo and not group.AnchorTo then group.AnchorTo = pos.AnchorTo end
    if pos.XOffset ~= nil and group.XOffset == nil then group.XOffset = pos.XOffset end
    if pos.YOffset ~= nil and group.YOffset == nil then group.YOffset = pos.YOffset end
    group.Position = nil
end

function DT:UpdateDB()
    if not (KE.db and KE.db.profile) then return end
    -- AceDB defaults don't deep-fill nested sub-tables that already exist in
    -- saved data (e.g. `Dungeons` is non-empty from BigWigsTimers, so the new
    -- `Dungeons.DungeonTimers` key isn't auto-populated). Trigger a backfill
    -- on first sight so positions/Enabled flags resolve correctly.
    if not (KE.db.profile.Dungeons and KE.db.profile.Dungeons.DungeonTimers) then
        if KE.FillProfileDefaults then
            KE:FillProfileDefaults()
        end
    end
    self.db = KE.db.profile.Dungeons and KE.db.profile.Dungeons.DungeonTimers
    if self.db then
        MigratePositionToFlat(self.db.BarGroup)
        MigratePositionToFlat(self.db.TextGroup)
    end
end

function DT:GetGroupSettings(groupType)
    self:UpdateDB()
    if not self.db then return nil end
    return groupType == "bar" and self.db.BarGroup or self.db.TextGroup
end

---------------------------------------------------------------------------------
-- DB-driven settings resolvers (with fallbacks for early-init paths)
---------------------------------------------------------------------------------

local function GetBarDisplay()
    if DT.db and DT.db.BarDisplay then return DT.db.BarDisplay end
    return nil
end

local function GetTextDisplay()
    if DT.db and DT.db.TextDisplay then return DT.db.TextDisplay end
    return nil
end

local function GetBarHeight()
    local d = GetBarDisplay()
    return (d and d.barHeight) or FALLBACK_BAR_HEIGHT
end

local function GetTextHeight()
    local d = GetTextDisplay()
    -- Text rows scale with font size — use 1.6× the configured font size as
    -- the row height baseline so larger fonts don't clip and small ones don't
    -- waste vertical space. Floor of FALLBACK_TEXT_HEIGHT keeps the rows
    -- readable at very small font sizes.
    local fontSize = (d and d.fontSize) or 14
    local h = math.floor(fontSize * 1.6 + 0.5)
    if h < FALLBACK_TEXT_HEIGHT then h = FALLBACK_TEXT_HEIGHT end
    return h
end

local function ResolveFontPath(face)
    if KE.LSM and face then
        local path = KE.LSM:Fetch("font", face)
        if path then return path end
    end
    return KE.FONT or "Fonts\\FRIZQT__.TTF"
end

local function ResolveTexture(name)
    if KE.LSM and name then
        local path = KE.LSM:Fetch("statusbar", name)
        if path then return path end
    end
    return "Interface\\Buttons\\WHITE8x8"
end

-- Groups are 1px-tall point anchors. Bars stack outward from the group's
-- TOPLEFT (DOWN growth) or BOTTOMLEFT (UP growth) corner, so the user-set
-- group position = the start of the bar stack regardless of bar height.
-- Sizing the group as `barWidth × (barHeight × 12)` was the original setup,
-- but that means changing bar height changes the group's center, which —
-- with the default CENTER↔CENTER anchor — shifts the entire stack on screen
-- whenever font/height sliders change.
function DT:EnsureBarGroup()
    if self.barGroup then return self.barGroup end
    local f = CreateFrame("Frame", "KE_DungeonTimers_BarGroup", UIParent)
    f:SetSize(1, 1)
    self.barGroup = f
    self:UpdateBarGroupPosition()
    return f
end

function DT:EnsureTextGroup()
    if self.textGroup then return self.textGroup end
    local f = CreateFrame("Frame", "KE_DungeonTimers_TextGroup", UIParent)
    f:SetSize(1, 1)
    self.textGroup = f
    self:UpdateTextGroupPosition()
    return f
end

function DT:UpdateBarGroupPosition()
    if not self.barGroup then return end
    local settings = self:GetGroupSettings("bar")
    if not settings then return end
    -- Flat schema: settings holds both posConfig (AnchorFrom/To/XOffset/YOffset)
    -- and Config (Strata/anchorFrameType/ParentFrame) at the same level.
    KE:ApplyFramePosition(self.barGroup, settings, settings)
end

function DT:UpdateTextGroupPosition()
    if not self.textGroup then return end
    local settings = self:GetGroupSettings("text")
    if not settings then return end
    KE:ApplyFramePosition(self.textGroup, settings, settings)
end

function DT:UpdateGroupPositions()
    self:UpdateBarGroupPosition()
    self:UpdateTextGroupPosition()
end

-- Pixel-aware SetValue gating. Skip the call when the visual delta is below
-- one pixel of bar width — saves ~6× WoW C-side calls vs raw per-frame
-- SetValue. Pattern matches DT (bigwigs) OnVisualUpdate / KT cooling-bar
-- (perf playbook entry #1). For text-mode bars there's no fill texture so
-- SetValue is a visual no-op anyway; we skip the call entirely there.
-- `frame` is the outer Frame, `frame.bar` is the inner StatusBar.
local function GatedSetValue(frame, value)
    if frame.displayMode ~= "bar" or not frame.bar then return end
    local sb = frame.bar
    local minV, maxV = sb:GetMinMaxValues()
    local span = maxV - minV
    if span <= 0 then return end
    local widthPx = frame._cachedBarWidth or sb:GetWidth()
    if widthPx <= 0 then
        sb:SetValue(value)
        frame._lastValue = value
        return
    end
    local valuePerPixel = span / widthPx
    local lastV = frame._lastValue
    if not lastV or math.abs(value - lastV) >= valuePerPixel then
        sb:SetValue(value)
        frame._lastValue = value
    end
end

-- Last-string SetText gating. Skips bar.timerText:SetText when the formatted
-- string equals the prior tick's string. Safe here because preview/real
-- BigWigs durations are plain numbers (BigWigs computes them, not the secret-
-- value Unit*CastingDuration API). See feedback_dirty_check_secret_durations
-- for why this gating is unsafe on Castbar/DungeonCasts.
local function GatedSetText(textObj, holderBar, slot, str)
    if holderBar[slot] ~= str then
        textObj:SetText(str)
        holderBar[slot] = str
    end
end

-- Updates the visible time string. Bar mode writes to the right-justified
-- timerText FontString; text mode rewrites label as "name » timer" (one
-- FontString avoids the same-alignment overlap of two).
local function UpdateTimeString(self, displayedTime)
    local timerStr = string_format("%.1f", displayedTime)
    if self.timerText then
        GatedSetText(self.timerText, self, "_lastTimerStr", timerStr)
    elseif self.label and self.baseText then
        GatedSetText(self.label, self, "_lastTimerStr",
            self.baseText .. " \194\187 " .. timerStr)
    end
end

local function BarOnUpdate(self)
    if self.phase == "cast" then
        local castElapsed = GetTime() - self.castStartTime
        if castElapsed >= self.castDuration then
            -- Loop bars (preview) reset to countdown phase with original colors
            -- instead of self-destructing.
            if self.loop then
                self.phase = "countdown"
                self.startTime = GetTime()
                if self.displayMode == "bar" and self.bar then
                    self.bar:SetStatusBarColor(0.3, 0.5, 0.9)
                end
                if self.timerText then self.timerText:SetTextColor(1, 1, 1) end
                if self.label then self.label:SetTextColor(1, 1, 1) end
                self._lastValue = nil
                self._lastTimerStr = nil
                return
            end
            self:SetScript("OnUpdate", nil)
            self:Hide()
            DT.bars[self.text] = nil
            DT:LayoutBars()
            return
        end
        local visual = self.castFromValue * (1 - castElapsed / self.castDuration)
        GatedSetValue(self, visual)
        UpdateTimeString(self, self.castDuration - castElapsed)
    else
        local remaining = self.totalDuration - (GetTime() - self.startTime)
        if remaining <= 0 then
            -- Loop bars (preview): reset to full duration and continue.
            if self.loop then
                self.startTime = GetTime()
                remaining = self.totalDuration
                self._lastValue = nil
                self._lastTimerStr = nil
            -- No curated extension means no StopBar→cast transition is expected
            -- (e.g. BigWigs Wipe-module Respawn timer with spellId=nil). Auto-hide.
            -- Bars with extension > 0 keep their value clamped at 0 and wait for
            -- StopBar so the cast-phase transition can capture the right moment.
            elseif (self.extension or 0) <= 0 then
                self:SetScript("OnUpdate", nil)
                self:Hide()
                DT.bars[self.text] = nil
                DT:LayoutBars()
                return
            else
                remaining = 0
            end
        end
        GatedSetValue(self, remaining)
        UpdateTimeString(self, remaining)
    end
end

---------------------------------------------------------------------------------
-- Visual application — used both by CreateBar (initial) and ApplySettings
-- (reapply to live bars in-place). Kept as a free function so the logic isn't
-- duplicated. Only sets visual properties; doesn't touch state/timing.
--
-- Frame layout (bar mode):
--   frame (Frame, BackdropTemplate)              outer container, 1px border
--     ├─ iconFrame (Frame, BackdropTemplate)     square on left, 1px border
--     │     └─ icon (Texture, ARTWORK)           cropped via KE:ApplyIconZoom
--     └─ barContainer (Frame, BackdropTemplate)  fills right of icon, 1px border
--           └─ bar (StatusBar)                   fill texture
--                 ├─ label (FontString)          left text
--                 └─ timerText (FontString)      right text
-- Frame layout (text mode):
--   frame (Frame)
--     └─ bar (StatusBar, no texture)             container only
--           ├─ label (FontString)
--           └─ timerText (FontString)
---------------------------------------------------------------------------------
local function ApplyVisualsToBar(frame)
    local isBar = (frame.displayMode == "bar")
    local barDisplay = GetBarDisplay()
    local textDisplay = GetTextDisplay()

    local w, h
    if isBar then
        w = (barDisplay and barDisplay.barWidth) or FALLBACK_BAR_WIDTH
        h = (barDisplay and barDisplay.barHeight) or FALLBACK_BAR_HEIGHT
    else
        w = (barDisplay and barDisplay.barWidth) or FALLBACK_BAR_WIDTH
        h = GetTextHeight()
    end
    frame:SetSize(w, h)

    if isBar then
        -- Icon visibility + sizing. iconEnabled toggles whether the bar
        -- starts after a square icon area or fills the full width. Width
        -- of barContainer drives the StatusBar fill width, which is what
        -- GatedSetValue measures.
        local iconEnabled = (barDisplay and barDisplay.iconEnabled ~= false)
        local iconSize = iconEnabled and h or 0

        if frame.iconFrame then
            if iconEnabled then
                frame.iconFrame:Show()
                frame.iconFrame:SetSize(iconSize, iconSize)
            else
                frame.iconFrame:Hide()
            end
        end

        if frame.barContainer then
            frame.barContainer:ClearAllPoints()
            frame.barContainer:SetPoint("TOPLEFT", frame, "TOPLEFT", iconSize, 0)
            frame.barContainer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        end

        if frame.bar and barDisplay then
            frame.bar:SetStatusBarTexture(ResolveTexture(barDisplay.barTexture))
            if frame.phase ~= "cast" then
                frame.bar:SetStatusBarColor(0.3, 0.5, 0.9)
            end
        end

        -- Cache the actual fill width (frame minus icon minus 2px border) for
        -- pixel-aware SetValue gating. Direct math beats per-frame :GetWidth()
        -- and stays accurate across width/iconEnabled changes.
        frame._cachedBarWidth = (w - iconSize) - 2
    else
        frame._cachedBarWidth = w
    end

    -- Settings change always invalidates the gating caches so the next tick
    -- re-applies fonts/widths/strings unconditionally.
    frame._lastValue = nil
    frame._lastTimerStr = nil

    -- Font on label + timerText
    local face, size, outline
    if isBar then
        face = (barDisplay and barDisplay.fontFace) or "Expressway"
        size = (barDisplay and barDisplay.fontSize) or 12
        outline = (barDisplay and barDisplay.fontOutline) or "OUTLINE"
    else
        face = (textDisplay and textDisplay.fontFace) or "Expressway"
        size = (textDisplay and textDisplay.fontSize) or 14
        outline = (textDisplay and textDisplay.fontOutline) or "SOFTOUTLINE"
    end
    if frame.label and KE.ApplyFontToText then
        KE:ApplyFontToText(frame.label, face, size, outline)
    elseif frame.label then
        frame.label:SetFont(ResolveFontPath(face), size, KE.GetFontOutline and KE:GetFontOutline(outline) or outline)
    end
    if frame.timerText and KE.ApplyFontToText then
        KE:ApplyFontToText(frame.timerText, face, size, outline)
    elseif frame.timerText then
        frame.timerText:SetFont(ResolveFontPath(face), size, KE.GetFontOutline and KE:GetFontOutline(outline) or outline)
    end

    -- Text anchoring within the bar.
    -- Bars: separate label (LEFT-justified) and timer (RIGHT-justified)
    -- FontStrings, both with 4px padding so the bar's empty middle visually
    -- separates them.
    -- Texts: a SINGLE label FontString rendering "name » 4.5" (composed each
    -- tick by BarOnUpdate). Two FontStrings with the same alignment overlap;
    -- one FontString with the user's chosen alignment doesn't.
    if frame.label and frame.bar then
        frame.label:ClearAllPoints()
        if isBar then
            frame.label:SetPoint("LEFT", frame.bar, "LEFT", 4, 0)
            frame.label:SetPoint("RIGHT", frame.bar, "RIGHT", -4, 0)
            frame.label:SetJustifyH("LEFT")
            if frame.timerText then
                frame.timerText:ClearAllPoints()
                frame.timerText:SetPoint("LEFT", frame.bar, "LEFT", 4, 0)
                frame.timerText:SetPoint("RIGHT", frame.bar, "RIGHT", -4, 0)
                frame.timerText:SetJustifyH("RIGHT")
            end
        else
            local align = (textDisplay and textDisplay.textAlign) or "CENTER"
            frame.label:SetPoint("LEFT", frame.bar, "LEFT", 0, 0)
            frame.label:SetPoint("RIGHT", frame.bar, "RIGHT", 0, 0)
            frame.label:SetJustifyH(align)
        end
    end
end

function DT:CreateBar(text, baseDuration, extension, displayMode)
    displayMode = displayMode or "text"
    local isBar = (displayMode == "bar")
    local group = isBar and self:EnsureBarGroup() or self:EnsureTextGroup()

    -- Outer container. BackdropTemplate so we get the 1px black border that
    -- gives the bar a polished, framed look (matches BigWigsTimers).
    local frame = CreateFrame("Frame", nil, group, "BackdropTemplate")
    frame.displayMode = displayMode

    if isBar then
        frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        frame:SetBackdropColor(0, 0, 0, 0.8)
        frame:SetBackdropBorderColor(0, 0, 0, 1)

        -- Icon container. Square, anchored LEFT. Size set in ApplyVisualsToBar.
        frame.iconFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        frame.iconFrame:SetPoint("LEFT", frame, "LEFT", 0, 0)
        frame.iconFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        frame.iconFrame:SetBackdropColor(0, 0, 0, 0.8)
        if KE.AddIconBorders then
            KE:AddIconBorders(frame.iconFrame)
        end

        frame.icon = frame.iconFrame:CreateTexture(nil, "ARTWORK")
        frame.icon:SetPoint("TOPLEFT", 1, -1)
        frame.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        if KE.ApplyIconZoom then KE:ApplyIconZoom(frame.icon) end
        -- Default placeholder until the caller assigns a real iconID.
        frame.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

        -- Bar container holds the StatusBar inset by 1px so the outer border
        -- shows. ApplyVisualsToBar repositions barContainer based on icon state.
        frame.barContainer = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        frame.barContainer:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        frame.barContainer:SetBackdropColor(0, 0, 0, 0.8)

        frame.bar = CreateFrame("StatusBar", nil, frame.barContainer)
        frame.bar:SetPoint("TOPLEFT", 1, -1)
        frame.bar:SetPoint("BOTTOMRIGHT", -1, 1)
    else
        -- Text mode: no border, no icon, no fill. Bar is a transparent
        -- container so the FontStrings have something to anchor to.
        frame.bar = CreateFrame("StatusBar", nil, frame)
        frame.bar:SetAllPoints()
    end

    local total = baseDuration + (extension or 0)
    frame.bar:SetMinMaxValues(0, total)
    frame.bar:SetValue(total)

    frame.startTime = GetTime()
    frame.duration = baseDuration
    frame.extension = extension or 0
    frame.totalDuration = total
    frame.phase = "countdown"
    frame.text = text

    -- FontStrings parented to the StatusBar so they overlay the fill texture
    -- (same as BigWigsTimers).
    -- Bar mode: separate `label` (LEFT) and `timerText` (RIGHT). Bar middle
    --           gives them spatial separation, no separator needed.
    -- Text mode: ONE combined `label` rendering "name » 4.5". Updated each
    --            tick by BarOnUpdate. Two FontStrings with the same align
    --            overlap; combining them avoids that without using
    --            GetStringWidth (which has secret-value taint risk per
    --            reference_secret_value_behaviors).
    frame.label = frame.bar:CreateFontString(nil, "OVERLAY")
    if isBar then
        frame.timerText = frame.bar:CreateFontString(nil, "OVERLAY")
    end

    -- All sizing/font/anchoring derived from DB. Must run BEFORE the first
    -- SetText call below — WoW errors `FontString:SetText(): Font not set`
    -- if the FontString has no font assigned yet.
    ApplyVisualsToBar(frame)
    frame.baseText = StripBigWigsCounter(text)
    if isBar then
        frame.label:SetText(frame.baseText)
    else
        -- Initial combined string; first OnUpdate tick refreshes the timer
        -- portion. Without an initial SetText the first frame would render
        -- empty; with this it renders the same combined shape it'll have
        -- one frame later.
        frame.label:SetText(frame.baseText .. " \194\187 " .. string_format("%.1f", total))
    end

    frame:SetScript("OnUpdate", BarOnUpdate)
    return frame
end

function DT:LayoutBars()
    local barGroup = self:EnsureBarGroup()
    local textGroup = self:EnsureTextGroup()
    self:UpdateDB()

    local barCfg = self.db and self.db.BarGroup or nil
    local textCfg = self.db and self.db.TextGroup or nil
    local barSpacing = (barCfg and barCfg.Spacing) or 2
    local textSpacing = (textCfg and textCfg.Spacing) or 0
    local barGrowth = (barCfg and barCfg.GrowthDirection) or "DOWN"
    local textGrowth = (textCfg and textCfg.GrowthDirection) or "DOWN"

    -- Anchor bars to the user's chosen AnchorFrom corner (matches
    -- BigWigsTimers PositionAllBars). This keeps the stack aligned to the
    -- corner the user picked: TOPRIGHT→TOPRIGHT keeps bars right-aligned
    -- to the group anchor point, CENTER→CENTER centers each row, etc.
    -- Hardcoding TOPLEFT here would make non-LEFT anchor configs hang off
    -- the wrong side of the user's chosen position.
    local barAnchorFrom = (barCfg and barCfg.AnchorFrom) or "CENTER"
    local textAnchorFrom = (textCfg and textCfg.AnchorFrom) or "CENTER"

    local barH = GetBarHeight()
    local textH = GetTextHeight()
    local barStride = barH + barSpacing
    local textStride = textH + textSpacing

    -- Collect into an ordered array so layout is deterministic. pairs() over
    -- the bars table iterates in hash order, which made the preview rows
    -- shuffle (e.g. C/A/B instead of A/B/C across reloads). sortIndex is
    -- assigned at creation time: previews get 1/2/3 explicitly; real bars
    -- get a monotonically increasing counter so they layout in the order
    -- BigWigs fires their timer events.
    local ordered = {}
    for _, bar in pairs(self.bars) do
        if bar:IsShown() then
            table_insert(ordered, bar)
        end
    end
    table_sort(ordered, function(a, b)
        return (a.sortIndex or 0) < (b.sortIndex or 0)
    end)

    local barY, textY = 0, 0
    for _, bar in ipairs(ordered) do
        bar:ClearAllPoints()
        if bar.displayMode == "bar" then
            local offset = (barGrowth == "UP") and barY or -barY
            bar:SetPoint(barAnchorFrom, barGroup, barAnchorFrom, 0, offset)
            barY = barY + barStride
        else
            local offset = (textGrowth == "UP") and textY or -textY
            bar:SetPoint(textAnchorFrom, textGroup, textAnchorFrom, 0, offset)
            textY = textY + textStride
        end
    end
end

---------------------------------------------------------------------------------
-- ApplySettings: reapply DB-driven visuals to all live bars + group positions.
-- Called from GUI panels after the user changes a setting (font, width,
-- spacing, etc.). Aliased as UpdateFrameVisuals to mirror the BigWigsTimers
-- API surface — GUI files can call either name.
---------------------------------------------------------------------------------
function DT:ApplySettings()
    self:UpdateDB()
    self:UpdateGroupPositions()
    -- Groups stay 1×1 point anchors regardless of bar width changes; bar
    -- width is applied per-frame in ApplyVisualsToBar (see EnsureBarGroup).
    for _, bar in pairs(self.bars) do
        ApplyVisualsToBar(bar)
    end
    self:LayoutBars()
end

function DT:UpdateFrameVisuals()
    self:ApplySettings()
end

-- Monotonic counter for real-bar sort ordering. Previews use 1/2/3
-- explicitly; real bars get a high counter so they always lay out AFTER
-- previews and in BigWigs-event order. Bumped each RenderBar call.
DT._barSortCounter = 1000

function DT:RenderBar(text, baseDur, extension, displayMode)
    if not text or not baseDur or baseDur <= 0 then return end
    local existing = self.bars[text]
    if existing then
        existing:SetScript("OnUpdate", nil)
        existing:Hide()
    end
    local bar = self:CreateBar(text, baseDur, extension, displayMode)
    self._barSortCounter = self._barSortCounter + 1
    bar.sortIndex = self._barSortCounter
    self.bars[text] = bar
    self:LayoutBars()
end

local function KillBar(self, text)
    local bar = self.bars[text]
    if not bar then return end
    bar:SetScript("OnUpdate", nil)
    bar:Hide()
    self.bars[text] = nil
    self:LayoutBars()
end

function DT:StopBar(text)
    if not text then return end
    local bar = self.bars[text]
    if not bar then return end

    -- Cast-phase StopBar = mid-cast interrupt. Kill.
    if bar.phase == "cast" then
        dprint("StopBar (cast interrupt): " .. tostring(text))
        KillBar(self, text)
        return
    end

    -- Countdown-phase StopBar:
    --   elapsed >= base - tolerance  → BigWigs's countdown finished naturally
    --                                  (auto-stop at zero OR real-cast-start
    --                                  fired StopBar). Transition the SAME bar
    --                                  in-place to cast phase: capture current
    --                                  visual value and drain to 0 over the
    --                                  curated castDuration. Cluster A: rate
    --                                  unchanged. Cluster B: rate slows so
    --                                  bar reaches 0 at real impact moment.
    --   elapsed <  base - tolerance  → mid-countdown interrupt, kill.
    local elapsed = GetTime() - bar.startTime
    local extension = bar.extension or 0

    if elapsed >= bar.duration - STOP_TOLERANCE and extension > 0 then
        local currentValue = bar.totalDuration - elapsed
        if currentValue <= 0 then
            -- StopBar arrived after the bar already drained past total — stale, kill.
            dprint(string_format("StopBar %s → killed (stale, elapsed=%.2f total=%.2f)",
                text, elapsed, bar.totalDuration))
            KillBar(self, text)
            return
        end
        bar.phase = "cast"
        bar.castStartTime = GetTime()
        bar.castFromValue = currentValue
        bar.castDuration = extension
        if bar.displayMode == "bar" and bar.bar then
            bar.bar:SetStatusBarColor(0.9, 0.45, 0.3)
        end
        -- Tint whichever FontString actually shows the timer.
        if bar.timerText then
            bar.timerText:SetTextColor(0.95, 0.55, 0.35)
        elseif bar.label then
            bar.label:SetTextColor(0.95, 0.55, 0.35)
        end
        dprint(string_format("StopBar %s → cast phase (fromValue=%.2f late=%.2fs)",
            text, currentValue, elapsed - bar.duration))
    else
        dprint(string_format("StopBar %s → killed (elapsed=%.2f base=%.2f ext=%.2f)",
            text, elapsed, bar.duration, extension))
        KillBar(self, text)
    end
end

function DT:StopAllBars()
    for text, bar in pairs(self.bars) do
        -- Spare preview bars — they're owned by GUI panel lifecycle, not the
        -- BigWigs encounter lifecycle. Real-boss StopBars/disable shouldn't
        -- nuke them mid-edit.
        if not bar.isPreview then
            bar:SetScript("OnUpdate", nil)
            bar:Hide()
            self.bars[text] = nil
        end
    end
    self:LayoutBars()
end

---------------------------------------------------------------------------------
-- Settings preview bars/texts (GUI panel feedback)
-- Looping fake bars rendered into BarGroup / TextGroup so the user sees
-- live position / font / spacing feedback while editing the GUI panels.
-- Idempotent guards: Show is a no-op if previews already showing for that
-- mode; Hide is a no-op if not showing. ApplySettings (called on every GUI
-- callback) re-applies fonts/sizes in-place so previews stay smooth instead
-- of restarting their countdown each tick.
---------------------------------------------------------------------------------
local PREVIEW_BAR_KEYS = { "__preview_bar_1", "__preview_bar_2", "__preview_bar_3" }
local PREVIEW_TEXT_KEYS = { "__preview_text_1", "__preview_text_2", "__preview_text_3" }
local PREVIEW_BAR_LABELS = { "Sample Timer A", "Sample Timer B", "Sample Timer C" }
local PREVIEW_TEXT_LABELS = { "Sample Text A", "Sample Text B", "Sample Text C" }
local PREVIEW_DURATIONS = { 8, 12, 16 }
-- Three distinct, recognizable spell iconIDs so the preview rows visually
-- read as "real boss timers" while editing display settings. Stable across
-- WoW versions; not tied to any spell ID.
local PREVIEW_ICON_IDS = { 136116, 136048, 132288 }

DT.previewBarShown = false
DT.previewTextShown = false

local function CreatePreviewBar(self, key, label, duration, displayMode, iconID, sortIndex)
    local existing = self.bars[key]
    if existing then
        existing:SetScript("OnUpdate", nil)
        existing:Hide()
    end
    local bar = self:CreateBar(label, duration, 0, displayMode)
    bar.isPreview = true
    bar.loop = true
    bar.sortIndex = sortIndex
    -- CreateBar uses `text` as the dict key. Override so our preview keys
    -- don't collide with a real BigWigs bar literally named "Sample Timer A".
    bar.text = key
    if iconID and bar.icon then
        bar.icon:SetTexture(iconID)
    end
    self.bars[key] = bar
end

function DT:ShowSettingsBarPreviews()
    if self.previewBarShown then
        self:ApplySettings()
        return
    end
    self.previewBarShown = true
    for i, key in ipairs(PREVIEW_BAR_KEYS) do
        CreatePreviewBar(self, key, PREVIEW_BAR_LABELS[i], PREVIEW_DURATIONS[i], "bar", PREVIEW_ICON_IDS[i], i)
    end
    self:LayoutBars()
end

function DT:HideSettingsBarPreviews()
    if not self.previewBarShown then return end
    self.previewBarShown = false
    for _, key in ipairs(PREVIEW_BAR_KEYS) do
        local bar = self.bars[key]
        if bar then
            bar:SetScript("OnUpdate", nil)
            bar:Hide()
            self.bars[key] = nil
        end
    end
    self:LayoutBars()
end

function DT:RefreshSettingsBarPreviews()
    if self.previewBarShown then
        self:ApplySettings()
    else
        self:ShowSettingsBarPreviews()
    end
end

function DT:ShowSettingsTextPreviews()
    if self.previewTextShown then
        self:ApplySettings()
        return
    end
    self.previewTextShown = true
    for i, key in ipairs(PREVIEW_TEXT_KEYS) do
        CreatePreviewBar(self, key, PREVIEW_TEXT_LABELS[i], PREVIEW_DURATIONS[i], "text", nil, i)
    end
    self:LayoutBars()
end

function DT:HideSettingsTextPreviews()
    if not self.previewTextShown then return end
    self.previewTextShown = false
    for _, key in ipairs(PREVIEW_TEXT_KEYS) do
        local bar = self.bars[key]
        if bar then
            bar:SetScript("OnUpdate", nil)
            bar:Hide()
            self.bars[key] = nil
        end
    end
    self:LayoutBars()
end

function DT:RefreshSettingsTextPreviews()
    if self.previewTextShown then
        self:ApplySettings()
    else
        self:ShowSettingsTextPreviews()
    end
end

function DT:OnInitialize()
    -- self.db must be populated BEFORE KitnEssentials:OnEnable runs its
    -- auto-enable loop (Core/Main.lua), which checks `module.db.Enabled`
    -- to decide whether to call EnableModule() at startup. Without this,
    -- the module never auto-enables across /reload — only the GUI checkbox
    -- can enable it for the current session.
    self:UpdateDB()
    self:SetEnabledState(false)
end

function DT:OnEnable()
    dprint("OnEnable")
    self:UpdateDB()
    self:UpdateGroupPositions()

    local encCount, spellCount = 0, 0
    for _, enc in pairs(KE.EncounterData or {}) do
        encCount = encCount + 1
        if enc.spells then
            for _ in pairs(enc.spells) do spellCount = spellCount + 1 end
        end
    end
    dprint(string_format("EncounterData: %d encounters, %d spells", encCount, spellCount))

    if BigWigsLoader then
        for _, event in ipairs(BIGWIGS_EVENTS) do
            BigWigsLoader.RegisterMessage(self, event, "EventCallback")
        end
        dprint("registered " .. #BIGWIGS_EVENTS .. " BigWigs events")
    else
        dprint("BigWigsLoader missing — event registration skipped")
    end
end

function DT:OnDisable()
    dprint("OnDisable")
    if BigWigsLoader then
        for _, event in ipairs(BIGWIGS_EVENTS) do
            BigWigsLoader.UnregisterMessage(self, event)
        end
    end
end

function DT:EventCallback(event, ...)
    if event == "BigWigs_Timer" then
        local addon, spellId, duration, _, text, count, icon = ...
        local baseDur = tonumber(duration) or 0
        local spellIdNum = tonumber(spellId)
        local ext = self:GetSpellExtension(spellIdNum)
        local total = baseDur + ext
        local displayMode = self:GetSpellDisplay(spellIdNum)
        dprint(string_format("Timer text=%s spellId=%s base=%.2f ext=%.2f total=%.2f display=%s mod=%s count=%s icon=%s",
            tostring(text),
            tostring(spellId),
            baseDur,
            ext,
            total,
            displayMode,
            tostring(addon and addon.moduleName or addon),
            tostring(count),
            tostring(icon)))
        self:RenderBar(text, baseDur, ext, displayMode)
    elseif event == "BigWigs_StopBar" then
        local _, text = ...
        dprint("StopBar text=" .. tostring(text))
        self:StopBar(text)
    elseif event == "BigWigs_StopBars" then
        local addon = ...
        dprint("StopBars mod=" .. tostring(addon and addon.moduleName or addon))
        self:StopAllBars()
    elseif event == "BigWigs_OnBossDisable" then
        local addon = ...
        dprint("OnBossDisable mod=" .. tostring(addon and addon.moduleName or addon))
        self:StopAllBars()
    end
end

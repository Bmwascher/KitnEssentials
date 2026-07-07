-- ╔══════════════════════════════════════════════════════════╗
-- ║  TrashOutput.lua                                         ║
-- ║  Central bar/text alert renderer for DungeonTrash.       ║
-- ║                                                          ║
-- ║  A focused countdown widget (not the BigWigs-coupled     ║
-- ║  DungeonTimers renderer): a trash alert is a simple      ║
-- ║  "next cast in Xs" countdown — no cast phase, no         ║
-- ║  StopBar, no follow-ups. It reuses KE's low-level        ║
-- ║  helpers (icon/font/pixel-perfect position) and the      ║
-- ║  DungeonTimers BarDisplay/TextDisplay VISUAL settings    ║
-- ║  so trash bars look identical to boss bars, but owns     ║
-- ║  its own group/position + free-list pool + lifecycle.    ║
-- ║  Extends the DungeonTrash module (loads after it).       ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local DTrash = KitnEssentials:GetModule("DungeonTrash", true)
if not DTrash then return end

local CreateFrame = CreateFrame
local UIParent = UIParent
local GetTime = GetTime
local table_remove = table.remove
local table_insert = table.insert
local table_sort = table.sort
local string_format = string.format
local math_ceil = math.ceil

local DEFAULT_TRASH_COLOR = { 0.3, 0.5, 0.9 }
local FALLBACK_BAR_WIDTH = 250
local FALLBACK_BAR_HEIGHT = 22

-- Free-lists of retired kits, keyed by mode. Bar and text kits differ and
-- never cross. WoW frames are never GC'd, so per-spawn creation leaks —
-- mirrors DungeonTimers/DungeonCasts.
local alertPool = { bar = {}, text = {} }

DTrash.alerts = {}       -- [key] = active kit
DTrash._barGroup = nil
DTrash._textGroup = nil
DTrash._alertSort = 0    -- monotonic spawn order for stable stacking

-- ── Settings resolvers ─────────────────────────────────────────────────────

-- Visuals AND position/stacking/reveal-timing are shared with DungeonTimers so
-- trash alerts sit in the exact same on-screen spot as the boss timers (user
-- directive 2026-07-06). DungeonTimers' DB always exists (AceDB defaults), so
-- these reads are safe even when that module is disabled.
local function dtBarDisplay()
    local p = KE.db and KE.db.profile and KE.db.profile.DungeonTimers
    return p and p.BarDisplay
end
local function dtTextDisplay()
    local p = KE.db and KE.db.profile and KE.db.profile.DungeonTimers
    return p and p.TextDisplay
end
-- The bar/text GROUP (position, growth, spacing, and the ShowAtSeconds reveal
-- window) — trash 'bar' alerts share DungeonTimers' BarGroup, 'text' its
-- TextGroup. The trash module's own groups are no longer read.
local function dtGroup(mode)
    local p = KE.db and KE.db.profile and KE.db.profile.DungeonTimers
    if not p then return nil end
    return (mode == "bar") and p.BarGroup or p.TextGroup
end

local function resolveTexture(name)
    if KE.LSM and name then
        local path = KE.LSM:Fetch("statusbar", name)
        if path then return path end
    end
    return "Interface\\Buttons\\WHITE8x8"
end

local function barHeight()
    local d = dtBarDisplay()
    return (d and d.barHeight) or FALLBACK_BAR_HEIGHT
end

local function textHeight()
    local d = dtTextDisplay()
    local size = (d and d.fontSize) or 20
    local h = math.floor(size * 1.4 + 0.5)
    return (h < FALLBACK_BAR_HEIGHT) and FALLBACK_BAR_HEIGHT or h
end

-- ── Group frames ───────────────────────────────────────────────────────────

function DTrash:EnsureAlertGroup(mode)
    local isBar = (mode == "bar")
    local existing = isBar and self._barGroup or self._textGroup
    if existing then return existing end
    local name = isBar and "KE_DungeonTrash_BarGroup" or "KE_DungeonTrash_TextGroup"
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(1, 1)
    if isBar then self._barGroup = f else self._textGroup = f end
    self:UpdateAlertGroupPosition(mode)
    return f
end

function DTrash:UpdateAlertGroupPosition(mode)
    local group = (mode == "bar") and self._barGroup or self._textGroup
    if not group then return end
    local settings = dtGroup(mode)
    if not settings then return end
    KE:ApplyFramePosition(group, settings, settings)
end

-- ── Kit construction (create-once children on a pooled frame) ───────────────

local function buildKit(mode)
    local isBar = (mode == "bar")
    local group = DTrash:EnsureAlertGroup(mode)
    local px = (KE.GetPixelSize and KE:GetPixelSize()) or 1

    local frame = table_remove(alertPool[mode])
    if frame then
        frame._pooled = false
        frame:Show()
        return frame, px
    end

    frame = CreateFrame("Frame", nil, group)
    frame._poolKey = mode

    frame.iconFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.iconFrame:SetPoint("LEFT", frame, "LEFT", 0, 0)
    frame.iconFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    frame.iconFrame:SetBackdropColor(0, 0, 0, 0.8)
    if KE.AddIconBorders then KE:AddIconBorders(frame.iconFrame) end
    frame.icon = frame.iconFrame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetPoint("TOPLEFT", px, -px)
    frame.icon:SetPoint("BOTTOMRIGHT", -px, px)
    if KE.ApplyIconZoom then KE:ApplyIconZoom(frame.icon) end

    if isBar then
        frame.barContainer = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        frame.barContainer:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = px,
        })
        frame.barContainer:SetBackdropColor(0, 0, 0, 0.8)
        frame.barContainer:SetBackdropBorderColor(0, 0, 0, 1)
        frame.bar = CreateFrame("StatusBar", nil, frame.barContainer)
        frame.bar:SetPoint("TOPLEFT", px, -px)
        frame.bar:SetPoint("BOTTOMRIGHT", -px, px)
    else
        frame.bar = CreateFrame("StatusBar", nil, frame)
        frame.bar:SetAllPoints()
    end

    frame.label = frame.bar:CreateFontString(nil, "OVERLAY")
    frame.timerText = frame.bar:CreateFontString(nil, "OVERLAY")
    return frame, px
end

-- Visuals-only (re)apply; safe to call on a reused kit.
local function applyKitVisuals(frame, color)
    local isBar = (frame._poolKey == "bar")
    local px = (KE.GetPixelSize and KE:GetPixelSize()) or 1
    local barD = dtBarDisplay()
    local textD = dtTextDisplay()

    local w = (barD and barD.barWidth) or FALLBACK_BAR_WIDTH
    local h = isBar and barHeight() or textHeight()
    frame:SetSize(w, h)

    local iconEnabled = isBar and (not barD or barD.iconEnabled ~= false)
        or (not isBar and textD and textD.ShowSpellIcon)
    local iconSize = 0
    if iconEnabled then
        iconSize = isBar and h or math.floor(h * ((textD and textD.IconScale) or 0.7) + 0.5)
        frame.iconFrame:Show()
        frame.iconFrame:SetSize(iconSize, iconSize)
    else
        frame.iconFrame:Hide()
    end

    if isBar then
        frame.barContainer:ClearAllPoints()
        frame.barContainer:SetPoint("TOPLEFT", frame, "TOPLEFT", iconSize, 0)
        frame.barContainer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        frame.bar:SetStatusBarTexture(resolveTexture(barD and barD.barTexture))
        frame.bar:SetStatusBarColor(color[1], color[2], color[3])
        frame.bar:SetPoint("TOPLEFT", frame.barContainer, "TOPLEFT", px, -px)
        frame.bar:SetPoint("BOTTOMRIGHT", frame.barContainer, "BOTTOMRIGHT", -px, px)
    end

    -- Fonts. Bar mode: white label left / white timer right inside the fill.
    -- Text mode: colored "label »" static + colored timer hanging off it.
    local face = (isBar and barD or textD)
    local fontFace = (face and face.fontFace) or "Expressway"
    local fontSize = (face and face.fontSize) or (isBar and 14 or 20)
    local fontOutline = (face and face.fontOutline) or "OUTLINE"
    KE:ApplyFontToText(frame.label, fontFace, fontSize, fontOutline)
    KE:ApplyFontToText(frame.timerText, fontFace, fontSize, fontOutline)

    frame.label:ClearAllPoints()
    frame.timerText:ClearAllPoints()
    if isBar then
        frame.label:SetPoint("LEFT", frame.bar, "LEFT", 4, 0)
        frame.timerText:SetPoint("RIGHT", frame.bar, "RIGHT", -4, 0)
        frame.label:SetTextColor(1, 1, 1)
        frame.timerText:SetTextColor(1, 1, 1)
    else
        local anchor = iconEnabled and frame.iconFrame or frame
        local rel = iconEnabled and "RIGHT" or "LEFT"
        frame.label:SetPoint("LEFT", anchor, rel, iconEnabled and 4 or 0, 0)
        frame.timerText:SetPoint("LEFT", frame.label, "RIGHT", 4, 0)
        frame.label:SetTextColor(color[1], color[2], color[3])
        frame.timerText:SetTextColor(color[1], color[2], color[3])
    end
end

-- decimalUnder = show one decimal below this many seconds, whole seconds at or
-- above (nil → 10, trash's default cutoff). Per-ability via the Time Format knob.
local function formatRemaining(remaining, decimalUnder)
    if remaining < (decimalUnder or 10) then return string_format("%.1f", remaining) end
    return string_format("%d", math_ceil(remaining))
end

-- Play an LSM sound by name (nil = no-op). Alerts fire onShow when they reveal
-- and onHide when the countdown reaches 0 (the predicted cast moment) — never on
-- a plate-removal hide, so a despawn doesn't fake a cast cue.
local function playTrashSound(name)
    if not name then return end
    local file = KE.LSM and KE.LSM:Fetch("sound", name)
    if file then PlaySoundFile(file, "Master") end
end

local function alertOnUpdate(self)
    local remaining = self.expireAt - GetTime()
    if remaining <= 0 then
        if self._loop then
            -- Config-page preview: re-arm and keep looping instead of self-
            -- destructing, so the sample stays on screen while editing. Re-arm
            -- from the scheduled expiry (not the clock) so per-frame overshoot
            -- doesn't accumulate; fall back to now if a hitch left us far behind.
            local dur = self.totalDuration or 1
            self.expireAt = (self.expireAt or 0) + dur
            if self.expireAt <= GetTime() then self.expireAt = GetTime() + dur end
            if self.bar then self.bar:SetValue(dur) end
            self._lastStr = nil
            return
        end
        if self._soundHide then playTrashSound(self._soundHide) end
        DTrash:HideAlert(self.key)
        return
    end
    if self.bar and self.totalDuration and self.totalDuration > 0 then
        self.bar:SetValue(remaining)
    end
    local str = formatRemaining(remaining, self._decimalUnder)
    if str ~= self._lastStr then
        self._lastStr = str
        self.timerText:SetText(str)
    end
end

-- ── Public API (called from DungeonTrash FinishCast seam) ───────────────────

-- Show (or refresh) a countdown alert. key uniquely identifies the alert
-- (namespaced per unit+spell). duration = seconds the bar counts down.
function DTrash:ShowAlert(key, duration, mode, label, color, iconID, sounds, decimalUnder)
    if not (self.db and self.db.Enabled) or not key or not duration or duration <= 0 then return end
    mode = (mode == "text") and "text" or "bar"
    color = color or DEFAULT_TRASH_COLOR

    -- Refresh in place if the same key is already showing in the same mode.
    local existing = self.alerts[key]
    if existing and existing._poolKey == mode then
        existing.expireAt = GetTime() + duration
        existing.totalDuration = duration
        existing._decimalUnder = decimalUnder
        existing._soundHide = sounds and sounds.onHide or nil  -- a re-prediction may carry a changed hide-sound override
        if existing.bar then existing.bar:SetMinMaxValues(0, duration); existing.bar:SetValue(duration) end
        return existing
    elseif existing then
        self:HideAlert(key)  -- mode changed → rebuild
    end

    local frame = buildKit(mode)
    self:UpdateAlertGroupPosition(mode)  -- keep the stack on the shared DungeonTimers position
    frame.key = key
    frame.mode = mode
    frame.expireAt = GetTime() + duration
    frame.totalDuration = duration
    frame._lastStr = nil
    frame._loop = nil  -- pooled frames may have been a preview; real alerts never loop
    frame._decimalUnder = decimalUnder
    frame._soundHide = sounds and sounds.onHide or nil
    self._alertSort = self._alertSort + 1
    frame.sortIndex = self._alertSort

    applyKitVisuals(frame, color)
    if frame.icon then
        frame.icon:SetTexture(iconID or "Interface\\Icons\\INV_Misc_QuestionMark")
    end
    frame.label:SetText(mode == "text" and ((label or "?") .. " \194\187") or (label or "?"))
    if frame.bar then
        frame.bar:SetMinMaxValues(0, duration)
        frame.bar:SetValue(duration)
    end
    frame.timerText:SetText(formatRemaining(duration, decimalUnder))
    frame:SetScript("OnUpdate", alertOnUpdate)

    self.alerts[key] = frame
    self:LayoutAlerts(mode)
    if sounds and sounds.onShow then playTrashSound(sounds.onShow) end
    return frame
end

function DTrash:HideAlert(key)
    local frame = self.alerts[key]
    if not frame then return end
    self.alerts[key] = nil
    local mode = frame._poolKey
    frame:SetScript("OnUpdate", nil)
    if frame.label and frame.label.softOutline then frame.label.softOutline:SetShown(false) end
    if frame.timerText and frame.timerText.softOutline then frame.timerText.softOutline:SetShown(false) end
    frame:Hide()
    frame:ClearAllPoints()
    if not frame._pooled and frame._poolKey then
        frame._pooled = true
        table_insert(alertPool[frame._poolKey], frame)
    end
    self:LayoutAlerts(mode)
end

function DTrash:HideAllAlerts()
    for key in pairs(self.alerts) do self:HideAlert(key) end
    -- The loop swept the reserved preview frame too; clear its key so the
    -- invariant (trashPreviewKey non-nil ⇒ its frame exists) always holds.
    self.trashPreviewKey = nil
end

-- ── Config-page live preview ─────────────────────────────────────────────────
-- One looping sample alert rendered through the same kit path so the config page
-- shows the ability's real bar/text appearance at the real on-screen position.
-- Reserved key (never collides with a live alert); built via the kit primitives
-- directly (not ShowAlert) so it ignores the Enabled gate and plays no sound —
-- mirrors how the boss ShowSpellPreview uses CreateBar rather than RenderBar.
local TRASH_PREVIEW_KEY = "__trash_preview"
DTrash.trashPreviewKey = nil

function DTrash:ShowTrashPreview(mapID, npcID, spellID)
    if not (mapID and npcID and spellID) then self:HideTrashPreview(); return end
    local sig = string_format("%d:%d:%d", mapID, npcID, spellID)
    if self.trashPreviewKey == sig and self.alerts[TRASH_PREVIEW_KEY] then return end
    self:HideTrashPreview()

    local mode = (self:GetSpellDisplay(mapID, npcID, spellID) == "text") and "text" or "bar"
    local duration = self:GetSpellRevealAt(mapID, npcID, spellID)
    if not duration or duration <= 0 then duration = 8 end
    local label = self:GetSpellLabel(mapID, npcID, spellID)
    local color = self:GetSpellEffectiveColor(mapID, npcID, spellID) or DEFAULT_TRASH_COLOR
    local iconID = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)) or nil
    local decimalUnder = self:GetSpellDecimalThreshold(mapID, npcID, spellID)

    local frame = buildKit(mode)
    self:UpdateAlertGroupPosition(mode)
    frame.key = TRASH_PREVIEW_KEY
    frame.mode = mode
    frame._loop = true            -- keep looping instead of self-destructing
    frame.totalDuration = duration
    frame.expireAt = GetTime() + duration
    frame._lastStr = nil
    frame._soundHide = nil        -- preview never plays a cue
    frame._decimalUnder = decimalUnder
    self._alertSort = self._alertSort + 1
    frame.sortIndex = self._alertSort

    applyKitVisuals(frame, color)
    if frame.icon then
        frame.icon:SetTexture(iconID or "Interface\\Icons\\INV_Misc_QuestionMark")
    end
    frame.label:SetText(mode == "text" and ((label or "?") .. " \194\187") or (label or "?"))
    if frame.bar then
        frame.bar:SetMinMaxValues(0, duration)
        frame.bar:SetValue(duration)
    end
    frame.timerText:SetText(formatRemaining(duration, decimalUnder))
    frame:SetScript("OnUpdate", alertOnUpdate)

    self.alerts[TRASH_PREVIEW_KEY] = frame
    self.trashPreviewKey = sig
    self:LayoutAlerts(mode)
end

function DTrash:HideTrashPreview()
    if self.alerts[TRASH_PREVIEW_KEY] then self:HideAlert(TRASH_PREVIEW_KEY) end
    self.trashPreviewKey = nil
end

function DTrash:RefreshTrashPreview()
    if not self.trashPreviewKey then return end
    local m, n, s = self.trashPreviewKey:match("^(%d+):(%d+):(%d+)$")
    if not m then return end
    self:HideTrashPreview()
    self:ShowTrashPreview(tonumber(m), tonumber(n), tonumber(s))
end

-- Stack every active alert of `mode` in its group, growing from the group's
-- own anchor corner in the configured direction.
function DTrash:LayoutAlerts(mode)
    local group = (mode == "bar") and self._barGroup or self._textGroup
    if not group then return end
    local settings = dtGroup(mode)
    local spacing = (settings and settings.Spacing) or 1
    local growth = (settings and settings.GrowthDirection) or "DOWN"
    local anchorFrom = (settings and settings.AnchorFrom) or "CENTER"
    local down = (growth ~= "UP")

    local list = {}
    for _, frame in pairs(self.alerts) do
        if frame._poolKey == mode and frame:IsShown() then list[#list + 1] = frame end
    end
    table_sort(list, function(a, b) return (a.sortIndex or 0) < (b.sortIndex or 0) end)

    local y = 0
    for _, frame in ipairs(list) do
        frame:ClearAllPoints()
        frame:SetPoint(anchorFrom, group, anchorFrom, 0, y)
        local step = frame:GetHeight() + spacing
        y = down and (y - step) or (y + step)
    end
end

-- ── Scheduling from a resolved prediction ──────────────────────────────────

local C_Timer = C_Timer
local C_Spell = C_Spell

-- Per-ability override key (parallel to DungeonTimers' numeric spell keys).
local function overrideKey(mapID, npcID, spellID)
    return string_format("%d:%d:%d", mapID or 0, npcID or 0, spellID or 0)
end

function DTrash:ResolveTrashColor(npcID, spellID)
    local ov = self.db and self.db.SpellColorOverrides
    local c = ov and ov[overrideKey(self.currentMapID, npcID, spellID)]
    if c then return c end
    return DEFAULT_TRASH_COLOR
end

function DTrash:IsTrashSpellDisabled(npcID, spellID)
    local d = self.db and self.db.SpellDisabled
    return (d and d[overrideKey(self.currentMapID, npcID, spellID)] == true) or false
end

-- Reveal a countdown alert for a resolved prediction in its final window.
-- rt = the nameplate runtime (for unit + token invalidation of stale timers).
function DTrash:ScheduleAlert(rt, npcID, spellID, spellData, nextStart)
    if not rt or not spellData or self:IsTrashSpellDisabled(npcID, spellID) then return end
    -- "Who sees it" role gate — skip alerts not curated/overridden for our role.
    if not self:PlayerSeesTrashSpell(self.currentMapID, npcID, spellID) then return end
    -- Display honours the per-ability override (GUI), falling back to curated.
    local mode = (self:GetSpellDisplay(self.currentMapID, npcID, spellID) == "text") and "text" or "bar"
    -- Reveal window: per-ability override → shared DungeonTimers group default.
    local revealAt = self:GetSpellRevealAt(self.currentMapID, npcID, spellID)
    -- Invariant guard: the deferred branch below feeds revealAt straight into
    -- ShowAlert as the duration, and ShowAlert silently drops anything <= 0.
    -- revealGroupDefault already floors the group default, but keep the alert
    -- alive against any future sub-1 override that skips that path.
    if revealAt < 1 then revealAt = 1 end
    local lead = nextStart - GetTime()
    if lead <= 0 then return end

    local key = string_format("%s:%d:%d", rt.unit, npcID, spellID)
    local label = self:GetSpellLabel(self.currentMapID, npcID, spellID)
    local color = self:ResolveTrashColor(npcID, spellID)
    local iconID = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)) or nil
    local decimalUnder = self:GetSpellDecimalThreshold(self.currentMapID, npcID, spellID)
    local sounds = {
        onShow = self:GetSpellSoundOnShow(self.currentMapID, npcID, spellID),
        onHide = self:GetSpellSoundOnHide(self.currentMapID, npcID, spellID),
    }

    if lead <= revealAt then
        self:ShowAlert(key, lead, mode, label, color, iconID, sounds, decimalUnder)
        return
    end
    -- Defer to the reveal window; a newer prediction for the same key bumps the
    -- token so this stale timer (and any plate re-add) no-ops.
    rt._alertTokens = rt._alertTokens or {}
    local token = (rt._alertTokens[key] or 0) + 1
    rt._alertTokens[key] = token
    C_Timer.After(lead - revealAt, function()
        local r = self.tracked[rt.unit]
        if not r or not r._alertTokens or r._alertTokens[key] ~= token then return end
        self:ShowAlert(key, revealAt, mode, label, color, iconID, sounds, decimalUnder)
    end)
end

-- Hide active alerts belonging to a nameplate unit (on plate removal). Pending
-- (deferred) alerts self-cancel via the tracked/token guard above.
function DTrash:HideUnitAlerts(unit)
    if not unit then return end
    local prefix = unit .. ":"
    for key in pairs(self.alerts) do
        if key:sub(1, #prefix) == prefix then self:HideAlert(key) end
    end
end

return DTrash

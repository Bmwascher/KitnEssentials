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
local TI = KE.TrashInference  -- Trash.xml: inference loads first
if not DTrash then return end

local CreateFrame = CreateFrame
local UIParent = UIParent
local GetTime = GetTime
local table_remove = table.remove
local table_insert = table.insert
local table_sort = table.sort
local string_format = string.format
local math_ceil = math.ceil
local math_floor = math.floor
local math_abs = math.abs
local tonumber = tonumber

-- Owned by TrashConfig.lua (loads first); aliased so both files use ONE value.
local DEFAULT_TRASH_COLOR = DTrash.DEFAULT_TRASH_COLOR
local FALLBACK_BAR_WIDTH = 250
local FALLBACK_BAR_HEIGHT = 22
-- Reserved alert key for the config-page looping sample (never collides with a
-- live alert's unit-prefixed key). Declared here because HideAllAlerts' partial
-- sweep needs it above the preview section.
local TRASH_PREVIEW_KEY = "__trash_preview"

-- Free-lists of retired kits, keyed by mode. Bar and text kits differ and
-- never cross. WoW frames are never GC'd, so per-spawn creation leaks —
-- mirrors DungeonTimers/DungeonCasts.
local alertPool = { bar = {}, text = {} }

DTrash.alerts = {}       -- [key] = active kit
DTrash._barGroup = nil
DTrash._textGroup = nil
DTrash._alertSort = 0    -- monotonic high-water mark for genuinely-new alert keys
DTrash._sortByKey = {}   -- [key] = stable stack slot, survives self-destruct→rebuild

-- ── Settings resolvers ─────────────────────────────────────────────────────

-- Visuals AND position/stacking/reveal-timing are shared with DungeonTimers so
-- trash alerts sit in the exact same on-screen spot as the boss timers.
-- DungeonTimers' DB always exists (AceDB defaults), so these reads are safe
-- even when that module is disabled.
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
    -- Explicit per-mode select. The old `isBar and self._barGroup or
    -- self._textGroup` collapsed on nil: in a text-first session the bar
    -- request fell through to the EXISTING text group, so both stacks shared
    -- ONE frame that UpdateAlertGroupPosition then yanked between the two
    -- position configs on every alert — the "bars and texts fighting for
    -- position" report (observed in the field: shown [bar] alerts while
    -- _barGroup was still nil, the group teleporting between both posSigs).
    local existing
    if isBar then existing = self._barGroup else existing = self._textGroup end
    if existing then return existing end
    local name = isBar and "KE_DungeonTrash_BarGroup" or "KE_DungeonTrash_TextGroup"
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(1, 1)
    if isBar then self._barGroup = f else self._textGroup = f end
    self:UpdateAlertGroupPosition(mode)
    return f
end

function DTrash:UpdateAlertGroupPosition(mode)
    local group  -- explicit select: nil bar group must NOT fall through to text
    if mode == "bar" then group = self._barGroup else group = self._textGroup end
    if not group then return end
    local settings = dtGroup(mode)
    if not settings then return end
    -- Re-applying an already-placed group re-runs KE:ApplyFramePosition, whose
    -- ClearAllPoints + SetPoint(raw config) + pixel re-snap flip-flops the stack a
    -- hair between the snapped and unsnapped position. On the ShowAlert hot path
    -- (once per new alert) that made the whole bar/text stack visibly JITTER in a
    -- busy pull. Skip when the position config is unchanged — the group only needs
    -- to move when the shared DungeonTimers group is repositioned in the GUI.
    local sig = tostring(settings.AnchorFrom) .. "|" .. tostring(settings.AnchorTo)
        .. "|" .. tostring(settings.XOffset) .. "|" .. tostring(settings.YOffset)
        .. "|" .. tostring(settings.anchorFrameType) .. "|" .. tostring(settings.ParentFrame)
        .. "|" .. tostring(settings.Strata)
    if group._posSig == sig then return end
    group._posSig = sig
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
        -- Align-aware text layout via the SHARED KE.ApplySplitTextLayout
        -- (DungeonTimers.lua — the boss text renderer routes through the same
        -- function), so the two renderers can never drift again: trash had
        -- diverged to 4/4px gaps vs the boss's 2/5px while both stacks draw at
        -- the same shared TextGroup position. textAlign is shared via
        -- TextDisplay; default CENTER.
        local align = (textD and textD.textAlign) or "CENTER"
        KE.ApplySplitTextLayout(frame.bar, frame.label, frame.timerText,
            frame.iconFrame, iconEnabled, align)
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
    -- Registry self-check (belt-and-braces for any key-aliasing bug): a frame
    -- no longer installed under its own key is an orphan. Left running, its
    -- zero would replay the hide sound EVERY render frame and
    -- HideAlert(self.key) would tear down the frame that IS installed —
    -- degrade to a silent detach-and-pool instead.
    if DTrash.alerts[self.key] ~= self then
        self:SetScript("OnUpdate", nil)
        if self.label and self.label.softOutline then self.label.softOutline:SetShown(false) end
        if self.timerText and self.timerText.softOutline then self.timerText.softOutline:SetShown(false) end
        self:Hide()
        self:ClearAllPoints()
        if not self._pooled and self._poolKey then
            self._pooled = true
            table_insert(alertPool[self._poolKey], self)
        end
        return
    end
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
            self._lastQuant = nil
            self._lastValue = nil
            return
        end
        if self._soundHide then playTrashSound(self._soundHide) end
        DTrash:HideAlert(self.key)
        return
    end
    -- Pixel-aware SetValue gate (perf pattern 1, mirrors the boss renderer's
    -- GatedSetValue): skip writes smaller than one pixel of fill. remaining is
    -- plain GetTime arithmetic — never secret — so both gates here are safe.
    -- _valuePerPixel caches duration/width; width can read 0 on the very first
    -- tick (anchor-derived rect not laid out yet) — retry next tick, ungated.
    if self.bar and self.totalDuration and self.totalDuration > 0 then
        local vpp = self._valuePerPixel
        if vpp == nil then
            local w = self.bar:GetWidth() or 0
            if w > 0 then vpp = self.totalDuration / w; self._valuePerPixel = vpp end
        end
        if not vpp or vpp <= 0 or self._lastValue == nil
            or (self._lastValue - remaining) >= vpp then
            self._lastValue = remaining
            self.bar:SetValue(remaining)
        end
    end
    -- Quantize BEFORE formatting: the displayed string only changes on 0.1s
    -- steps below the decimal cutoff (rounding, matching %.1f) and 1s steps
    -- (ceil) above — gating here skips the per-frame string.format garbage,
    -- not just the SetText (which _lastStr still belts-and-braces).
    local q
    if remaining < (self._decimalUnder or 10) then
        q = math_floor(remaining * 10 + 0.5)
    else
        q = math_ceil(remaining)
    end
    if q ~= self._lastQuant then
        self._lastQuant = q
        local str = formatRemaining(remaining, self._decimalUnder)
        if str ~= self._lastStr then
            self._lastStr = str
            self.timerText:SetText(str)
        end
    end
end

-- Shared kit populate — every field/visual assignment identical between a live
-- alert (ShowAlert) and the config-page looping sample (ShowTrashPreview), so
-- the preview stays pixel-identical to a real alert BY CONSTRUCTION instead of
-- by a hand-synced copy. Differences ride the two trailing params: soundHide
-- (live only) and loop (preview only).
local function populateKit(frame, key, mode, duration, label, color, iconID, decimalUnder, soundHide, loop)
    frame.key = key
    frame.expireAt = GetTime() + duration
    frame.totalDuration = duration
    frame._lastStr = nil
    frame._lastQuant = nil
    frame._lastValue = nil
    frame._valuePerPixel = nil
    frame._loop = loop or nil      -- pooled frames may have been a preview; real alerts never loop
    frame._decimalUnder = decimalUnder
    frame._soundHide = soundHide
    frame.sortIndex = DTrash:StableSortIndex(key)

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

    DTrash.alerts[key] = frame
    DTrash:LayoutAlerts(mode)
end

-- ── Public API (called from DungeonTrash FinishCast seam) ───────────────────

-- Show (or refresh) a countdown alert. key uniquely identifies the alert
-- (namespaced per unit+spell). duration = seconds the bar counts down.
-- Stable stack slot for an alert key. A trash alert self-destructs at its
-- countdown's zero (and again at cast impact) and is then rebuilt by the next
-- ShowAlert for the SAME key. Keying the slot to the alert identity — not a
-- fresh spawn counter — makes the rebuilt alert return to its previous slot
-- instead of jumping to the bottom of the stack, which was the "bars swap back
-- and forth as it can't decide" churn. A genuinely-new key takes a new
-- high-water slot; a key's slot retires only when its plate departs
-- (HideUnitAlerts) or on full teardown (HideAllAlerts) — NOT on the ordinary
-- self-destruct, which is the very transition we keep stable. Per-unit keys
-- keep intended same-spell duplicates in distinct, stable slots.
function DTrash:StableSortIndex(key)
    local idx = self._sortByKey[key]
    if not idx then
        self._alertSort = self._alertSort + 1
        idx = self._alertSort
        self._sortByKey[key] = idx
    end
    return idx
end

function DTrash:ShowAlert(key, duration, mode, label, color, iconID, sounds, decimalUnder)
    -- Direct call, no method-existence guard: Trash.xml loads DungeonTrash.lua
    -- (which defines it) before this file, and a correctness gate must fail
    -- LOUD on a rename, not silently fall open.
    if self:IsBossOutputSuppressed() then return end
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
        existing._lastStr = nil
        existing._lastQuant = nil
        existing._lastValue = nil
        existing._valuePerPixel = nil  -- duration changed → new value-per-pixel
        if existing.bar then existing.bar:SetMinMaxValues(0, duration); existing.bar:SetValue(duration) end
        return existing
    elseif existing then
        self:HideAlert(key)  -- mode changed → rebuild
    end

    local frame = buildKit(mode)
    self:UpdateAlertGroupPosition(mode)  -- keep the stack on the shared DungeonTimers position
    populateKit(frame, key, mode, duration, label, color, iconID, decimalUnder,
        sounds and sounds.onHide or nil, nil)
    if sounds and sounds.onShow then playTrashSound(sounds.onShow) end
    return frame
end

-- skipLayout: teardown sweeps (HideAllAlerts / HideUnitAlerts) hide in bulk and
-- run ONE layout pass per mode afterwards instead of re-sorting/re-anchoring
-- the whole stack per key — the boss renderer's StopAllBars pattern.
function DTrash:HideAlert(key, skipLayout)
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
    if not skipLayout then self:LayoutAlerts(mode) end
end

-- keepPreview: sweep combat alerts but leave the config-page looping sample
-- alive — the encounter blackout must silence combat output without killing
-- the preview a user is editing mid-dungeon (RefreshTrashPreview permanently
-- no-ops once trashPreviewKey is nil'd). Full teardowns sweep everything.
function DTrash:HideAllAlerts(keepPreview)
    local preview = keepPreview and self.trashPreviewKey and self.alerts[TRASH_PREVIEW_KEY] or nil
    for key in pairs(self.alerts) do
        if not (preview and key == TRASH_PREVIEW_KEY) then self:HideAlert(key, true) end
    end
    self:LayoutAlerts("bar")
    self:LayoutAlerts("text")
    if preview then
        -- Partial sweep: retire every slot except the surviving preview's.
        for key in pairs(self._sortByKey) do
            if key ~= TRASH_PREVIEW_KEY then self._sortByKey[key] = nil end
        end
    else
        -- Every alert is gone, so reset the stable-slot cache — nothing should
        -- pin a stack slot across a full teardown (monitor stop / zone change).
        self._sortByKey = {}
        -- The loop swept the reserved preview frame too; clear its key so the
        -- invariant (trashPreviewKey non-nil ⇒ its frame exists) always holds.
        self.trashPreviewKey = nil
    end
end

-- ── Config-page live preview ─────────────────────────────────────────────────
-- One looping sample alert rendered through the same kit path so the config page
-- shows the ability's real bar/text appearance at the real on-screen position.
-- Reserved key (TRASH_PREVIEW_KEY, declared top-of-file; never collides with a
-- live alert); built via the kit primitives directly (not ShowAlert) so it
-- ignores the Enabled gate and plays no sound — mirrors how the boss
-- ShowSpellPreview uses CreateBar rather than RenderBar.
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
    local color = self:GetSpellEffectiveColor(mapID, npcID, spellID)  -- never nil (falls to DEFAULT_TRASH_COLOR internally)
    local iconID = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)) or nil
    local decimalUnder = self:GetSpellDecimalThreshold(mapID, npcID, spellID)

    local frame = buildKit(mode)
    self:UpdateAlertGroupPosition(mode)
    -- loop=true keeps the sample cycling; no soundHide — a preview never cues.
    populateKit(frame, TRASH_PREVIEW_KEY, mode, duration, label, color, iconID, decimalUnder, nil, true)
    self.trashPreviewKey = sig
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
    local group  -- explicit select: nil bar group must NOT fall through to text
    if mode == "bar" then group = self._barGroup else group = self._textGroup end
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

    -- Merged stack with the boss timers — bars and texts each form ONE stack
    -- at the shared position: the two renderers' groups sit at the identical
    -- pixel-snapped spot, so trash rows start at the boss stack's current
    -- extent and continue it instead of drawing over slot-for-slot.
    -- DT:LayoutBars re-flows this block whenever the boss stack resizes; the
    -- read here is one-directional (no recursion).
    local bossExtent = 0
    local dt = KitnEssentials:GetModule("DungeonTimers", true)
    if dt and dt.GetStackExtent then bossExtent = dt:GetStackExtent(mode) or 0 end

    local y = down and -bossExtent or bossExtent
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

-- Unified with the GUI/preview path: user colour override → preset colour from
-- the effective label → flat default (see TrashConfig:GetSpellEffectiveColor).
function DTrash:ResolveTrashColor(npcID, spellID)
    return self:GetSpellEffectiveColor(self.currentMapID, npcID, spellID)
end

-- Delegates to TrashConfig's accessor — one reader, one key builder, so the
-- GUI checkbox and the live suppression can never silently diverge.
function DTrash:IsTrashSpellDisabled(npcID, spellID)
    return self:GetSpellDisabled(self.currentMapID, npcID, spellID)
end

-- Reveal a countdown alert for a resolved prediction in its final window.
-- rt = the nameplate runtime (for unit + token invalidation of stale timers).
function DTrash:ScheduleAlert(rt, npcID, spellID, spellData, nextStart)
    if not rt or not spellData or self:IsTrashSpellDisabled(npcID, spellID) then return end
    -- Arm-time blackout gate (the reference suppresses at schedule/registration
    -- time, not just display): a cast resolved mid-blackout must not arm a
    -- deferred timer that matures — and passes the ShowAlert gate — after
    -- ENCOUNTER_END. Identity recorded during a blocklisted encounter is
    -- exactly the mislabeled kind the blackout exists to silence.
    if self:IsBossOutputSuppressed() then return end
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
        -- Bump the key's token so any OLDER still-pending deferred arm no-ops
        -- at its token check below: without this, an early re-cast that lands
        -- in the immediate window leaves the previous deferred arm alive, and
        -- it later revives a countdown to a schedule that no longer exists
        -- (the references keep exactly ONE mutable timer per runtime+spell,
        -- refreshed in place, so a stale second arm can't exist there).
        rt._alertTokens = rt._alertTokens or {}
        rt._alertTokens[key] = (rt._alertTokens[key] or 0) + 1
        self:ShowAlert(key, lead, mode, label, color, iconID, sounds, decimalUnder)
        return
    end
    -- Defer to the reveal window; a newer prediction for the same key bumps the
    -- token so this stale timer (and any plate re-add) no-ops.
    rt._alertTokens = rt._alertTokens or {}
    local token = (rt._alertTokens[key] or 0) + 1
    rt._alertTokens[key] = token
    -- Retract a bar already SHOWING under this key: the new prediction is
    -- beyond the reveal window, so a visible countdown is counting to an
    -- OBSOLETE moment (the mob cast earlier than predicted) — left up, it
    -- runs to a stale zero, plays the "cast moment" cue seconds late, and
    -- contradicts the instantly-corrected plate icon. The reference re-times
    -- its one mutable timer in place and its lead-window clamp hides it the
    -- same tick. HideAlert plays no sound; the stable-slot cache returns the
    -- re-revealed alert to the same stack position.
    if self.alerts[key] then self:HideAlert(key) end
    C_Timer.After(lead - revealAt, function()
        -- Identity check on the CAPTURED runtime table (r ~= rt), not just the
        -- token: a recycled plate token hosts a FRESH runtime whose counter
        -- restarts at 1, so a same-npcID mob re-scheduling the same spell
        -- would collide with this timer's token and revive a dead mob's
        -- countdown. Comparing table identity (as the reference's captured-
        -- runtime guards do) makes any plate re-add a guaranteed no-op.
        -- Cache-window exception (reference: every cancel entry point no-ops
        -- while the runtime is pending recovery): a reveal maturing while
        -- rt's plate is flickered off still fires on schedule — the cache
        -- owns the real cancel (a restore wipes _alertTokens and re-arms
        -- under the new key; an expiry sweeps the shown frame by npcID).
        local live = self.tracked[rt.unit] == rt or rt._cachePending == true
        if not live or not rt._alertTokens or rt._alertTokens[key] ~= token then return end
        -- Re-check the per-spell gates at FIRE time: a mid-dungeon GUI disable
        -- or role change must kill this pending reveal — the reference rebuilds
        -- every schedule through its gates on each config revision; re-checking
        -- where armed output actually fires reproduces that outcome.
        if self:IsTrashSpellDisabled(npcID, spellID)
            or not self:PlayerSeesTrashSpell(self.currentMapID, npcID, spellID) then return end
        self:ShowAlert(key, revealAt, mode, label, color, iconID, sounds, decimalUnder)
    end)
end

-- Observed-cast-start cue: a third per-spell sound slot fired the moment a
-- tracked mob's REAL cast bar is observed.
-- The references dispatch their cast-start voice from the live START event
-- and force-DISABLE the countdown-zero cue for it ("CD zero means available,
-- not casting"); KE's onShow/onHide slots are both prediction-fired, so
-- neither ever fires at the observed cast — early casts silently swallow the
-- onHide cue via refresh-in-place, and a stunned mob's countdown plays it
-- with nothing casting. The spell is identified the way the reference
-- resolves its start-voice spell, DEFERRED one cue window so the +0.10s
-- cast-start fingerprint sampler lands first (the reference's
-- CAST_START_VOICE_TARGET_DELAY = 0.12 serves the same purpose): the sampled
-- start fingerprints are HARD eligibility filters ahead of the
-- nearest-predicted-start scoring (the reference gates every voice candidate
-- on its fingerprints the same way).
-- That filter — not the schedule — is what separates same-kind spells whose
-- predictions have drifted together: Alpha Eagle's Gust and Raging Screech
-- curate opposite targetClearOnCastStart, and a synchronous,
-- fingerprint-blind pick played the wrong spell's sound in the field.
-- Kind rule: cast → any curated cast, including a two-phase spell's cast
-- phase; channel → channel-ONLY (a two-phase channel start is the
-- transition, its cue fired at the cast). Ambiguity within the reference's
-- 0.05s tie margin plays nothing — never a guess. Once per cast instance
-- (activeCastSeq). Called from BeginCast on every start.
local CAST_START_CUE_TIE = 0.05    -- reference's inline 0.05s tie margin
local CAST_START_CUE_DELAY = 0.12  -- reference: CAST_START_VOICE_TARGET_DELAY

function DTrash:PlayObservedCastStartCue(rt, kind)
    if not (rt and rt.activeCastSeq) then return end
    local seq = rt.activeCastSeq
    C_Timer.After(CAST_START_CUE_DELAY, function()
        self:FireObservedCastStartCue(rt, kind, seq)
    end)
end

function DTrash:FireObservedCastStartCue(rt, kind, seq)
    if self.tracked[rt.unit] ~= rt then return end
    -- Still THIS cast: a kick/failure inside the window clears the active
    -- kind, a new start bumps the seq — either way the cue died with it
    -- (reference: the delayed voice re-resolves and bails when the runtime
    -- moved on).
    if rt.activeCastSeq ~= seq or rt.activeCastKind ~= kind then return end
    if rt._castStartCuedSeq == seq then return end
    local npcID = rt.matchedNPCID
    if not (npcID and rt.anchors) then return end
    if self:IsBossOutputSuppressed() then return end
    if not (self.db and self.db.Enabled) then return end
    local mob = self:MobData(npcID)
    if not (mob and mob.spells) then return end
    local startAt = rt.activeCastStartAt or GetTime()
    local fingerprints = {
        targetExists = rt.fpTargetExists,
        targetAPIExists = rt.fpTargetAPIExists,
        castStartChangeTarget = rt.fpCastStartChangeTarget,
        targetClearOnCastStart = rt.fpTargetClearOnCastStart,
        targetIsTank = rt.fpTargetIsTank,
        castStartAuraDelta = rt.fpCastStartAuraDelta,
    }
    local candidates
    for spellID, spellData in pairs(mob.spells) do
        local hasCast = (tonumber(spellData.castTime) or 0) > 0
        local hasChannel = (tonumber(spellData.channelTime) or 0) > 0
        local kindOK
        if kind == "cast" then kindOK = hasCast else kindOK = hasChannel and not hasCast end
        if kindOK and not TI.StartFingerprintsMatch(spellData, fingerprints) then kindOK = false end
        local anchor = kindOK and rt.anchors[spellID] or nil
        if anchor and anchor.nextStartAt then
            candidates = candidates or {}
            candidates[#candidates + 1] = { spellID = spellID, delta = math_abs(startAt - anchor.nextStartAt) }
        end
    end
    if not candidates then return end
    local best = candidates[1]
    for i = 2, #candidates do
        if candidates[i].delta < best.delta then best = candidates[i] end
    end
    for i = 1, #candidates do
        local c = candidates[i]
        if c ~= best and (c.delta - best.delta) <= CAST_START_CUE_TIE then return end
    end
    local spellID = best.spellID
    if self:IsTrashSpellDisabled(npcID, spellID) then return end
    if not self:PlayerSeesTrashSpell(self.currentMapID, npcID, spellID) then return end
    -- Effective resolver: user override > curated castSound default > silent.
    local sound = self:GetEffectiveSpellSoundOnCastStart(self.currentMapID, npcID, spellID)
    if not sound then return end
    rt._castStartCuedSeq = seq
    playTrashSound(sound)
end

-- Move a departed unit's still-visible alerts to its restored plate token
-- (TrashCache flicker recovery): same frames, same stable stack slots, new
-- unit-prefixed keys — the bars keep counting instead of being torn down and
-- re-emitted (the reference re-points its scheduler timers the same way).
-- Deferred timers are NOT re-pointed here; the cache kills them via their
-- token table and re-arms from the anchors. npcID (from the restored row)
-- scopes the move to the restored mob's own keys — a recycled token may
-- already carry a DIFFERENT live mob's bars, which must stay put (the
-- reference rebinds only timers owned by the restored runtime object).
function DTrash:RekeyUnitAlerts(oldUnit, newUnit, npcID)
    if not oldUnit or not newUnit or oldUnit == newUnit then return end
    local oldPrefix = npcID and (oldUnit .. ":" .. npcID .. ":") or (oldUnit .. ":")
    local newPrefix = npcID and (newUnit .. ":" .. npcID .. ":") or (newUnit .. ":")
    local moves
    for key, frame in pairs(self.alerts) do
        if key:sub(1, #oldPrefix) == oldPrefix then
            moves = moves or {}
            moves[key] = frame
        end
    end
    if moves then
        local sweptBar, sweptText = false, false
        for key, frame in pairs(moves) do
            local newKey = newPrefix .. key:sub(#oldPrefix + 1)
            -- Destination-key collision: two same-npcID twins can legally own
            -- the identical key the moment a recycled token is involved (the
            -- restored row's bars re-key onto a token whose live occupant
            -- shares the npcID). A blind overwrite orphaned the occupant —
            -- Shown, OnUpdate still attached, but registry-unreachable: at
            -- its zero it tore down THIS frame via HideAlert(self.key) and
            -- then re-entered its zero branch every render frame until
            -- /reload. Hide/pool the occupant first; one layout pass below.
            local clash = self.alerts[newKey]
            if clash and clash ~= frame then
                if clash._poolKey == "text" then sweptText = true else sweptBar = true end
                self:HideAlert(newKey, true)
            end
            self.alerts[key] = nil
            self.alerts[newKey] = frame
            frame.key = newKey  -- self-destruct path (alertOnUpdate) hides by frame.key
            if self._sortByKey[key] then
                self._sortByKey[newKey] = self._sortByKey[key]
            end
        end
        if sweptBar then self:LayoutAlerts("bar") end
        if sweptText then self:LayoutAlerts("text") end
    end
    -- Retire every remaining old-unit slot (including the moved originals').
    for key in pairs(self._sortByKey) do
        if key:sub(1, #oldPrefix) == oldPrefix then self._sortByKey[key] = nil end
    end
end

-- Hide active alerts belonging to a nameplate unit (on plate removal). Pending
-- (deferred) alerts self-cancel via the tracked/token guard above.
-- npcID (optional) scopes the sweep to that mob's keys alone: alert keys embed
-- npcID, and a token recycled inside the cache restore window can host TWO
-- runtimes' output at once (the cached mob's still-counting bars + the new
-- mob's). The reference never has this problem because its cancels are keyed
-- to the runtime object, not the reusable token — the npcID scope is KE's
-- equivalent isolation. nil npcID keeps the full-token sweep (teardowns).
function DTrash:HideUnitAlerts(unit, npcID)
    if not unit then return end
    local prefix = npcID and (unit .. ":" .. npcID .. ":") or (unit .. ":")
    local sweptBar, sweptText = false, false
    for key, frame in pairs(self.alerts) do
        if key:sub(1, #prefix) == prefix then
            if frame._poolKey == "text" then sweptText = true else sweptBar = true end
            self:HideAlert(key, true)
        end
    end
    if sweptBar then self:LayoutAlerts("bar") end
    if sweptText then self:LayoutAlerts("text") end
    -- Retire this unit's stable stack slots. Swept independently of self.alerts:
    -- an alert that already self-destructed (its countdown hit zero) is gone from
    -- self.alerts but its slot lingers, and the plate is now leaving for good.
    for key in pairs(self._sortByKey) do
        if key:sub(1, #prefix) == prefix then self._sortByKey[key] = nil end
    end
end

return DTrash

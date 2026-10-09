-- ╔══════════════════════════════════════════════════════════╗
-- ║  ShamanProcCooldowns.lua                                 ║
-- ║  Module: Shaman Proc Cooldowns                           ║
-- ║  Purpose: Counts down Nature's Guardian and Thunderous   ║
-- ║           Paws internal cooldowns after each proc.       ║
-- ║  Note: Shaman only. A tracker exists only while its      ║
-- ║        talent is known.                                  ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- The game reports neither cooldown: the spell cooldown API is inactive or
-- secret for every id involved. The proc's hidden spell does announce itself
-- on SPELL_UPDATE_COOLDOWN, so each tracker counts a fixed length from that
-- announcement.

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class ShamanProcCooldowns: AceModule, AceEvent-3.0
---@field editModeRegistered boolean? true while the EditMode element is registered; nil after UnregisterAnchor
---@field editModeFrame table? the frame the EditMode element was registered with
---@field ticker table? the text-mode ticker; nil while no countdown runs
---@field layoutCount number? text lines laid out last; nil forces a relayout
---@field ignoreUntil number? announcements before this GetTime() are ignored
local SPC = KitnEssentials:NewModule("ShamanProcCooldowns", "AceEvent-3.0")
-- Gates the preview manager.
SPC.classRestriction = "SHAMAN"

local Rules = KE.ShamanProcRules
local Ask = KE.PlateSlots.Ask

local CreateFrame = CreateFrame
local C_Timer = C_Timer
local GetTime = GetTime
local IsInInstance = IsInInstance
local UnitClass = UnitClass
local UnitAffectingCombat = UnitAffectingCombat
local ipairs, pairs, pcall = ipairs, pairs, pcall
local math_max = math.max
local string_format = string.format
local wipe = wipe

-- Flip to true, /reload, repro, read the log.
local DEBUG_SPC = false

local ATTACH_KEY = "shamanProcs"
local SLOT_WIDTH = 220
local TICK = 0.1
-- Talent state is not reliable on the frame a talent event fires.
local TALENT_EVAL_DELAY = 2
local FALLBACK_ICON = 134400
local PREVIEW_ELAPSED, PREVIEW_LENGTH = 12, 30
-- Marks a preview icon's sample cooldown. GetTime never returns it, so the
-- next live paint always replaces the sample.
local PREVIEW_START = -1

local EDIT_MODE_ELEMENT = {
    key = "ShamanProcCooldowns",
    displayName = "Shaman Proc Cooldowns",
    guiPath = "ClassTools",
    guiTab = "ShamanProcCooldowns",
}

local function IsKnown(spellID)
    return Ask(C_SpellBook and C_SpellBook.IsSpellKnown, spellID, Enum.SpellBookSpellBank.Player)
end

local function LengthNow(key, hasHarmony)
    local _, instanceType = IsInInstance()
    return Rules.Length(key, hasHarmony, Rules.IsPvPInstance(instanceType))
end

local function SpellIcon(spellID)
    local getTexture = C_Spell and C_Spell.GetSpellTexture
    if getTexture then
        local ok, icon = pcall(getTexture, spellID)
        if ok and icon then return icon end
    end
    return FALLBACK_ICON
end

local function HexOf(color)
    return KE:RGBAToHex(color and color[1], color and color[2], color and color[3])
end

local function Tick()
    SPC:Render()
end

local function DeferredEvaluate()
    if SPC:IsEnabled() then SPC:Evaluate() end
end

---------------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------------
function SPC:UpdateDB()
    self.db = KE.db.profile.ShamanProcCooldowns
end

function SPC:OnInitialize()
    self:UpdateDB()
    self.active, self.activeList = {}, {}
    self.startedAt, self.lengths, self.readyTimers = {}, {}, {}
    self.buttons, self.slots, self.shownButtons = {}, {}, {}
    self.linePrefix, self.readyLine = {}, {}
    self.live, self.combatEvents = false, false
    -- Starts false, not nil, so the first placement is not read as a change.
    self.attached = false
    self.isPreview = false
    self:SetEnabledState(false)
end

function SPC:CreateFrame_()
    if self.frame then return end
    local frame = CreateFrame("Frame", "KE_ShamanProcCooldowns", UIParent)
    frame:SetSize(SLOT_WIDTH, 30)
    frame:Hide()
    self.frame = frame
end

-- The length the next proc would count, or nil while the talent is not known.
function SPC:NextLength(tracker)
    if IsKnown(tracker.talent) ~= true then return nil end
    return LengthNow(tracker.key, IsKnown(Rules.NATURAL_HARMONY) == true)
end

---------------------------------------------------------------------------------
-- Attach and position
---------------------------------------------------------------------------------
-- Text only: Combat Texts places this frame below its lines and this module
-- reports every show, hide and resize.
function SPC:IsAttached()
    local db = self.db
    if not db or db.DisplayMode ~= "TEXT" then return false end
    local cm = KitnEssentials:GetModule("CombatTexts", true)
    return cm ~= nil and cm:AcceptsAttach(db.AttachToCombatTexts == true)
end

function SPC:NotifyAttach()
    if not self.attached then return end
    local cm = KitnEssentials:GetModule("CombatTexts", true)
    if cm then cm:AttachedFrameChanged(ATTACH_KEY) end
end

function SPC:UpdateAttachSubscription()
    local cm = KitnEssentials:GetModule("CombatTexts", true)
    if cm then cm:SyncAttachSubscription(self, self.live or self.isPreview) end
end

-- Attached, the text takes the Combat Texts face, outline and spacing, and its
-- size unless Override Text Size is on.
function SPC:EffectiveStyle()
    local db = self.db
    if self:IsAttached() then
        local cm = KitnEssentials:GetModule("CombatTexts", true)
        local c = cm and cm.db
        if c then
            local size = cm.ResolveAttachedSize(true, db.AttachOwnFontSize, db.FontSize, c.FontSize)
            return c.FontFace or db.FontFace, size, c.FontOutline or db.FontOutline, c.Spacing or db.Spacing
        end
    end
    return db.FontFace, db.FontSize, db.FontOutline, db.Spacing
end

function SPC:ApplyPosition()
    local frame, db = self.frame, self.db
    if not frame or not db then return end
    local cm = KitnEssentials:GetModule("CombatTexts", true)
    local wasAttached = self.attached
    local want = (self.live or self.isPreview) and cm ~= nil and self:IsAttached()
    self.attached = want and cm:SetAttachedFrame(ATTACH_KEY, frame) or false
    if not self.attached then
        if cm then cm:SetAttachedFrame(ATTACH_KEY, nil) end
        KE:ApplyFramePosition(frame, db.Position, db)
    end
    self:UpdateAttachSubscription()
    -- A Combat Texts on/off message flips attachment with nothing else behind
    -- it, so the mover follows here.
    if wasAttached ~= self.attached and (self.live or self.isPreview) then
        self:RegisterAnchor()
    end
end

---------------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------------
-- Every unregister goes through here. The cache below is what makes a repeat
-- RegisterAnchor a no-op, so dropping the key without clearing it would block
-- re-registration for the rest of the session.
function SPC:UnregisterAnchor()
    KE.EditMode:UnregisterElement("ShamanProcCooldowns")
    self.editModeRegistered = nil
    self.editModeFrame = nil
end

function SPC:RegisterAnchor()
    -- Attached, Combat Texts owns the anchor; a second mover would fight it.
    if not (self.live or self.isPreview) or self.attached then
        self:UnregisterAnchor()
        return
    end
    -- Re-registering the same frame would cancel a drag in progress.
    if self.editModeRegistered and self.editModeFrame == self.frame then return end

    local cfg = {}
    for k, v in pairs(EDIT_MODE_ELEMENT) do cfg[k] = v end
    cfg.frame = self.frame
    cfg.module = self
    cfg.getPosition = function() return self.db.Position end
    cfg.setPosition = function(pos)
        local p = self.db.Position
        p.AnchorFrom, p.AnchorTo = pos.AnchorFrom, pos.AnchorTo
        p.XOffset, p.YOffset = pos.XOffset, pos.YOffset
        self:ApplyPosition()
    end
    KE.EditMode:RegisterElement(cfg)
    self.editModeRegistered = true
    self.editModeFrame = self.frame
end

---------------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------------
function SPC:StyleButton(btn)
    local db = self.db
    btn:SetSize(db.IconSize or 44, db.IconSize or 44)
    btn.cooldown:SetCountdownMillisecondsThreshold(db.DecimalThreshold or 0)
    for _, region in ipairs({ btn.cooldown:GetRegions() }) do
        if region:GetObjectType() == "FontString" then
            KE:ApplyFontToText(region, db.FontFace, db.TimerFontSize, db.FontOutline)
            region:SetShadowOffset(0, 0)
            region:ClearAllPoints()
            region:SetPoint("CENTER", btn.cooldown, "CENTER", 0, 0)
        end
    end
end

function SPC:GetButton(tracker)
    local btn = self.buttons[tracker.key]
    if btn then return btn end

    btn = CreateFrame("Frame", nil, self.frame)
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints(btn)
    btn.icon:SetTexture(SpellIcon(tracker.talent))
    KE:ApplyIconZoom(btn.icon)
    KE:AddIconBorders(btn, { 0, 0, 0, 1 })

    btn.cooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    btn.cooldown:SetAllPoints(btn)
    btn.cooldown:SetDrawEdge(false)
    btn.cooldown:SetDrawSwipe(true)
    btn.cooldown:SetDrawBling(false)
    btn.cooldown:SetHideCountdownNumbers(false)

    btn:Hide()
    self.buttons[tracker.key] = btn
    self:StyleButton(btn)
    return btn
end

function SPC:StyleSlot(slot)
    local face, size, outline = self:EffectiveStyle()
    KE:ApplyFontToText(slot.text, face, size, outline)
    slot:SetSize(SLOT_WIDTH, (size or 16) + 6)
    slot.lastText = nil
end

function SPC:GetSlot(index)
    local slot = self.slots[index]
    if slot then return slot end
    slot = CreateFrame("Frame", nil, self.frame)
    slot.text = slot:CreateFontString(nil, "OVERLAY")
    slot.text:SetPoint("CENTER")
    self.slots[index] = slot
    -- A FontString with no font set throws on SetText.
    self:StyleSlot(slot)
    return slot
end

-- Runs on settings changes only: the cached line prefixes keep the per-tick
-- text work to one format and one concatenation per line.
function SPC:ApplyStyle()
    if not self.frame then return end
    local db = self.db
    local sep = db.Separator
    if sep == nil or sep == "" then sep = "-" end
    local nameHex, sepHex = HexOf(db.TextColor), HexOf(db.SeparatorColor)
    local timeHex, readyHex = HexOf(db.TimerColor), HexOf(db.ReadyColor)
    for _, tracker in ipairs(Rules.TRACKERS) do
        self.linePrefix[tracker.key] = string_format("|cff%s%s|r |cff%s%s|r |cff%s",
            nameHex, tracker.name, sepHex, sep, timeHex)
        self.readyLine[tracker.key] = string_format("|cff%s%s|r", readyHex, tracker.name)
    end

    local icons = db.DisplayMode == "ICONS"
    for _, slot in ipairs(self.slots) do
        self:StyleSlot(slot)
        if icons then slot:Hide() end
    end
    for _, btn in pairs(self.buttons) do
        self:StyleButton(btn)
        if not icons then btn:Hide() end
    end
    self.layoutCount = nil
end

---------------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------------
-- The frame keeps room for every active tracker, so an icon that appears or
-- disappears never moves the frame's center.
function SPC:LayoutIcons(shown, reserved)
    local db = self.db
    local size, spacing = db.IconSize or 44, db.IconSpacing or 2
    local dir = db.IconGrowDirection or "RIGHT"
    local slots = math_max(reserved, 1)
    local extent = size * slots + spacing * (slots - 1)
    if dir == "RIGHT" or dir == "LEFT" then
        self.frame:SetSize(extent, size)
    else
        self.frame:SetSize(size, extent)
    end
    for i, btn in ipairs(shown) do
        local step = (i - 1) * (size + spacing)
        btn:ClearAllPoints()
        if dir == "RIGHT" then
            btn:SetPoint("LEFT", self.frame, "LEFT", step, 0)
        elseif dir == "LEFT" then
            btn:SetPoint("RIGHT", self.frame, "RIGHT", -step, 0)
        elseif dir == "UP" then
            btn:SetPoint("BOTTOM", self.frame, "BOTTOM", 0, step)
        else
            btn:SetPoint("TOP", self.frame, "TOP", 0, -step)
        end
        btn:Show()
    end
end

-- Attached, the lines are members of the Combat Texts stack, so they stack
-- down whatever the saved direction.
function SPC:LayoutSlots(count)
    local db = self.db
    local _, size, _, spacing = self:EffectiveStyle()
    spacing = spacing or 2
    local slotHeight = (size or 16) + 6
    local dir = self.attached and "DOWN" or (db.GrowDirection or "DOWN")
    local horizontal = dir == "RIGHT" or dir == "LEFT"
    local prev
    for i = 1, count do
        local slot = self.slots[i]
        slot:ClearAllPoints()
        if horizontal then
            local side = dir == "RIGHT" and "LEFT" or "RIGHT"
            local opp = dir == "RIGHT" and "RIGHT" or "LEFT"
            if prev then
                slot:SetPoint(side, prev, opp, dir == "RIGHT" and spacing or -spacing, 0)
            else
                slot:SetPoint(side, self.frame, side, 0, 0)
            end
        else
            local side = dir == "UP" and "BOTTOM" or "TOP"
            local opp = dir == "UP" and "TOP" or "BOTTOM"
            if prev then
                slot:SetPoint(side, prev, opp, 0, dir == "UP" and spacing or -spacing)
            else
                slot:SetPoint(side, self.frame, side, 0, 0)
            end
        end
        slot:Show()
        prev = slot
    end
    for i = count + 1, #self.slots do
        self.slots[i]:Hide()
    end
    if count > 0 then
        local gaps = spacing * (count - 1)
        if horizontal then
            self.frame:SetSize(SLOT_WIDTH * count + gaps, slotHeight)
        else
            self.frame:SetSize(SLOT_WIDTH, slotHeight * count + gaps)
        end
    end
    self.layoutCount = count
end

---------------------------------------------------------------------------------
-- Render
---------------------------------------------------------------------------------
function SPC:StartTicker()
    if self.ticker then return end
    self.ticker = C_Timer.NewTicker(TICK, Tick)
end

function SPC:StopTicker()
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
end

function SPC:RenderIcons(now)
    local db = self.db
    local shown = self.shownButtons
    wipe(shown)
    for _, tracker in ipairs(Rules.TRACKERS) do
        local key = tracker.key
        if self.active[key] then
            local btn = self:GetButton(tracker)
            local started, length = self.startedAt[key], self.lengths[key]
            if Rules.Remaining(now, started, length) then
                if btn.appliedStart ~= started then
                    btn.cooldown:SetCooldown(started, length)
                    btn.appliedStart = started
                end
                btn.icon:SetDesaturated(true)
                shown[#shown + 1] = btn
            else
                if btn.appliedStart then
                    btn.cooldown:Clear()
                    btn.appliedStart = nil
                end
                btn.icon:SetDesaturated(false)
                if db.ShowWhenReady then
                    shown[#shown + 1] = btn
                else
                    btn:Hide()
                end
            end
        elseif self.buttons[key] then
            self.buttons[key]:Hide()
        end
    end
    self:LayoutIcons(shown, #self.activeList)
    if #shown > 0 then self.frame:Show() else self.frame:Hide() end
end

-- Returns whether a clock is running. Every value here is a number this
-- module computed, never a secret, so the changed-text gate is safe.
function SPC:RenderText(now)
    local db = self.db
    local count, running = 0, false
    for _, key in ipairs(self.activeList) do
        local rem = Rules.Remaining(now, self.startedAt[key], self.lengths[key])
        local line
        if rem then
            running = true
            line = self.linePrefix[key] .. Rules.FormatTime(rem) .. "|r"
        elseif db.ShowWhenReady then
            line = self.readyLine[key]
        end
        if line then
            count = count + 1
            local slot = self:GetSlot(count)
            if slot.lastText ~= line then
                slot.text:SetText(line)
                slot.lastText = line
            end
        end
    end
    if count ~= self.layoutCount then
        self:LayoutSlots(count)
        if count > 0 then self.frame:Show() else self.frame:Hide() end
        self:NotifyAttach()
    end
    return running
end

function SPC:Render()
    if self.isPreview or not self.frame then return end
    local db = self.db
    if not self.live or (db.HideOutOfCombat and not UnitAffectingCombat("player")) then
        self.frame:Hide()
        self.layoutCount = nil
        self:NotifyAttach()
        self:StopTicker()
        return
    end
    local now = GetTime()
    if db.DisplayMode == "ICONS" then
        self:RenderIcons(now)
        self:StopTicker()
    elseif self:RenderText(now) then
        self:StartTicker()
    else
        self:StopTicker()
    end
end

---------------------------------------------------------------------------------
-- Clocks
---------------------------------------------------------------------------------
function SPC:ClearClock(key)
    local timer = self.readyTimers[key]
    if timer then timer:Cancel() end
    self.readyTimers[key] = nil
    self.startedAt[key] = nil
    self.lengths[key] = nil
end

function SPC:OnReady(key)
    if not self:IsEnabled() then return end
    self:ClearClock(key)
    local db = self.db
    -- Plays while Hide Out of Combat hides the display too: the sound is its
    -- own opt-in.
    if db.SoundEnabled and db.Sound and db.Sound ~= "None" and KE.LSM then
        local path = KE.LSM:Fetch("sound", db.Sound, true)
        if path then pcall(PlaySoundFile, path, "Master") end
    end
    self:Render()
end

function SPC:OnCooldownPing(_, spellID, baseSpellID)
    local spellSecret, baseSecret = KE:IsSecretValue(spellID), KE:IsSecretValue(baseSpellID)
    local key = Rules.TrackerForPing(spellID, spellSecret, baseSpellID, baseSecret)
    if not key then
        if DEBUG_SPC and (spellSecret or baseSecret) then KE:Print("[SPC] ignored: secret id") end
        return
    end
    if not self.active[key] then
        if DEBUG_SPC then KE:Print("[SPC] " .. key .. " ignored: tracker inactive") end
        return
    end
    local now = GetTime()
    if not Rules.AcceptPing(now, self.ignoreUntil, self.startedAt[key], self.lengths[key]) then
        if DEBUG_SPC then
            local reason = self.ignoreUntil and now < self.ignoreUntil and "zone-in window" or "already counting"
            KE:Print("[SPC] " .. key .. " ignored: " .. reason)
        end
        return
    end
    local length = LengthNow(key, self.hasHarmony)
    self:ClearClock(key)
    self.startedAt[key], self.lengths[key] = now, length
    self.readyTimers[key] = C_Timer.NewTimer(length, function() self:OnReady(key) end)
    if DEBUG_SPC then KE:Print(("[SPC] %s started, %d s"):format(key, length)) end
    self:Render()
end

-- Clocks keep running across a zone change; only the re-announce burst is
-- ignored. With nothing live it re-reads talents, since at a cold login both
-- enable-time reads can land before talents are readable.
function SPC:OnEnteringWorld()
    self.ignoreUntil = GetTime() + Rules.ZONE_IN_IGNORE
    if not self.live then self:OnTalentChanged() end
end

---------------------------------------------------------------------------------
-- Activation
---------------------------------------------------------------------------------
function SPC:SyncCombatEvents()
    local want = self.live and self.db.HideOutOfCombat == true
    if want == self.combatEvents then return end
    self.combatEvents = want
    if want then
        self:RegisterEvent("PLAYER_REGEN_DISABLED", "Render")
        self:RegisterEvent("PLAYER_REGEN_ENABLED", "Render")
    else
        self:UnregisterEvent("PLAYER_REGEN_DISABLED")
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
end

-- Live = a tracker is active. Turning on opens the ignore window too, since
-- the cooldown event can be registered in the middle of a login burst.
function SPC:SetLive(on)
    if on ~= self.live then
        self.live = on
        if on then
            self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "OnCooldownPing")
            self.ignoreUntil = GetTime() + Rules.ZONE_IN_IGNORE
        else
            self:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
        end
    end
    self:SyncCombatEvents()
end

function SPC:Evaluate()
    if not self:IsEnabled() then return end
    local _, class = UnitClass("player")
    local list = Rules.ActiveTrackers(class, self.db, IsKnown)
    self.activeList = list
    wipe(self.active)
    for _, key in ipairs(list) do self.active[key] = true end
    self.hasHarmony = IsKnown(Rules.NATURAL_HARMONY) == true
    for _, tracker in ipairs(Rules.TRACKERS) do
        if not self.active[tracker.key] then self:ClearClock(tracker.key) end
    end

    if #list > 0 then
        self:CreateFrame_()
        self:SetLive(true)
        self:ApplyStyle()
        self:ApplyPosition()
        self:RegisterAnchor()
    else
        self:SetLive(false)
        self:StopTicker()
        if self.frame and not self.isPreview then
            self.frame:Hide()
            self:ApplyPosition()
            self:UnregisterAnchor()
        end
    end
    self:Render()
end

function SPC:OnTalentChanged()
    C_Timer.After(TALENT_EVAL_DELAY, DeferredEvaluate)
end

function SPC:OnSpecChanged(_, unit)
    if Rules.IsOwnSpecChange(unit, KE:IsSecretValue(unit)) then
        self:OnTalentChanged()
    end
end

function SPC:ApplySettings()
    self:UpdateDB()
    if self.db.Enabled then
        if not self:IsEnabled() then
            KitnEssentials:EnableModule("ShamanProcCooldowns")
        elseif self.isPreview then
            -- Render returns early while previewing, so repaint the preview.
            self:ShowPreview()
        else
            self:Evaluate()
        end
    elseif self:IsEnabled() then
        KitnEssentials:DisableModule("ShamanProcCooldowns")
    end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function SPC:OnEnable()
    self:UpdateDB()
    -- Class before anything else: a non-Shaman gets no events, frame or mover.
    local _, class = UnitClass("player")
    if class ~= "SHAMAN" then return end

    self:RegisterEvent("PLAYER_TALENT_UPDATE", "OnTalentChanged")
    self:RegisterEvent("TRAIT_CONFIG_UPDATED", "OnTalentChanged")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnSpecChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnteringWorld")
    self:Evaluate()
    -- At login the talents may not be readable yet; a second pass catches them.
    self:OnTalentChanged()
end

function SPC:OnDisable()
    self:UnregisterAllEvents()
    self.live, self.combatEvents = false, false
    for _, tracker in ipairs(Rules.TRACKERS) do self:ClearClock(tracker.key) end
    self:StopTicker()
    wipe(self.active)
    self.activeList = {}
    if self.frame then self.frame:Hide() end
    local cm = KitnEssentials:GetModule("CombatTexts", true)
    if cm then cm:SetAttachedFrame(ATTACH_KEY, nil) end
    self.attached = false
    self.isPreview = false
    self.layoutCount = nil
    self:UnregisterAnchor()
    self:UpdateAttachSubscription()
end

---------------------------------------------------------------------------------
-- Preview (PreviewManager contract)
---------------------------------------------------------------------------------
-- A placement sample: it ignores talents, boxes, Show When Ready and Hide Out
-- of Combat.
function SPC:ShowPreview()
    self:UpdateDB()
    self:CreateFrame_()
    self.isPreview = true
    self:StopTicker()
    self:ApplyStyle()
    self:ApplyPosition()

    if self.db.DisplayMode == "ICONS" then
        local shown = self.shownButtons
        wipe(shown)
        for i, tracker in ipairs(Rules.TRACKERS) do
            local btn = self:GetButton(tracker)
            if i == 1 then
                btn.cooldown:SetCooldown(GetTime() - PREVIEW_ELAPSED, PREVIEW_LENGTH)
                btn.appliedStart = PREVIEW_START
                btn.icon:SetDesaturated(true)
            else
                btn.cooldown:Clear()
                btn.appliedStart = nil
                btn.icon:SetDesaturated(false)
            end
            shown[#shown + 1] = btn
        end
        self:LayoutIcons(shown, #shown)
    else
        local counting = self.linePrefix.NaturesGuardian
            .. Rules.FormatTime(PREVIEW_LENGTH - PREVIEW_ELAPSED) .. "|r"
        local ready = self.readyLine.ThunderousPaws
        local first, second = self:GetSlot(1), self:GetSlot(2)
        first.text:SetText(counting)
        first.lastText = counting
        second.text:SetText(ready)
        second.lastText = ready
        self:LayoutSlots(2)
    end

    self.frame:Show()
    self:NotifyAttach()
    self:RegisterAnchor()
end

-- Also called on a disabled module during section changes, so every path is
-- safe without a live display. Enabled, it always re-evaluates: settings
-- changed during the preview only repainted the sample, and a tracker ticked
-- back on from none active must start listening here.
function SPC:HidePreview()
    self.isPreview = false
    if self:IsEnabled() then
        self:Evaluate()
        return
    end
    if not self.frame then return end
    self.frame:Hide()
    self:ApplyPosition()
    self:UnregisterAnchor()
end

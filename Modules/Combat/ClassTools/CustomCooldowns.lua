-- ╔══════════════════════════════════════════════════════════╗
-- ║  CustomCooldowns.lua                                     ║
-- ║  Module: Custom Cooldowns                                ║
-- ║  Purpose: Shows the cooldowns of spells the player adds  ║
-- ║         for a class or one spec, as text lines.        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class CustomCooldowns: AceModule, AceEvent-3.0
---@field editModeRegistered boolean? true while the EditMode element is registered; nil after UnregisterAnchor
local CCD = KitnEssentials:NewModule("CustomCooldowns", "AceEvent-3.0")

-- The cooldown readers are No Movement Alert's, so their secret rules live in
-- one place. They answer whether that module is on or off; its file loads first.
---@type NoMovementAlert
local NMA = KitnEssentials:GetModule("NoMovementAlert", true)
local Rules = KE.CustomCooldownsRules

local C_Spell = C_Spell
local C_Timer = C_Timer
local UnitClass, UnitAffectingCombat = UnitClass, UnitAffectingCombat
local ipairs, pcall, tostring, type, wipe = ipairs, pcall, tostring, type, wipe
local string_format = string.format
local math_max, math_min = math.max, math.min
-- Absent only if that file failed to load; every line, the preview's
-- included, then goes unescaped.
local EscapePipes = NMA and NMA.EscapePipes or tostring
local EscapeFormat = NMA and NMA.EscapeFormat or tostring

local ATTACH_KEY = "customCooldowns"
local TICK_SECONDS = 0.1
local DISPLAY_REFRESH_CAP = 0.1
local SPEC_SETTLE_DELAY = 2
-- One charge reads as a plain cooldown: its charge record says it is not
-- recharging while the spell cooldown runs.
local MIN_CHARGES = 2

local PREVIEW_SAMPLES = {
    { name = "Spell Reflection", remain = 18 },
    { name = "Shield Wall", remain = 95 },
}

------------------------------------------------------------------------
-- Spell reads
------------------------------------------------------------------------
local function SpellKnown(spellId)
    if not (C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook) then return false end
    local ok, known = pcall(C_SpellBook.IsSpellKnownOrInSpellBook, spellId,
        Enum.SpellBookSpellBank.Player, true)
    return ok and known == true
end

local function SpellInfo(spellId)
    if not (C_Spell and C_Spell.GetSpellInfo) then return nil end
    local ok, info = pcall(C_Spell.GetSpellInfo, spellId)
    if ok and type(info) == "table" and info.name then return info end
    return nil
end

-- maxCharges is never secret; it changes only with talents, which rebuild the list.
local function IsChargeSpell(spellId)
    if not (C_Spell and C_Spell.GetSpellCharges) then return false end
    local ok, info = pcall(C_Spell.GetSpellCharges, spellId)
    if not ok or type(info) ~= "table" then return false end
    local max = info.maxCharges
    if KE:IsSecretValue(max) or type(max) ~= "number" then return false end
    return max >= MIN_CHARGES
end

local function ReadPlain(spellId)
    if not NMA then return nil end
    return NMA:ReadCooldown(spellId)
end

local function ReadCharge(spellId)
    if not NMA then return nil end
    return NMA:ReadChargeCooldown(spellId)
end

------------------------------------------------------------------------
-- Display frame + pooled slots
------------------------------------------------------------------------
function CCD:UpdateDB()
    self.db = KE.db.profile.CustomCooldowns
end

function CCD:OnInitialize()
    self:UpdateDB()
    self.slots = {}
    self.tracked = {}
    self.slotAlphas = {}
    self.readyFired = {}
    -- Lines laid out by the last layout; nil means a layout is due.
    self.laidOut = nil
    self.isPreview = false
    -- Starts false, not nil, so the first placement is not read as a change.
    self.attached = false
    self:SetEnabledState(false)
end

function CCD:CreateFrame_()
    if self.frame then return end
    local frame = CreateFrame("Frame", "KE_CustomCooldowns", UIParent)
    frame:SetSize(220, 40)
    frame:Hide()
    self.frame = frame
    -- Attached, the login anchor pass must not put the frame back on its own
    -- Player Frame position.
    KE:RegisterAnchorRepair(frame, function()
        return not self:IsAttached() and self.db.anchorFrameType == "PLAYERFRAME"
    end, function() self:ApplyPosition() end)
end

function CCD:GetSlot(index)
    local slot = self.slots[index]
    if slot then return slot end

    slot = CreateFrame("Frame", nil, self.frame)
    slot:SetSize(220, 30)

    slot.text = slot:CreateFontString(nil, "OVERLAY")
    slot.text:SetPoint("CENTER")

    self.slots[index] = slot
    -- Styled before returning: a FontString with no font throws on SetText.
    self:StyleSlot(slot)
    return slot
end

-- One color for every part in theme mode, the three saved ones otherwise.
function CCD:RoleColor(key)
    local db = self.db
    if db.ColorMode == "THEME" then
        local accent = KE.Theme and KE.Theme.accent
        if accent then return accent end
    end
    return db[key] or db.TextColor
end

function CCD:StyleSlot(slot)
    local face, size, outline = self:EffectiveStyle()
    local c = self:RoleColor("TextColor")
    KE:ApplyFontToText(slot.text, face, size, outline)
    slot.text:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    slot:SetSize(220, size + 6)
    -- Opaque, so a slot reused from a hidden charge line comes back visible.
    slot:SetAlpha(1)
end

function CCD:LayoutSlots(count)
    local db = self.db
    local _, _, _, effSpacing = self:EffectiveStyle()
    local spacing = effSpacing or db.Spacing or 2
    local prev
    local w, h = 0, 0
    for i = 1, count do
        local slot = self:GetSlot(i)
        self:StyleSlot(slot)
        slot:ClearAllPoints()
        if db.GrowDirection == "RIGHT" or db.GrowDirection == "LEFT" then
            local side = db.GrowDirection == "RIGHT" and "LEFT" or "RIGHT"
            local opp = db.GrowDirection == "RIGHT" and "RIGHT" or "LEFT"
            if prev then
                slot:SetPoint(side, prev, opp, db.GrowDirection == "RIGHT" and spacing or -spacing, 0)
            else
                slot:SetPoint(side, self.frame, side, 0, 0)
            end
            w = w + slot:GetWidth() + spacing
            h = math_max(h, slot:GetHeight())
        else
            local side = db.GrowDirection == "UP" and "BOTTOM" or "TOP"
            local opp = db.GrowDirection == "UP" and "TOP" or "BOTTOM"
            if prev then
                slot:SetPoint(side, prev, opp, 0, db.GrowDirection == "UP" and spacing or -spacing)
            else
                slot:SetPoint(side, self.frame, side, 0, 0)
            end
            h = h + slot:GetHeight() + spacing
            w = math_max(w, slot:GetWidth())
        end
        slot:Show()
        prev = slot
    end
    for i = count + 1, #self.slots do
        self.slots[i]:Hide()
    end
    if count > 0 then
        -- The loop adds a gap after every slot; the last one has none below it.
        if db.GrowDirection == "RIGHT" or db.GrowDirection == "LEFT" then
            w = w - spacing
        else
            h = h - spacing
        end
        self.frame:SetSize(math_max(w, 1), math_max(h, 1))
    end
end

------------------------------------------------------------------------
-- Lines
------------------------------------------------------------------------
local function Code(c)
    return KE:ColorCode(c[1], c[2], c[3])
end

function CCD:Separator()
    local sep = self.db.Separator
    if sep == nil or sep == "" then sep = "-" end
    return sep
end

-- A line with a printf slot for the time, so a secret number is drawn by
-- SetFormattedText without being read. Built by concatenation, not
-- string.format: the result is itself a format string, so its slot must
-- survive and a literal % or pipe in the name or separator is escaped.
function CCD:ComposeFormat(name)
    return Code(self:RoleColor("TextColor")) .. EscapeFormat(name) .. "|r "
        .. Code(self:RoleColor("SeparatorColor")) .. EscapeFormat(self:Separator()) .. "|r "
        .. Code(self:RoleColor("TimerColor")) .. "%.0f|r"
end

function CCD:ComposeLine(name, timeText)
    local nameCode = Code(self:RoleColor("TextColor"))
    name = EscapePipes(name)
    if not timeText then
        return string_format("%s%s|r", nameCode, name)
    end
    return string_format("%s%s|r %s%s|r %s%s|r", nameCode, name,
        Code(self:RoleColor("SeparatorColor")), EscapePipes(self:Separator()),
        Code(self:RoleColor("TimerColor")), timeText)
end

function CCD:PlayReadySound()
    local db = self.db
    if not (db.SoundEnabled and db.Sound and db.Sound ~= "None" and KE.LSM) then return end
    local path = KE.LSM:Fetch("sound", db.Sound, true)
    if path then pcall(PlaySoundFile, path, "Master") end
end

------------------------------------------------------------------------
-- Tracked list and update loop
------------------------------------------------------------------------
function CCD:BuildTracked()
    local _, class = UnitClass("player")
    local ids = Rules.ResolveList(self.db.Spells, class, KE:GetPlayerSpecId(), SpellKnown)
    local out = {}
    for i = 1, #ids do
        local id = ids[i]
        local info = SpellInfo(id)
        if info then
            out[#out + 1] = { spellId = id, name = info.name, isCharge = IsChargeSpell(id) }
        end
    end
    self.tracked = out
end

function CCD:StartTicker()
    if self.ticker then return end
    self.ticker = C_Timer.NewTicker(TICK_SECONDS, function() self:Update() end)
end

function CCD:StopTicker()
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
end

-- Returns whether any line counts. A secret read counts: nothing about it can
-- be checked, and the ticker is what redraws it.
function CCD:Update()
    if self.isPreview then return end
    local db = self.db
    if not db or not db.Enabled or not self.frame then return end

    if db.HideOutOfCombat and not UnitAffectingCombat("player") then
        self.frame:Hide()
        self:NotifyAttach()
        self:StopTicker()
        return
    end

    local shown, anyRunning = 0, false
    local alphas = self.slotAlphas
    wipe(alphas)

    for _, entry in ipairs(self.tracked) do
        local plainLine, fmtLine, fmtValue
        local rem, isSecret, alpha
        if entry.isCharge then
            local r, _, s, a = ReadCharge(entry.spellId)
            rem, isSecret, alpha = r, s, a
        else
            local r, _, s = ReadPlain(entry.spellId)
            rem, isSecret = r, s
        end
        -- A secret alpha is truthy, so this keeps it; it goes only to SetAlpha.
        alpha = alpha or 1

        if isSecret then
            anyRunning = true
            -- A charge spell's duration object answers even with a charge banked,
            -- so a secret read does not mean a cooldown ran.
            if not entry.isCharge then self.readyFired[entry.spellId] = true end
            -- type() never throws on a secret; ~= nil is a comparison.
            if type(rem) ~= "nil" then
                fmtLine, fmtValue = self:ComposeFormat(entry.name), rem
            else
                plainLine = self:ComposeLine(entry.name, "...")
            end
        elseif rem then
            anyRunning = true
            self.readyFired[entry.spellId] = true
            ---@cast rem number
            plainLine = self:ComposeLine(entry.name, KE:FormatCountdown(rem))
        else
            if self.readyFired[entry.spellId] then
                self.readyFired[entry.spellId] = nil
                self:PlayReadySound()
            end
            if db.ShowWhenReady then plainLine = self:ComposeLine(entry.name, nil) end
        end

        if plainLine or fmtLine then
            shown = shown + 1
            local text = self:GetSlot(shown).text
            if fmtLine then
                text:SetFormattedText(fmtLine, fmtValue)
            else
                text:SetText(plainLine)
            end
            alphas[shown] = alpha
        end
    end

    if shown > 0 then
        -- A slot's size follows the font, never the text, so only a new line
        -- count or a settings change needs a layout.
        if self.laidOut ~= shown then
            self:LayoutSlots(shown)
            self.laidOut = shown
            if not self.attached then self:ApplyPosition() end
        end
        for i = 1, shown do
            self.slots[i]:SetAlpha(alphas[i])
        end
        self.frame:Show()
    else
        self.frame:Hide()
    end
    self:NotifyAttach()

    if not anyRunning then self:StopTicker() end
    return anyRunning
end

function CCD:Refresh()
    if self.isPreview then return end
    self:BuildTracked()
    if self:Update() then self:StartTicker() end
end

-- Cooldown and charge events change what a spell is doing, never which spells
-- are listed, so they only redraw, at most once per cap with a trailing flush.
local flushDisplayRefresh = function()
    CCD._displayCapped = false
    if CCD._displayPending then
        CCD._displayPending = false
        CCD:RefreshDisplay()
    end
end

function CCD:RefreshDisplay()
    if self.isPreview or not self:IsEnabled() then return end
    if self._displayCapped then
        self._displayPending = true
        return
    end
    self._displayCapped = true
    if self:Update() then self:StartTicker() end
    C_Timer.After(DISPLAY_REFRESH_CAP, flushDisplayRefresh)
end

-- Talent and spec state is not reliable immediately on these events.
function CCD:OnSpecChanged()
    C_Timer.After(SPEC_SETTLE_DELAY, function()
        if self:IsEnabled() then self:Refresh() end
    end)
end

------------------------------------------------------------------------
-- Combat Texts attach
------------------------------------------------------------------------
function CCD:IsAttached()
    local cm = KitnEssentials:GetModule("CombatTexts", true)
    return cm ~= nil and self.db ~= nil and cm:TakesAttached(ATTACH_KEY, self.frame, self.db.AttachToCombatTexts == true)
end

function CCD:NotifyAttach()
    if not self.attached then return end
    local cm = KitnEssentials:GetModule("CombatTexts", true)
    if cm then cm:AttachedFrameChanged(ATTACH_KEY) end
end

function CCD:UpdateAttachSubscription()
    local cm = KitnEssentials:GetModule("CombatTexts", true)
    if cm then cm:SyncAttachSubscription(self, self:IsEnabled() or self.isPreview) end
end

-- Attached, the lines take the Combat Texts font, size and spacing, so they
-- match the messages they sit under.
function CCD:EffectiveStyle()
    local db = self.db
    if self.attached then
        local cm = KitnEssentials:GetModule("CombatTexts", true)
        local c = cm and cm.db
        if c then
            local size = cm.ResolveAttachedSize(true, db.AttachOwnFontSize, db.FontSize, c.FontSize)
            return c.FontFace or db.FontFace, size,
                   c.FontOutline or db.FontOutline, c.Spacing or db.Spacing, 1
        end
    end
    return db.FontFace, db.FontSize, db.FontOutline, db.Spacing, db.Scale or 1
end

function CCD:ApplyPosition()
    local db, frame = self.db, self.frame
    if not frame or not db then return end

    local cm = KitnEssentials:GetModule("CombatTexts", true)
    local wasAttached = self.attached
    self.attached = (self:IsEnabled() or self.isPreview) and cm ~= nil and self:IsAttached()
        and cm:SetAttachedFrame(ATTACH_KEY, frame) or false
    if not self.attached then
        if cm then cm:SetAttachedFrame(ATTACH_KEY, nil) end
        KE:ApplyFramePosition(frame, db.Position, db)
    end
    local _, _, _, _, scale = self:EffectiveStyle()
    frame:SetScale(scale)
    self:UpdateAttachSubscription()
    if wasAttached ~= self.attached then
        -- The style follows the attachment.
        self.laidOut = nil
        if self:IsEnabled() or self.isPreview then self:RegisterAnchor() end
    end
end

function CCD:ApplySettings()
    self:UpdateDB()
    if self.db and self.db.Enabled then
        if not self:IsEnabled() then
            KitnEssentials:EnableModule("CustomCooldowns")
        elseif self.isPreview then
            -- Refresh and Update both return while previewing.
            self:ShowPreview()
        else
            self.laidOut = nil
            self:ApplyPosition()
            self:Refresh()
        end
    elseif self:IsEnabled() then
        KitnEssentials:DisableModule("CustomCooldowns")
    end
end

------------------------------------------------------------------------
-- Edit Mode
------------------------------------------------------------------------
local EDIT_MODE_ELEMENT = {
    key = "CustomCooldowns",
    displayName = "Custom Cooldowns",
    guiPath = "ClassTools",
    guiTab = "CustomCooldowns",
}

-- Every unregister goes through here, so the cache that makes a repeat
-- RegisterAnchor a no-op is cleared with the key.
function CCD:UnregisterAnchor()
    KE.EditMode:UnregisterElement("CustomCooldowns")
    self.editModeRegistered = nil
    self.editModeFrame = nil
end

function CCD:RegisterAnchor()
    -- Attached, Combat Texts owns the position; a second mover would fight it.
    if self:IsAttached() then
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
    cfg.getParentFrame = function()
        return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)
    end
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

------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------
function CCD:OnEnable()
    self:UpdateDB()
    self:CreateFrame_()
    self:ApplyPosition()

    self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "RefreshDisplay")
    self:RegisterEvent("SPELL_UPDATE_CHARGES", "RefreshDisplay")
    KE.Context:SubscribeSpec("CustomCooldowns", function() self:OnSpecChanged() end)
    self:RegisterEvent("PLAYER_TALENT_UPDATE", "OnSpecChanged")
    self:RegisterEvent("TRAIT_CONFIG_UPDATED", "OnSpecChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnSpecChanged")
    -- Combat transitions change what Hide Out of Combat shows.
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "Refresh")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "Refresh")

    self:Refresh()
    self:RegisterAnchor()
end

function CCD:OnDisable()
    KE.Context:UnsubscribeSpec("CustomCooldowns")
    self:UnregisterAllEvents()
    self:StopTicker()
    if self.frame then self.frame:Hide() end
    local cm = KitnEssentials:GetModule("CombatTexts", true)
    if cm then cm:SetAttachedFrame(ATTACH_KEY, nil) end
    self.attached = false
    self.laidOut = nil
    self.tracked = {}
    wipe(self.readyFired)
    self.isPreview = false
    self:UnregisterAnchor()
    self:UpdateAttachSubscription()
end

------------------------------------------------------------------------
-- Preview (PreviewManager contract)
------------------------------------------------------------------------
function CCD:ShowPreview()
    self:UpdateDB()
    self:CreateFrame_()
    self.isPreview = true
    self:StopTicker()

    local count = math_min(#PREVIEW_SAMPLES, math_max(1, self.db.PreviewCount or 2))
    for i = 1, count do
        local s = PREVIEW_SAMPLES[i]
        self:GetSlot(i).text:SetText(self:ComposeLine(s.name, KE:FormatCountdown(s.remain)))
    end
    local wasAttached = self.attached
    self:LayoutSlots(count)
    self:ApplyPosition()
    -- The style follows the placement; a preview that just changed it is laid
    -- out and placed again with the matching font.
    if self.attached ~= wasAttached then
        self:LayoutSlots(count)
        self:ApplyPosition()
    end
    self.laidOut = nil
    self.frame:Show()
    self:NotifyAttach()
    self:RegisterAnchor()
end

function CCD:HidePreview()
    self.isPreview = false
    if not self.frame then return end
    self.laidOut = nil
    if self.db and self.db.Enabled and self:IsEnabled() then
        self:Refresh()
    else
        self.frame:Hide()
        self:NotifyAttach()
        self:UnregisterAnchor()
        self:UpdateAttachSubscription()
    end
end

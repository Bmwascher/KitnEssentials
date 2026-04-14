-- ╔══════════════════════════════════════════════════════════╗
-- ║  CombatTexts.lua                                         ║
-- ║  Module: Combat Texts                                    ║
-- ║  Purpose: Floating text notifications for combat enter/  ║
-- ║           exit, interrupt announce with spell icon,      ║
-- ║           and low durability warnings.                   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class CombatTexts: AceModule, AceEvent-3.0
local CM = KitnEssentials:NewModule("CombatTexts", "AceEvent-3.0")

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local UIFrameFadeRemoveFrame = UIFrameFadeRemoveFrame
local UIFrameFadeOut = UIFrameFadeOut
local InCombatLockdown = InCombatLockdown
local UnitExists = UnitExists
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local GetInventoryItemDurability = GetInventoryItemDurability
local C_Spell_GetSpellInfo = C_Spell.GetSpellInfo
local GetSpecialization = C_SpecializationInfo.GetSpecialization or GetSpecialization
local GetSpecializationInfo = C_SpecializationInfo.GetSpecializationInfo
local issecretvalue = issecretvalue
local ipairs, pairs = ipairs, pairs
local math_max = math.max
local string_format = string.format

local EQUIP_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }

local SPEC_INTERRUPTS = {
    -- Warrior
    [71]   = { [6552] = true },                                         -- Arms: Pummel
    [72]   = { [6552] = true },                                         -- Fury: Pummel
    [73]   = { [6552] = true, [386071] = true },                        -- Prot: Pummel + Disrupting Shout
    -- Rogue
    [259]  = { [1766] = true },                                         -- Assassination: Kick
    [260]  = { [1766] = true },                                         -- Outlaw: Kick
    [261]  = { [1766] = true },                                         -- Subtlety: Kick
    -- Mage
    [62]   = { [2139] = true },                                         -- Arcane: Counterspell
    [63]   = { [2139] = true },                                         -- Fire: Counterspell
    [64]   = { [2139] = true },                                         -- Frost: Counterspell
    -- Shaman
    [262]  = { [57994] = true },                                        -- Elemental: Wind Shear
    [263]  = { [57994] = true },                                        -- Enhancement: Wind Shear
    [264]  = { [57994] = true },                                        -- Restoration: Wind Shear
    -- Druid
    [102]  = { [78675] = true },                                        -- Balance: Solar Beam
    [103]  = { [106839] = true },                                       -- Feral: Skull Bash
    [104]  = { [106839] = true },                                       -- Guardian: Skull Bash
    -- Death Knight
    [250]  = { [47528] = true },                                        -- Blood: Mind Freeze
    [251]  = { [47528] = true },                                        -- Frost: Mind Freeze
    [252]  = { [47528] = true },                                        -- Unholy: Mind Freeze
    -- Paladin
    [66]   = { [96231] = true, [375576] = true, [31935] = true },       -- Prot: Rebuke + Divine Toll + Avenger's Shield
    [70]   = { [96231] = true },                                        -- Retribution: Rebuke
    -- Demon Hunter
    [577]  = { [183752] = true },                                       -- Havoc: Disrupt
    [581]  = { [183752] = true },                                       -- Vengeance: Disrupt
    [1480] = { [183752] = true },                                       -- Devourer: Disrupt
    -- Monk
    [268]  = { [116705] = true },                                       -- Brewmaster: Spear Hand Strike
    [269]  = { [116705] = true },                                       -- Windwalker: Spear Hand Strike
    -- Priest
    [258]  = { [15487] = true },                                        -- Shadow: Silence
    -- Hunter
    [253]  = { [147362] = true },                                       -- Beast Mastery: Counter Shot
    [254]  = { [147362] = true },                                       -- Marksmanship: Counter Shot
    [255]  = { [187707] = true },                                       -- Survival: Muzzle
    -- Warlock (pet interrupts)
    [265]  = { [19647] = true, [119910] = true, [132409] = true },      -- Affliction: Spell Lock variants
    [266]  = { [19647] = true, [119910] = true, [119914] = true },      -- Demonology: Spell Lock + Felstorm
    [267]  = { [19647] = true, [119910] = true, [132409] = true },      -- Destruction: Spell Lock variants
    -- Evoker
    [1467] = { [351338] = true },                                       -- Devastation: Quell
    [1473] = { [351338] = true },                                       -- Augmentation: Quell
}

local MESSAGE_TYPES = {
    "enterCombat",
    "exitCombat",
    "noTarget",
    "lowDurability",
    "interrupt",
}

CM.container = nil
CM.messageFrames = {}
CM.activeMessages = {}
CM.isPreview = false
CM.inCombat = false
CM.noTargetCheckGeneration = 0
CM.interruptFlag = false
CM.interruptTimer = nil
CM.currentInterrupts = nil

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function CM:UpdateDB()
    self.db = KE.db.profile.CombatTexts
end

function CM:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

local function GetMessageConfig(db, msgType)
    if msgType == "enterCombat" then
        return db.EnterEnabled ~= false,
            db.EnterCombatText or "+ Combat",
            db.EnterColor or { 1, 0.1, 0.1, 1 }
    elseif msgType == "exitCombat" then
        return db.ExitEnabled ~= false,
            db.ExitCombatText or "- Combat",
            db.ExitColor or { 0.1, 1, 0.1, 1 }
    elseif msgType == "noTarget" then
        return db.NoTargetEnabled == true,
            db.NoTargetText or "NO TARGET",
            db.NoTargetColor or { 1, 0.8, 0, 1 }
    elseif msgType == "lowDurability" then
        return db.DurabilityEnabled ~= false,
            db.DurabilityText or "LOW DURABILITY",
            db.DurabilityColor or { 1, 0.3, 0.3, 1 }
    elseif msgType == "interrupt" then
        return db.InterruptEnabled ~= false,
            (db.InterruptText or "Interrupted") .. " [Spell Name]",
            db.InterruptColor or { 1, 1, 1, 1 }
    end
    return false, "", { 1, 1, 1, 1 }
end

---------------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------------
function CM:CreateContainer()
    if self.container then return end

    local container = CreateFrame("Frame", "KE_CombatTextsContainer", UIParent)
    container:SetSize(200, 100)
    KE:ApplyFramePosition(container, self.db.Position, self.db)
    container:SetFrameLevel(100)

    self.container = container
end

function CM:GetMessageFrame(msgType)
    if self.messageFrames[msgType] then
        return self.messageFrames[msgType]
    end

    local frame = CreateFrame("Frame", nil, self.container)
    local fontSize = self.db.FontSize or 16
    frame:SetSize(200, fontSize + 2)
    frame:Hide()

    local text = frame:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")
    text:SetWordWrap(false)

    frame.text = text
    frame.msgType = msgType
    frame.generation = 0

    self.messageFrames[msgType] = frame

    -- Apply font — interrupt uses native OUTLINE (SOFTOUTLINE shadows too visible on white text)
    if msgType == "interrupt" then
        local outline = self.db.FontOutline
        if outline == "SOFTOUTLINE" then outline = "OUTLINE" end
        KE:ApplyFont(text, self.db.FontFace, self.db.FontSize, KE:GetFontOutline(outline))
    else
        KE:ApplyFontToText(text, self.db.FontFace, self.db.FontSize, self.db.FontOutline)
    end

    return frame
end

---------------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------------
function CM:ArrangeMessages()
    local spacing = self.db.Spacing or 4
    local yOffset = 0

    for _, msgType in ipairs(MESSAGE_TYPES) do
        local frame = self.messageFrames[msgType]
        if frame and frame:IsShown() then
            frame:ClearAllPoints()
            frame:SetPoint("TOP", self.container, "TOP", 0, -yOffset)
            yOffset = yOffset + frame:GetHeight() + spacing
        end
    end

    if self.container then
        self.container:SetHeight(math_max(30, yOffset - spacing))
    end
end

---------------------------------------------------------------------------------
-- Core Logic
---------------------------------------------------------------------------------
function CM:ShowFlashMessage(msgType, textOverride)
    if not self.db or self.db.Enabled == false then return end
    if self.isPreview then return end

    local enabled, msgText, color = GetMessageConfig(self.db, msgType)
    if not enabled then return end
    if textOverride then msgText = textOverride end

    local frame = self:GetMessageFrame(msgType)
    if not frame then return end

    local duration
    if msgType == "enterCombat" or msgType == "exitCombat" then
        duration = self.db.CombatDuration or 1.5
    elseif msgType == "interrupt" then
        duration = self.db.InterruptDuration or 3.0
    else
        duration = 1.5
    end
    frame.generation = frame.generation + 1
    local myGeneration = frame.generation

    -- Stop any existing fade
    if UIFrameFadeRemoveFrame then
        UIFrameFadeRemoveFrame(frame)
    end
    frame:SetScript("OnUpdate", nil)

    -- Set text and color
    frame.text:SetText(msgText)
    frame.text:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)

    -- Show and arrange
    frame:SetAlpha(1)
    frame:Show()
    self.activeMessages[msgType] = true
    self:ArrangeMessages()

    -- Fade out and hide
    local function HideIfCurrent()
        if frame.generation == myGeneration and not self.isPreview then
            frame:Hide()
            self.activeMessages[msgType] = nil
            self:ArrangeMessages()
        end
    end

    -- Timer-based hide (avoid UIFrameFadeOut — causes stack overflow with soft outline hooks)
    C_Timer.After(duration, HideIfCurrent)
end

function CM:ShowPersistentMessage(msgType)
    if not self.db or self.db.Enabled == false then return end
    if self.isPreview then return end

    local enabled, msgText, color = GetMessageConfig(self.db, msgType)
    if not enabled then return end

    local frame = self:GetMessageFrame(msgType)
    if not frame then return end

    -- Stop any existing fade
    if UIFrameFadeRemoveFrame then
        UIFrameFadeRemoveFrame(frame)
    end
    frame:SetScript("OnUpdate", nil)

    frame.text:SetText(msgText)
    frame.text:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)

    frame:SetAlpha(1)
    frame:Show()
    self.activeMessages[msgType] = true
    self:ArrangeMessages()
end

function CM:HidePersistentMessage(msgType)
    local frame = self.messageFrames[msgType]
    if frame then
        frame:Hide()
        self.activeMessages[msgType] = nil
        self:ArrangeMessages()
    end
end

---------------------------------------------------------------------------------
-- No Target Warning
---------------------------------------------------------------------------------
function CM:CheckNoTarget()
    if not self.db or self.db.Enabled == false then return end
    if self.isPreview then return end

    if UnitIsDeadOrGhost("player") then
        self:HidePersistentMessage("noTarget")
        return
    end

    if self.inCombat and self.db.NoTargetEnabled then
        self.noTargetCheckGeneration = self.noTargetCheckGeneration + 1
        local myGeneration = self.noTargetCheckGeneration

        C_Timer.After(0.1, function()
            if self.noTargetCheckGeneration ~= myGeneration then return end
            if not self.inCombat then return end
            if UnitIsDeadOrGhost("player") then
                self:HidePersistentMessage("noTarget")
                return
            end
            if not UnitExists("target") then
                self:ShowPersistentMessage("noTarget")
            else
                self:HidePersistentMessage("noTarget")
            end
        end)
    else
        self:HidePersistentMessage("noTarget")
    end
end

---------------------------------------------------------------------------------
-- Event Handlers
---------------------------------------------------------------------------------
function CM:OnEnterCombat()
    self.inCombat = true
    self:HidePersistentMessage("lowDurability")
    self:ShowFlashMessage("enterCombat")
    self:CheckNoTarget()
end

function CM:OnExitCombat()
    self.inCombat = false
    self.noTargetCheckGeneration = self.noTargetCheckGeneration + 1
    self:HidePersistentMessage("noTarget")
    self:ShowFlashMessage("exitCombat")
    self:CheckDurability()
end

function CM:OnTargetChanged()
    self:CheckNoTarget()
end

function CM:OnPlayerDead()
    self.noTargetCheckGeneration = self.noTargetCheckGeneration + 1
    self:HidePersistentMessage("noTarget")
end

function CM:CheckDurability()
    if not self.db or self.db.Enabled == false then return end
    if self.isPreview then return end

    if self.db.DurabilityEnabled == false then
        self:HidePersistentMessage("lowDurability")
        return
    end

    local threshold = (self.db.DurabilityThreshold or 25) / 100

    if self.inCombat then
        self:HidePersistentMessage("lowDurability")
        return
    end

    local hasLow = false
    for _, slot in ipairs(EQUIP_SLOTS) do
        local current, maximum = GetInventoryItemDurability(slot)
        if current and maximum and maximum > 0 then
            if (current / maximum) < threshold then
                hasLow = true
                break
            end
        end
    end

    if hasLow then
        self:ShowPersistentMessage("lowDurability")
    else
        self:HidePersistentMessage("lowDurability")
    end
end

---------------------------------------------------------------------------------
-- Apply Settings
---------------------------------------------------------------------------------
function CM:ApplySettings()
    if not self.container then return end
    KE:ApplyFramePosition(self.container, self.db.Position, self.db)

    -- Update font settings and frame height for all message frames
    local fontSize = self.db.FontSize or 16
    for _, frame in pairs(self.messageFrames) do
        frame:SetHeight(fontSize + 2)
        if frame.text then
            if frame.msgType == "interrupt" then
                if frame.text._keSoftOutline then
                    frame.text._keSoftOutline:Release()
                end
                local outline = self.db.FontOutline
                if outline == "SOFTOUTLINE" then outline = "OUTLINE" end
                KE:ApplyFont(frame.text, self.db.FontFace, self.db.FontSize, KE:GetFontOutline(outline))
            else
                KE:ApplyFontToText(frame.text, self.db.FontFace, self.db.FontSize, self.db.FontOutline)
            end
        end
    end

    -- Update preview content if in preview mode
    if self.isPreview then
        for _, msgType in ipairs(MESSAGE_TYPES) do
            local frame = self.messageFrames[msgType]
            if frame then
                local _, msgText, msgColor = GetMessageConfig(self.db, msgType)
                frame.text:SetText(msgText)
                frame.text:SetTextColor(msgColor[1] or 1, msgColor[2] or 1, msgColor[3] or 1, msgColor[4] or 1)
            end
        end
        self:ArrangeMessages()
    else
        self:CheckNoTarget()
    end
end

function CM:ApplyPosition()
    if not self.container then return end
    KE:ApplyFramePosition(self.container, self.db.Position, self.db)
end

function CM:Refresh()
    self:ApplySettings()
end

---------------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------------
function CM:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "CombatTexts", displayName = "Combat Texts", frame = self.container,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos) self.db.Position = pos; KE:ApplyFramePosition(self.container, self.db.Position, self.db) end,
            getParentFrame = function() return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) end,
            guiPath = "CombatTexts",
        })
        self.editModeRegistered = true
    end
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------
function CM:ShowPreview()
    if not self.container then
        self:CreateContainer()
    end
    self:RegWithEditMode()

    self.isPreview = true

    for _, msgType in ipairs(MESSAGE_TYPES) do
        local frame = self:GetMessageFrame(msgType)
        if frame then
            local _, msgText, msgColor = GetMessageConfig(self.db, msgType)
            frame.text:SetText(msgText)
            frame.text:SetTextColor(msgColor[1] or 1, msgColor[2] or 1, msgColor[3] or 1, msgColor[4] or 1)
            frame:SetAlpha(1)
            frame:Show()
            self.activeMessages[msgType] = true
        end
    end

    self:ApplySettings()
    self:ArrangeMessages()
end

function CM:HidePreview()
    if not self.isPreview then return end

    self.isPreview = false

    for msgType, frame in pairs(self.messageFrames) do
        frame:Hide()
        self.activeMessages[msgType] = nil
    end

    -- Re-check actual state
    if self.inCombat then
        self:CheckNoTarget()
    end
end

---------------------------------------------------------------------------------
-- Interrupt Announce
---------------------------------------------------------------------------------
function CM:CacheInterruptSpells()
    local specIndex = GetSpecialization()
    if not specIndex then
        self.currentInterrupts = nil
        return
    end
    local specID = GetSpecializationInfo(specIndex)
    if not specID then
        self.currentInterrupts = nil
        return
    end
    self.currentInterrupts = SPEC_INTERRUPTS[specID]
end

function CM:OnSpellcastSucceeded(_, unit, _, spellID)
    if not self.db or self.db.InterruptEnabled == false then return end
    if not self.currentInterrupts then return end
    if issecretvalue(unit) then return end
    if unit ~= "player" and unit ~= "pet" then return end
    if issecretvalue(spellID) or not self.currentInterrupts[spellID] then return end

    self.interruptFlag = true
    if self.interruptTimer then
        self.interruptTimer:Cancel()
    end
    self.interruptTimer = C_Timer.NewTimer(0.1, function()
        self.interruptFlag = false
    end)
end

function CM:OnSpellcastInterrupted(_, _, _, spellID, interruptedBy)
    if not self.interruptFlag then return end
    if not interruptedBy then return end

    self.interruptFlag = false
    if self.interruptTimer then
        self.interruptTimer:Cancel()
        self.interruptTimer = nil
    end

    -- Build display: "Interrupted |Ticon|t [Spell Name]"
    -- C_Spell.GetSpellInfo accepts secret spellIDs (AllowedWhenTainted) and returns clean data
    local prefix = self.db.InterruptText or "Interrupted"
    local spellInfo = C_Spell_GetSpellInfo(spellID)
    if spellInfo and spellInfo.iconID and spellInfo.name then
        local iconSize = self.db.FontSize or 16
        local text = string_format("%s |T%d:%d|t [%s]", prefix, spellInfo.iconID, iconSize, spellInfo.name)
        self:ShowFlashMessage("interrupt", text)
    else
        self:ShowFlashMessage("interrupt")
    end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function CM:OnEnable()
    if not self.db.Enabled then return end

    self:CreateContainer()
    self:RegWithEditMode()

    -- Pre-create message frames
    for _, msgType in ipairs(MESSAGE_TYPES) do
        self:GetMessageFrame(msgType)
    end

    C_Timer.After(0.5, function()
        self:ApplySettings()
    end)

    -- Register events
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnEnterCombat")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnExitCombat")
    self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnTargetChanged")
    self:RegisterEvent("PLAYER_DEAD", "OnPlayerDead")
    self:RegisterEvent("UPDATE_INVENTORY_DURABILITY", "CheckDurability")

    -- Interrupt announce events
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnSpellcastSucceeded")
    self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", "OnSpellcastInterrupted")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP", "OnSpellcastInterrupted")
    self:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED", "CacheInterruptSpells")
    self:RegisterEvent("SPELLS_CHANGED", "CacheInterruptSpells")
    self:CacheInterruptSpells()

    -- Track initial combat state
    self.inCombat = InCombatLockdown()

    -- Initial checks (delayed to ensure frames exist)
    if self.inCombat then
        self:CheckNoTarget()
    else
        C_Timer.After(1, function() self:CheckDurability() end)
    end
end

function CM:OnDisable()
    for _, frame in pairs(self.messageFrames) do
        frame:Hide()
    end
    self.activeMessages = {}
    self.isPreview = false
    self.inCombat = false
    self.noTargetCheckGeneration = self.noTargetCheckGeneration + 1
    self.interruptFlag = false
    if self.interruptTimer then
        self.interruptTimer:Cancel()
        self.interruptTimer = nil
    end
    self.currentInterrupts = nil
    self:UnregisterAllEvents()
end

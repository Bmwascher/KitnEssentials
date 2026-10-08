-- ╔══════════════════════════════════════════════════════════╗
-- ║  CombatTexts.lua                                         ║
-- ║  Module: Combat Texts                                    ║
-- ║  Purpose: Floating text notifications for combat enter/  ║
-- ║           exit, interrupt announce with spell icon,      ║
-- ║           low durability and aggro warnings.             ║
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
local InCombatLockdown = InCombatLockdown
local UnitExists = UnitExists
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local GetInventoryItemDurability = GetInventoryItemDurability
local GetTime = GetTime
local UnitGUID = UnitGUID
local UnitCanAttack = UnitCanAttack
local UnitThreatSituation = UnitThreatSituation
local PlaySoundFile = PlaySoundFile
local C_Spell_GetSpellName = C_Spell.GetSpellName
local C_Spell_GetSpellTexture = C_Spell.GetSpellTexture
local ipairs, pairs = ipairs, pairs
local math_max = math.max
local string_format = string.format

-- Flip to true to log the classified landed-event decision tuple.
local DEBUG_CT = false

local EQUIP_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }
local INTERRUPT_ICON_GAP = 4
local INTERRUPT_FONT_EMPHASIS = 2
local REVERSE_EVENT_WINDOW = 0.05
local SPELL_LINK_BLUE = { 127 / 255, 207 / 255, 241 / 255 }
local AGGRO_MIN_STATUS = 2
local AGGRO_SOUND_GAP = 2
local AGGRO_PULSE_ALPHA = 0.35
local AGGRO_PULSE_DURATION = 0.45

local MESSAGE_TYPES = {
    "enterCombat",
    "exitCombat",
    "noTarget",
    "lowDurability",
    "interrupt",
    "aggro",
}

local EXTERNAL_LINE_TYPES = {
    "petStatus",
}
local IS_EXTERNAL_LINE = {}
for _, key in ipairs(EXTERNAL_LINE_TYPES) do IS_EXTERNAL_LINE[key] = true end

CM.container = nil
CM.messageFrames = {}
CM.activeMessages = {}
CM.isPreview = false
CM.inCombat = false
CM.noTargetCheckGeneration = 0
CM.interruptCastFrame = nil
CM.interruptEventsRegistered = false
CM.interruptAnnounceSpells = nil
CM.pendingInterruptAt = nil
CM.pendingInterruptSpellID = nil
CM.pendingInterruptUnit = nil
CM.lastAcceptedCastGUID = nil
CM.lastUnkeyedAcceptAt = nil
CM.reverseInterruptAt = nil
CM.reverseInterruptSuccessSpellID = nil
CM.aggroEventFrame = nil
CM.aggroEventsRegistered = false
CM.aggroSoundBlocked = false
CM.aggroPulse = nil
-- Sent on enable and disable, so an external line's owner can move its text
-- between its own frame and this stack.
CM.CHANGED_MESSAGE = "KitnEssentials_CombatTextsChanged"

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
    elseif msgType == "aggro" then
        return db.AggroEnabled ~= false,
            db.AggroText or "AGGRO",
            db.AggroColor or { 1, 0.15, 0.15, 1 }
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

    if msgType == "interrupt" then
        frame:SetHeight(fontSize + INTERRUPT_FONT_EMPHASIS * 2)
        local icon = frame:CreateTexture(nil, "OVERLAY")
        icon:SetSize(fontSize + INTERRUPT_FONT_EMPHASIS, fontSize + INTERRUPT_FONT_EMPHASIS)
        -- Trim the baked spell-icon border.
        icon:SetTexCoord(5 / 64, 59 / 64, 5 / 64, 59 / 64)
        icon:SetPoint("CENTER", frame, "CENTER", 0, 0)
        icon:Hide()
        frame.interruptIcon = icon

        local name = frame:CreateFontString(nil, "OVERLAY")
        name:SetPoint("LEFT", icon, "RIGHT", INTERRUPT_ICON_GAP, 0)
        name:SetJustifyH("LEFT")
        name:SetJustifyV("MIDDLE")
        name:SetWordWrap(false)
        name:Hide()
        frame.interruptName = name

        KE:ApplyFont(text, self.db.FontFace, fontSize + INTERRUPT_FONT_EMPHASIS,
            KE:GetFontOutline(self.db.FontOutline))
        text:SetHeight(fontSize + INTERRUPT_FONT_EMPHASIS * 2)
        KE:ApplyFont(name, self.db.FontFace, fontSize,
            KE:GetFontOutline(self.db.FontOutline))
        name:SetHeight(fontSize + INTERRUPT_FONT_EMPHASIS * 2)
    else
        KE:ApplyFontToText(text, self.db.FontFace, self.db.FontSize, self.db.FontOutline)
    end

    return frame
end

---------------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------------
local function StackFrames(self, types, yOffset, spacing)
    for _, msgType in ipairs(types) do
        local frame = self.messageFrames[msgType]
        if frame and frame:IsShown() then
            frame:ClearAllPoints()
            frame:SetPoint("TOP", self.container, "TOP", 0, -yOffset)
            yOffset = yOffset + frame:GetHeight() + spacing
        end
    end
    return yOffset
end

function CM:ArrangeMessages()
    local spacing = self.db.Spacing or 4
    local yOffset = StackFrames(self, MESSAGE_TYPES, 0, spacing)
    yOffset = StackFrames(self, EXTERNAL_LINE_TYPES, yOffset, spacing)

    if self.container then
        self.container:SetHeight(math_max(30, yOffset - spacing))
    end
end

---------------------------------------------------------------------------------
-- Core Logic
---------------------------------------------------------------------------------
function CM:ShowFlashMessage(msgType, textOverride, iconOverride, nameOverride)
    if not self.db or self.db.Enabled == false then return end
    if self.isPreview then return end

    local enabled, msgText, color = GetMessageConfig(self.db, msgType)
    if not enabled then return end
    if textOverride ~= nil then msgText = textOverride end

    local frame = self:GetMessageFrame(msgType)
    if not frame then return end
    if frame.interruptIcon then
        if iconOverride ~= nil and nameOverride ~= nil then
            frame.text:ClearAllPoints()
            frame.text:SetPoint("RIGHT", frame.interruptIcon, "LEFT", -INTERRUPT_ICON_GAP, 0)
            frame.interruptIcon:SetTexture(iconOverride)
            frame.interruptName:SetText("[" .. nameOverride .. "]")
            frame.interruptIcon:Show()
            frame.interruptName:Show()
        else
            frame.text:ClearAllPoints()
            frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
            frame.interruptIcon:Hide()
            frame.interruptName:Hide()
        end
    end

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
    if frame.interruptName then
        frame.interruptName:SetTextColor(
            SPELL_LINK_BLUE[1], SPELL_LINK_BLUE[2], SPELL_LINK_BLUE[3], color[4] or 1)
    end

    -- Show and arrange
    frame:SetAlpha(1)
    frame:Show()
    self.activeMessages[msgType] = true
    self:ArrangeMessages()

    -- Fade out and hide
    local function HideIfCurrent()
        if frame.generation == myGeneration and not self.isPreview then
            frame:Hide()
            -- Don't reset alpha here. Render tick can process a SetAlpha(1)
            -- as a visible frame before the Hide takes effect, flashing the
            -- text at full alpha.
            -- ShowFlashMessage does SetAlpha(1) on the next show path instead.
            self.activeMessages[msgType] = nil
            self:ArrangeMessages()
        end
    end

    -- Manual alpha fade rather than UIFrameFadeOut, which used to stack-overflow
    -- through the retired soft-outline hooks. Kept because it is known good and
    -- costs nothing: OnUpdate only runs during the fadeDuration window (not the full
    -- message duration), so per-frame cost is limited to ~0.4s per message.
    local fadeDuration = 0.4
    C_Timer.After(duration - fadeDuration, function()
        if frame.generation ~= myGeneration or self.isPreview then return end
        if not frame:IsShown() then return end
        local fadeStart = GetTime()
        frame:SetScript("OnUpdate", function(f)
            if f.generation ~= myGeneration or self.isPreview then
                f:SetScript("OnUpdate", nil)
                return
            end
            local progress = (GetTime() - fadeStart) / fadeDuration
            if progress >= 1 then
                f:SetScript("OnUpdate", nil)
                HideIfCurrent()
            else
                f:SetAlpha(1 - progress)
            end
        end)
    end)
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
-- External Lines
---------------------------------------------------------------------------------
function CM:AcceptsExternalLines()
    return self:IsEnabled() and self.db ~= nil and self.db.Enabled ~= false
        and self.container ~= nil
end

-- Not refused during the preview: the line belongs to its owner, and the
-- preview never repaints or hides it.
function CM:ShowExternalLine(key, text, r, g, b, a)
    if not IS_EXTERNAL_LINE[key] or not self:AcceptsExternalLines() then return false end
    local frame = self:GetMessageFrame(key)
    frame.text:SetText(text)
    frame.text:SetTextColor(r or 1, g or 1, b or 1, a or 1)
    frame:SetAlpha(1)
    frame:Show()
    self:ArrangeMessages()
    return true
end

function CM:HideExternalLine(key)
    if not IS_EXTERNAL_LINE[key] then return end
    local frame = self.messageFrames[key]
    if not (frame and frame:IsShown()) then return end
    frame:Hide()
    self:ArrangeMessages()
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
-- Aggro Warning
---------------------------------------------------------------------------------
-- Pure, so the rule is spec-covered. A secret reading hides the line: a warning
-- that fails open would claim aggro the player does not have.
function CM.ShouldShowAggro(db, inCombat, isTank, inInstance, threat, threatSecret)
    if db.AggroEnabled == false then return false end
    if not inCombat then return false end
    if isTank then return false end
    if db.AggroInstanceOnly ~= false and not inInstance then return false end
    if threatSecret then return false end
    return type(threat) == "number" and threat >= AGGRO_MIN_STATUS
end

-- Built on first use, so a player who never turns Pulse on never gets one.
-- Held on the module, not the frame: spec mock frames answer every field.
local function SetAggroPulse(frame, on)
    if not frame then return end
    local pulse = CM.aggroPulse
    if on then
        if not pulse then
            pulse = frame:CreateAnimationGroup()
            pulse:SetLooping("BOUNCE")
            local fade = pulse:CreateAnimation("Alpha")
            fade:SetFromAlpha(1)
            fade:SetToAlpha(AGGRO_PULSE_ALPHA)
            fade:SetDuration(AGGRO_PULSE_DURATION)
            fade:SetSmoothing("IN_OUT")
            CM.aggroPulse = pulse
        end
        if not pulse:IsPlaying() then pulse:Play() end
    elseif pulse and pulse:IsPlaying() then
        pulse:Stop()
        if frame:IsShown() then frame:SetAlpha(1) end
    end
end

-- A one-shot timer re-arms the sound, so threat bouncing between the player
-- and the tank cannot stack plays.
function CM:PlayAggroSound()
    local db = self.db
    if not db.AggroSoundEnabled or self.aggroSoundBlocked then return end
    local file = db.AggroSoundFile
    if not file or file == "None" or not KE.LSM then return end
    local path = KE.LSM:Fetch("sound", file, true)
    if not path then return end
    PlaySoundFile(path, db.AggroSoundChannel or "Master")
    self.aggroSoundBlocked = true
    C_Timer.After(AGGRO_SOUND_GAP, function() self.aggroSoundBlocked = false end)
end

function CM:CheckAggro()
    if not self.db or self.db.Enabled == false then return end
    if self.isPreview then return end

    local ok, status = pcall(UnitThreatSituation, "player")
    local threat, threatSecret = nil, false
    if ok then
        threat = status
        threatSecret = KE:IsSecretValue(status)
    end
    -- Resolved per call: this file parses before Cursor.lua. The test is a
    -- plain GetInstanceInfo read, live whether or not that module is on.
    local cursor = KitnEssentials:GetModule("Cursor", true)
    local inInstance = (cursor and cursor:InRealInstancedContent()) or false

    local frame = self.messageFrames.aggro
    if CM.ShouldShowAggro(self.db, self.inCombat, KE:IsPlayerTankSpec(), inInstance, threat, threatSecret) then
        if not (frame and frame:IsShown()) then
            self:ShowPersistentMessage("aggro")
            frame = self.messageFrames.aggro
            if frame and frame:IsShown() then self:PlayAggroSound() end
        end
        SetAggroPulse(frame, self.db.AggroPulse == true)
    elseif frame and frame:IsShown() then
        self:HidePersistentMessage("aggro")
        SetAggroPulse(frame, false)
    end
end

function CM:UpdateAggroEventRegistration(forceDisabled)
    local enabled = not forceDisabled
        and self:IsEnabled()
        and self.db
        and self.db.Enabled ~= false
        and self.db.AggroEnabled ~= false

    if enabled and not self.aggroEventsRegistered then
        if not self.aggroEventFrame then
            local frame = CreateFrame("Frame")
            frame:SetScript("OnEvent", function() self:CheckAggro() end)
            self.aggroEventFrame = frame
        end
        self.aggroEventFrame:RegisterUnitEvent("UNIT_THREAT_SITUATION_UPDATE", "player")
        -- A loading screen mid-combat can change the instance test with no
        -- threat change.
        self.aggroEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        self.aggroEventsRegistered = true
    elseif not enabled and self.aggroEventsRegistered then
        self.aggroEventFrame:UnregisterEvent("UNIT_THREAT_SITUATION_UPDATE")
        self.aggroEventFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
        self.aggroEventsRegistered = false
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
    self:CheckAggro()
end

function CM:OnExitCombat()
    self.inCombat = false
    self.noTargetCheckGeneration = self.noTargetCheckGeneration + 1
    self:HidePersistentMessage("noTarget")
    self:ShowFlashMessage("exitCombat")
    self:CheckDurability()
    self:CheckAggro()
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
    self:UpdateInterruptEventRegistration()
    self:UpdateAggroEventRegistration()
    if not self.container then return end
    KE:ApplyFramePosition(self.container, self.db.Position, self.db)

    -- Update font settings and frame height for all message frames
    local fontSize = self.db.FontSize or 16
    for _, frame in pairs(self.messageFrames) do
        frame:SetHeight(fontSize + 2)
        if frame.text then
            if frame.msgType == "interrupt" then
                frame:SetHeight(fontSize + INTERRUPT_FONT_EMPHASIS * 2)
                frame.interruptIcon:SetSize(fontSize + INTERRUPT_FONT_EMPHASIS,
                    fontSize + INTERRUPT_FONT_EMPHASIS)
                KE:ApplyFont(frame.text, self.db.FontFace, fontSize + INTERRUPT_FONT_EMPHASIS,
                    KE:GetFontOutline(self.db.FontOutline))
                frame.text:SetHeight(fontSize + INTERRUPT_FONT_EMPHASIS * 2)
                KE:ApplyFont(frame.interruptName, self.db.FontFace, fontSize,
                    KE:GetFontOutline(self.db.FontOutline))
                frame.interruptName:SetHeight(fontSize + INTERRUPT_FONT_EMPHASIS * 2)
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
                if frame.interruptIcon then
                    frame.text:ClearAllPoints()
                    frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
                    frame.interruptIcon:Hide()
                    frame.interruptName:Hide()
                end
                frame.text:SetText(msgText)
                frame.text:SetTextColor(msgColor[1] or 1, msgColor[2] or 1, msgColor[3] or 1, msgColor[4] or 1)
                if frame.interruptName then
                    frame.interruptName:SetTextColor(
                        msgColor[1] or 1, msgColor[2] or 1, msgColor[3] or 1, msgColor[4] or 1)
                end
            end
        end
        SetAggroPulse(self.messageFrames.aggro, self.db.AggroPulse == true)
        self:ArrangeMessages()
    else
        self:CheckNoTarget()
        self:CheckAggro()
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
            module = self,
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
            if frame.interruptIcon then
                frame.text:ClearAllPoints()
                frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
                frame.interruptIcon:Hide()
                frame.interruptName:Hide()
            end
            frame.text:SetText(msgText)
            frame.text:SetTextColor(msgColor[1] or 1, msgColor[2] or 1, msgColor[3] or 1, msgColor[4] or 1)
            if frame.interruptName then
                frame.interruptName:SetTextColor(
                    msgColor[1] or 1, msgColor[2] or 1, msgColor[3] or 1, msgColor[4] or 1)
            end
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

    -- Built-in lines only: an external line belongs to its owner and stays up.
    for _, msgType in ipairs(MESSAGE_TYPES) do
        local frame = self.messageFrames[msgType]
        if frame then frame:Hide() end
        self.activeMessages[msgType] = nil
    end
    -- Re-arranged only while such a line is still shown: the arrange shrinks
    -- the container, which moves anything anchored to its top.
    for _, key in ipairs(EXTERNAL_LINE_TYPES) do
        local frame = self.messageFrames[key]
        if frame and frame:IsShown() then
            self:ArrangeMessages()
            break
        end
    end

    SetAggroPulse(self.messageFrames.aggro, false)

    -- Re-check actual state
    if self.inCombat then
        self:CheckNoTarget()
        self:CheckAggro()
    end
end

---------------------------------------------------------------------------------
-- Interrupt Announce
---------------------------------------------------------------------------------
function CM.ResolveReadableInterruptOwner(interruptedBy, playerGUID, playerKnown, petGUID, petKnown)
    if playerKnown and interruptedBy == playerGUID then return "OWN" end
    if petKnown and petGUID ~= nil and interruptedBy == petGUID then return "OWN" end
    if not playerKnown or not petKnown then return "UNKNOWN" end
    return "OTHER"
end

function CM.ResolvePendingInterruptSource(unit, unitKnown)
    if not unitKnown then return nil end
    if unit == "player" or unit == "pet" then return unit end
    return nil
end

function CM:ClearPendingInterrupt()
    self.pendingInterruptAt = nil
    self.pendingInterruptSpellID = nil
    self.pendingInterruptUnit = nil
end

function CM:ClearInterruptQuarantine()
    self.reverseInterruptAt = nil
    self.reverseInterruptSuccessSpellID = nil
end

function CM:ClearInterruptState()
    self:ClearPendingInterrupt()
    self:ClearInterruptQuarantine()
    self.lastAcceptedCastGUID = nil
    self.lastUnkeyedAcceptAt = nil
end

function CM:RecordPendingInterrupt(spellID, source, now)
    self.pendingInterruptAt = now
    self.pendingInterruptSpellID = spellID
    self.pendingInterruptUnit = source
end

function CM.NormalizeInterruptSuccessSpellID(spellID)
    if spellID == 19647 or spellID == 119910 or spellID == 132409 then return 19647 end
    if spellID == 89766 or spellID == 119914 then return 89766 end
    return spellID
end

function CM:HasFreshInterruptQuarantine(now)
    if self.reverseInterruptAt == nil then return false end
    if now <= self.reverseInterruptAt + REVERSE_EVENT_WINDOW then
        return true
    end
    self:ClearInterruptQuarantine()
    return false
end

function CM:RecordInterruptQuarantine(now, seedSpellID)
    self.reverseInterruptAt = now
    self.reverseInterruptSuccessSpellID = seedSpellID ~= nil
        and CM.NormalizeInterruptSuccessSpellID(seedSpellID) or nil
end

function CM:ClassifyInterruptOwnership(interruptedBy)
    if KE:IsSecretValue(interruptedBy) then return "UNKNOWN", false end
    if interruptedBy == nil then return "UNKNOWN", true end

    local playerGUID = UnitGUID("player")
    local playerSecret = KE:IsSecretValue(playerGUID)
    local playerKnown = not playerSecret and playerGUID ~= nil
    if not playerKnown then playerGUID = nil end

    local petGUID = UnitGUID("pet")
    local petSecret = KE:IsSecretValue(petGUID)
    local petKnown = not petSecret
    if petSecret then petGUID = nil end

    return CM.ResolveReadableInterruptOwner(interruptedBy, playerGUID,
        playerKnown, petGUID, petKnown), false
end

function CM:ClassifyInterruptTarget(unitTarget)
    if KE:IsSecretValue(unitTarget) then return "UNKNOWN" end
    if type(unitTarget) ~= "string" then return "INVALID" end
    if unitTarget == "player" or unitTarget == "pet" then return "FRIENDLY" end

    local ok, hostile = pcall(UnitCanAttack, "player", unitTarget)
    if not ok or not KE:IsSafeValue(hostile) then return "UNKNOWN" end
    if hostile == true then return "HOSTILE" end
    if hostile == false then return "FRIENDLY" end
    return "UNKNOWN"
end

function CM:HasFreshPendingInterrupt(now)
    if self.pendingInterruptAt == nil then return false, nil, "none", "none" end

    local elapsed = now - self.pendingInterruptAt
    local pendingSource = self.pendingInterruptUnit or "unknown"
    if now <= self.pendingInterruptAt + 0.35 then
        return true, elapsed, pendingSource, "fresh"
    end

    self:ClearPendingInterrupt()
    return false, elapsed, pendingSource, "expired"
end

function CM:ShouldAcceptInterrupt(event, unitTarget, castGUID, interruptedBy, now)
    local ownership, nilOwnership = self:ClassifyInterruptOwnership(interruptedBy)
    local fresh, elapsed, pendingSource, pendingState = self:HasFreshPendingInterrupt(now)
    if ownership == "OTHER" then
        return false, ownership, "UNKNOWN", pendingSource, pendingState, "other-owner", elapsed
    end

    if ownership == "UNKNOWN" then
        if nilOwnership and event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            return false, ownership, "UNKNOWN", pendingSource, pendingState, "nil-channel-stop", elapsed
        end
        if not fresh then
            return false, ownership, "UNKNOWN", pendingSource, pendingState, "no-fresh-pending", elapsed
        end
    end

    local target = self:ClassifyInterruptTarget(unitTarget)
    if target == "FRIENDLY" then
        return false, ownership, target, pendingSource, pendingState, "friendly-target", elapsed
    end
    if target == "INVALID" then
        return false, ownership, target, pendingSource, pendingState, "invalid-target", elapsed
    end
    local readableCastGUID = not KE:IsSecretValue(castGUID) and type(castGUID) == "string"
    if readableCastGUID and castGUID == self.lastAcceptedCastGUID then
        return false, ownership, target, pendingSource, pendingState, "duplicate-cast-guid", elapsed
    end
    if not readableCastGUID and ownership == "OWN" and self.lastUnkeyedAcceptAt ~= nil
        and now < self.lastUnkeyedAcceptAt + 0.10 then
        return false, ownership, target, pendingSource, pendingState, "unkeyed-throttle", elapsed
    end

    if readableCastGUID then
        self.lastAcceptedCastGUID = castGUID
    elseif ownership == "OWN" then
        self.lastUnkeyedAcceptAt = now
    end
    self:ClearPendingInterrupt()
    local reason = ownership == "OWN" and "direct-owner" or "fallback"
    return true, ownership, target, pendingSource, pendingState, reason, elapsed
end

function CM:OnSpellcastSucceeded(_, unit, _, spellID)
    if not self.db or self.db.InterruptEnabled == false or not self.interruptAnnounceSpells then return end
    if not KE:IsSafeValue(spellID) then return end
    if not self.interruptAnnounceSpells[spellID] then return end

    local unitKnown = not KE:IsSecretValue(unit)
    local source = CM.ResolvePendingInterruptSource(unit, unitKnown)
    if unitKnown and source == nil then return end

    local now = GetTime()
    if self:HasFreshInterruptQuarantine(now) then
        local normalizedSpellID = CM.NormalizeInterruptSuccessSpellID(spellID)
        if self.reverseInterruptSuccessSpellID == nil then
            self.reverseInterruptSuccessSpellID = normalizedSpellID
            return
        end
        if self.reverseInterruptSuccessSpellID == normalizedSpellID then return end
        self:ClearInterruptQuarantine()
    end

    self:RecordPendingInterrupt(spellID, source, now)
end

function CM:BuildInterruptDisplayText(spellID)
    local name = C_Spell_GetSpellName(spellID)
    local iconID = C_Spell_GetSpellTexture(spellID)
    if name == nil or iconID == nil then return nil, nil, nil end

    local prefix = self.db.InterruptText or "Interrupted"
    return prefix, iconID, name
end

function CM:OnSpellcastInterrupted(event, unitTarget, castGUID, spellID, interruptedBy)
    if not self.db or self.db.InterruptEnabled == false then return end

    local now = GetTime()
    local pendingSpellID = self.pendingInterruptSpellID
    local accepted, ownership, target, pendingSource, pendingState, reason, elapsed =
        self:ShouldAcceptInterrupt(event, unitTarget, castGUID, interruptedBy, now)
    if DEBUG_CT then
        local elapsedText = elapsed and string_format("%.3f", elapsed) or "none"
        KE:Print(string_format("[CT] event=%s owner=%s target=%s pending=%s state=%s elapsed=%s reason=%s",
            event, ownership, target, pendingSource, pendingState, elapsedText, reason))
    end
    if not accepted then return end

    local quarantineSeed = pendingState == "fresh" and pendingSpellID or nil
    self:RecordInterruptQuarantine(now, quarantineSeed)
    local prefix, icon, name = self:BuildInterruptDisplayText(spellID)
    self:ShowFlashMessage("interrupt", prefix, icon, name)
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function CM:EnsureInterruptCastFrame()
    if self.interruptCastFrame then return end
    local frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", function(_, event, unit, castGUID, spellID)
        self:OnSpellcastSucceeded(event, unit, castGUID, spellID)
    end)
    self.interruptCastFrame = frame
end

function CM:UpdateInterruptEventRegistration(forceDisabled)
    local enabled = not forceDisabled
        and self:IsEnabled()
        and self.db
        and self.db.Enabled ~= false
        and self.db.InterruptEnabled ~= false

    if enabled and not self.interruptEventsRegistered then
        self:EnsureInterruptCastFrame()
        self.interruptCastFrame:RegisterUnitEvent(
            "UNIT_SPELLCAST_SUCCEEDED", "player", "pet")
        self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", "OnSpellcastInterrupted")
        self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP", "OnSpellcastInterrupted")
        self.interruptEventsRegistered = true
    elseif not enabled and self.interruptEventsRegistered then
        self.interruptCastFrame:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        self:UnregisterEvent("UNIT_SPELLCAST_INTERRUPTED")
        self:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
        self.interruptEventsRegistered = false
        self:ClearInterruptState()
    elseif not enabled then
        self:ClearInterruptState()
    end
end

function CM:OnEnable()
    if self.db.Enabled == false then return end

    self:CreateContainer()
    self:RegWithEditMode()
    self.interruptAnnounceSpells = KE:GetInterruptAnnounceSpellSet()
    self:EnsureInterruptCastFrame()

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

    self:UpdateInterruptEventRegistration()
    self:UpdateAggroEventRegistration()

    -- Track initial combat state
    self.inCombat = InCombatLockdown()

    -- Initial checks (delayed to ensure frames exist)
    if self.inCombat then
        self:CheckNoTarget()
        self:CheckAggro()
    else
        C_Timer.After(1, function() self:CheckDurability() end)
    end

    self:SendMessage(self.CHANGED_MESSAGE)
end

function CM:OnDisable()
    for _, frame in pairs(self.messageFrames) do
        frame:Hide()
    end
    self.activeMessages = {}
    self.isPreview = false
    self.inCombat = false
    self.noTargetCheckGeneration = self.noTargetCheckGeneration + 1
    SetAggroPulse(self.messageFrames.aggro, false)
    self:UpdateAggroEventRegistration(true)
    self:UpdateInterruptEventRegistration(true)
    self.interruptAnnounceSpells = nil
    self:UnregisterAllEvents()
    self:SendMessage(self.CHANGED_MESSAGE)
end

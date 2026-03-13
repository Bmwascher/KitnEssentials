-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class CombatTexts: AceModule, AceEvent-3.0
local CM = KitnEssentials:NewModule("CombatTexts", "AceEvent-3.0")

local CreateFrame = CreateFrame
local UIFrameFadeRemoveFrame = UIFrameFadeRemoveFrame
local UIFrameFadeOut = UIFrameFadeOut
local InCombatLockdown = InCombatLockdown
local GetInventoryItemDurability = GetInventoryItemDurability
local ipairs, pairs = ipairs, pairs
local math_max = math.max

-- Equipment slots to check for durability
local EQUIP_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }

-- Message types (order determines vertical stacking)
local MESSAGE_TYPES = {
    "enterCombat",
    "exitCombat",
    "lowDurability",
}

-- Module state
CM.container = nil
CM.messageFrames = {}
CM.activeMessages = {}
CM.isPreview = false
CM.inCombat = false

function CM:UpdateDB()
    self.db = KE.db.profile.CombatTexts
end

function CM:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

-- Get message config from flat DB keys
local function GetMessageConfig(db, msgType)
    if msgType == "enterCombat" then
        return db.EnterEnabled ~= false,
            db.EnterCombatText or "+ Combat",
            db.EnterColor or { 1, 0.1, 0.1, 1 }
    elseif msgType == "exitCombat" then
        return db.ExitEnabled ~= false,
            db.ExitCombatText or "- Combat",
            db.ExitColor or { 0.1, 1, 0.1, 1 }
    elseif msgType == "lowDurability" then
        return db.DurabilityEnabled ~= false,
            db.DurabilityText or "LOW DURABILITY",
            db.DurabilityColor or { 1, 0.3, 0.3, 1 }
    end
    return false, "", { 1, 1, 1, 1 }
end

-- Create container frame
function CM:CreateContainer()
    if self.container then return end

    local container = CreateFrame("Frame", "KE_CombatTextsContainer", UIParent)
    container:SetSize(200, 100)
    KE:ApplyFramePosition(container, self.db.Position, self.db)
    container:SetFrameLevel(100)

    self.container = container
end

-- Create or get a message frame for a given type
function CM:GetMessageFrame(msgType)
    if self.messageFrames[msgType] then
        return self.messageFrames[msgType]
    end

    local frame = CreateFrame("Frame", nil, self.container)
    frame:SetSize(200, 30)
    frame:Hide()

    local text = frame:CreateFontString(nil, "OVERLAY")
    text:SetAllPoints(frame)
    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")

    local fontPath = KE:GetFontPath(self.db.FontFace) or KE.FONT
    text:SetFont(fontPath, self.db.FontSize or 16, "")

    local width = math_max(text:GetWidth(), 150)
    local height = math_max(text:GetHeight(), 14)
    frame:SetSize(width + 5, height)

    frame.text = text
    frame.msgType = msgType
    frame.generation = 0

    self.messageFrames[msgType] = frame

    -- Apply font with SOFTOUTLINE support
    KE:ApplyFontToText(text, self.db.FontFace, self.db.FontSize, self.db.FontOutline)

    return frame
end

-- Arrange visible messages vertically
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

-- Show a flash message (fades out after duration)
function CM:ShowFlashMessage(msgType)
    if not self.db or self.db.Enabled == false then return end
    if self.isPreview then return end

    local enabled, msgText, color = GetMessageConfig(self.db, msgType)
    if not enabled then return end

    local frame = self:GetMessageFrame(msgType)
    if not frame then return end

    local duration = self.db.Duration or 1.5
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

    if UIFrameFadeOut then
        UIFrameFadeOut(frame, duration, 1, 0)
        C_Timer.After(duration, HideIfCurrent)
    else
        C_Timer.After(duration, HideIfCurrent)
    end
end

-- Show a persistent message (stays until explicitly hidden)
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

-- Hide a persistent message
function CM:HidePersistentMessage(msgType)
    local frame = self.messageFrames[msgType]
    if frame then
        frame:Hide()
        self.activeMessages[msgType] = nil
        self:ArrangeMessages()
    end
end

-- Combat event handlers
function CM:OnEnterCombat()
    self.inCombat = true
    self:HidePersistentMessage("lowDurability")
    self:ShowFlashMessage("enterCombat")
end

function CM:OnExitCombat()
    self.inCombat = false
    self:ShowFlashMessage("exitCombat")
    self:CheckDurability()
end

-- Check equipped gear durability
function CM:CheckDurability()
    if not self.db or self.db.Enabled == false then return end
    if self.isPreview then return end

    if self.db.DurabilityEnabled == false then
        self:HidePersistentMessage("lowDurability")
        return
    end

    local threshold = (self.db.DurabilityThreshold or 25) / 100

    -- Don't show while in combat
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

-- Apply all settings
function CM:ApplySettings()
    if not self.container then return end
    KE:ApplyFramePosition(self.container, self.db.Position, self.db)

    -- Update font settings for all message frames
    for _, frame in pairs(self.messageFrames) do
        if frame.text then
            KE:ApplyFontToText(frame.text, self.db.FontFace, self.db.FontSize, self.db.FontOutline)
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
    end
end

-- Apply position only
function CM:ApplyPosition()
    if not self.container then return end
    KE:ApplyFramePosition(self.container, self.db.Position, self.db)
end

-- Refresh
function CM:Refresh()
    self:ApplySettings()
end

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

-- Preview mode: show all message types
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
end

-- Module OnEnable
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
    self:RegisterEvent("UPDATE_INVENTORY_DURABILITY", "CheckDurability")

    -- Track initial combat state
    self.inCombat = InCombatLockdown()

    -- Initial durability check (delayed to ensure frames exist)
    if not self.inCombat then
        C_Timer.After(1, function() self:CheckDurability() end)
    end
end

-- Module OnDisable
function CM:OnDisable()
    for _, frame in pairs(self.messageFrames) do
        frame:Hide()
    end
    self.activeMessages = {}
    self.isPreview = false
    self.inCombat = false
    self:UnregisterAllEvents()
end

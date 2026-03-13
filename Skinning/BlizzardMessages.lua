-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local SK = KitnEssentials:NewModule("SkinBlizzardMessages", "AceEvent-3.0")

local GetTime = GetTime
local UIErrorsFrame = UIErrorsFrame
local ActionStatus = ActionStatus
local ChatBubbleFont = ChatBubbleFont
local ObjectiveTrackerLineFont = ObjectiveTrackerLineFont
local ObjectiveTrackerHeaderFont = ObjectiveTrackerHeaderFont
local C_Timer = C_Timer
local UIParent = UIParent
local _G = _G

function SK:UpdateDB()
    self.db = KE.db.profile.Skinning.Messages
end

function SK:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function SK:OnEnable()
    if KE:ShouldNotLoadModule() then return end
    if not self.db.Enabled then return end
    C_Timer.After(1.0, function()
        if self:IsEnabled() then
            self:ApplySettings()
        end
    end)
end

-- Zone text styling
function SK:ZoneTextStyling()
    local zoneDB = self.db.ZoneText
    if zoneDB.Hide then
        _G.ZoneTextFrame:UnregisterAllEvents()
    else
        local fontPath = KE:GetFontPath(self.db.Font)
        local outline = self.db.FontOutline == "NONE" and "" or (self.db.FontOutline or "OUTLINE")
        ZoneTextString:SetFont(fontPath, zoneDB.MainZone.Size, outline)
        ZoneTextString:SetShadowColor(0, 0, 0, 0)
        ZoneTextString:SetShadowOffset(0, 0)
        SubZoneTextString:SetFont(fontPath, zoneDB.SubZone.Size, outline)
        SubZoneTextString:SetShadowColor(0, 0, 0, 0)
        SubZoneTextString:SetShadowOffset(0, 0)

        PVPArenaTextString:SetFont(fontPath, zoneDB.SubZone.Size, outline)
        PVPArenaTextString:SetShadowColor(0, 0, 0, 0)
        PVPArenaTextString:SetShadowOffset(0, 0)

        PVPInfoTextString:SetFont(fontPath, zoneDB.SubZone.Size, outline)
        PVPInfoTextString:SetShadowColor(0, 0, 0, 0)
        PVPInfoTextString:SetShadowOffset(0, 0)

        _G.ZoneTextFrame:ClearAllPoints()
        _G.ZoneTextFrame:SetPoint(zoneDB.MainZone.Anchor, UIParent, zoneDB.MainZone.Anchor,
            zoneDB.MainZone.X, zoneDB.MainZone.Y)
        _G.ZoneTextFrame:RegisterEvent("ZONE_CHANGED")
        _G.ZoneTextFrame:RegisterEvent("ZONE_CHANGED_INDOORS")
        _G.ZoneTextFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    end
end

-- UI error text styling
function SK:StyleUIErrorsFrame()
    local errorsDB = self.db.UIErrorsFrame
    if not errorsDB or not UIErrorsFrame then return end

    if errorsDB.Hide then
        UIErrorsFrame:Hide()
        UIErrorsFrame:SetAlpha(0)
    else
        UIErrorsFrame:Show()
        UIErrorsFrame:SetAlpha(1)

        local fontPath = KE:GetFontPath(self.db.Font)
        local outline = self.db.FontOutline == "NONE" and "" or (self.db.FontOutline or "OUTLINE")
        UIErrorsFrame:SetFont(fontPath, errorsDB.Size, outline)

        if errorsDB.Position then
            UIErrorsFrame:ClearAllPoints()
            local anchor = errorsDB.Position.Anchor or "TOP"
            local x = errorsDB.Position.X or 0
            local y = errorsDB.Position.Y or -100
            UIErrorsFrame:SetPoint(anchor, UIParent, anchor, x, y)
        end

        UIErrorsFrame:SetShadowColor(0, 0, 0, 0)
    end
end

-- Action status text styling
function SK:StyleActionStatusText()
    local statusDB = self.db.ActionStatusText
    if not statusDB or not ActionStatus or not ActionStatus.Text then return end

    if statusDB.Hide then
        ActionStatus.Text:Hide()
        ActionStatus.Text:SetAlpha(0)
    else
        ActionStatus.Text:Show()
        ActionStatus.Text:SetAlpha(1)

        local fontPath = KE:GetFontPath(self.db.Font)
        local outline = self.db.FontOutline == "NONE" and "" or (self.db.FontOutline or "OUTLINE")
        ActionStatus.Text:SetFont(fontPath, statusDB.Size, outline)

        if statusDB.Position then
            ActionStatus.Text:ClearAllPoints()
            local anchor = statusDB.Position.Anchor or "TOP"
            local x = statusDB.Position.X or 0
            local y = statusDB.Position.Y or -150
            ActionStatus.Text:SetPoint(anchor, UIParent, anchor, x, y)
        end

        ActionStatus.Text:SetShadowColor(0, 0, 0, 0)
    end
end

-- Chat bubble styling
function SK:StyleChatBubbles()
    local bubblesDB = self.db.ChatBubbles
    if not bubblesDB or not bubblesDB.Enabled or not ChatBubbleFont then return end

    local fontPath = KE:GetFontPath(self.db.Font)
    local outline = self.db.FontOutline == "NONE" and "" or (self.db.FontOutline or "OUTLINE")
    ChatBubbleFont:SetFont(fontPath, bubblesDB.Size, outline)
end

-- Objective tracker styling
function SK:StyleObjectiveTracker()
    local trackerDB = self.db.ObjectiveTracker
    if not trackerDB or not trackerDB.Enabled then return end
    local fontPath = KE:GetFontPath(self.db.Font)
    local outline = self.db.FontOutline == "NONE" and "" or (self.db.FontOutline or "OUTLINE")

    if ObjectiveTrackerLineFont then
        ObjectiveTrackerLineFont:SetFont(fontPath, trackerDB.QuestTextSize, outline)
        ObjectiveTrackerLineFont:SetShadowColor(0, 0, 0, 0)
        ObjectiveTrackerLineFont:SetShadowOffset(0, 0)
    end

    if ObjectiveTrackerHeaderFont then
        ObjectiveTrackerHeaderFont:SetFont(fontPath, trackerDB.QuestTitleSize, outline)
        ObjectiveTrackerHeaderFont:SetShadowColor(0, 0, 0, 0)
        ObjectiveTrackerHeaderFont:SetShadowOffset(0, 0)
    end
end

-- Reset to Blizzard defaults
function SK:ResetUIErrorsFrame()
    if not UIErrorsFrame then return end
    UIErrorsFrame:Show()
    UIErrorsFrame:SetAlpha(1)
    UIErrorsFrame:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    UIErrorsFrame:ClearAllPoints()
    UIErrorsFrame:SetPoint("TOP", UIParent, "TOP", 0, -100)
end

function SK:ResetActionStatusText()
    if not ActionStatus or not ActionStatus.Text then return end
    ActionStatus.Text:Show()
    ActionStatus.Text:SetAlpha(1)
    ActionStatus.Text:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    ActionStatus.Text:ClearAllPoints()
    ActionStatus.Text:SetPoint("TOP", UIParent, "TOP", 0, -150)
end

-- Apply all styles
function SK:ApplySettings()
    if KE:ShouldNotLoadModule() then return end
    if not self.db or not self.db.Enabled then
        self:Reset()
        return
    end
    self:StyleUIErrorsFrame()
    self:StyleActionStatusText()
    self:StyleChatBubbles()
    self:StyleObjectiveTracker()
    self:ZoneTextStyling()
end

-- Reset all styled elements
function SK:Reset()
    self:ResetUIErrorsFrame()
    self:ResetActionStatusText()
end

-- Preview functions for GUI
function SK:PreviewUIErrors()
    if UIErrorsFrame then
        UIErrorsFrame:Clear()
        UIErrorsFrame:AddMessage("Error Message Text", 1, 0.1, 0.1, 1.0, 5)
    end
end

function SK:PreviewActionStatus()
    if ActionStatus and ActionStatus.Text then
        ActionStatus.Text:SetText("Action Status Text")
        ActionStatus:Show()
        ActionStatus.startTime = GetTime()
        ActionStatus.holdTime = 5
        ActionStatus.fadeTime = 1
    end
end

function SK:PreviewZone()
    if ZoneTextFrame and ZoneTextString then
        ZoneTextString:SetText("Main Zone Text")
        ZoneTextFrame:Show()
        ZoneTextFrame.fadingOut = false
        ZoneTextFrame.startTime = GetTime()
    end

    if SubZoneTextFrame and SubZoneTextString then
        SubZoneTextString:SetText("Sub Zone Text")
        SubZoneTextFrame:Show()
        SubZoneTextFrame.fadingOut = false
        SubZoneTextFrame.startTime = GetTime()
    end

    if PVPArenaTextString then
        PVPArenaTextString:SetText("(PVP Arena Text)")
        PVPArenaTextString:Show()
        PVPArenaTextString.fadingOut = false
        PVPArenaTextString.startTime = GetTime()
    end

    if PVPInfoTextString then
        PVPInfoTextString:SetText("(PVP Info Text)")
        PVPInfoTextString:Show()
        PVPInfoTextString.fadingOut = false
        PVPInfoTextString.startTime = GetTime()
    end

    SK:PreviewUIErrors()
    SK:PreviewActionStatus()
end

function SK:OnDisable()
    self:Reset()
end

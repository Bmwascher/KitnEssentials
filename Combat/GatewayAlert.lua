-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

-- Create module
---@class GatewayAlert: AceModule, AceEvent-3.0
local GA = KitnEssentials:NewModule("GatewayAlert", "AceEvent-3.0")

-- Localization
local C_Item = C_Item
local C_Timer = C_Timer
local IsUsableItem = C_Item.IsUsableItem
local GetItemCount = C_Item.GetItemCount
local GetItemInfo = C_Item.GetItemInfo
local CreateFrame = CreateFrame

-- Constants
local GATEWAY_ITEM_ID = 188152

-- Module state
GA.frame = nil
GA.text = nil
GA.isPreview = false

-- Update db
function GA:UpdateDB()
    self.db = KE.db.profile.GatewayAlert
end

-- Module init
function GA:OnInitialize()
    self:UpdateDB()
    self.wasUsable = false
    self.hasItem = false
    self.itemName = nil
    self:SetEnabledState(false)
end

-- Create the alert frame
function GA:CreateFrame()
    if self.frame then return end

    local frame = CreateFrame("Frame", "KE_GatewayAlertFrame", UIParent)
    frame:SetSize(300, 40)

    local text = frame:CreateFontString(nil, "OVERLAY")
    local fontPath = KE:GetFontPath(self.db.FontFace)
    text:SetFont(fontPath, self.db.FontSize, self.db.FontOutline or "")
    text:ClearAllPoints()
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)

    local color = self.db.Color or { 1, 0.82, 0, 1 }
    text:SetTextColor(color[1], color[2], color[3], color[4] or 1)

    self.frame = frame
    self.text = text
    frame:Hide()
end

-- Full update: check item count then usability
function GA:FullUpdate()
    C_Timer.After(0.5, function()
        local count = GetItemCount(GATEWAY_ITEM_ID)
        self.hasItem = count and count > 0
        if self.hasItem then
            if not self.itemName then self.itemName = GetItemInfo(GATEWAY_ITEM_ID) end
            self:CheckUsable()
        else
            self:UpdateState(false)
        end
    end)
end

-- Check if item is usable
function GA:CheckUsable()
    if not self.hasItem then
        self:UpdateState(false)
        return
    end
    self:UpdateState(IsUsableItem(GATEWAY_ITEM_ID) and true or false)
end

-- Handle state changes
function GA:UpdateState(isUsable)
    if self.isPreview then return end
    if isUsable == self.wasUsable then return end
    self.wasUsable = isUsable

    if isUsable then
        self.text:SetText("GATE USABLE")
        self.frame:SetAlpha(1)
        self.frame:Show()
    else
        if self.frame then
            self.frame:Hide()
        end
    end
end

-- Apply all settings
function GA:ApplySettings()
    if not self.frame then return end

    KE:ApplyFramePosition(self.frame, self.db.Position, self.db)
    KE:ApplyFontToText(self.text, self.db.FontFace, self.db.FontSize, self.db.FontOutline)

    local color = self.db.Color or { 1, 0.82, 0, 1 }
    self.text:SetTextColor(color[1], color[2], color[3], color[4] or 1)

    if self.db.Strata then
        self.frame:SetFrameStrata(self.db.Strata)
    end
end

function GA:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "GatewayAlert", displayName = "Gateway Alert", frame = self.frame,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos) self.db.Position = pos; KE:ApplyFramePosition(self.frame, self.db.Position, self.db) end,
            getParentFrame = function() return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) end,
            guiPath = "GatewayAlert",
        })
        self.editModeRegistered = true
    end
end

-- Preview mode
function GA:ShowPreview()
    if not self.frame then
        self:CreateFrame()
    end
    self:RegWithEditMode()

    self.isPreview = true
    self.text:SetText("GATE USABLE")
    self.frame:SetAlpha(1)
    self.frame:Show()
    self:ApplySettings()
end

function GA:HidePreview()
    self.isPreview = false
    if self.db.Enabled then
        self.wasUsable = nil
        self:CheckUsable()
    else
        if self.frame then self.frame:Hide() end
    end
end

-- Module OnEnable
function GA:OnEnable()
    if not self.db.Enabled then return end

    self:CreateFrame()
    self:RegWithEditMode()
    C_Timer.After(0.5, function()
        self:ApplySettings()
    end)

    self:RegisterEvent("PLAYER_ENTERING_WORLD", "FullUpdate")
    self:RegisterEvent("BAG_UPDATE", "FullUpdate")
    self:RegisterEvent("SPELL_UPDATE_USABLE", "CheckUsable")
    self:FullUpdate()
end

-- Module OnDisable
function GA:OnDisable()
    self:UnregisterAllEvents()
    if self.frame then self.frame:Hide() end
    self.wasUsable = false
    self.hasItem = false
    self.isPreview = false
end

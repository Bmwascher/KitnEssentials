-- ╔══════════════════════════════════════════════════════════╗
-- ║  Battlenet.lua                                           ║
-- ║  Module: Battle.net Toast                                ║
-- ║  Purpose: Reskins Battle.net notification toasts         ║
-- ║           with dark theme and repositions via anchor.    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local SK = KitnEssentials:NewModule("SkinBattlenet", "AceEvent-3.0", "AceHook-3.0")

-- Local references
local CreateFrame = CreateFrame
local _G = _G
local UIParent = UIParent
local hooksecurefunc = hooksecurefunc
local C_Timer = C_Timer
local Mixin = Mixin
local BackdropTemplateMixin = BackdropTemplateMixin

---------------------------------------------------------------------------------
-- Module Locals
---------------------------------------------------------------------------------

local anchorFrame = nil
local isRepositioning = false

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------

function SK:UpdateDB()
    self.db = KE.db.profile.Skinning.Battlenet
end

---------------------------------------------------------------------------------
-- Frame Skinning
---------------------------------------------------------------------------------

local function SkinFrame(frame)
    if not frame or frame.__KESkinned then return end

    -- Hide NineSlice border overlay
    if frame.NineSlice then
        frame.NineSlice:Hide()
    end

    -- Ensure frame supports backdrop API
    if not frame.SetBackdrop and BackdropTemplateMixin then
        Mixin(frame, BackdropTemplateMixin)
    end

    -- Apply dark backdrop
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            tile = false,
            edgeSize = 1,
        })
        frame:SetBackdropColor(0, 0, 0, 0.8)
        frame:SetBackdropBorderColor(0, 0, 0, 1)
    end

    frame.__KESkinned = true
end

---------------------------------------------------------------------------------
-- Anchor Frame
---------------------------------------------------------------------------------

local function CreateAnchorFrame()
    if anchorFrame then return anchorFrame end
    anchorFrame = CreateFrame("Frame", "KE_BNToastAnchor", UIParent)
    anchorFrame:SetSize(300, 50)
    anchorFrame:SetFrameStrata("DIALOG")
    return anchorFrame
end

local function PositionAnchorFrame()
    if not anchorFrame then return end
    local posDB = SK.db.Position
    anchorFrame:ClearAllPoints()
    anchorFrame:SetPoint(posDB.AnchorFrom, UIParent, posDB.AnchorTo, posDB.XOffset, posDB.YOffset)
end

---------------------------------------------------------------------------------
-- Toast Attachment
---------------------------------------------------------------------------------

local function AttachToastToAnchor()
    if not anchorFrame or not _G.BNToastFrame then return end
    if isRepositioning then return end
    isRepositioning = true

    _G.BNToastFrame:ClearAllPoints()
    _G.BNToastFrame:SetPoint("BOTTOMLEFT", anchorFrame, "BOTTOMLEFT", 0, 0)

    -- Match anchor size to toast dimensions
    local width = _G.BNToastFrame:GetWidth()
    local height = _G.BNToastFrame:GetHeight()
    if width and width > 0 and height and height > 0 then
        anchorFrame:SetSize(width, height)
    end

    isRepositioning = false
end

local function SetupPositionHooks()
    if not _G.BNToastFrame then return end

    -- Intercept Blizzard repositioning attempts
    hooksecurefunc(_G.BNToastFrame, "SetPoint", function()
        AttachToastToAnchor()
    end)

    -- Re-attach on show in case Blizzard repositions there
    _G.BNToastFrame:HookScript("OnShow", function()
        C_Timer.After(0, AttachToastToAnchor)
    end)
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------

function SK:ApplySettings()
    if KE:ShouldNotLoadModule() then return end
    PositionAnchorFrame()
end

---------------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------------

function SK:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "SkinBattlenet",
            displayName = "BNet Toast",
            frame = anchorFrame,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos)
                self.db.Position.AnchorFrom = pos.AnchorFrom
                self.db.Position.AnchorTo = pos.AnchorTo
                self.db.Position.XOffset = pos.XOffset
                self.db.Position.YOffset = pos.YOffset
                PositionAnchorFrame()
            end,
            getParentFrame = function() return UIParent end,
            guiPath = "SkinBattlenet",
        })
        self.editModeRegistered = true
    end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------

function SK:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function SK:OnEnable()
    if KE:ShouldNotLoadModule() then return end
    if not self.db.Enabled then return end

    C_Timer.After(1.0, function()
        if not self:IsEnabled() then return end

        -- Skin available frames
        SkinFrame(_G.BNToastFrame)
        SkinFrame(_G.TimeAlertFrame)
        if _G.TicketStatusFrameButton then
            SkinFrame(_G.TicketStatusFrameButton.NineSlice)
        end

        -- Create and position anchor
        CreateAnchorFrame()
        PositionAnchorFrame()

        -- Setup hooks and initial attachment
        SetupPositionHooks()
        AttachToastToAnchor()

        -- Register with EditMode for drag positioning
        self:RegWithEditMode()
    end)
end

function SK:OnDisable()
    self:UnregisterAllEvents()
    self:UnhookAll()
end

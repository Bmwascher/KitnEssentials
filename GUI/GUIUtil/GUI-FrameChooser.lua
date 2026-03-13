-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)

-- Frame Chooser: Click-to-select a frame as anchor target
KE.FrameChooser = {}
local FC = KE.FrameChooser
local Theme = KE.Theme

-- Localization
local ResetCursor = ResetCursor
local tostring = tostring
local pairs = pairs
local CreateFrame = CreateFrame
local IsMouseButtonDown = IsMouseButtonDown
local SetCursor = SetCursor
local GetMouseFoci = GetMouseFoci
local GetMouseFocus = GetMouseFocus

-- State
local chooserFrame = nil
local chooserBox = nil
local isActive = false
local currentCallback = nil
local originalValue = nil
local oldFocus = nil
local oldFocusName = nil

-- Get frame name recursively, using parent key if no :GetName() exists
local function RecurseGetName(frame)
    if not frame then return nil end

    local name = frame.GetName and frame:GetName() or nil
    if name then
        return name
    end

    local parent = frame.GetParent and frame:GetParent()
    if parent then
        for key, child in pairs(parent) do
            if child == frame then
                local parentName = RecurseGetName(parent)
                if parentName then
                    return parentName .. "." .. tostring(key)
                end
            end
        end
    end

    return nil
end

-- Create the frame chooser UI elements
local function EnsureFrameChooserUI()
    if chooserFrame then return end

    chooserFrame = CreateFrame("Frame", "KEFrameChooser", UIParent)
    chooserFrame:SetFrameStrata("TOOLTIP")
    chooserFrame:SetAllPoints(UIParent)
    chooserFrame:EnableMouse(false)
    chooserFrame:Hide()

    -- Highlight box around hovered frame
    chooserBox = CreateFrame("Frame", nil, chooserFrame, "BackdropTemplate")
    chooserBox:SetFrameStrata("TOOLTIP")
    chooserBox:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 3,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    local accent = (Theme and Theme.accent) or { 1, 0.82, 0, 1 }
    chooserBox:SetBackdropBorderColor(accent[1], accent[2], accent[3], accent[4] or 1)
    chooserBox:Hide()

    -- Instructions text
    local instructions = chooserFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    instructions:SetPoint("TOP", UIParent, "TOP", 0, -50)
    instructions:SetText("Click on a frame to select it as anchor\nRight-click to cancel")
    instructions:SetTextColor(0, 1, 0, 1)
    chooserFrame.instructions = instructions
end

-- OnUpdate: track mouse, highlight frames, handle clicks
local function OnUpdateHandler(self, elapsed)
    if not isActive then return end

    -- Right-click cancels
    if IsMouseButtonDown("RightButton") then
        FC:Stop(true)
        return
    end

    -- Left-click confirms
    if IsMouseButtonDown("LeftButton") and oldFocusName then
        FC:Stop(false)
        return
    end

    SetCursor("CAST_CURSOR")

    -- Get frame under cursor
    local focus
    if GetMouseFocus then
        focus = GetMouseFocus()
    elseif GetMouseFoci then
        local foci = GetMouseFoci()
        focus = foci and foci[1] or nil
    end

    local focusName = nil

    if focus then
        focusName = RecurseGetName(focus)
        if focusName == "WorldFrame" or not focusName then
            focusName = nil
        end

        if focus ~= oldFocus then
            if chooserBox then
                if focusName then
                    chooserBox:ClearAllPoints()
                    chooserBox:SetPoint("BOTTOMLEFT", focus, "BOTTOMLEFT", -4, -4)
                    chooserBox:SetPoint("TOPRIGHT", focus, "TOPRIGHT", 4, 4)
                    chooserBox:Show()
                else
                    chooserBox:Hide()
                end
            end

            if focusName ~= oldFocusName then
                oldFocusName = focusName
                if currentCallback then
                    currentCallback(focusName, true)
                end
            end

            oldFocus = focus
        end
    end

    if not focusName then
        if chooserBox then
            chooserBox:Hide()
        end
    end
end

-- Start frame chooser mode
function FC:Start(callback, initialValue)
    EnsureFrameChooserUI()

    if isActive then
        self:Stop(true)
    end

    isActive = true
    currentCallback = callback
    originalValue = initialValue
    oldFocus = nil
    oldFocusName = nil

    if chooserFrame then
        chooserFrame:SetScript("OnUpdate", OnUpdateHandler)
        chooserFrame:Show()
    end

    if KE.Print then
        KE:Print("Frame chooser active. Click a frame to select, right-click to cancel.")
    end
end

-- Stop frame chooser mode
function FC:Stop(cancelled)
    if not isActive then return end

    isActive = false

    if chooserFrame then
        chooserFrame:SetScript("OnUpdate", nil)
        chooserFrame:Hide()
    end

    if chooserBox then
        chooserBox:Hide()
    end

    ResetCursor()

    if currentCallback then
        if cancelled then
            currentCallback(originalValue, false)
        else
            currentCallback(oldFocusName, false)
        end
    end

    currentCallback = nil
    originalValue = nil
    oldFocus = nil
    oldFocusName = nil
end

function FC:IsActive()
    return isActive
end

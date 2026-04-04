-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

-- WorldMap module
-- Purpose: Adds configurable world map scaling and a coordinate waypoint search bar.
-- Author: Kitn (ported from atrocityEssentials by Bmwascher)

---@class WorldMap: AceModule, AceEvent-3.0
local WM = KitnEssentials:NewModule("WorldMap", "AceEvent-3.0")

-- Locals
local CreateFrame = CreateFrame
local tonumber = tonumber
local format = string.format
local gsub = string.gsub

local C_Map = C_Map
local C_SuperTrack = C_SuperTrack
local UiMapPoint = UiMapPoint
local EventRegistry = EventRegistry

-- Module state
WM.searchBar = nil
WM.scaleCallbacksRegistered = false

-- Update db
function WM:UpdateDB()
    self.db = KE.db.profile.WorldMap
end

-- Module init
function WM:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

-- ================================================================
-- SCALE
-- ================================================================

function WM:ApplyScale()
    if not self.db or not self.db.ScaleEnabled then
        -- Reset scale when disabled
        if WorldMapFrame then
            WorldMapFrame:SetScale(1)
        end
        return
    end

    local size = self.db.Scale or 1.2

    WorldMapFrame:SetClampedToScreen(true)
    WorldMapFrame:SetScale(size)

    -- Register minimize/maximize callbacks (closures capture the size correctly)
    if not self.scaleCallbacksRegistered then
        EventRegistry:RegisterCallback("WorldMapMinimized", function()
            if self.db and self.db.ScaleEnabled then
                WorldMapFrame:SetScale(self.db.Scale or 1.2)
            end
        end, self)
        EventRegistry:RegisterCallback("WorldMapMaximized", function()
            WorldMapFrame:SetScale(1)
        end, self)
        self.scaleCallbacksRegistered = true
    end
end

-- ================================================================
-- WAYPOINT SEARCH BAR
-- ================================================================

-- Parse coordinate text into x, y values.
-- Accepts formats like: 45 67, 45.2 67.8, 45, 67, /way 45 67
local function ParseCoordinates(text)
    if not text or text == "" then return nil, nil end

    -- Strip common prefixes
    text = gsub(text, "^%s*/way%s*", "")
    text = gsub(text, "^%s*way%s*", "")

    -- Normalize separators
    text = gsub(text, "[,/|\"'%[%]%(%)]+", " ")
    text = gsub(text, "%s+", " ")
    text = gsub(text, "^%s+", "")
    text = gsub(text, "%s+$", "")

    -- Extract numbers
    local numbers = {}
    for num in text:gmatch("([%d%.]+)") do
        local n = tonumber(num)
        if n then
            numbers[#numbers + 1] = n
        end
    end

    if #numbers < 2 then return nil, nil end

    local x, y = numbers[1], numbers[2]
    if x > 100 or y > 100 then return nil, nil end

    return x, y
end

-- Set a waypoint on the current map
local function SetWaypoint(x, y)
    local mapID = WorldMapFrame:IsShown() and WorldMapFrame:GetMapID()
        or C_Map.GetBestMapForUnit("player")

    if not mapID then return false, "No map found" end

    -- Scale to 0-1 range if needed
    if x > 1 then x = x / 100 end
    if y > 1 then y = y / 100 end

    if not C_Map.CanSetUserWaypointOnMap(mapID) then
        return false, "Can't set waypoint here"
    end

    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
    C_SuperTrack.SetSuperTrackedUserWaypoint(true)

    local mapInfo = C_Map.GetMapInfo(mapID)
    local mapName = mapInfo and mapInfo.name or "Unknown"
    return true, format("%s (%.1f, %.1f)", mapName, x * 100, y * 100)
end

function WM:CreateSearchBar()
    if self.searchBar then return end
    if not WorldMapFrame then return end
    if not self.db or not self.db.WaypointBarEnabled then return end

    local fontSize = 12

    -- EditBox
    local editBox = CreateFrame("EditBox", "KE_WorldMapSearchBar", WorldMapFrame)
    editBox:SetSize(140, 20)
    editBox:SetPoint("TOPLEFT", WorldMapFrame, "TOPLEFT", 3, -5)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(50)
    editBox:SetFrameStrata("DIALOG")

    -- Backdrop
    local bg = CreateFrame("Frame", nil, editBox, BackdropTemplateMixin and "BackdropTemplate")
    bg:SetAllPoints(editBox)
    bg:SetFrameLevel(editBox:GetFrameLevel() - 1)
    bg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    bg:SetBackdropColor(0, 0, 0, 0.7)
    bg:SetBackdropBorderColor(0, 0, 0, 1)

    -- Font
    local fontPath = KE:GetFontPath("Expressway") or "Fonts\\FRIZQT__.TTF"
    editBox:SetFont(fontPath, fontSize, "")
    editBox:SetTextColor(1, 1, 1, 1)
    editBox:SetTextInsets(4, 4, 0, 0)

    -- Placeholder text
    local placeholder = editBox:CreateFontString(nil, "ARTWORK")
    placeholder:SetFont(fontPath, fontSize, "")
    placeholder:SetTextColor(0.5, 0.5, 0.5, 0.8)
    placeholder:SetText("/way x y")
    placeholder:SetPoint("LEFT", editBox, "LEFT", 4, 0)
    editBox.placeholder = placeholder

    -- Status text (shows result after pressing Enter)
    local statusText = editBox:CreateFontString(nil, "ARTWORK")
    statusText:SetFont(fontPath, fontSize - 1, "OUTLINE")
    statusText:SetPoint("LEFT", editBox, "RIGHT", 5, 0)
    editBox.statusText = statusText

    -- Focus handlers
    editBox:SetScript("OnEditFocusGained", function()
        placeholder:Hide()
    end)

    editBox:SetScript("OnEditFocusLost", function(eb)
        local text = eb:GetText()
        if not text or text:gsub(" ", "") == "" then
            placeholder:Show()
        end
    end)

    -- Live preview while typing
    editBox:SetScript("OnTextChanged", function(eb, userInput)
        if not userInput then return end
        local text = eb:GetText()
        if not text or text:gsub(" ", "") == "" then
            statusText:SetText("")
            return
        end

        local x, y = ParseCoordinates(text)
        if x and y then
            local mapID = WorldMapFrame:GetMapID() or C_Map.GetBestMapForUnit("player")
            local mapInfo = mapID and C_Map.GetMapInfo(mapID)
            local name = mapInfo and mapInfo.name or ""
            statusText:SetTextColor(0.3, 1, 0.3, 1)
            statusText:SetText(format("%s (%.1f, %.1f)", name, x, y))
        else
            statusText:SetTextColor(1, 0.3, 0.3, 1)
            statusText:SetText("Invalid")
        end
    end)

    -- Enter to set waypoint
    editBox:SetScript("OnEnterPressed", function(eb)
        local text = eb:GetText()
        local x, y = ParseCoordinates(text)
        if x and y then
            local success, msg = SetWaypoint(x, y)
            if success then
                statusText:SetTextColor(0.3, 1, 0.3, 1)
                statusText:SetText(msg)
                KE:Print("Waypoint set: " .. msg)
                eb:SetText("")
            else
                statusText:SetTextColor(1, 0.3, 0.3, 1)
                statusText:SetText(msg)
            end
        else
            statusText:SetTextColor(1, 0.3, 0.3, 1)
            statusText:SetText("Invalid coordinates")
        end
        eb:ClearFocus()
    end)

    -- Escape to cancel
    editBox:SetScript("OnEscapePressed", function(eb)
        eb:SetText("")
        statusText:SetText("")
        placeholder:Show()
        eb:ClearFocus()
    end)

    self.searchBar = editBox
end

-- ================================================================
-- APPLY / ENABLE
-- ================================================================

function WM:ApplySettings()
    self:UpdateDB()
    if not self.db then return end

    -- Scale
    self:ApplyScale()

    -- Waypoint search bar
    if self.db.WaypointBarEnabled then
        if WorldMapFrame then
            self:CreateSearchBar()
            if self.searchBar then
                self.searchBar:Show()
            end
        end
    else
        if self.searchBar then
            self.searchBar:Hide()
        end
    end
end

function WM:OnEnable()
    if not self.db or not self.db.Enabled then return end
    C_Timer.After(0, function()
        self:ApplySettings()
    end)
end

function WM:OnDisable()
    -- Reset scale
    if WorldMapFrame then
        WorldMapFrame:SetScale(1)
    end
    -- Hide search bar
    if self.searchBar then
        self.searchBar:Hide()
    end
end

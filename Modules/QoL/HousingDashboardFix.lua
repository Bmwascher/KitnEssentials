---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

KE.HousingDashboardFixLoaded = true

local _G = _G
local C_AddOns_IsAddOnLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
local C_Housing_GetPlayerOwnedHouses = _G.C_Housing.GetPlayerOwnedHouses
local C_Timer_After = C_Timer.After

local function CheckAndRepair()
    local dashboard = _G.HousingDashboardFrame
    local dropdown = dashboard and dashboard.HouseDropdown
    local houseInfo = dashboard and dashboard.HouseInfoContent
    local content = houseInfo and houseInfo.ContentFrame
    local noHousesFrame = houseInfo and houseInfo.DashboardNoHousesFrame
    local houseList = dropdown and dropdown.playerHouseList
    if type(houseList) ~= "table" then return end

    local hasHouses = #houseList > 0
    local isStuck = (hasHouses and content and content.tabsInitialized ~= true)
        or (not hasHouses and noHousesFrame and not noHousesFrame:IsShown())
    if not isStuck then return end

    dropdown.playerHouseList = nil
    C_Housing_GetPlayerOwnedHouses()
end

local hooked = false
local function HookDashboard()
    if hooked then return end

    local dashboard = _G.HousingDashboardFrame
    if not dashboard then return end

    hooked = true
    dashboard:HookScript("OnShow", function()
        C_Timer_After(0, CheckAndRepair)
    end)
end

if C_AddOns_IsAddOnLoaded and C_AddOns_IsAddOnLoaded("Blizzard_HousingDashboard") then
    HookDashboard()
else
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("ADDON_LOADED")
    watcher:SetScript("OnEvent", function(self, _, addonName)
        if addonName ~= "Blizzard_HousingDashboard" then return end

        self:UnregisterEvent("ADDON_LOADED")
        HookDashboard()
    end)
end

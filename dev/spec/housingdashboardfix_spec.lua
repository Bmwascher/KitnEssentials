local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

local function loadFix(list, tabsInitialized, noHousesShown, dashboardLoaded)
    local scheduled = {}
    local refetches = 0

    local frames = mock.install({
        C_Timer = {
            After = function(delay, callback)
                scheduled[#scheduled + 1] = { delay = delay, callback = callback }
            end,
        },
    })
    helpers.installAddonShim()

    _G.C_AddOns = {
        IsAddOnLoaded = function(addon)
            local isDashboard = addon == "Blizzard_HousingDashboard"
            return isDashboard, isDashboard and dashboardLoaded ~= false
        end,
    }
    _G.C_Housing = {
        GetPlayerOwnedHouses = function()
            refetches = refetches + 1
        end,
    }

    local dashboard = CreateFrame("Frame")
    dashboard.HouseDropdown = { playerHouseList = list }
    dashboard.HouseInfoContent = {
        ContentFrame = { tabsInitialized = tabsInitialized },
        DashboardNoHousesFrame = {
            IsShown = function() return noHousesShown end,
        },
    }
    _G.HousingDashboardFrame = dashboard

    local KE = {}
    helpers.loadModule("Modules/QoL/HousingDashboardFix.lua", KE)

    return KE, dashboard, scheduled, function() return refetches end, frames
end

describe("HousingDashboardFix", function()
    it("leaves a healthy cached house list alone", function()
        local houses = { { houseGUID = "House-1" } }
        local KE, dashboard, scheduled, getRefetches = loadFix(houses, true, false)

        assert.equal(2, KE.HousingDashboardFixLoaded)
        dashboard:GetScript("OnShow")(dashboard)

        assert.equal(1, #scheduled)
        assert.equal(0, scheduled[1].delay)
        scheduled[1].callback()
        assert.equal(0, getRefetches())
        assert.equal(houses, dashboard.HouseDropdown.playerHouseList)
    end)

    it("leaves a healthy empty cached list alone", function()
        local houses = {}
        local _, dashboard, scheduled, getRefetches = loadFix(houses, true, true)

        dashboard:GetScript("OnShow")(dashboard)
        scheduled[1].callback()

        assert.equal(0, getRefetches())
        assert.equal(houses, dashboard.HouseDropdown.playerHouseList)
    end)

    it("repairs a nonempty cached list without initialized tabs", function()
        local _, dashboard, scheduled, getRefetches = loadFix({ { houseGUID = "House-1" } }, false, false)

        dashboard:GetScript("OnShow")(dashboard)
        scheduled[1].callback()

        assert.equal(1, getRefetches())
        assert.is_nil(dashboard.HouseDropdown.playerHouseList)
    end)

    it("repairs an empty cached list while the empty state is hidden", function()
        local _, dashboard, scheduled, getRefetches = loadFix({}, true, false)

        dashboard:GetScript("OnShow")(dashboard)
        scheduled[1].callback()

        assert.equal(1, getRefetches())
        assert.is_nil(dashboard.HouseDropdown.playerHouseList)
    end)
end)

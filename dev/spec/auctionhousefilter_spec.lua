local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

local FILTER = 7

local function loadModule(filterButton)
    mock.install({
        C_Timer = {
            After = function(_, callback) callback() end,
        },
    })

    local modules = helpers.installAddonShim()
    _G.Enum = {
        AuctionHouseFilter = {
            CurrentExpansionOnly = FILTER,
        },
    }
    _G.AuctionHouseFrame = {
        SearchBar = {
            FilterButton = filterButton,
        },
    }
    _G.ProfessionsCustomerOrdersFrame = nil

    local KE = {
        db = {
            profile = {
                AuctionHouseFilter = {
                    Enabled = true,
                    AuctionHouse = {
                        CurrentExpansion = true,
                        FocusSearchBar = false,
                    },
                    CraftOrders = {
                        CurrentExpansion = false,
                        FocusSearchBar = false,
                    },
                },
            },
        },
    }

    helpers.loadModule("Modules/QoL/AuctionHouseFilter.lua", KE)
    local module = modules.AuctionHouseFilter
    module:UpdateDB()
    return module
end

describe("AuctionHouseFilter", function()
    it("keeps the current-expansion filter enabled through the button API", function()
        local filters = { [FILTER] = false }
        local filterButton = {
            GetFilters = function()
                return filters
            end,
            ToggleFilter = function(_, filter)
                filters[filter] = not filters[filter]
            end,
        }
        local module = loadModule(filterButton)

        module:ApplyAuctionHouseFilter()
        assert.is_true(filters[FILTER])

        module:ApplyAuctionHouseFilter()
        assert.is_true(filters[FILTER])
    end)

    it("keeps legacy filter tables working", function()
        local filters = { [FILTER] = false }
        local module = loadModule({ filters = filters })

        module:ApplyAuctionHouseFilter()
        assert.is_true(filters[FILTER])
    end)
end)

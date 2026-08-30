local helpers = require("dev.spec._helpers")
local L = require("dev.spec._ke_loader")

local function findUpvalue(fn, name)
    local index = 1
    while true do
        local upName, upValue = debug.getupvalue(fn, index)
        if not upName then error("upvalue " .. name .. " not found") end
        if upName == name then return upValue end
        index = index + 1
    end
end

describe("AuraEngine duration formatting", function()
    it("configures the live formatter to show whole hours at one hour", function()
        local breakpoints
        _G.C_StringUtil = {
            CreateNumericRuleFormatter = function()
                return {
                    SetBreakpoints = function(_, value)
                        breakpoints = value
                    end,
                }
            end,
        }
        _G.Enum = {
            NumericRuleFormatRounding = {
                Down = "down",
                Up = "up",
            },
        }

        local KE = helpers.loadModule("Modules/Combat/AuraEngine/Style.lua")
        local getDurationFormatter = findUpvalue(KE.AuraStyle.RegisterRegions, "GetDurationFormatter")
        getDurationFormatter({})

        assert.equals(3600, breakpoints[1].threshold)
        assert.equals("%dh", breakpoints[1].format)
        assert.equals(3600, breakpoints[1].components[1].div)
        assert.equals("down", breakpoints[1].components[1].rounding)
    end)

    -- Down, not up: the Cooldown Manager's icons keep the game's own countdown
    -- numbers while these displays draw their own text, and a rounding flip
    -- here silently puts the same buff a second apart between the two.
    it("rounds the sub-minute seconds DOWN, so it agrees with the game's own numbers", function()
        local breakpoints
        _G.C_StringUtil = {
            CreateNumericRuleFormatter = function()
                return {
                    SetBreakpoints = function(_, value)
                        breakpoints = value
                    end,
                }
            end,
        }
        _G.Enum = {
            NumericRuleFormatRounding = {
                Down = "down",
                Up = "up",
            },
        }

        local KE = helpers.loadModule("Modules/Combat/AuraEngine/Style.lua")
        local getDurationFormatter = findUpvalue(KE.AuraStyle.RegisterRegions, "GetDurationFormatter")
        getDurationFormatter({})

        assert.equals(0, breakpoints[3].threshold)
        assert.equals("%d", breakpoints[3].format)
        assert.equals("down", breakpoints[3].rounding)
    end)

    it("formats preview durations in hours from the one-hour boundary", function()
        local Preview = L.loadAuraPreview()
        local buildFrames = findUpvalue(Preview.Enter, "BuildFrames")
        local populateEntryContent = findUpvalue(buildFrames, "PopulateEntryContent")
        local updateEntryTimer = findUpvalue(populateEntryContent, "UpdateEntryTimer")
        local formatRemaining = findUpvalue(updateEntryTimer, "FormatRemaining")

        assert.equals("59m", formatRemaining(3599))
        assert.equals("1h", formatRemaining(3600))
        assert.equals("23h", formatRemaining(84360))
    end)
end)

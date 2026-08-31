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

local function loadPreviewLocal(name, stopAtUpdate)
    local Preview = L.loadAuraPreview()
    local buildFrames = findUpvalue(Preview.Enter, "BuildFrames")
    local populateEntryContent = findUpvalue(buildFrames, "PopulateEntryContent")
    local updateEntryTimer = findUpvalue(populateEntryContent, "UpdateEntryTimer")
    if stopAtUpdate then return updateEntryTimer end
    return findUpvalue(updateEntryTimer, name)
end

local function installFormatterStubs()
    local captured = {}
    _G.C_StringUtil = {
        CreateNumericRuleFormatter = function()
            local formatter = {}
            formatter.SetBreakpoints = function(_, value)
                captured.breakpoints = value
            end
            return formatter
        end,
    }
    _G.Enum = {
        NumericRuleFormatRounding = {
            Down = "down",
            Up = "up",
        },
    }
    return captured
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

        local KE = helpers.loadModule("Modules/Combat/AuraEngine/Rules.lua")
        helpers.loadModule("Modules/Combat/AuraEngine/Style.lua", KE)
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

        local KE = helpers.loadModule("Modules/Combat/AuraEngine/Rules.lua")
        helpers.loadModule("Modules/Combat/AuraEngine/Style.lua", KE)
        local getDurationFormatter = findUpvalue(KE.AuraStyle.RegisterRegions, "GetDurationFormatter")
        getDurationFormatter({})

        assert.equals(0, breakpoints[3].threshold)
        assert.equals("%d", breakpoints[3].format)
        assert.equals("down", breakpoints[3].rounding)
    end)

    it("leaves the whole-second rule alone at a threshold of zero", function()
        local captured = installFormatterStubs()
        local KE = helpers.loadModule("Modules/Combat/AuraEngine/Rules.lua")
        helpers.loadModule("Modules/Combat/AuraEngine/Style.lua", KE)
        local getDurationFormatter = findUpvalue(KE.AuraStyle.RegisterRegions, "GetDurationFormatter")
        getDurationFormatter({ DecimalThreshold = 0 })

        assert.equals(3, #captured.breakpoints)
        assert.equals(0, captured.breakpoints[3].threshold)
        assert.equals(1, captured.breakpoints[3].step)
        assert.equals("%d", captured.breakpoints[3].format)
        assert.equals("down", captured.breakpoints[3].rounding)
    end)

    it("adds a tenths rule under a non-zero threshold", function()
        local captured = installFormatterStubs()
        local KE = helpers.loadModule("Modules/Combat/AuraEngine/Rules.lua")
        helpers.loadModule("Modules/Combat/AuraEngine/Style.lua", KE)
        local getDurationFormatter = findUpvalue(KE.AuraStyle.RegisterRegions, "GetDurationFormatter")
        getDurationFormatter({ DecimalThreshold = 5 })

        assert.equals(4, #captured.breakpoints)
        assert.equals(5, captured.breakpoints[3].threshold)
        assert.equals(1, captured.breakpoints[3].step)
        assert.equals("%d", captured.breakpoints[3].format)
        assert.equals(0, captured.breakpoints[4].threshold)
        assert.equals(0.1, captured.breakpoints[4].step)
        assert.equals("%.1f", captured.breakpoints[4].format)
    end)

    it("rounds both sub-minute rules DOWN when a threshold is set", function()
        local captured = installFormatterStubs()
        local KE = helpers.loadModule("Modules/Combat/AuraEngine/Rules.lua")
        helpers.loadModule("Modules/Combat/AuraEngine/Style.lua", KE)
        local getDurationFormatter = findUpvalue(KE.AuraStyle.RegisterRegions, "GetDurationFormatter")
        getDurationFormatter({ DecimalThreshold = 3 })

        assert.equals("down", captured.breakpoints[3].rounding)
        assert.equals("down", captured.breakpoints[4].rounding)
    end)

    -- The four GUI builders present this value and both rendering paths act on
    -- it, so a disagreement here shows a stored 11 as a slider reading 10 while
    -- the timer is actually off.
    it("normalizes a stored threshold to what the displays will act on", function()
        local KE = helpers.loadModule("Modules/Combat/AuraEngine/Rules.lua")
        local normalize = KE.AuraRules.NormalizeDecimalThreshold

        for _, value in ipairs({ "abc", -1, 11, 3.5, 0 / 0, 1 / 0, -1 / 0, true, {} }) do
            assert.equals(0, normalize(value))
        end
        assert.equals(0, normalize(nil))

        assert.equals(0, normalize(0))
        assert.equals(1, normalize(1))
        assert.equals(10, normalize(10))
        assert.equals(4, normalize("4"))
    end)

    -- A threshold that is not a whole second between 0 and 10 has no meaning on
    -- a one-decimal display, so every such value resolves to off rather than
    -- being clamped to an edge.
    it("resolves any threshold that is not a whole 0-10 to off", function()
        local captured = installFormatterStubs()
        local KE = helpers.loadModule("Modules/Combat/AuraEngine/Rules.lua")
        helpers.loadModule("Modules/Combat/AuraEngine/Style.lua", KE)
        local getDurationFormatter = findUpvalue(KE.AuraStyle.RegisterRegions, "GetDurationFormatter")

        for _, value in ipairs({ "abc", -1, 11, 3.5, 0 / 0, true }) do
            getDurationFormatter({ DecimalThreshold = value })
            assert.equals(3, #captured.breakpoints)
        end

        getDurationFormatter({})
        assert.equals(3, #captured.breakpoints)

        for _, value in ipairs({ 1, 10, "4" }) do
            getDurationFormatter({ DecimalThreshold = value })
            assert.equals(4, #captured.breakpoints)
            assert.equals(tonumber(value), captured.breakpoints[3].threshold)
        end
    end)

    it("rebuilds the cached formatter only when the resolved threshold changes", function()
        installFormatterStubs()
        local KE = helpers.loadModule("Modules/Combat/AuraEngine/Rules.lua")
        helpers.loadModule("Modules/Combat/AuraEngine/Style.lua", KE)
        local getDurationFormatter = findUpvalue(KE.AuraStyle.RegisterRegions, "GetDurationFormatter")

        local settings = { DecimalThreshold = 0 }
        local first = getDurationFormatter(settings)
        assert.is_true(first == getDurationFormatter(settings))

        -- Both resolve to off, so the cached formatter still stands.
        settings.DecimalThreshold = 99
        assert.is_true(first == getDurationFormatter(settings))

        settings.DecimalThreshold = 3
        local decimal = getDurationFormatter(settings)
        assert.is_false(first == decimal)
        assert.is_true(decimal == getDurationFormatter(settings))

        settings.DecimalThreshold = 2
        assert.is_false(decimal == getDurationFormatter(settings))
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

    -- Floors, like the live formatter: rounding up reads a second ahead of the
    -- same buff on a live icon.
    it("floors the preview seconds when no threshold is set", function()
        local formatRemaining = loadPreviewLocal("FormatRemaining")

        assert.equals("4", formatRemaining(4.9))
        assert.equals("4", formatRemaining(4.0))
        assert.equals("", formatRemaining(0))
    end)

    it("shows tenths under the threshold and whole seconds at or above it", function()
        local formatRemaining = loadPreviewLocal("FormatRemaining")

        assert.equals("2.9", formatRemaining(2.99, 3))
        assert.equals("0.4", formatRemaining(0.45, 3))
        assert.equals("3", formatRemaining(3, 3))
        assert.equals("9", formatRemaining(9.7, 3))
        assert.equals("4", formatRemaining(4.9, 0))
    end)

    it("ticks ten times faster only while a threshold is set", function()
        local Preview = L.loadAuraPreview()
        local buildFrames = findUpvalue(Preview.Enter, "BuildFrames")
        local getTickInterval = findUpvalue(buildFrames, "GetTickInterval")

        assert.equals(0.5, getTickInterval(0))
        assert.equals(0.05, getTickInterval(3))
    end)

    it("repaints the preview timer only when its string changes", function()
        local updateEntryTimer = loadPreviewLocal("UpdateEntryTimer", true)

        local painted, lastPainted = 0, nil
        local frame = { keTimer = { SetText = function(_, value)
            painted = painted + 1
            lastPainted = value
        end } }
        local entry = { expirationTime = 100 }

        updateEntryTimer(frame, entry, 90)
        assert.equals(1, painted)
        assert.equals("10", frame.keTimerLast)
        assert.equals("10", lastPainted)

        -- 10.3 seconds left, which still floors to the same string.
        updateEntryTimer(frame, entry, 89.7)
        assert.equals(1, painted)

        updateEntryTimer(frame, entry, 91)
        assert.equals(2, painted)
        assert.equals("9", frame.keTimerLast)
    end)
end)

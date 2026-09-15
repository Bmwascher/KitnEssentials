-- luacheck: std lua51+busted
-- Tier 1: Modules/Diagnostics/Tracer.lua. ParseCaller and FormatArg are pure
-- functions; the hooks, the ticker and the slash route are in-game only.
local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

local function loadTracer(overrides)
    mock.install(overrides)
    helpers.installAddonShim()
    return helpers.loadModule("Modules/Diagnostics/Tracer.lua", { Print = function() end })
end

local function stack(...)
    return table.concat({ ... }, "\n")
end

describe("Modules/Diagnostics/Tracer.lua", function()
    after_each(function()
        mock.reset()
    end)

    describe("Tracer.ParseCaller", function()
        local blizz  = '[string "@Interface/AddOns/Blizzard_UIParent/Mainline/UIParent.lua"]:1234: in function `UIParent_ManageFramePositions\''
        local tracer = '[string "@Interface/AddOns/KitnEssentials/Modules/Diagnostics/Tracer.lua"]:52: in function <Tracer.lua:50>'
        local mover  = '[string "@Interface/AddOns/KitnEssentials/Core/EditMode.lua"]:310: in function `Drag\''
        local other  = '[string "@Interface/AddOns/OtherAddon/Core.lua"]:77: in function ?'

        local cases = {
            { name = "skips Blizzard and tracer lines and returns the first addon line",
              stack = stack(tracer, blizz, mover, other),
              want = "KitnEssentials/Core/EditMode.lua:310" },
            { name = "falls back to the first addon line when every line is Blizzard or the tracer",
              stack = stack(tracer, blizz),
              want = "KitnEssentials/Modules/Diagnostics/Tracer.lua:52" },
            { name = "returns ? when no line names an addon file",
              stack = stack("[C]: in function `SetPoint'", "(tail call): ?"),
              want = "?" },
            { name = "returns ? for a non-string",
              stack = nil,
              want = "?" },
        }
        for _, c in ipairs(cases) do
            it(c.name, function()
                local KE = loadTracer()
                assert.equal(c.want, KE.Tracer.ParseCaller(c.stack))
            end)
        end
    end)

    describe("Tracer.FormatArg", function()
        it("prints <secret> for a secret value before any other formatting", function()
            local KE = loadTracer({
                issecretvalue = function(v) return type(v) == "table" and v.__secret == true end,
            })
            local secret = { __secret = true, GetName = function() return "NotThis" end }
            assert.equal("<secret>", KE.Tracer.FormatArg(secret))
        end)
    end)
end)

-- Tier: a refusal rule. MDT's widget skinner joins the AceGUI widget
-- skinners when the file loads, but it may skin nothing unless the MDT skin
-- has run with its row's dispatch gate open. A debug rerun calls that skin
-- even for a row that is off, so the gate is asked again there. The gate's
-- own row and suppression logic is runList's, covered in skinapi_spec.lua.
--
-- KE.Skins is a recording stub, not a Blizzard fake: the case only asks
-- whether the skinner touched the widget.

local helpers = require("dev.spec._helpers")

local function loadMDTSkin()
    local state = { stripped = {}, gateOpen = false }
    _G.C_Timer = nil
    _G.MDTFrame = nil
    local S = {
        AceWidgetSkinners = {},
        StripTextures = function(frame) state.stripped[#state.stripped + 1] = frame end,
        SkinEnabled = function(key, addon)
            assert.equals("MythicDungeonTools", key)
            assert.equals("MythicDungeonTools_UI", addon)
            return state.gateOpen
        end,
        Register = function(_, _, fn) state.runSkin = fn end,
    }
    helpers.loadModule("Modules/Skinning/Addons/MythicDungeonTools.lua", { Skins = S })
    state.skinWidget = S.AceWidgetSkinners[1]
    return state
end

describe("MDT widget skin: follows the MDT skin's dispatch gate", function()
    it("skins a widget only after the MDT skin ran with its gate open", function()
        local s = loadMDTSkin()
        local widget = { type = "MDTNewPullButton", frame = {} }

        -- Before the MDT skin has run.
        s.skinWidget(widget)
        assert.equals(0, #s.stripped)

        -- A debug rerun with the row off.
        s.gateOpen = false
        s.runSkin()
        s.skinWidget(widget)
        assert.equals(0, #s.stripped)

        -- The dispatch with the row on.
        s.gateOpen = true
        s.runSkin()
        s.skinWidget(widget)
        assert.equals(1, #s.stripped)
        assert.equals(widget.frame, s.stripped[1])
    end)
end)

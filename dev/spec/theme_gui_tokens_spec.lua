-- Tier 1: the settings-window color keys. KE.BlendColor makes the opaque
-- sub-tab fills, so a wrong mix paints every selected and hovered tab wrong.
-- The GUI-only keys must stay out of every theme mode's reach: a mode or a
-- Customize pick that overrode them would re-tint fields the theme does not
-- control.
local L = require("dev.spec._ke_loader")

local GUI_KEYS = {
    "fieldBg", "fieldBorder", "controlBg", "controlHover", "controlPressed",
    "controlBorder", "listBg", "listBorder", "thumbRest", "thumbHover",
    "knobOff", "divider",
}

local function Byte(v) return math.floor(v * 255 + 0.5) end

describe("KE settings-window color keys", function()
    local KE

    before_each(function()
        KE = L.loadAddonTheme()
        -- RefreshTheme notifies modules through this global; none exist here.
        _G.KitnEssentials = nil
    end)

    it("BlendColor mixes each channel by the weight and ignores both alphas", function()
        local pink = { 1.0, 0.0, 0.549, 0.3 }
        local cases = {
            { alpha = 0.20, base = { 0.031, 0.031, 0.031, 0.8 }, bytes = { 57, 6, 34 } },
            { alpha = 0.12, base = { 0.090, 0.090, 0.090, 0.5 }, bytes = { 51, 20, 37 } },
        }
        for _, c in ipairs(cases) do
            local r, g, b = KE.BlendColor(pink, c.alpha, c.base)
            assert.same(c.bytes, { Byte(r), Byte(g), Byte(b) })
        end
    end)

    it("keeps the GUI-only keys at their defaults in every theme mode", function()
        local foreign = {}
        for _, key in ipairs(GUI_KEYS) do foreign[key] = { 0.9, 0.1, 0.3, 1 } end
        for _, mode in ipairs({ "preset", "class", "custom" }) do
            KE.db = { global = { Theme = { Mode = mode, Preset = "KitnUI", Custom = foreign } } }
            KE:RefreshTheme()
            for _, key in ipairs(GUI_KEYS) do
                assert.is_table(KE.Theme[key], mode .. " " .. key)
                assert.same(KE.ThemeDefaults[key], KE.Theme[key], mode .. " " .. key)
            end
        end
    end)
end)

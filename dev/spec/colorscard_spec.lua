-- Tier 1: GUI/GUIWidgets/GUI-ColorsCard.lua -- the colour read/write pair.
-- This is the only logic in the card that can silently discard a saved colour,
-- so it is the only part with a spec; layout and gating are smoke-tested.
local helpers = require("dev.spec._helpers")

describe("ColorsCard colour read and write", function()
    local KE

    before_each(function()
        -- The widget binds KE.GUIFrame and KE.Theme at load and defines a
        -- method on GUIFrame, so both must exist before loadModule runs.
        KE = helpers.loadModule("GUI/GUIWidgets/GUI-ColorsCard.lua", {
            GUIFrame = {},
            Theme = {},
        })
    end)

    it("reads a stored colour", function()
        local r, g, b, a = KE:ReadCardColor({ BarColor = { 0.1, 0.2, 0.3, 0.4 } },
            { key = "BarColor", default = { 1, 1, 1, 1 } })
        assert.equals(0.1, r); assert.equals(0.2, g); assert.equals(0.3, b); assert.equals(0.4, a)
    end)

    it("falls back to the default when the key is absent", function()
        local r, g, b, a = KE:ReadCardColor({},
            { key = "BarColor", default = { 0.5, 0.6, 0.7, 0.8 } })
        assert.equals(0.5, r); assert.equals(0.6, g); assert.equals(0.7, b); assert.equals(0.8, a)
    end)

    it("defaults alpha to 1 when the stored colour omits it", function()
        local _, _, _, a = KE:ReadCardColor({ BarColor = { 0.1, 0.2, 0.3 } },
            { key = "BarColor", default = { 1, 1, 1, 1 } })
        assert.equals(1, a)
    end)

    it("prefers the stored colour over the default", function()
        local r = KE:ReadCardColor({ BarColor = { 0, 0, 0, 1 } },
            { key = "BarColor", default = { 1, 1, 1, 1 } })
        assert.equals(0, r)
    end)

    it("writes a colour as a four-element array", function()
        local db = {}
        KE:WriteCardColor(db, { key = "BarColor" }, 0.1, 0.2, 0.3, 0.4)
        assert.same({ 0.1, 0.2, 0.3, 0.4 }, db.BarColor)
    end)

    it("touches only its own key", function()
        local db = { BarColor = { 1, 1, 1, 1 }, TextColor = { 0, 0, 0, 1 } }
        KE:WriteCardColor(db, { key = "BarColor" }, 0.5, 0.5, 0.5, 1)
        assert.same({ 0, 0, 0, 1 }, db.TextColor)
    end)
end)

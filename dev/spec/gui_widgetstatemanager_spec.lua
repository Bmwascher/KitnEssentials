-- Tier 2: GUI/GUIMain/GUI-WidgetStateManager.lua -- the stale-manager refusal.
-- A manager outlives its page whenever a closure holds it. Once the page is
-- rebuilt, its cards and widgets are reused by the next page, so an old
-- manager must not gray them out. Pooled objects carry a generation that
-- every release advances; unpooled ones carry none.
local helpers = require("dev.spec._helpers")

describe("WidgetStateManager generation guard", function()
    local manager, savedMixin

    before_each(function()
        savedMixin = _G.Mixin
        -- Blizzard's Mixin copies fields; the manager is built with it.
        _G.Mixin = function(object, ...)
            for i = 1, select("#", ...) do
                for key, value in pairs((select(i, ...))) do object[key] = value end
            end
            return object
        end
        local GUIFrame = {}
        helpers.loadModule("GUI/GUIMain/GUI-WidgetStateManager.lua", { GUIFrame = GUIFrame })
        manager = GUIFrame:CreateWidgetStateManager()
    end)

    after_each(function()
        _G.Mixin = savedMixin
    end)

    local function widget(gen)
        local w = { _keGen = gen, states = {} }
        function w:SetEnabled(enabled) self.states[#self.states + 1] = enabled end
        return w
    end

    for _, method in ipairs({ "UpdateAll", "UpdateGroup" }) do
        it(method .. " skips a widget released since Register and still drives an unpooled one", function()
            local reused = widget(0)
            local unpooled = widget(nil)
            manager:Register(reused, "all")
            manager:Register(unpooled, "all")

            -- Released and handed to another page.
            reused._keGen = 1

            if method == "UpdateAll" then
                manager:UpdateAll(false)
            else
                manager:UpdateGroup("all", false)
            end
            assert.same({}, reused.states)
            assert.same({ false }, unpooled.states)
        end)
    end
end)

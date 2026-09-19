-- The repaint dispatch on ReadyCheckConsumables. A category the user turned
-- off, or whose contextual predicate says no, must not have its worker
-- called; the predicate is asked once; while aura identities are hidden the
-- weapon slots still repaint and the aura-driven ones do not; requests made
-- in one frame collapse into one repaint; a repaint queued before the row
-- died paints nothing; layout is not applied in combat, where the slot
-- buttons are protected; and a running glow is not restarted until the
-- teardown stop clears it. The workers, predicates and layout are stubbed
-- on the module instance because the dispatch is the seam under test.
-- The one stateful fake is C_Timer.After, which the loader captures so the
-- spec can fire the next-frame callback itself.

local L = require("dev.spec._ke_loader")

local function liveFrame()
    return setmetatable({
        IsVisible = function() return true end,
        Hide = function() end,
        SetAlpha = function() end,
        stateFrame = {},
    }, { __index = function() return function() end end })
end

local function stubButton()
    return {
        statusTexture = { SetTexture = function() end, Show = function() end, Hide = function() end },
        texture = { SetDesaturated = function() end, SetTexture = function() end },
        timeLeft = { SetText = function() end, SetTextColor = function() end },
        countText = { SetText = function() end },
        click = { Hide = function() end, Show = function() end, SetAttribute = function() end },
    }
end

describe("ReadyCheckConsumables UpdateAllIcons dispatch", function()
    local WORKERS = {
        "UpdateFood", "UpdateFlask", "UpdateWeaponEnchant", "UpdateRune",
        "UpdateHealthstone", "UpdateClassSlot",
    }
    local RCC, KE, seams, called, laidOut

    local function enableEveryCategory()
        for _, key in ipairs({ "ShowFood", "ShowFlask", "ShowWeaponOil", "ShowOffHandOil",
                               "ShowAugmentRune", "ShowHealthstone", "ShowClassItem" }) do
            RCC.db[key] = true
        end
        RCC.OffhandIsWeapon = function() return true end
        RCC.IsWarlockInGroup = function() return true end
        seams.playerClass = "WARLOCK"
    end

    before_each(function()
        RCC, KE, seams = L.loadReadyCheckConsumables()
        RCC.frame = liveFrame()
        RCC.buttons = { food = stubButton(), flask = stubButton(), rune = stubButton() }
        called, laidOut = {}, nil
        for _, name in ipairs(WORKERS) do
            RCC[name] = function(_, arg) called[name] = (called[name] or 0) + 1; called[name .. ":" .. tostring(arg)] = true end
        end
        RCC._LayoutRow = function(_, _, _, visibility) laidOut = visibility end
        enableEveryCategory()
    end)

    it("does not call a disabled category's worker", function()
        local cases = {
            { key = "ShowFood",        absent = "UpdateFood" },
            { key = "ShowFlask",       absent = "UpdateFlask" },
            { key = "ShowWeaponOil",   absent = "UpdateWeaponEnchant:oil" },
            { key = "ShowOffHandOil",  absent = "UpdateWeaponEnchant:oiloh" },
            { key = "ShowAugmentRune", absent = "UpdateRune" },
            { key = "ShowHealthstone", absent = "UpdateHealthstone" },
            { key = "ShowClassItem",   absent = "UpdateClassSlot" },
        }
        for _, c in ipairs(cases) do
            enableEveryCategory()
            RCC.db[c.key] = false
            called = {}
            RCC:UpdateAllIcons(true)
            assert.is_nil(called[c.absent], c.key)
            local ran = 0
            for _, name in ipairs(WORKERS) do ran = ran + (called[name] or 0) end
            assert.equals(6, ran, c.key)
        end
    end)

    it("skips a slot whose contextual predicate is false and asks the predicate once", function()
        local cases = {
            { predicate = "OffhandIsWeapon",  absent = "UpdateWeaponEnchant:oiloh", present = "UpdateWeaponEnchant:oil" },
            { predicate = "IsWarlockInGroup", absent = "UpdateHealthstone",          present = "UpdateFlask" },
        }
        for _, c in ipairs(cases) do
            enableEveryCategory()
            local asked = 0
            RCC[c.predicate] = function() asked = asked + 1; return false end
            called = {}
            RCC:UpdateAllIcons(true)
            assert.is_nil(called[c.absent], c.predicate)
            assert.is_truthy(called[c.present], c.predicate)
            assert.equals(1, asked, c.predicate)
        end
    end)

    it("repaints the weapon slots and lays out while aura identities are hidden, with no scan and no aura-driven worker", function()
        KE.AreAuraIdentitiesHidden = function() return true end
        local unavailable = {}
        RCC._PaintUnavailable = function(_, btn) unavailable[#unavailable + 1] = btn end
        RCC:UpdateAllIcons(true)
        assert.equals(0, seams.counts.scans)
        assert.is_nil(called.UpdateFood)
        assert.is_nil(called.UpdateFlask)
        assert.is_nil(called.UpdateRune)
        assert.equals(2, called.UpdateWeaponEnchant)
        assert.equals(3, #unavailable)
        assert.is_not_nil(laidOut)
    end)
end)

describe("ReadyCheckConsumables _LayoutRow", function()
    it("lays nothing out in combat and lays out on the next pass out of combat", function()
        local RCC, _, seams = L.loadReadyCheckConsumables()
        local anchored = 0
        local btn = {
            SetSize = function() end, Show = function() end, Hide = function() end,
            ClearAllPoints = function() end, SetPoint = function() anchored = anchored + 1 end,
            statusTexture = { SetSize = function() end },
        }
        local container = { SetWidth = function() end, SetHeight = function() end }

        seams.combat.inCombat = true
        RCC:_LayoutRow(container, { btn }, { true })
        assert.equals(0, anchored)
        assert.is_nil(container._layoutKey)

        seams.combat.inCombat = false
        RCC:_LayoutRow(container, { btn }, { true })
        assert.equals(1, anchored)
    end)
end)

describe("ReadyCheckConsumables RequestRefresh", function()
    local RCC, seams, visible

    local function fireTimers()
        local fns = seams.timers
        seams.timers = {}
        for i = 1, #fns do fns[i]() end
    end

    before_each(function()
        local loaded = { L.loadReadyCheckConsumables() }
        RCC, seams = loaded[1], loaded[3]
        visible = true
        RCC.frame = liveFrame()
        RCC.frame.IsVisible = function() return visible end
        RCC.buttons = {}
        RCC._LayoutRow = function() end
    end)

    it("collapses every request made in one frame into one repaint", function()
        for _ = 1, 5 do RCC:RequestRefresh() end
        assert.equals(1, #seams.timers)
        fireTimers()
        assert.equals(1, seams.counts.scans)
    end)

    it("repaints nothing once the row died before the queued repaint fired, and takes a new request afterwards", function()
        RCC:RequestRefresh()
        visible = false
        fireTimers()
        assert.equals(0, seams.counts.scans)

        visible = true
        RCC:RequestRefresh()
        assert.equals(1, #seams.timers)
    end)

    it("schedules nothing for a row that is not live", function()
        visible = false
        RCC:RequestRefresh()
        assert.equals(0, #seams.timers)
    end)
end)

describe("ReadyCheckConsumables glow guard", function()
    it("does not restart a running glow, and the teardown stop clears the flag", function()
        local RCC, _, seams = L.loadReadyCheckConsumables()
        RCC.frame = liveFrame()
        local btn = stubButton()
        RCC.buttons = { [5] = btn, rune = btn }
        RCC.db.UnlimitedRunesOnly = true
        seams.bagCount = 1

        RCC:UpdateRune({})
        RCC:UpdateRune({})
        assert.equals(1, seams.glow.starts)
        assert.is_true(btn.glowActive)

        RCC:HideFrame()
        assert.is_false(btn.glowActive)
        RCC:UpdateRune({})
        assert.equals(2, seams.glow.starts)
    end)
end)

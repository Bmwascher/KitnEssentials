-- Which item the flask and weapon clicks nominate. A flask tie at equal
-- rank goes to the Fleeting form and never to table iteration order; the
-- flask comparator orders every pair one way; the remembered stat outranks
-- the spec's priority only while it is stocked; each hand keeps its own
-- enhancement memory; the weapon fallback offers nothing the equipped
-- weapon cannot take and nothing at all when no compatible item is stocked;
-- an empty off hand arms no click; and the weapon order is memory, the
-- memory's other rank, oil, then rank. A nominated item the client has not
-- cached arms no click and has its data requested once, and the arrival
-- schedules one repaint only while the row is live. Bags, the equipped
-- weapon, its subclass and cached names are plain loader seams; the click
-- overlay is a recording stub because the nominated item is read back from
-- its attributes, never from the secure frame.

local L = require("dev.spec._ke_loader")

local MASTERY_PERSONAL_R1, MASTERY_PERSONAL_R2 = 241323, 241322
local MASTERY_FLEETING_R1 = 245932
local HASTE_PERSONAL_R2 = 241324
local OIL_R1, OIL_R2 = 243733, 243734
local WHETSTONE_R1, WHETSTONE_R2 = 237370, 237371
local WEIGHTSTONE_R2 = 237369
local ZOOMSHOTS_R2 = 257750
local SWORD_1H, STAFF, BOW, FISHING_POLE = 7, 10, 2, 20

local function recordingButton()
    local btn = {
        statusTexture = { SetTexture = function() end, Show = function() end, Hide = function() end },
        texture = { SetDesaturated = function() end, SetTexture = function() end },
        timeLeft = { SetText = function() end, SetTextColor = function() end },
        countText = {},
        click = { attributes = {}, shown = false },
    }
    btn.countText.SetText = function(_, s) btn.count = s end
    btn.click.SetAttribute = function(_, k, v) btn.click.attributes[k] = v end
    btn.click.Show = function() btn.click.shown = true end
    btn.click.Hide = function() btn.click.shown = false end
    return btn
end

local function stock(seams, ...)
    for i = 1, select("#", ...) do
        local itemID = select(i, ...)
        seams.bagCounts[itemID] = 5
        seams.itemNames[itemID] = "item " .. itemID
    end
end

describe("ReadyCheckConsumables flask selection", function()
    local RCC, seams, btn

    before_each(function()
        local _
        RCC, _, seams = L.loadReadyCheckConsumables()
        btn = recordingButton()
        RCC.buttons = { flask = btn }
        RCC._GetSpecFlaskPriority = function() return nil end
    end)

    it("nominates the Fleeting flask at equal rank, and the higher rank across forms", function()
        local cases = {
            { stocked = { MASTERY_PERSONAL_R1, MASTERY_FLEETING_R1 }, pick = MASTERY_FLEETING_R1 },
            { stocked = { MASTERY_PERSONAL_R2, MASTERY_FLEETING_R1 }, pick = MASTERY_PERSONAL_R2 },
        }
        for _, c in ipairs(cases) do
            seams.bagCounts, seams.itemNames = {}, {}
            stock(seams, unpack(c.stocked))
            RCC.db.LastFlaskStat = "mastery"
            RCC:UpdateFlaskClick()
            assert.equals("/stopmacro [combat]\n/use item " .. c.pick, btn.click.attributes.macrotext)
            assert.equals("5", btn.count)
        end
    end)

    it("orders every flask pair one way only, in the sorted order", function()
        local order, before = RCC._FlaskOrder, RCC._FlaskBefore
        for i = 1, #order do
            assert.is_false(before(order[i], order[i]))
            for j = i + 1, #order do
                assert.is_true(before(order[i], order[j]))
                assert.is_false(before(order[j], order[i]))
            end
        end
    end)

    it("uses the remembered stat over the spec priority while it is stocked, and falls through when not", function()
        RCC._GetSpecFlaskPriority = function() return { "haste" } end
        RCC.db.LastFlaskStat = "mastery"
        stock(seams, MASTERY_PERSONAL_R2, HASTE_PERSONAL_R2)
        RCC:UpdateFlaskClick()
        assert.equals("/stopmacro [combat]\n/use item " .. MASTERY_PERSONAL_R2, btn.click.attributes.macrotext)

        seams.bagCounts[MASTERY_PERSONAL_R2] = 0
        RCC:UpdateFlaskClick()
        assert.equals("/stopmacro [combat]\n/use item " .. HASTE_PERSONAL_R2, btn.click.attributes.macrotext)

        seams.bagCounts[HASTE_PERSONAL_R2] = 0
        RCC:UpdateFlaskClick()
        assert.is_false(btn.click.shown)
        assert.equals("", btn.count)
    end)
end)

describe("ReadyCheckConsumables weapon selection", function()
    local RCC, seams, mh, oh

    local function equip(slot, subclass)
        local itemID = 900000 + slot
        seams.equipped[slot] = itemID
        seams.itemInfo[itemID] = { 2, subclass }
    end

    before_each(function()
        local _
        RCC, _, seams = L.loadReadyCheckConsumables()
        mh, oh = recordingButton(), recordingButton()
        RCC.buttons = { oil = mh, oiloh = oh }
    end)

    it("keeps main-hand and off-hand memory apart", function()
        equip(16, SWORD_1H)
        equip(17, SWORD_1H)
        stock(seams, WHETSTONE_R2, OIL_R2)
        seams.enchants[16] = { enchantID = 7905, remainingTimeMs = 60000 }
        seams.enchants[17] = { enchantID = 8052, remainingTimeMs = 60000 }
        RCC:UpdateWeaponEnchant("oil", 16)
        RCC:UpdateWeaponEnchant("oiloh", 17)
        assert.equals(WHETSTONE_R2, RCC.db.LastWeaponEnchantItemMH)
        assert.equals(OIL_R2, RCC.db.LastWeaponEnchantItemOH)
        assert.equals("item " .. WHETSTONE_R2, mh.click.attributes.item)
        assert.equals("item " .. OIL_R2, oh.click.attributes.item)
        assert.equals("16", mh.click.attributes["target-slot"])
        assert.equals("17", oh.click.attributes["target-slot"])
    end)

    it("never offers an enhancement the weapon cannot take, and offers nothing when none fits", function()
        local cases = {
            { weapon = STAFF,        stocked = { WHETSTONE_R2 },                 pick = nil },
            { weapon = SWORD_1H,     stocked = { ZOOMSHOTS_R2 },                 pick = nil },
            { weapon = FISHING_POLE, stocked = { OIL_R2 },                       pick = nil },
            { weapon = STAFF,        stocked = { WHETSTONE_R2, WEIGHTSTONE_R2 }, pick = WEIGHTSTONE_R2 },
            { weapon = BOW,          stocked = { WHETSTONE_R2, ZOOMSHOTS_R2 },   pick = ZOOMSHOTS_R2 },
        }
        for _, c in ipairs(cases) do
            seams.bagCounts, seams.itemNames = {}, {}
            equip(16, c.weapon)
            stock(seams, unpack(c.stocked))
            RCC:UpdateWeaponEnchant("oil", 16)
            if c.pick then
                assert.equals("item " .. c.pick, mh.click.attributes.item)
                assert.is_true(mh.click.shown)
                assert.equals("5", mh.count)
            else
                assert.is_false(mh.click.shown)
                assert.equals("", mh.count)
            end
        end
    end)

    it("arms no click on an off hand with nothing equipped", function()
        stock(seams, OIL_R2)
        RCC:UpdateWeaponEnchant("oiloh", 17)
        assert.is_false(oh.click.shown)
        assert.equals("", oh.count)
    end)

    it("prefers the remembered item, then its other rank, then oil, then rank", function()
        local cases = {
            { remembered = WHETSTONE_R2, stocked = { WHETSTONE_R2, OIL_R2 },     pick = WHETSTONE_R2 },
            { remembered = WHETSTONE_R2, stocked = { WHETSTONE_R1, OIL_R2 },     pick = WHETSTONE_R1 },
            { remembered = nil,          stocked = { WHETSTONE_R2, OIL_R1 },     pick = OIL_R1 },
            { remembered = nil,          stocked = { OIL_R1, OIL_R2 },           pick = OIL_R2 },
            { remembered = nil,          stocked = { WHETSTONE_R1, WHETSTONE_R2 }, pick = WHETSTONE_R2 },
            { remembered = ZOOMSHOTS_R2, stocked = { ZOOMSHOTS_R2, OIL_R1 },     pick = OIL_R1 },
        }
        for _, c in ipairs(cases) do
            seams.bagCounts, seams.itemNames = {}, {}
            equip(16, SWORD_1H)
            stock(seams, unpack(c.stocked))
            RCC.db.LastWeaponEnchantItemMH = c.remembered
            RCC:UpdateWeaponEnchant("oil", 16)
            assert.equals("item " .. c.pick, mh.click.attributes.item, tostring(c.remembered))
        end
    end)
end)

describe("ReadyCheckConsumables uncached item name", function()
    local RCC, seams, btn

    before_each(function()
        local _
        RCC, _, seams = L.loadReadyCheckConsumables()
        btn = recordingButton()
        RCC.buttons = { flask = btn }
        RCC._GetSpecFlaskPriority = function() return nil end
        seams.bagCounts[MASTERY_PERSONAL_R2] = 5
    end)

    it("arms no click on an uncached name and requests the item's data once across repaints", function()
        RCC:UpdateFlaskClick()
        RCC:UpdateFlaskClick()
        assert.is_false(btn.click.shown)
        assert.equals(1, #seams.itemLoads)
        assert.equals(MASTERY_PERSONAL_R2, seams.itemLoads[1].id)

        seams.itemNames[MASTERY_PERSONAL_R2] = "item " .. MASTERY_PERSONAL_R2
        RCC:UpdateFlaskClick()
        assert.is_true(btn.click.shown)
        assert.equals(1, #seams.itemLoads)
    end)

    it("schedules one repaint from the load only while the row is live", function()
        RCC:UpdateFlaskClick()
        local cases = { { live = true, timers = 1 }, { live = false, timers = 0 } }
        for i, c in ipairs(cases) do
            seams.timers = {}
            RCC._refreshPending = nil
            RCC._IsRowLive = function() return c.live end
            seams.itemLoads[1].fn()
            assert.equals(c.timers, #seams.timers, "case " .. i)
        end
    end)
end)

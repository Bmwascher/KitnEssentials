-- Which item the flask and weapon clicks nominate. A flask tie at equal
-- rank goes to the Fleeting form and never to table iteration order; the
-- flask comparator orders every pair one way; the remembered stat outranks
-- the spec's priority only while it is stocked; each hand keeps its own
-- enhancement memory; the weapon fallback offers nothing the equipped
-- weapon cannot take and nothing at all when no compatible item is stocked;
-- an empty off hand arms no click; and the weapon order is memory, the
-- memory's other rank, oil, then rank. Bags, the equipped weapon, its
-- subclass and cached names are plain loader seams; the click overlay is a
-- recording stub because the nominated item is read back from its
-- attributes, never from the secure frame.

local L = require("dev.spec._ke_loader")

local MASTERY_PERSONAL_R1, MASTERY_PERSONAL_R2 = 241323, 241322
local MASTERY_FLEETING_R1 = 245932
local HASTE_PERSONAL_R2 = 241324

local function recordingButton()
    local btn = {
        statusTexture = { SetTexture = function() end, Show = function() end, Hide = function() end },
        texture = { SetDesaturated = function() end, SetTexture = function() end },
        timeLeft = { SetText = function() end },
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

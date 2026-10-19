-- Tier: guard logic KE invented (tiered test policy): who owns the inspect
-- window's two paperdoll buttons, read from their anchors, when InspectPanel
-- may move or restore them, and the refusal of a secret label width. Moving
-- them is frame layout and is smoke-tested.
local helpers = require("dev.spec._helpers")

-- InspectPanel captures issecretvalue as a file-local at load, so the stub goes
-- in before loadModule. A row names the one value that reads as secret.
local secretValue

local function loadIP()
    local modules = helpers.installAddonShim()
    _G.issecretvalue = function(v) return v ~= nil and v == secretValue end
    helpers.loadModule("Modules/Skinning/CharacterPanel/InspectPanel.lua", {})
    return modules["InspectPanel"]
end

local DOLL, ITEMS, FRAME = { name = "paperdoll" }, { name = "items" }, { name = "inspect frame" }
-- Each pair is Blizzard's anchor, then this module's.
local VIEW = {
    { point = "TOP", rel = DOLL, relPoint = "TOP", x = 0, y = -39 },
    { point = "TOPRIGHT", rel = DOLL, relPoint = "TOP", x = -2, y = -39 },
}
local TALENTS = {
    { point = "BOTTOMRIGHT", rel = ITEMS, relPoint = "BOTTOMRIGHT", x = -10, y = 11 },
    { point = "TOPLEFT", rel = DOLL, relPoint = "TOP", x = 2, y = -39 },
}

describe("Inspect buttons: who placed a button", function()
    it("tells Blizzard's anchor, this module's and any other apart", function()
        local owner = loadIP()._AnchorOwner
        local cases = {
            { name = "Blizzard's View anchor", w = VIEW,
              a = { 1, "TOP", DOLL, "TOP", 0, -39 }, want = "blizzard" },
            { name = "this module's View anchor", w = VIEW,
              a = { 1, "TOPRIGHT", DOLL, "TOP", -2, -39 }, want = "ours" },
            { name = "the Talents anchor Dark Theme and ElvUI use", w = TALENTS,
              a = { 1, "TOPRIGHT", FRAME, "BOTTOMRIGHT", 0, -1 }, want = "other" },
            { name = "another point", w = TALENTS,
              a = { 1, "TOPRIGHT", ITEMS, "BOTTOMRIGHT", -10, 11 }, want = "other" },
            { name = "another relative frame", w = TALENTS,
              a = { 1, "BOTTOMRIGHT", FRAME, "BOTTOMRIGHT", -10, 11 }, want = "other" },
            { name = "another relative point", w = TALENTS,
              a = { 1, "BOTTOMRIGHT", ITEMS, "TOPRIGHT", -10, 11 }, want = "other" },
            { name = "x one pixel off", w = TALENTS,
              a = { 1, "BOTTOMRIGHT", ITEMS, "BOTTOMRIGHT", -9, 11 }, want = "other" },
            { name = "y one pixel off", w = TALENTS,
              a = { 1, "BOTTOMRIGHT", ITEMS, "BOTTOMRIGHT", -10, 12 }, want = "other" },
            { name = "an offset inside the tolerance", w = TALENTS,
              a = { 1, "BOTTOMRIGHT", ITEMS, "BOTTOMRIGHT", -10.004, 11 }, want = "blizzard" },
            { name = "a second anchor", w = TALENTS,
              a = { 2, "BOTTOMRIGHT", ITEMS, "BOTTOMRIGHT", -10, 11 }, want = "other" },
            { name = "no anchor", w = TALENTS, a = { 0 }, want = "other" },
            { name = "a secret anchor count", w = TALENTS,
              a = { 1, "BOTTOMRIGHT", ITEMS, "BOTTOMRIGHT", -10, 11 }, secret = 1, want = "other" },
            { name = "a secret point", w = VIEW,
              a = { 1, "TOPRIGHT", DOLL, "TOP", -2, -39 }, secret = "TOPRIGHT", want = "other" },
            { name = "a secret relative frame", w = TALENTS,
              a = { 1, "BOTTOMRIGHT", ITEMS, "BOTTOMRIGHT", -10, 11 }, secret = ITEMS, want = "other" },
            { name = "a secret relative point", w = VIEW,
              a = { 1, "TOPRIGHT", DOLL, "TOP", -2, -39 }, secret = "TOP", want = "other" },
            { name = "a secret x", w = TALENTS,
              a = { 1, "BOTTOMRIGHT", ITEMS, "BOTTOMRIGHT", -10, 11 }, secret = -10, want = "other" },
            { name = "a secret y", w = TALENTS,
              a = { 1, "BOTTOMRIGHT", ITEMS, "BOTTOMRIGHT", -10, 11 }, secret = 11, want = "other" },
        }
        for _, c in ipairs(cases) do
            secretValue = c.secret
            local a = c.a
            assert.equals(c.want, owner(c.w[1], c.w[2], a[1], a[2], a[3], a[4], a[5], a[6]), c.name)
        end
        secretValue = nil
    end)
end)

describe("Inspect buttons: when the module moves them", function()
    it("moves them only with the module on and neither placed by another skin", function()
        local stock = loadIP()._StockButtonCase
        local cases = {
            { name = "module off, both at Blizzard's", on = false, view = "blizzard", talents = "blizzard", want = false },
            { name = "Talents moved by another skin", on = true, view = "blizzard", talents = "other", want = false },
            { name = "View moved by another skin", on = true, view = "other", talents = "blizzard", want = false },
            { name = "both at Blizzard's", on = true, view = "blizzard", talents = "blizzard", want = true },
            { name = "both already at this module's", on = true, view = "ours", talents = "ours", want = true },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.want, stock(c.on, c.view, c.talents), c.name)
        end
    end)
end)

describe("Inspect buttons: when the module restores them", function()
    it("restores only when both still have this module's anchors", function()
        local owns = loadIP()._OwnsBoth
        local cases = {
            { name = "both at this module's", view = "ours", talents = "ours", want = true },
            { name = "Talents moved by another skin since", view = "ours", talents = "other", want = false },
            { name = "View moved by another skin since", view = "other", talents = "ours", want = false },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.want, owns(c.view, c.talents), c.name)
        end
    end)
end)

describe("Inspect buttons: the restored View width", function()
    it("pads a plain label width and refuses a secret or missing one", function()
        local width = loadIP()._RestoreViewWidth
        local cases = {
            { name = "a plain label width", text = 133, want = 163 },
            { name = "a secret label width", text = 133, secret = 133, want = nil },
            { name = "no label width", want = nil },
        }
        for _, c in ipairs(cases) do
            secretValue = c.secret
            assert.equals(c.want, width(c.text), c.name)
        end
        secretValue = nil
    end)
end)

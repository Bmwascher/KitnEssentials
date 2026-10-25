-- Ready Check Consumables on the Forever client. The Forever tables are read
-- whenever the Forever data is loaded, and each rule that decides a Forever slot gets a
-- table-driven case: which flask, elixir, stone, oil, poison or imbue a
-- click nominates, how a hand's enchant list splits into layers, which
-- layers a hand needs and which one its click applies, and the Warlock
-- clicks. The Forever data is a small table built here, never the generated
-- file; the slot button is a recording stub because the click is read back
-- from its attributes.

local L = require("dev.spec._ke_loader")

local function foreverData()
    return {
        food = {}, flasks = {}, elixirs = {}, enhancements = {}, imbues = {},
        healthstones = { { item = 5512 } },
        createHealthstone = { 6201, 6202 },
        soulstones = { { item = 16896, buff = 20765 }, { item = 5232, buff = 20707 } },
        createSoulstone = { 693, 20757 },
        icons = { food = 1, flask = 2, oil = 3, oiloh = 4, elixir = 5, healthstone = 6, class = 7 },
        byEnchant = {},
    }
end

local function recordingButton()
    local btn = {
        statusTexture = { SetTexture = function() end, Show = function() end, Hide = function() end },
        texture = { SetDesaturated = function() end, SetTexture = function() end },
        timeLeft = { SetText = function() end, SetTextColor = function() end },
        countText = { SetText = function() end },
        click = { attributes = {}, shown = false },
    }
    btn.click.SetAttribute = function(_, k, v) btn.click.attributes[k] = v end
    btn.click.Show = function() btn.click.shown = true end
    btn.click.Hide = function() btn.click.shown = false end
    return btn
end

describe("ReadyCheckConsumables Forever client selection", function()
    it("reads the Forever data whenever it is loaded, seen through the Warlock healthstone click and the page flag", function()
        local SOULWELL = "/stopmacro [combat]\n/cast Create Soulwell"
        for _, row in ipairs({
            { name = "Forever, two ranks known", forever = true,  data = true,  known = { 6201, 6202 },
              macro = "/stopmacro [combat]\n/cast spell 6202", uses = true },
            { name = "Forever, none known",      forever = true,  data = true,  known = {}, macro = nil, uses = true },
            { name = "baseline load, interface read failed (data, not Forever)", forever = false, data = true, known = { 6202 },
              macro = "/stopmacro [combat]\n/cast spell 6202", uses = true },
            { name = "Forever interface, no data", forever = true, data = false, known = { 6202 },
              macro = SOULWELL, uses = false },
        }) do
            local RCC, _, seams = L.loadReadyCheckConsumables(nil,
                { forever = row.forever, foreverData = row.data and foreverData() or nil })
            seams.playerClass = "WARLOCK"
            for _, id in ipairs(row.known) do seams.knownSpells[id] = true end
            local btn = recordingButton()
            RCC.buttons = { hs = btn }
            RCC:UpdateHealthstone()
            if row.macro then
                assert.is_true(btn.click.shown, row.name)
                assert.equals(row.macro, btn.click.attributes.macrotext, row.name)
            else
                assert.is_false(btn.click.shown, row.name)
            end
            assert.equals(row.uses, RCC.usesForeverData, row.name)
        end
    end)

    it("shows the fifth slot by ShowElixir on Forever and by ShowAugmentRune on retail", function()
        for _, row in ipairs({
            { name = "Forever, elixir off",        forever = true,  elixir = false, rune = true,  want = false },
            { name = "Forever, rune off ignored",  forever = true,  elixir = true,  rune = false, want = true },
            { name = "retail, rune off",           forever = false, elixir = true,  rune = false, want = false },
            { name = "retail, elixir off ignored", forever = false, elixir = false, rune = true,  want = true },
        }) do
            local RCC = L.loadReadyCheckConsumables(nil, { forever = row.forever, foreverData = row.forever and foreverData() or nil })
            RCC.IsWarlockInGroup = function() return false end
            RCC.db.ShowElixir, RCC.db.ShowAugmentRune = row.elixir, row.rune
            assert.equals(row.want, RCC:_ComputeVisibility()[5], row.name)
        end
    end)

    it("gives other classes no Healthstone click on Forever and leaves the click alone in combat", function()
        for _, row in ipairs({
            { name = "Priest: hidden",               class = "PRIEST",  combat = false, shown = false },
            { name = "Priest in combat: untouched",  class = "PRIEST",  combat = true,  shown = true },
            { name = "Warlock in combat: untouched", class = "WARLOCK", combat = true,  shown = true },
        }) do
            local RCC, _, seams = L.loadReadyCheckConsumables(nil, { forever = true, foreverData = foreverData() })
            seams.playerClass = row.class
            seams.knownSpells[6202] = true
            seams.combat.inCombat = row.combat
            local btn = recordingButton()
            btn.click.shown = true
            RCC.buttons = { hs = btn }
            RCC:UpdateHealthstone()
            assert.equals(row.shown, btn.click.shown, row.name)
            assert.is_nil(btn.click.attributes.macrotext, row.name)
        end
    end)
end)

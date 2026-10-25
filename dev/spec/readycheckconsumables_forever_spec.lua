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

describe("ReadyCheckConsumables Forever flask and elixir picks", function()
    local RCC

    before_each(function()
        RCC = L.loadReadyCheckConsumables()
    end)

    local function counts(map)
        return function(item) return map[item] or 0 end
    end

    it("nominates the remembered buff's stocked item, else the first stocked row", function()
        local FLASKS = { { item = 13512, buff = 17628 }, { item = 13511, buff = 17627 }, { item = 13510, buff = 17626 } }
        for _, row in ipairs({
            { name = "remembered and stocked", remembered = 17626, stock = { [13511] = 2, [13510] = 1 }, pick = 13510, n = 1 },
            { name = "remembered, none left",  remembered = 17626, stock = { [13511] = 2 },              pick = 13511, n = 2 },
            { name = "nothing remembered",     remembered = nil,   stock = { [13511] = 2, [13510] = 1 }, pick = 13511, n = 2 },
            { name = "nothing stocked",        remembered = 17626, stock = {},                           pick = nil,   n = 0 },
        }) do
            local pick, n = RCC._PickByBuff(FLASKS, row.remembered, counts(row.stock))
            assert.equals(row.pick, pick, row.name)
            assert.equals(row.n, n, row.name)
        end
    end)

    it("ignores a retail import's cauldron-only toggle on the Forever flask click", function()
        local data = foreverData()
        data.flasks = { { item = 13512, buff = 17628 } }
        local ForeverRCC, _, seams = L.loadReadyCheckConsumables(nil, { forever = true, foreverData = data })
        seams.bagCounts[13512] = 3
        seams.itemNames[13512] = "item 13512"
        ForeverRCC.db.CauldronFlasksOnly = true
        local btn = recordingButton()
        ForeverRCC.buttons = { flask = btn }
        ForeverRCC:UpdateFlaskClick()
        assert.is_true(btn.click.shown)
        assert.equals("/stopmacro [combat]\n/use item 13512", btn.click.attributes.macrotext)
    end)

    it("leaves the Forever flask click untouched in combat and hides it while the flask's name is uncached", function()
        for _, row in ipairs({
            { name = "in combat: untouched",     combat = true,  named = true,  shown = true },
            { name = "name uncached: hidden",    combat = false, named = false, shown = false },
        }) do
            local data = foreverData()
            data.flasks = { { item = 13512, buff = 17628 } }
            local ForeverRCC, _, seams = L.loadReadyCheckConsumables(nil, { forever = true, foreverData = data })
            seams.bagCounts[13512] = 3
            if row.named then seams.itemNames[13512] = "item 13512" end
            seams.combat.inCombat = row.combat
            local btn = recordingButton()
            btn.click.shown = true
            ForeverRCC.buttons = { flask = btn }
            ForeverRCC:UpdateFlaskClick()
            assert.equals(row.shown, btn.click.shown, row.name)
            assert.is_nil(btn.click.attributes.macrotext, row.name)
        end
    end)

    it("follows the active elixir that runs out first, and picks it, or the remembered one when none is active, else the first stocked", function()
        local ELIXIRS = { { item = 13452, buff = 17538 }, { item = 9187, buff = 11334 }, { item = 3825, buff = 3593 } }
        local function remainOf(aura) return aura.remain end
        for _, row in ipairs({
            { name = "two active: the shorter sets the timer and the click",
              auras = { [17538] = { remain = 900 }, [11334] = { remain = 300 } },
              remembered = nil, stock = { [13452] = 1, [9187] = 2 }, buff = 11334, remain = 300, pick = 9187 },
            { name = "an untimed active counts last",
              auras = { [17538] = {}, [3593] = { remain = 600 } },
              remembered = nil, stock = { [3825] = 1, [9187] = 2 }, buff = 3593, remain = 600, pick = 3825 },
            { name = "the active elixir before a different remembered one",
              auras = { [11334] = { remain = 600 } },
              remembered = 3593, stock = { [9187] = 2, [3825] = 1 }, buff = 11334, remain = 600, pick = 9187 },
            { name = "the active elixir out of stock: list order, not the memory this repaint replaces",
              auras = { [11334] = { remain = 600 } },
              remembered = 3593, stock = { [13452] = 1, [3825] = 1 }, buff = 11334, remain = 600, pick = 13452 },
            { name = "none active: the remembered elixir before list order",
              auras = {},
              remembered = 3593, stock = { [9187] = 2, [3825] = 1 }, buff = nil, remain = nil, pick = 3825 },
            { name = "none active, the remembered one out: the first stocked",
              auras = {},
              remembered = 17538, stock = { [3825] = 1, [9187] = 2 }, buff = nil, remain = nil, pick = 9187 },
        }) do
            local buff, remain, pick = RCC._ForeverElixirState(ELIXIRS, row.auras, row.remembered, counts(row.stock), remainOf)
            assert.equals(row.buff, buff, row.name)
            assert.equals(row.remain, remain, row.name)
            assert.equals(row.pick, pick, row.name)
        end
    end)
end)

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

describe("ReadyCheckConsumables Forever weapon layers", function()
    local RCC

    before_each(function()
        RCC = L.loadReadyCheckConsumables()
    end)

    it("splits the enchant list into the stone or oil layer and the poison or imbue layer", function()
        local SECRET = {}
        local function isSafe(v) return v ~= nil and v ~= SECRET end
        local function entry(has, kind, id, left)
            return { hasEnchant = has, enchantType = kind, enchantID = id, timeLeft = left }
        end
        for _, row in ipairs({
            { name = "Permanent left out, Temporary and Imbue kept, an unsafe time gives no timer",
              list = { entry(true, 1, 1900, 0), entry(true, 2, 1643, 1800000), entry(true, 3, 323, SECRET) },
              want = { temp = { enchantID = 1643, remain = 1800 }, imbue = { enchantID = 323 } } },
            { name = "no enchant left out", list = { entry(false, 3, 7, 60000) }, want = {} },
            { name = "None type left out", list = { entry(true, 0, 5, 60000) }, want = {} },
            { name = "unsafe presence left out", list = { entry(SECRET, 3, 7, 60000) }, want = {} },
            { name = "unsafe type left out", list = { entry(true, SECRET, 1, 60000) }, want = {} },
            { name = "the first entry of a type wins",
              list = { entry(true, 2, 1643, 1800000), entry(true, 2, 40, 600000) },
              want = { temp = { enchantID = 1643, remain = 1800 } } },
            { name = "an unsafe enchant id keeps the layer", list = { entry(true, 3, SECRET, 60000) },
              want = { imbue = { remain = 60 } } },
            { name = "zero time left gives no timer", list = { entry(true, 2, 1643, 0) },
              want = { temp = { enchantID = 1643 } } },
            { name = "no list", list = nil, want = {} },
        }) do
            assert.same(row.want, RCC._ClassifyHandLayers(row.list, isSafe, 2, 3), row.name)
        end
    end)

    it("gives Rogue and Shaman main hands both layers, the Rogue off hand the poison, every other hand the stone or oil", function()
        for _, row in ipairs({
            { class = "ROGUE",   slot = 16, want = { "imbue", "temp" } },
            { class = "SHAMAN",  slot = 16, want = { "imbue", "temp" } },
            { class = "ROGUE",   slot = 17, want = { "imbue" } },
            { class = "SHAMAN",  slot = 17, want = { "temp" } },
            { class = "WARRIOR", slot = 16, want = { "temp" } },
        }) do
            assert.same(row.want, RCC._HandRule(row.class, row.slot), row.class .. " " .. row.slot)
        end
    end)

    it("is ready only with every needed layer, shows the soonest timer and clicks the first missing layer, else the soonest", function()
        local BOTH = { "imbue", "temp" }
        local poison = { enchantID = 1, remain = 300 }
        local stone = { enchantID = 2, remain = 900 }
        local untimed = { enchantID = 3 }
        for _, row in ipairs({
            { name = "both on, poison runs first", layers = { imbue = poison, temp = stone },
              ready = true, remain = 300, click = "imbue" },
            { name = "both on, stone runs first", layers = { imbue = { enchantID = 1, remain = 1200 }, temp = stone },
              ready = true, remain = 900, click = "temp" },
            { name = "poison missing", layers = { temp = stone }, ready = false, remain = nil, click = "imbue" },
            { name = "stone missing", layers = { imbue = poison }, ready = false, remain = nil, click = "temp" },
            { name = "both missing: the first needed", layers = {}, ready = false, remain = nil, click = "imbue" },
            { name = "no timer read", layers = { imbue = untimed, temp = untimed }, ready = true, remain = nil, click = "imbue" },
        }) do
            local ready, remain, click = RCC._HandPlan(row.layers, BOTH)
            assert.equals(row.ready, ready, row.name)
            assert.equals(row.remain, remain, row.name)
            assert.equals(row.click, click, row.name)
        end
    end)

    it("picks the remembered item, then its family, then the hand or class default, then any stocked item the weapon takes", function()
        local SWORD, STAFF = 7, 10
        local ROWS = {
            { item = 101, enchant = 1, kind = "stone",  family = "Sharpening Stone", rank = 4, applies = { [7] = true } },
            { item = 102, enchant = 2, kind = "stone",  family = "Sharpening Stone", rank = 5, applies = { [7] = true } },
            { item = 201, enchant = 3, kind = "stone",  family = "Weightstone",      rank = 5, applies = { [4] = true, [10] = true } },
            { item = 301, enchant = 4, kind = "wizard", family = "Wizard Oil",       rank = 3 },
            { item = 401, enchant = 5, kind = "mana",   family = "Mana Oil",         rank = 2 },
            { item = 501, enchant = 6, kind = "poison", family = "Deadly Poison",    rank = 2, applies = { [7] = true } },
            { item = 502, enchant = 7, kind = "poison", family = "Instant Poison",   rank = 1, applies = { [7] = true } },
            { item = 503, enchant = 8, kind = "poison", family = "Instant Poison",   rank = 3, applies = { [7] = true } },
        }
        for _, row in ipairs({
            { name = "Rogue main hand: Instant's highest stocked rank", class = "ROGUE", layer = "imbue", slot = 16,
              weapon = SWORD, stock = { 501, 502, 503 }, pick = 503 },
            { name = "Rogue off hand: Deadly", class = "ROGUE", layer = "imbue", slot = 17,
              weapon = SWORD, stock = { 501, 503 }, pick = 501 },
            { name = "Rogue: any poison without the hand default", class = "ROGUE", layer = "imbue", slot = 16,
              weapon = SWORD, stock = { 501 }, pick = 501 },
            { name = "Rogue: remembered family before the hand default", class = "ROGUE", layer = "imbue", slot = 17,
              weapon = SWORD, remembered = 502, stock = { 501, 503 }, pick = 503 },
            { name = "Rogue stone layer: never a poison", class = "ROGUE", layer = "temp", slot = 16,
              weapon = SWORD, stock = { 503 }, pick = nil },
            { name = "Warrior: stone before oil", class = "WARRIOR", layer = "temp", slot = 16,
              weapon = SWORD, stock = { 301, 101 }, pick = 101 },
            { name = "Mage: wizard oil before stone", class = "MAGE", layer = "temp", slot = 16,
              weapon = SWORD, stock = { 102, 301 }, pick = 301 },
            { name = "Druid: mana oil before stone", class = "DRUID", layer = "temp", slot = 16,
              weapon = STAFF, stock = { 201, 401 }, pick = 401 },
            { name = "remembered item before a higher rank", class = "WARRIOR", layer = "temp", slot = 16,
              weapon = SWORD, remembered = 101, stock = { 101, 102 }, pick = 101 },
            { name = "remembered family's highest stocked rank", class = "MAGE", layer = "temp", slot = 16,
              weapon = SWORD, remembered = 101, stock = { 102, 301 }, pick = 102 },
            { name = "a stone the weapon cannot take", class = "WARRIOR", layer = "temp", slot = 16,
              weapon = STAFF, stock = { 101 }, pick = nil },
        }) do
            local stocked = {}
            for _, item in ipairs(row.stock) do stocked[item] = 4 end
            local pick, n = RCC._PickForeverEnhancement(ROWS, row.layer, row.class, row.slot, row.weapon,
                row.remembered, function(item) return stocked[item] or 0 end)
            assert.equals(row.pick, pick, row.name)
            assert.equals(row.pick and 4 or 0, n, row.name)
        end
    end)

    it("casts the remembered imbue, else the first known, at its highest known rank, and nothing when none is known", function()
        local IMBUES = {
            { family = "Windfury Weapon",  ranks = { 8232, 8235 }, enchants = { 283, 284 } },
            { family = "Rockbiter Weapon", ranks = { 8017, 8018 }, enchants = { 29, 6 } },
        }
        for _, row in ipairs({
            { name = "remembered and known",   remembered = 8017, known = { 8017, 8018, 8232 }, family = 8017, rank = 8018 },
            { name = "remembered, not known",  remembered = 8017, known = { 8232 },             family = 8232, rank = 8232 },
            { name = "nothing remembered",     remembered = nil,  known = { 8017, 8232, 8235 }, family = 8232, rank = 8235 },
            { name = "nothing known",          remembered = 8232, known = {},                   family = nil,  rank = nil },
        }) do
            local set = {}
            for _, id in ipairs(row.known) do set[id] = true end
            local family, rank = RCC._PickImbue(IMBUES, row.remembered, function(id) return set[id] == true end)
            assert.equals(row.family, family, row.name)
            assert.equals(row.rank, rank, row.name)
        end
        assert.equals("/stopmacro [combat]\n/cast Windfury Weapon\n/use 16", RCC._ImbueClickMacro("Windfury Weapon"))
        assert.is_nil(RCC._ImbueClickMacro(nil))
    end)

    it("arms the imbue click only out of combat and only with a readable spell name", function()
        for _, row in ipairs({
            { name = "armed", combat = false, secret = false, shown = true,
              macro = "/stopmacro [combat]\n/cast spell 8235\n/use 16" },
            { name = "in combat: untouched", combat = true, secret = false, shown = true, macro = nil },
            { name = "unreadable name: hidden", combat = false, secret = true, shown = false, macro = nil },
        }) do
            local data = foreverData()
            data.imbues = { { family = "Windfury Weapon", ranks = { 8232, 8235 }, enchants = { 283, 284 } } }
            local ForeverRCC, _, seams = L.loadReadyCheckConsumables(nil, { forever = true, foreverData = data })
            seams.knownSpells[8232], seams.knownSpells[8235] = true, true
            seams.combat.inCombat = row.combat
            if row.secret then _G.C_Spell.GetSpellName = function() return seams.SECRET end end
            local btn = recordingButton()
            btn.click.shown = true
            ForeverRCC:_ArmImbueClick(btn, "oil", nil)
            assert.equals(row.shown, btn.click.shown, row.name)
            assert.equals(row.macro, btn.click.attributes.macrotext, row.name)
        end
    end)

    -- The oil has no `applies`, so it takes any weapon subclass: only the
    -- equipment gate can refuse it.
    it("arms the main-hand item click only for a readable equipped weapon, out of combat, with the item's name", function()
        for _, row in ipairs({
            { name = "sword: armed",                weapon = { 2, 7 },          shown = true,  item = "item 301" },
            { name = "no main-hand item: hidden",   weapon = nil,               shown = false },
            { name = "a shield: hidden",            weapon = { 4, 6 },          shown = false },
            { name = "unreadable subclass: hidden", weapon = { 2 },             shown = false },
            { name = "in combat: untouched",        weapon = { 2, 7 }, combat = true, shown = true },
            { name = "oil name uncached: hidden",   weapon = { 2, 7 }, unnamed = true, shown = false },
        }) do
            local data = foreverData()
            data.enhancements = { { item = 301, enchant = 4, kind = "wizard", family = "Wizard Oil", rank = 3 } }
            local ForeverRCC, _, seams = L.loadReadyCheckConsumables(nil, { forever = true, foreverData = data })
            seams.playerClass = "WARRIOR"
            seams.bagCounts[301] = 2
            if not row.unnamed then seams.itemNames[301] = "item 301" end
            if row.weapon then
                seams.equipped[16] = 5000
                seams.itemInfo[5000] = row.weapon
            end
            seams.combat.inCombat = row.combat == true
            local btn = recordingButton()
            btn.click.shown = true
            ForeverRCC.buttons = { oil = btn }
            ForeverRCC:UpdateWeaponEnchant("oil", 16)
            assert.equals(row.shown, btn.click.shown, row.name)
            assert.equals(row.item, btn.click.attributes.item, row.name)
        end
    end)
end)

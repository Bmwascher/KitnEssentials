-- Tier 1: GUI/GUIWidgets/GUI-PairedRow.lua -- the clear rule.
-- A dependent that stays stored while hidden is the one silent failure this
-- widget can have, and the safety property the whole design rests on. The
-- same predicate decides three things -- whether the dependent is built,
-- whether a master flip clears it, and whether the dependent's own deferred
-- callback is allowed to write -- so these four rows cover all three.
-- Layout, the chevron and the page rebuild are smoke.
local helpers = require("dev.spec._helpers")

describe("PairedRow dependent resolution", function()
    local GUIFrame

    before_each(function()
        -- The widget binds KE.GUIFrame and KE.Theme at load and defines its
        -- functions on GUIFrame, so both tables must exist before loadModule.
        local KE = helpers.loadModule("GUI/GUIWidgets/GUI-PairedRow.lua", {
            GUIFrame = {},
            Theme = {},
        })
        GUIFrame = KE.GUIFrame
    end)

    it("shows the dependent only while the master is on, and clears it only when clearable", function()
        local cases = {
            { name = "master on, clearable",      master = true,  clearable = true,  show = true,  clear = false },
            { name = "master on, not clearable",  master = true,  clearable = false, show = true,  clear = false },
            { name = "master off, clearable",     master = false, clearable = true,  show = false, clear = true  },
            { name = "master off, not clearable", master = false, clearable = false, show = false, clear = false },
        }
        for _, case in ipairs(cases) do
            local show, clear = GUIFrame.ResolvePairedDependent(case.master, case.clearable)
            assert.equals(case.show, show, case.name)
            assert.equals(case.clear, clear, case.name)
        end
    end)
end)

-- Reaches through CreatePairedRow itself, because the truth table above cannot
-- discriminate a missing write guard from a present one. The stubs only
-- capture callbacks; no animation and no timer is simulated.
local function newHarness()
    local KE = helpers.loadModule("GUI/GUIWidgets/GUI-PairedRow.lua", {
        GUIFrame = {},
        Theme = { rowHeight = 40, paddingSmall = 4, accent = { 1, 1, 1, 1 } },
    })
    local G = KE.GUIFrame
    local inert = setmetatable({}, { __index = function() return function() end end })

    function G:CreateRow()
        return { AddWidget = function() end, CreateTexture = function() return inert end }
    end
    function G:CreateCheckbox(_, _, cfg) return { cfg = cfg } end
    function G:CreateDropdown(_, _, cfg) return { cfg = cfg } end
    function G:RefreshContent() end

    return G, { content = {}, AddRow = function() end }
end

local function lootPair(G, card, db, calls)
    local _, master, dependent = G:CreatePairedRow(card, {
        master = {
            label = "Auto Loot",
            get = function() return db.AutoLoot ~= false end,
            callback = function(checked) db.AutoLoot = checked end,
        },
        dependent = {
            kind = "checkbox",
            label = "Fast Loot",
            value = db.FastLoot == true,
            callback = function(checked) db.FastLoot = checked end,
            clear = function()
                if calls then calls.clear = calls.clear + 1 end
                db.FastLoot = false
            end,
        },
    })
    return master, dependent
end

describe("PairedRow callback wiring", function()
    it("clears a dependent it inherits switched on beneath a master that is off", function()
        local G, card = newHarness()
        local db = { AutoLoot = false, FastLoot = true }
        local _, dependent = lootPair(G, card, db)
        assert.is_false(db.FastLoot)
        assert.is_nil(dependent)
    end)

    it("accepts a dependent write while its master is on", function()
        local G, card = newHarness()
        local db = { AutoLoot = true, FastLoot = false }
        local _, dependent = lootPair(G, card, db)
        dependent.cfg.callback(true)
        assert.is_true(db.FastLoot)
    end)

    it("refuses a dependent write from a row built before the master went off", function()
        local G, card = newHarness()
        local db = { AutoLoot = true, FastLoot = false }
        -- Two builds while the master still reads on, which is what another
        -- paired row's rebuild produces.
        local masterA = lootPair(G, card, db)
        local _, dependentB = lootPair(G, card, db)

        -- The first row's master callback lands first and takes the master off.
        masterA.cfg.callback(false)
        assert.is_false(db.AutoLoot)
        assert.is_false(db.FastLoot)

        -- The second row's dependent callback was queued before that and lands
        -- after it. It must not resurrect a setting the player cannot see.
        dependentB.cfg.callback(true)
        assert.is_false(db.FastLoot)
    end)

    -- The flip-time clear, on its own. The refusal case above starts with the
    -- dependent already off, so removing this clear entirely leaves it passing.
    it("clears a dependent that was on when its master is switched off", function()
        local G, card = newHarness()
        local db = { AutoLoot = true, FastLoot = true }
        local master = lootPair(G, card, db)
        master.cfg.callback(false)
        assert.is_false(db.FastLoot)
    end)

    -- The build-time clear is conditional: an apply chain runs inside it, and
    -- firing it for a dependent already off runs that chain for nothing.
    it("does not clear at build when the dependent is already off", function()
        local G, card = newHarness()
        local calls = { clear = 0 }
        lootPair(G, card, { AutoLoot = false, FastLoot = false }, calls)
        assert.equals(0, calls.clear)

        local inherited = { clear = 0 }
        lootPair(G, card, { AutoLoot = false, FastLoot = true }, inherited)
        assert.equals(1, inherited.clear)
    end)
end)

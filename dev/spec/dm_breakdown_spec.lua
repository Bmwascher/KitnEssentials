-- ╔══════════════════════════════════════════════════════════╗
-- ║  dev/spec/dm_breakdown_spec.lua                          ║
-- ║  Pure-helper spec for DamageMeter/Detail.lua aggregation.║
-- ╚══════════════════════════════════════════════════════════╝
--
-- Loads the REAL Modules/DamageMeter/Detail.lua headlessly and tests
-- AggregateEnemyPlayers / AutoAttackName / MergeSpellsByName / TipHeaderName
-- through the DM.* seam at its EOF (the helpers are file-locals). If Detail.lua ever gains
-- load-time C_* calls / event registrations this load breaks loudly — that is
-- the intended tripwire; fix the load path, don't re-mirror the bodies.
--
-- Reload-per-test: Detail.lua caches AutoAttackName's resolution in a file-local
-- upvalue; a fresh load per test resets it. The SECRET/SPELL stubs are installed
-- as closures BEFORE each load (captured into file-locals), so per-test mutation
-- still works.
--
-- HONESTY BOUNDARY (see dev/README.md): issecretvalue / C_Spell.GetSpellName are
-- stubbed. A pass verifies the branch logic given values we DECLARE secret/named,
-- never real 12.0 secret/taint semantics — that stays in-game-only.
local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

-- ── Controllable stubs the real file closes over ───────────────────────────────
local SECRET = {}   -- [value] = true  marks a value "secret"
local SPELL  = {}   -- [spellID] = name  for C_Spell.GetSpellName

-- ── Tests ──────────────────────────────────────────────────────────────────────
local DM
before_each(function()
    for k in pairs(SECRET) do SECRET[k] = nil end
    for k in pairs(SPELL) do SPELL[k] = nil end
    -- Detail.lua captures issecretvalue/C_Spell into file-locals at load:
    -- install the closures BEFORE loadModule. Reload per test resets the
    -- file-local _autoAttackName cache (replaces the mirror's manual reset).
    mock.install({ issecretvalue = function(v) return SECRET[v] == true end })
    _G.C_Spell = { GetSpellName = function(id) return SPELL[id] end,
                   GetSpellTexture = function() return nil end }
    local modules = helpers.installAddonShim()
    helpers.loadModule("Modules/DamageMeter/Detail.lua")
    DM = modules["DamageMeter"]
    assert(DM.MergeSpellsByName, "Detail.lua seam did not expose MergeSpellsByName")
end)

describe("MergeSpellsByName", function()
    it("returns nil for nil input", function()
        assert.is_nil(DM.MergeSpellsByName(nil))
    end)

    it("returns an empty list for empty combatSpells", function()
        local r = DM.MergeSpellsByName({})
        assert.same({}, r)
    end)

    it("collapses same-named spellIDs and sums amount + per-second", function()
        SPELL[100] = "Auto Attack"; SPELL[101] = "Auto Attack"; SPELL[200] = "Frostbane Slash"
        local r = DM.MergeSpellsByName({
            { spellID = 100, totalAmount = 50, amountPerSecond = 5 },
            { spellID = 200, totalAmount = 40, amountPerSecond = 4 },
            { spellID = 101, totalAmount = 30, amountPerSecond = 3 },
        })
        assert.equals(2, #r)
        -- Auto Attack: 50+30 = 80 / 5+3 = 8, outranks the single 40 after the re-sort.
        assert.equals(80, r[1].totalAmount)
        assert.equals(8, r[1].amountPerSecond)
        assert.equals(40, r[2].totalAmount)
    end)

    it("re-sorts by the MERGED total (a merged group can overtake a larger single)", function()
        SPELL[100] = "Auto Attack"; SPELL[101] = "Auto Attack"; SPELL[200] = "Big Hit"
        local r = DM.MergeSpellsByName({
            { spellID = 200, totalAmount = 70, amountPerSecond = 7 },  -- biggest single
            { spellID = 100, totalAmount = 50, amountPerSecond = 5 },
            { spellID = 101, totalAmount = 40, amountPerSecond = 4 },  -- merges to 90 > 70
        })
        assert.equals("Auto Attack", SPELL[r[1].spellID])
        assert.equals(90, r[1].totalAmount)
        assert.equals(70, r[2].totalAmount)
    end)

    it("keeps the FIRST variant's spellID as the merged row's representative", function()
        SPELL[100] = "Auto Attack"; SPELL[101] = "Auto Attack"
        local r = DM.MergeSpellsByName({
            { spellID = 100, totalAmount = 50, amountPerSecond = 5 },
            { spellID = 101, totalAmount = 30, amountPerSecond = 3 },
        })
        assert.equals(100, r[1].spellID)
    end)

    it("tags the auto-attack row with the melee iconOverride, others nil", function()
        SPELL[6603] = "Auto Attack"   -- canonical -> AutoAttackName resolves to this
        SPELL[100] = "Auto Attack"; SPELL[200] = "Frostbane Slash"
        local r = DM.MergeSpellsByName({
            { spellID = 100, totalAmount = 50, amountPerSecond = 5 },   -- 50 > 40 -> r[1]
            { spellID = 200, totalAmount = 40, amountPerSecond = 4 },
        })
        assert.equals(135349, r[1].iconOverride)
        assert.is_nil(r[2].iconOverride)
    end)

    it("does NOT override when AutoAttackName can't resolve (cold spell DB)", function()
        -- SPELL[6603] unset -> AutoAttackName() is nil -> no row matches -> no override
        SPELL[100] = "Auto Attack"
        local r = DM.MergeSpellsByName({ { spellID = 100, totalAmount = 50, amountPerSecond = 5 } })
        assert.is_nil(r[1].iconOverride)
    end)

    it("keeps secret-named spells on their own rows (keyed by spellID, never merged)", function()
        -- Two different spellIDs whose NAMES are secret: must not collapse together.
        SPELL[100] = "SecretName"; SPELL[101] = "SecretName"
        SECRET["SecretName"] = true
        local r = DM.MergeSpellsByName({
            { spellID = 100, totalAmount = 50, amountPerSecond = 5 },
            { spellID = 101, totalAmount = 30, amountPerSecond = 3 },
        })
        assert.equals(2, #r)   -- keyed "#100" and "#101", not merged under the secret name
    end)

    it("sanitizes secret/non-number amounts to 0 before summing", function()
        SPELL[100] = "Cleave"
        SECRET["s"] = true
        local r = DM.MergeSpellsByName({
            { spellID = 100, totalAmount = "s", amountPerSecond = 5 },   -- string -> 0
            { spellID = 100, totalAmount = 20, amountPerSecond = "s" },  -- secret-flagged amt path
        })
        -- both share name "Cleave" -> one row; "s" amount -> 0, second amt 20 -> total 20
        assert.equals(1, #r)
        assert.equals(20, r[1].totalAmount)
    end)
end)

describe("AggregateEnemyPlayers", function()
    local function det(name, class, icon) return { unitName = name, unitClassFilename = class, specIconID = icon } end

    it("returns nil for nil / empty / no-combatSpells", function()
        assert.is_nil(DM.AggregateEnemyPlayers(nil))
        assert.is_nil(DM.AggregateEnemyPlayers({}))
        assert.is_nil(DM.AggregateEnemyPlayers({ combatSpells = {} }))
    end)

    it("aggregates by attacking player, sums total + dps, sorted desc", function()
        local src = { combatSpells = {
            { totalAmount = 30, amountPerSecond = 3, combatSpellDetails = det("Bob", "MAGE", 11) },
            { totalAmount = 50, amountPerSecond = 5, combatSpellDetails = det("Amy", "ROGUE", 22) },
            { totalAmount = 30, amountPerSecond = 3, combatSpellDetails = det("Bob", "MAGE", 11) },
        } }
        local r = DM.AggregateEnemyPlayers(src)
        assert.equals(2, #r)
        assert.equals("Bob", r[1].name)      -- 30+30 = 60 > Amy(50), no tie
        assert.equals(60, r[1].total)
        assert.equals(6, r[1].dps)
        assert.equals("MAGE", r[1].class)
        assert.equals(11, r[1].specIcon)
        assert.equals("Amy", r[2].name)
        assert.equals(50, r[2].total)
    end)

    it("skips zero-damage attributions (amt > 0 gate, parity with BuildAllPlayerTargets)", function()
        local src = { combatSpells = {
            { totalAmount = 0, amountPerSecond = 0, combatSpellDetails = det("Ghost", "PRIEST", 1) },
            { totalAmount = 40, amountPerSecond = 4, combatSpellDetails = det("Real", "WARRIOR", 2) },
        } }
        local r = DM.AggregateEnemyPlayers(src)
        assert.equals(1, #r)
        assert.equals("Real", r[1].name)
    end)

    it("skips entries with a secret unitName", function()
        SECRET["Hidden"] = true
        local src = { combatSpells = {
            { totalAmount = 99, amountPerSecond = 9, combatSpellDetails = det("Hidden", "DRUID", 3) },
            { totalAmount = 40, amountPerSecond = 4, combatSpellDetails = det("Seen", "HUNTER", 4) },
        } }
        local r = DM.AggregateEnemyPlayers(src)
        assert.equals(1, #r)
        assert.equals("Seen", r[1].name)
    end)

    it("returns nil when every attacker is zero / secret (empty result)", function()
        SECRET["X"] = true
        local src = { combatSpells = {
            { totalAmount = 0, amountPerSecond = 0, combatSpellDetails = det("Zero", "MAGE", 1) },
            { totalAmount = 99, amountPerSecond = 9, combatSpellDetails = det("X", "ROGUE", 2) },
        } }
        assert.is_nil(DM.AggregateEnemyPlayers(src))
    end)

    it("sanitizes a secret amount to 0 (skips that contribution)", function()
        SECRET["sa"] = true
        local src = { combatSpells = {
            { totalAmount = "sa", amountPerSecond = 1, combatSpellDetails = det("Solo", "MAGE", 1) },
        } }
        -- "sa" -> 0, fails amt > 0 -> no row -> nil
        assert.is_nil(DM.AggregateEnemyPlayers(src))
    end)
end)

describe("TipHeaderName", function()
    -- History.lua is not loaded here: DM.PlainNameFor is stubbed per test
    -- (fresh DM each before_each, so stubs never leak).
    it("prefers the cached plain name and never consults the memo", function()
        DM.PlainNameFor = function() error("memo must not be consulted when a cached name exists") end
        local bar = { _cachedName = "Itsgg", _sourceGUID = "Player-1-A" }
        assert.equals("Itsgg", DM.TipHeaderName(DM, bar))
    end)

    it("falls back to the identity memo when the cached name is nil (secret-named bar)", function()
        DM.PlainNameFor = function(_, guid)
            return guid == "Player-1-A" and "Unsub-BurningLegion" or nil
        end
        assert.equals("Unsub-BurningLegion", DM.TipHeaderName(DM, { _sourceGUID = "Player-1-A" }))
    end)

    it("defaults to Breakdown on a memo miss", function()
        DM.PlainNameFor = function() return nil end
        assert.equals("Breakdown", DM.TipHeaderName(DM, { _sourceGUID = "Player-1-Z" }))
    end)

    it("defaults to Breakdown when no memo is installed (load-order safety)", function()
        assert.is_nil(DM.PlainNameFor)
        assert.equals("Breakdown", DM.TipHeaderName(DM, {}))
    end)
end)

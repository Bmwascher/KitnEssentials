-- ╔══════════════════════════════════════════════════════════╗
-- ║  dev/spec/dm_breakdown_spec.lua                          ║
-- ║  Pure-helper spec for DamageMeter/Detail.lua aggregation.║
-- ╚══════════════════════════════════════════════════════════╝
--
-- Loads the REAL Modules/DamageMeter/Detail.lua headlessly and tests
-- AutoAttackName / MergeSpellsByName / TipHeaderName
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
    it("returns nil for nil input, empty list for empty combatSpells", function()
        assert.is_nil(DM.MergeSpellsByName(nil))
        assert.same({}, DM.MergeSpellsByName({}))
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

    it("defaults to Breakdown when no memo is installed (load-order safety)", function()
        assert.is_nil(DM.PlainNameFor)
        assert.equals("Breakdown", DM.TipHeaderName(DM, {}))
    end)
end)

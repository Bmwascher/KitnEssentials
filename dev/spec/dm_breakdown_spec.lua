-- ╔══════════════════════════════════════════════════════════╗
-- ║  dev/spec/dm_breakdown_spec.lua                          ║
-- ║  Pure-helper spec for DamageMeter/Detail.lua aggregation.║
-- ╚══════════════════════════════════════════════════════════╝
--
-- MIRRORS the module-local helpers AggregateEnemyPlayers / AutoAttackName /
-- MergeSpellsByName from Modules/DamageMeter/Detail.lua. Those are file-locals
-- inside an AceModule that can't load headless, so the bodies are copied here
-- verbatim. IF THEY DRIFT FROM Detail.lua THE SPEC IS STALE — keep in sync.
--
-- HONESTY BOUNDARY (see dev/README.md): issecretvalue / C_Spell.GetSpellName are
-- stubbed. A pass verifies the branch logic given values we DECLARE secret/named,
-- never real 12.0 secret/taint semantics — that stays in-game-only.

-- ── Controllable stubs the mirrored bodies close over ──────────────────────────
local SECRET = {}   -- [value] = true  marks a value "secret"
local SPELL  = {}   -- [spellID] = name  for C_Spell.GetSpellName
_G.issecretvalue = function(v) return SECRET[v] == true end
_G.C_Spell = { GetSpellName = function(id) return SPELL[id] end }
local table_sort = table.sort

-- ── Verbatim mirror of Detail.lua (keep in sync) ───────────────────────────────
local function AggregateEnemyPlayers(src)
    if not src or not src.combatSpells or #src.combatSpells == 0 then return nil end
    local byName, list = {}, {}
    for _, spell in ipairs(src.combatSpells) do
        local det = spell.combatSpellDetails
        if det and det.unitName and not issecretvalue(det.unitName) then
            local amt = spell.totalAmount
            if issecretvalue(amt) or type(amt) ~= "number" then amt = 0 end
            if amt > 0 then
                local pName = det.unitName
                local ps = spell.amountPerSecond
                if issecretvalue(ps) or type(ps) ~= "number" then ps = 0 end
                local p = byName[pName]
                if not p then
                    p = { name = pName, class = det.unitClassFilename, specIcon = det.specIconID, total = 0, dps = 0 }
                    byName[pName] = p
                    list[#list + 1] = p
                end
                p.total = p.total + amt
                p.dps = p.dps + ps
            end
        end
    end
    if #list == 0 then return nil end
    table_sort(list, function(a, b) return a.total > b.total end)
    return list
end

local MELEE_ICON = 135349
local _autoAttackName
local function AutoAttackName()
    if not _autoAttackName then
        local ok, nm = pcall(C_Spell.GetSpellName, 6603)
        if ok and nm and not issecretvalue(nm) then _autoAttackName = nm end
    end
    return _autoAttackName
end

local function MergeSpellsByName(spells)
    if not spells then return nil end
    local byKey, list = {}, {}
    for _, spell in ipairs(spells) do
        local spID = spell.spellID
        local nm
        if spID then
            local ok, sn = pcall(C_Spell.GetSpellName, spID)
            if ok and sn and not issecretvalue(sn) then nm = sn end
        end
        local idSafe = (not issecretvalue(spID) and type(spID) == "number") and spID or nil
        local cnSafe = (spell.creatureName and not issecretvalue(spell.creatureName)) and spell.creatureName or nil
        local key = nm or (idSafe and ("#" .. tostring(idSafe))) or cnSafe or "?"
        local amt = spell.totalAmount
        if issecretvalue(amt) or type(amt) ~= "number" then amt = 0 end
        local ps = spell.amountPerSecond
        if issecretvalue(ps) or type(ps) ~= "number" then ps = 0 end
        local e = byKey[key]
        if not e then
            e = { spellID = spID, totalAmount = 0, amountPerSecond = 0, creatureName = spell.creatureName }
            local aaName = AutoAttackName()
            if aaName and nm == aaName then e.iconOverride = MELEE_ICON end
            byKey[key] = e
            list[#list + 1] = e
        end
        e.totalAmount = e.totalAmount + amt
        e.amountPerSecond = e.amountPerSecond + ps
    end
    table_sort(list, function(a, b) return a.totalAmount > b.totalAmount end)
    return list
end

-- ── Tests ──────────────────────────────────────────────────────────────────────
before_each(function()
    for k in pairs(SECRET) do SECRET[k] = nil end
    for k in pairs(SPELL) do SPELL[k] = nil end
    _autoAttackName = nil
end)

describe("MergeSpellsByName", function()
    it("returns nil for nil input", function()
        assert.is_nil(MergeSpellsByName(nil))
    end)

    it("returns an empty list for empty combatSpells", function()
        local r = MergeSpellsByName({})
        assert.same({}, r)
    end)

    it("collapses same-named spellIDs and sums amount + per-second", function()
        SPELL[100] = "Auto Attack"; SPELL[101] = "Auto Attack"; SPELL[200] = "Frostbane Slash"
        local r = MergeSpellsByName({
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
        local r = MergeSpellsByName({
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
        local r = MergeSpellsByName({
            { spellID = 100, totalAmount = 50, amountPerSecond = 5 },
            { spellID = 101, totalAmount = 30, amountPerSecond = 3 },
        })
        assert.equals(100, r[1].spellID)
    end)

    it("tags the auto-attack row with the melee iconOverride, others nil", function()
        SPELL[6603] = "Auto Attack"   -- canonical -> AutoAttackName resolves to this
        SPELL[100] = "Auto Attack"; SPELL[200] = "Frostbane Slash"
        local r = MergeSpellsByName({
            { spellID = 100, totalAmount = 50, amountPerSecond = 5 },   -- 50 > 40 -> r[1]
            { spellID = 200, totalAmount = 40, amountPerSecond = 4 },
        })
        assert.equals(135349, r[1].iconOverride)
        assert.is_nil(r[2].iconOverride)
    end)

    it("does NOT override when AutoAttackName can't resolve (cold spell DB)", function()
        -- SPELL[6603] unset -> AutoAttackName() is nil -> no row matches -> no override
        SPELL[100] = "Auto Attack"
        local r = MergeSpellsByName({ { spellID = 100, totalAmount = 50, amountPerSecond = 5 } })
        assert.is_nil(r[1].iconOverride)
    end)

    it("keeps secret-named spells on their own rows (keyed by spellID, never merged)", function()
        -- Two different spellIDs whose NAMES are secret: must not collapse together.
        SPELL[100] = "SecretName"; SPELL[101] = "SecretName"
        SECRET["SecretName"] = true
        local r = MergeSpellsByName({
            { spellID = 100, totalAmount = 50, amountPerSecond = 5 },
            { spellID = 101, totalAmount = 30, amountPerSecond = 3 },
        })
        assert.equals(2, #r)   -- keyed "#100" and "#101", not merged under the secret name
    end)

    it("sanitizes secret/non-number amounts to 0 before summing", function()
        SPELL[100] = "Cleave"
        SECRET["s"] = true
        local r = MergeSpellsByName({
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
        assert.is_nil(AggregateEnemyPlayers(nil))
        assert.is_nil(AggregateEnemyPlayers({}))
        assert.is_nil(AggregateEnemyPlayers({ combatSpells = {} }))
    end)

    it("aggregates by attacking player, sums total + dps, sorted desc", function()
        local src = { combatSpells = {
            { totalAmount = 30, amountPerSecond = 3, combatSpellDetails = det("Bob", "MAGE", 11) },
            { totalAmount = 50, amountPerSecond = 5, combatSpellDetails = det("Amy", "ROGUE", 22) },
            { totalAmount = 30, amountPerSecond = 3, combatSpellDetails = det("Bob", "MAGE", 11) },
        } }
        local r = AggregateEnemyPlayers(src)
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
        local r = AggregateEnemyPlayers(src)
        assert.equals(1, #r)
        assert.equals("Real", r[1].name)
    end)

    it("skips entries with a secret unitName", function()
        SECRET["Hidden"] = true
        local src = { combatSpells = {
            { totalAmount = 99, amountPerSecond = 9, combatSpellDetails = det("Hidden", "DRUID", 3) },
            { totalAmount = 40, amountPerSecond = 4, combatSpellDetails = det("Seen", "HUNTER", 4) },
        } }
        local r = AggregateEnemyPlayers(src)
        assert.equals(1, #r)
        assert.equals("Seen", r[1].name)
    end)

    it("returns nil when every attacker is zero / secret (empty result)", function()
        SECRET["X"] = true
        local src = { combatSpells = {
            { totalAmount = 0, amountPerSecond = 0, combatSpellDetails = det("Zero", "MAGE", 1) },
            { totalAmount = 99, amountPerSecond = 9, combatSpellDetails = det("X", "ROGUE", 2) },
        } }
        assert.is_nil(AggregateEnemyPlayers(src))
    end)

    it("sanitizes a secret amount to 0 (skips that contribution)", function()
        SECRET["sa"] = true
        local src = { combatSpells = {
            { totalAmount = "sa", amountPerSecond = 1, combatSpellDetails = det("Solo", "MAGE", 1) },
        } }
        -- "sa" -> 0, fails amt > 0 -> no row -> nil
        assert.is_nil(AggregateEnemyPlayers(src))
    end)
end)

-- Modules/Utilities/NoMovementAlert.lua -- the layers a later edit breaks
-- silently: spell resolution end to end (the exported tables and key format,
-- which spells count as enabled and for which spec, replacement choices, and
-- alias and category durations), how role colours resolve, how a cooldown reads
-- back, and whether an unreadable aura is allowed to masquerade as an absent
-- one. The tracking engine, the frames and the event wiring are a verbatim port
-- and are verified in game.
local L = require("dev.spec._ke_loader")

describe("movement alert spell resolution", function()
    local NMA, KE

    before_each(function()
        NMA, KE = L.loadMovementAlert()
    end)

    describe("the exported tables", function()
        it("publishes the four names the page needs", function()
            assert.is_table(KE.MOVEMENT_ABILITIES)
            assert.is_table(KE.MOVEMENT_BUFF_ACTIVE)
            assert.is_table(KE.MOVEMENT_DEFAULT_OFF)
            assert.is_function(KE.MOVEMENT_SPELL_KEY)
        end)

        it("keys spell overrides as specID:spellID", function()
            assert.equals("102:1850", KE.MOVEMENT_SPELL_KEY(102, 1850))
        end)

        it("treats a missing spec as spec zero rather than erroring", function()
            assert.equals("0:1850", KE.MOVEMENT_SPELL_KEY(nil, 1850))
        end)
    end)

    describe("effective enable state", function()
        -- SpellEnabled is a file-local, so it is reached through the module's
        -- own resolution rather than called directly. NMA.db is assigned here
        -- the way the module assigns it in UpdateDB.
        local function enabled(db, spellId, specId)
            return NMA:IsSpellEnabled(db, spellId, specId)
        end

        it("counts an untouched preset as on", function()
            assert.is_true(enabled({ Spells = {} }, 102401, 102))
        end)

        it("counts a default-off preset as off when untouched", function()
            -- Dash ships unchecked.
            assert.is_false(enabled({ Spells = {} }, 1850, 102))
        end)

        it("lets an explicit per-spec tick turn a default-off preset on", function()
            local db = { Spells = { ["102:1850"] = { enabled = true } } }
            assert.is_true(enabled(db, 1850, 102))
        end)

        it("lets an explicit per-spec untick turn a default-on preset off", function()
            local db = { Spells = { ["102:102401"] = { enabled = false } } }
            assert.is_false(enabled(db, 102401, 102))
        end)

        it("keeps one spec's choice out of another spec's answer", function()
            local db = { Spells = { ["102:102401"] = { enabled = false } } }
            assert.is_false(enabled(db, 102401, 102))
            assert.is_true(enabled(db, 102401, 103))
        end)

        it("still honours the older account-wide key as a fallback", function()
            local db = { Spells = { ["102401"] = { enabled = false } } }
            assert.is_false(enabled(db, 102401, 102))
        end)

        it("lets a per-spec key win over the older account-wide one", function()
            local db = {
                Spells = {
                    ["102401"] = { enabled = false },
                    ["102:102401"] = { enabled = true },
                },
            }
            assert.is_true(enabled(db, 102401, 102))
            -- The other spec has no per-spec key, so it still reads the old one.
            assert.is_false(enabled(db, 102401, 103))
        end)
    end)

    -- These cases model GetOverrideSpell, not spellbook known-ness. The
    -- known-ness route is measurably wrong in game: it reported
    -- an untalented replacement as known, hiding Blink for every Mage, and
    -- reported both halves of the Dash and Roll pairs as unknown, hiding
    -- neither. The mock returns the id it was given unless a case says
    -- otherwise, which is what the real API does.
    describe("talent choice pairs", function()
        it("suppresses the base when the replacement is live", function()
            _G.C_Spell.overrideSpell[1953] = 212653 -- Blink -> Shimmer
            assert.is_true(NMA:IsReplacedChoice(1953))    -- Blink is replaced
            assert.is_false(NMA:IsReplacedChoice(212653)) -- Shimmer is live
        end)
        it("suppresses the REPLACEMENT when the base is the live half", function()
            -- No override entry: the base resolves to itself, so the base is
            -- live and the untalented replacement must be hidden. Asking each
            -- spell about itself got this wrong and put Tiger Dash on screen
            -- beside Dash.
            assert.is_false(NMA:IsReplacedChoice(1953))  -- Blink is live
            assert.is_true(NMA:IsReplacedChoice(212653)) -- Shimmer is not
            assert.is_false(NMA:IsReplacedChoice(1850))   -- Dash is live
            assert.is_true(NMA:IsReplacedChoice(252216))  -- Tiger Dash is not
        end)
        it("suppresses nothing when a third spell overrides the base", function()
            -- Outside what this rule describes; hiding both halves would be
            -- worse than showing one too many.
            _G.C_Spell.overrideSpell[1953] = 999999
            assert.is_false(NMA:IsReplacedChoice(1953))
            assert.is_false(NMA:IsReplacedChoice(212653))
        end)
        it("does not fail shut for a baseline spell", function()
            -- The first regression hid nothing for Dash and Roll because it
            -- answered false for both halves. Baseline spells resolve to
            -- themselves and must stay visible.
            assert.is_false(NMA:IsReplacedChoice(1850))   -- Dash
            assert.is_false(NMA:IsReplacedChoice(109132)) -- Roll
        end)
        it("never touches spells outside a choice pair", function()
            _G.C_Spell.overrideSpell[358267] = 999999
            assert.is_false(NMA:IsReplacedChoice(358267)) -- Hover
        end)
    end)

    describe("category duration", function()
        it("returns a listed duration directly", function()
            assert.equals(18, NMA:GetCategoryDuration(1850))
        end)

        it("finds a duration through an alias group when the id has none", function()
            -- 77764 is in Stampeding Roar's alias group and carries no listed
            -- duration of its own; only 106898 and 77761 do. Two mechanisms can
            -- answer: the load-time back-fill that copies a sibling's duration
            -- onto every id in the group, and the group walk inside
            -- CategoryDuration itself. This example does not distinguish them
            -- and does not claim to — it fails only if BOTH are gone, which is
            -- exactly the breakage worth catching, since either one alone is
            -- sufficient and neither is safe to delete blind.
            assert.equals(120, NMA:GetCategoryDuration(77764))
        end)

        it("returns zero for a spell in no group and no table", function()
            assert.equals(0, NMA:GetCategoryDuration(6544))
        end)
    end)
end)

describe("NoMovementAlert RoleColor", function()
    it("returns the saved colour for each role in custom mode", function()
        local NMA = L.loadMovementAlert()
        NMA.db = {
            ColorMode = "CUSTOM",
            TextColor = { 1, 1, 1, 1 },
            TimerColor = { 1, 0, 0, 1 },
            SeparatorColor = { 0, 1, 0, 1 },
        }
        assert.same({ 1, 0, 0, 1 }, NMA:RoleColor("TimerColor"))
        assert.same({ 0, 1, 0, 1 }, NMA:RoleColor("SeparatorColor"))
    end)

    it("returns the theme accent for every role in theme mode", function()
        local NMA, KE = L.loadMovementAlert()
        KE.Theme = { accent = { 0.2, 0.4, 0.6, 1 } }
        NMA.db = {
            ColorMode = "THEME",
            TextColor = { 1, 1, 1, 1 },
            TimerColor = { 1, 0, 0, 1 },
            SeparatorColor = { 0, 1, 0, 1 },
        }
        assert.same({ 0.2, 0.4, 0.6, 1 }, NMA:RoleColor("TextColor"))
        assert.same({ 0.2, 0.4, 0.6, 1 }, NMA:RoleColor("TimerColor"))
        assert.same({ 0.2, 0.4, 0.6, 1 }, NMA:RoleColor("SeparatorColor"))
    end)

    it("falls back to the saved colour when no theme accent exists", function()
        local NMA, KE = L.loadMovementAlert()
        KE.Theme = nil
        NMA.db = { ColorMode = "THEME", TextColor = { 1, 1, 1, 1 }, TimerColor = { 1, 0, 0, 1 } }
        assert.same({ 1, 0, 0, 1 }, NMA:RoleColor("TimerColor"))
    end)

    -- isOnGCD is three-valued and its nil is AMBIGUOUS: a live 30s cooldown
    -- reports false for one second and then nil for the remaining 28, while
    -- the remaining time keeps counting down throughout.
    -- So timeUntilEndOfStartRecovery decides, and isOnGCD only vetoes the GCD.
    --
    -- The duration OBJECT is a separate trap and its gate does not move: it
    -- answers even when the spell is ready, which drew a one-second countdown
    -- under a half-minute ability. It stays reachable only on explicit false.
    -- The behaviour is the same in and out of restricted content.
    describe("what counts as a cooldown worth reporting", function()
        local cooldown, durationRemaining

        before_each(function()
            cooldown = {}
            durationRemaining = nil
        end)

        local function load(secret)
            local module, KE = L.loadMovementAlert({
                C_Spell = {
                    GetSpellCooldown = function() return cooldown end,
                    GetSpellCharges = function() return nil end,
                    GetSpellInfo = function(id) return { name = "Spell " .. tostring(id) } end,
                    GetSpellCooldownDuration = function()
                        if durationRemaining == nil then return nil end
                        return { GetRemainingDuration = function() return durationRemaining end }
                    end,
                },
            })
            KE.IsSecretValue = function(_, value) return secret == true and value ~= nil end
            return module
        end

        it("reports a real cooldown", function()
            cooldown = { isOnGCD = false, timeUntilEndOfStartRecovery = 30, duration = 35 }
            local rem, total, isSecret = load():ReadCooldown(1)
            assert.equals(30, rem)
            assert.equals(35, total)
            assert.is_false(isSecret)
        end)

        it("stays quiet on the global cooldown", function()
            cooldown = { isOnGCD = true, timeUntilEndOfStartRecovery = 1.5 }
            assert.is_nil(load():ReadCooldown(1))
        end)

        it("reports a cooldown the client stopped flagging", function()
            -- The Flying Serpent Kick case. isOnGCD goes nil a second into a
            -- real cooldown while the remaining time keeps counting. The old
            -- rule required an explicit false and hid the ability for the
            -- other 28 seconds.
            cooldown = { isOnGCD = nil, timeUntilEndOfStartRecovery = 28.6, duration = 30 }
            local rem, total = load():ReadCooldown(1)
            assert.equals(28.6, rem)
            assert.equals(30, total)
        end)

        it("does NOT consult the duration object when isOnGCD is nil", function()
            -- Ready reads as nil/nil, and the duration object answers anyway.
            -- Reaching it here is what drew a countdown under a ready spell.
            cooldown = {}
            durationRemaining = 1
            assert.is_nil(load():ReadCooldown(1))
        end)

        it("stays quiet when the spell is idle", function()
            durationRemaining = 30
            assert.is_nil(load():ReadCooldown(1))
        end)

        it("passes a secret remaining through without a total", function()
            cooldown = { isOnGCD = false, timeUntilEndOfStartRecovery = 30, duration = 35 }
            local rem, total, isSecret = load(true):ReadCooldown(1)
            assert.equals(30, rem)
            assert.is_nil(total)
            assert.is_true(isSecret)
        end)

        it("falls back to the duration object once a real cooldown is confirmed", function()
            cooldown = { isOnGCD = false }
            durationRemaining = 22
            assert.equals(22, load():ReadCooldown(1))
        end)
    end)

end)

local BURNING_RUSH = 111400

-- The loader does not seed the buff-readback state, because the module's own
-- OnEnable is never called headlessly. Each case starts from a known table
-- rather than inheriting one, and Update is stubbed so RefreshBuffStates can
-- run without a frame.
local function seededNMA(overrides)
    local NMA = L.loadMovementAlert(overrides)
    NMA.tracked = { { spellId = BURNING_RUSH, isBuffActive = true } }
    NMA.auraActive = {}
    NMA.glowing = {}
    NMA.auraScanTrusted = overrides.trusted == true or nil
    NMA.Update = function() end
    return NMA
end

describe("NoMovementAlert buff readback", function()
    it("reports active from a readable aura", function()
        local NMA = seededNMA({ aura = { spellId = BURNING_RUSH } })
        NMA:RefreshBuffStates()
        assert.is_true(NMA.auraActive[BURNING_RUSH])
    end)

    it("honours earned trust while identities are readable", function()
        -- Positive control for the fix: trust still works where it was earned.
        -- Without this, deleting the trust path entirely would pass every other
        -- case in this block.
        local NMA = seededNMA({ aura = nil, trusted = true })
        NMA.glowing[BURNING_RUSH] = true
        NMA:RefreshBuffStates()
        assert.is_false(NMA.auraActive[BURNING_RUSH])
    end)

    it("ignores earned trust while identities are hidden and uses the glow", function()
        -- The defect. Trust earned out of combat made the nil read authoritative
        -- inside a key, so the glow fallback was unreachable exactly when it was
        -- the only working source.
        local NMA = seededNMA({ aura = nil, trusted = true, aurasHidden = true })
        NMA.glowing[BURNING_RUSH] = true
        NMA:RefreshBuffStates()
        assert.is_true(NMA.auraActive[BURNING_RUSH])
    end)

    it("still reports inactive while hidden when the glow is also off", function()
        local NMA = seededNMA({ aura = nil, trusted = true, aurasHidden = true })
        NMA:RefreshBuffStates()
        assert.is_false(NMA.auraActive[BURNING_RUSH])
    end)

    it("uses the glow when trust was never earned", function()
        local NMA = seededNMA({ aura = nil })
        NMA.glowing[BURNING_RUSH] = true
        NMA:RefreshBuffStates()
        assert.is_true(NMA.auraActive[BURNING_RUSH])
    end)
end)

describe("NoMovementAlert trust acquisition", function()
    it("does NOT grant trust while identities are hidden", function()
        local NMA = seededNMA({ aura = { spellId = BURNING_RUSH }, aurasHidden = true })
        NMA:OnAura(nil, "player")
        assert.is_nil(NMA.auraScanTrusted)
    end)

    it("grants trust on a successful read while identities are readable", function()
        local NMA = seededNMA({ aura = { spellId = BURNING_RUSH } })
        NMA:OnAura(nil, "player")
        assert.is_true(NMA.auraScanTrusted)
    end)
end)

-- Group B reshape: the answer used to be computed ONCE for the whole sweep
-- and applied to every entry; now each entry asks for itself. Production
-- defines only one buff-active spell, so a synthetic second is added here to
-- prove two entries in the same sweep can land on different answers -- the
-- thing a hoisted answer could never produce.
describe("NoMovementAlert buff readback asks per spell", function()
    local SYNTHETIC_ID = 999001

    -- The secret map is read at CALL time (RefreshBuffStates runs after this
    -- returns), so it is populated once the real spell id is known from the
    -- loaded module's own exported table rather than guessed up front.
    local function loadFixture(aurasHidden)
        local secretMap = {}
        local NMA, KE = L.loadMovementAlert({
            aurasHidden = aurasHidden,
            C_Secrets = {
                ShouldSpellAuraBeSecret = function(spellId) return secretMap[spellId] end,
            },
        })
        NMA.auraActive = {}
        NMA.auraScanTrusted = true
        NMA.Update = function() end
        return NMA, secretMap, next(KE.MOVEMENT_BUFF_ACTIVE)
    end

    it("answers two spells in the same sweep differently, which a hoisted answer could not", function()
        local NMA, secretMap, realId = loadFixture(false)
        secretMap[realId] = true
        secretMap[SYNTHETIC_ID] = false
        NMA.tracked = {
            { spellId = realId, isBuffActive = true },
            { spellId = SYNTHETIC_ID, isBuffActive = true },
        }
        -- Load-bearing: an empty glow table makes both entries fall through to
        -- false no matter which spell is hidden, so seeding only the hidden
        -- spell's glow is what lets the two answers differ.
        NMA.glowing = { [realId] = true }

        NMA:RefreshBuffStates()

        assert.is_true(NMA.auraActive[realId])
        assert.is_false(NMA.auraActive[SYNTHETIC_ID])
    end)

    it("falls through to the glow when the exact answer hides a spell the broad answer would show", function()
        local NMA, secretMap, realId = loadFixture(false)
        secretMap[realId] = true
        NMA.tracked = { { spellId = realId, isBuffActive = true } }
        NMA.glowing = { [realId] = true }

        NMA:RefreshBuffStates()

        assert.is_true(NMA.auraActive[realId])
    end)

    it("lets trust report the buff off when the exact answer clears a spell the broad answer would hide", function()
        local NMA, secretMap, realId = loadFixture(true)
        secretMap[realId] = false
        NMA.tracked = { { spellId = realId, isBuffActive = true } }
        NMA.glowing = { [realId] = true }

        NMA:RefreshBuffStates()

        assert.is_false(NMA.auraActive[realId])
    end)
end)

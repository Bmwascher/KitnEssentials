-- Modules/Utilities/NoMovementAlert.lua -- the resolution layer only. The
-- tracking engine, the frames and the event wiring are a verbatim port and are
-- verified in game; what is tested here is the one rule a later edit breaks
-- silently: which spells count as enabled, and for which spec.
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

    describe("talent choice pairs", function()
        it("suppresses the replaced half when the replacement is known", function()
            _G.C_SpellBook.known[212653] = true -- Shimmer
            assert.is_true(NMA:IsReplacedChoice(1953))    -- Blink is replaced
            assert.is_false(NMA:IsReplacedChoice(212653)) -- Shimmer is not
        end)
        it("suppresses nothing when only the base is known", function()
            _G.C_SpellBook.known[1953] = true -- Blink alone
            assert.is_false(NMA:IsReplacedChoice(1953))
            assert.is_false(NMA:IsReplacedChoice(212653))
        end)
        it("never touches spells outside a choice pair", function()
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

    -- isOnGCD is three-valued and only an explicit false means "a real cooldown
    -- is running". Treating its nil as "cannot tell" and reading the cooldown
    -- duration object instead is what drew a one-second countdown under an
    -- ability whose cooldown is half a minute, so the nil case is the one these
    -- exist to pin. The behaviour is the same in and out of restricted content.
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

        it("stays quiet when the client declines to answer", function()
            -- isOnGCD absent (neither true nor false) means the client is not
            -- saying. Nothing may render -- and the duration object below
            -- must not be consulted either.
            cooldown = { timeUntilEndOfStartRecovery = 1 }
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

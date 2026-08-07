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

    -- Under restriction the client will not say whether a cooldown is only the
    -- global one: isOnGCD comes back nil and every number is secret. isActive
    -- still answers plainly but is true for both, so the module times the
    -- active window and treats anything outlasting the ceiling as real. Drawing
    -- the window that does NOT outlast it is the bug these cover.
    describe("global cooldown ceiling", function()
        local now, cooldown, durationRemaining

        before_each(function()
            now = 1000
            cooldown = { isActive = false }
            durationRemaining = nil
        end)

        local function load(secret)
            local module, KE = L.loadMovementAlert({
                GetTime = function() return now end,
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
            module.cdSince = {}
            return module
        end

        it("stays quiet while nothing is on cooldown", function()
            assert.is_nil(load():ReadCooldown(1))
        end)

        it("reports at once when the client answers the question outright", function()
            -- Outside a key isOnGCD is a real answer, so nothing is timed and
            -- the countdown appears immediately -- no ceiling is paid.
            local NMA = load()
            cooldown = { isActive = true, isOnGCD = false, timeUntilEndOfStartRecovery = 30 }
            assert.equals(30, NMA:ReadCooldown(1))
            assert.is_nil(NMA.cdSince[1])
        end)

        it("stays quiet at once when the client says it is only the global cooldown", function()
            local NMA = load()
            cooldown = { isActive = true, isOnGCD = true, timeUntilEndOfStartRecovery = 1.5 }
            assert.is_nil(NMA:ReadCooldown(1))
            now = now + 5
            assert.is_nil(NMA:ReadCooldown(1))
        end)

        it("stays quiet while the active window is still inside the ceiling", function()
            local NMA = load()
            cooldown = { isActive = true, timeUntilEndOfStartRecovery = 1.4 }
            assert.is_nil(NMA:ReadCooldown(1))
            now = now + 1.4
            assert.is_nil(NMA:ReadCooldown(1))
            assert.is_true(NMA.cdPending)
        end)

        it("never draws a window that ends inside the ceiling", function()
            local NMA = load()
            cooldown = { isActive = true, timeUntilEndOfStartRecovery = 1.5 }
            assert.is_nil(NMA:ReadCooldown(1))
            now = now + 1.0
            assert.is_nil(NMA:ReadCooldown(1))
            cooldown = { isActive = false }
            now = now + 0.5
            assert.is_nil(NMA:ReadCooldown(1))
        end)

        it("reports the remaining time once the window outlasts the ceiling", function()
            local NMA = load()
            cooldown = { isActive = true, timeUntilEndOfStartRecovery = 30, duration = 35 }
            NMA:ReadCooldown(1)
            now = now + 1.6
            local rem, total, isSecret = NMA:ReadCooldown(1)
            assert.equals(30, rem)
            assert.equals(35, total)
            assert.is_false(isSecret)
        end)

        it("stays quiet once the spell is ready again, however old the window", function()
            -- The client keeps offering a remaining time after the cooldown
            -- ends, so readiness has to be read from isActive rather than
            -- from whether a number is on offer.
            local NMA = load()
            cooldown = { isActive = true, timeUntilEndOfStartRecovery = 30 }
            NMA:ReadCooldown(1)
            now = now + 60
            cooldown = { isActive = false, timeUntilEndOfStartRecovery = 30 }
            assert.is_nil(NMA:ReadCooldown(1))
        end)

        it("times each new window from its own start", function()
            local NMA = load()
            cooldown = { isActive = true, timeUntilEndOfStartRecovery = 1.2 }
            NMA:ReadCooldown(1)
            cooldown = { isActive = false }
            now = now + 1.2
            NMA:ReadCooldown(1)
            assert.is_nil(NMA.cdSince[1])
            -- A fresh window inherits nothing from the one that just ended.
            cooldown = { isActive = true, timeUntilEndOfStartRecovery = 30 }
            now = now + 1.0
            assert.is_nil(NMA:ReadCooldown(1))
        end)

        it("passes a secret remaining through without a total", function()
            local NMA = load(true)
            cooldown = { isActive = true, timeUntilEndOfStartRecovery = 30, duration = 35 }
            NMA:ReadCooldown(1)
            now = now + 1.6
            local rem, total, isSecret = NMA:ReadCooldown(1)
            assert.equals(30, rem)
            assert.is_nil(total)
            assert.is_true(isSecret)
        end)

        it("falls back to the duration object when the recovery field is missing", function()
            local NMA = load()
            cooldown = { isActive = true }
            durationRemaining = 22
            NMA:ReadCooldown(1)
            now = now + 1.6
            assert.equals(22, NMA:ReadCooldown(1))
        end)
    end)
end)

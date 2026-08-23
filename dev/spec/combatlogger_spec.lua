-- Modules/QoL/CombatLogger.lua -- arena classification and the party guard.
--
-- The arena branch shipped calling nil for months: IsArenaSkirmish is a plain
-- global and the module cached it off C_PvP, which has no such member. The
-- loader's C_PvP carries only the members the module is supposed to use, so
-- reaching for a namespaced name that does not exist fails here too.

local L = require("dev.spec._ke_loader")

describe("CombatLogger arena classification", function()
    local CL, rec

    local function db(overrides)
        local t = {
            Enabled = true,
            QuietMode = true,
            DelayStop = false,
            PvPRatedArena = false,
            PvPArenaSkirmish = false,
            PvPSoloShuffle = false,
            PvPWarGame = false,
        }
        for k, v in pairs(overrides or {}) do t[k] = v end
        return t
    end

    before_each(function()
        CL, rec = L.loadCombatLogger()
        CL.isLogging = false
    end)

    it("logs a rated arena when the rated arena toggle is on", function()
        CL.db = db({ PvPRatedArena = true })
        rec.pvp.ratedArena = true
        CL:CheckArenaLogging()
        assert.is_true(rec.logging)
    end)

    it("leaves a rated arena alone when its toggle is off", function()
        CL.db = db({ PvPRatedArena = false })
        rec.pvp.ratedArena = true
        CL:CheckArenaLogging()
        assert.is_false(rec.logging)
    end)

    it("reads a skirmish as a skirmish, not a rated arena", function()
        -- The client reports a skirmish as a rated arena as well, so the rated
        -- branch has to exclude it or a skirmish would follow the wrong toggle.
        CL.db = db({ PvPRatedArena = true, PvPArenaSkirmish = false })
        rec.pvp.ratedArena = true
        rec.pvp.skirmish = true
        CL:CheckArenaLogging()
        assert.is_false(rec.logging)
    end)

    it("logs a skirmish when the skirmish toggle is on", function()
        CL.db = db({ PvPRatedArena = false, PvPArenaSkirmish = true })
        rec.pvp.ratedArena = true
        rec.pvp.skirmish = true
        CL:CheckArenaLogging()
        assert.is_true(rec.logging)
    end)

    it("reads solo shuffle as solo shuffle, not a rated arena", function()
        CL.db = db({ PvPRatedArena = true, PvPSoloShuffle = false })
        rec.pvp.ratedArena = true
        rec.pvp.soloShuffle = true
        CL:CheckArenaLogging()
        assert.is_false(rec.logging)
    end)

    it("logs solo shuffle when its own toggle is on", function()
        CL.db = db({ PvPRatedArena = false, PvPSoloShuffle = true })
        rec.pvp.soloShuffle = true
        CL:CheckArenaLogging()
        assert.is_true(rec.logging)
    end)

    it("reads a wargame as a wargame, not a rated arena", function()
        CL.db = db({ PvPRatedArena = true, PvPWarGame = false })
        rec.pvp.ratedArena = true
        rec.pvp.wargame = true
        CL:CheckArenaLogging()
        assert.is_false(rec.logging)
    end)

    it("logs a wargame when its own toggle is on", function()
        CL.db = db({ PvPRatedArena = false, PvPWarGame = true })
        rec.pvp.wargame = true
        CL:CheckArenaLogging()
        assert.is_true(rec.logging)
    end)

    it("stops a running log of ours once no arena kind wants it", function()
        CL.db = db()
        CL.isLogging = true
        CL.startedByUs = true
        rec.logging = true
        CL:CheckArenaLogging()
        assert.is_false(rec.logging)
    end)

    -- Ownership. A log the player opened by hand is not ours to close, and
    -- without this the module silently fights whatever else they are running.
    it("leaves a log it did not start running", function()
        CL.db = db()
        CL.isLogging = true
        CL.startedByUs = false
        rec.logging = true
        CL:CheckArenaLogging()
        assert.is_true(rec.logging)
    end)

    it("takes over a running log in content it would have logged itself", function()
        CL.db = db({ PvPRatedArena = true, QuietMode = false })
        rec.pvp.ratedArena = true
        rec.logging = true
        CL.isLogging = true
        CL.startedByUs = false
        CL:CheckArenaLogging()
        assert.is_true(CL.startedByUs)
        assert.is_true(#rec.prints > 0)
    end)

    it("does not take over a running log in content it would not log", function()
        CL.db = db()
        rec.logging = true
        CL.isLogging = true
        CL.startedByUs = false
        CL:CheckArenaLogging()
        assert.is_false(CL.startedByUs)
    end)

    -- Asks, but does not block. A basic log beats no log, and accepting the
    -- prompt afterwards cycles the running log so it records advanced detail.
    it("starts anyway without advanced combat logging, and asks", function()
        CL, rec = L.loadCombatLogger({
            C_CVar = { GetCVar = function() return "0" end, SetCVar = function() end },
        })
        CL.isLogging = false
        CL.db = db({ PromptAdvanced = true, PvPRatedArena = true })
        rec.pvp.ratedArena = true
        CL:CheckArenaLogging()
        assert.is_true(rec.logging)
        assert.equals("KE_COMBATLOGGER_ACL_PROMPT", rec.popups[1])
    end)

    it("does not ask when the prompt is switched off", function()
        CL, rec = L.loadCombatLogger({
            C_CVar = { GetCVar = function() return "0" end, SetCVar = function() end },
        })
        CL.isLogging = false
        CL.db = db({ PromptAdvanced = false, PvPRatedArena = true })
        rec.pvp.ratedArena = true
        CL:CheckArenaLogging()
        assert.is_true(rec.logging)
        assert.equals(0, #rec.popups)
    end)

    -- Turning it on must not need a reload: Blizzard's own checkbox for the
    -- CVar carries no restart flag. A log already running does have to be
    -- cycled, because its format was fixed when it opened.
    it("cycles a running log when advanced logging is turned on", function()
        local written = {}
        local cvar = "0"
        CL, rec = L.loadCombatLogger({
            C_CVar = {
                GetCVar = function() return cvar end,
                SetCVar = function(_, v) cvar = v; written[#written + 1] = v end,
            },
        })
        CL.db = db()
        CL.isLogging = true
        rec.logging = true
        CL:EnableAdvanced()
        assert.same({ "1" }, written)
        -- Closed and reopened, so the file the watchers see is a new one.
        assert.is_true(rec.logging)
    end)

    it("writes nothing when advanced logging is already on", function()
        local written = {}
        CL, rec = L.loadCombatLogger({
            C_CVar = {
                GetCVar = function() return "1" end,
                SetCVar = function(_, v) written[#written + 1] = v end,
            },
        })
        CL.db = db()
        CL:EnableAdvanced()
        assert.equals(0, #written)
    end)

    describe("scenario logging", function()
        it("logs a Torghast scenario when Scenario is on", function()
            CL.db = db({ Scenario = true })
            local should, label = CL:ShouldLog("scenario", 167, 5)
            assert.is_true(should)
            assert.equals("a scenario", label)
        end)

        it("logs a delve scenario when Scenario is on", function()
            -- The whole point of the widening: 208 is not 167, and the old
            -- rule returned false for it without consulting any setting.
            CL.db = db({ Scenario = true })
            local should, label = CL:ShouldLog("scenario", 208, 5)
            assert.is_true(should)
            assert.equals("a scenario", label)
        end)

        it("logs a scenario of unknown difficulty when Scenario is on", function()
            CL.db = db({ Scenario = true })
            assert.is_true((CL:ShouldLog("scenario", nil, nil)))
        end)

        it("refuses every scenario when Scenario is off", function()
            CL.db = db({ Scenario = false })
            assert.is_false((CL:ShouldLog("scenario", 167, 5)))
            assert.is_false((CL:ShouldLog("scenario", 208, 5)))
        end)

        it("returns a strict false, never nil, for an absent Scenario key", function()
            -- Callers branch on the first return; nil and false are not the
            -- same thing to a caller that stores it.
            CL.db = db({})
            local should = CL:ShouldLog("scenario", 167, 5)
            assert.is_false(should)
        end)
    end)

    describe("advanced logging prompt", function()
        it("prompts when PromptAdvanced is absent", function()
            CL.db = db({})
            assert.is_true(CL:_ShouldPromptAdvanced())
        end)

        it("prompts when PromptAdvanced is true", function()
            CL.db = db({ PromptAdvanced = true })
            assert.is_true(CL:_ShouldPromptAdvanced())
        end)

        it("stays silent when PromptAdvanced is false", function()
            CL.db = db({ PromptAdvanced = false })
            assert.is_false(CL:_ShouldPromptAdvanced())
        end)
    end)
end)

describe("CombatLogger content rules", function()
    local CL

    before_each(function()
        CL = L.loadCombatLogger()
        CL.db = {
            DungeonMythicPlus = true,
            DungeonNormal = true,
            RaidNormal = true,
            RaidMythic = true,
        }
    end)

    it("refuses a raid queued as a party regardless of difficulty", function()
        -- Some raid content reports instanceType "party"; without the size
        -- guard it would follow whichever dungeon toggle matched.
        assert.is_false(CL:ShouldLog("party", 1, 20))
        assert.is_true(CL:ShouldLog("party", 1, 5))
    end)

    it("treats a missing party size as a party", function()
        assert.is_true(CL:ShouldLog("party", 8, nil))
    end)

    it("returns false for an unmapped difficulty rather than nil", function()
        assert.is_false(CL:ShouldLog("party", 999, 5))
        assert.is_false(CL:ShouldLog("raid", 999, 20))
    end)

    it("ignores content types it does not handle", function()
        assert.is_false(CL:ShouldLog("none", 0, 0))
        assert.is_false(CL:ShouldLog("arena", 0, 5))
    end)
end)

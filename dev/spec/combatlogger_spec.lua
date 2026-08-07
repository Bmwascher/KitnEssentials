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
            DisableACLPrompt = true,
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

    it("stops a running log once no arena kind wants it", function()
        CL.db = db()
        CL.isLogging = true
        rec.logging = true
        CL:CheckArenaLogging()
        assert.is_false(rec.logging)
    end)

    it("refuses to start without advanced combat logging", function()
        CL, rec = L.loadCombatLogger({
            C_CVar = { GetCVar = function() return "0" end, SetCVar = function() end },
        })
        CL.isLogging = false
        CL.db = db({ DisableACLPrompt = false, PvPRatedArena = true })
        rec.pvp.ratedArena = true
        CL:CheckArenaLogging()
        assert.is_false(rec.logging)
        assert.equals("KE_COMBATLOGGER_ACL_PROMPT", rec.popups[1])
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

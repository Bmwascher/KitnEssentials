-- Modules/DungeonTools/KicksCasts/PartyStopsRules.lua: who gets a stop's
-- icon, which enemy plates are watched, and where the grid shows. The
-- shipped stops are data and get no case; these cases use their own.
local L = require("dev.spec._ke_loader")

describe("party stops rules", function()
    local Rules

    before_each(function()
        Rules = L.loadPartyStopsRules()
    end)

    it("gives a member a stop's icon by class, then need talents, then a known spec or role", function()
        local plain = { class = "MONK" }
        local needy = { class = "WARRIOR", need = { 1, 2 } }
        local tank = { class = "DEATHKNIGHT", spec = 250, role = "TANK" }
        local cases = {
            { plain, { class = "PRIEST" }, nil, false },
            { needy, { class = "WARRIOR" }, { [1] = 0, [2] = 0 }, false },
            { needy, { class = "WARRIOR" }, { [1] = 1, [2] = 0 }, true },
            { needy, { class = "WARRIOR" }, { [1] = 0 }, true },
            { needy, { class = "WARRIOR" }, { [1] = 0, [2] = 0 }, false, { [2] = true } },
            { needy, { class = "WARRIOR" }, { [1] = 0, [2] = 0 }, false, { [1] = true } },
            { needy, { class = "WARRIOR" }, { [1] = 0, [2] = 0 }, true, { [1] = true, [2] = true } },
            { needy, { class = "WARRIOR" }, nil, true },
            { tank, { class = "DEATHKNIGHT", spec = 250 }, nil, true },
            { tank, { class = "DEATHKNIGHT", spec = 251, role = "TANK" }, nil, false },
            { tank, { class = "DEATHKNIGHT", role = "TANK" }, nil, true },
            { tank, { class = "DEATHKNIGHT", role = "DAMAGER" }, nil, false },
            { tank, { class = "DEATHKNIGHT" }, nil, true },
        }
        for i, case in ipairs(cases) do
            assert.equals(case[4], Rules.Fits(case[1], case[2], case[3], case[5]), "case " .. i)
        end
    end)

    it("watches an attackable, unassistable, living non-boss, and only one in combat when strict", function()
        local NIL = {}
        local KEYS = { "exists", "canAttack", "canAssist", "isDead", "isBoss", "inCombat" }
        local function api(changes)
            local reads = {
                exists = true, canAttack = true, canAssist = false, isDead = false, isBoss = false, inCombat = true,
            }
            for key, value in pairs(changes) do
                if value == NIL then reads[key] = nil else reads[key] = value end
            end
            local out = {}
            for _, key in ipairs(KEYS) do
                out[key] = function() return reads[key] end
            end
            return out
        end
        local cases = {
            { {}, true, nil },
            { { exists = false }, false, "no unit" },
            { { canAttack = false }, false, "not attackable" },
            { { canAssist = true }, false, "assistable, or unreadable" },
            { { canAssist = NIL }, false, "assistable, or unreadable" },
            { { isDead = true }, false, "dead" },
            { { isBoss = true }, false, "boss" },
            { { inCombat = false }, true, "not in combat" },
            { { inCombat = false }, false, nil },
            { { inCombat = NIL }, true, nil },
        }
        for i, case in ipairs(cases) do
            assert.equals(case[3], Rules.Verdict("nameplate1", api(case[1]), case[2]), "case " .. i)
        end
    end)

    it("shows in a party, never in a raid, only in a party instance when asked, and waits on unknown facts", function()
        local function facts(inGroup, inRaid, inInstance, instanceType)
            return { inGroup = inGroup, inRaid = inRaid, inInstance = inInstance, instanceType = instanceType }
        end
        local dungeons = { OnlyInDungeons = true }
        local cases = {
            { facts(true, true, true, "raid"), {}, false },
            { facts(true, false, false, "none"), {}, true },
            { facts(false, false, false, "none"), {}, false },
            { facts(false, false, false, "none"), { OnlyInParty = false }, true },
            { facts(true, false, false, "none"), dungeons, false },
            { facts(true, false, true, "party"), dungeons, true },
            { facts(true, false, true, "scenario"), dungeons, false },
            { facts(true, nil, false, "none"), {}, nil },
            { facts(true, false, nil, nil), dungeons, nil },
        }
        for i, case in ipairs(cases) do
            assert.equals(case[3], Rules.Live(case[1], case[2]), "case " .. i)
        end
    end)

    it("wants an inspect until the talents are covered, unmarked and its own last read worked; a covered one is only stale", function()
        local want = { [1] = true, [2] = true }
        local covered = { covered = { [1] = true, [2] = true } }
        local stale = { covered = { [1] = true, [2] = true }, stale = "ready check" }
        local short = { covered = { [1] = true } }
        local cases = {
            { nil, false, true, false, "no snapshot" },
            { short, false, true, false, "a talent uncovered" },
            { covered, false, false, false, "read" },
            { stale, false, true, true, "marked stale" },
            { covered, true, true, true, "own read failed, mark cleared by another owner" },
        }
        for _, case in ipairs(cases) do
            assert.equals(case[3], Rules.InspectWanted(case[1], want, case[2]), case[5])
            assert.equals(case[4], Rules.OnlyStale(case[1], want, case[2]), case[5])
        end
    end)
end)

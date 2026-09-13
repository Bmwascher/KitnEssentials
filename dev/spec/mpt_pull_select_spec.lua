-- luacheck: std lua51+busted
-- Selection and format predicates of MythicPlusTimer_Pull.lua: public
-- eligibility, per-unit admission and the pull label's format choice.
--
-- Loads the REAL Modules/Dungeons/MythicPlusTimer/MythicPlusTimer_Pull.lua
-- headlessly. The unit predicates it captures at load are stubbed per case;
-- issecretvalue classifies one sentinel value as secret. Honesty boundary:
-- the mock verifies which branch a secret classification takes, never real
-- 12.0 taint semantics.
local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

describe("MPT pull: selection predicates", function()
    local MPT
    local units          -- [token] = { dead=, attackable=, threat=, controlled= }
    local SECRET = {}    -- sentinel: issecretvalue(SECRET) is true

    local function baseline()
        local db = { Enabled = true, ShowForces = true, ShowPullOverlay = true }
        local run = { active = true, completed = false,
                      forces = { total = 290, current = 204, completed = false } }
        return db, run
    end

    before_each(function()
        mock.install({
            issecretvalue = function(v) return v == SECRET end,
        })
        local modules = helpers.installAddonShim()
        units = {}
        _G.UnitExists = function(u) return units[u] ~= nil end
        _G.UnitIsDeadOrGhost = function(u) return units[u].dead end
        _G.UnitCanAttack = function(_, u) return units[u].attackable end
        _G.UnitThreatSituation = function(_, u) return units[u].threat end
        _G.UnitPlayerControlled = function(u)
            local base = u:match("^(.-)target$")
            return base and units[base] and units[base].controlled
        end
        _G.C_NamePlate = { GetNamePlates = function() return {} end }
        _G.C_ScenarioInfo = { GetUnitCriteriaProgressValues = function() return nil end }
        _G.C_StringUtil = { RoundToNearestString = function(v) return tostring(v) end }
        _G.CreateAbbreviateConfig = function() return {} end
        helpers.loadModule("Modules/Dungeons/MythicPlusTimer/MythicPlusTimer_Pull.lua",
            { Print = function() end })
        MPT = modules["MythicPlusTimer"]
        assert(MPT and MPT.PullEligible, "real MythicPlusTimer_Pull.lua did not load")
    end)

    after_each(function() mock.reset() end)

    it("eligibility holds for an enabled, opted-in, active, incomplete run and refuses each disabling state", function()
        local cases = {
            { name = "baseline",          expect = true },
            { name = "module disabled",   mut = function(db) db.Enabled = false end },
            { name = "forces hidden",     mut = function(db) db.ShowForces = false end },
            { name = "estimate opted out", mut = function(db) db.ShowPullOverlay = false end },
            { name = "preview",           preview = true },
            { name = "inactive run",      mut = function(_, run) run.active = false end },
            { name = "completed run",     mut = function(_, run) run.completed = true end },
            { name = "forces complete",   mut = function(_, run) run.forces.completed = true end },
            { name = "zero total",        mut = function(_, run) run.forces.total = 0 end },
            { name = "non-numeric total", mut = function(_, run) run.forces.total = "290" end },
            { name = "missing forces",    mut = function(_, run) run.forces = nil end },
        }
        for _, c in ipairs(cases) do
            local db, run = baseline()
            if c.mut then c.mut(db, run) end
            assert.are.equal(c.expect == true, MPT.PullEligible(db, run, c.preview), c.name)
        end
    end)

    it("admission rejects missing, dead and non-attackable units", function()
        units.nameplate1 = { dead = true,   attackable = true,   threat = 0 }
        units.nameplate2 = { dead = false,  attackable = false,  threat = 0 }
        units.nameplate3 = { dead = SECRET, attackable = true,   threat = 0 }
        units.nameplate4 = { dead = false,  attackable = SECRET, threat = 0 }
        assert.is_false(MPT.PullAdmits("nameplate9"), "missing")
        for _, u in ipairs({ "nameplate1", "nameplate2", "nameplate3", "nameplate4" }) do
            assert.is_false(MPT.PullAdmits(u), u)
        end
    end)

    it("admission selects on readable threat, else on a readable true controlled target", function()
        local cases = {
            { threat = 0,      controlled = false,  admit = true,  name = "readable threat" },
            { threat = 3,      controlled = nil,    admit = true,  name = "high threat, no target read" },
            { threat = nil,    controlled = true,   admit = true,  name = "fallback true" },
            { threat = SECRET, controlled = true,   admit = true,  name = "secret threat, fallback true" },
            { threat = nil,    controlled = false,  admit = false, name = "no threat, fallback false" },
            { threat = SECRET, controlled = false,  admit = false, name = "secret threat, fallback false" },
            { threat = nil,    controlled = SECRET, admit = false, name = "no threat, fallback secret" },
            { threat = SECRET, controlled = SECRET, admit = false, name = "both secret" },
        }
        for _, c in ipairs(cases) do
            units.nameplate1 = { dead = false, attackable = true, threat = c.threat, controlled = c.controlled }
            assert.are.equal(c.admit, MPT.PullAdmits("nameplate1"), c.name)
        end
    end)

    it("the pull label format follows the credited forces format", function()
        local cases = {
            { "PERCENT", "PERCENT" }, { "PERCENT_LABEL", "PERCENT" },
            { "COUNT", "COUNT" }, { "REMAINING", "COUNT" },
            { "COUNT_PERCENT", "COUNT_PERCENT" },
            { "CUSTOM", "PERCENT" }, { "BOGUS", "PERCENT" }, { false, "PERCENT" },
        }
        for _, c in ipairs(cases) do
            assert.are.equal(c[2], MPT.PullTextFormat(c[1] or nil), tostring(c[1]))
        end
    end)
end)

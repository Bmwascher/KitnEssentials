-- Tier 1: the companion-CVar rule only (tiered test policy). The CVar def
-- tables, the label copy and the page layout are data and frame work.
--
-- findYourselfModeOutline does nothing on its own -- Blizzard's own control
-- writes the master findYourselfAnywhere alongside it. Turning a mode off must
-- not take the master down while another highlight mode still wants it.
--
-- The last three cases are not rule coverage and are here on purpose. The rule
-- is only reachable through the shipped def and through ApplyCVars, so without
-- them every other case still passes on a build where the rule is written
-- correctly and wired to nothing.

local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

-- The module is loaded once per test with a recording C_CVar, so "wrote
-- nothing" is observable rather than inferred.
local function newFixture(cvars)
    cvars = cvars or {}
    -- The master exists on every real client, so it exists here unless a case
    -- says otherwise. Cases below list only the CVars they care about, and that
    -- is fine for reads that mean "off" -- but ApplyCompanion refuses to write a
    -- companion that does not exist, so an omitted master would silently turn
    -- every write case into a test of the absent-CVar refusal instead.
    if cvars.findYourselfAnywhere == nil then cvars.findYourselfAnywhere = "0" end
    local writes = {}

    _G.C_CVar = {
        GetCVar = function(key) return cvars[key] end,
        SetCVar = function(key, value)
            writes[#writes + 1] = { key = key, value = value }
            cvars[key] = tostring(value)
        end,
    }
    _G.SetCVar = _G.C_CVar.SetCVar
    _G.GetCVar = _G.C_CVar.GetCVar
    _G.CreateFrame = function()
        return setmetatable({}, { __index = function() return function() end end })
    end
    _G.hooksecurefunc = function() end
    _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
    _G.InCombatLockdown = function() return false end
    _G.issecretvalue = function() return false end
    _G.StaticPopupDialogs = {}
    _G.UIParent = _G.CreateFrame()

    -- The module indexes C_SpecializationInfo at file scope.
    mock.installSpecInfo()

    local modules = helpers.installAddonShim()
    helpers.loadModule("Modules/QoL/Automation.lua", { Print = function() end })
    local AU = modules["Automation"]
    AU.RegisterEvent = function() end
    AU.SetEnabledState = function() end

    local function writesTo(key)
        local found = {}
        for i = 1, #writes do
            if writes[i].key == key then found[#found + 1] = writes[i].value end
        end
        return found
    end

    return { AU = AU, writes = writes, writesTo = writesTo, cvars = cvars }
end

local OUTLINE = {
    key = "findYourselfModeOutline",
    type = "boolean",
    companion = "findYourselfAnywhere",
    companionKeepAlive = { "findYourselfModeCircle", "findYourselfModeIcon" },
}

describe("companion CVars", function()
    it("writes nothing for a def that has no companion", function()
        local f = newFixture()
        f.AU:ApplyCompanion({ key = "ffxGlow", type = "boolean" }, true)
        assert.equals(0, #f.writes)
    end)

    it("turns the master on when the mode goes on", function()
        local f = newFixture()
        f.AU:ApplyCompanion(OUTLINE, true)
        assert.same({ "1" }, f.writesTo("findYourselfAnywhere"))
    end)

    it("turns the master on even when a sibling mode is already on", function()
        local f = newFixture({ findYourselfModeCircle = "1" })
        f.AU:ApplyCompanion(OUTLINE, true)
        assert.same({ "1" }, f.writesTo("findYourselfAnywhere"))
    end)

    it("turns the master off when the mode goes off and no sibling wants it", function()
        local f = newFixture({ findYourselfModeCircle = "0", findYourselfModeIcon = "0" })
        f.AU:ApplyCompanion(OUTLINE, false)
        assert.same({ "0" }, f.writesTo("findYourselfAnywhere"))
    end)

    it("treats an unset sibling as not wanting the master", function()
        local f = newFixture()
        f.AU:ApplyCompanion(OUTLINE, false)
        assert.same({ "0" }, f.writesTo("findYourselfAnywhere"))
    end)

    it("leaves the master alone when the circle mode is on", function()
        local f = newFixture({ findYourselfModeCircle = "1", findYourselfModeIcon = "0" })
        f.AU:ApplyCompanion(OUTLINE, false)
        assert.same({}, f.writesTo("findYourselfAnywhere"))
    end)

    it("leaves the master alone when the icon mode is on", function()
        local f = newFixture({ findYourselfModeCircle = "0", findYourselfModeIcon = "1" })
        f.AU:ApplyCompanion(OUTLINE, false)
        assert.same({}, f.writesTo("findYourselfAnywhere"))
    end)

    it("leaves the master alone when both sibling modes are on", function()
        local f = newFixture({ findYourselfModeCircle = "1", findYourselfModeIcon = "1" })
        f.AU:ApplyCompanion(OUTLINE, false)
        assert.same({}, f.writesTo("findYourselfAnywhere"))
    end)

    it("turns the master off for a def with no keep-alive list", function()
        local f = newFixture({ findYourselfModeCircle = "1" })
        f.AU:ApplyCompanion({ key = "x", type = "boolean", companion = "findYourselfAnywhere" }, false)
        assert.same({ "0" }, f.writesTo("findYourselfAnywhere"))
    end)

    -- Membership, not order: which siblings keep the master alive is the
    -- contract, and the order they are listed in changes no behaviour. An
    -- ordered comparison would fail a swap that is not a defect.
    it("carries the companion fields on the shipped outline def", function()
        local f = newFixture()
        local def
        for _, d in ipairs(f.AU.CVAR_DEFS) do
            if d.key == "findYourselfModeOutline" then def = d end
        end
        assert.is_table(def)
        assert.equals("findYourselfAnywhere", def.companion)
        local seen = {}
        for _, k in ipairs(def.companionKeepAlive or {}) do seen[k] = true end
        assert.is_true(seen.findYourselfModeCircle)
        assert.is_true(seen.findYourselfModeIcon)
        assert.equals(2, #def.companionKeepAlive)
    end)

    -- The primary is in every fixture below because it is in every real client.
    -- ApplyCVars refuses to touch a def whose own CVar is absent, companion
    -- included, so a fixture that omitted it would be testing the absent-CVar
    -- refusal rather than the keep-alive rule.
    -- The guard on the primary does not cover this: the mode flag can be
    -- present while the master it needs is gone, and every path into
    -- ApplyCompanion ends in a SetCVar on that absent name.
    it("writes nothing when the companion itself is absent and the mode is on", function()
        local f = newFixture({ someFlag = "0" })
        f.AU:ApplyCompanion({ key = "someFlag", companion = "someMaster" }, true)
        assert.same({}, f.writesTo("someMaster"))
    end)

    it("writes nothing when the companion itself is absent and the mode is off", function()
        local f = newFixture({ someFlag = "0" })
        f.AU:ApplyCompanion({ key = "someFlag", companion = "someMaster",
            companionKeepAlive = { "sibling" } }, false)
        assert.same({}, f.writesTo("someMaster"))
    end)

    -- The control for both. A build that refuses every companion write passes
    -- the two cases above and fails this one.
    it("still writes a companion that exists", function()
        local f = newFixture({ someFlag = "0", someMaster = "0" })
        f.AU:ApplyCompanion({ key = "someFlag", companion = "someMaster" }, true)
        assert.same({ "1" }, f.writesTo("someMaster"))
    end)

    it("writes the master through the login pass, not only the direct call", function()
        local f = newFixture({ findYourselfModeOutline = "0", findYourselfModeCircle = "0", findYourselfModeIcon = "0" })
        f.AU.db = { CVarsEnabled = true, findYourselfModeOutline = true }
        f.AU:ApplyCVars()
        assert.same({ "1" }, f.writesTo("findYourselfAnywhere"))
    end)

    -- The keep-alive rule, reached the way the addon actually reaches it: the
    -- shipped def, through the login pass. The direct-call cases above all
    -- construct their own def, so none of them would notice the shipped one
    -- losing its keepAlive list.
    --
    -- Both halves are needed. Writing nothing is ALSO what a build with no rule
    -- at all does, so the first assertion alone cannot fail for the right
    -- reason; the second is what proves the pass was a decision.
    it("keeps the master alive through the login pass when a sibling is on", function()
        local kept = newFixture({ findYourselfModeOutline = "0", findYourselfModeCircle = "1", findYourselfAnywhere = "1" })
        kept.AU.db = { CVarsEnabled = true, findYourselfModeOutline = false }
        kept.AU:ApplyCVars()
        assert.same({}, kept.writesTo("findYourselfAnywhere"))

        local dropped = newFixture({ findYourselfModeOutline = "0", findYourselfModeCircle = "0", findYourselfModeIcon = "0", findYourselfAnywhere = "1" })
        dropped.AU.db = { CVarsEnabled = true, findYourselfModeOutline = false }
        dropped.AU:ApplyCVars()
        assert.same({ "0" }, dropped.writesTo("findYourselfAnywhere"))
    end)
end)

local L = require("dev.spec._ke_loader")

-- The gate is this module's refusal rule: off-class, off-role with Healers
-- Only on, or switched off, it must build nothing. The ready gate is the
-- second refusal: no glow while the player's own Power Infusion is down.
describe("PIAssist gate", function()
    local cases = {
        { name = "any Priest when Healers Only is off", class = "PRIEST", role = "DAMAGER", healersOnly = false, wanted = true },
        { name = "a healing Priest when Healers Only is on", class = "PRIEST", role = "HEALER", healersOnly = true, wanted = true },
        { name = "refuses a damage Priest when Healers Only is on", class = "PRIEST", role = "DAMAGER", healersOnly = true, wanted = false },
        { name = "refuses a non-Priest even in a healer role", class = "MONK", role = "HEALER", healersOnly = true, wanted = false },
    }
    for _, c in ipairs(cases) do
        it(c.name, function()
            local PA = L.loadPIAssist()
            assert.equals(c.wanted, PA.WantsSpec(c.class, c.role, c.healersOnly))
        end)
    end

    it("refuses while the module is switched off even on a wanted spec", function()
        local PA, rec = L.loadPIAssist({
            specIndex = 2, role = "HEALER", db = { Enabled = false, HealersOnly = true },
        })
        PA:EvaluateGate()
        assert.equals(0, rec.activate)
        assert.equals(1, rec.deactivate)
        -- The spec check itself passes: this refusal came from the switch.
        assert.is_true(PA:IsWantedSpec())
    end)

    it("activates for an enabled healing Priest", function()
        local PA, rec = L.loadPIAssist({ specIndex = 2, role = "HEALER" })
        PA:EvaluateGate()
        assert.equals(1, rec.activate)
        assert.equals(0, rec.deactivate)
    end)

    it("re-entering Activate registers once and re-resolves every time", function()
        local PA, rec = L.loadPIAssist({ liveActivate = true })
        PA:Activate()
        PA:Activate()
        assert.equals(1, rec.events.GROUP_ROSTER_UPDATE)
        assert.equals(1, rec.events.PLAYER_REGEN_ENABLED)
        assert.equals(1, rec.events.ADDON_RESTRICTION_STATE_CHANGED)
        assert.equals(1, rec.events.UNIT_SPELLCAST_SUCCEEDED)
        assert.equals(2, rec.resolve)
        assert.equals(2, rec.filters)
        assert.equals(2, rec.glow)
    end)
end)

-- The glow follows the name the macro carries: the builder's last written
-- name while it is on, the stored name while it is off.
describe("PIAssist target source", function()
    it("reads the applied name while the builder is on and the stored name while it is off", function()
        local cases = {
            { builder = { enabled = true,  applied = "Bob" }, target = "Alex", name = "Bob" },
            { builder = { enabled = true },                   target = "Alex", name = nil },
            { builder = { enabled = false, applied = "Bob" }, target = "Alex", name = "Alex" },
            { builder = { enabled = false },                  target = "",     name = nil },
        }
        for i, c in ipairs(cases) do
            local PA = L.loadPIAssist({ builder = c.builder, target = c.target })
            assert.equals(c.name, PA:TargetName(), "case " .. i)
        end
    end)
end)

-- Names are secret in restricted content: the keep rule decides whether a
-- scan that could not read every name may keep the last answer.
describe("PIAssist target retention", function()
    it("keeps the last unit only while a name was secret and the stored name is unchanged", function()
        local PA = L.loadPIAssist()
        local cases = {
            { sawSecret = true,  resolvedFor = "Alex-RealmA", stored = "Alex-RealmA", keep = true },
            { sawSecret = true,  resolvedFor = "Alex-RealmA", stored = "Alex-RealmB", keep = false },
            { sawSecret = false, resolvedFor = "Alex-RealmA", stored = "Alex-RealmA", keep = false },
            { sawSecret = true,  resolvedFor = nil,           stored = "Alex-RealmA", keep = false },
        }
        for i, c in ipairs(cases) do
            assert.equals(c.keep, PA.KeepsLastUnit(c.sawSecret, c.resolvedFor, c.stored), "case " .. i)
        end
    end)
end)

-- The setter is the macro half's refusal rule: no write in combat, the name
-- commits only with the write, and the builder being off stores without
-- writing.
describe("PIMacroBuilder SetTarget", function()
    it("refuses, commits, rolls back or stores by combat, write result and enabled state", function()
        local cases = {
            { name = "combat",      combat = true,  enabled = true,  writeOk = true,  target = "", set = "Alex", result = false, stored = "",     applied = 0 },
            { name = "write ok",    combat = false, enabled = true,  writeOk = true,  target = "", set = "Alex", result = true,  stored = "Alex", applied = 1 },
            { name = "write fails", combat = false, enabled = true,  writeOk = false, target = "Bob", set = "Alex", result = false, stored = "Bob", applied = 1 },
            { name = "disabled",    combat = false, enabled = false, writeOk = true,  target = "", set = "Alex", result = true,  stored = "Alex", applied = 0 },
            { name = "unchanged",   combat = false, enabled = true,  writeOk = true,  target = "Alex", set = "Alex", result = true, stored = "Alex", applied = 0 },
            { name = "clear",       combat = false, enabled = true,  writeOk = true,  target = "Alex", set = nil, result = true, stored = "", applied = 1 },
        }
        for _, c in ipairs(cases) do
            local PI, rec = L.loadPIMacroBuilder(c)
            assert.equals(c.result, PI:SetTarget(c.set), c.name)
            assert.equals(c.stored, PI.db.Target, c.name)
            assert.equals(c.applied, rec.applied, c.name)
        end
    end)

    -- The assist hears about the name the macro carries, not about writes.
    it("tells the assist only when the name the macro carries changes", function()
        local PI, rec = L.loadPIMacroBuilder({ realApply = true, target = "Alex" })
        assert.is_true(PI:ApplyMacro())
        assert.is_true(PI:ApplyMacro())
        assert.equals(1, rec.notified)
        assert.equals("Alex", PI.appliedTarget)
        PI.db.Target = "Bob"
        rec.combat = true
        assert.is_false(PI:ApplyMacro())
        assert.equals(1, rec.notified)
        assert.equals("Alex", PI.appliedTarget)
        rec.combat = false
        assert.is_true(PI:ApplyMacro())
        assert.equals(2, rec.notified)
        assert.equals("Bob", PI.appliedTarget)
    end)

    -- Restoring the name the macro already carries changes the stored name
    -- without changing the applied one; the page still has to hear it.
    it("announces a restored name once even though the write changed nothing", function()
        local PI, rec = L.loadPIMacroBuilder({ realApply = true, target = "Bob" })
        assert.is_true(PI:ApplyMacro())
        assert.equals(1, rec.notified)
        PI.db.Target = "Alex"
        assert.is_true(PI:SetTarget("Bob"))
        assert.equals("Bob", PI.appliedTarget)
        assert.equals(2, rec.notified)
        assert.is_true(PI:SetTarget("Carl"))
        assert.equals("Carl", PI.appliedTarget)
        assert.equals(3, rec.notified)
    end)
end)

describe("PIAssist ready gate", function()
    it("opens or closes on the deadline only when the option is on", function()
        local PA = L.loadPIAssist()
        local cases = {
            { only = false, backAt = 100, now = 0,   open = true },
            { only = true,  backAt = nil, now = 0,   open = true },
            { only = true,  backAt = 100, now = 50,  open = false },
            { only = true,  backAt = 100, now = 100, open = true },
        }
        for i, c in ipairs(cases) do
            assert.equals(c.open, PA.ReadyGateOpen(c.only, c.backAt, c.now), "case " .. i)
        end
    end)

    it("turns the base cooldown into a delay, clamped, with a fallback", function()
        local PA = L.loadPIAssist()
        local cases = {
            { ms = 120000, grace = 0,   delay = 120 },
            { ms = 90000,  grace = 15,  delay = 75 },
            { ms = 2000,   grace = 0,   delay = 2 },
            { ms = nil,    grace = 0,   delay = 120 },
            { ms = 1500,   grace = 0,   delay = 120 },
            { ms = 120000, grace = 200, delay = 0 },
        }
        for i, c in ipairs(cases) do
            assert.equals(c.delay, PA.ReadyDelay(c.ms, c.grace), "case " .. i)
        end
    end)
end)

-- Tier 2: the Damage Meter's guards around KE.CombatState (Core/CombatState.lua),
-- per the shared combat-state design's damagemeter_clock_spec budget. Drives
-- DM:BindCombatState, DM:OnCombatForceStop, DM:OnMeterReset/HeaderReset, and
-- DM:UpdateCombatClock directly against the fake KE.CombatState _ke_loader
-- installs (dev/spec/_ke_loader.lua's newFakeCombatState) -- never the real
-- machine, which is combatstate_spec.lua's job.
local L = require("dev.spec._ke_loader")

-- OnMeterReset/HeaderReset both end in a guarded DM:Tick() call, and Tick's
-- per-frame budget reads this. loadDMCore does not set it (only loadDMHistory
-- does); the reset-path cases below reach Tick without History.lua loaded.
_G.debugprofilestop = _G.debugprofilestop or function() return 0 end

-- A trackable stand-in for the clock FontString: records what UpdateCombatClock
-- would have painted, without a stateful frame fake.
local function fakeClock()
    local c = {}
    function c:Show() self.shown = true end
    function c:Hide() self.shown = false end
    function c:SetText(t) self.text = t end
    function c:SetTextColor(r, g, b) self.color = { r, g, b } end
    return c
end

describe("BindCombatState's mid-fight seed", function()
    it("clears _clockCleared, clears feign tags, and starts the ticker", function()
        local DM, KE = L.loadDMCore()
        DM._clockCleared = true
        DM._feignTags = { [123] = true }
        KE.CombatState.live = true

        DM:BindCombatState()

        assert.is_falsy(DM._clockCleared)
        assert.is_nil(next(DM._feignTags))
        assert.is_not_nil(DM._ticker)
    end)
end)

describe("OnCombatForceStop", function()
    it("raises _clockCleared and stops only when the machine is not live", function()
        local DM, KE = L.loadDMCore()
        local stopCalls = 0
        DM.StopTicker = function() stopCalls = stopCalls + 1 end

        KE.CombatState.live = true
        DM:OnCombatForceStop()
        assert.is_falsy(DM._clockCleared)
        assert.equals(0, stopCalls)

        KE.CombatState.live = false
        DM:OnCombatForceStop()
        assert.is_true(DM._clockCleared)
        assert.equals(1, stopCalls)
    end)
end)

describe("the deferred stop after an ENCOUNTER_END kill", function()
    local DM, KE, onStop, capturedAfter, stopCalls

    local function setup()
        capturedAfter = nil
        DM, KE = L.loadDMCore({
            C_Timer = {
                After = function(_, fn) capturedAfter = fn end,
                NewTimer = function() return { Cancel = function() end } end,
                NewTicker = function() return { Cancel = function() end } end,
            },
        })
        stopCalls = 0
        DM.StopTicker = function() stopCalls = stopCalls + 1 end
        -- OnEnable raises this; the deferred stop refuses to run without it.
        DM.enabled = true
        KE.CombatState.live = false
        DM:BindCombatState()
        onStop = KE.CombatState.listeners["DamageMeter"].OnStop
    end

    it("refuses when the generation has moved or the machine is live again", function()
        local cases = {
            { name = "generation moved", mutate = function() KE.CombatState.generation = 2 end },
            { name = "machine live again", mutate = function() KE.CombatState.live = true end },
        }
        for _, case in ipairs(cases) do
            setup()
            KE.CombatState.generation = 1
            onStop("encounterEnd")
            case.mutate()
            capturedAfter()
            assert.equals(0, stopCalls, case.name)
        end
    end)

    it("stops when the guards are still satisfied", function()
        setup()
        KE.CombatState.generation = 1
        onStop("encounterEnd")
        capturedAfter()
        assert.equals(1, stopCalls)
    end)

    it("stops at once for every other reason, scheduling nothing", function()
        -- encounterEndDelayed already spent its delay inside the machine.
        -- Deferring it again would add a second half-second to the totals.
        for _, reason in ipairs({ "encounterEndDelayed", "combat", "pvp", "wedgeGuard", "reset" }) do
            setup()
            onStop(reason)
            assert.equals(1, stopCalls, reason)
            assert.is_nil(capturedAfter, reason)
        end
    end)
end)

describe("the OnClockTick listener", function()
    it("repaints the clock only, never the bars", function()
        local DM, KE = L.loadDMCore()
        local tickCalls, repaintCalls = 0, 0
        DM.Tick = function() tickCalls = tickCalls + 1 end
        DM.RepaintCombatClock = function() repaintCalls = repaintCalls + 1 end

        DM:BindCombatState()
        KE.CombatState.listeners["DamageMeter"].OnClockTick(12, 0)

        assert.equals(1, repaintCalls)
        assert.equals(0, tickCalls)
    end)
end)

describe("UpdateCombatClock's branch selection", function()
    it("takes the shared branch whenever live or frozen, and the raw fallback only when neither", function()
        local DM, KE = L.loadDMClock()
        local clock = fakeClock()
        local W = { idx = 1, clock = clock }
        DM.windows_rt = { [1] = W }
        -- Only the raw fallback below reads ResolveWindowConfig; overridden here
        -- rather than built up through a full db.Windows table.
        DM.ResolveWindowConfig = function() return { SessionType = 1 } end

        KE.CombatState.live = true
        KE.CombatState.duration = 42
        DM:UpdateCombatClock(W, nil)
        assert.equals("[0:42]", clock.text)

        KE.CombatState.live = false
        KE.CombatState.frozen = true
        KE.CombatState.duration = 7
        DM:UpdateCombatClock(W, nil)
        assert.equals("[0:07]", clock.text)

        KE.CombatState.frozen = false
        _G.C_DamageMeter = { GetSessionDurationSeconds = function() return 99 end }
        DM:UpdateCombatClock(W, nil)
        assert.equals("[1:39]", clock.text)
    end)
end)

describe("the warm-up hold", function()
    it("survives an ordinary bar repaint but yields to the service's own paint", function()
        -- HideClock hides the FontString rather than blanking its text, and
        -- whether it is on screen also depends on the visibility gate, so the
        -- cached pair is what discriminates the two paths.
        local cases = {
            { name = "bar repaint holds", authoritative = nil, hasText = true, cached = "[0:42]" },
            { name = "service paint blanks", authoritative = true, hasText = false, cached = nil },
        }
        for _, case in ipairs(cases) do
            local DM, KE = L.loadDMClock()
            local clock = fakeClock()
            local W = { idx = 1, clock = clock }
            DM.windows_rt = { [1] = W }

            -- A fight in progress with its previous reading still on screen, and
            -- the pin not yet warm after a chain pull.
            KE.CombatState.live = true
            KE.CombatState.duration = 42
            DM:UpdateCombatClock(W, nil)
            KE.CombatState.duration = nil

            DM:UpdateCombatClock(W, nil, case.authoritative)
            assert.equals(case.hasText, W._clockHasText or false, case.name)
            assert.equals(case.cached, W._clockText, case.name)
        end
    end)
end)

describe("the two reset paths", function()
    it("raise _clockCleared only when the machine is not live", function()
        local cases = {
            { name = "OnMeterReset", fn = function(dm) dm:OnMeterReset() end },
            { name = "HeaderReset", fn = function(dm) dm:HeaderReset() end },
        }
        for _, case in ipairs(cases) do
            local DM, KE = L.loadDMCore()
            -- Tick's render path (VisibleWindows -> Dock.lua's DockWindowIndices)
            -- isn't loaded here; both reset paths guard their Tick call, so a
            -- no-op stub keeps the case scoped to _clockCleared.
            DM.Tick = function() end

            KE.CombatState.live = true
            case.fn(DM)
            assert.is_falsy(DM._clockCleared, case.name .. " (live)")

            KE.CombatState.live = false
            case.fn(DM)
            assert.is_true(DM._clockCleared, case.name .. " (not live)")
        end
    end)
end)

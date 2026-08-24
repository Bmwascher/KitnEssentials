-- Tier 1: World Map Scale refusal rules only (tiered test policy). The ported
-- feature body -- the scale accessors, the blackout texture capture and
-- restore, the EventRegistry binding -- is covered by the structural diff
-- against the reference and by the in-game smoke, not here.
--
-- Three refusals, and they are the whole reason this module was rewritten:
--   1. Nothing scales a map that is on screen, a map in combat, or a map whose
--      module has been switched off.
--   2. A deferral arms exactly one PLAYER_REGEN_ENABLED handler, however many
--      times it is asked, and a teardown never takes it down with it.
--   3. The regen handler applies what is pending, once, and disarms.
--
-- The deferral rides a plain frame rather than AceEvent, and the disable block
-- is what holds that in place: AceAddon calls OnEmbedDisable straight after
-- OnDisable returns, and AceEvent answers it by unregistering everything, so an
-- AceEvent registration made during a disable cannot survive.
--
-- Every case that lets a deferral run does it through the frame's own OnEvent
-- script, never by calling OnRegen_Apply directly. A frame that is armed but
-- bound to nothing is armed for nothing, and a test that calls the method by
-- hand cannot tell the difference.
--
-- The two positive cases -- a hidden map DOES scale, an out-of-combat blackout
-- DOES release the mouse -- are controls, not feature coverage. Without them
-- every refusal assertion above would also pass on a module that simply never
-- acts.

local helpers = require("dev.spec._helpers")

-- One fixture per test. WorldMapFrame, BlackoutFrame and the module's own
-- AceEvent surface are all recorded, so a refusal is observable as an absence
-- in the ledger rather than inferred from an internal flag alone.
local function newFixture(opts)
    opts = opts or {}
    local calls = {}
    local events = {}
    local registry = {}

    local function record(what, ...)
        calls[#calls + 1] = { what = what, n = select("#", ...), ... }
    end

    local blackoutTex = {
        GetTexture = function() return opts.blackoutTexture or "Interface\\Blackout" end,
        SetTexture = function(_, v) record("Blackout:SetTexture", v) end,
    }
    local blackout = {
        Blackout = blackoutTex,
        EnableMouse = function(_, v) record("Blackout:EnableMouse", v) end,
    }

    -- The module creates its regen watcher at file scope, so the stub has to
    -- exist before the chunk runs. Registration is modelled as LIVE state: the
    -- failure this catches is a teardown removing a handler that was armed
    -- moments earlier, and a call log cannot see that -- both calls happened.
    local watcherEvents = {}
    local watcherArms = 0
    local watcherScripts = {}
    local watcherFrame
    watcherFrame = {
        RegisterEvent = function(_, e) watcherArms = watcherArms + 1; watcherEvents[e] = true end,
        UnregisterEvent = function(_, e) watcherEvents[e] = nil end,
        SetScript = function(_, k, fn) watcherScripts[k] = fn end,
        Hide = function() end,
    }
    _G.CreateFrame = function() return watcherFrame end

    local shown = opts.mapShown or false
    local map = {
        BlackoutFrame = blackout,
        IsShown = function() return shown end,
        IsMaximized = function() return opts.maximized or false end,
        GetScale = function() return opts.currentScale or 1 end,
        SetScale = function(_, v) record("map:SetScale", v) end,
        SetClampedToScreen = function(_, v) record("map:SetClampedToScreen", v) end,
        HookScript = function(_, script, fn) record("map:HookScript", script); registry[script] = fn end,
    }

    _G.WorldMapFrame = map
    _G.EventRegistry = {
        RegisterCallback = function(_, event, _, _, arg) record("EventRegistry:Register", event, arg) end,
        UnregisterCallback = function(_, event) record("EventRegistry:Unregister", event) end,
    }
    local combat = opts.combat or false
    _G.InCombatLockdown = function() return combat end
    _G.C_Timer = { After = function(_, fn) record("C_Timer.After"); fn() end }

    local modules = helpers.installAddonShim()
    local KE = { db = { profile = { MapScale = opts.db or { Enabled = true, Scale = 1.4, MaximizedScale = 1 } } } }
    helpers.loadModule("Modules/QoL/MapScale.lua", KE)
    local MS = modules["MapScale"]

    -- AceEvent is not mixed in by the bare shim. These cover the module's own
    -- AceEvent surface, which after the redesign is ADDON_LOADED and nothing
    -- else. UnregisterAllEvents clears them, exactly as Ace does on disable --
    -- and must leave the plain-frame watcher alone.
    MS.RegisterEvent = function(_, event, handler)
        events[#events + 1] = { event = event, handler = handler }
    end
    MS.UnregisterEvent = function(_, event)
        record("MS:UnregisterEvent", event)
        for i = #events, 1, -1 do
            if events[i].event == event then table.remove(events, i) end
        end
    end
    MS.UnregisterAllEvents = function()
        record("MS:UnregisterAllEvents")
        for i = #events, 1, -1 do table.remove(events, i) end
    end
    MS.IsEnabled = function() return opts.enabled ~= false end
    MS.SetEnabledState = function() end
    MS:UpdateDB()

    local function count(what)
        local n = 0
        for i = 1, #calls do if calls[i].what == what then n = n + 1 end end
        return n
    end

    -- Cumulative: how many times the watcher was armed, ever.
    local function regenRegistrations()
        return watcherArms
    end

    -- Live: whether the watcher is armed RIGHT NOW. In game only this one
    -- decides whether PLAYER_REGEN_ENABLED reaches the module.
    local function regenArmed()
        return watcherEvents["PLAYER_REGEN_ENABLED"] and 1 or 0
    end

    -- Deliver the event the way the client does: through the frame's own
    -- OnEvent script. Calling MS:OnRegen_Apply() directly would pass on a
    -- watcher that was never bound to anything, which is the one failure this
    -- whole mechanism has.
    local function fireRegen()
        if not watcherEvents["PLAYER_REGEN_ENABLED"] then
            error("the watcher is not armed, so PLAYER_REGEN_ENABLED could not reach it", 2)
        end
        if not watcherScripts.OnEvent then
            error("the watcher has no OnEvent script, so nothing receives the event", 2)
        end
        watcherScripts.OnEvent(watcherFrame, "PLAYER_REGEN_ENABLED")
    end

    return {
        MS = MS, map = map, calls = calls, events = events, registry = registry,
        count = count, regenRegistrations = regenRegistrations, regenArmed = regenArmed,
        fireRegen = fireRegen,
        setShown = function(v) shown = v end,
        disable = function() MS.IsEnabled = function() return false end end,
        enable = function() MS.IsEnabled = function() return true end end,
        -- PLAYER_REGEN_ENABLED fires when combat ENDS, so a test that drives
        -- OnRegen_Apply leaves combat first. Holding combat across it tests a
        -- state the client never produces -- which is exactly what the one
        -- case asserting the re-defer refusal deliberately does, and the only
        -- reason that case is allowed to skip this.
        endCombat = function() combat = false end,
    }
end

local DIMMED = { Enabled = true, Scale = 1.4, MaximizedScale = 0.8 }

describe("MapScale refusals", function()
    describe("scaling a live or in-combat map", function()
        it("does not scale a map that is on screen", function()
            local f = newFixture({ mapShown = true })
            f.MS:ApplyScale()
            assert.equals(0, f.count("map:SetScale"))
        end)

        it("marks a change made while the map is open as pending", function()
            local f = newFixture({ mapShown = true })
            f.MS:ApplyScale()
            assert.is_true(f.MS._scaleDirty)
        end)

        it("does not arm the regen handler for a merely-shown map", function()
            local f = newFixture({ mapShown = true })
            f.MS:ApplyScale()
            assert.equals(0, f.regenRegistrations())
        end)

        it("does not scale in combat", function()
            local f = newFixture({ combat = true })
            f.MS:ApplyScale()
            assert.equals(0, f.count("map:SetScale"))
        end)

        it("arms the regen handler in combat", function()
            local f = newFixture({ combat = true })
            f.MS:ApplyScale()
            assert.equals(1, f.regenArmed())
        end)

        it("scales a hidden out-of-combat map", function()
            local f = newFixture({})
            f.MS:ApplyScale()
            assert.equals(1, f.count("map:SetScale"))
        end)

        it("does not scale for a module that is switched off", function()
            local f = newFixture({ enabled = false })
            f.MS:ApplyScale()
            assert.equals(0, f.count("map:SetScale"))
        end)
    end)

    describe("the blackout mouse layer", function()
        it("does not release the mouse in combat", function()
            local f = newFixture({ combat = true, db = DIMMED })
            f.MS:ApplyBlackout()
            assert.equals(0, f.count("Blackout:EnableMouse"))
        end)

        it("arms the regen handler in combat", function()
            local f = newFixture({ combat = true, db = DIMMED })
            f.MS:ApplyBlackout()
            assert.equals(1, f.regenArmed())
        end)

        it("releases the mouse out of combat below full scale", function()
            local f = newFixture({ db = DIMMED })
            f.MS:ApplyBlackout()
            assert.equals(1, f.count("Blackout:EnableMouse"))
            assert.is_false(f.calls[#f.calls][1])
        end)
    end)

    describe("the single regen handler", function()
        it("registers once when both a scale and a blackout change defer", function()
            local f = newFixture({ combat = true, db = DIMMED })
            f.MS:ApplyScale()
            f.MS:ApplyBlackout()
            assert.equals(1, f.regenRegistrations())
        end)

        it("registers once when the same change defers twice", function()
            local f = newFixture({ combat = true })
            f.MS:ApplyScale()
            f.MS:ApplyScale()
            assert.equals(1, f.regenRegistrations())
        end)

        it("arms the plain watcher, not the module's AceEvent surface", function()
            local f = newFixture({ combat = true })
            f.MS:ApplyScale()
            assert.equals(1, f.regenArmed())
            assert.equals(0, #f.events)
        end)
    end)

    describe("the regen handler itself", function()
        it("disarms the watcher", function()
            local f = newFixture({ combat = true })
            f.MS:ApplyScale()
            f.endCombat()
            f.fireRegen()
            assert.equals(0, f.regenArmed())
        end)

        it("clears the pending latch so a later deferral can arm again", function()
            local f = newFixture({ combat = true })
            f.MS:ApplyScale()
            f.endCombat()
            f.fireRegen()
            assert.is_nil(f.MS._regenPending)
        end)

        it("applies the scale change that was waiting", function()
            local f = newFixture({ combat = true })
            f.MS:ApplyScale()
            assert.equals(0, f.count("map:SetScale"))
            f.endCombat()
            f.fireRegen()
            assert.equals(1, f.count("map:SetScale"))
        end)

        -- Direct call on purpose: this one asserts what happens with no dirty
        -- flags set, and there is nothing to arm the watcher with.
        it("applies nothing when nothing was pending", function()
            local f = newFixture({})
            f.MS._regenPending = true
            f.MS:OnRegen_Apply()
            assert.equals(0, f.count("map:SetScale"))
        end)

        -- Combat should be over by the time this event fires. If it somehow is
        -- not, re-deferring is the only safe answer -- never a write.
        it("re-defers rather than writing if combat somehow persists", function()
            local f = newFixture({ combat = true })
            f.MS:ApplyScale()
            f.fireRegen()
            assert.equals(0, f.count("map:SetScale"))
            assert.is_true(f.MS._regenPending)
        end)
    end)

    -- A disable that has to defer its restore must leave a watcher Ace cannot
    -- tear down, and must never let the deferred work write a scale for a
    -- module that is now off.
    describe("disabling while a restore has to defer", function()
        it("leaves the watcher armed", function()
            local f = newFixture({ combat = true, db = DIMMED })
            f.disable()
            f.MS:OnDisable()
            assert.equals(1, f.regenArmed())
        end)

        it("survives the AceEvent teardown Ace runs straight afterwards", function()
            local f = newFixture({ combat = true, db = DIMMED })
            f.disable()
            f.MS:OnDisable()
            f.MS:UnregisterAllEvents() -- what AceEvent:OnEmbedDisable does next
            assert.equals(1, f.regenArmed())
        end)

        it("does not write a scale once the deferral runs", function()
            local f = newFixture({ combat = true, db = DIMMED })
            f.MS:ApplyScale()
            f.disable()
            f.MS:OnDisable()
            f.endCombat()
            f.fireRegen()
            assert.equals(0, f.count("map:SetScale"))
        end)

        it("still restores the blackout once the deferral runs", function()
            local f = newFixture({ combat = true, db = DIMMED })
            f.disable()
            f.MS:OnDisable()
            f.endCombat()
            f.fireRegen()
            assert.equals(1, f.count("Blackout:EnableMouse"))
            assert.is_true(f.calls[#f.calls][1])
        end)
    end)

    -- Putting Blizzard's scale back is a write like any other, so it obeys the
    -- same two refusals. The teardown, the OnHide hook and the regen handler
    -- all reach it through one function precisely so they cannot disagree.
    describe("restoring the scale on disable", function()
        it("restores immediately when the map is hidden and combat is over", function()
            local f = newFixture({ currentScale = 1.4 })
            f.disable()
            f.MS:OnDisable()
            assert.equals(1, f.count("map:SetScale"))
            assert.equals(1, f.calls[#f.calls][1])
        end)

        it("does not restore while the map is on screen", function()
            local f = newFixture({ mapShown = true, currentScale = 1.4 })
            f.disable()
            f.MS:OnDisable()
            assert.equals(0, f.count("map:SetScale"))
            assert.is_true(f.MS._restorePending)
        end)

        it("does not restore in combat, and arms the watcher instead", function()
            local f = newFixture({ combat = true, currentScale = 1.4 })
            f.disable()
            f.MS:OnDisable()
            assert.equals(0, f.count("map:SetScale"))
            assert.equals(1, f.regenArmed())
        end)

        it("restores once combat ends, without waiting for the map to open", function()
            local f = newFixture({ combat = true, currentScale = 1.4 })
            f.disable()
            f.MS:OnDisable()
            f.endCombat()
            f.fireRegen()
            assert.equals(1, f.count("map:SetScale"))
            assert.equals(1, f.calls[#f.calls][1])
        end)

        -- The OnHide hook fires whenever the map closes, combat or not. It must
        -- not become a way to write a scale during combat.
        it("does not restore from the OnHide hook while combat is still on", function()
            local f = newFixture({ mapShown = true, combat = true, currentScale = 1.4 })
            f.disable()
            f.MS:OnDisable()
            f.setShown(false)
            f.registry.OnHide()
            assert.equals(0, f.count("map:SetScale"))
        end)

        it("restores from the OnHide hook out of combat", function()
            local f = newFixture({ mapShown = true, currentScale = 1.4 })
            f.disable()
            f.MS:OnDisable()
            f.setShown(false)
            f.registry.OnHide()
            assert.equals(1, f.count("map:SetScale"))
            assert.equals(1, f.calls[#f.calls][1])
        end)

        it("writes nothing when the scale is already Blizzard's", function()
            local f = newFixture({ currentScale = 1 })
            f.disable()
            f.MS:OnDisable()
            assert.equals(0, f.count("map:SetScale"))
        end)

        -- The state that needs the enabled check at all: a restore deferred
        -- while the module was off, with the module switched back on before the
        -- deferral runs. Without the check anywhere, or with it below the write,
        -- this puts Blizzard's scale over the scale the live module just asked
        -- for. Where in the refusal order it sits is the next case's job.
        it("cancels a pending restore when the module is enabled again", function()
            local f = newFixture({ combat = true, currentScale = 1.4 })
            f.disable()
            f.MS:OnDisable()
            assert.is_true(f.MS._restorePending)
            f.enable()
            f.endCombat()
            f.fireRegen()
            assert.equals(0, f.count("map:SetScale"))
            assert.is_nil(f.MS._restorePending)
        end)

        -- And it comes before the combat check, not just before the write. A
        -- module re-enabled mid-combat with a restore still pending must drop
        -- that restore outright; checking combat first would instead arm the
        -- watcher for work that is no longer wanted.
        it("cancels a pending restore in combat without arming the watcher", function()
            local f = newFixture({ combat = true, currentScale = 1.4 })
            f.MS._restorePending = true
            f.MS:RestoreScale()
            assert.equals(0, f.count("map:SetScale"))
            assert.is_nil(f.MS._restorePending)
            assert.equals(0, f.regenArmed())
        end)
    end)
end)

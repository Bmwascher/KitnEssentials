local L = require("dev.spec._ke_loader")

-- A predicate whose answer the case controls, so every transition is
-- deliberate rather than incidental.
local function gateWith(hidden, soundPending)
    local state = { hidden = hidden, sound = soundPending }
    local G = L.loadAuraRestriction()
    local gate = G.New({
        isHidden       = function() return state.hidden end,
        soundIsPending = soundPending ~= nil
            and function() return state.sound end
            or nil,
    })
    return gate, state
end

describe("restriction gate", function()
    it("permits work when nothing is restricted", function()
        local gate = gateWith(false)
        assert.is_true(gate:Request("general"))
        assert.is_false(gate:IsPending("general"))
    end)

    it("refuses and records the debt when restricted", function()
        local gate = gateWith(true)
        assert.is_false(gate:Request("general"))
        assert.is_true(gate:IsPending("general"))
    end)

    -- A settings change between the restriction lifting and the drain firing
    -- does the owed work immediately. If the flag survived that, the drain
    -- would do it a second time.
    it("discharges an older debt when a later request succeeds", function()
        local gate, state = gateWith(true)
        gate:Request("general")
        state.hidden = false

        assert.is_true(gate:Request("general"))
        assert.is_false(gate:IsPending("general"))

        local runs = 0
        gate:Drain({ general = function() runs = runs + 1 end })
        assert.equals(0, runs)
    end)

    it("reports the sound debt from the registry, not from a flag of its own", function()
        local gate, state = gateWith(true, true)
        assert.is_true(gate:IsPending("sound"))
        assert.is_false(gate:IsPending("general"))

        -- The registry retires and clears; the gate must follow without
        -- anyone telling it.
        state.sound = false
        assert.is_false(gate:IsPending("sound"))
    end)

    it("reports no sound debt for a display that declares no sounds", function()
        local gate = gateWith(true)
        assert.is_false(gate:IsPending("sound"))
    end)
end)

describe("restriction drain", function()
    it("runs owed general work exactly once and clears the flag", function()
        local gate, state = gateWith(true)
        gate:Request("general")
        state.hidden = false

        local runs = 0
        gate:Drain({ general = function() runs = runs + 1 end })
        gate:Drain({ general = function() runs = runs + 1 end })

        assert.equals(1, runs)
        assert.is_false(gate:IsPending("general"))
    end)

    it("runs nothing when nothing was owed", function()
        local gate = gateWith(false)
        local runs = 0
        gate:Drain({ general = function() runs = runs + 1 end })
        assert.equals(0, runs)
    end)

    it("runs both handlers when both are owed and they differ", function()
        local gate, state = gateWith(true, true)
        gate:Request("general")
        state.hidden = false

        local seen = {}
        gate:Drain({
            general = function() seen[#seen + 1] = "general" end,
            sound   = function() seen[#seen + 1] = "sound" end,
        })
        assert.equals(2, #seen)
    end)

    -- The engine passes ONE closure for both kinds, because reapplying
    -- settings synchronises the sound on its way past. The design requires
    -- exactly one synchronisation when both debts drain together, and this
    -- collapse is what delivers it.
    it("runs a handler shared by both kinds exactly once", function()
        local gate, state = gateWith(true, true)
        gate:Request("general")
        state.hidden = false

        local runs = 0
        local reapply = function() runs = runs + 1 end
        gate:Drain({ general = reapply, sound = reapply })
        assert.equals(1, runs)
    end)

    it("runs the sound handler on a sound debt alone", function()
        local gate, state = gateWith(true, true)
        state.hidden = false

        local runs = 0
        gate:Drain({ sound = function() runs = runs + 1 end })
        assert.equals(1, runs)
    end)

    it("does not drain while still restricted", function()
        local gate = gateWith(true)
        gate:Request("general")
        local runs = 0
        gate:Drain({ general = function() runs = runs + 1 end })
        assert.equals(0, runs)
        assert.is_true(gate:IsPending("general"))
    end)
end)

describe("cancel", function()
    -- Disable clears the general debt so a later restriction release cannot
    -- resurrect work for a module that is switched off. The SOUND half of a
    -- disable is a retirement, not a flag clear: disable retires every id,
    -- which is what makes the registry stop reporting a debt. Cancel cannot
    -- and must not reach into it.
    it("clears the general debt so a later drain does nothing", function()
        local gate, state = gateWith(true, false)
        gate:Request("general")
        gate:Cancel()
        state.hidden = false

        local runs = 0
        gate:Drain({
            general = function() runs = runs + 1 end,
            sound   = function() runs = runs + 1 end,
        })
        assert.equals(0, runs)
    end)

    it("leaves a sound debt the registry still reports", function()
        local gate, state = gateWith(true, true)
        gate:Cancel()
        assert.is_true(gate:IsPending("sound"))

        -- Retirement is what settles it, and disable performs that
        -- separately.
        state.sound = false
        assert.is_false(gate:IsPending("sound"))
    end)

    it("leaves the gate usable afterwards", function()
        local gate, state = gateWith(true)
        gate:Request("general")
        gate:Cancel()
        state.hidden = false
        assert.is_true(gate:Request("general"))
    end)
end)

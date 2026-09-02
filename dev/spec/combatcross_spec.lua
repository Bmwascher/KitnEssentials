local loader = require("dev.spec._ke_loader")

-- The module's show/hide runs through the frame, so every test here creates
-- one and records what happened to it. A bare table would swallow the calls
-- and make each assertion vacuous.
local function withFrame(CC)
    local shown = false
    CC:CreateFrame()
    CC.frame.Show = function() shown = true end
    CC.frame.Hide = function() shown = false end
    CC.frame.IsShown = function() return shown end
    CC.frame.SetAlpha = function(_, a) CC.frame._alpha = a end
    CC.text = CC.text or {}
    CC.text.SetTextColor = function() end
    return function() return shown end
end

describe("CombatCross visibility", function()
    it("stays hidden out of combat by default", function()
        local CC = loader.loadCombatCross()
        local isShown = withFrame(CC)
        -- Shown FIRST. withFrame starts hidden, so asserting hidden after a
        -- no-op would pass against an UpdateVisibility that does nothing at
        -- all. Starting visible means only an actual Hide can satisfy this.
        CC.frame:Show()
        assert.is_true(isShown())
        CC:UpdateVisibility()
        assert.is_false(isShown())
    end)

    it("shows in combat", function()
        local CC = loader.loadCombatCross()
        local isShown = withFrame(CC)
        CC:UpdateVisibility(true)
        assert.is_true(isShown())
    end)

    it("hides on leaving combat under the in_combat mode", function()
        local CC = loader.loadCombatCross()
        local isShown = withFrame(CC)
        CC:UpdateVisibility(true)
        assert.is_true(isShown())
        CC:UpdateVisibility(false)
        assert.is_false(isShown())
    end)

    it("asks the client when told nothing, and comes up in combat", function()
        -- The reload-in-combat case: no PLAYER_REGEN_DISABLED will arrive for
        -- a fight already in progress, so the only source of truth is the
        -- client. Anything that trusted event history alone stays hidden here.
        local CC = loader.loadCombatCross({
            UnitAffectingCombat = function() return true end,
        })
        local isShown = withFrame(CC)
        CC:UpdateVisibility()
        assert.is_true(isShown())
    end)

    it("does not use InCombatLockdown as its combat test", function()
        -- InCombatLockdown answers "are secure frames locked", which is not the
        -- same question.
        --
        -- The polarity is deliberate: NOT in combat, with InCombatLockdown
        -- answering true. Seeding both true would let `UnitAffectingCombat() or
        -- InCombatLockdown()` short-circuit before ever touching the second
        -- call, and the test would pass against exactly the implementation it
        -- exists to reject. This way a cross that consults it shows when it
        -- should be hidden, AND the call counter catches it.
        local lockdownCalls = 0
        local CC = loader.loadCombatCross({
            UnitAffectingCombat = function() return false end,
            InCombatLockdown = function()
                lockdownCalls = lockdownCalls + 1
                return true
            end,
        })
        local isShown = withFrame(CC)
        CC:UpdateVisibility()
        assert.is_false(isShown())
        assert.equals(0, lockdownCalls)
    end)

    it("evaluates the range loop after the ability resolves on enable", function()
        -- Asserts OBSERVABLE END STATE, not a spy. A spy on UpdateVisibility
        -- would be satisfied by the call ApplySettings already makes, and
        -- ApplySettings runs BEFORE ResolveRangeAbility inside OnEnable -- so
        -- a decision taken only there evaluates the loop with no range ability
        -- and never revisits it. Only the closing call in OnEnable can leave
        -- onUpdateActive true here.
        local CC = loader.loadCombatCross({
            UnitAffectingCombat = function() return true end,
            GetSpecializationInfo = function() return 73 end,
            C_Spell = { IsSpellInRange = function() return 1 end },
        })
        CC.db.RangeColorMeleeEnabled = true
        CC.RegisterEvent = function() end
        CC.RegWithEditMode = function() end
        CC:OnEnable()
        assert.is_true(CC.gameplayActive)
        assert.is_true(CC.onUpdateActive)
    end)

    it("starts the range loop when an always-on mode puts the cross up", function()
        -- A mode that shows out of combat must not leave a visible cross with
        -- range colouring configured and no loop running. gameplayActive is
        -- what gates the loop, and only UpdateVisibility sets it.
        local CC = loader.loadCombatCross({
            GetSpecializationInfo = function() return 73 end,
            C_Spell = { IsSpellInRange = function() return 1 end },
        })
        CC.db.RangeColorMeleeEnabled = true
        CC:ResolveRangeAbility()
        withFrame(CC)
        CC:UpdateVisibility(false)
        assert.is_false(CC.onUpdateActive)

        CC.db.Visibility = "always"
        CC:UpdateVisibility(false)
        assert.is_true(CC.onUpdateActive)
    end)
end)

describe("CombatCross hide when in range", function()
    -- Protection Warrior (73) is in the melee table, so ResolveRangeAbility
    -- gives the module something to range-check. gameplayActive must be true
    -- or every alpha write is correctly suppressed.
    local function faded(overrides)
        local CC = loader.loadCombatCross(overrides)
        CC.db.HideWhenInRange = true
        CC:ResolveRangeAbility()
        withFrame(CC)
        CC.gameplayActive = true
        return CC
    end

    it("fades out while the target is in range", function()
        local CC = faded({ C_Spell = { IsSpellInRange = function() return 1 end } })
        CC:UpdateRangeColor()
        assert.equals(0, CC.frame._alpha)
    end)

    it("fades back in while the target is out of range", function()
        local CC = faded({ C_Spell = { IsSpellInRange = function() return 0 end } })
        CC:UpdateRangeColor()
        assert.equals(1, CC.frame._alpha)
    end)

    it("hides when there is no target at all", function()
        -- Nothing to be out of range of, so the cross goes away. This is the
        -- reference's behaviour and it is the opposite of a restore.
        local CC = faded({
            C_Spell = { IsSpellInRange = function() return 1 end },
            UnitExists = function() return false end,
        })
        CC.frame._alpha = 1
        CC:UpdateRangeColor()
        assert.equals(0, CC.frame._alpha)
    end)

    it("leaves alpha alone when the range answer is unreadable", function()
        -- 0.37 rather than 1, deliberately. Seeding 1 and expecting 1 would be
        -- satisfied by a wrong SetAlpha(1) as well as by the correct silence,
        -- so the test could not tell "wrote nothing" from "wrote the value I
        -- happened to seed". A value the code can never produce can.
        local CC = faded({ C_Spell = { IsSpellInRange = function() return nil end } })
        CC.frame._alpha = 0.37
        CC:UpdateRangeColor()
        assert.equals(0.37, CC.frame._alpha)
    end)

    it("leaves alpha alone when the option is off", function()
        local CC = faded({ C_Spell = { IsSpellInRange = function() return 1 end } })
        CC.db.HideWhenInRange = false
        CC.frame._alpha = 0.37
        CC:UpdateRangeColor()
        assert.equals(0.37, CC.frame._alpha)
    end)

    it("does not fade while a preview is showing", function()
        -- Edit Mode drags the frame. Fading it out mid-drag would leave the
        -- user moving something they cannot see.
        local CC = faded({ C_Spell = { IsSpellInRange = function() return 1 end } })
        CC.previewActive = true
        CC.frame._alpha = 0.37
        CC:UpdateRangeColor()
        assert.equals(0.37, CC.frame._alpha)
    end)

    it("re-asserts alpha when the range state has not changed", function()
        -- Pins the write's position BEFORE the lastInRange early-out. Something
        -- else raised alpha; the next evaluation must take it back down even
        -- though in-range is what it already was.
        local CC = faded({ C_Spell = { IsSpellInRange = function() return 1 end } })
        CC:UpdateRangeColor()
        assert.equals(0, CC.frame._alpha)
        CC.frame._alpha = 1
        CC:UpdateRangeColor()
        assert.equals(0, CC.frame._alpha)
    end)

    it("runs the range loop for this option even with both colours off", function()
        local CC = faded({ C_Spell = { IsSpellInRange = function() return 1 end } })
        CC.db.RangeColorMeleeEnabled = false
        CC.db.RangeColorRangedEnabled = false
        assert.is_true(CC:ShouldRunRangeUpdate())
    end)

    it("restores alpha when the range loop is torn down", function()
        local CC = faded({ C_Spell = { IsSpellInRange = function() return 1 end } })
        CC:UpdateRangeColor()
        assert.equals(0, CC.frame._alpha)
        CC.onUpdateActive = true
        CC.db.HideWhenInRange = false
        CC.db.RangeColorMeleeEnabled = false
        CC:UpdateOnUpdateState()
        assert.equals(1, CC.frame._alpha)
    end)

    it("restores alpha when the option is turned off while colouring stays on", function()
        -- The stranding case. The loop keeps running for colour, so nothing
        -- tears it down, and the faded cross has no other route back.
        local CC = faded({ C_Spell = { IsSpellInRange = function() return 1 end } })
        CC.db.RangeColorMeleeEnabled = true
        CC:UpdateRangeColor()
        assert.equals(0, CC.frame._alpha)
        CC.db.HideWhenInRange = false
        CC:ApplySettings()
        assert.equals(1, CC.frame._alpha)
    end)

    it("restores alpha when a preview starts on a faded cross", function()
        local CC = faded({ C_Spell = { IsSpellInRange = function() return 1 end } })
        -- Shown FIRST, which is the whole point. Show's pre-existing
        -- `if not IsShown()` branch already restores alpha on a hidden frame,
        -- so a test that leaves it hidden passes without the new isPreview
        -- write. Only an already-shown, already-faded cross can tell them apart.
        CC.frame:Show()
        CC:UpdateRangeColor()
        assert.equals(0, CC.frame._alpha)
        CC:Show(true)
        assert.equals(1, CC.frame._alpha)
    end)
end)

-- The mode predicate on its own. UpdateVisibility is covered above through the
-- frame; this covers the branching that decides what it is told.
describe("CombatCross visibility modes", function()
    it("ignores combat under always and never", function()
        local CC = loader.loadCombatCross()
        assert.is_true(CC.ShouldShowByMode("always", false))
        assert.is_true(CC.ShouldShowByMode("always", true))
        assert.is_false(CC.ShouldShowByMode("never", false))
        assert.is_false(CC.ShouldShowByMode("never", true))
    end)

    it("follows combat under the two combat modes", function()
        local CC = loader.loadCombatCross()
        assert.is_true(CC.ShouldShowByMode("in_combat", true))
        assert.is_false(CC.ShouldShowByMode("in_combat", false))
        assert.is_true(CC.ShouldShowByMode("out_of_combat", false))
        assert.is_false(CC.ShouldShowByMode("out_of_combat", true))
    end)

    it("shows under solo only when ungrouped", function()
        local CC = loader.loadCombatCross({ IsInGroup = function() return false end })
        assert.is_true(CC.ShouldShowByMode("solo", false))
        local grouped = loader.loadCombatCross({ IsInGroup = function() return true end })
        assert.is_false(grouped.ShouldShowByMode("solo", false))
    end)

    -- An unknown mode shows rather than hides: a crosshair nobody asked for is
    -- easier to notice and complain about than one that silently never appears.
    it("shows on a mode it does not know", function()
        local CC = loader.loadCombatCross()
        assert.is_true(CC.ShouldShowByMode("in_raid", false))
        assert.is_true(CC.ShouldShowByMode(nil, false))
    end)

    -- The only mode that leaves the module to answer. Both directions are
    -- asserted with the combat flag set opposite to the expected result, so a
    -- predicate that returned `inCombat` or a constant fails one of them.
    it("asks the cursor module whether this is instanced content", function()
        local CC = loader.loadCombatCross()
        local cursor = _G.KitnEssentials:GetModule("Cursor")
        cursor.InRealInstancedContent = function() return true end
        assert.is_true(CC.ShouldShowByMode("in_instance", false))
        cursor.InRealInstancedContent = function() return false end
        assert.is_false(CC.ShouldShowByMode("in_instance", true))
    end)

    -- The lookup is silent, so an unresolvable module returns nil rather than
    -- throwing. Hiding is the safe direction: a crosshair stuck on is a bug
    -- report, a Lua error on every visibility change is a broken session.
    it("hides rather than throws when the cursor module cannot be resolved", function()
        local CC = loader.loadCombatCross()
        _G.KitnEssentials.GetModule = function() return nil end
        assert.is_false(CC.ShouldShowByMode("in_instance", true))
    end)

    -- AceEvent hands the handler its event name first. Forwarding these events
    -- straight to UpdateVisibility would deliver that string as `inCombat`,
    -- and a non-nil string reads as "in combat" every time.
    it("drops the event name instead of reading it as combat state", function()
        local CC = loader.loadCombatCross()
        local isShown = withFrame(CC)
        CC.frame:Show()
        CC:OnContextChanged("GROUP_ROSTER_UPDATE")
        assert.is_false(isShown())
    end)

    it("routes the stored mode through UpdateVisibility", function()
        local CC = loader.loadCombatCross()
        CC.db.Visibility = "never"
        local isShown = withFrame(CC)
        CC.frame:Show()
        CC:UpdateVisibility(true)
        assert.is_false(isShown())
    end)
end)

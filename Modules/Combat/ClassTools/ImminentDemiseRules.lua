-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/Combat/ClassTools/ImminentDemiseRules.lua       ║
-- ║  Purpose: the pure rules of the Imminent Demise          ║
-- ║           Counter: the strike count, its proof and       ║
-- ║           the guards. No WoW API, no frames.             ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local string_format = string.format

local Rules = {}
KE.ImminentDemiseRules = Rules

-- Every name the player sees comes from here.
Rules.LABEL = "Imminent Demise Counter"

Rules.TALENT = 444769
Rules.ICON = 132346
Rules.TOTAL = 3
-- A glow this close to a strike is that strike's Sudden Death.
Rules.WITH = 0.1
Rules.PREVIEW_COUNT = 2
Rules.TEST_STEPS = { 0, 1, 2, 0 }
Rules.TEST_STEP = 1.5

-- Execute lights as several ids at once, which ones depending on the
-- specialization; any one is enough.
Rules.GLOW_IDS = { [163201] = true, [281000] = true, [330334] = true, [5308] = true }
-- Execute ranks before Condemn on the Cooldown Manager.
Rules.CDM_IDS = { [163201] = 1, [281000] = 1, [5308] = 1, [280735] = 1, [330334] = 2 }

-- Icon mode count spots: point, relative point, x, y.
Rules.SPOTS = {
    TOP         = { "TOP", "TOP", 0, -2 },
    CENTER      = { "CENTER", "CENTER", 0, 0 },
    BOTTOM      = { "BOTTOM", "BOTTOM", 0, 2 },
    TOPLEFT     = { "TOPLEFT", "TOPLEFT", 2, -2 },
    TOPRIGHT    = { "TOPRIGHT", "TOPRIGHT", -2, -2 },
    BOTTOMLEFT  = { "BOTTOMLEFT", "BOTTOMLEFT", 2, 2 },
    BOTTOMRIGHT = { "BOTTOMRIGHT", "BOTTOMRIGHT", -2, 2 },
    ABOVE       = { "BOTTOM", "TOP", 0, 2 },
    BELOW       = { "TOP", "BOTTOM", 0, -2 },
}

Rules.COLOR_KEYS = { [0] = "Color0", [1] = "Color1", [2] = "Color2" }
Rules.COLORS = {
    [0] = { 0.6, 0.6, 0.6, 1 },
    [1] = { 1, 1, 1, 1 },
    [2] = { 1, 0.82, 0.2, 1 },
}

-- The strike signals and their merge window are Executioner Stacks' rules.
local Executioner = KE.ExecutionerRules
Rules.DoorFor = Executioner.DoorFor
Rules.SAME = Executioner.SAME
Rules.ZONE_IN_IGNORE = Executioner.ZONE_IN_IGNORE

-- In step: the count has matched a Sudden Death since it was last reset.
function Rules.New()
    return {
        count = 0, inStep = false, proven = false,
        strikeHeard = false, strikeAt = -10, glowAt = -10,
    }
end

function Rules.Reset(state)
    state.count, state.ghost, state.inStep = 0, nil, false
end

-- A secret id is never compared.
function Rules.IsGlow(spellID, idSecret)
    if idSecret or spellID == nil then return false end
    return Rules.GLOW_IDS[spellID] == true
end

-- One mismatch while in step is taken for Sudden Death from another
-- source; the same mismatch twice, or one before the count was ever in
-- step, sets the count to 0.
function Rules.Proof(state)
    state.proven = true
    if state.count == 0 then
        state.ghost, state.inStep = nil, true
        return "matched"
    end
    if state.inStep and state.ghost ~= state.count then
        state.ghost = state.count
        return "ghost"
    end
    state.count, state.ghost, state.inStep = 0, nil, true
    return "fixed"
end

-- The buff's echo counts only until a strike echo proves the strike
-- doors work on this client. The second return is a proof's outcome,
-- when Execute lit just before the strike.
function Rules.Signal(state, door, now, ignoreUntil)
    if ignoreUntil and now < ignoreUntil then return "zone_in" end
    if door == "buff" then
        if state.strikeHeard then return "buff_ignored" end
    else
        state.strikeHeard = true
    end
    if now - state.strikeAt <= Rules.SAME then return "merged" end
    state.strikeAt, state.proven = now, false
    state.count = (state.count + 1) % Rules.TOTAL
    if now - state.glowAt <= Rules.WITH then return "counted", Rules.Proof(state) end
    return "counted"
end

-- Several Execute ids light in one frame; only the first is a proof.
function Rules.Glow(state, now)
    state.glowAt = now
    if state.proven or now - state.strikeAt > Rules.WITH then return nil end
    return Rules.Proof(state)
end

function Rules.Text(n)
    return string_format("%d/%d", n, Rules.TOTAL)
end

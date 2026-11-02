-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/Combat/ClassTools/ExecutionerRules.lua          ║
-- ║  Purpose: the pure rules of Executioner Stacks: the      ║
-- ║           count, the cancel cue and the guards.          ║
-- ║           No WoW API, no frames.                         ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local math_ceil, math_floor, math_max = math.ceil, math.floor, math.max
local string_format = string.format
local table_insert, table_remove = table.insert, table.remove
local tonumber, type = tonumber, type

local Rules = {}
KE.ExecutionerRules = Rules

-- Every name the player sees comes from here.
Rules.LABEL = "Executioner Stacks"

Rules.BUFF = 445584
Rules.STRIKE = 445579
Rules.DOMINANCE = 444767
Rules.FOCUS = 1270718
Rules.EXECUTES = { 281000, 163201 }
Rules.CANCEL_ICON = 458973

-- A number in /cancelaura reaches C_Spell.CancelSpellByID, so the macro
-- works in every client language.
Rules.MACRO_NAME = "Cancel Exec"
Rules.MACRO_BODY = "/cancelaura 445584"

Rules.CAP = 5
Rules.BASE = 12
Rules.FOCUS_ADD = 6
-- One strike can reach two events; signals this close are one proc.
Rules.SAME = 0.25
Rules.LAG = 0.005
Rules.CHECK_DELAY = 0.15
Rules.CHECK_QUIET = 0.12
-- The game re-announces cooldowns in a burst after zoning in.
Rules.ZONE_IN_IGNORE = 2
Rules.MAX_BARS = 12
Rules.MAX_MARKS = 7
Rules.CUE_QUIET = 3

Rules.PREVIEW_LEFT = { 3.2, 7.5, 11, 14.6, 16.1, 17.4 }
Rules.PREVIEW_STACKS = 4
Rules.TEST_AT = { 0, 1.2, 2.5, 3.4, 4.3, 5.5, 6.8, 8, 9.5, 21, 22.4 }

-- The first `stacks` timers are the stacks; the rest are hidden timers.
function Rules.New()
    return { timers = {}, stacks = 0, lastProc = -10, strikeHeard = false }
end

function Rules.Wipe(state)
    local timers = state.timers
    for i = #timers, 1, -1 do timers[i] = nil end
    state.stacks = 0
end

function Rules.Length(hasFocus)
    if hasFocus then return Rules.BASE + Rules.FOCUS_ADD end
    return Rules.BASE
end

-- A secret id is never compared.
function Rules.DoorFor(event, spellID, idSecret)
    if idSecret or spellID == nil then return nil end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if spellID == Rules.STRIKE then return "cast" end
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        if spellID == Rules.STRIKE then return "echo" end
        if spellID == Rules.BUFF then return "buff" end
    end
    return nil
end

function Rules.Add(state, now, length)
    local timers = state.timers
    local timer = { ends = now + length, len = length }
    local i = #timers + 1
    while i > 1 and timers[i - 1].ends > timer.ends do i = i - 1 end
    table_insert(timers, i, timer)
end

-- A timer that runs out takes a stack; with no stack left the buff is gone
-- and its hidden timers with it.
function Rules.Expire(state, now)
    local timers = state.timers
    local changed = false
    while timers[1] and timers[1].ends + Rules.LAG <= now do
        table_remove(timers, 1)
        changed = true
        if state.stacks > 0 then state.stacks = state.stacks - 1 end
        if state.stacks == 0 then Rules.Wipe(state) end
    end
    return changed
end

-- A proc at the cap still starts a timer: that timer is a hidden one.
function Rules.Proc(state, now, length)
    Rules.Expire(state, now)
    if state.stacks < Rules.CAP then state.stacks = state.stacks + 1 end
    Rules.Add(state, now, length)
end

-- The buff's own echo counts only until a strike signal proves the strike
-- doors work on this client.
function Rules.Signal(state, door, now, length, ignoreUntil)
    if door ~= "cast" and ignoreUntil and now < ignoreUntil then return "zone_in" end
    if door == "buff" then
        if state.strikeHeard then return "buff_ignored" end
    else
        state.strikeHeard = true
    end
    if now - state.lastProc <= Rules.SAME then return "merged" end
    state.lastProc = now
    Rules.Proc(state, now, length)
    return "counted"
end

function Rules.Hidden(state)
    return #state.timers - state.stacks
end

-- Called after Expire. Right after a proc or right before an expiry the
-- real buff may not have caught up with the count yet.
function Rules.CheckAllowed(state, now, testUntil)
    if testUntil and now < testUntil then return false end
    if now - state.lastProc < Rules.CHECK_QUIET then return false end
    local first = state.timers[1]
    if first and first.ends + Rules.LAG - now < Rules.CHECK_QUIET then return false end
    return true
end

-- A nil aura means "no buff" only once the aura is known to be readable.
function Rules.ReadStacks(auraHidden, aura, applications, applicationsSecret)
    if auraHidden then return nil end
    if aura == nil then return 0 end
    if applicationsSecret then return nil end
    local n = tonumber(applications) or 0
    if n < 1 then n = 1 end
    return n
end

function Rules.Correct(state, n, now, length)
    if n == state.stacks then return false end
    if n == 0 then
        Rules.Wipe(state)
        return true
    end
    local timers = state.timers
    if n < state.stacks then
        for _ = 1, state.stacks - n do table_remove(timers) end
    else
        while #timers < n do Rules.Add(state, now, length) end
    end
    state.stacks = n
    return true
end

function Rules.CueWanted(stacks, hidden)
    return stacks > 0 and hidden >= math_max(1, stacks - 1)
end

function Rules.CueState(wanted, waitSD, sdUp)
    local held = (wanted and waitSD and sdUp) and true or false
    local shown = (wanted and not held) and true or false
    return shown, held
end

function Rules.IsBuffCancel(spell, spellSecret, buffNameLower)
    if spellSecret or spell == nil then return false end
    if spell == Rules.BUFF then return true end
    if type(spell) ~= "string" or not buffNameLower then return false end
    return spell:lower() == buffNameLower
end

function Rules.SoundDue(lastAt, now)
    return lastAt == nil or now - lastAt >= Rules.CUE_QUIET
end

-- Macro writes are protected in combat. An existing macro is edited even
-- with both lists full, since editing takes no slot.
function Rules.MacroPlan(inCombat, index, numGeneral, numCharacter, maxGeneral, maxCharacter)
    if inCombat then return "combat" end
    if index and index > 0 then return "edit" end
    if (numGeneral or 0) < maxGeneral then return "account" end
    if (numCharacter or 0) < maxCharacter then return "character" end
    return "full"
end

-- Whole seconds rounded up from 3 s, tenths below.
function Rules.SecondsKey(left)
    if left < 0 then left = 0 end
    if left >= 3 then return math_ceil(left - 0.001) end
    return -math_floor(left * 10 + 0.5)
end

function Rules.Seconds(left)
    if left < 0 then left = 0 end
    if left >= 3 then return string_format("%d", math_ceil(left - 0.001)) end
    return string_format("%.1f", left)
end

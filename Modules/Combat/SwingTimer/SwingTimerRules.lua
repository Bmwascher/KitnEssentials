-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/Combat/SwingTimer/SwingTimerRules.lua           ║
-- ║  Purpose: Swing Timer's constants, proof switches and    ║
-- ║           pure rules. No WoW API, no frames.             ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local math_huge, math_min = math.huge, math.min
local ipairs, type = ipairs, type

local Rules = {}
KE.SwingTimerRules = Rules

-- The gap from a stop to the next shot has no Blizzard source, so this is the
-- measured gap less the world latency, which each swing adds back. A zone
-- slightly too wide costs a slightly early stop; one too narrow costs a shot.
Rules.AIM_SECONDS = 0.66
Rules.SEAL_SECONDS = 30
Rules.OUT_OF_RANGE_ALPHA = 0.4
Rules.INTERVAL_MIN = 0.50
Rules.INTERVAL_MAX = 5.00

-- Each switch guards an aid that rests on an in-game read, and holds that read's
-- answer. While false the aid takes its safe path.
Rules.PROOF = {
    -- Hits on the player read plain: offer the Target bar.
    TARGET_BAR = true,
    -- Writing Blizzard's setting from addon code is safe: offer the hide button.
    BLIZZARD_BUTTON = true,
    -- Edit Mode's checkbox turns a hidden bar back on: the page may promise it.
    EDIT_MODE_CHECKBOX = true,
    -- The range check answers false inside a hunter's dead zone: drop the note.
    RANGE_SEES_DEAD_ZONE = false,
    -- A parry does not re-fire the swing event: shorten the swing here.
    OWN_PARRY_HASTE = false,
}

local SWING_BARS = { [0] = "MH", [1] = "OH", [2] = "R" }
local GUIDE_CLASSES = { HUNTER = true, MAGE = true, PRIEST = true, WARLOCK = true }
local GUIDE_ORDER = { "R", "MH", "OH" }
local OTHER_ORDER = { "MH", "OH", "R" }

function Rules.BarFor(swingType)
    if swingType == nil then return nil end
    return SWING_BARS[swingType]
end

function Rules.ValidDuration(seconds)
    return type(seconds) == "number" and seconds == seconds and seconds > 0 and seconds < math_huge
end

function Rules.IsGuideClass(classFile)
    return GUIDE_CLASSES[classFile] == true
end

function Rules.BarOrder(classFile)
    return GUIDE_CLASSES[classFile] and GUIDE_ORDER or OTHER_ORDER
end

-- A slot comes from the fixed order and the weapons known, never from what has
-- swung, so a bar appearing moves no other bar.
function Rules.Slots(order, known)
    local slots, row = {}, 0
    for _, bar in ipairs(order) do
        if bar == "MH" or known[bar] then
            row = row + 1
            slots[bar] = row
        end
    end
    return slots
end

function Rules.BarShown(showWhenSwings, isPrimary, known, used)
    if not known then return false end
    if not showWhenSwings then return true end
    return isPrimary or used == true
end

-- An unreadable read says nothing about the weapon, so the last answer stands.
function Rules.WeaponKnown(readable, read, known)
    if not readable then return known == true end
    return Rules.ValidDuration(read)
end

function Rules.SwapRestartSpeed(readable, read)
    if readable and Rules.ValidDuration(read) then return read end
    return nil
end

function Rules.OutOfRange(readable, isInRange)
    return readable == true and isInRange == false
end

function Rules.OutOfRangeFromEvent(readable, isInRange, checksRange)
    return readable == true and checksRange == true and isInRange == false
end

function Rules.FrameShown(visibility, inCombat, anyLive, isPreview)
    if isPreview then return true end
    if visibility == "always" then return true end
    if visibility == "idle" then return anyLive == true end
    return inCombat == true
end

function Rules.MeleeState(attackOn, now, ends)
    if not attackOn then return "empty" end
    if ends and now < ends then return "running" end
    return "parked"
end

-- The window's width as a fraction of the bar, measured from the end.
function Rules.EndWindow(seconds, duration, addLatency, latency)
    if not seconds or seconds <= 0 or not Rules.ValidDuration(duration) then return nil end
    local width = seconds
    if addLatency then width = width + (latency or 0) end
    return math_min(1, width / duration)
end

function Rules.Mirror(fraction, deplete)
    if deplete then return 1 - fraction end
    return fraction
end

local math_max = math.max
local SHOT_SPELLS = { [75] = true, [5019] = true }

-- The stop-by line and the start of the final latency, as fractions of the bar.
function Rules.Zones(duration, aim, latency)
    local stopBy = 1 - (aim + latency) / duration
    local go = 1 - latency / duration
    return math_max(0, stopBy), math_max(0, go)
end

function Rules.ShotTime(swingEnd, lastStop, aim, latency)
    return math_max(swingEnd, (lastStop or 0) + aim + latency)
end

function Rules.RangedAtEnd(moving, casting, outOfRange, now, shotAt)
    if moving then return "held" end
    if casting or outOfRange then return "wait" end
    if now < shotAt then return "aim" end
    return "ready"
end

function Rules.ReloadWord(inZone, moving)
    if not inZone then return "MOVE" end
    return moving and "STOP" or "STILL"
end

function Rules.TickIgnored(spellID)
    return SHOT_SPELLS[spellID] == true
end

-- Returns the fraction and whether the cast clips the swing, or nil.
function Rules.TickFraction(castEnd, swingStart, duration)
    if not Rules.ValidDuration(duration) then return nil end
    local fraction = (castEnd - swingStart) / duration
    if fraction > 1 then return 1, true end
    return math_max(0, fraction), false
end

Rules.QUEUE_SPELLS = {
    WARRIOR = { { id = 78, colorKey = "ColorQueue" }, { id = 845, colorKey = "ColorCleave" } },
    DRUID = { { id = 6807, colorKey = "ColorQueue" } },
    HUNTER = { { id = 2973, colorKey = "ColorQueue" } },
}

Rules.SEALS = {
    { id = 20154, colorKey = "ColorSealRighteousness", label = "Righteousness" },
    { id = 21082, colorKey = "ColorSealCrusader", label = "Crusader" },
    { id = 20375, colorKey = "ColorSealCommand", label = "Command" },
    { id = 20164, colorKey = "ColorSealJustice", label = "Justice" },
    { id = 20165, colorKey = "ColorSealLight", label = "Light" },
    { id = 20166, colorKey = "ColorSealWisdom", label = "Wisdom" },
    { id = 1311649, colorKey = "ColorSealFury", label = "Fury" },
    { id = 407798, colorKey = "ColorSealMartyrdom", label = "Martyrdom" },
}

local PHYSICAL_SCHOOL = 1
local SWING_ACTIONS = {
    WOUND = true, MISS = true, DODGE = true, PARRY = true, BLOCK = true,
    DEFLECT = true, ABSORB = true, IMMUNE = true, EVADE = true,
}

function Rules.QueueEventWanted(classFile, colorOn)
    return colorOn == true and Rules.QUEUE_SPELLS[classFile] ~= nil
end

function Rules.SealFromCast(name, sealByName)
    if type(name) ~= "string" then return nil end
    return sealByName[name]
end

function Rules.SealSeconds(readable, auraLength, known)
    if readable and Rules.ValidDuration(auraLength) then return auraLength end
    return known or Rules.SEAL_SECONDS
end

function Rules.SealSource(aurasHidden, inCombat)
    if aurasHidden or inCombat then return "cast" end
    return "auras"
end

function Rules.BarColorKey(isMelee, queueKey, sealKey, baseKey)
    if not isMelee then return baseKey end
    return queueKey or sealKey or baseKey
end

-- Reading the setting on clears a stale flag, so a re-enable from outside the
-- addon needs no event.
function Rules.BlizzardFlag(cvarOn, flag)
    if cvarOn then return false end
    return flag == true
end

-- Returns whether the button shows and what it does.
function Rules.BlizzardButton(cvarOn, flag)
    if cvarOn then return true, "hide" end
    if flag then return true, "show" end
    return false, nil
end

-- Returns the setting's value to write and the new flag, or nil when refused.
function Rules.BlizzardClick(cvarOn, flag, inCombat)
    if inCombat then return nil end
    if cvarOn then return "0", true end
    if flag then return "1", false end
    return nil
end

-- The flag is shared with Blizzard's bar, so it is released only while that bar
-- is off.
function Rules.ReleaseRangeFlag(cvarOn)
    return not cvarOn
end

function Rules.ParryHastened(remaining, duration)
    if remaining > 0.6 * duration then return remaining - 0.4 * duration end
    if remaining > 0.2 * duration then return 0.2 * duration end
    return remaining
end

-- An unreadable "not on me" passes, since the bar is labeled an estimate.
function Rules.TargetHitCounts(action, school, onMeReadable, onMe)
    if not SWING_ACTIONS[action] or school ~= PHYSICAL_SCHOOL then return false end
    return not (onMeReadable and onMe == false)
end

function Rules.LearnInterval(previousHit, now, lastGood)
    if not previousHit then return lastGood end
    local sample = now - previousHit
    if sample < Rules.INTERVAL_MIN or sample > Rules.INTERVAL_MAX then return lastGood end
    return sample
end

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

-- The gap from a stop to the next shot has no Blizzard source. A zone slightly
-- too wide costs a slightly early stop; one too narrow costs a shot.
Rules.AIM_SECONDS = 0.5
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

-- Returns the speed and whether a weapon is known. An unreadable read says
-- nothing about the weapon, so the cache answers.
function Rules.ResolveSpeed(readable, read, cached)
    if not readable then return cached, cached ~= nil end
    if Rules.ValidDuration(read) then return read, true end
    return nil, false
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

function Rules.RangedWord(phase, inZone, moving)
    if phase == "reload" then
        if not inZone then return "MOVE" end
        return moving and "STOP" or "STILL"
    end
    if phase == "aim" then return "STILL" end
    if phase == "held" then return "STOP" end
    return nil
end

function Rules.TickIgnored(spellID)
    return SHOT_SPELLS[spellID] == true
end

-- Returns the fraction and whether the cast clips the swing, or nil.
function Rules.TickFraction(readable, castEnd, swingStart, duration)
    if not readable or not Rules.ValidDuration(duration) then return nil end
    local fraction = (castEnd - swingStart) / duration
    if fraction > 1 then return 1, true end
    return math_max(0, fraction), false
end

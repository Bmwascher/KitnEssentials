-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/Combat/AuraEngine/GlowRules.lua                 ║
-- ║  Purpose: pure glow value rules — type coercion, speed   ║
-- ║  normalisation, and the legacy-duration adapter.         ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local GlowRules = {}
KE.AuraGlowRules = GlowRules

local DEFAULT_TYPE      = "ants"
local DEFAULT_FREQUENCY = 0.25

-- Grid data, not guesses: both atlases are declared 6x5 with 30 frames in
-- Blizzard's own action-bar templates, and the alert sheet holds 25 cells of
-- which only the first 22 are real -- playing all 25 flashes an empty gap that
-- reads as a backwards stutter. The size factor scales the TEXTURE, never the
-- host frame.
--
-- frameWidth/frameHeight are the flipbook's CELL size. Zero means "derive it",
-- which an atlas can do because it carries its own region. A raw texture file
-- has no region to measure, so the alert sheet must state its cell size or the
-- animation has no geometry to step through.
GlowRules.FLIPBOOKS = {
    ants = {
        -- Lowercase, exactly as Blizzard declares it. A capitalised spelling
        -- finds nothing when searching the client source.
        atlas = "rotationhelper_ants_flipbook",
        rows = 6, columns = 5, frames = 30, sizeFactor = 1.6,
        frameWidth = 0, frameHeight = 0,
    },
    procloop = {
        atlas = "UI-HUD-ActionBar-Proc-Loop-Flipbook",
        rows = 6, columns = 5, frames = 30, sizeFactor = 1.4,
        frameWidth = 0, frameHeight = 0,
    },
    alert = {
        texture = [[Interface\SpellActivationOverlay\IconAlertAnts]],
        rows = 5, columns = 5, frames = 22, sizeFactor = 1.25,
        frameWidth = 48, frameHeight = 48,
    },
}

-- Every selectable style, and which host draws it. The flipbook host steps a
-- sheet; the pixel host marches four masked dash strips. ResolveType keys off
-- this rather than FLIPBOOKS, which knows only about the sheet-based three.
GlowRules.STYLES = {
    pixel    = { kind = "pixel" },
    ants     = { kind = "flipbook" },
    procloop = { kind = "flipbook" },
    alert    = { kind = "flipbook" },
}

-- Read-time coercion, never a profile rewrite: a migration would write a
-- value the user could not yet have chosen.
-- `pixel` is absent on purpose: it renders again, so it resolves to itself
-- through the STYLES lookup and must not be coerced away.
local TYPE_MAP = {
    autocast = "pixel",     -- both trace the button edge
    button   = "procloop",  -- both are a soft fill rather than an outline
    proc     = "procloop",
}

function GlowRules.ResolveType(stored)
    if GlowRules.STYLES[stored] then return stored end
    return TYPE_MAP[stored] or DEFAULT_TYPE
end

-- The bounds arrive from the caller's adapter rather than as constants,
-- which is what lets Externals keep the old 0.5 second minimum by passing a
-- maximum of 2 while every other consumer stays at 1.
function GlowRules.NormaliseFrequency(value, min, max)
    local frequency = tonumber(value)
    if not frequency or frequency <= 0 then frequency = DEFAULT_FREQUENCY end
    if min and frequency < min then frequency = min end
    if max and frequency > max then frequency = max end
    return frequency
end

-- The slider stores a FREQUENCY; a FlipBook's SetDuration wants a PERIOD.
-- Passing the frequency straight through would invert the control.
function GlowRules.FrequencyToDuration(frequency)
    return 1 / frequency
end

-- A user stored on proc has their tuned loop period in GlowDuration, which is
-- the same quantity the new flipbook wants. Discarding it would throw away a
-- speed they deliberately set.
function GlowRules.ReadSpeed(db, keys)
    if not db or not keys then return DEFAULT_FREQUENCY end

    if db[keys.type] == "proc" then
        local duration = tonumber(db[keys.duration])
        if duration and duration > 0 then
            return 1 / duration
        end
    end

    return db[keys.frequency]
end

-- Writes BOTH values, in this order. Without settling the type, the raw value
-- stays proc, the read rule keeps preferring GlowDuration, and the new Speed
-- is read straight back as the old one.
function GlowRules.WriteSpeed(db, keys, value)
    if not db or not keys then return end
    db[keys.frequency] = value
    db[keys.type]      = GlowRules.ResolveType(db[keys.type])
    return db[keys.frequency], db[keys.type]
end

-- The type dropdown's settling rule, and the reason it cannot be a plain
-- assignment. A user stored on proc keeps their tuned period in GlowDuration.
-- Writing only the type retires the read rule that was reaching that value,
-- so the tuned speed is silently lost on the very next read. Resolve the
-- speed FIRST, under the old type, then write both.
function GlowRules.SetType(db, keys, chosen)
    if not db or not keys then return end
    -- Normalised, not raw: ReadSpeed can return nil, and this writes to the
    -- user's profile.
    local speed = GlowRules.NormaliseFrequency(GlowRules.ReadSpeed(db, keys), 0.05, 2)
    db[keys.frequency] = speed
    db[keys.type]      = chosen
    return db[keys.frequency], db[keys.type]
end

-- The flipbook's OWN inputs, and nothing else. Icon size and colour are
-- deliberately absent: changing them must not restart a playing animation.
function GlowRules.FlipbookState(entry, duration)
    return {
        source      = entry.atlas or entry.texture,
        rows        = entry.rows,
        columns     = entry.columns,
        frames      = entry.frames,
        frameWidth  = entry.frameWidth or 0,
        frameHeight = entry.frameHeight or 0,
        duration    = duration,
    }
end

-- `source` is the field the older test was missing. Two styles can declare an
-- identical grid, so comparing the grid alone reports "unchanged" across a
-- texture swap and the animation is never stopped and replayed.
function GlowRules.NeedsRestart(applied, wanted)
    if not applied then return true end
    return applied.source      ~= wanted.source
        or applied.rows        ~= wanted.rows
        or applied.columns     ~= wanted.columns
        or applied.frames      ~= wanted.frames
        or applied.frameWidth  ~= wanted.frameWidth
        or applied.frameHeight ~= wanted.frameHeight
        or applied.duration    ~= wanted.duration
end

local math_floor = math.floor

-- Clamped to the range the Lines slider offers, so a hand-edited profile
-- cannot ask for a dash count the geometry was never solved for.
function GlowRules.NormalisePixelCount(value)
    local n = tonumber(value)
    if not n or n < 1 then return 8 end
    if n > 16 then return 16 end
    return math_floor(n)
end

-- Same rule for the Thickness slider's range.
function GlowRules.NormalisePixelThickness(value)
    local t = tonumber(value)
    if not t or t < 1 then return 1 end
    if t > 8 then return 8 end
    return math_floor(t)
end

-- The marching border, as scalars.
--
-- `cycle` is the pixel span of one dash plus its gap. Each strip is drawn one
-- whole cycle LONGER than its edge and translated by exactly one cycle, so the
-- snap back at the end of the loop lands on identical pixels and is invisible.
-- `phase` is each edge's cumulative distance around the perimeter, expressed in
-- cycles, which is what keeps the dashes continuous across a corner: phase
-- matters only modulo one cycle, so the one-cycle strip overhang cancels out.
--
-- Edge order is clockwise from the top: top, right, bottom, left.
function GlowRules.PixelPerimeter(count, width, height, period)
    local n = GlowRules.NormalisePixelCount(count)
    local perimeter = 2 * (width + height)
    local cycle = perimeter / n

    return {
        count = n,
        cycle = cycle,
        step  = period / n,
        phase = {
            0,
            width / cycle,
            (width + height) / cycle,
            (width + height + width) / cycle,
        },
        spanH = (width + cycle) / cycle,
        spanV = (height + cycle) / cycle,
    }
end

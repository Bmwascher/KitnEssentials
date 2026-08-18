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
-- which only the first 22 are real — playing all 25 flashes an empty gap that
-- reads as a backwards stutter. The size factor scales the TEXTURE, never the
-- host frame.
GlowRules.FLIPBOOKS = {
    ants = {
        -- Lowercase, exactly as Blizzard declares it. A capitalised spelling
        -- finds nothing when searching the client source.
        atlas = "rotationhelper_ants_flipbook",
        rows = 6, columns = 5, frames = 30, sizeFactor = 1.6,
    },
    procloop = {
        atlas = "UI-HUD-ActionBar-Proc-Loop-Flipbook",
        rows = 6, columns = 5, frames = 30, sizeFactor = 1.4,
    },
    alert = {
        texture = [[Interface\SpellActivationOverlay\IconAlertAnts]],
        rows = 5, columns = 5, frames = 22, sizeFactor = 1.25,
    },
}

-- Read-time coercion, never a profile rewrite: a migration would write a
-- value the user could not yet have chosen, and stored glow types are never
-- migrated by design.
local TYPE_MAP = {
    pixel    = "ants",      -- both trace the button edge
    autocast = "ants",
    button   = "procloop",  -- both are a soft fill rather than an outline
    proc     = "procloop",
}

function GlowRules.ResolveType(stored)
    if GlowRules.FLIPBOOKS[stored] then return stored end
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

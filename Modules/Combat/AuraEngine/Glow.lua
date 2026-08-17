-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/Combat/AuraEngine/Glow.lua                       ║
-- ║  Purpose: the flipbook glow host -- animation-driven, so   ║
-- ║  it keeps animating while auras are secret.                ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local Glow = {}
KE.AuraGlow = Glow

local GlowRules = KE.AuraGlowRules

-- Externals' historical bounds: 0.05 is the old minimum loop period, 2 is
-- the old maximum -- both come from the module this engine replaces.
local MIN_FREQUENCY = 0.05
local MAX_FREQUENCY = 2

-- ReadSpeed's key-table shape: the settings table doubles as the db it reads,
-- since a "proc"-typed profile keeps its tuned loop period in GlowDuration
-- rather than GlowFrequency.
local SPEED_KEYS = { type = "GlowType", frequency = "GlowFrequency", duration = "GlowDuration" }

local function ResolveEntry(settings)
    local key = GlowRules.ResolveType(settings.GlowType)
    return GlowRules.FLIPBOOKS[key] or GlowRules.FLIPBOOKS.ants
end

-- Shared by CreateHost and Apply so the two can never drift: CreateHost
-- calls this once to seed a valid starting state, Apply calls it again on
-- every reconfiguration to pick up changed settings.
local function ConfigureHost(host, settings)
    local entry = ResolveEntry(settings)
    local texture = host.texture

    -- Take the size from settings, never from button:GetWidth(): a frame
    -- measured before its layout pass reports 1x1, which reads as a valid
    -- number and would produce a glow too small to see.
    local size = (settings.IconSize or 32) * entry.sizeFactor
    texture:SetSize(size, size)
    texture:ClearAllPoints()
    texture:SetPoint("CENTER", host, "CENTER", 0, 0)

    if entry.atlas then
        texture:SetAtlas(entry.atlas, false)
    elseif entry.texture then
        texture:SetTexture(entry.texture)
    end

    local read = GlowRules.ReadSpeed(settings, SPEED_KEYS)
    local frequency = GlowRules.NormaliseFrequency(read, MIN_FREQUENCY, MAX_FREQUENCY)
    local duration = GlowRules.FrequencyToDuration(frequency)

    -- No in-client case mutates a PLAYING flipbook's grid or duration; every
    -- one sets them on a stopped group and plays it afterward. Restarting
    -- unconditionally on every reconfigure would stutter an unrelated change
    -- (icon size, colour), so the group is only stopped and replayed when a
    -- flipbook property actually differs from what is already applied.
    local applied = host.appliedFlip
    local changed = not applied
        or applied.rows ~= entry.rows
        or applied.columns ~= entry.columns
        or applied.frames ~= entry.frames
        or applied.duration ~= duration

    if changed then
        host.animGroup:Stop()
        host.flip:SetFlipBookRows(entry.rows)
        host.flip:SetFlipBookColumns(entry.columns)
        host.flip:SetFlipBookFrames(entry.frames)
        host.flip:SetDuration(duration)
        host.animGroup:Play()
        host.appliedFlip = { rows = entry.rows, columns = entry.columns, frames = entry.frames, duration = duration }
    end

    -- Without the desaturate the atlas keeps its own hue and the colour
    -- setting appears to do nothing on some sources.
    texture:SetDesaturated(true)
    local r, g, b, a = KE:ResolveColor(settings.GlowColor, { 0, 1, 0, 1 })
    texture:SetVertexColor(r, g, b, a)

    host:SetShown(settings.GlowEnabled and true or false)
end

-- initializeFrame is the only legally guaranteed window to parent a frame to
-- an aura button, and button:GetFrameLevel() is only legal to read here,
-- before the access restriction attaches.
--
-- KE's existing glow library (LibCustomGlow) is unusable here, and the
-- reason is where it touches the button rather than how it animates: its
-- entry point lazily reparents a pooled frame to the target and reads the
-- target's frame level and size, long after this window has closed.
function Glow.CreateHost(button, settings)
    local host = CreateFrame("Frame", nil, button)
    host:SetAllPoints(button)
    host:SetFrameLevel(button:GetFrameLevel() + 3)
    host:EnableMouse(false)

    local texture = host:CreateTexture(nil, "OVERLAY")

    local animGroup = texture:CreateAnimationGroup()
    animGroup:SetLooping("REPEAT")
    local flip = animGroup:CreateAnimation("FlipBook")
    flip:SetFlipBookFrameWidth(0)
    flip:SetFlipBookFrameHeight(0)

    host.texture   = texture
    host.animGroup = animGroup
    host.flip      = flip

    ConfigureHost(host, settings)

    return host
end

-- Takes the BUTTON, not the host, because Reconfigure iterates buttons and
-- must not know where a host is stored. Called unconditionally from both
-- the live button path and the preview-frame path, so it must tolerate a
-- frame with no glow host (a group without the glow capability parents
-- none).
function Glow.Apply(button, settings, capabilities)
    local host = button and button.keGlow
    if not host then return end

    local caps = capabilities or {}
    if not caps.hasGlow then return end

    ConfigureHost(host, settings)
end

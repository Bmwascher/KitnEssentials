-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/Combat/AuraEngine/Glow.lua                      ║
-- ║  Purpose: the flipbook glow host -- animation-driven, so ║
-- ║  it keeps animating while auras are secret.              ║
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

-- The dash strips tile horizontally and vertically, so the two orientations
-- are separate files rather than one rotated at draw time.
local DASH_H   = [[Interface\AddOns\KitnEssentials\Media\Glows\glow-dash-h.tga]]
local DASH_V   = [[Interface\AddOns\KitnEssentials\Media\Glows\glow-dash-v.tga]]
local DASH_MASK = [[Interface\Buttons\WHITE8X8]]

local function ResolveEntry(settings)
    local key = GlowRules.ResolveType(settings.GlowType)
    return GlowRules.FLIPBOOKS[key] or GlowRules.FLIPBOOKS.ants
end

-- The mask is pinned to the edge and the strip overhangs it by one cycle, so
-- the translation carries dashes into the masked span from outside it and the
-- loop point never shows. Anchors differ per edge because each strip enters
-- from the side it travels away from.
local function ConfigurePixel(host, settings, period)
    local dashes = host.dashes
    if not dashes then return end

    local size = settings.IconSize or 32
    local thickness = GlowRules.NormalisePixelThickness(settings.GlowThickness)
    local p = GlowRules.PixelPerimeter(settings.GlowLines, size, size, period)
    local r, g, b, a = KE:ResolveColor(settings.GlowColor, { 0, 1, 0, 1 })

    local edges = {
        { texture = DASH_H, vertical = false, dx =  p.cycle, dy = 0 },
        { texture = DASH_V, vertical = true,  dx = 0, dy = -p.cycle },
        { texture = DASH_H, vertical = false, dx = -p.cycle, dy = 0 },
        { texture = DASH_V, vertical = true,  dx = 0, dy =  p.cycle },
    }

    for i = 1, 4 do
        local e = edges[i]
        local d = dashes[i]
        local phase = p.phase[i]

        d.group:Stop()
        d.strip:SetTexture(e.texture, "REPEAT", "REPEAT")
        d.strip:SetVertexColor(r, g, b, a)
        d.mask:ClearAllPoints()
        d.strip:ClearAllPoints()

        if not e.vertical then
            d.mask:SetSize(size, thickness)
            d.strip:SetSize(size + p.cycle, thickness)
            if i == 1 then
                d.mask:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                d.strip:SetPoint("TOPLEFT", host, "TOPLEFT", -p.cycle, 0)
            else
                d.mask:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, 0)
                d.strip:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, 0)
            end
            d.strip:SetTexCoord(phase, phase + p.spanH, 0, 1)
        else
            d.mask:SetSize(thickness, size)
            d.strip:SetSize(thickness, size + p.cycle)
            if i == 2 then
                d.mask:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
                d.strip:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, p.cycle)
            else
                d.mask:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, 0)
                d.strip:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, -p.cycle)
            end
            d.strip:SetTexCoord(0, 1, phase, phase + p.spanV)
        end

        d.strip:Show()
        d.move:SetOffset(e.dx, e.dy)
        d.move:SetDuration(p.step)
        d.group:Play()
    end
end

local function HidePixel(host)
    if not host.dashes then return end
    for i = 1, 4 do
        host.dashes[i].group:Stop()
        host.dashes[i].strip:Hide()
    end
end

-- Shared by CreateHost and Apply so the two can never drift: CreateHost
-- calls this once to seed a valid starting state, Apply calls it again on
-- every reconfiguration to pick up changed settings.
local function ConfigureHost(host, settings)
    -- Glow off stops every group rather than only hiding the host. A playing
    -- animation on a hidden texture still costs a C-side update, which is the
    -- same reason the pixel branch below stops the sheet layers instead of
    -- hiding them. appliedFlip is cleared so re-enabling is seen as a change
    -- and replays -- the reconfiguration that re-enables is the restart hook.
    if not settings.GlowEnabled then
        host.animGroup:Stop()
        if host.overlayGroup then
            host.overlayGroup:Stop()
            host.overlay:Hide()
        end
        HidePixel(host)
        host.texture:Hide()
        host.appliedFlip = nil
        host:Hide()
        return
    end

    local key = GlowRules.ResolveType(settings.GlowType)
    local style = GlowRules.STYLES[key] or GlowRules.STYLES.ants

    local read = GlowRules.ReadSpeed(settings, SPEED_KEYS)
    local frequency = GlowRules.NormaliseFrequency(read, MIN_FREQUENCY, MAX_FREQUENCY)
    local period = GlowRules.FrequencyToDuration(frequency)

    if style.kind == "pixel" then
        -- Every sheet-based layer is stopped, not merely hidden: a playing
        -- animation on a hidden texture still costs a C-side update.
        host.animGroup:Stop()
        host.texture:Hide()
        if host.overlay then
            host.overlay:Hide()
            host.overlayGroup:Stop()
        end
        -- Cleared so a later return to a flipbook style is seen as a change
        -- and restarts, rather than trusting state from before the switch.
        host.appliedFlip = nil

        ConfigurePixel(host, settings, period)
        host:SetShown(settings.GlowEnabled and true or false)
        return
    end

    HidePixel(host)

    local entry = ResolveEntry(settings)
    local texture = host.texture
    texture:Show()

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

    -- No in-client case mutates a PLAYING flipbook's grid or duration; every
    -- one sets them on a stopped group and plays it afterward. Restarting
    -- unconditionally on every reconfigure would stutter an unrelated change
    -- (icon size, colour), so the group is only stopped and replayed when
    -- something the flipbook itself reads actually differs. The TEXTURE SOURCE
    -- counts: two styles can share a grid, so comparing the grid alone reports
    -- "unchanged" across a sheet swap and the animation is never replayed.
    local wanted = GlowRules.FlipbookState(entry, period)

    local restarted = GlowRules.NeedsRestart(host.appliedFlip, wanted)

    if restarted then
        host.animGroup:Stop()
        host.flip:SetFlipBookRows(wanted.rows)
        host.flip:SetFlipBookColumns(wanted.columns)
        host.flip:SetFlipBookFrames(wanted.frames)
        host.flip:SetFlipBookFrameWidth(wanted.frameWidth)
        host.flip:SetFlipBookFrameHeight(wanted.frameHeight)
        host.flip:SetDuration(wanted.duration)
        host.animGroup:Play()
        host.appliedFlip = wanted
    end

    -- Without the desaturate the atlas keeps its own hue and the colour
    -- setting appears to do nothing on some sources.
    texture:SetDesaturated(true)
    local r, g, b, a = KE:ResolveColor(settings.GlowColor, { 0, 1, 0, 1 })
    texture:SetVertexColor(r, g, b, a)

    -- Atlas styles only. The alert sheet is already high-contrast and a
    -- doubled additive copy of it blows out to white.
    local overlay = host.overlay
    if overlay then
        if entry.atlas then
            overlay:SetSize(size, size)
            overlay:ClearAllPoints()
            overlay:SetPoint("CENTER", host, "CENTER", 0, 0)
            overlay:SetAtlas(entry.atlas, false)
            overlay:SetDesaturated(false)
            overlay:SetVertexColor(1, 1, 1, 1)
            overlay:SetAlpha(0.35)
            overlay:Show()

            -- Gated on the SAME predicate as the main texture so the two
            -- animations start together. Restarting one without the other
            -- leaves the highlight layer a frame or more out of phase, which
            -- reads as a double image.
            if restarted then
                host.overlayGroup:Stop()
                host.overlayFlip:SetFlipBookRows(wanted.rows)
                host.overlayFlip:SetFlipBookColumns(wanted.columns)
                host.overlayFlip:SetFlipBookFrames(wanted.frames)
                host.overlayFlip:SetFlipBookFrameWidth(wanted.frameWidth)
                host.overlayFlip:SetFlipBookFrameHeight(wanted.frameHeight)
                host.overlayFlip:SetDuration(wanted.duration)
                host.overlayGroup:Play()
            end
        else
            overlay:Hide()
            host.overlayGroup:Stop()
        end
    end

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

    host.texture   = texture
    host.animGroup = animGroup
    host.flip      = flip

    -- A desaturated, tinted atlas loses the artwork's own highlights. An
    -- untinted additive copy of the same animation restores them. Created
    -- here rather than lazily because this is the only window in which a
    -- child may be parented to an aura button.
    local overlay = host:CreateTexture(nil, "OVERLAY")
    overlay:SetBlendMode("ADD")
    local overlayGroup = overlay:CreateAnimationGroup()
    overlayGroup:SetLooping("REPEAT")
    local overlayFlip = overlayGroup:CreateAnimation("FlipBook")

    host.overlay      = overlay
    host.overlayGroup = overlayGroup
    host.overlayFlip  = overlayFlip

    -- Created here for the same reason as everything else on this host: this
    -- is the only window in which a child may be parented to an aura button.
    -- Four strips exist even while a flipbook style is selected; they are
    -- simply hidden. Allocating them lazily would mean allocating them after
    -- the window has closed, which is the mistake that retired this style.
    local dashes = {}
    for i = 1, 4 do
        local mask = host:CreateMaskTexture()
        mask:SetTexture(DASH_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")

        local strip = host:CreateTexture(nil, "OVERLAY")
        strip:AddMaskTexture(mask)

        local group = strip:CreateAnimationGroup()
        group:SetLooping("REPEAT")
        local move = group:CreateAnimation("Translation")
        move:SetSmoothing("NONE")

        dashes[i] = { mask = mask, strip = strip, group = group, move = move }
    end
    host.dashes = dashes

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

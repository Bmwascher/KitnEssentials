-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/Combat/AuraEngine/Style.lua                     ║
-- ║  Purpose: button dressing -- hosts, region registration,  ║
-- ║  and the duration formatter. Shared by live and preview.  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local math_floor = math.floor

local Style = {}
KE.AuraStyle = Style

-- The dispel badge is a fixed fraction of the icon, not a setting -- ported
-- from the modules this engine replaces. A field rather than a local so the
-- Edit Mode hitbox math can share this one definition instead of copying it.
Style.DISPEL_ICON_FRACTION = 0.40

---------------------------------------------------------------------------------
-- Duration formatter -- declarative data, not a callback. Wave 1 has neither
-- a ShowDecimalSeconds nor a ColorDurationUnderThreshold setting on either
-- display, so only the non-decimal breakpoint set is built and textColor is
-- never populated. Weak-keyed on the settings table: the same settings table
-- is reused for every reconfiguration of a display, so this rebuilds a
-- formatter once per settings table rather than once per button.
---------------------------------------------------------------------------------

local DurationFormatterCache = setmetatable({}, { __mode = "k" })

local function GetDurationFormatter(settings)
    local cached = DurationFormatterCache[settings]
    if cached then return cached end

    local formatter = C_StringUtil.CreateNumericRuleFormatter()
    formatter:SetBreakpoints({
        {
            threshold = 60,
            format    = "%dm",
            components = {
                { div = 60, step = 1, rounding = Enum.NumericRuleFormatRounding.Down },
            },
        },
        {
            threshold = 0,
            step      = 1,
            rounding  = Enum.NumericRuleFormatRounding.Up,
            format    = "%d",
        },
    })

    DurationFormatterCache[settings] = formatter
    return formatter
end

---------------------------------------------------------------------------------
-- Host creation -- called once, from initializeFrame, per Step 1's rule.
---------------------------------------------------------------------------------

-- Deliberately NOT KE:AddIconBorders. That helper registers every frame it
-- decorates into the weak-keyed KE._borderRegistry, and KE:ResnapAllBorders
-- later walks that registry reading frame.borders on UI_SCALE_CHANGED -- an
-- event that can fire while auras are secret, which would be a denied read
-- from tainted code at an arbitrary later moment.
--
-- The trade: a mid-fight UI-scale change leaves these borders unsnapped until
-- the next reconfiguration. That is the correct side to err on.
--
-- Fixed black, matching the plain border both modules being replaced draw
-- (their dispel-coloured decoration is a SEPARATE region, now the dispel
-- host below). Sized from settings.IconSize at creation; StyleAuraFrame
-- re-sizes on every reconfiguration the same way, in case IconSize changed.
function Style.CreateBorderHost(button, settings)
    local px   = KE:GetPixelSize()
    local size = settings.IconSize or 0

    local function MakeEdge(width, height)
        local tex = button:CreateTexture(nil, "OVERLAY", nil, 7)
        tex:SetColorTexture(0, 0, 0, 1)
        tex:SetTexelSnappingBias(0)
        tex:SetSnapToPixelGrid(false)
        tex:SetSize(width, height)
        return tex
    end

    local host = {
        top    = MakeEdge(size, px),
        bottom = MakeEdge(size, px),
        left   = MakeEdge(px, size),
        right  = MakeEdge(px, size),
    }
    host.top:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    host.bottom:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    host.left:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    host.right:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)

    return host
end

-- The dispel decoration: a texture (registered via AddDispelTypeTexture,
-- Blizzard's own vocabulary calls this the aura's "border" -- see the
-- deprecated SetAuraBorder alias) plus a fontstring (the colourblind-mode
-- symbol, aliased SetAuraSymbol). Both live on their own overlay frame so
-- their level can sit above the cooldown swipe (Step 2), and both take no
-- mouse input so decoration can never swallow a click or the tooltip.
--
-- Sized/fonted here at creation so the very first UpdateAuraDisplay (fired
-- from inside RegisterRegions's Set* calls, before StyleAuraFrame's first
-- pass) never calls SetText on a fontless string or SetPoint on a size-0
-- texture. StyleAuraFrame re-dresses both on every reconfiguration.
function Style.CreateDispelHost(button, settings)
    local host = CreateFrame("Frame", nil, button)
    host:SetAllPoints(button)
    host:EnableMouse(false)

    local size = math_floor((settings.IconSize or 0) * Style.DISPEL_ICON_FRACTION)

    local texture = host:CreateTexture(nil, "OVERLAY")
    texture:SetSize(size, size)
    texture:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)

    local text = host:CreateFontString(nil, "OVERLAY")
    KE:ApplyFontToText(text, settings.FontFace, settings.FontSize, settings.FontOutline)
    text:SetPoint("CENTER", texture, "CENTER", 0, 0)

    -- The dispel-coloured ring. Parented directly to the BUTTON, not the
    -- overlay host above -- sublevel only orders regions of the same frame,
    -- and this has to sit below CreateBorderHost's plain black edges
    -- (OVERLAY sublevel 7) rather than above them, which a higher frame
    -- level would force regardless of sublevel. Two-point corner-to-corner
    -- anchors, one pixel inset on every edge, with only the thin dimension
    -- given an explicit size -- that is what lets the ring track the
    -- button's real size instead of a size fixed at creation.
    local px      = KE:GetPixelSize()
    local innerPx = 2 * px

    local function MakeRingEdge()
        local tex = button:CreateTexture(nil, "OVERLAY", nil, 6)
        tex:SetTexelSnappingBias(0)
        -- White: the dispel-mode repaint tints via vertex colour, which
        -- multiplies against the texture's own colour, so anything but
        -- white here would darken or discolour the result.
        tex:SetColorTexture(1, 1, 1, 1)
        tex:SetSnapToPixelGrid(false)
        return tex
    end

    local ring = {
        top    = MakeRingEdge(),
        bottom = MakeRingEdge(),
        left   = MakeRingEdge(),
        right  = MakeRingEdge(),
    }

    ring.top:SetPoint("TOPLEFT", button, "TOPLEFT", px, -px)
    ring.top:SetPoint("TOPRIGHT", button, "TOPRIGHT", -px, -px)
    ring.top:SetHeight(innerPx)

    ring.bottom:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", px, px)
    ring.bottom:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -px, px)
    ring.bottom:SetHeight(innerPx)

    ring.left:SetPoint("TOPLEFT", button, "TOPLEFT", px, -px)
    ring.left:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", px, px)
    ring.left:SetWidth(innerPx)

    ring.right:SetPoint("TOPRIGHT", button, "TOPRIGHT", -px, -px)
    ring.right:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -px, px)
    ring.right:SetWidth(innerPx)

    host.texture = texture
    host.text    = text
    host.ring    = ring
    return host
end

-- initializeFrame is the only legally guaranteed window to parent a frame to
-- an aura button: DenyTaintedAccessWhenAurasAreSecret attaches the moment it
-- returns, and a host created later when a user flips a setting has no such
-- window.
--
-- The rule is per GROUP. Each AddAuraGroup builds its own frame provider from
-- its own callback, so a group creates the hosts ITS capabilities name and no
-- others -- that is how only the externals group gets a glow.
--
-- CreateRegions is shared with the PREVIEW path, which cannot register
-- anything. Keeping creation in one function is what lets both paths use the
-- same dressing function afterwards.
function Style.CreateRegions(frame, group, settings)
    local caps = group.capabilities or {}

    frame.keIcon = frame:CreateTexture(nil, "ARTWORK")
    frame.keIcon:SetAllPoints(frame)
    KE:ApplyIconZoom(frame.keIcon)

    frame.keCooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    frame.keCooldown:SetAllPoints(frame)
    frame.keCooldown:SetDrawEdge(false)
    frame.keCooldown:EnableMouse(false)
    -- Blizzard's built-in countdown numbers are superseded by the SEPARATE
    -- duration-text region below (registered via SetDurationText onto its
    -- own fontstring), so the cooldown widget's own numbers would double up
    -- with it if left visible.
    frame.keCooldown:SetHideCountdownNumbers(true)

    -- The count and timer live on their OWN overlay frame, not on the button.
    -- A FontString parented to the button sits at the button's frame level,
    -- so the cooldown swipe and the glow -- both child FRAMES at higher levels
    -- -- paint straight over it. This overlay is the +4 level the design names,
    -- and it takes no mouse input so it cannot steal the button's tooltip.
    frame.keTextOverlay = CreateFrame("Frame", nil, frame)
    frame.keTextOverlay:SetAllPoints(frame)
    frame.keTextOverlay:EnableMouse(false)

    frame.keCount = frame.keTextOverlay:CreateFontString(nil, "OVERLAY")
    frame.keCount:SetJustifyH("RIGHT")
    frame.keTimer = frame.keTextOverlay:CreateFontString(nil, "OVERLAY")

    -- Seeded here for the same reason as the dispel host's fontstring:
    -- RegisterRegions's Set* calls can trigger an immediate UpdateAuraDisplay,
    -- and SetText on a fontless string errors.
    KE:ApplyFontToText(frame.keCount, settings.FontFace, settings.FontSize, settings.FontOutline)
    KE:ApplyFontToText(frame.keTimer, settings.FontFace, settings.TimerFontSize, settings.FontOutline)
    if frame.keTimer.SetShadowOffset then frame.keTimer:SetShadowOffset(0, 0) end

    if caps.hasBorder then
        frame.keBorder = Style.CreateBorderHost(frame, settings)
    end
    if caps.hasDispel then
        frame.keDispel = Style.CreateDispelHost(frame, settings)
    end
    if caps.hasGlow then
        frame.keGlow = KE.AuraGlow.CreateHost(frame, settings)
    end

    -- Frame levels, off the button: cooldown +1, dispel overlay +2, glow +3,
    -- text overlay +4. Higher levels paint over lower ones regardless of
    -- creation order, which is what stops the swipe and the glow from
    -- covering the count/timer text.
    local baseLevel = frame:GetFrameLevel()
    frame.keCooldown:SetFrameLevel(baseLevel + 1)
    if frame.keDispel then frame.keDispel:SetFrameLevel(baseLevel + 2) end
    if frame.keGlow then frame.keGlow:SetFrameLevel(baseLevel + 3) end
    frame.keTextOverlay:SetFrameLevel(baseLevel + 4)
end

function Style.InitializeButton(button, display, group, settings)
    local caps = group.capabilities or {}

    Style.CreateRegions(button, group, settings)

    -- Tooltip policy, per button and LIVE ONLY. Both methods live on the aura
    -- BUTTON mixin; a plain preview frame has neither.
    button:SetMouseMotionEnabled(true)
    button:SetTooltipAnchorPoint("ANCHOR_BOTTOMLEFT")
    button:SetHideTooltipInCombat(false)

    Style.RegisterRegions(button, display, group, settings)
    Style.StyleAuraFrame(button, settings, caps)
    KE.AuraGlow.Apply(button, settings, caps)
end

-- The preview path: create and dress, never register.
function Style.InitializePreviewFrame(frame, _display, group, settings)
    local caps = group.capabilities or {}
    Style.CreateRegions(frame, group, settings)
    Style.StyleAuraFrame(frame, settings, caps)
    KE.AuraGlow.Apply(frame, settings, caps)
end

---------------------------------------------------------------------------------
-- Region registration -- IDEMPOTENT, and re-run on every reconfiguration.
-- Every registered region pairs with a clear on toggle-off, so an
-- unregistration is always reachable from an ordinary checkbox.
---------------------------------------------------------------------------------

function Style.RegisterRegions(button, _display, group, settings)
    if button.keIcon then
        button:SetIcon(button.keIcon)
    end

    -- "Swipe" gates the cooldown REGION itself, not just its visual: the
    -- registration must be reversible, so ClearDurationCooldown has to be
    -- reachable from the checkbox.
    if button.keCooldown then
        if settings.Swipe ~= false then
            button.keCooldown:Show()
            button:SetDurationCooldown(button.keCooldown)
        else
            button:ClearDurationCooldown()
            button.keCooldown:Clear()
            button.keCooldown:Hide()
        end
    end

    if button.keTimer then
        button:SetDurationText(button.keTimer, {
            textFormatter = GetDurationFormatter(settings),
            textColor     = nil,
        })
    end

    if button.keCount then
        button:SetApplicationCount(button.keCount)
    end

    -- List-shaped: clear before add, or a reconfiguration stacks a second
    -- dispel texture on top of the first.
    if button.keDispel then
        button:ClearDispelTypeTextures()

        -- Badge: Blizzard's built-in dispel atlases already carry their own
        -- colours, so no curve here -- the curve goes to the ring instead.
        button:AddDispelTypeTexture(button.keDispel.texture, {
            style = Enum.CustomAuraButtonDispelTypeTextureStyle.Icon,
        })
        button:SetDispelTypeText(button.keDispel.text, {})

        -- The ring is only a registered dispel texture in "dispel" mode, so
        -- Blizzard repaints it per aura. Any other mode paints it directly
        -- in StyleAuraFrame instead, so registering it here would fight
        -- that paint on every UpdateAuraDisplay.
        local ring = button.keDispel.ring
        if ring and settings.BorderColorMode == "dispel" then
            local ringOptions = {
                style = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset,
                -- The old ring never hid itself for an aura with no dispel
                -- type; this option is the only thing that reproduces that.
                showWithoutDispelType = true,
            }
            if group.getDispelColorCurve then
                ringOptions.customDispelColorCurve = group.getDispelColorCurve(settings)
            end
            button:AddDispelTypeTexture(ring.top, ringOptions)
            button:AddDispelTypeTexture(ring.bottom, ringOptions)
            button:AddDispelTypeTexture(ring.left, ringOptions)
            button:AddDispelTypeTexture(ring.right, ringOptions)
        end
    end
end

---------------------------------------------------------------------------------
-- Dressing -- everything a setting can change. Re-runnable on an existing
-- button; shared by the live and preview paths.
---------------------------------------------------------------------------------

function Style.StyleAuraFrame(frame, settings, capabilities)
    local caps = capabilities or {}

    -- Nothing else sizes an aura button. Blizzard's flow layout only anchors
    -- its elements, and the group layout's elementWidth feeds spacing
    -- arithmetic rather than the frame, so without this every SetAllPoints
    -- region collapses.
    local iconSize = settings.IconSize
    if iconSize then
        frame:SetSize(iconSize, iconSize)
    end

    if frame.keIcon then
        KE:ApplyIconZoom(frame.keIcon)
    end

    if frame.keCooldown then
        frame.keCooldown:SetReverse(settings.Reverse)
    end

    if frame.keCount then
        KE:ApplyFontToText(frame.keCount, settings.FontFace, settings.FontSize, settings.FontOutline)
        frame.keCount:ClearAllPoints()
        local sp = settings.StackPosition
        if sp then
            frame.keCount:SetPoint(sp.AnchorFrom, frame, sp.AnchorTo, sp.XOffset, sp.YOffset)
        else
            frame.keCount:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
        end
    end

    if frame.keTimer then
        KE:ApplyFontToText(frame.keTimer, settings.FontFace, settings.TimerFontSize, settings.FontOutline)
        if frame.keTimer.SetShadowOffset then frame.keTimer:SetShadowOffset(0, 0) end
        frame.keTimer:ClearAllPoints()
        local tp = settings.TimerPosition
        if tp then
            frame.keTimer:SetPoint(tp.AnchorFrom, frame, tp.AnchorTo, tp.XOffset, tp.YOffset)
        end
    end

    if caps.hasBorder and frame.keBorder then
        local px   = KE:GetPixelSize()
        local size = settings.IconSize or 0
        local host = frame.keBorder

        host.top:SetSize(size, px)
        host.bottom:SetSize(size, px)
        host.left:SetSize(px, size)
        host.right:SetSize(px, size)

        host.top:ClearAllPoints();    host.top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        host.bottom:ClearAllPoints(); host.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        host.left:ClearAllPoints();   host.left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        host.right:ClearAllPoints();  host.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    end

    if caps.hasDispel and frame.keDispel then
        local size = math_floor((settings.IconSize or 0) * Style.DISPEL_ICON_FRACTION)
        local tex  = frame.keDispel.texture
        tex:SetSize(size, size)
        tex:ClearAllPoints()
        local dp = settings.DispelPosition
        if dp then
            tex:SetPoint(dp.AnchorFrom, frame, dp.AnchorTo, dp.XOffset, dp.YOffset)
        else
            tex:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        end

        local text = frame.keDispel.text
        KE:ApplyFontToText(text, settings.FontFace, settings.FontSize, settings.FontOutline)
        text:ClearAllPoints()
        text:SetPoint("CENTER", tex, "CENTER", 0, 0)

        local ring = frame.keDispel.ring
        if ring then
            local px      = KE:GetPixelSize()
            local innerPx = 2 * px

            ring.top:ClearAllPoints()
            ring.top:SetPoint("TOPLEFT", frame, "TOPLEFT", px, -px)
            ring.top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -px, -px)
            ring.top:SetHeight(innerPx)

            ring.bottom:ClearAllPoints()
            ring.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", px, px)
            ring.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -px, px)
            ring.bottom:SetHeight(innerPx)

            ring.left:ClearAllPoints()
            ring.left:SetPoint("TOPLEFT", frame, "TOPLEFT", px, -px)
            ring.left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", px, px)
            ring.left:SetWidth(innerPx)

            ring.right:ClearAllPoints()
            ring.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -px, -px)
            ring.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -px, px)
            ring.right:SetWidth(innerPx)

            -- Colour: "dispel" mode is Blizzard's to paint, via the vertex
            -- tint RegisterRegions wires up -- kept white here so that tint
            -- is never multiplied against a colour of ours. Any other mode
            -- paints the flat setting directly, the same final fallback the
            -- module this engine replaces used.
            local r, g, b, a
            if settings.BorderColorMode == "dispel" then
                r, g, b, a = 1, 1, 1, 1
            else
                r, g, b, a = KE:ResolveColor(settings.BorderColor, { 0.8, 0, 0, 1 })
            end
            ring.top:SetColorTexture(r, g, b, a);    ring.top:SetSnapToPixelGrid(false)
            ring.bottom:SetColorTexture(r, g, b, a); ring.bottom:SetSnapToPixelGrid(false)
            ring.left:SetColorTexture(r, g, b, a);   ring.left:SetSnapToPixelGrid(false)
            ring.right:SetColorTexture(r, g, b, a);  ring.right:SetSnapToPixelGrid(false)
        end
    end
end

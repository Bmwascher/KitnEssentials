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
-- from the modules this engine replaces.
local DISPEL_ICON_FRACTION = 0.40

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
            rounding  = Enum.NumericRuleFormatRounding.Down,
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

    local size = math_floor((settings.IconSize or 0) * DISPEL_ICON_FRACTION)

    local texture = host:CreateTexture(nil, "OVERLAY")
    texture:SetSize(size, size)
    texture:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)

    local text = host:CreateFontString(nil, "OVERLAY")
    KE:ApplyFontToText(text, settings.FontFace, settings.FontSize, settings.FontOutline)
    text:SetPoint("CENTER", texture, "CENTER", 0, 0)

    host.texture = texture
    host.text    = text
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

    -- "Swipe" gates the cooldown REGION itself, not just its visual: a
    -- button toggled off must be reachable from the checkbox again later,
    -- which a plain SetDrawSwipe(false) on an always-registered cooldown
    -- would not by itself guarantee reflects registration state.
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

        local options = { style = Enum.CustomAuraButtonDispelTypeTextureStyle.Icon }
        if group.getDispelColorCurve then
            options.customDispelColorCurve = group.getDispelColorCurve(settings)
        end
        button:AddDispelTypeTexture(button.keDispel.texture, options)
        button:SetDispelTypeText(button.keDispel.text, {})
    end
end

---------------------------------------------------------------------------------
-- Dressing -- everything a setting can change. Re-runnable on an existing
-- button; shared by the live and preview paths.
---------------------------------------------------------------------------------

function Style.StyleAuraFrame(frame, settings, capabilities)
    local caps = capabilities or {}

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
        local size = math_floor((settings.IconSize or 0) * DISPEL_ICON_FRACTION)
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
    end
end

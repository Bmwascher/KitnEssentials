-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/QoL/Campfire/CampfireViews.lua                  ║
-- ║  Purpose: Campfire's Round, Simple and alert frames.     ║
-- ║           Draws one render table and reads no auras.     ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local Rules = KE.CampfireRules

local C_ChatInfo = C_ChatInfo
local C_DurationUtil = C_DurationUtil
local C_StringUtil = C_StringUtil
local CreateFrame = CreateFrame
local Enum = Enum
local GameTooltip = GameTooltip
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local UIParent = UIParent
local ceil, max = math.ceil, math.max
local format = string.format
local ipairs = ipairs

local Views = {}
KE.CampfireViews = Views

-- Every frame sits on UIParent whatever a profile says: the buttons compute
-- coordinates from these frames, and UIParent's anchoring is never secret.
local PLACEMENT = { anchorFrameType = "UIPARENT", ParentFrame = "UIParent" }

local MEDIA = "Interface\\AddOns\\KitnEssentials\\Media\\Campfire\\"
local ART, RING, MASK = MEDIA .. "campfire.tga", MEDIA .. "ring.tga", MEDIA .. "mask.tga"
local CLAMP = "CLAMPTOBLACKADDITIVE"
local WHITE_TEX = "Interface\\Buttons\\WHITE8X8"

local TRACK_OUT, DRAIN_OUT = 6, 5
Views.TRACK_OUT = TRACK_OUT
local LIST_GAP, LINE_HEIGHT, CHECK_GAP = 12, 18, 5
local DOT_SIZE, DOT_GAP = 10, 4
local LABEL_DROP = TRACK_OUT + 3
local SIMPLE_FIRE, SIMPLE_LABEL_X, SIMPLE_GAP, SIMPLE_TIME_PAD, SIMPLE_TIME_GAP = 18, 29, 10, 10, 12
local ALERT_HEIGHT, ALERT_FIRE, ALERT_GAP = 36, 25, 6
local PANEL_DROP, PANEL_PAD = 4, 6
local GRAY_ALPHA, DIM_ALPHA, HOT_ALPHA = 0.7, 0.6, 0.45
local LANDING_DELAY, LANDING_FADE = 5, 0.4
Views.LANDING_TIME = LANDING_DELAY + LANDING_FADE
local ALERT_IN, ALERT_OUT, ALERT_BREATHE, ALERT_BREATHE_TO = 0.3, 0.4, 0.8, 0.6
local SHOW_MINUTES_FROM, SHOW_HOURS_FROM = 90, 5400

local PLATE = { 0.14, 0.15, 0.16 }
local KEY_COLORS = {
    good = { 0.29, 0.87, 0.5 },
    warn = { 0.98, 0.8, 0.08 },
    bad = { 0.97, 0.27, 0.27 },
}
local MUTED = { 0.604, 0.62, 0.651 }
local LABEL_COLORS = { soft = { 0.435, 0.839, 1 }, muted = MUTED, green = KEY_COLORS.good }
local MUTED_CODE, GREEN_CODE, WHITE_CODE = "|cff9a9ea6", "|cff4ade80", "|cffffffff"

local fontVersion = 0
local plainFormat, seatedFormat

local function Colored(code, text)
    return code .. text .. "|r"
end

function Views.Muted(text) return Colored(MUTED_CODE, text) end
function Views.Green(text) return Colored(GREEN_CODE, text) end
function Views.White(text) return Colored(WHITE_CODE, text) end

local function KeyColor(key)
    if key == "seated" then return KE:GetAccentColor("theme") end
    local color = KEY_COLORS[key]
    return color[1], color[2], color[3]
end

local function LineText(line, showKept)
    local row = line.row
    local text, head, name = Rules.Label(row.feature, row.amounts[1])
    if line.style == "new" then return Colored(GREEN_CODE, text) end
    if line.style == "dim" then return Colored(MUTED_CODE, text) end
    if line.style == "kept" then return Colored(MUTED_CODE, showKept and (text .. " kept") or text) end
    if head then return Colored(WHITE_CODE, head) .. " " .. Colored(MUTED_CODE, name) end
    return Colored(MUTED_CODE, name)
end

local function LineAlpha(line)
    return line.style == "dim" and DIM_ALPHA or 1
end

---------------------------------------------------------------------------------
-- Timers
---------------------------------------------------------------------------------

local function NewFormatter(prefix)
    local up = Enum.NumericRuleFormatRounding.Up
    local formatter = C_StringUtil.CreateNumericRuleFormatter()
    -- Rounded after the division, so 661 seconds reads 12m, as the alert does.
    formatter:SetBreakpoints({
        { threshold = 0, format = prefix .. "%ds", step = 1, rounding = up },
        { threshold = SHOW_MINUTES_FROM, format = prefix .. "%dm",
            components = { { div = 60, step = 1, rounding = up } } },
        { threshold = SHOW_HOURS_FROM, format = prefix .. "%dh",
            components = { { div = 3600, step = 1, rounding = up } } },
    })
    return formatter
end

local function NewBinding(fontString, duration)
    local binding = C_DurationUtil.CreateDurationTextBinding()
    binding:SetFontString(fontString)
    binding:SetDuration(duration)
    binding:SetFormatter(plainFormat)
    binding:SetZeroDurationText("")
    binding:SetExpiredText("")
    binding:SetEnabled(false)
    return binding
end

local function SetTimeText(f, r, formatter)
    if f.timeExpiry == r.expiry and f.timeSeated == r.seated then return end
    f.timeExpiry, f.timeSeated = r.expiry, r.seated
    if r.expiry then
        f.dur:SetTimeFromEnd(r.expiry, r.duration)
        f.binding:SetFormatter(formatter)
        f.binding:SetEnabled(true)
    else
        f.binding:SetEnabled(false)
        f.time:SetText("")
    end
end

local function ShortTime(seconds)
    if seconds < SHOW_MINUTES_FROM then return format("%ds", ceil(seconds)) end
    if seconds < SHOW_HOURS_FROM then return format("%dm", ceil(seconds / 60)) end
    return format("%dh", ceil(seconds / 3600))
end

---------------------------------------------------------------------------------
-- Tooltip and click to sit
---------------------------------------------------------------------------------

local function ShowTip(owner)
    local r = Views.last
    if not r then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if not r.buffUp and not r.seated then
        GameTooltip:SetText("No Camp Benefits", 1, 1, 1)
        if r.near then GameTooltip:AddLine("A campfire is in range", MUTED[1], MUTED[2], MUTED[3]) end
        GameTooltip:Show()
        return
    end
    GameTooltip:SetText("Camp Benefits", 1, 1, 1)
    if r.seated and r.expiry then
        GameTooltip:AddDoubleLine("Resting", "in " .. ShortTime(max(r.expiry - GetTime(), 0)),
            1, 1, 1, MUTED[1], MUTED[2], MUTED[3])
    end
    for _, line in ipairs(r.lines or {}) do
        local feature = line.row.feature
        local detail = feature.name or ""
        if line.coverer then
            detail = (detail ~= "" and (detail .. ", ") or "") .. "covered by " .. line.coverer
        end
        GameTooltip:AddDoubleLine(Rules.Words(feature, line.row.amounts), detail,
            1, 1, 1, MUTED[1], MUTED[2], MUTED[3])
    end
    GameTooltip:Show()
end

local function HideTip()
    GameTooltip:Hide()
end

local function NewTip(parent, region, level)
    local tip = CreateFrame("Frame", nil, parent)
    tip:SetAllPoints(region)
    tip:SetFrameLevel(level)
    tip:EnableMouseMotion(true)
    tip:SetScript("OnEnter", ShowTip)
    tip:SetScript("OnLeave", HideTip)
    return tip
end

local function SitDown(_, button)
    if button == "LeftButton" and not InCombatLockdown() then
        C_ChatInfo.PerformEmote("SIT")
    end
end

-- A plain button: it shows only while a click would sit, so every other click
-- passes through the shape to the world.
local function NewSit(parent, region, hot, level, withTip)
    local sit = CreateFrame("Button", nil, parent)
    sit:SetAllPoints(region)
    sit:SetFrameLevel(level)
    sit:RegisterForClicks("LeftButtonUp")
    sit:SetScript("OnClick", SitDown)
    sit:SetScript("OnEnter", function(self)
        hot:Show()
        if withTip then ShowTip(self) end
    end)
    sit:SetScript("OnLeave", function()
        hot:Hide()
        if withTip then HideTip() end
    end)
    sit:SetScript("OnHide", function() hot:Hide() end)
    sit:Hide()
    return sit
end

local function NewFire(parent, layer, sublevel)
    local tex = parent:CreateTexture(nil, layer, nil, sublevel)
    tex:SetTexture(ART, "CLAMP", "CLAMP", "TRILINEAR")
    return tex
end

---------------------------------------------------------------------------------
-- Pools
---------------------------------------------------------------------------------

local function AcquireText(parent, pool, index, db, size)
    local fs = pool[index]
    if not fs then
        fs = parent:CreateFontString(nil, "OVERLAY")
        fs:SetWordWrap(false)
        pool[index] = fs
    end
    if fs.fontVersion ~= fontVersion or fs.fontSize ~= size then
        KE:ApplyFontToText(fs, db.FontFace, size, db.FontOutline)
        fs.fontVersion, fs.fontSize = fontVersion, size
    end
    fs:Show()
    return fs
end

local function HideTexts(pool, from)
    for index = from, #pool do pool[index]:Hide() end
end

local function AcquireDot(parent, pool, index)
    local dot = pool[index]
    if not dot then
        dot = {}
        dot.ring = parent:CreateTexture(nil, "ARTWORK")
        dot.ring:SetTexture(RING)
        dot.ring:SetSize(DOT_SIZE, DOT_SIZE)
        dot.fill = parent:CreateTexture(nil, "ARTWORK", nil, 1)
        dot.fill:SetTexture(MASK)
        pool[index] = dot
    end
    dot.ring:Show()
    return dot
end

local function HideDots(pool, from)
    for index = from, #pool do
        pool[index].ring:Hide()
        pool[index].fill:Hide()
    end
end

local function SetDotState(dot, state)
    local color = LABEL_COLORS.soft
    dot.fill:ClearAllPoints()
    dot.fill:SetPoint("LEFT", dot.ring, "LEFT", 0, 0)
    dot.fill:SetVertexColor(color[1], color[2], color[3], 1)
    if state == "on" then
        dot.fill:SetSize(DOT_SIZE, DOT_SIZE)
        dot.fill:SetTexCoord(0, 1, 0, 1)
        dot.fill:Show()
    elseif state == "part" then
        dot.fill:SetSize(DOT_SIZE / 2, DOT_SIZE)
        dot.fill:SetTexCoord(0, 0.5, 0, 1)
        dot.fill:Show()
    else
        dot.fill:Hide()
    end
end

local function DotText(entry)
    local text = entry.state == "off" and Colored(MUTED_CODE, entry.name) or Colored(WHITE_CODE, entry.name)
    if entry.note then text = text .. " " .. Colored(MUTED_CODE, entry.note) end
    return text
end

---------------------------------------------------------------------------------
-- Landing
---------------------------------------------------------------------------------

local function NewLanding(f)
    local group = f:CreateAnimationGroup()
    local fade = group:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetStartDelay(LANDING_DELAY)
    fade:SetDuration(LANDING_FADE)
    group:SetToFinalAlpha(true)
    group:SetScript("OnFinished", function()
        if Views.owner then Views.owner:OnLandingFinished() end
    end)
    return group
end

local function ApplyLanding(f, r, baseAlpha)
    if r.landingToken then
        if f.landingToken ~= r.landingToken then
            f.landingToken = r.landingToken
            f.landing:Stop()
            f:SetAlpha(1)
            f.landing:Play()
        end
        return
    end
    if f.landing:IsPlaying() then f.landing:Stop() end
    f.landingToken = nil
    f:SetAlpha(baseAlpha)
end

---------------------------------------------------------------------------------
-- Round
---------------------------------------------------------------------------------

local function BuildRound()
    local f = CreateFrame("Frame", "KE_CampfireRound", UIParent)
    f:Hide()
    local level = f:GetFrameLevel()

    f.track = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    f.track:SetPoint("TOPLEFT", f, "TOPLEFT", -TRACK_OUT, TRACK_OUT)
    f.track:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", TRACK_OUT, -TRACK_OUT)
    f.track:SetTexture(MASK)
    f.track:SetVertexColor(0, 0, 0, 1)

    f.edge = f:CreateTexture(nil, "BACKGROUND", nil, 0)
    f.edge:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
    f.edge:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
    f.edge:SetTexture(MASK)
    f.edge:SetVertexColor(0, 0, 0, 1)

    local mask = f:CreateMaskTexture()
    mask:SetAllPoints(f)
    mask:SetTexture(MASK, CLAMP, CLAMP)

    f.plate = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.plate:SetAllPoints(f)
    f.plate:SetColorTexture(PLATE[1], PLATE[2], PLATE[3], 1)
    f.plate:AddMaskTexture(mask)

    f.gray = NewFire(f, "ARTWORK", 0)
    f.gray:SetAllPoints(f)
    f.gray:SetDesaturated(true)
    f.gray:AddMaskTexture(mask)

    f.lit = NewFire(f, "ARTWORK", 1)
    f.lit:SetAllPoints(f)
    f.lit:AddMaskTexture(mask)

    f.hot = NewFire(f, "OVERLAY")
    f.hot:SetAllPoints(f)
    f.hot:SetBlendMode("ADD")
    f.hot:SetAlpha(HOT_ALPHA)
    f.hot:AddMaskTexture(mask)
    f.hot:Hide()

    f.catch = f.lit:CreateAnimationGroup()
    f.catchAlpha = f.catch:CreateAnimation("Alpha")
    f.catch:SetToFinalAlpha(true)

    f.full = f:CreateTexture(nil, "BORDER")
    f.full:SetPoint("TOPLEFT", f, "TOPLEFT", -DRAIN_OUT, DRAIN_OUT)
    f.full:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", DRAIN_OUT, -DRAIN_OUT)
    f.full:SetTexture(RING)
    f.full:Hide()

    f.drain = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.drain:SetPoint("TOPLEFT", f, "TOPLEFT", -DRAIN_OUT, DRAIN_OUT)
    f.drain:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", DRAIN_OUT, -DRAIN_OUT)
    f.drain:EnableMouse(false)
    f.drain:SetSwipeTexture(RING, 1, 1, 1, 1)
    f.drain:SetDrawEdge(false)
    f.drain:SetDrawBling(false)
    f.drain:SetHideCountdownNumbers(true)
    f.drain:SetFrameLevel(level + 1)
    f.drain:Hide()

    local host = CreateFrame("Frame", nil, f)
    host:SetAllPoints(f)
    host:SetFrameLevel(level + 2)
    f.time = host:CreateFontString(nil, "OVERLAY")
    f.time:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.label = host:CreateFontString(nil, "OVERLAY")
    f.label:SetPoint("TOP", f, "BOTTOM", 0, -LABEL_DROP)

    f.dur = C_DurationUtil.CreateDuration()
    f.binding = NewBinding(f.time, f.dur)
    f.landing = NewLanding(f)

    f.list = CreateFrame("Frame", nil, f)
    f.list:SetFrameLevel(level + 2)
    f.list:Hide()
    f.list.lines = {}
    f.list.dots = {}
    f.list.dotTexts = {}

    f.tip = NewTip(f, f, level + 3)
    f.sit = NewSit(f, f, f.hot, level + 4, true)
    return f
end

local function LayoutRoundList(f, r, db)
    local list = f.list
    if not r.showList then
        list:Hide()
        return
    end
    local size = db.ListTextSize
    local right = db.ListSide ~= "LEFT"
    local point = right and "TOPLEFT" or "TOPRIGHT"
    local justify = right and "LEFT" or "RIGHT"

    list:ClearAllPoints()
    if right then
        list:SetPoint("LEFT", f, "RIGHT", TRACK_OUT + LIST_GAP, 0)
    else
        list:SetPoint("RIGHT", f, "LEFT", -(TRACK_OUT + LIST_GAP), 0)
    end

    local used, y, width = 0, 0, 0
    for _, line in ipairs(r.lines) do
        used = used + 1
        local fs = AcquireText(list, list.lines, used, db, size)
        fs:ClearAllPoints()
        fs:SetPoint(point, list, point, 0, -y)
        fs:SetJustifyH(justify)
        fs:SetAlpha(LineAlpha(line))
        fs:SetText(LineText(line, true))
        width = max(width, fs:GetStringWidth())
        y = y + LINE_HEIGHT
    end
    HideTexts(list.lines, used + 1)

    local dots = r.dots
    local dotCount = dots and #dots or 0
    if dotCount > 0 and y > 0 then y = y + CHECK_GAP end
    for index = 1, dotCount do
        local entry = dots[index]
        local dot = AcquireDot(list, list.dots, index)
        dot.ring:ClearAllPoints()
        dot.ring:SetPoint(point, list, point, 0, -(y + (LINE_HEIGHT - DOT_SIZE) / 2))
        SetDotState(dot, entry.state)
        local fs = AcquireText(list, list.dotTexts, index, db, size)
        fs:ClearAllPoints()
        fs:SetPoint(point, list, point, right and (DOT_SIZE + DOT_GAP) or -(DOT_SIZE + DOT_GAP), -y)
        fs:SetJustifyH(justify)
        fs:SetText(DotText(entry))
        width = max(width, DOT_SIZE + DOT_GAP + fs:GetStringWidth())
        y = y + LINE_HEIGHT
    end
    HideDots(list.dots, dotCount + 1)
    HideTexts(list.dotTexts, dotCount + 1)

    list:SetSize(max(width, 1), max(y, 1))
    list:Show()
end

local function RenderRoundFire(f, r)
    f.lit:SetShown(r.fire ~= "gray")
    if r.fire == "catching" and r.expiry then
        if f.catchExpiry ~= r.expiry then
            f.catchExpiry = r.expiry
            f.catch:Stop()
            f.catchAlpha:SetFromAlpha(r.share)
            f.catchAlpha:SetToAlpha(1)
            f.catchAlpha:SetDuration(max(r.left, 0.1))
            f.catch:Play()
        end
    else
        if f.catch:IsPlaying() then f.catch:Stop() end
        f.catchExpiry = nil
        f.lit:SetAlpha(1)
    end
end

local function RenderRoundRing(f, r)
    f.track:SetShown(r.expiry ~= nil or r.fullRing == true)
    if r.fullRing then
        local good = KEY_COLORS.good
        f.full:SetVertexColor(good[1], good[2], good[3], 1)
        f.full:Show()
        f.drain:Hide()
        f.ringExpiry, f.ringSeated = nil, nil
        return
    end
    f.full:Hide()
    if not r.expiry then
        f.drain:Hide()
        f.ringExpiry, f.ringSeated = nil, nil
        return
    end
    local cr, cg, cb = KeyColor(r.colorKey)
    f.drain:SetSwipeColor(cr, cg, cb, 1)
    if f.ringExpiry ~= r.expiry or f.ringSeated ~= r.seated then
        f.ringExpiry, f.ringSeated = r.expiry, r.seated
        f.drain:SetReverse(r.seated == true)
        f.drain:SetCooldownFromExpirationTime(r.expiry, r.duration)
    end
    f.drain:Show()
end

local function RenderRound(r, db)
    local f = Views.round
    f:Show()
    ApplyLanding(f, r, r.fire == "gray" and GRAY_ALPHA or 1)
    RenderRoundFire(f, r)
    RenderRoundRing(f, r)
    SetTimeText(f, r, plainFormat)
    if r.label then
        local color = LABEL_COLORS[r.labelColor]
        f.label:SetTextColor(color[1], color[2], color[3], 1)
        f.label:SetText(r.label)
        f.label:Show()
    else
        f.label:Hide()
    end
    LayoutRoundList(f, r, db)
    f.sit:SetShown(r.clickable)
end

local function StopRound()
    local f = Views.round
    if f.landing:IsPlaying() then f.landing:Stop() end
    f.landingToken = nil
    if f.catch:IsPlaying() then f.catch:Stop() end
    f.catchExpiry = nil
    f.binding:SetEnabled(false)
    f.timeExpiry, f.timeSeated, f.ringExpiry, f.ringSeated = nil, nil, nil, nil
    f.drain:Hide()
    f.list:Hide()
    f:Hide()
end

---------------------------------------------------------------------------------
-- Simple
---------------------------------------------------------------------------------

local function BuildSimple()
    local f = CreateFrame("Frame", "KE_CampfireSimple", UIParent, "BackdropTemplate")
    f:Hide()
    f:SetBackdrop({ bgFile = WHITE_TEX, edgeFile = WHITE_TEX, edgeSize = 1 })
    local level = f:GetFrameLevel()

    f.fire = NewFire(f, "ARTWORK")
    f.fire:SetSize(SIMPLE_FIRE, SIMPLE_FIRE)
    f.hot = NewFire(f, "OVERLAY")
    f.hot:SetAllPoints(f.fire)
    f.hot:SetBlendMode("ADD")
    f.hot:SetAlpha(HOT_ALPHA)
    f.hot:Hide()

    f.time = f:CreateFontString(nil, "OVERLAY")
    f.time:SetPoint("RIGHT", f, "RIGHT", -SIMPLE_TIME_PAD, 1)
    f.measure = f:CreateFontString(nil, "OVERLAY")
    f.measure:SetAlpha(0)
    f.measure:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.more = f:CreateFontString(nil, "OVERLAY")
    f.labels = {}

    f.bar = CreateFrame("StatusBar", nil, f)
    f.bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
    f.bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    f.bar:SetHeight(2)
    f.bar:SetStatusBarTexture(WHITE_TEX)
    f.bar:SetMinMaxValues(0, 1)
    f.bar:Hide()

    f.dur = C_DurationUtil.CreateDuration()
    f.binding = NewBinding(f.time, f.dur)
    f.landing = NewLanding(f)

    f.panel = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.panel:SetBackdrop({ bgFile = WHITE_TEX, edgeFile = WHITE_TEX, edgeSize = 1 })
    f.panel:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -PANEL_DROP)
    f.panel.head = f.panel:CreateFontString(nil, "OVERLAY")
    f.panel.head:SetPoint("TOPLEFT", f.panel, "TOPLEFT", PANEL_PAD, -PANEL_PAD)
    f.panel.dots = {}
    f.panel.texts = {}
    f.panel:Hide()

    f.tip = NewTip(f, f, level + 3)
    f.sit = NewSit(f, f.fire, f.hot, level + 4, true)
    return f
end

local function SimpleTimeColor(key)
    if key == "good" then return 1, 1, 1 end
    return KeyColor(key)
end

local function LayoutSimpleLabels(f, r, db)
    local size = db.SimpleTextSize
    local labels = f.labels
    local lines = r.simpleLines
    local limit = db.SimpleWidth - SIMPLE_TIME_PAD
    if r.expiry then
        f.measure:SetText(r.seated and "in 88m" or "88m")
        limit = limit - f.measure:GetStringWidth() - SIMPLE_TIME_GAP
    end

    local x, used = SIMPLE_LABEL_X, 0
    if r.simpleHead then
        used = 1
        local fs = AcquireText(f, labels, used, db, size)
        fs:SetAlpha(1)
        fs:SetText(r.simpleHead)
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", f, "LEFT", x, 1)
        x = x + fs:GetStringWidth() + SIMPLE_GAP
    end

    local total = x
    for index, line in ipairs(lines) do
        local fs = AcquireText(f, labels, used + index, db, size)
        fs:SetAlpha(LineAlpha(line))
        fs:SetText(LineText(line, false))
        total = total + fs:GetStringWidth() + SIMPLE_GAP
    end

    local reserve = 0
    f.more:SetText(Colored(MUTED_CODE, "+" .. #lines .. " more"))
    if total - SIMPLE_GAP > limit then reserve = f.more:GetStringWidth() + SIMPLE_GAP end

    local shown = 0
    for index = 1, #lines do
        local fs = labels[used + index]
        local width = fs:GetStringWidth()
        if x + width + reserve > limit then break end
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", f, "LEFT", x, 1)
        x = x + width + SIMPLE_GAP
        shown = index
    end
    HideTexts(labels, used + shown + 1)

    if shown < #lines then
        f.more:SetText(Colored(MUTED_CODE, "+" .. (#lines - shown) .. " more"))
        f.more:ClearAllPoints()
        f.more:SetPoint("LEFT", f, "LEFT", x, 1)
        f.more:Show()
    else
        f.more:Hide()
    end
end

local function LayoutSimplePanel(f, r, db)
    local panel = f.panel
    local dots = r.panel
    if not dots then
        panel:Hide()
        return
    end
    local size = db.SimpleTextSize
    panel.head:SetText(Colored(MUTED_CODE, "Also stacks"))
    local y = PANEL_PAD + LINE_HEIGHT
    local width = panel.head:GetStringWidth()
    local count = 0
    -- The first dot is Camp Benefits, which the bar above already shows.
    for index = 2, #dots do
        count = count + 1
        local entry = dots[index]
        local dot = AcquireDot(panel, panel.dots, count)
        dot.ring:ClearAllPoints()
        dot.ring:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_PAD, -(y + (LINE_HEIGHT - DOT_SIZE) / 2))
        SetDotState(dot, entry.state)
        local fs = AcquireText(panel, panel.texts, count, db, size)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_PAD + DOT_SIZE + DOT_GAP, -y)
        fs:SetText(DotText(entry))
        width = max(width, DOT_SIZE + DOT_GAP + fs:GetStringWidth())
        y = y + LINE_HEIGHT
    end
    HideDots(panel.dots, count + 1)
    HideTexts(panel.texts, count + 1)
    panel:SetSize(width + PANEL_PAD * 2, y + PANEL_PAD)
    panel:Show()
end

local function RenderSimpleTimer(f, r)
    SetTimeText(f, r, r.seated and seatedFormat or plainFormat)
    if not r.expiry then
        f.bar:Hide()
        f.barExpiry = nil
        return
    end
    local cr, cg, cb = KeyColor(r.colorKey)
    f.bar:SetStatusBarColor(cr, cg, cb, 1)
    f.time:SetTextColor(SimpleTimeColor(r.colorKey))
    if f.barExpiry ~= r.expiry or f.barSeated ~= r.seated then
        f.barExpiry, f.barSeated = r.expiry, r.seated
        local direction = r.seated and Enum.StatusBarTimerDirection.ElapsedTime
            or Enum.StatusBarTimerDirection.RemainingTime
        f.bar:SetTimerDuration(f.dur, Enum.StatusBarInterpolation.Immediate, direction)
    end
    f.bar:Show()
end

local function RenderSimple(r, db)
    local f = Views.simple
    local bg = KE.Theme.bgDark
    f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
    f:SetBackdropBorderColor(0, 0, 0, 1)
    f.panel:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
    f.panel:SetBackdropBorderColor(0, 0, 0, 1)
    f:Show()
    ApplyLanding(f, r, 1)
    f.fire:SetDesaturated(r.fire == "gray")
    RenderSimpleTimer(f, r)
    LayoutSimpleLabels(f, r, db)
    LayoutSimplePanel(f, r, db)
    f.sit:SetShown(r.clickable)
end

local function StopSimple()
    local f = Views.simple
    if f.landing:IsPlaying() then f.landing:Stop() end
    f.landingToken = nil
    f.binding:SetEnabled(false)
    f.timeExpiry, f.timeSeated = nil, nil
    if f.barExpiry then
        f.dur:SetTimeFromStart(GetTime() - 1, 1)
        f.bar:SetTimerDuration(f.dur, Enum.StatusBarInterpolation.Immediate,
            Enum.StatusBarTimerDirection.RemainingTime)
    end
    f.barExpiry, f.barSeated = nil, nil
    f.panel:Hide()
    f:Hide()
end

---------------------------------------------------------------------------------
-- Alert
---------------------------------------------------------------------------------

local function NewAlertFade(f, from, to, duration)
    local group = f:CreateAnimationGroup()
    local fade = group:CreateAnimation("Alpha")
    fade:SetFromAlpha(from)
    fade:SetToAlpha(to)
    fade:SetDuration(duration)
    group:SetToFinalAlpha(true)
    return group
end

local function BuildAlert()
    local f = CreateFrame("Frame", "KE_CampfireAlert", UIParent)
    f:SetSize(ALERT_FIRE, ALERT_HEIGHT)
    f:Hide()
    local level = f:GetFrameLevel()

    f.catcher = CreateFrame("Frame", nil, f)
    f.catcher:SetAllPoints(f)
    f.catcher:SetFrameLevel(level + 1)
    f.catcher:EnableMouse(false)
    f.catcher:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and Views.owner then Views.owner:DismissAlert() end
    end)

    f.body = CreateFrame("Frame", nil, f)
    f.body:SetAllPoints(f)
    f.body:SetFrameLevel(level + 2)

    f.fire = NewFire(f.body, "ARTWORK")
    f.fire:SetSize(ALERT_FIRE, ALERT_FIRE)
    f.fire:SetPoint("LEFT", f.body, "LEFT", 0, 0)
    f.hot = NewFire(f.body, "OVERLAY")
    f.hot:SetAllPoints(f.fire)
    f.hot:SetBlendMode("ADD")
    f.hot:SetAlpha(HOT_ALPHA)
    f.hot:Hide()

    f.text = f.body:CreateFontString(nil, "OVERLAY")
    f.text:SetPoint("LEFT", f.fire, "RIGHT", ALERT_GAP, 0)

    f.fadeIn = NewAlertFade(f, 0, 1, ALERT_IN)
    f.fadeOut = NewAlertFade(f, 1, 0, ALERT_OUT)
    f.fadeOut:SetScript("OnFinished", function() f:Hide() end)
    f.breathe = f.body:CreateAnimationGroup()
    local breath = f.breathe:CreateAnimation("Alpha")
    breath:SetFromAlpha(1)
    breath:SetToAlpha(ALERT_BREATHE_TO)
    breath:SetDuration(ALERT_BREATHE)
    f.breathe:SetLooping("BOUNCE")

    f.sit = NewSit(f.body, f.fire, f.hot, level + 3, false)
    return f
end

local function AlertOff()
    local f = Views.alert
    if not f.active then return end
    f.active = false
    f.sit:Hide()
    f.breathe:Stop()
    f.fadeIn:Stop()
    f.fadeOut:Play()
end

-- The catcher keeps the right click, which dismisses, and nothing else: every
-- other button passes through, and motion reaches the world. Protected, so out
-- of combat only: at build, or at the next render out of combat. Until then the
-- catcher takes no mouse at all, so no click is lost.
local function PassClicksThrough(f)
    if f.passThrough or InCombatLockdown() then return end
    f.catcher:SetPassThroughButtons("LeftButton", "MiddleButton", "Button4", "Button5")
    f.catcher:SetMouseClickEnabled(true)
    f.passThrough = true
end

local function RenderAlert(r)
    local f = Views.alert
    PassClicksThrough(f)
    if not r.alertText then
        AlertOff()
        return
    end
    f.text:SetText(KE:ColorTextByTheme("Camp Nearby") .. " " .. Colored(WHITE_CODE, r.alertText))
    f:SetWidth(ALERT_FIRE + ALERT_GAP + f.text:GetStringWidth())
    f.sit:SetShown(r.clickable)
    if f.active then return end
    f.active = true
    f.fadeOut:Stop()
    f:Show()
    f.fadeIn:Play()
    f.breathe:Play()
end

local function StopAlert()
    local f = Views.alert
    f.active = false
    f.sit:Hide()
    f.breathe:Stop()
    f.fadeIn:Stop()
    f.fadeOut:Stop()
    f:Hide()
end

---------------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------------

local countdownArgs = { seated = false }

-- The views' countdown on a frame of another file, which owns f.time. Only after
-- Views.Build, which makes the formatter.
function Views.AddCountdown(f)
    f.dur = C_DurationUtil.CreateDuration()
    f.binding = NewBinding(f.time, f.dur)
end

-- expiry nil clears the text.
function Views.SetCountdown(f, expiry, duration)
    countdownArgs.expiry, countdownArgs.duration = expiry, duration
    SetTimeText(f, countdownArgs, plainFormat)
end

Views.KeyColor = KeyColor
Views.ShortTime = ShortTime

function Views.Build(owner)
    Views.owner = owner
    if Views.round then return end
    plainFormat = NewFormatter("")
    seatedFormat = NewFormatter("in ")
    Views.round = BuildRound()
    Views.simple = BuildSimple()
    Views.alert = BuildAlert()
    PassClicksThrough(Views.alert)
end

function Views.ApplySettings(db)
    fontVersion = fontVersion + 1
    PLACEMENT.Strata = db.Strata

    local round = Views.round
    local size = db.RoundSize
    round:SetSize(size, size)
    KE:ApplyFontToText(round.time, db.FontFace, size * 0.31, db.FontOutline)
    KE:ApplyFontToText(round.label, db.FontFace, 11 + size / 22, db.FontOutline)
    KE:ApplyFramePosition(round, db.RoundPosition, PLACEMENT)

    local simple = Views.simple
    simple:SetSize(db.SimpleWidth, db.SimpleHeight)
    simple.fire:ClearAllPoints()
    simple.fire:SetPoint("TOPLEFT", simple, "TOPLEFT", 3, -(db.SimpleHeight - 2 - SIMPLE_FIRE) / 2)
    for _, fs in ipairs({ simple.time, simple.measure, simple.more, simple.panel.head }) do
        KE:ApplyFontToText(fs, db.FontFace, db.SimpleTextSize, db.FontOutline)
    end
    KE:ApplyFramePosition(simple, db.SimplePosition, PLACEMENT)

    local alert = Views.alert
    KE:ApplyFontToText(alert.text, db.FontFace, db.AlertTextSize, "OUTLINE")
    KE:ApplyFramePosition(alert, db.AlertPosition, PLACEMENT)
end

function Views.Render(r, db)
    Views.last = r
    if r.showShape and r.shape == "ROUND" then RenderRound(r, db) else StopRound() end
    if r.showShape and r.shape == "SIMPLE" then RenderSimple(r, db) else StopSimple() end
    RenderAlert(r)
end

-- A color step needs no aura read, so it works from the last render.
function Views.SetColorKey(key)
    local r = Views.last
    if not r or r.seated or r.fullRing or not r.expiry then return end
    r.colorKey = key
    local cr, cg, cb = KeyColor(key)
    Views.round.drain:SetSwipeColor(cr, cg, cb, 1)
    Views.simple.bar:SetStatusBarColor(cr, cg, cb, 1)
    Views.simple.time:SetTextColor(SimpleTimeColor(key))
end

function Views.EnterHeld(inCombat, keepList)
    AlertOff()
    if inCombat then
        if not keepList then Views.round.list:Hide() end
        Views.simple.panel:Hide()
    end
end

function Views.HideShape()
    StopRound()
    StopSimple()
end

function Views.HideAll()
    -- Enabled inside an instance, nothing has been built yet.
    if not Views.round then return end
    StopRound()
    StopSimple()
    StopAlert()
    Views.last = nil
end

-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/Skinning/RestedXP/RestedXPWindow.lua            ║
-- ║  Purpose: RestedXP's guide in one KE window: its         ║
-- ║           progress, the active steps and the steps       ║
-- ║           after them. RestedXP's two windows stay alive  ║
-- ║           at alpha 0, because its handlers write to      ║
-- ║           their rows.                                    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local C_Timer, CreateFrame, GameTooltip, UIParent = C_Timer, CreateFrame, GameTooltip, UIParent
local hooksecurefunc, IsInInstance, IsShiftKeyDown = hooksecurefunc, IsInInstance, IsShiftKeyDown
local GetTime, InCombatLockdown, LibStub = GetTime, InCombatLockdown, LibStub
local ipairs, pairs, select, setmetatable, type = ipairs, pairs, select, setmetatable, type
local floor, math_max, math_min = math.floor, math.max, math.min

local Safe, Rules, Theme = KE.RestedXPSafe, KE.RestedXPRules, KE.RestedXPTheme
local Model, Icons, Arrow = KE.RestedXPWindowModel, KE.RestedXPIcons, KE.RestedXPArrow
local Has, Dig, Run, Secret = Safe.Has, Safe.Dig, Safe.Run, Safe.Secret
local Option = Theme.Option

local Window = {}
KE.RestedXPWindow = Window

-- The fixed layout, art and words in one table: as locals they would take this
-- file past Lua 5.1's limit of 200 locals in one chunk.
local K = {
    WINDOW_NAME = "KitnEssentialsRestedXPWindow",
    STRATA = "MEDIUM",
    WHITE = "Interface\\Buttons\\WHITE8X8",
    MARK_RIM = "Interface\\AddOns\\KitnEssentials\\Media\\RestedXP\\Logo\\rim.tga",
    MARK_K = "Interface\\AddOns\\KitnEssentials\\Media\\RestedXP\\Logo\\k.tga",
    CLOCK = "Interface\\AddOns\\KitnEssentials\\Media\\RestedXP\\Icons\\clock.tga",
    COG = "Interface\\AddOns\\KitnEssentials\\Media\\Icon\\dm_settings.tga",
    CHECK = "Interface\\AddOns\\KitnEssentials\\Media\\RestedXP\\Icons\\complete.tga",
    GRIP_UP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up",
    GRIP_DOWN = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down",
    GRIP_HIGHLIGHT = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight",
    GRIP_CORNER = "BOTTOMRIGHT",
    PERCENT = 100,
    PAD = 10, BOX_PAD = 7, FOLD_W = 16, GAP = 5, TOP_GAP = 2, COG_SIZE = 14, FOLD_GROW = 8,
    HEAD_PAD = 10, LIST_PAD = 6, ROW_GAP = 8, MARK_CLEAR = 3,
    BOX_TITLE_TEXT = 9, BOX_TITLE_HEIGHT = 19, BOX_TITLE_ROOM = 10,
    BAND_HEIGHT = 14, BAND_TEXT_X = 6, BAND_ALPHA = 0.92, TITLE_SLACK = 0.5,
    ICON_GAP = 5, GRIP_SIZE = 16, TIMER_ICON_INSET = 2,
    FIRST_GROW = 2, FIRST_ICON_GROW = 2, MARK_SIZE = 24, BAR_HEIGHT = 5, ICON_SIZE = 18,
    HOVER_ALPHA = 0.25, ICON_DONE_ALPHA = 0.5, DONE_ALPHA = 0.5, YARDS_ALPHA = 0.85,
    COUNT_GAP = 2, CHECK_SIZE = 10, CHECK_OUT = 2, RING_ALPHA = 0.15,
    REDRAW_GAP = 0.1,
    GUIDE_ROW_WIDGET = "RXPV2GuideStepsItem",
    FLASH_FROM = 0.4, FLASH_SECONDS = 0.55,
    BAG_EVENT = "BAG_UPDATE_DELAYED",
    SHADOW = { Enabled = true, OffsetX = 1, OffsetY = -1, Color = { 0, 0, 0, 0.9 } },
    TEXT_FOLD = "-", TEXT_UNFOLD = "+", TEXT_DOT = " \194\183 ",
    TEXT_YARDS = "\194\183 %d yd",
    TEXT_STEP = "Step %d",
    TEXT_NONE = "No guide selected",
    TEXT_SKIP = "Skip step",
    TEXT_HIDE = "Hide step",
    TEXT_MENU = "Menu",
    TEXT_GO = "Go to step",
    TEXT_PICK = "Pick a guide",
    KEY_SHIFT = "Shift-click", KEY_CLICK = "Click", KEY_RIGHT = "Right-click",
    TEXT_LINE = "Skip this line", TEXT_UNSKIP = "Undo skip",
    TEXT_NEXT = "NEXT STEPS",
    TIP_DIM = 0.7,
    WHEEL_LINES = 2,
    LABEL_LINES = 1,
    SCROLL_W = 2, SCROLL_GAP = 4, SCROLL_MIN = 12,
    HOME = { "LEFT", "LEFT", 0, 35 },
    DRAG_BUTTON = "LeftButton", TIP_ANCHOR = "ANCHOR_TOP",
    -- The target and the mob placeholder file ids on Targets buttons.
    PLACEHOLDER_GLYPHS = { [2056011] = "gossip", [135274] = "combat" },
}
K.SCROLL_ROOM = K.SCROLL_W + K.SCROLL_GAP
K.WIDTH_MIN, K.WIDTH_MAX = Rules.Range("Width")
K.STEPS_MAX = select(2, Rules.Range("ListedSteps"))

local window, active, started, pending, cooling, dirty, styled, wantsBags, paintPending
local retake = true
local allowedHere = true
local sizing, sizingModel, moving
local scroll, anchorGuide, anchorAfter = 0, nil, nil
local colors, fontName, fontPath, fontOutline
local pools
local linesDrawn = 0
local lastBox, yardBox, yardText
local silenced = setmetatable({}, { __mode = "k" })
-- How many rows each active-step item had at its last walk.
local rowsSeen = setmetatable({}, { __mode = "k" })
local guideTaken, guideGrew, grewPending, rowsWatched, stepsChildren
local dressed = setmetatable({}, { __mode = "k" })
local alphaHooked = setmetatable({}, { __mode = "k" })
local textHooked = setmetatable({}, { __mode = "k" })
local paintHooked = setmetatable({}, { __mode = "k" })
local seenText = setmetatable({}, { __mode = "k" })
local placeholders = setmetatable({}, { __mode = "k" })
local titleHome = setmetatable({}, { __mode = "k" })
local targetingHooked
-- RestedXP's countdown bars. Its functions are fields: as locals they would take this
-- file past Lua 5.1's limit of 200 locals in one chunk.
local Timers = {
    -- Each bar RestedXP started, to the one key of its table it was started under.
    owned = setmetatable({}, { __mode = "k" }),
    -- Each bar the window took, to what it had at first touch.
    taken = setmetatable({}, { __mode = "k" }),
    -- Each bar the last redraw gave a line, to that line's slot.
    slotOf = setmetatable({}, { __mode = "k" }),
    -- The last order outside a held grip and its line count, which a held grip draws
    -- from, so its redraws, up to one a frame, make no list.
    list = {}, shown = 0,
    -- Each listed bar's start at that redraw, so a held grip shows a line only for the
    -- same run of the same bar. Refilled in place, never made again.
    starts = {},
    -- The order with no bar table. Never written.
    none = {},
}
-- The header band on Targets and Items, a table of fields for the same reason.
local Band = {
    -- Each frame given a band, to its fill and line.
    of = setmetatable({}, { __mode = "k" }),
}
-- Skipping one line from its icon, a table of fields for the same reason.
local Lines = {}
local Draw

local function DB()
    return KE.db.profile.SkinRestedXP
end

---------------------------------------------------------------------------------
-- Redraw requests
---------------------------------------------------------------------------------
local function Redraw()
    if not Run("WindowDraw", Draw) then wipe(seenText) end
end

-- Only when RestedXP changed something: the next frame, then at most one per
-- K.REDRAW_GAP, because RestedXP's update setting goes down to 5 ms.
local Refresh, Take

local function CoolDown()
    cooling = false
    if dirty then
        dirty = false
        Refresh()
    end
end

function Refresh()
    if not active or pending then return end
    if cooling then
        dirty = true
        return
    end
    pending = true
    C_Timer.After(0, function()
        pending = false
        if not active then return end
        -- A held grip's own redraws do not walk, and RestedXP's rows still take the
        -- mouse. This path has the cap. The flag stays set for the release's repaint.
        if sizing and retake then Take() end
        Redraw()
        cooling = true
        C_Timer.After(K.REDRAW_GAP, CoolDown)
    end)
end

local function Wheel(_, delta)
    scroll = scroll - delta * K.WHEEL_LINES
    Refresh()
end

local function RefreshAccepts()
    local rxp = _G.RXP
    if not Has(rxp, "ActiveStepElementEventHandler") or type(rxp.questAccept) ~= "table" then return end
    local steps = Dig(rxp, "RXPFrame", "activeSteps")
    if type(steps) ~= "table" then return end
    for _, step in ipairs(steps) do
        if step.active then
            for _, element in ipairs(step.elements or {}) do
                local frame = element.frame
                if element.tag == "accept" and element.questId and not rxp.questAccept[element.questId]
                        and frame and frame.element == element and frame.step == step and Has(frame, "callback") then
                    Run("WindowAccept", rxp.ActiveStepElementEventHandler, frame)
                end
            end
        end
    end
end

local function OnSourceText(source, text)
    if not active then return end
    if not Secret(text) then
        if seenText[source] == text then return end
        seenText[source] = text
    end
    Refresh()
end

local function Watch(source)
    if textHooked[source or false] or not Has(source, "SetText") then return end
    textHooked[source] = true
    hooksecurefunc(source, "SetText", OnSourceText)
end

---------------------------------------------------------------------------------
-- Silencing RestedXP's two windows
---------------------------------------------------------------------------------
local function OnSilencedAlpha(self, alpha)
    if silenced[self] and alpha ~= 0 then self:SetAlpha(0) end
end

local Silence

local function SilenceChildren(...)
    for i = 1, select("#", ...) do Silence((select(i, ...)), false) end
end

-- Records alpha and mouse on first touch, so a later walk cannot store 0 as the
-- player's value.
function Silence(frame, top)
    if not frame or frame:IsForbidden() or frame:IsProtected() then return end
    if not silenced[frame] then
        silenced[frame] = Rules.KeepHome(silenced[frame], top and frame:GetAlpha() or nil, frame:IsMouseEnabled())
        if top then
            frame:SetAlpha(0)
            if not alphaHooked[frame] then
                alphaHooked[frame] = true
                hooksecurefunc(frame, "SetAlpha", OnSilencedAlpha)
            end
        end
        frame:EnableMouse(false)
    end
    SilenceChildren(frame:GetChildren())
end

-- The guide window's widgets grow with the guide, and its chrome is built with it,
-- so after its first walk only a guide row RestedXP makes needs one, and a row is
-- found by not being silenced yet: a release can leave the list's count the same.
-- Making a row is rare, so the child list is a table.
local function SilenceGuideRows()
    if not (guideGrew and active) then return end
    guideGrew = false
    local list = Dig(_G.RXPV2GuideWindow, "guideSteps", "content")
    if not Has(list, "GetChildren") then
        Silence(Dig(_G.RXPV2GuideWindow, "frame"), true)
        return
    end
    for _, child in ipairs({ list:GetChildren() }) do
        if not silenced[child] then Silence(child, false) end
    end
end

-- RestedXP's rows come from AceGUI, whichever of its calls asks. The rebuild's hook
-- silences them in the same call; the next frame catches any other caller.
local function OnWidgetCreated(_, widgetType)
    if not active or widgetType ~= K.GUIDE_ROW_WIDGET then return end
    guideGrew = true
    if grewPending then return end
    grewPending = true
    C_Timer.After(0, function()
        grewPending = false
        SilenceGuideRows()
    end)
end

local function WatchGuideRows()
    local gui = LibStub and LibStub("AceGUI-3.0", true)
    if not Has(gui, "Create") then return end
    rowsWatched = true
    hooksecurefunc(gui, "Create", OnWidgetCreated)
end

local function StepsFrame()
    local name = Dig(_G.RXP, "player", "name")
    local steps = name and _G["RXPActiveStepsFrame" .. name]
    return Dig(steps, "frame") or steps
end

-- With no watch on new rows, each capped walk covers the whole guide window instead.
function Take()
    local guide = Dig(_G.RXPV2GuideWindow, "frame")
    local steps = StepsFrame()
    if not (guideTaken and rowsWatched) then
        guideTaken = guide ~= nil
        Silence(guide, true)
    end
    Silence(steps, true)
    return guide ~= nil and steps ~= nil and steps ~= false
end

-- A row RestedXP just added takes the mouse as soon as it is laid out, under an
-- invisible ancestor, so this runs in the rebuild and not behind the redraw's cap.
-- It reads counts, and walks only what grew.
local function SilenceNew()
    local name = Dig(_G.RXP, "player", "name")
    local items = name and Dig(_G.RXP, "v2", "state", "player", name, "activeStepItems")
    if type(items) == "table" then
        for _, item in ipairs(items) do
            local rows = item.elementRows
            local count = type(rows) == "table" and #rows or 0
            if rowsSeen[item] ~= count then
                rowsSeen[item] = count
                Silence(item.frame, false)
            end
        end
    end
    -- A party tab is the window's own child, and a used one goes back to a pool on
    -- that same frame, so the count only grows.
    local steps = StepsFrame()
    if steps then
        local children = select("#", steps:GetChildren())
        if children ~= stepsChildren then
            stepsChildren = children
            Silence(steps, true)
        end
    end
    SilenceGuideRows()
end

local function OnPartyTabs()
    if active then SilenceNew() end
end

local releaseQueued

-- A frame that became protected after it was silenced cannot change in combat, so
-- it comes back when combat ends; every other frame comes back at once.
local function ReleaseFrames()
    if active then return end
    local locked, held = InCombatLockdown(), false
    for frame, home in pairs(silenced) do
        if locked and frame:IsProtected() then
            held = true
        else
            silenced[frame] = nil
            if home.alpha then frame:SetAlpha(home.alpha) end
            frame:EnableMouse(home.mouse)
        end
    end
    if held and not releaseQueued then
        releaseQueued = true
        KE:RunAfterCombat(function()
            releaseQueued = false
            ReleaseFrames()
        end)
    end
end

local function Release()
    ReleaseFrames()
    for item in pairs(rowsSeen) do rowsSeen[item] = nil end
    guideTaken, guideGrew, stepsChildren = false, false, nil
    retake = true
end

local function Rebuilt()
    if not active then return end
    SilenceNew()
    retake = true
    Model.Stale()
    Refresh()
end

local function StepChanged()
    if not active then return end
    RefreshAccepts()
    Rebuilt()
end

---------------------------------------------------------------------------------
-- Text and color
---------------------------------------------------------------------------------
local function ReadFont()
    fontName = DB().FontFace
    fontPath = KE:GetFontPath(fontName)
    fontOutline = Option("FontOutline")
end

-- Shadow is not a font flag: it is no outline plus KE's shadow setting. KE's font
-- helper adds the Slug flag for every caller, and this window's text goes without
-- it, so the font is set once more with the plain flags.
local function Faced(fs, size)
    local last = dressed[fs]
    if last and last.path == fontPath and last.size == size and last.outline == fontOutline then return end
    local shadow = fontOutline == "shadow"
    local outline = shadow and "NONE" or fontOutline
    KE:ApplyFontToText(fs, fontName, size, outline, shadow and K.SHADOW or nil)
    local path, height = fs:GetFont()
    if path then fs:SetFont(path, height, KE:GetFontOutline(outline)) end
    dressed[fs] = { path = fontPath, size = size, outline = fontOutline }
end

local function Text(parent, size, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    Faced(fs, size)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetJustifyV("TOP")
    return fs
end

local function Colored(fs, name)
    local c = colors[name]
    fs:SetTextColor(c[1], c[2], c[3], c[4])
end

local function Tint(name, text)
    return "|cff" .. Rules.Hex(colors[name]) .. text .. "|r"
end

local function TintRange(range)
    return Tint("accent", range)
end

local READ_OPTIONS = {
    -- The tag-along boxes hidden this session, by their step tables.
    hidden = setmetatable({}, { __mode = "k" }),
    tint = TintRange,
    iconText = function(text) return Icons.InlineText(text) end,
    getCount = function(id) return C_Item.GetItemCount(id) end,
}

---------------------------------------------------------------------------------
-- Targets and Items: a repaint only, they keep their secure buttons
---------------------------------------------------------------------------------
local function SkinBox(part)
    local back, border = part.rxpBackground, part.rxpBorder
    if type(Dig(back, "textures")) == "table" and back.textures[1] then
        local c = colors.box
        back.textures[1]:SetVertexColor(c[1], c[2], c[3], c[4])
    end
    if type(Dig(border, "textures")) ~= "table" then return end
    local c = colors.boxBorder
    for _, texture in ipairs(border.textures) do texture:SetColorTexture(c[1], c[2], c[3], c[4]) end
    border:SetShown(not back or back:IsShown())
end

function Band.Shown(part)
    if Has(part, "IsShown") then return part:IsShown() end
end

function Band.Show(part, shown)
    if shown ~= nil and Has(part, "SetShown") then part:SetShown(shown) end
end

-- A frame's points, or nil when any value reads as a secret, which is neither
-- compared nor kept.
function Band.Points(frame)
    local count = frame:GetNumPoints()
    if Secret(count) then return nil end
    local points = {}
    for i = 1, count do
        local point, relative, relativePoint, x, y = frame:GetPoint(i)
        if Secret(point) or Secret(relative) or Secret(relativePoint) or Secret(x) or Secret(y) then return nil end
        points[i] = { point, relative, relativePoint, x, y }
    end
    return points
end

-- On RestedXP's own background frame, so the band hides with RestedXP's Hide
-- Background setting, and the buttons and the title draw over it. False where the
-- frame has none.
function Band.Paint(frame)
    local host = frame.rxpBackground
    if not Has(host, "CreateTexture") then return false end
    local band = Band.of[frame]
    if not band then
        band = { fill = host:CreateTexture(nil, "BORDER"), line = host:CreateTexture(nil, "ARTWORK") }
        band.fill:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        band.fill:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
        band.line:SetPoint("BOTTOMLEFT", band.fill, "BOTTOMLEFT", 0, 0)
        band.line:SetPoint("BOTTOMRIGHT", band.fill, "BOTTOMRIGHT", 0, 0)
        Band.of[frame] = band
    end
    local box, accent = colors.box, colors.accent
    band.fill:SetHeight(K.BAND_HEIGHT)
    band.fill:SetColorTexture(box[1], box[2], box[3], K.BAND_ALPHA)
    band.line:SetHeight(KE:GetPixelSize())
    band.line:SetColorTexture(accent[1], accent[2], accent[3], 1)
    band.fill:Show()
    band.line:Show()
    return true
end

function Band.Clear()
    for _, band in pairs(Band.of) do
        band.fill:Hide()
        band.line:Hide()
    end
end

-- RestedXP sizes these frames from their title only when it lays them out, so a title
-- whose width changed asks for that once, by RestedXP's own call. Both return in
-- combat, and the repaint runs only out of it.
function Band.Layout(frame)
    local rxp = _G.RXP
    if frame == Dig(rxp, "activeItemFrame") then
        if Has(rxp, "UpdateItemFrame") then Run("WindowLayout", rxp.UpdateItemFrame, frame) end
        return
    end
    local targeting = Dig(rxp, "targeting")
    if Has(targeting, "UpdateTargetFrame") then Run("WindowLayout", targeting.UpdateTargetFrame, targeting) end
end

-- First touch only: all that the repaint changes on a title, so turning off gives it
-- back. RestedXP writes the words once, when it builds the frame.
local function KeepTitle(title, text)
    if titleHome[text] then return titleHome[text] end
    local font, size, flags = text:GetFont()
    local r, g, b, a = text:GetTextColor()
    local shadowX, shadowY = text:GetShadowOffset()
    local shadowR, shadowG, shadowB, shadowA = text:GetShadowColor()
    local words = text:GetText()
    if Secret(words) or type(words) ~= "string" then words = nil end
    titleHome[text] = {
        font = font, size = size, flags = flags, r = r, g = g, b = b, a = a,
        shadowX = shadowX, shadowY = shadowY, shadowR = shadowR, shadowG = shadowG, shadowB = shadowB, shadowA = shadowA,
        title = title, words = words, caps = words and words:upper(),
        mouse = title:IsMouseEnabled(), back = Band.Shown(title.rxpBackground), edge = Band.Shown(title.rxpBorder),
        points = Band.Points(title),
    }
    return titleHome[text]
end

-- RestedXP sizes the frame from the title's width, so the title is never stretched to
-- the frame. A frame with no background of RestedXP's, or a title whose points read as
-- secret, keeps its plate. Returns whether the title's width changed.
local function SkinTitle(frame)
    local title = frame.title
    local text = Dig(title, "text")
    if not Has(text, "GetFont") then return false end
    local home = KeepTitle(title, text)
    Faced(text, K.BOX_TITLE_TEXT)
    Colored(text, "title")
    if home.points and Band.Paint(frame) then
        local now = text:GetText()
        if home.caps and (Secret(now) or now ~= home.caps) then text:SetText(home.caps) end
        Band.Show(title.rxpBackground, false)
        Band.Show(title.rxpBorder, false)
        -- A press reaches the frame's own drag, and the buttons under the title.
        title:EnableMouse(false)
        title:ClearAllPoints()
        title:SetPoint("LEFT", frame, "TOPLEFT", K.BAND_TEXT_X - K.BOX_TITLE_ROOM / 2, -K.BAND_HEIGHT / 2)
    else
        SkinBox(title)
    end
    local was, width = title:GetWidth(), text:GetStringWidth() + K.BOX_TITLE_ROOM
    title:SetSize(width, K.BOX_TITLE_HEIGHT)
    if Secret(was) then return false end
    return was < width - K.TITLE_SLACK or was > width + K.TITLE_SLACK
end

local function SkinPlaceholders(frame)
    for _, button in ipairs({ frame:GetChildren() }) do
        local texture = button.placeholder
        local id = texture and texture:GetTexture()
        local glyph = not Secret(id) and id and K.PLACEHOLDER_GLYPHS[id]
        local path = glyph and Icons.TextureFor(glyph)
        if path then
            texture:SetTexture(path)
            placeholders[texture] = { id = id, shown = texture:GetTexture() }
        end
    end
end

-- RestedXP draws a found target's portrait or icon on the same texture and does
-- not draw it again until the target changes, so only KE's own file goes back.
local function RestorePlaceholders()
    for texture, swap in pairs(placeholders) do
        placeholders[texture] = nil
        local now = texture:GetTexture()
        if not Secret(now) and now ~= nil and now == swap.shown then texture:SetTexture(swap.id) end
    end
end

-- The words go back before RestedXP's own UpdateVisuals, which sizes the title from
-- its text.
local function RestoreTitles()
    Band.Clear()
    for text, home in pairs(titleHome) do
        titleHome[text] = nil
        dressed[text] = nil
        if home.font then text:SetFont(home.font, home.size, home.flags or "") end
        if home.r then text:SetTextColor(home.r, home.g, home.b, home.a) end
        if home.shadowX then text:SetShadowOffset(home.shadowX, home.shadowY) end
        if home.shadowR then text:SetShadowColor(home.shadowR, home.shadowG, home.shadowB, home.shadowA) end
        if home.words then text:SetText(home.words) end
        local title = home.title
        title:EnableMouse(home.mouse)
        Band.Show(title.rxpBackground, home.back)
        Band.Show(title.rxpBorder, home.edge)
        if home.points then
            title:ClearAllPoints()
            for _, point in ipairs(home.points) do title:SetPoint(unpack(point, 1, 5)) end
        end
    end
end

local function SkinFrame(frame)
    SkinBox(frame)
    local resized = frame.title and SkinTitle(frame)
    SkinPlaceholders(frame)
    if resized then Band.Layout(frame) end
end

local function SkinFrames()
    local frames = {}
    local target, items = Dig(_G.RXP, "targeting", "activeTargetFrame"), Dig(_G.RXP, "activeItemFrame")
    if target then frames[#frames + 1] = target end
    if items then frames[#frames + 1] = items end
    return frames
end

local function SkinRestore(frame)
    if Has(frame, "UpdateVisuals") then Run("WindowSkin", frame.UpdateVisuals, frame) end
    for _, part in ipairs({ frame, frame.title }) do
        local border, back = part.rxpBorder, part.rxpBackground
        if border then border:SetShown(not back or back:IsShown()) end
    end
end

local Repaint

local function SkinHooks(frames)
    for _, frame in ipairs(frames) do
        if not paintHooked[frame] and Has(frame, "UpdateVisuals") then
            paintHooked[frame] = true
            hooksecurefunc(frame, "UpdateVisuals", function()
                -- The one place RestedXP writes this title's font after building it.
                local text = Dig(frame, "title", "text")
                if text then dressed[text] = nil end
                if active then Repaint() end
            end)
        end
    end
    local targeting = Dig(_G.RXP, "targeting")
    if not targeting or targetingHooked then return end
    targetingHooked = true
    local function OnTargets()
        if active then Repaint() end
    end
    if Has(targeting, "RenderTargetFrameBackground") then
        hooksecurefunc(targeting, "RenderTargetFrameBackground", OnTargets)
    end
    if Has(targeting, "UpdateTargetFrame") then hooksecurefunc(targeting, "UpdateTargetFrame", OnTargets) end
end

local function PaintFrames()
    local frames = SkinFrames()
    if active then
        styled = true
        colors = Theme.WindowColors()
        ReadFont()
        SkinHooks(frames)
        for _, frame in ipairs(frames) do SkinFrame(frame) end
    elseif styled then
        styled = false
        RestorePlaceholders()
        -- The record can hold a theme that is gone. RestedXP writes the title's font
        -- and color from its current theme, so it goes last, whichever way a theme
        -- reload and this teardown are ordered.
        RestoreTitles()
        for _, frame in ipairs(frames) do
            SkinRestore(frame)
            Band.Layout(frame)
        end
    end
end

-- These frames hold secure buttons, so a repaint in combat waits, once.
function Repaint()
    if paintPending then return end
    paintPending = true
    KE:RunAfterCombat(function()
        paintPending = false
        Run("WindowPaint", PaintFrames)
    end)
end

---------------------------------------------------------------------------------
-- Moving and clicking
---------------------------------------------------------------------------------
local function Save(frame, db)
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    if point then (db or DB()).WindowPos = { point, relativePoint, x, y } end
end

local function Place(frame)
    local saved = DB().WindowPos
    frame:ClearAllPoints()
    if type(saved) == "table" then
        frame:SetPoint(saved[1], UIParent, saved[2] or saved[1], saved[3] or 0, saved[4] or 0)
        return
    end
    local home = Dig(_G.RXPV2GuideWindow, "frame")
    local point, relativePoint, x, y = K.HOME[1], K.HOME[2], K.HOME[3], K.HOME[4]
    if Has(home, "GetPoint") then
        local first, _, relative, dx, dy = home:GetPoint(1)
        if first then point, relativePoint, x, y = first, relative, dx, dy end
    end
    frame:SetPoint(point, UIParent, relativePoint, x, y)
end

-- A retained window keeps its scale and points across a reset and a profile switch,
-- so every start and every settings pass sets them again. A held grip or drag is
-- left alone until it ends.
local function ApplyGeometry()
    if not window or sizing or moving then return end
    window:SetScale(Option("Scale") / K.PERCENT)
    Place(window)
end

local function Menu()
    local menu = Dig(_G.RXP, "RXPFrame", "DropDownMenu")
    if type(menu) == "function" then Run("WindowMenu", menu) end
end

local function MenuOnRight(_, button)
    if button == "RightButton" then Menu() end
end

local function PickGuide()
    local v2 = Dig(_G.RXP, "v2")
    if Has(v2, "ShowGuideSelectionMenu") then
        Run("WindowPick", v2.ShowGuideSelectionMenu, v2)
    else
        Menu()
    end
end

-- A profile can change while a drag or grip is held. The result belongs to the
-- profile it began on, and the window then takes the current profile's geometry,
-- which the settings pass skipped.
local function DragStopped()
    if not moving then return end
    local owner = moving
    moving = nil
    window:StopMovingOrSizing()
    Save(window, owner)
    if owner ~= DB() then ApplyGeometry() end
end

local function Draggable(frame)
    frame:RegisterForDrag(K.DRAG_BUTTON)
    frame:SetScript("OnDragStart", function()
        if Option("Lock") then return end
        moving = DB()
        window:StartMoving()
    end)
    frame:SetScript("OnDragStop", DragStopped)
end

local function GoTo(index)
    Run("WindowGo", _G.RXP.SetStep, index)
end

-- As RestedXP's own checkbox marks a line: its OnComplete runs as it turns skipped,
-- then the flag is set. RestedXP's own box, under this window, is set to match where
-- its row still holds this line, because a row's done look reads that box first.
function Lines.Mark(element, skip)
    if skip and not element.skip and type(element.OnComplete) == "function" then
        Run("WindowComplete", element.OnComplete, element)
    end
    element.skip = skip
    local frame = element.frame
    local button = Dig(frame, "button")
    if Dig(frame, "element") == element and Has(button, "SetChecked") then
        Run("WindowLineBox", button.SetChecked, button, skip or element.completed == true)
    end
end

function Lines.Updated(rxp)
    rxp.updateSteps = true
    if Has(rxp, "UpdateMap") then Run("WindowMap", rxp.UpdateMap) end
end

-- A sticky step is not the guide's progress, so moving on would skip the wrong
-- one. Its objectives are marked skipped, as RestedXP's own checkbox does.
local function SkipObjectives(rxp, step)
    for _, element in ipairs(step.elements or {}) do
        if not element.optional and not element.skip then Lines.Mark(element, true) end
    end
    Lines.Updated(rxp)
end

local function SkipStep(step)
    local rxp = _G.RXP
    local progress = Run("WindowProgress", rxp.GetGuideProgress)
    if not progress then return end
    if Rules.TagAlong(step, progress) then
        -- This window's own: RestedXP's state does not change.
        READ_OPTIONS.hidden[step] = true
        Refresh()
    elseif step and step.index ~= progress then
        SkipObjectives(rxp, step)
    else
        GoTo(progress + 1)
    end
end

local function MaySkip()
    local mode = Option("Skip")
    return mode == "click" or (mode == "shift" and IsShiftKeyDown())
end

local function StepClick(self, button)
    if button == "RightButton" then return Menu() end
    if MaySkip() then SkipStep(self.step) end
end

-- The full text of a string the window cut, or nil for one that fits.
local function CutText(fs)
    local cut = Has(fs, "IsTruncated") and fs:IsTruncated()
    if Secret(cut) or not cut then return nil end
    return fs:GetText()
end

local tipOwner

-- One tooltip per hover, in one style: a cut line's full text, else the heading in
-- the accent, then each key in white beside its action in gray.
local function Tip(owner, heading, full, key, action, key2, action2)
    if not Option("Tips") or GameTooltip:IsForbidden() then return end
    GameTooltip:SetOwner(owner, K.TIP_ANCHOR)
    tipOwner = owner
    if full then
        GameTooltip:SetText(full, 1, 1, 1, 1, true)
    else
        local accent = Theme.Tokens().accent
        GameTooltip:SetText(heading, accent[1], accent[2], accent[3])
    end
    local dim = K.TIP_DIM
    if key then GameTooltip:AddDoubleLine(key, action, 1, 1, 1, dim, dim, dim) end
    if key2 then GameTooltip:AddDoubleLine(key2, action2, 1, 1, 1, dim, dim, dim) end
    GameTooltip:Show()
end

-- The key that skips a step, or nil with Skipping Steps off.
local function SkipKey()
    local mode = Option("Skip")
    if mode == "shift" then return K.KEY_SHIFT end
    if mode == "click" then return K.KEY_CLICK end
    return nil
end

local function StepHeading(step)
    return K.TEXT_STEP:format(type(step) == "table" and step.index or 0)
end

-- The words say what the click does, by the rule the click uses.
local function StepTip(owner, step)
    local rxp = _G.RXP
    local progress = Has(rxp, "GetGuideProgress") and Run("WindowProgress", rxp.GetGuideProgress) or nil
    local key = SkipKey()
    if not key then return Tip(owner, StepHeading(step), nil, K.KEY_RIGHT, K.TEXT_MENU) end
    Tip(owner, StepHeading(step), nil, key, Rules.TagAlong(step, progress) and K.TEXT_HIDE or K.TEXT_SKIP,
        K.KEY_RIGHT, K.TEXT_MENU)
end

-- A leave with no tooltip of this window's own leaves another owner's up. A row's
-- owner is its box, and a redraw can move the row, so the check is on the last owner.
local function TipHide()
    local owner = tipOwner
    tipOwner = nil
    if owner and not GameTooltip:IsForbidden() and GameTooltip:GetOwner() == owner then GameTooltip:Hide() end
end

---------------------------------------------------------------------------------
-- Skipping one line from its icon
---------------------------------------------------------------------------------
function Lines.Ring(hit, on)
    hit.ring:SetShown(on)
    for _, texture in pairs(hit.borders) do texture:SetShown(on) end
end

-- Only a line RestedXP's own checkbox can change rings and gives a hint.
function Lines.Enter(hit)
    local skip = Rules.LineSkip(hit.element)
    if skip == nil then return end
    local accent = colors.accent
    hit.ring:SetColorTexture(accent[1], accent[2], accent[3], K.RING_ALPHA)
    hit:SetBorderColor(accent[1], accent[2], accent[3], 1)
    Lines.Ring(hit, true)
    Tip(hit, StepHeading(hit.step), nil, K.KEY_CLICK, skip and K.TEXT_LINE or K.TEXT_UNSKIP, K.KEY_RIGHT, K.TEXT_MENU)
end

function Lines.Leave(hit)
    Lines.Ring(hit, false)
    TipHide()
end

-- One line and never its step, in every Skipping Steps mode; a second click takes
-- it back. The rule runs again here, since the line can finish after the hover.
function Lines.Click(hit, button)
    if button == "RightButton" then return Menu() end
    local skip = Rules.LineSkip(hit.element)
    if skip == nil then return end
    Lines.Mark(hit.element, skip)
    Lines.Updated(_G.RXP)
    Refresh()
end

-- Over the icon alone and above its row, so a click there never reaches the row.
function Lines.Make(row)
    local hit = CreateFrame("Button", nil, row)
    hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    hit.ring = hit:CreateTexture(nil, "BACKGROUND")
    hit.ring:SetAllPoints()
    KE:AddBorders(hit, colors.accent)
    hit:SetScript("OnClick", Lines.Click)
    hit:SetScript("OnEnter", Lines.Enter)
    hit:SetScript("OnLeave", Lines.Leave)
    Draggable(hit)
    Lines.Ring(hit, false)
    hit:Hide()
    return hit
end

-- Every draw sets the hit and the check from this row alone, so a pooled row never
-- keeps another line's look or target. size is the icon's, or nil with no icon.
function Lines.Draw(item, row, size)
    local hit, check = item.lineHit, item.check
    hit.element, hit.step = row.element, row.step
    Lines.Ring(hit, false)
    local clickable = size ~= nil and Option("LineSkip")
    if clickable then
        hit:ClearAllPoints()
        hit:SetPoint("TOPLEFT", item, "TOPLEFT", 0, 0)
        hit:SetSize(size, size)
    end
    hit:SetShown(clickable)
    local checked = size ~= nil and row.skipped == true
    if checked then
        local accent = colors.accent
        check:SetVertexColor(accent[1], accent[2], accent[3])
        check:ClearAllPoints()
        check:SetPoint("BOTTOMRIGHT", item, "TOPLEFT", size + K.CHECK_OUT, -size - K.CHECK_OUT)
    end
    check:SetShown(checked)
end

---------------------------------------------------------------------------------
-- Sizing
---------------------------------------------------------------------------------
-- The label takes a line as soon as one step shows, so the first step costs two.
local function StepsFor(height)
    return Rules.StepsForHeight(height, window.chrome, window.lineHeight, K.LABEL_LINES)
end

local function HeldSteps(hold, height)
    return Rules.GripSteps(hold.listed, height, hold.pressedHeight, StepsFor(height), window.lineHeight)
end

local function LiveSize(width, height)
    if not (sizing and sizingModel and window) then return end
    sizing.width = math_min(K.WIDTH_MAX, math_max(K.WIDTH_MIN, width))
    sizing.steps = math_max(0, math_min(K.STEPS_MAX, HeldSteps(sizing, height)))
    Redraw()
end

local function GripReleased()
    if not sizing then return end
    local hold = sizing
    sizing, sizingModel = nil, nil
    window:StopMovingOrSizing()
    local width, height = window:GetWidth(), window:GetHeight()
    -- A press with no drag changes no setting, and the window keeps its home.
    if width ~= hold.pressedWidth or height ~= hold.pressedHeight then
        hold.db.Width = Rules.Option("Width", width)
        hold.db.ListedSteps = Rules.Option("ListedSteps", HeldSteps(hold, height))
        Save(window, hold.db)
    end
    ApplyGeometry()
    Redraw()
end

-- A hidden frame may never get its mouse-up or drag stop.
local function HoldEnded()
    DragStopped()
    GripReleased()
end

local function MakeGrip(parent)
    local grip = CreateFrame("Button", nil, parent)
    grip:SetSize(K.GRIP_SIZE, K.GRIP_SIZE)
    grip:SetPoint(K.GRIP_CORNER, parent, K.GRIP_CORNER, 0, 0)
    grip:SetNormalTexture(K.GRIP_UP)
    grip:SetPushedTexture(K.GRIP_DOWN)
    grip:SetHighlightTexture(K.GRIP_HIGHLIGHT)
    grip:SetScript("OnMouseDown", function()
        if Option("Lock") then return end
        sizingModel = Run("WindowGripRead", Model.Read, _G.RXP, READ_OPTIONS)
        local width, height, listed = window:GetWidth(), window:GetHeight(), Option("ListedSteps")
        sizing = {
            width = width, steps = listed, db = DB(),
            pressedWidth = width, pressedHeight = height, listed = listed,
        }
        window:StartSizing(K.GRIP_CORNER)
    end)
    grip:SetScript("OnMouseUp", GripReleased)
    return grip
end

---------------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------------
local function MakeBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar.track = bar:CreateTexture(nil, "BACKGROUND")
    bar.track:SetAllPoints()
    KE:AddBorders(bar, colors.boxBorder)
    return bar
end

local function PaintBar(bar, fraction)
    local fill, back, edge = colors.barFill, colors.barBack, colors.boxBorder
    bar:SetStatusBarTexture(K.WHITE)
    bar:SetStatusBarColor(fill[1], fill[2], fill[3], fill[4])
    bar.track:SetColorTexture(back[1], back[2], back[3], back[4])
    bar:SetBorderColor(edge[1], edge[2], edge[3], edge[4])
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(fraction)
    local height = K.BAR_HEIGHT + 2 * KE:GetPixelSize()
    bar:SetHeight(height)
    return height
end

local function OnWindowEvent(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        if window then window:SetAlpha(Option("CombatFade") / K.PERCENT) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if window then window:SetAlpha(1) end
    else
        Refresh()
    end
end

local function ToggleFold()
    DB().Folded = not Option("Folded")
    Redraw()
end

-- Over a string the window may cut: its full text on hover, and the window's drag and
-- menu.
local function CutHit(f, fs)
    local hit = CreateFrame("Frame", nil, f)
    hit:SetAllPoints(fs)
    hit:EnableMouse(true)
    hit:SetScript("OnEnter", function(self)
        local full = CutText(fs)
        if full then Tip(self, nil, full) end
    end)
    hit:SetScript("OnLeave", TipHide)
    hit:SetScript("OnMouseUp", MenuOnRight)
    Draggable(hit)
    return hit
end

local function Build()
    local f = CreateFrame("Frame", K.WINDOW_NAME, UIParent)
    f:SetFrameStrata(K.STRATA)
    f:SetScale(Option("Scale") / K.PERCENT)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    window = f
    Draggable(f)
    f:SetScript("OnHide", HoldEnded)
    f:SetScript("OnMouseUp", MenuOnRight)
    f:SetScript("OnEvent", OnWindowEvent)
    f.back = f:CreateTexture(nil, "BACKGROUND")
    f.back:SetAllPoints()
    KE:AddBorders(f, colors.border)
    f.fold = CreateFrame("Button", nil, f)
    f.fold.text = Text(f.fold, Option("ListSize") + K.FOLD_GROW, "CENTER")
    -- Sized by its glyph, which is taller than the bar, so the glyph is never cut.
    f.fold.text:SetPoint("CENTER", f.fold, "CENTER", 0, 0)
    f.fold:SetScript("OnClick", ToggleFold)
    f.cog = CreateFrame("Button", nil, f)
    f.cog:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f.cog:SetScript("OnClick", Menu)
    f.cog.icon = f.cog:CreateTexture(nil, "OVERLAY")
    f.cog.icon:SetTexture(K.COG)
    f.cog.icon:SetSize(K.COG_SIZE, K.COG_SIZE)
    f.cog.icon:SetPoint("CENTER", f.cog, "CENTER", 0, 0)
    f.group = Text(f, Option("ListSize"))
    f.group:SetWordWrap(false)
    f.groupHit = CutHit(f, f.group)
    f.divider = f:CreateTexture(nil, "ARTWORK")
    f.divider:SetHeight(KE:GetPixelSize())
    f.title = Text(f, Option("TitleSize"))
    f.title:SetWordWrap(false)
    f.titleHit = CutHit(f, f.title)
    f.progress = Text(f, Option("TitleSize"), "RIGHT")
    f.rim = f:CreateTexture(nil, "OVERLAY")
    f.rim:SetTexture(K.MARK_RIM)
    f.rim:SetSize(K.MARK_SIZE, K.MARK_SIZE)
    f.k = f:CreateTexture(nil, "OVERLAY")
    f.k:SetTexture(K.MARK_K)
    f.k:SetSize(K.MARK_SIZE, K.MARK_SIZE)
    f.nextLabel = Text(f, Option("ListSize"))
    f.rule = f:CreateTexture(nil, "ARTWORK")
    f.rule:SetHeight(KE:GetPixelSize())
    f.bar = MakeBar(f)
    f.track = f:CreateTexture(nil, "ARTWORK")
    f.thumb = f:CreateTexture(nil, "OVERLAY")
    f.wheel = CreateFrame("Frame", nil, f)
    f.wheel:SetScript("OnMouseWheel", Wheel)
    f:SetScript("OnSizeChanged", function(_, width, height) LiveSize(width, height) end)
    f.grip = MakeGrip(f)
    Place(f)
    return f
end

local function MakeBox(holder)
    local box = CreateFrame("Button", nil, holder)
    box:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    box:SetScript("OnClick", StepClick)
    box:SetScript("OnEnter", function(self) StepTip(self, self.step) end)
    box:SetScript("OnLeave", TipHide)
    Draggable(box)
    box.back = box:CreateTexture(nil, "BACKGROUND")
    box.back:SetAllPoints()
    KE:AddBorders(box, colors.boxBorder)
    box.label = Text(box, Option("StepSize"))
    box.label:SetPoint("TOPLEFT", box, "TOPLEFT", K.BOX_PAD, -K.BOX_PAD)
    box.yards = Text(box, Option("StepSize"))
    box.yards:SetPoint("LEFT", box.label, "RIGHT", 6, 0)
    box.flash = box:CreateTexture(nil, "OVERLAY")
    box.flash:SetAllPoints()
    box.flash:SetAlpha(0)
    box.flashAnim = box.flash:CreateAnimationGroup()
    local fade = box.flashAnim:CreateAnimation("Alpha")
    fade:SetFromAlpha(K.FLASH_FROM)
    fade:SetToAlpha(0)
    fade:SetDuration(K.FLASH_SECONDS)
    return box
end

local function LinkEnter(row, link)
    if row:IsForbidden() or GameTooltip:IsForbidden() then return end
    GameTooltip:SetOwner(row, "ANCHOR_CURSOR")
    tipOwner = row
    GameTooltip:SetHyperlink(link)
end

local function LinkLeave(row)
    if row:IsForbidden() or GameTooltip:IsForbidden() then return end
    if GameTooltip:GetOwner() == row then GameTooltip:Hide() end
end

local function MakeRow(holder)
    local row = CreateFrame("Button", nil, holder)
    row:SetHyperlinksEnabled(true)
    row:SetScript("OnHyperlinkClick", function(_, link, text, button)
        _G.SetItemRef(link, text, button)
    end)
    row:SetScript("OnHyperlinkEnter", LinkEnter)
    row:SetScript("OnHyperlinkLeave", LinkLeave)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", StepClick)
    row:SetScript("OnEnter", function(self) StepTip(self.box or self, self.step) end)
    row:SetScript("OnLeave", TipHide)
    row.icon = Text(row, K.ICON_SIZE)
    row.glyph = row:CreateTexture(nil, "OVERLAY")
    row.check = row:CreateTexture(nil, "OVERLAY", nil, 1)
    row.check:SetTexture(K.CHECK)
    row.check:SetSize(K.CHECK_SIZE, K.CHECK_SIZE)
    row.lineHit = Lines.Make(row)
    row.meter = MakeBar(row)
    row.text = Text(row, Option("StepSize"))
    row.text:SetWordWrap(true)
    Draggable(row)
    return row
end

local function MakeLine(holder)
    local line = Text(holder, Option("ListSize"))
    line:SetWordWrap(false)
    return { row = line }
end

local function MakeHit(holder)
    local hit = CreateFrame("Button", nil, holder)
    hit:RegisterForClicks("LeftButtonUp")
    hit.shade = hit:CreateTexture(nil, "BACKGROUND")
    hit.shade:SetAllPoints()
    hit:SetScript("OnClick", function(self)
        if self.menu then return PickGuide() end
        if MaySkip() then GoTo(self.index) end
    end)
    hit:SetScript("OnEnter", function(self)
        local full = not self.menu and CutText(self.line) or nil
        local key = SkipKey()
        if not self.menu and not key then
            if full then Tip(self, nil, full) end
            return
        end
        local accent = Theme.Tokens().accent
        self.shade:SetColorTexture(accent[1], accent[2], accent[3], K.HOVER_ALPHA)
        self.shade:Show()
        if self.menu then
            Tip(self, K.TEXT_NONE, nil, K.KEY_CLICK, K.TEXT_PICK)
        else
            -- A cut line's full text starts with its number, so it stands in for the heading.
            Tip(self, K.TEXT_STEP:format(self.index or 0), full, key, K.TEXT_GO)
        end
    end)
    hit:SetScript("OnLeave", function(self)
        self.shade:Hide()
        TipHide()
    end)
    Draggable(hit)
    return hit
end

local function Pools()
    if not pools then
        pools = {
            box = KE.FramePool:New(MakeBox),
            row = KE.FramePool:New(MakeRow),
            line = KE.FramePool:New(MakeLine),
            hit = KE.FramePool:New(MakeHit),
            timer = KE.FramePool:New(Timers.MakeSlot),
        }
    end
    return pools
end

local function ReleaseAll()
    for _, pool in pairs(Pools()) do pool:ReleaseAll() end
    linesDrawn = 0
end

---------------------------------------------------------------------------------
-- RestedXP's countdown bars
---------------------------------------------------------------------------------
-- RestedXP files each bar under the label it gives it. A frame another addon has
-- taken since carries that addon's label, which can be secret.
function Timers.Labeled(bar, key)
    if not Has(bar, "GetLabel") then return false end
    local text = bar:GetLabel()
    if Secret(text) then return false end
    return (text or "") == key
end

-- RestedXP's table can hold a key whose frame is no longer its bar, and one frame
-- under two keys, so a bar counts only under the key it was started under. An error
-- in a post-hook reaches RestedXP's own caller, so the note runs guarded.
function Timers.Started(duration, label)
    if not (active and window) then return end
    Run("WindowTimerStart", Timers.Note, duration, label)
end

function Timers.Note(duration, label)
    local frame = Dig(_G.RXP, "RXPFrame")
    -- The start's own refusal: past it, the entry under the label is the bar it started.
    if type(duration) ~= "number" or duration <= 0 or not (Has(frame, "IsShown") and frame:IsShown()) then return end
    label = label or ""
    local bar = Dig(frame, "BarContainer", "bars", label)
    if type(bar) ~= "table" or not Timers.Labeled(bar, label) then return end
    Timers.owned[bar] = label
    -- RestedXP's sort inside the start ran before this, so the new bar is taken here,
    -- unseen until the redraw gives it a line. Under a held grip that is the release's
    -- redraw, even for a bar restarted on a frame that already has a line.
    if sizing then Timers.slotOf[bar] = nil end
    Timers.busy = true
    Run("WindowTimerTake", Timers.Keep, bar)
    Timers.busy = false
    Refresh()
end

-- RestedXP's sort hangs every bar of its table under its own footer again, so the
-- bars the window holds go back to their lines in the same call.
function Timers.Sorted()
    if not active or Timers.busy or not window then return end
    -- A bar taken under a hidden window hides, and RestedXP's hide handler sorts again.
    Timers.busy = true
    Timers.Hold()
    Timers.busy = false
    Refresh()
end

-- The library calls this before it hides and caches the bar. RestedXP restarts a bar
-- from its own pool without the library's reset, so the bar gets its own look back
-- first, and hides under a shown parent, which RestedXP's hide handler needs. The
-- library lists the bar as free itself once every listener has run, and not before:
-- a listener that made a bar in between could take this one while it still stops.
function Timers.Stopped(_, bar)
    if type(bar) ~= "table" then return end
    Timers.owned[bar] = nil
    local home = Timers.taken[bar]
    if not home then return end
    Timers.Forget(bar)
    if Run("WindowTimerHeld", Timers.Held, bar) then Run("WindowTimerBack", Timers.Restore, bar, home, false) end
    Refresh()
end

-- Only while the window runs. Every copy of the library shares one callback table.
function Timers.Watch(on)
    local candy = LibStub and LibStub("LibCandyBar-3.0", true)
    if not (Has(candy, "RegisterCallback") and Has(candy, "UnregisterCallback")) then return end
    if on then
        Run("WindowTimerWatch", candy.RegisterCallback, Timers, "LibCandyBar_Stop", Timers.Stopped)
    else
        Run("WindowTimerUnwatch", candy.UnregisterCallback, Timers, "LibCandyBar_Stop")
    end
end

function Timers.Hook(rxp)
    if not (Has(rxp, "SortTimers") and Has(rxp, "StartTimer")) then
        Safe.Missing("Timer bars", "timer calls")
        return
    end
    hooksecurefunc(rxp, "SortTimers", Timers.Sorted)
    hooksecurefunc(rxp, "StartTimer", Timers.Started)
end

-- KE's frame behind one bar: its border, a divider and the clock. The bar is the
-- window's child, because each redraw hides the slots it releases, and a bar that
-- hides drops out of RestedXP's table.
function Timers.MakeSlot(holder)
    local slot = CreateFrame("Frame", nil, holder)
    KE:AddBorders(slot, colors.boxBorder)
    slot.clock = slot:CreateTexture(nil, "ARTWORK")
    slot.clock:SetTexture(K.CLOCK)
    slot.divider = slot:CreateTexture(nil, "ARTWORK")
    return slot
end

function Timers.PaintSlot(slot, y, inner, room)
    local edge, accent, px = colors.boxBorder, colors.accent, KE:GetPixelSize()
    local icon = room - K.TIMER_ICON_INSET * 2
    slot:ClearAllPoints()
    slot:SetPoint("TOPLEFT", window, "TOPLEFT", K.PAD, y)
    slot:SetSize(inner, room)
    slot:SetBorderColor(edge[1], edge[2], edge[3], edge[4])
    slot.clock:ClearAllPoints()
    slot.clock:SetPoint("CENTER", slot, "TOPLEFT", room / 2, -room / 2)
    slot.clock:SetSize(icon, icon)
    slot.clock:SetVertexColor(accent[1], accent[2], accent[3])
    slot.divider:ClearAllPoints()
    slot.divider:SetPoint("TOPLEFT", slot, "TOPLEFT", room - px, 0)
    slot.divider:SetPoint("BOTTOMLEFT", slot, "BOTTOMLEFT", room - px, 0)
    slot.divider:SetWidth(px)
    slot.divider:SetColorTexture(edge[1], edge[2], edge[3], edge[4])
    slot.room = room
end

-- The library's list of free bars, which its New hands frames out from.
function Timers.Cache()
    local cache = Dig(LibStub and LibStub("LibCandyBar-3.0", true), "barCache")
    return type(cache) == "table" and cache or nil
end

-- RestedXP's running bars by label.
function Timers.Bars()
    local bars = Dig(_G.RXP, "RXPFrame", "BarContainer", "bars")
    return type(bars) == "table" and bars or nil
end

function Timers.Held(bar)
    return bar:GetParent() == window
end

-- Which icon calls a bar takes. A newer copy of the library keeps an icon flag in a
-- table an older copy's bar does not have, and fails there, so that bar takes none.
function Timers.IconMode(bar)
    if not Has(bar, "SetIconVisibility") then return "plain" end
    if type(bar.data) == "table" then return "flag" end
    return nil
end

-- First touch only, so a later hold cannot store the window's look as RestedXP's.
function Timers.Take(bar)
    if Timers.taken[bar] then return end
    local label, timeText, fill, back = bar.candyBarLabel, bar.candyBarDuration, bar.candyBarBar, bar.candyBarBackground
    local home = {
        parent = bar:GetParent(), strata = bar:GetFrameStrata(), level = bar:GetFrameLevel(), alpha = bar:GetAlpha(),
        fill = fill:GetStatusBarTexture():GetTexture(), fillColor = { fill:GetStatusBarColor() },
        back = back:GetTexture(), backColor = { back:GetVertexColor() },
        labelFont = { label:GetFont() }, timeFont = { timeText:GetFont() }, textColor = { label:GetTextColor() },
        shadowOffset = { label:GetShadowOffset() }, shadowColor = { label:GetShadowColor() },
        icon = bar:GetIcon(),
    }
    local mode = Timers.IconMode(bar)
    if mode == "flag" then home.iconShown = bar:IsIconVisible() == true end
    -- A newer copy loaded later replaces this setter with one this bar cannot run, so
    -- the record keeps the one the bar was made with.
    if mode == "plain" then home.setIcon = bar.SetIcon end
    -- RestedXP restarts a stopped bar from its own pool, which leaves the library
    -- listing it as free. While the window holds it, no addon's New can hand it out.
    local cache = Timers.Cache()
    if cache and cache[bar] then
        home.cached = true
        cache[bar] = nil
    end
    Timers.taken[bar] = home
    bar:SetParent(window)
    bar:SetAlpha(0)
    -- Under a hidden window the bar hides, and RestedXP's hide handler drops it.
    local bars = Timers.Bars()
    if bars then Timers.PutBack(bars, bar, GetTime()) end
end

-- RestedXP writes its icon, color and height again on a bar it starts again, so a
-- held bar is dressed at every hold.
function Timers.Dress(bar)
    local fill, back, text = colors.barFill, colors.barBack, colors.text
    local size = Option("ListSize")
    bar:SetTexture(K.WHITE)
    bar:SetColor(fill[1], fill[2], fill[3], fill[4])
    bar:SetBackgroundColor(back[1], back[2], back[3], back[4])
    Faced(bar.candyBarLabel, size)
    Faced(bar.candyBarDuration, size)
    bar:SetTextColor(text[1], text[2], text[3], text[4])
    -- One version of the library lays out the icon's square while this flag is on.
    local mode = Timers.IconMode(bar)
    if mode == "flag" then bar:SetIconVisibility(false) end
    if mode then bar:SetIcon(nil) end
end

-- RestedXP's sort hangs each bar on the one before it, so a bar it hung on this one
-- would follow it into the window. That bar takes this one's anchors instead, the
-- place RestedXP's column gives it without this one. A bar already on its slot was
-- not hung on since, because only RestedXP's sort hangs bars.
function Timers.HandOver(bar, slot)
    local n = bar:GetNumPoints()
    if Secret(n) or n == 0 then return end
    local first = select(2, bar:GetPoint(1))
    if Secret(first) or first == slot then return end
    -- An anchor the client keeps secret is neither compared nor handed on.
    for i = 2, n do
        if Secret((select(2, bar:GetPoint(i)))) then return end
    end
    local bars = Timers.Bars()
    if not bars then return end
    for _, other in pairs(bars) do
        local rel = other ~= bar and Has(other, "GetPoint") and select(2, other:GetPoint(1))
        if not Secret(rel) and rel == bar then
            -- One frame under two keys could hang the bar on the frame it hands over to.
            local loops = false
            for i = 1, n do
                if select(2, bar:GetPoint(i)) == other then loops = true end
            end
            if not loops then
                other:ClearAllPoints()
                for i = 1, n do other:SetPoint(bar:GetPoint(i)) end
            end
        end
    end
end

-- The level is set each time: a new parent may change the level the library gave.
function Timers.Place(bar, slot)
    local px = KE:GetPixelSize()
    Timers.HandOver(bar, slot)
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", slot, "TOPLEFT", slot.room, -px)
    bar:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -px, px)
    bar:SetFrameLevel(slot:GetFrameLevel() + 1)
    bar:SetAlpha(1)
end

function Timers.Keep(bar)
    Timers.Take(bar)
    Timers.Dress(bar)
    local slot = Timers.slotOf[bar]
    if slot then Timers.Place(bar, slot) else bar:SetAlpha(0) end
end

-- One guard a bar: RestedXP's sort has already hung every held bar in its column.
function Timers.Hold()
    local bars = Timers.Bars()
    if not bars then return end
    for key, bar in pairs(bars) do
        if Timers.owned[bar] == key then Run("WindowTimerHold", Timers.Keep, bar) end
    end
end

function Timers.Forget(bar)
    Timers.taken[bar], Timers.slotOf[bar] = nil, nil
    local label, timeText = Dig(bar, "candyBarLabel"), Dig(bar, "candyBarDuration")
    if label then dressed[label] = nil end
    if timeText then dressed[timeText] = nil end
end

-- listed: whether to list the bar as free again, for a give back. A stop leaves that
-- to the library. The parent and the listing come first, so a failure in the look
-- still leaves the frame RestedXP's and free.
function Timers.Restore(bar, home, listed)
    bar:SetParent(home.parent or UIParent)
    local cache = listed and home.cached and Timers.Cache()
    if cache then cache[bar] = true end
    bar:SetFrameStrata(home.strata)
    bar:SetFrameLevel(home.level)
    bar:SetAlpha(home.alpha)
    -- A getter can return no path, which these setters refuse: the fill falls back to
    -- RestedXP's own texture, and a font with no path stays as it is.
    local fill = home.fill or Dig(_G.RXP, "RXPFrame", "BarContainer", "barTexture")
    if fill then bar.candyBarBar:SetStatusBarTexture(fill) end
    bar.candyBarBar:SetStatusBarColor(unpack(home.fillColor))
    bar.candyBarBackground:SetTexture(home.back)
    bar.candyBarBackground:SetVertexColor(unpack(home.backColor))
    if home.labelFont[1] then bar.candyBarLabel:SetFont(unpack(home.labelFont)) end
    if home.timeFont[1] then bar.candyBarDuration:SetFont(unpack(home.timeFont)) end
    bar:SetTextColor(unpack(home.textColor))
    bar:SetShadowOffset(unpack(home.shadowOffset))
    bar:SetShadowColor(unpack(home.shadowColor))
    local mode = Timers.IconMode(bar)
    if mode == "flag" and home.iconShown ~= nil then bar:SetIconVisibility(home.iconShown) end
    if mode then
        bar:SetIcon(home.icon)
    elseif home.setIcon then
        home.setIcon(bar, home.icon)
    end
end

-- RestedXP drops a bar from its table when the bar hides with the window while it
-- still runs. It goes back under its label at once, as RestedXP's own show puts bars
-- back, so RestedXP's stop still reaches it while the window is hidden.
function Timers.PutBack(bars, bar, now)
    local label = Timers.owned[bar]
    if label and bars[label] == nil and bar:IsShown() and type(bar.exp) == "number" and bar.exp > now then
        bars[label] = bar
    end
end

function Timers.Refill()
    local bars = Timers.Bars()
    if not bars then return end
    local now = GetTime()
    for bar in pairs(Timers.taken) do
        if Run("WindowTimerHeld", Timers.Held, bar) then Run("WindowTimerPutBack", Timers.PutBack, bars, bar, now) end
    end
end

-- A hide KE did not cause, as the whole interface hiding, drops bars the same way.
function Timers.Order(bars, now)
    Timers.Refill()
    return Rules.TimerOrder(bars, Timers.owned, now)
end

-- Before the window hides, so no bar it holds drops out of RestedXP's table, and
-- RestedXP's own sort then hangs them under its footer again.
function Timers.GiveBack()
    local bars = Timers.Bars()
    local now, gave = GetTime(), false
    for bar, home in pairs(Timers.taken) do
        Timers.Forget(bar)
        if Run("WindowTimerHeld", Timers.Held, bar) then
            gave = true
            Run("WindowTimerBack", Timers.Restore, bar, home, true)
            if bars then Run("WindowTimerPutBack", Timers.PutBack, bars, bar, now) end
        end
    end
    wipe(Timers.owned)
    wipe(Timers.slotOf)
    local rxp = _G.RXP
    if gave and Has(rxp, "SortTimers") then Run("WindowTimerGiveSort", rxp.SortTimers, rxp) end
end

-- Under the last step box and above NEXT STEPS, one line a bar. A held grip draws the
-- order and count it pressed on, so the height it reads stays the list's.
function Timers.DrawSlot(y, inner, room)
    if not sizing then
        local bars = Timers.Bars()
        local list = bars and Run("WindowTimerRead", Timers.Order, bars, GetTime()) or Timers.none
        Timers.list, Timers.shown = list, #list
        for i, bar in ipairs(list) do Timers.starts[i] = bar.start end
    end
    wipe(Timers.slotOf)
    for i = 1, Timers.shown do
        local slot = Pools().timer:Acquire(window)
        Timers.PaintSlot(slot, y, inner, room)
        local bar = Timers.list[i]
        if bar and not Run("WindowTimerLine", Timers.Lined, bar, i) then bar = nil end
        slot:SetShown(bar ~= nil)
        if bar then Timers.slotOf[bar] = slot end
        y = y - room
    end
    if Timers.shown > 0 then y = y - K.GAP end
    return y
end

-- Under a held grip a line keeps only its own run: a bar that ended has left the
-- owner map, and a frame RestedXP started again since has a new start.
function Timers.Lined(bar, i)
    return Timers.owned[bar] ~= nil and bar.start == Timers.starts[i] and bar:IsShown()
end

function Timers.Fade(bar)
    if Timers.Held(bar) then bar:SetAlpha(0) end
end

function Timers.Wait()
    for bar in pairs(Timers.taken) do
        if not Timers.slotOf[bar] then Run("WindowTimerWait", Timers.Fade, bar) end
    end
end

-- After the window shows: a bar taken under a hidden window hides, and RestedXP's
-- hide handler drops it from its table.
function Timers.Seat()
    for bar in pairs(Timers.slotOf) do Run("WindowTimerSeat", Timers.Keep, bar) end
    Timers.Wait()
end

---------------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------------
local function DrawIcon(item, row, size)
    local path = Icons.PathOf(row.icon)
    if not path then
        item.glyph:Hide()
        item.icon:SetText(row.icon)
        return
    end
    item.icon:SetText("")
    item.glyph:ClearAllPoints()
    item.glyph:SetPoint("TOPLEFT", item.icon, "TOPLEFT", 0, 0)
    item.glyph:SetSize(size, size)
    item.glyph:SetTexture(path)
    local accent = colors.accent
    item.glyph:SetVertexColor(accent[1], accent[2], accent[3])
    item.glyph:SetAlpha(row.done and K.ICON_DONE_ALPHA or 1)
    item.glyph:Show()
end

local function DrawMeter(item, row, fill, x, y, width)
    item.meter:ClearAllPoints()
    item.meter:SetPoint("TOPLEFT", item, "TOPLEFT", x, -y)
    item.meter:SetWidth(width)
    local height = PaintBar(item.meter, fill)
    item.meter:Show()
    if row.bags then wantsBags = true end
    return height
end

local function DrawRow(parent, row, x, y, width, first)
    local item = Pools().row:Acquire(parent)
    item.box = parent ~= window and parent or nil
    item.step = row.step
    item:ClearAllPoints()
    item:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    item:SetWidth(width)
    local iconSize, textSize = K.ICON_SIZE, Option("StepSize")
    if first then
        textSize = textSize + K.FIRST_GROW
        iconSize = iconSize + K.FIRST_GROW * K.FIRST_ICON_GROW
    end
    -- A row with no icon gives the column to its text.
    local hasIcon = type(row.icon) == "string" and row.icon ~= ""
    local iconW = hasIcon and iconSize + K.ICON_GAP or 0
    local drop = hasIcon and math_max(0, floor((iconSize - textSize) / 2)) or 0
    local textWidth = width - iconW
    item.icon:ClearAllPoints()
    item.icon:SetPoint("TOPLEFT", item, "TOPLEFT", 0, 0)
    Faced(item.icon, iconSize)
    DrawIcon(item, row, iconSize)
    Lines.Draw(item, row, hasIcon and iconSize or nil)
    item.text:ClearAllPoints()
    item.text:SetPoint("TOPLEFT", item, "TOPLEFT", iconW, -drop)
    item.text:SetWidth(textWidth)
    Colored(item.text, row.done and "muted" or "text")
    Faced(item.text, textSize)
    item.text:SetText(row.text)
    local height = math_max(drop + math_max(item.text:GetStringHeight(), textSize), hasIcon and iconSize or 0)
    local fill = Rules.CountFill(row.have, row.need, row.bags, row.done)
    if fill then
        height = height + K.COUNT_GAP + DrawMeter(item, row, fill, iconW, height + K.COUNT_GAP, textWidth)
    else
        item.meter:Hide()
    end
    item:SetHeight(height)
    Watch(row.source)
    return height
end

local function DrawBox(step, y, inner)
    local box = Pools().box:Acquire(window)
    box.step = step.source
    local size = Option("StepSize")
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", window, "TOPLEFT", K.PAD, y)
    box:SetWidth(inner)
    local fill, edge, accent = colors.box, colors.boxBorder, colors.accent
    box.back:SetColorTexture(fill[1], fill[2], fill[3], fill[4])
    box:SetBorderColor(edge[1], edge[2], edge[3], edge[4])
    box.flash:SetColorTexture(accent[1], accent[2], accent[3], 1)
    Faced(box.label, size)
    Colored(box.label, "accent")
    box.label:SetText(step.label:upper())
    Faced(box.yards, size)
    Colored(box.yards, "text")
    box.yards:SetAlpha(K.YARDS_ALPHA)
    box.yards:SetText("")
    local pad, gap = K.BOX_PAD, K.GAP
    local by = -pad - size - gap
    local column = K.ICON_SIZE + K.ICON_GAP
    for i, row in ipairs(step.rows) do
        local set = i > 1 and row.nested and column or 0
        by = by - DrawRow(box, row, pad + set, by, inner - pad * 2 - set, i == 1) - gap
    end
    box:SetHeight(-by + pad - gap)
    lastBox = box
    return y + by - pad
end

local function DrawFold(folded, topH)
    local fold = window.fold
    fold:SetSize(K.FOLD_W, topH)
    fold:ClearAllPoints()
    fold:SetPoint("TOPRIGHT", window, "TOPRIGHT", -K.PAD - K.FOLD_W - K.TOP_GAP, -K.PAD)
    Faced(fold.text, Option("ListSize") + K.FOLD_GROW)
    fold.text:SetText(folded and K.TEXT_UNFOLD or K.TEXT_FOLD)
    Colored(fold.text, "line")
end

-- Returns where the chapter row starts.
local function DrawTop(model, folded, width, topH)
    local pad, button = K.PAD, K.FOLD_W
    local line = colors.line
    local cog = window.cog
    cog:SetSize(button, topH)
    cog:ClearAllPoints()
    cog:SetPoint("TOPRIGHT", window, "TOPRIGHT", -pad, -pad)
    cog.icon:SetVertexColor(line[1], line[2], line[3], line[4])
    DrawFold(folded, topH)
    local group = window.group
    group:ClearAllPoints()
    group:SetPoint("LEFT", window, "TOPLEFT", pad, -pad - topH / 2)
    -- A width of 0 would let the name run under the buttons.
    group:SetWidth(math_max(1, width - pad * 2 - button * 2 - K.TOP_GAP - K.GAP))
    Faced(group, Option("ListSize"))
    Colored(group, "muted")
    group:SetText(model.group or "")
    local below = -pad - topH
    window.divider:ClearAllPoints()
    window.divider:SetPoint("TOPLEFT", window, "TOPLEFT", pad, below)
    window.divider:SetPoint("TOPRIGHT", window, "TOPRIGHT", -pad, below)
    window.divider:SetColorTexture(line[1], line[2], line[3], line[4])
    -- The mark is centered on the title's line, so a small title lifts it toward the
    -- divider, and the row then starts lower.
    local gap = K.ROW_GAP
    if Option("ShowMark") then
        gap = math_max(gap, K.MARK_SIZE / 2 + K.MARK_CLEAR - floor(Option("TitleSize") / 2))
    end
    return below - gap
end

-- Centered on the title's line. Returns the width it takes from the title.
local function DrawMark(x, top, titleSize)
    local shown = Option("ShowMark")
    window.rim:SetShown(shown)
    window.k:SetShown(shown)
    if not shown then return 0 end
    local muted, accent = colors.muted, colors.accent
    window.rim:SetVertexColor(muted[1], muted[2], muted[3])
    window.k:SetVertexColor(accent[1], accent[2], accent[3])
    local size, y = K.MARK_SIZE, top - titleSize / 2
    window.rim:ClearAllPoints()
    window.rim:SetPoint("CENTER", window, "TOPLEFT", x + size / 2, y)
    window.k:ClearAllPoints()
    window.k:SetPoint("CENTER", window, "TOPLEFT", x + size / 2, y)
    return size + K.GAP
end

local function DrawHeader(model, width, top)
    local pad, gap = K.PAD, K.GAP
    local size = Option("TitleSize")
    window.progress:ClearAllPoints()
    window.progress:SetPoint("TOPRIGHT", window, "TOPRIGHT", -pad, top)
    Faced(window.progress, size)
    if model.step then
        window.progress:SetText(Tint("accent", ("%d/%d"):format(model.step, model.total)) .. K.TEXT_DOT
            .. ("%d%%"):format(model.percent))
    else
        window.progress:SetText("")
    end
    -- A color escape is opaque, so the percent takes the string's color and alpha.
    Colored(window.progress, "title")
    local x = pad + DrawMark(pad, top, size)
    window.title:ClearAllPoints()
    window.title:SetPoint("TOPLEFT", window, "TOPLEFT", x, top)
    -- A width of 0 would let the string run under the progress.
    window.title:SetWidth(math_max(1, width - x - pad - window.progress:GetStringWidth() - gap))
    Faced(window.title, size)
    Colored(window.title, "title")
    window.title:SetText(model.heading)
end

local function DrawLine(model, y)
    local line, pad = Option("UnderTitle"), K.PAD
    window.rule:Hide()
    window.bar:Hide()
    if line == "bar" then
        window.bar:ClearAllPoints()
        window.bar:SetPoint("TOPLEFT", window, "TOPLEFT", pad, y)
        window.bar:SetPoint("TOPRIGHT", window, "TOPRIGHT", -pad, y)
        local height = PaintBar(window.bar, model.fraction or 0)
        window.bar:Show()
        return y - height - K.GAP
    elseif line == "rule" then
        local c = colors.line
        window.rule:ClearAllPoints()
        window.rule:SetPoint("TOPLEFT", window, "TOPLEFT", pad, y)
        window.rule:SetPoint("TOPRIGHT", window, "TOPRIGHT", -pad, y)
        window.rule:SetColorTexture(c[1], c[2], c[3], c[4])
        window.rule:Show()
        return y - K.GAP
    end
    return y
end

local function DrawPanel()
    local panel, edge = colors.panel, colors.border
    if panel then window.back:SetColorTexture(panel[1], panel[2], panel[3], panel[4]) end
    window.back:SetShown(panel ~= nil)
    window:SetBorderColor(edge[1], edge[2], edge[3], edge[4])
    local showEdge = Option("Border")
    for _, texture in pairs(window.borders) do texture:SetShown(showEdge) end
end

local function ListLine(y, inner, listH, text, index, menu, look, barred)
    local line = Pools().line:Acquire(window).row
    linesDrawn = linesDrawn + 1
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", window, "TOPLEFT", K.PAD, y)
    line:SetWidth(barred and inner - K.SCROLL_ROOM or inner)
    Faced(line, Option("ListSize"))
    Colored(line, look == "current" and "accent" or "muted")
    line:SetAlpha(look == "done" and K.DONE_ALPHA or 1)
    line:SetText(text)
    local hit = Pools().hit:Acquire(window)
    hit:ClearAllPoints()
    hit:SetPoint("TOPLEFT", window, "TOPLEFT", K.PAD, y)
    hit:SetSize(inner, listH)
    hit.index, hit.menu, hit.line = index, menu, line
    hit.shade:Hide()
    return y - listH
end

local function DrawScrollBar(from, height, top, count, total)
    local grip = math_max(K.SCROLL_MIN, height * count / total)
    local share = math_min(1, (top - 1) / (total - count))
    local line, accent = colors.line, colors.accent
    window.track:ClearAllPoints()
    window.track:SetPoint("TOPRIGHT", window, "TOPRIGHT", -K.PAD, from)
    window.track:SetSize(K.SCROLL_W, height)
    window.track:SetColorTexture(line[1], line[2], line[3], line[4])
    window.thumb:ClearAllPoints()
    window.thumb:SetPoint("TOPRIGHT", window, "TOPRIGHT", -K.PAD, from - share * (height - grip))
    window.thumb:SetSize(K.SCROLL_W, grip)
    window.thumb:SetColorTexture(accent[1], accent[2], accent[3], accent[4])
end

local function DrawNextLabel(y, listH)
    local label = window.nextLabel
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", window, "TOPLEFT", K.PAD, y)
    Faced(label, Option("ListSize"))
    Colored(label, "accent")
    label:SetText(K.TEXT_NEXT)
    label:Show()
    window.labelLines = K.LABEL_LINES
    return y - listH
end

local function DrawSteps(model, y, inner, listH)
    local list = model.list
    local count = sizing and sizing.steps or Option("ListedSteps")
    local top
    top, scroll = Rules.ListWindow(model.first, scroll, count, #list)
    local last = math_min(#list, top + count - 1)
    local scrollable = count > 0 and #list > count
    local barred = scrollable and Option("ScrollBar")
    if last >= top then y = DrawNextLabel(y, listH) end
    local from = y
    for i = top, last do
        local entry = list[i]
        local look = model.current[entry.index] and "current" or entry.done and "done" or nil
        y = ListLine(y, inner, listH, ("%d  %s"):format(entry.index, Model.LineText(entry)), entry.index, false,
            look, barred)
    end
    window.track:SetShown(barred)
    window.thumb:SetShown(barred)
    window.wheel:ClearAllPoints()
    window.wheel:SetPoint("TOPLEFT", window, "TOPLEFT", K.PAD, from)
    window.wheel:SetSize(inner, math_max(count, 1) * listH)
    window.wheel:EnableMouseWheel(scrollable)
    window.wheel:SetShown(scrollable)
    if barred then DrawScrollBar(from, from - y, top, count, #list) end
    return y
end

local function DrawList(model, y, inner, listH)
    if model.empty then y = ListLine(y, inner, listH, K.TEXT_PICK, nil, true, "current") end
    for _, step in ipairs(model.steps) do y = DrawBox(step, y, inner) end
    y = Timers.DrawSlot(y, inner, listH)
    return DrawSteps(model, y, inner, listH)
end

local function DrawFolded(model, y, inner)
    if not Option("FoldObjective") then return y end
    local step = model.steps[#model.steps]
    local row = step and step.rows[1]
    if not row then return y end
    return y - DrawRow(window, row, K.PAD, y, inner, false) - K.GAP
end

local function DrawChrome(y, listH, folded)
    if not sizing then window:SetHeight(-y + K.PAD) end
    if wantsBags then window:RegisterEvent(K.BAG_EVENT) else window:UnregisterEvent(K.BAG_EVENT) end
    window.lineHeight = listH
    -- The label is left out, so showing or hiding it under a held grip cannot change
    -- how many steps a height means.
    window.chrome = -y + K.PAD - (linesDrawn + window.labelLines) * listH
    local locked = Option("Lock")
    window:SetResizable(not locked and not folded)
    window:SetResizeBounds(K.WIDTH_MIN, window.chrome, K.WIDTH_MAX,
        window.chrome + (K.STEPS_MAX + K.LABEL_LINES) * listH)
    window.grip:SetShown(not folded and not locked)
end

local function OnYards(af)
    if not (active and yardBox and Option("StepYards")) then return end
    local distance = Dig(af, "distance")
    local show = Has(af, "IsShown") and af:IsShown() and af.alpha ~= 0 and not af.wrongContinent
        and not Secret(distance) and type(distance) == "number"
    local text = show and K.TEXT_YARDS:format(distance) or ""
    if text == yardText then return end
    yardText = text
    yardBox.yards:SetText(text)
end

function Draw()
    if not active then return true end
    wantsBags, lastBox, yardBox, yardText = false, nil, nil, nil
    colors = Theme.WindowColors()
    ReadFont()
    window = window or Build()
    if not sizing and retake then
        retake = not Take()
        Repaint()
    end
    if not allowedHere then
        window:Hide()
        -- The hide drops the window's bars from RestedXP's table, and its stop needs them.
        Run("WindowTimerKeep", Timers.Refill)
        return true
    end
    local model = sizing and sizingModel or Model.Read(_G.RXP, READ_OPTIONS) or Model.NoGuide()
    if not sizing and model.guide ~= anchorGuide then wipe(READ_OPTIONS.hidden) end
    local moved = not sizing and (model.guide ~= anchorGuide or model.after ~= anchorAfter)
    local flash = moved and Option("StepFlash") and Rules.ShouldFlash(anchorGuide, anchorAfter, model.guide, model.after)
    if moved then scroll = 0 end
    ReleaseAll()
    local width = sizing and sizing.width or Option("Width")
    local folded = Option("Folded")
    local headH = Option("TitleSize") + K.HEAD_PAD
    local listH = Option("ListSize") + K.LIST_PAD
    if not sizing then window:SetWidth(width) end
    DrawPanel()
    local top = DrawTop(model, folded, width, listH)
    DrawHeader(model, width, top)
    local y = DrawLine(model, top - headH)
    window.track:Hide()
    window.thumb:Hide()
    window.wheel:Hide()
    window.nextLabel:Hide()
    window.labelLines = 0
    if folded then
        y = Timers.DrawSlot(DrawFolded(model, y, width - K.PAD * 2), width - K.PAD * 2, listH)
    else
        y = DrawList(model, y, width - K.PAD * 2, listH)
    end
    DrawChrome(y, listH, folded)
    window:Show()
    Timers.Seat()
    yardBox = lastBox
    if yardBox then OnYards(_G.RXPG_ARROW) end
    if flash and lastBox then lastBox.flashAnim:Play() end
    -- Kept only after a full pass, so a failed one is retried.
    if moved then anchorGuide, anchorAfter = model.guide, model.after end
    return true
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
local function TestShowIn()
    local _, kind = IsInInstance()
    allowedHere = Rules.ShowInAllowed(kind, Option("ShowOpenWorld"), Option("ShowDungeons"), Option("ShowRaids"),
        Option("ShowPvP"))
end

local function Activate(want)
    if want == active then
        if active then Refresh() end
        return
    end
    active = want
    if want then
        retake = true
        Model.Stale()
        TestShowIn()
        RefreshAccepts()
        Timers.Watch(true)
        ApplyGeometry()
        Redraw()
        if window then
            window:RegisterEvent("PLAYER_REGEN_DISABLED")
            window:RegisterEvent("PLAYER_REGEN_ENABLED")
            window:SetAlpha(InCombatLockdown() and Option("CombatFade") / K.PERCENT or 1)
        end
    else
        Release()
        wipe(READ_OPTIONS.hidden)
        Timers.Watch(false)
        Run("WindowTimerGive", Timers.GiveBack)
        if window then
            window:Hide()
            window:UnregisterAllEvents()
        end
        Repaint()
    end
end

local function HookRebuilt(owner, name)
    if Has(owner, name) then hooksecurefunc(owner, name, Rebuilt) end
end

function Window.Start()
    if not started then
        started = true
        local rxp = _G.RXP
        if Has(rxp, "SetStep") then hooksecurefunc(rxp, "SetStep", StepChanged) end
        local v2 = Dig(rxp, "v2")
        HookRebuilt(v2, "UpdateGuideWindow")
        HookRebuilt(v2, "UpdateActiveStepsFrame")
        HookRebuilt(v2, "UpdatePlayerActiveStepItem")
        if Has(v2, "RefreshActivePartyTabs") then hooksecurefunc(v2, "RefreshActivePartyTabs", OnPartyTabs) end
        WatchGuideRows()
        Timers.Hook(rxp)
    end
    Arrow.WatchYards(OnYards)
    Activate(true)
end

function Window.Stop()
    if not active then return end
    Arrow.WatchYards(nil)
    Activate(false)
end

function Window.IsActive()
    return active == true
end

-- How many of RestedXP's bars the window holds now, for the smoke's macros.
function Window.HeldTimers()
    local count = 0
    for bar in pairs(Timers.taken) do
        if Run("WindowTimerHeld", Timers.Held, bar) then count = count + 1 end
    end
    return count
end

-- How many of Targets and Items show KE's header band now, for the smoke's macros.
function Window.Banded()
    local count = 0
    for _, band in pairs(Band.of) do
        if band.fill:IsShown() then count = count + 1 end
    end
    return count
end

-- A color setting or KE's accent changed. Targets and Items repaint only when told,
-- and wait out combat; the window takes the new colors on its next redraw.
function Window.Recolor()
    if not active then return end
    Repaint()
    Refresh()
end

function Window.ApplySettings()
    ApplyGeometry()
    if not active then return end
    TestShowIn()
    Window.Recolor()
end

-- One SetScale for the whole window, keeping it in place on screen.
function Window.SetScale(percent)
    local was = window and window:GetScale() or Option("Scale") / K.PERCENT
    DB().Scale = percent
    local now = Option("Scale") / K.PERCENT
    local saved = DB().WindowPos
    if window then
        local point, _, relativePoint, x, y = window:GetPoint(1)
        window:SetScale(now)
        if point then
            window:ClearAllPoints()
            window:SetPoint(point, UIParent, relativePoint, x * was / now, y * was / now)
            Save(window)
        end
    elseif type(saved) == "table" then
        saved[3], saved[4] = saved[3] * was / now, saved[4] * was / now
    end
end

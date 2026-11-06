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
local InCombatLockdown, LibStub = InCombatLockdown, LibStub
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
    GRIP_UP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up",
    GRIP_DOWN = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down",
    GRIP_HIGHLIGHT = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight",
    GRIP_CORNER = "BOTTOMRIGHT",
    PERCENT = 100,
    PAD = 10, BOX_PAD = 7, FOLD_W = 16, PROGRESS_W = 120, GAP = 5,
    HEAD_PAD = 10, LIST_PAD = 6,
    BOX_TITLE_TEXT = 9, BOX_TITLE_HEIGHT = 19, BOX_TITLE_ROOM = 10,
    BAR_W = 2, ICON_GAP = 5, GRIP_SIZE = 16,
    FIRST_GROW = 2, FIRST_ICON_GROW = 2, MARK_SIZE = 24, BAR_HEIGHT = 5, INDENT = 12, ICON_SIZE = 18,
    HOVER_ALPHA = 0.25, ICON_DONE_ALPHA = 0.5, DONE_ALPHA = 0.5, YARDS_ALPHA = 0.85,
    COUNT_GAP = 2,
    REDRAW_GAP = 0.1,
    GUIDE_ROW_WIDGET = "RXPV2GuideStepsItem",
    FLASH_FROM = 0.4, FLASH_SECONDS = 0.55,
    BAG_EVENT = "BAG_UPDATE_DELAYED",
    SHADOW = { Enabled = true, OffsetX = 1, OffsetY = -1, Color = { 0, 0, 0, 0.9 } },
    TEXT_FOLD = "-", TEXT_UNFOLD = "+", TEXT_DOT = " \194\183 ",
    TEXT_YARDS = "\194\183 %d yd",
    TEXT_SKIP = "Skip step",
    TEXT_SHIFT = "Shift-click",
    TEXT_MENU = "Right-click: menu",
    TEXT_GO = "Go to step %d",
    TEXT_PICK = "Pick a guide",
    TIP_DIM = 0.7,
    WHEEL_LINES = 2,
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

Window.Refresh = Refresh

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

-- Shadow is not a font flag: it is no outline plus KE's shadow setting.
local function Faced(fs, size)
    local last = dressed[fs]
    if last and last.path == fontPath and last.size == size and last.outline == fontOutline then return end
    local shadow = fontOutline == "shadow"
    KE:ApplyFontToText(fs, fontName, size, shadow and "NONE" or fontOutline, shadow and K.SHADOW or nil)
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

local function KeepTitle(text)
    if titleHome[text] then return end
    local font, size, flags = text:GetFont()
    local r, g, b, a = text:GetTextColor()
    local shadowX, shadowY = text:GetShadowOffset()
    local shadowR, shadowG, shadowB, shadowA = text:GetShadowColor()
    titleHome[text] = {
        font = font, size = size, flags = flags, r = r, g = g, b = b, a = a,
        shadowX = shadowX, shadowY = shadowY, shadowR = shadowR, shadowG = shadowG, shadowB = shadowB, shadowA = shadowA,
    }
end

local function SkinTitle(title)
    SkinBox(title)
    local text = title.text
    if not Has(text, "GetFont") then return end
    KeepTitle(text)
    -- RestedXP writes this string's font in UpdateVisuals, so KE's last write says
    -- nothing about what it holds now.
    dressed[text] = nil
    Faced(text, K.BOX_TITLE_TEXT)
    Colored(text, "title")
    title:SetSize(text:GetStringWidth() + K.BOX_TITLE_ROOM, K.BOX_TITLE_HEIGHT)
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

local function RestoreTitles()
    for text, home in pairs(titleHome) do
        titleHome[text] = nil
        dressed[text] = nil
        if home.font then text:SetFont(home.font, home.size, home.flags or "") end
        if home.r then text:SetTextColor(home.r, home.g, home.b, home.a) end
        if home.shadowX then text:SetShadowOffset(home.shadowX, home.shadowY) end
        if home.shadowR then text:SetShadowColor(home.shadowR, home.shadowG, home.shadowB, home.shadowA) end
    end
end

local function SkinFrame(frame)
    SkinBox(frame)
    if frame.title then SkinTitle(frame.title) end
    SkinPlaceholders(frame)
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
        for _, frame in ipairs(frames) do SkinRestore(frame) end
    end
end

-- These frames hold secure buttons, so a repaint in combat waits, once.
function Repaint()
    if paintPending then return end
    paintPending = true
    KE:RunAfterCombat(function()
        paintPending = false
        PaintFrames()
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

-- A retained window keeps its scale and points across a reset, a Look change and
-- a profile switch, so every start and every settings pass sets them again. A held
-- grip or drag is left alone until it ends.
local function ApplyGeometry()
    if not window or sizing or moving then return end
    window:SetScale(Option("Scale") / K.PERCENT)
    Place(window)
end

local function Menu()
    local menu = Dig(_G.RXP, "RXPFrame", "DropDownMenu")
    if type(menu) == "function" then Run("WindowMenu", menu) end
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

-- A sticky step is not the guide's progress, so moving on would skip the wrong
-- one. Its objectives are marked skipped, as RestedXP's own checkbox does.
local function SkipObjectives(rxp, step)
    for _, element in ipairs(step.elements or {}) do
        if not element.optional and not element.skip then
            element.skip = true
            if type(element.OnComplete) == "function" then Run("WindowComplete", element.OnComplete, element) end
        end
    end
    rxp.updateSteps = true
    if Has(rxp, "UpdateMap") then Run("WindowMap", rxp.UpdateMap) end
end

local function SkipStep(step)
    local rxp = _G.RXP
    local progress = Run("WindowProgress", rxp.GetGuideProgress)
    if not progress then return end
    if step and step.index ~= progress then
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

local function Tip(owner, text, menu, plain)
    if not Option("Tips") or GameTooltip:IsForbidden() then return end
    local mode = Option("Skip")
    local accent = Theme.Tokens().accent
    local dim = K.TIP_DIM
    GameTooltip:SetOwner(owner, K.TIP_ANCHOR)
    if plain then
        GameTooltip:SetText(text, accent[1], accent[2], accent[3])
    elseif mode == "off" then
        GameTooltip:SetText(K.TEXT_MENU, accent[1], accent[2], accent[3])
    else
        GameTooltip:SetText(text, accent[1], accent[2], accent[3])
        if mode == "shift" then GameTooltip:AddLine(K.TEXT_SHIFT, dim, dim, dim) end
        if menu then GameTooltip:AddLine(K.TEXT_MENU, dim, dim, dim) end
    end
    GameTooltip:Show()
end

local function TipHide()
    if not GameTooltip:IsForbidden() then GameTooltip:Hide() end
end

---------------------------------------------------------------------------------
-- Sizing
---------------------------------------------------------------------------------
local function StepsFor(height)
    return floor((height - window.chrome) / window.lineHeight)
end

local function LiveSize(width, height)
    if not (sizing and sizingModel and window) then return end
    sizing.width = math_min(K.WIDTH_MAX, math_max(K.WIDTH_MIN, width))
    sizing.steps = math_max(0, math_min(K.STEPS_MAX, StepsFor(height)))
    Redraw()
end

local function GripReleased()
    if not sizing then return end
    local owner = sizing.db
    sizing, sizingModel = nil, nil
    window:StopMovingOrSizing()
    owner.Width = Rules.Option("Width", window:GetWidth())
    owner.ListedSteps = Rules.Option("ListedSteps", StepsFor(window:GetHeight()))
    Save(window, owner)
    if owner ~= DB() then ApplyGeometry() end
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
        sizing = { width = window:GetWidth(), steps = Option("ListedSteps"), db = DB() }
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
    f:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then Menu() end
    end)
    f:SetScript("OnEvent", OnWindowEvent)
    f.back = f:CreateTexture(nil, "BACKGROUND")
    f.back:SetAllPoints()
    KE:AddBorders(f, colors.border)
    f.fold = CreateFrame("Button", nil, f)
    f.fold.text = Text(f.fold, Option("TitleSize"), "CENTER")
    f.fold.text:SetAllPoints()
    f.fold:SetScript("OnClick", ToggleFold)
    f.title = Text(f, Option("TitleSize"))
    f.title:SetWordWrap(false)
    f.progress = Text(f, Option("StepSize"), "RIGHT")
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
    box:SetScript("OnEnter", function(self) Tip(self, K.TEXT_SKIP, true) end)
    box:SetScript("OnLeave", TipHide)
    Draggable(box)
    box.back = box:CreateTexture(nil, "BACKGROUND")
    box.back:SetAllPoints()
    KE:AddBorders(box, colors.boxBorder)
    box.label = Text(box, Option("StepSize"))
    local pad, mark = K.BOX_PAD, K.MARK_SIZE
    box.label:SetPoint("TOPLEFT", box, "TOPLEFT", pad, -pad)
    box.yards = Text(box, Option("StepSize"))
    box.yards:SetPoint("LEFT", box.label, "RIGHT", 6, 0)
    box.rim = box:CreateTexture(nil, "OVERLAY")
    box.rim:SetTexture(K.MARK_RIM)
    box.rim:SetSize(mark, mark)
    box.rim:SetPoint("TOPRIGHT", box, "TOPRIGHT", -pad, -pad)
    box.k = box:CreateTexture(nil, "OVERLAY")
    box.k:SetTexture(K.MARK_K)
    box.k:SetSize(mark, mark)
    box.k:SetPoint("TOPRIGHT", box, "TOPRIGHT", -pad, -pad)
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
    row:SetScript("OnEnter", function(self) Tip(self.box or self, K.TEXT_SKIP, true) end)
    row:SetScript("OnLeave", TipHide)
    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.icon = Text(row, K.ICON_SIZE)
    row.glyph = row:CreateTexture(nil, "OVERLAY")
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
        if not self.menu and Option("Skip") == "off" then return end
        local accent = Theme.Tokens().accent
        self.shade:SetColorTexture(accent[1], accent[2], accent[3], K.HOVER_ALPHA)
        self.shade:Show()
        if self.menu then
            Tip(self, K.TEXT_PICK, false, true)
        else
            Tip(self, K.TEXT_GO:format(self.index or 0))
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
        }
    end
    return pools
end

local function ReleaseAll()
    for _, pool in pairs(Pools()) do pool:ReleaseAll() end
    linesDrawn = 0
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

local function DrawRow(parent, row, x, y, width, first, noSideBar)
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
    local iconW = iconSize + K.ICON_GAP
    local drop = math_max(0, floor((iconSize - textSize) / 2))
    local lead = K.BAR_W + K.GAP
    local textWidth = width - lead - iconW
    item.bar:ClearAllPoints()
    item.bar:SetPoint("TOPLEFT", item, "TOPLEFT", 0, 0)
    item.bar:SetPoint("BOTTOMLEFT", item, "BOTTOMLEFT", 0, 0)
    item.bar:SetWidth(K.BAR_W)
    item.bar:SetShown(not first and not noSideBar and not row.nested and not row.note)
    local side = row.done and colors.muted or colors.accent
    item.bar:SetColorTexture(side[1], side[2], side[3], side[4])
    item.icon:ClearAllPoints()
    item.icon:SetPoint("TOPLEFT", item, "TOPLEFT", lead, 0)
    Faced(item.icon, iconSize)
    DrawIcon(item, row, iconSize)
    item.text:ClearAllPoints()
    item.text:SetPoint("TOPLEFT", item, "TOPLEFT", lead + iconW, -drop)
    item.text:SetWidth(textWidth)
    Colored(item.text, row.done and "muted" or "text")
    Faced(item.text, textSize)
    item.text:SetText(row.text)
    local height = math_max(drop + math_max(item.text:GetStringHeight(), textSize), iconSize)
    local fill = Rules.CountFill(row.have, row.need, row.bags, row.done)
    if fill then
        local x2 = lead + iconW
        height = height + K.COUNT_GAP + DrawMeter(item, row, fill, x2, height + K.COUNT_GAP, textWidth)
    else
        item.meter:Hide()
    end
    item:SetHeight(height)
    Watch(row.source)
    return height
end

local function DrawBox(step, y, inner, first)
    local box = Pools().box:Acquire(window)
    box.step = step.source
    local size = Option("StepSize")
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", window, "TOPLEFT", K.PAD, y)
    box:SetWidth(inner)
    local fill, edge, accent, muted = colors.box, colors.boxBorder, colors.accent, colors.muted
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
    local mark = first and Option("Logo") == "mark"
    box.rim:SetShown(mark)
    box.k:SetShown(mark)
    local head = size
    if mark then
        box.rim:SetVertexColor(muted[1], muted[2], muted[3])
        box.k:SetVertexColor(accent[1], accent[2], accent[3])
        head = math_max(size, K.MARK_SIZE)
    end
    local pad, gap = K.BOX_PAD, K.GAP
    local by = -pad - head - gap
    local column = K.ICON_SIZE + K.ICON_GAP
    for i, row in ipairs(step.rows) do
        local set = i > 1 and K.INDENT or 0
        if i > 1 and row.nested then set = set + column end
        by = by - DrawRow(box, row, pad + set, by, inner - pad * 2 - set, i == 1) - gap
    end
    box:SetHeight(-by + pad - gap)
    lastBox = box
    return y + by - pad
end

local function DrawFold(folded, headH)
    local fold = window.fold
    fold:SetSize(K.FOLD_W, headH)
    fold:ClearAllPoints()
    fold:SetPoint("TOPLEFT", window, "TOPLEFT", K.PAD, -K.PAD)
    Faced(fold.text, Option("TitleSize"))
    fold.text:SetText(folded and K.TEXT_UNFOLD or K.TEXT_FOLD)
    Colored(fold.text, "line")
end

local function DrawHeader(model, folded, width, headH)
    DrawFold(folded, headH)
    local pad, foldW, gap = K.PAD, K.FOLD_W, K.GAP
    window.title:ClearAllPoints()
    window.title:SetPoint("TOPLEFT", window, "TOPLEFT", pad + foldW + gap, -pad)
    window.title:SetWidth(width - pad * 2 - foldW - gap - K.PROGRESS_W)
    Faced(window.title, Option("TitleSize"))
    Colored(window.title, "title")
    window.title:SetText(model.heading)
    window.progress:ClearAllPoints()
    window.progress:SetPoint("TOPRIGHT", window, "TOPRIGHT", -pad, -pad)
    Faced(window.progress, Option("StepSize"))
    if model.step then
        window.progress:SetText(Tint("accent", ("%d/%d"):format(model.step, model.total)) .. K.TEXT_DOT
            .. Tint("title", ("%d%%"):format(model.percent)))
    else
        window.progress:SetText("")
    end
    window.progress:SetTextColor(1, 1, 1, 1)
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
    hit.index, hit.menu = index, menu
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

local function DrawSteps(model, y, inner, listH)
    local list = model.list
    local count = sizing and sizing.steps or Option("ListedSteps")
    local top
    top, scroll = Rules.ListWindow(model.first, scroll, count, #list)
    local scrollable = count > 0 and #list > count
    local barred = scrollable and Option("ScrollBar")
    local from = y
    for i = top, math_min(#list, top + count - 1) do
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
    for i, step in ipairs(model.steps) do y = DrawBox(step, y, inner, i == 1) end
    return DrawSteps(model, y, inner, listH)
end

local function DrawFolded(model, y, inner)
    if not Option("FoldObjective") then return y end
    local step = model.steps[#model.steps]
    local row = step and step.rows[1]
    if not row then return y end
    return y - DrawRow(window, row, K.PAD, y, inner, false, true) - K.GAP
end

local function DrawChrome(y, listH, folded)
    if not sizing then window:SetHeight(-y + K.PAD) end
    if wantsBags then window:RegisterEvent(K.BAG_EVENT) else window:UnregisterEvent(K.BAG_EVENT) end
    window.lineHeight = listH
    window.chrome = -y + K.PAD - linesDrawn * listH
    local locked = Option("Lock")
    window:SetResizable(not locked and not folded)
    window:SetResizeBounds(K.WIDTH_MIN, window.chrome, K.WIDTH_MAX, window.chrome + K.STEPS_MAX * listH)
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
        return true
    end
    local model = sizing and sizingModel or Model.Read(_G.RXP, READ_OPTIONS) or Model.NoGuide()
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
    DrawHeader(model, folded, width, headH)
    local y = DrawLine(model, -K.PAD - headH)
    window.track:Hide()
    window.thumb:Hide()
    window.wheel:Hide()
    if folded then
        y = DrawFolded(model, y, width - K.PAD * 2)
    else
        y = DrawList(model, y, width - K.PAD * 2, listH)
    end
    DrawChrome(y, listH, folded)
    window:Show()
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
        TestShowIn()
        RefreshAccepts()
        ApplyGeometry()
        Redraw()
        if window then
            window:RegisterEvent("PLAYER_REGEN_DISABLED")
            window:RegisterEvent("PLAYER_REGEN_ENABLED")
            window:SetAlpha(InCombatLockdown() and Option("CombatFade") / K.PERCENT or 1)
        end
    else
        Release()
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
    end
    Arrow.WatchYards(OnYards)
    Activate(true)
end

function Window.Stop()
    if not active then return end
    Arrow.WatchYards(nil)
    Activate(false)
end

function Window.ApplySettings()
    ApplyGeometry()
    if not active then return end
    TestShowIn()
    Refresh()
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

-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/Skinning/RestedXP/RestedXPImporter.lua          ║
-- ║  Purpose: RestedXP's Guide Import popup and its          ║
-- ║           Purge and Remove confirms in KE's look:        ║
-- ║           larger, in two cards, with a state chip, on    ║
-- ║           RestedXP's own frames and widgets.             ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local GetLocale, hooksecurefunc, UIParent = GetLocale, hooksecurefunc, UIParent
local ipairs, pairs, setmetatable, type = ipairs, pairs, setmetatable, type
local floor, math_rad, tonumber = math.floor, math.rad, tonumber

local Safe, Theme = KE.RestedXPSafe, KE.RestedXPTheme
local Has, Dig, Run = Safe.Has, Safe.Dig, Safe.Run

local Importer = {}
KE.RestedXPImporter = Importer

-- Places are RestedXP units from the popup's top left, before the scale.
local K = {
    -- RestedXP sets this popup's text at 8 to 10 points.
    SCALE = 1.5,
    BAR = "KitnUI",
    CROSS = "Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\KitnCustomCrossv3.png",
    MARK_RIM = "Interface\\AddOns\\KitnEssentials\\Media\\RestedXP\\Logo\\rim.tga",
    MARK_K = "Interface\\AddOns\\KitnEssentials\\Media\\RestedXP\\Logo\\k.tga",
    CROSS_SIZE = 12, CROSS_INSET = 3, CROSS_TURN = 45,
    MARK_SIZE = 14, MARK_X = 4, TITLE_X = 22, VERSION_X = 20,
    BAND = 14, BAND_ALPHA = 0.92, BAND_TEXT_X = 6, CARD_ALPHA = 0.55,
    LABEL_SIZE = 8, HINT_SIZE = 9,
    CARD_IMPORT = { 18, 28, 464, 112 }, CARD_GUIDES = { 18, 150, 464, 86 },
    WIDTH = 500, HEADER = 18,
    -- The paste box's frame, and its field: RestedXP insets the field 4 units.
    PASTE = { 26, 44, 26, 58 }, FIELD = { 26, 48, 26, 50 },
    IMPORT = { 26, 106, 296, 24 }, IMPORT_ALONE = 448, SPLICE = { 330, 106, 144, 24 },
    LIST = { 26, 172, 154, 24 }, DELETE = { 354, 172, 120, 24 },
    -- The open list draws a little smaller than the popup, at the field's width.
    LIST_SCALE = 1.2,
    RELOAD = { 26, 204, 220, 24 }, PURGE = { 254, 204, 220, 24 },
    BAR_AT = { 18, 261, 18, 8 }, STATUS_LIFT = 5,
    HEIGHT = 282, HISTORY_PAD = 10,
    CONFIRM_TITLE_X = 8,
    DANGER = { 1, 0.35, 0.29, 1 },
    TEXT_IMPORT = "IMPORT", TEXT_GUIDES = "IMPORTED GUIDES",
    TEXT_HINT = "Paste a guide string here (Ctrl+V)",
    TEXT_IDLE = "Paste a string to begin",
    TEXT_WAITING = "Waiting for a string", TEXT_READY = "%d characters ready",
    TEXT_DONE = "Imported %d of %d", TEXT_FAILED = "Import failed", TEXT_OFFLINE = "Battle.net not reached",
    TEXT_ONE = "1 guide", TEXT_MANY = "%d guides",
    TEXT_RELOAD = "Reload UI", TEXT_PURGE = "Purge all",
    COUNT_PATTERN = "(%d+)/(%d+)",
    -- Read in place of a missing table. Never written.
    NONE = {},
    WHITE = { 1, 1, 1, 1 },
    -- AceGUI's own gray for a disabled dropdown's text.
    DISABLED = { 0.5, 0.5, 0.5, 1 },
}
local BUTTON_KEYS = { "importButton", "importSplicedString", "purgeButton", "reloadButton", "deleteButton" }
local HIDDEN_KEYS = { "importLabel", "guidesLabel", "progressLabel" }
-- RestedXP's Purge and Remove confirms: one popup type, Yes first and No second.
local CONFIRM_KEYS = { "purgeConfirmation", "deleteConfirmation" }

local active, hooked, dressed, colors, px, idleShown
-- RestedXP's frames this file gave hover scripts, to what each one is.
local owned = setmetatable({}, { __mode = "k" })
-- What RestedXP had before the first dress, and what this file added.
local home = { points = {} }
-- Each confirm popup this file has painted, to its own regions and kept places.
local confirms = {}

local function Widgets()
    return Dig(_G.RXP, "guideImporter", "widgets")
end

local function Color(texture, color)
    texture:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
end

local function Ink(text, color)
    text:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

-- KE's borders: one physical pixel, never snapped to the grid, which at a
-- fractional scale draws some sides two pixels wide and drops others.
local function Loose(texture, snap, bias)
    texture:SetTexelSnappingBias(bias or 0)
    texture:SetSnapToPixelGrid(snap or false)
end

-- RestedXP's backdrop is a fill frame and four edge textures: top, bottom, left, right.
-- With no snap given they take KE's; the restore passes RestedXP's back.
local function Edges(frame, size, snap, bias)
    local edges = Dig(frame, "rxpBorder", "textures")
    if not (edges and edges[4]) then return end
    edges[1]:SetHeight(size)
    edges[2]:SetHeight(size)
    edges[3]:SetWidth(size)
    edges[4]:SetWidth(size)
    for _, edge in ipairs(edges) do Loose(edge, snap, bias) end
end

local function Box(frame, fill, edge)
    if not frame then return end
    local fills, lines = Dig(frame, "rxpBackground", "textures"), Dig(frame, "rxpBorder", "textures")
    if fills then for _, texture in ipairs(fills) do Color(texture, fill) end end
    if lines then for _, texture in ipairs(lines) do Color(texture, edge) end end
    Edges(frame, px)
end

local function TintOne(texture, color, gray)
    if not texture then return end
    texture:SetDesaturated(gray)
    Color(texture, color)
end

local function Tint(button, color, gray)
    TintOne(button:GetNormalTexture(), color, gray)
    TintOne(button:GetPushedTexture(), color, gray)
    TintOne(button:GetDisabledTexture(), color, gray)
end

local function Unlit(button, alpha)
    local glow = button:GetHighlightTexture()
    if glow then glow:SetAlpha(alpha) end
end

-- Under the mouse a button takes KE's lighter plate and an accent edge; Import keeps
-- an accent edge whenever it can import; the cross and the arrow turn the accent.
local function Lit(frame, kind, hover)
    local on = frame:IsEnabled()
    hover = hover and on
    if kind == "cross" or kind == "arrow" then
        Tint(frame, hover and colors.accent or colors.text, true)
    elseif hover then
        Box(frame, KE.Theme.bgLight, colors.accent)
    else
        Box(frame, KE.Theme.bgButton, (kind == "primary" and on) and colors.accent or KE.Theme.border)
    end
end

-- AceGUI pools these widgets. RestedXP never releases the importer's, and the check
-- keeps a reused frame inert if a later version did.
local function Ours(frame)
    local obj, w = frame.obj, Widgets()
    if obj == nil or not w then return obj == nil end
    if obj == w.currentGuides then return true end
    for _, key in ipairs(BUTTON_KEYS) do
        if obj == w[key] then return true end
    end
    return false
end

local function Hover(self, hover)
    local kind = active and colors and owned[self]
    if kind and Ours(self) then Lit(self, kind, hover) end
end

local function OnEnter(self) Hover(self, true) end
local function OnLeave(self) Hover(self, false) end

local function Own(frame, kind)
    if not owned[frame] then
        frame:HookScript("OnEnter", OnEnter)
        frame:HookScript("OnLeave", OnLeave)
    end
    owned[frame] = kind
end

-- KE's cross on a RestedXP close button, and RestedXP's own art back on it.
local function Cross(close, frame)
    close:SetNormalTexture(K.CROSS)
    close:SetPushedTexture(K.CROSS)
    close:GetNormalTexture():SetRotation(math_rad(K.CROSS_TURN))
    close:GetPushedTexture():SetRotation(math_rad(K.CROSS_TURN))
    close:SetSize(K.CROSS_SIZE, K.CROSS_SIZE)
    close:ClearAllPoints()
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -K.CROSS_INSET, -K.CROSS_INSET)
    Unlit(close, 0)
    Own(close, "cross")
end

local function Uncross(close, art)
    close:SetNormalTexture(art)
    close:SetPushedTexture(art)
    for _, texture in ipairs({ close:GetNormalTexture(), close:GetPushedTexture() }) do
        texture:SetRotation(0)
        texture:SetDesaturated(false)
        texture:SetVertexColor(1, 1, 1, 1)
    end
    Unlit(close, 1)
end

---------------------------------------------------------------------------------
-- Places
---------------------------------------------------------------------------------
-- Kept once, at the first dress, and put back by the restore.
local function Keep(region, points)
    points = points or home.points
    if not region or points[region] then return end
    local kept = { width = region:GetWidth(), height = region:GetHeight() }
    for i = 1, region:GetNumPoints() do kept[i] = { region:GetPoint(i) } end
    points[region] = kept
end

-- A font string sizes to its text, so only frames take their kept size back.
local function PutBack(region, kept)
    region:ClearAllPoints()
    for _, point in ipairs(kept) do region:SetPoint(point[1], point[2], point[3], point[4], point[5]) end
    if region:GetObjectType() ~= "FontString" then region:SetSize(kept.width, kept.height) end
end

-- A place on the physical pixel grid at the popup's scale, where px is one pixel. A
-- 1-pixel edge on a half pixel draws two pixels or none, snapped or not.
local function Snap(v)
    return floor(v / px + 0.5) * px
end

local function At(region, frame, x, y, width, height)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", frame, "TOPLEFT", Snap(x), -Snap(y))
    if width then region:SetWidth(Snap(width)) end
    if height then region:SetHeight(Snap(height)) end
end

-- Spans the popup between a left and a right inset.
local function Span(region, frame, place)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", frame, "TOPLEFT", Snap(place[1]), -Snap(place[2]))
    region:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -Snap(place[3]), -Snap(place[2]))
    region:SetHeight(Snap(place[4]))
end

-- An open list keeps the width it opened with, so a scale change closes it first.
local function CloseList(dropdown)
    if dropdown and dropdown.open and Has(dropdown.pullout, "Close") then dropdown.pullout:Close() end
end

-- The popup's top left on the grid, so every place measured from it lands there too.
local function Pin(frame)
    local left, top = frame:GetLeft(), frame:GetTop()
    if not (left and top) then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", Snap(left), Snap(top))
end

-- A scale change keeps a dragged popup where it is on screen.
local function Rescale(frame, scale)
    local ratio = frame:GetScale() / scale
    local points = {}
    for i = 1, frame:GetNumPoints() do points[i] = { frame:GetPoint(i) } end
    frame:SetScale(scale)
    frame:ClearAllPoints()
    for _, p in ipairs(points) do frame:SetPoint(p[1], p[2], p[3], (p[4] or 0) * ratio, (p[5] or 0) * ratio) end
end

-- Back to scale 1, anchored by its center the way RestedXP grows it, with that center
-- kept where it stands on screen. The center is read at the old scale, whose units
-- times the scale are UIParent's.
local function Unscale(frame)
    local x, y = frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (x and ux) then return Rescale(frame, 1) end
    local scale = frame:GetScale()
    frame:SetScale(1)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", x * scale - ux, y * scale - uy)
end

local function Layout(w, frame)
    w.import:SetWidth(Snap(K.WIDTH))
    local header = frame.importerHeader
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", px, -px)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -px, -px)
    header:SetHeight(Snap(K.HEADER))
    -- RestedXP insets its body fill 1 unit, half a pixel past the 1-pixel edge here.
    local body = frame.importerBody
    if body then
        body:ClearAllPoints()
        body:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
        body:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")
        body:SetPoint("BOTTOM", frame, "BOTTOM", 0, px)
    end
    for i, card in ipairs(home.cards) do
        local place = i == 1 and K.CARD_IMPORT or K.CARD_GUIDES
        At(card.fill, frame, place[1], place[2], place[3], place[4])
    end
    Span(w.importBox.frame, frame, K.PASTE)
    Span(w.importBox.background, frame, K.FIELD)
    local import, splice = w.importButton.frame, w.importSplicedString.frame
    At(import, frame, K.IMPORT[1], K.IMPORT[2], splice:IsShown() and K.IMPORT[3] or K.IMPORT_ALONE, K.IMPORT[4])
    At(splice, frame, K.SPLICE[1], K.SPLICE[2], K.SPLICE[3], K.SPLICE[4])
    Span(w.currentGuides.frame, frame, K.LIST)
    At(w.deleteButton.frame, frame, K.DELETE[1], K.DELETE[2], K.DELETE[3], K.DELETE[4])
    At(w.reloadButton.frame, frame, K.RELOAD[1], K.RELOAD[2], K.RELOAD[3], K.RELOAD[4])
    At(w.purgeButton.frame, frame, K.PURGE[1], K.PURGE[2], K.PURGE[3], K.PURGE[4])
    Span(w.progress, frame, K.BAR_AT)
    local status = w.progressText
    status:ClearAllPoints()
    status:SetPoint("BOTTOMLEFT", w.progress, "TOPLEFT", 0, K.STATUS_LIFT)
    status:SetPoint("BOTTOMRIGHT", w.progress, "TOPRIGHT", 0, K.STATUS_LIFT)
    for _, key in ipairs(HIDDEN_KEYS) do
        if w[key] then w[key]:Hide() end
    end
    w.import.description:Hide()
    local history = w.history
    local extra = history and history:IsShown() and history:GetHeight() + K.HISTORY_PAD or 0
    w.import:SetHeight(Snap(K.HEIGHT + extra))
end

---------------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------------
local function GuideCount()
    local count = 0
    for _ in pairs(Dig(_G.RXP, "db", "profile", "guides") or K.NONE) do count = count + 1 end
    return count
end

-- The chip's words and color, from the state RestedXP keeps; "waiting" when idle.
local function State()
    local importer = _G.RXP.guideImporter
    local gui = importer.gui or K.NONE
    if not Dig(_G.RXPData, "cache") then return K.TEXT_OFFLINE, K.DANGER end
    if gui.progressError then return K.TEXT_FAILED, K.DANGER end
    local buffer = Dig(importer, "importCache", "bufferString")
    if importer.importReady and buffer then return K.TEXT_READY:format(#buffer), colors.accent end
    local done, total = (gui.progressMessage or ""):match(K.COUNT_PATTERN)
    if done then return K.TEXT_DONE:format(tonumber(done), tonumber(total)), colors.accent end
    return K.TEXT_WAITING, colors.muted, true
end

-- The edit box's scripts pass it in; a paste can run this once per character, and
-- the box has focus then.
local function Hint(edit)
    if not home.hint then return end
    if edit and edit:HasFocus() then
        home.hint:Hide()
        return
    end
    edit = edit or Dig(Widgets(), "importBox", "editBox")
    if not edit then return end
    home.hint:SetShown(active and dressed and edit:GetText() == "" and not edit:HasFocus())
end

---------------------------------------------------------------------------------
-- Confirms: RestedXP's Purge and Remove popups, at the import popup's scale
---------------------------------------------------------------------------------
-- RestedXP does not keep the close button: it is the one button child that is
-- neither Yes nor No.
local function FindClose(frame, buttons)
    for _, child in ipairs({ frame:GetChildren() }) do
        if child:IsObjectType("Button") and child ~= buttons[1] and child ~= buttons[2] then return child end
    end
end

local function ConfirmBuild(popup)
    local frame = popup.frame
    local look = { points = {}, close = FindClose(frame, popup.buttons) }
    -- RestedXP's fill frame shares this frame's level, so its order against regions
    -- drawn here is not fixed; it is hidden and this fill takes its place.
    look.fill = frame:CreateTexture(nil, "BACKGROUND")
    look.fill:SetAllPoints()
    look.band = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    look.rule = frame:CreateTexture(nil, "ARTWORK")
    look.rule:SetPoint("TOPLEFT", look.band, "BOTTOMLEFT")
    look.rule:SetPoint("TOPRIGHT", look.band, "BOTTOMRIGHT")
    Keep(popup.title, look.points)
    Keep(look.close, look.points)
    local art = look.close and look.close:GetNormalTexture()
    look.art = art and art:GetTexture()
    confirms[popup] = look
    return look
end

-- Runs after RestedXP's own repaint, which comes with every show.
local function ConfirmPaint(popup)
    local frame, buttons = popup.frame, popup.buttons
    if not (active and frame and frame:IsShown() and popup.title and popup.message and buttons and buttons[2]
            and frame.rxpBackground and Dig(frame, "rxpBorder", "textures", 4)) then
        return
    end
    local look = confirms[popup] or ConfirmBuild(popup)
    local close = look.close
    if not close then return end
    px = KE:GetPixelSize() / K.SCALE
    colors = colors or Theme.WindowColors()
    if not look.dressed then
        look.dressed = true
        Rescale(frame, K.SCALE)
        Pin(frame)
        if frame.rxpShadow then frame.rxpShadow:Hide() end
        frame.rxpBackground:Hide()
        for _, region in ipairs({ look.fill, look.band, look.rule }) do region:Show() end
        Cross(close, frame)
        for _, button in ipairs(buttons) do
            Unlit(button, 0)
            Own(button, "button")
        end
    end

    -- It sits over the import popup, so its panel is opaque.
    local panel = colors.panel or KE.db.profile.SkinRestedXP.PanelColor
    look.fill:SetColorTexture(panel[1], panel[2], panel[3], 1)
    local band, line = KE.Theme.bgMedium, colors.line
    look.band:ClearAllPoints()
    look.band:SetPoint("TOPLEFT", frame, "TOPLEFT", px, -px)
    look.band:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -px, -px)
    look.band:SetHeight(Snap(K.HEADER))
    look.band:SetColorTexture(band[1], band[2], band[3], 1)
    look.rule:SetHeight(px)
    look.rule:SetColorTexture(line[1], line[2], line[3], line[4])
    Loose(look.rule)
    for _, texture in ipairs(frame.rxpBorder.textures) do Color(texture, colors.border) end
    Edges(frame, px)

    popup.title:ClearAllPoints()
    popup.title:SetPoint("LEFT", look.band, "LEFT", K.CONFIRM_TITLE_X, 0)
    Ink(popup.title, colors.accent)
    Ink(popup.message, colors.text)
    Lit(close, "cross", close:IsMouseOver())
    for i, button in ipairs(buttons) do
        Lit(button, "button", button:IsMouseOver())
        if button.text then Ink(button.text, i == 1 and K.DANGER or colors.text) end
    end
end

local function ConfirmRestore(popup, look)
    if not look.dressed then return end
    look.dressed = false
    local frame = popup.frame
    Unscale(frame)
    if frame.rxpShadow then frame.rxpShadow:Show() end
    frame.rxpBackground:Show()
    for _, region in ipairs({ look.fill, look.band, look.rule }) do region:Hide() end
    for region, kept in pairs(look.points) do PutBack(region, kept) end
    Uncross(look.close, look.art)
    for _, button in ipairs(popup.buttons) do
        Unlit(button, 1)
        Edges(button, home.edge, home.snap, home.bias)
    end
    Edges(frame, home.edge, home.snap, home.bias)
    Run("ConfirmRepaint", popup.UpdateSubTheme, popup)
end

local function OnConfirm(popup)
    if active then Run("ConfirmPaint", ConfirmPaint, popup) end
end

-- RestedXP makes both confirms with the import popup, so its first dress hooks them.
-- A refresh while one is shown repaints it; its show repaints it after RestedXP's.
local function HookConfirms(w)
    for _, key in ipairs(CONFIRM_KEYS) do
        local popup = w[key]
        local frame = popup and popup.frame
        if Has(popup, "UpdateSubTheme") and frame then
            hooksecurefunc(popup, "UpdateSubTheme", OnConfirm)
            frame:HookScript("OnShow", function() OnConfirm(popup) end)
            frame:HookScript("OnDragStop", function(self)
                local look = confirms[popup]
                if active and look and look.dressed then Run("ConfirmPin", Pin, self) end
            end)
        end
    end
end

---------------------------------------------------------------------------------
-- Dress: once per start, on the first paint with the popup shown
---------------------------------------------------------------------------------
local function Label(parent, size, justify)
    local text = parent:CreateFontString(nil, "OVERLAY")
    text:SetFont(home.font, size, "")
    if justify then text:SetJustifyH(justify) end
    return text
end

-- A card is regions on RestedXP's own frame, under every widget: a fill, a band,
-- four edges, its title and its chip.
local function Card(frame, place, words)
    local card = { regions = {} }
    local function Add(region)
        card.regions[#card.regions + 1] = region
        return region
    end
    card.fill = Add(frame:CreateTexture(nil, "BACKGROUND", nil, 2))
    At(card.fill, frame, place[1], place[2], place[3], place[4])
    card.band = Add(frame:CreateTexture(nil, "BACKGROUND", nil, 3))
    card.band:SetPoint("TOPLEFT", card.fill)
    card.band:SetPoint("TOPRIGHT", card.fill)
    card.band:SetHeight(K.BAND)
    card.edges = {}
    for i, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local edge = Add(frame:CreateTexture(nil, "BORDER"))
        Loose(edge)
        local across = side == "TOP" or side == "BOTTOM"
        edge:SetPoint(across and side .. "LEFT" or "TOP" .. side, card.fill)
        edge:SetPoint(across and side .. "RIGHT" or "BOTTOM" .. side, card.fill)
        card.edges[i] = edge
    end
    card.title = Add(Label(frame, K.LABEL_SIZE, "LEFT"))
    card.title:SetPoint("LEFT", card.band, "LEFT", K.BAND_TEXT_X, 0)
    card.title:SetText(words)
    card.chip = Add(Label(frame, K.LABEL_SIZE, "RIGHT"))
    card.chip:SetPoint("RIGHT", card.band, "RIGHT", -K.BAND_TEXT_X, 0)
    return card
end

-- RestedXP's theme font, at each show and recolor.
local function Refont(path)
    if not path or path == home.font then return end
    home.font = path
    local labels = { home.version, home.hint }
    for _, card in ipairs(home.cards) do
        labels[#labels + 1] = card.title
        labels[#labels + 1] = card.chip
    end
    for _, label in ipairs(labels) do
        local _, size = label:GetFont()
        label:SetFont(path, size or K.LABEL_SIZE, "")
    end
end

local function ShowCards(shown)
    for _, card in ipairs(home.cards) do
        for _, region in ipairs(card.regions) do region:SetShown(shown) end
    end
end

local function Build(w, importer, frame)
    local close = importer.closebutton
    home.font = importer.title:GetFont()
    home.close = close:GetNormalTexture():GetTexture()
    home.bar = w.progress:GetStatusBarTexture():GetTexture()
    local edge = Dig(frame, "rxpBorder", "textures", 1)
    home.edge, home.snap, home.bias = edge:GetHeight(), edge:IsSnappingToPixelGrid(), edge:GetTexelSnappingBias()
    home.title = importer.title:GetText()
    home.reload, home.purge = w.reloadButton.text:GetText(), w.purgeButton.text:GetText()
    home.width = frame:GetWidth()
    for _, region in ipairs({ close, importer.title, frame.importerHeader, w.importBox.frame,
        w.importBox.background, w.importButton.frame,
        w.importSplicedString.frame, w.currentGuides.frame, w.deleteButton.frame, w.reloadButton.frame,
        w.purgeButton.frame, w.progress, w.progressText }) do
        Keep(region)
    end
    Keep(frame.importerBody)

    local header = frame.importerHeader
    home.rule = frame:CreateTexture(nil, "ARTWORK")
    Loose(home.rule)
    home.rule:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
    home.rule:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")
    home.rim = frame:CreateTexture(nil, "OVERLAY")
    home.rim:SetTexture(K.MARK_RIM)
    home.k = frame:CreateTexture(nil, "OVERLAY")
    home.k:SetTexture(K.MARK_K)
    for _, mark in ipairs({ home.rim, home.k }) do
        mark:SetSize(K.MARK_SIZE, K.MARK_SIZE)
        mark:SetPoint("LEFT", header, "LEFT", K.MARK_X, 0)
    end
    home.version = Label(frame, K.LABEL_SIZE, "RIGHT")
    home.version:SetPoint("RIGHT", header, "RIGHT", -K.VERSION_X, 0)
    home.cards = { Card(frame, K.CARD_IMPORT, K.TEXT_IMPORT), Card(frame, K.CARD_GUIDES, K.TEXT_GUIDES) }

    local edit = w.importBox.editBox
    home.hint = Label(edit, K.HINT_SIZE, "CENTER")
    home.hint:SetPoint("CENTER", edit, "CENTER")
    home.hint:SetText(K.TEXT_HINT)
    for _, script in ipairs({ "OnEditFocusGained", "OnEditFocusLost", "OnTextChanged" }) do
        edit:HookScript(script, Hint)
    end
    -- RestedXP's open refreshes the popup again after its show, which then reads the
    -- colors fresh.
    frame:HookScript("OnShow", function() colors = nil end)
    frame:HookScript("OnDragStop", function(self)
        if active and dressed then Run("ImporterPin", Pin, self) end
    end)
    HookConfirms(w)
end

local function Dress(w, importer, frame)
    if not home.rule then Build(w, importer, frame) end
    dressed = true
    CloseList(w.currentGuides)
    Rescale(frame, K.SCALE)
    Pin(frame)
    local pullout = Dig(w.currentGuides, "pullout", "frame")
    if pullout then
        home.pullout = home.pullout or pullout:GetScale()
        pullout:SetScale(K.LIST_SCALE)
    end
    -- KE's 1-pixel edge reads as a band over RestedXP's soft shadow.
    if frame.rxpShadow then frame.rxpShadow:Hide() end
    -- KE's Ace3 dark skin plates the dropdown's template, which draws a second, inset
    -- box inside this field.
    local skins = KE.Skins
    home.plate = Has(skins, "GetBackdrop") and skins.GetBackdrop(w.currentGuides.dropdown) or nil
    if home.plate then home.plate:Hide() end
    for _, part in ipairs({ home.rule, home.rim, home.k, home.version }) do part:Show() end
    ShowCards(true)

    local L = Dig(_G.RXP, "locale", "Get")
    local version = Dig(_G.RXP, "versionText")
    if type(L) == "function" and type(version) == "string" then
        importer.title:SetText(("RestedXP %s"):format(L("Guide Import")))
        home.version:SetText(version)
    end
    importer.title:ClearAllPoints()
    importer.title:SetPoint("LEFT", frame.importerHeader, "LEFT", K.TITLE_X, 0)
    -- The new labels would replace RestedXP's translations elsewhere.
    if GetLocale() == "enUS" then
        w.reloadButton:SetText(K.TEXT_RELOAD)
        w.purgeButton:SetText(K.TEXT_PURGE)
    end

    Cross(importer.closebutton, frame)

    w.progress:SetStatusBarTexture(KE:GetStatusbarPath(K.BAR))
    w.progress:GetStatusBarTexture():SetDrawLayer("ARTWORK")

    for _, key in ipairs(BUTTON_KEYS) do
        Unlit(w[key].frame, 0)
        Own(w[key].frame, key == "importButton" and "primary" or "button")
    end
    local arrow = w.currentGuides.button
    Unlit(arrow, 0)
    Own(arrow, "arrow")
end

---------------------------------------------------------------------------------
-- Paint
---------------------------------------------------------------------------------
-- Runs after every RestedXP refresh of the shown popup: its open, its repaint, a
-- focus or a pick, and each import step. RestedXP imports one guide per frame and
-- refreshes after each, so during an import this runs once a frame: about 250
-- setters, a count of the saved guides and no table made, beside RestedXP's own
-- refresh, which rebuilds the dropdown's list every time.
local function Paint()
    local w = Widgets()
    local importer = Dig(w, "import")
    local frame = Dig(importer, "frame")
    if not (frame and frame:IsShown() and frame.importerHeader and Dig(frame, "rxpBorder", "textures", 4)
            and importer.closebutton and w.progress and w.progressText and w.importBox and w.currentGuides
            and w.currentGuides.button and w.deleteButton and w.importSplicedString) then
        return
    end
    px = KE:GetPixelSize() / K.SCALE
    if not dressed then Dress(w, importer, frame) end
    -- A confirm's paint can read the colors first, so the font is checked apart.
    colors = colors or Theme.WindowColors()
    Refont(importer.title:GetFont())
    local theme, text, muted, accent = KE.Theme, colors.text, colors.muted, colors.accent

    Layout(w, frame)
    local list = w.currentGuides
    if Has(list, "SetPulloutWidth") then list:SetPulloutWidth(list.frame:GetWidth() * K.SCALE / K.LIST_SCALE) end
    local panel = colors.panel or KE.db.profile.SkinRestedXP.PanelColor
    frame.importerBackground:SetColorTexture(panel[1], panel[2], panel[3], panel[4] or 1)
    if frame.importerBody then frame.importerBody:SetColorTexture(panel[1], panel[2], panel[3], panel[4] or 1) end
    local band = theme.bgMedium
    frame.importerHeader:SetColorTexture(band[1], band[2], band[3], 1)
    frame.importerHeader:SetAlpha(1)
    for _, texture in ipairs(frame.rxpBorder.textures) do Color(texture, colors.border) end
    Edges(frame, px)
    local line = colors.line
    home.rule:SetHeight(px)
    -- SetColorTexture turns the grid snap back on, so each recolor turns it off.
    home.rule:SetColorTexture(line[1], line[2], line[3], line[4])
    Loose(home.rule)
    Color(home.rim, muted)
    Color(home.k, accent)
    Ink(importer.title, accent)
    Ink(home.version, muted)

    local box, edge = colors.box, theme.border
    for _, card in ipairs(home.cards) do
        card.fill:SetColorTexture(box[1], box[2], box[3], K.CARD_ALPHA)
        card.band:SetColorTexture(band[1], band[2], band[3], K.BAND_ALPHA)
        for i, side in ipairs(card.edges) do
            side:SetColorTexture(edge[1], edge[2], edge[3], 1)
            Loose(side)
            if i <= 2 then side:SetHeight(px) else side:SetWidth(px) end
        end
        Ink(card.title, muted)
    end
    if w.history then Ink(w.history, muted) end
    local words, tint, idle = State()
    home.cards[1].chip:SetText(words)
    Ink(home.cards[1].chip, tint)
    local count = GuideCount()
    home.cards[2].chip:SetText(count == 1 and K.TEXT_ONE or K.TEXT_MANY:format(count))
    Ink(home.cards[2].chip, muted)
    Ink(home.hint, muted)
    Hint()

    -- RestedXP owns the status line; the idle words fill it only while it is empty.
    local status = w.progressText
    local current = status:GetText() or ""
    if current ~= K.TEXT_IDLE then idleShown = false end
    if idle and current == "" then
        status:SetText(K.TEXT_IDLE)
        idleShown = true
    elseif idleShown and not idle then
        status:SetText("")
        idleShown = false
    end
    if idleShown then Ink(status, muted) end

    Box(w.importBox.background, theme.bgMedium, theme.border)
    Box(w.currentGuides.frame, theme.bgMedium, theme.border)
    if w.currentGuides.text then Ink(w.currentGuides.text, w.currentGuides.disabled and K.DISABLED or text) end
    local arrow = w.currentGuides.button
    Lit(arrow, "arrow", arrow:IsMouseOver())
    Lit(importer.closebutton, "cross", importer.closebutton:IsMouseOver())

    for _, key in ipairs(BUTTON_KEYS) do
        local button = w[key]
        local kind = owned[button.frame]
        Lit(button.frame, kind, button.frame:IsMouseOver())
        if button.text then
            Ink(button.text, kind == "primary" and accent or key == "purgeButton" and K.DANGER or text)
        end
    end

    local bar, fill, back = w.progress, colors.barFill, colors.barBack
    bar:SetStatusBarColor(fill[1], fill[2], fill[3], fill[4] or 1)
    if w.progressBackground then w.progressBackground:SetColorTexture(back[1], back[2], back[3], back[4] or 1) end
    local edges = Dig(bar, "rxpBorder", "textures")
    if edges then for _, texture in ipairs(edges) do Color(texture, colors.border) end end
    Edges(bar, px)
end

-- RestedXP re-tints the arrow alone when the list opens.
local function OnDropdownTheme(_, dropdown)
    if not (active and dressed and colors) or dropdown ~= Dig(Widgets(), "currentGuides") then return end
    local arrow = dropdown.button
    if arrow then Run("ImporterArrow", Lit, arrow, "arrow", arrow:IsMouseOver()) end
end

---------------------------------------------------------------------------------
-- Restore
---------------------------------------------------------------------------------
local function Restore()
    if not dressed then return end
    dressed = false
    local w = Widgets()
    local importer = Dig(w, "import")
    local frame = Dig(importer, "frame")
    if not frame then return end
    CloseList(w.currentGuides)
    Unscale(frame)
    local pullout = Dig(w.currentGuides, "pullout", "frame")
    if pullout and home.pullout then pullout:SetScale(home.pullout) end
    if Has(w.currentGuides, "SetPulloutWidth") then w.currentGuides:SetPulloutWidth(nil) end
    if home.width then w.import:SetWidth(home.width) end
    if frame.rxpShadow then frame.rxpShadow:Show() end
    if home.plate then home.plate:Show() end
    for _, part in ipairs({ home.rule, home.rim, home.k, home.version, home.hint }) do part:Hide() end
    ShowCards(false)
    for region, kept in pairs(home.points) do PutBack(region, kept) end
    for _, key in ipairs(HIDDEN_KEYS) do
        if w[key] then w[key]:Show() end
    end
    importer.description:Show()
    importer.title:SetText(home.title)
    w.reloadButton:SetText(home.reload)
    w.purgeButton:SetText(home.purge)
    if idleShown then
        if w.progressText:GetText() == K.TEXT_IDLE then w.progressText:SetText("") end
        idleShown = false
    end

    Uncross(importer.closebutton, home.close)

    for _, key in ipairs(BUTTON_KEYS) do
        Unlit(w[key].frame, 1)
        Edges(w[key].frame, home.edge, home.snap, home.bias)
    end
    local arrow = w.currentGuides.button
    Unlit(arrow, 1)
    Tint(arrow, K.WHITE, false)
    for _, boxed in ipairs({ frame, w.importBox.background, w.currentGuides.frame, w.progress }) do
        Edges(boxed, home.edge, home.snap, home.bias)
    end
    w.progress:SetStatusBarTexture(home.bar)
    w.progress:GetStatusBarTexture():SetDrawLayer("ARTWORK")

    local guideImporter = _G.RXP.guideImporter
    if Has(guideImporter, "UpdateTheme") then Run("ImporterRepaint", guideImporter.UpdateTheme, guideImporter) end
end

---------------------------------------------------------------------------------
-- Start and stop
---------------------------------------------------------------------------------
local function Repaint()
    if active then Run("ImporterPaint", Paint) end
end

-- A confirm already open at a start or a recolor; the paint skips a hidden one.
local function RepaintConfirms()
    local w = Widgets()
    if not w then return end
    for _, key in ipairs(CONFIRM_KEYS) do
        if w[key] then OnConfirm(w[key]) end
    end
end

function Importer.Start()
    if active then return end
    local guideImporter = Dig(_G.RXP, "guideImporter")
    if not Has(guideImporter, "UpdateImportUI") then return end
    active = true
    colors = nil
    if not hooked then
        hooked = true
        hooksecurefunc(guideImporter, "UpdateImportUI", Repaint)
        local v2 = Dig(_G.RXP, "ui", "v2")
        if Has(v2, "ApplyDropdownTheme") then hooksecurefunc(v2, "ApplyDropdownTheme", OnDropdownTheme) end
    end
    Repaint()
    RepaintConfirms()
end

function Importer.Stop()
    if not active then return end
    active = false
    Run("ImporterRestore", Restore)
    for popup, look in pairs(confirms) do Run("ConfirmRestore", ConfirmRestore, popup, look) end
end

-- The colors are read at start, here, and at each show of the popup.
function Importer.Recolor()
    if not active then return end
    colors = nil
    Repaint()
    RepaintConfirms()
end


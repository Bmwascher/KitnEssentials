-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/Skinning/RestedXP/RestedXPImporter.lua          ║
-- ║  Purpose: RestedXP's Guide Import popup in KE's look,    ║
-- ║           larger, on RestedXP's own frames and layout.   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local hooksecurefunc, ipairs, setmetatable = hooksecurefunc, ipairs, setmetatable
local math_rad = math.rad

local Safe, Theme = KE.RestedXPSafe, KE.RestedXPTheme
local Has, Dig, Run = Safe.Has, Safe.Dig, Safe.Run

local Importer = {}
KE.RestedXPImporter = Importer

local K = {
    -- RestedXP sets this popup's text at 8 to 10 points.
    SCALE = 1.5,
    BAR = "KitnUI",
    CROSS = "Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\KitnCustomCrossv3.png",
    MARK_RIM = "Interface\\AddOns\\KitnEssentials\\Media\\RestedXP\\Logo\\rim.tga",
    MARK_K = "Interface\\AddOns\\KitnEssentials\\Media\\RestedXP\\Logo\\k.tga",
    CROSS_SIZE = 12, CROSS_INSET = 3, CROSS_TURN = 45,
    MARK_SIZE = 14, MARK_X = 4,
}

local active, hooked, dressed, colors, px
-- RestedXP's frames this file gave hover scripts, to what each one is.
local owned = setmetatable({}, { __mode = "k" })
-- What RestedXP had before the first dress.
local home = {}

local function Widgets()
    return Dig(_G.RXP, "guideImporter", "widgets")
end

local function Buttons(w)
    return { w.importButton, w.importSplicedString, w.purgeButton, w.reloadButton, w.deleteButton }
end

local function Color(texture, color)
    texture:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
end

-- RestedXP's backdrop is a fill frame and four edge textures: top, bottom, left, right.
local function Edges(frame, size)
    local edges = Dig(frame, "rxpBorder", "textures")
    if not (edges and edges[4]) then return end
    edges[1]:SetHeight(size)
    edges[2]:SetHeight(size)
    edges[3]:SetWidth(size)
    edges[4]:SetWidth(size)
end

local function Box(frame, fill, edge)
    if not frame then return end
    for _, texture in ipairs(Dig(frame, "rxpBackground", "textures") or {}) do Color(texture, fill) end
    for _, texture in ipairs(Dig(frame, "rxpBorder", "textures") or {}) do Color(texture, edge) end
    Edges(frame, px)
end

local function Tint(button, color)
    for _, texture in ipairs({ button:GetNormalTexture(), button:GetPushedTexture(), button:GetDisabledTexture() }) do
        if texture then Color(texture, color) end
    end
end

local function Unlit(button, alpha)
    local glow = button:GetHighlightTexture()
    if glow then glow:SetAlpha(alpha) end
end

-- A button lifts its plate and takes an accent edge under the mouse; the close
-- cross and the dropdown arrow turn the accent.
local function Lit(frame, kind, hover)
    hover = hover and frame:IsEnabled()
    if kind ~= "button" then
        Tint(frame, hover and colors.accent or colors.text)
    elseif hover then
        Box(frame, KE.Theme.bgLight, colors.accent)
    else
        Box(frame, KE.Theme.bgButton, KE.Theme.border)
    end
end

local function OnEnter(self)
    local kind = active and colors and owned[self]
    if kind then Lit(self, kind, true) end
end

local function OnLeave(self)
    local kind = active and colors and owned[self]
    if kind then Lit(self, kind, false) end
end

-- The importer is made once and never released, so its pooled AceGUI frames stay
-- RestedXP's; the scripts do nothing while this skin is off.
local function Own(frame, kind)
    if not owned[frame] then
        frame:HookScript("OnEnter", OnEnter)
        frame:HookScript("OnLeave", OnLeave)
    end
    owned[frame] = kind
end

local function Dress(w, importer, frame)
    dressed = true
    local close = importer.closebutton
    if not home.close then
        home.close = close:GetNormalTexture():GetTexture()
        home.bar = w.progress:GetStatusBarTexture():GetTexture()
        home.edge = Dig(frame, "rxpBorder", "textures", 1):GetHeight()
        local header = frame.importerHeader
        home.rule = frame:CreateTexture(nil, "ARTWORK")
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
    end
    frame:SetScale(K.SCALE)
    for _, part in ipairs({ home.rule, home.rim, home.k }) do part:Show() end

    close:SetNormalTexture(K.CROSS)
    close:SetPushedTexture(K.CROSS)
    for _, texture in ipairs({ close:GetNormalTexture(), close:GetPushedTexture() }) do
        texture:SetRotation(math_rad(K.CROSS_TURN))
    end
    close:SetSize(K.CROSS_SIZE, K.CROSS_SIZE)
    close:ClearAllPoints()
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -K.CROSS_INSET, -K.CROSS_INSET)
    Unlit(close, 0)
    Own(close, "cross")

    local bar = w.progress
    bar:SetStatusBarTexture(KE:GetStatusbarPath(K.BAR))
    bar:GetStatusBarTexture():SetDrawLayer("ARTWORK")

    for _, button in ipairs(Buttons(w)) do
        Unlit(button.frame, 0)
        Own(button.frame, "button")
    end
    local arrow = w.currentGuides.button
    Unlit(arrow, 0)
    Own(arrow, "arrow")
end

-- After every RestedXP refresh of the popup: its open, its repaint and each import
-- step. A few dozen setters, never per frame.
local function Paint()
    local w = Widgets()
    local importer = Dig(w, "import")
    local frame = Dig(importer, "frame")
    if not (active and frame and frame.importerHeader and Dig(frame, "rxpBorder", "textures", 4)
            and importer.closebutton and w.progress and w.importBox and w.currentGuides and w.currentGuides.button) then
        return
    end
    if not dressed then Dress(w, importer, frame) end
    colors = Theme.WindowColors()
    px = KE:GetPixelSize() / K.SCALE
    local theme, text, muted, accent = KE.Theme, colors.text, colors.muted, colors.accent

    local panel = colors.panel or KE.db.profile.SkinRestedXP.PanelColor
    for _, texture in ipairs({ frame.importerBackground, frame.importerBody }) do
        if texture then texture:SetColorTexture(panel[1], panel[2], panel[3], panel[4] or 1) end
    end
    local band = theme.bgMedium
    frame.importerHeader:SetColorTexture(band[1], band[2], band[3], 1)
    frame.importerHeader:SetAlpha(1)
    for _, texture in ipairs(Dig(frame, "rxpBorder", "textures") or {}) do Color(texture, colors.border) end
    Edges(frame, px)
    home.rule:SetHeight(px)
    home.rule:SetColorTexture(colors.line[1], colors.line[2], colors.line[3], colors.line[4])
    Color(home.rim, muted)
    Color(home.k, accent)

    importer.title:SetTextColor(accent[1], accent[2], accent[3])
    importer.description:SetTextColor(text[1], text[2], text[3])
    for _, label in ipairs({ w.importLabel, w.guidesLabel, w.progressLabel, w.history }) do
        if label then label:SetTextColor(muted[1], muted[2], muted[3]) end
    end

    Box(w.importBox.background, theme.bgMedium, theme.border)
    Box(w.currentGuides.frame, theme.bgMedium, theme.border)
    if w.currentGuides.text then w.currentGuides.text:SetTextColor(text[1], text[2], text[3]) end
    local arrow = w.currentGuides.button
    for _, texture in ipairs({ arrow:GetNormalTexture(), arrow:GetPushedTexture(), arrow:GetDisabledTexture() }) do
        if texture then texture:SetDesaturated(true) end
    end
    Lit(arrow, "arrow", arrow:IsMouseOver())
    Lit(importer.closebutton, "cross", importer.closebutton:IsMouseOver())

    for _, button in ipairs(Buttons(w)) do
        Lit(button.frame, "button", button.frame:IsMouseOver())
        if button.text then button.text:SetTextColor(text[1], text[2], text[3]) end
    end

    local bar, fill, back = w.progress, colors.barFill, colors.barBack
    bar:SetStatusBarColor(fill[1], fill[2], fill[3], fill[4] or 1)
    if w.progressBackground then w.progressBackground:SetColorTexture(back[1], back[2], back[3], back[4] or 1) end
    for _, texture in ipairs(Dig(bar, "rxpBorder", "textures") or {}) do Color(texture, colors.border) end
    Edges(bar, px)
end

local function Restore()
    if not dressed then return end
    dressed = false
    local w = Widgets()
    local importer = Dig(w, "import")
    local frame = Dig(importer, "frame")
    if not frame then return end
    frame:SetScale(1)
    for _, part in ipairs({ home.rule, home.rim, home.k }) do part:Hide() end

    local close = importer.closebutton
    close:SetNormalTexture(home.close)
    close:SetPushedTexture(home.close)
    for _, texture in ipairs({ close:GetNormalTexture(), close:GetPushedTexture() }) do
        texture:SetRotation(0)
        texture:SetVertexColor(1, 1, 1, 1)
    end
    close:SetSize(20, 20)
    close:ClearAllPoints()
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 6, 6)
    Unlit(close, 1)

    for _, button in ipairs(Buttons(w)) do
        Unlit(button.frame, 1)
        Edges(button.frame, home.edge)
    end
    local arrow = w.currentGuides.button
    Unlit(arrow, 1)
    for _, texture in ipairs({ arrow:GetNormalTexture(), arrow:GetPushedTexture(), arrow:GetDisabledTexture() }) do
        if texture then
            texture:SetDesaturated(false)
            texture:SetVertexColor(1, 1, 1, 1)
        end
    end
    for _, boxed in ipairs({ frame, w.importBox.background, w.currentGuides.frame, w.progress }) do
        Edges(boxed, home.edge)
    end
    w.progress:SetStatusBarTexture(home.bar)
    w.progress:GetStatusBarTexture():SetDrawLayer("ARTWORK")

    local guideImporter = _G.RXP.guideImporter
    if Has(guideImporter, "UpdateTheme") then Run("ImporterRepaint", guideImporter.UpdateTheme, guideImporter) end
end

local function Repaint()
    Run("ImporterPaint", Paint)
end

function Importer.Start()
    if active then return end
    local guideImporter = Dig(_G.RXP, "guideImporter")
    if not Has(guideImporter, "UpdateImportUI") then return end
    active = true
    if not hooked then
        hooked = true
        hooksecurefunc(guideImporter, "UpdateImportUI", Repaint)
    end
    Repaint()
end

function Importer.Stop()
    if not active then return end
    active = false
    Run("ImporterRestore", Restore)
end

function Importer.Recolor()
    if active then Repaint() end
end

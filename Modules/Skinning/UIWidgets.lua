-- ╔══════════════════════════════════════════════════════════╗
-- ║  UIWidgets.lua                                           ║
-- ║  Module: UI Widgets                                      ║
-- ║  Purpose: Restyles the widgets in the four owned UI      ║
-- ║           widget containers: top-center, center-screen,  ║
-- ║           power bar and below-minimap.                   ║
-- ╚══════════════════════════════════════════════════════════╝

local KE = select(2, ...)

if not KitnEssentials then
    error("UIWidgets: Addon object not initialized. Check file load order!")
    return
end

local UIW = KitnEssentials:NewModule("UIWidgets", "AceEvent-3.0")

-- Styling applies destructively (widths, anchors, textures, fonts, backdrops)
-- and OnDisable is EMPTY, so nothing is ever undone. Core/ProfileManager.lua
-- only defers modules whose name starts "Skin" or that carry this flag, and
-- "UIWidgets" fails the name test. ContextMenus.lua sets it for the same reason.
UIW.keDeferToReload = true

local pairs, ipairs = pairs, ipairs
local pcall = pcall
local _G = _G
local C_Timer = C_Timer
local CreateFrame = CreateFrame
local UIParent = UIParent
local unpack = unpack
local math_max, math_min = math.max, math.min

-- The four containers this module restyles. Widgets are pooled and drawn by
-- many owners (tooltips, nameplates, the objective tracker); everything
-- outside these four is left as Blizzard made it.
local OWNED_CONTAINERS = {
    "UIWidgetTopCenterContainerFrame",
    "UIWidgetCenterScreenContainerFrame",
    "UIWidgetPowerBarContainerFrame",
    "UIWidgetBelowMinimapContainerFrame",
}

local ignoreWidget = {
    [283] = 3463,
}

-- Never a field on the widget: a pooled frame carries its fields into
-- whatever shows it next.
local backdrops = setmetatable({}, { __mode = "k" })

-- Fill color per Blizzard fill kit. Only the plain "widgetstatusbar" frame
-- kit gets one; themed frame kits keep their own art.
local FILL_COLORS = {
    green  = { 0.30, 0.78, 0.30 },
    yellow = { 0.95, 0.77, 0.20 },
    red    = { 0.85, 0.22, 0.22 },
    orange = { 0.95, 0.55, 0.20 },
    blue   = { 0.25, 0.55, 0.90 },
    purple = { 0.64, 0.35, 0.90 },
}

-- A "white" fill takes the bar's own tint. nil leaves Blizzard's fill.
function UIW.ResolveFillColor(frameKit, fillKit, r, g, b)
    if frameKit ~= "widgetstatusbar" or type(fillKit) ~= "string" then return nil end
    local kit = fillKit:lower()
    if kit == "white" then return r, g, b end
    local c = FILL_COLORS[kit]
    if not c then return nil end
    return c[1], c[2], c[3]
end

local FONT_ROLES = {
    Label   = { group = "StatusBar",  flag = "StyleLabel",   size = "LabelSize" },
    BarText = { group = "StatusBar",  flag = "StyleBarText", size = "BarTextSize" },
    Text    = { group = "TextWidget", flag = "StyleText",    size = "Size" },
}

-- The sweep and the SetFontObject hook share this rule. nil leaves
-- Blizzard's font; it is also the hook's off switch, since a hook cannot be
-- removed.
function UIW.FontSizeForRole(db, role)
    local spec = FONT_ROLES[role]
    if not (spec and db and db.Enabled) then return nil end
    local group = db[spec.group]
    if not (group and group.Enabled and group[spec.flag]) then return nil end
    return group[spec.size]
end

function UIW.ShouldCenterText(db)
    return UIW.FontSizeForRole(db, "Text") ~= nil and db.TextWidget.CenterText == true
end

function UIW:UpdateDB()
    self.db = KE.db.profile.Skinning.UIWidgets

    self._styleGen = (self._styleGen or 0) + 1
end

function UIW:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function UIW:OnEnable()
    if KE:ShouldNotLoadModule() then return end
    if not self.db.Enabled then return end

    self:SetupHooks()
    self:StyleExistingWidgets()
    self:EnsureTopCenterHolder()
    self:ApplyTopCenter()
    self:RegisterEditMode()

    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()

        C_Timer.After(0, function() -- was 0.1s
            if self:IsEnabled() then self:StyleExistingWidgets() end
        end)
    end)
end

local fontGen, cachedFontPath, cachedOutline = 0, nil, nil
function UIW:GetFontSettings()
    if self._styleGen ~= fontGen or not cachedFontPath then
        cachedFontPath = KE:GetFontPath(KE:GetEffectiveFont(self.db))
        cachedOutline = KE:GetFontOutline(self.db.FontOutline)
        fontGen = self._styleGen
    end
    return cachedFontPath, cachedOutline
end

local function SetFontIfChanged(fs, path, size, outline)
    local f, s, o = fs:GetFont()
    if f ~= path or s ~= size or (o or "") ~= (outline or "") then
        fs:SetFont(path, size, outline)
    end
end

-- Font strings KE styles, keyed to their role. Blizzard's Setup calls
-- SetFontObject on every update, each second for a timer widget; the hook
-- puts KE's font back before Setup justifies and measures the text.
local fontRoles = setmetatable({}, { __mode = "k" })

local function StyleFont(fs, role)
    local size = UIW.FontSizeForRole(UIW.db, role)
    if not size then return false end
    local fontPath, outline = UIW:GetFontSettings()
    SetFontIfChanged(fs, fontPath, size, outline)
    fs:SetShadowColor(0, 0, 0, 0)
    return true
end

-- Runs inside Blizzard's widget pass, so nothing KE does may stop it.
local function ReapplyFont(fs)
    pcall(StyleFont, fs, fontRoles[fs])
end

-- Per font string, never on a mixin: these pools belong to the four owned
-- containers and never lend a frame to a tooltip.
local function ApplyFont(fs, role)
    if StyleFont(fs, role) and not fontRoles[fs] then
        fontRoles[fs] = role
        hooksecurefunc(fs, "SetFontObject", ReapplyFont)
    end
end

local function HideFill(record)
    if record.fill then record.fill:Hide() end
end

-- A released bar is hidden with the last widget's fill still on it, and the
-- next Setup shows it again before KE's sweep has seen the new kit. Hiding
-- the fill with the bar and re-sweeping on show keeps the old fill off it.
local function RestyleOnShow()
    UIW:OnWidgetEvent()
end

-- KE's fill sits one sublevel above Blizzard's fill, which is in ARTWORK:
-- regions sharing a layer and sublevel draw in no fixed order. The text is
-- in OVERLAY, above both. Anchored to the fill texture, it follows the value
-- and the smooth fill with no Lua of its own. Some widgets name a plain
-- Frame .Bar; only a StatusBar has a fill texture.
local function UpdateFill(bar, record, barDB)
    local fillTex = bar:IsObjectType("StatusBar") and bar:GetStatusBarTexture()
    if not fillTex then
        HideFill(record)
        return
    end

    local r, g, b = UIW.ResolveFillColor(bar.frameTextureKit, bar.textureKit, bar:GetStatusBarColor())
    if not r then
        HideFill(record)
        return
    end

    local fill = record.fill
    if not fill then
        fill = bar:CreateTexture(nil, "ARTWORK")
        record.fill = fill
        record:SetScript("OnHide", HideFill)
        record:SetScript("OnShow", RestyleOnShow)
    end

    local layer, sublevel = fillTex:GetDrawLayer()
    fill:SetDrawLayer(layer, math_min((sublevel or 0) + 1, 7))

    if record.fillAnchor ~= fillTex then
        fill:ClearAllPoints()
        fill:SetPoint("TOPLEFT", fillTex, "TOPLEFT")
        fill:SetPoint("BOTTOMRIGHT", fillTex, "BOTTOMRIGHT")
        record.fillAnchor = fillTex
    end

    local path = KE:GetStatusbarPath(barDB.BarTexture)
    if record.fillPath ~= path then
        fill:SetTexture(path)
        record.fillPath = path
    end

    fill:SetVertexColor(r, g, b)
    fill:Show()
end

-- Text widgets KE centers. Setup justifies from the widget's own alignment
-- inside a fixed width, which leaves a short string off-center; the hook
-- turns it back to CENTER, and its own re-entrant call passes CENTER.
local centered = setmetatable({}, { __mode = "k" })

local function CenterNow(fs, justify)
    if justify ~= "CENTER" and UIW.ShouldCenterText(UIW.db) then
        fs:SetJustifyH("CENTER")
    end
end

local function ReCenter(fs, justify)
    pcall(CenterNow, fs, justify)
end

local function ApplyCenter(fs)
    if not UIW.ShouldCenterText(UIW.db) then return end
    CenterNow(fs, fs:GetJustifyH())
    if not centered[fs] then
        centered[fs] = true
        hooksecurefunc(fs, "SetJustifyH", ReCenter)
    end
end

-- Setup re-sets the icon's texture, size and mask shown-state and the
-- Border's atlas and shown-state on every update, but never the texcoords,
-- either border's alpha or which masks the icon carries: one pass holds.
local skinnedIcons = setmetatable({}, { __mode = "k" })

local function StyleSpellIcon(spell)
    local icon = spell and spell.Icon
    local S = KE.Skins
    if not (icon and S) or skinnedIcons[icon] then return end
    skinnedIcons[icon] = true

    if spell.IconMask then icon:RemoveMaskTexture(spell.IconMask) end
    if spell.CircleMask then icon:RemoveMaskTexture(spell.CircleMask) end
    if spell.Border then spell.Border:SetAlpha(0) end
    if spell.DebuffBorder then spell.DebuffBorder:SetAlpha(0) end
    S.Icon(icon, true)
end

function UIW:StyleStatusBarWidget(widget)
    if not widget or widget:IsForbidden() then return end

    if widget.widgetID and ignoreWidget[widget.widgetSetID] == widget.widgetID then return end

    local barDB = self.db.StatusBar

    local width = barDB.Width or 0
    if width > 0 then
        widget:SetWidth(width)
        if widget.Bar then
            widget.Bar:SetWidth(width)
        end
    end

    -- Font only. Setup measures Label's width and height and sizes the widget
    -- from them; an anchor written here would be measured instead of the text.
    if widget.Label then ApplyFont(widget.Label, "Label") end

    -- A capture bar's Bar is a Texture (UIWidgetTemplateCaptureBar.xml), not
    -- a frame; the backdrop below is parented to it.
    local bar = widget.Bar
    if bar and bar.GetObjectType and bar:IsObjectType("Texture") then bar = nil end
    if bar then

        if bar.Label then ApplyFont(bar.Label, "BarText") end

        if bar.LeftText and barDB.StyleBarText then
            ApplyFont(bar.LeftText, "BarText")
            bar.LeftText:SetJustifyH("LEFT")
            bar.LeftText:SetJustifyV("MIDDLE")
        end

        if bar.RightText and barDB.StyleBarText then
            ApplyFont(bar.RightText, "BarText")
            bar.RightText:SetJustifyH("RIGHT")
            bar.RightText:SetJustifyV("MIDDLE")
        end

        if barDB.StripTextures then
            if bar.BGLeft then bar.BGLeft:SetAlpha(0) end
            if bar.BGRight then bar.BGRight:SetAlpha(0) end
            if bar.BGCenter then bar.BGCenter:SetAlpha(0) end
            if bar.BorderLeft then bar.BorderLeft:SetAlpha(0) end
            if bar.BorderRight then bar.BorderRight:SetAlpha(0) end
            if bar.BorderCenter then bar.BorderCenter:SetAlpha(0) end
            if bar.Spark then bar.Spark:SetAlpha(0) end

            if not backdrops[bar] then

                local backdrop = CreateFrame("Frame", nil, bar)
                backdrop:SetFrameLevel(math_max(bar:GetFrameLevel() - 1, 0))
                backdrop:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1)
                backdrop:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)

                backdrop.bg = backdrop:CreateTexture(nil, "BACKGROUND")
                backdrop.bg:SetAllPoints()
                backdrop.bg:SetColorTexture(unpack(barDB.BackdropColor))

                local borderFrame = CreateFrame("Frame", nil, bar)
                borderFrame:SetFrameLevel(bar:GetFrameLevel() + 1)
                borderFrame:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1)
                borderFrame:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)
                KE:AddBorders(borderFrame, barDB.BorderColor)

                backdrop.borderFrame = borderFrame
                backdrops[bar] = backdrop
            end
        end

        local record = backdrops[bar]
        if record then
            if barDB.StripTextures then
                UpdateFill(bar, record, barDB)
            else
                HideFill(record)
            end
        end
    end
end

local TEXT_WITH_STATE = Enum and Enum.UIWidgetVisualizationType
    and Enum.UIWidgetVisualizationType.TextWithState

function UIW:StyleTextWidget(widget)
    if not widget or widget:IsForbidden() then return end

    -- No anchor or width here. Setup sizes the widget from this fontstring's
    -- string width on every update; a forced widget width leaves Text at its
    -- TOPLEFT anchor, and a LEFT/RIGHT anchor here overrides the width Setup
    -- gives it.
    local text = widget.Text
    if not text then return end
    ApplyFont(text, "Text")
    if TEXT_WITH_STATE and widget.widgetType == TEXT_WITH_STATE then ApplyCenter(text) end
end

function UIW:StyleWidgetByType(widget)
    if not widget or widget:IsForbidden() then return end
    if widget.Bar and self.db.StatusBar.Enabled then
        self:StyleStatusBarWidget(widget)
    elseif widget.Text and not widget.Bar and self.db.TextWidget.Enabled then
        self:StyleTextWidget(widget)
    elseif widget.Spell and self.db.SkinIcons then
        StyleSpellIcon(widget.Spell)
    end
end

-- One timer drains however many widgets a sweep queued. pcall: a widget
-- mid-teardown must not stop the rest of the drain.
local queue, queued, flushScheduled = {}, setmetatable({}, { __mode = "k" }), false

function UIW:Flush()
    flushScheduled = false

    local list = queue
    queue = {}

    for i = 1, #list do
        local widget = list[i]
        queued[widget] = nil
        if self:IsEnabled() and self.db.Enabled then
            pcall(self.StyleWidgetByType, self, widget)
        end
    end
end

function UIW:QueueWidget(widget)
    if not widget or queued[widget] then return end

    queued[widget] = true
    queue[#queue + 1] = widget

    if not flushScheduled then
        flushScheduled = true
        C_Timer.After(0, function() UIW:Flush() end)
    end
end

-- No hook on the widget mixins: a post-hook on Setup runs inside
-- UIWidgetManager's pass and taints the rest of it, and the next widget's
-- own Setup then throws on a secret. The game's widget events drive the
-- restyle from KE's own frame instead: one timer tick to sweep after
-- Blizzard's containers have processed the change, a second to flush.
-- ApplyFont's and ApplyCenter's per-font-string hooks are the exception.
local restyleScheduled = false
function UIW:OnWidgetEvent()
    if restyleScheduled or not self.db.Enabled then return end
    restyleScheduled = true
    C_Timer.After(0, function()
        restyleScheduled = false
        if UIW:IsEnabled() then UIW:StyleExistingWidgets() end
    end)
end

function UIW:SetupHooks()
    self:RegisterEvent("UPDATE_UI_WIDGET", "OnWidgetEvent")
    self:RegisterEvent("UPDATE_ALL_UI_WIDGETS", "OnWidgetEvent")
end

function UIW:StyleExistingWidgets()
    if not self.db.Enabled then return end

    for _, name in ipairs(OWNED_CONTAINERS) do
        local container = _G[name]
        if container and container.widgetFrames then
            for _, widget in pairs(container.widgetFrames) do
                self:QueueWidget(widget)
            end
        end
    end
end

---------------------------------------------------------------------------------
-- Top-center container control
---------------------------------------------------------------------------------
-- The container is a plain UIParent child anchored once in XML; nothing in
-- the client re-anchors it and it only shows itself when it registers its
-- widget set at load. So one placement from KE's own execution holds, and
-- no hook on the container is needed (a post-hook there would run inside
-- UIWidgetManager's pass and taint the widgets it lays out next).

function UIW:EnsureTopCenterHolder()
    if self.topCenterHolder then return end
    self.topCenterHolder = CreateFrame("Frame", "KE_TopCenterWidgetHolder", UIParent)
    self.topCenterHolder:SetSize(400, 40)
end

function UIW:ApplyTopCenter()
    local container = _G.UIWidgetTopCenterContainerFrame
    local tc = self.db and self.db.TopCenter
    if not (container and tc and self.topCenterHolder) then return end

    if not tc.Enabled then
        -- Replay the placement recorded before the first move.
        local orig = self._topCenterOrig
        if orig then
            container:ClearAllPoints()
            container:SetPoint(orig.point, orig.relativeTo, orig.relativePoint, orig.x, orig.y)
            container:SetScale(orig.scale)
            container:SetFrameStrata(orig.strata)
            container:Show()
            self._topCenterOrig = nil
        end
        return
    end

    if not self._topCenterOrig then
        local point, relativeTo, relativePoint, x, y = container:GetPoint()
        self._topCenterOrig = {
            point = point or "TOP", relativeTo = relativeTo or UIParent,
            relativePoint = relativePoint or "TOP", x = x or 0, y = y or -15,
            scale = container:GetScale(), strata = container:GetFrameStrata(),
        }
    end

    KE:ApplyFramePosition(self.topCenterHolder, tc.Position, tc)
    container:ClearAllPoints()
    container:SetPoint("TOP", self.topCenterHolder, "TOP", 0, 0)
    container:SetScale(tc.Scale or 1)
    container:SetFrameStrata(tc.Strata or "MEDIUM")
    container:SetShown(not tc.Hide)
end

function UIW:RegisterEditMode()
    if not KE.EditMode or self.editModeRegistered then return end
    self.editModeRegistered = true
    KE.EditMode:RegisterElement({
        key = "TopCenterWidgets",
        module = self,
        isEligible = function()
            return self.db and self.db.TopCenter
                and self.db.TopCenter.Enabled == true or false
        end,
        displayName = "Top-Center Widgets",
        frame = self.topCenterHolder,
        getPosition = function() return self.db.TopCenter.Position end,
        setPosition = function(pos)
            local p = self.db.TopCenter.Position
            p.AnchorFrom = pos.AnchorFrom
            p.AnchorTo = pos.AnchorTo
            p.XOffset = pos.XOffset
            p.YOffset = pos.YOffset
            self:ApplyTopCenter()
        end,
        getParentFrame = function()
            local tc = self.db.TopCenter
            return KE:ResolveAnchorFrame(tc.anchorFrameType, tc.ParentFrame)
        end,
        guiPath = "SkinBlizzardFrames",
        guiTab = "SkinBlizzardFramesWidgets",
    })
end

-- ApplySettings does not call UpdateDB. GetFontSettings caches its resolved
-- font path and outline keyed on _styleGen, and _styleGen only bumps inside
-- UpdateDB, so without this call the Font and Outline dropdowns write
-- to the DB but the cache never invalidates: nothing restyles until a reload
-- or profile switch, and even newly created widgets get the stale font.
-- BlizzardFonts.lua already calls UpdateDB in this same slot of its
-- own ApplySettings; this mirrors that shape.
function UIW:ApplySettings()
    if KE:ShouldNotLoadModule() then return end
    self:UpdateDB()
    if not self.db.Enabled then return end
    self:StyleExistingWidgets()
    self:ApplyTopCenter()
end

function UIW:OnDisable()
end

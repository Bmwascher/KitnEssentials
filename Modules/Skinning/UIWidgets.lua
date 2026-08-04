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

local hooksecurefunc = hooksecurefunc
local pairs = pairs
local _G = _G
local C_Timer = C_Timer
local unpack = unpack

local hooked = {
    statusBar = false,
    textWithState = false,
    captureBar = false,
}

local ignoreWidget = {
    [283] = 3463,
}

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

function UIW:StyleStatusBarWidget(widget)
    if not widget or widget:IsForbidden() then return end

    if widget.widgetID and ignoreWidget[widget.widgetSetID] == widget.widgetID then return end

    local fontPath, outline = self:GetFontSettings()
    local barDB = self.db.StatusBar

    local width = barDB.Width or 0
    if width > 0 then
        widget:SetWidth(width)
        if widget.Bar then
            widget.Bar:SetWidth(width)
        end
    end

    if widget.Label and barDB.StyleLabel then
        SetFontIfChanged(widget.Label, fontPath, barDB.LabelSize, outline)
        widget.Label:SetShadowColor(0, 0, 0, 0)

        widget.Label:ClearAllPoints()
        widget.Label:SetPoint("LEFT", widget, "LEFT", 0, 0)
        widget.Label:SetPoint("RIGHT", widget, "RIGHT", 0, 0)
        widget.Label:SetJustifyH("CENTER")
    end

    local bar = widget.Bar
    if bar then

        if bar.Label and barDB.StyleBarText then
            SetFontIfChanged(bar.Label, fontPath, barDB.BarTextSize, outline)
            bar.Label:SetShadowColor(0, 0, 0, 0)

            bar.Label:ClearAllPoints()
            bar.Label:SetPoint("LEFT", bar, "LEFT", 0, 0)
            bar.Label:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
            bar.Label:SetJustifyH("CENTER")
            bar.Label:SetJustifyV("MIDDLE")
        end

        if bar.LeftText and barDB.StyleBarText then
            SetFontIfChanged(bar.LeftText, fontPath, barDB.BarTextSize, outline)
            bar.LeftText:SetShadowColor(0, 0, 0, 0)
            bar.LeftText:SetJustifyH("LEFT")
            bar.LeftText:SetJustifyV("MIDDLE")
        end

        if bar.RightText and barDB.StyleBarText then
            SetFontIfChanged(bar.RightText, fontPath, barDB.BarTextSize, outline)
            bar.RightText:SetShadowColor(0, 0, 0, 0)
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

            if not bar.keUIWidgetBackdrop then

                local backdrop = CreateFrame("Frame", nil, bar)
                backdrop:SetFrameLevel(math.max(bar:GetFrameLevel() - 1, 0))
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
                bar.keUIWidgetBackdrop = backdrop
            end
        end
    end
end

function UIW:StyleTextWidget(widget)
    if not widget or widget:IsForbidden() then return end

    local fontPath, outline = self:GetFontSettings()
    local textDB = self.db.TextWidget

    local width = textDB.Width or 0
    if width > 0 then
        widget:SetWidth(width)
    end

    if widget.Text and textDB.StyleText then
        SetFontIfChanged(widget.Text, fontPath, textDB.Size, outline)
        widget.Text:SetShadowColor(0, 0, 0, 0)

        widget.Text:ClearAllPoints()
        widget.Text:SetPoint("LEFT", widget, "LEFT", 0, 0)
        widget.Text:SetPoint("RIGHT", widget, "RIGHT", 0, 0)
        widget.Text:SetJustifyH("CENTER")
        widget.Text:SetJustifyV("MIDDLE")
    end
end

-- UI widgets are pooled, and GameTooltip borrows them for the widget sets on
-- Area POI tooltips. Restyling one there means our insecure ClearAllPoints /
-- SetPoint / SetWidth run on a frame Blizzard then lays out itself, and on
-- hide DefaultWidgetLayout -> LayoutFrame compares a secret number in tainted
-- execution:
--
--   LayoutFrame.lua: attempt to compare a secret number value
--   (execution tainted by an addon)
--
-- Nothing is lost by skipping them: tooltip widget sets are transient and
-- already inherit the tooltip's own styling.
-- was a parent walk that called :GetName() on whatever it
-- found. Something in that chain is not a real frame -- a proxy or a
-- plain table with a GetName field -- and the call died with
--
--   UIWidgets.lua: calling '?' on bad self
--   (Usage: local name = self:GetName())
--
-- reported from clicking the wind orb in Skyreach.
--
-- No walk is needed. Blizzard passes the container straight to Setup:
--
--   UIWidgetTemplateStatusBarMixin:Setup(widgetInfo, widgetContainer)
--
-- and GameTooltip creates exactly one (GameTooltip.lua: self.widgetContainer
-- = CreateFrame("FRAME", nil, self, "UIWidgetContainerTemplate")). So the
-- test is an identity comparison against the tooltips that own one --
-- no method calls on unknown objects, nothing to go wrong.
local TOOLTIPS_WITH_WIDGETS = {
    "GameTooltip", "ItemRefTooltip", "EmbeddedItemTooltip",
    "GameTooltipTooltip", "NamePlateTooltip",
}

local function InTooltip(_widget, container)
    if not container then return false end

    for _, name in ipairs(TOOLTIPS_WITH_WIDGETS) do
        local tip = _G[name]
        if tip and rawget(tip, "widgetContainer") == container then return true end
    end
    return false
end

function UIW:SetupHooks()

    if not hooked.statusBar and _G.UIWidgetTemplateStatusBarMixin then
        hooksecurefunc(_G.UIWidgetTemplateStatusBarMixin, "Setup", function(widget, _, container)
            if self.db.Enabled and self.db.StatusBar.Enabled and not InTooltip(widget, container) then
                self:StyleStatusBarWidget(widget)
            end
        end)
        hooked.statusBar = true
    end

    if not hooked.textWithState and _G.UIWidgetTemplateTextWithStateMixin then
        hooksecurefunc(_G.UIWidgetTemplateTextWithStateMixin, "Setup", function(widget, _, container)
            if self.db.Enabled and self.db.TextWidget.Enabled and not InTooltip(widget, container) then
                self:StyleTextWidget(widget)
            end
        end)
        hooked.textWithState = true
    end

    local extraBarMixins = {
        "UIWidgetTemplateDiscreteProgressBarMixin",
        "UIWidgetTemplateCaptureBarMixin",
        "UIWidgetTemplateDoubleStatusBarMixin",
    }
    for _, mixinName in ipairs(extraBarMixins) do
        local mixin = _G[mixinName]
        if mixin and mixin.Setup and not hooked[mixinName] then
            hooksecurefunc(mixin, "Setup", function(widget, _, container)
                if self.db.Enabled and self.db.StatusBar.Enabled and not InTooltip(widget, container) then
                    self:StyleWidgetByType(widget)
                end
            end)
            hooked[mixinName] = true
        end
    end

    if not (hooked.statusBar and hooked.textWithState) then
        C_Timer.After(0, function() -- was 1s; widget mixins
            if self:IsEnabled() then self:SetupHooks() end -- appear within frames
        end)
    end
end

function UIW:StyleExistingWidgets()
    if not self.db.Enabled then return end

    if _G.UIWidgetTopCenterContainerFrame and _G.UIWidgetTopCenterContainerFrame.widgetFrames then
        for _, widget in pairs(_G.UIWidgetTopCenterContainerFrame.widgetFrames) do
            self:StyleWidgetByType(widget)
        end
    end

    if _G.UIWidgetCenterScreenContainerFrame and _G.UIWidgetCenterScreenContainerFrame.widgetFrames then
        for _, widget in pairs(_G.UIWidgetCenterScreenContainerFrame.widgetFrames) do
            self:StyleWidgetByType(widget)
        end
    end

    if _G.UIWidgetPowerBarContainerFrame and _G.UIWidgetPowerBarContainerFrame.widgetFrames then
        for _, widget in pairs(_G.UIWidgetPowerBarContainerFrame.widgetFrames) do
            self:StyleWidgetByType(widget)
        end
    end

    if _G.UIWidgetBelowMinimapContainerFrame and _G.UIWidgetBelowMinimapContainerFrame.widgetFrames then
        for _, widget in pairs(_G.UIWidgetBelowMinimapContainerFrame.widgetFrames) do
            self:StyleWidgetByType(widget)
        end
    end
end

function UIW:StyleWidgetByType(widget)
    if not widget or widget:IsForbidden() then return end
    if widget.Bar and self.db.StatusBar.Enabled then
        self:StyleStatusBarWidget(widget)
    elseif widget.Text and not widget.Bar and self.db.TextWidget.Enabled then
        self:StyleTextWidget(widget)
    end
end

-- ApplySettings does not call UpdateDB. GetFontSettings caches its resolved
-- font path and outline keyed on _styleGen, and _styleGen only bumps inside
-- UpdateDB, so without this call the Font and Outline dropdowns write
-- to the DB but the cache never invalidates: nothing restyles until a reload
-- or profile switch, and even newly created widgets get the stale font.
-- BlizzardFonts.lua already calls UpdateDB in this same slot of its
-- own ApplySettings; this mirrors that shape. Intentional departure from the
-- reference, not a port gap.
function UIW:ApplySettings()
    if KE:ShouldNotLoadModule() then return end
    self:UpdateDB()
    if not self.db.Enabled then return end
    self:StyleExistingWidgets()
end

function UIW:OnDisable()
end

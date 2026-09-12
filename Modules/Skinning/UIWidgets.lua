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
local math_max = math.max

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

    -- Font only. Setup measures Label's width and height and sizes the widget
    -- from them; an anchor written here would be measured instead of the text.
    if widget.Label and barDB.StyleLabel then
        SetFontIfChanged(widget.Label, fontPath, barDB.LabelSize, outline)
        widget.Label:SetShadowColor(0, 0, 0, 0)
    end

    -- A capture bar's Bar is a Texture (UIWidgetTemplateCaptureBar.xml), not
    -- a frame; the backdrop below is parented to it.
    local bar = widget.Bar
    if bar and bar.GetObjectType and bar:IsObjectType("Texture") then bar = nil end
    if bar then

        if bar.Label and barDB.StyleBarText then
            SetFontIfChanged(bar.Label, fontPath, barDB.BarTextSize, outline)
            bar.Label:SetShadowColor(0, 0, 0, 0)
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
    end
end

function UIW:StyleTextWidget(widget)
    if not widget or widget:IsForbidden() then return end

    local fontPath, outline = self:GetFontSettings()
    local textDB = self.db.TextWidget

    -- Font only. Setup sizes the widget from this fontstring's string width
    -- on every update; a forced widget width leaves Text at its TOPLEFT
    -- anchor, and a LEFT/RIGHT anchor here overrides the width Setup gives it.
    if widget.Text and textDB.StyleText then
        SetFontIfChanged(widget.Text, fontPath, textDB.Size, outline)
        widget.Text:SetShadowColor(0, 0, 0, 0)
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
-- Top-centre container control
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
        displayName = "Top-Centre Widgets",
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

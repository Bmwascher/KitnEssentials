-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class SkinActionBars: AceModule, AceEvent-3.0, AceHook-3.0
local SK = KitnEssentials:NewModule("SkinActionBars", "AceEvent-3.0", "AceHook-3.0")

-- Localization
local CreateFrame = CreateFrame
local ipairs = ipairs
local pairs = pairs
local InCombatLockdown = InCombatLockdown
local PetHasActionBar = PetHasActionBar
local GetNumShapeshiftForms = GetNumShapeshiftForms
local GetCursorPosition = GetCursorPosition
local pcall = pcall
local SecureCmdOptionParse = SecureCmdOptionParse
local hooksecurefunc = hooksecurefunc
local GetPetActionInfo = GetPetActionInfo
local GetShapeshiftFormInfo = GetShapeshiftFormInfo
local getmetatable = getmetatable
local table_insert = table.insert
local unpack = unpack
local _G = _G

-- Frame map
local BAR_FRAME_MAP = {
    Bar1 = { frame = "MainActionBar", prefix = "ActionButton" },
    Bar2 = { frame = "MultiBarBottomLeft", prefix = "MultiBarBottomLeftButton" },
    Bar3 = { frame = "MultiBarBottomRight", prefix = "MultiBarBottomRightButton" },
    Bar4 = { frame = "MultiBarRight", prefix = "MultiBarRightButton" },
    Bar5 = { frame = "MultiBarLeft", prefix = "MultiBarLeftButton" },
    Bar6 = { frame = "MultiBar5", prefix = "MultiBar5Button" },
    Bar7 = { frame = "MultiBar6", prefix = "MultiBar6Button" },
    Bar8 = { frame = "MultiBar7", prefix = "MultiBar7Button" },
    PetBar = { frame = "PetActionBar", prefix = "PetActionButton" },
    StanceBar = { frame = "StanceBar", prefix = "StanceButton" },
}

-- Hidden frame for hiding Blizzard elements
local hiddenFrame = CreateFrame("Frame")
hiddenFrame:Hide()

-- Hide a Blizzard element by re-parenting to hidden frame
local function HideElement(object, ...)
    if type(object) == "string" then
        object = _G[object]
    end
    if ... then
        for index = 1, select("#", ...) do
            object = object[select(index, ...)]
        end
    end
    if object then
        if object.HideBase then
            object:HideBase(true)
        else
            object:Hide(true)
        end
        if object.EnableMouse then object:EnableMouse(false) end
        if object.UnregisterAllEvents then
            object:UnregisterAllEvents()
            object:SetAttribute("statehidden", true)
        end
        if object.SetUserPlaced then
            pcall(object.SetUserPlaced, object, true)
            pcall(object.SetDontSavePosition, object, true)
        end
        object:SetParent(hiddenFrame)
    end
end

-- Icon zoom
local function ApplyZoom(tex, zoom)
    local texMin = 0.25 * zoom
    local texMax = 1 - 0.25 * zoom
    tex:SetTexCoord(texMin, texMax, texMin, texMax)
end

-- Add pixel-perfect borders to a frame
local function AddBorders(frame, color, borderParent)
    if not frame then return end
    color = color or { 0, 0, 0, 1 }
    borderParent = borderParent or frame

    frame.borders = frame.borders or {}

    local function CreateBorder(point1, point2, width, height)
        local tex = borderParent:CreateTexture(nil, "OVERLAY", nil, 7)
        tex:SetColorTexture(unpack(color))
        tex:SetTexelSnappingBias(0)
        tex:SetSnapToPixelGrid(false)
        if width then
            tex:SetWidth(width)
            tex:SetPoint("TOPLEFT", frame, point1, 0, 0)
            tex:SetPoint("BOTTOMLEFT", frame, point2, 0, 0)
        else
            tex:SetHeight(height)
            tex:SetPoint("TOPLEFT", frame, point1, 0, 0)
            tex:SetPoint("TOPRIGHT", frame, point2, 0, 0)
        end
        return tex
    end

    frame.borders.top = CreateBorder("TOPLEFT", "TOPRIGHT", nil, 1)

    frame.borders.bottom = borderParent:CreateTexture(nil, "OVERLAY", nil, 7)
    frame.borders.bottom:SetHeight(1)
    frame.borders.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    frame.borders.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    frame.borders.bottom:SetColorTexture(unpack(color))
    frame.borders.bottom:SetTexelSnappingBias(0)
    frame.borders.bottom:SetSnapToPixelGrid(false)

    frame.borders.left = CreateBorder("TOPLEFT", "BOTTOMLEFT", 1, nil)

    frame.borders.right = borderParent:CreateTexture(nil, "OVERLAY", nil, 7)
    frame.borders.right:SetWidth(1)
    frame.borders.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    frame.borders.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    frame.borders.right:SetColorTexture(unpack(color))
    frame.borders.right:SetTexelSnappingBias(0)
    frame.borders.right:SetSnapToPixelGrid(false)

    function frame:SetBorderColor(r, g, b, a)
        if not self.borders then return end
        for _, tex in pairs(self.borders) do
            tex:SetColorTexture(r, g, b, a or 1)
        end
    end

    return frame
end

-- Disable Blizzard bar mouse interaction
local function BlizzBarMouseToggle(barKey)
    local frameInfo = BAR_FRAME_MAP[barKey]
    local frame = _G[frameInfo.frame]
    if frame then frame:EnableMouse(false) end
end

-- Build config for a single bar from DB
local configTable = {}
local function BuildBarConfig(barKey, barDB, globalMouseover)
    local frameInfo = BAR_FRAME_MAP[barKey]
    if not frameInfo or not barDB then return nil end

    local frame = _G[frameInfo.frame]
    if not frame then return nil end

    local useGlobal = barDB.Mouseover and barDB.Mouseover.GlobalOverride
    local mouseoverEnabled, mouseoverAlpha
    if useGlobal then
        mouseoverEnabled = globalMouseover.Enabled == true
        mouseoverAlpha = globalMouseover.Alpha or 1
    else
        mouseoverEnabled = barDB.Mouseover and barDB.Mouseover.Enabled == true
        mouseoverAlpha = (barDB.Mouseover and barDB.Mouseover.Alpha) or 1
    end

    return {
        name = barKey,
        dbReference = barDB,
        frame = frame,
        buttonPrefix = frameInfo.prefix,
        spacing = barDB.Spacing or 1,
        buttonSize = barDB.ButtonSize or 40,
        totalButtons = barDB.TotalButtons or 12,
        layout = barDB.Layout or "HORIZONTAL",
        growthDirection = barDB.GrowthDirection or "RIGHT",
        buttonsPerLine = barDB.ButtonsPerLine or 12,
        anchorFrom = barDB.Position and barDB.Position.AnchorFrom or "BOTTOM",
        relativeTo = _G[barDB.ParentFrame] or UIParent,
        anchorTO = barDB.Position and barDB.Position.AnchorTo or "BOTTOM",
        x = barDB.Position and barDB.Position.XOffset or 0,
        y = barDB.Position and barDB.Position.YOffset or 0,
        enabled = barDB.Enabled ~= false,
        mouseover = {
            enabled = mouseoverEnabled,
            fadeInDuration = globalMouseover.FadeInDuration or 0.3,
            fadeOutDuration = globalMouseover.FadeOutDuration or 1,
            alpha = mouseoverAlpha,
        }
    }
end

function SK:UpdateDB()
    self.db = KE.db.profile.Skinning.ActionBars
end

function SK:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function SK:BuildConfigTable()
    configTable = {}
    if not self.db or not self.db.Bars then return end
    local globalMouseover = self.db.Mouseover or {}

    for barKey, _ in pairs(BAR_FRAME_MAP) do
        BlizzBarMouseToggle(barKey)
        local barDB = self.db.Bars[barKey]
        if barDB then
            local cfg = BuildBarConfig(barKey, barDB, globalMouseover)
            if cfg then
                table_insert(configTable, cfg)
            end
        end
    end
end

-- Remap keybind text to shorter versions
local function RemapKeyText(button)
    local text = button.HotKey:GetText() or ""
    if not text or text == "" then return end
    text = text:upper()
    text = text:gsub(" ", "")
    text = text:gsub("%-", "")
    text = text:gsub("SPACEBAR", "SP")
    text = text:gsub("MIDDLEMOUSE", "M3")
    text = text:gsub("MOUSEWHEELUP", "MWU")
    text = text:gsub("MOUSEWHEELDOWN", "MWD")
    text = text:gsub("MOUSEBUTTON4", "M4")
    text = text:gsub("MOUSEBUTTON5", "M5")
    text = text:gsub("NUMPAD%s*(%d)", "NP%1")
    text = text:gsub("NUMPAD", "NP")
    button.HotKey:SetText(text)
end

-- Get font sizes for a bar, respects GlobalOverride
function SK:GetFontSizes(barKey)
    local barDB = self.db.Bars and self.db.Bars[barKey]
    local globalFontSizes = self.db.FontSizes or {}
    local barFontSizes = barDB and barDB.FontSizes or {}
    local useGlobal = barFontSizes.GlobalOverride == true
    if useGlobal then
        return {
            keybind = globalFontSizes.KeybindSize or 12,
            cooldown = globalFontSizes.CooldownSize or 14,
            charge = globalFontSizes.ChargeSize or 12,
            macro = globalFontSizes.MacroSize or 10,
        }
    else
        return {
            keybind = barFontSizes.KeybindSize or 12,
            cooldown = barFontSizes.CooldownSize or 14,
            charge = barFontSizes.ChargeSize or 12,
            macro = barFontSizes.MacroSize or 10,
        }
    end
end

-- Get text positions for a bar, respects GlobalOverride
function SK:GetTextPositions(barKey)
    local barDB = self.db.Bars and self.db.Bars[barKey]
    local barTextPos = barDB and barDB.TextPositions or {}
    local useGlobal = barTextPos.GlobalOverride ~= false
    if useGlobal then
        return {
            keybindAnchor = self.db.KeybindAnchor or "TOPRIGHT",
            keybindXOffset = self.db.KeybindXOffset or -2,
            keybindYOffset = self.db.KeybindYOffset or -2,
            chargeAnchor = self.db.ChargeAnchor or "BOTTOMRIGHT",
            chargeXOffset = self.db.ChargeXOffset or -2,
            chargeYOffset = self.db.ChargeYOffset or 2,
            macroAnchor = self.db.MacroAnchor or "BOTTOM",
            macroXOffset = self.db.MacroXOffset or 0,
            macroYOffset = self.db.MacroYOffset or -2,
            cooldownAnchor = self.db.CooldownAnchor or "CENTER",
            cooldownXOffset = self.db.CooldownXOffset or 0,
            cooldownYOffset = self.db.CooldownYOffset or 0,
        }
    else
        return {
            keybindAnchor = barTextPos.KeybindAnchor or "TOPRIGHT",
            keybindXOffset = barTextPos.KeybindXOffset or -2,
            keybindYOffset = barTextPos.KeybindYOffset or -2,
            chargeAnchor = barTextPos.ChargeAnchor or "BOTTOMRIGHT",
            chargeXOffset = barTextPos.ChargeXOffset or -2,
            chargeYOffset = barTextPos.ChargeYOffset or 2,
            macroAnchor = barTextPos.MacroAnchor or "BOTTOM",
            macroXOffset = barTextPos.MacroXOffset or 0,
            macroYOffset = barTextPos.MacroYOffset or -2,
            cooldownAnchor = barTextPos.CooldownAnchor or "CENTER",
            cooldownXOffset = barTextPos.CooldownXOffset or 0,
            cooldownYOffset = barTextPos.CooldownYOffset or 0,
        }
    end
end

-- Get bar-specific config
function SK:GetBarConfig(barKey)
    return self.db.Bars and self.db.Bars[barKey]
end

-- Style button texts
function SK:StyleButtonText(button, barKey)
    if not button then return end
    local hotkey = button.HotKey
    local name = button.Name
    local count = button.Count
    local cooldown = button.cooldown
    local fontpath = KE:GetFontPath(self.db.FontFace)

    local fontSizes = self:GetFontSizes(barKey)
    local textPos = self:GetTextPositions(barKey)

    -- Style cooldown text
    if cooldown then
        local fontSize = math.max(8, fontSizes.cooldown)
        for _, region in ipairs({ cooldown:GetRegions() }) do
            if region:GetObjectType() == "FontString" then
                pcall(function()
                    region:ClearAllPoints()
                    region:SetPoint(textPos.cooldownAnchor, button, textPos.cooldownAnchor,
                        textPos.cooldownXOffset, textPos.cooldownYOffset)
                    region:SetFont(fontpath, fontSize, self.db.FontOutline)
                    region:SetTextColor(1, 1, 1, 1)
                    region:SetShadowOffset(0, 0)
                    region:SetShadowColor(0, 0, 0, 0)
                    region:SetAlpha(1)
                    region:SetJustifyH("CENTER")
                end)
            end
        end
    end

    -- Style keybind text
    if hotkey then
        local fontSize = math.max(6, fontSizes.keybind)
        hotkey:ClearAllPoints()
        hotkey:SetPoint(textPos.keybindAnchor, button, textPos.keybindAnchor,
            textPos.keybindXOffset, textPos.keybindYOffset)
        hotkey:SetWidth((button:GetWidth() - 2) or 0)
        hotkey:SetFont(fontpath, fontSize, self.db.FontOutline)
        hotkey:SetShadowColor(0, 0, 0, 0)
        hotkey:SetJustifyH("RIGHT")
        hotkey:SetWordWrap(false)

        -- Store for hooks
        hotkey._keAnchor = textPos.keybindAnchor
        hotkey._keXOffset = textPos.keybindXOffset
        hotkey._keYOffset = textPos.keybindYOffset
        hotkey._keFontPath = fontpath
        hotkey._keFontSize = fontSize
        hotkey._keFontOutline = self.db.FontOutline

        -- Hook SetVertexColor to preserve white unless range red
        if not hotkey._keColorHooked then
            hotkey._keColorHooked = true
            hotkey._keStyled = true
            local metaSetVertexColor = getmetatable(hotkey).__index.SetVertexColor
            hooksecurefunc(hotkey, "SetVertexColor", function(self, r, g, b, a)
                if not (r and r > 0.9 and g < 0.2 and b < 0.2) then
                    metaSetVertexColor(self, 1, 1, 1, 1)
                end
            end)
        end
        getmetatable(hotkey).__index.SetVertexColor(hotkey, 1, 1, 1, 1)

        -- Hook UpdateHotkeys for restyle on keybind change
        if button.UpdateHotkeys and not button._keHotkeyHooked then
            button._keHotkeyHooked = true
            hooksecurefunc(button, "UpdateHotkeys", function(self)
                local hk = self.HotKey
                if hk and hk._keStyled then
                    hk:ClearAllPoints()
                    hk:SetPoint(hk._keAnchor, self, hk._keAnchor,
                        hk._keXOffset, hk._keYOffset)
                    hk:SetWidth((self:GetWidth() - 2) or 0)
                    hk:SetFont(hk._keFontPath, hk._keFontSize, hk._keFontOutline)
                    hk:SetWordWrap(false)
                end
                RemapKeyText(self)
            end)
        end
        RemapKeyText(button)
    end

    -- Style macro name text
    if name then
        if self.db.HideMacroText then
            name:SetAlpha(0)
        else
            name:SetAlpha(1)
            local fontSize = math.max(6, fontSizes.macro)
            name:ClearAllPoints()
            name:SetPoint(textPos.macroAnchor, button, textPos.macroAnchor,
                textPos.macroXOffset, textPos.macroYOffset)
            name:SetFont(fontpath, fontSize, self.db.FontOutline)
            name:SetTextColor(1, 1, 1, 1)
            name:SetShadowColor(0, 0, 0, 0)
            name:SetJustifyH("CENTER")
        end
    end

    -- Style count/charge text
    if count then
        local fontSize = math.max(6, fontSizes.charge)
        count:ClearAllPoints()
        count:SetPoint(textPos.chargeAnchor, button, textPos.chargeAnchor,
            textPos.chargeXOffset, textPos.chargeYOffset)
        count:SetFont(fontpath, fontSize, self.db.FontOutline)
        count:SetTextColor(1, 1, 1, 1)
        count:SetShadowColor(0, 0, 0, 0)
        count:SetJustifyH("RIGHT")
    end
end

-- Button texture styling/hiding
function SK:StyleButtonTextures(button)
    if not button then return end

    HideElement(button, "Border")
    HideElement(button, "Flash")
    HideElement(button, "NewActionTexture")
    HideElement(button, "SpellHighlightTexture")
    HideElement(button, "SlotBackground")

    local normalTex = button:GetNormalTexture()
    if normalTex then normalTex:SetAlpha(0) end

    if button.CheckedTexture then
        button:GetCheckedTexture():SetColorTexture(0, 0, 0, 0)
    end

    if button.HighlightTexture then
        button.HighlightTexture:SetTexture("Interface\\Buttons\\WHITE8x8")
        button.HighlightTexture:SetTexCoord(0, 1, 0, 1)
        button.HighlightTexture:ClearAllPoints()
        button.HighlightTexture:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        button.HighlightTexture:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        button.HighlightTexture:SetBlendMode("ADD")
        button.HighlightTexture:SetVertexColor(1, 1, 1, 0.3)
    end

    local pushed = button:GetPushedTexture()
    if pushed then
        pushed:SetTexture("Interface\\Buttons\\WHITE8x8")
        pushed:SetTexCoord(0, 1, 0, 1)
        pushed:ClearAllPoints()
        pushed:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        pushed:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        pushed:SetBlendMode("ADD")
        pushed:SetVertexColor(1, 1, 1, 0.4)
    end
end

-- Check if a button has content
local function ButtonHasContent(barName, button)
    if barName == "PetBar" then
        local id = button:GetID()
        local name = GetPetActionInfo(id)
        return name ~= nil
    elseif barName == "StanceBar" then
        local id = button:GetID()
        local texture = GetShapeshiftFormInfo(id)
        return texture ~= nil
    else
        return button.action and HasAction(button.action)
    end
end

-- Create backdrop for individual button
function SK:CreateButtonBackdrop(button, barName, index, buttonSize)
    if not button then return end
    buttonSize = buttonSize or 40

    local barConfig = self:GetBarConfig(barName)
    local backdropColor = barConfig and barConfig.BackdropColor or { 0, 0, 0, 0.8 }
    local borderColor = barConfig and barConfig.BorderColor or { 0, 0, 0, 1 }

    local backdrop = CreateFrame("Frame", "KE_" .. barName .. "Backdrop" .. index, UIParent, "BackdropTemplate")
    backdrop:SetSize(buttonSize, buttonSize)
    backdrop:SetFrameStrata("BACKGROUND")
    backdrop:SetFrameLevel(1)

    backdrop:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        tile = false,
        tileSize = 0,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    backdrop:SetBackdropColor(backdropColor[1], backdropColor[2], backdropColor[3], backdropColor[4] or 0.8)

    local borderFrame = CreateFrame("Frame", nil, backdrop)
    borderFrame:SetAllPoints(backdrop)
    borderFrame:SetFrameLevel(backdrop:GetFrameLevel() + 1)
    backdrop._borderFrame = borderFrame

    AddBorders(backdrop, borderColor, borderFrame)
    backdrop._barName = barName

    -- Re-parent button to backdrop
    button:SetParent(backdrop)
    button:ClearAllPoints()
    button:SetSize(buttonSize, buttonSize)
    button:SetPoint("CENTER", backdrop, "CENTER", 0, 0)

    -- Empty backdrop visibility
    local function UpdateBackdropVisibility()
        if SK.isDraggingSpell then
            backdrop:SetAlpha(1)
            return
        end

        local currentConfig = self:GetBarConfig(barName)
        local shouldHideEmpty = currentConfig and currentConfig.HideEmptyBackdrops == true

        if shouldHideEmpty then
            if ButtonHasContent(barName, button) then
                backdrop:SetAlpha(1)
            else
                backdrop:SetAlpha(0)
            end
        else
            backdrop:SetAlpha(1)
        end
    end

    if button.Update then
        hooksecurefunc(button, "Update", UpdateBackdropVisibility)
    end
    if button.UpdateAction then
        hooksecurefunc(button, "UpdateAction", UpdateBackdropVisibility)
    end

    backdrop:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    backdrop:RegisterEvent("ACTIONBAR_UPDATE_STATE")
    backdrop:SetScript("OnEvent", function(self, event, slot)
        if event == "ACTIONBAR_SLOT_CHANGED" then
            if slot == button.action then
                UpdateBackdropVisibility()
            end
        else
            UpdateBackdropVisibility()
        end
    end)

    UpdateBackdropVisibility()
    backdrop._updateVisibility = UpdateBackdropVisibility

    -- Hide profession texture
    if self.db.HideProfTexture then
        C_Timer.After(0.5, function()
            if button["ProfessionQualityOverlayFrame"] then button["ProfessionQualityOverlayFrame"]:SetAlpha(0) end
        end)
    end

    -- Blizzard elements hide/skin
    if button.SlotArt then button.SlotArt:Hide() end
    if button.IconMask then button.IconMask:Hide() end
    if button.InterruptDisplay then button.InterruptDisplay:SetAlpha(0) end
    if button.SpellCastAnimFrame then button.SpellCastAnimFrame:SetAlpha(0) end
    if button.icon then button.icon:SetAllPoints(button) end
    if button.cooldown then button.cooldown:SetAllPoints(button) end
    if button.SpellHighlightTexture then button.SpellHighlightTexture:SetAllPoints(button) end
    if button.AutoCastable then button.AutoCastable:SetDrawLayer("OVERLAY", 7) end

    if button.AutoCastOverlay then
        button.AutoCastOverlay:ClearAllPoints()
        button.AutoCastOverlay:SetPoint("TOPLEFT", button, "TOPLEFT", -2, 2)
        button.AutoCastOverlay:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2)
        if button.AutoCastOverlay.Shine then
            button.AutoCastOverlay.Shine:ClearAllPoints()
            button.AutoCastOverlay.Shine:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
            button.AutoCastOverlay.Shine:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
        end
    end

    ApplyZoom(button.icon, 0.3)

    -- Range overlay
    local rangeOverlay = button:CreateTexture(nil, "OVERLAY", nil, 1)
    rangeOverlay:SetAllPoints(button)
    rangeOverlay:SetColorTexture(1, 0, 0, 0.2)
    rangeOverlay:Hide()
    button._keRangeOverlay = rangeOverlay

    button.ke_backdrop = backdrop
    return backdrop
end

-- Calculate button position based on layout (pixel-snapped to avoid sub-pixel gaps)
local function CalculateButtonPosition(index, layout, columns, rows, growLeft, buttonSize, spacing)
    local col, row
    if layout == "HORIZONTAL" then
        col = index % columns
        row = math.floor(index / columns)
    else
        row = index % rows
        col = math.floor(index / rows)
    end
    local rawCol = growLeft and (columns - 1 - col) or col
    local dx = math.floor(rawCol * (buttonSize + spacing) + 0.5)
    local dy = -math.floor(row * (buttonSize + spacing) + 0.5)
    return dx, dy
end

-- Layout function
local function SkinBar(cfg)
    if not cfg or not cfg.frame then return end
    local buttonsPerLine = math.max(1, math.min(cfg.buttonsPerLine, cfg.totalButtons))
    local growLeft = cfg.growthDirection == "LEFT"

    local columns, rows
    if cfg.layout == "HORIZONTAL" then
        columns = buttonsPerLine
        rows = math.ceil(cfg.totalButtons / columns)
    else
        rows = buttonsPerLine
        columns = math.ceil(cfg.totalButtons / rows)
    end

    local container = CreateFrame("Frame", "KE_" .. cfg.name .. "_Container", UIParent)
    container:SetSize(columns * cfg.buttonSize + (columns - 1) * cfg.spacing,
        rows * cfg.buttonSize + (rows - 1) * cfg.spacing)
    container:SetPoint(cfg.anchorFrom, cfg.relativeTo, cfg.anchorTO, cfg.x, cfg.y)
    container:SetFrameStrata("LOW")

    local mouseoverEnabled = cfg.mouseover and cfg.mouseover.enabled
    container:SetAlpha(mouseoverEnabled and (cfg.mouseover.alpha or 0) or 1)
    container._fadeAlpha = cfg.mouseover and cfg.mouseover.alpha or 0
    container._fadeInDur = cfg.mouseover and cfg.mouseover.fadeInDuration or 0.3
    container._fadeOutDur = cfg.mouseover and cfg.mouseover.fadeOutDuration or 1
    container._mouseoverEnabled = mouseoverEnabled
    container._isMouseOver = false
    cfg.ke_container = container

    for i = 1, cfg.totalButtons do
        local button = _G[cfg.buttonPrefix .. i]
        if button then
            SK:StyleButtonTextures(button)
            SK:StyleButtonText(button, cfg.name)

            local backdrop = SK:CreateButtonBackdrop(button, cfg.name, i, cfg.buttonSize)
            if backdrop then
                backdrop:SetParent(container)
                local dx, dy = CalculateButtonPosition(i - 1, cfg.layout, columns, rows, growLeft, cfg.buttonSize,
                    cfg.spacing)
                backdrop:ClearAllPoints()
                backdrop:SetPoint("TOPLEFT", container, "TOPLEFT", dx, dy)
            end
        end
    end
end


-- Mouseover polling
local function SetupMouseoverScript(container)
    if not container then return end
    if container._mouseoverScriptSetup then return end
    container._mouseoverScriptSetup = true

    local function IsMouseOverContainer()
        local left, bottom, width, height = container:GetRect()
        if not left then return false end
        local scale = container:GetEffectiveScale()
        local x, y = GetCursorPosition()
        x, y = x / scale, y / scale
        return x >= left and x <= (left + width) and y >= bottom and y <= (bottom + height)
    end

    local function FadeIn()
        if container._isMouseOver then return end
        if not container._mouseoverEnabled then return end
        container._isMouseOver = true
        local dur = container._fadeInDur or 0.3
        if InCombatLockdown() then dur = 0.1 end
        KE:CombatSafeFade(container, 1, dur)
    end

    local function FadeOut()
        if not container._isMouseOver then return end
        container._isMouseOver = false
        if container._bonusBarActive then return end
        if not container._mouseoverEnabled then
            container:SetAlpha(1)
            return
        end
        local alpha = container._fadeAlpha or 0
        local dur = container._fadeOutDur or 0.5
        KE:CombatSafeFade(container, alpha, dur)
    end

    local pollInterval = 0.1
    local elapsed = 0

    container:SetScript("OnUpdate", function(self, delta)
        elapsed = elapsed + delta
        if elapsed < pollInterval then return end
        elapsed = 0
        local isOver = IsMouseOverContainer()
        if isOver and not self._isMouseOver then
            FadeIn()
        elseif not isOver and self._isMouseOver then
            FadeOut()
        end
    end)
end

-- Setup vehicle/bonusbar override for Bar1
local function SetupBonusBarOverride(bar1Container, db)
    if not bar1Container then return end

    local stateFrame = CreateFrame("Frame", "KE_BonusBarStateFrame", UIParent, "SecureHandlerStateTemplate")
    stateFrame:SetSize(1, 1)
    stateFrame:Hide()

    stateFrame.container = bar1Container
    stateFrame.fadeAlpha = bar1Container._fadeAlpha or 0

    stateFrame:SetAttribute("_onstate-bonusbar", [[
        self:CallMethod("OnBonusBarChange", newstate)
    ]])

    function stateFrame:OnBonusBarChange(state)
        local container = self.container
        if not container then return end
        if not container._bonusBarOverrideEnabled then
            container._bonusBarActive = false
            return
        end
        if state == "vehicle" then
            container._bonusBarActive = true
            KE:CombatSafeFade(container, 1, 0.3)
        else
            container._bonusBarActive = false
            if not container._isMouseOver then
                if container._mouseoverEnabled then
                    container:SetAlpha(container._fadeAlpha or 0)
                else
                    container:SetAlpha(1)
                end
            end
        end
    end

    RegisterStateDriver(stateFrame, "bonusbar", "[bonusbar:5][vehicleui][overridebar][possessbar] vehicle; normal")

    bar1Container._bonusBarOverrideEnabled = db.MouseoverOverride == true
    bar1Container._stateFrame = stateFrame
end

function SK:UpdateBonusBarOverride()
    local bar1Container = _G["KE_Bar1_Container"]
    if not bar1Container then return end
    local enabled = self.db.MouseoverOverride == true
    bar1Container._bonusBarOverrideEnabled = enabled

    if not enabled then
        bar1Container._bonusBarActive = false
        if not bar1Container._isMouseOver then
            if bar1Container._mouseoverEnabled then
                bar1Container:SetAlpha(bar1Container._fadeAlpha or 0)
            else
                bar1Container:SetAlpha(1)
            end
        end
    else
        if bar1Container._stateFrame and bar1Container._stateFrame.OnBonusBarChange then
            local currentState = SecureCmdOptionParse("[bonusbar:5][vehicleui][overridebar][possessbar] vehicle; normal")
            bar1Container._stateFrame:OnBonusBarChange(currentState)
        end
    end
end

-- Generic visibility handler for Pet and Stance bars
local function SetupSpecialBarVisibility(container, blizzFrame, events, visibilityCheckFn, barKey)
    if not container then return end

    if blizzFrame then
        blizzFrame:SetParent(UIParent)
        blizzFrame:ClearAllPoints()
        blizzFrame:SetPoint("TOP", UIParent, "BOTTOM", 0, -500)
        blizzFrame:EnableMouse(false)
    end

    local pendingUpdate = false
    local function UpdateVisibility()
        if InCombatLockdown() then
            pendingUpdate = true
            return
        end
        pendingUpdate = false
        local barDB = SK.db and SK.db.Bars and SK.db.Bars[barKey]
        local isEnabled = barDB and barDB.Enabled ~= false
        if isEnabled and visibilityCheckFn() then
            container:Show()
        else
            container:Hide()
        end
    end

    local eventFrame = CreateFrame("Frame")
    for _, event in ipairs(events) do
        eventFrame:RegisterEvent(event)
    end
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            if pendingUpdate then UpdateVisibility() end
        else
            UpdateVisibility()
        end
    end)

    if not InCombatLockdown() then
        UpdateVisibility()
    else
        pendingUpdate = true
    end

    container._visibilityFrame = eventFrame
end

local function SetupPetBarVisibility(container)
    SetupSpecialBarVisibility(
        container, PetActionBar,
        { "PET_BAR_UPDATE", "UNIT_PET", "PLAYER_CONTROL_GAINED", "PLAYER_CONTROL_LOST", "PLAYER_FARSIGHT_FOCUS_CHANGED" },
        PetHasActionBar, "PetBar"
    )
end

local function SetupStanceBarVisibility(container)
    SetupSpecialBarVisibility(
        container, StanceBar,
        { "UPDATE_SHAPESHIFT_FORMS", "UPDATE_SHAPESHIFT_FORM", "PLAYER_ENTERING_WORLD" },
        function() return GetNumShapeshiftForms() > 0 end, "StanceBar"
    )
end

-- Register bar with KE edit mode
local function RegisterBarWithEditMode(barName, barDB, barContainer, relativeTo)
    if not KE.EditMode then return end
    local db = barDB
    local frame = barContainer
    local rel = relativeTo or UIParent

    KE.EditMode:RegisterElement({
        key = "ActionBars_" .. barName,
        displayName = barName,
        frame = frame,
        getPosition = function()
            return {
                AnchorFrom = (db.Position and db.Position.AnchorFrom) or "CENTER",
                AnchorTo = (db.Position and db.Position.AnchorTo) or "CENTER",
                XOffset = (db.Position and db.Position.XOffset) or 0,
                YOffset = (db.Position and db.Position.YOffset) or 0,
            }
        end,
        setPosition = function(pos)
            if not db.Position then db.Position = {} end
            db.Position.AnchorFrom = pos.AnchorFrom
            db.Position.AnchorTo = pos.AnchorTo
            db.Position.XOffset = pos.XOffset
            db.Position.YOffset = pos.YOffset
            frame:ClearAllPoints()
            frame:SetPoint(pos.AnchorFrom, rel, pos.AnchorTo, pos.XOffset, pos.YOffset)
        end,
        getParentFrame = function()
            local parentName = db.ParentFrame
            if parentName and _G[parentName] then return _G[parentName] end
            return rel
        end,
        guiPath = "SkinActionBars",
        guiContext = barName,
    })
end

-- Module OnEnable
function SK:OnEnable()
    if KE:ShouldNotLoadModule() then return end
    if not self.db.Enabled then return end
    self:BuildConfigTable()

    C_Timer.After(0.5, function()
        self:HideBlizzardBars()

        for _, cfg in ipairs(configTable) do
            SkinBar(cfg)
            SetupMouseoverScript(cfg.ke_container)
            RegisterBarWithEditMode(cfg.name, cfg.dbReference, cfg.ke_container, cfg.relativeTo)

            if cfg.name == "Bar1" and cfg.ke_container then
                SetupBonusBarOverride(cfg.ke_container, self.db)
                self:UpdateBonusBarOverride()
            end

            if cfg.name == "PetBar" and cfg.ke_container then
                SetupPetBarVisibility(cfg.ke_container)
            elseif cfg.name == "StanceBar" and cfg.ke_container then
                SetupStanceBarVisibility(cfg.ke_container)
            end

            if not cfg.enabled and cfg.ke_container then
                cfg.ke_container:Hide()
            end
        end

        for i = 2, 8 do
            Settings.SetValue("PROXY_SHOW_ACTIONBAR_" .. i, false)
        end
        C_CVar.SetCVar("countdownForCooldowns", 1)
        SettingsPanel:CommitSettings(true)

        C_Timer.After(1, function() SK:UpdateButtonTexts() end)
        C_Timer.After(2, function() SK:UpdateButtonTexts() end)

        self:SetupDragDetection()
        self:SetupRangeIndicatorHook()
    end)
end

-- Range indicator hook
function SK:SetupRangeIndicatorHook()
    if self._rangeHookSetup then return end
    self._rangeHookSetup = true

    hooksecurefunc("ActionButton_UpdateRangeIndicator", function(self, checksRange, inRange)
        local hotkey = self.HotKey
        if not hotkey or not hotkey._keStyled then return end

        if self._keRangeOverlay then
            if checksRange and not inRange then
                self._keRangeOverlay:Show()
            else
                self._keRangeOverlay:Hide()
            end
        end
    end)
end

-- Iterate all backdrops
local function ForEachBackdrop(callback)
    local bars = { "Bar1", "Bar2", "Bar3", "Bar4", "Bar5", "Bar6", "Bar7", "Bar8", "PetBar", "StanceBar" }
    for _, barKey in ipairs(bars) do
        local i = 1
        while true do
            local backdrop = _G["KE_" .. barKey .. "Backdrop" .. i]
            if not backdrop then break end
            callback(backdrop)
            i = i + 1
        end
    end
end

function SK:ShowAllBackdropsTemporary()
    ForEachBackdrop(function(backdrop) backdrop:SetAlpha(1) end)
end

function SK:RestoreBackdropVisibility()
    ForEachBackdrop(function(backdrop)
        if backdrop._updateVisibility then
            backdrop._updateVisibility()
        else
            backdrop:SetAlpha(1)
        end
    end)
end

function SK:SetupDragDetection()
    if self.dragFrame then return end

    local dragFrame = CreateFrame("Frame")
    dragFrame:RegisterEvent("ACTIONBAR_SHOWGRID")
    dragFrame:RegisterEvent("ACTIONBAR_HIDEGRID")
    dragFrame:SetScript("OnEvent", function(_, event)
        if event == "ACTIONBAR_SHOWGRID" then
            SK.isDraggingSpell = true
            SK:ShowAllBackdropsTemporary()
        elseif event == "ACTIONBAR_HIDEGRID" then
            SK.isDraggingSpell = false
            SK:RestoreBackdropVisibility()
        end
    end)

    self.dragFrame = dragFrame
end

-- Update functions for GUI

function SK:UpdateButtonTexts()
    for _, cfg in ipairs(configTable) do
        if cfg.enabled then
            for i = 1, cfg.totalButtons do
                local button = _G[cfg.buttonPrefix .. i]
                if button then
                    self:StyleButtonText(button, cfg.name)
                end
            end
        end
    end
end

function SK:UpdateProfessionTextures()
    local hideProf = self.db.HideProfTexture
    for _, cfg in ipairs(configTable) do
        if cfg.enabled then
            for i = 1, cfg.totalButtons do
                local button = _G[cfg.buttonPrefix .. i]
                if button and button.ProfessionQualityOverlayFrame then
                    button.ProfessionQualityOverlayFrame:SetAlpha(hideProf and 0 or 1)
                end
            end
        end
    end
end

local function GetBarData(barKey)
    local barDB = SK.db and SK.db.Bars and SK.db.Bars[barKey]
    local container = _G["KE_" .. barKey .. "_Container"]
    if not barDB or not container then return nil, nil end
    return barDB, container
end

function SK:UpdateBarPosition(barKey)
    local barDB, container = GetBarData(barKey)
    if not barDB or not container then return end
    local anchor = barDB.Position and barDB.Position.AnchorFrom or "BOTTOM"
    local relTo = _G[barDB.ParentFrame] or UIParent
    local relPt = barDB.Position and barDB.Position.AnchorTo or "BOTTOM"
    local x = barDB.Position and barDB.Position.XOffset or 0
    local y = barDB.Position and barDB.Position.YOffset or 0
    container:ClearAllPoints()
    container:SetPoint(anchor, relTo, relPt, x, y)
end

function SK:UpdateAllPositions()
    for barKey, _ in pairs(BAR_FRAME_MAP) do
        self:UpdateBarPosition(barKey)
    end
end

function SK:UpdateBarMouseover(barKey)
    local barDB, container = GetBarData(barKey)
    if not barDB or not container then return end

    local globalMouseover = self.db.Mouseover or {}
    local useGlobal = barDB.Mouseover and barDB.Mouseover.GlobalOverride == true

    local mouseoverEnabled, mouseoverAlpha, fadeInDur, fadeOutDur
    if useGlobal then
        mouseoverEnabled = globalMouseover.Enabled == true
        mouseoverAlpha = globalMouseover.Alpha or 0
        fadeInDur = globalMouseover.FadeInDuration or 0.3
        fadeOutDur = globalMouseover.FadeOutDuration or 1
    else
        mouseoverEnabled = barDB.Mouseover and barDB.Mouseover.Enabled == true
        mouseoverAlpha = (barDB.Mouseover and barDB.Mouseover.Alpha) or 0
        fadeInDur = globalMouseover.FadeInDuration or 0.3
        fadeOutDur = globalMouseover.FadeOutDuration or 1
    end

    container._fadeAlpha = mouseoverAlpha
    container._fadeInDur = fadeInDur
    container._fadeOutDur = fadeOutDur
    container._mouseoverEnabled = mouseoverEnabled

    if not container._isMouseOver and not container._bonusBarActive then
        if mouseoverEnabled then
            container:SetAlpha(mouseoverAlpha)
        else
            container:SetAlpha(1)
        end
    end
end

function SK:UpdateAllMouseover()
    for barKey, _ in pairs(BAR_FRAME_MAP) do
        self:UpdateBarMouseover(barKey)
    end
end

function SK:UpdateBarLayout(barKey)
    local barDB, container = GetBarData(barKey)
    if not barDB or not container then return end

    local buttonSize = barDB.ButtonSize or 40
    local spacing = barDB.Spacing or 1
    local totalButtons = barDB.TotalButtons or 12
    local layout = barDB.Layout or "HORIZONTAL"
    local growthDirection = barDB.GrowthDirection or "RIGHT"
    local growLeft = growthDirection == "LEFT"
    local buttonsPerLine = math.max(1, math.min(barDB.ButtonsPerLine or 12, totalButtons))
    local frameInfo = BAR_FRAME_MAP[barKey]

    local columns, rows
    if layout == "HORIZONTAL" then
        columns = buttonsPerLine
        rows = math.ceil(totalButtons / columns)
    else
        rows = buttonsPerLine
        columns = math.ceil(totalButtons / rows)
    end
    container:SetSize(
        columns * buttonSize + (columns - 1) * spacing,
        rows * buttonSize + (rows - 1) * spacing
    )

    for i = 1, totalButtons do
        local button = _G[frameInfo.prefix .. i]
        if button then
            local backdrop = button.ke_backdrop

            if not backdrop then
                self:StyleButtonTextures(button)
                self:StyleButtonText(button, barKey)
                backdrop = self:CreateButtonBackdrop(button, barKey, i, buttonSize)
                if backdrop then
                    backdrop:SetParent(container)
                end
            end

            if backdrop then
                backdrop:Show()
                button:SetSize(buttonSize, buttonSize)
                backdrop:SetSize(buttonSize, buttonSize)

                local dx, dy = CalculateButtonPosition(i - 1, layout, columns, rows, growLeft, buttonSize, spacing)
                backdrop:ClearAllPoints()
                backdrop:SetPoint("TOPLEFT", container, "TOPLEFT", dx, dy)

                if button.icon then button.icon:SetAllPoints(button) end
                if button.cooldown then button.cooldown:SetAllPoints(button) end
                if button.SpellHighlightTexture then button.SpellHighlightTexture:SetAllPoints(button) end

                self:StyleButtonText(button, barKey)
            end
        end
    end

    -- Hide backdrops beyond totalButtons
    for i = totalButtons + 1, 12 do
        local button = _G[frameInfo.prefix .. i]
        if button and button.ke_backdrop then
            button.ke_backdrop:Hide()
        end
    end
end

function SK:UpdateAllLayouts()
    for barKey, _ in pairs(BAR_FRAME_MAP) do
        self:UpdateBarLayout(barKey)
    end
end

function SK:UpdateBarEnabled(barKey)
    local barDB, container = GetBarData(barKey)
    if not barDB or not container then return end
    if barDB.Enabled then
        container:Show()
    else
        container:Hide()
    end
end

-- Main update function called from GUI
function SK:UpdateSettings(updateType, barKey)
    if not self:IsEnabled() then return end
    updateType = updateType or "all"

    if updateType == "all" then
        self:UpdateButtonTexts()
        self:UpdateAllPositions()
        self:UpdateAllMouseover()
        self:UpdateAllLayouts()
        self:UpdateProfessionTextures()
    elseif updateType == "fonts" then
        self:UpdateButtonTexts()
    elseif updateType == "positions" then
        if barKey then self:UpdateBarPosition(barKey) else self:UpdateAllPositions() end
    elseif updateType == "mouseover" then
        if barKey then self:UpdateBarMouseover(barKey) else self:UpdateAllMouseover() end
    elseif updateType == "layout" then
        if barKey then self:UpdateBarLayout(barKey) else self:UpdateAllLayouts() end
    elseif updateType == "enabled" and barKey then
        self:UpdateBarEnabled(barKey)
    elseif updateType == "profTextures" then
        self:UpdateProfessionTextures()
    elseif updateType == "backdrops" then
        if barKey then self:UpdateBarBackdropColors(barKey) else self:UpdateAllBackdropColors() end
    end
end

-- Hide Blizzard bar frames
function SK:HideBlizzardBars()
    if PetActionBar then
        PetActionBar:SetParent(UIParent)
        PetActionBar:ClearAllPoints()
        PetActionBar:SetPoint("TOP", UIParent, "BOTTOM", 0, -500)
        PetActionBar:EnableMouse(false)
    end
    if StanceBar then
        StanceBar:SetParent(UIParent)
        StanceBar:ClearAllPoints()
        StanceBar:SetPoint("TOP", UIParent, "BOTTOM", 0, -500)
        StanceBar:EnableMouse(false)
    end

    local blizzBars = { "MultiBar5", "MultiBar6", "MultiBar7" }
    for _, barName in ipairs(blizzBars) do
        local frame = _G[barName]
        if frame then
            frame:SetParent(UIParent)
            frame:ClearAllPoints()
            frame:SetPoint("TOP", UIParent, "BOTTOM", 0, -500)
            frame:EnableMouse(false)
        end
    end
end

-- Apply all settings
function SK:ApplySettings()
    if KE:ShouldNotLoadModule() then return end
    C_Timer.After(0.1, function()
        if InCombatLockdown() then return end
        self:HideBlizzardBars()

        for i = 2, 8 do
            Settings.SetValue("PROXY_SHOW_ACTIONBAR_" .. i, false)
        end

        self:BuildConfigTable()

        for barKey, _ in pairs(BAR_FRAME_MAP) do
            local barDB = self.db.Bars and self.db.Bars[barKey]
            local container = _G["KE_" .. barKey .. "_Container"]

            if container then
                if barDB and barDB.Enabled then
                    container:Show()
                    if container._visibilityFrame then
                        container._visibilityFrame:GetScript("OnEvent")(container._visibilityFrame, "PLAYER_ENTERING_WORLD")
                    end
                else
                    container:Hide()
                end
            end
        end

        self:UpdateSettings("all")
        self:UpdateAllBackdropColors()
    end)
end

-- Update backdrop colors for a bar
function SK:UpdateBarBackdropColors(barKey)
    local barConfig = self:GetBarConfig(barKey)
    if not barConfig then return end

    local backdropColor = barConfig.BackdropColor or { 0, 0, 0, 0.8 }
    local borderColor = barConfig.BorderColor or { 0, 0, 0, 1 }
    local hideEmpty = barConfig.HideEmptyBackdrops == true

    local i = 1
    while true do
        local backdrop = _G["KE_" .. barKey .. "Backdrop" .. i]
        if not backdrop then break end

        backdrop:SetBackdropColor(backdropColor[1], backdropColor[2], backdropColor[3], backdropColor[4] or 0.8)
        backdrop:SetBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)

        if backdrop._updateVisibility and hideEmpty then
            backdrop._updateVisibility()
        elseif not hideEmpty then
            backdrop:SetAlpha(1)
        end

        i = i + 1
    end
end

function SK:UpdateAllBackdropColors()
    local bars = { "Bar1", "Bar2", "Bar3", "Bar4", "Bar5", "Bar6", "Bar7", "Bar8", "PetBar", "StanceBar" }
    for _, barKey in ipairs(bars) do
        self:UpdateBarBackdropColors(barKey)
    end
end

function SK:OnDisable()
    self:UnregisterAllEvents()
    self:UnhookAll()
end

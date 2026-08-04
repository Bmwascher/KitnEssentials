-- ╔══════════════════════════════════════════════════════════╗
-- ║  ColorPicker.lua                                         ║
-- ║  Module: Color Picker                                    ║
-- ║  Purpose: Upgrade Blizzard's global color picker dialog  ║
-- ║           with R/G/B (0-255) and Alpha (0-100) entry     ║
-- ║           boxes, copy/paste, a class-color button, and   ║
-- ║           KE's own skin.                                 ║
-- ║                                                          ║
-- ║  ONE-WAY: the enhancement rewires a Blizzard global      ║
-- ║  frame and cannot be unwound at runtime. Turning this    ║
-- ║  module off only takes effect after a /reload.           ║
-- ║                                                          ║
-- ║  The small OnUpdate below exists only while the picker   ║
-- ║  is open: dragging the alpha slider fires no script we   ║
-- ║  can hook, so a child frame polls IsMouseOver() instead. ║
-- ║  It costs nothing while the picker is closed.            ║
-- ║                                                          ║
-- ║  Blizzard's own Okay button calls swatchFunc             ║
-- ║  unconditionally, and that field is only assigned by     ║
-- ║  SetupColorPickerAndShow -- frame.swatchFunc = noop      ║
-- ║  below patches any path that shows the frame without a   ║
-- ║  full setup, which would otherwise crash on Okay.        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class ColorPicker: AceModule
local CP = KitnEssentials:NewModule("ColorPicker")

-- Applies once and cannot be unwound at runtime (see the header), so a
-- profile switch that wants this module OFF must stay enabled and prompt
-- for /reload instead of disabling live.
CP.keReloadOnDisable = true

local _G = _G
local format, strlen, strjoin = format, strlen, strjoin
-- gsub is not in the project's luacheck read_globals allowlist; reach it
-- through _G rather than widen the allowlist for one convenience global.
local gsub = _G.gsub
local tonumber, floor, strsub = tonumber, floor, strsub
local CreateFrame = CreateFrame
local IsControlKeyDown = IsControlKeyDown
local IsModifierKeyDown = IsModifierKeyDown
local UnitClass = UnitClass
local C_Timer = C_Timer
local RAID_CLASS_COLORS = RAID_CLASS_COLORS

-- CALENDAR_COPY_EVENT/CALENDAR_PASTE_EVENT/CLASS are GlobalStrings, also not
-- in the allowlist; same _G routing as gsub above.
local CALENDAR_COPY_EVENT, CALENDAR_PASTE_EVENT = _G.CALENDAR_COPY_EVENT, _G.CALENDAR_PASTE_EVENT
local CLASS = _G.CLASS

-- Addons that already own this same dialog. ElvUI ships this exact
-- enhancement (its own Blizzard/ColorPicker.lua) -- both running would
-- rewire the same frame twice and double every added widget.
local CONFLICTS = { "ElvUI", "ColorPickerPlus", "ColorTools" }

local function ConflictLoaded()
    if not (_G.C_AddOns and _G.C_AddOns.IsAddOnLoaded) then return false end
    for _, name in ipairs(CONFLICTS) do
        local loadedOrLoading = _G.C_AddOns.IsAddOnLoaded(name)
        if loadedOrLoading then return true end
    end
    return false
end

local noop = function() end
local function Round255(x) return floor(x * 255 + 0.5) end

local colorBuffer = {}

local function Picker() return _G.ColorPickerFrame end

local function AlphaValue(num)
    return num and floor((num * 100) + .05) or 0
end

local function UpdateAlphaText(alpha)
    if not alpha then
        alpha = AlphaValue(Picker():GetColorAlpha())
    end
    CP.boxA:SetText(alpha)
end

local function ExpandFromThree(r, g, b)
    return strjoin("", r, r, g, g, b, b)
end

local function ExtendToSix(str)
    for _ = 1, 6 - strlen(str) do str = str .. 0 end
    return str
end

local function GetHexColor(box)
    local rgb, rgbSize = box:GetText(), box:GetNumLetters()
    if rgbSize == 3 then
        rgb = gsub(rgb, "(%x)(%x)(%x)$", ExpandFromThree)
    elseif rgbSize < 6 then
        rgb = gsub(rgb, "(.+)$", ExtendToSix)
    end

    local r = tonumber(strsub(rgb, 0, 2), 16) or 0
    local g = tonumber(strsub(rgb, 3, 4), 16) or 0
    local b = tonumber(strsub(rgb, 5, 6), 16) or 0

    return r / 255, g / 255, b / 255
end

--- Passing nil for r, g and b means "read the current colour from the frame"
---@param r number?
---@param g number?
---@param b number?
---@param box table?
local function UpdateColorTexts(r, g, b, box)
    local frame = Picker()
    if not (r and g and b) then
        r, g, b = frame:GetColorRGB()

        if box then
            if box == frame.Content.HexBox then
                r, g, b = GetHexColor(box)
            else
                local num = box:GetNumber()
                if num > 255 then num = 255 end

                local c = num / 255
                if box == CP.boxR then
                    r = c
                elseif box == CP.boxG then
                    g = c
                elseif box == CP.boxB then
                    b = c
                end
            end
        end
    end

    r, g, b = Round255(r), Round255(g), Round255(b)

    frame.Content.HexBox:SetText(format("%.2x%.2x%.2x", r, g, b))
    CP.boxR:SetText(r)
    CP.boxG:SetText(g)
    CP.boxB:SetText(b)
end

local function UpdateColor()
    local frame = Picker()
    local r, g, b = GetHexColor(frame.Content.HexBox)
    frame.Content.ColorPicker:SetColorRGB(r, g, b)
    frame.Content.ColorSwatchCurrent:SetColorTexture(r, g, b)
end

-- Delayed callback flush: while dragging the wheel/slider, Blizzard-style
-- immediate swatchFunc/opacityFunc spam is throttled to one call per 0.15s --
-- some consumers rebuild whole option panels on every callback.
local delayWait, delayFunc = 0.15, nil
local function DelayCall()
    if delayFunc then
        delayFunc()
        delayFunc = nil
    end
end

local last = { r = 0, g = 0, b = 0, a = 0 }
local function OnAlphaValueChanged(_, value)
    local alpha = AlphaValue(value)
    if last.a ~= alpha then
        last.a = alpha
    else -- alpha matched so we don't need to update
        return
    end

    UpdateAlphaText(alpha)

    local frame = Picker()
    if not frame:IsVisible() then
        DelayCall()
    else
        local opacityFunc = frame.opacityFunc
        if delayFunc and (delayFunc ~= opacityFunc) then
            delayFunc = opacityFunc
        elseif not delayFunc then
            delayFunc = opacityFunc
            C_Timer.After(delayWait, DelayCall)
        end
    end
end

local function UpdateAlpha(tbox)
    local num = tbox:GetNumber()
    if num > 100 then
        tbox:SetText(100)
        num = 100
    end

    local value = num * 0.01
    Picker().Content.ColorPicker:SetColorAlpha(value)
    OnAlphaValueChanged(nil, value)
end

local function OnColorSelect(frame, r, g, b)
    if r ~= last.r or g ~= last.g or b ~= last.b then
        last.r, last.g, last.b = r, g, b
    else -- colors match, most likely mouse is held down
        return
    end

    local picker = Picker()
    picker.Content.ColorSwatchCurrent:SetColorTexture(r, g, b)
    -- REQUIRED DEVIATION: Blizzard's own OnColorSelect calls
    -- self.swatch:SetColorRGB(r, g, b) when a caller's setup table passed a
    -- swatch (ColorPickerFrame.lua). This handler replaces that
    -- script outright, so without this line any caller relying on `swatch`
    -- for live updates silently stops getting them.
    if picker.swatch then picker.swatch:SetColorRGB(r, g, b) end
    UpdateColorTexts(r, g, b)
    UpdateAlphaText()

    if not frame:IsVisible() then
        DelayCall()
    elseif not delayFunc then
        delayFunc = picker.swatchFunc

        if delayFunc then
            C_Timer.After(delayWait, DelayCall)
        end
    end
end

function CP:UpdateDB()
    self.db = KE.db and KE.db.profile and KE.db.profile.ColorPicker
end

function CP:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function CP:OnEnable()
    self:UpdateDB()
    self:Enhance()
end

-- The enhancement rewires a Blizzard global frame and cannot be unwound at
-- runtime; disabling takes effect after a /reload (the GUI says so).
function CP:OnDisable() end

function CP:ApplySettings()
    self:UpdateDB()
    -- One-way: Enhance is guarded by self.applied and there is no teardown, so
    -- there is nothing to undo here. The GUI prompts for a reload on the OFF
    -- transition instead.
    if self.db and self.db.Enabled then self:Enhance() end
end

function CP:Enhance()
    if self.applied then return end
    if ConflictLoaded() then return end
    self.applied = true

    -- KE.Skins is read here, not captured at file scope: this file loads
    -- from Modules/QoL/, which loads BEFORE Modules/Skinning/
    -- (KitnEssentials.toc), so a file-scope capture would be nil.
    local S = KE.Skins
    local frame = Picker()
    local Content, Footer = frame.Content, frame.Footer

    -- Frame plate: hide the DialogBorderTemplate child and lay our backdrop.
    frame.Border:Hide()
    S.StripTextures(frame)
    S.Backdrop(frame)

    -- Blizzard's OkayButton OnClick calls swatchFunc unconditionally; it's
    -- only assigned by SetupColorPickerAndShow, so pre-fill with a noop for
    -- any path that shows the frame without a full setup.
    frame.swatchFunc = noop

    local Header = frame.Header or _G.ColorPickerFrameHeader
    S.StripTextures(Header)
    Header:ClearAllPoints()
    Header:SetPoint("TOP", frame, 0, 5)
    local headerText = Header.Text or _G.ColorPickerFrameHeaderText
    if headerText then S.SetFont(headerText, 12, "") end

    Footer.CancelButton:ClearAllPoints()
    Footer.OkayButton:ClearAllPoints()
    Footer.CancelButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)
    Footer.CancelButton:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 0, 6)
    Footer.OkayButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 6, 6)
    Footer.OkayButton:SetPoint("RIGHT", Footer.CancelButton, "LEFT", -4, 0)
    S.Button(Footer.OkayButton)
    S.Button(Footer.CancelButton)
    S.EditBox(Content.HexBox)

    S.SetFont(Content.HexBox.Hash, 12, "")
    local HexText = Content.HexBox:GetRegions()
    if HexText and HexText.SetFont then S.SetFont(HexText, 12, "") end

    -- Take over live updates (swatch + text sync + throttled callbacks).
    Content.ColorPicker:SetScript("OnColorSelect", OnColorSelect)

    frame:HookScript("OnShow", function(f)
        -- remember the color that will be replaced
        local r, g, b = f:GetColorRGB()
        f.Content.ColorSwatchOriginal:SetColorTexture(r, g, b)

        -- show/hide the alpha box
        if f.hasOpacity then
            CP.boxA:Show()
            CP.boxA.label:Show()
            f.Content.HexBox:SetScript("OnTabPressed", function() CP.boxA:SetFocus() end)
            UpdateAlphaText()
            f:SetWidth(405)
        else
            CP.boxA:Hide()
            CP.boxA.label:Hide()
            f.Content.HexBox:SetScript("OnTabPressed", function() CP.boxR:SetFocus() end)
            f:SetWidth(345)
        end

        -- sync the number boxes
        UpdateColorTexts(nil, nil, nil, f.Content.HexBox)
    end)

    -- Copied-color swatch
    local swatchWidth, swatchHeight = Content.ColorSwatchCurrent:GetSize()
    local copiedColor = frame:CreateTexture("KE_ColorPickerCopySwatch")
    copiedColor:SetColorTexture(0, 0, 0)
    copiedColor:SetSize(swatchWidth, swatchHeight)
    copiedColor:Hide()
    CP.copySwatch = copiedColor

    -- Copy / Paste / Class buttons
    local copyButton = CreateFrame("Button", "KE_ColorPickerCopy", frame)
    copyButton:SetText(CALENDAR_COPY_EVENT)
    copyButton:SetSize(60, 22)
    S.Button(copyButton)
    local copyFS = copyButton:GetFontString()
    if copyFS then S.SetFont(copyFS, 12, "") end

    local pasteButton = CreateFrame("Button", "KE_ColorPickerPaste", frame)
    pasteButton:SetText(CALENDAR_PASTE_EVENT)
    pasteButton:SetSize(60, 22)
    pasteButton:Disable() -- enabled once something has been copied
    S.Button(pasteButton)
    local pasteFS = pasteButton:GetFontString()
    if pasteFS then S.SetFont(pasteFS, 12, "") end

    local classButton = CreateFrame("Button", "KE_ColorPickerClass", frame)
    classButton:SetText(CLASS)
    classButton:SetSize(80, 22)
    S.Button(classButton)
    local classFS = classButton:GetFontString()
    if classFS then
        S.SetFont(classFS, 12, "")
        -- label inherits the player's class color -- doubles as a preview of
        -- what the button will apply. Static: class can't change mid-session.
        local _, classToken = UnitClass("player")
        local cc = classToken and RAID_CLASS_COLORS[classToken]
        if cc then classFS:SetTextColor(cc.r, cc.g, cc.b, 1) end
    end

    copyButton:SetScript("OnClick", function()
        colorBuffer.r, colorBuffer.g, colorBuffer.b = frame:GetColorRGB()

        pasteButton:Enable()
        copiedColor:SetColorTexture(colorBuffer.r, colorBuffer.g, colorBuffer.b)
        copiedColor:Show()

        colorBuffer.a = (frame.hasOpacity and frame:GetColorAlpha()) or nil
    end)

    pasteButton:SetScript("OnClick", function()
        Content.ColorPicker:SetColorRGB(colorBuffer.r, colorBuffer.g, colorBuffer.b)
        Content.ColorSwatchCurrent:SetColorTexture(colorBuffer.r, colorBuffer.g, colorBuffer.b)

        if frame.hasOpacity and colorBuffer.a then -- copied color had an alpha value
            Content.ColorPicker:SetColorAlpha(colorBuffer.a)
            OnAlphaValueChanged(nil, colorBuffer.a)
        end
    end)

    classButton:SetScript("OnClick", function()
        local _, classToken = UnitClass("player")
        local color = classToken and RAID_CLASS_COLORS[classToken]
        if not color then return end
        Content.ColorPicker:SetColorRGB(color.r, color.g, color.b)
        Content.ColorSwatchCurrent:SetColorTexture(color.r, color.g, color.b)
    end)

    -- Alpha slider drags fire no hookable script; poll only while the mouse
    -- is over the slider AND the picker is open (child frame's OnUpdate
    -- stops the moment the picker hides).
    local alphaUpdater = CreateFrame("Frame", "$parent_KE_AlphaUpdater", frame)
    alphaUpdater:SetScript("OnUpdate", function()
        if Content.ColorPicker.Alpha:IsMouseOver() then
            OnAlphaValueChanged(nil, frame:GetColorAlpha())
        end
    end)

    -- R / G / B (0-255) + A (0-100) entry boxes
    local boxes = {}
    for i, rgb in ipairs({ "R", "G", "B", "A" }) do
        local box = CreateFrame("EditBox", "KE_ColorPickerBox" .. rgb, frame)
        box:SetPoint("TOP", Content.ColorSwatchOriginal, "BOTTOM", 0, -105)
        box:SetFrameStrata("DIALOG")
        box:SetAutoFocus(false)
        box:SetTextInsets(0, 7, 0, 0)
        box:SetJustifyH("RIGHT")
        box:SetHeight(24)
        box:SetID(i)

        S.SetFont(box, 12, "")
        S.EditBox(box, true)

        box:SetMaxLetters(3)
        box:SetWidth(40)
        box:SetNumeric(true)

        local label = box:CreateFontString("KE_ColorPickerBoxLabel" .. rgb, "ARTWORK")
        S.SetFont(label, 12, "")
        label:SetPoint("RIGHT", box, "LEFT", -5, 0)
        label:SetText(rgb)
        label:SetTextColor(1, 1, 1)
        box.label = label

        if i == 4 then
            box:SetScript("OnKeyUp", function(eb, key)
                local copyPaste = IsControlKeyDown() and key == "V"
                if key == "BACKSPACE" or copyPaste or (strlen(key) == 1 and not IsModifierKeyDown()) then
                    UpdateAlpha(eb)
                elseif key == "ENTER" or key == "ESCAPE" then
                    eb:ClearFocus()
                    UpdateAlpha(eb)
                end
            end)
        else
            box:SetScript("OnKeyUp", function(eb, key)
                local copyPaste = IsControlKeyDown() and key == "V"
                if key == "BACKSPACE" or copyPaste or (strlen(key) == 1 and not IsModifierKeyDown()) then
                    UpdateColorTexts(nil, nil, nil, eb)
                    UpdateColor()
                elseif key == "ENTER" or key == "ESCAPE" then
                    eb:ClearFocus()
                    UpdateColorTexts(nil, nil, nil, eb)
                    UpdateColor()
                end
            end)
        end

        box:SetScript("OnEditFocusGained", function(eb) eb:SetCursorPosition(0) eb:HighlightText() end)
        box:SetScript("OnEditFocusLost", function(eb) eb:HighlightText(0, 0) end)
        box:Show()

        boxes[rgb] = box
    end
    CP.boxR, CP.boxG, CP.boxB, CP.boxA = boxes.R, boxes.G, boxes.B, boxes.A

    -- resync the alpha background
    Content.AlphaBackground:SetAllPoints(Content.ColorPicker.Alpha)

    -- move the color swatches
    Content.ColorSwatchCurrent:SetPoint("TOPLEFT", Content, "TOPRIGHT", -120, -37)
    Content.ColorSwatchOriginal:SetPoint("TOPLEFT", Content.ColorSwatchCurrent, "BOTTOMLEFT", 0, -2)

    -- copied-color swatch above Paste
    copiedColor:SetPoint("BOTTOM", pasteButton, "TOP", 0, 5)

    -- right-side buttons
    copyButton:SetPoint("TOPLEFT", Content.ColorSwatchOriginal, "BOTTOMLEFT", -6, -5)
    pasteButton:SetPoint("TOPLEFT", copyButton, "TOPRIGHT", 2, 0)
    classButton:SetPoint("TOP", copyButton, "BOTTOMRIGHT", 0, -7)

    Content.HexBox:ClearAllPoints()
    Content.HexBox:SetPoint("TOPRIGHT", classButton, "BOTTOMRIGHT", 0, -9)
    Content.HexBox:SetWidth(78)

    CP.boxA:SetPoint("RIGHT", Content.HexBox, "LEFT", -45, 0)
    CP.boxR:SetPoint("LEFT", Content, 25, 0)
    CP.boxG:SetPoint("LEFT", CP.boxR, 65, 0)
    CP.boxB:SetPoint("LEFT", CP.boxG, 65, 0)

    -- tab cursor order R -> G -> B -> Hex (-> A -> R when opacity shown)
    CP.boxR:SetScript("OnTabPressed", function() CP.boxG:SetFocus() end)
    CP.boxG:SetScript("OnTabPressed", function() CP.boxB:SetFocus() end)
    CP.boxB:SetScript("OnTabPressed", function() Content.HexBox:SetFocus() end)
    CP.boxA:SetScript("OnTabPressed", function() CP.boxR:SetFocus() end)

    -- Make the color picker movable (drag strip across the header). Blizzard's
    -- own DragBar already covers this same header hitbox and moves the same
    -- frame -- harmless duplication, kept as ported.
    local mover = CreateFrame("Frame", nil, frame)
    mover:SetPoint("TOPLEFT", frame, "TOP", -60, 0)
    mover:SetPoint("BOTTOMRIGHT", frame, "TOP", 60, -15)
    mover:SetScript("OnMouseDown", function() frame:StartMoving() end)
    mover:SetScript("OnMouseUp", function() frame:StopMovingOrSizing() end)
    mover:EnableMouse(true)

    -- taller frame to make room for the entry boxes
    frame:SetHeight(frame:GetHeight() + 40)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:SetUserPlaced(true)
    frame:EnableKeyboard(false)
end

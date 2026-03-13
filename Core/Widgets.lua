-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)

-- Common widget creation helpers used by modules
-- Full GUI widget library is in GUI/GUIWidgets/

local CreateFrame = CreateFrame
local UIFrameFadeIn = UIFrameFadeIn
local UIFrameFadeOut = UIFrameFadeOut
local C_Timer = C_Timer
local UIParent = UIParent
local type = type
local IsControlKeyDown = IsControlKeyDown
local IsMetaKeyDown = IsMetaKeyDown
local StaticPopup_Show = StaticPopup_Show
local ReloadUI = ReloadUI
local ACCEPT = ACCEPT
local CANCEL = CANCEL

--------------------------------------------------------------------------------
-- Message Popup (centered on-screen toast with fade out)
--------------------------------------------------------------------------------
local MESSAGE_POPUP_SIZE = 64

local function ValidateThemeColor(color, default)
    if not color or type(color) ~= "table" then return default end
    return color
end

function KE:CreateMessagePopup(timer, text, fontSize, parentFrame, xOffset, yOffset)
    if KE.msgContainer then
        KE.msgContainer:Hide()
    end

    local Theme = KE.Theme
    local parent = parentFrame or UIParent
    local x = xOffset or 0
    local y = yOffset or 250

    if not Theme then return end

    local msgContainer = CreateFrame("Frame", nil, parent)
    msgContainer:SetToplevel(true)
    msgContainer:SetFrameStrata("TOOLTIP")
    msgContainer:SetFrameLevel(150)
    msgContainer:SetSize(MESSAGE_POPUP_SIZE, MESSAGE_POPUP_SIZE)
    msgContainer:SetPoint("CENTER", parent, "CENTER", x, y)

    local msgText = msgContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    msgText:SetPoint("CENTER")
    msgText:SetText(text)
    msgText:SetFont(KE.FONT, fontSize, "")

    KE:ApplyFontToText(msgText, "Expressway", fontSize, "SOFTOUTLINE")

    local accent = ValidateThemeColor(Theme.accent, { 1, 0.82, 0, 1 })
    msgText:SetTextColor(accent[1], accent[2], accent[3], 1)
    msgText:SetShadowColor(0, 0, 0, 0)

    UIFrameFadeIn(msgText, 0.2, 0, 1)
    msgContainer:Show()

    C_Timer.After(timer, function()
        UIFrameFadeOut(msgText, 1.5, 1, 0)
        C_Timer.After(1.6, function()
            msgContainer:Hide()
        end)
    end)

    KE.msgContainer = msgContainer
    return msgContainer
end

--------------------------------------------------------------------------------
-- Prompt Dialog (themed confirmation / editbox popup)
--------------------------------------------------------------------------------
local POPUP_WIDTH = 360
local POPUP_HEIGHT = 120
local BUTTON_WIDTH = 100
local BUTTON_HEIGHT = 26

-- Create themed button for prompts
local function CreateThemedButton(parent, Theme, labelText, isPrimary)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    local textColor = isPrimary and Theme.accent or Theme.textPrimary
    local bgMedium = ValidateThemeColor(Theme.bgMedium, { 0.1, 0.1, 0.1, 1 })
    local bgLight = ValidateThemeColor(Theme.bgLight, { 0.15, 0.15, 0.15, 1 })
    local border = ValidateThemeColor(Theme.border, { 0.3, 0.3, 0.3, 1 })
    local accent = ValidateThemeColor(Theme.accent, { 1, 0.82, 0, 1 })

    btn:SetBackdropColor(bgMedium[1], bgMedium[2], bgMedium[3], 1)
    btn:SetBackdropBorderColor(border[1], border[2], border[3], 1)

    local label = btn:CreateFontString(nil, "OVERLAY")
    label:SetPoint("CENTER")
    if KE.ApplyThemeFont then
        KE:ApplyThemeFont(label, "normal")
    else
        label:SetFontObject("GameFontNormal")
    end
    label:SetText(labelText)
    label:SetTextColor(textColor[1], textColor[2], textColor[3], 1)
    label:SetShadowColor(0, 0, 0, 0)
    btn.label = label

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(bgLight[1], bgLight[2], bgLight[3], 1)
        self:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
    end)

    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(bgMedium[1], bgMedium[2], bgMedium[3], 1)
        self:SetBackdropBorderColor(border[1], border[2], border[3], 1)
    end)

    return btn
end

function KE:CreatePrompt(title, text, showEditBox, editBoxLabelText, useTexture, texturePath, textureSizeX,
                              textureSizeY, textureColor, onAccept, onCancel, acceptText, cancelText,
                              showSecondEditBox, secondEditBoxLabel)
    local Theme = KE.Theme
    if not Theme then
        StaticPopupDialogs["KE_PROMPT_DIALOG"] = {
            text = text or "",
            button1 = acceptText or ACCEPT,
            button2 = cancelText or CANCEL,
            OnAccept = onAccept,
            OnCancel = onCancel,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        return StaticPopup_Show("KE_PROMPT_DIALOG")
    end

    if KE.activePrompt then
        KE.activePrompt:Hide()
    end

    -- Validate theme colors
    local bgLight = ValidateThemeColor(Theme.bgLight, { 0.15, 0.15, 0.15, 1 })
    local bgMedium = ValidateThemeColor(Theme.bgMedium, { 0.1, 0.1, 0.1, 1 })
    local border = ValidateThemeColor(Theme.border, { 0.3, 0.3, 0.3, 1 })
    local accent = ValidateThemeColor(Theme.accent, { 1, 0.82, 0, 1 })
    local textPrimary = ValidateThemeColor(Theme.textPrimary, { 1, 1, 1, 1 })
    local textSecondary = ValidateThemeColor(Theme.textSecondary, { 0.7, 0.7, 0.7, 1 })

    local dialog = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    dialog:SetSize(POPUP_WIDTH, POPUP_HEIGHT)
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    dialog:SetFrameStrata("TOOLTIP")
    dialog:SetFrameLevel(100)
    dialog:EnableMouse(true)
    dialog:SetMovable(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)

    dialog:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    dialog:SetBackdropColor(bgLight[1], bgLight[2], bgLight[3], bgLight[4] or 1)
    dialog:SetBackdropBorderColor(border[1], border[2], border[3], 1)

    local header = CreateFrame("Frame", nil, dialog, "BackdropTemplate")
    header:SetHeight(28)
    header:SetPoint("TOPLEFT", dialog, "TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -1, -1)
    header:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    header:SetBackdropColor(bgMedium[1], bgMedium[2], bgMedium[3], 1)

    local headerbottomBorder = header:CreateTexture(nil, "BORDER")
    headerbottomBorder:SetHeight(Theme.borderSize or 1)
    headerbottomBorder:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    headerbottomBorder:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    headerbottomBorder:SetColorTexture(border[1], border[2], border[3], border[4] or 1)

    local titleLabel = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleLabel:SetPoint("CENTER", header, "CENTER", 0, 0)
    titleLabel:SetText(title or "Confirm")
    titleLabel:SetTextColor(accent[1], accent[2], accent[3], accent[4] or 1)
    titleLabel:SetShadowColor(0, 0, 0, 0)

    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -6, 0)

    local closeTex = closeBtn:CreateTexture(nil, "ARTWORK")
    closeTex:SetAllPoints()
    closeTex:SetTexture("Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\KitnCustomCrossv3.png")
    closeTex:SetRotation(math.rad(45))
    closeTex:SetVertexColor(textPrimary[1], textPrimary[2], textPrimary[3], textPrimary[4] or 1)
    closeTex:SetTexelSnappingBias(0)
    closeTex:SetSnapToPixelGrid(false)

    closeBtn:SetScript("OnEnter", function()
        closeTex:SetVertexColor(accent[1], accent[2], accent[3], accent[4] or 1)
    end)
    closeBtn:SetScript("OnLeave", function()
        closeTex:SetVertexColor(textPrimary[1], textPrimary[2], textPrimary[3], textPrimary[4] or 1)
    end)
    closeBtn:SetScript("OnClick", function()
        if onCancel then onCancel() end
        dialog:Hide()
        KE.activePrompt = nil
    end)

    if useTexture and texturePath then
        local logoN = CreateFrame("Button", nil, header)
        logoN:SetSize(textureSizeX, textureSizeY)
        logoN:SetPoint("LEFT", header, "LEFT", 6, 0)
        local logoTexture = logoN:CreateTexture(nil, "ARTWORK")
        logoTexture:SetAllPoints()
        logoTexture:SetTexture(texturePath)
        if textureColor then
            logoTexture:SetVertexColor(textureColor.r, textureColor.g, textureColor.b, 1)
        end
        logoTexture:SetTexelSnappingBias(0)
        logoTexture:SetSnapToPixelGrid(false)
    end

    if not showEditBox or onAccept and not dialog.messageLabel then
        local messageLabel = dialog:CreateFontString(nil, "OVERLAY")
        messageLabel:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 12, -12)
        messageLabel:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -12, -12)
        messageLabel:SetJustifyH("CENTER")
        messageLabel:SetJustifyV("TOP")
        if KE.ApplyThemeFont then
            KE:ApplyThemeFont(messageLabel, "normal")
        else
            messageLabel:SetFontObject("GameFontNormal")
        end
        messageLabel:SetText(text or "")
        messageLabel:SetTextColor(textPrimary[1], textPrimary[2], textPrimary[3], 1)
        messageLabel:SetShadowColor(0, 0, 0, 0)
    end

    if showEditBox and not dialog.editBox then
        -- When two editboxes: put label above first editbox
        local editBox1Label
        if showSecondEditBox then
            editBox1Label = dialog:CreateFontString(nil, "OVERLAY")
            editBox1Label:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 24, -10)
            editBox1Label:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -24, -10)
            editBox1Label:SetJustifyH("CENTER")
            if KE.ApplyThemeFont then
                KE:ApplyThemeFont(editBox1Label, "normal")
            else
                editBox1Label:SetFontObject("GameFontNormal")
            end
            editBox1Label:SetText(editBoxLabelText or "")
            editBox1Label:SetTextColor(textSecondary[1], textSecondary[2], textSecondary[3], 1)
            editBox1Label:SetShadowColor(0, 0, 0, 0)
        end

        local editBox = CreateFrame("EditBox", nil, dialog, "BackdropTemplate")
        editBox:SetSize(dialog:GetWidth() - 24, 24)
        if editBox1Label then
            editBox:SetPoint("TOPLEFT", editBox1Label, "BOTTOMLEFT", -12, -4)
        else
            editBox:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 12, -12)
        end
        editBox:SetAutoFocus(true)
        editBox:SetText("")
        editBox:SetJustifyH("CENTER")

        editBox:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        editBox:SetBackdropColor(bgMedium[1], bgMedium[2], bgMedium[3], 1)
        editBox:SetBackdropBorderColor(border[1], border[2], border[3], 1)
        if KE.ApplyThemeFont then
            KE:ApplyThemeFont(editBox, "normal")
        else
            editBox:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
        end
        editBox:SetTextColor(textPrimary[1], textPrimary[2], textPrimary[3], 1)
        editBox:SetShadowColor(0, 0, 0, 0)

        if not onAccept then
            editBox:SetScript("OnKeyDown", function(self, key)
                if key == "C" and (IsControlKeyDown() or IsMetaKeyDown()) then
                    KE:CreateMessagePopup(2, "Copied to clipboard", 18, UIParent, 0, 350)
                    if onCancel then onCancel() end
                    dialog:Hide()
                    KE.activePrompt = nil
                end
            end)
        else
            editBox:SetScript("OnEnterPressed", function(self)
                if onAccept then
                    onAccept(self:GetText())
                    dialog:Hide()
                    KE.activePrompt = nil
                end
            end)
        end

        editBox:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
        end)
        editBox:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(border[1], border[2], border[3], 1)
        end)

        -- Below-editbox label (only for single editbox mode)
        local editBoxLabel
        if not showSecondEditBox then
            editBoxLabel = dialog:CreateFontString(nil, "OVERLAY")
            editBoxLabel:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", 12, -6)
            editBoxLabel:SetPoint("TOPRIGHT", editBox, "BOTTOMRIGHT", -12, -6)
            editBoxLabel:SetJustifyH("CENTER")
            editBoxLabel:SetJustifyV("TOP")
            if KE.ApplyThemeFont then
                KE:ApplyThemeFont(editBoxLabel, "normal")
            else
                editBoxLabel:SetFontObject("GameFontNormal")
            end
            editBoxLabel:SetText(editBoxLabelText or "")
            editBoxLabel:SetTextColor(textSecondary[1], textSecondary[2], textSecondary[3], 1)
            editBoxLabel:SetShadowColor(0, 0, 0, 0)
        end

        dialog.editBox = editBox
        dialog.editBoxLabel = editBoxLabel or editBox1Label
    end

    -- Second editbox (for two-field prompts like import: name + string)
    if showSecondEditBox and showEditBox and dialog.editBox then
        local editBox2Label = dialog:CreateFontString(nil, "OVERLAY")
        editBox2Label:SetPoint("TOPLEFT", dialog.editBox, "BOTTOMLEFT", 12, -10)
        editBox2Label:SetPoint("TOPRIGHT", dialog.editBox, "BOTTOMRIGHT", -12, -10)
        editBox2Label:SetJustifyH("CENTER")
        if KE.ApplyThemeFont then
            KE:ApplyThemeFont(editBox2Label, "normal")
        else
            editBox2Label:SetFontObject("GameFontNormal")
        end
        editBox2Label:SetText(secondEditBoxLabel or "")
        editBox2Label:SetTextColor(textSecondary[1], textSecondary[2], textSecondary[3], 1)
        editBox2Label:SetShadowColor(0, 0, 0, 0)

        local editBox2 = CreateFrame("EditBox", nil, dialog, "BackdropTemplate")
        editBox2:SetHeight(24)
        editBox2:SetPoint("TOPLEFT", editBox2Label, "BOTTOMLEFT", -12, -4)
        editBox2:SetPoint("TOPRIGHT", editBox2Label, "BOTTOMRIGHT", 12, -4)
        editBox2:SetAutoFocus(false)
        editBox2:SetText("")
        editBox2:SetJustifyH("CENTER")

        editBox2:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        editBox2:SetBackdropColor(bgMedium[1], bgMedium[2], bgMedium[3], 1)
        editBox2:SetBackdropBorderColor(border[1], border[2], border[3], 1)
        if KE.ApplyThemeFont then
            KE:ApplyThemeFont(editBox2, "normal")
        else
            editBox2:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
        end
        editBox2:SetTextColor(textPrimary[1], textPrimary[2], textPrimary[3], 1)
        editBox2:SetShadowColor(0, 0, 0, 0)

        editBox2:SetScript("OnEnterPressed", function(self)
            if onAccept and dialog.editBox then
                onAccept(dialog.editBox:GetText(), self:GetText())
                dialog:Hide()
                KE.activePrompt = nil
            end
        end)

        editBox2:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
        end)
        editBox2:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(border[1], border[2], border[3], 1)
        end)

        dialog.editBox2 = editBox2

        -- Tab between editboxes
        dialog.editBox:SetScript("OnTabPressed", function()
            editBox2:SetFocus()
        end)
        editBox2:SetScript("OnTabPressed", function()
            dialog.editBox:SetFocus()
        end)

        -- Expand dialog height to fit both fields
        dialog:SetHeight(POPUP_HEIGHT + 70)
    end

    if dialog.editBox then
        dialog.editBox:SetText(text or "")
        dialog.editBox:HighlightText()
        dialog.editBox:SetAutoFocus(true)
    end

    if not showEditBox or onAccept then
        local buttonContainer = CreateFrame("Frame", nil, dialog)
        buttonContainer:SetHeight(30)
        buttonContainer:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 12, 12)
        buttonContainer:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -12, 12)

        local acceptBtn = CreateThemedButton(buttonContainer, Theme, acceptText or "Accept", true)
        acceptBtn:SetPoint("RIGHT", buttonContainer, "CENTER", -4, 0)
        acceptBtn:SetScript("OnClick", function()
            if onAccept then
                if showEditBox and dialog.editBox then
                    if dialog.editBox2 then
                        onAccept(dialog.editBox:GetText(), dialog.editBox2:GetText())
                    else
                        onAccept(dialog.editBox:GetText())
                    end
                else
                    onAccept()
                end
            end
            dialog:Hide()
            KE.activePrompt = nil
        end)

        local cancelBtn = CreateThemedButton(buttonContainer, Theme, cancelText or "Cancel", false)
        cancelBtn:SetPoint("LEFT", buttonContainer, "CENTER", 4, 0)
        cancelBtn:SetScript("OnClick", function()
            if onCancel then onCancel() end
            dialog:Hide()
            KE.activePrompt = nil
        end)
    end

    dialog:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            if onCancel then onCancel() end
            self:Hide()
            KE.activePrompt = nil
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    dialog:EnableKeyboard(true)

    dialog:Show()
    KE.activePrompt = dialog

    return dialog
end

function KE:CreateReloadPrompt(reason)
    local text = reason or "Would you like to reload your UI now?"
    return self:CreatePrompt(
        "Reload Required",
        text,
        false,
        nil,
        false,
        nil,
        nil,
        nil,
        nil,
        function() ReloadUI() end,
        nil,
        "Reload Now",
        "Later"
    )
end

function KE:SkinningReloadPrompt()
    return self:CreateReloadPrompt("Changing this setting may require a reload to take full effect.")
end

--------------------------------------------------------------------------------
-- Combat-Safe Fade (smooth alpha transition via OnUpdate, avoids taint)
--------------------------------------------------------------------------------
function KE:CombatSafeFade(frame, targetAlpha, duration)
    if frame._fadeTimer then frame._fadeTimer:Hide() end

    local startAlpha = frame:GetAlpha()
    local diff = targetAlpha - startAlpha
    if diff == 0 or duration <= 0 then
        frame:SetAlpha(targetAlpha)
        return
    end

    local timer = frame._fadeTimer or CreateFrame("Frame")
    frame._fadeTimer = timer
    local elapsed = 0
    timer:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        local progress = elapsed / duration
        if progress >= 1 then
            frame:SetAlpha(targetAlpha)
            self:Hide()
        else
            frame:SetAlpha(startAlpha + diff * progress)
        end
    end)
    timer:Show()
end

--------------------------------------------------------------------------------
-- Font & Backdrop helpers
--------------------------------------------------------------------------------

-- Apply font to a FontString with font shadow and soft outline support
function KE:ApplyFontToText(fontString, fontName, fontSize, fontOutline, shadowConfig)
    if not fontString then return end

    -- Soft outline mode: use 8-shadow system instead of WoW's built-in outline
    if fontOutline == "SOFTOUTLINE" then
        local success = self:ApplyFont(fontString, fontName, fontSize, "SOFTOUTLINE")
        fontString:SetShadowOffset(0, 0)
        fontString:SetShadowColor(0, 0, 0, 0)

        local fontPath = self:GetFontPath(fontName)

        if not fontString.softOutline then
            fontString.softOutline = self:CreateSoftOutline(fontString, {
                thickness = 1,
                color = { 0, 0, 0 },
                alpha = 0.9,
                fontPath = fontPath,
                fontSize = fontSize,
            })
        else
            fontString.softOutline:SetFont(fontPath, fontSize, "")
            fontString.softOutline:SetText(fontString:GetText() or "")
            fontString.softOutline:SetShown(true)
        end

        return success
    end

    -- Hide soft outline if switching away from SOFTOUTLINE
    if fontString.softOutline then
        fontString.softOutline:SetShown(false)
    end

    self:ApplyFont(fontString, fontName, fontSize, fontOutline)

    if shadowConfig and shadowConfig.Enabled then
        fontString:SetShadowOffset(shadowConfig.OffsetX or 1, shadowConfig.OffsetY or -1)
        fontString:SetShadowColor(
            shadowConfig.Color and shadowConfig.Color[1] or 0,
            shadowConfig.Color and shadowConfig.Color[2] or 0,
            shadowConfig.Color and shadowConfig.Color[3] or 0,
            shadowConfig.Color and shadowConfig.Color[4] or 0.8
        )
    else
        fontString:SetShadowOffset(0, 0)
        fontString:SetShadowColor(0, 0, 0, 0)
    end
end

-- Create a simple backdrop on a frame
function KE:ApplyBackdrop(frame, backdropConfig)
    if not frame or not backdropConfig then return end
    if backdropConfig.Enabled then
        local borderSize = backdropConfig.BorderSize or 1
        frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false,
            tileSize = 0,
            edgeSize = borderSize,
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        local bgColor = backdropConfig.Color or { 0, 0, 0, 0.6 }
        local borderColor = backdropConfig.BorderColor or { 0, 0, 0, 1 }
        frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 0.6)
        frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
    else
        frame:SetBackdrop(nil)
    end
end

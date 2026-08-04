-- ╔══════════════════════════════════════════════════════════╗
-- ║  Widgets.lua                                             ║
-- ║  Purpose: Common widget helpers used by modules —        ║
-- ║           prompts, font, backdrop, icon zoom/borders.    ║
-- ║  Note: Full GUI widget library is in GUI/GUIWidgets/.    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local CreateFrame = CreateFrame
local C_Timer = C_Timer
local UIParent = UIParent
local type = type
local IsControlKeyDown = IsControlKeyDown
local IsMetaKeyDown = IsMetaKeyDown
local StaticPopup_Show = StaticPopup_Show
local ReloadUI = ReloadUI
local ACCEPT = ACCEPT
local CANCEL = CANCEL

---------------------------------------------------------------------------------
-- Message Popup
---------------------------------------------------------------------------------

local MESSAGE_POPUP_SIZE = 64

local function ValidateThemeColor(color, default)
    if not color or type(color) ~= "table" then return default end
    return color
end

-- Build-once singleton: a fresh container per call leaked the frame, the
-- FontString, AND its 8-shadow soft outline permanently (frames are never
-- GC'd; softOutline caches per FontString, so reuse stops that too).
function KE:CreateMessagePopup(timer, text, fontSize, parentFrame, xOffset, yOffset)
    if KE.msgContainer then
        KE.msgContainer:Hide()
    end

    local Theme = KE.Theme
    local parent = parentFrame or UIParent
    local x = xOffset or 0
    local y = yOffset or 250

    if not Theme then return end

    local msgContainer = KE.msgContainer
    if not msgContainer then
        msgContainer = CreateFrame("Frame", nil, parent)
        msgContainer:SetToplevel(true)
        msgContainer:SetSize(MESSAGE_POPUP_SIZE, MESSAGE_POPUP_SIZE)
        msgContainer.msgText = msgContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        msgContainer.msgText:SetPoint("CENTER")
        KE.msgContainer = msgContainer
    end
    local msgText = msgContainer.msgText

    msgContainer:SetParent(parent)
    -- Re-assert strata/level AFTER SetParent — reparenting rebases them.
    msgContainer:SetFrameStrata("TOOLTIP")
    msgContainer:SetFrameLevel(150)
    msgContainer:ClearAllPoints()
    msgContainer:SetPoint("CENTER", parent, "CENTER", x, y)

    -- SetText BEFORE ApplyFontToText — the soft-outline reuse path copies
    -- GetText() into the shadow layer.
    msgText:SetText(text)
    msgText:SetFont(KE.FONT, fontSize, "")

    KE:ApplyFontToText(msgText, "Expressway", fontSize, "SOFTOUTLINE")

    local accent = ValidateThemeColor(Theme.accent, { 1, 0.82, 0, 1 })
    msgText:SetTextColor(accent[1], accent[2], accent[3], 1)
    msgText:SetShadowColor(0, 0, 0, 0)

    msgText:SetAlpha(1)
    msgContainer:Show()

    -- Generation token: both timer levels bail if a newer call re-showed the
    -- popup (EditMode's 20s enter timer vs 1s exit timer is a live overlap).
    local token = (msgContainer._hideToken or 0) + 1
    msgContainer._hideToken = token
    C_Timer.After(timer, function()
        if msgContainer._hideToken ~= token then return end
        msgText:SetAlpha(0)
        C_Timer.After(0.1, function()
            if msgContainer._hideToken ~= token then return end
            msgContainer:Hide()
        end)
    end)

    return msgContainer
end

---------------------------------------------------------------------------------
-- Prompt Dialog
---------------------------------------------------------------------------------

local POPUP_WIDTH = 360
local POPUP_HEIGHT = 120
local BUTTON_WIDTH = 100
local BUTTON_HEIGHT = 26
-- Breathing room each side of a label that outgrows BUTTON_WIDTH.
local BUTTON_TEXT_PADDING = 24

-- Re-applies theme colors, edge size, and label to a themed button. Split
-- from CreateThemedButton so the singleton prompt can re-theme its
-- persistent buttons per call; hover scripts read the stored _bg*/_accent
-- fields so a theme change never leaves stale colors baked into closures.
local function ThemeButton(btn, Theme, labelText, isPrimary)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = KE:GetPixelSize(),
    })
    local textColor = isPrimary and Theme.accent or Theme.textPrimary
    btn._bgMedium = ValidateThemeColor(Theme.bgMedium, { 0.1, 0.1, 0.1, 1 })
    btn._bgLight = ValidateThemeColor(Theme.bgLight, { 0.15, 0.15, 0.15, 1 })
    btn._border = ValidateThemeColor(Theme.border, { 0.3, 0.3, 0.3, 1 })
    btn._accent = ValidateThemeColor(Theme.accent, { 1, 0.82, 0, 1 })

    btn:SetBackdropColor(btn._bgMedium[1], btn._bgMedium[2], btn._bgMedium[3], 1)
    btn:SetBackdropBorderColor(btn._border[1], btn._border[2], btn._border[3], 1)

    if KE.ApplyThemeFont then
        KE:ApplyThemeFont(btn.label, "normal")
    else
        btn.label:SetFontObject("GameFontNormal")
    end
    btn.label:SetText(labelText)
    btn.label:SetTextColor(textColor[1], textColor[2], textColor[3], 1)
    btn.label:SetShadowColor(0, 0, 0, 0)

    -- GROW-ONLY: the label is a centered FontString with no width limit, so a
    -- label wider than BUTTON_WIDTH spilled equally past both edges and drew
    -- straight over the neighbouring button (the two sit 8px apart around the
    -- container's center). Every prior caller used short labels -- "Reset",
    -- "Reload Now" -- which is why this only surfaced once a prompt put a
    -- variable-length addon name on a button. Widening only when the text
    -- demands it leaves every existing prompt pixel-identical.
    local textWidth = btn.label:GetStringWidth() or 0
    btn:SetWidth(math.max(BUTTON_WIDTH, textWidth + BUTTON_TEXT_PADDING))
end

local function CreateThemedButton(parent, Theme, labelText, isPrimary)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)

    local label = btn:CreateFontString(nil, "OVERLAY")
    label:SetPoint("CENTER")
    btn.label = label

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(self._bgLight[1], self._bgLight[2], self._bgLight[3], 1)
        self:SetBackdropBorderColor(self._accent[1], self._accent[2], self._accent[3], 1)
    end)

    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(self._bgMedium[1], self._bgMedium[2], self._bgMedium[3], 1)
        self:SetBackdropBorderColor(self._border[1], self._border[2], self._border[3], 1)
    end)

    ThemeButton(btn, Theme, labelText, isPrimary)
    return btn
end

-- Closes the singleton prompt. Snapshots and NILS the callback fields
-- before invoking — the immortal dialog would otherwise pin multi-KB
-- export-string closures, and the close-then-invoke order lets a chained
-- prompt opened inside the callback (profile change → reload prompt)
-- survive the outer close. Returns the snapshotted onAccept.
local function ClosePrompt(dialog, runCancel)
    local onAccept = dialog._onAccept
    local onCancel = dialog._onCancel
    dialog._onAccept = nil
    dialog._onCancel = nil
    dialog:Hide()
    KE.activePrompt = nil
    if runCancel and onCancel then onCancel() end
    return onAccept
end

-- Build-once skeleton for the prompt singleton: dialog chrome + header +
-- close button, scripts wired once reading per-call state off the dialog.
-- Mode-specific widgets (message label, editboxes, buttons) are ensured
-- lazily by CreatePrompt's create pass. KE.promptDialog is the persistent
-- cache; KE.activePrompt keeps its nil-on-close "a prompt is open" meaning.
local function EnsurePromptDialog()
    if KE.promptDialog then return KE.promptDialog end

    local dialog = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    dialog:SetSize(POPUP_WIDTH, POPUP_HEIGHT)
    dialog:SetFrameStrata("TOOLTIP")
    dialog:SetFrameLevel(100)
    dialog:EnableMouse(true)
    dialog:SetMovable(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", function(d) d:StartMoving(true) end)
    dialog:SetScript("OnDragStop", function(d) d:StopMovingOrSizing() end)
    -- Guarded for the same reason as the show-time reset (:717-741):
    -- EnableKeyboard is protected. This builder runs once, on the session's
    -- FIRST prompt, so an unguarded call here throws for a player whose first
    -- prompt of the session happens to be raised mid-fight. Skipping it leaves
    -- that prompt without ESCAPE until the combat watcher arms it (:788-795).
    if not InCombatLockdown() then dialog:EnableKeyboard(true) end
    dialog:SetScript("OnKeyDown", function(self, key)
        -- SetPropagateKeyboardInput is combat-protected for insecure frames;
        -- skip it in lockdown (ESC-close itself is fine — see EditMode's
        -- RemoveEscapeHandler for the same treatment).
        if key == "ESCAPE" then
            if not InCombatLockdown() then self:SetPropagateKeyboardInput(false) end
            ClosePrompt(self, true)
        else
            if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
        end
    end)
    dialog:Hide()

    local header = CreateFrame("Frame", nil, dialog, "BackdropTemplate")
    header:SetHeight(28)
    header:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    dialog.header = header

    local headerBottomBorder = header:CreateTexture(nil, "BORDER")
    headerBottomBorder:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    headerBottomBorder:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    dialog.headerBottomBorder = headerBottomBorder

    local titleLabel = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleLabel:SetPoint("CENTER", header, "CENTER", 0, 0)
    dialog.titleLabel = titleLabel

    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -6, 0)

    local closeTex = closeBtn:CreateTexture(nil, "ARTWORK")
    closeTex:SetAllPoints()
    closeTex:SetTexture("Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\KitnCustomCrossv3.png")
    closeTex:SetRotation(math.rad(45))
    closeTex:SetTexelSnappingBias(0)
    closeTex:SetSnapToPixelGrid(false)
    dialog.closeTex = closeTex

    closeBtn:SetScript("OnEnter", function()
        local a = dialog._accent
        if a then closeTex:SetVertexColor(a[1], a[2], a[3], a[4] or 1) end
    end)
    closeBtn:SetScript("OnLeave", function()
        local t = dialog._textPrimary
        if t then closeTex:SetVertexColor(t[1], t[2], t[3], t[4] or 1) end
    end)
    closeBtn:SetScript("OnClick", function()
        ClosePrompt(dialog, true)
    end)

    KE.promptDialog = dialog
    return dialog
end

-- Singleton prompt dialog. The previous implementation rebuilt the whole
-- 6-frame tree per call and leaked it permanently (frames are never GC'd).
-- Three strictly ordered passes: ENSURE-CREATE everything the current mode
-- needs → CONFIGURE/anchor/theme → VISIBILITY (SetShown on every optional
-- widget, shown or not — a widget left visible from the last mode is a bug).
-- NOTE: single-field-accept mode (showEditBox + onAccept, no second box)
-- currently has no live caller — untested API surface.
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

    local dialog = EnsurePromptDialog()
    local twoField = (showEditBox and showSecondEditBox) and true or false
    -- Hard-codes the original's effective evaluation (its `and not
    -- dialog.messageLabel` guard could never fire on a fresh frame).
    local showMessage = (not showEditBox) or (onAccept ~= nil)
    -- OPT-IN single Close button for copy mode (edit box, no accept
    -- callback): the caller asks for it by passing cancelText. No other
    -- mode can reach this flag -- showEditBox+onAccept~=nil already shows
    -- buttons the ordinary way, and confirm mode (not showEditBox) always
    -- did. A copy prompt carrying a cancelText IS the Copy Anything window;
    -- the title/edit-box colour swap below keys off the same flag rather
    -- than adding a second parameter for what is really one signal.
    local isCopyPrompt = showEditBox and not onAccept and cancelText and true or false
    local showButtons = (not showEditBox) or (onAccept ~= nil) or isCopyPrompt

    ------------------------------------------------------------------
    -- PASS 1: ensure-create every widget the current mode needs.
    ------------------------------------------------------------------
    if showMessage and not dialog.messageLabel then
        local messageLabel = dialog:CreateFontString(nil, "OVERLAY")
        messageLabel:SetPoint("TOPLEFT", dialog.header, "BOTTOMLEFT", 12, -12)
        messageLabel:SetPoint("TOPRIGHT", dialog.header, "BOTTOMRIGHT", -12, -12)
        messageLabel:SetJustifyH("CENTER")
        messageLabel:SetJustifyV("TOP")
        dialog.messageLabel = messageLabel
    end

    if useTexture and texturePath and not dialog.logoBtn then
        local logoBtn = CreateFrame("Button", nil, dialog.header)
        logoBtn:SetPoint("LEFT", dialog.header, "LEFT", 6, 0)
        local logoTexture = logoBtn:CreateTexture(nil, "ARTWORK")
        logoTexture:SetAllPoints()
        logoTexture:SetTexelSnappingBias(0)
        logoTexture:SetSnapToPixelGrid(false)
        dialog.logoBtn = logoBtn
        dialog.logoTexture = logoTexture
    end

    if twoField and not dialog.editBoxTopLabel then
        -- Two-field mode: label ABOVE the first editbox.
        local editBoxTopLabel = dialog:CreateFontString(nil, "OVERLAY")
        editBoxTopLabel:SetPoint("TOPLEFT", dialog.header, "BOTTOMLEFT", 24, -10)
        editBoxTopLabel:SetPoint("TOPRIGHT", dialog.header, "BOTTOMRIGHT", -24, -10)
        editBoxTopLabel:SetJustifyH("CENTER")
        dialog.editBoxTopLabel = editBoxTopLabel
    end

    if showEditBox and not dialog.editBox then
        local editBox = CreateFrame("EditBox", nil, dialog, "BackdropTemplate")
        editBox:SetJustifyH("CENTER")

        -- Copy-mode Ctrl+C (no accept callback = export/copy prompt).
        editBox:SetScript("OnKeyDown", function(_, key)
            local d = KE.promptDialog
            if d._onAccept then return end
            if key == "C" and (IsControlKeyDown() or IsMetaKeyDown()) then
                KE:CreateMessagePopup(2, "Copied to clipboard", 18, UIParent, 0, 350)
                ClosePrompt(d, true)
            end
        end)
        editBox:SetScript("OnEnterPressed", function(self)
            local d = KE.promptDialog
            if not d._onAccept then return end
            local text1 = self:GetText()
            local accept = ClosePrompt(d, false)
            if accept then accept(text1) end
        end)
        -- Gated on the per-call flag: a persistent editBox2 would otherwise
        -- steal Tab focus in copy-mode prompts and eat the Ctrl+C the label
        -- tells the user to press.
        editBox:SetScript("OnTabPressed", function()
            local d = KE.promptDialog
            if d._showSecondEditBox and d.editBox2 then
                d.editBox2:SetFocus()
            end
        end)
        editBox:SetScript("OnEnter", function(self)
            local a = KE.promptDialog._accent
            if a then self:SetBackdropBorderColor(a[1], a[2], a[3], 1) end
        end)
        editBox:SetScript("OnLeave", function(self)
            local b = KE.promptDialog._border
            if b then self:SetBackdropBorderColor(b[1], b[2], b[3], 1) end
        end)
        dialog.editBox = editBox
    end

    if showEditBox and not twoField and not dialog.editBoxBottomLabel then
        -- Single-field mode: label BELOW the editbox.
        local editBoxBottomLabel = dialog:CreateFontString(nil, "OVERLAY")
        editBoxBottomLabel:SetPoint("TOPLEFT", dialog.editBox, "BOTTOMLEFT", 12, -6)
        editBoxBottomLabel:SetPoint("TOPRIGHT", dialog.editBox, "BOTTOMRIGHT", -12, -6)
        editBoxBottomLabel:SetJustifyH("CENTER")
        editBoxBottomLabel:SetJustifyV("TOP")
        dialog.editBoxBottomLabel = editBoxBottomLabel
    end

    if twoField and not dialog.editBox2 then
        -- Second editbox (for two-field prompts like import: name + string)
        local editBox2Label = dialog:CreateFontString(nil, "OVERLAY")
        editBox2Label:SetPoint("TOPLEFT", dialog.editBox, "BOTTOMLEFT", 12, -10)
        editBox2Label:SetPoint("TOPRIGHT", dialog.editBox, "BOTTOMRIGHT", -12, -10)
        editBox2Label:SetJustifyH("CENTER")
        dialog.editBox2Label = editBox2Label

        local editBox2 = CreateFrame("EditBox", nil, dialog, "BackdropTemplate")
        editBox2:SetHeight(24)
        editBox2:SetPoint("TOPLEFT", editBox2Label, "BOTTOMLEFT", -12, -4)
        editBox2:SetPoint("TOPRIGHT", editBox2Label, "BOTTOMRIGHT", 12, -4)
        editBox2:SetAutoFocus(false)
        editBox2:SetJustifyH("CENTER")

        editBox2:SetScript("OnEnterPressed", function(self)
            local d = KE.promptDialog
            if not d._onAccept then return end
            local text1 = d.editBox and d.editBox:GetText()
            local text2 = self:GetText()
            local accept = ClosePrompt(d, false)
            if accept then accept(text1, text2) end
        end)
        editBox2:SetScript("OnTabPressed", function()
            local d = KE.promptDialog
            if d._showSecondEditBox and d.editBox then
                d.editBox:SetFocus()
            end
        end)
        editBox2:SetScript("OnEnter", function(self)
            local a = KE.promptDialog._accent
            if a then self:SetBackdropBorderColor(a[1], a[2], a[3], 1) end
        end)
        editBox2:SetScript("OnLeave", function(self)
            local b = KE.promptDialog._border
            if b then self:SetBackdropBorderColor(b[1], b[2], b[3], 1) end
        end)
        dialog.editBox2 = editBox2
    end

    if showButtons and not dialog.buttonContainer then
        local buttonContainer = CreateFrame("Frame", nil, dialog)
        buttonContainer:SetHeight(30)
        buttonContainer:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 12, 12)
        buttonContainer:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -12, 12)
        dialog.buttonContainer = buttonContainer

        local acceptBtn = CreateThemedButton(buttonContainer, Theme, acceptText or "Accept", true)
        acceptBtn:SetPoint("RIGHT", buttonContainer, "CENTER", -4, 0)
        acceptBtn:SetScript("OnClick", function()
            local d = KE.promptDialog
            -- Branch on the per-call FLAGS, never on widget existence — the
            -- singleton keeps editBox/editBox2 around across modes. Confirm
            -- mode must invoke with ZERO args.
            local wasEdit = d._showEditBox
            local wasSecond = d._showSecondEditBox
            local text1 = d.editBox and d.editBox:GetText()
            local text2 = d.editBox2 and d.editBox2:GetText()
            local accept = ClosePrompt(d, false)
            if not accept then return end
            if wasEdit then
                if wasSecond then
                    accept(text1, text2)
                else
                    accept(text1)
                end
            else
                accept()
            end
        end)
        dialog.acceptBtn = acceptBtn

        local cancelBtn = CreateThemedButton(buttonContainer, Theme, cancelText or "Cancel", false)
        cancelBtn:SetPoint("LEFT", buttonContainer, "CENTER", 4, 0)
        cancelBtn:SetScript("OnClick", function()
            ClosePrompt(KE.promptDialog, true)
        end)
        dialog.cancelBtn = cancelBtn
    end

    ------------------------------------------------------------------
    -- PASS 2: configure — per-call state, theme, anchors, heights.
    ------------------------------------------------------------------
    dialog._onAccept = onAccept
    dialog._onCancel = onCancel
    dialog._showEditBox = showEditBox and true or false
    dialog._showSecondEditBox = twoField
    -- Hover scripts read these (theme can change between prompts).
    dialog._accent = accent
    dialog._border = border
    dialog._textPrimary = textPrimary

    local dialogPx = KE:GetPixelSize()
    dialog:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = dialogPx,
    })
    dialog:SetBackdropColor(bgLight[1], bgLight[2], bgLight[3], bgLight[4] or 1)
    dialog:SetBackdropBorderColor(border[1], border[2], border[3], 1)
    -- Reset size/position BEFORE the adaptive-height branches: the singleton
    -- remembers the last mode's height and any user drag.
    dialog:SetHeight(POPUP_HEIGHT)
    dialog:ClearAllPoints()
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 100)

    local header = dialog.header
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", dialog, "TOPLEFT", dialogPx, -dialogPx)
    header:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -dialogPx, -dialogPx)
    header:SetBackdropColor(bgMedium[1], bgMedium[2], bgMedium[3], 1)

    dialog.headerBottomBorder:SetHeight(Theme.borderSize or 1)
    dialog.headerBottomBorder:SetColorTexture(border[1], border[2], border[3], border[4] or 1)

    dialog.titleLabel:SetText(title or "Confirm")
    -- Copy Anything is the one KE popup styled against the reference: white
    -- title, accent-coloured id (edit box, below). isCopyPrompt is the same
    -- flag Step 2 uses for the Close button -- see its definition above.
    local titleColor = isCopyPrompt and textPrimary or accent
    dialog.titleLabel:SetTextColor(titleColor[1], titleColor[2], titleColor[3], titleColor[4] or 1)
    dialog.titleLabel:SetShadowColor(0, 0, 0, 0)
    dialog.closeTex:SetVertexColor(textPrimary[1], textPrimary[2], textPrimary[3], textPrimary[4] or 1)

    if dialog.messageLabel and showMessage then
        local messageLabel = dialog.messageLabel
        if KE.ApplyThemeFont then
            KE:ApplyThemeFont(messageLabel, "normal")
        else
            messageLabel:SetFontObject("GameFontNormal")
        end
        messageLabel:SetText(text or "")
        messageLabel:SetTextColor(textPrimary[1], textPrimary[2], textPrimary[3], 1)
        messageLabel:SetShadowColor(0, 0, 0, 0)

        -- Adaptive height for confirmation-style prompts. Default POPUP_HEIGHT
        -- (120) leaves only ~26px of message space between header and buttons —
        -- enough for one line, but text with "\n\nAre you sure?" wraps past the
        -- button row. Editbox modes have their own SetHeight paths below.
        if not showEditBox then
            local textHeight = messageLabel:GetStringHeight() or 0
            -- header(28) + topMargin(12) + text + bottomMargin(12) + buttons(30) + bottomMargin(12)
            local needed = 28 + 12 + textHeight + 12 + 30 + 12
            if needed > POPUP_HEIGHT then
                dialog:SetHeight(needed)
            end
        end
    end

    if dialog.logoBtn and useTexture and texturePath then
        dialog.logoBtn:SetSize(textureSizeX, textureSizeY)
        dialog.logoTexture:SetTexture(texturePath)
        if textureColor then
            dialog.logoTexture:SetVertexColor(textureColor.r, textureColor.g, textureColor.b, 1)
        else
            dialog.logoTexture:SetVertexColor(1, 1, 1, 1)
        end
    end

    if dialog.editBoxTopLabel and twoField then
        local label = dialog.editBoxTopLabel
        if KE.ApplyThemeFont then
            KE:ApplyThemeFont(label, "normal")
        else
            label:SetFontObject("GameFontNormal")
        end
        label:SetText(editBoxLabelText or "")
        label:SetTextColor(textSecondary[1], textSecondary[2], textSecondary[3], 1)
        label:SetShadowColor(0, 0, 0, 0)
    end

    if dialog.editBox and showEditBox then
        local editBox = dialog.editBox
        editBox:SetSize(dialog:GetWidth() - 24, 24)
        editBox:ClearAllPoints()
        if twoField then
            editBox:SetPoint("TOPLEFT", dialog.editBoxTopLabel, "BOTTOMLEFT", -12, -4)
        else
            editBox:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 12, -12)
        end
        editBox:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = dialogPx,
        })
        editBox:SetBackdropColor(bgMedium[1], bgMedium[2], bgMedium[3], 1)
        editBox:SetBackdropBorderColor(border[1], border[2], border[3], 1)
        if KE.ApplyThemeFont then
            KE:ApplyThemeFont(editBox, "normal")
        else
            editBox:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
        end
        -- Same isCopyPrompt swap as the title above: Copy Anything shows its
        -- id in the accent colour instead of the usual white.
        local editTextColor = isCopyPrompt and accent or textPrimary
        editBox:SetTextColor(editTextColor[1], editTextColor[2], editTextColor[3], 1)
        editBox:SetShadowColor(0, 0, 0, 0)
        editBox:SetText(text or "")
        editBox:HighlightText()
        -- SetAutoFocus(true) re-grabs focus on Show; no pre-Show SetFocus.
        editBox:SetAutoFocus(true)
    end

    if dialog.editBoxBottomLabel and showEditBox and not twoField then
        local label = dialog.editBoxBottomLabel
        if KE.ApplyThemeFont then
            KE:ApplyThemeFont(label, "normal")
        else
            label:SetFontObject("GameFontNormal")
        end
        label:SetText(editBoxLabelText or "")
        label:SetTextColor(textSecondary[1], textSecondary[2], textSecondary[3], 1)
        label:SetShadowColor(0, 0, 0, 0)

        -- Adaptive height for single-field prompts so the below-editbox label
        -- doesn't clip. header(28) + topMargin(12) + editBox(24) + gap(6) +
        -- labelHeight + bottomMargin(12) + buttons(30) + bottomMargin(12).
        local labelHeight = label:GetStringHeight() or 0
        local needed = 28 + 12 + 24 + 6 + labelHeight + 12 + 30 + 12
        if needed > POPUP_HEIGHT then
            dialog:SetHeight(needed)
        end
    end

    if dialog.editBox2 and twoField then
        local label = dialog.editBox2Label
        if KE.ApplyThemeFont then
            KE:ApplyThemeFont(label, "normal")
        else
            label:SetFontObject("GameFontNormal")
        end
        label:SetText(secondEditBoxLabel or "")
        label:SetTextColor(textSecondary[1], textSecondary[2], textSecondary[3], 1)
        label:SetShadowColor(0, 0, 0, 0)

        local editBox2 = dialog.editBox2
        editBox2:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = dialogPx,
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
        editBox2:SetText("")

        -- Expand dialog height to fit both fields
        dialog:SetHeight(POPUP_HEIGHT + 70)
    end

    if dialog.buttonContainer and showButtons and isCopyPrompt then
        -- Copy Anything's opt-in: ONE centred button carrying cancelText,
        -- no accept button at all. ThemeButton alone (not both), so the
        -- hidden acceptBtn keeps whatever theme/label it last had -- fine,
        -- since PASS 3 below hides it and the mode that shows it again
        -- always re-themes it itself.
        ThemeButton(dialog.cancelBtn, Theme, cancelText, false)
        dialog.cancelBtn:ClearAllPoints()
        dialog.cancelBtn:SetPoint("CENTER", dialog.buttonContainer, "CENTER", 0, 0)
        -- Same grow-only idiom as the two-button branch below, sized for one
        -- button instead of a pair.
        dialog:SetWidth(math.max(POPUP_WIDTH, dialog.cancelBtn:GetWidth() + 24))
    elseif dialog.buttonContainer and showButtons then
        ThemeButton(dialog.acceptBtn, Theme, acceptText or "Accept", true)
        ThemeButton(dialog.cancelBtn, Theme, cancelText or "Cancel", false)

        -- ThemeButton grows a button to fit its label, so the pair can now
        -- outgrow the dialog. Two things follow, and the second is the one an
        -- obvious fix misses.
        --
        -- RE-ANCHOR AS A GROUP. The create pass anchors accept entirely LEFT of
        -- the container's center and cancel entirely RIGHT of it. That centers
        -- the pair only while the two are the same width; with a long label on
        -- one side the group sits off-center and the wide button alone needs
        -- HALF the container, so sizing the dialog by the sum still overflows.
        -- Anchoring the pair as one group makes the sum correct and squares the
        -- layout. For equal-width buttons this is pixel-identical to the old
        -- anchoring, so the 19 short-label prompts are untouched.
        local pairWidth = dialog.acceptBtn:GetWidth() + dialog.cancelBtn:GetWidth() + 8
        dialog.acceptBtn:ClearAllPoints()
        dialog.acceptBtn:SetPoint("LEFT", dialog.buttonContainer, "CENTER", -pairWidth / 2, 0)
        dialog.cancelBtn:ClearAllPoints()
        dialog.cancelBtn:SetPoint("LEFT", dialog.acceptBtn, "RIGHT", 8, 0)

        -- Then widen to fit the group plus the container's 12px inset each
        -- side. Grow-only against POPUP_WIDTH, so short-label prompts keep
        -- their exact size.
        dialog:SetWidth(math.max(POPUP_WIDTH, pairWidth + 24))
    else
        -- The dialog is a singleton: without this, a button-less prompt would
        -- inherit the width of whatever wide-labelled prompt ran before it.
        dialog:SetWidth(POPUP_WIDTH)
    end

    ------------------------------------------------------------------
    -- PASS 3: visibility — SetShown on EVERY optional widget so nothing
    -- from the previous mode survives into this one.
    ------------------------------------------------------------------
    if dialog.messageLabel then dialog.messageLabel:SetShown(showMessage) end
    if dialog.logoBtn then dialog.logoBtn:SetShown((useTexture and texturePath) and true or false) end
    if dialog.editBox then dialog.editBox:SetShown(showEditBox and true or false) end
    if dialog.editBoxTopLabel then dialog.editBoxTopLabel:SetShown(twoField) end
    if dialog.editBoxBottomLabel then
        dialog.editBoxBottomLabel:SetShown((showEditBox and not twoField) and true or false)
    end
    if dialog.editBox2Label then dialog.editBox2Label:SetShown(twoField) end
    if dialog.editBox2 then dialog.editBox2:SetShown(twoField) end
    if dialog.buttonContainer then dialog.buttonContainer:SetShown(showButtons) end
    -- Individually shown too, not just via the container: isCopyPrompt shows
    -- the container with only cancelBtn in it, so acceptBtn -- left visible
    -- from a prior confirm-mode call -- must be hidden explicitly here.
    if dialog.acceptBtn then dialog.acceptBtn:SetShown(showButtons and not isCopyPrompt) end
    if dialog.cancelBtn then dialog.cancelBtn:SetShown(showButtons) end

    -- Reset the keyboard state on every show, OUT OF COMBAT ONLY.
    --
    -- The reset is what matters: an ESCAPE close leaves propagation false
    -- (:211-213), and without this that state is what the next prompt inherits,
    -- so a later prompt swallows every key until it is dismissed.
    --
    -- Nothing is touched in combat, and that is not caution, it is the API:
    -- EnableKeyboard is `IsProtectedFunction = true` and
    -- SetPropagateKeyboardInput is `HasRestrictions = true`
    -- (.wow-api-reference 12.0.7.68887,
    -- Blizzard_APIDocumentationGenerated/SimpleFrameAPIDocumentation.lua:217-219,
    -- :1308-1310). Calling either in lockdown throws, which is worse than the
    -- state it would repair. Core/EditMode.lua:448-456 records the same contract.
    --
    -- Residual, deliberately not fixed here: a prompt RAISED during combat keeps
    -- whatever state it inherited, so in the narrow case of an ESCAPE close
    -- immediately before a pull it can still swallow keys. The watcher below
    -- repairs it the moment combat ends. Repairing it DURING combat needs the
    -- keyboard capture moved onto a separate child frame that can be Hidden,
    -- which is EditMode's escapeFrame pattern and a change to every prompt in
    -- the addon -- out of scope for this branch.
    if not InCombatLockdown() then
        dialog:EnableKeyboard(true)
        dialog:SetPropagateKeyboardInput(true)
    end

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

-- Repair, at the end of a fight, a prompt that spent it swallowing keys.
--
-- CreatePrompt resets keyboard state on every show, but only out of combat
-- (:717-741), so a prompt raised in lockdown inherits whatever the previous one
-- left behind -- and an ESCAPE close leaves "swallow" behind (:211-213). The
-- builder has the same hole for the session's very first prompt (:201-206).
-- PLAYER_REGEN_ENABLED fires after lockdown lifts, so both calls are legal here
-- and this is the only moment the repair can be made.
--
-- There is deliberately NO PLAYER_REGEN_DISABLED half. Disarming a prompt at
-- the pull needs EnableKeyboard, which is `IsProtectedFunction = true`
-- (.wow-api-reference 12.0.7.68887,
-- Blizzard_APIDocumentationGenerated/SimpleFrameAPIDocumentation.lua:217-219)
-- and throws in combat -- the conclusion Core/EditMode.lua:448-456 also reached.
-- Modules/QoL/CopyAnything.lua:277-286 does call it from a combat handler; per
-- the reference that call is unsafe, and it is not a precedent to copy.
local promptCombatWatcher = CreateFrame("Frame")
promptCombatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
promptCombatWatcher:SetScript("OnEvent", function()
    local dialog = KE.activePrompt
    if not dialog or not dialog.IsShown or not dialog:IsShown() then return end
    dialog:EnableKeyboard(true)
    dialog:SetPropagateKeyboardInput(true)
end)

-- Skinning toggles FLAG instead of prompting. A user ticking eight windows
-- should get one prompt when they close the GUI, not eight interruptions while
-- they are still working. Ported from the reference's FlagReloadNeeded
-- (References/atrocityEssentials/atrocityEssentials v4.0.203/Core/Globals.lua:267-269).
--
-- Profile operations deliberately do NOT go through here: Brandon's ruling
-- 2026-08-02 is that a profile switch always prompts immediately
-- (Core/ProfileManager.lua:491-507).
function KE:FlagReloadNeeded()
    self.reloadPending = true
end

-- Fired from the GUI frame's own OnHide, not from GUIFrame:Hide. The reference
-- learned this the hard way (its v3.5.548 note at GUI/Main/MainFrame.lua:262-264):
-- hooking the wrapper let some close paths skip the prompt entirely. The frame
-- script cannot be skipped.
--
-- The creation-time Hide() is inert, because only a user action ever sets the
-- flag.
function KE:FlushPendingReloadPrompt()
    if not self.reloadPending then return end

    -- Entering combat HIDES this GUI (GUI/GUIMain/GUI-MainFrame.lua:682-698),
    -- which would otherwise put a "Reload Now" button on screen at the pull --
    -- one misclick from reloading mid-fight. Either guard below KEEPS the flag
    -- rather than clearing it: the combat handler reopens the GUI when combat
    -- ends, so the next ordinary close raises the prompt instead.
    --
    -- The FIRST guard is the load-bearing one. That handler sets
    -- reopenAfterCombat immediately BEFORE it hides us, so the flag identifies a
    -- combat close with no dependence on when the API flips. In-game 2026-08-04:
    -- the InCombatLockdown check ALONE did not hold -- the prompt still appeared
    -- on the combat close -- so this is not defence in depth, it is the fix.
    local gui = self.GUIFrame
    if gui and gui.reopenAfterCombat then return end

    -- The second still earns its place: a user who opens this GUI during combat
    -- and closes it themselves never sets the flag above.
    if InCombatLockdown and InCombatLockdown() then return end

    self.reloadPending = false
    return self:CreateReloadPrompt("Some of the changes you made need a UI reload to take effect. Reload now?")
end

---------------------------------------------------------------------------------
-- Combat-Safe Fade
---------------------------------------------------------------------------------

-- Smooth alpha transition via OnUpdate, avoids taint
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

---------------------------------------------------------------------------------
-- Font and Backdrop Helpers
---------------------------------------------------------------------------------

function KE:ApplyFontToText(fontString, fontName, fontSize, fontOutline, shadowConfig)
    if not fontString then return end

    -- Soft outline mode: use 8-shadow system instead of WoW's built-in outline.
    -- Main and shadow FontStrings both render with the "SLUG" flag (Blizzard's
    -- vector glyph renderer) so the halo stays crisp at every sub-pixel screen
    -- position. Bitmap rasterization on the bare main text used to produce a
    -- visible ghost-shadow that varied with the frame's X offset.
    if fontOutline == "SOFTOUTLINE" then
        local success = self:ApplyFont(fontString, fontName, fontSize, "SLUG")
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
            fontString.softOutline:SetFont(fontPath, fontSize, "SLUG")
            fontString.softOutline:SetText(fontString:GetText() or "")
            fontString.softOutline:SetShown(true)
        end

        return success
    end

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
        local bgr, bgg, bgb, bga = KE:ResolveColor(backdropConfig.Color, { 0, 0, 0, 0.6 })
        local bdr, bdg, bdb, bda = KE:ResolveColor(backdropConfig.BorderColor, { 0, 0, 0, 1 })
        frame:SetBackdropColor(bgr, bgg, bgb, bga)
        frame:SetBackdropBorderColor(bdr, bdg, bdb, bda)
    else
        frame:SetBackdrop(nil)
    end
end

---------------------------------------------------------------------------------
-- Icon Helpers
---------------------------------------------------------------------------------

-- Weak-keyed registry of borders created by AddIconBorders/AddBorders.
-- Used by KE:ResnapAllBorders (in PixelPerfect.lua) to re-apply pixel
-- size on UI_SCALE_CHANGED / DISPLAY_SIZE_CHANGED.
KE._borderRegistry = KE._borderRegistry or setmetatable({}, { __mode = "k" })

local function _KE_RegisterBorder(frame)
    if frame and frame.borders then
        KE._borderRegistry[frame] = true
    end
end

local function _KE_ApplyBorderPixel(frame)
    if not (frame and frame.borders) then return end
    local px = KE:GetPixelSize()
    local b = frame.borders
    if b.top and b.top.SetHeight then b.top:SetHeight(px) end
    if b.bottom and b.bottom.SetHeight then b.bottom:SetHeight(px) end
    if b.left and b.left.SetWidth then b.left:SetWidth(px) end
    if b.right and b.right.SetWidth then b.right:SetWidth(px) end
end

-- After border creation, re-snap for 2 frames in case parent scale hasn't
-- settled. Avoids a race where borders are created at the wrong pixel
-- thickness when a parent's effective scale is set immediately after.
-- Uses chained C_Timer.After(0) (GC'd closures) instead of a throwaway
-- ticker frame — frames are never garbage-collected.
local function _KE_DelayedBorderResnap(frame)
    if not frame then return end
    C_Timer.After(0, function()
        _KE_ApplyBorderPixel(frame)
        C_Timer.After(0, function()
            _KE_ApplyBorderPixel(frame)
        end)
    end)
end

-- zoom: 0.3 = standard (7.5% crop), 0 = no crop, 1 = max crop
function KE:ApplyIconZoom(tex, zoom)
    zoom = zoom or 0.3
    local texMin = 0.25 * zoom
    local texMax = 1 - 0.25 * zoom
    tex:SetTexCoord(texMin, texMax, texMin, texMax)
end

function KE:AddIconBorders(frame, color)
    local r, g, b, a = self:ResolveColor(color, { 0, 0, 0, 1 })
    frame.borders = {}
    frame._borderColor = { r, g, b, a }
    frame._borderParent = frame

    local function MakeBorder(point1, rel1, point2, rel2, w, h)
        local tex = frame:CreateTexture(nil, "OVERLAY", nil, 7)
        tex:SetColorTexture(r, g, b, a)
        tex:SetTexelSnappingBias(0)
        tex:SetSnapToPixelGrid(false)
        tex:SetPoint(point1, frame, rel1, 0, 0)
        tex:SetPoint(point2, frame, rel2, 0, 0)
        if w then tex:SetWidth(w) end
        if h then tex:SetHeight(h) end
        return tex
    end

    local px = KE:GetPixelSize()
    frame.borders.top    = MakeBorder("TOPLEFT", "TOPLEFT", "TOPRIGHT", "TOPRIGHT", nil, px)
    frame.borders.bottom = MakeBorder("BOTTOMLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT", nil, px)
    frame.borders.left   = MakeBorder("TOPLEFT", "TOPLEFT", "BOTTOMLEFT", "BOTTOMLEFT", px, nil)
    frame.borders.right  = MakeBorder("TOPRIGHT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT", px, nil)
    _KE_RegisterBorder(frame)
    _KE_DelayedBorderResnap(frame)
end

---------------------------------------------------------------------------------
-- Enhanced Borders (with optional borderParent for frame level control)
---------------------------------------------------------------------------------

function KE:AddBorders(frame, color, borderParent)
    if not frame then return end
    local cr, cg, cb, ca = self:ResolveColor(color, { 0, 0, 0, 1 })
    borderParent = borderParent or frame

    frame.borders = frame.borders or {}
    frame._borderColor = { cr, cg, cb, ca }
    frame._borderParent = borderParent

    local function CreateBorder(point1, point2, width, height)
        local tex = borderParent:CreateTexture(nil, "OVERLAY", nil, 7)
        tex:SetColorTexture(cr, cg, cb, ca)
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

    local px = KE:GetPixelSize()
    frame.borders.top = CreateBorder("TOPLEFT", "TOPRIGHT", nil, px)

    frame.borders.bottom = borderParent:CreateTexture(nil, "OVERLAY", nil, 7)
    frame.borders.bottom:SetHeight(px)
    frame.borders.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    frame.borders.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    frame.borders.bottom:SetColorTexture(cr, cg, cb, ca)
    frame.borders.bottom:SetTexelSnappingBias(0)
    frame.borders.bottom:SetSnapToPixelGrid(false)

    frame.borders.left = CreateBorder("TOPLEFT", "BOTTOMLEFT", px, nil)

    frame.borders.right = borderParent:CreateTexture(nil, "OVERLAY", nil, 7)
    frame.borders.right:SetWidth(px)
    frame.borders.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    frame.borders.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    frame.borders.right:SetColorTexture(cr, cg, cb, ca)
    frame.borders.right:SetTexelSnappingBias(0)
    frame.borders.right:SetSnapToPixelGrid(false)

    function frame:SetBorderColor(r, g, b, a)
        if not self.borders then return end
        self._borderColor = { r, g, b, a or 1 }
        for _, tex in pairs(self.borders) do
            tex:SetColorTexture(r, g, b, a or 1)
            -- SetColorTexture re-enables Blizzard's pixel-grid snap on the
            -- texture; re-assert so recolored borders stay crisp. (Formerly
            -- handled by the global TextureSnap hook — see Core/TextureSnap.lua.)
            tex:SetSnapToPixelGrid(false)
        end
    end

    _KE_RegisterBorder(frame)
    _KE_DelayedBorderResnap(frame)
    return frame
end


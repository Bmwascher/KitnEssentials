local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local hooksecurefunc = hooksecurefunc

local function SkinAttachment(btn)
    if not btn then return end
    if not S.data(btn).skinned then
        S.StripTextures(btn)
        S.Backdrop(btn)
        S.Hover(btn)
        if btn.IconBorder then S.IconBorder(btn.IconBorder, S.GetBackdrop(btn)) end
        S.data(btn).skinned = true
    end
    local icon = btn.icon or btn.Icon or (btn.GetNormalTexture and btn:GetNormalTexture())
    if icon then
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    end
end

-- Three numbered runs of attachment slots. The counts come from Blizzard's own
-- constants, with a fallback for the case where the mail UI has not loaded and
-- they are not defined yet.
local SEND_RUN = { prefix = "SendMailAttachment",       count = "ATTACHMENTS_MAX_SEND",    fallback = 12 }
local OPEN_RUN = { prefix = "OpenMailAttachmentButton", count = "ATTACHMENTS_MAX_RECEIVE", fallback = 16 }

local function SkinRun(run)
    for i = 1, (_G[run.count] or run.fallback) do
        SkinAttachment(_G[run.prefix .. i])
    end
end

-- Kept as separate entry points: each is hooked to its own Blizzard update.
local function SkinSendAttachments() SkinRun(SEND_RUN) end
local function SkinOpenAttachments() SkinRun(OPEN_RUN) end

-- Inbox rows wrap their attachment in a container that needs stripping too.
local function SkinInboxRows()
    for i = 1, (_G.INBOXITEMS_TO_DISPLAY or 7) do
        local item = _G["MailItem" .. i]
        if item then
            S.StripTextures(item)
            SkinAttachment(item.Button)
        end
    end
end

local function Skin()
    local frame = _G.MailFrame
    if not frame then return end
    S.Frame(frame)

    if _G.InboxFrame and _G.MailItem1 and _G.MailItem7 then
        local bd = S.Backdrop(_G.InboxFrame)
        if bd then
            bd:ClearAllPoints()
            bd:SetPoint("TOPLEFT", _G.MailItem1, "TOPLEFT")
            bd:SetPoint("BOTTOMRIGHT", _G.MailItem7, "BOTTOMRIGHT")
        end
    end

    if _G.InboxPrevPageButton then
        S.ArrowButton(_G.InboxPrevPageButton, "left")
        _G.InboxPrevPageButton:SetPoint("BOTTOMLEFT", 30, 100)
    end
    if _G.InboxNextPageButton then
        S.ArrowButton(_G.InboxNextPageButton, "right")
        _G.InboxNextPageButton:SetPoint("BOTTOMRIGHT", -80, 100)
    end

    S.Tabs("MailFrameTab", 2)

    if _G.SendMailScrollFrame then
        S.StripTextures(_G.SendMailScrollFrame, true)
        S.Backdrop(_G.SendMailScrollFrame)
        if _G.SendMailScrollFrame.ScrollBar then S.TrimScrollBar(_G.SendMailScrollFrame.ScrollBar) end
    end

    for _, name in next, { "SendMailNameEditBox", "SendMailSubjectEditBox",
        "SendMailMoneyGold", "SendMailMoneySilver", "SendMailMoneyCopper" } do
        if _G[name] then S.EditBox(_G[name]) end
    end
    if _G.SendMailMoneyBg then S.KillAllTextures(_G.SendMailMoneyBg) end
    if _G.SendMailMoneyInset then S.StripTextures(_G.SendMailMoneyInset) end

    if _G.SendMailNameEditBox and _G.SendMailFrame then
        _G.SendMailNameEditBox:ClearAllPoints()
        _G.SendMailNameEditBox:SetPoint("TOPLEFT", _G.SendMailFrame, "TOPLEFT", 90, -30)
        _G.SendMailNameEditBox:SetSize(109, 18)
    end
    if _G.SendMailSubjectEditBox and _G.SendMailNameEditBox then
        _G.SendMailSubjectEditBox:SetPoint("TOPLEFT", _G.SendMailNameEditBox, "BOTTOMLEFT", 0, -10)
        _G.SendMailSubjectEditBox:SetSize(214, 18)
    end
    if _G.SendMailFrame then S.StripTextures(_G.SendMailFrame) end

    SkinSendAttachments()
    SkinOpenAttachments()
    SkinInboxRows()

    if _G.SendMailFrame_Update then hooksecurefunc("SendMailFrame_Update", SkinSendAttachments) end
    if _G.OpenMail_Update then hooksecurefunc("OpenMail_Update", SkinOpenAttachments) end
    if _G.InboxFrame_Update then hooksecurefunc("InboxFrame_Update", SkinInboxRows) end

    if _G.SendMailMailButton then S.Button(_G.SendMailMailButton) end
    if _G.SendMailCancelButton then S.Button(_G.SendMailCancelButton) end
    if _G.SendMailSendMoneyButton then S.CheckBox(_G.SendMailSendMoneyButton) end
    if _G.SendMailCODButton then S.CheckBox(_G.SendMailCODButton) end
    if _G.SendMailSendMoneyButton and _G.SendMailMoney then
        _G.SendMailSendMoneyButton:ClearAllPoints()
        _G.SendMailSendMoneyButton:SetPoint("TOPRIGHT", _G.SendMailMoney, "TOPRIGHT", 30, 8)
    end

    if _G.OpenMailFrame then
        S.StripTextures(_G.OpenMailFrame, true)
        S.Backdrop(_G.OpenMailFrame)
    end
    if _G.OpenMailFrameInset then S.Inset(_G.OpenMailFrameInset) end
    if _G.OpenMailFrameCloseButton then S.CloseButton(_G.OpenMailFrameCloseButton) end
    for _, name in next, { "OpenMailReportSpamButton", "OpenMailReplyButton",
        "OpenMailDeleteButton", "OpenMailCancelButton", "OpenAllMail" } do
        if _G[name] then S.Button(_G[name]) end
    end

    if _G.InboxFrame then S.StripTextures(_G.InboxFrame) end
    if _G.MailFrameInset then S.Inset(_G.MailFrameInset) end

    if _G.OpenMailScrollFrame then
        S.StripTextures(_G.OpenMailScrollFrame, true)
        S.Backdrop(_G.OpenMailScrollFrame)
        if _G.OpenMailScrollFrame.ScrollBar then S.TrimScrollBar(_G.OpenMailScrollFrame.ScrollBar) end
    end

    -- Body fonts for the letter and the auction invoice.
    for _, name in next, { "InvoiceTextFontNormal", "MailTextFontNormal" } do
        local font = _G[name]
        if font then
            S.SetFont(font, 13)
            font:SetTextColor(1, 1, 1)
        end
    end
    if _G.OpenMailArithmeticLine then S.KillAllTextures(_G.OpenMailArithmeticLine) end

    for _, name in next, { "OpenMailLetterButton", "OpenMailMoneyButton" } do
        local btn = _G[name]
        if btn then
            S.StripTextures(btn)
            S.Backdrop(btn)
            S.Hover(btn)
            local icon = _G[name .. "IconTexture"]
            if icon then
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                icon:ClearAllPoints()
                icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
                icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
            end
        end
    end

    if _G.OpenMailReplyButton and _G.OpenMailDeleteButton then
        _G.OpenMailReplyButton:SetPoint("RIGHT", _G.OpenMailDeleteButton, "LEFT", -2, 0)
    end
    if _G.OpenMailDeleteButton and _G.OpenMailCancelButton then
        _G.OpenMailDeleteButton:SetPoint("RIGHT", _G.OpenMailCancelButton, "LEFT", -2, 0)
    end
    if _G.SendMailMailButton and _G.SendMailCancelButton then
        _G.SendMailMailButton:SetPoint("RIGHT", _G.SendMailCancelButton, "LEFT", -2, 0)
    end
end

S:RegisterEarly(Skin, "Mail")

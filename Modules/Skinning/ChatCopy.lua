-- ╔══════════════════════════════════════════════════════════╗
-- ║  ChatCopy.lua                                            ║
-- ║  Module: Chat (copy window)                              ║
-- ║  Purpose: The copy button on each chat frame and the     ║
-- ║           window it opens.                               ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

-- Re-opens the Chat module rather than creating one, so the moved methods keep
-- the same receiver and every existing call site works unedited.
local CHAT = KitnEssentials:GetModule("Chat")

local CreateFrame = CreateFrame
local UIParent = UIParent
local tinsert = tinsert
local format = format
local strlower = strlower
local gsub = string.gsub
local tconcat = table.concat
local math_max = math.max
local math_min = math.min
local C_Timer = C_Timer
local _G = _G
local Theme = KE.Theme

local COPY_FRAME_WIDTH = 700
local COPY_FRAME_HEIGHT = 300
local COPY_FRAME_BG = { 0.0627, 0.0627, 0.0627, 0.60 }
local COPY_TEX = "Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\chat_copy.png"

local copyLines = {}

local removeIconFromLine
do
    local raidIconFunc = function(x)
        x = x ~= "" and _G["RAID_TARGET_" .. x]
        return x and ("{" .. strlower(x) .. "}") or ""
    end
    local stripTextureFunc = function(w, x, y)
        if x == "" then return (w ~= "" and w) or (y ~= "" and y) or "" end
    end
    local hyperLinkFunc = function(w, _, y)
        if w ~= "" then return end
        return y
    end
    local fourString = function(v, w, x, y)
        return format("%s%s%s", v, w, (v and v == "1" and x) or y)
    end

    removeIconFromLine = function(text)
        if not text then return "" end
        text = gsub(text, [[|TInterface\TargetingFrame\UI%-RaidTargetingIcon_(%d+):0|t]], raidIconFunc)
        text = gsub(text, "(%s?)(|?)|[TA].-|[ta](%s?)", stripTextureFunc)
        text = gsub(text, "(|?)|H(.-)|h(.-)|h", hyperLinkFunc)
        text = gsub(text, "(%d+)(.-)|4(.-):(.-);", fourString)
        return text
    end
end

local function ColorizeLine(text, r, g, b)
    return format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, text)
end

function CHAT:GetChatLines(frame)
    if not frame or not frame.GetNumMessages then
        return 0
    end

    local numMessages = frame:GetNumMessages()
    if not numMessages or numMessages == 0 then
        return 0
    end

    local index = 1
    for i = 1, numMessages do
        local message, r, g, b = frame:GetMessageInfo(i)
        if message and not self:MessageIsProtected(message) then
            r, g, b = r or 1, g or 1, b or 1
            message = removeIconFromLine(message)
            message = ColorizeLine(message, r, g, b)
            copyLines[index] = message
            index = index + 1
        end
    end
    return index - 1
end

function CHAT:CopyChat(frame)
    if not self.CopyChatFrame then
        self:BuildCopyChatFrame()
    end

    if not self.CopyChatFrame then
        return
    end

    if self.CopyChatFrame:IsShown() then
        self.copyRawText = ""
        self.CopyChatFrameEditBox:SetText("")
        self.CopyChatFrame:Hide()
    else
        local count = self:GetChatLines(frame)
        if count > 0 then
            local text = tconcat(copyLines, " \n", 1, count)
            self.copyRawText = text
            self.CopyChatFrameEditBox:SetText(text)
        else
            self.copyRawText = ""
            self.CopyChatFrameEditBox:SetText("")
        end
        self.CopyChatFrame:Show()
        -- Default to everything selected -- open, Ctrl+C, done.
        self.CopyChatFrameEditBox:SetFocus()
        self.CopyChatFrameEditBox:HighlightText()
    end
end

function CHAT:CopyChatEditBox_OnEscapePressed()
    CHAT.CopyChatFrame:Hide()
end

function CHAT:BuildCopyChatFrame()
    if self.CopyChatFrame then return end

    local HEADER_HEIGHT = 32
    local SCROLLBAR_WIDTH = 10
    local CONTENT_PADDING = 8

    local frame = CreateFrame("Frame", "KE_CopyChatFrame", UIParent, "BackdropTemplate")
    tinsert(_G.UISpecialFrames, "KE_CopyChatFrame")
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1, })
    frame:SetBackdropColor(COPY_FRAME_BG[1], COPY_FRAME_BG[2], COPY_FRAME_BG[3], COPY_FRAME_BG[4])
    frame:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
    frame:SetSize(COPY_FRAME_WIDTH, COPY_FRAME_HEIGHT)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    frame:Hide()
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetResizable(true)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    -- The header used to register the drag as well, and the two handed the
    -- drag back and forth: a start re-anchors the window to the cursor, the
    -- jump carries the pointer across the header's lower edge, the frame
    -- losing the pointer ends its drag and the one gaining it starts
    -- another, which jumps again. One drag was measured as thirteen
    -- start/stop pairs alternating between the two. The header is mouse-free
    -- now, so this frame is the only drag source and there is nothing to
    -- hand off to; its close button keeps its own mouse and is unaffected.
    --
    -- The guard below is belt and braces against any other repeat start.
    -- OnHide clears the flag: a window closed mid-drag never reaches
    -- OnDragStop, and a flag left set would swallow the next drag entirely.
    local function StartDrag()
        if frame.isMoving then return end
        frame.isMoving = true
        frame:StartMoving()
    end
    local function StopDrag()
        if not frame.isMoving then return end
        frame.isMoving = false
        frame:StopMovingOrSizing()
    end

    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", StartDrag)
    frame:SetScript("OnDragStop", StopDrag)
    frame:SetScript("OnHide", StopDrag)
    self.CopyChatFrame = frame

    local header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    header:SetHeight(HEADER_HEIGHT)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    header:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    header:SetBackdropColor(COPY_FRAME_BG[1], COPY_FRAME_BG[2], COPY_FRAME_BG[3], COPY_FRAME_BG[4])
    frame.header = header

    local headerBorder = header:CreateTexture(nil, "BORDER")
    headerBorder:SetHeight(1)
    headerBorder:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    headerBorder:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    headerBorder:SetColorTexture(Theme.border[1], Theme.border[2], Theme.border[3], 1)

    local title = header:CreateFontString(nil, "OVERLAY")
    title:SetPoint("LEFT", header, "LEFT", 12, 0)
    title:SetPoint("RIGHT", header, "RIGHT", -34, 0)
    title:SetJustifyH("CENTER")
    title:SetFont(CHAT.cachedFontPath, 14, "OUTLINE")
    title:SetText("Chat Copy")
    title:SetTextColor(1, 1, 1, 1)
    title:SetShadowColor(0, 0, 0, 0)
    frame.title = title

    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -6, 0)

    local closeTex = closeBtn:CreateTexture(nil, "ARTWORK")
    closeTex:SetAllPoints()
    closeTex:SetTexture("Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\KitnCustomCrossv3.png")
    closeTex:SetRotation(math.rad(45))
    closeTex:SetVertexColor(0.851, 0.851, 0.851, 1)
    closeTex:SetTexelSnappingBias(0)
    closeTex:SetSnapToPixelGrid(false)

    closeBtn:SetScript("OnEnter", function()
        closeTex:SetVertexColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    end)
    closeBtn:SetScript("OnLeave", function()
        closeTex:SetVertexColor(0.851, 0.851, 0.851, 1)
    end)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    frame.closeButton = closeBtn

    local hint = header:CreateFontString(nil, "OVERLAY")
    hint:SetFont(CHAT.cachedFontPath, 13, "OUTLINE")
    hint:SetPoint("RIGHT", closeBtn, "LEFT", -12, 0)
    do
        local a = Theme.accent
        local hex = format("%02x%02x%02x", (a[1] or 1) * 255, (a[2] or 1) * 255, (a[3] or 1) * 255)
        hint:SetFormattedText("Press |cff%sCtrl+C|r to copy", hex)
    end
    hint:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 0.8)
    frame.hint = hint

    local contentArea = CreateFrame("Frame", nil, frame)
    contentArea:SetPoint("TOPLEFT", frame, "TOPLEFT", CONTENT_PADDING, -HEADER_HEIGHT - CONTENT_PADDING)
    contentArea:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -CONTENT_PADDING, CONTENT_PADDING)
    frame.contentArea = contentArea

    local scrollbar = CreateFrame("Slider", nil, contentArea, "BackdropTemplate")
    scrollbar:SetWidth(SCROLLBAR_WIDTH)
    scrollbar:SetPoint("TOPRIGHT", contentArea, "TOPRIGHT", 0, 0)
    scrollbar:SetPoint("BOTTOMRIGHT", contentArea, "BOTTOMRIGHT", 0, 0)
    scrollbar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1, })
    scrollbar:SetBackdropColor(COPY_FRAME_BG[1], COPY_FRAME_BG[2], COPY_FRAME_BG[3], 0.5)
    scrollbar:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
    scrollbar:SetOrientation("VERTICAL")
    scrollbar:SetMinMaxValues(0, 1)
    scrollbar:SetValue(0)
    scrollbar:Hide()
    frame.scrollbar = scrollbar

    local thumb = scrollbar:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(SCROLLBAR_WIDTH - 2, 40)
    -- Theme lookup first, literal only as a fallback: dropping the lookup
    -- ships a hardcoded colour instead of KE's accent.
    local brand = (KE.GetThemeColor and KE:GetThemeColor("accent")) or { 1.0, 0.0, 0.549 }
    thumb:SetColorTexture(brand[1], brand[2], brand[3], 0.8)
    scrollbar:SetThumbTexture(thumb)
    scrollbar.thumb = thumb

    local scrollFrame = CreateFrame("ScrollFrame", "KE_CopyChatScrollFrame", contentArea)
    scrollFrame:SetPoint("TOPLEFT", contentArea, "TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", contentArea, "BOTTOMRIGHT", 0, 0)
    self.CopyChatScrollFrame = scrollFrame

    local editBox = CreateFrame("EditBox", "KE_CopyChatFrameEditBox", scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetMaxLetters(99999)
    editBox:EnableMouse(true)
    editBox:SetAutoFocus(false)
    editBox:SetFont(CHAT.cachedFontPath, 15, "OUTLINE")
    editBox:SetShadowColor(0, 0, 0, 0)
    editBox:SetShadowOffset(0, 0)
    editBox:SetTextColor(Theme.textPrimary[1], Theme.textPrimary[2], Theme.textPrimary[3], 1)
    editBox:SetScript("OnEscapePressed", self.CopyChatEditBox_OnEscapePressed)
    self.CopyChatFrameEditBox = editBox

    scrollFrame:SetScrollChild(editBox)
    editBox:SetWidth(scrollFrame:GetWidth())
    editBox:SetHeight(COPY_FRAME_HEIGHT)

    scrollbar:SetScript("OnValueChanged", function(_, value) scrollFrame:SetVerticalScroll(value) end)

    scrollFrame:SetScript("OnScrollRangeChanged", function(_, _, yRange)
        if yRange and yRange > 0 then
            scrollbar:Show()
            scrollbar:SetMinMaxValues(0, yRange)
            scrollFrame:SetPoint("BOTTOMRIGHT", contentArea, "BOTTOMRIGHT", -SCROLLBAR_WIDTH - 4, 0)
        else
            scrollbar:Hide()
            scrollbar:SetMinMaxValues(0, 0)
            scrollFrame:SetPoint("BOTTOMRIGHT", contentArea, "BOTTOMRIGHT", 0, 0)
        end
        editBox:SetWidth(scrollFrame:GetWidth())
    end)

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(_, delta)
        local current = scrollbar:GetValue()
        local _, maxVal = scrollbar:GetMinMaxValues()
        local step = 40
        local newVal = current - (delta * step)
        newVal = math_max(0, math_min(maxVal, newVal))
        scrollbar:SetValue(newVal)
    end)

    -- Read-only: any user edit (typing, paste, delete) synchronously
    -- restores the canonical snapshot and re-selects all. Selection and
    -- Ctrl+C keep working since the box stays enabled.
    local restoring = false
    editBox:SetScript("OnTextChanged", function(eb, userInput)
        if restoring then return end
        if userInput then
            restoring = true
            eb:SetText(CHAT.copyRawText or "")
            restoring = false
            eb:HighlightText()
            return
        end
        C_Timer.After(0.01, function()
            local _, maxVal = scrollbar:GetMinMaxValues()
            scrollbar:SetValue(maxVal)
        end)
    end)

    scrollFrame:SetScript("OnSizeChanged", function() editBox:SetWidth(scrollFrame:GetWidth()) end)

    frame:SetScript("OnShow", function()
        editBox:SetWidth(scrollFrame:GetWidth())
    end)

    -- Clicking anywhere in the window focuses the editbox, so Ctrl+A
    -- (native select-all while focused) always works.
    frame:SetScript("OnMouseDown", function()
        editBox:SetFocus()
    end)

    -- No keyboard grab. This used EnableKeyboard(true) plus an OnKeyDown
    -- calling SetPropagateKeyboardInput, which is PROTECTED IN COMBAT:
    --
    --   [ADDON_ACTION_BLOCKED] tried to call the protected function
    --   'KE_CopyChatFrame:SetPropagateKeyboardInput()'
    --
    -- and because the frame was holding the keyboard, the blocked call
    -- meant propagation was never restored -- keys stopped reaching the
    -- game while the window was open. The frame is registered in
    -- UISpecialFrames above, which is Blizzard's own Escape-to-close
    -- mechanism and needs no keyboard grab at all.
end

function CHAT:CreateCopyButton(chat)
    if chat.copyButton then chat.copyButton:Show(); return end
    if _G.IsCombatLog and _G.IsCombatLog(chat) then return end

    local id = chat:GetID()
    local copyButton = CreateFrame("Frame", format("KE_CopyChatButton%d", id), chat)
    copyButton:EnableMouse(true)
    copyButton:SetSize(20, 22)
    copyButton:SetPoint("TOPRIGHT", chat, "TOPRIGHT", 4, 6)
    copyButton:SetFrameLevel(chat:GetFrameLevel() + 5)
    chat.copyButton = copyButton

    -- Accent-independent (always white), so the hover states below only change
    -- alpha. The art is already upright, so there is no rotation.
    local icon = copyButton:CreateTexture(nil, "OVERLAY")
    icon:SetSize(14, 14)
    icon:SetPoint("CENTER", copyButton, "CENTER", 0, 0)
    icon:SetTexture(COPY_TEX)
    icon:SetTexelSnappingBias(0)
    icon:SetSnapToPixelGrid(false)
    copyButton.icon = icon

    icon:SetVertexColor(1, 1, 1, 0.5)

    copyButton:SetScript("OnMouseUp", function(btn, mouseBtn)
        if mouseBtn == "LeftButton" then
            local chatFrame = btn:GetParent()
            if chatFrame.isDocked and _G.GeneralDockManager then
                chatFrame = _G.GeneralDockManager.selected or chatFrame
            end
            CHAT:CopyChat(chatFrame)
        end
    end)
    copyButton:SetScript("OnEnter", function() icon:SetVertexColor(1, 1, 1, 1) end)
    copyButton:SetScript("OnLeave", function() icon:SetVertexColor(1, 1, 1, 0.5) end)
end

-- ╔══════════════════════════════════════════════════════════╗
-- ║  Chat.lua                                                ║
-- ║  Module: Chat                                            ║
-- ║  Purpose: Chat panel backdrop, positioning, and           ║
-- ║           lifecycle.                                      ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local CHAT = KitnEssentials:NewModule("Chat", "AceEvent-3.0", "AceHook-3.0")

-- Styling applies destructively to Blizzard chat frames at enable and
-- OnDisable has no frame teardown, same as the Skin* modules; the name
-- doesn't match ProfileManager's "^Skin" test, so opt in explicitly.
CHAT.keDeferToReload = true

local CreateFrame = CreateFrame
local UIParent = UIParent
local ipairs = ipairs
local pairs = pairs
local select = select
local type = type
local pcall = pcall
local unpack = unpack
local tinsert = tinsert
local tremove = tremove
local gsub = string.gsub
local strmatch = string.match
local strfind = string.find
local strupper = strupper
local strlower = strlower
local strsub = strsub
local format = format
local time = time
local wipe = wipe
local hooksecurefunc = hooksecurefunc
local Mixin = Mixin
local BackdropTemplateMixin = BackdropTemplateMixin
local InCombatLockdown = InCombatLockdown
local IsAltKeyDown = IsAltKeyDown
local IsShiftKeyDown = IsShiftKeyDown
local GetCVar = GetCVar
local GetRealmName = GetRealmName
local GetPlayerInfoByGUID = GetPlayerInfoByGUID
local GetServerTime = GetServerTime
local PlaySound = PlaySound
local GameTooltip = GameTooltip
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local _G = _G

-- Blizzard globals not on KE's read_globals allowlist -- read through _G.
-- per family convention rather than growing .luacheckrc for this port.
local BetterDate = (_G.TimeUtil and _G.TimeUtil.BetterDate) or _G.BetterDate
local SOUND_U_CHAT_SCROLL_BUTTON = (_G.SOUNDKIT and _G.SOUNDKIT.U_CHAT_SCROLL_BUTTON) or 1115

local PANEL_HEIGHT = 250
local PANEL_WIDTH = 450
local PANEL_FRAME_LEVEL = 300
local EDITBOX_HEIGHT = 22
local CHAT_FRAME_LEVEL = 4
local BASE_OFFSET = 35
local PADDING = 5
local H_PADDING = 5
local TAB_HEIGHT = 22
local GUID_CACHE_MAX = 500

local IGNORE_FRAMES = { [2] = "CombatLog", [3] = "Voice", }
local TAB_TEXTURES = { "", "Selected", "Active", "Highlight" }

local TAB_STYLES = {
    NONE   = "%s",
    ARROW  = "%s>|r%s%s<|r",
    ARROW1 = "%s>|r %s %s<|r",
    ARROW2 = "%s<|r%s%s>|r",
    ARROW3 = "%s<|r %s %s>|r",
    BOX    = "%s[|r%s%s]|r",
    BOX1   = "%s[|r %s %s]|r",
    CURLY  = "%s{|r%s%s}|r",
    CURLY1 = "%s{|r %s %s}|r",
    CURVE  = "%s(|r%s%s)|r",
    CURVE1 = "%s(|r %s %s)|r",
}

local HYPERLINK_TYPES = {
    achievement = true,
    apower = true,
    currency = true,
    enchant = true,
    glyph = true,
    instancelock = true,
    item = true,
    keystone = true,
    quest = true,
    spell = true,
    talent = true,
    unit = true,
}

local BLIZZ_FRAME_KEYS = {
    'Inset', 'inset', 'InsetFrame', 'LeftInset', 'RightInset',
    'NineSlice', 'BG', 'Bg', 'border', 'Border', 'Background',
    'BorderFrame', 'bottomInset', 'BottomInset', 'bgLeft', 'bgRight',
    'FilligreeOverlay', 'PortraitOverlay', 'ArtOverlayFrame',
    'Portrait', 'portrait', 'ScrollFrameBorder',
}

local SHORT_CHANNELS = {
    GUILD = "G",
    PARTY = "P",
    RAID = "R",
    OFFICER = "O",
    INSTANCE_CHAT = "I",
}

local CLOSE_BUTTONS = {}
do
    CLOSE_BUTTONS[_G.CLOSE_CHAT_CONVERSATION_WINDOW or "Close Conversation Window"] = true
    CLOSE_BUTTONS[_G.CLOSE_CHAT_WHISPER_WINDOW or "Close Whisper Window"] = true
    CLOSE_BUTTONS[_G.CLOSE_CHAT_WINDOW or "Close Window"] = true
end

local BLANK_TEX = "Interface\\Buttons\\WHITE8x8"
local ARROW_TEX = "Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\collapse.tga"

local BACKDROP_TEMPLATE = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1, }

local SHORT_CHANNEL_NAMES = {
    { global = "CHAT_RAID_WARNING_GET",  short = "RW" },
    { global = "CHAT_INSTANCE_CHAT_GET", short = "I" },
    { global = "CHAT_PARTY_GET",         short = "P" },
    { global = "CHAT_RAID_GET",          short = "R" },
    { global = "CHAT_GUILD_GET",         short = "G" },
    { global = "CHAT_OFFICER_GET",       short = "O" },
}

local SHORT_CHANNEL_PATTERNS
local function BuildShortChannelPatterns()
    if SHORT_CHANNEL_PATTERNS then return end
    SHORT_CHANNEL_PATTERNS = {}

    for _, info in ipairs(SHORT_CHANNEL_NAMES) do
        local formatStr = _G[info.global]
        if formatStr then
            local bracketText = strmatch(formatStr, "(%[.-%])")
            if bracketText then
                local escapedPattern = gsub(bracketText, "([%[%]%-])", "%%%1")
                tinsert(SHORT_CHANNEL_PATTERNS,
                    { pattern = "^" .. escapedPattern, replacement = "[" .. info.short .. "]" })
            end
        end
    end
end

local function NormalizeFontOutline(outline)
    if not outline or outline == "NONE" then return "" end
    return outline
end

-- Cached values to avoid repeated lookups; refreshed in UpdateDB.
local cachedFontPath
local cachedTabAccentColor = { r = 1, g = 0.82, b = 0 }

CHAT.ChatWindow = nil
CHAT.ClassNames = {}
CHAT.originalStates = {}
CHAT.GuidCache = {}
CHAT.GuidCacheCount = 0

local canChangeMessage = function(arg1, id)
    if id and arg1 == "" then return id end
end

local communityAbbrevCache = {}

-- BNet whisper class colors (ElvUI-exact resolution): BN whisper events
-- carry no senderGUID, so Blizzard's secure class-color path never fires
-- for them. Resolve via the C_BattleNet friend APIs instead and color the
-- display text ourselves.
local bnClassTokens
local function BNClassToken(localizedName)
    if not localizedName or localizedName == "" then return nil end
    if not bnClassTokens then
        bnClassTokens = {}
        for token, loc in pairs(_G.LOCALIZED_CLASS_NAMES_MALE or {}) do bnClassTokens[loc] = token end
        for token, loc in pairs(_G.LOCALIZED_CLASS_NAMES_FEMALE or {}) do bnClassTokens[loc] = token end
    end
    return bnClassTokens[localizedName]
end

local function BNFirstToonClassName(id)
    if not id then return end
    for i = 1, (_G.BNGetNumFriends() or 0) do
        local info = _G.C_BattleNet.GetFriendAccountInfo(i)
        if info and info.bnetAccountID == id then
            for y = 1, (_G.C_BattleNet.GetFriendNumGameAccounts(i) or 0) do
                local gameInfo = _G.C_BattleNet.GetFriendGameAccountInfo(i, y)
                if gameInfo and gameInfo.clientProgram == _G.BNET_CLIENT_WOW
                    and gameInfo.className and gameInfo.className ~= "" then
                    return gameInfo.className
                end
            end
            break
        end
    end
end

local function BNClassColorStr(id)
    local info = _G.C_BattleNet.GetAccountInfoByID(id)
    local gameInfo = info and info.gameAccountID and _G.C_BattleNet.GetGameAccountInfoByID(info.gameAccountID)
    local className = (gameInfo and gameInfo.className) or BNFirstToonClassName(id)
    local token = BNClassToken(className)
    local color = token and (_G.CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[token]
    return color and color.colorStr
end

local function ColorizeBNSenders(msg)
    -- Link data fields (name:bnetIDAccount:lineID:chatType:chatTarget)
    -- contain |K-escaped names with PIPES in both the name and the
    -- chatTarget field, so the link body must be matched lazily up to
    -- its |h terminator and the account ID extracted in a second step.
    return (gsub(msg, "(|HBNplayer:(.-)|h)%[(.-)%]|h", function(link, data, display)
        if strfind(display, "|c", 1, true) then return nil end -- already colored; nil keeps original
        local id = strmatch(data, "^[^:]*:(%d+)")
        if not id then return nil end
        local ok, colorStr = pcall(BNClassColorStr, tonumber(id))
        if not ok or not colorStr then return nil end
        return format("%s[|c%s%s|r]|h", link, colorStr, display)
    end))
end

local function SafeSetupTextureCoordinates(frame)
    local width, height = CHAT:SafeSize(frame)
    if width and height and width > 0 and height > 0 then BackdropTemplateMixin.SetupTextureCoordinates(frame) end
end

local function ReplaceSetupTextureCoordinates(frame)
    if frame.SetupTextureCoordinates and frame.SetupTextureCoordinates ~= SafeSetupTextureCoordinates then
        frame.SetupTextureCoordinates = SafeSetupTextureCoordinates
    end
end

local function GetTemplateColors(template)
    local backdropR, backdropG, backdropB, backdropA = 0.1, 0.1, 0.1, 0.9
    local borderR, borderG, borderB, borderA = 0, 0, 0, 1

    if template == "Transparent" then backdropA = 0.8 end

    return backdropR, backdropG, backdropB, backdropA, borderR, borderG, borderB, borderA
end

function CHAT:UpdateDB()
    self.db = KE.db.profile.Skinning.Chat
    cachedFontPath = KE:GetFontPath(self.db.FontFace)
    local customColor = self.db.TabTextColor
    if customColor then
        cachedTabAccentColor.r = customColor.r or 1
        cachedTabAccentColor.g = customColor.g or 0.82
        cachedTabAccentColor.b = customColor.b or 0
    end
end

function CHAT:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
    BuildShortChannelPatterns()
end

function CHAT:OnEnable()
    if KE:ShouldNotLoadModule() then return end
    if not self.db.Enabled then return end
    self:UpdateDB()
    self:CreateChatPanel()

    self:SetupChat()
    self:RegisterEvent("UPDATE_CHAT_WINDOWS", "SetupChat")
    self:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS", "SetupChat")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "RefreshDockPosition")
    self:RegisterEvent("CVAR_UPDATE", "OnCVAR_UPDATE")

    if _G.Blizzard_CombatLog_Update_QuickButtons then
        self:SecureHook("Blizzard_CombatLog_Update_QuickButtons", "StyleCombatLog")
    else
        self:RegisterEvent("ADDON_LOADED", function(_, addon)
            if addon == "Blizzard_CombatLog" then
                self:StyleCombatLog()
                if _G.Blizzard_CombatLog_Update_QuickButtons then
                    self:SecureHook("Blizzard_CombatLog_Update_QuickButtons", "StyleCombatLog")
                end
            end
        end)
    end
end

function CHAT:OnDisable()
    if self.panel then self.panel:Hide() end
end

function CHAT:CreateChatPanel()
    if self.panel then
        self.panel:Show()
        if self.panel.backdrop then self.panel.backdrop:Show() end
        self:UpdatePanel()
        return
    end

    local db = self.db
    local panel = CreateFrame("Frame", "KE_ChatPanel", UIParent)
    panel:SetSize(db.Width or PANEL_WIDTH, db.Height or PANEL_HEIGHT)
    KE:ApplyFramePosition(panel, db.Position, db)
    panel:SetFrameStrata("BACKGROUND")
    panel:SetFrameLevel(PANEL_FRAME_LEVEL)
    panel:SetClampedToScreen(true)
    self.panel = panel

    local backdrop = CreateFrame("Frame", "KE_ChatPanelBackdrop", panel, "BackdropTemplate")
    backdrop:SetFrameLevel(panel:GetFrameLevel() - 1)
    backdrop:SetAllPoints(panel)
    panel.backdrop = backdrop
    self:ApplyBackdrop(backdrop)

    local tabBackdrop = CreateFrame("Frame", "KE_ChatTabBackdrop", panel, "BackdropTemplate")
    tabBackdrop:SetFrameLevel(panel:GetFrameLevel() + 1)
    self.tabBackdrop = tabBackdrop
    self:UpdateTabBackdrop()
end

function CHAT:UpdateTabBackdrop()
    if not self.tabBackdrop then return end

    local db = self.db
    local tabBackdrop = self.tabBackdrop

    tabBackdrop:ClearAllPoints()
    tabBackdrop:SetPoint("TOPLEFT", self.panel, "TOPLEFT", 0, 0)
    tabBackdrop:SetPoint("BOTTOMRIGHT", self.panel, "TOPRIGHT", 0, -TAB_HEIGHT)

    local tabBgColor = db.TabBackdrop and db.TabBackdrop.Color or { 0, 0, 0, 0.5 }
    local tabBorderColor = db.TabBackdrop and db.TabBackdrop.BorderColor or { 0, 0, 0, 1 }
    local tabBackdropEnabled = db.TabBackdrop and db.TabBackdrop.Enabled

    tabBackdrop:SetBackdrop(BACKDROP_TEMPLATE)

    if tabBackdropEnabled then
        tabBackdrop:SetBackdropColor(tabBgColor[1], tabBgColor[2], tabBgColor[3], tabBgColor[4] or 0.5)
        tabBackdrop:SetBackdropBorderColor(tabBorderColor[1], tabBorderColor[2], tabBorderColor[3],
            tabBorderColor[4] or 1)
        tabBackdrop:Show()
    else
        tabBackdrop:Hide()
    end
end

function CHAT:ApplyBackdrop(backdrop)
    local db = self.db

    backdrop:SetBackdrop(BACKDROP_TEMPLATE)

    if db.Backdrop.Enabled ~= false then
        backdrop:SetBackdropColor(db.Backdrop.Color[1], db.Backdrop.Color[2], db.Backdrop.Color[3],
            db.Backdrop.Color[4] or 0.6)
        backdrop:SetBackdropBorderColor(db.Backdrop.BorderColor[1], db.Backdrop.BorderColor[2],
            db.Backdrop.BorderColor[3], db.Backdrop.BorderColor[4] or 1)
        backdrop:Show()
    else
        backdrop:SetBackdropColor(0, 0, 0, 0)
        backdrop:SetBackdropBorderColor(0, 0, 0, 0)
    end
end

function CHAT:SetBackgroundVisible(background, show)
    if not background then return end

    if show then
        background.Show = nil
        background:Show()
    else
        background:Hide()
        background.Show = background.Hide
    end
end

function CHAT:GetAnchorParent(anchor, chat)
    if not anchor then return end

    local _, relativeTo = chat:GetPoint()
    if relativeTo == anchor then return anchor:GetParent() end
end

function CHAT:IsFloating(chat, docker)
    if not docker then docker = _G.GeneralDockManager.primary end

    local primaryUndocked = docker ~= self.ChatWindow
    return not chat.isDocked or (primaryUndocked and ((chat == docker) or self:GetAnchorParent(docker, chat)))
end

------------------------------------------------------------------------
-- Chat setup, tab styling and docking (Task 3)
------------------------------------------------------------------------

local ChatEditSetLastActiveWindow = (_G.ChatFrameUtil and _G.ChatFrameUtil.SetLastActiveWindow) or
    _G.ChatEdit_SetLastActiveWindow

function CHAT:GetTab(chat)
    if not chat then return end
    if not chat.tab then chat.tab = _G["ChatFrame" .. chat:GetID() .. "Tab"] end
    return chat.tab
end

function CHAT:GetCombatLog()
    local LOG = _G.COMBATLOG
    if LOG then return LOG, self:GetTab(LOG) end
end

function CHAT:ShouldIgnoreFrame(chat)
    if not chat then return true end
    local id = chat:GetID()
    return IGNORE_FRAMES[id] ~= nil
end

function CHAT:IsChatValid(chat)
    if not chat then return false end
    if self:ShouldIgnoreFrame(chat) then return false end
    if _G.IsCombatLog and _G.IsCombatLog(chat) then return false end
    return true
end

-- Fires on chat activity. Cheap (one table lookup per frame) and it
-- closes the gap for any window created by a path we do not hook: if a
-- frame is in CHAT_FRAMES without our AddMessage, style it now.
function CHAT:OnChatMessage(frame)
    if not self.panel or not frame then return end
    if frame.OldAddMessage or self:ShouldIgnoreFrame(frame) then return end
    self:StyleChat(frame)
end

function CHAT:SetupChat()
    if not self.panel then return end

    for _, frameName in ipairs(_G.CHAT_FRAMES) do
        local chat = _G[frameName]
        if chat then
            self:StyleChat(chat)
            local eb = chat.editBox
            if eb and eb.SetFont then
                eb:SetFont(cachedFontPath, self.db.EditBoxFontSize or 14, NormalizeFontOutline(self.db.FontOutline))
            end
            if _G.FCFTab_UpdateAlpha then _G.FCFTab_UpdateAlpha(chat) end
        end
    end

    self:PositionChats()
    self:SetupDockManager()
    self:UpdateChatTabs()
    self:UpdateEditboxAnchors()
    self:StyleCombatLog()

    if _G.TextToSpeechButtonFrame then _G.TextToSpeechButtonFrame:Hide() end
    if _G.TextToSpeechButton then _G.TextToSpeechButton:Hide() end
    if _G.QuickJoinToastButton then _G.QuickJoinToastButton:Hide() end
    if _G.ChatFrameMenuButton then _G.ChatFrameMenuButton:Hide() end
    if _G.ChatFrameChannelButton then _G.ChatFrameChannelButton:Hide() end
    if _G.ChatFrameToggleVoiceDeafenButton then _G.ChatFrameToggleVoiceDeafenButton:Hide() end
    if _G.ChatFrameToggleVoiceMuteButton then _G.ChatFrameToggleVoiceMuteButton:Hide() end

    if not self.hooksSecured then
        self:SecureHook("FCF_OpenTemporaryWindow", "SetupChat")
        if type(_G.FCF_OpenNewWindow) == "function" then
            self:SecureHook("FCF_OpenNewWindow", "SetupChat")
        end
        if type(_G.FCF_SetWindowName) == "function" then
            self:SecureHook("FCF_SetWindowName", "SetupChat")
        end
        if type(_G.ChatFrame_MessageEventHandler) == "function" then
            self:SecureHook("ChatFrame_MessageEventHandler", "OnChatMessage")
        end
        self:SecureHook("FCF_SavePositionAndDimensions", "OnDockStateChanged")
        self:SecureHook("FCF_DockFrame", "OnDockStateChanged")
        self:SecureHook("FCF_UnDockFrame", "OnDockStateChanged")
        self:SecureHook("FCF_ResetChatWindows", "OnFCF_ResetChatWindows")
        self:SecureHook("FCF_SetButtonSide", "OnFCF_SetButtonSide")
        self:SecureHook("FCF_Close", "OnFCF_Close")
        self:SecureHook("FCF_SetWindowAlpha", "OnFCF_SetWindowAlpha")
        self:SecureHook("FCF_SetChatWindowFontSize", "OnFCF_SetChatWindowFontSize")
        self:SecureHook("FCFTab_UpdateColors", "OnFCFTab_UpdateColors")
        self:SecureHook("FCFDock_SelectWindow", "OnFCFDock_SelectWindow")
        self:SecureHook("FCFDock_ScrollToSelectedTab", "OnFCFDock_ScrollToSelectedTab")
        self:SecureHook("RedockChatWindows", "OnRedockChatWindows")

        if _G.ChatFrameUtil then
            self:SecureHook(_G.ChatFrameUtil, "ActivateChat", "OnChatEdit_ActivateChat")
            self:SecureHook(_G.ChatFrameUtil, "DeactivateChat", "OnChatEdit_DeactivateChat")
            self:SecureHook(_G.ChatFrameUtil, "SetLastActiveWindow", "OnChatEdit_SetLastActiveWindow")
        else
            self:SecureHook("ChatEdit_ActivateChat", "OnChatEdit_ActivateChat")
            self:SecureHook("ChatEdit_DeactivateChat", "OnChatEdit_DeactivateChat")
            self:SecureHook("ChatEdit_SetLastActiveWindow", "OnChatEdit_SetLastActiveWindow")
        end

        if _G.FCFDockOverflowButton_UpdatePulseState then
            self:SecureHook("FCFDockOverflowButton_UpdatePulseState",
                "OnFCFDockOverflowButton_UpdatePulseState")
        end
        if _G.UIDropDownMenu_AddButton then self:SecureHook("UIDropDownMenu_AddButton", "OnUIDropDownMenu_AddButton") end
        if _G.GetPlayerInfoByGUID then self:SecureHook("GetPlayerInfoByGUID", "OnGetPlayerInfoByGUID") end
        if _G.ChatEdit_OnEnterPressed then self:SecureHook("ChatEdit_OnEnterPressed", "OnChatEdit_OnEnterPressed") end
        if _G.ChatEdit_UpdateHeader then self:SecureHook("ChatEdit_UpdateHeader", "OnChatEdit_UpdateHeader") end

        self.hooksSecured = true
    end
end

function CHAT:OnCVAR_UPDATE(_, cvar, value)
    if cvar == "chatStyle" then self:UpdateEditboxAnchors() end
    if cvar == "whisperMode" and value ~= "inline" then
        C_Timer.After(0, function() C_CVar.SetCVar("whisperMode", "inline") end)
    end
end

function CHAT:ClearSnapReference(chat)
    if chat == self.ChatWindow then
        self.ChatWindow = nil
        if self.db then self.db.panelSnapID = nil end
    end
end

function CHAT:ResetPanelSnap()
    self.ChatWindow = nil
    if self.db then self.db.panelSnapID = nil end
end

function CHAT:OnDockStateChanged(chat)
    if self.isPositioning then return end

    self:ClearSnapReference(chat)

    if chat == _G.GeneralDockManager.primary then
        for _, frame in ipairs(_G.GeneralDockManager.DOCKED_CHAT_FRAMES) do self:PositionChat(frame) end
    else
        self:PositionChat(chat)
    end
end

function CHAT:RefreshDockPosition(event, isInitialLogin, isReloadingUi)
    if event == "PLAYER_ENTERING_WORLD" and (isInitialLogin or isReloadingUi) then return end
    local docker = _G.GeneralDockManager and _G.GeneralDockManager.primary
    if docker then self:OnDockStateChanged(docker) end
end

function CHAT:GetPanelAnchoredChat()
    if self.ChatWindow then return self.ChatWindow end

    local docker = _G.GeneralDockManager and _G.GeneralDockManager.primary
    if not docker or not self.db then return end

    local savedSnapID = self.db.panelSnapID

    for index, frameName in ipairs(_G.CHAT_FRAMES) do
        local chat = _G[frameName]
        if chat and ((chat.isDocked and chat == docker) or (not chat.isDocked and chat:IsShown())) then
            if savedSnapID and savedSnapID == index then
                self.ChatWindow = chat
                return chat
            elseif not savedSnapID then
                if self:FrameOverlapsPanel(chat) then
                    self.db.panelSnapID = index
                    self.ChatWindow = chat
                    return chat
                elseif chat == docker then
                    self.db.panelSnapID = index
                    self.ChatWindow = chat
                    return chat
                end
            end
        end
    end
end

-- Secret-safe geometry reads (ported inline from the reference's skinning
-- API): a frame that came from Blizzard can return secret values from
-- GetRect/GetSize while a secret-value restriction is active, so callers
-- degrade to "skip the adjustment" rather than throwing.
function CHAT:SafeRect(frame)
    if not (frame and frame.GetRect) then return nil end

    local l, b, w, h = frame:GetRect()
    if not l then return nil end
    if KE:IsSecretValue(l) or KE:IsSecretValue(b)
        or KE:IsSecretValue(w) or KE:IsSecretValue(h) then
        return nil
    end
    return l, b, w, h
end

function CHAT:SafeSize(frame)
    if not (frame and frame.GetSize) then return nil end

    local w, h = frame:GetSize()
    if not w or KE:IsSecretValue(w) or KE:IsSecretValue(h) then return nil end
    return w, h
end

function CHAT:FrameOverlapsPanel(frame)
    if not frame or not self.panel then return false end

    local frameLeft, frameBottom, frameWidth, frameHeight = self:SafeRect(frame)
    local panelLeft, panelBottom, panelWidth, panelHeight = self.panel:GetRect()

    if not frameLeft or not panelLeft then return false end

    local frameRight = frameLeft + frameWidth
    local frameTop = frameBottom + frameHeight
    local panelRight = panelLeft + panelWidth
    local panelTop = panelBottom + panelHeight

    return frameLeft < panelRight and frameRight > panelLeft and frameBottom < panelTop and frameTop > panelBottom
end

function CHAT:OnFCF_ResetChatWindows()
    self:ResetPanelSnap()
    self:SetupChat()
end

function CHAT:OnFCF_SetButtonSide(chat)
    if chat and self:IsChatValid(chat) then self:PositionButtonFrame(chat) end
end

function CHAT:PostChatClose(chat)
    local tab = CHAT:GetTab(chat)
    if tab then
        tab.whisperName = nil
        tab.classColor = nil
    end
end

function CHAT:OnFCF_Close(chat)
    if not chat then return end
    local id = chat:GetID()
    self.originalStates[id] = nil
    chat.styled = nil
    chat.scriptsSet = nil
    self:PostChatClose(chat)
end

function CHAT:OnFCF_SetWindowAlpha(frame, alpha)
    if not frame then return end
    frame.oldAlpha = alpha or 1
end

function CHAT:OnFCF_SetChatWindowFontSize(_, chatFrame, fontSize)
    if not chatFrame then chatFrame = _G.FCF_GetCurrentChatFrame and _G.FCF_GetCurrentChatFrame() end
    if not chatFrame or not self:IsChatValid(chatFrame) then return end
    if not fontSize then return end

    self:UpdateEditboxFont(chatFrame)
end

function CHAT:GetOwner(tab)
    if not tab then return end
    if not tab.owner then tab.owner = _G[format("ChatFrame%s", tab:GetID())] end
    return tab.owner
end

function CHAT:OnFCFTab_UpdateColors(tab, selected)
    if not tab then return end

    if tab:GetParent() == _G.ChatConfigFrameChatTabManager then
        if selected then tab.Text:SetTextColor(1, 1, 1) end

        local name = _G.GetChatWindowInfo(tab:GetID())
        if name and KE:NotSecretValue(name) then tab.Text:SetText(name) end

        tab:SetAlpha(1)
    else
        local chat = self:GetOwner(tab)
        if not chat then return end

        local db = self.db
        tab.selected = selected

        local name = chat.name or _G.UNKNOWN
        local chatTarget = chat.chatTarget
        local whisper = tab.conversationIcon and chatTarget

        if whisper and not tab.whisperName and KE:NotSecretValue(name) then
            local strippedName = self:StripMyRealm(name)
            tab.whisperName = gsub(strippedName, "([%S]-)%-[%S]+", "%1|cFF999999*|r")
        end

        local nameText = tab.whisperName or name
        local nameTextNotSecret = KE:NotSecretValue(nameText)

        if selected then
            if nameTextNotSecret then
                local tabSelector = db.TabSelector or "ARROW1"

                if tabSelector == "NONE" then
                    tab:SetFormattedText(TAB_STYLES.NONE, nameText)
                else
                    local selectorColor = db.TabSelectorColor
                    local hexColor = selectorColor and self:RGBToHex(selectorColor.r, selectorColor.g, selectorColor.b) or
                        "|cff4cff4c"
                    tab:SetFormattedText(TAB_STYLES[tabSelector] or TAB_STYLES.ARROW1, hexColor, nameText, hexColor)
                end
            end

            if db.TabSelectedTextEnabled then
                local selectedTextColor = db.TabSelectedTextColor
                if selectedTextColor then
                    tab.Text:SetTextColor(selectedTextColor.r, selectedTextColor.g, selectedTextColor.b)
                else
                    tab.Text:SetTextColor(1, 1, 1)
                end
                return
            end
        end

        if whisper then
            if nameTextNotSecret and not selected then tab:SetText(nameText) end

            local nameLower = not tab.classColor and KE:NotSecretValue(name) and strlower(name)
            local classMatch = nameLower and self.ClassNames[nameLower]
            if classMatch then tab.classColor = self:GetClassColor(classMatch) end

            if tab.classColor then
                tab.Text:SetTextColor(tab.classColor.r, tab.classColor.g, tab.classColor.b)
            else
                local whisperInfo = _G.ChatTypeInfo and _G.ChatTypeInfo["WHISPER"]
                if whisperInfo then tab.Text:SetTextColor(whisperInfo.r, whisperInfo.g, whisperInfo.b) end
            end
        else
            if nameTextNotSecret and not selected then tab:SetText(name) end

            local colorMode = db.TabTextColorMode or "custom"
            local customColor = db.TabTextColor or cachedTabAccentColor
            local r, g, b = KE:GetAccentColor(colorMode, { customColor.r, customColor.g, customColor.b, 1 })
            tab.Text:SetTextColor(r, g, b)
        end
    end
end

function CHAT:OnFCFDock_SelectWindow(_, chatFrame)
    if chatFrame and self:IsChatValid(chatFrame) then self:UpdateEditboxFont(chatFrame) end
end

function CHAT:OnFCFDock_ScrollToSelectedTab(dock)
    if dock ~= _G.GeneralDockManager then return end
    if not self.panel then return end

    local scrollFrame = dock.scrollFrame
    if scrollFrame then
        local logChat, logChatTab = self:GetCombatLog()

        scrollFrame:ClearAllPoints()
        scrollFrame:SetPoint("RIGHT", dock.overflowButton, "LEFT")

        local anchorTab = (logChat and logChat.isDocked and logChatTab) or self:GetTab(dock.primary)
        if anchorTab then scrollFrame:SetPoint("TOPLEFT", anchorTab, "TOPRIGHT", 0, 1) end
    end
end

function CHAT:OnRedockChatWindows()
    self:ResetPanelSnap()
    self:SetupChat()
end

function CHAT:OnChatEdit_ActivateChat(editbox)
    if not editbox then return end
    local chatFrame = editbox.chatFrame or editbox:GetParent()
    if chatFrame and self:IsChatValid(chatFrame) then self:UpdateEditboxFont(chatFrame) end
end

function CHAT:OnChatEdit_DeactivateChat(editbox)
    if not editbox then return end
    local style = editbox.chatStyle or GetCVar("chatStyle")
    if style == "im" then editbox:Hide() end
end

function CHAT:OnChatEdit_SetLastActiveWindow(editbox)
    if not editbox then return end
    local style = editbox.chatStyle or GetCVar("chatStyle")
    if style == "im" then editbox:SetAlpha(0.5) end
end

function CHAT:UpdateEditboxFont(chatFrame)
    if not chatFrame then return end

    local style = GetCVar("chatStyle")
    if style == "classic" and self.ChatWindow then chatFrame = self.ChatWindow end

    local docker = _G.GeneralDockManager
    if docker and chatFrame == docker.primary then
        chatFrame = docker.selected or chatFrame
    end

    local editbox = chatFrame.editBox
    if not editbox then return end

    local id = chatFrame:GetID()
    local _, fontSize = _G.GetChatWindowInfo(id)
    if not fontSize or fontSize == 0 then fontSize = 14 end
    fontSize = (self.db and self.db.EditBoxFontSize) or fontSize
    editbox:SetFont(cachedFontPath, fontSize, NormalizeFontOutline(self.db and self.db.FontOutline))
end

function CHAT:OnFCFDockOverflowButton_UpdatePulseState(btn)
    if not btn or not btn.Texture then return end

    local db = self.db
    if btn.alerting then
        btn:SetAlpha(1)
        if db.TabSelectedTextEnabled and db.TabSelectedTextColor then
            local c = db.TabSelectedTextColor
            btn.Texture:SetVertexColor(c.r, c.g, c.b)
        else
            btn.Texture:SetVertexColor(1, 1, 1)
        end
    elseif not btn:IsMouseOver() then
        local colorMode = db.TabTextColorMode or "custom"
        local customColor = db.TabTextColor or cachedTabAccentColor
        local r, g, b = KE:GetAccentColor(colorMode, { customColor.r, customColor.g, customColor.b, 1 })
        btn.Texture:SetVertexColor(r, g, b)
    end
end

function CHAT:OnUIDropDownMenu_AddButton(info, level)
    if not info or not CLOSE_BUTTONS[info.text] then return end
    if not level then level = 1 end

    local list = _G["DropDownList" .. level]
    if not list then return end

    local index = list.numButtons or 1
    local button = _G[list:GetName() .. "Button" .. index]
    if not button then return end

    if button.func == _G.FCF_PopInWindow then
        button.func = CHAT.FCF_PopInWindow
    elseif button.func == _G.FCF_Close then
        button.func = CHAT.FCF_Close
    end
end

function CHAT:StripMyRealm(name)
    if not name then return name end
    if KE:IsSecretValue(name) then return name end
    local myRealm = GetRealmName and GetRealmName()
    if myRealm then
        myRealm = gsub(myRealm, " ", "")
        name = gsub(name, "%-" .. myRealm, "")
    end
    return name
end

function CHAT:RGBToHex(r, g, b)
    r = r <= 1 and r >= 0 and r or 1
    g = g <= 1 and g >= 0 and g or 1
    b = b <= 1 and b >= 0 and b or 1
    return format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end

function CHAT:ShortChannel()
    local key = gsub(strupper(self), " ", "_")
    local abbr = SHORT_CHANNELS[key]
    if not abbr then
        abbr = communityAbbrevCache[key]
        if abbr == nil then
            local resolved = false
            local chanName = select(2, _G.GetChannelName(gsub(self, "channel:", "")))
            if chanName then
                local communityID = strmatch(chanName, "Community:(%d+):")
                if communityID and _G.C_Club and _G.C_Club.GetClubInfo then
                    local clubInfo = _G.C_Club.GetClubInfo(communityID)
                    if clubInfo and clubInfo.name and clubInfo.name ~= "" then
                        abbr = strupper(strsub(clubInfo.name, 1, 2))
                        resolved = true
                    end
                end
            end
            communityAbbrevCache[key] = resolved and abbr or false
        end
        if abbr == false then abbr = nil end
    end
    return format("|Hchannel:%s|h[%s]|h", self, abbr or gsub(self, "channel:", ""))
end

function CHAT:HandleShortChannels(msg, hide)
    msg = gsub(msg, "|Hchannel:(.-)|h%[(.-)%]|h", hide and "" or CHAT.ShortChannel)
    msg = gsub(msg, "CHANNEL:", "")
    msg = gsub(msg, "^(.-|h) whispers", "%1")
    msg = gsub(msg, "^(.-|h) says", "%1")
    msg = gsub(msg, "^(.-|h) yells", "%1")
    msg = gsub(msg, "<" .. _G.AFK .. ">", "[|cffFF9900AFK|r] ")
    msg = gsub(msg, "<" .. _G.DND .. ">", "[|cffFF3333DND|r] ")

    if SHORT_CHANNEL_PATTERNS then
        for _, info in ipairs(SHORT_CHANNEL_PATTERNS) do msg = gsub(msg, info.pattern, info.replacement) end
    end

    return msg
end

function CHAT:GetDateTime(useLocal)
    return useLocal and time() or GetServerTime()
end

function CHAT:MessageIsProtected(message)
    if KE:IsSecretValue(message) then return true end
    return message and (message ~= gsub(message, "(:?|?)|K(.-)|k", canChangeMessage))
end

function CHAT:AddMessageEdits(_, msg, isHistory, historyTime)
    if not msg then return msg end
    if KE:IsSecretValue(msg) then return msg end

    -- BN colorize runs BEFORE the |K protection bail below: BN messages
    -- ALWAYS contain |K names, so MessageIsProtected is true for every
    -- one of them and the rest of the edit pipeline skips them.
    local db = self.db
    if db.ClassColorWhispers ~= false and strfind(msg, "|HBNplayer:", 1, true) then
        msg = ColorizeBNSenders(msg)
    end

    local isProtected = self:MessageIsProtected(msg)
    if isProtected then return msg end

    if strmatch(msg, '^%s*$') or strmatch(msg, '^|Hketime|h') then return msg end

    local historyTimestamp
    if isHistory == "KE_ChatHistory" then historyTimestamp = historyTime end
    if db.ShortChannels then msg = self:HandleShortChannels(msg, false) end
    if db.TimestampFormat and db.TimestampFormat ~= "NONE" then
        local timestamp = BetterDate(db.TimestampFormat, historyTimestamp or self:GetDateTime(db.UseLocalTime))
        timestamp = gsub(timestamp, " ", "")
        timestamp = gsub(timestamp, "AM", " AM")
        timestamp = gsub(timestamp, "PM", " PM")
        if db.TimestampColorEnabled and db.TimestampColor then
            local c = db.TimestampColor
            local colorCode = format("|cff%02x%02x%02x", (c.r or 0.6) * 255, (c.g or 0.6) * 255, (c.b or 0.6) * 255)
            msg = format("|Hketime|h%s%s|r|h %s", colorCode, timestamp, msg)
        else
            msg = format("|Hketime|h%s|h %s", timestamp, msg)
        end
    end

    return msg
end

function CHAT:AddMessage(msg, infoR, infoG, infoB, infoID, accessID, typeID, event, eventArgs, msgFormatter, isHistory,
                         historyTime)
    local body = CHAT:AddMessageEdits(self, msg, isHistory, historyTime)
    self.OldAddMessage(self, body, infoR, infoG, infoB, infoID, accessID, typeID, event, eventArgs, msgFormatter)
end

function CHAT:GetClassColor(class)
    if not class then return nil end
    return RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
end

function CHAT:OnGetPlayerInfoByGUID(guid)
    if KE:IsSecretValue(guid) then return end

    local data = self.GuidCache[guid]
    if data then
        if data.classColor then data.classColor = self:GetClassColor(data.englishClass) end
        return data
    end

    local ok, localizedClass, englishClass, localizedRace, englishRace, sex, name, realm = pcall(GetPlayerInfoByGUID,
        guid)
    if not ok or not englishClass then return end

    local hasRealm = realm and realm ~= ''
    local nameWithRealm = hasRealm and (name .. "-" .. realm) or nil

    data = {
        localizedClass = localizedClass,
        englishClass = englishClass,
        localizedRace = localizedRace,
        englishRace = englishRace,
        sex = sex,
        name = name,
        realm = hasRealm and realm or nil,
        nameWithRealm = nameWithRealm,
    }

    if name and not KE:IsSecretValue(name) then
        self.ClassNames[strlower(name)] = englishClass
    end
    if nameWithRealm and not KE:IsSecretValue(nameWithRealm) then
        self.ClassNames[strlower(nameWithRealm)] = englishClass
    end

    if self.GuidCacheCount >= GUID_CACHE_MAX then
        wipe(self.GuidCache)
        wipe(self.ClassNames)
        self.GuidCacheCount = 0
    end

    self.GuidCache[guid] = data
    self.GuidCacheCount = self.GuidCacheCount + 1

    data.classColor = self:GetClassColor(englishClass)

    return data
end

function CHAT:OnChatEdit_OnEnterPressed(editBox)
    if not editBox then return end

    local chatType = editBox:GetAttribute("chatType")
    if not chatType then return end

    local chatFrame = editBox:GetParent()
    if not chatFrame or chatFrame.isTemporary then return end

    local info = _G.ChatTypeInfo and _G.ChatTypeInfo[chatType]
    if info and info.sticky == 1 then editBox:SetAttribute("chatType", "SAY") end
end

function CHAT:OnChatEdit_UpdateHeader(editbox)
    if not editbox then return end

    local chatType = editbox:GetAttribute("chatType")
    if not chatType then return end

    local ChatTypeInfo = _G.ChatTypeInfo
    local info = ChatTypeInfo and ChatTypeInfo[chatType]
    local chanTarget = editbox:GetAttribute("channelTarget")
    local chanIndex = chanTarget and _G.GetChannelName(chanTarget)

    local insetLeft, insetRight, insetTop, insetBottom = editbox:GetTextInsets()
    editbox:SetTextInsets(insetLeft, insetRight + 30, insetTop, insetBottom)
    self:ApplyFrameStyle(editbox, nil, true)

    if chanIndex and chatType == "CHANNEL" then
        if chanIndex == 0 then
            editbox:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        else
            info = ChatTypeInfo[chatType .. chanIndex]
            if info then editbox:SetBackdropBorderColor(info.r, info.g, info.b, 1) end
        end
    elseif info and info.r and info.g and info.b then
        editbox:SetBackdropBorderColor(info.r, info.g, info.b, 1)
    end
end

function CHAT.ChatFrameTab_SetAlpha(tab, _, skip)
    if skip then return end

    local chat = CHAT:GetOwner(tab)
    local selected = _G.GeneralDockManager.selected

    if chat then
        tab:SetAlpha((not chat.isDocked or chat == selected) and 1 or 0.6, true)
    else
        tab:SetAlpha(1, true)
    end
end

function CHAT:UpdateChatTabs()
    for _, frameName in ipairs(_G.CHAT_FRAMES) do
        local chat = _G[frameName]
        if chat then self:UpdateChatTab(chat) end
    end
end

function CHAT:UpdateChatTab(chat)
    if chat.lastGM then return end

    local tab = self:GetTab(chat)
    if not tab then return end

    local isSnapped = chat == self.ChatWindow
    local parent = isSnapped and self.panel or UIParent

    if not chat.isDocked then tab:SetParent(parent) end
    chat:SetParent(parent)

    if chat.EditModeResizeButton then
        chat.EditModeResizeButton:SetFrameStrata("HIGH")
        chat.EditModeResizeButton:SetFrameLevel(6)
    end
end

function CHAT:UpdateChatTabColors()
    for _, frameName in ipairs(_G.CHAT_FRAMES) do
        local chat = _G[frameName]
        local tab = chat and self:GetTab(chat)
        if tab then self:OnFCFTab_UpdateColors(tab, tab.selected) end
    end
end

function CHAT:FCF_Tab_OnClick(button)
    local chat = self and CHAT:GetOwner(self)
    if not chat then return end

    if button == "RightButton" then
        chat:StopMovingOrSizing()

        _G.CURRENT_CHAT_FRAME_ID = self:GetID()
        _G.FCF_Tab_SetupMenu(self)
    elseif button == "MiddleButton" then
        if not _G.IsBuiltinChatWindow(chat) then
            if not chat.isTemporary then
                CHAT.FCF_PopInWindow(self, chat)
                return
            elseif chat.chatType == "WHISPER" or chat.chatType == "BN_WHISPER" then
                CHAT.FCF_PopInWindow(self, chat)
                return
            elseif chat.chatType == "PET_BATTLE_COMBAT_LOG" then
                CHAT.FCF_Close(chat)
            end
        end
    else
        _G.CloseDropDownMenus()
        _G.SELECTED_CHAT_FRAME = chat

        if chat.isDocked and _G.FCFDock_GetSelectedWindow(_G.GeneralDockManager) ~= chat then
            _G.FCF_SelectDockFrame(chat)
        end

        if GetCVar("chatStyle") ~= "classic" then
            local chatFrame = (chat.isDocked and _G.GeneralDockManager.primary) or chat
            if chatFrame then
                ChatEditSetLastActiveWindow(chatFrame.editBox)
            end
        end

        chat:ResetAllFadeTimes()

        _G.FCF_FadeInChatFrame(chat)
    end
end

function CHAT:Tab_OnClick(button)
    CHAT.FCF_Tab_OnClick(self, button)
    PlaySound(SOUND_U_CHAT_SCROLL_BUTTON)
end

function CHAT:FCF_Close(fallback)
    if fallback then self = fallback end
    if not self or self == CHAT then self = _G.FCF_GetCurrentChatFrame() end
    if self == _G.DEFAULT_CHAT_FRAME then return end

    _G.FCF_UnDockFrame(self)
    self:Hide()
    CHAT:GetTab(self):Hide()

    _G.FCF_FlagMinimizedPositionReset(self)

    if self.minFrame and self.minFrame:IsShown() then
        self.minFrame:Hide()
    end

    if self.isTemporary then
        _G.FCFManager_UnregisterDedicatedFrame(self, self.chatType, self.chatTarget)
        self.isRegistered = false
        self.inUse = false
    end

    if self.RemoveAllMessageGroups then
        self:RemoveAllMessageGroups()
        self:RemoveAllChannels()
        self:ReceiveAllPrivateMessages()
    else
        _G.ChatFrame_RemoveAllMessageGroups(self)
        _G.ChatFrame_RemoveAllChannels(self)
        _G.ChatFrame_ReceiveAllPrivateMessages(self)
    end

    CHAT:PostChatClose(self)
end

function CHAT:FCF_PopInWindow(fallback)
    if fallback then self = fallback end
    if not self or self == CHAT then self = _G.FCF_GetCurrentChatFrame() end
    if self == _G.DEFAULT_CHAT_FRAME then return end

    _G.FCF_RestoreChatsToFrame(_G.DEFAULT_CHAT_FRAME, self)
    CHAT.FCF_Close(self)
end

function CHAT:StripTabTextures(tab)
    if not tab then return end

    local tabName = tab:GetName()
    local glowName = tabName and (tabName .. "Glow")

    for _, region in pairs({ tab:GetRegions() }) do
        if region:IsObjectType("Texture") then
            local regionName = region:GetName()
            local isGlow = regionName and (regionName == glowName or regionName:find("Glow"))
            if not isGlow then
                region:SetTexture()
                if region.SetAtlas then region:SetAtlas("") end
            end
        end
    end

    local textureKeys = {
        "leftTexture", "middleTexture", "rightTexture",
        "Left", "Middle", "Right",
        "ActiveLeft", "ActiveMiddle", "ActiveRight",
        "HighlightLeft", "HighlightMiddle", "HighlightRight",
        "SelectedLeft", "SelectedMiddle", "SelectedRight",
    }

    for _, key in ipairs(textureKeys) do
        local tex = tab[key]
        if tex and tex.SetTexture then tex:SetTexture() end
    end
end

function CHAT:StyleTab(tab, chat)
    if not tab or tab.styled then return end

    local name = chat:GetName()

    self:StripTabTextures(tab)

    for _, texName in pairs(TAB_TEXTURES) do
        local texKey = name .. "Tab"
        local leftKey = texName .. "Left"
        local middleKey = texName .. "Middle"
        local rightKey = texName .. "Right"

        local main = _G[texKey]
        local left = _G[texKey .. leftKey] or (main and main[leftKey])
        local middle = _G[texKey .. middleKey] or (main and main[middleKey])
        local right = _G[texKey .. rightKey] or (main and main[rightKey])

        if left then left:SetTexture() end
        if middle then middle:SetTexture() end
        if right then right:SetTexture() end
    end

    if tab.Text then
        tab.Text:ClearAllPoints()
        tab.Text:SetPoint("CENTER", tab, "CENTER", 0, 0)
        tab.Text:Show()
    end

    if tab.conversationIcon then tab.conversationIcon:Show() end

    if not tab.SetAlphaHooked then
        hooksecurefunc(tab, "SetAlpha", CHAT.ChatFrameTab_SetAlpha)
        tab.SetAlphaHooked = true
    end

    tab:SetHeight(22)

    if tab.conversationIcon then
        tab.conversationIcon:ClearAllPoints()
        tab.conversationIcon:SetPoint("RIGHT", tab.Text, "LEFT", -1, 0)
    end

    tab.styled = true
end

function CHAT:ApplyFrameStyle(frame, template, glossTex, ignoreUpdates, forcePixelMode)
    if not frame then return end

    frame.template = template or "Default"
    frame.glossTex = glossTex
    frame.ignoreUpdates = ignoreUpdates
    frame.forcePixelMode = forcePixelMode

    if not frame.SetBackdrop then
        Mixin(frame, BackdropTemplateMixin)
        if frame.OnSizeChanged then frame:HookScript("OnSizeChanged", frame.OnBackdropSizeChanged) end
    end

    ReplaceSetupTextureCoordinates(frame)
    KE:DisablePixelSnap(frame)

    if template == "NoBackdrop" then
        frame:SetBackdrop(nil)
        return
    end

    local db = self.db
    local edgeSize = KE:GetPixelSize()

    frame:SetBackdrop({
        bgFile = glossTex and (type(glossTex) == "string" and glossTex or BLANK_TEX) or BLANK_TEX,
        edgeFile = BLANK_TEX,
        edgeSize = edgeSize,
    })

    local backdropR, backdropG, backdropB, backdropA, borderR, borderG, borderB, borderA = GetTemplateColors(template)

    if db.EditBox then
        local bgColor = db.EditBox.BackdropColor
        if bgColor then
            backdropR, backdropG, backdropB, backdropA = bgColor[1], bgColor[2], bgColor[3], bgColor[4] or backdropA
        end
    end

    if frame.callbackBackdropColor then
        frame:callbackBackdropColor()
    else
        frame:SetBackdropColor(backdropR, backdropG, backdropB, frame.customBackdropAlpha or backdropA)
    end

    if frame.forcedBorderColors then borderR, borderG, borderB, borderA = unpack(frame.forcedBorderColors) end

    frame:SetBackdropBorderColor(borderR, borderG, borderB, borderA)
end

function CHAT:EditBoxFocusGained(editbox)
    if not self.panel:IsShown() then
        self.panel.editboxforced = true
        self.panel:Show()
        if self.panel.backdrop then self.panel.backdrop:Show() end
        editbox:Show()
    end
end

function CHAT:EditBoxFocusLost(editbox)
    if self.panel.editboxforced then
        self.panel.editboxforced = nil
        if self.panel:IsShown() then
            editbox:Hide()
        end
    end
end

function CHAT:EditBoxOnKeyDown(editbox, key)
    if not editbox then return end

    local lines = editbox.historyLines
    if not lines then return end

    if IsAltKeyDown() then return end

    local maxLines = #lines
    if maxLines == 0 then return end

    if key == "DOWN" then
        editbox.historyIndex = (editbox.historyIndex or 0) - 1

        if editbox.historyIndex < 1 then
            editbox.historyIndex = 0
            editbox:SetText("")
            return
        end
    elseif key == "UP" then
        editbox.historyIndex = (editbox.historyIndex or 0) + 1

        if editbox.historyIndex > maxLines then editbox.historyIndex = maxLines end
    else
        return
    end

    local historyLine = maxLines - (editbox.historyIndex - 1)
    local historyText = lines[historyLine]
    if historyText then editbox:SetText(historyText) end
end

function CHAT:StyleEditbox(editbox)
    if not editbox or editbox.styled then return end

    local db = self.db
    local name = editbox:GetName()

    editbox:SetAltArrowKeyMode(false)
    self:ApplyFrameStyle(editbox, nil, true)
    editbox:SetFont(cachedFontPath, db.EditBoxFontSize or 14, NormalizeFontOutline(db.FontOutline))

    if name then
        local header = _G[name .. "Header"]
        if header then header:Hide() end

        local headerSuffix = _G[name .. "HeaderSuffix"]
        if headerSuffix then headerSuffix:Hide() end
    end

    if editbox.focusLeft then editbox.focusLeft:SetAlpha(0) end
    if editbox.focusRight then editbox.focusRight:SetAlpha(0) end
    if editbox.focusMid then editbox.focusMid:SetAlpha(0) end

    if name then
        for _, suffix in next, { "Left", "Mid", "Right" } do
            local tex = _G[name .. suffix]
            if tex then
                tex:SetTexture(nil)
                tex:SetAlpha(0)
            end
        end
    end

    editbox:HookScript("OnEditFocusGained", function(eb)
        C_Timer.After(0, function() CHAT:EditBoxFocusGained(eb) end)
    end)
    editbox:HookScript("OnEditFocusLost", function(eb)
        C_Timer.After(0, function() CHAT:EditBoxFocusLost(eb) end)
    end)
    editbox:HookScript("OnKeyDown", function(eb, key) CHAT:EditBoxOnKeyDown(eb, key) end)

    editbox.historyLines = {}
    editbox.historyIndex = 0

    if editbox.AddHistoryLine and not self:IsHooked(editbox, "AddHistoryLine") then
        self:SecureHook(editbox, "AddHistoryLine", function(eb, text)
            if text and #text > 0 then
                tinsert(eb.historyLines, text)
                while #eb.historyLines > 50 do
                    tremove(eb.historyLines, 1)
                end
            end
        end)
    end

    if editbox.UpdateHeader and not self:IsHooked(editbox, "UpdateHeader") then
        self:SecureHook(editbox, "UpdateHeader", "OnChatEdit_UpdateHeader")
    end

    editbox:Hide()

    editbox.styled = true
end

function CHAT:UpdateEditboxAnchors(cvar, value)
    if not cvar then value = GetCVar("chatStyle") end

    local db = self.db
    local classic = value == "classic"
    local leftChat = classic and self.panel
    local panelHeight = EDITBOX_HEIGHT

    local position = db.EditBoxPosition or "BELOW_CHAT"
    local aboveInside = position == "ABOVE_CHAT_INSIDE"
    local belowInside = position == "BELOW_CHAT_INSIDE"
    local below = position == "BELOW_CHAT"

    local offsetBelow = classic and (belowInside and 1 or 0) or -5
    local offsetAbove = classic and (aboveInside and -1 or 0) or 2

    local belowTopY = classic and 0 or -2
    local belowBottomY = classic and 0 or -2
    local belowTopX = offsetBelow + (belowInside and panelHeight or 0)
    local belowBottomX = offsetBelow + (belowInside and 0 or -panelHeight)

    local aboveTopY = classic and (aboveInside and -1 or 0) or 2
    local aboveBottomY = classic and (aboveInside and 1 or 0) or -2
    local aboveTopX = offsetAbove + (aboveInside and 0 or panelHeight)
    local aboveBottomX = offsetAbove + (aboveInside and -panelHeight or 0)

    for _, frameName in ipairs(_G.CHAT_FRAMES) do
        local chat = _G[frameName]
        local editbox = chat and chat.editBox
        if editbox and self:IsChatValid(chat) then
            editbox.chatStyle = value
            editbox:ClearAllPoints()

            local anchorTo = leftChat or chat
            if below or belowInside then
                editbox:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", belowTopY, belowTopX)
                editbox:SetPoint("BOTTOMRIGHT", anchorTo, "BOTTOMRIGHT", belowBottomY, belowBottomX)
            else
                editbox:SetPoint("TOPRIGHT", anchorTo, "TOPRIGHT", aboveTopY, aboveTopX)
                editbox:SetPoint("BOTTOMLEFT", anchorTo, "TOPLEFT", aboveBottomY, aboveBottomX)
            end
        end
    end
end

function CHAT:StyleChat(chat)
    if not chat then return end

    local db = self.db
    local id = chat:GetID()
    local tab = self:GetTab(chat)

    local fontSize = db.FontSize
    if not fontSize then
        fontSize = select(2, _G.FCF_GetChatWindowInfo(id))
    end
    if not fontSize or fontSize == 0 then fontSize = 14 end
    local fontOutline = NormalizeFontOutline(db.FontOutline)
    chat:SetFont(cachedFontPath, fontSize, fontOutline)

    chat:SetTimeVisible(db.FadeEnabled and db.FadeTime or 120)
    chat:SetMaxLines(db.MaxLines or 500)
    chat:SetFading(db.FadeEnabled ~= false)

    local allowHooks = id and not IGNORE_FRAMES[id]
    if allowHooks and not chat.OldAddMessage then
        chat.OldAddMessage = chat.AddMessage
        chat.AddMessage = self.AddMessage
    end

    if tab and not (_G.IsCombatLog and _G.IsCombatLog(chat)) then tab:SetScript("OnClick", CHAT.Tab_OnClick) end

    if tab and tab.Text then
        local tabFontSize = db.TabFontSize or 12
        local tabFontOutline = NormalizeFontOutline(db.TabFontOutline or db.FontOutline)
        tab.Text:SetFont(cachedFontPath, tabFontSize, tabFontOutline)
    end

    if tab and not chat.isDocked and _G.PanelTemplates_TabResize then
        _G.PanelTemplates_TabResize(tab, tab.sizePadding or 0)
    end

    if chat.styled then return end

    if not self.originalStates[id] then
        self.originalStates[id] = {
            parent = chat:GetParent(),
            points = {},
            width = chat:GetWidth(),
            height = chat:GetHeight(),
            frameLevel = chat:GetFrameLevel(),
            timeVisible = chat.GetTimeVisible and chat:GetTimeVisible(),
            maxLines = chat.GetMaxLines and chat:GetMaxLines(),
            fading = chat.GetFading and chat:GetFading(),
        }

        for i = 1, chat:GetNumPoints() do
            local point, relativeTo, relativePoint, xOfs, yOfs = chat:GetPoint(i)
            self.originalStates[id].points[i] = { point, relativeTo, relativePoint, xOfs, yOfs }
        end

        if tab then self.originalStates[id].tabParent = tab:GetParent() end
        if chat.Background then self.originalStates[id].backgroundShown = chat.Background:IsShown() end
    end

    chat:SetFrameLevel(CHAT_FRAME_LEVEL)
    chat:SetClampRectInsets(0, 0, 0, 0)
    chat:SetClampedToScreen(false)

    if tab then self:StyleTab(tab, chat) end

    self:HideChatElements(chat)
    self:SetupChatScripts(chat)

    local editbox = chat.editBox
    if editbox then self:StyleEditbox(editbox) end

    self:CreateCopyButton(chat)

    chat.styled = true
end

local HiddenFrame = CreateFrame("Frame")
HiddenFrame:Hide()

function CHAT:DisableFrame(object)
    if not object then return end

    if object.GetChildren then for _, child in pairs({ object:GetChildren() }) do self:DisableFrame(child) end end
    if object.UnregisterAllEvents then
        object:UnregisterAllEvents()
        object:SetParent(HiddenFrame)
    else
        object.Show = object.Hide
    end
    object:Hide()
end

function CHAT:ClearFrameTextures(frame, kill)
    if not frame then return end

    local frameName = frame.GetName and frame:GetName()
    for _, blizz in ipairs(BLIZZ_FRAME_KEYS) do
        local child = frame[blizz] or (frameName and _G[frameName .. blizz])
        if child and child.GetRegions then self:ClearFrameTextures(child, kill) end
    end

    if frame.GetRegions then
        for _, region in pairs({ frame:GetRegions() }) do
            if region and region.IsObjectType and region:IsObjectType("Texture") then
                if kill then
                    region:Hide()
                    if region.UnregisterAllEvents then region:UnregisterAllEvents() end
                else
                    region:SetTexture()
                    if region.SetAtlas then region:SetAtlas("") end
                end
            end
        end
    end
end

function CHAT:HideChatElements(chat)
    local name = chat:GetName()

    self:PositionButtonFrame(chat)

    self:ClearFrameTextures(chat, true)

    if chat.ScrollBar then self:DisableFrame(chat.ScrollBar) end
    if chat.ScrollToBottomButton then self:DisableFrame(chat.ScrollToBottomButton) end

    local thumbTexture = _G[name .. "ThumbTexture"]
    if thumbTexture then self:DisableFrame(thumbTexture) end

    local minimize = _G[name .. "MinimizeButton"]
    if minimize then self:DisableFrame(minimize) end

    local editLeft = _G[name .. "EditBoxLeft"]
    if editLeft then self:DisableFrame(editLeft) end

    local editMid = _G[name .. "EditBoxMid"]
    if editMid then self:DisableFrame(editMid) end

    local editRight = _G[name .. "EditBoxRight"]
    if editRight then self:DisableFrame(editRight) end
end

function CHAT:PositionButtonFrame(chat)
    if not chat.buttonFrame then return end
    chat.buttonFrame:ClearAllPoints()
    chat.buttonFrame:SetPoint("TOP", chat, "BOTTOM", 0, -90000)
    chat.buttonFrame:SetClipsChildren(true)
end

local hyperlinkHoveredFrame
function CHAT:OnHyperlinkEnter(frame, refString)
    if InCombatLockdown() then return end
    local linkToken = strmatch(refString, "^([^:]+)")
    if HYPERLINK_TYPES[linkToken] then
        GameTooltip:SetOwner(frame, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(refString)
        GameTooltip:Show()
        hyperlinkHoveredFrame = frame
    end
end

function CHAT:OnHyperlinkLeave()
    if hyperlinkHoveredFrame then
        hyperlinkHoveredFrame = nil
        GameTooltip:Hide()
    end
end

function CHAT:SetupChatScripts(chat)
    if chat.scriptsSet then return end

    local id = chat:GetID()
    local allowHooks = id and not IGNORE_FRAMES[id]

    if not chat.keSetScriptHooked then
        chat.keSetScriptHooked = true
        hooksecurefunc(chat, "SetScript", function(frame, scriptType, handler)
            self:ChatFrame_SetScript(frame, scriptType, handler)
        end)
    end

    -- Replace OnEvent with our handler to prevent taint from secret values.
    -- KE.ChatMessageHandler is Task 7's module; until it exists this
    -- guard leaves Blizzard's own OnEvent in place rather than nil-ing it.
    if allowHooks and KE.ChatMessageHandler then
        chat:SetScript("OnEvent", function(frame, event, ...)
            KE.ChatMessageHandler:FloatingChatFrame_OnEvent(frame, event, ...)
        end)
    end

    chat.keSettingMouseWheel = true
    chat:SetScript("OnMouseWheel", function(frame, delta) self:ChatFrame_OnMouseWheel(frame, delta) end)
    chat.keSettingMouseWheel = nil

    if not self:IsHooked(chat, "OnHyperlinkEnter") then self:HookScript(chat, "OnHyperlinkEnter", "OnHyperlinkEnter") end
    if not self:IsHooked(chat, "OnHyperlinkLeave") then self:HookScript(chat, "OnHyperlinkLeave", "OnHyperlinkLeave") end

    chat.scriptsSet = true
end

function CHAT:SetupDockManager()
    local docker = _G.GeneralDockManager
    if not docker then return end

    local primary = docker.primary
    if not primary then return end

    if not self.originalDockState then
        self.originalDockState = { parent = docker:GetParent(), points = {}, }
        for i = 1, docker:GetNumPoints() do
            local point, relativeTo, relativePoint, xOfs, yOfs = docker:GetPoint(i)
            self.originalDockState.points[i] = { point, relativeTo, relativePoint, xOfs, yOfs }
        end
    end

    docker:SetParent(self.panel)
    docker:ClearAllPoints()
    docker:SetPoint("BOTTOMLEFT", primary, "TOPLEFT", 0, 7)
    docker:SetPoint("BOTTOMRIGHT", primary, "TOPRIGHT", 0, 7)
    docker:SetHeight(22)

    local scrollFrame = _G.GeneralDockManagerScrollFrame
    if scrollFrame then scrollFrame:SetHeight(22) end

    if _G.GeneralDockManagerScrollFrameChild then _G.GeneralDockManagerScrollFrameChild:SetHeight(22) end

    self:StyleOverflowButton()
    self:OnFCFDock_ScrollToSelectedTab(docker)
end

function CHAT:StyleOverflowButton()
    local btn = _G.GeneralDockManagerOverflowButton
    if not btn then return end

    if _G.GeneralDockManagerOverflowButtonList then
        _G.GeneralDockManagerOverflowButtonList:SetFrameStrata("LOW")
        _G.GeneralDockManagerOverflowButtonList:SetFrameLevel(5)
    end

    btn:ClearAllPoints()
    btn:SetPoint("RIGHT", _G.GeneralDockManager, "RIGHT", -4, 0)

    if not btn.KEStyled then
        for _, region in next, { btn:GetRegions() } do
            if region:IsObjectType("Texture") then
                region:SetTexture(nil)
                region:Hide()
            end
        end

        if btn.Texture then
            btn.Texture:SetTexture(nil)
            btn.Texture:Hide()
        end
        if btn.Flash then
            btn.Flash:SetTexture(nil)
            btn.Flash:Hide()
        end
        if btn.FlashBorder then
            btn.FlashBorder:SetTexture(nil)
            btn.FlashBorder:Hide()
        end
        if btn.GlowTexture then
            btn.GlowTexture:SetTexture(nil)
            btn.GlowTexture:Hide()
        end

        local hl = btn:GetHighlightTexture()
        if hl then
            hl:SetTexture(nil)
            hl:Hide()
        end

        local normal = btn:GetNormalTexture()
        if normal then
            normal:SetTexture(nil)
            normal:Hide()
        end

        local pushed = btn:GetPushedTexture()
        if pushed then
            pushed:SetTexture(nil)
            pushed:Hide()
        end

        local arrow = btn:CreateTexture(nil, "ARTWORK")
        arrow:SetTexture(ARROW_TEX)
        arrow:SetTexCoord(0, 1, 0, 1)
        arrow:SetSize(14, 14)
        arrow:SetPoint("CENTER")

        btn.Texture = arrow
        btn.KEStyled = true
    end

    local function ApplyInactiveColor()
        if not btn.Texture then return end
        local colorMode = self.db.TabTextColorMode or "custom"
        local customColor = self.db.TabTextColor or cachedTabAccentColor
        local r, g, b = KE:GetAccentColor(colorMode, { customColor.r, customColor.g, customColor.b, 1 })
        btn.Texture:SetVertexColor(r, g, b)
    end

    local function ApplySelectedColor()
        if not btn.Texture then return end
        if self.db.TabSelectedTextEnabled and self.db.TabSelectedTextColor then
            local c = self.db.TabSelectedTextColor
            btn.Texture:SetVertexColor(c.r, c.g, c.b)
        else
            btn.Texture:SetVertexColor(1, 1, 1)
        end
    end

    ApplyInactiveColor()

    if not btn.KEHooked then
        btn:HookScript("OnEnter", ApplySelectedColor)
        btn:HookScript("OnLeave", ApplyInactiveColor)
        btn.KEHooked = true
    end

    if not btn.SetAlphaHooked then
        local origSetAlpha = btn.SetAlpha
        btn.SetAlpha = function(frame, alpha)
            if frame.alerting then
                alpha = 1
            elseif alpha < 0.5 then
                local hooks = CHAT.hooks and CHAT.hooks[_G.GeneralDockManager.primary]
                if not (hooks and hooks.OnEnter) then alpha = 0.5 end
            end
            origSetAlpha(frame, alpha)
        end
        btn.SetAlphaHooked = true
    end
end

function CHAT:PositionChats()
    if not self.panel then return end

    local db = self.db
    local panelWidth = db.Width or PANEL_WIDTH
    local panelHeight = db.Height or PANEL_HEIGHT

    self.panel:SetSize(panelWidth, panelHeight)

    local docker = _G.GeneralDockManager and _G.GeneralDockManager.primary
    if docker then self:PositionChat(docker) end

    for _, frameName in ipairs(_G.CHAT_FRAMES) do
        local chat = _G[frameName]
        if chat and chat ~= docker and self:IsChatValid(chat) then self:PositionChat(chat) end
    end
end

function CHAT:PositionChat(chat)
    if not chat or not self.panel then return end
    if self.isPositioning then return end

    if InCombatLockdown() then
        self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            self:PositionChat(chat)
        end)
        return
    end

    self.isPositioning = true
    self.ChatWindow = self:GetPanelAnchoredChat()

    local docker = _G.GeneralDockManager.primary
    if chat == docker then
        local chatParent = (chat == self.ChatWindow) and self.panel or UIParent
        _G.GeneralDockManager:SetParent(chatParent)
    end

    self:UpdateChatTab(chat)

    if chat:IsMovable() then chat:SetUserPlaced(true) end

    if chat.FontStringContainer then
        chat.FontStringContainer:ClearAllPoints()
        chat.FontStringContainer:SetPoint("TOPLEFT", chat, "TOPLEFT", -3, 3)
        chat.FontStringContainer:SetPoint("BOTTOMRIGHT", chat, "BOTTOMRIGHT", 3, -3)
    end

    local db = self.db
    local panelWidth = db.Width or PANEL_WIDTH
    local panelHeight = db.Height or PANEL_HEIGHT

    local logOffset = 0
    if _G.IsCombatLog and _G.IsCombatLog(chat) then
        local tabBackdropHeight = self.tabBackdrop and self.tabBackdrop:IsShown() and self.tabBackdrop:GetHeight() or
            TAB_HEIGHT
        logOffset = tabBackdropHeight + 4
    end

    if chat == self.ChatWindow then
        chat:SetParent(self.panel)
        chat:ClearAllPoints()
        chat:SetPoint("BOTTOMLEFT", self.panel, "BOTTOMLEFT", H_PADDING, PADDING)
        chat:SetSize(panelWidth - (H_PADDING * 2), panelHeight - BASE_OFFSET - logOffset)

        local tab = self:GetTab(chat)
        if tab and not chat.isDocked then tab:SetParent(self.panel) end

        self:SetBackgroundVisible(chat.Background, false)
    else
        self:SetBackgroundVisible(chat.Background, self:IsFloating(chat, docker))
    end

    if chat.EditModeResizeButton then
        chat.EditModeResizeButton:SetFrameStrata("HIGH")
        chat.EditModeResizeButton:SetFrameLevel(6)
    end

    self.isPositioning = false
end

function CHAT:StyleCombatLog()
    local bar = _G.CombatLogQuickButtonFrame_Custom
    if not bar then return end

    local combatLog = _G.ChatFrame2

    if bar.SetBackdrop and not bar.styled then
        for _, region in pairs({ bar:GetRegions() }) do
            if region:IsObjectType("Texture") then
                region:SetTexture()
            end
        end

        bar:SetBackdrop(BACKDROP_TEMPLATE)
        bar:SetBackdropColor(0, 0, 0, 0.6)
        bar:SetBackdropBorderColor(0, 0, 0, 1)
        bar.styled = true
    end

    bar:ClearAllPoints()
    bar:SetPoint("BOTTOMLEFT", combatLog, "TOPLEFT", -3, 2)
    bar:SetPoint("BOTTOMRIGHT", combatLog, "TOPRIGHT", 3, 2)

    local tex = _G.CombatLogQuickButtonFrame_CustomTexture
    if tex then tex:Hide() end
end

function CHAT:ChatFrame_OnMouseWheel(frame, delta)
    if hyperlinkHoveredFrame == frame then
        hyperlinkHoveredFrame = nil
        GameTooltip:Hide()
    end

    local numScrollMessages = self.db.NumScrollMessages or 3

    if delta < 0 then
        if IsShiftKeyDown() then
            frame:ScrollToBottom()
        elseif IsAltKeyDown() then
            frame:ScrollDown()
        else
            for _ = 1, numScrollMessages do frame:ScrollDown() end
        end
    elseif delta > 0 then
        if IsShiftKeyDown() then
            frame:ScrollToTop()
        elseif IsAltKeyDown() then
            frame:ScrollUp()
        else
            for _ = 1, numScrollMessages do frame:ScrollUp() end
        end
    end
end

function CHAT:ChatFrame_SetScript(frame, scriptType)
    if scriptType == "OnMouseWheel" and not frame.keSettingMouseWheel then
        C_Timer.After(0, function()
            if frame and frame.scriptsSet and not frame.keSettingMouseWheel then
                frame.keSettingMouseWheel = true
                frame:SetScript("OnMouseWheel", function(f, delta) self:ChatFrame_OnMouseWheel(f, delta) end)
                frame.keSettingMouseWheel = nil
            end
        end)
    end
end

function CHAT:UpdatePanel()
    if not self.panel then return end
    local db = self.db

    self.panel:SetSize(db.Width or PANEL_WIDTH, db.Height or PANEL_HEIGHT)
    KE:ApplyFramePosition(self.panel, db.Position, db)
    self.panel:SetFrameStrata("BACKGROUND")

    if self.panel.backdrop then self:ApplyBackdrop(self.panel.backdrop) end
    self:UpdateTabBackdrop()
    self:PositionChats()
end

-- Task 5's GUI callbacks call this to push config changes onto live
-- frames. Note: the reference's ApplySettings also calls
-- self:ApplyGuildMemberStatus() and the file-local RebuildLFGRoles() --
-- both belong to the social/role-icon subsystem Task 4 Step 3b ports;
-- wiring them in here is left to that task, same as OnEnable/OnDisable
-- were left thin in Task 2 for methods that didn't exist yet.
function CHAT:ApplySettings()
    if KE:ShouldNotLoadModule() then return end
    if not self.db.Enabled then return end
    self:UpdateDB()
    self:UpdatePanel()

    for _, frameName in ipairs(_G.CHAT_FRAMES) do
        local chat = _G[frameName]
        if chat then
            self:StyleChat(chat)
            if _G.FCFTab_UpdateAlpha then _G.FCFTab_UpdateAlpha(chat) end
        end
    end

    self:UpdateChatTabs()
    self:UpdateChatTabColors()
    self:UpdateEditboxAnchors()

    if _G.FCFDock_UpdateTabs and _G.GeneralDockManager then
        _G.FCFDock_UpdateTabs(_G.GeneralDockManager, true)
    end
end

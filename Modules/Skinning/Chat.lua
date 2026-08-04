-- ╔══════════════════════════════════════════════════════════╗
-- ║  Chat.lua                                                ║
-- ║  Module: Chat                                            ║
-- ║  Purpose: Chat panel backdrop, positioning, and          ║
-- ║           lifecycle.                                     ║
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
local PlaySoundFile = PlaySoundFile
local GameTooltip = GameTooltip
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local STANDARD_TEXT_FONT = STANDARD_TEXT_FONT
local tconcat = table.concat
local math_max = math.max
local math_min = math.min
local IsInGuild = IsInGuild
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local GetNumGroupMembers = GetNumGroupMembers
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitFullName = UnitFullName
local UnitName = UnitName
local UnitExists = UnitExists
local UnitIsUnit = UnitIsUnit
local Ambiguate = Ambiguate
local _G = _G
local Theme = KE.Theme

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
local COPY_FRAME_WIDTH = 700
local COPY_FRAME_HEIGHT = 300

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
    local width, height = KE.Skins.SafeSize(frame)
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

-- Forward declarations: OnInitialize/OnEnable call these before their
-- file-local definitions (Step 3b, near the end of the file) are reached;
-- assigned there, not re-localized, so this same upvalue is what
-- OnInitialize/OnEnable's closures see.
local RebuildLFGRoles
local BuildGuildStatusPatterns

function CHAT:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
    BuildShortChannelPatterns()
    BuildGuildStatusPatterns()
end

------------------------------------------------------------------------
-- Whisper features (Task 4)
------------------------------------------------------------------------

function CHAT:PlayWhisperSound(soundName)
    if not soundName or soundName == "None" then return end
    local file = KE.LSM and KE.LSM:Fetch("sound", soundName)
    if file then PlaySoundFile(file, "Master") end
end

function CHAT:RegisterWhisperSounds()
    local ws = self.db.WhisperSounds
    if not ws or not ws.Enabled then return end
    if self.whisperSoundsRegistered then return end
    self.whisperSoundsRegistered = true

    -- Read the table fresh on every fire rather than closing over `ws`.
    -- Unchecking the GUI box only sets Enabled = false and calls this
    -- function again, which early-returns without unregistering -- so the
    -- check has to happen here or the sound keeps playing. Reading through
    -- self.db also survives a profile switch, which a captured `ws` would not.
    self:RegisterEvent("CHAT_MSG_WHISPER", function()
        local live = self.db and self.db.WhisperSounds
        if live and live.Enabled then self:PlayWhisperSound(live.WhisperSound) end
    end)
    self:RegisterEvent("CHAT_MSG_BN_WHISPER", function()
        local live = self.db and self.db.WhisperSounds
        if live and live.Enabled then self:PlayWhisperSound(live.BNetWhisperSound) end
    end)
end

-- Taint protection: forces whisper mode to be inline always. Auto-opening
-- new tabs while a secret value is in play on the whisper name causes
-- taint errors.
function CHAT:ForceInlineWhispers()
    if self.inlineWhispersSetup then return end
    self.inlineWhispersSetup = true

    _G.C_CVar.SetCVar("whisperMode", "inline")
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("VARIABLES_LOADED")
    frame:SetScript("OnEvent", function() _G.C_CVar.SetCVar("whisperMode", "inline") end)
end

-- Adds a warning label with a tooltip explaining why New Tab whisper mode
-- is forced to In-line.
function CHAT:AddWhisperModeWarning()
    if self.whisperWarningSetup then return end
    self.whisperWarningSetup = true

    local warningFrame = CreateFrame("Frame", nil, UIParent)
    warningFrame:SetSize(200, 20)
    warningFrame:SetFrameStrata("DIALOG")
    warningFrame:Hide()
    warningFrame:EnableMouse(true)

    local text = warningFrame:CreateFontString(nil, "OVERLAY")
    text:SetPoint("LEFT", 0, 0)
    text:SetJustifyH("LEFT")
    text:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    text:SetShadowColor(0, 0, 0, 0)
    text:SetText(KE:ColorTextByTheme("KitnEssentials") .. "\nNew Tab disabled")

    warningFrame:SetScript("OnEnter", function(frame)
        GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
        GameTooltip:AddLine("KitnEssentials: New Tab Disabled", Theme.accent[1], Theme.accent[2], Theme.accent[3])
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(
            "The 'New Tab' whisper mode causes taint errors when clicking on whisper tabs with secret player names.",
            1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("KitnEssentials forces 'In-line' mode to prevent these errors.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)

    warningFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local function UpdateWarningPosition()
        local settingsPanel = _G.SettingsPanel
        if not settingsPanel or not settingsPanel:IsShown() then
            warningFrame:Hide()
            return
        end

        local scrollBox = settingsPanel.Container and settingsPanel.Container.SettingsList and
            settingsPanel.Container.SettingsList.ScrollBox
        if not scrollBox or not scrollBox.ScrollTarget then
            warningFrame:Hide()
            return
        end

        for _, child in pairs({ scrollBox.ScrollTarget:GetChildren() }) do
            local labelText = child.Text and child.Text:GetText()
            if labelText == "New Whispers" and child:IsShown() then
                warningFrame:SetParent(child)
                warningFrame:ClearAllPoints()
                warningFrame:SetPoint("LEFT", child.Text, "RIGHT", 300, 2)
                warningFrame:Show()
                return
            end
        end

        warningFrame:Hide()
    end

    local function SetupHooks()
        if _G.SettingsPanel then
            hooksecurefunc(_G.SettingsPanel, "Show", UpdateWarningPosition)
            hooksecurefunc(_G.SettingsPanel, "Hide", function() warningFrame:Hide() end)
        end
        if _G.SettingsPanel and _G.SettingsPanel.Container and _G.SettingsPanel.Container.SettingsList then
            hooksecurefunc(_G.SettingsPanel.Container.SettingsList.ScrollBox, "Update", UpdateWarningPosition)
        end
    end

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("ADDON_LOADED")
    frame:SetScript("OnEvent", function(_, _, addon)
        if addon == "Blizzard_Settings" or addon == "Blizzard_SettingsDefinitions_Frame" then
            C_Timer.After(0.5, SetupHooks)
        end
    end)

    SetupHooks()
end

function CHAT:OnEnable()
    if KE:ShouldNotLoadModule() then return end
    if not self.db.Enabled then return end
    self:UpdateDB()
    self:BuildCopyChatFrame()
    self:CreateChatPanel()

    self:SetupChat()
    self:RegisterEditMode()
    self:SetupBlizzardEditModeLock()
    self:RegisterWhisperSounds()
    self:ForceInlineWhispers()
    self:AddWhisperModeWarning()
    self:SetupSocialEvents()
    self:ApplyGuildMemberStatus()
    RebuildLFGRoles()

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

    if _G.EditModeManagerFrame then
        self:SecureHook(_G.EditModeManagerFrame, "UpdateLayoutInfo", "OnEditModeLayoutChange")
    end
end

-- OnDisable must reverse everything OnEnable and the styling pass did, not
-- just hide the panel: unlike the sibling Skin* modules, Chat does not
-- match ProfileManager's "^Skin" gate, so a GUI toggle disables it LIVE
-- (see CHAT.keDeferToReload's note at the top of this file for the
-- reload-deferred path, which is the primary protection; this teardown is
-- the backstop for every other path that reaches OnDisable).
function CHAT:OnDisable()
    if KE.ChatMessageHandler and KE.ChatMessageHandler.lfgRoles then
        wipe(KE.ChatMessageHandler.lfgRoles)
    end

    self:UnregisterEvent("UPDATE_CHAT_WINDOWS")
    self:UnregisterEvent("UPDATE_FLOATING_CHAT_WINDOWS")
    self:UnregisterEvent("CVAR_UPDATE")
    self:UnregisterEvent("CHAT_MSG_WHISPER")
    self:UnregisterEvent("CHAT_MSG_BN_WHISPER")
    self.whisperSoundsRegistered = false

    self:TeardownSocialEvents()
    self:TeardownGuildMemberStatus()

    self:UnhookAll()
    self._inviteLinkHooked = false

    self:RestoreAllChats()
    self:UnregisterEditMode()
    self.hooksSecured = false
    self.blizzEditModeLockSetup = false

    if self.CopyChatFrame then self.CopyChatFrame:Hide() end
    if self.panel then self.panel:Hide() end
end

------------------------------------------------------------------------
-- Edit mode (Task 4)
------------------------------------------------------------------------

function CHAT:RegisterEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "Chat", displayName = "Chat", frame = self.panel,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos)
                self.db.Position = pos
                KE:ApplyFramePosition(self.panel, self.db.Position, self.db)
                self.panel:SetFrameStrata("BACKGROUND")
            end,
            getParentFrame = function()
                return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)
            end,
            guiPath = "Chat",
        })
        self.editModeRegistered = true
    end
end

function CHAT:UnregisterEditMode()
    if KE.EditMode then KE.EditMode:UnregisterElement("Chat") end
    self.editModeRegistered = false
end

function CHAT:OnEditModeLayoutChange()
    self:PositionChats()
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

function CHAT:FrameOverlapsPanel(frame)
    if not frame or not self.panel then return false end

    local frameLeft, frameBottom, frameWidth, frameHeight = KE.Skins.SafeRect(frame)
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

    -- BN colorize runs BEFORE the |K protection check below: BN messages
    -- ALWAYS contain |K names, so MessageIsProtected is true for every
    -- one of them.
    local db = self.db
    if db.ClassColorWhispers ~= false and strfind(msg, "|HBNplayer:", 1, true) then
        msg = ColorizeBNSenders(msg)
    end

    -- Protected messages skip the string-parsing steps below (the
    -- strmatch early-return and HandleShortChannels' gsub rewrite) but
    -- still fall through to the timestamp block, which only prepends via
    -- format and never parses the |K payload. Matches ElvUI's
    -- AddMessageEdits (ElvUI/Game/Shared/Modules/Chat/Chat.lua),
    -- which uses the same isProtected flag only to skip its strmatch guards.
    local isProtected = self:MessageIsProtected(msg)

    if not isProtected then
        if strmatch(msg, '^%s*$') or strmatch(msg, '^|Hketime|h') then return msg end
    end

    local historyTimestamp
    if isHistory == "KE_ChatHistory" then historyTimestamp = historyTime end
    if not isProtected and db.ShortChannels then msg = self:HandleShortChannels(msg, false) end
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
        local resizeButton = chat.EditModeResizeButton
        resizeButton.keOldStrata = resizeButton.keOldStrata or resizeButton:GetFrameStrata()
        resizeButton.keOldFrameLevel = resizeButton.keOldFrameLevel or resizeButton:GetFrameLevel()
        resizeButton:SetFrameStrata("HIGH")
        resizeButton:SetFrameLevel(6)
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
        -- Rewind history to the newest entry every time the box is opened.
        -- Set synchronously, not inside the deferred call below, so it lands
        -- before the first key press. See the AddHistoryLine hook for why.
        eb.historyIndex = 0
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
                -- Setting historyIndex to 0 once at style time is not enough:
                -- the index then carries over between uses, so after browsing
                -- back three entries the next Up resumes from there instead
                -- of the newest line. Reset on every send as well as on
                -- focus, so Up always starts at the most recent message.
                eb.historyIndex = 0
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

------------------------------------------------------------------------
-- Chat copy feature (Task 4)
------------------------------------------------------------------------

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
    frame:SetBackdropColor(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], Theme.bgDark[4])
    frame:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
    frame:SetSize(COPY_FRAME_WIDTH, COPY_FRAME_HEIGHT)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    frame:Hide()
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetResizable(true)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(f) f:StartMoving() end)
    frame:SetScript("OnDragStop", function(f) f:StopMovingOrSizing() end)
    self.CopyChatFrame = frame

    local header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    header:SetHeight(HEADER_HEIGHT)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    header:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    header:SetBackdropColor(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], Theme.bgDark[4] or 1)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() frame:StartMoving() end)
    header:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
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
    title:SetFont(cachedFontPath, 14, "OUTLINE")
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
    hint:SetFont(cachedFontPath, 13, "OUTLINE")
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
    scrollbar:SetBackdropColor(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], 0.5)
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
    editBox:SetFont(cachedFontPath, 15, "OUTLINE")
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

    -- Chevron icon (collapse.tga, same texture as the sidebar section
    -- headers) rotated to point right; accent-independent (always white).
    local icon = copyButton:CreateTexture(nil, "OVERLAY")
    icon:SetSize(14, 14)
    icon:SetPoint("CENTER", copyButton, "CENTER", 0, 0)
    icon:SetTexture(ARROW_TEX)
    icon:SetRotation(math.pi / 2)
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

    if tab and not (_G.IsCombatLog and _G.IsCombatLog(chat)) then
        tab.keOldOnClick = tab.keOldOnClick or tab:GetScript("OnClick")
        tab:SetScript("OnClick", CHAT.Tab_OnClick)
    end

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
            clampedToScreen = chat.IsClampedToScreen and chat:IsClampedToScreen(),
        }

        if chat.GetClampRectInsets then
            self.originalStates[id].clampRectInsets = { chat:GetClampRectInsets() }
        end

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
    chat.keStyled = true
end

local HiddenFrame = CreateFrame("Frame")
HiddenFrame:Hide()

-- `list`, when passed, collects every object touched (this one plus all
-- recursed-into children) in a flat sequence so RestoreDisabledFrame can
-- restore each one directly instead of re-walking the tree: DisableFrame
-- reparents children to HiddenFrame before reparenting the object itself,
-- so by restore time the children are no longer object:GetChildren().
function CHAT:DisableFrame(object, list)
    if not object then return end

    if object.GetChildren then for _, child in pairs({ object:GetChildren() }) do self:DisableFrame(child, list) end end
    if object.UnregisterAllEvents then
        -- UnregisterAllEvents has no inverse query API, so the events this
        -- drops cannot be recovered on restore; the reparent and the Hide
        -- below are the only pieces of this that are capturable. The same
        -- irreversible call also happens inside ClearFrameTextures(frame, true).
        object:UnregisterAllEvents()
        object.keOldParent = object.keOldParent or object:GetParent()
        object:SetParent(HiddenFrame)
    else
        object.keOldShow = object.keOldShow or object.Show
        object.Show = object.Hide
    end
    object:Hide()

    if list then list[#list + 1] = object end
end

-- Reverses the capturable half of DisableFrame (reparent + Show override)
-- for a single object; see the comment there for what cannot be undone.
function CHAT:RestoreDisabledFrame(object)
    if not object then return end

    if object.keOldParent then
        object:SetParent(object.keOldParent)
        object.keOldParent = nil
    end
    if object.keOldShow then
        object.Show = object.keOldShow
        object.keOldShow = nil
    end
    object:Show()
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

    chat.keDisabledObjects = chat.keDisabledObjects or {}
    local list = chat.keDisabledObjects

    if chat.ScrollBar then self:DisableFrame(chat.ScrollBar, list) end
    if chat.ScrollToBottomButton then self:DisableFrame(chat.ScrollToBottomButton, list) end

    local thumbTexture = _G[name .. "ThumbTexture"]
    if thumbTexture then self:DisableFrame(thumbTexture, list) end

    local minimize = _G[name .. "MinimizeButton"]
    if minimize then self:DisableFrame(minimize, list) end

    local editLeft = _G[name .. "EditBoxLeft"]
    if editLeft then self:DisableFrame(editLeft, list) end

    local editMid = _G[name .. "EditBoxMid"]
    if editMid then self:DisableFrame(editMid, list) end

    local editRight = _G[name .. "EditBoxRight"]
    if editRight then self:DisableFrame(editRight, list) end
end

-- Reverses the DisableFrame calls HideChatElements made by restoring the
-- flat list of objects DisableFrame actually touched (itself plus every
-- recursed-into child), rather than re-walking the object tree: those
-- children are no longer reachable via GetChildren() once DisableFrame has
-- reparented them to HiddenFrame.
function CHAT:RestoreChatElements(chat)
    if not chat.keDisabledObjects then return end

    for _, object in ipairs(chat.keDisabledObjects) do
        self:RestoreDisabledFrame(object)
    end

    chat.keDisabledObjects = nil
end

function CHAT:PositionButtonFrame(chat)
    if not chat.buttonFrame then return end
    local buttonFrame = chat.buttonFrame

    if not buttonFrame.keOldPoints then
        buttonFrame.keOldPoints = {}
        for i = 1, buttonFrame:GetNumPoints() do
            buttonFrame.keOldPoints[i] = { buttonFrame:GetPoint(i) }
        end
        buttonFrame.keOldClipsChildren = buttonFrame:DoesClipChildren()
    end

    buttonFrame:ClearAllPoints()
    buttonFrame:SetPoint("TOP", chat, "BOTTOM", 0, -90000)
    buttonFrame:SetClipsChildren(true)
end

-- Reverses PositionButtonFrame's reparent-off-screen and clips-children
-- override.
function CHAT:RestoreButtonFrame(chat)
    local buttonFrame = chat.buttonFrame
    if not buttonFrame or not buttonFrame.keOldPoints then return end

    buttonFrame:ClearAllPoints()
    for _, pointData in ipairs(buttonFrame.keOldPoints) do
        if pointData[2] then
            buttonFrame:SetPoint(pointData[1], pointData[2], pointData[3], pointData[4], pointData[5])
        end
    end
    buttonFrame:SetClipsChildren(buttonFrame.keOldClipsChildren or false)

    buttonFrame.keOldPoints = nil
    buttonFrame.keOldClipsChildren = nil
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
        chat.keOldOnEvent = chat.keOldOnEvent or chat:GetScript("OnEvent")
        chat:SetScript("OnEvent", function(frame, event, ...)
            KE.ChatMessageHandler:FloatingChatFrame_OnEvent(frame, event, ...)
        end)
    end

    chat.keOldOnMouseWheel = chat.keOldOnMouseWheel or chat:GetScript("OnMouseWheel")
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

    local overflowList = _G.GeneralDockManagerOverflowButtonList
    if overflowList then
        overflowList.keOldStrata = overflowList.keOldStrata or overflowList:GetFrameStrata()
        overflowList.keOldFrameLevel = overflowList.keOldFrameLevel or overflowList:GetFrameLevel()
        overflowList:SetFrameStrata("LOW")
        overflowList:SetFrameLevel(5)
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
        btn.keOldSetAlpha = btn.keOldSetAlpha or btn.SetAlpha
        local origSetAlpha = btn.keOldSetAlpha
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
        local resizeButton = chat.EditModeResizeButton
        resizeButton.keOldStrata = resizeButton.keOldStrata or resizeButton:GetFrameStrata()
        resizeButton.keOldFrameLevel = resizeButton.keOldFrameLevel or resizeButton:GetFrameLevel()
        resizeButton:SetFrameStrata("HIGH")
        resizeButton:SetFrameLevel(6)
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
                frame.keOldOnMouseWheel = frame.keOldOnMouseWheel or frame:GetScript("OnMouseWheel")
                frame.keSettingMouseWheel = true
                frame:SetScript("OnMouseWheel", function(f, delta) self:ChatFrame_OnMouseWheel(f, delta) end)
                frame.keSettingMouseWheel = nil
            end
        end)
    end
end

------------------------------------------------------------------------
-- Teardown (Task 4)
------------------------------------------------------------------------

function CHAT:RestoreAllChats()
    for _, frameName in ipairs(_G.CHAT_FRAMES) do
        local chat = _G[frameName]
        if chat then self:RestoreChat(chat) end
    end

    self:RestoreDockManager()
    self.originalStates = {}
    self.ChatWindow = nil
end

function CHAT:RestoreChat(chat)
    if not chat then return end

    local id = chat:GetID()
    local tab = self:GetTab(chat)

    -- Scripts/child-frame mutations only ever happened if the styling pass
    -- reached its one-time block for this frame (chat.keStyled); gating on
    -- it here keeps an untouched frame (e.g. the combat log) from having
    -- SetScript(..., nil) called on it and losing Blizzard's own handler.
    -- Checked BEFORE the originalStates[id] lookup below: OnFCF_Close nils
    -- originalStates[id] on window close while leaving keStyled and the
    -- keOld* saves set, so gating this block on state instead would skip
    -- it forever for any chat window closed during the session.
    if chat.keStyled then
        if chat.keOldOnEvent then chat:SetScript("OnEvent", chat.keOldOnEvent) end
        if chat.keOldOnMouseWheel then chat:SetScript("OnMouseWheel", chat.keOldOnMouseWheel) end
        chat.AddMessage = chat.OldAddMessage or chat.AddMessage
        if tab and tab.keOldOnClick then tab:SetScript("OnClick", tab.keOldOnClick) end

        self:RestoreChatElements(chat)
        self:RestoreButtonFrame(chat)
        if chat.copyButton then chat.copyButton:Hide() end

        if chat.Selection and (chat.Selection.keOldOnDragStart ~= nil or chat.Selection.keOldOnDragStop ~= nil) then
            local selection = chat.Selection
            selection:SetScript("OnDragStart", selection.keOldOnDragStart)
            selection:SetScript("OnDragStop", selection.keOldOnDragStop)
            selection:EnableMouse(true)
            selection.keOldOnDragStart, selection.keOldOnDragStop = nil, nil
        end

        if chat.EditModeResizeButton then
            local resizeButton = chat.EditModeResizeButton
            if resizeButton.keOldShow then
                resizeButton.Show = resizeButton.keOldShow
                resizeButton.keOldShow = nil
                resizeButton:EnableMouse(true)
            end
            if resizeButton.keOldStrata then
                resizeButton:SetFrameStrata(resizeButton.keOldStrata)
                resizeButton:SetFrameLevel(resizeButton.keOldFrameLevel)
                resizeButton.keOldStrata, resizeButton.keOldFrameLevel = nil, nil
            end
        end

        chat.OldAddMessage, chat.keOldOnEvent, chat.keOldOnMouseWheel = nil, nil, nil
        if tab then tab.keOldOnClick = nil end

        -- StyleEditbox early-returns on editbox.styled, but OnDisable's
        -- UnhookAll has already removed the hooks that flag stands for. Left
        -- set, a disable then re-enable in the same session silently loses
        -- focus-shows-panel, Up/Down history recall and the chat-type border
        -- for the rest of the session.
        if chat.editBox then chat.editBox.styled = nil end

        chat.keStyled = nil
    end

    local state = self.originalStates[id]
    if not state then
        chat.styled = nil
        chat.scriptsSet = nil
        return
    end

    if state.parent then chat:SetParent(state.parent) end
    if state.points then
        chat:ClearAllPoints()
        for _, pointData in ipairs(state.points) do
            if pointData[2] then
                chat:SetPoint(pointData[1], pointData[2], pointData[3], pointData[4], pointData[5])
            end
        end
    end

    if state.width and state.height then chat:SetSize(state.width, state.height) end
    if state.frameLevel then chat:SetFrameLevel(state.frameLevel) end
    if state.timeVisible then chat:SetTimeVisible(state.timeVisible) end
    if state.maxLines then chat:SetMaxLines(state.maxLines) end
    if state.fading ~= nil then chat:SetFading(state.fading) end
    if state.clampRectInsets then chat:SetClampRectInsets(unpack(state.clampRectInsets)) end
    if state.clampedToScreen ~= nil then chat:SetClampedToScreen(state.clampedToScreen) end

    if tab and state.tabParent then tab:SetParent(state.tabParent) end
    if chat.Background then
        chat.Background.Show = nil
        if state.backgroundShown then chat.Background:Show() end
    end

    chat.styled = nil
    chat.scriptsSet = nil
end

function CHAT:RestoreDockManager()
    local docker = _G.GeneralDockManager
    if not docker or not self.originalDockState then return end
    if self.originalDockState.parent then docker:SetParent(self.originalDockState.parent) end
    if self.originalDockState.points then
        docker:ClearAllPoints()
        for _, pointData in ipairs(self.originalDockState.points) do
            if pointData[2] then docker:SetPoint(pointData[1], pointData[2], pointData[3], pointData[4], pointData[5]) end
        end
    end
    self.originalDockState = nil

    local overflowList = _G.GeneralDockManagerOverflowButtonList
    if overflowList and overflowList.keOldStrata then
        overflowList:SetFrameStrata(overflowList.keOldStrata)
        overflowList:SetFrameLevel(overflowList.keOldFrameLevel)
        overflowList.keOldStrata, overflowList.keOldFrameLevel = nil, nil
    end

    local overflowBtn = _G.GeneralDockManagerOverflowButton
    if overflowBtn and overflowBtn.SetAlphaHooked then
        overflowBtn.SetAlpha = overflowBtn.keOldSetAlpha
        overflowBtn.keOldSetAlpha = nil
        overflowBtn.SetAlphaHooked = nil
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

------------------------------------------------------------------------
-- Social status and role icons (Task 4 Step 3b)
------------------------------------------------------------------------
-- Guild member login/logout messages -- rewrites the system lines with
-- class-colored names, green (online) / red (offline), via the official
-- ChatFrameUtil.AddMessageEventFilter pipeline on CHAT_MSG_SYSTEM (returns
-- a modified message, so it works in both the default chat and the panel).
-- Class cache built from GetGuildRosterInfo on GUILD_ROSTER_UPDATE only --
-- no polling. [Invite] link on guild logins dispatched from a secure
-- post-hook on ItemRefTooltip:SetHyperlink. Role icons before names in
-- group chat -- lfgRoles cache rebuilt on GROUP_ROSTER_UPDATE, consumed at
-- the pflag site in ChatMessageHandler.
--
-- These installs are panel-DEPENDENT (wired from OnEnable/OnDisable), not
-- installed once at OnInitialize, so the three config keys
-- (GuildMemberStatus, GuildMemberStatusInviteLink, RoleIcons) only take
-- effect while the Chat module itself is enabled.
local guildPlayerCache = {}
local guildStatusFilterActive = false
local socialEventFrame

local offlineMessageTemplate, offlineMessagePattern
local onlineMessageTemplate, onlineMessagePattern
function BuildGuildStatusPatterns()
    if offlineMessagePattern then return end
    offlineMessageTemplate = "%s" .. _G.ERR_FRIEND_OFFLINE_S
    offlineMessagePattern = format("^%s$", (gsub(_G.ERR_FRIEND_OFFLINE_S, "%%s", "(.+)")))
    onlineMessageTemplate = (gsub(_G.ERR_FRIEND_ONLINE_SS, "%[%%s%]", "%%s%%s"))
    onlineMessagePattern = format("^%s$",
        (gsub(_G.ERR_FRIEND_ONLINE_SS, "|Hplayer:%%s|h%[%%s%]|h", "|Hplayer:(.+)|h%%[(.+)%%]|h")))
end

local GREEN_ONLINE = "4ade80"
local RED_OFFLINE = "f43f5e"
-- Resolved per call, never at file scope: the theme DB does not exist yet
-- when this file parses, and a captured hex would freeze at the fallback.
local function BrandHex()
    return (KE.GetThemeColorHex and KE:GetThemeColorHex()) or "FF008C"
end

local function RebuildGuildCache()
    wipe(guildPlayerCache)
    if not IsInGuild() then return end
    for i = 1, (_G.GetNumGuildMembers() or 0) do
        local name, _, _, _, _, _, _, _, _, _, classFile = _G.GetGuildRosterInfo(i)
        if name and classFile then
            guildPlayerCache[Ambiguate(name, "none")] = classFile
        end
    end
end

local function ClassColoredName(name, classFile)
    local color = classFile and RAID_CLASS_COLORS[classFile]
    if color and color.colorStr then
        return format("|c%s%s|r", color.colorStr, name)
    end
    return name
end

local function GuildStatusFilter(_, _, msg, ...)
    local db = CHAT.db
    if not (db and db.GuildMemberStatus) then return false end
    if type(msg) ~= "string" then return false end

    local link, name = nil, strmatch(msg, offlineMessagePattern)
    if not name then
        link, name = strmatch(msg, onlineMessagePattern)
    end
    if not name then return false end

    local class = guildPlayerCache[name] or (link and guildPlayerCache[link])
    if not class then return false end -- not a guildmate; leave the line alone

    local displayName = (db.ShortChannels ~= false) and Ambiguate(name, "short") or name
    local coloredName = ClassColoredName(displayName, class)

    if link then -- online
        local resultText = format(onlineMessageTemplate, link, "", coloredName)
        resultText = format("|cff%s%s|r", GREEN_ONLINE, resultText)
        if db.GuildMemberStatusInviteLink then
            resultText = resultText .. format(" |Hkeslink:invite:%s|h|cff%s[Invite]|r|h", link, BrandHex())
        end
        return false, resultText, select(1, ...)
    else -- offline
        local resultText = format(offlineMessageTemplate, "", coloredName)
        return false, format("|cff%s%s|r", RED_OFFLINE, resultText), select(1, ...)
    end
end

function CHAT:OnInviteLinkClick(_, data)
    if type(data) ~= "string" or strsub(data, 1, 7) ~= "keslink" then return end
    local feature, arg = strmatch(data, "^keslink:([^:]+):(.*)$")
    if feature == "invite" and arg and arg ~= "" then
        if _G.C_PartyInfo and _G.C_PartyInfo.InviteUnit then
            _G.C_PartyInfo.InviteUnit(arg)
        elseif _G.InviteUnit then
            _G.InviteUnit(arg)
        end
    end
end

function CHAT:ApplyGuildMemberStatus()
    local db = self.db
    local want = db and db.GuildMemberStatus ~= false
    if want and not guildStatusFilterActive then
        if _G.ChatFrameUtil and _G.ChatFrameUtil.AddMessageEventFilter then
            _G.ChatFrameUtil.AddMessageEventFilter("CHAT_MSG_SYSTEM", GuildStatusFilter)
        elseif _G.ChatFrame_AddMessageEventFilter then
            _G.ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", GuildStatusFilter)
        end
        guildStatusFilterActive = true
        if not self._inviteLinkHooked then
            self:SecureHook(_G.ItemRefTooltip, "SetHyperlink", "OnInviteLinkClick")
            self._inviteLinkHooked = true
        end
    elseif not want and guildStatusFilterActive then
        self:RemoveGuildMemberStatusFilter()
    end
end

function CHAT:RemoveGuildMemberStatusFilter()
    if not guildStatusFilterActive then return end
    if _G.ChatFrameUtil and _G.ChatFrameUtil.RemoveMessageEventFilter then
        _G.ChatFrameUtil.RemoveMessageEventFilter("CHAT_MSG_SYSTEM", GuildStatusFilter)
    elseif _G.ChatFrame_RemoveMessageEventFilter then
        _G.ChatFrame_RemoveMessageEventFilter("CHAT_MSG_SYSTEM", GuildStatusFilter)
    end
    guildStatusFilterActive = false
end

function CHAT:TeardownGuildMemberStatus()
    self:RemoveGuildMemberStatusFilter()
end

-- Role icon textures: Blizzard's own group-finder role atlases (the same
-- atlas names PrescienceTracker uses for its role badges), so there is no
-- custom art to ship and no broken texture path.
local ROLE_ICON_ATLASES = {
    TANK    = "groupfinder-icon-role-large-tank",
    HEALER  = "groupfinder-icon-role-large-heal",
    DAMAGER = "groupfinder-icon-role-large-dps",
}

local ROLE_ICON_STRINGS
local function BuildRoleIconStrings()
    if ROLE_ICON_STRINGS then return end
    ROLE_ICON_STRINGS = {}
    for role, atlas in pairs(ROLE_ICON_ATLASES) do
        ROLE_ICON_STRINGS[role] = format("|A:%s:14:14|a", atlas)
    end
end

function RebuildLFGRoles()
    local CMH = KE.ChatMessageHandler
    if not CMH then return end
    wipe(CMH.lfgRoles)

    local db = CHAT.db
    if not (db and db.Enabled and db.RoleIcons ~= false) then return end
    if not IsInGroup() then return end
    BuildRoleIconStrings()

    local myRole = UnitGroupRolesAssigned("player")
    local myName, myRealm = UnitFullName("player")
    if myRole and myName and ROLE_ICON_STRINGS[myRole] then
        CMH.lfgRoles[myName] = ROLE_ICON_STRINGS[myRole]
        if myRealm and myRealm ~= "" then
            CMH.lfgRoles[myName .. "-" .. myRealm] = ROLE_ICON_STRINGS[myRole]
        end
    end

    local unit = IsInRaid() and "raid" or "party"
    for i = 1, GetNumGroupMembers() do
        local u = unit .. i
        if UnitExists(u) and not UnitIsUnit(u, "player") then
            local role = UnitGroupRolesAssigned(u)
            local icon = role and ROLE_ICON_STRINGS[role]
            local name, realm = UnitName(u)
            if icon and name then
                CMH.lfgRoles[name] = icon
                if realm and realm ~= "" then
                    CMH.lfgRoles[name .. "-" .. realm] = icon
                end
            end
        end
    end
end

-- Guarded on the registration state (self.socialEventsRegistered), not the
-- frame's existence: the frame itself is a harmless one-time allocation,
-- but after a disable/re-enable cycle the frame already exists, and an
-- existence-only guard would silently skip re-registering its events.
function CHAT:SetupSocialEvents()
    if self.socialEventsRegistered then return end

    if not socialEventFrame then
        socialEventFrame = CreateFrame("Frame")
        socialEventFrame:SetScript("OnEvent", function(_, event)
            if event == "GROUP_ROSTER_UPDATE" then
                RebuildLFGRoles()
            else
                RebuildGuildCache()
                if event == "PLAYER_ENTERING_WORLD" then
                    if _G.C_GuildInfo and _G.C_GuildInfo.GuildRoster then _G.C_GuildInfo.GuildRoster() end
                    RebuildLFGRoles()
                end
            end
        end)
    end

    socialEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    socialEventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
    socialEventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    self.socialEventsRegistered = true
end

function CHAT:TeardownSocialEvents()
    if socialEventFrame then socialEventFrame:UnregisterAllEvents() end
    self.socialEventsRegistered = false
end

-- Task 5's GUI callbacks call this to push config changes onto live
-- frames.
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

    self:ApplyGuildMemberStatus()
    RebuildLFGRoles()
end

------------------------------------------------------------------------
-- Blizzard Edit Mode lock (Task 4)
------------------------------------------------------------------------
-- Prevents dragging/resizing chat in Blizzard's own Edit Mode and shows
-- helper text redirecting to KE's edit mode instead.
local blizzEditModeLockState = setmetatable({}, { __mode = "k" })

function CHAT:GetBlizzEditModeLockState(selection)
    local state = blizzEditModeLockState[selection]
    if not state then
        state = {}
        blizzEditModeLockState[selection] = state
    end
    return state
end

function CHAT:EnsureBlizzEditModeLockText(selection)
    if not selection then return end
    local state = self:GetBlizzEditModeLockState(selection)
    if state.lockText then return end

    if not state.textOverlay then
        state.textOverlay = CreateFrame("Frame", nil, UIParent)
        state.textOverlay:SetAllPoints(selection)
        state.textOverlay:SetFrameStrata("TOOLTIP")
        state.textOverlay:SetFrameLevel(selection:GetFrameLevel() + 5)
    end

    local text = state.textOverlay:CreateFontString(nil, "OVERLAY")
    text:SetIgnoreParentScale(true)
    text:SetPoint("CENTER")
    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")
    text:SetWordWrap(true)
    state.lockText = text
end

function CHAT:SetBlizzEditModeLockText(frame, shown)
    if InCombatLockdown() then return end

    local selection = frame.Selection
    if not selection then return end

    if not shown then
        local state = blizzEditModeLockState[selection]
        if state then
            if state.lockText then state.lockText:Hide() end
            if state.textOverlay then state.textOverlay:Hide() end
        end
        return
    end

    self:EnsureBlizzEditModeLockText(selection)
    local state = self:GetBlizzEditModeLockState(selection)
    local text = state.lockText
    if state.textOverlay then state.textOverlay:Show() end

    local fontPath = KE.FONT or STANDARD_TEXT_FONT
    text:SetFont(fontPath, 12, "OUTLINE")
    text:SetShadowColor(0, 0, 0, 0)
    text:SetShadowOffset(0, 0)
    text:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)

    local maxWidth = selection:GetWidth() - 12
    if maxWidth > 0 then text:SetWidth(maxWidth) end

    text:SetText("Edit Mode locked for the chat\nUse |cff00ff00/kes edit|r or |cff00ff00/kes|r -> Chat")
    text:Show()
end

function CHAT:SetupBlizzEditModeLockHandlers(frame)
    if InCombatLockdown() then return end

    local selection = frame.Selection
    if not selection then return end

    local state = self:GetBlizzEditModeLockState(selection)
    if state.handlersSet then return end

    state.handlersSet = true

    selection:HookScript("OnMouseDown", function()
        self:SetBlizzEditModeLockText(frame, true)
        state.lockTextToken = (state.lockTextToken or 0) + 1
        local token = state.lockTextToken
        C_Timer.After(3, function()
            if state.lockTextToken == token then self:SetBlizzEditModeLockText(frame, false) end
        end)
    end)

    selection:HookScript("OnHide", function() self:SetBlizzEditModeLockText(frame, false) end)
end

function CHAT:LockChatInBlizzEditMode(chat)
    if not chat then return end
    if InCombatLockdown() then return end

    local selection = chat.Selection
    if selection then
        selection.keOldOnDragStart = selection.keOldOnDragStart or selection:GetScript("OnDragStart")
        selection.keOldOnDragStop = selection.keOldOnDragStop or selection:GetScript("OnDragStop")
        selection:SetScript("OnDragStart", nil)
        selection:SetScript("OnDragStop", nil)
        selection:EnableMouse(false)
    end

    if chat.EditModeResizeButton then
        chat.EditModeResizeButton:Hide()
        chat.EditModeResizeButton:EnableMouse(false)
        chat.EditModeResizeButton.keOldShow = chat.EditModeResizeButton.keOldShow or chat.EditModeResizeButton.Show
        chat.EditModeResizeButton.Show = chat.EditModeResizeButton.Hide
    end

    self:SetupBlizzEditModeLockHandlers(chat)
    self:SetBlizzEditModeLockText(chat, false)
end

function CHAT:SetupBlizzardEditModeLock()
    if self.blizzEditModeLockSetup then return end

    local function TrySetup()
        local EditModeSystemSettingsDialog = _G.EditModeSystemSettingsDialog
        if not EditModeSystemSettingsDialog then return false end

        local chatFrame = _G.ChatFrame1
        if not chatFrame then return false end

        hooksecurefunc(EditModeSystemSettingsDialog, "AttachToSystemFrame", function(dialog, systemFrame)
            if not systemFrame then return end
            local name = systemFrame:GetName()
            if not name then return end

            if strmatch(name, "^ChatFrame%d+$") then
                dialog:Hide()
                self:SetupBlizzEditModeLockHandlers(systemFrame)
                if not self.blizzEditModeChatNoticeShown then
                    KE:Print("Chat position is managed by |cff00ff00/kes edit|r or |cff00ff00/kes|r settings.")
                    self.blizzEditModeChatNoticeShown = true
                end
            end
        end)

        for i = 1, 12 do
            local chat = _G["ChatFrame" .. i]
            if chat then
                if chat.SelectSystem then
                    hooksecurefunc(chat, "SelectSystem", function(cf)
                        if EditModeSystemSettingsDialog.attachedToSystem == cf then EditModeSystemSettingsDialog:Hide() end
                        self:SetupBlizzEditModeLockHandlers(cf)
                        if cf.Selection then cf.Selection:EnableMouse(false) end
                        if not self.blizzEditModeChatNoticeShown then
                            KE:Print(
                                "Chat position is managed by |cff00ff00/kes edit|r or |cff00ff00/kes|r settings.")
                            self.blizzEditModeChatNoticeShown = true
                        end
                    end)
                end

                if chat.HighlightSystem then
                    hooksecurefunc(chat, "HighlightSystem", function(cf) self:SetupBlizzEditModeLockHandlers(cf) end)
                end
                if chat.ClearHighlight then
                    hooksecurefunc(chat, "ClearHighlight", function(cf) self:SetBlizzEditModeLockText(cf, false) end)
                end

                self:LockChatInBlizzEditMode(chat)
            end
        end

        self.blizzEditModeLockSetup = true
        return true
    end

    if not TrySetup() then
        _G.EventUtil.ContinueOnAddOnLoaded("Blizzard_EditMode", function() TrySetup() end)
    end
end

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
local tinsert = tinsert
local gsub = string.gsub
local strmatch = string.match
local _G = _G

local PANEL_HEIGHT = 250
local PANEL_WIDTH = 450
local PANEL_FRAME_LEVEL = 300

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

function CHAT:UpdateDB()
    self.db = KE.db.profile.Skinning.Chat
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
end

function CHAT:OnDisable()
    if self.panel then self.panel:Hide() end
end

function CHAT:CreateChatPanel()
    if self.panel then
        self.panel:Show()
        if self.panel.backdrop then self.panel.backdrop:Show() end
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

-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local SK = KitnEssentials:NewModule("SkinTooltips", "AceEvent-3.0", "AceHook-3.0")

-- Localization
local hooksecurefunc = hooksecurefunc
local issecretvalue = issecretvalue
local pcall = pcall
local UnitIsPlayer = UnitIsPlayer
local UnitClass = UnitClass
local UnitIsConnected = UnitIsConnected
local UnitIsTapDenied = UnitIsTapDenied
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local GetGuildInfo = GetGuildInfo
local UnitRace = UnitRace
local UnitLevel = UnitLevel
local IsInInstance = IsInInstance
local CreateFrame = CreateFrame
local pairs = pairs
local ipairs = ipairs
local GetCoinTextureString = GetCoinTextureString
local AddTooltipPostCall = TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
local STANDARD_TEXT_FONT = STANDARD_TEXT_FONT
local FACTION_HORDE = FACTION_HORDE
local FACTION_ALLIANCE = FACTION_ALLIANCE
local _G = _G
local TooltipDataType = Enum.TooltipDataType

-- Small fix for ToolTipMoney frame errors
-- Credit to MoneyFrameFix by FootTapper for this snippet
function SetTooltipMoney(frame, money, type, prefixText, suffixText)
    frame:AddLine((prefixText or "") .. "  " .. GetCoinTextureString(money) .. " " .. (suffixText or ""), 0, 1, 1)
end

-- Module State tracking
local isInitialized = false
local hookedTooltips = {}
local tooltipBackdrops = {}
local hookedStatusBars = {}

-- List of common tooltips to skin
local TOOLTIPS_TO_SKIN = {
    "GameTooltip",
    "ItemRefTooltip",
    "ItemRefShoppingTooltip1",
    "ItemRefShoppingTooltip2",
    "ShoppingTooltip1",
    "ShoppingTooltip2",
    "EmbeddedItemTooltip",
    "FriendsTooltip",
    "GameSmallHeaderTooltip",
    "QuickKeybindTooltip",
    "ReputationParagonTooltip",
    "WarCampaignTooltip",
    "LibDBIconTooltip",
    "SettingsTooltip",
}

-- Spec icon table for spec and class matching
local SPEC_ICONS = {
    -- Death Knight
    ["Blood Death Knight"]     = 135770,
    ["Frost Death Knight"]     = 135773,
    ["Unholy Death Knight"]    = 135775,
    -- Demon Hunter
    ["Havoc Demon Hunter"]     = 1247264,
    ["Vengeance Demon Hunter"] = 1247265,
    ["Devourer Demon Hunter"]  = 7455385,
    -- Druid
    ["Balance Druid"]          = 136096,
    ["Feral Druid"]            = 132115,
    ["Guardian Druid"]         = 132276,
    ["Restoration Druid"]      = 136041,
    -- Evoker
    ["Devastation Evoker"]     = 451165,
    ["Preservation Evoker"]    = 451164,
    ["Augmentation Evoker"]    = 5198700,
    -- Hunter
    ["Beast Mastery Hunter"]   = 461112,
    ["Marksmanship Hunter"]    = 236179,
    ["Survival Hunter"]        = 461113,
    -- Mage
    ["Arcane Mage"]            = 135932,
    ["Fire Mage"]              = 135810,
    ["Frost Mage"]             = 135846,
    -- Monk
    ["Brewmaster Monk"]        = 608951,
    ["Windwalker Monk"]        = 608953,
    ["Mistweaver Monk"]        = 608952,
    -- Paladin
    ["Holy Paladin"]           = 135920,
    ["Protection Paladin"]     = 236264,
    ["Retribution Paladin"]    = 135873,
    -- Priest
    ["Discipline Priest"]      = 135940,
    ["Holy Priest"]            = 135920,
    ["Shadow Priest"]          = 136207,
    -- Rogue
    ["Assassination Rogue"]    = 236270,
    ["Outlaw Rogue"]           = 236286,
    ["Subtlety Rogue"]         = 132320,
    -- Shaman
    ["Elemental Shaman"]       = 136048,
    ["Enhancement Shaman"]     = 136051,
    ["Restoration Shaman"]     = 136052,
    -- Warlock
    ["Affliction Warlock"]     = 136145,
    ["Demonology Warlock"]     = 136172,
    ["Destruction Warlock"]    = 136186,
    -- Warrior
    ["Arms Warrior"]           = 132355,
    ["Fury Warrior"]           = 132347,
    ["Protection Warrior"]     = 132341,
}

-- Update db, used for profile changes
function SK:UpdateDB()
    self.db = KE.db.profile.Skinning.Tooltips
end

-- Module init
function SK:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

-- Get or create custom backdrop for a tooltip
function SK:GetOrCreateBackdrop(tooltip)
    if tooltipBackdrops[tooltip] then
        return tooltipBackdrops[tooltip]
    end
    local backdrop = CreateFrame("Frame", nil, tooltip, "BackdropTemplate")
    local level = tooltip:GetFrameLevel()
    backdrop:SetFrameLevel(level > 0 and level - 1 or 0)
    backdrop:SetAllPoints(tooltip)
    tooltipBackdrops[tooltip] = backdrop
    return backdrop
end

-- Update backdrop settings
function SK:UpdateBackdrop(backdrop)
    if not self.db then return end

    backdrop:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = self.db.BorderSize or 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })

    local bgColor = self.db.BackgroundColor or { 0, 0, 0, 0.8 }
    local borderColor = self.db.BorderColor or { 0, 0, 0, 1 }

    backdrop:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 0.8)
    backdrop:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
end

-- Fetch color info from unit if unit is a player
function SK:FetchUnitColour(unit)
    local success, _ = pcall(UnitIsPlayer, unit)
    if not success then return end
    if not unit then return 1, 1, 1, 1 end
    if success then
        local online = UnitIsConnected(unit)
        local tapDenied = UnitIsTapDenied(unit)
        local deadOrGhost = UnitIsDeadOrGhost(unit)
        if tapDenied then return 0.5, 0.5, 0.5, 1 end
        if not online then return 0.5, 0.5, 0.5, 1 end
        if deadOrGhost then return 0.5, 0.5, 0.5, 1 end
        local _, class = UnitClass(unit)
        if class then
            local classColor = RAID_CLASS_COLORS[class]
            if classColor then
                return classColor.r, classColor.g, classColor.b, 1
            end
        end
    end
    return 1, 1, 1, 1
end

-- Fetch guild info from unit if unit is a player
function SK:FetchUnitGuild(unit)
    local success, _ = pcall(UnitIsPlayer, unit)
    if not success then return end
    if not unit then return end
    if success then
        local guildName, guildRank = GetGuildInfo(unit)
        local playerGuildName = GetGuildInfo("player")
        if not guildName then return end
        if guildName == playerGuildName then
            guildName = "|cffe51039" .. guildName .. "|r"
            guildRank = "|cffe51039" .. guildRank .. "|r"
        else
            guildName = "|cff41ff00" .. guildName .. "|r"
            guildRank = "|cff41ff00" .. guildRank .. "|r"
        end
        return guildName, guildRank
    end
end

-- Fetch units level and race type
function SK:FetchUnitLevelRace(unit)
    if not unit then return end
    local race = UnitRace(unit)
    local level = UnitLevel(unit)
    if race then
        race = "|cffFFFFFF" .. race .. "|r"
    end
    local levelOut
    if level then
        levelOut = "|cffffad00" .. level .. "|r"
    end
    return race, levelOut
end

-- Fetch units classname only if its from a player
function SK:FetchUnitClassInfo(unit)
    if not unit then return end
    local unitIsPlayer = UnitIsPlayer(unit)
    if unitIsPlayer then
        local className = UnitClass(unit)
        if not className then return end
        return className
    end
end

-- Check Class and Spec string, match it to correct icon, return it
function SK:FetchUnitSpecInfo(text)
    if not text then return text, nil end
    local matchedSpec
    local matchedIcon

    for specName, icon in pairs(SPEC_ICONS) do
        if text:find(specName) then
            matchedSpec = specName
            matchedIcon = icon
            break
        end
    end

    return matchedSpec, matchedIcon
end

-- Hide the default Blizzard NineSlice border
function SK:HideNineSlice(tooltip)
    if tooltip.NineSlice then
        tooltip.NineSlice:SetAlpha(0)
        tooltip.NineSlice:Hide()
    end

    local elements = {
        "BottomEdge", "BottomLeftCorner", "BottomRightCorner",
        "Center", "LeftEdge", "RightEdge",
        "TopEdge", "TopLeftCorner", "TopRightCorner",
    }

    for _, element in ipairs(elements) do
        if tooltip[element] then
            if tooltip[element].SetAlpha then
                tooltip[element]:SetAlpha(0)
            end
            if tooltip[element].Hide then
                tooltip[element]:Hide()
            end
        end
    end

    if tooltip.SetBackdrop then
        tooltip:SetBackdrop(nil)
    end
    if tooltip.SetBackdropColor then
        tooltip:SetBackdropColor(0, 0, 0, 0)
    end
    if tooltip.SetBackdropBorderColor then
        tooltip:SetBackdropBorderColor(0, 0, 0, 0)
    end
end

-- Permanently hide a status bar by hooking its Show method
function SK:PermanentlyHideStatusBar(statusBar)
    if not statusBar then return end
    if hookedStatusBars[statusBar] then return end
    statusBar:Hide()
    statusBar:SetAlpha(0)
    hooksecurefunc(statusBar, "Show", function(self)
        self:Hide()
    end)
    hookedStatusBars[statusBar] = true
end

-- Perma hide health bars for a tooltip
function SK:HideHealthBars(tooltip)
    if not self.db.HideHealthBar then return end

    if tooltip.StatusBar then
        SK:PermanentlyHideStatusBar(tooltip.StatusBar)
    end

    local statusBarName = tooltip:GetName() and (tooltip:GetName() .. "StatusBar")
    if statusBarName and _G[statusBarName] then
        SK:PermanentlyHideStatusBar(_G[statusBarName])
    end
end

-- Helper function to apply coloring
function SK:ColorText(text, r, g, b)
    return string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, text)
end

-- Tooltip Styling
function SK:StyleTooltip(tooltip, unit)
    if not self.db.Enabled then return end
    if not tooltip then return end

    SK:HideNineSlice(tooltip)

    -- Secret-value safety check
    local safeToStyle = true
    if issecretvalue then
        if issecretvalue(tooltip:GetWidth()) then
            safeToStyle = false
        end
    end
    if safeToStyle then
        local backdrop = SK:GetOrCreateBackdrop(tooltip)
        SK:UpdateBackdrop(backdrop)
        if unit then
            local r, g, b, a = SK:FetchUnitColour(unit)
            local nameLine = _G["GameTooltipTextLeft1"]
            if nameLine then
                nameLine:SetTextColor(r, g, b, a)
            end
        else
            local nameLine = _G["GameTooltipTextLeft1"]
            if nameLine then
                nameLine:SetTextColor(1, 1, 1, 1)
            end
        end
        backdrop:Show()
    end
    SK:HideHealthBars(tooltip)
end

-- Add tooltip processor for unit tooltips
local tooltipProcessorRegistered = false
function SK:InitializeTooltipProcessor()
    if tooltipProcessorRegistered then return end
    tooltipProcessorRegistered = true
    AddTooltipPostCall(TooltipDataType.Unit, function(tooltip)
        local db = SK.db
        if not db or not db.Enabled then return end
        local NameFontSize = db.NameFontSize
        local GuildFontSize = db.GuildFontSize
        local RaceLevelFontSize = db.RaceLevelFontSize
        local SpecFontSize = db.SpecFontSize
        local FactionFontSize = db.FactionFontSize
        local fontPath = KE:GetFontPath(db.FontFace)
        if not fontPath or fontPath == "" then
            fontPath = STANDARD_TEXT_FONT
        end
        local outline = KE:GetFontOutline(db.FontOutline)
        local _, unit = tooltip:GetUnit()
        local success, _ = pcall(UnitIsPlayer, unit)
        local inInstance, instanceType = IsInInstance()

        local secretEnv = success and unit ~= "mouseover" and inInstance == true and instanceType ~= "none" and
            instanceType ~= "nil"
        local nonSecretEnv = success and inInstance ~= true

        if (secretEnv and not nonSecretEnv) or (not secretEnv and nonSecretEnv) then
            local r, g, b, a = SK:FetchUnitColour(unit)

            -- Name skin
            local className = SK:FetchUnitClassInfo(unit)
            if className then
                local nameLine = _G["GameTooltipTextLeft1"]
                if nameLine then
                    nameLine:SetFont(fontPath, NameFontSize, outline)
                    nameLine:SetTextColor(r, g, b, a)
                    nameLine:SetShadowColor(0, 0, 0, 0)
                end
            end

            -- Guild skin
            local guildName, guildRank = SK:FetchUnitGuild(unit)
            local guildLine = _G["GameTooltipTextLeft2"]
            if guildLine then
                if guildName then
                    guildLine:SetFont(fontPath, GuildFontSize, outline)
                    guildLine:SetText("<" .. guildName .. "|r" .. ">" .. " " .. "[" .. guildRank .. "]")
                    guildLine:SetShadowColor(0, 0, 0, 0)
                end
            end

            -- Race and Level skin
            local lineOffset = guildName and 0 or -1
            local race, level = SK:FetchUnitLevelRace(unit)
            local raceLevelLine = _G["GameTooltipTextLeft" .. (3 + lineOffset)]
            if raceLevelLine then
                raceLevelLine:SetFont(fontPath, RaceLevelFontSize, outline)
                raceLevelLine:SetShadowColor(0, 0, 0, 0)
                if race and not level then
                    raceLevelLine:SetText(race)
                end
                if race and level then
                    raceLevelLine:SetText(level .. " " .. race)
                end
                if level and not race then
                    raceLevelLine:SetText(level)
                end
                if not level and not race then return end
            end

            -- Spec and Class skin
            if className then
                local classLine = _G["GameTooltipTextLeft" .. (4 + lineOffset)]
                if classLine then
                    local specText = classLine:GetText()
                    local spec, iconID = SK:FetchUnitSpecInfo(specText)
                    classLine:SetFont(fontPath, SpecFontSize, outline)
                    classLine:SetShadowColor(0, 0, 0, 0)
                    local text = ""
                    if iconID then
                        local iconExport = "|T" .. iconID .. ":16:16:0:0:64:64:5:59:7:57|t"
                        text = text .. iconExport .. " "
                    end
                    if spec then
                        local specHex = SK:ColorText(spec, r, g, b)
                        text = text .. specHex .. " "
                    end
                    classLine:SetText(text)
                end
            end

            -- Faction Skin
            for i = 2, tooltip:NumLines() do
                local line = _G["GameTooltipTextLeft" .. i]
                if line then
                    local text = line:GetText()
                    if text == FACTION_HORDE then
                        line:SetTextColor(1, 0, 0)
                        line:SetFont(fontPath, FactionFontSize, outline)
                        line:SetShadowColor(0, 0, 0, 0)
                    elseif text == FACTION_ALLIANCE then
                        line:SetTextColor(0, 0.5, 1)
                        line:SetFont(fontPath, FactionFontSize, outline)
                        line:SetShadowColor(0, 0, 0, 0)
                    end
                end
            end
        end
    end)
end

-- Hook a tooltip to apply styling
function SK:HookTooltip(tooltip)
    if not tooltip then return end
    if hookedTooltips[tooltip] then return end
    if not self.db.Enabled then return end
    tooltip:HookScript("OnShow", function(self)
        SK:HideNineSlice(self)
        SK:HideHealthBars(self)
        local backdrop = SK:GetOrCreateBackdrop(self)
        SK:UpdateBackdrop(backdrop)
        backdrop:Show()
    end)

    tooltip:HookScript("OnHide", function(self)
        local backdrop = tooltipBackdrops[self]
        if backdrop then
            backdrop:Hide()
        end
    end)
    hookedTooltips[tooltip] = true
end

-- Refresh styling on all hooked tooltips
function SK:Refresh()
    SK:InitializeTooltipProcessor()

    for _, tooltipName in ipairs(TOOLTIPS_TO_SKIN) do
        local tooltip = _G[tooltipName]
        if tooltip then
            SK:HookTooltip(tooltip)
        end
    end

    for tooltip in pairs(hookedTooltips) do
        if tooltip:IsShown() then
            SK:StyleTooltip(tooltip)
        end
        local backdrop = tooltipBackdrops[tooltip]
        if backdrop then
            SK:UpdateBackdrop(backdrop)
        end
    end
end

-- ApplySettings
function SK:ApplySettings()
    if KE:ShouldNotLoadModule() then return end
    self:Refresh()
end

-- Create our own anchor frame that we later use to anchor tooltip to
function SK:CreateTooltipAnchorFrame()
    local TTAnchor = CreateFrame("Frame", "KE_ToolTipAnchorFrame", UIParent)
    TTAnchor:SetSize(170, 60)
    TTAnchor:ClearAllPoints()
    TTAnchor:SetPoint(self.db.Position.AnchorFrom, UIParent, self.db.Position.AnchorTo, self.db.Position.XOffset,
        self.db.Position.YOffset)
    TTAnchor:SetClampedToScreen(true)

    self.TTAnchor = TTAnchor
    return TTAnchor
end

-- Remove tooltip anchoring Edit Mode UI since we do position changes in our custom Edit mode
local function DisableTooltipEditMode()
    if GameTooltipDefaultContainer then
        GameTooltipDefaultContainer.SetIsInEditMode = nop
        GameTooltipDefaultContainer.OnEditModeEnter = nop
        GameTooltipDefaultContainer.OnEditModeExit = nop
        GameTooltipDefaultContainer.HasActiveChanges = nop
        GameTooltipDefaultContainer.HighlightSystem = nop
        GameTooltipDefaultContainer.SelectSystem = nop
        GameTooltipDefaultContainer.system = nil
    end
end

function SK:AnchorTooltip(tooltip)
    if not tooltip or tooltip:IsForbidden() then return end
    tooltip:ClearAllPoints()
    tooltip:SetOwner(UIParent, "ANCHOR_NONE")
    tooltip:SetPoint("BOTTOMRIGHT", self.TTAnchor, "BOTTOMRIGHT", 0, 0)
end

local function tooltipAnchorReg()
    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(self)
        SK:AnchorTooltip(self)
    end)
end

-- Skin QueueStatusFrame
local function SkinQueueStatus()
    local frame = QueueStatusFrame
    if not frame then return end

    local children = { frame:GetChildren() }
    local borderFrame = children[1]

    if borderFrame then
        for _, region in ipairs({ borderFrame:GetRegions() }) do
            region:SetAlpha(0)
            region:Hide()
        end
        hooksecurefunc(borderFrame, "Show", function(self)
            for _, region in ipairs({ self:GetRegions() }) do
                region:SetAlpha(0)
                region:Hide()
            end
        end)
    end

    local backdrop = SK:GetOrCreateBackdrop(frame)
    SK:UpdateBackdrop(backdrop)

    frame:HookScript("OnShow", function(self)
        if borderFrame then
            for _, region in ipairs({ borderFrame:GetRegions() }) do
                region:SetAlpha(0)
                region:Hide()
            end
        end
        local bd = SK:GetOrCreateBackdrop(self)
        SK:UpdateBackdrop(bd)
        bd:Show()
    end)

    frame:HookScript("OnHide", function(self)
        local bd = tooltipBackdrops[self]
        if bd then bd:Hide() end
    end)
end

-- Initialize tooltip skinning
function SK:OnEnable()
    if KE:ShouldNotLoadModule() then return end
    if not self.db.Enabled then return end
    if isInitialized then return end
    SK:CreateTooltipAnchorFrame()
    SK:Refresh()
    SkinQueueStatus()

    isInitialized = true
    tooltipAnchorReg()

    C_Timer.After(0.5, function()
        DisableTooltipEditMode()
    end)

    -- Register with custom edit mode
    local config = {
        key = "TooltipModule",
        displayName = "Tooltip Anchor",
        frame = self.TTAnchor,
        getPosition = function()
            return self.db.Position
        end,
        setPosition = function(pos)
            self.db.Position.AnchorFrom = pos.AnchorFrom
            self.db.Position.AnchorTo = pos.AnchorTo
            self.db.Position.XOffset = pos.XOffset
            self.db.Position.YOffset = pos.YOffset

            self.TTAnchor:ClearAllPoints()
            self.TTAnchor:SetPoint(pos.AnchorFrom, UIParent, pos.AnchorTo, pos.XOffset, pos.YOffset)
        end,
        getParentFrame = function()
            return UIParent
        end,
        guiPath = "SkinTooltips",
    }
    KE.EditMode:RegisterElement(config)
end

function SK:OnDisable()
    self:UnregisterAllEvents()
    self:UnhookAll()
end

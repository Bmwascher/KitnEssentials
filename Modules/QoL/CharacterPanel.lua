-- ╔══════════════════════════════════════════════════════════╗
-- ║  CharacterPanel.lua                                      ║
-- ║  Module: Character Panel                                 ║
-- ║  Purpose: Missing enchant/gem warnings, decimal ilvl,    ║
-- ║           character text styling, race text, item track  ║
-- ║           indicators, gem socket helper.                 ║
-- ║  Credit: Warnings based on BetterCharacterPanel by       ║
-- ║          Grimonja. Feature set ported from NUI v3.13     ║
-- ║          CharacterPanel.                                  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class CharacterPanel: AceModule, AceEvent-3.0, AceHook-3.0
local CP = KitnEssentials:NewModule("CharacterPanel", "AceEvent-3.0", "AceHook-3.0")

local _G = _G
local CreateFrame = CreateFrame
local GetInventoryItemLink = GetInventoryItemLink
local GetExpansionForLevel = GetExpansionForLevel
local GetItemInfoInstant = C_Item.GetItemInfoInstant
local UnitLevel = UnitLevel
local IsLevelAtEffectiveMaxLevel = IsLevelAtEffectiveMaxLevel
local C_TooltipInfo = C_TooltipInfo
local strsplit = strsplit
local pairs, ipairs = pairs, ipairs
local table_concat = table.concat
local C_Timer = C_Timer

local INVSLOT_HEAD      = INVSLOT_HEAD
local INVSLOT_NECK      = INVSLOT_NECK
local INVSLOT_SHOULDER  = INVSLOT_SHOULDER
local INVSLOT_BACK      = INVSLOT_BACK
local INVSLOT_CHEST     = INVSLOT_CHEST
local INVSLOT_WRIST     = INVSLOT_WRIST
local INVSLOT_WAIST     = INVSLOT_WAIST
local INVSLOT_LEGS      = INVSLOT_LEGS
local INVSLOT_FEET      = INVSLOT_FEET
local INVSLOT_FINGER1   = INVSLOT_FINGER1
local INVSLOT_FINGER2   = INVSLOT_FINGER2
local INVSLOT_MAINHAND  = INVSLOT_MAINHAND
local INVSLOT_OFFHAND   = INVSLOT_OFFHAND

local function ElvUILoaded()
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("ElvUI")
end

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------

-- Enchantable slots per expansion (keyed by GetExpansionForLevel() return value)
local expansionEnchantableSlots = {
    [11] = {
        [INVSLOT_MAINHAND] = true, [INVSLOT_HEAD] = true, [INVSLOT_SHOULDER] = true,
        [INVSLOT_CHEST] = true, [INVSLOT_LEGS] = true, [INVSLOT_FEET] = true,
        [INVSLOT_FINGER1] = true, [INVSLOT_FINGER2] = true,
    },
    [10] = {
        [INVSLOT_BACK] = true, [INVSLOT_CHEST] = true, [INVSLOT_WRIST] = true,
        [INVSLOT_LEGS] = true, [INVSLOT_FEET] = true, [INVSLOT_MAINHAND] = true,
        [INVSLOT_FINGER1] = true, [INVSLOT_FINGER2] = true,
    },
}

-- Which side of the character panel each slot sits on
local slotLayout = {
    [INVSLOT_HEAD] = "left",      [INVSLOT_NECK] = "left",
    [INVSLOT_SHOULDER] = "left",  [INVSLOT_BACK] = "left",
    [INVSLOT_CHEST] = "left",     [INVSLOT_WRIST] = "left",
    [INVSLOT_WAIST] = "right",
    [INVSLOT_LEGS] = "right",     [INVSLOT_FEET] = "right",
    [INVSLOT_FINGER1] = "right",  [INVSLOT_FINGER2] = "right",
    [INVSLOT_MAINHAND] = "center", [INVSLOT_OFFHAND] = "center",
}

-- Enchantable slot buttons
local enchantSlotButtons = {
    [INVSLOT_HEAD]      = "CharacterHeadSlot",
    [INVSLOT_SHOULDER]  = "CharacterShoulderSlot",
    [INVSLOT_BACK]      = "CharacterBackSlot",
    [INVSLOT_CHEST]     = "CharacterChestSlot",
    [INVSLOT_WRIST]     = "CharacterWristSlot",
    [INVSLOT_LEGS]      = "CharacterLegsSlot",
    [INVSLOT_FEET]      = "CharacterFeetSlot",
    [INVSLOT_FINGER1]   = "CharacterFinger0Slot",
    [INVSLOT_FINGER2]   = "CharacterFinger1Slot",
    [INVSLOT_MAINHAND]  = "CharacterMainHandSlot",
    [INVSLOT_OFFHAND]   = "CharacterSecondaryHandSlot",
}

-- Slots that can have gem sockets this expansion
local gemSlotButtons = {
    [INVSLOT_HEAD]    = "CharacterHeadSlot",
    [INVSLOT_NECK]    = "CharacterNeckSlot",
    [INVSLOT_WRIST]   = "CharacterWristSlot",
    [INVSLOT_WAIST]   = "CharacterWaistSlot",
    [INVSLOT_FINGER1] = "CharacterFinger0Slot",
    [INVSLOT_FINGER2] = "CharacterFinger1Slot",
}

-- Gem socket types for socket helper scanning.
local GEM_SOCKET_TYPES = {
    { name = "Prismatic",  locale = "EMPTY_SOCKET_PRISMATIC",  icon = 458977 },
    { name = "Meta",       locale = "EMPTY_SOCKET_META",       icon = 136257 },
    { name = "Tinker",     locale = "EMPTY_SOCKET_TINKER",     icon = 2958630 },
    { name = "Cogwheel",   locale = "EMPTY_SOCKET_COGWHEEL",   icon = 407324 },
    { name = "Primordial", locale = "EMPTY_SOCKET_PRIMORDIAL", icon = 4095404 },
    { name = "Fiber",      locale = "EMPTY_SOCKET_FIBER",      icon = 136260 },
}

-- Slot IDs the gem socket helper scans.
local socketableSlots = { 1, 2, 5, 6, 9, 10, 11, 12, 13, 14, 15 }

-- Item track tier metadata. Letter shown on slot, color RGB.
local ITEM_TRACKS = {
    { keyword = "Myth",       letter = "M", color = { 1.00, 0.50, 0.00 } },
    { keyword = "Hero",       letter = "H", color = { 0.78, 0.30, 0.78 } },
    { keyword = "Champion",   letter = "C", color = { 0.00, 0.70, 1.00 } },
    { keyword = "Veteran",    letter = "V", color = { 0.00, 0.80, 0.00 } },
    { keyword = "Adventurer", letter = "A", color = { 0.70, 0.70, 0.70 } },
}

-- Crafted gear track auto-detection from item level.
local CRAFTED_TRACKS = {
    { minIlvl = 295, letter = "C", color = { 1.00, 0.50, 0.00 }, weaponOnly = true },
    { minIlvl = 285, letter = "C", color = { 1.00, 0.50, 0.00 } },
    { minIlvl = 282, letter = "C", color = { 0.78, 0.30, 0.78 } },
    { minIlvl = 269, letter = "C", color = { 0.00, 0.70, 1.00 } },
}

-- All equipped slots — for track indicators and gem helper anchor frames.
local SLOT_FRAMES = {
    [1]  = "CharacterHeadSlot",      [2]  = "CharacterNeckSlot",
    [3]  = "CharacterShoulderSlot",
    [5]  = "CharacterChestSlot",     [6]  = "CharacterWaistSlot",
    [7]  = "CharacterLegsSlot",      [8]  = "CharacterFeetSlot",
    [9]  = "CharacterWristSlot",     [10] = "CharacterHandsSlot",
    [11] = "CharacterFinger0Slot",   [12] = "CharacterFinger1Slot",
    [13] = "CharacterTrinket0Slot",  [14] = "CharacterTrinket1Slot",
    [15] = "CharacterBackSlot",
    [16] = "CharacterMainHandSlot",  [17] = "CharacterSecondaryHandSlot",
}

-- Slot IDs anchored on the right side of CharacterFrame.
local RIGHT_SLOTS = {
    [6] = true, [7] = true, [8] = true, [10] = true,
    [11] = true, [12] = true, [13] = true, [14] = true, [17] = true,
}

-- Track indicator quality atlas regex (extracted from item link).
local qualityAtlasPattern = "|A:(Professions%-ChatIcon%-Quality%-[^:]+):%d+:%d+"

-- Combined set of all slots that need checking
local allCheckSlots = {}
for slot, btn in pairs(enchantSlotButtons) do allCheckSlots[slot] = btn end
for slot, btn in pairs(gemSlotButtons) do allCheckSlots[slot] = btn end

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------
local slotTexts = {}
local hooked = false
local updatePending = false
local backgroundsHidden = false
local backgroundOriginalState = {}

local UPDATE_DEBOUNCE = 0.1
local CHARACTER_BACKGROUND_TEXTURES = {
    "BackgroundTopLeft", "BackgroundTopRight",
    "BackgroundBotLeft", "BackgroundBotRight",
    "BackgroundOverlay",
}

---------------------------------------------------------------------------------
-- Core Logic
---------------------------------------------------------------------------------
local function HasEnchant(itemLink)
    if not itemLink then return false end
    local itemString = itemLink:match("item[%-?%d:]+")
    if not itemString then return false end
    local _, _, enchantId = strsplit(":", itemString)
    return enchantId and enchantId ~= "" and enchantId ~= "0"
end

local function CanEnchantSlot(slot)
    local expansion = GetExpansionForLevel(UnitLevel("player"))
    local slots = expansion and expansionEnchantableSlots[expansion]
    if not slots then return false end
    if slots[slot] then return true end

    if slot == INVSLOT_OFFHAND then
        local itemLink = GetInventoryItemLink("player", slot)
        if itemLink then
            local itemEquipLoc = select(4, GetItemInfoInstant(itemLink))
            return itemEquipLoc ~= "INVTYPE_HOLDABLE" and itemEquipLoc ~= "INVTYPE_SHIELD"
        end
        return false
    end
    return false
end

local function HasEmptySocket(slot)
    if not gemSlotButtons[slot] then return false end
    local tooltipData = C_TooltipInfo.GetInventoryItem("player", slot)
    if not tooltipData or not tooltipData.lines then return false end

    for _, line in ipairs(tooltipData.lines) do
        if line.leftText and line.leftText:find("Prismatic Socket") then
            return true
        end
    end
    return false
end

---------------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------------
local function CreateSlotText(button, slot)
    local db = CP.db
    local fontFace    = (db and db.FontFace)    or "Expressway"
    local fontSize    = (db and db.FontSize)    or 13
    local fontOutline = (db and db.FontOutline) or "OUTLINE"
    local text = button:CreateFontString(nil, "OVERLAY")
    KE:ApplyFontToText(text, fontFace, fontSize, fontOutline)
    text:SetTextColor(1, 0, 0, 1)

    local side = slotLayout[slot]
    if side == "left" then
        text:SetPoint("TOPLEFT", button, "TOPRIGHT", 4, -5)
    elseif side == "right" then
        text:SetPoint("TOPRIGHT", button, "TOPLEFT", -4, -5)
    elseif side == "center" then
        if slot == INVSLOT_MAINHAND then
            text:SetPoint("TOPRIGHT", button, "TOPLEFT", -4, -2)
        else
            text:SetPoint("TOPLEFT", button, "TOPRIGHT", 4, -2)
        end
    end
    return text
end

local function ApplyFontToAll()
    local db = CP.db
    local fontFace    = (db and db.FontFace)    or "Expressway"
    local fontSize    = (db and db.FontSize)    or 13
    local fontOutline = (db and db.FontOutline) or "OUTLINE"
    for _, text in pairs(slotTexts) do
        KE:ApplyFontToText(text, fontFace, fontSize, fontOutline)
    end
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
local function UpdateDisplay()
    local db = CP.db
    local enchantEnabled = db and db.ShowEnchants ~= false
    local gemEnabled = db and db.ShowMissingGems ~= false
    local isMaxLevel = IsLevelAtEffectiveMaxLevel(UnitLevel("player"))

    for slot, buttonName in pairs(allCheckSlots) do
        local button = _G[buttonName]
        if button then
            if not slotTexts[slot] then
                slotTexts[slot] = CreateSlotText(button, slot)
            end

            local parts = {}
            if isMaxLevel then
                local itemLink = GetInventoryItemLink("player", slot)
                if itemLink then
                    if enchantEnabled and CanEnchantSlot(slot) and not HasEnchant(itemLink) then
                        parts[#parts + 1] = "No Enchant"
                    end
                    if gemEnabled and HasEmptySocket(slot) then
                        parts[#parts + 1] = "No Gem"
                    end
                end
            end

            if #parts > 0 then
                slotTexts[slot]:SetText("|cFFFF0000" .. table_concat(parts, " / ") .. "|r")
            else
                slotTexts[slot]:SetText("")
            end
        end
    end
end

-- Debounced update — collapses bursts of equipment events into one update
local function QueueUpdate()
    if updatePending then return end
    if not (CharacterFrame and CharacterFrame:IsShown()) then return end
    updatePending = true
    C_Timer.After(UPDATE_DEBOUNCE, function()
        updatePending = false
        if CharacterFrame and CharacterFrame:IsShown() then
            UpdateDisplay()
        end
    end)
end

local function HideCharacterBackground()
    local scene = _G.CharacterModelScene
    if not scene then return end

    if not backgroundsHidden then
        for _, texName in pairs(CHARACTER_BACKGROUND_TEXTURES) do
            local tex = scene[texName]
            if tex then
                backgroundOriginalState[texName] = tex:IsShown()
            end
        end
        if scene.backdrop then
            backgroundOriginalState.backdrop = scene.backdrop:IsShown()
        end
        if _G.CharacterModelFrameBackgroundOverlay then
            backgroundOriginalState.frameOverlay = _G.CharacterModelFrameBackgroundOverlay:IsShown()
        end
    end

    for _, texName in pairs(CHARACTER_BACKGROUND_TEXTURES) do
        local tex = scene[texName]
        if tex then tex:Hide() end
    end
    if scene.backdrop then scene.backdrop:Hide() end
    if _G.CharacterModelFrameBackgroundOverlay then
        _G.CharacterModelFrameBackgroundOverlay:Hide()
    end

    backgroundsHidden = true
end

local function RestoreCharacterBackground()
    if not backgroundsHidden then return end
    local scene = _G.CharacterModelScene
    if not scene then return end

    for _, texName in pairs(CHARACTER_BACKGROUND_TEXTURES) do
        local tex = scene[texName]
        if tex and backgroundOriginalState[texName] then
            tex:Show()
        end
    end
    if scene.backdrop and backgroundOriginalState.backdrop then
        scene.backdrop:Show()
    end
    if _G.CharacterModelFrameBackgroundOverlay and backgroundOriginalState.frameOverlay then
        _G.CharacterModelFrameBackgroundOverlay:Show()
    end

    backgroundsHidden = false
end

local function HookCharacterPanel()
    if hooked then return end

    if PaperDollFrame then
        PaperDollFrame:HookScript("OnShow", function()
            QueueUpdate()
            local db = CP.db
            if db and db.HideCharacterBackground then
                HideCharacterBackground()
            end
        end)
    end

    -- PEC alone is the direct signal; UIC was duplicative.
    CP.eventFrame = CreateFrame("Frame")
    CP.eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    CP.eventFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_EQUIPMENT_CHANGED" then
            QueueUpdate()
        end
    end)

    hooked = true
end

function CP:Refresh()
    HookCharacterPanel()
    ApplyFontToAll()
    if CharacterFrame and CharacterFrame:IsShown() then
        UpdateDisplay()
    end
end

function CP:ClearAll()
    for _, text in pairs(slotTexts) do text:SetText("") end
end

function CP:ApplyFont(fontString, size)
    local db = self.db
    local fontFace    = db.FontFace    or "Expressway"
    local fontOutline = db.FontOutline or "OUTLINE"
    KE:ApplyFontToText(fontString, fontFace, size, fontOutline)
end

function CP:UpdateItemLevelText()
    local itemLevelFrame = CharacterStatsPane and CharacterStatsPane.ItemLevelFrame
    if not itemLevelFrame or not itemLevelFrame.Value then return end

    local _, avgItemLevelEquipped = GetAverageItemLevel()
    if self.db.Enabled and self.db.DecimalItemLevel and not ElvUILoaded() then
        itemLevelFrame.Value:SetText(string.format("%.2f", avgItemLevelEquipped))
    else
        itemLevelFrame.Value:SetText(string.format("%d", math.floor(avgItemLevelEquipped)))
    end
end

function CP:SetupDecimalItemLevel()
    if ElvUILoaded() then return end
    if self._decimalIlvlHooked then return end
    self._decimalIlvlHooked = true

    self:SecureHook("PaperDollFrame_SetItemLevel", function(_, unit)
        if not self.db.DecimalItemLevel then return end
        if unit ~= "player" then return end
        self:UpdateItemLevelText()
    end)
end

function CP:StyleCharacterTexts()
    if ElvUILoaded() then return end

    local levelText = CharacterLevelText
    if levelText then
        self:ApplyFont(levelText, self.db.LevelTextSize or 12)
        levelText:SetWidth(0)
        levelText:SetWordWrap(true)
    end

    local nameText = CharacterFrameTitleText
    if nameText then
        self:ApplyFont(nameText, self.db.NameTextSize or 12)
    end

    self:StyleStatsPaneTexts()
end

function CP:StyleStatsPaneTexts()
    if ElvUILoaded() then return end

    local statsPane = CharacterStatsPane
    if not statsPane then return end

    local categorySize = self.db.CategoryFontSize or 12

    if statsPane.ItemLevelCategory and statsPane.ItemLevelCategory.Title then
        self:ApplyFont(statsPane.ItemLevelCategory.Title, categorySize)
    end

    if statsPane.ItemLevelFrame and statsPane.ItemLevelFrame.Value then
        self:ApplyFont(statsPane.ItemLevelFrame.Value, self.db.IlvlValueSize or 16)
    end

    for _, category in ipairs({ statsPane.AttributesCategory, statsPane.EnhancementsCategory }) do
        if category and category.Title then
            self:ApplyFont(category.Title, categorySize)
        end
    end
end

function CP:SetupStatTextHook()
    if ElvUILoaded() then return end
    if self._statTextHooked then return end
    self._statTextHooked = true

    hooksecurefunc("PaperDollFrame_SetLabelAndText", function(statFrame)
        if not CP.db.Enabled then return end
        if CharacterStatsPane and statFrame == CharacterStatsPane.ItemLevelFrame then return end
        local statsSize = CP.db.StatsFontSize or 12
        if statFrame.Label then CP:ApplyFont(statFrame.Label, statsSize) end
        if statFrame.Value then CP:ApplyFont(statFrame.Value, statsSize) end
    end)
end

---------------------------------------------------------------------------------
-- Level Text Faction Indicator + Race Text
---------------------------------------------------------------------------------
function CP:UpdateLevelTextWithFaction()
    if ElvUILoaded() then return end

    local levelText = CharacterLevelText
    if not levelText then return end

    local text = levelText:GetText()
    if not text then return end

    -- Strip any prior suffix we added.
    text = text:gsub(" |c%x%x%x%x%x%x%x%x%([AH]%)|r$", "")

    if self.db.ShowFactionOnLevel then
        local faction = UnitFactionGroup("player")
        if faction == "Alliance" then
            text = text .. " |cff3399ff(A)|r"
        elseif faction == "Horde" then
            text = text .. " |cffe63333(H)|r"
        end
    end

    levelText:SetText(text)
end

function CP:SetupLevelTextHook()
    if ElvUILoaded() then return end
    if self._levelTextHooked then return end
    self._levelTextHooked = true

    hooksecurefunc("PaperDollFrame_SetLevel", function()
        if not CP.db.Enabled then return end
        CP:UpdateLevelTextWithFaction()
        CP:UpdateRaceTextPosition()
    end)
end

function CP:CreateRaceText()
    if self._raceText then return self._raceText end

    local text = PaperDollFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall2")
    text:SetPoint("TOP", CharacterLevelText, "BOTTOM", 0, 5)
    text:SetText(UnitRace("player"))
    text:Hide()

    self._raceText = text
    return text
end

function CP:UpdateRaceTextPosition()
    if not self._raceText then return end
    if not self.db.ShowRaceText then return end
    if not CharacterLevelText then return end
    CharacterLevelText:SetPointsOffset(0, -37)
end

function CP:ShowRaceText()
    if ElvUILoaded() then return end
    if not self.db.ShowRaceText then return end

    local text = self:CreateRaceText()
    self:ApplyFont(text, self.db.LevelTextSize or 12)
    text:SetText(UnitRace("player"))
    text:Show()
    self:UpdateRaceTextPosition()
end

function CP:HideRaceText()
    if self._raceText then self._raceText:Hide() end
    if CharacterLevelText then
        CharacterLevelText:SetPointsOffset(0, 0)
    end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function CP:OnInitialize()
    self.db = KE.db.profile.CharacterPanel
    self:SetEnabledState(false)
end

function CP:OnEnable()
    if not self.db.Enabled then return end
    HookCharacterPanel()

    -- HookCharacterPanel short-circuits via the file-local `hooked` flag, so
    -- the eventFrame is created exactly once. After a disable cycle,
    -- OnDisable's UnregisterAllEvents stripped PLAYER_EQUIPMENT_CHANGED but
    -- HookCharacterPanel won't re-register it (hooked == true). Explicitly
    -- re-register here so equipment-change updates resume on re-enable.
    if self.eventFrame then
        self.eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    end

    if CharacterFrame and CharacterFrame:IsShown() then
        UpdateDisplay()
    end
end

function CP:OnDisable()
    self:ClearAll()
    if self.eventFrame then
        self.eventFrame:UnregisterAllEvents()
    end
    RestoreCharacterBackground()
    updatePending = false
end

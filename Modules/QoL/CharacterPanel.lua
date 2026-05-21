-- ╔══════════════════════════════════════════════════════════╗
-- ║  CharacterPanel.lua                                      ║
-- ║  Module: Character Panel                                 ║
-- ║  Purpose: Missing enchant/gem warnings, decimal ilvl,    ║
-- ║           character text styling, race text, item track  ║
-- ║           indicators, gem socket helper.                 ║
-- ║  Credit: Warnings based on BetterCharacterPanel by       ║
-- ║          Grimonja. Feature set ported from NUI v3.13     ║
-- ║          CharacterPanel.                                 ║
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
            if not CP.db.Enabled then return end
            QueueUpdate()                                 -- warnings
            if CP.db.HideCharacterBackground then HideCharacterBackground() end
            if CP.db.SocketHelperEnabled then CP:RefreshSocketButtons() end
            if CP.db.TrackIndicatorsEnabled then CP:UpdateAllTrackIndicators() end
        end)
        PaperDollFrame:HookScript("OnHide", function()
            if CP.socketContainer then CP.socketContainer:Hide() end
            CP:HideGemPopup()
            CP:HideSlotHighlight()
        end)
    end

    CP.eventFrame = CreateFrame("Frame")
    CP.eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    CP.eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    CP.eventFrame:SetScript("OnEvent", function(_, event, slotID)
        if not CP.db.Enabled then return end
        if event == "PLAYER_EQUIPMENT_CHANGED" then
            QueueUpdate()                                 -- warnings
            if CP.db.SocketHelperEnabled then CP:RefreshSocketButtons() end
            if CP.db.TrackIndicatorsEnabled and slotID then
                CP:UpdateSlotTrackIndicator(slotID)
            end
        elseif event == "BAG_UPDATE_DELAYED" then
            -- Socketing a gem / applying an enchant consumes the item from bags
            -- and fires this rather than PLAYER_EQUIPMENT_CHANGED, so refresh the
            -- missing-enchant/gem warnings here too (debounced + panel-gated).
            QueueUpdate()
            if CP.socketContainer and CP.socketContainer:IsShown() then
                CP:RefreshSocketButtons()
            end
        end
    end)

    hooked = true
end

function CP:Refresh()
    self.db = KE.db.profile.CharacterPanel
    HookCharacterPanel()
    ApplyFontToAll()                                      -- warning fonts
    if self.db.Enabled then
        self:ApplySettings()
        if CharacterFrame and CharacterFrame:IsShown() then UpdateDisplay() end
    end
end

function CP:ApplySettings()
    if not self.db.Enabled then return end

    -- Live apply/restore of the character-panel background hide. Idempotent;
    -- lets the GUI toggle take effect immediately instead of only on the next
    -- PaperDollFrame OnShow.
    if self.db.HideCharacterBackground then
        HideCharacterBackground()
    else
        RestoreCharacterBackground()
    end

    self:SetupDecimalItemLevel()
    self:UpdateItemLevelText()
    self:StyleCharacterTexts()
    self:SetupStatTextHook()
    self:SetupLevelTextHook()
    self:UpdateLevelTextWithFaction()
    self:SetupGemSocketHelper()
    self:SetupTrackIndicators()

    if self.db.ShowRaceText then
        self:ShowRaceText()
    else
        self:HideRaceText()
    end

    if self.db.SocketHelperEnabled and PaperDollFrame and PaperDollFrame:IsShown() then
        self:RefreshSocketButtons()
    end
    if self.db.TrackIndicatorsEnabled and PaperDollFrame and PaperDollFrame:IsShown() then
        self:UpdateAllTrackIndicators()
    end
end

function CP:ClearAll()
    for _, text in pairs(slotTexts) do text:SetText("") end
end

function CP:ApplyFont(fontString, size)
    local db = self.db
    local fontFace    = db.FontFace    or "Expressway"
    local fontOutline = db.FontOutline or "OUTLINE"
    -- These style Blizzard's own FontStrings (level/name/stat/category texts).
    -- SOFTOUTLINE is KE's custom 8-shadow system; on Blizzard's recycled
    -- FontStrings it renders as solid black, so use the low-level ApplyFont
    -- (no shadow objects) and never pass SOFTOUTLINE through here.
    if fontOutline == "SOFTOUTLINE" then fontOutline = "OUTLINE" end
    KE:ApplyFont(fontString, fontFace, size, fontOutline)
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

    -- Per-stat rows (Label/Value) are restyled by our PaperDollFrame_SetLabelAndText
    -- hook, which only fires when Blizzard re-renders the stats pane. Force a
    -- re-render so a StatsFontSize change applies live instead of on next reopen.
    if PaperDollFrame and PaperDollFrame:IsShown() and PaperDollFrame_UpdateStats then
        PaperDollFrame_UpdateStats()
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
    -- SetPointsOffset(0,0) is a transient offset and doesn't always snap the
    -- level text back to Blizzard's baseline on its own (it stays displaced
    -- until the panel is reopened). Re-running Blizzard's level layout — what a
    -- reopen does — restores it immediately. Our PaperDollFrame_SetLevel hook is
    -- safe here: UpdateRaceTextPosition early-returns now that ShowRaceText is
    -- off, it only re-applies the faction suffix.
    if PaperDollFrame and PaperDollFrame:IsShown() and PaperDollFrame_SetLevel then
        PaperDollFrame_SetLevel()
    end
end

---------------------------------------------------------------------------------
-- Item Track Indicators
---------------------------------------------------------------------------------
function CP:GetItemTrack(slotID)
    local data = C_TooltipInfo.GetInventoryItem("player", slotID)
    if not data or not data.lines then return nil end

    local isCrafted = false
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if text then
            if text:find("Upgrade Level:") or text:find("Ascendant Voidforged:") then
                for _, track in ipairs(ITEM_TRACKS) do
                    if text:find(track.keyword) then return track end
                end
            end
            if text:find("Crafted") then isCrafted = true end
        end
    end

    if isCrafted then
        local itemLink = GetInventoryItemLink("player", slotID)
        if itemLink then
            local ilvl = GetDetailedItemLevelInfo(itemLink)
            if ilvl then
                local isWeapon = slotID == 16 or slotID == 17
                for _, track in ipairs(CRAFTED_TRACKS) do
                    if ilvl >= track.minIlvl and (not track.weaponOnly or isWeapon) then
                        return track
                    end
                end
            end
        end
    end

    return nil
end

function CP:CreateTrackOverlay(slotFrame, slotID)
    if slotFrame._trackOverlay then return slotFrame._trackOverlay end

    local isRight = RIGHT_SLOTS[slotID]
    local overlay = CreateFrame("Frame", nil, slotFrame)
    overlay:SetSize(14, 14)
    overlay:SetFrameLevel(slotFrame:GetFrameLevel() + 10)

    if isRight then
        overlay:SetPoint("BOTTOMRIGHT", slotFrame, "BOTTOMRIGHT", 0, 1)
    else
        overlay:SetPoint("BOTTOMLEFT", slotFrame, "BOTTOMLEFT", 1, 1)
    end

    overlay.text = overlay:CreateFontString(nil, "OVERLAY")
    KE:ApplyFontToText(overlay.text, self.db.FontFace or "Expressway", self.db.TrackLetterSize or 12, "OUTLINE")
    overlay.text:SetShadowColor(0, 0, 0, 0)

    if isRight then
        overlay.text:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", 0, 0)
        overlay.text:SetJustifyH("RIGHT")
    else
        overlay.text:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", 0, 0)
        overlay.text:SetJustifyH("LEFT")
    end

    overlay:Hide()
    slotFrame._trackOverlay = overlay
    return overlay
end

function CP:UpdateSlotTrackIndicator(slotID)
    local frameName = SLOT_FRAMES[slotID]
    if not frameName then return end

    local slotFrame = _G[frameName]
    if not slotFrame then return end

    local overlay = self:CreateTrackOverlay(slotFrame, slotID)
    local track = self:GetItemTrack(slotID)

    if track then
        -- Re-apply font each update so a TrackLetterSize change is live.
        KE:ApplyFontToText(overlay.text, self.db.FontFace or "Expressway", self.db.TrackLetterSize or 12, "OUTLINE")
        overlay.text:SetText(track.letter)
        overlay.text:SetTextColor(track.color[1], track.color[2], track.color[3])
        overlay:Show()
    else
        overlay:Hide()
    end
end

function CP:UpdateAllTrackIndicators()
    if not self.db.TrackIndicatorsEnabled then return end
    for slotID in pairs(SLOT_FRAMES) do
        self:UpdateSlotTrackIndicator(slotID)
    end
end

function CP:HideAllTrackIndicators()
    for _, frameName in pairs(SLOT_FRAMES) do
        local slotFrame = _G[frameName]
        if slotFrame and slotFrame._trackOverlay then
            slotFrame._trackOverlay:Hide()
        end
    end
end

function CP:SetupTrackIndicators()
    if not self.db.TrackIndicatorsEnabled then return end
    if self._trackIndicatorsHooked then return end
    self._trackIndicatorsHooked = true
    -- Track indicators register on PaperDollFrame OnShow via the combined
    -- HookCharacterPanel handler (added in Task 12). No separate hook here.
end

---------------------------------------------------------------------------------
-- Gem Socket Helper
---------------------------------------------------------------------------------

-- File-locals: scan tooltip + caches
local scanTooltip
local gemCache = {}
local socketCache = {}

-- Helper constants
local TITLE_HEIGHT      = 24
local HOVER_DURATION    = 0.12
local ITEM_ROW_PADDING  = 4
local POPUP_PADDING     = 2
local POPUP_ICON_SIZE   = 24
local STANDARD_BACKDROP = { bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 }

local function GetScanTooltip()
    if not scanTooltip then
        scanTooltip = CreateFrame("GameTooltip", "KE_CharacterPanelScanTooltip", nil, "GameTooltipTemplate")
        scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    end
    return scanTooltip
end

local function GetQualityAtlasFromLink(link)
    if not link then return nil end
    return link:match(qualityAtlasPattern)
end

local function SetQualityAtlas(texture, atlas)
    if not atlas then texture:Hide(); return end
    texture:SetAtlas(atlas, false)
    texture:Show()
end

local function GetGemStatsFromLink(link)
    if not link then return nil end
    local data = C_TooltipInfo.GetHyperlink(link)
    if not data or not data.lines then return nil end
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if text and text:match("^%+%d+") then
            return text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        end
    end
    return nil
end

local function IsMouseOverGemUI()
    if CP.gemPopup and CP.gemPopup:IsMouseOver() then return true end
    if CP.gemPopup then
        for _, btn in pairs(CP.gemPopup.buttons) do
            if btn:IsShown() and btn:IsMouseOver() then return true end
        end
    end
    if CP.currentSocketBtn and CP.currentSocketBtn:IsMouseOver() then return true end
    if CP.socketContainer then
        for _, socketBtn in pairs(CP.socketContainer.buttons) do
            if socketBtn:IsShown() and socketBtn:IsMouseOver() then return true end
        end
    end
    return false
end

local function CreateQualityOverlay(parent, anchor)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetFrameLevel(parent:GetFrameLevel() + 10)
    frame:SetSize(16, 16)
    frame:SetPoint("TOPLEFT", anchor or parent, "TOPLEFT", -5, 5)
    local texture = frame:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints()
    texture:Hide()
    return frame, texture
end

function CP:ScanItemSockets(slotID)
    local itemLink = GetInventoryItemLink("player", slotID)
    if not itemLink then return nil end

    local result = {
        slotID = slotID,
        itemLink = itemLink,
        sockets = {},
        totalCount = 0, filledCount = 0, emptyCount = 0,
    }

    for socketIndex = 1, 3 do
        local gemName, gemLink = C_Item.GetItemGem(itemLink, socketIndex)
        if gemLink then
            result.filledCount = result.filledCount + 1
            result.totalCount  = result.totalCount + 1
            local gemID = C_Item.GetItemInfoInstant(gemLink)
            local gemIcon = gemID and C_Item.GetItemIconByID(gemID)
            table.insert(result.sockets, {
                index = socketIndex, filled = true,
                gemLink = gemLink, gemName = gemName, gemID = gemID, icon = gemIcon,
            })
        end
    end

    local tt = GetScanTooltip()
    tt:ClearLines()
    tt:SetInventoryItem("player", slotID)

    for i = 1, tt:NumLines() do
        local line = _G["KE_CharacterPanelScanTooltipTextLeft" .. i]
        if line then
            local text = line:GetText()
            if text then
                for _, socketType in ipairs(GEM_SOCKET_TYPES) do
                    local localeString = _G[socketType.locale]
                    if localeString and text:find(localeString, 1, true) then
                        result.emptyCount = result.emptyCount + 1
                        result.totalCount = result.totalCount + 1
                        table.insert(result.sockets, {
                            index = result.totalCount, filled = false,
                            socketType = socketType.name, icon = socketType.icon,
                        })
                    end
                end
            end
        end
    end

    return result.totalCount > 0 and result or nil
end

function CP:ScanAllEquippedSockets()
    wipe(socketCache)
    for _, slotID in ipairs(socketableSlots) do
        local socketInfo = self:ScanItemSockets(slotID)
        if socketInfo then table.insert(socketCache, socketInfo) end
    end
    return socketCache
end

function CP:ScanBagsForGems()
    wipe(gemCache)
    local NUM_BAG_SLOTS = NUM_BAG_SLOTS or 4
    local LE_ITEM_CLASS_GEM = Enum.ItemClass.Gem or 3
    for bag = 0, NUM_BAG_SLOTS do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(info.itemID)
                if classID == LE_ITEM_CLASS_GEM then
                    local existing = gemCache[info.itemID]
                    if existing then
                        existing.count = existing.count + info.stackCount
                    else
                        gemCache[info.itemID] = {
                            itemID = info.itemID, icon = info.iconFileID,
                            count = info.stackCount, link = info.hyperlink,
                            bagID = bag, slotID = slot,
                        }
                    end
                end
            end
        end
    end
    return gemCache
end

function CP:CreateSocketContainer()
    if self.socketContainer then return self.socketContainer end

    local db = self.db
    local anchor = CharacterFrameTab3 or CharacterFrameTab2 or CharacterFrameTab1 or CharacterFrame

    local container = CreateFrame("Frame", "KE_SocketContainer", PaperDollFrame)
    container:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, -6)
    container:SetSize(200, db.SocketButtonSize)
    container:Hide()

    container.buttons = {}
    self.socketContainer = container
    return container
end

function CP:CreateSocketButton(index)
    local db = self.db
    local container = self.socketContainer
    if container.buttons[index] then return container.buttons[index] end

    local Theme = KE.Theme

    local btn = CreateFrame("Button", nil, container)
    btn:SetSize(db.SocketButtonSize, db.SocketButtonSize)
    if index == 1 then
        btn:SetPoint("LEFT", container, "LEFT", 0, 0)
    else
        btn:SetPoint("LEFT", container.buttons[index - 1], "RIGHT", db.SocketButtonSpacing, 0)
    end

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()
    KE:ApplyIconZoom(btn.icon, 0.3)
    KE:AddIconBorders(btn, Theme.border)

    btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.highlight:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    btn.highlight:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    btn.highlight:SetColorTexture(1, 1, 1, 0.2)
    btn.highlight:SetBlendMode("ADD")

    btn.qualityFrame, btn.quality = CreateQualityOverlay(btn)

    btn:SetScript("OnEnter", function(self)
        CP.currentSocketBtn = self
        CP:ShowGemPopup(self)
        if self.socketInfo then CP:ShowSlotHighlight(self.socketInfo.slotID) end
        if self.socket and self.socket.filled and self.socket.gemLink then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 40, 0)
            GameTooltip:SetHyperlink(self.socket.gemLink)
            GameTooltip:Show()
        end
    end)

    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
        C_Timer.After(0.05, function()
            if IsMouseOverGemUI() then return end
            CP:HideGemPopup()
            CP:HideSlotHighlight()
        end)
    end)

    btn:SetScript("OnClick", function(self)
        if InCombatLockdown() then
            KE:Print("Cannot socket during combat")
            return
        end
        if self.socketInfo then SocketInventoryItem(self.socketInfo.slotID) end
    end)

    container.buttons[index] = btn
    return btn
end

function CP:CreateGemPopup()
    if self.gemPopup then return self.gemPopup end

    local Theme = KE.Theme

    local popup = CreateFrame("Frame", "KE_GemPopup", UIParent, "BackdropTemplate")
    popup:SetBackdrop(STANDARD_BACKDROP)
    popup:SetBackdropColor(Theme.bgMedium[1], Theme.bgMedium[2], Theme.bgMedium[3], Theme.bgMedium[4])
    popup:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
    popup:SetSize(280, 50)
    popup:SetFrameStrata("TOOLTIP")
    popup:SetClipsChildren(true)
    popup:Hide()

    popup.title = popup:CreateFontString(nil, "OVERLAY")
    popup.title:SetPoint("TOPLEFT", 6, -6)
    KE:ApplyFontToText(popup.title, "Expressway", 14, "OUTLINE")
    popup.title:SetText("Gems")
    popup.title:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3])

    popup.separator = popup:CreateTexture(nil, "ARTWORK")
    popup.separator:SetHeight(1)
    popup.separator:SetPoint("TOPLEFT", popup, "TOPLEFT", 0, -TITLE_HEIGHT)
    popup.separator:SetPoint("TOPRIGHT", popup, "TOPRIGHT", 0, -TITLE_HEIGHT)
    popup.separator:SetColorTexture(Theme.border[1], Theme.border[2], Theme.border[3], 1)

    popup.noGems = popup:CreateFontString(nil, "OVERLAY")
    popup.noGems:SetPoint("CENTER", 0, -8)
    KE:ApplyFontToText(popup.noGems, "Expressway", 14, "OUTLINE")
    popup.noGems:SetText("No compatible gems")
    popup.noGems:SetTextColor(Theme.textMuted[1], Theme.textMuted[2], Theme.textMuted[3])
    popup.noGems:Hide()

    popup:EnableMouse(true)
    popup:SetScript("OnEnter", function()
        if CP.currentSocketBtn and CP.currentSocketBtn.socketInfo then
            CP:ShowSlotHighlight(CP.currentSocketBtn.socketInfo.slotID)
        end
    end)
    popup:SetScript("OnLeave", function()
        C_Timer.After(0.05, function()
            if IsMouseOverGemUI() then return end
            CP:HideGemPopup()
            CP:HideSlotHighlight()
        end)
    end)

    popup.buttons = {}
    self.gemPopup = popup
    return popup
end

function CP:CreateGemButton(index)
    local popup = self.gemPopup
    local Theme = KE.Theme
    local iconSize = POPUP_ICON_SIZE
    local rowHeight = POPUP_ICON_SIZE + ITEM_ROW_PADDING

    if popup.buttons[index] then return popup.buttons[index] end

    local btn = CreateFrame("Button", "KE_GemBtn" .. index, popup)
    btn:SetHeight(rowHeight)
    btn:SetPoint("TOPLEFT",  popup, "TOPLEFT",  POPUP_PADDING, -TITLE_HEIGHT - (index - 1) * rowHeight)
    btn:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -POPUP_PADDING, -TITLE_HEIGHT - (index - 1) * rowHeight)

    btn.iconFrame = CreateFrame("Frame", nil, btn)
    btn.iconFrame:SetSize(iconSize, iconSize)
    btn.iconFrame:SetPoint("LEFT", 0, 0)
    KE:AddIconBorders(btn.iconFrame, Theme.border)

    btn.icon = btn.iconFrame:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()
    KE:ApplyIconZoom(btn.icon, 0.3)

    btn.qualityFrame, btn.quality = CreateQualityOverlay(btn, btn.iconFrame)

    btn.stats = btn:CreateFontString(nil, "OVERLAY")
    btn.stats:SetPoint("LEFT", btn.iconFrame, "RIGHT", 6, 0)
    btn.stats:SetWidth(220)
    btn.stats:SetJustifyH("LEFT")
    btn.stats:SetWordWrap(true)
    KE:ApplyFontToText(btn.stats, "Expressway", 12, "OUTLINE")
    btn.stats:SetTextColor(Theme.textPrimary[1], Theme.textPrimary[2], Theme.textPrimary[3])
    btn.stats:SetShadowColor(0, 0, 0, 0)

    btn.count = btn:CreateFontString(nil, "OVERLAY")
    btn.count:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
    KE:ApplyFontToText(btn.count, "Expressway", 12, "OUTLINE")
    btn.count:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3])
    btn.count:SetShadowColor(0, 0, 0, 0)

    local hoverBg = btn:CreateTexture(nil, "BACKGROUND")
    hoverBg:SetAllPoints()
    hoverBg:SetColorTexture(1, 1, 1, 0.05)
    hoverBg:SetAlpha(0)
    btn._hoverBg = hoverBg
    btn._hoverTarget = 0

    btn:SetScript("OnUpdate", function(self, elapsed)
        local current = self._hoverBg:GetAlpha()
        if math.abs(current - self._hoverTarget) > 0.01 then
            local speed = elapsed / HOVER_DURATION
            if self._hoverTarget > current then
                self._hoverBg:SetAlpha(math.min(current + speed, self._hoverTarget))
            else
                self._hoverBg:SetAlpha(math.max(current - speed, self._hoverTarget))
            end
        end
    end)

    btn:SetScript("OnEnter", function(self)
        self._hoverTarget = 1
        if self.targetSlotID then CP:ShowSlotHighlight(self.targetSlotID) end
        if self.gemData and self.gemData.link then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 40, 0)
            GameTooltip:SetHyperlink(self.gemData.link)
            GameTooltip:Show()
        end
    end)

    btn:SetScript("OnLeave", function(self)
        self._hoverTarget = 0
        GameTooltip:Hide()
        C_Timer.After(0.05, function()
            if IsMouseOverGemUI() then return end
            CP:HideGemPopup()
            CP:HideSlotHighlight()
        end)
    end)

    btn:SetScript("OnClick", function(self)
        if InCombatLockdown() then
            KE:Print("Cannot socket during combat")
            return
        end
        if self.gemData and self.targetSlotID and self.targetSocketIndex then
            SocketInventoryItem(self.targetSlotID)
            C_Container.PickupContainerItem(self.gemData.bagID, self.gemData.slotID)
            C_ItemSocketInfo.ClickSocketButton(self.targetSocketIndex)
            ClearCursor()
            AcceptSockets()
            CloseSocketInfo()
            if ItemSocketingFrame then HideUIPanel(ItemSocketingFrame) end
            CP:HideGemPopup()
            CP:HideSlotHighlight()
            C_Timer.After(0.1, function()
                if InCombatLockdown() then return end
                CP:RefreshSocketButtons()
            end)
        end
    end)

    popup.buttons[index] = btn
    return btn
end

function CP:RefreshSocketButtons()
    if not self.socketContainer then return end
    if not self.db.SocketHelperEnabled then return end

    local allSockets = self:ScanAllEquippedSockets()
    local db = self.db
    local buttonIndex = 1

    self.socketContainer:SetHeight(db.SocketButtonSize)

    for _, itemSocketInfo in ipairs(allSockets) do
        for _, socket in ipairs(itemSocketInfo.sockets) do
            if not db.ShowOnlyEmptySockets or not socket.filled then
                local btn = self:CreateSocketButton(buttonIndex)
                btn.socketInfo = itemSocketInfo
                btn.socket = socket
                btn:SetSize(db.SocketButtonSize, db.SocketButtonSize)
                btn:ClearAllPoints()
                if buttonIndex == 1 then
                    btn:SetPoint("LEFT", self.socketContainer, "LEFT", 0, 0)
                else
                    btn:SetPoint("LEFT", self.socketContainer.buttons[buttonIndex - 1], "RIGHT", db.SocketButtonSpacing, 0)
                end

                if socket.filled and socket.icon then
                    btn.icon:SetTexture(socket.icon)
                    btn:SetAlpha(1)
                    local atlas = GetQualityAtlasFromLink(socket.gemLink)
                    SetQualityAtlas(btn.quality, atlas)
                else
                    btn.icon:SetTexture(socket.icon or 458977)
                    btn:SetAlpha(0.85)
                    btn.quality:Hide()
                end

                btn:Show()
                buttonIndex = buttonIndex + 1
            end
        end
    end

    for i = buttonIndex, #self.socketContainer.buttons do
        self.socketContainer.buttons[i]:Hide()
    end

    local totalWidth = (buttonIndex - 1) * (db.SocketButtonSize + db.SocketButtonSpacing)
    self.socketContainer:SetWidth(totalWidth > 0 and totalWidth or 1)

    if buttonIndex > 1 then self.socketContainer:Show() else self.socketContainer:Hide() end
end

function CP:ShowGemPopup(socketBtn)
    if not socketBtn.socket then self:HideGemPopup(); return end

    local popup = self:CreateGemPopup()
    local gems = self:ScanBagsForGems()
    -- Re-pull theme colors each show so a theme change applies without a reload
    -- (the popup + its buttons are created once and cached).
    local Theme = KE.Theme

    local gemList = {}
    local currentGemID = socketBtn.socket.gemID
    for _, gemData in pairs(gems) do
        if gemData.itemID ~= currentGemID then table.insert(gemList, gemData) end
    end

    popup.title:SetText(socketBtn.socket.filled and "Replace Gem" or "Socket Gem")
    popup.title:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3])

    local minWidth = popup.title:GetStringWidth() + 26
    local minRowHeight = POPUP_ICON_SIZE + ITEM_ROW_PADDING
    local targetHeight

    if #gemList == 0 then
        popup.noGems:Show()
        popup.separator:Hide()
        popup.noGems:SetText(socketBtn.socket.filled and "No replacement gems" or "No compatible gems")
        popup.noGems:SetTextColor(Theme.textMuted[1], Theme.textMuted[2], Theme.textMuted[3])
        for _, btn in pairs(popup.buttons) do btn:Hide() end
        popup:SetWidth(math.max(200, minWidth))
        targetHeight = 50
    else
        popup.noGems:Hide()
        popup.separator:Show()

        local yOffset = TITLE_HEIGHT
        for i, gemData in ipairs(gemList) do
            local btn = self:CreateGemButton(i)
            btn.gemData = gemData
            btn.targetSlotID = socketBtn.socketInfo.slotID
            btn.targetSocketIndex = socketBtn.socket.index
            btn.icon:SetTexture(gemData.icon)
            btn.count:SetText(gemData.count .. "x")
            btn.count:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3])
            btn._hoverBg:SetAlpha(0); btn._hoverTarget = 0

            local stats = GetGemStatsFromLink(gemData.link)
            btn.stats:SetText(stats or "")
            btn.stats:SetTextColor(Theme.textPrimary[1], Theme.textPrimary[2], Theme.textPrimary[3])

            local textHeight = btn.stats:GetStringHeight()
            local rowHeight = math.max(minRowHeight, textHeight + ITEM_ROW_PADDING)
            btn:SetHeight(rowHeight)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", popup, "TOPLEFT", POPUP_PADDING, -yOffset)
            btn:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -POPUP_PADDING, -yOffset)
            btn.iconFrame:SetSize(POPUP_ICON_SIZE, POPUP_ICON_SIZE)

            local atlas = GetQualityAtlasFromLink(gemData.link)
            SetQualityAtlas(btn.quality, atlas)

            btn:Show()
            yOffset = yOffset + rowHeight
        end
        for i = #gemList + 1, #popup.buttons do popup.buttons[i]:Hide() end

        popup:SetWidth(280)
        targetHeight = yOffset
    end

    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", socketBtn, "BOTTOMLEFT", 0, -1)
    popup:SetHeight(targetHeight)
    popup:Show()
end

function CP:HideGemPopup()
    if self.gemPopup then self.gemPopup:Hide() end
end

function CP:ShowSlotHighlight(slotID)
    self:HideSlotHighlight()

    local frameName = SLOT_FRAMES[slotID]
    if not frameName then return end
    local slotFrame = _G[frameName]
    if not slotFrame then return end

    -- Native Blizzard spell-activation overlay glow on the gear slot — the same
    -- code path DominationSocketHelper uses (pixel-identical to the in-game
    -- "ability ready" glow). No accent overlay underneath.
    if ActionButtonSpellAlertManager then
        ActionButtonSpellAlertManager:ShowAlert(slotFrame)
        self._glowingSlotFrame = slotFrame
    end
end

function CP:HideSlotHighlight()
    if ActionButtonSpellAlertManager and self._glowingSlotFrame then
        ActionButtonSpellAlertManager:HideAlert(self._glowingSlotFrame)
        self._glowingSlotFrame = nil
    end
end

function CP:SetupGemSocketHelper()
    if not self.db.SocketHelperEnabled then return end
    if self._gemSocketHooked then return end
    self._gemSocketHooked = true

    self:CreateSocketContainer()
    self:CreateGemPopup()
    -- PaperDollFrame OnShow/OnHide + PLAYER_EQUIPMENT_CHANGED + BAG_UPDATE_DELAYED
    -- handlers are installed by the combined HookCharacterPanel in Task 12.
end

function CP:DisableGemSocketHelper()
    if self.socketContainer then self.socketContainer:Hide() end
    self:HideGemPopup()
    self:HideSlotHighlight()
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

    if self.eventFrame then
        self.eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        self.eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    end

    self:ApplySettings()

    if CharacterFrame and CharacterFrame:IsShown() then
        UpdateDisplay()                                   -- warnings
    end
end

function CP:OnDisable()
    self:ClearAll()                                       -- warnings clear
    if self.eventFrame then self.eventFrame:UnregisterAllEvents() end
    self:DisableGemSocketHelper()
    self:HideAllTrackIndicators()
    self:HideRaceText()
    RestoreCharacterBackground()
    updatePending = false
end

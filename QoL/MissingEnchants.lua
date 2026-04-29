-- ╔══════════════════════════════════════════════════════════╗
-- ║  MissingEnchants.lua                                     ║
-- ║  Module: Missing Enchants/Gems                           ║
-- ║  Purpose: Red warnings on character panel for missing    ║
-- ║           enchants and empty gem sockets. Max level only.║
-- ║  Credit: Based on BetterCharacterPanel by Grimonja.      ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class MissingEnchants: AceModule, AceEvent-3.0
local ME = KitnEssentials:NewModule("MissingEnchants", "AceEvent-3.0")

local _G = _G
local CreateFrame = CreateFrame
local GetInventoryItemLink = GetInventoryItemLink
local GetExpansionForLevel = GetExpansionForLevel
local GetItemInfoInstant = GetItemInfoInstant
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

local function GetFontSettings()
    local db = ME.db
    local fontFace = db and db.FontFace or "Expressway"
    local fontSize = db and db.FontSize or 13
    local fontOutline = db and db.FontOutline or "OUTLINE"
    local fontPath = KE:GetFontPath(fontFace) or KE.FONT or "Fonts\\FRIZQT__.TTF"
    return fontPath, fontSize, fontOutline
end

---------------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------------
local function CreateSlotText(button, slot)
    local fontPath, fontSize, fontOutline = GetFontSettings()
    local text = button:CreateFontString(nil, "OVERLAY")
    text:SetFont(fontPath, fontSize, fontOutline)
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
    local fontPath, fontSize, fontOutline = GetFontSettings()
    for _, text in pairs(slotTexts) do
        text:SetFont(fontPath, fontSize, fontOutline)
    end
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
local function UpdateDisplay()
    local db = ME.db
    local enchantEnabled = db and db.ShowEnchants ~= false
    local gemEnabled = db and db.GemEnabled ~= false
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
            local db = ME.db
            if db and db.HideCharacterBackground then
                HideCharacterBackground()
            end
        end)
    end

    -- PEC alone is the direct signal; UIC was duplicative.
    ME.eventFrame = CreateFrame("Frame")
    ME.eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    ME.eventFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_EQUIPMENT_CHANGED" then
            QueueUpdate()
        end
    end)

    hooked = true
end

function ME:Refresh()
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("BetterCharacterPanel") then return end
    HookCharacterPanel()
    ApplyFontToAll()
    if CharacterFrame and CharacterFrame:IsShown() then
        UpdateDisplay()
    end
end

function ME:ClearAll()
    for _, text in pairs(slotTexts) do text:SetText("") end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function ME:OnInitialize()
    self.db = KE.db.profile.MissingEnchants
    self:SetEnabledState(false)
end

function ME:OnEnable()
    -- Skip if BetterCharacterPanel is loaded (provides same functionality)
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("BetterCharacterPanel") then return end
    if not self.db.ShowEnchants and not self.db.GemEnabled and not self.db.HideCharacterBackground then return end
    HookCharacterPanel()
    if CharacterFrame and CharacterFrame:IsShown() then
        UpdateDisplay()
    end
end

function ME:OnDisable()
    self:ClearAll()
    if self.eventFrame then
        self.eventFrame:UnregisterAllEvents()
    end
    RestoreCharacterBackground()
    updatePending = false
end

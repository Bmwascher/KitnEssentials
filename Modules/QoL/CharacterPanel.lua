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
local C_Timer = C_Timer

---------------------------------------------------------------------------------
-- FFD: weak-keyed per-frame state.
-- Stores overlay frames + caches that previously lived as direct fields on
-- Blizzard slot buttons (._slotWarning, ._slotDetail, ._trackOverlay). Weak
-- keys auto-GC when the Blizz frame is destroyed; using an external table
-- reduces 12.0 taint surface for the future inspect module port.
---------------------------------------------------------------------------------
local FFD = setmetatable({}, { __mode = "k" })
local function GetFFD(frame)
    local d = FFD[frame]
    if not d then d = {}; FFD[frame] = d end
    return d
end

-- O(1) slotID -> slot frame lookup. PLAYER_EQUIPMENT_CHANGED carries the
-- slotID as arg1, so routing a single-slot refresh avoids the full 17-slot
-- iteration that UpdateAllSlotDetails / UpdateAllTrackIndicators do.
-- Populated lazily on first use (slot frames may not exist at file-parse time
-- if another addon has reparented them).
local SLOT_FRAMES_BY_ID = {}
local _slotFramesMapBuilt = false
local function BuildSlotFramesByID()
    if _slotFramesMapBuilt then return end
    _slotFramesMapBuilt = true
    for slotID, frameName in pairs(SLOT_FRAMES) do
        local frame = _G[frameName]
        if frame then SLOT_FRAMES_BY_ID[slotID] = frame end
    end
end

-- Per-slot dirty cache. Each render function gates on its own subset of
-- fields:
--   warning   -> warnLink, warnEnchant
--   detail    -> detailLink, detailEnchant, detailIlvl
--   track     -> trackLink, trackKey
-- Only fields derived from non-secret APIs (GetInventoryItemLink, parsed
-- enchant/track IDs, ItemLocation-derived ilvl on the player) are cached.
-- See feedback_dirty_check_secret_durations memory note for why we don't
-- extend this to stat/duration values.
local _lastSlotState = {}
local function _slotState(slotID)
    local s = _lastSlotState[slotID]
    if not s then s = {}; _lastSlotState[slotID] = s end
    return s
end

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

-- Empty-socket fallback icon keyed by C_TooltipInfo's line.socketType string.
local EMPTY_SOCKET_ICON = {}
for _, t in ipairs(GEM_SOCKET_TYPES) do EMPTY_SOCKET_ICON[t.name] = t.icon end

-- C_TooltipInfo gem-socket line type (3); resolved from Enum with a literal fallback.
local SOCKET_LINE_TYPE = (Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.GemSocket) or 3

-- Inspect socket-scan tracing. Flip true, /reload, inspect a target with gemmed
-- gear, paste the chat log. Dumps (once per unit+slot) every C_TooltipInfo line that
-- looks gem-related plus what C_Item.GetItemGem returns, so we can see exactly where
-- the inspect gem data lives. Leave false in shipped code.
local DEBUG_CP = false

-- Slot IDs the gem socket helper scans.
local socketableSlots = { 1, 2, 5, 6, 9, 10, 11, 12, 13, 14, 15 }

-- Set form of socketableSlots for O(1) membership (used by per-slot detail gems).
local socketableSlotSet = {}
for _, slotID in ipairs(socketableSlots) do socketableSlotSet[slotID] = true end

-- Enchant label processing: map full effect names to short stat-based labels,
-- strip the "Enchant <Slot> - " prefixes, then abbreviate stat words. Anything
-- not in the tables falls through to a length-truncated raw name.
local enchantStripPrefixes = {
    ["Enchant "]      = "",
    ["Weapon %- "]    = "",
    ["Shoulders %- "] = "",
    ["Chest %- "]     = "",
    ["Ring %- "]      = "",
    ["Boots %- "]     = "",
    ["Helm %- "]      = "",
    ["%+"]            = "",
}

local enchantStatAbbrev = {
    ["Stamina"]         = "Stam",
    ["Intellect"]       = "Int",
    ["Agility"]         = "Agi",
    ["Strength"]        = "Str",
    ["Mastery"]         = "Mast",
    ["Versatility"]     = "Vers",
    ["Critical Strike"] = "Crit",
    ["Haste"]           = "Haste",
    ["Avoidance"]       = "Avoid",
}

local enchantNicknames = {
    ["Minor Speed Increase"] = "Speed",
    ["Homebound Speed"]      = "Speed & HS Red.",
    ["Plainsrunner's Breeze"] = "Speed",
    ["Graceful Avoidance"]   = "Avoid",
    ["Regenerative Leech"]   = "Leech",
    ["Watcher's Loam"]       = "Stam",
    ["Rider's Reassurance"]  = "Mount Speed",
    ["Accelerated Agility"]  = "Speed & Agi",
    ["Reserve of Int"]       = "Mana & Int",
    ["Sustained Str"]        = "Stam & Str",
    ["Waking Stats"]         = "Primary Stat",
    ["Cavalry's March"]      = "Mount Speed",
    ["Scout's March"]        = "Speed",
    ["Defender's March"]     = "Stam",
    ["Stormrider's Agi"]     = "Agi & Speed",
    ["Council's Intellect"]  = "Int & Mana",
    ["Crystalline Radiance"] = "Primary Stat",
    ["Oathsworn's Strength"] = "Str & Stam",
    ["Chant of Armored Avoidance"] = "Avoid",
    ["Chant of Armored Leech"]     = "Leech",
    ["Chant of Armored Speed"]     = "Speed",
    ["Chant of Winged Grace"]      = "Avoid & FallDmg",
    ["Chant of Leeching Fangs"]    = "Leech & Recup",
    ["Chant of Burrowing Rapidity"] = "Speed & HScd",
    ["Cursed Haste"]       = "Haste & |cffcc0000-Vers|r",
    ["Cursed Crit"]        = "Crit & |cffcc0000-Haste|r",
    ["Cursed Mastery"]     = "Mast & |cffcc0000-Crit|r",
    ["Cursed Versatility"] = "Vers & |cffcc0000-Mast|r",
    ["Shadowed Belt Clasp"] = "Stamina",
    ["Incandescent Essence"] = "Essence",
    ["Acuity of the Ren'dorei"] = "Proc Prim",
    ["Arcane Mastery"]          = "Proc Mast",
    ["Berserker's Rage"]        = "Proc Haste",
    ["Flames of the Sin'dorei"] = "Dot->AoE",
    ["Jan'alai's Precision"]    = "Proc Crit",
    ["Strength of Halazzi"]     = "Bleed",
    ["Worldsoul Aegis"]         = "Shield->AoE",
    ["Worldsoul Tenacity"]      = "Proc Vers",
    ["Empowered Blessing of Speed"] = "Speed+Vigor",
    ["Blessing of Speed"]           = "Speed",
    ["Empowered Rune of Avoidance"] = "Avoid+MS",
    ["Rune of Avoidance"]           = "Avoid",
    ["Empowered Hex of Leeching"]   = "Empowered Leech",
    ["Hex of Leeching"]             = "Leech",
    ["Akil'zon's Swiftness"] = "Speed",
    ["Flight of the Eagle"]  = "Speed",
    ["Amirdrassil's Grace"]  = "Avoid",
    ["Nature's Grace"]       = "Avoid",
    ["Thalassian Recovery"]  = "Leech",
    ["Mark of Nalorakk"]       = "Str & Stam",
    ["Mark of the Magister"]   = "Int & Mana",
    ["Mark of the Rootwarden"] = "Agi & Speed",
    ["Mark of the Worldsoul"]  = "Primary Stat",
    ["Arcanoweave Spellthread"]    = "Int & Mana",
    ["Blood Knight's Armor Kit"]   = "Agi/Str & Armor",
    ["Forest Hunter's Armor Kit"]  = "Ag/Str & Stam",
    ["Thalassian Scout Armor Kit"] = "Agi/Str",
    ["Bright Linen Spellthread"]   = "Int",
    ["Shaladrassil's Roots"] = "Leech & Stam",
    ["Silvermoon's Mending"] = "Leech",
    ["Farstrider's Hunt"]    = "Speed & Stam",
    ["Lynx's Dexterity"]     = "Avoid & Stam",
    ["Eyes of the Eagle"]    = "Crit%+",
    ["Nature's Fury"]        = "Crit",
    ["Nature's Wrath"]       = "Crit",
    ["Silvermoon's Alacrity"] = "Haste%",
    ["Thalassian Haste"]     = "Haste",
    ["Zul'jin's Mastery"]    = "Mast",
    ["Amani Mastery"]        = "Mast",
    ["Silvermoon's Tenacity"] = "Vers",
    ["Thalassian Versatility"] = "Vers",
    ["Rune of the Fallen Crusader"] = "Crusader",
    ["Rune of the Apocalypse"] = "Apocalypse",
    ["Rune of Razorice"] = "Razorice",
    ["Rune of Sanguination"] = "Sanguination",
    ["Rune of the Stoneskin Gargoyle"] = "Gargoyle",
    ["Rune of Unending Thirst"] = "Unend Thirst",
    ["Rune of Spellwarding"] = "Spellwarding",
}

-- Nickname keys sorted longest-first. Matching the most specific entry before its
-- base (e.g. "Empowered Hex of Leeching" before "Hex of Leeching") makes the label
-- deterministic regardless of pairs() order, so the empowered variants keep their
-- distinct labels instead of accidentally falling back to the base.
local enchantNicknameOrder = {}
for seek in pairs(enchantNicknames) do
    enchantNicknameOrder[#enchantNicknameOrder + 1] = seek
end
table.sort(enchantNicknameOrder, function(a, b) return #a > #b end)

-- Pipeline (in order): strip the "Enchant <Slot> - " prefix from the raw effect
-- text, map the bare name through the nickname table, then abbreviate stat words.
local function ProcessEnchantText(text)
    -- Strip the "Enchant <Slot> - " prefix (and any stray "+") from the raw effect
    -- text FIRST, so nickname lookups match the bare effect name and the "+"-strip
    -- can't later eat a "+" a nickname value intentionally adds (e.g. "Crit%+").
    for prefix, replacement in pairs(enchantStripPrefixes) do
        text = text:gsub(prefix, replacement)
    end
    -- Nickname values are literal display labels. Iterate longest-key-first (see
    -- enchantNicknameOrder) and use a FUNCTION replacement so a "%" in the value
    -- (e.g. "Crit%+", "Haste%") is emitted verbatim instead of being treated as a
    -- gsub replacement escape (Lua 5.1 silently drops a lone %).
    for _, seek in ipairs(enchantNicknameOrder) do
        local replacement = enchantNicknames[seek]
        text = text:gsub(seek, function() return replacement end)
    end
    for word, abbrev in pairs(enchantStatAbbrev) do
        text = text:gsub(word, abbrev)
    end
    return text
end

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

-- Inspect paperdoll mirrors the same slot layout; names swap Character->Inspect.
local INSPECT_SLOT_FRAMES = {}
for slotID, frameName in pairs(SLOT_FRAMES) do
    INSPECT_SLOT_FRAMES[slotID] = frameName:gsub("^Character", "Inspect")
end

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

-- Enchant ID from the item link (locale-independent; same field HasEnchant reads).
local function GetSlotEnchantID(unit, slot)
    unit = unit or "player"
    local link = GetInventoryItemLink(unit, slot)
    if not link then return nil end
    local itemString = link:match("item[%-?%d:]+")
    if not itemString then return nil end
    local enchantId = select(3, strsplit(":", itemString))
    if enchantId and enchantId ~= "" and enchantId ~= "0" then
        return tonumber(enchantId)
    end
    return nil
end

-- Effect name from the tooltip's "Enchanted: Enchant <Slot> - <Effect>" line.
-- Returns the full "Enchant <Slot> - <Effect>" text after the "Enchanted: "
-- prefix. ProcessEnchantText does the nickname-map / strip / abbreviate (in that
-- order), so we deliberately do NOT pre-strip here.
local function GetSlotEnchantName(unit, slot)
    unit = unit or "player"
    local data = C_TooltipInfo.GetInventoryItem(unit, slot)
    if not data or not data.lines then return nil end
    local prefix = ENCHANTED_TOOLTIP_LINE:gsub("%%s.*$", "")  -- "Enchanted: "
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if text and text:find(prefix, 1, true) == 1 then
            local body = text:sub(#prefix + 1)
            -- Strip the trailing quality-atlas markup ("|A:Professions-...|a") that
            -- crafted enchants append, so it can't leak into the label.
            body = body:gsub("%s*|A:.-|a", "")
            return strtrim(body)
        end
    end
    return nil
end

-- Fixed (non-configurable): the nickname table keeps labels short, so the
-- truncation cap and gem icon size are constants rather than user sliders.
local SLOT_ENCHANT_MAX_LEN = 18
local SLOT_GEM_ICON_SIZE   = 14

function CP:ResolveEnchantLabel(unit, slot)
    unit = unit or "player"
    -- Enchant-ID check is the locale-robust "is it enchanted?" gate; the readable
    -- label comes from the tooltip + ProcessEnchantText.
    if not GetSlotEnchantID(unit, slot) then return nil end
    local name = GetSlotEnchantName(unit, slot)
    if not name then return "Enchanted" end
    name = ProcessEnchantText(name)
    if #name > SLOT_ENCHANT_MAX_LEN then name = name:sub(1, SLOT_ENCHANT_MAX_LEN) end
    return name
end

function CP:GetSlotItemLevel(unit, slot)
    unit = unit or "player"
    local link = GetInventoryItemLink(unit, slot)
    if not link then return nil end
    -- For the player's own gear, prefer C_Item.GetCurrentItemLevel via ItemLocation:
    -- it has character-scale context, so heirloom and level-scaled items report what
    -- the tooltip displays. The link-only GetDetailedItemLevelInfo lacks that context
    -- and returns a template ilvl (e.g. an heirloom showing 71 instead of the actual
    -- 69 on a low-level character; non-heirloom scaled blues can be far worse).
    if unit == "player" then
        local loc = ItemLocation and ItemLocation:CreateFromEquipmentSlot(slot)
        if loc and loc:IsValid() then
            local lvl = C_Item.GetCurrentItemLevel(loc)
            if lvl and lvl > 0 then return lvl end
        end
    end
    -- Inspect / fallback: no ItemLocation for other units; the link API is the
    -- best we can do, so low-level inspected targets may still show templated ilvls.
    local effective = C_Item.GetDetailedItemLevelInfo(link)
    return effective
end

local function CanEnchantSlot(unit, slot)
    unit = unit or "player"
    local expansion = GetExpansionForLevel(UnitLevel(unit))
    local slots = expansion and expansionEnchantableSlots[expansion]
    if not slots then return false end
    if slots[slot] then return true end

    if slot == INVSLOT_OFFHAND then
        local itemLink = GetInventoryItemLink(unit, slot)
        if itemLink then
            local itemEquipLoc = select(4, GetItemInfoInstant(itemLink))
            return itemEquipLoc ~= "INVTYPE_HOLDABLE" and itemEquipLoc ~= "INVTYPE_SHIELD"
        end
        return false
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

    -- Inset toward the model to align with the slot-detail enchant name.
    local side = slotLayout[slot]
    if side == "left" then
        text:SetPoint("TOPLEFT", button, "TOPRIGHT", 3, -4)
    elseif side == "right" then
        text:SetPoint("TOPRIGHT", button, "TOPLEFT", -3, -4)
    elseif side == "center" then
        -- Weapons: match the slot-detail enchant-name anchor (bottom-side of the
        -- slot) so the warning sits where a real enchant name would, clear of the
        -- ilvl number above the slot. y=4 lifts the baseline so the offhand enchant
        -- doesn't clip the ilvl row beneath the weapon strip.
        if slot == INVSLOT_MAINHAND then
            text:SetJustifyH("RIGHT")
            text:SetPoint("BOTTOMRIGHT", button, "BOTTOMLEFT", -3, 4)
        else
            text:SetJustifyH("LEFT")
            text:SetPoint("BOTTOMLEFT", button, "BOTTOMRIGHT", 3, 4)
        end
    end
    return text
end

local function ApplyFontToAll()
    local db = CP.db
    local fontFace    = (db and db.FontFace)    or "Expressway"
    local fontSize    = (db and db.FontSize)    or 13
    local fontOutline = (db and db.FontOutline) or "OUTLINE"
    for _, buttonName in pairs(allCheckSlots) do
        local button = _G[buttonName]
        local warning = button and FFD[button] and FFD[button].warning
        if warning then
            KE:ApplyFontToText(warning, fontFace, fontSize, fontOutline)
        end
    end
    for _, frameName in pairs(INSPECT_SLOT_FRAMES) do
        local button = _G[frameName]
        local warning = button and FFD[button] and FFD[button].warning
        if warning then
            KE:ApplyFontToText(warning, fontFace, fontSize, fontOutline)
        end
    end
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
-- Per-slot missing-enchant/gem warning. Lazily creates a button-attached
-- FontString so the same helper drives both the player and inspect frames.
local function UpdateSlotWarning(button, unit, slot)
    if not button then return end
    unit = unit or "player"

    -- Dirty-check: itemLink + enchantID determine the warning. If neither
    -- changed since last render, skip the work. Cached only for the player
    -- slot path (inspect path goes through different functions); inspect's
    -- own dirty caching is part of the future inspect module spec.
    if unit == "player" then
        local s = _slotState(slot)
        local link = GetInventoryItemLink(unit, slot)
        local enchantID = GetSlotEnchantID(unit, slot)
        if s.warnLink == link and s.warnEnchant == enchantID then
            return
        end
        s.warnLink, s.warnEnchant = link, enchantID
    end

    local db = CP.db
    local enchantEnabled = db and db.ShowEnchants ~= false

    local ffd = GetFFD(button)
    if not ffd.warning then
        ffd.warning = CreateSlotText(button, slot)
    end

    -- Enchant warning only. A missing GEM is shown as a red empty-socket icon in
    -- the gem row (see UpdateSlotDetail), reference-style, to avoid a third text
    -- line the short slots can't fit.
    local noEnchant = false
    if IsLevelAtEffectiveMaxLevel(UnitLevel(unit)) then
        local itemLink = GetInventoryItemLink(unit, slot)
        if itemLink and enchantEnabled and CanEnchantSlot(unit, slot) and not HasEnchant(itemLink) then
            noEnchant = true
        end
    end

    ffd.warning:SetText(noEnchant and "|cFFFF0000No Enchant|r" or "")
end

local function UpdateDisplay()
    for slot, buttonName in pairs(allCheckSlots) do
        local button = _G[buttonName]
        if button then
            UpdateSlotWarning(button, "player", slot)
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
            -- Register gear-tracking events ONLY while the pane is open. These
            -- fire heavily in combat (every consumable, every gear proc); idle
            -- dispatch was wasted work when the pane was closed.
            if CP.eventFrame then
                CP.eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
                CP.eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
            end
            QueueUpdate()                                 -- warnings
            if CP.db.HideCharacterBackground then HideCharacterBackground() end
            if CP.db.SocketHelperEnabled then CP:RefreshSocketButtons() end
            if CP.db.TrackIndicatorsEnabled then CP:UpdateAllTrackIndicators() end
            if CP.db.ShowSlotItemLevel or CP.db.ShowEnchantNames or CP.db.ShowSlotGems or CP.db.ShowMissingGems then
                CP:UpdateAllSlotDetails()
            end
        end)
        PaperDollFrame:HookScript("OnHide", function()
            if CP.eventFrame then
                CP.eventFrame:UnregisterEvent("PLAYER_EQUIPMENT_CHANGED")
                CP.eventFrame:UnregisterEvent("BAG_UPDATE_DELAYED")
            end
            if CP.socketContainer then CP.socketContainer:Hide() end
            CP:HideGemPopup()
            CP:HideSlotHighlight()
        end)
    end

    -- Persistent event frame, but events are now registered conditionally
    -- (above) on PaperDollFrame Show/Hide. The frame itself is cheap; what
    -- mattered was the dispatch overhead from always-listening.
    CP.eventFrame = CreateFrame("Frame")
    CP.eventFrame:SetScript("OnEvent", function(_, event, slotID)
        if not CP.db.Enabled then return end
        if event == "PLAYER_EQUIPMENT_CHANGED" then
            -- Route by slotID so we update one slot's overlays, not all 17.
            -- The keyed-queue / debounce paths (QueueUpdate, socket helper)
            -- still operate panel-wide because they aggregate cross-slot
            -- state (warning visibility, socket-button row).
            QueueUpdate()                                 -- warnings (debounced, panel-wide)
            if CP.db.SocketHelperEnabled then CP:RefreshSocketButtons() end
            if slotID then
                CP:RefreshSlot(slotID, "player")          -- detail + track for the affected slot only
            end
        elseif event == "BAG_UPDATE_DELAYED" then
            -- Socketing a gem / applying an enchant consumes the item from bags
            -- and fires this rather than PLAYER_EQUIPMENT_CHANGED, so refresh the
            -- missing-enchant/gem warnings here too (debounced + panel-gated).
            QueueUpdate()
            if CP.socketContainer and CP.socketContainer:IsShown() then
                CP:RefreshSocketButtons()
            end
            if CP.db.ShowSlotItemLevel or CP.db.ShowEnchantNames or CP.db.ShowSlotGems or CP.db.ShowMissingGems then
                CP:UpdateAllSlotDetails()
            end
        end
    end)

    hooked = true
end

---------------------------------------------------------------------------------
-- Inspect Frame Support
---------------------------------------------------------------------------------

-- Run all slot overlays (warning / detail / track) for one inspect button.
-- Resolve the unit + slotID for an inspect button, applying the shared guards
-- (db enabled, frame unit available, same-map). Returns (unit, slotID) or nil.
local function ResolveInspectSlot(button)
    if not CP.db or not CP.db.Enabled then return end
    if not button then return end
    local unit = InspectFrame and InspectFrame.unit
    if not unit then return end
    -- Long-range inspect returns incomplete gear; skip only on a CONFIRMED
    -- cross-map mismatch (both maps known and different). An unknown (nil) map
    -- is not treated as a mismatch, so normal same-zone inspects still render.
    local pm = C_Map.GetBestMapForUnit("player")
    local um = C_Map.GetBestMapForUnit(unit)
    if pm and um and pm ~= um then return end

    local slotID = button:GetID()
    if not slotID or slotID == 0 then return end
    return unit, slotID
end

-- Render the overlays (warning + per-slot detail + track letter) for one inspect
-- slot. Pure render: assumes the item's data is already cached. Driven by
-- RequestInspectSlot synchronously (cached items) or by ITEM_DATA_LOAD_RESULT
-- (items that had to load).
function CP:RenderInspectSlot(button)
    local unit, slotID = ResolveInspectSlot(button)
    if not unit then return end
    UpdateSlotWarning(button, unit, slotID)
    if self.db.ShowSlotItemLevel or self.db.ShowEnchantNames or self.db.ShowSlotGems or self.db.ShowMissingGems then
        self:UpdateSlotDetail(button, slotID, unit)
    end
    if self.db.TrackIndicatorsEnabled then
        self:UpdateSlotTrackIndicator(button, slotID, unit)
    end
end

-- Request side of the keyed-queue model: resolve the inspect slot's equipped
-- item, queue {slotID -> itemID}, and ask Blizzard to load its full data.
-- ITEM_DATA_LOAD_RESULT then renders just that slot and drains the queue entry
-- — no blanket re-scan, no self-sustaining loop. Keyed by slotID (not itemID)
-- so two slots sharing an itemID (duplicate rings) both resolve. Reference:
-- BetterCharacterPanel's itemLoadQueue model.
--
-- Always queue + request, never short-circuit on a cache check: C_Item's cache
-- predicates report BASE item data (name, icon, base stats), NOT inspect-specific
-- socket/gem data, which arrives in the inspect packet for THIS player. Items
-- whose base was cached from prior contexts would otherwise render synchronously
-- before the inspect packet's gems loaded, leaving red sockets on filled slots.
-- ITEM_DATA_LOAD_RESULT for the equipped itemID is what signals the inspect
-- packet is ready; for already-base-cached items it fires within ~1 frame, so the
-- deferral is imperceptible. Total C_TooltipInfo allocations per inspect are
-- unchanged — only the timing shifts from "now" to "next event."
function CP:RequestInspectSlot(button)
    local unit, slotID = ResolveInspectSlot(button)
    if not unit then return end

    self._inspectQueue = self._inspectQueue or {}
    local link = GetInventoryItemLink(unit, slotID)
    if not link then
        -- Empty slot: nothing to wait on; clear any pending entry and render.
        self._inspectQueue[slotID] = nil
        self:RenderInspectSlot(button)
        return
    end

    local itemID = C_Item.GetItemInfoInstant(link)
    if not itemID then return end

    -- Skip re-issuing if this slot is already waiting on the same itemID — avoids
    -- piling duplicate requests during a re-pass while the slot's still loading.
    if self._inspectQueue[slotID] ~= itemID then
        self._inspectQueue[slotID] = itemID
        C_Item.RequestLoadItemDataByID(itemID)
    end
end

-- Re-run every inspect slot through the keyed queue (the level hook, INSPECT_READY,
-- UNIT_INVENTORY_CHANGED, etc. all funnel here via QueueInspectUpdate). Cached items
-- render synchronously; uncached items render later via ITEM_DATA_LOAD_RESULT. The
-- average ilvl is full-paperdoll so it only computes when the queue is fully drained.
function CP:UpdateAllInspectSlots()
    self._inspectQueue = self._inspectQueue or {}
    for _, frameName in pairs(INSPECT_SLOT_FRAMES) do
        self:RequestInspectSlot(_G[frameName])
    end
    if next(self._inspectQueue) == nil then
        self:UpdateInspectItemLevel()
    end
end

-- Average-item-level computation, ported from ElvUI (Game/Shared/General/
-- ItemLevel.lua CalculateAverageItemLevel). C_PaperDollInfo.GetInspectItemLevel
-- only returns a rounded integer, so to show real decimals we sum the equipped
-- slots and divide by 16 ourselves — the same arithmetic ElvUI displays.
local AVG_ARMOR_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 }
local AVG_X2_INVTYPES = {
    INVTYPE_2HWEAPON = true,
    INVTYPE_RANGEDRIGHT = true,
    INVTYPE_RANGED = true,
}
local AVG_X2_EXCEPTIONS = { [2] = 19 }  -- wands report RANGEDRIGHT but are 1H

-- Returns the equipped average item level to 2 decimals, or nil if the inspect
-- data isn't ready yet (caller retries on the next INSPECT_READY / late-data event).
function CP:GetInspectAverageItemLevel(unit)
    local spec = GetInspectSpecialization(unit)
    if not spec or spec == 0 then return nil end  -- inspect data not resolved yet

    local total = 0
    for _, id in ipairs(AVG_ARMOR_SLOTS) do
        if GetInventoryItemLink(unit, id) then
            local cur = self:GetSlotItemLevel(unit, id)
            if not cur then return nil end            -- item data still loading
            if cur > 0 then total = total + cur end
        elseif GetInventoryItemTexture(unit, id) then
            return nil                                -- slot filled but link not ready
        end
    end

    local _
    local mainLevel = 0
    local mainQuality, mainEquipLoc, mainClass, mainSubClass
    local mainLink = GetInventoryItemLink(unit, 16)
    if mainLink then
        mainLevel = self:GetSlotItemLevel(unit, 16)
        if not mainLevel then return nil end
        _, _, mainQuality, _, _, _, _, _, mainEquipLoc, _, _, mainClass, mainSubClass = C_Item.GetItemInfo(mainLink)
    elseif GetInventoryItemTexture(unit, 16) then
        return nil
    end

    local offLevel = 0
    local offEquipLoc
    local offLink = GetInventoryItemLink(unit, 17)
    if offLink then
        offLevel = self:GetSlotItemLevel(unit, 17)
        if not offLevel then return nil end
        _, _, _, _, _, _, _, _, offEquipLoc = C_Item.GetItemInfo(offLink)
    elseif GetInventoryItemTexture(unit, 17) then
        return nil
    end

    -- 2H / Titan's Grip handling: count the main hand twice when there's no off
    -- hand and the weapon occupies both slots (excluding wands and Fury warriors).
    if mainQuality == 6 or (not offEquipLoc and AVG_X2_INVTYPES[mainEquipLoc]
        and AVG_X2_EXCEPTIONS[mainClass] ~= mainSubClass and spec ~= 72) then
        mainLevel = math.max(mainLevel, offLevel)
        total = total + mainLevel * 2
    else
        total = total + mainLevel + offLevel
    end

    if total == 0 then return nil end
    return math.floor((total / 16) * 100 + 0.5) / 100
end

-- Blizzard's inspect frame shows no average item level, so render our own.
-- (Mirrors BetterCharacterPanel: a custom FontString on the inspect items frame;
-- there is no native element to restyle the way the player panel reuses
-- CharacterStatsPane.ItemLevelFrame.)
function CP:UpdateInspectItemLevel()
    if not self.db.Enabled then return end
    local unit = InspectFrame and InspectFrame.unit
    if not unit then return end
    -- Same cross-map guard as the slot overlays: long-range inspect returns
    -- incomplete gear, so only render on a confirmed same-map (or unknown) target.
    local pm = C_Map.GetBestMapForUnit("player")
    local um = C_Map.GetBestMapForUnit(unit)
    if pm and um and pm ~= um then return end

    local parent = _G.InspectPaperDollItemsFrame or InspectFrame
    if not parent then return end

    if not self._inspectIlvl then
        local fs = parent:CreateFontString(nil, "OVERLAY")
        fs:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -4, 4)
        fs:SetJustifyH("RIGHT")
        self._inspectIlvl = fs
    end

    local ilvl = self:GetInspectAverageItemLevel(unit)
    if not ilvl or ilvl <= 0 then
        self._inspectIlvl:Hide()
        return
    end

    self:ApplyFont(self._inspectIlvl, self.db.IlvlValueSize or 16)
    local accent = KE.Theme.accent
    self._inspectIlvl:SetTextColor(accent[1], accent[2], accent[3])
    self._inspectIlvl:SetText(string.format("%.2f", ilvl))
    self._inspectIlvl:Show()
end

-- Debounced, next-frame batch of the full inspect refresh. A first inspect fires
-- a burst (per-slot button updates + INSPECT_READY + UNIT_INVENTORY_CHANGED) on the
-- same frame Blizzard loads + renders the inspect UI; collapsing it into ONE
-- deferred pass keeps that heavy tooltip-scan work off the busy load frame.
local inspectUpdatePending = false
local function QueueInspectUpdate()
    if inspectUpdatePending then return end
    if not (CP.db and CP.db.Enabled) then return end
    if not (InspectFrame and InspectFrame:IsShown()) then return end
    inspectUpdatePending = true
    -- 0.2s (not 0.05) collapses bursty late-data events into far fewer full re-scans.
    -- Each re-scan allocates a C_TooltipInfo table per socketable slot, so a higher
    -- debounce directly cuts the transient garbage generated while inspecting.
    C_Timer.After(0.2, function()
        inspectUpdatePending = false
        if CP.db and CP.db.Enabled and InspectFrame and InspectFrame:IsShown() then
            CP:UpdateAllInspectSlots()
        end
    end)
end

function CP:SetupInspectSupport()
    if self._inspectSetup then return end
    self._inspectSetup = true

    -- Forward-declared so installHooks can toggle the data events on it.
    local f
    -- Sole late-data event we need: ITEM_DATA_LOAD_RESULT fires with the equipped
    -- itemID once Blizzard has fully loaded an item we requested (incl. its socketed
    -- gems). The Task 0 trace confirmed SOCKET_INFO_UPDATE and GET_ITEM_INFO_RECEIVED
    -- never fired in the inspect path with active requests in place. Registered only
    -- while the inspect frame is open.
    local INSPECT_DATA_EVENTS = { "ITEM_DATA_LOAD_RESULT" }

    -- Best-effort per-slot hooks. These only exist once Blizzard_InspectUI is
    -- loaded, and may not fire on every code path, so they are NOT the primary
    -- render trigger — INSPECT_READY (below) is. Idempotent: safe to call again.
    local function installHooks()
        if self._inspectHooked then return end
        if not InspectPaperDollItemSlotButton_Update then return end
        self._inspectHooked = true
        hooksecurefunc("InspectPaperDollItemSlotButton_Update", function()
            QueueInspectUpdate()
        end)
        if InspectPaperDollFrame_SetLevel then
            hooksecurefunc("InspectPaperDollFrame_SetLevel", function()
                QueueInspectUpdate()
            end)
        end
        -- ITEM_DATA_LOAD_RESULT fires per item we requested via RequestInspectSlot;
        -- it lands gem data with the equipped item's itemID. Registered only while
        -- the inspect frame is shown so we don't react to player-side item loads.
        if InspectFrame then
            local function regData()   for _, e in ipairs(INSPECT_DATA_EVENTS) do f:RegisterEvent(e) end end
            local function unregData()
                for _, e in ipairs(INSPECT_DATA_EVENTS) do f:UnregisterEvent(e) end
                if CP._inspectQueue then wipe(CP._inspectQueue) end
            end
            InspectFrame:HookScript("OnShow", regData)
            InspectFrame:HookScript("OnHide", unregData)
            if InspectFrame:IsShown() then regData() end
        end
    end

    -- Persistent frame: always alive so it catches the events regardless of when
    -- Blizzard_InspectUI loads relative to this module's init. The late-data events
    -- are registered on demand (only while the inspect frame is shown) by installHooks.
    f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:RegisterEvent("INSPECT_READY")
    f:RegisterEvent("UNIT_INVENTORY_CHANGED")
    f:SetScript("OnEvent", function(_, event, arg1, arg2)
        -- Task 0 trace: log every inspect-related event with its args + timestamp so
        -- it can be correlated against the "FLIP" lines from ScanItemSockets to learn
        -- which event drives a late gem's resolution.
        if DEBUG_CP then
            KE:Print(string.format("[CP] EVT %s a1=%s a2=%s t=%.2f",
                event, tostring(arg1), tostring(arg2), GetTime()))
        end
        if event == "ADDON_LOADED" then
            if arg1 == "Blizzard_InspectUI" then installHooks() end
        elseif event == "INSPECT_READY" then
            -- New inspect target: clear the per-slot pending queue so the new unit's
            -- gear gets requested fresh, then ensure the hooks exist and queue a pass.
            if CP._inspectQueue then wipe(CP._inspectQueue) end
            if CP._cpDbg then wipe(CP._cpDbg) end          -- debug: re-allow dumps
            if CP._cpDbgFilled then wipe(CP._cpDbgFilled) end
            installHooks()
            QueueInspectUpdate()
        elseif event == "UNIT_INVENTORY_CHANGED" then
            -- Inspected unit's gear changed mid-inspect — re-pass to pick up the new
            -- item(s). RequestInspectSlot handles changed-itemID per slot correctly.
            if arg1 and InspectFrame and arg1 == InspectFrame.unit then
                QueueInspectUpdate()
            end
        elseif event == "ITEM_DATA_LOAD_RESULT" then
            -- A requested item finished loading. Render only the slot(s) that were
            -- waiting on this exact itemID (targeted, not blanket), and recompute the
            -- average once the last pending slot drains.
            local itemID = arg1
            if itemID and CP._inspectQueue and InspectFrame and InspectFrame:IsShown() then
                for slotID, queuedID in pairs(CP._inspectQueue) do
                    if queuedID == itemID then
                        CP._inspectQueue[slotID] = nil
                        local slotFrameName = INSPECT_SLOT_FRAMES[slotID]
                        local b = slotFrameName and _G[slotFrameName]
                        if b then CP:RenderInspectSlot(b) end
                    end
                end
                if next(CP._inspectQueue) == nil then
                    CP:UpdateInspectItemLevel()
                end
            end
        end
    end)

    -- If the inspect UI is already loaded at setup, hook immediately.
    if C_AddOns.IsAddOnLoaded("Blizzard_InspectUI") then installHooks() end
end

function CP:Refresh()
    self.db = KE.db.profile.CharacterPanel
    HookCharacterPanel()
    self:SetupInspectSupport()
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
    if (self.db.ShowSlotItemLevel or self.db.ShowEnchantNames or self.db.ShowSlotGems or self.db.ShowMissingGems)
        and PaperDollFrame and PaperDollFrame:IsShown() then
        self:UpdateAllSlotDetails()
    end
end

function CP:ClearAll()
    for _, buttonName in pairs(allCheckSlots) do
        local button = _G[buttonName]
        local warning = button and FFD[button] and FFD[button].warning
        if warning then warning:SetText("") end
    end
    for _, frameName in pairs(INSPECT_SLOT_FRAMES) do
        local button = _G[frameName]
        local warning = button and FFD[button] and FFD[button].warning
        if warning then warning:SetText("") end
    end
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
function CP:GetItemTrack(unit, slotID)
    unit = unit or "player"
    local data = C_TooltipInfo.GetInventoryItem(unit, slotID)
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
        local itemLink = GetInventoryItemLink(unit, slotID)
        if itemLink then
            local ilvl = C_Item.GetDetailedItemLevelInfo(itemLink)
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
    local ffd = GetFFD(slotFrame)
    if ffd.track then return ffd.track end

    local isRight = RIGHT_SLOTS[slotID]
    local overlay = CreateFrame("Frame", nil, slotFrame)
    overlay:SetSize(14, 14)
    overlay:SetFrameLevel(slotFrame:GetFrameLevel() + 10)

    if isRight then
        overlay:SetPoint("BOTTOMRIGHT", slotFrame, "BOTTOMRIGHT", 1, 1)
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
    ffd.track = overlay
    return overlay
end

function CP:UpdateSlotTrackIndicator(slotFrame, slotID, unit)
    unit = unit or "player"
    if not slotFrame then return end

    -- Dirty-check (player path only): itemLink + track letter determine the
    -- rendered output. Skip the font re-apply + SetText when unchanged.
    if unit == "player" then
        local s = _slotState(slotID)
        local link = GetInventoryItemLink(unit, slotID)
        local track = self:GetItemTrack(unit, slotID)
        local key = track and track.letter or nil
        if s.trackLink == link and s.trackKey == key then return end
        s.trackLink, s.trackKey = link, key
    end

    local overlay = self:CreateTrackOverlay(slotFrame, slotID)
    local track = self:GetItemTrack(unit, slotID)

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
    for slotID, frameName in pairs(SLOT_FRAMES) do
        self:UpdateSlotTrackIndicator(_G[frameName], slotID, "player")
    end
end

function CP:HideAllTrackIndicators()
    for _, frameName in pairs(SLOT_FRAMES) do
        local slotFrame = _G[frameName]
        local overlay = slotFrame and FFD[slotFrame] and FFD[slotFrame].track
        if overlay then overlay:Hide() end
    end
    for _, frameName in pairs(INSPECT_SLOT_FRAMES) do
        local slotFrame = _G[frameName]
        local overlay = slotFrame and FFD[slotFrame] and FFD[slotFrame].track
        if overlay then overlay:Hide() end
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
-- Slot Details (per-slot item level / enchant label / inline gem icons)
---------------------------------------------------------------------------------

-- Number of gem icons a slot can show inline (matches the 3-socket max).
local SLOT_DETAIL_MAX_GEMS = 3

-- Sanitize the configured outline for Blizzard-adjacent FontStrings — SOFTOUTLINE
-- is KE's custom 8-shadow system and renders as solid black on these, so collapse
-- it to a plain OUTLINE (same rule the warning/level texts follow via ApplyFont).
local function SanitizeDetailOutline(outline)
    if outline == "SOFTOUTLINE" then return "OUTLINE" end
    return outline or "OUTLINE"
end

local CENTER_SLOTS = { [16] = true, [17] = true }

-- Anchor the gem-icon row inline beside the ilvl text (reference model).
local function AnchorGemsRightOf(detail, parent)
    for i = 1, SLOT_DETAIL_MAX_GEMS do
        local icon = detail.gemIcons[i]
        icon:ClearAllPoints()
        if i == 1 then
            -- 0 (vs the right side's 1) intentionally compensates for sub-pixel
            -- rounding that made the left gems read 1px looser than the right.
            icon:SetPoint("LEFT", parent, "RIGHT", 0, 0)
        else
            icon:SetPoint("LEFT", detail.gemIcons[i - 1], "RIGHT", 2, 0)
        end
    end
end

local function AnchorGemsLeftOf(detail, parent)
    for i = 1, SLOT_DETAIL_MAX_GEMS do
        local icon = detail.gemIcons[i]
        icon:ClearAllPoints()
        if i == 1 then
            icon:SetPoint("RIGHT", parent, "LEFT", -1, 0)
        else
            icon:SetPoint("RIGHT", detail.gemIcons[i - 1], "LEFT", -2, 0)
        end
    end
end

function CP:CreateSlotDetail(slotFrame, slotID)
    local ffd = GetFFD(slotFrame)
    if ffd.detail then return ffd.detail end

    local isRight  = RIGHT_SLOTS[slotID]
    local isCenter = CENTER_SLOTS[slotID]
    local fontFace    = self.db.FontFace or "Expressway"
    local fontSize    = self.db.SlotInfoFontSize or 11
    local fontOutline = SanitizeDetailOutline(self.db.FontOutline)

    -- Parent to the slot's parent so the strip can extend beyond the slot bounds
    -- without clipping; render above the slot.
    local detail = CreateFrame("Frame", nil, slotFrame:GetParent())
    detail:SetWidth(100)
    detail:SetFrameLevel(slotFrame:GetFrameLevel() + 10)

    detail.enchantText = detail:CreateFontString(nil, "OVERLAY")
    KE:ApplyFont(detail.enchantText, fontFace, fontSize, fontOutline)
    detail.enchantText:SetTextColor(0, 1, 0, 1)
    detail.enchantText:SetShadowColor(0, 0, 0, 0)

    detail.ilvlText = detail:CreateFontString(nil, "OVERLAY")
    KE:ApplyFont(detail.ilvlText, fontFace, fontSize, fontOutline)
    detail.ilvlText:SetShadowColor(0, 0, 0, 0)

    local iconSize = SLOT_GEM_ICON_SIZE
    detail.gemIcons = {}
    for i = 1, SLOT_DETAIL_MAX_GEMS do
        local iconFrame = CreateFrame("Frame", nil, detail)
        iconFrame:SetSize(iconSize, iconSize)
        local tex = iconFrame:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        KE:ApplyIconZoom(tex, 0.3)
        KE:AddIconBorders(iconFrame, { 0, 0, 0, 1 })
        iconFrame.tex = tex
        iconFrame:Hide()
        detail.gemIcons[i] = iconFrame
    end

    -- Static anchors per slot side (reference model): enchant at the slot's
    -- inner-TOP, item level at the inner-BOTTOM, gem icons inline beside the ilvl.
    detail.enchantText:ClearAllPoints()
    detail.ilvlText:ClearAllPoints()
    if isCenter then
        -- Weapons at the bottom-center: ilvl above the slot; enchant + gems to the
        -- outer side (mainhand -> left, offhand -> right). y=4 on the enchant lifts
        -- the baseline so the offhand enchant doesn't clip the ilvl row below the
        -- weapon strip. Must stay in lockstep with the warning anchor in
        -- CreateSlotText so the missing-enchant red text occupies the same line.
        detail:SetPoint("BOTTOMLEFT", slotFrame, "BOTTOMLEFT", -100, 0)
        detail:SetPoint("TOPRIGHT", slotFrame, "TOPRIGHT", 0, -100)
        detail.ilvlText:SetPoint("BOTTOM", slotFrame, "TOP", 0, 3)
        if slotID == 16 then
            detail.enchantText:SetJustifyH("RIGHT")
            detail.enchantText:SetPoint("BOTTOMRIGHT", slotFrame, "BOTTOMLEFT", -3, 4)
            AnchorGemsLeftOf(detail, detail.ilvlText)
        else
            detail.enchantText:SetJustifyH("LEFT")
            detail.enchantText:SetPoint("BOTTOMLEFT", slotFrame, "BOTTOMRIGHT", 3, 4)
            AnchorGemsRightOf(detail, detail.ilvlText)
        end
    elseif isRight then
        detail:SetPoint("TOPRIGHT", slotFrame, "TOPLEFT", 0, 0)
        detail:SetPoint("BOTTOMRIGHT", slotFrame, "BOTTOMLEFT", 0, 0)
        detail.ilvlText:SetJustifyH("RIGHT")
        detail.ilvlText:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -3, 2)
        detail.enchantText:SetJustifyH("RIGHT")
        detail.enchantText:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -3, -6)
        AnchorGemsLeftOf(detail, detail.ilvlText)
    else
        detail:SetPoint("TOPLEFT", slotFrame, "TOPRIGHT", 0, 0)
        detail:SetPoint("BOTTOMLEFT", slotFrame, "BOTTOMRIGHT", 0, 0)
        detail.ilvlText:SetJustifyH("LEFT")
        detail.ilvlText:SetPoint("BOTTOMLEFT", detail, "BOTTOMLEFT", 3, 2)
        detail.enchantText:SetJustifyH("LEFT")
        detail.enchantText:SetPoint("TOPLEFT", detail, "TOPLEFT", 3, -6)
        AnchorGemsRightOf(detail, detail.ilvlText)
    end

    ffd.detail = detail
    return detail
end

function CP:UpdateSlotDetail(slotFrame, slotID, unit)
    unit = unit or "player"
    if not slotFrame then return end

    -- Dirty-check (player path only): itemLink + enchantID + ilvl determine
    -- the rendered output. If all three match the previous render, skip the
    -- font re-apply + SetText + gem-icon work entirely. Inspect path goes
    -- unguarded here — its own invalidation lives in INSPECT_READY.
    if unit == "player" then
        local s = _slotState(slotID)
        local link = GetInventoryItemLink(unit, slotID)
        local enchantID = GetSlotEnchantID(unit, slotID)
        local ilvl = self:GetSlotItemLevel(unit, slotID)
        if s.detailLink == link and s.detailEnchant == enchantID and s.detailIlvl == ilvl then
            return
        end
        s.detailLink, s.detailEnchant, s.detailIlvl = link, enchantID, ilvl
    end

    local detail = self:CreateSlotDetail(slotFrame, slotID)
    local fontFace    = self.db.FontFace or "Expressway"
    local fontSize    = self.db.SlotInfoFontSize or 11
    local fontOutline = SanitizeDetailOutline(self.db.FontOutline)

    -- Re-apply font each call so the size slider is live.
    KE:ApplyFont(detail.enchantText, fontFace, fontSize, fontOutline)
    KE:ApplyFont(detail.ilvlText, fontFace, fontSize, fontOutline)

    -- Enchant label (green). "No Enchant" stays with the warning feature.
    if self.db.ShowEnchantNames then
        local label = self:ResolveEnchantLabel(unit, slotID)
        detail.enchantText:SetText(label or "")
        detail.enchantText:SetShown(label ~= nil)
    else
        detail.enchantText:SetText("")
        detail.enchantText:Hide()
    end

    -- Item level, colored by the equipped item's quality.
    if self.db.ShowSlotItemLevel then
        local lvl = self:GetSlotItemLevel(unit, slotID)
        if lvl then
            local quality = GetInventoryItemQuality(unit, slotID)
            if quality then
                local hex = select(4, C_Item.GetItemQualityColor(quality))
                detail.ilvlText:SetText("|c" .. hex .. lvl .. "|r")
            else
                detail.ilvlText:SetText(tostring(lvl))
            end
            detail.ilvlText:Show()
        else
            detail.ilvlText:SetText("")
            detail.ilvlText:Hide()
        end
    else
        detail.ilvlText:SetText("")
        detail.ilvlText:Hide()
    end

    -- Gem icons inline beside the ilvl text (only scan socketable slots).
    -- Filled sockets show their gem (ShowSlotGems); empty sockets show a RED
    -- empty-socket icon (ShowMissingGems) — the reference-style missing-gem cue
    -- that replaces the old "No Gem" text (no room to stack a third text line).
    local gemCount = 0
    local showFilled = self.db.ShowSlotGems
    local showEmpty  = self.db.ShowMissingGems ~= false
    if (showFilled or showEmpty) and socketableSlotSet[slotID] then
        local result = self:ScanItemSockets(unit, slotID)
        if result and result.sockets then
            local iconSize = SLOT_GEM_ICON_SIZE
            for _, socket in ipairs(result.sockets) do
                if gemCount >= SLOT_DETAIL_MAX_GEMS then break end
                if (socket.filled and showFilled) or (not socket.filled and showEmpty) then
                    gemCount = gemCount + 1
                    local iconFrame = detail.gemIcons[gemCount]
                    iconFrame:SetSize(iconSize, iconSize)
                    iconFrame.tex:SetTexture(socket.icon or 458977)
                    if socket.filled then
                        iconFrame.tex:SetVertexColor(1, 1, 1)
                        iconFrame:SetAlpha(1)
                    else
                        iconFrame.tex:SetVertexColor(1, 0, 0)  -- missing gem
                        iconFrame:SetAlpha(1)
                    end
                    iconFrame:Show()
                end
            end
        end
    end
    for i = gemCount + 1, SLOT_DETAIL_MAX_GEMS do
        detail.gemIcons[i]:Hide()
    end

    -- Transparent container — element visibility controls what's drawn.
    detail:Show()
end

-- Event-driven single-slot refresh. Resolves the slot frame from the slotID,
-- builds the slot lookup map on first use, and runs each enabled update for
-- the affected slot only — avoids the 17-slot iteration that
-- UpdateAllSlotDetails / UpdateAllTrackIndicators do on a full refresh.
-- Each downstream Update* function performs its own dirty-check guard
-- (added in Tasks 8-10), so calling RefreshSlot for an unchanged slot is
-- effectively free.
function CP:RefreshSlot(slotID, unit)
    if not slotID then return end
    BuildSlotFramesByID()
    local slotFrame = SLOT_FRAMES_BY_ID[slotID]
    if not slotFrame then return end
    unit = unit or "player"

    -- Warning text lives on the slot BUTTON, not on the SLOT frame; resolve
    -- via allCheckSlots which maps slotID -> button name.
    local buttonName = allCheckSlots[slotID]
    local button = buttonName and _G[buttonName]
    if button then
        UpdateSlotWarning(button, unit, slotID)
    end

    if self.db.TrackIndicatorsEnabled then
        self:UpdateSlotTrackIndicator(slotFrame, slotID, unit)
    end

    if self.db.ShowSlotItemLevel or self.db.ShowEnchantNames
       or self.db.ShowSlotGems or self.db.ShowMissingGems then
        self:UpdateSlotDetail(slotFrame, slotID, unit)
    end
end

function CP:UpdateAllSlotDetails()
    if not (self.db.ShowSlotItemLevel or self.db.ShowEnchantNames or self.db.ShowSlotGems or self.db.ShowMissingGems) then
        self:HideAllSlotDetails()
        return
    end
    for slotID, frameName in pairs(SLOT_FRAMES) do
        self:UpdateSlotDetail(_G[frameName], slotID, "player")
    end
end

function CP:HideAllSlotDetails()
    for _, frameName in pairs(SLOT_FRAMES) do
        local slotFrame = _G[frameName]
        local detail = slotFrame and FFD[slotFrame] and FFD[slotFrame].detail
        if detail then detail:Hide() end
    end
    for _, frameName in pairs(INSPECT_SLOT_FRAMES) do
        local slotFrame = _G[frameName]
        local detail = slotFrame and FFD[slotFrame] and FFD[slotFrame].detail
        if detail then detail:Hide() end
    end
    if self._inspectIlvl then self._inspectIlvl:Hide() end
end

---------------------------------------------------------------------------------
-- Gem Socket Helper
---------------------------------------------------------------------------------

-- File-locals: scan tooltip + caches
local gemCache = {}
local socketCache = {}

-- Helper constants
local TITLE_HEIGHT      = 24
local HOVER_DURATION    = 0.12
local ITEM_ROW_PADDING  = 4
local POPUP_PADDING     = 2
local POPUP_ICON_SIZE   = 24
local STANDARD_BACKDROP = { bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 }

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

function CP:ScanItemSockets(unit, slotID)
    unit = unit or "player"
    local itemLink = GetInventoryItemLink(unit, slotID)
    if not itemLink then return nil end

    -- Read the structured tooltip rather than C_Item.GetItemGem. GetItemGem fails to
    -- resolve gems across the inspect boundary (returns nil even for socketed gear,
    -- showing false "missing" reds), whereas C_TooltipInfo reflects what's actually
    -- rendered. Socket lines come back in physical order, so the running counter IS
    -- each socket's true index for both filled and empty — no position reconciliation
    -- needed. (Reference: BetterCharacterPanel.)
    local data = C_TooltipInfo.GetInventoryItem(unit, slotID)
    if not data or not data.lines then return nil end

    if DEBUG_CP and unit ~= "player" and socketableSlotSet[slotID] then
        self._cpDbg = self._cpDbg or {}
        local key = unit .. ":" .. slotID
        if not self._cpDbg[key] then
            self._cpDbg[key] = true
            local itemID = itemLink:match("|Hitem:(%d+)") or "?"
            KE:Print(string.format("[CP] inspect slot %d item %s, %d lines", slotID, itemID, #data.lines))
            for i = 1, 3 do
                local n, l = C_Item.GetItemGem(itemLink, i)
                KE:Print(string.format("[CP]   GetItemGem(%d)=%s / %s", i, tostring(n), tostring(l)))
            end
            for i, line in ipairs(data.lines) do
                if line.type == SOCKET_LINE_TYPE or line.gemIcon ~= nil or line.socketType ~= nil then
                    KE:Print(string.format("[CP]   L%d type=%s gemIcon=%s socketType=%s txt=%s",
                        i, tostring(line.type), tostring(line.gemIcon), tostring(line.socketType),
                        tostring(line.leftText)))
                end
            end
        end
    end

    local result = {
        slotID = slotID,
        itemLink = itemLink,
        sockets = {},
        totalCount = 0, filledCount = 0, emptyCount = 0,
    }

    local socketIndex = 0
    for _, line in ipairs(data.lines) do
        if line.type == SOCKET_LINE_TYPE then
            socketIndex = socketIndex + 1
            result.totalCount = result.totalCount + 1
            if line.gemIcon then
                -- Filled. line.gemIcon is the gem's icon (works on inspect). Enrich
                -- with GetItemGem for the link/id the player-only socket helper needs;
                -- nil on inspect is harmless since inspect only displays the icon.
                result.filledCount = result.filledCount + 1
                local gemName, gemLink = C_Item.GetItemGem(itemLink, socketIndex)
                local gemID = gemLink and C_Item.GetItemInfoInstant(gemLink)
                table.insert(result.sockets, {
                    index = socketIndex, filled = true,
                    gemLink = gemLink, gemName = gemName, gemID = gemID,
                    icon = line.gemIcon,
                })
            else
                -- Empty. line.socketType is the type string (e.g. "Prismatic").
                result.emptyCount = result.emptyCount + 1
                local socketType = line.socketType
                table.insert(result.sockets, {
                    index = socketIndex, filled = false,
                    socketType = socketType,
                    icon = (socketType and EMPTY_SOCKET_ICON[socketType]) or 458977,
                })
            end
        end
    end

    -- Task 0 trace: log when an inspected socketable slot's filled count CHANGES
    -- (the red->gem flip), with a timestamp, so it can be correlated against the
    -- event log in SetupInspectSupport to learn which event drove the resolution.
    if DEBUG_CP and unit ~= "player" and socketableSlotSet[slotID] then
        CP._cpDbgFilled = CP._cpDbgFilled or {}
        local prev = CP._cpDbgFilled[slotID]
        if prev ~= result.filledCount then
            KE:Print(string.format("[CP] FLIP slot %d filled %s->%d empty %d t=%.2f",
                slotID, tostring(prev), result.filledCount, result.emptyCount, GetTime()))
            CP._cpDbgFilled[slotID] = result.filledCount
        end
    end

    return result.totalCount > 0 and result or nil
end

function CP:ScanAllEquippedSockets()
    wipe(socketCache)
    for _, slotID in ipairs(socketableSlots) do
        local socketInfo = self:ScanItemSockets("player", slotID)
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
    container:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 3, -5)
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

    -- KitnEssentials now covers BetterCharacterPanel's feature set across the
    -- player and inspect frames, so leaving both enabled double-renders. Disable
    -- BCP per-character; the disable persists, so after the user /reloads,
    -- IsAddOnLoaded stays false and this path is silent on later logins.
    if C_AddOns.IsAddOnLoaded("BetterCharacterPanel") then
        C_AddOns.DisableAddOn("BetterCharacterPanel")
        KE:Print("BetterCharacterPanel disabled — all of its features and then some are now in KitnEssentials. |cffffff00/reload|r to apply.")
    end

    HookCharacterPanel()
    self:SetupInspectSupport()

    -- Race: if the character pane is already shown when the module enables
    -- (e.g. user toggled the module on with the pane open), the PaperDollFrame
    -- OnShow hook installed above won't fire on this path. Register events +
    -- force one refresh inline.
    if PaperDollFrame and PaperDollFrame:IsShown() then
        if self.eventFrame then
            self.eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
            self.eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
        end
        UpdateDisplay()                                   -- warnings
        if self.db.TrackIndicatorsEnabled then self:UpdateAllTrackIndicators() end
        if self.db.ShowSlotItemLevel or self.db.ShowEnchantNames or self.db.ShowSlotGems or self.db.ShowMissingGems then
            self:UpdateAllSlotDetails()
        end
    end

    self:ApplySettings()
end

function CP:OnDisable()
    self:ClearAll()                                       -- warnings clear
    if self.eventFrame then self.eventFrame:UnregisterAllEvents() end
    self:DisableGemSocketHelper()
    self:HideAllTrackIndicators()
    self:HideAllSlotDetails()
    self:HideRaceText()
    RestoreCharacterBackground()
    updatePending = false
    inspectUpdatePending = false
    if self._inspectQueue then wipe(self._inspectQueue) end
end

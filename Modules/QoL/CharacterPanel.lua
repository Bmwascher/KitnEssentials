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

-- Gem socket types for socket helper scanning. Canonical list lives on KE
-- (Core/Globals.lua) because the Character window skin needs the same one.
local GEM_SOCKET_TYPES = KE.GEM_SOCKET_TYPES

-- Empty-socket fallback icon keyed by C_TooltipInfo's line.socketType string.
local EMPTY_SOCKET_ICON = {}
for _, t in ipairs(GEM_SOCKET_TYPES) do EMPTY_SOCKET_ICON[t.name] = t.icon end

-- C_TooltipInfo gem-socket line type (3); resolved from Enum with a literal fallback.
local SOCKET_LINE_TYPE = (Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.GemSocket) or 3

-- Socket-scan tracing. Flip true, /reload, then either inspect a target with
-- gemmed gear (dumps, once per unit+slot, every C_TooltipInfo line that looks
-- gem-related plus what C_Item.GetItemGem returns) or open the character panel
-- on a cold item cache (logs QueueGemLoad requests + ITEM_DATA_LOAD_RESULT
-- repaints for the player gem-hydration path). Leave false in shipped code.
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
-- Memoized by raw effect name: the pipeline runs ~76 gsubs per label and the
-- same handful of equipped enchant names re-resolve on every slot render
-- (including inspect gem-race retries). Pure function of the input and the
-- load-time constant tables above, so entries never invalidate.
local _enchantLabelCache = {}
local function ProcessEnchantText(text)
    local cached = _enchantLabelCache[text]
    if cached then return cached end
    local raw = text
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
    _enchantLabelCache[raw] = text
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
-- FFD: weak-keyed per-frame state.
-- Stores overlay frames + caches that previously lived as direct fields on
-- Blizzard slot buttons (._slotWarning, ._slotDetail, ._trackOverlay). Weak
-- keys auto-GC when the Blizz frame is destroyed; using an external table
-- reduces 12.0 taint surface for the future inspect module port.
--
-- Declared AFTER SLOT_FRAMES / allCheckSlots so BuildSlotFramesByID's
-- reference to SLOT_FRAMES binds to the upvalue (not the nil global). Lua
-- parses functions lazily but resolves locals at definition time — placing
-- these helpers before the SLOT_FRAMES declaration would make SLOT_FRAMES a
-- free global reference and BuildSlotFramesByID would fault on first call.
---------------------------------------------------------------------------------
local FFD = setmetatable({}, { __mode = "k" })
function CP:GetFFD(frame)
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

---------------------------------------------------------------------------------
-- Cold-cache gem hydration (player path).
-- A client patch wipes the local item cache; at the first logins after it the
-- GEM items socketed into equipped gear aren't loaded yet, so the tooltip's
-- socket lines come back with gemIcon == nil on FILLED sockets (gem icons
-- require item-sparse data — see Blizzard's PaperDollItemSocketDisplayMixin:
-- SetItem, which documents that even C_Item.GetItemGem can't resolve then).
-- The equipped item LINK still carries the gem IDs, so C_Item.GetItemGemID is
-- the uncached-safe filled-vs-empty truth. Unresolved icons are requested via
-- RequestLoadItemDataByID and the slot repaints on ITEM_DATA_LOAD_RESULT —
-- the same event chain InspectPanel's gem-race fix uses on the inspect side.
---------------------------------------------------------------------------------
local _pendingGemLoads = {}   -- [itemID] = { [slotID] = true }
local _gemLoadAttempts = {}   -- [itemID] = request count (loop cap, mirrors InspectPanel's paint passes)
local MAX_GEM_LOAD_ATTEMPTS = 5

local function QueueGemLoad(itemID, slotID)
    if not itemID then return end
    local attempts = _gemLoadAttempts[itemID] or 0
    if attempts >= MAX_GEM_LOAD_ATTEMPTS then return end
    local slots = _pendingGemLoads[itemID]
    if not slots then slots = {}; _pendingGemLoads[itemID] = slots end
    if slots[slotID] then return end
    slots[slotID] = true
    _gemLoadAttempts[itemID] = attempts + 1
    if DEBUG_CP then
        KE:Print(string.format("[CP] queue item load %d for slot %d (attempt %d)",
            itemID, slotID, attempts + 1))
    end
    C_Item.RequestLoadItemDataByID(itemID)
end

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
---@param itemLink string?
local function HasEnchant(itemLink)
    if not itemLink then return false end
    local itemString = itemLink:match("item[%-?%d:]+")
    if not itemString then return false end
    local _, _, enchantId = strsplit(":", itemString)
    return enchantId and enchantId ~= "" and enchantId ~= "0"
end

-- Enchant ID from the item link (locale-independent; same field HasEnchant reads).
function CP:GetSlotEnchantID(unit, slot)
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
-- data (optional): pre-fetched C_TooltipInfo.GetInventoryItem(unit, slot) table
-- shared by the caller's render pass — each fetch allocates a fresh table, so
-- the render paths thread ONE read through enchant/track/gem consumers.
local function GetSlotEnchantName(unit, slot, data)
    unit = unit or "player"
    data = data or C_TooltipInfo.GetInventoryItem(unit, slot)
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

function CP:ResolveEnchantLabel(unit, slot, data)
    unit = unit or "player"
    -- Enchant-ID check is the locale-robust "is it enchanted?" gate; the readable
    -- label comes from the tooltip + ProcessEnchantText.
    if not self:GetSlotEnchantID(unit, slot) then return nil end
    local name = GetSlotEnchantName(unit, slot, data)
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
function CP:UpdateSlotWarning(button, unit, slot)
    if not button then return end
    unit = unit or "player"

    -- EllesmereUI flags a missing enchant itself, in exactly the place this text
    -- goes (its enchant label anchors to the same slot edge). Stand down only
    -- when it is ACTUALLY drawing that cue on THIS frame -- on inspect the cue
    -- is an icon that its own inspectShowEnchants toggle can switch off, and
    -- then nothing would mark the slot at all. Ahead of the dirty-check store
    -- below, so a handback redraws instead of short-circuiting on a key cached
    -- while EUI owned the slot.
    if KE:EUIDrawsSlotElement(unit, "missingEnchant") then
        local d = FFD[button]
        if d and d.warning then d.warning:SetText("") end
        return
    end

    -- Dirty-check: itemLink + enchantID determine the warning. If neither
    -- changed since last render, skip the work. Cached only for the player
    -- slot path (inspect path goes through different functions); inspect's
    -- own dirty caching is part of the future inspect module spec.
    if unit == "player" then
        local s = _slotState(slot)
        local link = GetInventoryItemLink(unit, slot)
        local enchantID = self:GetSlotEnchantID(unit, slot)
        if s.warnLink == link and s.warnEnchant == enchantID then
            return
        end
        s.warnLink, s.warnEnchant = link, enchantID
    end

    local db = CP.db
    local enchantEnabled = db and db.ShowEnchants ~= false

    local ffd = self:GetFFD(button)
    if not ffd.warning then
        ffd.warning = CreateSlotText(button, slot)
    end

    -- Enchant warning only. A missing GEM is shown as a red empty-socket icon in
    -- the gem row (see UpdateSlotDetail), reference-style, to avoid a third text
    -- line the short slots can't fit.
    -- UnitLevel on inspect targets (hostile/encounter units) can be secret in 12.0;
    -- treat secret as "not max level" so we don't accuse an inspect target of
    -- missing enchants when the level is unreadable.
    local noEnchant = false
    local level = UnitLevel(unit)
    if level and not (issecretvalue and issecretvalue(level))
        and IsLevelAtEffectiveMaxLevel(level) then
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
            CP:UpdateSlotWarning(button, "player", slot)
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

-- Debounced socket-helper refresh — same trailing pattern as QueueUpdate.
-- ScanAllEquippedSockets has no dirty-check (the row is rebuilt from live
-- socket state), so un-collapsed event bursts (looting, procs, gem swaps)
-- each re-scanned all 11 socketable slots; this folds a burst into one scan.
local socketRefreshPending = false
local function QueueSocketRefresh()
    if socketRefreshPending then return end
    if not (PaperDollFrame and PaperDollFrame:IsShown()) then return end
    socketRefreshPending = true
    C_Timer.After(UPDATE_DEBOUNCE, function()
        socketRefreshPending = false
        if CP.db and CP.db.Enabled and CP.db.SocketHelperEnabled
            and PaperDollFrame and PaperDollFrame:IsShown() then
            CP:RefreshSocketButtons()
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
                CP.eventFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
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
                CP.eventFrame:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
            end
            -- In-flight gem loads lose their listener with the pane; drop the
            -- mapping. The slot's detailGemsPending dirty-state survives, so a
            -- reopen re-scans and re-queues anything still unresolved. The
            -- attempt counters reset too — each pane session gets a fresh
            -- retry budget, so a gem that exhausted its cap (flaky load) can
            -- recover on the next open instead of being starved all session.
            wipe(_pendingGemLoads)
            wipe(_gemLoadAttempts)
            if CP.socketContainer then CP.socketContainer:Hide() end
            CP:HideGemPopup()
            CP:HideEnchantPopup()
            CP:HideSlotHighlight()
        end)
    end

    -- Persistent event frame, but events are now registered conditionally
    -- (above) on PaperDollFrame Show/Hide. The frame itself is cheap; what
    -- mattered was the dispatch overhead from always-listening.
    CP.eventFrame = CreateFrame("Frame")
    CP.eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
        if not CP.db.Enabled then return end
        if event == "PLAYER_EQUIPMENT_CHANGED" then
            -- Route by slotID (arg1) so we update one slot's overlays, not all
            -- 17. The keyed-queue / debounce paths (QueueUpdate, socket helper)
            -- still operate panel-wide because they aggregate cross-slot
            -- state (warning visibility, socket-button row).
            QueueUpdate()                                 -- warnings (debounced, panel-wide)
            if CP.db.SocketHelperEnabled then QueueSocketRefresh() end
            if arg1 then
                CP:RefreshSlot(arg1, "player")            -- detail + track for the affected slot only
            end
        elseif event == "ITEM_DATA_LOAD_RESULT" then
            -- A gem/base item we requested (QueueGemLoad) finished loading;
            -- repaint the slots that were waiting on it. Clearing the slot's
            -- dirty state first is required — link/enchant/ilvl haven't
            -- changed, so RefreshSlot would otherwise short-circuit on the
            -- stale cold-cache render.
            local slots = _pendingGemLoads[arg1]
            if slots then
                _pendingGemLoads[arg1] = nil
                if DEBUG_CP then
                    KE:Print(string.format("[CP] item %s loaded (success=%s)", tostring(arg1), tostring(arg2)))
                end
                -- arg2 == false: the load failed (invalid/refused item) — nothing
                -- changed, so repainting would only re-scan, re-queue, and burn
                -- an attempt. The next natural re-scan (gear/bag event, reopen)
                -- re-queues, bounded by the attempt cap.
                if arg2 ~= false then
                    for pendingSlotID in pairs(slots) do
                        _lastSlotState[pendingSlotID] = nil
                        CP:RefreshSlot(pendingSlotID, "player")
                    end
                    if CP.db.SocketHelperEnabled then QueueSocketRefresh() end
                end
            end
        elseif event == "BAG_UPDATE_DELAYED" then
            -- Socketing a gem / applying an enchant consumes the item from bags
            -- and fires this rather than PLAYER_EQUIPMENT_CHANGED, so refresh the
            -- missing-enchant/gem warnings here too (debounced + panel-gated).
            QueueUpdate()
            if CP.socketContainer and CP.socketContainer:IsShown() then
                QueueSocketRefresh()
            end
            if CP.db.ShowSlotItemLevel or CP.db.ShowEnchantNames or CP.db.ShowSlotGems or CP.db.ShowMissingGems then
                CP:UpdateAllSlotDetails()
            end
        end
    end)

    hooked = true
end

function CP:Refresh()
    -- Cached slot state may be stale relative to new settings (font size,
    -- track letter size, etc.). Force a re-render by clearing the dirty cache.
    wipe(_lastSlotState)

    self.db = KE.db.profile.CharacterPanel
    HookCharacterPanel()
    -- Inspect setup is owned by InspectPanel module (cascaded from CP:OnEnable);
    -- SetupInspectSupport is idempotent so any prior call still holds.
    ApplyFontToAll()                                      -- warning fonts
    if self.db.Enabled then
        self:ApplySettings()
        if CharacterFrame and CharacterFrame:IsShown() then UpdateDisplay() end
    end
end

function CP:ApplySettings()
    wipe(_lastSlotState)

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
function CP:GetItemTrack(unit, slotID, data)
    unit = unit or "player"
    data = data or C_TooltipInfo.GetInventoryItem(unit, slotID)
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
    local ffd = self:GetFFD(slotFrame)
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

function CP:UpdateSlotTrackIndicator(slotFrame, slotID, unit, data)
    unit = unit or "player"
    if not slotFrame then return end

    -- EllesmereUI prints the upgrade track beside its own item level ("(Myth)"),
    -- so our corner letter is the same fact twice. It does not overlap theirs,
    -- but two readings of one thing on every slot is clutter -- Brandon's call,
    -- 2026-08-03. Only while EUI is actually drawing it on THIS frame: its
    -- showUpgradeTrack / inspectShowUpgradeTrack toggles turn it off separately,
    -- and then ours is the only one left. Bail before the tooltip read too --
    -- GetItemTrack allocates one per slot just to decide the letter.
    if KE:EUIDrawsSlotElement(unit, "track") then
        local d = FFD[slotFrame]
        if d and d.track then d.track:Hide() end
        return
    end

    -- One tooltip read serves both the dirty-check and the render below (the
    -- render previously re-fetched identical data a second time).
    local track = self:GetItemTrack(unit, slotID, data)

    -- Dirty-check (player path only): itemLink + track letter determine the
    -- rendered output. Skip the font re-apply + SetText when unchanged.
    if unit == "player" then
        local s = _slotState(slotID)
        local link = GetInventoryItemLink(unit, slotID)
        local key = track and track.letter or nil
        if s.trackLink == link and s.trackKey == key then return end
        s.trackLink, s.trackKey = link, key
    end

    local overlay = self:CreateTrackOverlay(slotFrame, slotID)

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

-- Lazy quality→hex cache: C_Item.GetItemQualityColor returns constants, so
-- resolve each quality once instead of a C call + select() per slot render.
local QUALITY_HEX = {}
local function GetQualityHex(quality)
    local hex = QUALITY_HEX[quality]
    if not hex then
        hex = select(4, C_Item.GetItemQualityColor(quality))
        QUALITY_HEX[quality] = hex
    end
    return hex
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
    local ffd = self:GetFFD(slotFrame)
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

-- suppressGems (optional): when true, skip the gem-icon scan + render and hide
-- all icon slots. Used by InspectPanel's paint-pass retry to avoid flashing red
-- "empty socket" cues while the inspect packet's gem data is still resolving.
-- data (optional): pre-fetched C_TooltipInfo.GetInventoryItem table from the
-- caller's render pass (RefreshSlot / RenderInspectSlot) — threaded down to the
-- enchant label + gem scan so one read serves the whole slot render.
function CP:UpdateSlotDetail(slotFrame, slotID, unit, suppressGems, data)
    unit = unit or "player"
    if not slotFrame then return end

    -- EllesmereUI ownership, resolved FIRST -- ahead of the dirty-check store.
    -- Asked per ELEMENT and per FRAME, never as one blanket "is EUI on": EUI has
    -- an independent live toggle for each of these, so a single test would delete
    -- an element from both addons the moment the user turned EUI's copy off.
    -- Its inspect sheet also draws no gems at any setting, which is why the gem
    -- row survives there.
    local euiOwnsEnchant = KE:EUIDrawsSlotElement(unit, "enchant")
    local euiOwnsIlvl    = KE:EUIDrawsSlotElement(unit, "ilvl")
    local euiOwnsGems    = KE:EUIDrawsSlotElement(unit, "gems")

    -- Nothing left for us to draw on this frame: bail before BOTH the dirty-check
    -- store and the tooltip read. Order matters -- storing the link/enchant/ilvl
    -- key while standing down would make a later handback short-circuit against a
    -- key recorded when EUI owned the slot, and the display would stay blank
    -- until the item itself changed. FFD is indexed directly so a slot that never
    -- had a detail frame does not get one built just to hide it.
    --
    -- A handback lands on the next refresh -- an equipment change or a panel
    -- reopen -- not on the same frame the user flips EUI's setting: nothing
    -- notifies KE of a write to EUI's saved variables. On the inspect side
    -- InspectPanel's own per-GUID cache gates ahead of this function too, and it
    -- is wiped when the inspect frame hides, so a reopen is the reliable trigger.
    local wantsText = (self.db.ShowEnchantNames and not euiOwnsEnchant)
        or (self.db.ShowSlotItemLevel and not euiOwnsIlvl)
    local wantsGems = (self.db.ShowSlotGems or self.db.ShowMissingGems ~= false)
        and not euiOwnsGems and not suppressGems
    if not (wantsText or wantsGems) then
        local existing = FFD[slotFrame]
        if existing and existing.detail then existing.detail:Hide() end
        return
    end

    -- Dirty-check (player path only): itemLink + enchantID + ilvl determine
    -- the rendered output. If all three match the previous render, skip the
    -- font re-apply + SetText + gem-icon work entirely. Inspect path goes
    -- unguarded here — its own invalidation lives in INSPECT_READY.
    if unit == "player" then
        local s = _slotState(slotID)
        local link = GetInventoryItemLink(unit, slotID)
        local enchantID = self:GetSlotEnchantID(unit, slotID)
        local ilvl = self:GetSlotItemLevel(unit, slotID)
        -- detailGemsPending: the previous render ran on unhydrated gem data
        -- (cold item cache), so the link/enchant/ilvl key is NOT sufficient —
        -- skip the short-circuit and re-scan until the gems resolve.
        if s.detailLink == link and s.detailEnchant == enchantID and s.detailIlvl == ilvl
            and not s.detailGemsPending then
            return
        end
        s.detailLink, s.detailEnchant, s.detailIlvl = link, enchantID, ilvl
    end

    -- Fetch after the dirty check so a short-circuited call allocates nothing;
    -- both tooltip consumers below (enchant label, gem scan) share this read.
    data = data or C_TooltipInfo.GetInventoryItem(unit, slotID)

    local detail = self:CreateSlotDetail(slotFrame, slotID)
    local fontFace    = self.db.FontFace or "Expressway"
    local fontSize    = self.db.SlotInfoFontSize or 11
    local fontOutline = SanitizeDetailOutline(self.db.FontOutline)

    -- Re-apply font each call so the size slider is live.
    KE:ApplyFont(detail.enchantText, fontFace, fontSize, fontOutline)
    KE:ApplyFont(detail.ilvlText, fontFace, fontSize, fontOutline)

    -- Enchant label (green). "No Enchant" stays with the warning feature.
    if self.db.ShowEnchantNames and not euiOwnsEnchant then
        local label = self:ResolveEnchantLabel(unit, slotID, data)
        detail.enchantText:SetText(label or "")
        detail.enchantText:SetShown(label ~= nil)
    else
        detail.enchantText:SetText("")
        detail.enchantText:Hide()
    end

    -- Item level, colored by the equipped item's quality.
    if self.db.ShowSlotItemLevel and not euiOwnsIlvl then
        local lvl = self:GetSlotItemLevel(unit, slotID)
        if lvl then
            local quality = GetInventoryItemQuality(unit, slotID)
            if quality then
                local hex = GetQualityHex(quality)
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
    local gemsPending = false
    if not suppressGems then
        local showFilled = self.db.ShowSlotGems and not euiOwnsGems
        local showEmpty  = self.db.ShowMissingGems ~= false and not euiOwnsGems
        if (showFilled or showEmpty) and socketableSlotSet[slotID] then
            local result = self:ScanItemSockets(unit, slotID, data)
            gemsPending = (result and result.pendingGems) or false
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
    end
    -- When suppressGems is true, gemCount is 0 so ALL icon slots get hidden
    -- (clean transparent state until the retry resolves the inspect packet).
    for i = gemCount + 1, SLOT_DETAIL_MAX_GEMS do
        detail.gemIcons[i]:Hide()
    end

    if unit == "player" then
        _slotState(slotID).detailGemsPending = gemsPending or nil
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
        self:UpdateSlotWarning(button, unit, slotID)
    end

    -- One tooltip read shared by the track + detail renders below (each used
    -- to fetch its own copy of identical same-frame data). RefreshSlot's
    -- callers fire on actual slot changes, so the dirty checks downstream
    -- rarely short-circuit — prefetching here doesn't waste the read.
    -- Mirrors the stand-down rules in the two Update* functions below, purely so
    -- the shared tooltip read is skipped when neither will draw. Getting this
    -- wrong costs an allocation, never correctness -- each function re-checks.
    local wantsTrack  = self.db.TrackIndicatorsEnabled
        and not KE:EUIDrawsSlotElement(unit, "track")
    local wantsDetail =
        (self.db.ShowSlotItemLevel and not KE:EUIDrawsSlotElement(unit, "ilvl"))
        or (self.db.ShowEnchantNames and not KE:EUIDrawsSlotElement(unit, "enchant"))
        or ((self.db.ShowSlotGems or self.db.ShowMissingGems ~= false)
            and not KE:EUIDrawsSlotElement(unit, "gems"))
    local data
    if wantsTrack or wantsDetail then
        data = C_TooltipInfo.GetInventoryItem(unit, slotID)
    end

    if wantsTrack then
        self:UpdateSlotTrackIndicator(slotFrame, slotID, unit, data)
    end

    if wantsDetail then
        self:UpdateSlotDetail(slotFrame, slotID, unit, nil, data)
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
    -- Inspect ilvl FontString lives on InspectPanel; cleanup happens via
    -- InspectPanel:HideAllInspectOverlays (called from InspectPanel:OnDisable
    -- cascaded by CP:OnDisable).
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

-- Covers BOTH popups on the bar: leaving the gem popup to cross onto the
-- enchant button (or the reverse) must not count as leaving the UI, or the
-- 0.05s close timer fires mid-move and the popup you were heading for shuts.
local function IsMouseOverGemUI()
    if CP.gemPopup and CP.gemPopup:IsMouseOver() then return true end
    if CP.gemPopup then
        for _, btn in pairs(CP.gemPopup.buttons) do
            if btn:IsShown() and btn:IsMouseOver() then return true end
        end
    end
    if CP.enchantPopup and CP.enchantPopup:IsMouseOver() then return true end
    if CP.enchantPopup then
        for _, btn in pairs(CP.enchantPopup.buttons) do
            if btn:IsShown() and btn:IsMouseOver() then return true end
        end
    end
    if CP.enchantButton and CP.enchantButton:IsShown()
        and CP.enchantButton:IsMouseOver() then return true end
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

-- data (optional): pre-fetched C_TooltipInfo.GetInventoryItem table shared by
-- the caller's render pass (UpdateSlotDetail / RenderInspectSlot).
function CP:ScanItemSockets(unit, slotID, data)
    unit = unit or "player"
    local itemLink = GetInventoryItemLink(unit, slotID)
    if not itemLink then return nil end

    -- Read the structured tooltip rather than C_Item.GetItemGem. GetItemGem fails to
    -- resolve gems across the inspect boundary (returns nil even for socketed gear,
    -- showing false "missing" reds), whereas C_TooltipInfo reflects what's actually
    -- rendered. Socket lines come back in physical order, so the running counter IS
    -- each socket's true index for both filled and empty — no position reconciliation
    -- needed. (Reference: BetterCharacterPanel.)
    data = data or C_TooltipInfo.GetInventoryItem(unit, slotID)
    local lines = data and data.lines
    if not lines then
        -- Inspect: no tooltip data means nothing to show. Player: fall through
        -- with zero socket lines so the cold-cache fallback below can still
        -- synthesize filled sockets from the link's gem IDs.
        if unit ~= "player" then return nil end
        lines = {}
    end

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
    for _, line in ipairs(lines) do
        if line.type == SOCKET_LINE_TYPE then
            socketIndex = socketIndex + 1
            result.totalCount = result.totalCount + 1
            -- line.gemIcon is also nil for a FILLED socket whose gem item isn't
            -- in the local item cache yet (cold cache at the first logins after
            -- a client patch). The gem ID is embedded in the equipped item's
            -- link, so GetItemGemID resolves without the gem's data (Blizzard
            -- PaperDollFrame pattern). Player-only: inspect links go through
            -- InspectPanel's own gem-race handling.
            local coldGemID
            if not line.gemIcon and unit == "player" then
                coldGemID = C_Item.GetItemGemID(itemLink, socketIndex)
            end
            if line.gemIcon or coldGemID then
                -- Filled. line.gemIcon is the gem's icon (works on inspect). Enrich
                -- with GetItemGem for the link/id the player-only socket helper needs;
                -- nil on inspect is harmless since inspect only displays the icon.
                result.filledCount = result.filledCount + 1
                local gemName, gemLink = C_Item.GetItemGem(itemLink, socketIndex)
                local gemID = (gemLink and C_Item.GetItemInfoInstant(gemLink)) or coldGemID
                local icon = line.gemIcon
                if coldGemID then
                    icon = C_Item.GetItemIconByID(coldGemID)
                    -- Gem data still hydrating. The icon can resolve from static
                    -- data while sparse (link/name — the quality border + hover
                    -- tooltip in the socket helper) lags, or neither resolves.
                    -- Queue the load in both cases so the slot repaints fully
                    -- cached on ITEM_DATA_LOAD_RESULT.
                    if not icon or not gemLink then
                        QueueGemLoad(coldGemID, slotID)
                        result.pendingGems = true
                    end
                end
                table.insert(result.sockets, {
                    index = socketIndex, filled = true,
                    gemLink = gemLink, gemName = gemName, gemID = gemID,
                    icon = icon,
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

    -- Cold-cache fallback (player): the tooltip carried NO socket lines AND the
    -- BASE item's data isn't cached — the real socket layout is unknowable, so
    -- if the link says gems are socketed, synthesize the filled sockets and
    -- request the base item; the slot repaints with the full layout (including
    -- empty sockets) on ITEM_DATA_LOAD_RESULT. The IsItemDataCachedByID gate
    -- keeps the warm path free of the GetItemGemID probes: a cached base item
    -- with zero socket lines genuinely has no sockets.
    if unit == "player" and result.totalCount == 0 then
        local baseID = GetItemInfoInstant(itemLink)
        if baseID and not C_Item.IsItemDataCachedByID(baseID) then
            for i = 1, SLOT_DETAIL_MAX_GEMS do
                local gemID = C_Item.GetItemGemID(itemLink, i)
                if gemID then
                    result.totalCount = result.totalCount + 1
                    result.filledCount = result.filledCount + 1
                    local icon = C_Item.GetItemIconByID(gemID)
                    if not icon then QueueGemLoad(gemID, slotID) end
                    table.insert(result.sockets, {
                        index = i, filled = true, gemID = gemID, icon = icon,
                    })
                end
            end
            if result.totalCount > 0 then
                result.pendingGems = true
                QueueGemLoad(baseID, slotID)
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

---------------------------------------------------------------------------------
-- Replace All (Shift-click) — Socket Helper (DSH) replace-all model.
-- Shift-clicking a gem in the popup replaces EVERY equipped socket holding the
-- same gem as the target socket's current gem. Unique-Equipped gems are exempt
-- in both directions: a unique current gem can't have duplicates (flow never
-- offers), and a unique replacement falls back to the single-socket path (the
-- client rejects staging a second copy).
---------------------------------------------------------------------------------

-- Memoized Unique-Equipped check from the gem's own tooltip. English-literal
-- match, same convention as GetItemTrack's "Upgrade Level:"/"Crafted" lines.
-- Only memoizes when tooltip data actually resolved, so a cold-cache read
-- can't latch a wrong "not unique".
local _gemUniqueCache = {}  -- [gemID] = true/false
local function IsGemUnique(gemLink, gemID)
    if not gemLink or not gemID then return false end
    local cached = _gemUniqueCache[gemID]
    if cached ~= nil then return cached end
    local data = C_TooltipInfo.GetHyperlink(gemLink)
    if not (data and data.lines) then return false end
    local unique = false
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if text and text:find("Unique%-Equipped") then
            unique = true
            break
        end
    end
    _gemUniqueCache[gemID] = unique
    return unique
end

-- All equipped sockets currently holding gemID. Fresh scan, slot order — so
-- consecutive sockets on the SAME item are adjacent for the CloseSocketInfo
-- handling in the replace loop.
function CP:GetMatchingGemSockets(gemID)
    local matches = {}
    for _, itemSocketInfo in ipairs(self:ScanAllEquippedSockets()) do
        for _, socket in ipairs(itemSocketInfo.sockets) do
            if socket.filled and socket.gemID == gemID then
                table.insert(matches, {
                    slotID = itemSocketInfo.slotID,
                    socketIndex = socket.index,
                })
            end
        end
    end
    return matches
end

-- One bag position currently holding itemID. Re-resolved per placement —
-- socketing consumes from the stack, so a cached bag/slot goes stale mid-loop.
local function FindGemInBags(itemID)
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            if C_Container.GetContainerItemID(bag, slot) == itemID then
                return bag, slot
            end
        end
    end
    return nil
end

-- The replace loop. Upstream-verified sequencing on 12.0.7 (DSH ships this
-- working): SocketInventoryItem opens the socketing UI for the equipped item;
-- verify it actually opened (GetExistingSocketLink(1)) and that the staged gem
-- landed (GetNewSocketLink) before accepting — one 0.1s-delayed full retry
-- pass if either check fails, since the socket UI can lag the call by a frame.
-- Upstream-documented gotcha: the API cannot stage gems into two sockets of
-- the SAME item in one open — close between consecutive matches on one slotID.
-- Uses the canonical C_ItemSocketInfo namespace (the bare globals DSH calls
-- are Blizzard_DeprecatedItemSocketInfo shims in 12.0.7).
function CP:ReplaceAllMatchingGems(oldGemID, newGemID, isRetry)
    if InCombatLockdown() then
        KE:Print("Cannot socket during combat")
        return
    end
    if not oldGemID or not newGemID or oldGemID == newGemID then return end

    local matches = self:GetMatchingGemSockets(oldGemID)
    if #matches == 0 then return end

    local have = C_Item.GetItemCount(newGemID)
    if have < #matches then
        KE:Print(string.format(
            "Replace All: only %d replacement gem%s for %d sockets - replacing what fits.",
            have, have == 1 and "" or "s", #matches))
    end

    local replaced = 0
    for i, m in ipairs(matches) do
        SocketInventoryItem(m.slotID)
        if not C_ItemSocketInfo.GetExistingSocketLink(1) and not isRetry then
            -- Socket UI wasn't ready; close and re-run the whole pass once.
            -- Already-replaced sockets no longer match oldGemID, so the retry
            -- pass naturally resumes where this one stopped.
            C_Timer.After(0.1, function()
                CloseSocketInfo()
                CP:ReplaceAllMatchingGems(oldGemID, newGemID, true)
            end)
            return
        end

        local existing = C_ItemSocketInfo.GetExistingSocketLink(m.socketIndex)
        local existingID = existing and GetItemInfoInstant(existing)
        if existingID == oldGemID then
            local bag, slot = FindGemInBags(newGemID)
            if not bag then break end  -- out of replacement gems; stop cleanly

            C_Container.PickupContainerItem(bag, slot)
            C_ItemSocketInfo.ClickSocketButton(m.socketIndex)
            ClearCursor()

            local staged = C_ItemSocketInfo.GetNewSocketLink(m.socketIndex)
            local stagedID = staged and GetItemInfoInstant(staged)
            if stagedID ~= newGemID then
                if not isRetry then
                    C_Timer.After(0.1, function()
                        CloseSocketInfo()
                        CP:ReplaceAllMatchingGems(oldGemID, newGemID, true)
                    end)
                    return
                end
                -- Retry pass failed for this socket too; skip it and continue.
            else
                AcceptSockets()
                replaced = replaced + 1
                if matches[i + 1] and matches[i + 1].slotID == m.slotID then
                    CloseSocketInfo()
                end
            end
        end
    end

    CloseSocketInfo()
    if ItemSocketingFrame then HideUIPanel(ItemSocketingFrame) end
    if DEBUG_CP then
        KE:Print(string.format("[CP] Replace All: %d/%d sockets replaced", replaced, #matches))
    end
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
        -- Mirrors the enchant button's own OnEnter, and the reference's
        -- (NorskenUI v6 CharacterPanel.lua:730). Without it, sliding from the
        -- enchant popup onto a socket leaves BOTH popups up: IsMouseOverGemUI
        -- now recognises the socket you just moved onto, so the enchant popup's
        -- 0.05s close timer sees the bar still hovered and bails.
        CP:HideEnchantPopup()
        CP.currentSocketBtn = self
        -- ShowGemPopup ends in UpdateReplaceAllPreview, which sets the slot
        -- glow (single, or multi when Shift is already held) — so no separate
        -- ShowSlotHighlight here; a direct call would clobber the multi-glow.
        CP:ShowGemPopup(self)
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

    -- Replace All footer hint (its own separated row, reference style). Text +
    -- visibility driven by UpdateReplaceAllPreview; the modifier keyword is
    -- colored bright red there so it stands out from the gem rows.
    popup.replaceHint = popup:CreateFontString(nil, "OVERLAY")
    popup.replaceHint:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 6, 6)
    popup.replaceHint:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -6, 6)
    popup.replaceHint:SetJustifyH("LEFT")
    KE:ApplyFontToText(popup.replaceHint, "Expressway", 12, "OUTLINE")
    popup.replaceHint:Hide()

    -- Divider above the footer so it reads as a distinct row, not a trailing
    -- gem line. Spans the full popup width (the ±6 cancels the hint's insets).
    popup.replaceSep = popup:CreateTexture(nil, "ARTWORK")
    popup.replaceSep:SetHeight(1)
    popup.replaceSep:SetPoint("BOTTOMLEFT", popup.replaceHint, "TOPLEFT", -6, 4)
    popup.replaceSep:SetPoint("BOTTOMRIGHT", popup.replaceHint, "TOPRIGHT", 6, 4)
    popup.replaceSep:SetColorTexture(Theme.border[1], Theme.border[2], Theme.border[3], 1)
    popup.replaceSep:Hide()

    -- Live Shift preview (DSH model): listen for modifier changes only while
    -- the popup is shown, so Shift-down glows the affected slots immediately.
    popup:SetScript("OnEvent", function(_, _, key)
        if key == "LSHIFT" or key == "RSHIFT" then
            CP:UpdateReplaceAllPreview()
        end
    end)
    popup:SetScript("OnShow", function(p) p:RegisterEvent("MODIFIER_STATE_CHANGED") end)
    popup:SetScript("OnHide", function(p) p:UnregisterEvent("MODIFIER_STATE_CHANGED") end)

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
        -- Glow via the preview authority so Shift keeps the multi-slot preview
        -- while hovering a candidate row (targetSlotID == the current socket's
        -- slot, so the single-glow case matches the old direct call).
        CP:UpdateReplaceAllPreview()
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
        -- Shift: Replace All — swap every equipped socket holding the target's
        -- current gem for this row's gem. A unique replacement gem falls
        -- through to the normal single-socket path (can't equip duplicates).
        if IsShiftKeyDown() and CP.gemPopup and CP.gemPopup._replaceAllGemID
            and self.gemData and not IsGemUnique(self.gemData.link, self.gemData.itemID) then
            local oldGemID = CP.gemPopup._replaceAllGemID
            CP:HideGemPopup()
            CP:HideSlotHighlight()
            CP:ReplaceAllMatchingGems(oldGemID, self.gemData.itemID)
            C_Timer.After(0.1, function()
                if InCombatLockdown() then return end
                CP:RefreshSocketButtons()
            end)
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

                if socket.filled then
                    -- icon can be nil while the gem's item data hydrates (cold
                    -- cache); show the placeholder at full alpha — the row
                    -- repaints via ITEM_DATA_LOAD_RESULT once the gem loads.
                    btn.icon:SetTexture(socket.icon or 458977)
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

    -- After the hide loop: the enchant button parks itself after the last
    -- button still SHOWN, so it has to read their final state.
    self:RefreshEnchantButton()
    local enchantShown = (self.enchantButton and self.enchantButton:IsShown()) and 1 or 0

    local slotCount = (buttonIndex - 1) + enchantShown
    local totalWidth = slotCount * (db.SocketButtonSize + db.SocketButtonSpacing)
    self.socketContainer:SetWidth(totalWidth > 0 and totalWidth or 1)

    -- Shown when EITHER half has something to offer: with no sockets at all
    -- the enchant button is still worth a bar of its own.
    if slotCount > 0 then self.socketContainer:Show() else self.socketContainer:Hide() end
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

    -- Replace All eligibility: candidate rows exist and the target socket holds
    -- a resolvable, non-unique gem (a unique gem can't have duplicates to
    -- replace). Consumed by the OnClick shift branch + the footer preview.
    popup._replaceAllGemID = (#gemList > 0 and socketBtn.socket.filled and currentGemID
        and not IsGemUnique(socketBtn.socket.gemLink, currentGemID))
        and currentGemID or nil

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
        if popup._replaceAllGemID then
            targetHeight = targetHeight + 22  -- separator + footer hint row
        end
    end

    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", socketBtn, "BOTTOMLEFT", 0, -1)
    popup:SetHeight(targetHeight)
    popup:Show()
    self:UpdateReplaceAllPreview()
end

-- Sole authority for the socket-helper glow + Replace All footer while the
-- popup is open. Shift + a replace-eligible socket = glow every affected slot
-- and show the match count; otherwise the hovered socket's single glow, plus
-- the discoverability hint when eligible. Called at popup build, on
-- MODIFIER_STATE_CHANGED, and from the socket/gem hover handlers — so the
-- glow can't be left in a stale single/multi state by a hover-then-shift race.
function CP:UpdateReplaceAllPreview()
    local popup = self.gemPopup
    if not popup or not popup:IsShown() then return end
    local oldGemID = popup._replaceAllGemID

    -- Bright red modifier keyword matching the DSH reference (|cffFC0316); a
    -- white base keeps the rest legible against the popup background.
    local SHIFT_RED = "|cffFC0316"
    if oldGemID and IsShiftKeyDown() then
        local matches = self:GetMatchingGemSockets(oldGemID)
        local slotIDs = {}
        for _, m in ipairs(matches) do table.insert(slotIDs, m.slotID) end
        self:ShowSlotHighlights(slotIDs)
        popup.replaceHint:SetText(string.format("%sReplace All:|r %d socket%s",
            SHIFT_RED, #matches, #matches == 1 and "" or "s"))
        popup.replaceHint:SetTextColor(1, 1, 1)
        popup.replaceHint:Show()
        popup.replaceSep:Show()
    else
        -- Single glow on the hovered socket (the pre-Replace-All behavior).
        if self.currentSocketBtn and self.currentSocketBtn.socketInfo then
            self:ShowSlotHighlight(self.currentSocketBtn.socketInfo.slotID)
        end
        if oldGemID then
            popup.replaceHint:SetText(SHIFT_RED .. "Shift-Click:|r Replace All")
            popup.replaceHint:SetTextColor(1, 1, 1)
            popup.replaceHint:Show()
            popup.replaceSep:Show()
        else
            popup.replaceHint:Hide()
            popup.replaceSep:Hide()
        end
    end
end

function CP:HideGemPopup()
    if self.gemPopup then self.gemPopup:Hide() end
end

function CP:ShowSlotHighlight(slotID)
    self:ShowSlotHighlights({ slotID })
end

-- Multi-slot variant for the Replace All preview: Shift-down glows every slot
-- the replace would touch. Native Blizzard spell-activation overlay glow —
-- the same code path DominationSocketHelper uses (pixel-identical to the
-- in-game "ability ready" glow). No accent overlay underneath.
function CP:ShowSlotHighlights(slotIDs)
    self:HideSlotHighlight()
    if not ActionButtonSpellAlertManager then return end
    self._glowingSlotFrames = self._glowingSlotFrames or {}
    local seen = {}
    for _, slotID in ipairs(slotIDs) do
        local frameName = SLOT_FRAMES[slotID]
        local slotFrame = frameName and _G[frameName]
        -- Dedup: two matched sockets on one item glow its slot frame once
        -- (a second ShowAlert would orphan an overlay on the single HideAlert).
        if slotFrame and not seen[slotFrame] then
            seen[slotFrame] = true
            ActionButtonSpellAlertManager:ShowAlert(slotFrame)
            table.insert(self._glowingSlotFrames, slotFrame)
        end
    end
end

function CP:HideSlotHighlight()
    if ActionButtonSpellAlertManager and self._glowingSlotFrames then
        for _, slotFrame in ipairs(self._glowingSlotFrames) do
            ActionButtonSpellAlertManager:HideAlert(slotFrame)
        end
        wipe(self._glowingSlotFrames)
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
    self:HideEnchantPopup()
    if self.enchantButton then self.enchantButton:Hide() end
    self:HideSlotHighlight()
end

---------------------------------------------------------------------------------
-- Enchant Helper
---------------------------------------------------------------------------------
-- One extra button on the right end of the socket bar. Hovering it lists every
-- enchant in your bags; clicking a row starts Blizzard's normal "now click the
-- item" flow. Ported from NorskenUI v6 CharacterPanel.lua:1162-1562. Three
-- deliberate deviations from that source, each noted at its site below.

-- Enchanting profession icon. The reference uses a bare fileID (4620672); a
-- named texture path says what it is and survives an asset renumber.
local ENCHANT_BUTTON_ICON = "Interface\\Icons\\Trade_Engraving"

-- Which slots an enchant targets, resolved from words in its tooltip. English
-- literals, same convention as GetItemTrack's "Upgrade Level:" and IsGemUnique's
-- "Unique-Equipped" scans.
local ENCHANT_SLOT_KEYWORDS = {
    ["chest"] = { 5 },
    ["cloak"] = { 15 },
    ["back"] = { 15 },
    ["cape"] = { 15 },
    ["legs"] = { 7 },
    ["leg"] = { 7 },
    ["boot"] = { 8 },
    ["feet"] = { 8 },
    ["bracer"] = { 9 },
    ["wrist"] = { 9 },
    ["ring"] = { 11, 12 },
    ["2h weapon"] = { 16 },
    ["weapon"] = { 16, 17 },
    ["staff"] = { 16 },
    ["glove"] = { 10 },
    ["hand"] = { 10 },
    ["helm"] = { 1 },
    ["head"] = { 1 },
    ["shoulder"] = { 3 },
    ["belt"] = { 6 },
    ["waist"] = { 6 },
    ["neck"] = { 2 },
    ["trinket"] = { 13, 14 },
}

-- DEVIATION 1 (bug fix). The reference walks this table with pairs() and
-- returns on the first hit, so a tooltip containing two keywords resolves
-- non-deterministically. "Enchant 2H Weapon - ..." contains BOTH "2h weapon"
-- ({16}) and "weapon" ({16, 17}), and which one wins can differ between
-- sessions. Longest key first makes the most specific match win every time.
-- Same fix, same reason as enchantNicknameOrder above.
local enchantKeywordOrder = {}
for keyword in pairs(ENCHANT_SLOT_KEYWORDS) do
    enchantKeywordOrder[#enchantKeywordOrder + 1] = keyword
end
table.sort(enchantKeywordOrder, function(a, b) return #a > #b end)

local enchantCache = {}

local function GetEnchantTargetSlots(itemLink)
    if not itemLink then return nil end
    local data = C_TooltipInfo.GetHyperlink(itemLink)
    if not data or not data.lines then return nil end

    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if text then
            local lowerText = text:lower()
            for _, keyword in ipairs(enchantKeywordOrder) do
                if lowerText:find(keyword, 1, true) then
                    return ENCHANT_SLOT_KEYWORDS[keyword]
                end
            end
        end
    end
    return nil
end
CP._GetEnchantTargetSlots = GetEnchantTargetSlots

local function GetEnchantDisplayName(itemLink)
    if not itemLink then return nil end
    local data = C_TooltipInfo.GetHyperlink(itemLink)
    if not data or not data.lines or not data.lines[1] then return nil end
    local name = data.lines[1].leftText
    if name then
        name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    end
    return name
end

local function IsRingEnchant(targetSlots)
    if not targetSlots then return false end
    for _, slotID in ipairs(targetSlots) do
        if slotID == 11 or slotID == 12 then return true end
    end
    return false
end

-- Leg armour kits are excluded from the list. The reference excludes them with
-- no rationale in the source; Brandon confirmed why on 2026-08-03 -- they did
-- not work reliably there. Keeping them out until someone establishes what
-- breaks, rather than shipping a row that fails on click.
local function IsArmorKit(targetSlots)
    if not targetSlots then return false end
    for _, slotID in ipairs(targetSlots) do
        if slotID == 7 then return true end
    end
    return false
end

function CP:ScanBagsForEnchants()
    wipe(enchantCache)
    local NUM_BAG_SLOTS = NUM_BAG_SLOTS or 4
    -- DEVIATION 2: the reference reads LE_ITEM_CLASS_ITEM_ENHANCEMENT, a legacy
    -- global. Enum with a literal fallback matches ScanBagsForGems above.
    local ITEM_ENHANCEMENT = (Enum and Enum.ItemClass and Enum.ItemClass.ItemEnhancement) or 8
    for bag = 0, NUM_BAG_SLOTS do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(info.itemID)
                if classID == ITEM_ENHANCEMENT then
                    local targetSlots = GetEnchantTargetSlots(info.hyperlink)
                    if targetSlots and not IsArmorKit(targetSlots) then
                        local existing = enchantCache[info.itemID]
                        if existing then
                            existing.count = existing.count + info.stackCount
                        else
                            enchantCache[info.itemID] = {
                                itemID = info.itemID, icon = info.iconFileID,
                                count = info.stackCount, link = info.hyperlink,
                                bagID = bag, slotID = slot,
                                targetSlots = targetSlots,
                            }
                        end
                    end
                end
            end
        end
    end
    return enchantCache
end

-- The first target slot that actually holds an item. Drives the hover glow
-- only; the click path hands off to Blizzard, which picks the real target.
function CP:FindBestEnchantSlot(targetSlots)
    if not targetSlots or #targetSlots == 0 then return nil end
    for _, slotID in ipairs(targetSlots) do
        if GetInventoryItemLink("player", slotID) then return slotID end
    end
    return nil
end

function CP:CreateEnchantButton()
    if self.enchantButton then return self.enchantButton end

    local db = self.db
    local Theme = KE.Theme

    local btn = CreateFrame("Button", nil, self.socketContainer)
    btn:SetSize(db.SocketButtonSize, db.SocketButtonSize)

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()
    btn.icon:SetTexture(ENCHANT_BUTTON_ICON)
    KE:ApplyIconZoom(btn.icon, 0.3)
    KE:AddIconBorders(btn, Theme.border)

    btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.highlight:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    btn.highlight:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    btn.highlight:SetColorTexture(1, 1, 1, 0.2)
    btn.highlight:SetBlendMode("ADD")

    btn:SetScript("OnEnter", function()
        -- The two popups share the bar, so opening this one closes the gem
        -- popup and its slot glow first.
        CP:HideGemPopup()
        CP:HideSlotHighlight()
        CP:ShowEnchantPopup(btn)
    end)

    btn:SetScript("OnLeave", function()
        C_Timer.After(0.05, function()
            if IsMouseOverGemUI() then return end
            CP:HideGemPopup()
            CP:HideEnchantPopup()
            CP:HideSlotHighlight()
        end)
    end)

    btn:Hide()
    self.enchantButton = btn
    return btn
end

function CP:CreateEnchantPopup()
    if self.enchantPopup then return self.enchantPopup end

    local Theme = KE.Theme

    local popup = CreateFrame("Frame", "KE_EnchantPopup", UIParent, "BackdropTemplate")
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
    popup.title:SetText("Enchants")
    popup.title:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3])

    popup.separator = popup:CreateTexture(nil, "ARTWORK")
    popup.separator:SetHeight(1)
    popup.separator:SetPoint("TOPLEFT", popup, "TOPLEFT", 0, -TITLE_HEIGHT)
    popup.separator:SetPoint("TOPRIGHT", popup, "TOPRIGHT", 0, -TITLE_HEIGHT)
    popup.separator:SetColorTexture(Theme.border[1], Theme.border[2], Theme.border[3], 1)

    popup.noEnchants = popup:CreateFontString(nil, "OVERLAY")
    popup.noEnchants:SetPoint("CENTER", 0, -8)
    KE:ApplyFontToText(popup.noEnchants, "Expressway", 14, "OUTLINE")
    popup.noEnchants:SetText("No enchants in bags")
    popup.noEnchants:SetTextColor(Theme.textMuted[1], Theme.textMuted[2], Theme.textMuted[3])
    popup.noEnchants:Hide()

    popup:EnableMouse(true)
    popup:SetScript("OnLeave", function()
        C_Timer.After(0.05, function()
            if IsMouseOverGemUI() then return end
            CP:HideEnchantPopup()
            CP:HideSlotHighlight()
        end)
    end)

    popup.buttons = {}
    self.enchantPopup = popup
    return popup
end

function CP:CreateEnchantRow(index)
    local popup = self.enchantPopup
    local Theme = KE.Theme
    local iconSize = POPUP_ICON_SIZE
    local rowHeight = POPUP_ICON_SIZE + ITEM_ROW_PADDING

    if popup.buttons[index] then return popup.buttons[index] end

    local btn = CreateFrame("Button", "KE_EnchantBtn" .. index, popup)
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

    btn:SetScript("OnUpdate", function(button, elapsed)
        local current = button._hoverBg:GetAlpha()
        if math.abs(current - button._hoverTarget) > 0.01 then
            local speed = elapsed / HOVER_DURATION
            if button._hoverTarget > current then
                button._hoverBg:SetAlpha(math.min(current + speed, button._hoverTarget))
            else
                button._hoverBg:SetAlpha(math.max(current - speed, button._hoverTarget))
            end
        end
    end)

    btn:SetScript("OnEnter", function(button)
        button._hoverTarget = 1
        -- Ring enchants can go on either finger, so glow both.
        if button.enchantData and IsRingEnchant(button.enchantData.targetSlots) then
            CP:ShowSlotHighlights(button.enchantData.targetSlots)
        elseif button.targetSlotID then
            CP:ShowSlotHighlight(button.targetSlotID)
        end
        if button.enchantData and button.enchantData.link then
            GameTooltip:SetOwner(button, "ANCHOR_RIGHT", 40, 0)
            GameTooltip:SetHyperlink(button.enchantData.link)
            GameTooltip:Show()
        end
    end)

    btn:SetScript("OnLeave", function(button)
        button._hoverTarget = 0
        GameTooltip:Hide()
        C_Timer.After(0.05, function()
            if IsMouseOverGemUI() then return end
            CP:HideEnchantPopup()
            CP:HideSlotHighlight()
        end)
    end)

    btn:SetScript("OnClick", function(button)
        CP:ApplyEnchantFromBags(button.enchantData)
    end)

    popup.buttons[index] = btn
    return btn
end

-- Split out of the OnClick closure so the combat refusal is reachable without
-- standing up a frame (dev/spec/character_panel_enchant_spec.lua). Returns
-- true only when the pickup was actually issued.
function CP:ApplyEnchantFromBags(enchantData)
    if InCombatLockdown() then
        KE:Print("Cannot enchant during combat")
        return false
    end
    if not enchantData then return false end
    -- DEVIATION 3: the reference calls the bare UseContainerItem global.
    -- Blizzard's own code uses the namespaced form everywhere in 12.0.7
    -- (ContainerFrame.lua:1342, SecureTemplates.lua:771), so the bare name is
    -- at best a deprecated shim.
    -- This picks the enchant up; the player then clicks the item to apply it.
    -- Deliberately NOT auto-applied -- same as the reference.
    C_Container.UseContainerItem(enchantData.bagID, enchantData.slotID)
    self:HideEnchantPopup()
    self:HideSlotHighlight()
    return true
end

function CP:ShowEnchantPopup(enchantBtn)
    local popup = self:CreateEnchantPopup()
    local enchants = self:ScanBagsForEnchants()
    local Theme = KE.Theme

    -- Only offer an enchant whose target slot actually holds gear.
    local enchantList = {}
    for _, enchantData in pairs(enchants) do
        local targetSlotID = self:FindBestEnchantSlot(enchantData.targetSlots)
        if targetSlotID then
            enchantData.resolvedSlotID = targetSlotID
            table.insert(enchantList, enchantData)
        end
    end

    popup.title:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3])

    local minWidth = popup.title:GetStringWidth() + 26
    local minRowHeight = POPUP_ICON_SIZE + ITEM_ROW_PADDING
    local targetHeight

    if #enchantList == 0 then
        popup.noEnchants:Show()
        popup.separator:Hide()
        popup.noEnchants:SetTextColor(Theme.textMuted[1], Theme.textMuted[2], Theme.textMuted[3])
        for _, btn in pairs(popup.buttons) do btn:Hide() end
        popup:SetWidth(math.max(200, minWidth))
        targetHeight = 50
    else
        popup.noEnchants:Hide()
        popup.separator:Show()

        local yOffset = TITLE_HEIGHT
        for i, enchantData in ipairs(enchantList) do
            local btn = self:CreateEnchantRow(i)
            btn.enchantData = enchantData
            btn.targetSlotID = enchantData.resolvedSlotID
            btn.icon:SetTexture(enchantData.icon)
            btn.count:SetText(enchantData.count .. "x")
            btn.count:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3])
            btn._hoverBg:SetAlpha(0); btn._hoverTarget = 0

            btn.stats:SetText(GetEnchantDisplayName(enchantData.link) or "")
            btn.stats:SetTextColor(Theme.textPrimary[1], Theme.textPrimary[2], Theme.textPrimary[3])

            local textHeight = btn.stats:GetStringHeight()
            local rowHeight = math.max(minRowHeight, textHeight + ITEM_ROW_PADDING)
            btn:SetHeight(rowHeight)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", popup, "TOPLEFT", POPUP_PADDING, -yOffset)
            btn:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -POPUP_PADDING, -yOffset)
            btn.iconFrame:SetSize(POPUP_ICON_SIZE, POPUP_ICON_SIZE)

            SetQualityAtlas(btn.quality, GetQualityAtlasFromLink(enchantData.link))

            btn:Show()
            yOffset = yOffset + rowHeight
        end
        for i = #enchantList + 1, #popup.buttons do popup.buttons[i]:Hide() end

        popup:SetWidth(280)
        targetHeight = yOffset
    end

    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", enchantBtn, "BOTTOMLEFT", 0, -1)
    popup:SetHeight(targetHeight)
    popup:Show()
end

function CP:HideEnchantPopup()
    if self.enchantPopup then self.enchantPopup:Hide() end
end

-- Parks the button after the last VISIBLE socket button, so it stays flush
-- with the bar whether there are eleven sockets or none.
function CP:RefreshEnchantButton()
    if not self.socketContainer then return end
    if not (self.db.SocketHelperEnabled and self.db.EnchantHelperEnabled) then
        if self.enchantButton then self.enchantButton:Hide() end
        return
    end

    local db = self.db
    local btn = self:CreateEnchantButton()
    btn:SetSize(db.SocketButtonSize, db.SocketButtonSize)
    btn:ClearAllPoints()

    local lastSocketBtn
    for i = #self.socketContainer.buttons, 1, -1 do
        if self.socketContainer.buttons[i]:IsShown() then
            lastSocketBtn = self.socketContainer.buttons[i]
            break
        end
    end

    if lastSocketBtn then
        btn:SetPoint("LEFT", lastSocketBtn, "RIGHT", db.SocketButtonSpacing, 0)
    else
        btn:SetPoint("LEFT", self.socketContainer, "LEFT", 0, 0)
    end

    btn:Show()
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
-- One-shot login cache warm-up. A client patch wipes the local item cache; the
-- GEM items (not the equipped gear itself) are then unloaded at first login,
-- so the first character-panel open renders sockets from unhydrated data.
-- Request everything the gem features will need during the loading screen.
-- Gem IDs come from the equipped links via GetItemGemID, which resolves
-- without the gem's item data (Blizzard PaperDollFrame pattern).
function CP:PrimeGemCache(_, isInitialLogin)
    if not isInitialLogin then return end
    -- Only warm what a gem feature will actually render (ShowMissingGems is
    -- default-on, hence the ~= false form matching UpdateSlotDetail's gate).
    if not (self.db.ShowSlotGems or self.db.ShowMissingGems ~= false or self.db.SocketHelperEnabled) then
        return
    end
    for slotID in pairs(SLOT_FRAMES) do
        local link = GetInventoryItemLink("player", slotID)
        if link then
            local baseID = GetItemInfoInstant(link)
            if baseID and not C_Item.IsItemDataCachedByID(baseID) then
                C_Item.RequestLoadItemDataByID(baseID)
            end
            for i = 1, SLOT_DETAIL_MAX_GEMS do
                local gemID = C_Item.GetItemGemID(link, i)
                if gemID and not C_Item.IsItemDataCachedByID(gemID) then
                    C_Item.RequestLoadItemDataByID(gemID)
                end
            end
        end
    end
end

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
        KE:Print("BetterCharacterPanel disabled - all of its features and then some are now in KitnEssentials. |cffffff00/reload|r to apply.")
    end

    HookCharacterPanel()

    -- Warm the gem cache during the login loading screen (see PrimeGemCache).
    -- AceEvent unregisters automatically on module disable.
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "PrimeGemCache")

    -- Wake InspectPanel; it owns the inspect orchestration.
    local insp = KitnEssentials:GetModule("InspectPanel", true)
    if insp then insp:Enable() end

    -- Race: if the character pane is already shown when the module enables
    -- (e.g. user toggled the module on with the pane open), the PaperDollFrame
    -- OnShow hook installed above won't fire on this path. Register events +
    -- force one refresh inline.
    if PaperDollFrame and PaperDollFrame:IsShown() then
        if self.eventFrame then
            self.eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
            self.eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
            self.eventFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
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
    wipe(_lastSlotState)
    wipe(_pendingGemLoads)
    wipe(_gemLoadAttempts)
    self:DisableGemSocketHelper()
    self:HideAllTrackIndicators()
    self:HideAllSlotDetails()
    self:HideRaceText()
    RestoreCharacterBackground()
    updatePending = false

    -- Cascade to InspectPanel; it owns its own state (queue, inspectUpdatePending,
    -- event frame, ilvl FontString) and teardown.
    local insp = KitnEssentials:GetModule("InspectPanel", true)
    if insp then insp:Disable() end
end

-- ╔══════════════════════════════════════════════════════════╗
-- ║  CharacterPanel.lua                                      ║
-- ║  Module: Character Panel                                 ║
-- ║  Purpose: Missing enchant/gem warnings, decimal ilvl,    ║
-- ║           character text styling, Mythic+ score, item    ║
-- ║           track indicators, gem socket helper.           ║
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
local CursorHasItem = CursorHasItem
local SpellIsTargeting = SpellIsTargeting
local PickupInventoryItem = PickupInventoryItem
local UnitLevel = UnitLevel
local GameRulesUtil = GameRulesUtil
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

-- 12.1 removed the IsLevelAtEffectiveMaxLevel global; Blizzard code now
-- compares against GameRulesUtil.GetEffectiveMaxLevelForPlayer (GameRulesUtil.lua).
local function IsLevelAtEffectiveMaxLevel(level)
    return GameRulesUtil and GameRulesUtil.GetEffectiveMaxLevelForPlayer
        and level >= GameRulesUtil.GetEffectiveMaxLevelForPlayer()
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

-- The style decides which pipeline a label takes, and they diverge rather than
-- nest. Every style strips the "Enchant <Slot> - " prefix; "full" is then done.
-- "verbose" reduces what is left to its keyword. "short" skips the keyword step
-- and instead maps through the nickname table, then abbreviates stat words.
-- Memoized because that last path walks the nickname and stat-abbreviation tables
-- entry by entry -- one gsub each, so the cost is their combined size and grows
-- whenever either does -- while the same handful of equipped enchant names
-- re-resolve on every slot render, including inspect gem-race retries.
-- ProcessEnchantText owns the cache key; a pure function of its inputs and the
-- load-time constant tables, so entries never invalidate.
-- Words that never carry the meaning of an enchant name, so the keyword walk
-- below skips them rather than returning one.
local ENCHANT_FILLER = { ["of"] = true, ["the"] = true, ["and"] = true, ["a"] = true }

-- The last word that is not filler. Splits by EXCLUSION on ASCII separators
-- rather than with %w: Lua's character classes are ASCII-only, so %w matches no
-- multi-byte byte at all and a non-Latin name would reduce to nothing.
local function EnchantKeyword(name)
    if not name or name == "" then return name end
    local keyword
    for word in name:gmatch("[^%s,:;/%.%(%)]+") do
        if not ENCHANT_FILLER[word:lower()] then keyword = word end
    end
    return keyword or name
end

local _enchantLabelCache = {}
local function ProcessEnchantText(text, style)
    if not text or text == "" then return text end
    if style ~= "verbose" and style ~= "full" then style = "short" end

    -- Keyed on style AND raw text. Keying on the raw text alone would serve
    -- one style's label to another, and the entries never expire.
    local cacheKey = style .. "\0" .. text
    local cached = _enchantLabelCache[cacheKey]
    if cached then return cached end

    -- Strip the "Enchant <Slot> - " preamble FIRST, so nickname lookups match the
    -- bare effect name. Every style wants it gone -- naming the slot beside the
    -- slot says nothing.
    for prefix, replacement in pairs(enchantStripPrefixes) do
        text = text:gsub(prefix, replacement)
    end

    -- "full" is the effect name as the tooltip gives it, so it stops here and
    -- KEEPS a leading "+": an enchant reading "+10 Stats" must not render as
    -- "10 Stats".
    if style == "full" then
        _enchantLabelCache[cacheKey] = text
        return text
    end

    -- The "+" strip is NOT a prefix -- it is unanchored and removes the sign
    -- wherever it appears -- so it lives here rather than in the table above:
    -- after the "full" exit, and before the nickname pass, where a value may
    -- deliberately reintroduce one (e.g. "Crit%+").
    text = text:gsub("%+", "")

    if style == "verbose" then
        text = EnchantKeyword(text)
        _enchantLabelCache[cacheKey] = text
        return text
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
    _enchantLabelCache[cacheKey] = text
    return text
end
CP._ProcessEnchantText = ProcessEnchantText

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

-- The two weapon slots under the model. They appear in RIGHT_SLOTS too, for gem
-- and enchant anchoring, but their item level is centred above the icon rather
-- than pinned to an inner edge -- so anything ordering by side must exclude them.
local CENTER_SLOTS = { [16] = true, [17] = true }

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
    name = ProcessEnchantText(name, self.db.EnchantNameStyle)
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
    local fontFace    = (db and db.FontFace)
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
    local fontFace    = (db and db.FontFace)
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
        -- Drop the dirty key on the way out, not just skip storing it. The key
        -- describes an item, so on an UNCHANGED item it still matches the one
        -- the last real render left behind -- and the handback would then
        -- short-circuit against it and leave the slot blank in both addons.
        if unit == "player" then
            local s = _slotState(slot)
            s.warnLink, s.warnEnchant = nil, nil
        end
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
    -- the gem row (see UpdateSlotDetail), to avoid a third text
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
    if not CP:IsEnabled() then return end
    if not (CharacterFrame and CharacterFrame:IsShown()) then return end
    updatePending = true
    C_Timer.After(UPDATE_DEBOUNCE, function()
        updatePending = false
        -- Re-checked rather than captured: this fires later and the module may
        -- have been torn down in between.
        if CP:IsEnabled() and CharacterFrame and CharacterFrame:IsShown() then
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
    if not CP:IsEnabled() then return end
    if not (PaperDollFrame and PaperDollFrame:IsShown()) then return end
    socketRefreshPending = true
    C_Timer.After(UPDATE_DEBOUNCE, function()
        socketRefreshPending = false
        if CP:IsEnabled() and CP.db and CP.db.SocketHelperEnabled
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

---------------------------------------------------------------------------------
-- Wider character window
---------------------------------------------------------------------------------
-- Fixed, not a slider. Everything below is expressed as `add` or `add / 2`, so
-- the layout re-centres itself at any value -- the number is a matter of taste
-- rather than of geometry, and a slider would invite widths nobody has looked
-- at.
local WIDEN_BY = 40

-- Stands down whenever another addon owns the character sheet. ElvUI reskins
-- the frame, and an EUI themed sheet re-anchors every slot into its own
-- two-column grid, so widening under either fights a layout we do not control.
--
-- The ElvUI test matches the one the GUI card is gated on. A behaviour gate
-- that disagreed with its own control would act on a setting the user is being
-- told is unavailable.
local function ExtraWidth()
    local db = CP.db
    if not db or not db.WiderFrame then return 0 end
    -- The module's LIFECYCLE STATE, not the preference key. The hooks below
    -- install once and cannot be removed, so without this they keep re-widening
    -- after the module is switched off -- and the control for this setting lives
    -- inside that master gate, so the player could not reach it to stop them.
    --
    -- `IsEnabled()` rather than `db.Enabled` because the two can disagree:
    -- `CP:Disable()` is reachable without the key changing, and Ace marks the
    -- module disabled BEFORE running OnDisable, so this reads false there while
    -- the key is still true. Reading the key would re-apply the widen from
    -- inside the very teardown meant to undo it.
    if not CP:IsEnabled() then return 0 end
    if ElvUILoaded() then return 0 end
    if KE:EUISheetActive("player") then return 0 end
    return WIDEN_BY
end
CP._ExtraWidth = ExtraWidth

local widenHooked = false
local widenApplied = false

-- How much extra width to write, or nil to write NOTHING. Separated from
-- ApplyWiden so the decision can be tested; ApplyWiden itself is pure frame
-- geometry, which is not testable headless.
--
-- Three states, and the difference between the last two is the whole point:
--
--   * Paper doll not shown -> nil. The Reputation and Currency tabs are sized 400
--     by Blizzard, not PANEL_DEFAULT_WIDTH, and UpdateSize is one of the four
--     hooks, so writing a paper-doll width here corrupts the tab on every switch.
--   * Gate off but we HAVE widened -> 0, exactly once. The reload prompt this
--     setting raises can be answered "Later", so the key really can go false while
--     a widened frame is on screen. One pass writes Blizzard's own numbers back.
--   * Gate off and we have NOT widened -> nil. Never touch geometry we did not
--     set: this is the state where another UI owns the sheet, and writing
--     Blizzard's defaults would overwrite the anchors it just applied.
local function WidenAmount(extra, pdfShown, applied)
    if not pdfShown then return nil end
    if extra > 0 then return extra end
    if applied then return 0 end
    return nil
end
CP._WidenAmount = WidenAmount

-- The header belongs over the character, not over the panel. Blizzard centres
-- both header strings on the whole frame, so the stat pane drags them right of
-- the model.
--
-- Blizzard's own anchor points, captured before anything is moved.
-- ClearAllPoints is destructive and leaves nothing behind that knows where a
-- string belongs, so without this a disabled module strands the header wherever
-- we last put it.
local origHeaderAnchors = {}

local function CaptureAnchors(region)
    if not region or origHeaderAnchors[region] then return end
    local points, count = {}, region:GetNumPoints()
    if count < 1 then return end
    for i = 1, count do
        local point, relativeTo, relativePoint, x, y = region:GetPoint(i)
        points[i] = { point, relativeTo, relativePoint, x, y }
    end
    origHeaderAnchors[region] = points
end

local function RestoreAnchors(region)
    local points = region and origHeaderAnchors[region]
    if not points then return end
    region:ClearAllPoints()
    for _, a in ipairs(points) do
        region:SetPoint(a[1], a[2], a[3], a[4], a[5])
    end
end

local function HeaderRegions()
    local cf = _G.CharacterFrame
    local titleText = _G.CharacterFrameTitleText
        or (cf and cf.TitleContainer and cf.TitleContainer.TitleText)
    return cf, titleText, _G.CharacterLevelText
end

-- ABSOLUTE anchors, never deltas. Every value is set to a computed absolute, so
-- running this ten times produces the same layout as running it once. Four
-- hooks call it and they do not agree on whether Blizzard has just rewritten
-- the geometry, so any sum over live values eventually compounds.
--
-- The right slot column hangs off the STAT PANE'S LEFT EDGE rather than off the
-- inset. Defining the column relative to the thing it would otherwise collide
-- with makes a collision impossible at any width.
local function ApplyWiden()
    local cf = _G.CharacterFrame
    local inset, insetR = _G.CharacterFrameInset, _G.CharacterFrameInsetRight
    local hands, mh = _G.CharacterHandsSlot, _G.CharacterMainHandSlot
    local model, items = _G.CharacterModelScene, _G.PaperDollItemsFrame
    local pdf = _G.PaperDollFrame
    if not (cf and inset and insetR and hands and mh and model and items and pdf) then return end

    local add = WidenAmount(ExtraWidth(), pdf:IsShown() and true or false, widenApplied)
    if not add then return end
    widenApplied = add > 0

    -- Blizzard's own values, with literal fallbacks.
    local baseW = cf.Expanded and (_G.CHARACTERFRAME_EXPANDED_WIDTH or 540)
        or (_G.PANEL_DEFAULT_WIDTH or 338)

    cf:SetWidth(baseW + add)

    -- Stat pane: left edge pushed out by the extra width, right edge still
    -- pinned to the frame (which grew by the same amount), so it MOVES rather
    -- than stretching.
    insetR:ClearAllPoints()
    insetR:SetPoint("TOPLEFT", inset, "TOPRIGHT", 1 + add, 0)
    insetR:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", -4, 4)

    -- The stat-pane-left-edge anchor described above. On the single restoring
    -- pass (add == 0) Blizzard's own anchor goes back instead.
    hands:ClearAllPoints()
    if add > 0 then
        hands:SetPoint("TOPRIGHT", insetR, "TOPLEFT", -4, -2)
    else
        hands:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -4, -2)
    end

    -- Centred content moves by half the delta, from Blizzard's literal offsets.
    model:ClearAllPoints()
    model:SetPoint("TOPLEFT", pdf, "TOPLEFT", 52 + add / 2, -66)

    mh:ClearAllPoints()
    mh:SetPoint("BOTTOMLEFT", items, "BOTTOMLEFT", 130 + add / 2, 16)
end

-- Independent of ApplyWiden's early return: the header correction is needed
-- whether or not this module widens anything, and ApplyWiden bails whenever
-- there is no width to write.
--
-- ANCHORS, not offsets. The name hangs off the model scene and the level line
-- hangs off the name, so the whole stack tracks the model for free. An x offset
-- derived from the frame's centre is only correct at the width it was measured
-- at, and CharacterFrame swaps widths on Expand/Collapse -- which puts the name
-- right on the first open and drifting on the next.
function CP:ApplyHeaderCentering()
    local cf, titleText, levelText = HeaderRegions()
    if not (cf and titleText and levelText) then return end

    CaptureAnchors(titleText)
    CaptureAnchors(levelText)

    -- Restore rather than return. An early return strands the last anchors we
    -- wrote, which is how a disabled module keeps holding Blizzard's header.
    --
    -- BOTH enable tests. IsEnabled() is the Ace lifecycle state, db.Enabled is
    -- the profile key, and the two genuinely disagree -- a profile switch
    -- re-applies settings without re-enabling.
    local pdf = _G.PaperDollFrame
    local model = _G.CharacterModelScene
    local own = self:IsEnabled() and self.db and self.db.Enabled
        and not ElvUILoaded()
        and not KE:EUIDrawsSlotElement("player", "headerText")

    -- Paperdoll tab only. Reputation and Currency reuse this same title string
    -- for their own headers, where a name centred over the model column reads
    -- wrong above a list.
    if not (own and pdf and pdf:IsShown() and model) then
        RestoreAnchors(titleText)
        RestoreAnchors(levelText)
        return
    end

    -- Captured ONCE, while the title is still on Blizzard's anchor: after the
    -- move this reads our own placement back and the name walks up the frame on
    -- every pass.
    if self._titleModelTopOff == nil then
        local titleTop, modelTop = titleText:GetTop(), model:GetTop()
        if not (titleTop and modelTop) then return end
        self._titleModelTopOff = titleTop - modelTop
    end

    -- +10: the model is posed slightly right of the scene frame's own centre.
    titleText:ClearAllPoints()
    titleText:SetPoint("TOP", model, "TOP", 10, self._titleModelTopOff)

    levelText:ClearAllPoints()
    levelText:SetPoint("TOP", titleText, "BOTTOM", 0, -1)
end

-- FOUR hooks, not one. These are the methods that set the width back, and
-- missing any one is what makes a widened frame snap back at random. All four
-- do the same thing because ApplyWiden is absolute -- it does not matter which
-- fired or what happened before it.
--
-- Post-hooks only. CharacterFrame is an ordinary unprotected frame whose panel
-- registration pins no width, which is what keeps this taint-safe.
function CP:SetupWiderFrame()
    local cf = _G.CharacterFrame
    if not cf then return end

    -- The once-guard wraps ONLY the installation. `ApplyWiden` below runs on
    -- every enable: re-enabling with the paper doll already open would otherwise
    -- leave the frame narrow until some unrelated reset method happened to fire,
    -- because an early return here skips it.
    if not widenHooked then
        widenHooked = true
        for _, method in ipairs({ "Expand", "Collapse", "UpdateSize", "ShowSubFrame" }) do
            local methodFunc = cf[method]
            if type(methodFunc) == "function" then
                hooksecurefunc(cf, method, function()
                    ApplyWiden()
                    CP:ApplyHeaderCentering()
                end)
            end
        end
    end

    ApplyWiden()
    CP:ApplyHeaderCentering()
end

-- Exported so a spec can prove the nil guard runs BEFORE the first geometry
-- write. The predicate alone cannot: deleting `if not add then return end`, or
-- moving it below `cf:SetWidth(...)`, leaves every predicate case green.
CP._ApplyWiden = ApplyWiden

local function HookCharacterPanel()
    if hooked then return end

    if PaperDollFrame then
        PaperDollFrame:HookScript("OnShow", function()
            -- This hook is permanent and outlives OnDisable, so it gates on the
            -- module rather than on the key the player set.
            if not CP:IsEnabled() then return end
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
            -- Full refresh, not the dirty-checked one: a setting changed while
            -- the pane was CLOSED never got applied, so the old display would
            -- otherwise come back with the feature off.
            CP:RefreshSlotDisplays()
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
        -- The script is set once and never cleared. Belt and braces with the
        -- OnShow gate above: that one stops the re-registration, this one stops
        -- anything already in flight.
        if not CP:IsEnabled() then return end
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

    self:UpdateDB()
    -- The rebind above always runs; the rest does not. The GUI calls this
    -- method directly, and below it installs permanent hooks -- machinery for a
    -- module that is switched off.
    if not self:IsEnabled() then return end
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

    -- Above the master-key return: switching to a profile with the panel off
    -- must still hand Blizzard's header back.
    self:ApplyHeaderCentering()

    if not self.db.Enabled then return end

    -- Wake or stand down InspectPanel; it owns the inspect orchestration. Here
    -- rather than in OnEnable because the profile manager re-applies settings
    -- without re-enabling, and this key can differ between profiles.
    self:ApplyInspectPanelState()

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
    -- EITHER frame: the inspect overlays follow the same settings, and the
    -- inspect frame can be open while the character panel is not.
    local inspectFrame = _G.InspectFrame
    if (PaperDollFrame and PaperDollFrame:IsShown())
        or (inspectFrame and inspectFrame:IsShown()) then
        self:RefreshSlotDisplays()
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
    local fontFace    = db.FontFace
    local fontOutline = db.FontOutline or "OUTLINE"
    KE:ApplyFont(fontString, fontFace, size, fontOutline)
end

function CP:UpdateItemLevelText()
    if not self:IsEnabled() then return end
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

-- Blizzard's own font on the two header strings, captured before KE first
-- overwrites it. Weak-keyed: never a field on a Blizzard frame.
--
-- Skipping the write is NOT enough to stand down here. EUI only re-anchors
-- these strings (CharacterSheet.lua) -- it never sets a font -- so
-- whatever KE applied while EUI's sheet was off survives into EUI's header and
-- no later refresh can release it. The stand-down has to hand back what it took.
local headerTextOriginals = setmetatable({}, { __mode = "k" })

-- withLayout: also capture width and word wrap, for the string whose layout KE
-- actually changes. CharacterLevelText is configured 220x24 in Blizzard's own
-- XML (PaperDollFrame.xml), so GetWidth() here reads a
-- real configured width, not a measurement of auto-sized text -- restoring it
-- is right. CharacterFrameTitleText only ever gets a font from us.
local function RememberHeaderText(fs, withLayout)
    if headerTextOriginals[fs] ~= nil then return end
    local record = {}
    -- The font OBJECT where there is one: restoring that also clears any
    -- explicit SetFont, which restoring file/height/flags by hand does not.
    record.fontObject = fs.GetFontObject and fs:GetFontObject() or nil
    if not record.fontObject then
        local file, height, flags = fs:GetFont()
        if not file then return end
        record.font = { file, height, flags }
    end
    if withLayout then
        record.width = fs:GetWidth()
        -- Not `x and x() or nil`: a legitimate false would collapse to nil
        -- there and the restore would silently skip it.
        if fs.CanWordWrap then record.wordWrap = fs:CanWordWrap() end
    end
    headerTextOriginals[fs] = record
end

local function RestoreHeaderText(fs)
    local original = headerTextOriginals[fs]
    if not original then return end
    headerTextOriginals[fs] = nil
    if original.fontObject then
        fs:SetFontObject(original.fontObject)
    else
        fs:SetFont(original.font[1], original.font[2], original.font[3])
    end
    if original.width then fs:SetWidth(original.width) end
    if original.wordWrap ~= nil then fs:SetWordWrap(original.wordWrap) end
end

function CP:StyleCharacterTexts()
    if ElvUILoaded() then return end

    local levelText = CharacterLevelText
    local nameText = CharacterFrameTitleText

    -- EllesmereUI re-anchors both strings into its own header, so re-fonting
    -- them from here is two addons fighting over the same FontStrings. The
    -- stats pane below is still ours to style -- EUI leaves those alone.
    if KE:EUIDrawsSlotElement("player", "headerText") then
        if levelText then RestoreHeaderText(levelText) end
        if nameText then RestoreHeaderText(nameText) end
    else
        if levelText then
            RememberHeaderText(levelText, true)   -- width + wrap change below
            self:ApplyFont(levelText, self.db.LevelTextSize or 12)
            levelText:SetWidth(0)
            levelText:SetWordWrap(true)
        end

        if nameText then
            RememberHeaderText(nameText)
            self:ApplyFont(nameText, self.db.NameTextSize or 12)
        end
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
    -- hook, which only fires when Blizzard re-renders the stats pane. Walk the live
    -- rows so a StatsFontSize change applies now instead of on next reopen.
    -- Calling PaperDollFrame_UpdateStats to force that re-render taints Blizzard's
    -- stat code, which then throws comparing UnitStat's secret buff values.
    local statsSize = self.db.StatsFontSize or 12
    if statsPane.statsFramePool and statsPane.statsFramePool.EnumerateActive then
        for row in statsPane.statsFramePool:EnumerateActive() do
            if row ~= statsPane.ItemLevelFrame then
                if row.Label then self:ApplyFont(row.Label, statsSize) end
                if row.Value then self:ApplyFont(row.Value, statsSize) end
            end
        end
    end
end

function CP:SetupStatTextHook()
    if ElvUILoaded() then return end
    if self._statTextHooked then return end
    self._statTextHooked = true

    hooksecurefunc("PaperDollFrame_SetLabelAndText", function(statFrame)
        if not CP:IsEnabled() then return end
        if CharacterStatsPane and statFrame == CharacterStatsPane.ItemLevelFrame then return end
        local statsSize = CP.db.StatsFontSize or 12
        if statFrame.Label then CP:ApplyFont(statFrame.Label, statsSize) end
        if statFrame.Value then CP:ApplyFont(statFrame.Value, statsSize) end
    end)
end

---------------------------------------------------------------------------------
-- Level Text Faction Indicator + Mythic+ Score Line
---------------------------------------------------------------------------------
function CP:UpdateLevelTextWithFaction()
    if not self:IsEnabled() then return end
    if ElvUILoaded() then return end

    local levelText = CharacterLevelText
    if not levelText then return end

    local text = levelText:GetText()
    if not text then return end

    -- Strip any prior suffix we added. Unconditional, and ahead of the EUI
    -- stand-down below, so handing the string back removes our tag instead of
    -- freezing it into EUI's header.
    text = text:gsub(" |c%x%x%x%x%x%x%x%x%([AH]%)|r$", "")

    if self.db.ShowFactionOnLevel and not KE:EUIDrawsSlotElement("player", "headerText") then
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
        if not CP:IsEnabled() then return end
        CP:UpdateLevelTextWithFaction()
        CP:UpdateRaceTextPosition()
    end)
end

-- Returns nil rather than "0" for an unscored character: an empty line reads
-- better than a zero, and the caller hides the string on nil.
local function DungeonScoreText()
    if not (C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore) then return nil end
    local score = C_ChallengeMode.GetOverallDungeonScore()
    if type(score) ~= "number" or score <= 0 then return nil end

    local color = C_ChallengeMode.GetDungeonScoreRarityColor
        and C_ChallengeMode.GetDungeonScoreRarityColor(score)
    if color and color.GenerateHexColor then
        -- The label stays uncoloured; only the number carries the rating colour.
        return "Mythic+ Score: |c" .. color:GenerateHexColor() .. score .. "|r"
    end
    return "Mythic+ Score: " .. score
end
CP._DungeonScoreText = DungeonScoreText

function CP:CreateRaceText()
    if self._raceText then return self._raceText end

    local text = PaperDollFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall2")
    text:SetPoint("TOP", CharacterLevelText, "BOTTOM", 0, 1)
    text:Hide()

    self._raceText = text
    return text
end

-- The score line hangs off the level string, which hangs off the name, so
-- showing or hiding it moves nothing above it. Re-anchoring is all this needs.
function CP:UpdateRaceTextPosition()
    self:ApplyHeaderCentering()
end

function CP:ShowRaceText()
    if not self:IsEnabled() then return end
    if ElvUILoaded() then return end
    if not self.db.ShowRaceText then return end
    -- EUI has already re-anchored the level string into its own header, so our
    -- line would land on top of its text. Stand down rather than fight over the
    -- anchor.
    if KE:EUIDrawsSlotElement("player", "headerText") then
        self:HideRaceText()
        return
    end

    local text = self:CreateRaceText()
    self:ApplyFont(text, self.db.LevelTextSize or 12)
    local scoreText = DungeonScoreText()
    if not scoreText then
        text:Hide()
        return
    end
    text:SetText(scoreText)
    text:Show()
    self:UpdateRaceTextPosition()
end

function CP:HideRaceText()
    if self._raceText then self._raceText:Hide() end
end

---------------------------------------------------------------------------------
-- Item Track Indicators
---------------------------------------------------------------------------------
-- Returns a WRAPPER, never an ITEM_TRACKS entry: the entries are a shared
-- constant, and writing the per-slot count onto one would leak that count onto
-- every other slot of the same track.
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
                    if text:find(track.keyword) then
                        local cur, max = text:match("(%d+)%s*/%s*(%d+)")
                        return { track = track, cur = cur, max = max }
                    end
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
                        return { track = track }
                    end
                end
            end
        end
    end

    return nil
end

-- The dirty key for everything a track wrapper can make a slot render. ONE
-- definition, used by the track indicator's dirty check. The count belongs in it
-- because an upgrade from 5/6 to 6/6 leaves the letter alone: a letter-only key
-- would skip that repaint, and under the merged layout it would also strand the
-- slot in the wrong one of the two layouts.
local function TrackDirtyKey(w)
    if not w then return nil end
    return (w.track and w.track.letter or "") .. "/" .. (w.cur or "") .. "/" .. (w.max or "")
end
CP._TrackDirtyKey = TrackDirtyKey

-- Capped means there is nothing left to report. No count at all counts as
-- capped: the progress display exists to show progress, and an item that does
-- not report any has none to show.
local function IsUpgradeCapped(w)
    if not (w and w.cur and w.max) then return true end
    local cur, max = tonumber(w.cur), tonumber(w.max)
    if not (cur and max) then return true end
    return cur >= max
end
CP._IsUpgradeCapped = IsUpgradeCapped

-- The track letter and the upgrade count are two independent user toggles over
-- one string. Either, both, or neither -- and neither means no span at all.
local function UpgradeSpan(w, showLetter, showUpgrade)
    if not (w and w.track) then return nil end
    local inner = ""
    if showLetter then inner = w.track.letter end
    if showUpgrade and w.cur and w.max then inner = inner .. w.cur .. "/" .. w.max end
    if inner == "" then return nil end
    local c = w.track.color or { 1, 1, 1 }
    return ("|cff%02x%02x%02x%s|r"):format(c[1] * 255, c[2] * 255, c[3] * 255, inner)
end
CP._UpgradeSpan = UpgradeSpan

-- THE decision, in ONE place, consulted by both render paths.
--
-- The corner letter and the merged item-level span are drawn by two different
-- functions, and the order they run in is not fixed -- some call sites do the
-- track first, some the detail first, and the inspect side differs again. So
-- neither may infer what the other did. Both call this instead.
--
-- Every condition here is one the corner path can answer as cheaply as the
-- detail path can. Item level being unreadable is deliberately NOT a condition:
-- when it is, the detail path still draws the span on its own, so the track is
-- never lost. Splitting this across the two sites is what made the corner stand
-- down while nothing replaced it whenever item levels were off or EUI owned
-- them.
local function MergeTrackIntoIlvl(db, w, euiOwnsIlvl, euiOwnsTrack)
    if not db then return false end
    if not db.ShowUpgradeProgress then return false end
    if not db.ShowSlotItemLevel then return false end
    if euiOwnsIlvl or euiOwnsTrack then return false end
    return not IsUpgradeCapped(w)
end
CP._MergeTrackIntoIlvl = MergeTrackIntoIlvl

-- The item level always sits nearest the icon, so the order flips with the
-- column. Extracted rather than inlined because the design names this ordering
-- as a decision to test, and a branch inside a render function cannot be
-- reached from a spec.
local function IlvlLine(base, span, isRight)
    if not span then return base end
    if isRight then return span .. " " .. base end
    return base .. " " .. span
end
CP._IlvlLine = IlvlLine

local function IlvlSpanOnLeft(slotID)
    return RIGHT_SLOTS[slotID] and true or false
end
CP._IlvlSpanOnLeft = IlvlSpanOnLeft

-- Weapons use a second centered line so two upgrade spans cannot meet between
-- the slots. Every other slot keeps the span inline with its item level.
local function SlotIlvlLines(slotID, base, span)
    if CENTER_SLOTS[slotID] then return base, span end
    if not base then return span, nil end
    return IlvlLine(base, span, IlvlSpanOnLeft(slotID)), nil
end
CP._SlotIlvlLines = SlotIlvlLines

-- Whether the track span this render drew is MISSING rather than absent, so the
-- next call must not short-circuit past it. Extracted for the same reason as the
-- helpers above: it is a guard, and a guard inside a render function cannot be
-- reached from a spec without faking the whole frame.
--
-- An empty slot reports no tooltip either, and pending it would re-render every
-- empty slot on every bag event, forever.
local function TrackPending(held, data)
    if not held then return nil end
    return (not (data and data.lines)) or nil
end
CP._TrackPending = TrackPending

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
    KE:ApplyFontToText(overlay.text, self.db.FontFace, self.db.TrackLetterSize or 12, "OUTLINE")
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
    -- but two readings of one thing on every slot is clutter. Suppressed only
    -- while EUI is actually drawing it on THIS frame: its
    -- showUpgradeTrack / inspectShowUpgradeTrack toggles turn it off separately,
    -- and then ours is the only one left. Bail before the tooltip read too --
    -- GetItemTrack allocates one per slot just to decide the letter.
    if KE:EUIDrawsSlotElement(unit, "track") then
        local d = FFD[slotFrame]
        if d and d.track then d.track:Hide() end
        -- Same reason as the warning stand-down: clear the key so a handback on
        -- an unchanged item redraws instead of matching the pre-stand-down one.
        if unit == "player" then
            local s = _slotState(slotID)
            s.trackLink, s.trackKey = nil, nil
        end
        return
    end

    -- One tooltip read serves both the dirty-check and the render below (the
    -- render previously re-fetched identical data a second time).
    local w = self:GetItemTrack(unit, slotID, data)

    -- Dirty-check (player path only): itemLink plus everything the render can
    -- show, via TrackDirtyKey, which owns the reason the count is in there.
    if unit == "player" then
        local s = _slotState(slotID)
        local link = GetInventoryItemLink(unit, slotID)
        local key = TrackDirtyKey(w)
        if s.trackLink == link and s.trackKey == key then return end
        s.trackLink, s.trackKey = link, key
    end

    local overlay = self:CreateTrackOverlay(slotFrame, slotID)

    -- While the item is still upgrading, the letter and its count move to the
    -- item-level detail row, so the corner stands down. Weapons use a separate
    -- upper line; other slots keep the span inline. Once capped, the corner is
    -- where the letter has always lived.
    --
    -- Asked of the SHARED predicate, never re-derived here. The detail path asks
    -- the same question with the same inputs, so the two cannot disagree and
    -- leave the track drawn nowhere.
    local merged = MergeTrackIntoIlvl(self.db, w,
        KE:EUIDrawsSlotElement(unit, "ilvl"), KE:EUIDrawsSlotElement(unit, "track"))

    if w and w.track and not merged then
        -- Re-apply font each update so a TrackLetterSize change is live.
        KE:ApplyFontToText(overlay.text, self.db.FontFace, self.db.TrackLetterSize or 12, "OUTLINE")
        overlay.text:SetText(w.track.letter)
        overlay.text:SetTextColor(w.track.color[1], w.track.color[2], w.track.color[3])
        overlay:Show()
    else
        overlay:Hide()
    end
end

-- The inspect half of every All-level function below. Its dirty state lives in
-- InspectPanel, keyed per GUID, so this file cannot reach it directly -- and
-- should not: hiding an inspect overlay without dropping that state left the
-- setting one-way there exactly as it did for the player keys.
local function InvalidateInspectSlots()
    local insp = KitnEssentials:GetModule("InspectPanel", true)
    if insp and insp.InvalidateSlotCache then insp:InvalidateSlotCache() end
end

local function RepaintInspectSlots()
    local frame = _G.InspectFrame
    if not (frame and frame:IsShown()) then return end
    local insp = KitnEssentials:GetModule("InspectPanel", true)
    if insp and insp:IsEnabled() then insp:UpdateAllInspectSlots() end
end

-- Settings-change entry point for both per-slot displays. The dirty checks in
-- UpdateSlotDetail and UpdateSlotTrackIndicator key on the ITEM, so a settings
-- change that leaves the item alone is invisible to them and the display keeps
-- whatever the previous settings drew -- turning one detail option off while
-- another stays on was the visible case. Dropping the caches first is what
-- makes the settings two-way.
--
-- Deliberately NOT folded into the All-level updaters below: those also run on
-- bag and equipment events, where the dirty check is the whole point.
function CP:RefreshSlotDisplays()
    if not self:IsEnabled() then return end
    wipe(_lastSlotState)
    InvalidateInspectSlots()
    if self.db.TrackIndicatorsEnabled then
        self:UpdateAllTrackIndicators()
    else
        self:HideAllTrackIndicators()
    end
    self:UpdateAllSlotDetails()   -- routes to HideAllSlotDetails when all off
end

function CP:UpdateAllTrackIndicators()
    if not self.db.TrackIndicatorsEnabled then return end
    for slotID, frameName in pairs(SLOT_FRAMES) do
        self:UpdateSlotTrackIndicator(_G[frameName], slotID, "player")
    end
    RepaintInspectSlots()
end

function CP:HideAllTrackIndicators()
    for slotID, frameName in pairs(SLOT_FRAMES) do
        local slotFrame = _G[frameName]
        local overlay = slotFrame and FFD[slotFrame] and FFD[slotFrame].track
        if overlay then overlay:Hide() end
        -- Hiding without clearing the key left the setting one-way: turning the
        -- indicators back on hit the unchanged-item short-circuit and the
        -- overlay stayed hidden until the item itself changed.
        local s = _slotState(slotID)
        s.trackLink, s.trackKey = nil, nil
    end
    for _, frameName in pairs(INSPECT_SLOT_FRAMES) do
        local slotFrame = _G[frameName]
        local overlay = slotFrame and FFD[slotFrame] and FFD[slotFrame].track
        if overlay then overlay:Hide() end
    end
    InvalidateInspectSlots()
end

function CP:SetupTrackIndicators()
    if not self:IsEnabled() then return end
    if not self.db.TrackIndicatorsEnabled then return end
    if self._trackIndicatorsHooked then return end
    self._trackIndicatorsHooked = true
    -- Track indicators register on PaperDollFrame OnShow via the combined
    -- HookCharacterPanel handler. No separate hook here.
end

---------------------------------------------------------------------------------
-- Slot Details (per-slot item level / enchant label / inline gem icons)
---------------------------------------------------------------------------------

-- Number of gem icons a slot can show inline (matches the 3-socket max).
local SLOT_DETAIL_MAX_GEMS = 3

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

-- Anchor the gem-icon row inline beside the ilvl text.
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
    local fontFace    = self.db.FontFace
    local fontSize    = self.db.SlotInfoFontSize or 11
    local fontOutline = self.db.FontOutline or "OUTLINE"

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

    if isCenter then
        detail.weaponSpanText = detail:CreateFontString(nil, "OVERLAY")
        KE:ApplyFont(detail.weaponSpanText, fontFace, fontSize, fontOutline)
        detail.weaponSpanText:SetShadowColor(0, 0, 0, 0)
    end

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

    -- Static anchors per slot side: enchant at the slot's
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
        detail.weaponSpanText:SetPoint("BOTTOM", detail.ilvlText, "TOP", 0, 1)
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
    -- The merged track span reads this too, so it belongs in the ownership
    -- stamp below: EUI's track toggle is independent of its item level one.
    local euiOwnsTrack   = KE:EUIDrawsSlotElement(unit, "track")
    -- Ownership is part of what this slot renders, so it has to be part of the
    -- dirty key below -- three elements means ownership can change while the
    -- item does not, and the item-only key cannot see that. Unlike the warning
    -- and track stand-downs, clearing the key on the way out is not enough here:
    -- those are all-or-nothing, this one keeps drawing whatever EUI left us.
    local ownKey = (euiOwnsEnchant and 1 or 0) + (euiOwnsIlvl and 2 or 0)
        + (euiOwnsGems and 4 or 0) + (euiOwnsTrack and 8 or 0)

    -- Nothing left for us to draw on this frame: bail before BOTH the dirty-check
    -- store and the tooltip read, and clear the key on the way out so a handback
    -- on an unchanged item redraws. FFD is indexed directly so a slot that never
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
        if unit == "player" then
            local s = _slotState(slotID)
            s.detailLink, s.detailEnchant, s.detailIlvl = nil, nil, nil
            s.detailTrackPending = nil
        end
        return
    end

    -- Dirty-check (player path only): itemLink + enchantID + ilvl + the EUI
    -- ownership stamp determine the rendered output. If all four match the
    -- previous render, skip the font re-apply + SetText + gem-icon work
    -- entirely. Inspect path goes unguarded here — its own invalidation lives
    -- in INSPECT_READY.
    if unit == "player" then
        local s = _slotState(slotID)
        local link = GetInventoryItemLink(unit, slotID)
        local enchantID = self:GetSlotEnchantID(unit, slotID)
        local ilvl = self:GetSlotItemLevel(unit, slotID)
        -- detailGemsPending: the previous render ran on unhydrated gem data
        -- (cold item cache), so the link/enchant/ilvl key is NOT sufficient —
        -- skip the short-circuit and re-scan until the gems resolve.
        -- detailTrackPending: same shape as detailGemsPending above. The item
        -- level string now carries the track span, and a cold item cache
        -- renders it without one. An actual upgrade rewrites the link and the
        -- item level, so the keys above catch it; only the unhydrated first
        -- render needs this, and re-reading the tooltip on every call to key on
        -- the track value instead would cost a read per slot per bag event.
        if s.detailLink == link and s.detailEnchant == enchantID and s.detailIlvl == ilvl
            and s.detailOwn == ownKey and not s.detailGemsPending
            and not s.detailTrackPending then
            return
        end
        s.detailLink, s.detailEnchant, s.detailIlvl = link, enchantID, ilvl
        s.detailOwn = ownKey
    end

    -- Fetch after the dirty check so a short-circuited call allocates nothing;
    -- both tooltip consumers below (enchant label, gem scan) share this read.
    data = data or C_TooltipInfo.GetInventoryItem(unit, slotID)

    local detail = self:CreateSlotDetail(slotFrame, slotID)
    local fontFace    = self.db.FontFace
    local fontSize    = self.db.SlotInfoFontSize or 11
    local fontOutline = self.db.FontOutline or "OUTLINE"

    -- Re-apply font each call so the size slider is live.
    KE:ApplyFont(detail.enchantText, fontFace, fontSize, fontOutline)
    KE:ApplyFont(detail.ilvlText, fontFace, fontSize, fontOutline)
    if detail.weaponSpanText then
        KE:ApplyFont(detail.weaponSpanText, fontFace, fontSize, fontOutline)
    end

    -- Enchant label (green). "No Enchant" stays with the warning feature.
    if self.db.ShowEnchantNames and not euiOwnsEnchant then
        local label = self:ResolveEnchantLabel(unit, slotID, data)
        detail.enchantText:SetText(label or "")
        detail.enchantText:SetShown(label ~= nil)
    else
        detail.enchantText:SetText("")
        detail.enchantText:Hide()
    end

    -- Item level, colored by the equipped item's quality. While the item is
    -- still upgrading, weapons put the track span on a separate upper line;
    -- other slots keep it inline. The item level retains its quality colour,
    -- while the span carries the track colour.
    if self.db.ShowSlotItemLevel and not euiOwnsIlvl then
        local lvl = self:GetSlotItemLevel(unit, slotID)

        local span
        local w = self:GetItemTrack(unit, slotID, data)
        if MergeTrackIntoIlvl(self.db, w, euiOwnsIlvl, euiOwnsTrack) then
            span = UpgradeSpan(w, self.db.TrackIndicatorsEnabled, true)
        end

        local base
        if lvl then
            local quality = GetInventoryItemQuality(unit, slotID)
            if quality then
                base = "|c" .. GetQualityHex(quality) .. lvl .. "|r"
            else
                base = tostring(lvl)
            end
        end

        local ilvlLine, weaponSpanLine = SlotIlvlLines(slotID, base, span)
        detail.ilvlText:SetText(ilvlLine or "")
        detail.ilvlText:SetShown(ilvlLine ~= nil)
        if detail.weaponSpanText then
            detail.weaponSpanText:SetText(weaponSpanLine or "")
            detail.weaponSpanText:SetShown(weaponSpanLine ~= nil)
        end
    else
        detail.ilvlText:SetText("")
        detail.ilvlText:Hide()
        if detail.weaponSpanText then
            detail.weaponSpanText:SetText("")
            detail.weaponSpanText:Hide()
        end
    end

    -- Gem icons inline beside the ilvl text (only scan socketable slots).
    -- Filled sockets show their gem (ShowSlotGems); empty sockets show a RED
    -- empty-socket icon (ShowMissingGems) — a missing-gem cue that replaces the
    -- old "No Gem" text (no room to stack a third text line).
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
        local s = _slotState(slotID)
        s.detailGemsPending = gemsPending or nil
        -- An unusable tooltip means any track span this render should have
        -- drawn is missing, not absent. Nothing else can change the span
        -- behind an unchanged key, so this is the whole of the track's
        -- staleness problem.
        --
        -- Gated on an equipped item. An EMPTY slot has no tooltip either, and
        -- without this gate it would pend forever and re-render on every bag
        -- event -- for every empty slot on the character.
        -- GetInventoryItemLink, not the `link` from the dirty check: that one is
        -- scoped to the block above and the inspect path never computes it. This
        -- is a cached string lookup, not another tooltip allocation.
        s.detailTrackPending = TrackPending(GetInventoryItemLink(unit, slotID), data)
    end

    -- Transparent container — element visibility controls what's drawn.
    detail:Show()
end

-- Event-driven single-slot refresh. Resolves the slot frame from the slotID,
-- builds the slot lookup map on first use, and runs each enabled update for
-- the affected slot only — avoids the 17-slot iteration that
-- UpdateAllSlotDetails / UpdateAllTrackIndicators do on a full refresh.
-- Each downstream Update* function performs its own dirty-check guard, so
-- calling RefreshSlot for an unchanged slot is effectively free.
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
    -- the shared tooltip read is skipped when neither will draw. This decides
    -- the READ, never the CALL: each function owns its own EUI stand-down, and
    -- that stand-down is what hides the leftover frame and clears the dirty key.
    -- Gating the call on ownership instead would leave KE's old text sitting on
    -- top of EUI's, stale, until something else refreshed the slot.
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

    -- The track overlay has no enable check of its own, so the setting is still
    -- the caller's to test. UpdateSlotDetail tests every one of its own.
    if self.db.TrackIndicatorsEnabled then
        self:UpdateSlotTrackIndicator(slotFrame, slotID, unit, data)
    end
    self:UpdateSlotDetail(slotFrame, slotID, unit, nil, data)
end

function CP:UpdateAllSlotDetails()
    if not (self.db.ShowSlotItemLevel or self.db.ShowEnchantNames or self.db.ShowSlotGems or self.db.ShowMissingGems) then
        self:HideAllSlotDetails()
        return
    end
    for slotID, frameName in pairs(SLOT_FRAMES) do
        self:UpdateSlotDetail(_G[frameName], slotID, "player")
    end
    RepaintInspectSlots()
end

function CP:HideAllSlotDetails()
    for slotID, frameName in pairs(SLOT_FRAMES) do
        local slotFrame = _G[frameName]
        local detail = slotFrame and FFD[slotFrame] and FFD[slotFrame].detail
        if detail then detail:Hide() end
        -- Same one-way-setting bug as the track overlays: clear the key so
        -- re-enabling a detail option redraws an item that has not changed.
        local s = _slotState(slotID)
        s.detailLink, s.detailEnchant, s.detailIlvl, s.detailOwn = nil, nil, nil, nil
    end
    for _, frameName in pairs(INSPECT_SLOT_FRAMES) do
        local slotFrame = _G[frameName]
        local detail = slotFrame and FFD[slotFrame] and FFD[slotFrame].detail
        if detail then detail:Hide() end
    end
    InvalidateInspectSlots()
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

-- Popup fill, shared by the gem and enchant popups. Theme.bgMedium is 60%
-- alpha, which is right for a panel sitting on another panel but washes out
-- over open world -- these two float over whatever is behind the character
-- sheet. Matched instead to the Damage Meter's own popup menus
-- (DamageMeter/SegmentMenu.lua), the closest thing KE already has to a
-- transient list over the world.
local POPUP_BG = { 0.05, 0.05, 0.05, 0.97 }

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
    -- needed.
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

    -- Debug trace: log when an inspected socketable slot's filled count CHANGES
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

-- Where the row's gem is RIGHT NOW, or nil if it has left the bags.
--
-- The popup row caches the bag position it was scanned from, and bags move
-- underneath an open popup. SocketInventoryItem resolves the DESTINATION
-- socket only, so trusting that cached position would pick up whatever now
-- sits there and socket it. Replace All already re-resolves per placement
-- (FindGemInBags above, and its comment); the single-gem click did not.
--
function CP:ResolveGemSource(gemData)
    if not gemData or not gemData.itemID then return nil end
    return FindGemInBags(gemData.itemID)
end

-- The socket button's whole click action, lifted out of the OnClick closure so
-- the REFUSAL is reachable, not just the resolver behind it. A spec that only
-- calls ResolveGemSource proves nothing about the call site: swapping it back
-- for the cached bagID/slotID there would leave every such test green.
--
-- Returns true only when the pickup was actually issued. The socket calls
-- themselves stay unasserted -- the tiered test policy leaves those to the
-- in-game smoke, and the missing-gem case returns before reaching any of them.
function CP:SocketGemFromPopup(gemData, targetSlotID, targetSocketIndex)
    local bag, slot = self:ResolveGemSource(gemData)
    if not bag then
        self:HideGemPopup()
        self:HideSlotHighlight()
        return false
    end
    SocketInventoryItem(targetSlotID)
    C_Container.PickupContainerItem(bag, slot)
    C_ItemSocketInfo.ClickSocketButton(targetSocketIndex)
    ClearCursor()
    AcceptSockets()
    CloseSocketInfo()
    if ItemSocketingFrame then HideUIPanel(ItemSocketingFrame) end
    self:HideGemPopup()
    self:HideSlotHighlight()
    C_Timer.After(0.1, function()
        if InCombatLockdown() then return end
        CP:RefreshSocketButtons()
    end)
    return true
end

-- The replace loop. Sequencing verified on 12.0.7: SocketInventoryItem opens
-- the socketing UI for the equipped item;
-- verify it actually opened (GetExistingSocketLink(1)) and that the staged gem
-- landed (GetNewSocketLink) before accepting — one 0.1s-delayed full retry
-- pass if either check fails, since the socket UI can lag the call by a frame.
-- API gotcha: gems cannot be staged into two sockets of
-- the SAME item in one open — close between consecutive matches on one slotID.
-- Uses the canonical C_ItemSocketInfo namespace (the bare globals
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
        -- Mirrors the enchant button's own OnEnter. Without it, sliding from the
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
    popup:SetBackdropColor(POPUP_BG[1], POPUP_BG[2], POPUP_BG[3], POPUP_BG[4])
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

    -- Replace All footer hint, on its own separated row. Text +
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
            CP:SocketGemFromPopup(self.gemData, self.targetSlotID, self.targetSocketIndex)
        end
    end)

    popup.buttons[index] = btn
    return btn
end

function CP:RefreshSocketButtons()
    -- Two socket-click timers land here a tenth of a second later, and the
    -- guards below cannot see a teardown: the container is only hidden, never
    -- released, and the preference key is untouched.
    if not self:IsEnabled() then return end
    if not self.socketContainer then return end
    if not self.db.SocketHelperEnabled then return end

    local db = self.db
    local buttonIndex = 1

    self.socketContainer:SetHeight(db.SocketButtonSize)

    -- EllesmereUI ships the same socket row along the bottom of its themed
    -- sheet (SocketPanel.lua: one icon per equipped socket, click for a bag-gem
    -- flyout). Only the SOCKETS stand down -- the enchant button below has no
    -- EUI equivalent, so the bar stays and carries it alone. The scan is skipped
    -- too: it walks every equipped item.
    if not KE:EUIDrawsSlotElement("player", "socketPanel") then
        local allSockets = self:ScanAllEquippedSockets()
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
    end

    for i = buttonIndex, #self.socketContainer.buttons do
        self.socketContainer.buttons[i]:Hide()
    end

    -- The gem popup anchors to a socket button. With none left showing it would
    -- hang there orphaned, so close it -- reachable both from EUI taking the
    -- sockets and from "only empty sockets" with everything gemmed.
    if buttonIndex == 1 then
        self:HideGemPopup()
        self:HideSlotHighlight()
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

    -- Bright red modifier keyword (|cffFC0316); a
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
-- pixel-identical to the in-game "ability ready" glow. No accent overlay
-- underneath.
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
    if not self:IsEnabled() then return end
    if not self.db.SocketHelperEnabled then return end
    if self._gemSocketHooked then return end
    self._gemSocketHooked = true

    self:CreateSocketContainer()
    self:CreateGemPopup()
    -- PaperDollFrame OnShow/OnHide + PLAYER_EQUIPMENT_CHANGED + BAG_UPDATE_DELAYED
    -- handlers are installed by the combined HookCharacterPanel.
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
-- enchant in your bags. Clicking a row applies the enchant outright where there
-- is exactly one slot it could mean; where there is more than one, or a slot we
-- cannot read, it leaves the cursor loaded for Blizzard's normal "now click the
-- item" flow and the player picks.

-- Enchanting profession icon. A named texture path rather than a bare fileID:
-- it says what it is and survives an asset renumber.
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

-- Walking this table with pairs() and returning on the first hit resolves
-- non-deterministically when a tooltip contains two keywords.
-- "Enchant 2H Weapon - ..." contains BOTH "2h weapon"
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

local WEAPON_SLOTS = { [16] = true, [17] = true }
local WEAPON_EQUIP_LOCS = {
    INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true,
    INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true,
    INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true,
}

-- THREE-VALUED, not boolean: `true` is definitely a target, `false` is
-- definitely not, and the string `"unknown"` is equipped-but-unreadable.
--
-- The third state is the whole point. Treating unreadable as a plain candidate
-- is NOT the safe reading it looks like: a slot we cannot read, sitting alone,
-- would then be the ONLY candidate, read as unambiguous, and get the enchant
-- spent on it -- the exact outcome the caution was meant to prevent. An unknown
-- must never be the thing that decides.
local function SlotHoldsEnchantTarget(slotID)
    local link = GetInventoryItemLink("player", slotID)
    if not link then return false end
    if not WEAPON_SLOTS[slotID] then return true end

    local ok, _, _, _, equipLoc = pcall(GetItemInfoInstant, link)
    if not ok or not KE:IsSafeValue(equipLoc) then return "unknown" end
    return WEAPON_EQUIP_LOCS[equipLoc] == true
end
CP._SlotHoldsEnchantTarget = SlotHoldsEnchantTarget

-- The single slot this enchant can only mean, or nil when it is a judgement
-- call. Two rings, a weapon in each hand, or nothing equipped all return nil.
local function UnambiguousEnchantSlot(targetSlots)
    if not targetSlots then return nil end
    local found
    for _, slotID in ipairs(targetSlots) do
        local holds = SlotHoldsEnchantTarget(slotID)
        -- ANY unreadable slot aborts the whole decision, even when it would
        -- otherwise have been the sole candidate. Refusing costs the player a
        -- click; guessing costs them the enchant.
        if holds == "unknown" then return nil end
        if holds then
            if found then return nil end
            found = slotID
        end
    end
    return found
end
CP._UnambiguousEnchantSlot = UnambiguousEnchantSlot

local function IsRingEnchant(targetSlots)
    if not targetSlots then return false end
    for _, slotID in ipairs(targetSlots) do
        if slotID == 11 or slotID == 12 then return true end
    end
    return false
end

-- Slots KE will not offer an enchant for, whatever the tooltip claims.
--
--   [7] legs -- armour kits, which do not apply reliably through this flow.
--
-- Head is NOT in here, and must not go back in: Midnight ships current helm
-- enchants. See BLOCKED_ENCHANT_ITEMS below for what actually fails.
local UNOFFERABLE_ENCHANT_SLOTS = { [7] = true }

-- Individual items that throw ADDON_ACTION_FORBIDDEN on UseContainerItem. The
-- call is blocked before it does anything, so there is nothing to catch -- the
-- only way to keep the error out of the player's log is not to offer the row.
--
--   [210494] Incandescent Essence
--
-- This is a blacklist rather than a rule because the in-game data gives no rule
-- to write. Probed in game, every enchant in one bag at once:
--
--   itemID  name                                        subclass  expansion
--   244007  Enchant Helm - Empowered Rune of Avoidance   0         11   works
--   210494  Incandescent Essence                         0          9   BLOCKED
--   243977  Enchant Chest - Mark of the Worldsoul        4         11   works
--   243959  Enchant Ring - Zul'jin's Mastery            10         11   works
--
-- Same class, and the same subclass as the helm enchant that works, so neither
-- separates them. Expansion does, but "older than current" is not the same
-- claim as "blocked" -- plenty of old enchants still apply to old gear, and
-- filtering on it would hide them. One confirmed item, one entry.
local BLOCKED_ENCHANT_ITEMS = {
    [210494] = true,
}

-- True when EVERY slot the enchant could target is unofferable. A weapon
-- enchant ({16, 17}) or a ring enchant ({11, 12}) keeps its offerable half.
local function IsUnofferableEnchant(targetSlots)
    if not targetSlots then return true end
    for _, slotID in ipairs(targetSlots) do
        if not UNOFFERABLE_ENCHANT_SLOTS[slotID] then return false end
    end
    return true
end
CP._IsUnofferableEnchant = IsUnofferableEnchant

-- Both refusals in one question, asked once per bag item and again on click.
local function IsOfferableEnchant(itemID, targetSlots)
    if BLOCKED_ENCHANT_ITEMS[itemID] then return false end
    return not IsUnofferableEnchant(targetSlots)
end
CP._IsOfferableEnchant = IsOfferableEnchant

function CP:ScanBagsForEnchants()
    wipe(enchantCache)
    local NUM_BAG_SLOTS = NUM_BAG_SLOTS or 4
    -- Enum with a literal fallback (matches ScanBagsForGems above), never the
    -- legacy LE_ITEM_CLASS_ITEM_ENHANCEMENT global.
    local ITEM_ENHANCEMENT = (Enum and Enum.ItemClass and Enum.ItemClass.ItemEnhancement) or 8
    for bag = 0, NUM_BAG_SLOTS do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(info.itemID)
                if classID == ITEM_ENHANCEMENT then
                    local targetSlots = GetEnchantTargetSlots(info.hyperlink)
                    if targetSlots and IsOfferableEnchant(info.itemID, targetSlots) then
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
    popup:SetBackdropColor(POPUP_BG[1], POPUP_BG[2], POPUP_BG[3], POPUP_BG[4])
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
            -- 40px right of the row cleared the popup but read as detached.
            -- 8px keeps the gap without the drift.
            GameTooltip:SetOwner(button, "ANCHOR_RIGHT", 8, 0)
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
    -- Second line of defence on the blacklist. ScanBagsForEnchants already
    -- keeps these out of the popup, but a row built before the list is only
    -- rebuilt on a refresh, and the whole point is that this call cannot fail
    -- quietly -- it puts an error in the player's log with our name on it.
    if not IsOfferableEnchant(enchantData.itemID, enchantData.targetSlots) then
        return false
    end
    -- ...and the id we just vetted has to be the id we act on. The row caches
    -- the bag and slot it was scanned from, but bags move underneath an open
    -- popup: BAG_UPDATE_DELAYED refreshes the socket bar and never rebuilds
    -- this list, so a sort can slide a different item into that exact slot.
    -- Without this the vetted id passes and UseContainerItem fires on whatever
    -- is there now -- including the one item the blacklist exists to stop.
    local live = C_Container.GetContainerItemInfo(enchantData.bagID, enchantData.slotID)
    if not live or live.itemID ~= enchantData.itemID then
        self:HideEnchantPopup()
        self:HideSlotHighlight()
        return false
    end
    -- REFUSE unless the cursor is idle in BOTH senses, before doing anything at
    -- all. Auto-apply reads "a spell is now waiting for a target" as proof our
    -- enchant started, and that reading is only sound if nothing was waiting
    -- beforehand.
    --
    --   * An ITEM already held: UseContainerItem on a full cursor does not
    --     reliably start the enchant, and PickupInventoryItem would then EQUIP
    --     that item into the slot, swapping the player's weapon for a bag item.
    --   * A SPELL already targeting: if our UseContainerItem then silently does
    --     nothing, the earlier spell keeps SpellIsTargeting true and the pickup
    --     fires with no enchant pending at all -- the exact unequip this guard
    --     exists to stop.
    --
    -- Refusing costs one re-click after the player finishes what they started.
    if CursorHasItem() or (SpellIsTargeting and SpellIsTargeting()) then
        KE:Print("Cannot enchant while the cursor is busy")
        return false
    end

    -- Namespaced form, never the bare UseContainerItem global: Blizzard's own
    -- code uses C_Container everywhere, so the bare name is at best a
    -- deprecated shim. This starts the enchant.
    C_Container.UseContainerItem(enchantData.bagID, enchantData.slotID)

    -- Where there is exactly one item it could mean, finish the job.
    -- PickupInventoryItem is what Blizzard's own paperdoll slot OnClick calls
    -- with a loaded cursor, and this runs inside a real button press, which is
    -- what such a call needs. Where it is a judgement call -- two rings, a
    -- weapon in each hand, a target we could not read -- the cursor is left
    -- loaded and the player picks.
    --
    -- SpellIsTargeting is the signal, NOT CursorHasItem: using an enchant starts
    -- a spell waiting for a target rather than putting an item on the cursor. The
    -- refusal above established it was FALSE a moment ago, so true here means OUR
    -- call set it. Without the check PickupInventoryItem picks UP the equipped
    -- item when nothing is pending, unequipping a weapon.
    --
    -- The cursor is re-checked too. UseContainerItem can load the cursor rather
    -- than start a targeting spell, and equipping that into the slot is the same
    -- accident the entry refusal prevents.
    --
    -- Overwriting an existing enchant destroys the old one, so that
    -- confirmation stays Blizzard's to raise and the player's to answer.
    local only = UnambiguousEnchantSlot(enchantData.targetSlots)
    local pending = (SpellIsTargeting and SpellIsTargeting()) and not CursorHasItem()
    if only and pending then
        PickupInventoryItem(only)
    end

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

-- Called by the profile manager's rebind pass before any enable or disable
-- runs. Without it this module keeps the OUTGOING profile table, which AceDB
-- has already stripped default-equal keys out of by then.
function CP:UpdateDB()
    self.db = KE.db.profile.CharacterPanel
end

function CP:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

-- The inspect overlays are a separate AceModule with its own lifecycle, so the
-- user switch drives Enable/Disable rather than a draw flag. Absent means on,
-- so a profile written before the switch existed keeps what it had.
function CP:ApplyInspectPanelState()
    local insp = KitnEssentials:GetModule("InspectPanel", true)
    if not insp then return end
    -- `IsEnabled()` for the master, not `db.Enabled`. `CP:Disable()` is reachable
    -- without the key changing, so reading the key here would let a later GUI
    -- callback wake InspectPanel while CharacterPanel itself is disabled.
    if self:IsEnabled() and self.db.InspectPanelEnabled ~= false then
        insp:Enable()
    else
        insp:Disable()
    end
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
    self:SetupWiderFrame()

    -- Warm the gem cache during the login loading screen (see PrimeGemCache).
    -- AceEvent unregisters automatically on module disable.
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "PrimeGemCache")
    self:RegisterEvent("CHALLENGE_MODE_COMPLETED", "ShowRaceText")

    -- Score line: if the character pane is already shown when the module
    -- enables (e.g. toggled on with the pane open), the PaperDollFrame
    -- OnShow hook installed above won't fire on this path. Register events +
    -- force one refresh inline.
    if PaperDollFrame and PaperDollFrame:IsShown() then
        if self.eventFrame then
            self.eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
            self.eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
            self.eventFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
        end
        UpdateDisplay()                                   -- warnings
        self:RefreshSlotDisplays()
    end

    self:ApplySettings()
end

function CP:OnDisable()
    self:ClearAll()                                       -- warnings clear
    if self.eventFrame then self.eventFrame:UnregisterAllEvents() end
    wipe(_lastSlotState)
    wipe(_pendingGemLoads)
    wipe(_gemLoadAttempts)
    -- AceHook removes the module's hooks on disable, so the latch that says
    -- "already hooked" must go with them or re-enable silently skips the
    -- reinstall.
    self._decimalIlvlHooked = nil
    self:DisableGemSocketHelper()
    self:HideAllTrackIndicators()
    self:HideAllSlotDetails()
    self:HideRaceText()
    RestoreCharacterBackground()
    -- Same shape as the line above: undo a geometry change this module made.
    -- A no-op unless the frame is up and we actually widened it.
    ApplyWiden()
    self:ApplyHeaderCentering()
    updatePending = false

    -- Cascade to InspectPanel; it owns its own state (queue, inspectUpdatePending,
    -- event frame, ilvl FontString) and teardown.
    local insp = KitnEssentials:GetModule("InspectPanel", true)
    if insp then insp:Disable() end
end

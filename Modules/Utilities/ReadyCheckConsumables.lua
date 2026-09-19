-- ╔══════════════════════════════════════════════════════════╗
-- ║  ReadyCheckConsumables.lua                               ║
-- ║  Module: Ready Check Consumables                         ║
-- ║  Purpose: On ready check, attaches a row of clickable    ║
-- ║           consumable icons (food, flask, weapon          ║
-- ║           enhancement MH/OH, augment rune, healthstone,  ║
-- ║           Warlock Soulstone) to the ready check popup.   ║
-- ║           Icons show ready/missing status and remaining  ║
-- ║           buff duration. Click uses the item via         ║
-- ║           SecureActionButton.                            ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class ReadyCheckConsumables: AceModule, AceEvent-3.0
local RCC = KitnEssentials:NewModule("ReadyCheckConsumables", "AceEvent-3.0")

local CreateFrame           = CreateFrame
local string_format         = string.format
local math_ceil             = math.ceil
local pairs                 = pairs
local ipairs                = ipairs
local table_sort            = table.sort
local GetTime               = GetTime
local InCombatLockdown      = InCombatLockdown
local UnitClass             = UnitClass
local UnitIsUnit            = UnitIsUnit
local UnitExists            = UnitExists
local UnitIsDeadOrGhost     = UnitIsDeadOrGhost
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local GetUnitName           = GetUnitName
local IsInRaid              = IsInRaid
local IsInGroup             = IsInGroup
local GetItemCount          = C_Item.GetItemCount
local GetItemInfo           = C_Item.GetItemInfo
local GetInventoryItemID    = GetInventoryItemID
local GetItemInfoInstant    = C_Item.GetItemInfoInstant
local GetTemporaryEnchantmentInfo = C_PaperDollInfo.GetTemporaryEnchantmentInfo
local GetSpecialization     = C_SpecializationInfo.GetSpecialization
local GetSpecializationInfo = C_SpecializationInfo.GetSpecializationInfo
local C_Spell               = C_Spell
local C_UnitAuras           = C_UnitAuras
local C_Item                = C_Item
-- issecretvalue is accessed via KE:IsSafeValue / KE:IsSecretValue helpers
-- (see Core/Secret.lua) — no module-local alias needed here.

-- LibCustomGlow for pixel-glow hints (e.g. "rune in bags but not active").
-- Optional dependency — module degrades gracefully if missing.
local LCG = LibStub("LibCustomGlow-1.0", true)

local DEBUG_RCC = false

---------------------------------------------------------------------------------
-- Constants — Slot Layout
---------------------------------------------------------------------------------

-- Logical slot indices (7 slots; enchanting kit category dropped — does not exist in Midnight).
-- Physical display order is set dynamically in UpdateAllIcons (off-hand enchant
-- slot is hidden when the player has no OH weapon equipped, similar to MRT).
local SLOT_FOOD      = 1
local SLOT_FLASK     = 2
local SLOT_OIL       = 3   -- main-hand weapon enhancement  (inv slot 16: oil/stone/ammo)
local SLOT_OILOH     = 4   -- off-hand weapon enhancement   (inv slot 17)
local SLOT_RUNE      = 5   -- augment rune
local SLOT_HS        = 6   -- healthstone
local SLOT_CLASS     = 7   -- class-specific (Warlock Soulstone; hidden for other classes)

local NUM_SLOTS = 7

-- Placeholder icons shown before the specific consumable is known.
-- Actual icons are resolved per-slot from item data in UpdateAllIcons.
local DEFAULT_ICONS = {
    [SLOT_FOOD]   = 136000,   -- generic food icon
    [SLOT_FLASK]  = 7548902,  -- flask placeholder
    [SLOT_OIL]    = 7548987,  -- weapon oil placeholder (Midnight)
    [SLOT_OILOH]  = 7548942,   -- off-hand enhancement placeholder
    [SLOT_RUNE]   = 4549099,  -- Midnight augment rune
    [SLOT_HS]     = 538745,   -- healthstone
    [SLOT_CLASS]  = 136210,   -- class item placeholder
}

-- Per-slot db toggle keys (consumed by _ComputeVisibility via direct db key access).
-- Kept here only for reference — _ComputeVisibility reads these keys by hardcoded name
-- since it also needs per-slot contextual logic (OH weapon presence, class match).
-- Keys: ShowFood, ShowFlask, ShowWeaponOil, ShowOffHandOil, ShowAugmentRune,
--       ShowHealthstone, ShowClassItem.

---------------------------------------------------------------------------------
-- Consumable Data Tables (Midnight 12.0)
---------------------------------------------------------------------------------
-- To update for a new raid tier / season, edit these tables directly.
-- Each is keyed by the identifier most relevant to its detection API.

-- Food buff spell IDs → stat amount (primary stat or highest-secondary).
-- Same spell ID may be shared by multiple items (feasts + matching single-serve food).
-- Feasts additionally grant +98 Stamina via a separate stamina aura.
-- "Hearty" variants persist through death — a gameplay property, not a quality tier.
-- Format to add entries later:
--   [spellID] = amount,  -- Item name(s) (stat type / feast or single / hearty or regular)
local FOOD_BUFFS = {
    -- Feasts (+98 Stam)
    [1232585] = 50,   -- Harandar Celebration / Silvermoon Parade (primary; also Royal Roast / Impossible Royal Roast)
    [1232086] = 65,   -- Quel'dorei Medley (highest secondary)
    [1232087] = 65,   -- Blooming Feast (highest secondary)
    -- Hearty Feasts (+98 Stam, persists through death)
    [1285644] = 50,   -- Hearty Harandar Celebration / Hearty Silvermoon Parade (primary)
    [1232076] = 65,   -- Hearty Quel'dorei Medley (highest secondary)
    [1232078] = 65,   -- Hearty Blooming Feast (highest secondary)
    -- Regular Food
    [1284616] = 65,   -- Flora Frenzy (highest secondary)
    [1284617] = 65,   -- Champion's Bento (highest secondary)
    [1294727] = 50,   -- Impossible Royal Roast / Royal Roast (primary)
    -- Hearty Food (persists through death)
    [1233724] = 50,   -- Hearty Impossible Royal Roast / Hearty Royal Roast (primary)
    [1233703] = 65,   -- Hearty Flora Frenzy / Hearty Champion's Bento (highest secondary)
}

-- Subset of FOOD_BUFFS whose active aura persists through death (for tooltip annotation).
local HEARTY_FOOD_BUFFS = {
    [1285644] = true,
    [1232076] = true,
    [1233724] = true,
    [1233703] = true,
    [1232078] = true
}

-- Weapon enhancements — unified table for oils, weapon stones, and ammo mods.
-- All three apply as temporary enchants, so C_PaperDollInfo.GetTemporaryEnchantmentInfo
-- reports them uniformly without a secondary confirmation click.
-- Keyed by enchant ID (enchantID in the returned TemporaryItemEnchantInfo).
-- Rank 1 = lower quality craft, Rank 2 = higher quality craft (some have rank 2 = lower ID).
local WEAPON_ENHANCEMENTS = {
    -- Thalassian Phoenix Oil
    [8051] = { item = 243733, kind = "oil",   rank = 1, name = "Thalassian Phoenix Oil"  },
    [8052] = { item = 243734, kind = "oil",   rank = 2, name = "Thalassian Phoenix Oil"  },
    -- Refulgent Whetstone
    [7906] = { item = 237370, kind = "stone", rank = 1, name = "Refulgent Whetstone"      },
    [7905] = { item = 237371, kind = "stone", rank = 2, name = "Refulgent Whetstone"      },
    -- Refulgent Weightstone
    [7907] = { item = 237367, kind = "stone", rank = 1, name = "Refulgent Weightstone"    },
    [7908] = { item = 237369, kind = "stone", rank = 2, name = "Refulgent Weightstone"    },
    -- Laced Zoomshots
    [8608] = { item = 257749, kind = "ammo",  rank = 1, name = "Laced Zoomshots"          },
    [8609] = { item = 257750, kind = "ammo",  rank = 2, name = "Laced Zoomshots"          },
    -- Weighted Boomshots
    [8610] = { item = 257751, kind = "ammo",  rank = 1, name = "Weighted Boomshots"       },
    [8611] = { item = 257752, kind = "ammo",  rank = 2, name = "Weighted Boomshots"       },
}

-- Augment Runes — keyed by buff spell ID for aura detection.
-- Multiple tiers tracked because older-expansion runes may still be used:
--   priority 1 = Midnight single-use (preferred when available)
--   priority 2 = DF Unlimited (currently strongest unlimited)
--   priority 3 = TWW Unlimited (secondary unlimited)
-- TODO: Future Midnight Unlimited rune (expected in a later season) — add as priority 0 when released.
local AUGMENT_RUNES = {
    [1264426] = { item = 259085, name = "Void-Touched Augment Rune", tier = "MN",  unlimited = false, priority = 1 },
    [393438]  = { item = 211495, name = "Dreambound Augment Rune",   tier = "DF",  unlimited = true,  priority = 2 },
    [1234969] = { item = 243191, name = "Ethereal Augment Rune",     tier = "TWW", unlimited = true,  priority = 3 },
}

-- Flasks / Phials — keyed by item ID.
-- 4 stat flasks × 2 ranks × 2 forms (regular + Fleeting Cauldron variant) = 16 items.
local FLASKS = {
    -- Mastery — Flask of the Magisters (buff 1235108)
    [241323] = { stat = "mastery", rank = 1, fleeting = false, buff = 1235108, name = "Flask of the Magisters" },
    [241322] = { stat = "mastery", rank = 2, fleeting = false, buff = 1235108, name = "Flask of the Magisters" },
    [245932] = { stat = "mastery", rank = 1, fleeting = true,  buff = 1235108, name = "Flask of the Magisters (Fleeting)" },
    [245933] = { stat = "mastery", rank = 2, fleeting = true,  buff = 1235108, name = "Flask of the Magisters (Fleeting)" },
    -- Haste — Flask of the Blood Knights (buff 1235110)
    [241325] = { stat = "haste",   rank = 1, fleeting = false, buff = 1235110, name = "Flask of the Blood Knights" },
    [241324] = { stat = "haste",   rank = 2, fleeting = false, buff = 1235110, name = "Flask of the Blood Knights" },
    [245930] = { stat = "haste",   rank = 1, fleeting = true,  buff = 1235110, name = "Flask of the Blood Knights (Fleeting)" },
    [245931] = { stat = "haste",   rank = 2, fleeting = true,  buff = 1235110, name = "Flask of the Blood Knights (Fleeting)" },
    -- Crit — Flask of the Shattered Sun (buff 1235111)
    [241327] = { stat = "crit",    rank = 1, fleeting = false, buff = 1235111, name = "Flask of the Shattered Sun" },
    [241326] = { stat = "crit",    rank = 2, fleeting = false, buff = 1235111, name = "Flask of the Shattered Sun" },
    [245928] = { stat = "crit",    rank = 1, fleeting = true,  buff = 1235111, name = "Flask of the Shattered Sun (Fleeting)" },
    [245929] = { stat = "crit",    rank = 2, fleeting = true,  buff = 1235111, name = "Flask of the Shattered Sun (Fleeting)" },
    -- Versatility — Flask of Thalassian Resistance (buff 1235057)
    [241321] = { stat = "vers",    rank = 1, fleeting = false, buff = 1235057, name = "Flask of Thalassian Resistance" },
    [241320] = { stat = "vers",    rank = 2, fleeting = false, buff = 1235057, name = "Flask of Thalassian Resistance" },
    [245927] = { stat = "vers",    rank = 1, fleeting = true,  buff = 1235057, name = "Flask of Thalassian Resistance (Fleeting)" },
    [245926] = { stat = "vers",    rank = 2, fleeting = true,  buff = 1235057, name = "Flask of Thalassian Resistance (Fleeting)" },
}

-- Flask buff spell IDs (4 total; one per stat line). Keyed for O(1) aura scan lookup.
local FLASK_BUFFS = {
    [1235108] = "mastery",  -- Flask of the Magisters
    [1235110] = "haste",    -- Flask of the Blood Knights
    [1235111] = "crit",     -- Flask of the Shattered Sun
    [1235057] = "vers",     -- Flask of Thalassian Resistance
}

-- Per-spec flask stat priority, [specID] = { primaryStat, secondaryStat? }.
-- Meta defaults, edited per tier; only consulted while db.LastFlaskStat has
-- nothing stocked, so a player's own flask choice always outranks them.
local SPEC_FLASK_PRIORITY = {
    -- Death Knight
    [250]  = { "vers",    "crit"    },  -- Blood
    [251]  = { "mastery", "crit"    },  -- Frost
    [252]  = { "crit",    "mastery" },  -- Unholy
    -- Demon Hunter
    [577]  = { "crit",    "mastery" },  -- Havoc
    [581]  = { "haste",   "vers"    },  -- Vengeance
    [1480] = { "haste",   "mastery" },  -- Devourer
    -- Druid
    [102]  = { "mastery", "crit"    },  -- Balance
    [103]  = { "mastery", "haste"   },  -- Feral
    [104]  = { "haste",   "vers"    },  -- Guardian
    [105]  = { "haste",   "mastery" },  -- Restoration
    -- Evoker
    [1467] = { "crit",    "haste"   },  -- Devastation
    [1468] = { "haste",   "mastery" },  -- Preservation
    [1473] = { "crit",    "haste"   },  -- Augmentation
    -- Hunter
    [253]  = { "mastery", "crit"    },  -- Beast Mastery
    [254]  = { "crit",    "mastery" },  -- Marksmanship
    [255]  = { "mastery", "crit"    },  -- Survival
    -- Mage
    [62]   = { "mastery", "vers"    },  -- Arcane
    [63]   = { "mastery", "haste"   },  -- Fire
    [64]   = { "crit",    "mastery" },  -- Frost
    -- Monk
    [268]  = { "vers",    "crit"    },  -- Brewmaster
    [270]  = { "haste",   "crit"    },  -- Mistweaver
    [269]  = { "crit",    "mastery" },  -- Windwalker
    -- Paladin
    [65]   = { "mastery", "haste"   },  -- Holy
    [66]   = { "haste",   "crit"    },  -- Protection
    [70]   = { "mastery", "crit"    },  -- Retribution
    -- Priest
    [256]  = { "crit",    "haste"   },  -- Discipline
    [257]  = { "crit",    "vers"    },  -- Holy
    [258]  = { "mastery", "haste"   },  -- Shadow
    -- Rogue
    [259]  = { "crit",    "haste"   },  -- Assassination
    [260]  = { "haste",   "crit"    },  -- Outlaw
    [261]  = { "mastery", "haste"   },  -- Subtlety
    -- Shaman
    [262]  = { "mastery", "crit"    },  -- Elemental
    [263]  = { "haste",   "mastery" },  -- Enhancement
    [264]  = { "crit",    "vers"    },  -- Restoration
    -- Warlock
    [265]  = { "crit",    "mastery" },  -- Affliction
    [266]  = { "crit",    "haste"   },  -- Demonology
    [267]  = { "crit",    "mastery" },  -- Destruction
    -- Warrior
    [71]   = { "crit",    "haste"   },  -- Arms
    [72]   = { "mastery", "haste"   },  -- Fury
    [73]   = { "haste",   "mastery" },  -- Protection
}

-- The flask click order: rank desc, then Fleeting before personal (the
-- cauldron flask expires with the raid, the bought one keeps), then stat
-- alphabetical, then itemID so the order is strict for table.sort. Every
-- flask pick walks FLASKS_SORTED, so pairs() order never decides a tie.
local function FlaskBefore(a, b)
    local da, db = FLASKS[a], FLASKS[b]
    local ra, rb = da.rank or 1, db.rank or 1
    if ra ~= rb then return ra > rb end
    if da.fleeting ~= db.fleeting then return da.fleeting == true end
    if da.stat ~= db.stat then return da.stat < db.stat end
    return a < b
end

local FLASKS_SORTED = {}
do
    for itemID in pairs(FLASKS) do
        FLASKS_SORTED[#FLASKS_SORTED + 1] = itemID
    end
    table_sort(FLASKS_SORTED, FlaskBefore)
end
-- Spec seams.
RCC._FlaskBefore = FlaskBefore
RCC._FlaskOrder = FLASKS_SORTED

-- Healthstones — keyed by item ID.
-- 5512: standard healthstone, craftable/droppable for any class to carry.
-- 224464: Demonic Healthstone — a warlock-only talent upgrade that allows multiple uses in combat.
local HEALTHSTONES = {
    [5512]   = { warlockOnly = false, name = "Healthstone"         },
    [224464] = { warlockOnly = true,  name = "Demonic Healthstone" },
}

-- Class slot — Warlock Soulstone (custom, NOT MRT parity).
-- MRT's real class slot is an Enhancement Shaman weapon imbue button (spell 192106);
-- we intentionally skip that and replace it with Warlock Soulstone tracking because
-- that's the practical raid use case (pre-pull stone on a Mass-Res healer for wipe
-- protection — healer self-res's from the stone, then Mass Res's the rest of the raid).
-- Slot hidden entirely for all non-Warlock classes.
--
-- Detection: spell cooldown on 20707. If the spell is on CD, the Warlock cast it
-- recently → someone in the raid has a Soulstone. Not as accurate as a raid-wide
-- aura scan (which would require full inspection logic), but
-- simple and sufficient — a Warlock isn't expected to recast Soulstone during its
-- CD window, so "spell on CD" ≈ "someone is stoned".
--
-- Click target priority: mouseover friendly → target friendly → self.
-- Self fallback prevents wasted casts if no appropriate target is hovered.
--- macrotext is `string | function(self) -> string`. Functions are invoked at
--- UpdateClassSlot time so the macrotext can be re-derived from world state
--- (used by Warlock Soulstone for healer-targeting priority chain).
local CLASS_SLOT = {
    WARLOCK = {
        spellID   = 20707,
        name      = "Soulstone",
        macrotext = function(rcc) return rcc:_BuildSoulstoneMacrotext() end,
    },
}

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------

RCC.frame       = nil   -- KE_ReadyCheckConsumables container
RCC.buttons     = {}    -- [1..NUM_SLOTS] button frames
RCC.previewFrame   = nil   -- KE_ReadyCheckConsumables_Preview container (settings preview only)
RCC.previewButtons = nil   -- [1..NUM_SLOTS] preview stubs; no click overlays
RCC.db          = nil
RCC.stateDriverActive = false  -- true while the combat state driver is registered (see _EnableStateDriver)
RCC._refreshPending = nil      -- true while a coalesced repaint waits for the next frame (see RequestRefresh)
RCC._visibility = {}           -- [1..NUM_SLOTS] the real row's visible set, rebuilt in place each repaint

-- Sticky last-target for the Warlock CLASS slot (Soulstone). Holds the name
-- of the most recently confirmed Soulstone recipient so the click macro keeps
-- nominating the same healer after the aura drops (consumed/expired).
-- Not persisted to SavedVariables — wiped on /reload, regenerates on the next live scan.
-- Pruned in _GetSoulstonedTarget when the cached name is no longer in group.
RCC._lastSoulstoneTarget = nil

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------

function RCC:UpdateDB()
    self.db = KE.db.profile.ReadyCheckConsumables
end

---------------------------------------------------------------------------------
-- Secure State Driver Lifecycle
---------------------------------------------------------------------------------
-- The combat state driver is registered only while a ready check is displayed
-- (ShowFrame -> _EnableStateDriver) and torn down when it ends (HideFrame ->
-- _DisableStateDriver). Between ready checks it does not run, so the secure
-- frame stops costing per-frame state-driver evaluation.

--- Registers the secure combat state driver. Idempotent via stateDriverActive.
--- Only called from ShowFrame, which is OOC-guaranteed by its InCombatLockdown
--- guard, so RegisterStateDriver never runs in lockdown.
function RCC:_EnableStateDriver()
    if self.stateDriverActive then return end
    if not self.frame or not self.frame.stateFrame then return end
    RegisterStateDriver(self.frame.stateFrame, "combat", "[combat] hide; [nocombat] show")
    self.stateDriverActive = true
    if DEBUG_RCC then KE:Print("[RCC] state driver registered.") end
end

--- Unregisters the state driver. Only called from HideFrame's out-of-combat
--- path (the in-combat path queues the whole hide on KE:RunAfterCombat,
--- which re-enters HideFrame out of combat). Passing no attribute makes the
--- manager drop its entry for the frame instead of keeping an empty one in
--- its update loop.
function RCC:_DisableStateDriver()
    if not self.stateDriverActive then return end
    if self.frame and self.frame.stateFrame then
        UnregisterAttributeDriver(self.frame.stateFrame)
    end
    self.stateDriverActive = false
    if DEBUG_RCC then KE:Print("[RCC] state driver unregistered.") end
end

--- _BuildIconRow
--- Creates the 7 visual icon stubs under `parent` and returns them indexed
--- 1..NUM_SLOTS. Chains them left to right on `parent`; _LayoutRow re-anchors
--- the visible ones. Builds no secure frame, so both the real row and the
--- settings preview use it.
function RCC:_BuildIconRow(parent)
    local db = self.db
    local iconSize = db.IconSize or 32
    local spacing  = db.IconSpacing or 4
    local buttons = {}

    for i = 1, NUM_SLOTS do
        -- Outer container frame (non-secure; houses the icon texture and text)
        local btn = CreateFrame("Frame", nil, parent)
        btn:SetSize(iconSize, iconSize)
        if i == 1 then
            btn:SetPoint("LEFT", parent, "LEFT", 0, 0)
        else
            btn:SetPoint("LEFT", buttons[i - 1], "RIGHT", spacing, 0)
        end

        -- Icon texture (ARTWORK layer, default sublevel 0)
        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        if DEFAULT_ICONS[i] then
            tex:SetTexture(DEFAULT_ICONS[i])
        end
        -- Standard KE icon zoom (default 0.3 = 7.5% crop) per icon standard memory
        KE:ApplyIconZoom(tex)
        btn.texture = tex

        -- Standard KE 1px pixel-perfect black borders (OVERLAY sublevel 7)
        -- Created BEFORE statusTex so the status overlay at the same sublevel
        -- renders on top (creation order = render order within same sublevel).
        KE:AddIconBorders(btn)

        -- Ready/missing status overlay. OVERLAY sublevel 7 — same as borders.
        -- Creation after KE:AddIconBorders ensures this renders on top of the
        -- 1px border lines. Sublevel 7 is the max valid value for CreateTexture
        -- (range -8 to 7 enforced by the engine).
        local statusTex = btn:CreateTexture(nil, "OVERLAY", nil, 7)
        statusTex:SetPoint("CENTER", btn, "CENTER", 0, 0)
        statusTex:SetSize(iconSize / 2, iconSize / 2)
        statusTex:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
        statusTex:Hide()
        btn.statusTexture = statusTex

        -- Duration text above icon (OVERLAY sublevel 8 per icon standard)
        local timeLeft = btn:CreateFontString(nil, "OVERLAY", nil, 8)
        timeLeft:SetPoint("BOTTOM", btn, "TOP", 0, 1)
        KE:ApplyFontToText(timeLeft,
            db.FontFace,
            db.FontSize    or 11,
            db.FontOutline or "OUTLINE")
        local dr, dg, db_, da = KE:ResolveColor(db.DurationColor, { 1, 1, 1, 1 })
        timeLeft:SetTextColor(dr, dg, db_, da)
        timeLeft:SetText("")
        btn.timeLeft = timeLeft

        -- Count text (bottom-right corner, OVERLAY sublevel 8)
        local countText = btn:CreateFontString(nil, "OVERLAY", nil, 8)
        countText:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
        KE:ApplyFontToText(countText,
            db.FontFace,
            db.FontSize    or 11,
            db.FontOutline or "OUTLINE")
        countText:SetTextColor(dr, dg, db_, da)
        countText:SetText("")
        btn.countText = countText

        buttons[i] = btn
    end

    return buttons
end

--- _LayoutRow
--- Sizes every stub and its status overlay from db, chains the visible ones
--- left to right on `container`, hides the rest, and fits the container to
--- the visible count. `visibility` is indexed 1..NUM_SLOTS. Nothing is
--- touched unless the visible set or the geometry differs from the last pass
--- over this container. The slot buttons parent secure click overlays, so
--- they and the container are protected in combat; the key is left alone
--- then, and the combat-exit repaint lays out.
function RCC:_LayoutRow(container, buttons, visibility)
    if InCombatLockdown() then return end
    local db = self.db
    local iconSize = db.IconSize or 32
    local spacing  = db.IconSpacing or 4

    local mask = 0
    for i = 1, NUM_SLOTS do
        if visibility[i] then mask = mask + 2 ^ (i - 1) end
    end
    local key = string_format("%s:%s:%d", iconSize, spacing, mask)
    if container._layoutKey == key then return end
    container._layoutKey = key

    local prev
    local totalVisible = 0
    for i = 1, NUM_SLOTS do
        local btn = buttons[i]
        if btn then
            btn:SetSize(iconSize, iconSize)
            if btn.statusTexture then
                btn.statusTexture:SetSize(iconSize / 2, iconSize / 2)
            end
            if visibility[i] then
                btn:Show()
                btn:ClearAllPoints()
                if prev then
                    btn:SetPoint("LEFT", prev, "RIGHT", spacing, 0)
                else
                    btn:SetPoint("LEFT", container, "LEFT", 0, 0)
                end
                prev = btn
                totalVisible = totalVisible + 1
            else
                btn:Hide()
            end
        end
    end

    if totalVisible > 0 then
        local width = (iconSize * totalVisible) + (spacing * (totalVisible - 1))
        container:SetWidth(width)
        container:SetHeight(iconSize)
    end
end

--- BuildFrame
--- Creates the KE_ReadyCheckConsumables container and 7 icon button stubs.
--- The container anchors to ReadyCheckListenerFrame (falling back to
--- ReadyCheckFrame) so it floats above the ready check popup.
function RCC:BuildFrame()
    if self.frame then return end

    -- Prefer ReadyCheckListenerFrame; fall back to ReadyCheckFrame (ElvUI replaces it).
    local parent = ReadyCheckListenerFrame or ReadyCheckFrame
    if not parent then
        if DEBUG_RCC then KE:Print("[RCC] BuildFrame: no parent frame found, deferring.") end
        return
    end

    local db = self.db
    local iconSize = db.IconSize or 32
    local spacing  = db.IconSpacing or 4

    -- Container frame (no backdrop — deliberately minimal; icons speak for themselves)
    local f = CreateFrame("Frame", "KE_ReadyCheckConsumables", parent)
    local totalWidth = (iconSize * NUM_SLOTS) + (spacing * (NUM_SLOTS - 1))
    f:SetSize(totalWidth, iconSize)
    f:SetPoint("BOTTOM", parent, "TOP", 0, 2)
    f:SetFrameStrata("HIGH")
    f:Hide()

    -- SecureHandlerState for combat visibility.
    -- Slots with click buttons are hidden in combat via state driver.
    local stateFrame = CreateFrame("Frame", "KE_ReadyCheckConsumables_State", nil, "SecureHandlerStateTemplate")
    -- Hide direction only. Combat entry is the one moment we are in lockdown;
    -- re-showing after combat is ordinary Lua (PLAYER_REGEN_ENABLED repaints
    -- the row), and a restricted handle cannot read plain Lua fields anyway.
    stateFrame:SetAttribute("_onstate-combat", [=[
        if newstate == "hide" then
            for i = 1, 7 do
                local btn = self:GetFrameRef("ClickBtn" .. i)
                if btn then btn:Hide() end
            end
        end
    ]=])
    -- RegisterStateDriver is deferred to ShowFrame (registered only while a
    -- ready check is displayed) and torn down in HideFrame. The snippet above
    -- and the SetFrameRef wiring below are still set up here at build time.

    f.stateFrame = stateFrame
    local buttons = self:_BuildIconRow(f)
    self.buttons = buttons

    for i = 1, NUM_SLOTS do
        local btn = buttons[i]

        -- SecureActionButton click frame for slots that can be activated.
        -- Click-enabled: flask (2), oil MH (3), oil OH (4), rune (5), class (7).
        -- Display-only: food (1, tracked via aura only), healthstone (6, dropped by Warlock).
        -- Oil slots use type="item" with target-slot 16/17; others use type="macro".
        -- Macrotext is set dynamically in UpdateAllIcons based on the active consumable.
        local hasClickFrame = (i == SLOT_FLASK or
                               i == SLOT_OIL  or i == SLOT_OILOH or
                               i == SLOT_RUNE or i == SLOT_HS or i == SLOT_CLASS)
        if hasClickFrame then
            local click = CreateFrame("Button", nil, btn, "SecureActionButtonTemplate")
            click:SetAllPoints()
            click:Hide()
            click:RegisterForClicks("AnyUp", "AnyDown")

            -- Oil slots use item type with target-slot; others use macro
            if i == SLOT_OIL then
                click:SetAttribute("type", "item")
                click:SetAttribute("target-slot", "16")
            elseif i == SLOT_OILOH then
                click:SetAttribute("type", "item")
                click:SetAttribute("target-slot", "17")
            else
                click:SetAttribute("type", "macro")
                -- macrotext set dynamically in UpdateAllIcons
            end

            -- Dim parent on hover so the icon appears interactive
            click:SetScript("OnEnter", function() btn:SetAlpha(0.7) end)
            click:SetScript("OnLeave", function() btn:SetAlpha(1.0) end)

            stateFrame:SetFrameRef("ClickBtn" .. i, click)
            btn.click = click
        end
    end

    -- Named slot aliases for readability in update functions
    self.buttons.food  = self.buttons[SLOT_FOOD]
    self.buttons.flask = self.buttons[SLOT_FLASK]
    self.buttons.oil   = self.buttons[SLOT_OIL]
    self.buttons.oiloh = self.buttons[SLOT_OILOH]
    self.buttons.rune  = self.buttons[SLOT_RUNE]
    self.buttons.hs    = self.buttons[SLOT_HS]
    self.buttons.class = self.buttons[SLOT_CLASS]

    -- Close button — only visible when we initiated the ready check (no
    -- Blizzard popup shows for the starter, so we provide our own dismiss).
    -- Hand-rolled minimal Backdrop button instead of UIPanelButtonTemplate
    -- to avoid the inner highlight/double-border look that template renders.
    -- Matches the clean single-edge MRT style.
    local rcc = self
    local closeBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    closeBtn:SetHeight(22)
    closeBtn:SetPoint("TOPLEFT",  f, "BOTTOMLEFT",  0, -2)
    closeBtn:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -2)
    closeBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    closeBtn:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
    closeBtn:SetBackdropBorderColor(0, 0, 0, 1)

    local closeText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeText:SetPoint("CENTER", closeBtn, "CENTER", 0, 0)
    closeText:SetText("Close")
    closeText:SetTextColor(1, 1, 1, 1)

    closeBtn:SetScript("OnEnter", function(btn)
        btn:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    end)
    closeBtn:SetScript("OnLeave", function(btn)
        btn:SetBackdropBorderColor(0, 0, 0, 1)
    end)
    closeBtn:SetScript("OnClick", function() rcc:HideFrame() end)
    closeBtn:Hide()
    f.closeBtn = closeBtn

    self.frame = f

    if DEBUG_RCC then
        KE:Print("[RCC] BuildFrame: frame created, parent=" .. tostring(parent:GetName() or "<anonymous>"))
    end
end

---------------------------------------------------------------------------------
-- Icon Updates
---------------------------------------------------------------------------------

---------------------------------------------------------------------------------
-- Detection Helpers
---------------------------------------------------------------------------------

local READY_TEXTURE     = "Interface\\RaidFrame\\ReadyCheck-Ready"
local NOT_READY_TEXTURE = "Interface\\RaidFrame\\ReadyCheck-NotReady"

--- ScanPlayerAuras
--- Walks the player's HELPFUL auras once and returns a {spellId = auraData} map.
--- Aura entries with secret spellIds are filtered out — they cannot be safely
--- used as table keys or compared against data table IDs.
--- The walk is uncapped: a nil batch size pages until the continuation token
--- runs out, and the callback never ends it early. Callers gate on
--- KE:AreAuraIdentitiesHidden() first; the slot calls hard error without
--- aura access.
function RCC:ScanPlayerAuras()
    local auras = {}
    AuraUtil.ForEachAura("player", "HELPFUL", nil, function(auraData)
        if not auraData then return end

        local spellId = auraData.spellId
        if KE:IsSafeValue(spellId) then
            auras[spellId] = auraData
        end
    end, true)
    return auras
end

--- GetAuraRemaining
--- Returns seconds remaining on an aura, or nil if permanent / secret / expired.
function RCC:GetAuraRemaining(auraData)
    if not auraData then return nil end
    local expire = auraData.expirationTime
    if not KE:IsSafeValue(expire) or expire == 0 then return nil end

    local remain = expire - GetTime()
    if remain <= 0 then return nil end
    return remain
end

--- OffhandIsWeapon
--- Returns true if the player's OH slot holds an item with itemClassID == 2 (Weapon).
--- Shields, off-hand frills (itemClassID 4), and empty slots return false.
function RCC:OffhandIsWeapon()
    local itemID = GetInventoryItemID("player", 17)
    if not itemID then return false end

    local _, _, _, _, _, classID = GetItemInfoInstant(itemID)
    return classID == 2
end

--- IsWarlockInGroup
--- Returns true if the player is a Warlock OR a Warlock exists in the current
--- party/raid. Healthstones only exist when a Warlock is present to summon
--- them, so the HS slot is hidden otherwise (matches MRT's behavior).
--- Solo non-Warlocks: returns false (slot hidden).
function RCC:IsWarlockInGroup()
    local _, myClass = UnitClass("player")
    if myClass == "WARLOCK" then return true end

    if IsInRaid() then
        for i = 1, 40 do
            local unit = "raid" .. i
            if UnitExists(unit) then
                local _, class = UnitClass(unit)
                if class == "WARLOCK" then return true end
            end
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            local unit = "party" .. i
            if UnitExists(unit) then
                local _, class = UnitClass(unit)
                if class == "WARLOCK" then return true end
            end
        end
    end
    return false
end

--- _IsNameInGroup
--- Returns true if `name` (in "Name-Realm" form) currently appears in the
--- player's party or raid roster. Used to validate that a cached sticky
--- last-target hasn't left the group between refreshes.
function RCC:_IsNameInGroup(name)
    if not name then return false end
    if IsInRaid() then
        for i = 1, 40 do
            local unit = "raid" .. i
            if UnitExists(unit) then
                local n = GetUnitName(unit, true)
                if KE:IsSafeValue(n) and n == name then return true end
            end
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            local unit = "party" .. i
            if UnitExists(unit) then
                local n = GetUnitName(unit, true)
                if KE:IsSafeValue(n) and n == name then return true end
            end
        end
    end
    return false
end

--- _GetSoulstonedTarget
--- Returns the name of the player's current Soulstone target ("Name-Realm"),
--- or nil if no sticky target can be resolved.
---
--- Resolution order:
---   1. **Live scan** — first group member with a player-source Soulstone aura.
---      When found, populates RCC._lastSoulstoneTarget so subsequent calls can
---      fall back to it after the aura drops.
---   2. **Cache fallback** — if no live target, return RCC._lastSoulstoneTarget
---      provided the cached name is still in the group. This is the BR
---      stickiness behavior (Core/State.lua — "If not active, keep old
---      last target so macro still targets them after it falls off"): once
---      the warlock manually targets a specific healer with their first cast,
---      every subsequent click keeps nominating that same person, even after
---      the aura is consumed on their death. The macro's `,nodead` self-corrects
---      if the cached target is currently dead.
---   3. **Cache prune** — if the cached name is no longer in the group, clear
---      it and return nil so the priority chain falls through to "first living
---      healer." Mirrors BR's prune step (State.lua).
---
--- Player intentionally skipped from the live scan — matches BR's
--- `not UnitIsUnit(data.unit, "player")` guard. Self-stones are covered by
--- the macro's final [@player] fallback; pinning sticky priority to self
--- would route the next click back at us instead of letting the warlock
--- target a healer.
---
--- Secret-value guards: aura sourceUnit can be secret in chat-messaging
--- lockdown; treat secret/missing source as "not from us." GetUnitName is
--- guarded against SecretWhenUnitIdentityRestricted (encounter anonymization).
function RCC:_GetSoulstonedTarget()
    local function check(unit)
        if KE:IsAuraHiddenForSpell("Soulstone") then return nil end
        if not UnitExists(unit) then return nil end
        if UnitIsDeadOrGhost(unit) then return nil end
        local auraData = C_UnitAuras.GetAuraDataBySpellName(unit, "Soulstone", "HELPFUL")
        if not auraData then return nil end
        local source = auraData.sourceUnit
        if not KE:IsSafeValue(source) then return nil end
        if not (source == "player" or UnitIsUnit(source, "player")) then return nil end
        local n = GetUnitName(unit, true)
        if not KE:IsSafeValue(n) then return nil end
        return n
    end

    local liveTarget
    if IsInRaid() then
        for i = 1, 40 do
            local name = check("raid" .. i)
            if name then liveTarget = name; break end
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            local name = check("party" .. i)
            if name then liveTarget = name; break end
        end
    end

    if liveTarget then
        self._lastSoulstoneTarget = liveTarget
        return liveTarget
    end

    -- No live target: keep nominating the cached name if they're still in group.
    local cached = self._lastSoulstoneTarget
    if cached then
        if self:_IsNameInGroup(cached) then
            return cached
        end
        -- Cached member left the group — prune.
        if DEBUG_RCC then
            KE:Print("[RCC] _GetSoulstonedTarget: cached target left group, clearing.")
        end
        self._lastSoulstoneTarget = nil
    end
    return nil
end

--- _GetFirstLivingHealer
--- Returns the name of the first living group member assigned the HEALER role
--- ("Name-Realm" format), or nil if no living healer exists. Iteration order
--- matches raid/party slot order.
function RCC:_GetFirstLivingHealer()
    local function check(unit)
        if not UnitExists(unit) then return nil end
        if UnitIsDeadOrGhost(unit) then return nil end
        if UnitGroupRolesAssigned(unit) ~= "HEALER" then return nil end
        local n = GetUnitName(unit, true)
        if not KE:IsSafeValue(n) then return nil end
        return n
    end

    if IsInRaid() then
        for i = 1, 40 do
            local name = check("raid" .. i)
            if name then return name end
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            local name = check("party" .. i)
            if name then return name end
        end
    end
    return nil
end

--- _BuildSoulstoneMacrotext
--- Composes the dynamic macro string for the Warlock CLASS_SLOT click button.
---
--- Priority chain (intentionally diverges from BR's sticky-first ordering):
---   1. @mouseover (kept for macro-pattern consistency; effectively
---      unreachable since clicking the icon steals mouseover focus)
---   2. @target — lets the warlock manually override the sticky for one
---      pull by clicking on a different friendly first, then clicking the
---      RCC icon. The post-cast UNIT_AURA refresh updates the sticky
---      cache to the new target, so subsequent pulls auto-route to them
---      until the next manual override.
---   3. Sticky last target (sourced from _GetSoulstonedTarget — live scan
---      OR cache fallback) — the dominant priority during normal flow
---      because the warlock usually has the boss (hostile) targeted, so
---      the @target,help conditional fails and falls through here.
---   4. First living healer in group — fallback when no sticky exists yet
---      (first cast of the session before any soulstone has been placed).
---   5. @player — final self-fallback.
---
--- Why not sticky-first (BR's order at Buffs.lua)? With sticky-first,
--- a live sticky target shadows @target — the warlock can't override by
--- targeting a different healer; the click always routes to the cached
--- name. Putting @target before sticky makes "click target → click icon"
--- the natural manual-override flow.
---
--- The `,help,nodead` conditionals self-correct if a cached name is dead
--- (chain falls through to the next prefix), so out-of-combat-only
--- refresh remains sufficient.
---
--- Stays well under WoW's 255-char macro limit:
---   ~70 chars base + ~30 chars per dynamic prefix * 2 = ~150 chars max.
function RCC:_BuildSoulstoneMacrotext()
    local stoned = self:_GetSoulstonedTarget()
    local healer = self:_GetFirstLivingHealer()

    local cast = "/cast [@mouseover,help,nodead][@target,help,nodead]"
    if stoned then
        cast = cast .. "[@" .. stoned .. ",help,nodead]"
    end
    if healer and healer ~= stoned then
        cast = cast .. "[@" .. healer .. ",help,nodead]"
    end
    cast = cast .. "[@player] Soulstone"

    if DEBUG_RCC then
        KE:Print(string_format("[RCC] BuildSoulstoneMacrotext: stoned=%s healer=%s",
            tostring(stoned), tostring(healer)))
    end

    return "/stopmacro [combat]\n" .. cast
end

--- CountItems
--- Sums bag+bank counts across a list of item IDs.
function RCC:CountItems(itemIDs)
    local total = 0
    for _, id in ipairs(itemIDs) do
        local count = GetItemCount(id, false, true)
        if count then total = total + count end
    end
    return total
end

--- SafeItemName
--- Returns a non-nil, non-secret item name, or nil if unavailable / secret.
--- Item names can be secret in chat messaging lockdown per api-validator guidance.
function RCC:SafeItemName(itemID)
    local name = GetItemInfo(itemID)
    if name and KE:IsSafeValue(name) then return name end
    return nil
end

--- SetIconFromItem
--- Resolves the item icon via C_Item.GetItemIconByID and applies it to a texture.
--- Falls back silently if the icon isn't cached yet.
function RCC:SetIconFromItem(texture, itemID)
    if not texture or not itemID then return end
    if C_Item and C_Item.GetItemIconByID then
        local icon = C_Item.GetItemIconByID(itemID)
        if icon then texture:SetTexture(icon) end
    end
end

--- SetDurationText
--- Formats seconds as "Nm" minutes, ceiling. Empty string for nil.
local function formatDurationText(seconds)
    if not seconds or seconds <= 0 then return "" end
    return string_format("%dm", math_ceil(seconds / 60))
end

local SOULSTONE_GLOW_COLOR = { 1, 1, 0, 1 }

-- LibCustomGlow rebuilds the glow on every Start call, so a slot that is
-- already glowing is left alone across repaints.
local function StartGlow(btn, color)
    if not LCG or btn.glowActive then return end
    LCG.PixelGlow_Start(btn, color, 8, 0.25, 8, 2, 1, 1, false, nil)
    btn.glowActive = true
end

local function StopGlow(btn)
    if not btn.glowActive then return end
    if LCG then LCG.PixelGlow_Stop(btn) end
    btn.glowActive = false
end

--- _PaintUnavailable
--- An aura-driven slot while aura identities are hidden: no status mark, a
--- greyed icon, no text, no glow and no armed click, so a slot that cannot
--- be read never shows a state left over from an earlier check.
function RCC:_PaintUnavailable(btn)
    if not btn then return end
    btn.statusTexture:Hide()
    btn.texture:SetDesaturated(true)
    btn.timeLeft:SetText("")
    btn.countText:SetText("")
    StopGlow(btn)
    if btn.click and not InCombatLockdown() then btn.click:Hide() end
end

---------------------------------------------------------------------------------
-- Per-Slot Updates
---------------------------------------------------------------------------------

--- UpdateFood
--- Display-only slot. Matches any FOOD_BUFFS spellId in the scanned aura map.
--- Hearty food (persists through death) uses HeartyFoodColor on the duration
--- text as a visual cue.
function RCC:UpdateFood(auras)
    local btn = self.buttons.food
    if not btn then return end

    for spellId in pairs(FOOD_BUFFS) do
        local aura = auras[spellId]
        if aura then
            btn.statusTexture:SetTexture(READY_TEXTURE)
            btn.statusTexture:Show()
            btn.texture:SetDesaturated(false)
            btn.timeLeft:SetText(formatDurationText(self:GetAuraRemaining(aura)))

            -- Hearty annotation: tint duration text green to flag "persists through death"
            local cr, cg, cb, ca
            if HEARTY_FOOD_BUFFS[spellId] then
                cr, cg, cb, ca = KE:ResolveColor(self.db.HeartyFoodColor, { 0.2, 1.0, 0.2, 1.0 })
            else
                cr, cg, cb, ca = KE:ResolveColor(self.db.DurationColor, { 1, 1, 1, 1 })
            end
            btn.timeLeft:SetTextColor(cr, cg, cb, ca)
            btn.countText:SetText("")
            return
        end
    end

    btn.statusTexture:SetTexture(NOT_READY_TEXTURE)
    btn.statusTexture:Show()
    btn.texture:SetDesaturated(true)
    btn.timeLeft:SetText("")
    btn.countText:SetText("")
end

--- _GetSpecFlaskPriority
--- Returns the SPEC_FLASK_PRIORITY entry for the player's current spec, or
--- nil if no spec / not in the table. Safe APIs in 12.0 — GetSpecialization
--- and GetSpecializationInfo are not combat-restricted and don't return
--- secret values.
function RCC:_GetSpecFlaskPriority()
    local specIndex = GetSpecialization and GetSpecialization()
    if not specIndex then return nil end
    local specId = GetSpecializationInfo and GetSpecializationInfo(specIndex)
    if not specId then return nil end
    return SPEC_FLASK_PRIORITY[specId]
end

--- UpdateFlask
--- Paints the flask slot's ready state from the aura map and remembers the
--- buffed stat line. The click half lives in UpdateFlaskClick, which reads
--- bags only and so runs whether or not the aura walk did.
function RCC:UpdateFlask(auras)
    local btn = self.buttons.flask
    if not btn then return end

    local activeAura, activeBuffId
    for buffId in pairs(FLASK_BUFFS) do
        if auras[buffId] then
            activeAura = auras[buffId]
            activeBuffId = buffId
            break
        end
    end

    if activeAura then
        btn.statusTexture:SetTexture(READY_TEXTURE)
        btn.statusTexture:Show()
        btn.texture:SetDesaturated(false)
        btn.timeLeft:SetText(formatDurationText(self:GetAuraRemaining(activeAura)))

        -- Remembered as the stat string rather than the buff id so the
        -- preference survives a re-id of the buff as long as FLASKS keeps
        -- its stat field.
        if self.db then
            local stat = FLASK_BUFFS[activeBuffId]
            if stat then self.db.LastFlaskStat = stat end
        end
    else
        btn.statusTexture:SetTexture(NOT_READY_TEXTURE)
        btn.statusTexture:Show()
        btn.texture:SetDesaturated(true)
        btn.timeLeft:SetText("")
    end
end

--- UpdateFlaskClick
--- Nominates the flask the click will use and paints its icon and count;
--- btn.nominatedItem carries the pick for probes. Bag reads carry no aura
--- restriction, which is why this runs outside the aura-identity gate and
--- arms in a keystone.
function RCC:UpdateFlaskClick()
    local btn = self.buttons.flask
    if not btn then return end
    local click = btn.click
    local cauldronOnly = self.db and self.db.CauldronFlasksOnly

    local available = {}
    for itemID, data in pairs(FLASKS) do
        if (not cauldronOnly) or data.fleeting then
            local count = GetItemCount(itemID, false, true)
            if count and count > 0 then available[itemID] = count end
        end
    end

    local function bestForStat(stat)
        for _, itemID in ipairs(FLASKS_SORTED) do
            if FLASKS[itemID].stat == stat and available[itemID] then return itemID end
        end
        return nil
    end

    local pickItem
    local lastStat = self.db and self.db.LastFlaskStat
    if lastStat then pickItem = bestForStat(lastStat) end

    if not pickItem then
        local prio = self:_GetSpecFlaskPriority()
        if prio then
            for _, stat in ipairs(prio) do
                pickItem = bestForStat(stat)
                if pickItem then break end
            end
        end
    end

    if not pickItem then
        for _, itemID in ipairs(FLASKS_SORTED) do
            if available[itemID] then
                pickItem = itemID
                break
            end
        end
    end

    btn.nominatedItem = pickItem
    if pickItem then
        self:SetIconFromItem(btn.texture, pickItem)
        btn.countText:SetText(tostring(available[pickItem]))
    else
        btn.texture:SetTexture(DEFAULT_ICONS[SLOT_FLASK])
        btn.countText:SetText("")
    end

    local clickName = pickItem and self:SafeItemName(pickItem) or nil

    if click and not InCombatLockdown() then
        if clickName then
            click:SetAttribute("type", "macro")
            click:SetAttribute("macrotext", "/stopmacro [combat]\n/use " .. clickName)
            click:Show()
        else
            click:Hide()
        end
    end
end

--- UpdateWeaponEnchant
--- Detects an active temporary enchant on one weapon slot via
--- C_PaperDollInfo.GetTemporaryEnchantmentInfo. Covers oils, weapon stones,
--- and ammo mods uniformly. Swaps the slot's icon to match the specific
--- enchant when known.
--- slotKey: "oil" (MH) or "oiloh" (OH).
--- invSlot: 16 or 17.
function RCC:UpdateWeaponEnchant(slotKey, invSlot)
    local btn = self.buttons[slotKey]
    if not btn then return end
    local click = btn.click

    -- Nothing back means no temporary enchant; an empty or two-hander
    -- off-hand slot answers the same way, so nil is the whole test.
    local info = GetTemporaryEnchantmentInfo(invSlot)
    local exp, enchID
    if info then
        exp, enchID = info.remainingTimeMs, info.enchantID
    end

    if DEBUG_RCC then
        KE:Print(string.format("[RCC] UpdateWeaponEnchant slot=%s invSlot=%d has=%s ench=%s",
            tostring(slotKey), invSlot, tostring(info ~= nil), tostring(enchID)))
    end

    if info then
        btn.statusTexture:SetTexture(READY_TEXTURE)
        btn.statusTexture:Show()
        btn.texture:SetDesaturated(false)

        if KE:IsSafeValue(exp) and exp > 0 then
            btn.timeLeft:SetText(string_format("%dm", math_ceil(exp / 1000 / 60)))
        else
            btn.timeLeft:SetText("")
        end

        -- Icon + last-used memory (only if enchant ID is known and safe)
        if KE:IsSafeValue(enchID) then
            local data = WEAPON_ENHANCEMENTS[enchID]
            if data then
                self:SetIconFromItem(btn.texture, data.item)
                if self.db then self.db.LastWeaponEnchantItem = data.item end
            end
        end
    else
        btn.statusTexture:SetTexture(NOT_READY_TEXTURE)
        btn.statusTexture:Show()
        btn.texture:SetDesaturated(true)
        btn.timeLeft:SetText("")
    end

    -- Click wiring — offer last-remembered item (or any available in bags)
    local preferredItem = self.db and self.db.LastWeaponEnchantItem
    local bagCount = 0

    if preferredItem then
        bagCount = GetItemCount(preferredItem, false, true) or 0
    end
    -- Fallback: if no memory or memory item is out of stock, pick any available
    if bagCount == 0 then
        for _, data in pairs(WEAPON_ENHANCEMENTS) do
            local count = GetItemCount(data.item, false, true)
            if count and count > 0 then
                preferredItem = data.item
                bagCount = count
                break
            end
        end
    end
    btn.countText:SetText(bagCount > 0 and tostring(bagCount) or "")

    if click and not InCombatLockdown() then
        if preferredItem and bagCount > 0 then
            local itemName = self:SafeItemName(preferredItem)
            if itemName then
                click:SetAttribute("type", "item")
                click:SetAttribute("item", itemName)
                click:SetAttribute("target-slot", tostring(invSlot))
                click:Show()
            else
                click:Hide()
            end
        else
            click:Hide()
        end
    end
end

--- UpdateRune
--- Aura scan against AUGMENT_RUNES buff IDs. Click offers the highest-priority
--- (lowest priority number) rune item currently in bags.
function RCC:UpdateRune(auras)
    local btn = self.buttons.rune
    if not btn then return end
    local click = btn.click

    local activeAura, activeData
    for buffId, data in pairs(AUGMENT_RUNES) do
        if auras[buffId] then
            activeAura = auras[buffId]
            activeData = data
            break
        end
    end

    if activeAura then
        btn.statusTexture:SetTexture(READY_TEXTURE)
        btn.statusTexture:Show()
        btn.texture:SetDesaturated(false)
        btn.timeLeft:SetText(formatDurationText(self:GetAuraRemaining(activeAura)))
        if activeData then self:SetIconFromItem(btn.texture, activeData.item) end
    else
        btn.statusTexture:SetTexture(NOT_READY_TEXTURE)
        btn.statusTexture:Show()
        btn.texture:SetDesaturated(true)
        btn.timeLeft:SetText("")
    end

    -- Pick best available rune by priority
    local bestRune, bestPriority, bestCount
    local unlimitedOnly = self.db.UnlimitedRunesOnly
    for _, data in pairs(AUGMENT_RUNES) do
        -- UnlimitedRunesOnly: skip single-use runes (only offer DF/TWW reusable)
        if (not unlimitedOnly) or data.unlimited then
            local count = GetItemCount(data.item, false, true)
            if count and count > 0 then
                if not bestPriority or data.priority < bestPriority then
                    bestRune = data
                    bestPriority = data.priority
                    bestCount = count
                end
            end
        end
    end
    -- Count hidden in unlimited-only mode (these runes don't have a finite
    -- "quantity" — they're reusable, so "1" or "2" would be misleading).
    if unlimitedOnly then
        btn.countText:SetText("")
    else
        btn.countText:SetText(bestCount and tostring(bestCount) or "")
    end

    -- UnlimitedRunesOnly extras:
    --   1. Swap icon to the preferred unlimited rune when no buff is active
    --      (if buff IS active, activeData's icon is already applied above).
    --   2. Pixel-glow border as a "apply your rune" nudge — matches MRT.
    -- Both extras are gated on the toggle being checked; default behavior is
    -- unchanged with toggle off.
    if unlimitedOnly and bestRune and not activeAura then
        self:SetIconFromItem(btn.texture, bestRune.item)
    end
    if unlimitedOnly and bestRune and not activeAura then
        StartGlow(btn, nil)
    else
        StopGlow(btn)
    end

    if click and not InCombatLockdown() then
        if bestRune then
            local name = self:SafeItemName(bestRune.item)
            if name then
                click:SetAttribute("type", "macro")
                click:SetAttribute("macrotext", "/stopmacro [combat]\n/use " .. name)
                click:Show()
            else
                click:Hide()
            end
        else
            click:Hide()
        end
    end
end

--- UpdateHealthstone
--- Counts Standard + Demonic (warlock-only) HS in bags. Display-only for
--- non-Warlocks. For Warlocks, clicking the slot casts Create Soulwell (29893)
--- to drop a fresh well — the source healthstones come from. Mirrors
--- Healthstone reminder click (castSpellID).
function RCC:UpdateHealthstone()
    local btn = self.buttons.hs
    if not btn then return end
    local click = btn.click

    local _, playerClass = UnitClass("player")
    local items = {}
    for itemID, data in pairs(HEALTHSTONES) do
        if (not data.warlockOnly) or playerClass == "WARLOCK" then
            items[#items + 1] = itemID
        end
    end

    local count = self:CountItems(items)
    if count > 0 then
        btn.statusTexture:SetTexture(READY_TEXTURE)
        btn.statusTexture:Show()
        btn.texture:SetDesaturated(false)
    else
        btn.statusTexture:SetTexture(NOT_READY_TEXTURE)
        btn.statusTexture:Show()
        btn.texture:SetDesaturated(true)
    end
    btn.countText:SetText(count > 0 and tostring(count) or "")
    btn.timeLeft:SetText("")

    -- Warlock-only click wiring: cast Create Soulwell. Hidden for other classes
    -- (slot stays display-only — healthstone use is on the player's keybinds).
    if click and not InCombatLockdown() then
        if playerClass == "WARLOCK" then
            click:SetAttribute("type", "macro")
            click:SetAttribute("macrotext", "/stopmacro [combat]\n/cast Create Soulwell")
            click:Show()
        else
            click:Hide()
        end
    end
end

--- UpdateClassSlot
--- Warlock-only Soulstone slot. Uses C_Spell.GetSpellCooldown(20707) as a
--- proxy for "someone in the raid has a Soulstone": on CD ≈ stoned,
--- off CD ≈ need to cast.
---
--- Secret value guards: C_Spell.GetSpellCooldown's startTime and duration can
--- return secret values in 12.0 (per api-validator guidance) — we fallback to
--- 0 on secret so the off-CD branch triggers and no tainted arithmetic occurs.
function RCC:UpdateClassSlot()
    local btn = self.buttons.class
    if not btn then return end
    local click = btn.click

    local _, playerClass = UnitClass("player")
    local classData = CLASS_SLOT[playerClass]
    if not classData then
        btn:Hide()
        return
    end

    local start, duration = 0, 0
    if C_Spell and C_Spell.GetSpellCooldown then
        local cdInfo = C_Spell.GetSpellCooldown(classData.spellID)
        -- Require BOTH fields safe. If only one is secret, we can't compute a
        -- meaningful remaining-time, and showing "on CD — --" misleads the user.
        -- Falling through to 0/0 (→ onCD=false, default "not ready" state) is
        -- the accurate representation of "we cannot determine the state."
        if cdInfo and KE:IsSafeValue(cdInfo.startTime) and KE:IsSafeValue(cdInfo.duration) then
            start = cdInfo.startTime
            duration = cdInfo.duration
        end
    end

    -- >1.5s filters out GCD false-positives (Soulstone has a long CD, so this
    -- is a safe threshold).
    local onCD = duration > 1.5

    if onCD then
        btn.statusTexture:SetTexture(READY_TEXTURE)
        btn.statusTexture:Show()
        btn.texture:SetDesaturated(false)
        local remain = start + duration - GetTime()
        btn.timeLeft:SetText(formatDurationText(remain))
    else
        btn.statusTexture:SetTexture(NOT_READY_TEXTURE)
        btn.statusTexture:Show()
        btn.texture:SetDesaturated(true)
        btn.timeLeft:SetText("")
    end
    btn.countText:SetText("")

    -- Yellow pixel glow when Soulstone is missing (grayed-out state).
    -- Stops automatically when the slot transitions to ready (onCD branch).
    -- HideFrame stops all glows defensively on RC teardown.
    if onCD then
        StopGlow(btn)
    else
        StartGlow(btn, SOULSTONE_GLOW_COLOR)
    end

    if click and not InCombatLockdown() then
        local macrotext = classData.macrotext
        if type(macrotext) == "function" then
            macrotext = macrotext(self)
        end
        click:SetAttribute("type", "macro")
        click:SetAttribute("macrotext", macrotext)
        click:Show()
    end
end

---------------------------------------------------------------------------------
-- Main Update Orchestrator
---------------------------------------------------------------------------------

--- _IsRowLive
--- True while the real row should keep repainting on events: built, visible
--- through its parent chain (a respondent's Ready/Not Ready hides the
--- Blizzard popup the row is parented to), and not waiting on a deferred
--- hide.
function RCC:_IsRowLive()
    return self.frame ~= nil and self.frame:IsVisible() and not self._hidePending
end

--- PLAYER_REGEN_ENABLED, registered only while a ready check is displayed.
--- The state driver hid the click overlays on combat entry; a full repaint
--- re-arms the ones that still apply and shows them again.
function RCC:PLAYER_REGEN_ENABLED()
    self:RequestRefresh()
end

--- _ComputeVisibility
--- The real row's visible set, each contextual predicate asked once per
--- repaint. ShowPreview keeps a toggle-only table of its own so the settings
--- preview shows every category.
function RCC:_ComputeVisibility()
    local db = self.db
    local _, playerClass = UnitClass("player")
    local visibility = self._visibility
    visibility[SLOT_FOOD]  = db.ShowFood        ~= false
    visibility[SLOT_FLASK] = db.ShowFlask       ~= false
    visibility[SLOT_OIL]   = db.ShowWeaponOil   ~= false
    visibility[SLOT_OILOH] = (db.ShowOffHandOil  ~= false) and self:OffhandIsWeapon()
    visibility[SLOT_RUNE]  = db.ShowAugmentRune ~= false
    visibility[SLOT_HS]    = (db.ShowHealthstone ~= false) and self:IsWarlockInGroup()
    visibility[SLOT_CLASS] = (db.ShowClassItem   ~= false) and (CLASS_SLOT[playerClass] ~= nil)
    return visibility
end

--- UpdateAllIcons
--- Computes the visible set, scans player auras once, repaints each visible
--- slot, then lays the row out. Only the food, flask and rune slots need
--- aura access; while aura identities are hidden they are painted
--- unavailable and the weapon, healthstone and class slots still repaint,
--- since C_PaperDollInfo.GetTemporaryEnchantmentInfo and C_Item.GetItemCount
--- carry no aura restriction and the class slot asks its own per-spell gate.
--- The flask click is bag-driven and repaints under the gate too.
---
--- Secret value guards are layered:
---   1. KE:AreAuraIdentitiesHidden() — no aura walk and no aura-driven paint
---      while the global aura system is locked for this player.
---   2. Per-aura spellId / expirationTime guards via ScanPlayerAuras filter.
---   3. Per-API guards inside individual slot updaters (weapon enchant exp/ID,
---      spell cooldown start/duration, item names passed to macrotext).
--- @param force boolean  literal true skips the liveness test (ShowFrame's
---   first paint, before the popup's visibility is known); the aura gate
---   still applies. Anything else, including an event name arriving in this
---   position, does not force.
function RCC:UpdateAllIcons(force)
    if force ~= true and not self:_IsRowLive() then return end
    if not self.frame or not self.db then return end

    local visibility = self:_ComputeVisibility()
    local buttons = self.buttons

    local auras
    if KE:AreAuraIdentitiesHidden() then
        if DEBUG_RCC then KE:Print("[RCC] UpdateAllIcons: auras are secret, aura slots unavailable.") end
    else
        auras = self:ScanPlayerAuras()
    end

    if auras then
        if visibility[SLOT_FOOD]  then self:UpdateFood(auras) end
        if visibility[SLOT_FLASK] then self:UpdateFlask(auras) end
        if visibility[SLOT_RUNE]  then self:UpdateRune(auras) end
    else
        if visibility[SLOT_FOOD]  then self:_PaintUnavailable(buttons.food) end
        if visibility[SLOT_FLASK] then self:_PaintUnavailable(buttons.flask) end
        if visibility[SLOT_RUNE]  then self:_PaintUnavailable(buttons.rune) end
    end
    -- After the unavailable paint so the bag-driven click, icon and count
    -- land on top of it.
    if visibility[SLOT_FLASK] then self:UpdateFlaskClick() end
    if visibility[SLOT_OIL]   then self:UpdateWeaponEnchant("oil",   16) end
    if visibility[SLOT_OILOH] then self:UpdateWeaponEnchant("oiloh", 17) end
    if visibility[SLOT_HS]    then self:UpdateHealthstone() end
    if visibility[SLOT_CLASS] then self:UpdateClassSlot() end

    self:_LayoutRow(self.frame, buttons, visibility)
end

-- Pre-declared so RequestRefresh allocates no closure per call.
local function _RefreshFire()
    RCC._refreshPending = nil
    RCC:UpdateAllIcons()
end

--- RequestRefresh
--- The event entry point. Every request made in one frame collapses into
--- one UpdateAllIcons on the next. Liveness is tested here so a dead row
--- schedules nothing, and again inside UpdateAllIcons so a request queued
--- just before the row died repaints nothing.
function RCC:RequestRefresh()
    if self._refreshPending or not self:_IsRowLive() then return end
    self._refreshPending = true
    C_Timer.After(0, _RefreshFire)
end

--- RefreshLayout
--- Lays the real row out from the current visible set without repainting
--- any slot.
function RCC:RefreshLayout()
    if not self.frame or not self.db then return end
    self:_LayoutRow(self.frame, self.buttons, self:_ComputeVisibility())
end

--- RefreshIconVisibility
--- Compatibility wrapper — older code may call this name. Delegates to RefreshLayout.
function RCC:RefreshIconVisibility()
    self:RefreshLayout()
end

---------------------------------------------------------------------------------
-- GUI Integration
---------------------------------------------------------------------------------

--- ApplySettings
--- Called by the GUI panel when any config changes. Re-reads db, re-applies
--- font + base text color to whichever rows exist, re-lays the preview when
--- one is up, and repaints the real row when it is live. Both dispatches
--- run: a toggle changed while a preview and a real check are both on
--- screen reaches both.
function RCC:ApplySettings()
    self:UpdateDB()
    if not self.frame and not self.previewFrame then return end

    local db = self.db
    if not db then return end

    -- Hearty food color is re-applied per update cycle inside UpdateFood.
    local dr, dg, db_, da = KE:ResolveColor(db.DurationColor, { 1, 1, 1, 1 })
    local function applyFonts(buttons)
        if not buttons then return end
        for i = 1, NUM_SLOTS do
            local btn = buttons[i]
            if btn then
                if btn.timeLeft then
                    KE:ApplyFontToText(btn.timeLeft,
                        db.FontFace,
                        db.FontSize    or 11,
                        db.FontOutline or "OUTLINE")
                    btn.timeLeft:SetTextColor(dr, dg, db_, da)
                end
                if btn.countText then
                    KE:ApplyFontToText(btn.countText,
                        db.FontFace,
                        db.FontSize    or 11,
                        db.FontOutline or "OUTLINE")
                    btn.countText:SetTextColor(dr, dg, db_, da)
                end
            end
        end
    end
    applyFonts(self.buttons)
    applyFonts(self.previewButtons)

    if self.inPreview then
        self:ShowPreview()
    end
    self:UpdateAllIcons()
end

---------------------------------------------------------------------------------
-- Frame Show / Hide
---------------------------------------------------------------------------------

--- ShowFrame
--- Called on READY_CHECK. Builds the frame if needed, updates icons, and
--- shows the consumable row anchored to the ready check popup.
---
--- @param initiatorUnit string  unit that initiated the ready check (passed from event)
function RCC:ShowFrame(initiatorUnit)
    local db = self.db
    if not db or not db.Enabled then return end

    -- Guard: initiatorUnit may arrive as a secret value during Chat Messaging
    -- Lockdown (M+, rated PvP). Passing a secret string to UnitIsUnit crashes,
    -- so treat "unsafe initiator" as "not the starter" (false) rather than
    -- testing the predicate at all.
    local isStarter = KE:IsSafeValue(initiatorUnit)
        and UnitIsUnit(initiatorUnit, "player")

    -- HideForStarter: suppress display if we initiated the ready check.
    if db.HideForStarter and isStarter then
        if DEBUG_RCC then KE:Print("[RCC] ShowFrame: suppressed (HideForStarter, we initiated)") end
        return
    end

    -- RegisterStateDriver and the click overlays' attribute writes are
    -- combat-protected. The RC's 15s window is too short for re-showing at
    -- combat-end to be useful, so skip entirely; a hide queued by a prior
    -- check still runs at combat end.
    if InCombatLockdown() then
        if DEBUG_RCC then KE:Print("[RCC] ShowFrame: skipped (in combat).") end
        return
    end

    -- A hide queued by a previous check that finished in combat must not
    -- fire on this new row after combat ends.
    self._hidePending = nil

    -- Build frame on first use (lazy; deferred until the first ready check).
    if not self.frame then
        self:BuildFrame()
        if not self.frame then
            if DEBUG_RCC then KE:Print("[RCC] ShowFrame: BuildFrame returned nil, aborting.") end
            return
        end
    end

    -- Restore alpha in case a prior deferred hide set it to 0 (see HideFrame).
    self.frame:SetAlpha(1)

    -- Anchor selection — three cases:
    --   1. Custom position: user-defined anchor (honors db settings).
    --   2. Auto + we're the starter: ReadyCheckListenerFrame isn't shown to
    --      the initiator (Blizzard auto-readies us, no popup needed), so a
    --      child of that frame would stay hidden. Parent to UIParent and
    --      position at screen center instead. Matches MRT's rlpointer pattern.
    --   3. Auto + we're NOT the starter: anchor to ReadyCheckListenerFrame
    --      top so the row floats above the popup we see.
    self.frame:ClearAllPoints()
    if db.PositionMode == "custom" then
        self.frame:SetParent(UIParent)
        self.frame:SetPoint(
            db.SelfPoint   or "BOTTOM",
            db.AnchorFrame or "UIParent",
            db.AnchorPoint or "CENTER",
            db.XOffset or 0,
            db.YOffset or 100)
    elseif isStarter then
        self.frame:SetParent(UIParent)
        self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    else
        local parent = ReadyCheckListenerFrame or ReadyCheckFrame
        if parent then
            self.frame:SetParent(parent)
            self.frame:SetPoint("BOTTOM", parent, "TOP", 0, 2)
        else
            -- Extremely defensive fallback: if neither Blizzard frame exists
            -- (e.g. addon conflict reskin), floating at UIParent is better
            -- than not showing at all.
            self.frame:SetParent(UIParent)
            self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
    end

    -- Close button: visible only when we're the starter (Blizzard shows no
    -- Ready Check popup to the initiator, so we provide our own dismiss).
    if self.frame.closeBtn then
        if isStarter then
            self.frame.closeBtn:Show()
        else
            self.frame.closeBtn:Hide()
        end
    end

    self.frame:Show()
    -- Register the secure state driver now that the row is displayed. ShowFrame
    -- is OOC-guaranteed (InCombatLockdown guard near the top returns first), so
    -- this secure call never runs in lockdown.
    self:_EnableStateDriver()
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    -- Forced: whether the Blizzard popup this row is parented to is already
    -- visible depends on event dispatch order, and the first paint must not.
    -- UpdateAllIcons ends with the layout, so no separate call is needed.
    self:UpdateAllIcons(true)

    if DEBUG_RCC then
        local parentFrame = self.frame:GetParent()
        KE:Print(string_format("[RCC] ShowFrame: shown (isStarter=%s, parentVisible=%s).",
            tostring(isStarter), tostring(parentFrame and parentFrame:IsVisible())))
    end
end

--- HideFrame
--- Full teardown on READY_CHECK_FINISHED, Close-button click, or OnDisable.
--- Beyond frame:Hide() (which cascades to all children), this explicitly
--- stops LibCustomGlow animations, hides the click overlays so a later check
--- under an aura restriction cannot re-show stale ones, and unregisters the
--- state driver. Without the explicit glow stop, LCG's animation group can
--- continue to tick on the hidden frame, contributing to idle FPS drops.
function RCC:HideFrame()
    if not self.frame then return end

    -- Stop all LibCustomGlow animations on any slot that might have one.
    -- Rune and class (warlock soulstone) slots currently use glow; stopping
    -- all defensively future-proofs the cleanup if more glow effects are added.
    -- The flag is cleared with them so the next check can start a glow again.
    for i = 1, NUM_SLOTS do
        local btn = self.buttons[i]
        if btn then
            if LCG then
                LCG.PixelGlow_Stop(btn)
                LCG.ButtonGlow_Stop(btn)
                LCG.AutoCastGlow_Stop(btn)
                LCG.ProcGlow_Stop(btn)
            end
            btn.glowActive = false
        end
    end

    self:UnregisterEvent("PLAYER_REGEN_ENABLED")

    -- _DisableStateDriver writes to SecureStateDriverManager, a protected
    -- Blizzard frame, and the click overlays are protected too, so the rest
    -- of the teardown waits for combat to end. SetAlpha is unprotected and
    -- makes the row disappear now. The queue is KE-owned: AceEvent's
    -- UnregisterAllEvents on OnDisable cannot cancel it. _hidePending makes
    -- the queued closures idempotent and stops event repaints meanwhile.
    if InCombatLockdown() then
        self.frame:SetAlpha(0)
        self._hidePending = true
        KE:RunAfterCombat(function()
            if self._hidePending then self:HideFrame() end
        end)
        if DEBUG_RCC then KE:Print("[RCC] HideFrame: deferred (in combat, alpha=0).") end
        return
    end

    self:_DisableStateDriver()
    for i = 1, NUM_SLOTS do
        local btn = self.buttons[i]
        if btn and btn.click then
            btn.click:Hide()
        end
    end
    self.frame:Hide()
    self._hidePending = nil

    if DEBUG_RCC then KE:Print("[RCC] HideFrame: hidden (full cleanup).") end
end

---------------------------------------------------------------------------------
-- Event Handlers
---------------------------------------------------------------------------------

--- READY_CHECK fires when a ready check is initiated.
--- @param _ string          event name (unused)
--- @param initiatorUnit string  unit that started the ready check
--- @param duration number       ready check window duration in seconds
function RCC:READY_CHECK(_, initiatorUnit, duration)
    if DEBUG_RCC then
        -- initiatorUnit carries SecretInChatMessagingLockdown — guard before tostring.
        local safeName = KE:IsSafeValue(initiatorUnit) and tostring(initiatorUnit) or "<secret>"
        KE:Print(string_format("[RCC] READY_CHECK: initiator=%s duration=%.1f",
            safeName, tonumber(duration) or 0))
    end

    self:_SetCheckEvents(true)

    self:ShowFrame(initiatorUnit)
end

--- READY_CHECK_FINISHED fires when the ready check closes (all responded or timed out).
function RCC:READY_CHECK_FINISHED()
    if DEBUG_RCC then KE:Print("[RCC] READY_CHECK_FINISHED") end

    self:_SetCheckEvents(false)

    self:HideFrame()
end

-- Subscribed for the ready-check window only. The row is repainted from
-- scratch when it shows, so nothing is missed between checks, and bag and
-- cooldown events fire far too often to keep a handler on for an idle module.
local CHECK_EVENTS = {
    "UNIT_AURA", "UNIT_INVENTORY_CHANGED", "BAG_UPDATE_DELAYED",
    "GROUP_ROSTER_UPDATE", "PLAYER_SPECIALIZATION_CHANGED",
}

--- _SetCheckEvents
--- Registers or drops the per-check subscriptions. SPELL_UPDATE_COOLDOWN
--- feeds only the class slot, so a class without one never subscribes.
function RCC:_SetCheckEvents(on)
    if not on then
        for _, event in ipairs(CHECK_EVENTS) do self:UnregisterEvent(event) end
        self:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
        return
    end
    for _, event in ipairs(CHECK_EVENTS) do self:RegisterEvent(event) end
    local _, playerClass = UnitClass("player")
    if CLASS_SLOT[playerClass] then self:RegisterEvent("SPELL_UPDATE_COOLDOWN") end
end

--- UNIT_AURA fires for every unit whose aura set changes. The player's
--- auras drive the consumable slots; a party or raid member's matter only to
--- the Warlock class slot (Soulstone target tracking). Every other token is
--- dropped before it reaches the coalescer.
--- @param _ string   event name (unused)
--- @param unit string
function RCC:UNIT_AURA(_, unit)
    -- The token is secret while identities are hidden, and every branch below
    -- compares it against a literal.
    if KE:IsUnreadableAuraPayload(unit, nil) then return end
    if unit == "player" then
        if DEBUG_RCC then KE:Print("[RCC] UNIT_AURA: player auras changed, refreshing.") end
        self:RequestRefresh()
        return
    end

    local _, playerClass = UnitClass("player")
    if playerClass == "WARLOCK" and (unit:find("^party%d+$") or unit:find("^raid%d+$")) then
        if DEBUG_RCC then
            KE:Print(string_format("[RCC] UNIT_AURA: group unit %s changed, refreshing.", unit))
        end
        self:RequestRefresh()
    end
end

--- UNIT_INVENTORY_CHANGED fires for every unit whose equipment changes; only
--- the player's weapon slots are read.
function RCC:UNIT_INVENTORY_CHANGED(_, unit)
    if unit ~= "player" then return end
    if DEBUG_RCC then KE:Print("[RCC] UNIT_INVENTORY_CHANGED: refreshing.") end
    self:RequestRefresh()
end

--- BAG_UPDATE_DELAYED: a consumable acquired or used during the check.
function RCC:BAG_UPDATE_DELAYED()
    self:RequestRefresh()
end

--- GROUP_ROSTER_UPDATE: the Warlock-in-group test and the healer fallback
--- both read the roster.
function RCC:GROUP_ROSTER_UPDATE()
    self:RequestRefresh()
end

--- PLAYER_SPECIALIZATION_CHANGED: the flask preference is per spec.
function RCC:PLAYER_SPECIALIZATION_CHANGED(_, unit)
    if unit ~= "player" then return end
    self:RequestRefresh()
end

--- SPELL_UPDATE_COOLDOWN drives the class slot's cooldown proxy. A nil
--- spellID means every cooldown changed; any other spell's is irrelevant.
function RCC:SPELL_UPDATE_COOLDOWN(_, spellID, baseSpellID)
    if spellID ~= nil then
        local _, playerClass = UnitClass("player")
        local classData = CLASS_SLOT[playerClass]
        if not classData then return end
        if spellID ~= classData.spellID and baseSpellID ~= classData.spellID then return end
    end
    self:RequestRefresh()
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------

--- GetPreviewMock
--- Lazily builds a fake Ready Check popup frame used only during GUI preview.
--- Mimics the visual style of the real ReadyCheckListenerFrame so users see
--- the consumable row's anchor + sizing in context. The mock is UIParent-anchored
--- at screen center; icons anchor to its top (same offset as a real ready check).
function RCC:GetPreviewMock()
    if self.previewMock then return self.previewMock end

    local mock = CreateFrame("Frame", "KE_ReadyCheckConsumables_PreviewMock",
        UIParent, "BackdropTemplate")
    mock:SetSize(330, 115)
    mock:SetFrameStrata("HIGH")
    mock:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true, tileSize = 16, edgeSize = 16,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })

    local title = mock:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", mock, "TOP", 0, -14)
    title:SetText("Ready Check")
    title:SetTextColor(1, 0.82, 0)

    local subtitle = mock:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -6)
    subtitle:SetText("Preview")
    subtitle:SetTextColor(1, 1, 1)

    -- Buttons anchored relative to the mock's BOTTOM center so they sit
    -- close together in the middle, matching the real ready check layout.
    local readyBtn = CreateFrame("Button", nil, mock, "UIPanelButtonTemplate")
    readyBtn:SetSize(140, 32)
    readyBtn:SetPoint("BOTTOMRIGHT", mock, "BOTTOM", -4, 20)
    readyBtn:SetText("Ready")
    readyBtn:EnableMouse(false)

    local notReadyBtn = CreateFrame("Button", nil, mock, "UIPanelButtonTemplate")
    notReadyBtn:SetSize(140, 32)
    notReadyBtn:SetPoint("BOTTOMLEFT", mock, "BOTTOM", 4, 20)
    notReadyBtn:SetText("Not Ready")
    notReadyBtn:EnableMouse(false)

    mock:Hide()
    self.previewMock = mock
    return mock
end

--- BuildPreviewFrame
--- The settings preview's own container: the 7 visual stubs on a plain
--- UIParent frame, with no state frame, click overlays or Close button. A
--- real ready check and a preview can therefore be on screen together
--- without either touching the other's frames.
function RCC:BuildPreviewFrame()
    if self.previewFrame then return end
    local db = self.db
    if not db then return end

    local iconSize = db.IconSize or 32
    local spacing  = db.IconSpacing or 4

    local f = CreateFrame("Frame", "KE_ReadyCheckConsumables_Preview", UIParent)
    f:SetSize((iconSize * NUM_SLOTS) + (spacing * (NUM_SLOTS - 1)), iconSize)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 85)
    f:SetFrameStrata("HIGH")
    f:Hide()

    self.previewButtons = self:_BuildIconRow(f)
    self.previewFrame = f
end

--- ShowPreview
--- Display the preview row + a mock Ready Check popup at UIParent center.
--- Respects user category toggles (Show<Category>) so disabling a category
--- hides it from preview immediately. Ignores context-dependent visibility
--- (OH weapon state, class match) so the preview stays consistent regardless
--- of what the player is currently wearing or which class they're on.
--- Skipped entirely in KES edit mode — this module's frame is contextually
--- anchored to ReadyCheckListenerFrame, not manually positioned by the user,
--- so it doesn't need an edit-mode drag target.
function RCC:ShowPreview()
    local db = self.db
    if not db then return end

    if KE.PreviewManager and KE.PreviewManager.editModeActive then
        return
    end

    if not self.previewFrame then
        self:BuildPreviewFrame()
        if not self.previewFrame then return end
    end
    local frame = self.previewFrame

    self.inPreview = true

    frame:ClearAllPoints()
    if db.HidePreviewMock then
        -- Mock popup suppressed — anchor the row slightly above screen center,
        -- roughly where the row would sit above the mock when the box is shown.
        if self.previewMock then self.previewMock:Hide() end
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 85)
    else
        -- Show mock popup at screen center, anchor consumable row to its top
        -- (same 5px gap as the real ReadyCheckListenerFrame anchor).
        local mock = self:GetPreviewMock()
        mock:ClearAllPoints()
        mock:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        mock:Show()
        frame:SetPoint("BOTTOM", mock, "TOP", 0, 2)
    end

    -- User-toggle visibility map. No context filters — this is a settings preview.
    local visibility = {
        [SLOT_FOOD]   = db.ShowFood        ~= false,
        [SLOT_FLASK]  = db.ShowFlask       ~= false,
        [SLOT_OIL]    = db.ShowWeaponOil   ~= false,
        [SLOT_OILOH]  = db.ShowOffHandOil  ~= false,
        [SLOT_RUNE]   = db.ShowAugmentRune ~= false,
        [SLOT_HS]     = db.ShowHealthstone ~= false,
        [SLOT_CLASS]  = db.ShowClassItem   ~= false,
    }

    self:_LayoutRow(frame, self.previewButtons, visibility)
    frame:Show()
end

--- HidePreview
--- Exit preview mode. PreviewManager calls this on every GUI open and close
--- for each registry module, so it must tolerate a preview that was never
--- built.
function RCC:HidePreview()
    self.inPreview = false

    if self.previewMock then
        self.previewMock:Hide()
    end
    if self.previewFrame then
        self.previewFrame:Hide()
    end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------

function RCC:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function RCC:OnEnable()
    if not self.db or not self.db.Enabled then return end

    -- Frame is built lazily on the first ready check (ShowFrame's combat-guarded
    -- BuildFrame fallback). Deferring avoids creating 7 buttons + the secure
    -- state frame for sessions that never run a ready check (solo, world
    -- content). ShowFrame's InCombatLockdown guard runs before its BuildFrame
    -- fallback, so the build is always out of combat — the old eager build
    -- bought nothing the fallback doesn't already cover.

    -- Core events always registered while module is enabled
    self:RegisterEvent("READY_CHECK")
    self:RegisterEvent("READY_CHECK_FINISHED")

    -- The refresh triggers (CHECK_EVENTS and SPELL_UPDATE_COOLDOWN) are
    -- registered only during an active ready check (in READY_CHECK handler)
    -- and unregistered in READY_CHECK_FINISHED to avoid unnecessary
    -- processing at all other times.

    if DEBUG_RCC then KE:Print("[RCC] OnEnable") end
end

function RCC:OnDisable()
    self:UnregisterAllEvents()
    self:HideFrame()
    self:HidePreview()
    self._lastSoulstoneTarget = nil

    if DEBUG_RCC then KE:Print("[RCC] OnDisable") end
end

-- Tier 2: the enchant helper's two testable pieces.
--
-- Scope is deliberate (AGENTS.md tiered test policy). The popup, its rows and
-- the bar anchoring are a port of NorskenUI v6 CharacterPanel.lua:1269-1562 and
-- are verified by diffing against that source plus an in-game smoke -- a spec
-- there would only encode the porter's reading. What IS covered:
--
--   1. GetEnchantTargetSlots' keyword resolution. This is NOT a verbatim port:
--      the reference walks its keyword table with pairs() and returns on the
--      first hit, so a tooltip matching two keywords resolves differently
--      between sessions. KE sorts longest-key-first instead. That is invented
--      branching logic, so it gets a test.
--   2. The combat refusal on applying an enchant. A guard rule that fails
--      silently and is awkward to smoke (you would have to pull a mob first).
local helpers = require("dev.spec._helpers")

local function loadCP(overrides)
    helpers.installAddonShim()

    -- Captured as file-locals when CharacterPanel.lua loads, so they must be
    -- installed BEFORE loadModule, not after.
    _G.C_TooltipInfo = { GetHyperlink = function() return nil end }
    _G.C_Item = { GetItemInfoInstant = function() return nil end }
    _G.C_Container = {}
    _G.C_Timer = { After = function() end }
    _G.CreateFrame = function() return nil end
    _G.InCombatLockdown = function() return false end
    _G.ENCHANTED_TOOLTIP_LINE = "Enchanted: %s"
    for _, name in ipairs({
        "GetInventoryItemLink", "GetExpansionForLevel", "UnitLevel",
        "IsLevelAtEffectiveMaxLevel", "GetInventoryItemQuality", "issecretvalue",
    }) do
        _G[name] = _G[name] or function() return nil end
    end
    _G.strsplit = function() return nil end
    -- INVSLOT_* are plain numbers in WoW; the module builds lookup tables keyed
    -- by them at load, so nil would collapse several keys onto one another.
    local invslots = {
        INVSLOT_HEAD = 1, INVSLOT_NECK = 2, INVSLOT_SHOULDER = 3, INVSLOT_CHEST = 5,
        INVSLOT_WAIST = 6, INVSLOT_LEGS = 7, INVSLOT_FEET = 8, INVSLOT_WRIST = 9,
        INVSLOT_FINGER1 = 11, INVSLOT_FINGER2 = 12, INVSLOT_BACK = 15,
        INVSLOT_MAINHAND = 16, INVSLOT_OFFHAND = 17,
    }
    for name, id in pairs(invslots) do _G[name] = id end

    for k, v in pairs(overrides or {}) do _G[k] = v end

    -- KE.GEM_SOCKET_TYPES is read at file scope (EMPTY_SOCKET_ICON is built
    -- from it), so the seed has to carry it.
    local KE = {
        GEM_SOCKET_TYPES = { { name = "Prismatic", locale = "EMPTY_SOCKET_PRISMATIC", icon = 1 } },
        Print = function() end,
    }
    helpers.loadModule("Modules/QoL/CharacterPanel.lua", KE)
    return _G.KitnEssentials:GetModule("CharacterPanel"), KE
end

-- Builds a C_TooltipInfo.GetHyperlink stand-in returning one tooltip line.
local function tooltipSaying(line)
    return { GetHyperlink = function() return { lines = { { leftText = line } } } end }
end

describe("Enchant helper: target slot resolution", function()
    it("resolves a plain weapon enchant to both weapon slots", function()
        local CP = loadCP({ C_TooltipInfo = tooltipSaying("Enchant Weapon - Authority of Air") })
        assert.same({ 16, 17 }, CP._GetEnchantTargetSlots("item:1"))
    end)

    it("resolves a cloak enchant to the back slot", function()
        local CP = loadCP({ C_TooltipInfo = tooltipSaying("Enchant Cloak - Chant of Winged Grace") })
        assert.same({ 15 }, CP._GetEnchantTargetSlots("item:1"))
    end)

    it("resolves a ring enchant to BOTH finger slots", function()
        local CP = loadCP({ C_TooltipInfo = tooltipSaying("Enchant Ring - Radiant Critical Strike") })
        assert.same({ 11, 12 }, CP._GetEnchantTargetSlots("item:1"))
    end)

    -- THE REGRESSION GUARD. "Enchant 2H Weapon - ..." contains both the
    -- "2h weapon" keyword ({16}) and the "weapon" keyword ({16, 17}). Under the
    -- reference's pairs() walk either could win. Longest-key-first must pick the
    -- more specific one every time. Revert enchantKeywordOrder to a pairs()
    -- loop and this starts failing intermittently.
    it("prefers the most specific keyword when a tooltip matches two", function()
        local CP = loadCP({ C_TooltipInfo = tooltipSaying("Enchant 2H Weapon - Oathsworn's Strength") })
        assert.same({ 16 }, CP._GetEnchantTargetSlots("item:1"))
    end)

    -- Same assertion, repeated against freshly built order tables. A pairs()
    -- implementation can happen to give the right answer once; it cannot give
    -- it on every independent load.
    it("gives the same answer on repeated independent loads", function()
        for _ = 1, 25 do
            local CP = loadCP({ C_TooltipInfo = tooltipSaying("Enchant 2H Weapon - Oathsworn's Strength") })
            assert.same({ 16 }, CP._GetEnchantTargetSlots("item:1"))
        end
    end)

    it("negative control: an unrelated tooltip resolves to no slot", function()
        local CP = loadCP({ C_TooltipInfo = tooltipSaying("Conjured Mana Bun") })
        assert.is_nil(CP._GetEnchantTargetSlots("item:1"))
    end)

    it("returns nil without a link, and without tooltip data", function()
        local CP = loadCP()
        assert.is_nil(CP._GetEnchantTargetSlots(nil))
        assert.is_nil(CP._GetEnchantTargetSlots("item:1"))
    end)
end)

describe("Enchant helper: combat refusal", function()
    local function armed(inCombat)
        local used = {}
        local CP, KE = loadCP({
            InCombatLockdown = function() return inCombat end,
            C_Container = {
                UseContainerItem = function(bag, slot)
                    used[#used + 1] = { bag = bag, slot = slot }
                end,
            },
        })
        -- The real ones need frames; the refusal path must not reach them anyway.
        CP.HideEnchantPopup = function() end
        CP.HideSlotHighlight = function() end
        return CP, KE, used
    end

    it("picks the enchant up out of combat", function()
        local CP, _, used = armed(false)
        assert.is_true(CP:ApplyEnchantFromBags({ bagID = 3, slotID = 7 }))
        assert.equals(1, #used)
        assert.same({ bag = 3, slot = 7 }, used[1])
    end)

    it("refuses in combat and touches no bag slot", function()
        local CP, _, used = armed(true)
        assert.is_false(CP:ApplyEnchantFromBags({ bagID = 3, slotID = 7 }))
        assert.equals(0, #used)
    end)

    it("tells the player why it refused", function()
        local CP, KE = armed(true)
        local said
        KE.Print = function(_, msg) said = msg end
        CP:ApplyEnchantFromBags({ bagID = 3, slotID = 7 })
        assert.is_truthy(said)
        assert.is_truthy(said:lower():find("combat", 1, true))
    end)

    it("does nothing without enchant data, even out of combat", function()
        local CP, _, used = armed(false)
        assert.is_false(CP:ApplyEnchantFromBags(nil))
        assert.equals(0, #used)
    end)
end)

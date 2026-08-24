-- Tier 2: the enchant helper's two testable pieces.
--
-- Scope is deliberate (AGENTS.md tiered test policy). The popup, its rows and
-- the bar anchoring are verified by an in-game smoke -- a spec
-- there would only encode the author's reading. What IS covered:
--
--   1. GetEnchantTargetSlots' keyword resolution. Walking the keyword table
--      with pairs() and returning on the
--      first hit resolves a two-keyword tooltip differently
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
        "GetInventoryItemQuality", "issecretvalue",
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
    -- "2h weapon" keyword ({16}) and the "weapon" keyword ({16, 17}). Under a
    -- pairs() walk either could win. Longest-key-first must pick the
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

-- A refusal rule, so it is tested even though the list it guards is a data
-- table (AGENTS.md: guard rules WIN over the verbatim-port exemption).
describe("Enchant helper: slots we refuse to offer", function()
    it("refuses leg armour kits", function()
        local CP = loadCP()
        assert.is_true(CP._IsUnofferableEnchant({ 7 }))
    end)

    -- THE REGRESSION GUARD. Head was briefly on the refusal list on the theory
    -- that it stopped being enchantable after Mists. Midnight ships current
    -- helm enchants and the mistake hid a working one, so head must stay
    -- offerable. Two head-targeting LEGACY items do fail, and those are handled
    -- by item id, not by slot.
    it("still offers head, which Midnight enchants", function()
        local CP = loadCP()
        assert.is_false(CP._IsUnofferableEnchant({ 1 }))
    end)

    it("offers every other enchantable slot", function()
        local CP = loadCP()
        for _, slots in ipairs({ { 5 }, { 15 }, { 9 }, { 8 }, { 11, 12 }, { 16, 17 }, { 16 } }) do
            assert.is_false(CP._IsUnofferableEnchant(slots), table.concat(slots, ","))
        end
    end)

    -- The half-and-half case. Refusing on ANY unofferable slot rather than ALL
    -- of them would silently drop a real enchant that happens to list one.
    it("keeps an enchant whose other target slot is fine", function()
        local CP = loadCP()
        assert.is_false(CP._IsUnofferableEnchant({ 7, 5 }))
    end)

    it("refuses a nil slot list rather than offering it", function()
        local CP = loadCP()
        assert.is_true(CP._IsUnofferableEnchant(nil))
    end)
end)

-- The item blacklist. Also a refusal rule, and the one most likely to be
-- "cleaned up" by someone who reads it as a stray magic number.
describe("Enchant helper: items we refuse to offer", function()
    it("refuses Incandescent Essence, which blocks UseContainerItem", function()
        local CP = loadCP()
        assert.is_false(CP._IsOfferableEnchant(210494, { 1 }))
    end)

    -- Same slot, same subclass, different item: the blacklist must be reading
    -- the ITEM. Refusing by slot instead is the mistake this guards against.
    it("still offers the current helm enchant that shares its slot", function()
        local CP = loadCP()
        assert.is_true(CP._IsOfferableEnchant(244007, { 1 }))
    end)

    it("applies the slot refusal too, for an item not on the list", function()
        local CP = loadCP()
        assert.is_false(CP._IsOfferableEnchant(999999, { 7 }))
    end)

    it("refuses a blacklisted item even when its slot is fine", function()
        local CP = loadCP()
        assert.is_false(CP._IsOfferableEnchant(210494, { 5 }))
    end)
end)

-- The gem popup's sibling of the enchant bag-slot guard. Its row caches the
-- bag position it was scanned from, and bags move under an open popup, so the
-- source gem has to be re-resolved before it is picked up. A refusal rule, so
-- it is specced even though the socket sequence around it is not.
describe("Gem helper: resolving the source gem at click time", function()
    -- bags: { [bag] = { [slot] = itemID } }
    local function withBags(bags)
        return loadCP({
            C_Container = {
                GetContainerNumSlots = function(bag) return bags[bag] and 20 or 0 end,
                GetContainerItemID = function(bag, slot)
                    return bags[bag] and bags[bag][slot] or nil
                end,
            },
        })
    end

    it("finds the gem where it actually is now, not where the row cached it", function()
        local CP = withBags({ [2] = { [11] = 5555 } })
        local bag, slot = CP:ResolveGemSource({ itemID = 5555, bagID = 0, slotID = 1 })
        assert.equals(2, bag)
        assert.equals(11, slot)
    end)

    it("refuses when the gem has left the bags entirely", function()
        local CP = withBags({ [2] = { [11] = 9999 } })
        assert.is_nil(CP:ResolveGemSource({ itemID = 5555, bagID = 2, slotID = 11 }))
    end)

    it("refuses without gem data, and without an item id", function()
        local CP = withBags({ [2] = { [11] = 5555 } })
        assert.is_nil(CP:ResolveGemSource(nil))
        assert.is_nil(CP:ResolveGemSource({ bagID = 2, slotID = 11 }))
    end)
end)

-- The CLICK ACTION, not the resolver behind it. Testing only the resolver
-- leaves the call site free to go back to the cached bag position with every
-- test still green -- which is exactly what the first version of this spec did.
describe("Gem helper: the click action refuses a gem that has moved", function()
    local function armed(bags)
        local picked, sockets, hidden = {}, {}, { popup = 0, glow = 0 }
        local CP = loadCP({
            C_Container = {
                GetContainerNumSlots = function(bag) return bags[bag] and 20 or 0 end,
                GetContainerItemID = function(bag, slot)
                    return bags[bag] and bags[bag][slot] or nil
                end,
                PickupContainerItem = function(bag, slot)
                    picked[#picked + 1] = { bag = bag, slot = slot }
                end,
            },
            -- Recorders, not a fake socketing subsystem: nothing below asserts
            -- on the sequence, they exist so the success path can run at all.
            SocketInventoryItem = function(slotID) sockets[#sockets + 1] = slotID end,
            C_ItemSocketInfo = { ClickSocketButton = function() end },
            ClearCursor = function() end,
            AcceptSockets = function() end,
            CloseSocketInfo = function() end,
            HideUIPanel = function() end,
            ItemSocketingFrame = nil,
        })
        CP.HideGemPopup = function() hidden.popup = hidden.popup + 1 end
        CP.HideSlotHighlight = function() hidden.glow = hidden.glow + 1 end
        CP.RefreshSocketButtons = function() end
        return CP, picked, sockets, hidden
    end

    it("refuses, and opens no socket session, when the gem is gone", function()
        local CP, picked, sockets, hidden = armed({ [2] = { [11] = 9999 } })
        assert.is_false(CP:SocketGemFromPopup({ itemID = 5555, bagID = 2, slotID = 11 }, 5, 1))
        assert.equals(0, #picked)
        assert.equals(0, #sockets)
        assert.equals(1, hidden.popup)
        assert.equals(1, hidden.glow)
    end)

    -- THE REGRESSION GUARD. The row's cached position is bag 0 slot 1; the gem
    -- is really in bag 2 slot 11. Reading the cache instead picks up whatever
    -- now sits in bag 0 slot 1.
    it("picks the gem up where it is now, not where the row cached it", function()
        local CP, picked = armed({ [2] = { [11] = 5555 } })
        assert.is_true(CP:SocketGemFromPopup({ itemID = 5555, bagID = 0, slotID = 1 }, 5, 1))
        assert.equals(1, #picked)
        assert.same({ bag = 2, slot = 11 }, picked[1])
    end)
end)

describe("Enchant helper: combat refusal", function()
    -- occupantID: what GetContainerItemInfo reports is actually sitting in the
    -- row's cached bag slot at click time. Defaults to the row's own item;
    -- pass something else to model bags having moved under an open popup.
    local function armed(inCombat, occupantID)
        local used = {}
        local CP, KE = loadCP({
            InCombatLockdown = function() return inCombat end,
            C_Container = {
                UseContainerItem = function(bag, slot)
                    used[#used + 1] = { bag = bag, slot = slot }
                end,
                GetContainerItemInfo = function()
                    if occupantID == false then return nil end
                    return { itemID = occupantID or 243977 }
                end,
            },
        })
        -- The real ones need frames; the refusal path must not reach them anyway.
        CP.HideEnchantPopup = function() end
        CP.HideSlotHighlight = function() end
        return CP, KE, used
    end

    -- Shaped like what ScanBagsForEnchants actually stores. itemID and
    -- targetSlots are load-bearing now: the click path re-checks the refusals,
    -- so a fixture missing them is refused before combat is ever consulted.
    local function chestEnchant()
        return { itemID = 243977, bagID = 3, slotID = 7, targetSlots = { 5 } }
    end

    it("picks the enchant up out of combat", function()
        local CP, _, used = armed(false)
        assert.is_true(CP:ApplyEnchantFromBags(chestEnchant()))
        assert.equals(1, #used)
        assert.same({ bag = 3, slot = 7 }, used[1])
    end)

    it("refuses in combat and touches no bag slot", function()
        local CP, _, used = armed(true)
        assert.is_false(CP:ApplyEnchantFromBags(chestEnchant()))
        assert.equals(0, #used)
    end)

    it("tells the player why it refused", function()
        local CP, KE = armed(true)
        local said
        KE.Print = function(_, msg) said = msg end
        CP:ApplyEnchantFromBags(chestEnchant())
        assert.is_truthy(said)
        assert.is_truthy(said:lower():find("combat", 1, true))
    end)

    it("does nothing without enchant data, even out of combat", function()
        local CP, _, used = armed(false)
        assert.is_false(CP:ApplyEnchantFromBags(nil))
        assert.equals(0, #used)
    end)

    -- The click path re-checks the blacklist rather than trusting the row.
    it("refuses a blacklisted item on click, out of combat", function()
        local CP, _, used = armed(false)
        local blocked = chestEnchant()
        blocked.itemID = 210494
        assert.is_false(CP:ApplyEnchantFromBags(blocked))
        assert.equals(0, #used)
    end)

    -- Combat is checked FIRST, so the player still gets told why. Reordering
    -- the two guards would silently swallow the combat message.
    it("blames combat, not the blacklist, when both would refuse", function()
        local CP, KE = armed(true)
        local said
        KE.Print = function(_, msg) said = msg end
        local blocked = chestEnchant()
        blocked.itemID = 210494
        CP:ApplyEnchantFromBags(blocked)
        assert.is_truthy(said)
        assert.is_truthy(said:lower():find("combat", 1, true))
    end)

    -- THE BYPASS. Every check above reads the row's CACHED item id, but the
    -- call acts on a cached bag SLOT, and bags move under an open popup. Vet
    -- one item and use another and the blacklist means nothing.
    it("refuses when another item now occupies the cached bag slot", function()
        local CP, _, used = armed(false, 210494)
        assert.is_false(CP:ApplyEnchantFromBags(chestEnchant()))
        assert.equals(0, #used)
    end)

    it("refuses when the cached bag slot is now empty", function()
        local CP, _, used = armed(false, false)
        assert.is_false(CP:ApplyEnchantFromBags(chestEnchant()))
        assert.equals(0, #used)
    end)

    it("proceeds when the slot still holds the item the row was built from", function()
        local CP, _, used = armed(false, 243977)
        assert.is_true(CP:ApplyEnchantFromBags(chestEnchant()))
        assert.equals(1, #used)
    end)
end)

---------------------------------------------------------------------------------
-- Item F: the inspect-side toggle
---------------------------------------------------------------------------------
describe("Inspect Item Info toggle", function()
    -- A recording stand-in for the InspectPanel module, so the assertion is
    -- "was it asked to enable" rather than "did anything happen".
    local function withInspectStub(fn)
        local calls = {}
        local CP = loadCP()
        local addon = _G.KitnEssentials
        local prior = addon.GetModule
        addon.GetModule = function(_, name)
            if name == "InspectPanel" then
                return {
                    Enable = function() calls[#calls + 1] = "Enable" end,
                    Disable = function() calls[#calls + 1] = "Disable" end,
                }
            end
            return nil
        end
        local ok, err = pcall(fn, CP, calls)
        addon.GetModule = prior
        if not ok then error(err, 0) end
    end

    it("enables the inspect module when the module is up and the key is on", function()
        withInspectStub(function(CP, calls)
            CP.db = { Enabled = true, InspectPanelEnabled = true }
            CP.IsEnabled = function() return true end
            CP:ApplyInspectPanelState()
            assert.same({ "Enable" }, calls)
        end)
    end)

    it("disables it when only the inspect key is off", function()
        withInspectStub(function(CP, calls)
            CP.db = { Enabled = true, InspectPanelEnabled = false }
            CP.IsEnabled = function() return true end
            CP:ApplyInspectPanelState()
            assert.same({ "Disable" }, calls)
        end)
    end)

    -- The key stays TRUE here. `CP:Disable()` is reachable without the profile
    -- changing, so reading `db.Enabled` instead would wake the inspect module
    -- while CharacterPanel itself is down.
    it("disables it when the MODULE is down, whatever the inspect key says", function()
        withInspectStub(function(CP, calls)
            CP.db = { Enabled = true, InspectPanelEnabled = true }
            CP.IsEnabled = function() return false end
            CP:ApplyInspectPanelState()
            assert.same({ "Disable" }, calls)
        end)
    end)

    it("treats an absent inspect key as on, so an old profile keeps its overlays", function()
        withInspectStub(function(CP, calls)
            CP.db = { Enabled = true }
            CP.IsEnabled = function() return true end
            CP:ApplyInspectPanelState()
            assert.same({ "Enable" }, calls)
        end)
    end)
end)

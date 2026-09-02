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
        "CursorHasItem", "SpellIsTargeting", "PickupInventoryItem",
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
        IsSafeValue = function(_, v) return v ~= nil end,
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

---------------------------------------------------------------------------------
-- Item A: enchant name style
---------------------------------------------------------------------------------
describe("Enchant name style", function()
    local RAW = "Enchant Ring - Radiant Critical Strike"

    it("gives three DIFFERENT labels for one input", function()
        local CP = loadCP()
        local short = CP._ProcessEnchantText(RAW, "short")
        local verbose = CP._ProcessEnchantText(RAW, "verbose")
        local full = CP._ProcessEnchantText(RAW, "full")
        -- If any two agree, the styles have not been distinguished and this
        -- test has proved nothing.
        assert.are_not.equal(short, verbose)
        assert.are_not.equal(verbose, full)
        assert.are_not.equal(short, full)
    end)

    it("full keeps the effect name and drops only the slot preamble", function()
        local CP = loadCP()
        assert.equals("Radiant Critical Strike", CP._ProcessEnchantText(RAW, "full"))
    end)

    it("verbose reduces to the last non-filler word", function()
        local CP = loadCP()
        assert.equals("Strike", CP._ProcessEnchantText(RAW, "verbose"))
    end)

    it("an unknown or absent style resolves as short", function()
        local CP = loadCP()
        local short = CP._ProcessEnchantText(RAW, "short")
        assert.equals(short, CP._ProcessEnchantText(RAW, nil))
        assert.equals(short, CP._ProcessEnchantText(RAW, "nonsense"))
    end)

    -- The "+" strip is unanchored, so leaving it in the prefix table would eat
    -- the sign under every style. "full" is defined as the tooltip's own text,
    -- so it must keep it; short must still drop it.
    it("full keeps a leading + that short drops", function()
        local CP = loadCP()
        local raw = "Enchant Ring - +10 Stats"
        assert.equals("+10 Stats", CP._ProcessEnchantText(raw, "full"))
        assert.is_nil(CP._ProcessEnchantText(raw, "short"):find("+", 1, true))
    end)

    -- The cache defect. This case MUST be seen to fail against a cache keyed
    -- on the raw text alone: that is what proves it tests the key and not
    -- merely the resolver.
    it("does not serve one style's label from another style's cache entry", function()
        local CP = loadCP()
        local first = CP._ProcessEnchantText(RAW, "full")
        local second = CP._ProcessEnchantText(RAW, "verbose")
        assert.equals("Radiant Critical Strike", first)
        assert.equals("Strike", second)
        -- And back again, to catch a cache that only breaks in one direction.
        assert.equals("Radiant Critical Strike", CP._ProcessEnchantText(RAW, "full"))
    end)
end)

---------------------------------------------------------------------------------
-- Item H: conditional auto-apply
---------------------------------------------------------------------------------
describe("Enchant auto-apply: unambiguous slot resolution", function()
    it("returns the one slot when only one candidate is equipped", function()
        local CP = loadCP({
            GetInventoryItemLink = function(_, slot) return slot == 11 and "link" or nil end,
        })
        assert.equals(11, CP._UnambiguousEnchantSlot({ 11, 12 }))
    end)

    -- The whole reason the feature is safe. Two rings means the player picks.
    it("returns nil when BOTH rings are equipped", function()
        local CP = loadCP({
            GetInventoryItemLink = function() return "link" end,
        })
        assert.is_nil(CP._UnambiguousEnchantSlot({ 11, 12 }))
    end)

    it("returns nil when no candidate is equipped", function()
        local CP = loadCP({
            GetInventoryItemLink = function() return nil end,
        })
        assert.is_nil(CP._UnambiguousEnchantSlot({ 11, 12 }))
    end)
end)

describe("Enchant auto-apply: the weapon-slot branch", function()
    it("counts a real weapon as a candidate", function()
        local CP = loadCP({
            GetInventoryItemLink = function(_, slot) return slot == 16 and "link" or nil end,
            C_Item = { GetItemInfoInstant = function() return 1, nil, nil, "INVTYPE_WEAPONMAINHAND" end },
        })
        assert.is_true(CP._SlotHoldsEnchantTarget(16))
    end)

    it("does not count an off-hand shield as a weapon candidate", function()
        local CP = loadCP({
            GetInventoryItemLink = function(_, slot) return slot == 17 and "link" or nil end,
            C_Item = { GetItemInfoInstant = function() return 1, nil, nil, "INVTYPE_SHIELD" end },
        })
        assert.is_false(CP._SlotHoldsEnchantTarget(17))
    end)

    -- The fail-safe DIRECTION. Unreadable reports its own third state rather
    -- than a boolean, so the resolver can refuse instead of guessing.
    it("reports an UNREADABLE equip location as unknown, not as a plain candidate", function()
        local CP = loadCP({
            GetInventoryItemLink = function(_, slot) return slot == 16 and "link" or nil end,
            C_Item = { GetItemInfoInstant = function() error("unreadable") end },
        })
        assert.equals("unknown", CP._SlotHoldsEnchantTarget(16))
    end)

    -- The case that makes the third state worth having. With unreadable
    -- returning a plain `true`, a SOLE unreadable slot is the only candidate,
    -- reads as unambiguous, and gets the enchant spent on it -- the opposite of
    -- the intended caution, and invisible to the boolean case above.
    it("REFUSES when the only candidate is a slot it cannot read", function()
        local CP = loadCP({
            GetInventoryItemLink = function(_, slot) return slot == 16 and "link" or nil end,
            C_Item = { GetItemInfoInstant = function() error("unreadable") end },
        })
        assert.is_nil(CP._UnambiguousEnchantSlot({ 16, 17 }))
    end)

    it("counts any non-weapon slot holding an item, without asking about type", function()
        local CP = loadCP({
            GetInventoryItemLink = function(_, slot) return slot == 15 and "link" or nil end,
        })
        assert.is_true(CP._SlotHoldsEnchantTarget(15))
    end)

    it("counts an empty slot as no candidate", function()
        local CP = loadCP({ GetInventoryItemLink = function() return nil end })
        assert.is_false(CP._SlotHoldsEnchantTarget(15))
    end)
end)

---------------------------------------------------------------------------------
-- Item H: the auto-apply ACTION itself
--
-- The predicate cases above prove which slot would be chosen. They say nothing
-- about whether the action fires, so the whole PickupInventoryItem block could be
-- deleted and every one of them would still pass. These six drive
-- ApplyEnchantFromBags and assert on the call.
---------------------------------------------------------------------------------
describe("Enchant auto-apply: the action", function()
    -- Returns the CP under test plus a ledger of PickupInventoryItem calls, with
    -- the bag re-read and the offerable check satisfied so the function reaches
    -- its tail. Overrides are merged in, so a case can flip one input.
    -- SpellIsTargeting is STATEFUL here, and it has to be. The production code
    -- refuses when a spell is already targeting on entry, then reads targeting
    -- AFTER UseContainerItem as proof the enchant started. A stub that returns a
    -- constant true would be refused at the door and could never reach the
    -- pickup; a constant false could never reach it either. Only the false-to-true
    -- transition the real API performs exercises the path.
    local function applyFixture(overrides)
        local picked, started = {}, false
        local o = {
            C_Container = {
                GetContainerItemInfo = function() return { itemID = 1 } end,
                UseContainerItem = function() started = true end,
            },
            GetInventoryItemLink = function(_, slot) return slot == 16 and "link" or nil end,
            C_Item = { GetItemInfoInstant = function() return 1, nil, nil, "INVTYPE_WEAPON" end },
            CursorHasItem = function() return false end,
            SpellIsTargeting = function() return started end,
            PickupInventoryItem = function(slot) picked[#picked + 1] = slot end,
        }
        for k, v in pairs(overrides or {}) do o[k] = v end
        local CP = loadCP(o)
        CP.HideEnchantPopup = function() end
        CP.HideSlotHighlight = function() end
        return CP, picked
    end

    local function enchantData()
        return { itemID = 1, bagID = 0, slotID = 1, targetSlots = { 16, 17 } }
    end

    it("applies to the one candidate slot when a spell is waiting for a target", function()
        local CP, picked = applyFixture()
        CP:ApplyEnchantFromBags(enchantData())
        assert.same({ 16 }, picked)
    end)

    -- The refusal that keeps a loaded cursor from being equipped into the slot.
    it("REFUSES outright when something is already on the cursor", function()
        local CP, picked = applyFixture({ CursorHasItem = function() return true end })
        assert.is_false(CP:ApplyEnchantFromBags(enchantData()))
        assert.same({}, picked)
    end)

    -- The other half of the same refusal, and the subtler one. Auto-apply reads
    -- "a spell is now waiting for a target" as proof OUR enchant started. That
    -- reading is only sound if nothing was waiting beforehand -- otherwise an
    -- unrelated targeting spell plus a silently failed UseContainerItem fires the
    -- pickup with no enchant pending, which unequips the item.
    it("REFUSES outright when a spell is already waiting for a target", function()
        -- True on ENTRY, before UseContainerItem runs. That is the state the
        -- fixture's transition stub cannot reach on its own.
        local CP, picked = applyFixture({ SpellIsTargeting = function() return true end })
        assert.is_false(CP:ApplyEnchantFromBags(enchantData()))
        assert.same({}, picked)
    end)

    -- Without this the call fires on an idle cursor and picks UP the equipped
    -- item, which unequips it.
    -- UseContainerItem ran but no spell ended up waiting -- a silent failure.
    -- Overriding with a constant false defeats the fixture's transition, which is
    -- exactly the state being tested.
    it("does not fire when no spell is waiting for a target afterwards", function()
        local CP, picked = applyFixture({ SpellIsTargeting = function() return false end })
        CP:ApplyEnchantFromBags(enchantData())
        assert.same({}, picked)
    end)

    -- The POST-call cursor check, which nothing else reaches. The entry refusal
    -- sees an empty cursor; UseContainerItem then loads the cursor instead of
    -- starting a targeting spell. Without the second check, PickupInventoryItem
    -- equips that item into the slot -- the same accident, one step later.
    it("does not fire when UseContainerItem loads the cursor instead", function()
        -- Both stubs read one flag, so the ENTRY gate sees an idle cursor and the
        -- POST-call test sees a loaded one. Overriding C_Container replaces the
        -- fixture's own transition, so this case carries its own.
        local used = false
        local CP, picked = applyFixture({
            CursorHasItem = function() return used end,
            SpellIsTargeting = function() return used end,
            C_Container = {
                GetContainerItemInfo = function() return { itemID = 1 } end,
                UseContainerItem = function() used = true end,
            },
        })
        CP:ApplyEnchantFromBags(enchantData())
        assert.same({}, picked)
    end)

    it("does not fire when the slot is a judgement call", function()
        local CP, picked = applyFixture({
            GetInventoryItemLink = function() return "link" end,
        })
        CP:ApplyEnchantFromBags(enchantData())
        assert.same({}, picked)
    end)
end)

-- Tier 1: KE:EUISheetActive / KE:EUIDrawsSlotElement (Core/Globals.lua).
--
-- These decide, per frame and per element, whether EllesmereUI is already
-- drawing something so CharacterPanel can stand down. Invented branching logic
-- with two asymmetries that a later edit would break silently, so it is tested
-- (AGENTS.md tiered test policy):
--
--   * EUI's inspect sheet draws NO gems at any setting, so a gem stand-down
--     must never fire on the inspect frame.
--   * "missingEnchant" is not one flag. On the CHARACTER sheet EUI's pulsing
--     red border fires outside its showEnchants branch, so EUI marks the slot
--     even with enchant display off. On the INSPECT sheet the cue is only an
--     icon and that icon IS gated, so with inspectShowEnchants off nothing
--     marks it and ours must show.
--
-- Getting either wrong deletes a display from BOTH addons, which is worse than
-- the doubling the gate exists to remove.
local L = require("dev.spec._ke_loader")

-- L.loadGlobals already stands up the WoW surface Core/Globals.lua touches at
-- load (LibStub/LSM, SlashCmdList, UIParent, addon metadata). Only the two
-- things the gate actually reads are set here: whether EUI's skin addon is
-- loaded, and EUI's saved variables. The addon half goes in BEFORE the load
-- (Core/Globals.lua localizes C_AddOns at file scope); the saved variables go
-- in after, because the gate reads them live on every call.
local function loadGlobals(euiDB, opts)
    opts = opts or {}
    local KE = L.loadGlobals(nil, {
        loadedAddOns = opts.notLoaded and {} or { EllesmereUIBlizzardSkin = true },
    })
    -- Written after the load: the gate reads them live, per call.
    _G.EllesmereUIDB = euiDB
    _G.EllesmereUI = opts.euiNamespace
    return KE
end

describe("EUISheetActive", function()
    it("is false when the skin addon is not loaded", function()
        local KE = loadGlobals({}, { notLoaded = true })
        assert.is_false(KE:EUISheetActive("player"))
        assert.is_false(KE:EUISheetActive("target"))
    end)

    it("treats an absent key as ON, EUI's own convention", function()
        local KE = loadGlobals({})
        assert.is_true(KE:EUISheetActive("player"))
        assert.is_true(KE:EUISheetActive("target"))
    end)

    it("only a literal false turns a sheet off", function()
        local KE = loadGlobals({ themedCharacterSheet = 0 })
        assert.is_true(KE:EUISheetActive("player"))
    end)

    -- The bug the cross-model review caught: the two sheets have separate keys
    -- and separate user-facing toggles, so one shared test is wrong both ways.
    it("reads the CHARACTER key for the player frame only", function()
        local KE = loadGlobals({ themedCharacterSheet = false })
        assert.is_false(KE:EUISheetActive("player"))
        assert.is_true(KE:EUISheetActive("target"))
    end)

    it("reads the INSPECT key for any other frame only", function()
        local KE = loadGlobals({ themedInspectSheet = false })
        assert.is_true(KE:EUISheetActive("player"))
        assert.is_false(KE:EUISheetActive("target"))
    end)

    it("treats a nil unit as the player frame", function()
        local KE = loadGlobals({ themedCharacterSheet = false })
        assert.is_false(KE:EUISheetActive(nil))
    end)

    it("the master kill switch takes down both sheets", function()
        local KE = loadGlobals({}, {
            euiNamespace = { BlizzWindowSkinsKilled = function() return true end },
        })
        assert.is_false(KE:EUISheetActive("player"))
        assert.is_false(KE:EUISheetActive("target"))
    end)

    it("survives a kill switch that throws", function()
        local KE = loadGlobals({}, {
            euiNamespace = { BlizzWindowSkinsKilled = function() error("boom") end },
        })
        assert.is_true(KE:EUISheetActive("player"))
    end)

    it("survives the namespace not exposing the switch at all", function()
        local KE = loadGlobals({}, { euiNamespace = {} })
        assert.is_true(KE:EUISheetActive("player"))
    end)
end)

describe("EUIDrawsSlotElement", function()
    it("claims every character element when EUI is on with defaults", function()
        local KE = loadGlobals({})
        for _, el in ipairs({ "ilvl", "enchant", "gems", "track" }) do
            assert.is_true(KE:EUIDrawsSlotElement("player", el), el)
        end
    end)

    it("claims nothing at all when the sheet is off", function()
        local KE = loadGlobals({ themedCharacterSheet = false })
        for _, el in ipairs({ "ilvl", "enchant", "gems", "track", "missingEnchant" }) do
            assert.is_false(KE:EUIDrawsSlotElement("player", el), el)
        end
    end)

    -- The per-element toggles are the point: EUI turning one off must hand THAT
    -- element back to us, not delete it from both addons.
    it("releases exactly the element EUI turned off, and no other", function()
        local KE = loadGlobals({ showGems = false })
        assert.is_false(KE:EUIDrawsSlotElement("player", "gems"))
        assert.is_true(KE:EUIDrawsSlotElement("player", "ilvl"))
        assert.is_true(KE:EUIDrawsSlotElement("player", "enchant"))
        assert.is_true(KE:EUIDrawsSlotElement("player", "track"))
    end)

    it("uses the inspect-prefixed keys on the inspect frame", function()
        local KE = loadGlobals({ inspectShowItemLevel = false, showItemLevel = true })
        assert.is_false(KE:EUIDrawsSlotElement("target", "ilvl"))
        -- and the character key is untouched by the inspect one
        assert.is_true(KE:EUIDrawsSlotElement("player", "ilvl"))
    end)

    it("does not let a character toggle leak onto the inspect frame", function()
        local KE = loadGlobals({ showEnchants = false })
        assert.is_false(KE:EUIDrawsSlotElement("player", "enchant"))
        assert.is_true(KE:EUIDrawsSlotElement("target", "enchant"))
    end)

    -- ASYMMETRY 1. EUI's inspect sheet has no gem code at all.
    it("never claims gems on the inspect frame, at any setting", function()
        for _, db in ipairs({ {}, { showGems = true }, { showGems = false } }) do
            local KE = loadGlobals(db)
            assert.is_false(KE:EUIDrawsSlotElement("target", "gems"))
        end
    end)

    -- ASYMMETRY 2. Character border is unconditional; inspect icon is gated.
    it("always claims the missing-enchant cue on the character sheet", function()
        local KE = loadGlobals({ showEnchants = false })
        assert.is_true(KE:EUIDrawsSlotElement("player", "missingEnchant"))
    end)

    it("releases the missing-enchant cue on inspect when its icon is off", function()
        local KE = loadGlobals({ inspectShowEnchants = false })
        assert.is_false(KE:EUIDrawsSlotElement("target", "missingEnchant"))
    end)

    it("claims the missing-enchant cue on inspect while its icon is on", function()
        local KE = loadGlobals({})
        assert.is_true(KE:EUIDrawsSlotElement("target", "missingEnchant"))
    end)

    it("negative control: an element EUI has no concept of is never claimed", function()
        local KE = loadGlobals({})
        assert.is_false(KE:EUIDrawsSlotElement("player", "raceText"))
        assert.is_false(KE:EUIDrawsSlotElement("target", "raceText"))
    end)
end)

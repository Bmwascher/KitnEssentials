-- Tier: the stand-down refusal only. The anchor arithmetic is a verbatim port
-- and is covered by the structural diff against its source, not here -- a spec
-- written from the same reading could not see an error in that source either.
--
-- What IS covered: the gate that decides whether the widen happens at all.
-- It fails silently when wrong (the window is simply the wrong width) and it
-- is awkward to smoke, because proving the ElvUI branch means installing ElvUI.

local helpers = require("dev.spec._helpers")

-- Copied from dev/spec/character_panel_enchant_spec.lua's loadCP, which is the
-- proven recipe for standing this module up headless. Do not hand-minimise it:
-- the module captures several of these as file-locals at load.
local function loadCP(overrides, keOverrides)
    local modules = helpers.installAddonShim()

    _G.C_TooltipInfo = { GetHyperlink = function() return nil end,
                         GetInventoryItem = function() return nil end }
    _G.C_Item = { GetItemInfoInstant = function() return nil end,
                  GetDetailedItemLevelInfo = function() return nil end }
    _G.C_Container = {}
    _G.C_Timer = { After = function() end }
    _G.CreateFrame = function() return nil end
    _G.InCombatLockdown = function() return false end
    _G.ENCHANTED_TOOLTIP_LINE = "Enchanted: %s"
    _G.C_AddOns = { IsAddOnLoaded = function() return false end }
    for _, name in ipairs({
        "GetInventoryItemLink", "GetExpansionForLevel", "UnitLevel",
        "GetInventoryItemQuality", "issecretvalue",
    }) do
        _G[name] = _G[name] or function() return nil end
    end
    _G.strsplit = function() return nil end
    local invslots = {
        INVSLOT_HEAD = 1, INVSLOT_NECK = 2, INVSLOT_SHOULDER = 3, INVSLOT_CHEST = 5,
        INVSLOT_WAIST = 6, INVSLOT_LEGS = 7, INVSLOT_FEET = 8, INVSLOT_WRIST = 9,
        INVSLOT_FINGER1 = 11, INVSLOT_FINGER2 = 12, INVSLOT_BACK = 15,
        INVSLOT_MAINHAND = 16, INVSLOT_OFFHAND = 17,
    }
    for name, id in pairs(invslots) do _G[name] = id end

    for k, v in pairs(overrides or {}) do _G[k] = v end

    local KE = {
        -- Read at file scope: EMPTY_SOCKET_ICON is built by iterating it, so a
        -- missing key is not a nil method later, it is
        -- "bad argument #1 to 'ipairs'" while the module is still loading.
        GEM_SOCKET_TYPES = { { name = "Prismatic", locale = "EMPTY_SOCKET_PRISMATIC", icon = 1 } },
        Print = function() end,
        IsFullyRestricted = function() return false end,
        IsSafeValue = function(_, v) return v ~= nil end,
        EUIDrawsSlotElement = function() return false end,
        EUISheetActive = function() return false end,
    }
    for k, v in pairs(keOverrides or {}) do KE[k] = v end

    helpers.loadModule("Modules/QoL/CharacterPanel.lua", KE)
    local CP = modules["CharacterPanel"]
    -- In game this is an AceModule and `IsEnabled` comes from Ace. The spec shim
    -- returns a bare table, so the lifecycle predicate `ExtraWidth` reads has to
    -- be supplied here or every case dies on "attempt to call method
    -- 'IsEnabled' (a nil value)". Enabled by default; the disabled case
    -- overrides it.
    CP.IsEnabled = function() return true end
    return CP
end

-- Every fixture sets `Enabled` explicitly, even though `ExtraWidth` reads the
-- module's `IsEnabled()` rather than that key. `Core/Defaults.lua` always
-- supplies it, so a db table without it does not occur in the wild, and a fixture
-- shaped unlike a real profile invites the next reader to trust the wrong shape.
--
-- The two are NOT the same thing, which is the point of the disabled case below:
-- `CP:Disable()` is reachable without the key ever changing.
describe("Widen character window: the stand-down gate", function()
    it("widens by 40 when the key is on and nothing else owns the sheet", function()
        local CP = loadCP()
        CP.db = { Enabled = true, WiderFrame = true }
        assert.equals(40, CP._ExtraWidth())
    end)

    it("does not widen when the key is off", function()
        local CP = loadCP()
        CP.db = { Enabled = true, WiderFrame = false }
        assert.equals(0, CP._ExtraWidth())
    end)

    it("stands down while ElvUI is loaded, even with the key on", function()
        local CP = loadCP({
            C_AddOns = { IsAddOnLoaded = function(name) return name == "ElvUI" end },
        })
        CP.db = { Enabled = true, WiderFrame = true }
        assert.equals(0, CP._ExtraWidth())
    end)

    it("stands down while an EllesmereUI themed sheet is active, even with the key on", function()
        local CP = loadCP(nil, { EUISheetActive = function() return true end })
        CP.db = { Enabled = true, WiderFrame = true }
        assert.equals(0, CP._ExtraWidth())
    end)

    -- The hooks install once per session and cannot be removed, so this branch is
    -- what actually stops them after the module is switched off. Without it the
    -- widen survives a disable that the player cannot then undo, because the
    -- control lives inside the master gate.
    -- The key stays TRUE here on purpose. `CP:Disable()` marks the module disabled
    -- without touching the profile, and Ace flips that state BEFORE running
    -- OnDisable -- so this is the exact state in which reading `db.Enabled`
    -- instead would re-widen the frame from inside its own teardown.
    it("stands down while the module itself is disabled, even with both keys on", function()
        local CP = loadCP()
        CP.db = { Enabled = true, WiderFrame = true }
        CP.IsEnabled = function() return false end
        assert.equals(0, CP._ExtraWidth())
    end)

    it("ignores an addon other than ElvUI being loaded", function()
        local CP = loadCP({
            C_AddOns = { IsAddOnLoaded = function(name) return name == "SomeOtherAddon" end },
        })
        CP.db = { Enabled = true, WiderFrame = true }
        assert.equals(40, CP._ExtraWidth())
    end)
end)

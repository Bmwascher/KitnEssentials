-- Tier 2: the lifecycle refusals that sit on exported methods.
--
-- The eight closure gates on this branch live inside permanent hook closures, a
-- frame script and C_Timer continuations. Reaching those needs Blizzard event
-- timing and a real frame, so they are smoked, not specced. All eight METHOD
-- gates are here, plus the rebind that must survive Refresh's own gate, and the
-- teardown latch reset. Nothing below fakes a Blizzard layout: every stand-in is
-- either a method on this module or a table with the one or two fields the code
-- reads.
local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

local function loadCP()
    helpers.installAddonShim()
    mock.install()

    _G.C_TooltipInfo = { GetHyperlink = function() return nil end }
    _G.C_Item = { GetItemInfoInstant = function() return nil end }
    _G.C_Container = {}
    _G.ENCHANTED_TOOLTIP_LINE = "Enchanted: %s"
    for _, name in ipairs({
        "GetInventoryItemLink", "GetExpansionForLevel", "UnitLevel",
        "GetInventoryItemQuality", "issecretvalue", "GetAverageItemLevel",
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

    local KE = {
        GEM_SOCKET_TYPES = { { name = "Prismatic", locale = "EMPTY_SOCKET_PRISMATIC", icon = 1 } },
        Print = function() end,
        EUIDrawsSlotElement = function() return false end,
    }
    -- CP:Refresh rebinds from here before it does anything else.
    KE.db = { profile = { CharacterPanel = {
        Enabled = true, SocketHelperEnabled = true, TrackIndicatorsEnabled = true,
    } } }
    helpers.loadModule("Modules/QoL/CharacterPanel.lua", KE)

    local CP = _G.KitnEssentials:GetModule("CharacterPanel")
    -- loadModule does not run OnInitialize, so the module never binds its own db.
    CP.db = KE.db.profile.CharacterPanel
    -- In game IsEnabled comes from Ace; the shim's module table has no Ace on it.
    CP.IsEnabled = function() return false end
    return CP, KE
end

describe("Character panel: refusals while the module is disabled", function()
    -- The GUI calls Refresh directly, and everything below the gate installs
    -- permanent hooks. ApplySettings is the observable end of that path.
    it("Refresh does nothing past the rebind while the module is disabled", function()
        local CP = loadCP()
        local applied = false
        CP.ApplySettings = function() applied = true end
        CP:Refresh()
        assert.is_false(applied)
    end)

    -- The rebind is NOT gated, and must still happen: it is the whole point of
    -- CP:UpdateDB. Without this case the gate could be moved above the rebind
    -- and nothing would notice.
    it("Refresh still rebinds the profile while the module is disabled", function()
        local CP, KE = loadCP()
        CP.ApplySettings = function() end
        local fresh = { Enabled = true }
        KE.db.profile.CharacterPanel = fresh
        CP:Refresh()
        assert.equals(fresh, CP.db)
    end)

    -- Two socket-click timers land in RefreshSocketButtons a tenth of a second
    -- later. SetHeight is the first thing it touches past its own guards, and
    -- both of those guards stay true through teardown.
    it("RefreshSocketButtons refuses while the module is disabled", function()
        local CP = loadCP()
        local touched = false
        CP.socketContainer = setmetatable(
            { SetHeight = function() touched = true end },
            { __index = function() return function() end end })
        CP:RefreshSocketButtons()
        assert.is_false(touched)
    end)

    -- Driven from every slot-display checkbox on the GUI page.
    it("RefreshSlotDisplays refuses while the module is disabled", function()
        local CP = loadCP()
        local drew = false
        CP.UpdateAllTrackIndicators = function() drew = true end
        CP:RefreshSlotDisplays()
        assert.is_false(drew)
    end)

    -- Its own latch is the observable: setting it while disabled would also mean
    -- a later legitimate enable finds the helper already "installed".
    it("SetupGemSocketHelper refuses while the module is disabled", function()
        local CP = loadCP()
        CP:SetupGemSocketHelper()
        assert.is_nil(CP._gemSocketHooked)
    end)

    -- Same shape, different latch, and a separate GUI checkbox drives it.
    it("SetupTrackIndicators refuses while the module is disabled", function()
        local CP = loadCP()
        CP:SetupTrackIndicators()
        assert.is_nil(CP._trackIndicatorsHooked)
    end)

    -- Both branches of this one end in SetText, so a numeric average and a
    -- recording Value are the whole fixture. No layout is modelled.
    it("UpdateItemLevelText refuses while the module is disabled", function()
        local CP = loadCP()
        local painted = false
        _G.GetAverageItemLevel = function() return 600, 600 end
        _G.CharacterStatsPane = {
            ItemLevelFrame = { Value = { SetText = function() painted = true end } },
        }
        CP:UpdateItemLevelText()
        assert.is_false(painted)
    end)
    -- Reads and writes CharacterLevelText and nothing else -- no anchors, no
    -- new regions -- so a two-method stand-in is the whole fixture.
    it("UpdateLevelTextWithFaction refuses while the module is disabled", function()
        local CP = loadCP()
        local wrote = false
        _G.CharacterLevelText = {
            GetText = function() return "Level 80" end,
            SetText = function() wrote = true end,
        }
        _G.UnitFactionGroup = function() return "Alliance" end
        CP:UpdateLevelTextWithFaction()
        assert.is_false(wrote)
    end)

    -- Everything past the gate goes through methods on this module, so the
    -- fixture stubs those rather than modelling a FontString.
    it("ShowRaceText refuses while the module is disabled", function()
        local CP = loadCP()
        -- Seeded, and load-bearing: the method's SECOND guard is this key, so
        -- without it the case passes whether the lifecycle gate is there or not.
        CP.db.ShowRaceText = true
        local built = false
        CP.CreateRaceText = function()
            built = true
            return { SetText = function() end, Show = function() end }
        end
        CP.ApplyFont = function() end
        CP.UpdateRaceTextPosition = function() end
        CP.HideRaceText = function() end
        _G.UnitRace = function() return "Orc" end
        CP:ShowRaceText()
        assert.is_false(built)
    end)

    -- Not a test of Ace. Ace removes the hook on its own; what this asserts is
    -- that THIS module drops the latch saying the hook is still installed.
    it("OnDisable clears the decimal item-level latch", function()
        local CP = loadCP()
        CP.IsEnabled = function() return true end
        CP._decimalIlvlHooked = true
        for _, name in ipairs({
            "ClearAll", "DisableGemSocketHelper", "HideAllTrackIndicators",
            "HideAllSlotDetails", "HideRaceText",
        }) do
            CP[name] = function() end
        end
        -- OnDisable ends by cascading a Disable to InspectPanel. The addon shim
        -- hands back a bare table for ANY module name, so this is not optional:
        -- without it the call errors before the assertion, whether or not the
        -- latch line is present.
        _G.KitnEssentials:GetModule("InspectPanel").Disable = function() end
        CP:OnDisable()
        assert.is_nil(CP._decimalIlvlHooked)
    end)
end)

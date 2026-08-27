-- luacheck: push ignore 211
-- Tier 2: deterministic branching around WoW unit-spellcast APIs.
-- The mock can verify branches given declared classifications; it cannot prove
-- Blizzard secret/taint behavior or real event ordering. Those remain in-game.
local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

local function loadCombatTexts(options)
    options = options or {}
    local now = options.now or 100
    local printed = {}
    local unitGUIDs = options.unitGUIDs or {
        player = "Player-1-00000001",
        pet = "Pet-1-00000002",
    }
    local frames = mock.install({
        C_Timer = { After = function() end },
        GetTime = function() return now end,
        UnitGUID = function(unit) return unitGUIDs[unit] end,
    })
    local createFrame = _G.CreateFrame
    _G.CreateFrame = function(...)
        local frame = createFrame(...)
        local registerUnitEvent = frame.RegisterUnitEvent
        local unregisterEvent = frame.UnregisterEvent
        frame._unitRegisterCalls = 0
        frame._unitUnregisterCalls = {}
        function frame:RegisterUnitEvent(event, ...)
            self._unitRegisterCalls = self._unitRegisterCalls + 1
            self._unitRegisterArgs = { event, ... }
            registerUnitEvent(self, event)
        end
        function frame:UnregisterEvent(event)
            self._unitUnregisterCalls[event] = (self._unitUnregisterCalls[event] or 0) + 1
            unregisterEvent(self, event)
        end
        return frame
    end
    _G.UnitCanAttack = options.UnitCanAttack or function() return true end
    _G.GetInventoryItemDurability = function() return nil end
    _G.UIParent = {}
    local spellNameCalls = {}
    local spellTextureCalls = {}
    _G.C_Spell = {
        GetSpellName = function(spellID)
            spellNameCalls[#spellNameCalls + 1] = spellID
            if options.getSpellName then return options.getSpellName(spellID) end
            return "Enemy Spell"
        end,
        GetSpellTexture = function(spellID)
            spellTextureCalls[#spellTextureCalls + 1] = spellID
            if options.getSpellTexture then return options.getSpellTexture(spellID) end
            return 12345
        end,
    }

    local modules = helpers.installAddonShim()
    local aceEvents = {}
    local aceRegisterCalls = {}
    local aceUnregisterCalls = {}
    modules.CombatTexts = {
        RegisterEvent = function(_, event)
            aceEvents[event] = true
            aceRegisterCalls[event] = (aceRegisterCalls[event] or 0) + 1
        end,
        UnregisterEvent = function(_, event)
            aceEvents[event] = nil
            aceUnregisterCalls[event] = (aceUnregisterCalls[event] or 0) + 1
        end,
        UnregisterAllEvents = function(self)
            for event in pairs(aceEvents) do
                aceEvents[event] = nil
            end
            self._unregisterAllCalls = self._unregisterAllCalls + 1
        end,
        IsEnabled = function() return options.moduleEnabled ~= false end,
    }
    local KE = {
        db = { profile = { CombatTexts = {} } },
        ApplyFramePosition = function() end,
        ApplyFont = function() end,
        ApplyFontToText = function() end,
        GetFontOutline = function() return "" end,
        GetInterruptAnnounceSpellSet = function()
            return { [6552] = true, [119910] = true }
        end,
        IsSecretValue = function(_, value)
            return options.secretValues and options.secretValues[value] == true
        end,
        IsSafeValue = function(self, value)
            if self:IsSecretValue(value) then return false end
            return type(value) ~= "nil"
        end,
        Print = function(_, message)
            printed[#printed + 1] = message
        end,
    }
    helpers.loadModule("Modules/Combat/CombatTexts.lua", KE)
    local CM = modules.CombatTexts
    CM.db = {
        Enabled = true,
        InterruptEnabled = true,
        InterruptText = "Interrupted",
        FontSize = 16,
    }
    CM.interruptAnnounceSpells = KE:GetInterruptAnnounceSpellSet()
    CM._aceEvents = aceEvents
    CM._aceRegisterCalls = aceRegisterCalls
    CM._aceUnregisterCalls = aceUnregisterCalls
    CM._unregisterAllCalls = 0
    CM.spellNameCalls = spellNameCalls
    CM.spellTextureCalls = spellTextureCalls
    CM.printed = printed
    CM.shown = {}
    CM.ShowFlashMessage = function(self, kind, text, icon)
        self.shown[#self.shown + 1] = { kind = kind, text = text, icon = icon }
    end
    return CM, KE, frames, function(value) now = value end
end
-- luacheck: pop

-- luacheck: globals describe it assert
describe("Combat Texts interrupt attribution", function()
    it("records recognized player and pet casts without a timer", function()
        local CM = loadCombatTexts()
        CM:OnSpellcastSucceeded("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-a", 6552)
        assert.equals(100, CM.pendingInterruptAt)
        assert.equals(6552, CM.pendingInterruptSpellID)
        assert.equals("player", CM.pendingInterruptUnit)

        CM:OnSpellcastSucceeded("UNIT_SPELLCAST_SUCCEEDED", "pet", "cast-b", 119910)
        assert.equals(119910, CM.pendingInterruptSpellID)
        assert.equals("pet", CM.pendingInterruptUnit)
        assert.is_nil(CM.interruptTimer)
    end)

    it("ignores unknown cast IDs", function()
        local CM = loadCombatTexts()
        CM:OnSpellcastSucceeded("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-a", 999999)
        assert.is_nil(CM.pendingInterruptAt)
    end)

    it("accepts readable player and pet ownership without pending state", function()
        local CM = loadCombatTexts()
        CM:OnSpellcastInterrupted("UNIT_SPELLCAST_INTERRUPTED", "target",
            "enemy-cast-a", 777, "Player-1-00000001")
        CM:OnSpellcastInterrupted("UNIT_SPELLCAST_INTERRUPTED", "target",
            "enemy-cast-b", 778, "Pet-1-00000002")
        assert.equals(2, #CM.shown)
    end)

    it("rejects another readable interrupter without consuming pending", function()
        local CM = loadCombatTexts()
        CM:OnSpellcastSucceeded("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-a", 6552)
        CM:OnSpellcastInterrupted("UNIT_SPELLCAST_INTERRUPTED", "target",
            "enemy-cast-a", 777, "Player-1-OTHER")
        assert.equals(0, #CM.shown)
        assert.equals(100, CM.pendingInterruptAt)
    end)

    it("rejects another readable interrupter when no pet exists", function()
        local CM = loadCombatTexts({
            unitGUIDs = { player = "Player-1-00000001" },
        })
        CM:OnSpellcastSucceeded("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-a", 6552)
        CM:OnSpellcastInterrupted("UNIT_SPELLCAST_INTERRUPTED", "target",
            "enemy-cast-a", 777, "Player-1-OTHER")
        assert.equals(0, #CM.shown)
        assert.equals(100, CM.pendingInterruptAt)
        assert.equals(6552, CM.pendingInterruptSpellID)
        assert.equals("player", CM.pendingInterruptUnit)
    end)

    it("rejects a readable cast source outside the filtered units", function()
        local CM = loadCombatTexts()
        CM:OnSpellcastSucceeded("UNIT_SPELLCAST_SUCCEEDED", "party1", "cast-a", 6552)
        assert.is_nil(CM.pendingInterruptAt)
    end)

    it("rejects friendly targets without consuming pending", function()
        local CM = loadCombatTexts({ UnitCanAttack = function() return false end })
        CM:OnSpellcastSucceeded("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-a", 6552)
        CM:OnSpellcastInterrupted("UNIT_SPELLCAST_INTERRUPTED", "party1",
            "friendly-cast-a", 777, "Player-1-00000001")
        CM:OnSpellcastInterrupted("UNIT_SPELLCAST_INTERRUPTED", "party1",
            "friendly-cast-b", 778, nil)
        assert.equals(0, #CM.shown)
        assert.equals(100, CM.pendingInterruptAt)
    end)

    it("rejects invalid target payloads without consuming pending", function()
        local CM = loadCombatTexts()
        CM:OnSpellcastSucceeded("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-a", 6552)
        CM:OnSpellcastInterrupted("UNIT_SPELLCAST_INTERRUPTED", nil,
            "invalid-target-cast", 777, nil)
        assert.equals(0, #CM.shown)
        assert.equals(100, CM.pendingInterruptAt)
    end)

    it("accepts nil ownership only for a fresh interrupted cast", function()
        local CM, _, _, setNow = loadCombatTexts({ now = 0 })
        CM:OnSpellcastSucceeded("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-a", 6552)
        setNow(0.35)
        CM:OnSpellcastInterrupted("UNIT_SPELLCAST_INTERRUPTED", "target",
            "enemy-cast", 777, nil)
        assert.equals(1, #CM.shown)
        assert.is_nil(CM.pendingInterruptAt)
    end)

    it("rejects nil ownership on natural channel stop", function()
        local CM = loadCombatTexts()
        CM:OnSpellcastSucceeded("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-a", 6552)
        CM:OnSpellcastInterrupted("UNIT_SPELLCAST_CHANNEL_STOP", "target",
            "enemy-channel", 777, nil)
        assert.equals(0, #CM.shown)
        assert.equals(100, CM.pendingInterruptAt)
    end)

    it("clears expired pending state", function()
        local CM, _, _, setNow = loadCombatTexts()
        CM:OnSpellcastSucceeded("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-a", 6552)
        setNow(100.351)
        CM:OnSpellcastInterrupted("UNIT_SPELLCAST_INTERRUPTED", "target",
            "enemy-cast", 777, nil)
        assert.equals(0, #CM.shown)
        assert.is_nil(CM.pendingInterruptAt)
    end)

    it("consumes fallback pending state before a duplicate can render", function()
        local CM = loadCombatTexts()
        CM:OnSpellcastSucceeded("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-a", 6552)
        CM:OnSpellcastInterrupted("UNIT_SPELLCAST_INTERRUPTED", "target", nil, 777, nil)
        CM:OnSpellcastInterrupted("UNIT_SPELLCAST_INTERRUPTED", "target", nil, 777, nil)
        assert.equals(1, #CM.shown)
    end)

    it("preserves pending across a readable duplicate rejection", function()
        local CM = loadCombatTexts()
        CM:OnSpellcastInterrupted("UNIT_SPELLCAST_INTERRUPTED", "target",
            "enemy-cast-a", 777, "Player-1-00000001")
        CM:OnSpellcastSucceeded("UNIT_SPELLCAST_SUCCEEDED", "player", "kick-a", 6552)
        CM:OnSpellcastInterrupted("UNIT_SPELLCAST_INTERRUPTED", "target",
            "enemy-cast-a", 777, "Player-1-00000001")
        assert.equals(100, CM.pendingInterruptAt)
        assert.equals(6552, CM.pendingInterruptSpellID)
        assert.equals("player", CM.pendingInterruptUnit)
        CM:OnSpellcastInterrupted("UNIT_SPELLCAST_INTERRUPTED", "target",
            "enemy-cast-b", 778, nil)
        assert.equals(2, #CM.shown)
        assert.is_nil(CM.pendingInterruptAt)
    end)

    it("preserves pending across an unkeyed throttle rejection", function()
        local CM, _, _, setNow = loadCombatTexts({ now = 0 })
        CM:OnSpellcastInterrupted("UNIT_SPELLCAST_INTERRUPTED", "target",
            nil, 777, "Player-1-00000001")
        CM:OnSpellcastSucceeded("UNIT_SPELLCAST_SUCCEEDED", "player", "kick-a", 6552)
        setNow(0.099)
        CM:OnSpellcastInterrupted("UNIT_SPELLCAST_INTERRUPTED", "target",
            nil, 778, "Player-1-00000001")
        assert.equals(0, CM.pendingInterruptAt)
        assert.equals(6552, CM.pendingInterruptSpellID)
        assert.equals("player", CM.pendingInterruptUnit)
        CM:OnSpellcastInterrupted("UNIT_SPELLCAST_INTERRUPTED", "target",
            "enemy-cast-b", 779, nil)
        assert.is_nil(CM.pendingInterruptAt)
        setNow(0.10)
        CM:OnSpellcastInterrupted("UNIT_SPELLCAST_INTERRUPTED", "target",
            nil, 780, "Player-1-00000001")
        assert.equals(3, #CM.shown)
    end)

    it("classifies unreadable comparison GUIDs as unknown", function()
        assert.equals("UNKNOWN", loadCombatTexts().ResolveReadableInterruptOwner(
            "Pet-1-00000002", "Player-1-00000001", true, nil, false))
    end)

    it("records an unknown filtered source without inspecting its token", function()
        local CM = loadCombatTexts({ secretValues = { SECRET_UNIT = true } })
        CM:OnSpellcastSucceeded("UNIT_SPELLCAST_SUCCEEDED", "SECRET_UNIT", "cast-a", 6552)
        assert.equals(100, CM.pendingInterruptAt)
        assert.is_nil(CM.pendingInterruptUnit)
    end)

    it("guards the spell ID before the announce-set lookup", function()
        local CM = loadCombatTexts({ secretValues = { [6552] = true } })
        CM:OnSpellcastSucceeded("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-a", 6552)
        assert.is_nil(CM.pendingInterruptAt)
    end)

    it("uses fresh pending for secret ownership and unknown targets", function()
        local CM = loadCombatTexts({
            secretValues = { SECRET_GUID = true },
            UnitCanAttack = function() error("unavailable") end,
        })
        CM:OnSpellcastInterrupted("UNIT_SPELLCAST_CHANNEL_STOP", "target",
            "enemy-channel-a", 777, "SECRET_GUID")
        assert.equals(0, #CM.shown)
        CM:OnSpellcastSucceeded("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-a", 6552)
        CM:OnSpellcastInterrupted("UNIT_SPELLCAST_CHANNEL_STOP", "target",
            "enemy-channel-b", 778, "SECRET_GUID")
        assert.equals(1, #CM.shown)
        assert.is_nil(CM.pendingInterruptAt)
    end)

    it("returns complete pending evidence before an accepted fallback clears it", function()
        local CM = loadCombatTexts()
        CM:OnSpellcastSucceeded("UNIT_SPELLCAST_SUCCEEDED", "player", "kick-a", 6552)
        local accepted, ownership, target, pendingSource, pendingState, reason, elapsed =
            CM:ShouldAcceptInterrupt("UNIT_SPELLCAST_INTERRUPTED", "target", "enemy-cast-a", nil, 100.25)
        assert.is_true(accepted)
        assert.equals("UNKNOWN", ownership)
        assert.equals("HOSTILE", target)
        assert.equals("player", pendingSource)
        assert.equals("fresh", pendingState)
        assert.equals("fallback", reason)
        assert.equals(0.25, elapsed)
        assert.is_nil(CM.pendingInterruptAt)
    end)
end)

local function packValues(...)
    return { n = select("#", ...), ... }
end

local decisionCases = {
    {
        name = "direct-owner",
        args = packValues("UNIT_SPELLCAST_INTERRUPTED", "target", "enemy-cast-a", "Player-1-00000001", 100),
        expected = packValues(true, "OWN", "HOSTILE", "none", "none", "direct-owner", nil),
    },
    {
        name = "other-owner",
        prepare = function(CM) CM:RecordPendingInterrupt(6552, "player", 100) end,
        args = packValues("UNIT_SPELLCAST_INTERRUPTED", "target", "enemy-cast-a", "Player-1-OTHER", 100),
        expected = packValues(false, "OTHER", "UNKNOWN", "player", "fresh", "other-owner", 0),
    },
    {
        name = "nil-channel-stop",
        prepare = function(CM) CM:RecordPendingInterrupt(6552, "player", 100) end,
        args = packValues("UNIT_SPELLCAST_CHANNEL_STOP", "target", "enemy-cast-a", nil, 100),
        expected = packValues(false, "UNKNOWN", "UNKNOWN", "player", "fresh", "nil-channel-stop", 0),
    },
    {
        name = "no-fresh-pending",
        options = { now = 0 },
        prepare = function(CM) CM:RecordPendingInterrupt(6552, "player", 0) end,
        args = packValues("UNIT_SPELLCAST_INTERRUPTED", "target", "enemy-cast-a", nil, 0.351),
        expected = packValues(false, "UNKNOWN", "UNKNOWN", "player", "expired", "no-fresh-pending", 0.351),
    },
    {
        name = "friendly-target",
        options = { UnitCanAttack = function() return false end },
        args = packValues("UNIT_SPELLCAST_INTERRUPTED", "party1", "enemy-cast-a", "Player-1-00000001", 100),
        expected = packValues(false, "OWN", "FRIENDLY", "none", "none", "friendly-target", nil),
    },
    {
        name = "invalid-target",
        args = packValues("UNIT_SPELLCAST_INTERRUPTED", nil, "enemy-cast-a", "Player-1-00000001", 100),
        expected = packValues(false, "OWN", "INVALID", "none", "none", "invalid-target", nil),
    },
    {
        name = "duplicate-cast-guid",
        prepare = function(CM)
            CM:ShouldAcceptInterrupt("UNIT_SPELLCAST_INTERRUPTED", "target", "enemy-cast-a", "Player-1-00000001", 100)
            CM:RecordPendingInterrupt(6552, "player", 100)
        end,
        args = packValues("UNIT_SPELLCAST_INTERRUPTED", "target", "enemy-cast-a", "Player-1-00000001", 100),
        expected = packValues(false, "OWN", "HOSTILE", "player", "fresh", "duplicate-cast-guid", 0),
    },
    {
        name = "unkeyed-throttle",
        options = { now = 0 },
        prepare = function(CM)
            CM.lastUnkeyedAcceptAt = 0
            CM:RecordPendingInterrupt(6552, "player", 0)
        end,
        args = packValues("UNIT_SPELLCAST_INTERRUPTED", "target", nil, "Player-1-00000001", 0.05),
        expected = packValues(false, "OWN", "HOSTILE", "player", "fresh", "unkeyed-throttle", 0.05),
    },
    {
        name = "fallback",
        prepare = function(CM) CM:RecordPendingInterrupt(6552, "player", 100) end,
        args = packValues("UNIT_SPELLCAST_INTERRUPTED", "target", "enemy-cast-a", nil, 100.25),
        expected = packValues(true, "UNKNOWN", "HOSTILE", "player", "fresh", "fallback", 0.25),
    },
}

for _, case in ipairs(decisionCases) do
    it("returns the complete " .. case.name .. " decision", function()
        local CM = loadCombatTexts(case.options)
        if case.prepare then case.prepare(CM) end
        local actual = packValues(CM:ShouldAcceptInterrupt(unpack(case.args, 1, case.args.n)))
        assert.same(case.expected, actual)
    end)
end

local function setDebugCT(CM, value)
    local index = 1
    while true do
        local name = debug.getupvalue(CM.OnSpellcastInterrupted, index)
        if not name then break end
        if name == "DEBUG_CT" then
            debug.setupvalue(CM.OnSpellcastInterrupted, index, value)
            return
        end
        index = index + 1
    end
    error("DEBUG_CT upvalue not found")
end

it("logs only the frozen plain decision tuple", function()
    local CM = loadCombatTexts({
        unitGUIDs = { player = "RAW_OWNER", pet = "RAW_PET" },
    })
    setDebugCT(CM, true)
    CM:OnSpellcastInterrupted("UNIT_SPELLCAST_INTERRUPTED", "RAW_TARGET", "RAW_CAST", 987654, "RAW_OWNER")
    assert.same({
        "[CT] event=UNIT_SPELLCAST_INTERRUPTED owner=OWN target=HOSTILE " ..
        "pending=none state=none elapsed=none reason=direct-owner",
    }, CM.printed)
end)

it("routes declared-secret spell name and texture to the interrupt display", function()
    local spellName = "SECRET_SPELL_NAME"
    local iconID = 24680
    local CM = loadCombatTexts({
        secretValues = {
            SECRET_SPELL_ID = true,
            [spellName] = true,
            [iconID] = true,
        },
        getSpellName = function() return spellName end,
        getSpellTexture = function() return iconID end,
    })
    CM:OnSpellcastInterrupted("UNIT_SPELLCAST_INTERRUPTED", "target",
        "enemy-cast", "SECRET_SPELL_ID", "Player-1-00000001")
    assert.same({ "SECRET_SPELL_ID" }, CM.spellNameCalls)
    assert.same({ "SECRET_SPELL_ID" }, CM.spellTextureCalls)
    assert.equals(1, #CM.shown)
    assert.equals("interrupt", CM.shown[1].kind)
    assert.equals("Interrupted [" .. spellName .. "]", CM.shown[1].text)
    assert.equals(iconID, CM.shown[1].icon)
end)

it("falls back generically only when spell name or texture is nil", function()
    local cases = {
        {
            getSpellName = function() return nil end,
        },
        {
            getSpellTexture = function() return nil end,
        },
    }

    for _, case in ipairs(cases) do
        local CM = loadCombatTexts(case)
        CM:OnSpellcastInterrupted("UNIT_SPELLCAST_INTERRUPTED", "target",
            "enemy-cast", 777, "Player-1-00000001")
        assert.equals(1, #CM.spellNameCalls)
        assert.equals(1, #CM.spellTextureCalls)
        assert.equals(1, #CM.shown)
        assert.equals("interrupt", CM.shown[1].kind)
        assert.is_nil(CM.shown[1].text)
        assert.is_nil(CM.shown[1].icon)
    end
end)

it("registers interrupt events once and removes them when toggled off", function()
    local CM = loadCombatTexts()
    CM:EnsureInterruptCastFrame()
    CM:UpdateInterruptEventRegistration()
    CM:UpdateInterruptEventRegistration()
    assert.equals(1, CM._aceRegisterCalls.UNIT_SPELLCAST_INTERRUPTED)
    assert.equals(1, CM._aceRegisterCalls.UNIT_SPELLCAST_CHANNEL_STOP)
    assert.equals(1, CM.interruptCastFrame._unitRegisterCalls)
    assert.same({ "UNIT_SPELLCAST_SUCCEEDED", "player", "pet" },
        CM.interruptCastFrame._unitRegisterArgs)

    CM:RecordPendingInterrupt(6552, "player", 100)
    CM.lastAcceptedCastGUID = "enemy-cast"
    CM.lastUnkeyedAcceptAt = 100
    CM.db.InterruptEnabled = false
    CM:UpdateInterruptEventRegistration()
    CM:UpdateInterruptEventRegistration()
    assert.is_false(CM.interruptCastFrame:IsEventRegistered("UNIT_SPELLCAST_SUCCEEDED"))
    assert.is_nil(CM._aceEvents.UNIT_SPELLCAST_INTERRUPTED)
    assert.is_nil(CM._aceEvents.UNIT_SPELLCAST_CHANNEL_STOP)
    assert.equals(1, CM.interruptCastFrame._unitUnregisterCalls.UNIT_SPELLCAST_SUCCEEDED)
    assert.equals(1, CM._aceUnregisterCalls.UNIT_SPELLCAST_INTERRUPTED)
    assert.equals(1, CM._aceUnregisterCalls.UNIT_SPELLCAST_CHANNEL_STOP)
    assert.is_nil(CM.pendingInterruptAt)
    assert.is_nil(CM.pendingInterruptSpellID)
    assert.is_nil(CM.pendingInterruptUnit)
    assert.is_nil(CM.lastAcceptedCastGUID)
    assert.is_nil(CM.lastUnkeyedAcceptAt)

    CM.db.InterruptEnabled = true
    CM:UpdateInterruptEventRegistration()
    CM:UpdateInterruptEventRegistration()
    assert.equals(2, CM._aceRegisterCalls.UNIT_SPELLCAST_INTERRUPTED)
    assert.equals(2, CM._aceRegisterCalls.UNIT_SPELLCAST_CHANNEL_STOP)
    assert.equals(2, CM.interruptCastFrame._unitRegisterCalls)
    assert.same({ "UNIT_SPELLCAST_SUCCEEDED", "player", "pet" },
        CM.interruptCastFrame._unitRegisterArgs)
    CM:OnSpellcastInterrupted("UNIT_SPELLCAST_INTERRUPTED", "target",
        nil, 777, "Player-1-00000001")
    assert.equals(1, #CM.shown)
end)

it("refuses initial registration while the Ace module is disabled", function()
    local CM = loadCombatTexts({ moduleEnabled = false })
    CM:UpdateInterruptEventRegistration()
    assert.equals(0, CM._aceRegisterCalls.UNIT_SPELLCAST_INTERRUPTED or 0)
    assert.equals(0, CM._aceRegisterCalls.UNIT_SPELLCAST_CHANNEL_STOP or 0)
    assert.is_nil(CM.interruptCastFrame)
end)

it("refuses initial registration while Combat Texts is disabled", function()
    local CM = loadCombatTexts()
    CM.db.Enabled = false
    CM:UpdateInterruptEventRegistration()
    assert.equals(0, CM._aceRegisterCalls.UNIT_SPELLCAST_INTERRUPTED or 0)
    assert.equals(0, CM._aceRegisterCalls.UNIT_SPELLCAST_CHANNEL_STOP or 0)
    assert.is_nil(CM.interruptCastFrame)
end)

it("ApplySettings updates registration even before the container exists", function()
    local CM = loadCombatTexts()
    CM.container = nil
    CM:ApplySettings()
    assert.is_true(CM.interruptEventsRegistered)
    CM.db.InterruptEnabled = false
    CM:ApplySettings()
    assert.is_false(CM.interruptEventsRegistered)
end)

it("module disable tears down both event owners and transient state", function()
    local CM = loadCombatTexts()
    CM:EnsureInterruptCastFrame()
    CM:UpdateInterruptEventRegistration()
    CM:RecordPendingInterrupt(6552, "player", 100)
    CM.lastAcceptedCastGUID = "enemy-cast"
    CM.lastUnkeyedAcceptAt = 100
    CM:OnDisable()
    assert.is_false(CM.interruptCastFrame:IsEventRegistered("UNIT_SPELLCAST_SUCCEEDED"))
    assert.equals(1, CM.interruptCastFrame._unitUnregisterCalls.UNIT_SPELLCAST_SUCCEEDED)
    assert.equals(1, CM._aceUnregisterCalls.UNIT_SPELLCAST_INTERRUPTED)
    assert.equals(1, CM._aceUnregisterCalls.UNIT_SPELLCAST_CHANNEL_STOP)
    assert.equals(1, CM._unregisterAllCalls)
    assert.is_false(CM.interruptEventsRegistered)
    assert.is_nil(CM.pendingInterruptAt)
    assert.is_nil(CM.pendingInterruptSpellID)
    assert.is_nil(CM.pendingInterruptUnit)
    assert.is_nil(CM.lastAcceptedCastGUID)
    assert.is_nil(CM.lastUnkeyedAcceptAt)
end)

it("wires and restores the filtered frame through the real lifecycle", function()
    local CM = loadCombatTexts()
    CM.interruptAnnounceSpells = nil
    CM:OnEnable()
    local frame = CM.interruptCastFrame
    assert.is_not_nil(frame)
    assert.same({ "UNIT_SPELLCAST_SUCCEEDED", "player", "pet" }, frame._unitRegisterArgs)
    frame:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "kick-a", 6552)
    assert.equals(6552, CM.pendingInterruptSpellID)

    CM:OnDisable()
    assert.is_nil(CM.pendingInterruptAt)
    assert.is_nil(CM.interruptAnnounceSpells)

    CM:OnEnable()
    assert.equals(frame, CM.interruptCastFrame)
    assert.equals(2, frame._unitRegisterCalls)
    assert.equals(2, CM._aceRegisterCalls.UNIT_SPELLCAST_INTERRUPTED)
    assert.equals(2, CM._aceRegisterCalls.UNIT_SPELLCAST_CHANNEL_STOP)
    assert.is_true(CM._aceEvents.UNIT_SPELLCAST_INTERRUPTED)
    assert.is_true(CM._aceEvents.UNIT_SPELLCAST_CHANNEL_STOP)
    frame:Fire("UNIT_SPELLCAST_SUCCEEDED", "pet", "kick-b", 119910)
    assert.equals(119910, CM.pendingInterruptSpellID)
    assert.equals("pet", CM.pendingInterruptUnit)
end)

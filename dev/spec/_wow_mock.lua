-- ╔══════════════════════════════════════════════════════════╗
-- ║  dev/spec/_wow_mock.lua                                  ║
-- ║  Minimal, HONEST WoW API mock for headless busted tests. ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- This stubs ONLY the slice of the WoW API a test actually touches. It does
-- NOT emulate WoW behaviour — in particular it cannot reproduce 12.0 secret /
-- taint semantics. A mock verifies "does my code branch correctly given a
-- value I DECLARE secret/restricted", never "is my understanding of real
-- secret semantics correct". Anything depending on true secret/taint runtime
-- behaviour stays in-game-only; see dev/README.md.
--
-- Usage:
--   local mock = require("dev.spec._wow_mock")
--   mock.install()                       -- nothing is secret, no combat
--   mock.install({ InCombatLockdown = function() return true end })
--
-- install() returns the list of frames created via CreateFrame so a test can
-- drive event handlers deterministically: frames[1]:Fire("PLAYER_REGEN_DISABLED").

local M = {}

-- A fake frame records event registrations and scripts so tests can simulate
-- the client dispatching events. Any unstubbed method (Show/Hide/SetSize/...)
-- resolves to a no-op via the metatable, so module load code never crashes.
local function newFrame()
    local f = { _events = {}, _scripts = {} }
    function f:RegisterEvent(e) self._events[e] = true end
    function f:RegisterUnitEvent(e) self._events[e] = true end
    function f:UnregisterEvent(e) self._events[e] = nil end
    function f:UnregisterAllEvents() self._events = {} end
    function f:IsEventRegistered(e) return self._events[e] == true end
    function f:SetScript(k, fn) self._scripts[k] = fn end
    function f:GetScript(k) return self._scripts[k] end
    function f:HookScript(k, fn) self._scripts[k] = fn end
    -- Test helper: simulate the client firing an event at this frame.
    function f:Fire(event, ...)
        if self._scripts.OnEvent then self._scripts.OnEvent(self, event, ...) end
    end
    function f:CreateFontString()
        return setmetatable({}, { __index = function() return function() end end })
    end
    function f:CreateTexture()
        return setmetatable({}, { __index = function() return function() end end })
    end
    return setmetatable(f, { __index = function() return function() end end })
end

-- Install WoW globals into _G. `overrides` replaces any default stub by name.
-- Returns the (growing) list of frames created during the test.
function M.install(overrides)
    overrides = overrides or {}
    local frames = {}

    _G.CreateFrame = overrides.CreateFrame or function()
        local f = newFrame()
        frames[#frames + 1] = f
        return f
    end
    _G.frames = frames

    -- Pure-Lua globals WoW exposes
    _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    _G.InCombatLockdown = overrides.InCombatLockdown or function() return false end
    _G.GetTime = overrides.GetTime or function() return 0 end

    -- C_Timer: run-immediately by default so deferred logic is testable.
    _G.C_Timer = overrides.C_Timer or {
        After = function(_, fn) if fn then fn() end end,
        NewTimer = function(_, fn) return { Cancel = function() end, _fn = fn } end,
        NewTicker = function(_, fn) return { Cancel = function() end, _fn = fn } end,
    }

    -- 12.0 secret API. DEFAULT: nothing is secret, everything accessible.
    -- Tests override per-case to exercise the guard branches.
    _G.issecretvalue  = overrides.issecretvalue  or function() return false end
    _G.issecrettable  = overrides.issecrettable  or function() return false end
    _G.canaccessvalue = overrides.canaccessvalue or function() return true end
    _G.canaccesstable = overrides.canaccesstable or function() return true end

    -- Unit helpers commonly read behind secret guards.
    _G.UnitName = overrides.UnitName or function() return "Mockname" end
    _G.UnitGUID = overrides.UnitGUID or function() return "Player-0000-DEADBEEF" end
    _G.UnitExists = overrides.UnitExists or function() return true end
    _G.UnitIsUnit = overrides.UnitIsUnit or function() return false end

    -- Number formatters.
    _G.AbbreviateNumbers = overrides.AbbreviateNumbers or function(v) return tostring(v) end
    _G.BreakUpLargeNumbers = overrides.BreakUpLargeNumbers or function(v) return tostring(v) end

    return frames
end

-- Reset the stubbed globals so specs don't leak into each other.
function M.reset()
    for _, k in ipairs({
        "CreateFrame", "frames", "wipe",
        "InCombatLockdown", "GetTime", "C_Timer",
        "issecretvalue", "issecrettable", "canaccessvalue", "canaccesstable",
        "UnitName", "UnitGUID", "UnitExists", "UnitIsUnit",
        "AbbreviateNumbers", "BreakUpLargeNumbers",
        "C_Secrets", "C_UnitAuras", "C_Spell", "UnitCastingInfo", "UnitChannelInfo",
        "UnitClass", "PlaySoundFile", "StopSound", "PlayerUtil", "RunNextFrame",
        "GetUnitEmpowerMinHoldTime", "LibStub",
        "GetNumGroupMembers", "IsInRaid", "UnitGroupRolesAssigned",
        "GetSpecialization", "GetSpecializationInfo", "UIParent",
        "C_SpellActivationOverlay", "UnitAffectingCombat",
        "IsMounted", "UnitOnTaxi", "UnitInVehicle", "UnitHasVehicleUI",
        "UnitIsDeadOrGhost", "PetHasActionBar", "GetPetActionInfo",
        "C_SpellBook", "Enum", "strsplit", "KitnEssentials",
    }) do
        _G[k] = nil
    end
end

return M

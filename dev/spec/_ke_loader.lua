-- ╔══════════════════════════════════════════════════════════╗
-- ║  dev/spec/_ke_loader.lua                                 ║
-- ║  Per-module headless loaders: stub set + load + return.  ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- One loader per spec target. Each installs _wow_mock plus the module's
-- probe-verified stub set, loads the REAL source file(s) via
-- helpers.loadModule, and returns what specs assert against. All installs
-- are unconditional — deterministic regardless of what ran earlier in the
-- file (busted insulates _G per spec file; within a file, describes share it).
--
--   local L = require("dev.spec._ke_loader")
--   local DT, KE = L.loadDungeonTimers({ withEncounterData = true })
--   local KE = L.loadGlobals()
--   local DM = L.loadDMCore({ issecretvalue = myFn })
--
-- Loaders taking opts (loadDungeonTimers, loadPixelPerfect) accept mock
-- overrides as a second arg; the rest take overrides first. Override keys
-- _wow_mock manages (issecretvalue, C_Timer, AbbreviateNumbers, ...) win
-- over the loader defaults; stubs _wow_mock does NOT manage live on _G and
-- can simply be reassigned after the loader returns.

local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

local L = {}

-- _wow_mock's default C_Timer.After fires callbacks synchronously (useful
-- for testing deferred logic, wrong as a loader default): the probe runs
-- kept timers inert so deferred paths (phase tickers, delayed prints) never
-- fire mid-spec. Pass overrides.C_Timer to opt back in.
local function inertTimer()
    return {
        After = function() end,
        NewTicker = function() return { Cancel = function() end } end,
    }
end

-- Any method resolves to a no-op returning nil; CreateFontString returns the
-- same kind of object (Core/Globals.lua builds its font probe at file scope).
local function noopObject()
    return setmetatable({}, { __index = function() return function() end end })
end

local function noopFrame()
    local f = { CreateFontString = function() return noopObject() end }
    return setmetatable(f, { __index = function() return function() end end })
end

-- mock.install with loader defaults; caller overrides win. Only keys
-- _wow_mock manages belong in defaults — everything else goes on _G.
local function installMock(overrides, defaults)
    local merged = {}
    for k, v in pairs(defaults) do merged[k] = v end
    for k, v in pairs(overrides or {}) do merged[k] = v end
    return mock.install(merged)
end

-- Modules/DungeonTimers/DungeonTimers.lua. DT is a file-local never assigned
-- onto KE — the shim registry is the only handle to it. Returns DT, KE.
-- opts.withEncounterData loads the real EncounterData.lua into the same KE
-- first (its guard needs the truthy KitnEssentials global the shim sets).
function L.loadDungeonTimers(opts, overrides)
    opts = opts or {}
    installMock(overrides, { C_Timer = inertTimer() })
    local modules = helpers.installAddonShim()
    _G.UIParent = noopFrame()
    _G.LibStub = function() return nil end
    local KE = { Print = function() end }
    if opts.withEncounterData then
        helpers.loadModule("Modules/DungeonTimers/EncounterData.lua", KE)
    end
    helpers.loadModule("Modules/DungeonTimers/DungeonTimers.lua", KE)
    return modules["DungeonTimers"], KE
end

-- Core/Globals.lua. The KE seed carries the two Core/Colors.lua members
-- Globals reads (Theme accent + ColorTextByTheme — Colors loads first
-- in-game). Returns the KE table.
function L.loadGlobals(overrides)
    installMock(overrides, { C_Timer = inertTimer() })
    helpers.installAddonShim()
    -- Fake LSM: "GoodFont" is a known-valid non-default key so font-repair
    -- specs can tell "kept" apart from "reset to Expressway".
    local lsm = {
        Register = function() end,
        Fetch = function(_, _, name) return name and ("path/" .. name) or nil end,
        IsValid = function(_, _, name) return name == "Expressway" or name == "GoodFont" end,
    }
    _G.LibStub = function(name)
        if name == "LibSharedMedia-3.0" then return lsm end
        return nil
    end
    _G.C_AddOns = {
        GetAddOnMetadata = function() return "KE" end,
        IsAddOnLoaded = function() return false end,
    }
    _G.EditModeManagerFrame = nil
    _G.UIParent = noopFrame()   -- file-scope font probe: UIParent:CreateFontString()
    _G.SlashCmdList = {}        -- /kes registration happens at file scope
    _G.ReloadUI = function() end
    _G.GetSpecialization = function() return 2 end
    _G.GetSpecializationRole = function() return "HEALER" end   -- healer-context live path reachable
    local KE = {
        Theme = { accent = { 1, 0, 0.549, 1 } },
        ColorTextByTheme = function(_, text) return text end,
    }
    return helpers.loadModule("Core/Globals.lua", KE)
end

-- Modules/DamageMeter/Core.lua (KE.DamageMeter is set at file scope).
-- Secret handling is DECLARED, never real: a table with __secret == true
-- counts as secret, so specs exercise guard branches only — real 12.0 taint
-- semantics stay in-game-only (see the _wow_mock header). Returns DM, KE.
function L.loadDMCore(overrides)
    installMock(overrides, {
        C_Timer = inertTimer(),
        issecretvalue = function(v) return type(v) == "table" and v.__secret == true end,
        -- Deterministic stand-in: numbers pass through un-abbreviated. Specs
        -- assert KE's routing/clamping, never Blizzard abbreviation output.
        AbbreviateNumbers = function(v)
            if type(v) == "table" then return "SECRETSTR" end
            return tostring(v)
        end,
    })
    helpers.installAddonShim()
    _G.UIParent = noopFrame()
    _G.LibStub = function() return nil end
    _G.CreateAbbreviateConfig = function(cfg) return cfg end
    _G.C_ChatInfo = { SendChatMessage = function() end }
    -- Core.lua reads Enum.* members at file scope. The real values never
    -- matter headlessly — any Enum.X.Y resolves to the stable string "X.Y",
    -- unique per member so comparisons against them still discriminate.
    _G.Enum = setmetatable({}, { __index = function(_, group)
        return setmetatable({}, { __index = function(t, member)
            rawset(t, member, tostring(group) .. "." .. tostring(member))
            return t[member]
        end })
    end })
    local KE = { Print = function() end }
    helpers.loadModule("Modules/DamageMeter/Core.lua", KE)
    return KE.DamageMeter, KE
end

-- Core/PixelPerfect.lua. Defaults model a PERFECT UI scale (768/1440 at
-- 1440p → pixelSize exactly 1). The stubs read opts live: mutate
-- opts.effectiveScale (or physicalHeight) and call KE:UpdatePixelCache() to
-- drive cache-invalidation cases. Returns the KE table.
function L.loadPixelPerfect(opts, overrides)
    opts = opts or {}
    opts.physicalWidth = opts.physicalWidth or 2560
    opts.physicalHeight = opts.physicalHeight or 1440
    opts.effectiveScale = opts.effectiveScale or (768 / 1440)
    mock.install(overrides)
    helpers.installAddonShim()
    _G.GetPhysicalScreenSize = function() return opts.physicalWidth, opts.physicalHeight end
    _G.UIParent = { GetEffectiveScale = function() return opts.effectiveScale end }
    return helpers.loadModule("Core/PixelPerfect.lua")
end

-- Core/Nicknames.lua against the REAL embedded serialization stack (LibStub,
-- CallbackHandler, AceSerializer, LibDeflate) so export/import round-trips
-- exercise real encoding, not a mirror. Nicknames.lua captures its globals
-- as file-scope upvalues, so every stub must exist BEFORE its loadModule.
-- Returns the KE table (nickname store: KE.db.global.Nicknames, read live).
function L.loadNicknames(overrides)
    installMock(overrides, { UnitName = function() return "Bob" end })
    helpers.installAddonShim()
    -- WoW string-global aliases the embedded libs expect.
    _G.strmatch = string.match
    _G.securecallfunction = function(fn, ...) return fn(...) end
    -- Other loaders install fake LibStub FUNCTIONS; the real lib can only
    -- version-upgrade over a table, so clear it before loading fresh.
    _G.LibStub = nil
    helpers.loadModule("Libs/LibStub/LibStub.lua", {})
    helpers.loadModule("Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua", {})
    helpers.loadModule("Libs/AceSerializer-3.0/AceSerializer-3.0.lua", {})
    helpers.loadModule("Libs/LibDeflate/LibDeflate.lua", {})
    -- Unit identity consistent with the mock UnitName ("Bob" on "Realm").
    _G.UnitFullName = function() return "Bob", "Realm" end
    _G.UnitIsPlayer = function() return true end
    _G.GetNormalizedRealmName = function() return "Realm" end
    local KE = { db = { global = { Nicknames = {} } } }
    return helpers.loadModule("Core/Nicknames.lua", KE)
end

-- Modules/Dungeons/TargetedSpells.lua pure helpers. Returns TS, KE.
function L.loadTargetedSpells(overrides)
    installMock(overrides, { C_Timer = inertTimer() })
    local modules = helpers.installAddonShim()
    _G.UIParent = noopFrame()
    _G.LibStub = function() return nil end
    local KE = { Print = function() end, curves = {} }
    helpers.loadModule("Modules/Dungeons/TargetedSpells.lua", KE)
    return modules["TargetedSpells"], KE
end

return L

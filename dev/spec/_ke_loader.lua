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
-- overrides as a second arg; the rest take overrides first (loadGlobals takes
-- overrides first AND an optional opts second). Override keys
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
        NewTimer = function() return { Cancel = function() end } end,
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

-- Like noopFrame, but SetSize/SetPoint calls are recorded instead of
-- swallowed. Used wherever a spec needs to inspect a frame CreateFrame
-- handed back to production code -- e.g. LootRoll's addon-owned stack
-- anchor, which a spec cannot reach any other way.
local function trackablePointFrame()
    local f = {
        _points = {},
        SetSize = function(self, w, h) self._w, self._h = w, h end,
        GetWidth = function(self) return self._w end,
        GetHeight = function(self) return self._h end,
        ClearAllPoints = function(self) self._points = {} end,
        SetPoint = function(self, point, rel, relPoint, x, y)
            self._points[#self._points + 1] =
                { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
        end,
        CreateFontString = function() return noopObject() end,
    }
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
    local KE = {
        Print = function() end,
        GetGlobalFont = function() return "Expressway" end,
    }
    if opts.withEncounterData then
        helpers.loadModule("Modules/DungeonTimers/EncounterData.lua", KE)
    end
    helpers.loadModule("Modules/DungeonTimers/DungeonTimers.lua", KE)
    return modules["DungeonTimers"], KE
end

-- Core/Globals.lua. The KE seed carries the two Core/Colors.lua members
-- Globals reads (Theme accent + ColorTextByTheme — Colors loads first
-- in-game). Returns the KE table, plus a table that the geterrorhandler
-- stub appends xpcall-caught error messages into (used by the
-- KE:RunAfterCombat drain spec to assert an errored closure still reaches
-- the error handler).
function L.loadGlobals(overrides, opts)
    opts = opts or {}
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
    -- opts.loadedAddOns is a name->true set of addons IsAddOnLoaded reports;
    -- absent means nothing is loaded, the historical behaviour. It is an opt
    -- rather than a mock override because Core/Globals.lua localizes C_AddOns
    -- at file scope, so reassigning the namespace after the load is too late.
    local loadedAddOns = opts.loadedAddOns or {}
    _G.C_AddOns = {
        GetAddOnMetadata = function() return "KE" end,
        IsAddOnLoaded = function(name) return loadedAddOns[name] == true end,
    }
    _G.EditModeManagerFrame = nil
    _G.UIParent = noopFrame()   -- file-scope font probe: UIParent:CreateFontString()
    _G.SlashCmdList = {}        -- /kes registration happens at file scope
    _G.ReloadUI = function() end
    _G.GetSpecialization = function() return 2 end
    _G.GetSpecializationRole = function() return "HEALER" end   -- healer-context live path reachable
    _G.UnitClass = function() return "Mock", "EVOKER" end       -- PreviewManager classRestriction gate
    -- geterrorhandler() returns Blizzard's current error handler function;
    -- KE:RunAfterCombat's drain loop passes it to xpcall so one closure's
    -- error can't abort the rest of the queue. Not stubbed by _wow_mock, so
    -- record here in the same style as the frames it returns for firing events.
    local caughtErrors = {}
    _G.geterrorhandler = function()
        return function(err) caughtErrors[#caughtErrors + 1] = err end
    end
    local KE = {
        Theme = { accent = { 1, 0, 0.549, 1 } },
        ColorTextByTheme = function(_, text) return text end,
        -- Core/Secret.lua loads before Globals in-game, so its members belong
        -- to the seed too. KE:CanReanchorNow reads this one.
        IsSecretValue = function(_, value)
            return issecretvalue and issecretvalue(value)
        end,
    }
    return helpers.loadModule("Core/Globals.lua", KE), caughtErrors
end

-- Core/EditMode.lua onto an ALREADY-LOADED KE (its category predicate calls
-- KE:GetSectionForItem, which Core/Globals.lua defines, and it reads KE.Theme
-- at file scope). Pass the table L.loadGlobals returned. The file only defines
-- functions at load -- no frames, no slash registration -- so whatever mock the
-- caller's loader installed is enough. Returns the EditMode table.
function L.loadEditMode(KE)
    return helpers.loadModule("Core/EditMode.lua", KE).EditMode
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

-- Modules/DamageMeter/History.lua on top of a loaded DM Core. Same honesty
-- boundary as loadDMCore (declared secrets, mocked C_*). Returns DM, KE.
function L.loadDMHistory(overrides)
    local DM, KE = L.loadDMCore(overrides)
    _G.debugprofilestop = _G.debugprofilestop or function() return 0 end
    helpers.loadModule("Modules/DamageMeter/History.lua", KE)
    return DM, KE
end

-- Modules/DamageMeter/Dock.lua on top of a loaded DM Core. Dock.lua reads
-- KE:PixelSnap at file scope and captures five platform globals as upvalues, so
-- each must exist BEFORE the load; loadDMCore already supplies three of the
-- five, and the two here are the remainder. Same honesty boundary as
-- loadDMCore. Returns DM, KE.
--
-- PixelSnap is an IDENTITY stub, not the real snapper: the dock arithmetic
-- these specs assert is addition and subtraction over already-snapped inputs, so
-- a real snapper would only put grid rounding into assertions that are not about
-- the grid.
function L.loadDMDock(overrides)
    local DM, KE = L.loadDMCore(overrides)
    KE.PixelSnap = KE.PixelSnap or function(_, v) return v end
    _G.GetCursorPosition = _G.GetCursorPosition or function() return 0, 0 end
    _G.IsInInstance = _G.IsInInstance or function() return false, "none" end
    helpers.loadModule("Modules/DamageMeter/Dock.lua", KE)
    return DM, KE
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
    _G.StaticPopupDialogs = {}  -- in-game Blizzard defines it; module must never assign the global
    local KE = { Print = function() end, curves = {} }
    helpers.loadModule("Modules/Dungeons/TargetedSpells.lua", KE)
    return modules["TargetedSpells"], KE
end

-- Core/ProfileManager.lua over a fake AceDB-shaped KE.db. Mirrors the AceDB
-- semantics the manager depends on: SetProfile early-returns when already on
-- that profile, and OnProfileChanged/OnProfileCopied/OnProfileReset fire
-- SYNCHRONOUSLY inside the mutating call (AceDB-3.0.lua).
-- Specs replicate Core/Main.lua's callback registration themselves.
-- Returns PM, KE, db.
function L.loadProfileManager(overrides)
    installMock(overrides, { C_Timer = inertTimer() })
    helpers.installAddonShim()
    _G.LibStub = function() return setmetatable({}, { __index = function() return function() end end }) end
    local callbacks = {}
    local db = {
        profiles = { Default = {} },
        keys = { profile = "Default" },
        global = {},
    }
    db.profile = db.profiles.Default
    local function fire(event, ...)
        for _, fn in ipairs(callbacks[event] or {}) do fn(...) end
    end
    function db:GetProfiles(into)
        local list = into or {}
        for name in pairs(self.profiles) do list[#list + 1] = name end
        return list
    end
    function db:GetCurrentProfile() return self.keys.profile end
    function db:SetProfile(name)
        if name == self.keys.profile then return end
        self.profiles[name] = self.profiles[name] or {}
        self.keys.profile = name
        self.profile = self.profiles[name]
        fire("OnProfileChanged", self, name)
    end
    function db:CopyProfile(source)
        local target = self.profiles[self.keys.profile]
        for k in pairs(target) do target[k] = nil end
        for k, v in pairs(self.profiles[source] or {}) do target[k] = v end
        fire("OnProfileCopied", self, source)
    end
    function db:ResetProfile()
        local target = self.profiles[self.keys.profile]
        for k in pairs(target) do target[k] = nil end
        fire("OnProfileReset", self)
    end
    function db:DeleteProfile(name) self.profiles[name] = nil end
    db.RegisterCallback = function(_, event, fn)
        callbacks[event] = callbacks[event] or {}
        callbacks[event][#callbacks[event] + 1] = fn
    end
    -- RefreshAllModules walks _G.KitnEssentials:IterateModules(); give the
    -- addon shim the minimal surface so profile ops don't crash in specs
    -- that don't install their own fake module registry.
    _G.KitnEssentials.IterateModules = _G.KitnEssentials.IterateModules or function() return pairs({}) end
    _G.KitnEssentials.EnableModule = _G.KitnEssentials.EnableModule or function() end
    _G.KitnEssentials.DisableModule = _G.KitnEssentials.DisableModule or function() end
    local KE = { db = db }
    helpers.loadModule("Core/ProfileManager.lua", KE)
    return KE.ProfileManager, KE, db
end

-- Core/Conflicts.lua. The fake KE carries the prompt API so a spec can capture
-- a prompt and answer it by calling the recorded onAccept/onCancel. Returns
-- KE, prompts (every CreatePrompt/CreateReloadPrompt call, in order),
-- disabled (addon names passed to C_AddOns.DisableAddOn), and printed (chat
-- lines, kept separate so prompt-count assertions stay exact).
function L.loadConflicts(overrides)
    installMock(overrides, {})
    local disabled = {}
    -- Models production: DisableAddOn flips the enable state while the addon
    -- stays LOADED for the rest of the session. Absent means enabled.
    local enableState = {}
    _G.C_AddOns = {
        IsAddOnLoaded = function() return false end,
        GetAddOnEnableState = function(name) return enableState[name] or 2 end,
        DisableAddOn = function(name)
            disabled[#disabled + 1] = name
            enableState[name] = 0
        end,
    }
    local prompts = {}
    local printed = {}
    local KE
    KE = {
        db = { profile = {} },
        activePrompt = nil,
        ShouldNotLoadModule = function() return false end,
        -- SEVEN placeholders between text and onAccept, matching the real
        -- signature's showEditBox, editBoxLabelText, useTexture, texturePath,
        -- textureSizeX, textureSizeY, textureColor (Core/Widgets.lua).
        -- Six would shift every later argument by one and silently capture
        -- closures as button labels.
        CreatePrompt = function(_, title, text, _, _, _, _, _, _, _,
                                onAccept, onCancel, acceptText, cancelText)
            -- ClosePrompt CLEARS the handle at Core/Widgets.lua BEFORE
            -- invoking either callback at :168, so the fake wraps them to do
            -- the same. A fake that leaves the handle set while a callback
            -- runs does not model production.
            local function wrap(fn)
                if not fn then return nil end
                return function(...) KE.activePrompt = nil; return fn(...) end
            end
            prompts[#prompts + 1] = {
                title = title, text = text,
                onAccept = wrap(onAccept), onCancel = wrap(onCancel),
                acceptText = acceptText, cancelText = cancelText,
            }
            -- The real CreatePrompt sets this singleton handle
            -- (Core/Widgets.lua); the stall-recovery path reads it.
            KE.activePrompt = { n = #prompts }
        end,
        CreateReloadPrompt = function(_, reason)
            prompts[#prompts + 1] = { reload = true, reason = reason }
            KE.activePrompt = { n = #prompts }
        end,
        RunAfterCombat = function(_, fn) fn() end,
        -- Chat lines go in their OWN list: folding them into prompts would
        -- break every "#prompts" assertion, since each choice prints.
        Print = function(_, msg) printed[#printed + 1] = msg end,
    }
    return helpers.loadModule("Core/Conflicts.lua", KE), prompts, disabled, printed
end

-- Modules/Skinning/ChatMessageHandler.lua. GetPFlag is pure string logic --
-- no WoW API -- so it unit-tests directly against the real KE table the
-- module writes onto (KE.ChatMessageHandler).
function L.loadChatMessageHandler(overrides)
    -- Timers stay INERT. _wow_mock's default C_Timer fires synchronously, which
    -- would flush a group of one before the second player is ever captured, so
    -- every grouping case would see two singular lines. The specs drive the
    -- flush explicitly with CMH.FlushAchievements().
    installMock(overrides, {
        C_Timer = { After = function() end },
    })

    -- The module captures these as file-scope upvalues at load time, so they
    -- must exist BEFORE loadModule or every one is captured as nil.
    _G.format = string.format
    _G.gsub = string.gsub
    _G.gmatch = string.gmatch
    _G.strmatch = string.match
    _G.strsub = string.sub
    _G.strlower = string.lower
    _G.strlen = string.len
    _G.sort = table.sort
    _G.tinsert = table.insert
    _G.strjoin = function(sep, ...) return table.concat({ ... }, sep) end
    _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    _G.RAID_CLASS_COLORS = {
        MAGE = { r = 0.25, g = 0.78, b = 0.92 },
        ROGUE = { r = 1, g = 0.96, b = 0.41 },
    }
    _G.GUILD_ACHIEVEMENT_EARNED_BY = "Earned by"
    _G.PLAYER_LIST_DELIMITER = ", "
    _G.GetTime = function() return 0 end
    _G.InCombatLockdown = function() return false end
    _G.PlaySoundFile = function() end
    _G.UnitName = function() return "Kitn" end
    -- GetNormalizedRealmName is deliberately NOT stubbed. Leaving it absent
    -- makes the specs exercise the display-realm stripping fallback, which is
    -- the path that can disagree with a chat sender's suffix.
    _G.UnitFullName = function() return "Kitn", "Ravencrest" end

    local KE = { db = { profile = { Skinning = { Chat = {} } } } }
    -- KE:NotSecretValue and KE:IsSecretValue are defined by Core/Secret.lua, not
    -- by the handler. Without this line every new case dies on
    -- "attempt to call method 'NotSecretValue' (a nil value)".
    helpers.loadModule("Core/Secret.lua", KE)
    return helpers.loadModule("Modules/Skinning/ChatMessageHandler.lua", KE)
end

-- Modules/Skinning/SkinAPI.lua. Creates frames at file scope (the hidden
-- parking frame and the edge refresher), so CreateFrame must exist before
-- the load. GetThemeColor is seeded rather than loading Core/AddonTheme.lua,
-- which would drag in the whole profile stack for two colour lookups.
local SKINAPI_THEME = {
    accent      = { 1.0, 0.0, 0.549, 1 },
    accentHover = { 1.0, 0.0, 0.549, 0.25 },
}

function L.loadSkinAPI(overrides)
    installMock(overrides, { C_Timer = inertTimer() })
    helpers.installAddonShim()
    _G.GetPhysicalScreenSize = function() return 2560, 1440 end
    _G.UIParent = {
        GetScale = function() return 1 end,
        GetEffectiveScale = function() return 1 end,
    }
    _G.CreateFrame = function() return noopFrame() end
    _G.hooksecurefunc = function() end
    _G.SetCheckButtonIsRadio = nil
    local KE = {
        Print = function() end,
        GetThemeColor = function(_, key) return SKINAPI_THEME[key] end,
        -- EnsureFontInit resolves an unset skin face through this.
        GetGlobalFont = function() return "Expressway" end,
        db = { profile = { Skinning = { BlizzardFrames = {} } } },
    }
    helpers.loadModule("Core/Secret.lua", KE)
    return helpers.loadModule("Modules/Skinning/SkinAPI.lua", KE)
end

-- Modules/Skinning/Tooltips.lua. TT is a file-local never assigned onto KE --
-- the shim registry is the only handle to it. Returns TT, KE.
-- `opts` carries globals _wow_mock does not manage; `overrides` is for
-- mock-managed keys only.
function L.loadTooltips(opts, overrides)
    opts = opts or {}
    installMock(overrides, { C_Timer = inertTimer() })
    -- C_CVar is outside the shared mock; the default models a client without
    -- the optional aura-ID CVar.
    _G.C_CVar = (overrides or {}).C_CVar or {
        GetCVar = function() return nil end,
        SetCVar = function() return true end,
    }
    local modules = helpers.installAddonShim()
    _G.UIParent = noopFrame()
    _G.CreateFrame = function() return noopFrame() end
    _G.hooksecurefunc = function() end
    _G.FACTION_BAR_COLORS = {
        [1] = { r = 0.87, g = 0.37, b = 0.37 },
        [4] = { r = 0.87, g = 0.87, b = 0.37 },
        [5] = { r = 0.37, g = 0.87, b = 0.37 },
    }
    -- ColorMixin entries, as the live table carries -- Blizzard builds these
    -- with CreateColor, so they answer :GetRGB(). A bare {r,g,b} here would let
    -- a colour-object caller pass headlessly and break in game.
    _G.RAID_CLASS_COLORS = {
        EVOKER = _G.CreateColor(0.20, 0.58, 0.50),
    }
    _G.UnitReaction = opts.UnitReaction or function() return 5 end
    _G.IsModifierKeyDown = opts.IsModifierKeyDown or function() return false end
    _G.GetPetActionInfo = opts.GetPetActionInfo or function() return nil end
    -- UnitColor's inputs. The class-colour branches are refusal rules, so they
    -- are driven from here rather than left to the live tooltip.
    _G.UnitIsPlayer = opts.UnitIsPlayer or function() return false end
    _G.UnitClass = opts.UnitClass or function() return "Evoker", "EVOKER" end
    _G.GetPlayerInfoByGUID = opts.GetPlayerInfoByGUID or function() return "Evoker", "EVOKER" end
    _G.C_ClassColor = opts.C_ClassColor or nil
    -- Specs drive helpers, module methods and PLAYER_ENTERING_WORLD directly;
    -- OnEnable remains outside this fixture.
    local KE = {
        Print = function() end,
        ShouldNotLoadModule = function() return false end,
        db = { profile = { Skinning = { Tooltips = { ShowIDs = "MODIFIER" } } } },
    }
    helpers.loadModule("Core/Secret.lua", KE)
    helpers.loadModule("Modules/Skinning/Tooltips.lua", KE)
    return modules["SkinTooltips"], KE
end

-- Modules/Skinning/EUIWindows.lua. Pure decision layer, so the load needs
-- no frames and no DB -- only a KE table to hang the two functions on and a
-- KE.Skins table for the cache. C_AddOns is left absent on purpose: the
-- live path must be a no-op when it cannot read an addon version, and a
-- spec that always supplies one would never exercise that.
function L.loadEUIWindows(overrides)
    installMock(overrides, {})
    local KE = { Skins = {} }
    return helpers.loadModule("Modules/Skinning/EUIWindows.lua", KE), KE
end

-- Modules/Combat/AuraEngine/Rules.lua. Pure decision logic -- no WoW API, no
-- frames -- so the load needs only a KE table to hang KE.AuraRules on.
-- Returns KE.AuraRules, KE.
function L.loadAuraRules(overrides)
    installMock(overrides, {})
    local KE = {}
    helpers.loadModule("Modules/Combat/AuraEngine/Rules.lua", KE)
    return KE.AuraRules, KE
end

-- Modules/Combat/AuraEngine/GlowRules.lua. Pure decision logic -- no WoW API,
-- no frames -- so the load needs only a KE table to hang KE.AuraGlowRules on.
-- Returns KE.AuraGlowRules, KE.
function L.loadAuraGlowRules(overrides)
    installMock(overrides, {})
    local KE = {}
    helpers.loadModule("Modules/Combat/AuraEngine/GlowRules.lua", KE)
    return KE.AuraGlowRules, KE
end

-- Modules/Combat/AuraEngine/Restriction.lua. The predicate is INJECTED
-- (opts.isHidden), so the load needs only a KE table to hang
-- KE.AuraRestriction on -- no C_Secrets/C_RestrictedActions stub. Returns
-- KE.AuraRestriction, KE.
function L.loadAuraRestriction(overrides)
    installMock(overrides, {})
    local KE = {}
    helpers.loadModule("Modules/Combat/AuraEngine/Restriction.lua", KE)
    return KE.AuraRestriction, KE
end

-- Modules/Combat/AuraEngine/Sound.lua. The api/resolveMedia/isHidden trio is
-- INJECTED, so the load needs only the default mock's Enum stub -- no
-- C_UnitAuras or LibSharedMedia. Returns KE.AuraSound, KE.
function L.loadAuraSound()
    mock.install()
    local KE = helpers.loadModule("Modules/Combat/AuraEngine/Sound.lua")
    return KE.AuraSound, KE
end

-- Modules/Combat/AuraEngine/Preview.lua. Only PlanEnter/PlanExit are
-- reachable from a spec -- both are pure and sit in a section of the file
-- with no upvalue dependency on Style/Container/Rules/Glow, so the load
-- needs only the default mock's Enum stub, same as loadAuraSound. Returns
-- KE.AuraPreview, KE.
function L.loadAuraPreview()
    mock.install()
    local KE = helpers.loadModule("Modules/Combat/AuraEngine/Preview.lua")
    return KE.AuraPreview, KE
end

-- Modules/Combat/AuraEngine/Rules.lua, Restriction.lua and Engine.lua on ONE
-- KE, in that order: Engine.lua captures KE.AuraRules as a file-scope local at
-- load, so loading Rules any later leaves that capture nil.
--
-- Everything the engine reaches beyond those three is project-owned and
-- stubbed. KE.EditMode is left ABSENT so the Edit Mode branch no-ops, and the
-- declaration carries no `sounds` key, so no sound registry is built and no
-- C_UnitAuras stub is needed.
--
-- Returns KE.AuraEngine, KE and one registered display. The container recorder
-- is KE.AuraContainer; a spec flips the restriction by reassigning
-- KE.AreAuraIdentitiesHidden, which the gate reads through KE at call time.
function L.loadAuraEngine()
    mock.install()

    local KE = {
        -- Unrestricted by default. This is the predicate the whole engine spec
        -- turns on, so every case that cares sets its own.
        AreAuraIdentitiesHidden = function() return false end,
    }

    -- Counted rather than swallowed: whether the container was created, and
    -- whether it was reconfigured afterwards, is the only thing the engine's
    -- permission rule can be observed by from outside.
    local container = { creates = 0, applyStates = 0, reconfigures = 0 }

    container.Create = function(display)
        container.creates = container.creates + 1
        -- The real handle's shape. Only anchorFrame is read outside the
        -- container itself, and only by the Edit Mode branch disabled above.
        return {
            anchorFrame        = noopFrame(),
            container          = noopFrame(),
            corner             = "TOPLEFT",
            defaultIconsPerRow = display.defaultIconsPerRow,
        }
    end
    container.ApplyState = function() container.applyStates = container.applyStates + 1 end
    container.Reconfigure = function() container.reconfigures = container.reconfigures + 1 end
    KE.AuraContainer = container

    helpers.loadModule("Modules/Combat/AuraEngine/Rules.lua", KE)
    helpers.loadModule("Modules/Combat/AuraEngine/Restriction.lua", KE)
    helpers.loadModule("Modules/Combat/AuraEngine/Engine.lua", KE)

    -- Register keys its duplicate check on the owner object and hands it every
    -- event registration, so the owner is real work even where a spec never
    -- fires an event. Reachable afterwards as display.owner.
    local owner = { events = {} }
    owner.RegisterEvent = function(_, event, handler) owner.events[event] = handler end

    -- Only the fields Register and ApplySettings actually read.
    local display = KE.AuraEngine.Register(owner, {
        key                = "AuraEngineSpec",
        sortMethod         = "TIME",
        groups             = {},
        splitLimit         = function() return {} end,
        buildPreview       = function() return {} end,
        defaultIconsPerRow = 6,
    }, function() return { Enabled = true } end)

    return KE.AuraEngine, KE, display
end

-- Modules/Skinning/SkinAPI.lua AND Modules/Skinning/EUIWindows.lua on the
-- SAME KE instance. loadSkinAPI and loadEUIWindows above each return a
-- separate KE, so no spec driven through either loader alone can push a real
-- resolved suppression record through the real dispatcher and diagnostics --
-- exactly why the table-concatenation crash the two functions used to have
-- was invisible to busted. Returns the composed KE.
function L.loadSkinAPI_EUIWindows(overrides)
    local KE = L.loadSkinAPI(overrides)
    helpers.loadModule("Modules/Skinning/EUIWindows.lua", KE)
    return KE
end

-- Modules/Skinning/Frames/Alerts.lua. The Alerts/LootToast key split lives
-- entirely in the two S:RegisterEarly call sites at file scope -- nothing
-- else in the file needs to run to observe it, so KE.Skins carries only a
-- recorder for that one method (every Dress*/Skin* function stays merely
-- DEFINED, never invoked, since nothing here calls hooksecurefunc's
-- captured closures). Returns the recorded calls, each
-- { fn = <function>, key = <string> }, in registration order.
function L.loadAlertsSkin(overrides)
    installMock(overrides, {})
    local calls = {}
    local KE = { Skins = {
        RegisterEarly = function(_, fn, key) calls[#calls + 1] = { fn = fn, key = key } end,
    } }
    helpers.loadModule("Modules/Skinning/Frames/Alerts.lua", KE)
    return calls
end

-- Walks a Lua function's upvalues by NAME. Returns the upvalue's current
-- value, or nil if fn has no upvalue by that name.
local function findUpvalue(fn, name)
    local i = 1
    while true do
        local upName, upVal = debug.getupvalue(fn, i)
        if not upName then return nil end
        if upName == name then return upVal end
        i = i + 1
    end
end

-- Modules/Skinning/UIWidgets.lua. StyleWidgetByType is a module METHOD, so
-- it's reachable straight off the returned UIW table -- no seam needed.
-- InTooltip and SetFontIfChanged are file-locals with no stored handle:
--   * SetFontIfChanged is itself a local FUNCTION value, so it is an upvalue
--     of any stored method that calls it directly (StyleStatusBarWidget).
--     findUpvalue recovers the function object straight off that upvalue
--     slot -- no need to ever run StyleStatusBarWidget itself.
--   * InTooltip is referenced only inside the anonymous closures SetupHooks
--     hands to hooksecurefunc, never by a stored method. hooksecurefunc is
--     stubbed to capture those closures; SetupHooks is run once (with both
--     stock mixins present so it hooks in one pass, no deferred retry) to
--     create them; InTooltip is pulled off the first captured closure's
--     upvalues.
-- Returns UIW, KE, seams (seams.InTooltip, seams.SetFontIfChanged).
function L.loadUIWidgets(overrides)
    installMock(overrides, { C_Timer = inertTimer() })
    local modules = helpers.installAddonShim()
    _G.UIParent = noopFrame()
    local hooks = {}
    _G.hooksecurefunc = function(target, method, fn)
        hooks[#hooks + 1] = { target = target, method = method, fn = fn }
    end
    _G.UIWidgetTemplateStatusBarMixin = {}
    _G.UIWidgetTemplateTextWithStateMixin = {}
    local KE = {
        db = { profile = { Skinning = { UIWidgets = {} } } },
        ShouldNotLoadModule = function() return false end,
        GetFontPath = function(_, name) return name end,
        GetFontOutline = function(_, o) return o end,
        GetEffectiveFont = function(_, db) return db and db.FontFace end,
        AddBorders = function() end,
    }
    helpers.loadModule("Modules/Skinning/UIWidgets.lua", KE)
    local UIW = modules["UIWidgets"]

    UIW:SetupHooks()
    local seams = {
        SetFontIfChanged = findUpvalue(UIW.StyleStatusBarWidget, "SetFontIfChanged"),
        InTooltip = hooks[1] and findUpvalue(hooks[1].fn, "InTooltip"),
    }
    return UIW, KE, seams
end

-- Modules/Skinning/ContextMenus.lua. SkinFrame is a file-local with no stored
-- handle, but OnMenuOpen -- also a file-local -- calls it directly, so it sits
-- in OnMenuOpen's upvalue slots. OnMenuOpen is handed straight to
-- hooksecurefunc by CM:Setup, so stubbing hooksecurefunc captures the function
-- object itself and findUpvalue lifts SkinFrame off it.
-- Returns CM, KE, seams (seams.SkinFrame), and a `calls` recorder holding the
-- skin operations SkinFrame performed.
function L.loadContextMenus(overrides)
    installMock(overrides, { C_Timer = inertTimer() })
    local modules = helpers.installAddonShim()
    local hooks = {}
    _G.hooksecurefunc = function(target, method, fn)
        hooks[#hooks + 1] = { target = target, method = method, fn = fn }
    end
    local manager = {}
    _G.Menu = { GetManager = function() return manager end }

    local calls = { stripped = {}, backdrops = {} }
    local KE = {
        db = { profile = { Skinning = { ContextMenus = { Enabled = true } } } },
        IsSecretValue = function(_, v) return v == "SECRET" end,
        Print = function() end,
        Skins = {
            StripTextures = function(frame) calls.stripped[#calls.stripped + 1] = frame end,
            Backdrop = function(frame)
                local bd = { frame = frame, w = nil, h = nil, shown = false }
                function bd:ClearAllPoints() end
                function bd:SetPoint() end
                function bd:SetSize(w, h) self.w, self.h = w, h end
                function bd:SetFrameLevel() end
                function bd:Show() self.shown = true end
                function bd:Hide() self.shown = false end
                calls.backdrops[#calls.backdrops + 1] = bd
                return bd
            end,
            TrimScrollBar = function() end,
        },
    }
    helpers.loadModule("Modules/Skinning/ContextMenus.lua", KE)
    local CM = modules["ContextMenus"]

    CM:Setup()
    local seams = { SkinFrame = hooks[1] and findUpvalue(hooks[1].fn, "SkinFrame") }
    return CM, KE, seams, calls
end

-- Modules/Skinning/LootRoll.lua. LR:UpdateDB/OnInitialize/OnEnable are never
-- run -- specs set LR.db themselves, the same way a real OnInitialize would
-- have via KE.db.profile.Skinning.LootRoll. GroupLootContainer is a
-- secure-managed Blizzard frame, headlessly replaced by calling the returned
-- `container(mock)` setter, which just assigns _G.GroupLootContainer -- the
-- global LR:ApplyPosition reads. The module positions its OWN addon-owned
-- stack anchor (LR:GetStackAnchor), never the container, so CreateFrame
-- returns a trackablePointFrame and LR._lastPoint() reads that anchor's
-- _points log instead of the container mock's. Returns LR, container.
function L.loadLootRoll(overrides)
    installMock(overrides, { C_Timer = inertTimer() })
    local modules = helpers.installAddonShim()
    _G.UIParent = noopFrame()
    _G.CreateFrame = function() return trackablePointFrame() end
    _G.hooksecurefunc = function() end
    _G.InCombatLockdown = function() return false end
    -- The module's DEBUG_LR tracer captures these as upvalues AT LOAD, so they
    -- must exist before loadModule -- and the whole suite must survive the flag
    -- being flipped to true. It shipped `true` once during the probe
    -- and every LootRoll spec errored on a nil debugprofilestop, which is a
    -- spec-harness gap, not a module bug: a debug flag must never be able to
    -- break the test suite. KE:Print is stubbed for the same reason.
    _G.debugprofilestop = _G.debugprofilestop or function() return 0 end
    local KE = {
        db = { profile = { Skinning = { LootRoll = {} } } },
        ShouldNotLoadModule = function() return false end,
        Skins = {},
        Print = function() end,
    }
    helpers.loadModule("Modules/Skinning/LootRoll.lua", KE)
    local LR = modules["LootRoll"]

    local function container(mockContainer)
        _G.GroupLootContainer = mockContainer
    end

    LR._lastPoint = function()
        local a = LR.stackAnchor
        if not a or not a._points or #a._points == 0 then return nil end
        return a._points[#a._points]
    end

    return LR, container
end

-- Modules/Skinning/LootRoll.lua followed by Modules/Skinning/LootRollBars.lua
-- on the same KE/module instance -- LootRollBars.lua attaches its pool
-- (RollBar_Get/Create, ShowPreview/HidePreview, SetupRollBars/TeardownRollBars)
-- onto the LR table LootRoll.lua registered, exactly as they load in-game via
-- Skinning.xml. CreateFrame returns a rich stub whose Get*Texture methods
-- return real (if inert) texture objects -- RollBar_Create's RollTexCoords
-- pass calls `icon:SetTexCoord(...)` on whatever GetNormalTexture() et al.
-- return, so a plain nil (the generic noopFrame's metatable fallback) would
-- error there. Unlike noopFrame, the stub's __index only synthesises a
-- no-op for CapitalCase keys (WoW API method convention) -- RollBar_Create
-- stores plain data straight on the frame (bar.rollID, bar.time, ...), all
-- lowercase-first, and a blanket "any missing key is a truthy function"
-- fallback would make `if not bar.rollID` always false, breaking every free/
-- busy pool check. KE.Skins carries just enough of the real S surface
-- (Backdrop/GetBackdrop paired through a per-frame table, SetFont, palette,
-- borderColor) for RollBar_Create/ShowPreview/START_LOOT_ROLL to run without
-- touching real skinning code. LR:UpdateDB() seeds LR.db the same way a real
-- OnInitialize would. Returns LR.
function L.loadLootRollBars(overrides)
    installMock(overrides, { C_Timer = inertTimer() })
    local modules = helpers.installAddonShim()
    _G.UIParent = noopFrame()
    -- Missing CapitalCase keys (WoW API methods) resolve to a no-op;
    -- missing lowercase keys (data fields the module assigns itself) read
    -- as a real nil, same as an unset field on a genuine WoW frame.
    local function apiStubIndex(_, key)
        if type(key) == "string" and key:match("^%u") then
            return function() end
        end
        return nil
    end
    local function textureStub()
        return setmetatable({}, { __index = apiStubIndex })
    end
    local function rollBarFrame()
        local normalTex, pushedTex, disabledTex, highlightTex =
            textureStub(), textureStub(), textureStub(), textureStub()
        local f = {
            GetNormalTexture = function() return normalTex end,
            GetPushedTexture = function() return pushedTex end,
            GetDisabledTexture = function() return disabledTex end,
            GetHighlightTexture = function() return highlightTex end,
            CreateFontString = function() return textureStub() end,
            CreateTexture = function() return textureStub() end,
        }
        return setmetatable(f, { __index = apiStubIndex })
    end
    _G.CreateFrame = function() return rollBarFrame() end
    _G.hooksecurefunc = function() end
    _G.InCombatLockdown = function() return false end
    local backdrops = setmetatable({}, { __mode = "k" })
    local iconCalls = {}
    local KE = {
        db = { profile = { Skinning = { LootRoll = {} } } },
        ShouldNotLoadModule = function() return false end,
        GetStatusbarPath = function(_, name) return name end,
        Skins = {
            Backdrop = function(frame)
                local bd = textureStub()
                backdrops[frame] = bd
                return bd
            end,
            GetBackdrop = function(frame) return backdrops[frame] end,
            SetFont = function() end,
            -- The real S.Icon (Modules/Skinning/SkinAPI.lua) applies the
            -- standard crop and a pixel snap. Neither is observable headlessly,
            -- so this records the call instead: a spec can assert the item icon
            -- goes through the shared helper rather than a hardcoded SetTexCoord.
            Icon = function(icon, withBackdrop)
                iconCalls[#iconCalls + 1] = { icon = icon, withBackdrop = withBackdrop }
            end,
            palette = { brand = { 1, 0, 0.549 } },
            borderColor = { 0, 0, 0, 1 },
        },
    }
    -- Same reason as loadLootRoll: LootRoll.lua's DEBUG_LR tracer captures
    -- debugprofilestop at load, and the suite must not break when that flag is
    -- flipped on for a live probe.
    _G.debugprofilestop = _G.debugprofilestop or function() return 0 end
    helpers.loadModule("Modules/Skinning/LootRoll.lua", KE)
    helpers.loadModule("Modules/Skinning/LootRollBars.lua", KE)
    local LR = modules["LootRoll"]
    LR:UpdateDB()
    local seams = {
        setBlizzardRollsEnabled = findUpvalue(LR.SetupRollBars, "SetBlizzardRollsEnabled"),
    }
    return LR, iconCalls, seams
end

-- Modules/Skinning/LootFrame.lua. LF:UpdateDB/OnInitialize/OnEnable are never
-- run -- specs set LF.db themselves, the same way a real OnInitialize would
-- have via KE.db.profile.Skinning.Loot. All the file-scope `local X = X`
-- captures (CloseLoot, LootSlot, GetNumLootItems, ...) tolerate a nil global
-- at load time, so this loader only needs KitnEssentials truthy and a KE.Skins
-- table -- nothing calls into the Loot API surface until LF:Build()/OnEnable
-- run, which this loader deliberately does not do. Returns LF.
function L.loadLootFrame(overrides)
    installMock(overrides, { C_Timer = inertTimer() })
    local modules = helpers.installAddonShim()
    _G.UIParent = noopFrame()
    _G.CreateFrame = function() return noopFrame() end
    _G.hooksecurefunc = function() end
    local KE = {
        db = { profile = { Skinning = { Loot = {} } } },
        ShouldNotLoadModule = function() return false end,
        Skins = {},
    }
    helpers.loadModule("Modules/Skinning/LootFrame.lua", KE)
    local LF = modules["LootFrame"]
    LF:UpdateDB()
    return LF
end

-- Modules/Combat/Cursor.lua. The file-scope `local X = X` captures include
-- C_Spell.GetSpellCooldown, so C_Spell must exist before load or the index
-- throws. Nothing creates a frame at load time -- CreateCursorFrame and the
-- satellite constructors only run from lifecycle methods, which this loader
-- deliberately does not call. C.db is pointed at the profile table the same
-- way a real C:UpdateDB() would.
--
-- Any override for a key in MANAGED_MOCK_KEYS (C_Timer, GetTime,
-- InCombatLockdown, CreateFrame and the rest) is forwarded to installMock so
-- the caller still wins on it. Every other API here is UNMANAGED, so it is
-- assigned to _G directly and its per-test override is read off `overrides`
-- here rather than handed to installMock, which would drop it.
-- Returns C, KE, seams.
-- Keys _wow_mock.install actually consumes (dev/spec/_wow_mock.lua).
-- A caller override for one of these MUST be routed through installMock or it
-- is discarded; anything not on this list must be assigned to _G directly.
local MANAGED_MOCK_KEYS = {
    "CreateFrame", "InCombatLockdown", "GetTime", "C_Timer",
    "issecretvalue", "issecrettable", "canaccessvalue", "canaccesstable",
    "UnitName", "UnitGUID", "UnitExists", "UnitIsUnit",
    "AbbreviateNumbers", "BreakUpLargeNumbers",
}

local function managedSubset(overrides)
    local t = {}
    for _, k in ipairs(MANAGED_MOCK_KEYS) do
        if overrides[k] ~= nil then t[k] = overrides[k] end
    end
    return t
end

-- Mirrors Core/Globals.lua's art table. Membership is what makes a set an ART
-- set, so a fixture that omits a set changes what the code under test decides.
local ROLE_ICON_ART_SETS = {
    "modern", "outlined", "framed",
    "hexagon", "plain", "muted", "shaded",
}

-- `extra` injects art sets the production table does not have. That is what
-- makes derivation falsifiable: a hand-maintained validity list containing
-- exactly today's keys satisfies every assertion about today's keys, so only
-- a set the list CANNOT know about proves the list is derived at all.
local function roleIconArt(PATH, extra)
    local art = {}
    local function add(set)
        art[set] = {
            TANK = PATH .. [[RoleIcons\tank-]] .. set .. ".png",
            HEALER = PATH .. [[RoleIcons\healer-]] .. set .. ".png",
            DAMAGER = PATH .. [[RoleIcons\dps-]] .. set .. ".png",
        }
    end
    for i = 1, #ROLE_ICON_ART_SETS do add(ROLE_ICON_ART_SETS[i]) end
    for i = 1, #(extra or {}) do add(extra[i]) end
    return art
end

-- Modules/Skinning/Frames/LFG.lua. Only the role-icon resolver and painters
-- are under test; the S stub carries the minimum the file touches at load,
-- which is Register (called at file scope) plus the data/PixelSnap pair the
-- painters use.
function L.loadLFGSkin(overrides)
    overrides = overrides or {}
    installMock(managedSubset(overrides), {
        C_Timer = inertTimer(),
        InCombatLockdown = function() return false end,
        -- Overridable so a case can mark a sentinel secret; Core/Secret.lua
        -- reads this global and nothing else.
        issecretvalue = overrides.issecretvalue or function() return false end,
    })
    helpers.installAddonShim()
    _G.hooksecurefunc = overrides.hooksecurefunc or function() end
    _G.CreateFrame = overrides.CreateFrame or function() return noopFrame() end
    _G.C_LFGList = overrides.C_LFGList or {}
    _G.RAID_CLASS_COLORS = overrides.RAID_CLASS_COLORS or {}
    _G.LFG_LIST_GROUP_DATA_ATLASES = overrides.LFG_LIST_GROUP_DATA_ATLASES
        or { TANK = "atlas-tank", HEALER = "atlas-heal", DAMAGER = "atlas-dps" }
    _G.LFG_LIST_GROUP_DATA_ROLE_ORDER = overrides.LFG_LIST_GROUP_DATA_ROLE_ORDER
        or { "TANK", "HEALER", "DAMAGER" }

    local frameData = {}
    local KE = {
        PATH = [[Interface\AddOns\KitnEssentials\Media\]],
        db = { profile = { Skinning = overrides.Skinning or { BlizzardFrames = {} } } },
    }
    KE.ROLE_ICON_ART = roleIconArt(KE.PATH, overrides.extraRoleIconArt)
    KE.ROLE_ICONS = KE.ROLE_ICON_ART.modern
    KE.Skins = {
        Register = function() end,
        -- LFG.lua calls S:RegisterEarly(Skin, "LFG") at file scope. Without
        -- this the module errors while loading and no case ever runs.
        RegisterEarly = function() end,
        PixelSnap = function() end,
        data = function(_, f)
            frameData[f] = frameData[f] or {}
            return frameData[f]
        end,
    }
    -- S.data is called as a plain function, not a method, in this file.
    KE.Skins.data = function(f)
        frameData[f] = frameData[f] or {}
        return frameData[f]
    end
    helpers.loadModule("Core/Secret.lua", KE)
    helpers.loadModule("Modules/Skinning/Frames/LFG.lua", KE)
    return KE, KE.Skins
end

-- The builder lives in its own file precisely so a spec can load it without
-- Modules/Skinning/Chat.lua, which is far too large to pull in for one pure
-- function.
function L.loadChatRoleIconStrings()
    local helpersLocal = require("dev.spec._helpers")
    local KE = { PATH = [[Interface\AddOns\KitnEssentials\Media\]] }
    KE.ROLE_ICON_ART = roleIconArt(KE.PATH)
    KE.ROLE_ICONS = KE.ROLE_ICON_ART.modern
    -- loadModule returns the KE table, never the chunk's own return value,
    -- so the builder is taken off KE explicitly.
    helpersLocal.loadModule("Modules/Skinning/ChatRoleIcons.lua", KE)
    return KE.BuildChatRoleIconStrings
end

-- The cache-key rule from the same file. Pure, so it needs no art table and
-- no mock environment at all.
function L.loadChatRoleIconKeys()
    local helpersLocal = require("dev.spec._helpers")
    local KE = { PATH = "", ROLE_ICON_ART = {} }
    helpersLocal.loadModule("Modules/Skinning/ChatRoleIcons.lua", KE)
    return KE.ChatRoleIconKeys
end

-- Modules/Skinning/RoleIconSamples.lua. Same reason as the chat builder above:
-- the file holds one pure function and needs no KE.Skins and no frames, so it
-- loads against a bare KE carrying only the art table.
function L.loadRoleIconSample()
    local helpersLocal = require("dev.spec._helpers")
    local KE = { PATH = [[Interface\AddOns\KitnEssentials\Media\]] }
    KE.ROLE_ICON_ART = roleIconArt(KE.PATH)
    helpersLocal.loadModule("Modules/Skinning/RoleIconSamples.lua", KE)
    return KE.BuildRoleIconSample, KE.ROLE_ICON_ART
end

function L.loadChatMemberAcceptor(overrides)
    overrides = overrides or {}
    -- Core/Secret.lua calls CreateFrame at FILE SCOPE and registers events on
    -- the result, so the mock environment has to be installed before it loads
    -- rather than just the one global the helper under test consults.
    installMock(managedSubset(overrides), {
        C_Timer = inertTimer(),
        InCombatLockdown = function() return false end,
        CreateFrame = function() return noopFrame() end,
        issecretvalue = overrides.issecretvalue or function() return false end,
    })
    local helpersLocal = require("dev.spec._helpers")
    local KE = { PATH = "", ROLE_ICONS = {}, ROLE_ICON_ART = {} }
    helpersLocal.loadModule("Core/Secret.lua", KE)
    helpersLocal.loadModule("Modules/Skinning/ChatRoleIcons.lua", KE)
    return KE.AcceptChatMember
end

function L.loadCursor(overrides)
    overrides = overrides or {}
    -- Managed overrides go THROUGH installMock so the caller still wins on
    -- them; passing {} here would silently discard a caller's C_Timer or
    -- GetTime override. CreateFrame is a default rather than a later _G
    -- assignment for the same reason.
    installMock(managedSubset(overrides), {
        C_Timer = inertTimer(),
        GetTime = function() return 0 end,
        InCombatLockdown = function() return false end,
        CreateFrame = function() return noopFrame() end,
    })
    local modules = helpers.installAddonShim()
    _G.UIParent = noopFrame()

    _G.C_Spell = overrides.C_Spell or {
        GetSpellCooldown = function() return nil end,
        GetSpellCooldownDuration = function() return nil end,
    }
    _G.C_SpellBook = overrides.C_SpellBook or {
        IsSpellInSpellBook = function() return false end,
    }
    -- The taunt gate reads the SPELLBOOK, not the role. The loader's default
    -- IsSpellInSpellBook returns false, so a gate-positive test FAILS without
    -- an override rather than passing vacuously.
    _G.GetSpecialization = overrides.GetSpecialization or function() return 1 end
    -- The taunt gate reads the spec ID through C_SpecializationInfo, whose
    -- mock delegates to this global at call time. Without it every
    -- spec-gated entry in TRACKED_SPELLS is skipped, so a test asserting
    -- one is NOT found passes for the wrong reason. 73 is Protection
    -- Warrior: a spec in no `specs` table, so the default drives the plain
    -- taunt entries and nothing else.
    _G.GetSpecializationInfo = overrides.GetSpecializationInfo
        or function() return 73 end
    _G.GetCursorPosition = overrides.GetCursorPosition or function() return 0, 0 end
    _G.UnitCastingInfo = overrides.UnitCastingInfo or function() return nil end
    _G.UnitChannelInfo = overrides.UnitChannelInfo or function() return nil end
    _G.IsMouseButtonDown = overrides.IsMouseButtonDown or function() return false end
    _G.IsInGroup = overrides.IsInGroup or function() return false end
    _G.GetInstanceInfo = overrides.GetInstanceInfo or function() return "none", "none" end

    local profile = {
        Cursor = {
            Enabled = true,
            GCD = {}, Cast = {}, Trail = {},
            Dispel = {},
            Taunt = {
                Enabled = true, AnchorPoint = "CENTER",
                XOffset = 10, YOffset = 10,
                FontFace = "Expressway", FontSize = 18,
                TextColor = { 1, 1, 1, 1 },
            },
        },
    }
    local KE = {
        db = { profile = profile },
        FONT = "Fonts\\Expressway.TTF",
        GetFontPath = function() return "Fonts\\Expressway.TTF" end,
        GetAccentColor = function() return 1, 1, 1, 1 end,
    }
    helpers.loadModule("Modules/Combat/Cursor.lua", KE)
    local C = modules["Cursor"]
    C:UpdateDB()
    -- _tauntOnEvent is a file-local with no stored handle, and the noop frame's
    -- GetScript cannot hand it back. It IS an upvalue of CreateTauntSatellite,
    -- which stores it via SetScript, so findUpvalue recovers the function object
    -- without ever running the constructor. Guarded because Task 2 runs before
    -- Task 4 creates that method.
    local seams = {}
    if C.CreateTauntSatellite then
        seams.tauntOnEvent = findUpvalue(C.CreateTauntSatellite, "_tauntOnEvent")
    end
    return C, KE, seams
end

-- Modules/Combat/CombatCross.lua. The file-scope `local X = X` captures
-- include C_SpecializationInfo.GetSpecialization and C_Spell, so both must
-- exist before load or the index throws. Nothing creates a frame at load time
-- -- CreateFrame only runs from lifecycle methods, which this loader
-- deliberately does not call, so a spec that needs a frame calls
-- CC:CreateFrame() itself.
--
-- UnitAffectingCombat is UNMANAGED (dev/spec/_wow_mock.lua), so it is assigned
-- to _G directly; handing it to installMock would silently drop it.
-- Returns CC, KE.
function L.loadCombatCross(overrides)
    overrides = overrides or {}
    installMock(managedSubset(overrides), {
        C_Timer = inertTimer(),
        GetTime = function() return 0 end,
        InCombatLockdown = function() return false end,
        CreateFrame = function() return noopFrame() end,
        UnitExists = function() return true end,
    })
    local modules = helpers.installAddonShim()
    _G.UIParent = noopFrame()

    _G.C_Spell = overrides.C_Spell or {
        IsSpellInRange = function() return nil end,
    }
    -- Defaults to OUT of combat. A visibility test that expects the cross up
    -- must say so, either through this override or through Visibility -- it
    -- cannot pass by inheriting a permissive default.
    _G.UnitAffectingCombat = overrides.UnitAffectingCombat or function() return false end
    -- Solo is the only mode that asks, and the module localises this at load,
    -- so a nil here is a throw rather than a wrong answer.
    _G.IsInGroup = overrides.IsInGroup or function() return false end
    _G.GetSpecialization = overrides.GetSpecialization or function() return 1 end
    _G.GetSpecializationInfo = overrides.GetSpecializationInfo or function() return 73 end

    local profile = {
        CombatCross = {
            Enabled = true,
            Strata = "HIGH",
            anchorFrameType = "UIPARENT",
            ParentFrame = "UIParent",
            Position = {},
            ColorMode = "custom",
            Color = { 0, 1, 0.169, 1 },
            Shape = "cross",
            Visibility = "in_combat",
            Thickness = 22,
            Outline = true,
            RangeColorMeleeEnabled = false,
            RangeColorRangedEnabled = false,
            HideWhenInRange = false,
            OutOfRangeColor = { 1, 0, 0, 1 },
        },
    }
    local KE = {
        db = { profile = profile },
        FONT = "Fonts\\Expressway.TTF",
        GetFontPath = function() return "Fonts\\Expressway.TTF" end,
        GetAccentColor = function() return 1, 1, 1, 1 end,
        ApplyFramePosition = function() end,
    }
    helpers.loadModule("Modules/Combat/CombatCross.lua", KE)
    local CC = modules["CombatCross"]
    CC:UpdateDB()
    return CC, KE
end

-- Modules/QoL/SlashCommands.lua. The file guards on a truthy KitnEssentials at
-- load, which installAddonShim supplies, and it indexes C_CVar at file scope
-- (SlashCommands.lua), so C_CVar must exist before load. Nothing registers
-- a slash command until KE:ApplySlashCommands runs, which this loader
-- deliberately does not call.
--
-- Managed overrides (InCombatLockdown and anything else in MANAGED_MOCK_KEYS)
-- are forwarded to installMock. C_CVar, C_AddOns, ReloadUI, SlashCmdList and
-- NUM_CHAT_WINDOWS are UNMANAGED (dev/spec/_wow_mock.lua), so they are
-- assigned to _G directly; handing them to installMock would silently drop
-- them. Returns KE.
function L.loadSlashCommands(overrides)
    overrides = overrides or {}
    -- Managed subset routed through installMock so a caller's
    -- InCombatLockdown override still reaches _wow_mock. Same regression class
    -- as loadCursor's.
    installMock(managedSubset(overrides), {
        InCombatLockdown = function() return false end,
    })
    helpers.installAddonShim()

    _G.C_CVar = overrides.C_CVar
        or { GetCVar = function() return "1" end, SetCVar = function() end }
    _G.C_AddOns = overrides.C_AddOns
        or { DoesAddOnExist = function() return false end }
    _G.ReloadUI = overrides.ReloadUI or function() end
    _G.SlashCmdList = overrides.SlashCmdList or {}
    -- The module clears its own aliases out of the chat engine's resolved
    -- command caches, so both tables have to exist for that path to be visible
    -- to a spec rather than silently skipped by its nil guard.
    _G.hash_SlashCmdList = overrides.hash_SlashCmdList or {}
    _G.hash_ChatTypeInfoList = overrides.hash_ChatTypeInfoList or {}
    _G.NUM_CHAT_WINDOWS = overrides.NUM_CHAT_WINDOWS or 10

    local KE = { db = { profile = { SlashCommands = {} } }, Print = function() end }
    helpers.loadModule("Modules/QoL/SlashCommands.lua", KE)
    return KE
end

-- Modules/Dungeons/LFGReminder.lua. The file-scope `local X = X` captures
-- include C_Spell, C_SpellBook, C_LFGList, GameTooltip and UIParent, and the
-- file also reads Enum.SpellBookSpellBank.Player at file scope, so all of
-- them must exist before load or the capture takes nil. `issecretvalue` and
-- `issecrettable` are captured with an `or function() return false end`
-- fallback in the module itself, so neither needs a stub here -- but
-- _wow_mock manages both, so a caller override still routes through
-- installMock.
--
-- Nothing creates a frame at load time: BuildPopup only runs from OnEnable
-- and from the show path, neither of which this loader calls.
-- Returns LR, KE, seams.
-- BuildPopup chains off its CreateTexture returns (hdrBg:SetColorTexture,
-- icon:SetTexCoord, hover:SetAllPoints), and the shared noopFrame() returns
-- nil from every method except CreateFontString (see :45-48 above), so a
-- popup built on it errors on the first texture call. Supply a richer stub
-- locally rather than widening the shared helper that other module loaders
-- depend on.
-- Show/Hide/IsShown track real state, because the teardown paths branch on
-- popup:IsShown() and a frame that is never "shown" would make those tests
-- vacuous.
local function lfgFrame()
    local shown, attrs = false, {}
    local f = {
        CreateFontString = function() return noopObject() end,
        CreateTexture    = function() return noopObject() end,
        Show             = function() shown = true end,
        Hide             = function() shown = false end,
        IsShown          = function() return shown end,
        GetPoint         = function() return nil end,
        -- Recorded so teardown specs can assert the secure button was
        -- actually disarmed, not merely hidden.
        SetAttribute     = function(_, k, v) attrs[k] = v end,
        GetAttribute     = function(_, k) return attrs[k] end,
    }
    return setmetatable(f, { __index = function() return function() end end })
end

function L.loadLFGReminder(overrides)
    overrides = overrides or {}
    local createdFrames = {}
    -- Managed overrides go THROUGH installMock so the caller still wins on
    -- them; everything below is unmanaged and goes straight to _G.
    installMock(managedSubset(overrides), {
        C_Timer = inertTimer(),
        GetTime = function() return 0 end,
        -- inCombatFn lets a test flip combat state mid-test; inCombat is the
        -- fixed-value shorthand.
        InCombatLockdown = overrides.inCombatFn
            or (overrides.inCombat and function() return true end)
            or function() return false end,
        -- onCreateFrame is a loader-only spy. It never replaces the return
        -- value: a stub that returns nil would make BuildPopup error before
        -- a test could assert anything about it. Named frames are recorded
        -- so specs can reach the popup and the secure button directly
        -- (CreateFrame's second argument is the global name).
        CreateFrame = function(_, name, ...)
            if overrides.onCreateFrame then overrides.onCreateFrame(name, ...) end
            local f = lfgFrame()
            if name then createdFrames[name] = f end
            return f
        end,
    })
    local modules = helpers.installAddonShim()
    _G.UIParent = noopFrame()
    _G.GameTooltip = overrides.GameTooltip or noopFrame()

    _G.C_Spell = overrides.C_Spell or {
        GetSpellInfo = function() return nil end,
        GetSpellCooldown = function() return nil end,
        GetSpellCooldownDuration = function() return nil end,
    }
    _G.C_LFGList = overrides.C_LFGList or {
        GetSearchResultInfo = function() return nil end,
        GetActivityInfoTable = function() return nil end,
    }
    -- LFGReminder.lua reads Enum.SpellBookSpellBank.Player at file scope, so the
    -- stub must exist BEFORE helpers.loadModule runs.
    _G.Enum = overrides.Enum or { SpellBookSpellBank = { Player = "Player" } }
    _G.C_SpellBook = overrides.C_SpellBook or {
        IsSpellKnown = function() return true end,
    }
    _G.IsInGroup = overrides.IsInGroup or function() return true end
    _G.IsInInstance = overrides.IsInInstance or function() return false, "none" end
    _G.IsInRaid = overrides.IsInRaid or function() return false end
    _G.GetNumGroupMembers = overrides.GetNumGroupMembers or function() return 0 end

    local profile = {
        LFGReminder = {
            Enabled     = true,
            Scale       = 1.05,
            ShowDisable = true,
        },
    }
    -- RunAfterCombat mirrors Core/Globals.lua -- immediate when out of
    -- combat, queued otherwise. Tests drain the queue with
    -- seams.runCombatQueue() to simulate combat ending.
    local combatQueue = {}
    local KE = {
        db = { profile = profile },
        Print = function() end,
        Skins = overrides.Skins or nil,
        RunAfterCombat = function(_, fn)
            if not _G.InCombatLockdown() then fn(); return end
            combatQueue[#combatQueue + 1] = fn
        end,
        -- Mirrors Core/Secret.lua's real IsSecretValue (`issecretvalue and
        -- issecretvalue(value)`) without loading the whole file: Secret.lua
        -- creates two frames at file scope, which would pollute this
        -- loader's onCreateFrame spy (used to count BuildPopup's frames).
        IsSecretValue = function(_, v) return _G.issecretvalue and _G.issecretvalue(v) end,
    }
    helpers.loadModule("Modules/Dungeons/LFGReminder.lua", KE)
    local LR = modules["LFGReminder"]
    -- ShowPopup/HidePopup (the leader/cooldown-gate work) register and
    -- unregister SPELL_UPDATE_COOLDOWN on every show/hide, and installAddonShim
    -- hands back a bare module table with no AceEvent mixin -- almost every
    -- test in this file reaches one of those two paths, so the default lives
    -- here rather than being stubbed per test. Recorded so a spec CAN assert
    -- registration symmetry via seams.registeredEvents, though none currently
    -- does.
    local registeredEvents = {}
    LR.RegisterEvent = function(_, event) registeredEvents[event] = true end
    LR.UnregisterEvent = function(_, event) registeredEvents[event] = nil end
    LR:UpdateDB()

    -- ResolveTeleportSpellByName has no stored handle and no caller that
    -- references it, so debug.getupvalue cannot reach it -- the module
    -- exports it directly as LR._ResolveTeleportSpellByName (Task 3).
    -- The deferral helpers ARE upvalues of the module methods that call
    -- them, so findUpvalue recovers those without running anything.
    -- Both are guarded: Task 5 is what creates these methods.
    -- The module lifecycle methods (SetEnabledState, IsEnabled) are NOT
    -- stubbed by helpers.installAddonShim -- its modules are bare tables. A
    -- test that drives a path calling one of them stubs it itself, e.g.
    -- LR.IsEnabled = function() return true end.
    local seams = {}
    seams.resolveByName = LR._ResolveTeleportSpellByName
    seams.registeredEvents = registeredEvents
    -- Drain the deferred-teardown queue, i.e. "combat ended".
    seams.runCombatQueue = function()
        local fns = combatQueue
        combatQueue = {}
        for i = 1, #fns do fns[i]() end
    end
    -- Named frames, so a spec can assert on the popup and the secure button
    -- themselves: seams.frames["KE_LFGReminderPopup"],
    -- seams.frames["KE_LFGReminderTeleport"].
    seams.frames = createdFrames
    if LR.LFG_LIST_JOINED_GROUP then
        seams.resolveDungeon = findUpvalue(LR.LFG_LIST_JOINED_GROUP, "ResolveDungeon")
        seams.showPrompt     = findUpvalue(LR.LFG_LIST_JOINED_GROUP, "ShowPrompt")
    end
    return LR, KE, seams
end

-- LFGQuickCreate builds real Buttons with textures and font strings, which
-- the shared noopFrame cannot supply (its CreateTexture returns nil).
-- Records scripts and shown state so specs can drive them.
local function qcFrame(name)
    local f
    f = {
        _name    = name,
        _shown   = false,
        _scripts = {},
        _attrs   = {},
        _points  = {},
        SetSize = function() end, SetPoint = function(_, ...) f._points[#f._points + 1] = { ... } end,
        ClearAllPoints = function() f._points = {} end, SetAllPoints = function() end,
        SetHeight = function() end, GetHeight = function() return 100 end,
        GetPoint = function() return "TOPLEFT", nil, "TOPLEFT", 0, -55 end,
        GetParent = function() return f._parent end,
        GetFrameLevel = function() return 1 end, SetFrameLevel = function() end,
        Show = function() f._shown = true end,
        Hide = function() f._shown = false end,
        SetShown = function(_, s) f._shown = s and true or false end,
        IsShown = function() return f._shown end,
        IsEnabled = function() return true end,
        SetScript = function(_, k, fn) f._scripts[k] = fn end,
        HookScript = function(_, k, fn) f._scripts[k] = fn end,
        GetScript = function(_, k) return f._scripts[k] end,
        SetAttribute = function(_, k, v) f._attrs[k] = v end,
        GetAttribute = function(_, k) return f._attrs[k] end,
        RegisterForClicks = function() end,
        SetTexture = function() end, SetColorTexture = function() end,
        SetTexCoord = function() end, SetFont = function() end,
        SetText = function(_, t) f._text = t end, GetText = function() return f._text end,
        SetDesaturated = function() end, SetAlpha = function() end,
    }
    f.CreateTexture = function() return qcFrame(name .. "_tex") end
    f.CreateFontString = function() return qcFrame(name .. "_fs") end
    return f
end

-- Modules/Dungeons/LFGQuickCreate.lua. The file-scope `local X = X` captures
-- include C_Timer, C_LFGList, C_ChallengeMode, C_MythicPlus, GameTooltip,
-- IsInGroup, LibStub, hooksecurefunc and InCombatLockdown, so every one must
-- exist BEFORE helpers.loadModule or the capture takes nil. The module reads
-- Enum.LFGEntryPlaystyle at click time only, not at file scope.
--
-- Nothing creates a frame at load time: Init() runs only from OnEnable and the
-- ADDON_LOADED / PLAYER_ENTERING_WORLD paths, none of which this loader calls.
function L.loadLFGQuickCreate(overrides)
    overrides = overrides or {}
    -- Managed overrides go THROUGH installMock so a caller still wins on them;
    -- everything below is unmanaged and goes straight to _G. CreateFrame and
    -- UnitName are MANAGED (MANAGED_MOCK_KEYS above) -- assigning either to _G
    -- directly would be silently discarded.
    installMock(managedSubset(overrides), {
        C_Timer = inertTimer(),
        GetTime = function() return 0 end,
        InCombatLockdown = overrides.inCombatFn
            or (overrides.inCombat and function() return true end)
            or function() return false end,
        CreateFrame = function(_, name) return qcFrame(name or "anon") end,
        UnitName = function() return "Tester" end,
    })
    local modules = helpers.installAddonShim()

    _G.UIParent = qcFrame("UIParent")
    _G.GameTooltip = overrides.GameTooltip or qcFrame("GameTooltip")

    _G.LFGListFrame = overrides.LFGListFrame or nil
    _G.C_LFGList = overrides.C_LFGList or {
        GetActivityInfoTable = function() return nil end,
        GetOwnedKeystoneActivityAndGroupAndLevel = function() return nil end,
        CreateListing = function() return true end,
    }
    _G.C_ChallengeMode = overrides.C_ChallengeMode or {
        GetMapTable = function() return {} end,
        GetMapUIInfo = function() return nil end,
    }
    _G.C_MythicPlus = overrides.C_MythicPlus or {
        RequestMapInfo = function() end,
        GetCurrentSeason = function() return 1 end,
    }
    _G.C_AddOns = overrides.C_AddOns or {
        IsAddOnLoaded = function() return false, false end,
    }
    _G.IsInGroup = overrides.IsInGroup or function() return false end
    _G.LibStub = overrides.LibStub or nil
    _G.hooksecurefunc = overrides.hooksecurefunc or function() end
    -- UnitNameUnmodified is NOT managed, unlike UnitName -- check the list
    -- rather than pairing them by name.
    _G.UnitNameUnmodified = overrides.UnitNameUnmodified or function() return "Tester" end
    _G.Enum = overrides.Enum or { LFGEntryPlaystyle = { None = 0 } }

    local profile = {
        LFGQuickCreate = {
            Enabled          = true,
            QuickCreate      = true,
            DefaultPlaystyle = 1,
            DoubleClickStart = true,
        },
    }
    local KE = {
        db = { profile = profile },
        FONT = "Fonts\\FRIZQT__.TTF",
        Print = function() end,
    }
    if overrides.profile then KE.db.profile = overrides.profile end

    -- loadModule returns the KE table, so the MODULE comes from the shim's
    -- registry, never from this call's return value.
    helpers.loadModule("Modules/Dungeons/LFGQuickCreate.lua", KE)
    local QC = modules["LFGQuickCreate"]

    -- Seed db DIRECTLY rather than calling QC:UpdateDB(). The sibling loader
    -- can call its module's UpdateDB because that module is complete; this
    -- plan builds incrementally and UpdateDB does not exist until Task 6,
    -- while Task 3 is the first task to use this loader. Task 6's sanitizer
    -- specs call the real QC:UpdateDB() themselves, after it exists.
    QC.db = KE.db.profile.LFGQuickCreate

    local seams = {
        activeDungeons   = QC._ActiveDungeons,
        currentPlaystyle = QC._CurrentPlaystyle,
    }
    return QC, KE, seams
end

-- Modules/Dungeons/GroupFinderPanel.lua. The file-scope `local X = X` captures
-- are _G, ipairs, CreateFrame and string.format, so all four must exist BEFORE
-- helpers.loadModule. C_LFGList, C_MythicPlus, C_ChallengeMode, C_SocialQueue,
-- C_AddOns, C_Timer, Enum and bit are read at CALL time, not file scope, but
-- the helpers under test call several of them, so they are stubbed here.
--
-- Nothing creates a frame at load time: CreatePanel runs only from Refresh,
-- which this loader never calls.
function L.loadGroupFinderPanel(overrides)
    overrides = overrides or {}
    -- ONLY keys in MANAGED_MOCK_KEYS go in this dict. `_wow_mock.install`
    -- reads a fixed key list and SILENTLY DROPS anything else, so an
    -- unmanaged key placed here never reaches _G and the spec fails with
    -- "attempt to call a nil value" far from the cause.
    installMock(managedSubset(overrides), {
        C_Timer = inertTimer(),
        GetTime = function() return 0 end,
        InCombatLockdown = function() return false end,
        CreateFrame = function(_, name) return qcFrame(name or "anon") end,
    })

    _G.IsInGroup = overrides.IsInGroup or function() return false end
    _G.GetNumGroupMembers = overrides.GetNumGroupMembers or function() return 0 end
    _G.UnitGroupRolesAssigned = overrides.UnitGroupRolesAssigned
        or function() return "NONE" end
    _G.hooksecurefunc = overrides.hooksecurefunc or function() end
    local modules = helpers.installAddonShim()

    _G.bit = _G.bit or {
        bor  = function(a, b) return (a or 0) + (b or 0) end,
        band = function(a) return a or 0 end,
        bnot = function(a) return -(a or 0) - 1 end,
    }
    _G.Enum = overrides.Enum or {
        LFGListFilter = {
            PvE = 1, Recommended = 2, NotRecommended = 4,
            CurrentSeason = 8, CurrentExpansion = 16, NotCurrentSeason = 32,
        },
    }
    _G.C_SpecializationInfo = overrides.C_SpecializationInfo or {
        GetSpecialization = function() return 1 end,
        GetSpecializationInfo = function() return 1, "Spec", "", nil, "DAMAGER" end,
    }
    _G.C_LFGList = overrides.C_LFGList or {
        GetAvailableActivityGroups = function() return {} end,
        GetActivityGroupInfo = function() return nil end,
    }
    _G.C_AddOns = overrides.C_AddOns or { IsAddOnLoaded = function() return false end }
    _G.C_SocialQueue = overrides.C_SocialQueue
    -- issecretvalue / issecrettable are deliberately NOT set here. They ARE
    -- in MANAGED_MOCK_KEYS, so `managedSubset` already forwards a caller's
    -- override through installMock, and _wow_mock defaults both to "nothing
    -- is secret". Task 3's specs override them the ordinary way.
    _G.GROUP_FINDER_CATEGORY_ID_DUNGEONS = 2

    local profile = {
        GroupFinderPanel = {
            Enabled        = true,
            DungeonFilter  = {},
            PartyFit       = false,
            HasTank        = false,
            HasHealer      = false,
            MinScore       = 0,
        },
    }
    local KE = {
        db = { profile = profile, global = {} },
        FONT = "Fonts\\FRIZQT__.TTF",
        Print = function() end,
        Theme = { accent = { 1, 0, 0.549, 1 } },
    }
    if overrides.profile then KE.db.profile = overrides.profile end

    helpers.loadModule("Modules/Dungeons/GroupFinderPanel.lua", KE)
    local GFP = modules["GroupFinderPanel"]

    -- Seeded DIRECTLY, not via GFP:UpdateDB(). UpdateDB does not exist until
    -- Task 7, and Task 2 is the first task to use this loader. Task 7's own
    -- specs call the real GFP:UpdateDB() after it exists.
    GFP.db = KE.db.profile.GroupFinderPanel

    local seams = {
        playerSpecRole      = GFP._PlayerSpecRole,
        getPartyRoles       = GFP._GetPartyRoles,
        seasonGroups        = GFP._SeasonGroups,
        isDungeonSearchMode = GFP._IsDungeonSearchMode,
        abbreviate          = GFP._Abbreviate,
        armMinScoreSave     = GFP._ArmMinScoreSave,
    }
    return GFP, KE, seams
end

-- Modules/QoL/CopyAnything.lua. TryCopy is never invoked by this loader --
-- CheckModifiers and GetNPCIDFromGUID are file locals with no stored handle,
-- but TryCopy calls both directly, so they sit in its upvalue slots;
-- findUpvalue recovers them without running any tooltip logic (so GameTooltip,
-- C_ChallengeMode, C_Spell, C_Item and C_AddOns need no stubs here).
--
-- IsControlKeyDown/IsShiftKeyDown/IsAltKeyDown are NOT in MANAGED_MOCK_KEYS,
-- so a caller override placed in `overrides` and routed through installMock
-- would be silently dropped. The module captures each as a file-scope upvalue
-- at load time (`local IsControlKeyDown = IsControlKeyDown`), so this loader
-- assigns them to _G directly BEFORE helpers.loadModule, and the caller's
-- override (or the "not held" default) is what CheckModifiers actually closes
-- over. A spec must assert `_G.IsControlKeyDown == theFunctionItPassed` after
-- calling this loader -- a regression that reroutes these three through
-- installMock would drop them back to the default and read exactly like a
-- passing test otherwise.
-- Returns CA, KE, seams (seams.checkModifiers, seams.getNPCIDFromGUID).
--
-- strsplit is a WoW-provided global, not standard Lua, and GetNPCIDFromGUID
-- calls it directly -- also captured as a file-scope upvalue, so it must
-- exist on _G before helpers.loadModule. The stand-in treats each character
-- of the delimiter as its own separator (WoW's own documented behaviour),
-- which is all GetNPCIDFromGUID's single-character "-" delimiter needs.
local function wowStrsplit(delimiter, str)
    if not str then return end
    local escaped = delimiter:gsub("(%W)", "%%%1")
    local pieces = {}
    for piece in str:gmatch("[^" .. escaped .. "]+") do
        pieces[#pieces + 1] = piece
    end
    return unpack(pieces)
end

function L.loadCopyAnything(overrides)
    overrides = overrides or {}
    local modules = helpers.installAddonShim()
    _G.IsControlKeyDown = overrides.IsControlKeyDown or function() return false end
    _G.IsShiftKeyDown = overrides.IsShiftKeyDown or function() return false end
    _G.IsAltKeyDown = overrides.IsAltKeyDown or function() return false end
    _G.strsplit = overrides.strsplit or wowStrsplit
    local KE = {
        db = { profile = { CopyAnything = {} } },
        CreatePrompt = function() end,
    }
    helpers.loadModule("Modules/QoL/CopyAnything.lua", KE)
    local CA = modules["CopyAnything"]
    local seams = {
        checkModifiers = findUpvalue(CA.TryCopy, "CheckModifiers"),
        getNPCIDFromGUID = findUpvalue(CA.TryCopy, "GetNPCIDFromGUID"),
    }
    return CA, KE, seams
end

-- Modules/QoL/AlertFrames.lua. AF:PostAlertMove/InstallHooks/OnEnable are
-- never invoked -- nothing at file scope beyond function definitions and
-- constant assignments runs on load, so no CreateFrame/hooksecurefunc/Blizzard
-- frame stubs are needed here. ShouldGrowUp is a file local with no stored
-- handle, but AF:PostAlertMove calls it directly, so it sits in that method's
-- upvalue slots; findUpvalue recovers it without ever creating a frame or
-- calling OnEnable. Returns AF, KE, seams -- seams.shouldGrowUp,
-- seams.isDirectAlertFrame, seams.isHeldByLootContainer, seams.adjustSubSystem.
-- For the AddAlertFrame post-hook itself, use L.loadAlertFramesWithHooks below.
function L.loadAlertFrames()
    local modules = helpers.installAddonShim()
    local KE = {
        db = { profile = { AlertFrames = {} } },
        ApplyFramePosition = function() end,
        CreateReloadPrompt = function() end,
        Print = function() end,
    }
    helpers.loadModule("Modules/QoL/AlertFrames.lua", KE)
    local AF = modules["AlertFrames"]
    local seams = {
        shouldGrowUp = findUpvalue(AF.PostAlertMove, "ShouldGrowUp"),
        -- Referenced only by the AddAlertFrame closure InstallHooks builds, which
        -- makes it an upvalue of InstallHooks itself.
        isDirectAlertFrame = findUpvalue(AF.InstallHooks, "IsDirectAlertFrame"),
        isHeldByLootContainer = findUpvalue(AF.PositionBonusRollToasts, "IsHeldByLootContainer"),
        -- The refusal itself rather than its predicate: AdjustSubSystem is what
        -- decides whether a subsystem's AdjustAnchors gets replaced, so a spec
        -- that calls it observes the decision instead of restating the test.
        adjustSubSystem = findUpvalue(AF.InstallHooks, "AdjustSubSystem"),
    }
    return AF, KE, seams
end

-- Modules/QoL/AlertFrames.lua with InstallHooks actually RUN, which the loader
-- above deliberately avoids. Needed because the guards inside the AddAlertFrame
-- post-hook are only observable by driving that callback: a spec that calls the
-- predicates instead still passes when the guard is deleted from the hook.
--
-- The stub is deliberately thin. InstallHooks registers several callbacks and
-- reaches for optional globals; this route ignores every registration except
-- AddAlertFrame, which it captures, and leaves the optional globals nil so the
-- branches that want them simply do not run. AF:IsEnabled and AF.holder are set
-- because the hook's first guard reads both, and PostAlertMove is replaced by a
-- counter so the assertions can see the placement decision without the layout
-- work behind it.
--
-- Returns AF, hook, calls, KE:
--   hook  the captured AddAlertFrame post-hook, called as hook(af, frame)
--   calls {postAlertMove = n} -- the placement side effect the guards suppress;
--         a placed frame also records its own clearAllPoints/setPoint counts
function L.loadAlertFramesWithHooks()
    local modules = helpers.installAddonShim()
    local KE = {
        db = { profile = { AlertFrames = {} } },
        ApplyFramePosition = function() end,
        CreateReloadPrompt = function() end,
        Print = function() end,
    }

    -- BEFORE loadModule, not after: the file captures `local hooksecurefunc =
    -- hooksecurefunc` at its own scope, so a stub installed later is never the
    -- one InstallHooks calls.
    local alertFrame = { alertFrameSubSystems = {} }
    local captured
    _G.AlertFrame = alertFrame
    _G.GroupLootContainer = nil
    _G.GroupLootContainer_Update = nil
    _G.hooksecurefunc = function(target, name, fn)
        if target == alertFrame and name == "AddAlertFrame" then captured = fn end
    end

    helpers.loadModule("Modules/QoL/AlertFrames.lua", KE)
    local AF = modules["AlertFrames"]

    local calls = { postAlertMove = 0 }
    AF.IsEnabled = function() return true end
    AF.holder = { GetCenter = function() return 0, 0 end }
    AF.PostAlertMove = function() calls.postAlertMove = calls.postAlertMove + 1 end

    AF:InstallHooks()
    return AF, captured, calls, KE
end

-- Modules/QoL/AlertFrames.lua with the managed-frame layout parent present.
-- The layout pass restores GroupLootContainer's stock screen-bottom anchor;
-- rec.fireManagedLayout runs that pass and then the post-hook InstallHooks
-- registered, matching hooksecurefunc's order. Returns AF, rec, KE.
function L.loadAlertFramesWithManagedLayout()
    local modules = helpers.installAddonShim()
    local KE = {
        db = { profile = { AlertFrames = {} } },
        ApplyFramePosition = function() end,
        CreateReloadPrompt = function() end,
        Print = function() end,
    }

    local uiParent = trackablePointFrame()
    local holder = trackablePointFrame()
    local container = trackablePointFrame()
    local alertFrame = { alertFrameSubSystems = {} }
    local layoutParent = {}
    local layoutHook

    function layoutParent:Layout()
        container:ClearAllPoints()
        container:SetPoint("BOTTOM", uiParent, "BOTTOM", 0, 0)
    end
    container.layoutParent = layoutParent

    _G.UIParent = uiParent
    _G.AlertFrame = alertFrame
    _G.GroupLootContainer = container
    _G.GroupLootContainer_Update = function() end
    _G.hooksecurefunc = function(target, name, fn)
        if target == layoutParent and name == "Layout" then layoutHook = fn end
    end

    helpers.loadModule("Modules/QoL/AlertFrames.lua", KE)
    local AF = modules["AlertFrames"]
    AF.IsEnabled = function() return true end
    AF.holder = holder
    AF:InstallHooks()

    local rec = {
        container = container,
        holder = holder,
        uiParent = uiParent,
    }
    rec.fireManagedLayout = function()
        layoutParent:Layout()
        if layoutHook then layoutHook(layoutParent) end
    end
    return AF, rec, KE
end

-- Modules/QoL/ColorPicker.lua captures WoW string globals as file-scope
-- upvalues at load time (`local format, strlen, strjoin = format, strlen,
-- strjoin`, plus gsub/strsub/floor separately), so real Lua equivalents must
-- exist on _G BEFORE helpers.loadModule runs, exactly like wowStrsplit above.
-- strjoin's contract is strjoin(delimiter, ...) -- the OPPOSITE argument
-- order from table.concat -- so it needs its own shim, not a table.concat
-- alias.
local function wowStrjoin(delimiter, ...)
    return table.concat({ ... }, delimiter)
end

-- Enhance/OnEnable are never invoked (the five pure conversion helpers this
-- spec targets are reached purely through debug.getupvalue chains), so no
-- Blizzard frame or CreateFrame stub is needed here.
-- Returns CP, KE, seams:
--   seams.getHexColor      seams.round255      seams.alphaValue
--   seams.expandFromThree  seams.extendToSix
function L.loadColorPicker(overrides)
    overrides = overrides or {}
    local modules = helpers.installAddonShim()
    _G.strlen = overrides.strlen or string.len
    _G.strsub = overrides.strsub or string.sub
    _G.gsub = overrides.gsub or string.gsub
    _G.format = overrides.format or string.format
    _G.floor = overrides.floor or math.floor
    _G.strjoin = overrides.strjoin or wowStrjoin
    local KE = { db = { profile = { ColorPicker = {} } } }
    helpers.loadModule("Modules/QoL/ColorPicker.lua", KE)
    local CP = modules["ColorPicker"]

    local updateColorTexts = findUpvalue(CP.Enhance, "UpdateColorTexts")
    local onColorSelect = findUpvalue(CP.Enhance, "OnColorSelect")
    local getHexColor = findUpvalue(updateColorTexts, "GetHexColor")
    local updateAlphaText = findUpvalue(onColorSelect, "UpdateAlphaText")
    local seams = {
        getHexColor = getHexColor,
        round255 = findUpvalue(updateColorTexts, "Round255"),
        alphaValue = findUpvalue(updateAlphaText, "AlphaValue"),
        expandFromThree = findUpvalue(getHexColor, "ExpandFromThree"),
        extendToSix = findUpvalue(getHexColor, "ExtendToSix"),
    }
    return CP, KE, seams
end

-- Modules/QoL/MoveFrames.lua. GetFrame is called directly by MF.HandleFrame
--; both frame tables are referenced directly by MF.OnEnable
--; disabled is the file-local table MF:SetMovable
-- writes to -- all four seams are one debug.getupvalue hop.
-- strsplit is delimiter-first and not supplied by _wow_mock.lua; the module
-- captures it as a file-scope local, so a real equivalent must be on _G
-- before helpers.loadModule -- reusing wowStrsplit above (already
-- delimiter-first) rather than adding a second local of the same name.
-- Returns MF, KE, seams (seams.getFrame, seams.blizzardFrames,
-- seams.blizzardFramesOnDemand, seams.disabled).
function L.loadMoveFrames(overrides)
    overrides = overrides or {}
    local modules = helpers.installAddonShim()
    _G.strsplit = overrides.strsplit or wowStrsplit
    _G.wipe = overrides.wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
    _G.tDeleteItem = overrides.tDeleteItem or function() end
    _G.RunNextFrame = overrides.RunNextFrame or function() end
    _G.GenerateFlatClosure = overrides.GenerateFlatClosure or function(f) return f end
    _G.InCombatLockdown = overrides.InCombatLockdown or function() return false end
    _G.C_AddOns = { IsAddOnLoaded = function() return false end }
    local KE = { db = { profile = { MoveFrames = {} } } }
    helpers.loadModule("Modules/QoL/MoveFrames.lua", KE)
    local MF = modules["MoveFrames"]

    local seams = {
        getFrame = findUpvalue(MF.HandleFrame, "GetFrame"),
        blizzardFrames = findUpvalue(MF.OnEnable, "BlizzardFrames"),
        blizzardFramesOnDemand = findUpvalue(MF.OnEnable, "BlizzardFramesOnDemand"),
        disabled = findUpvalue(MF.SetMovable, "disabled"),
    }
    return MF, KE, seams
end

-- Modules/QoL/RaidControl.lua captures WoW globals as file-scope upvalues AND
-- calls SetGrabCoords three times at file scope, so
-- GetTexCoordsByGrid, SOUNDKIT and RAID_CLASS_COLORS must exist on _G BEFORE
-- helpers.loadModule runs or the file errors while loading.
-- Seams, and the hop chain that reaches each:
--   targetIconsGetCoords  <- RC.CreateTargetIcons                 (1 hop)
--   screenPosition        <- RC.PositionSections                  (1 hop)
--   inGroup               <- RC.ToggleRaidControl                 (1 hop)
--   notInPVP              <- inGroup                              (2 hops)
--   onEnterRole            <- RC.CreateRoleIcons                  (1 hop)
--   roleIconsSortNames    <- onEnterRole                          (2 hops)
--   roleIconsAddNames     <- onEnterRole                          (2 hops)
--   maxRaidGroup          <- RC.UpdateBuffStrip                   (1 hop)
--   setGrabCoords         <- RC.UpdateDB is NOT a holder; SetGrabCoords is
--                            called only at file scope, so it is reached
--                            through no exported function and is NOT a seam.
function L.loadRaidControl(overrides)
    overrides = overrides or {}
    -- installMock installs _G.CreateFrame (dev/spec/_wow_mock.lua). The
    -- module calls CreateFrame at FILE SCOPE for the frame hider's parked
    -- parent, so this cannot be skipped the way loadMoveFrames skips it.
    installMock(overrides, {})
    local modules = helpers.installAddonShim()
    _G.mod = overrides.mod or math.fmod
    _G.floor = overrides.floor or math.floor
    _G.strsub = overrides.strsub or string.sub
    _G.format = overrides.format or string.format
    _G.gsub = overrides.gsub or string.gsub
    _G.strfind = overrides.strfind or string.find
    _G.tinsert = overrides.tinsert or table.insert
    _G.sort = overrides.sort or table.sort
    _G.wipe = overrides.wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
    _G.GetTexCoordsByGrid = overrides.GetTexCoordsByGrid or function() return 0, 1, 0, 1 end
    _G.RAID_CLASS_COLORS = overrides.RAID_CLASS_COLORS
        or { PRIEST = { r = 1, g = 1, b = 1 }, MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
    _G.SOUNDKIT = overrides.SOUNDKIT or { IG_MAINMENU_OPTION_CHECKBOX_ON = 1 }
    _G.C_PartyInfo = overrides.C_PartyInfo
        or { SetEveryoneIsAssistant = function() end, DoReadyCheck = function() end, DoCountdown = function() end }
    _G.C_AddOns = overrides.C_AddOns or { IsAddOnLoaded = function() return false end }
    _G.InCombatLockdown = overrides.InCombatLockdown or function() return false end
    _G.IsInInstance = overrides.IsInInstance or function() return false, "none" end
    _G.IsInGroup = overrides.IsInGroup or function() return false end
    -- Captured as file-scope locals like everything above, so a spec that only
    -- sets these afterwards leaves the module holding nil. GetInstanceInfo
    -- returns name, instanceType, difficultyID -- MaxRaidGroup reads 2 and 3.
    _G.UnitInRaid = overrides.UnitInRaid or function() return nil end
    _G.GetInstanceInfo = overrides.GetInstanceInfo
        or function() return "Somewhere", "none", 0 end
    _G.GetRaidDifficultyID = overrides.GetRaidDifficultyID or function() return 14 end
    _G.C_UnitAuras = overrides.C_UnitAuras or { GetAuraDataByIndex = function() return nil end }
    _G.GetNumGroupMembers = overrides.GetNumGroupMembers or function() return 0 end
    _G.GetRaidRosterInfo = overrides.GetRaidRosterInfo or function() return nil end
    -- UIParent is captured as a file-scope local, so it must exist
    -- on _G BEFORE loadModule. Setting it afterwards has no effect on the
    -- module's captured upvalue -- ScreenPosition would read a stale table.
    _G.UIParent = overrides.UIParent
        or { GetSize = function() return 1600, 900 end, GetWidth = function() return 1600 end }
    local KE = { db = { profile = { RaidControl = { Position = {} } } }, Skins = {} }
    KE.Skins.SafeCenter = overrides.SafeCenter or function() return 0, 0 end
    helpers.loadModule("Core/Secret.lua", KE)
    helpers.loadModule("Modules/QoL/RaidControl.lua", KE)
    local RC = modules["RaidControl"]

    local inGroup = findUpvalue(RC.ToggleRaidControl, "InGroup")
    local onEnterRole = findUpvalue(RC.CreateRoleIcons, "OnEnter_Role")
    local seams = {
        targetIconsGetCoords = findUpvalue(RC.CreateTargetIcons, "TargetIcons_GetCoords"),
        screenPosition = findUpvalue(RC.PositionSections, "ScreenPosition"),
        inGroup = inGroup,
        notInPVP = findUpvalue(inGroup, "NotInPVP"),
        onEnterRole = onEnterRole,
        roleIconsSortNames = findUpvalue(onEnterRole, "RoleIcons_SortNames"),
        roleIconsAddNames = findUpvalue(onEnterRole, "RoleIcons_AddNames"),
        maxRaidGroup = findUpvalue(RC.UpdateBuffStrip, "MaxRaidGroup"),
    }
    return RC, KE, seams
end

-- Modules/QoL/GroupSort.lua. The module captures its WoW API functions as
-- file-scope locals at load, so every mock must be on _G BEFORE
-- helpers.loadModule runs -- setting one afterwards leaves the module
-- holding a stale upvalue. installMock(overrides, {}) is required even though
-- no defaults are needed: the continuation driver calls CreateFrame at file
-- scope.
-- Groups (engine state) is reached through GS.GetSortedGroup's upvalues;
-- writing Processing/ProcessStart into it drives the in-progress refusal
-- rule. Returns GS, KE, seams.
function L.loadGroupSort(overrides)
    overrides = overrides or {}
    -- The continuation driver calls CreateFrame at FILE SCOPE, so
    -- installMock cannot be skipped.
    installMock(overrides, {})
    helpers.installAddonShim()
    -- Every one of these is captured as a file-scope local at load, so it has
    -- to exist on _G BEFORE loadModule. Setting any of them afterwards leaves
    -- the module holding a stale upvalue.
    _G.GetTime = overrides.GetTime or function() return 1000 end
    _G.UnitExists = overrides.UnitExists or function() return false end
    _G.UnitName = overrides.UnitName or function(unit) return unit end
    _G.UnitGUID = overrides.UnitGUID or function(unit) return "GUID-" .. tostring(unit) end
    _G.UnitClass = overrides.UnitClass or function() return "Priest", "PRIEST", 5 end
    _G.UnitInRaid = overrides.UnitInRaid or function() return nil end
    _G.UnitIsUnit = overrides.UnitIsUnit or function(a, b) return a == b end
    _G.UnitFullName = overrides.UnitFullName or function() return "Tester", "Realm" end
    _G.UnitIsGroupLeader = overrides.UnitIsGroupLeader or function() return false end
    _G.UnitIsGroupAssistant = overrides.UnitIsGroupAssistant or function() return false end
    _G.UnitAffectingCombat = overrides.UnitAffectingCombat or function() return false end
    _G.UnitGroupRolesAssigned = overrides.UnitGroupRolesAssigned or function() return "DAMAGER" end
    _G.GetRaidRosterInfo = overrides.GetRaidRosterInfo or function() return nil end
    _G.GetInstanceInfo = overrides.GetInstanceInfo or function() return "Zone", "none", 0 end
    _G.GetRaidDifficultyID = overrides.GetRaidDifficultyID or function() return 14 end
    _G.SetRaidSubgroup = overrides.SetRaidSubgroup or function() end
    _G.SwapRaidSubgroup = overrides.SwapRaidSubgroup or function() end
    _G.InCombatLockdown = overrides.InCombatLockdown or function() return false end
    _G.issecretvalue = overrides.issecretvalue or function() return false end
    _G.strsplit = overrides.strsplit or function(sep, str)
        local a, b = string.match(str, "^(.-)" .. sep .. "(.*)$")
        if a then return a, b end
        return str
    end
    _G.C_ChatInfo = overrides.C_ChatInfo or { InChatMessagingLockdown = function() return false end }
    _G.C_Timer = overrides.C_Timer or { After = function() end }
    _G.LibStub = overrides.LibStub or function() return nil end

    local prints = {}
    local KE = { Print = function(_, msg) prints[#prints + 1] = msg end }
    helpers.loadModule("Modules/QoL/GroupSort.lua", KE)
    local GS = KE.GroupSort

    local seams = {
        prints = prints,
        -- Engine state. The in-progress refusal rule is driven through this.
        groups = findUpvalue(GS.GetSortedGroup, "Groups"),
    }
    return GS, KE, seams
end

-- Modules/Dungeons/KeystoneHelper.lua. The KE seed records the three calls
-- ApplyReminderSettings drives (position, both fonts) plus a fake EditMode,
-- so a spec can read what the module resolved without inspecting a frame.
-- LibStub returns nil, so LibCustomGlow is absent and the glow paths no-op.
-- Specs assign KH.db themselves; UpdateDB is never called.
-- Returns KH, rec, KE. rec comes before KE, unlike the other loaders here, so a
-- spec wanting only the first two needs no discard local: luacheck rejects an
-- unused local and `_` would write a global.
function L.loadKeystoneHelper(overrides)
    installMock(overrides, { C_Timer = inertTimer() })
    local modules = helpers.installAddonShim()
    _G.UIParent = noopFrame()
    _G.LibStub = function() return nil end
    _G.IsInGroup = function() return false end
    _G.IsInRaid = function() return false end
    _G.GetInstanceInfo = function()
        return "Mock", "party", 23, "Mythic", 5, 0, false, 2286
    end
    _G.C_ChatInfo = { SendChatMessage = function() end }
    _G.C_ChallengeMode = {
        GetMapUIInfo = function() return "Mock Dungeon", nil, nil, 12345 end,
        GetChallengeCompletionInfo = function() return nil end,
    }
    _G.C_MythicPlus = {
        GetOwnedKeystoneLevel = function() return nil end,
        GetOwnedKeystoneChallengeMapID = function() return nil end,
        GetOwnedKeystoneMapID = function() return nil end,
    }

    local rec = { positions = {}, fonts = {} }

    local KE = {
        Print = function() end,
        ApplyIconZoom = function() end,
        AddIconBorders = function() end,
        ApplyFramePosition = function(_, frame, position, opts)
            rec.positions[#rec.positions + 1] =
                { frame = frame, position = position, opts = opts }
        end,
        ApplyFontToText = function(_, fontString, face, size, outline)
            rec.fonts[#rec.fonts + 1] =
                { fontString = fontString, face = face, size = size, outline = outline }
        end,
        ResolveColor = function(_, color, fallback)
            local c = color or fallback or { 1, 1, 1, 1 }
            return c[1], c[2], c[3], c[4]
        end,
        ResolveAnchorFrame = function(_, frameType, parentFrame)
            return { _frameType = frameType, _parentFrame = parentFrame }
        end,
    }

    rec.editMode = {
        registered = {},
        isActive = false,
        RegisterElement = function(self, config) self.registered[config.key] = config end,
        -- unregisterCalls is the only way to see a drop-then-recreate: the
        -- registered table alone looks identical either way.
        unregisterCalls = {},
        UnregisterElement = function(self, key)
            self.registered[key] = nil
            self.unregisterCalls[#self.unregisterCalls + 1] = key
        end,
    }
    KE.EditMode = rec.editMode

    helpers.loadModule("Modules/Dungeons/KeystoneHelper.lua", KE)
    return modules["KeystoneHelper"], rec, KE
end

-- Modules/QoL/Optimize.lua. The module captures SetCVar/GetCVar as file-scope
-- locals at load, so the fake cvar store has to exist on _G BEFORE loadModule --
-- assigning it afterwards leaves the module holding a stale upvalue. rec.cvars
-- IS that store: seed a key to set the live value, read a key to see what the
-- module wrote. rec.difficultyID is the third GetInstanceInfo return, which is
-- what the Mythic+ override branches on. The AceAddon shim hands back a bare
-- table with no AceEvent, so the two event methods are stubbed onto the module
-- and recorded in rec.events. Nothing calls OnInitialize for you.
-- Returns OPT, rec, KE.
function L.loadOptimize(overrides)
    overrides = overrides or {}
    installMock(overrides, { C_Timer = inertTimer() })
    local modules = helpers.installAddonShim()

    local rec = { cvars = {}, prints = {}, events = {}, difficultyID = 0 }

    _G.SetCVar = function(cvar, value) rec.cvars[cvar] = tostring(value) end
    _G.GetCVar = function(cvar) return rec.cvars[cvar] end
    _G.C_CVar = { SetCVar = _G.SetCVar, GetCVar = _G.GetCVar }
    _G.GetInstanceInfo = function() return "Mock", "party", rec.difficultyID end
    _G.StaticPopupDialogs = {}
    _G.ReloadUI = function() end
    -- Wiped per load: this is the module's own SavedVariables and busted
    -- insulates _G per FILE, not per test.
    _G.KitnEssentialsOptimizeDB = nil

    local KE = { Print = function(_, msg) rec.prints[#rec.prints + 1] = msg end }
    helpers.loadModule("Modules/QoL/Optimize.lua", KE)

    local OPT = modules["Optimize"]
    function OPT:RegisterEvent(event) rec.events[event] = true end
    function OPT:UnregisterEvent(event) rec.events[event] = nil end

    return OPT, rec, KE
end

-- Modules/Combat/CombatTimer.lua. Only the pure stop rule is reachable
-- headlessly: everything else in that module is frames, an OnUpdate ticker and
-- event timing, which this project verifies in game.
function L.loadCombatTimer(overrides)
    overrides = overrides or {}
    installMock(overrides, { C_Timer = inertTimer() })
    local modules = helpers.installAddonShim()

    _G.UIParent = noopFrame()
    _G.GetTime = overrides.GetTime or function() return 1000 end
    _G.InCombatLockdown = overrides.InCombatLockdown or function() return false end
    _G.C_InstanceEncounter = overrides.C_InstanceEncounter or {
        IsEncounterInProgress = function() return false end,
    }

    local KE = { Print = function() end }
    helpers.loadModule("Modules/Combat/CombatTimer.lua", KE)
    return modules["CombatTimer"], KE
end

-- Modules/Utilities/NoMovementAlert.lua. Several layers are reachable
-- headlessly: the PURE resolution layer (data tables, per-spec override rules,
-- alias and category duration lookup), the role-colour resolver, the cooldown
-- readback, and the buff-readback refusal rules, which are driven directly
-- rather than through OnEnable. The frames and the event timing are still
-- verified in game.
-- The module captures C_Spell/C_Timer/GetTime/UnitClass at file scope, so they
-- have to exist on _G BEFORE loadModule or the module holds stale upvalues.
-- Returns NMA, KE, rec. KE comes SECOND, unlike some loaders here, because the
-- resolution spec wants the module and the namespace and never the recorder:
-- a discard in the middle would have to be `_`, which is a GLOBAL write in Lua
-- and luacheck's allowlist hides it.
function L.loadMovementAlert(overrides)
    overrides = overrides or {}
    installMock(overrides, { C_Timer = inertTimer() })
    local modules = helpers.installAddonShim()

    local rec = { fonts = {}, editMode = { registered = {}, unregisterCalls = {} } }

    _G.UIParent = noopFrame()
    _G.GetTime = overrides.GetTime or function() return 1000 end
    _G.UnitClass = overrides.UnitClass or function() return "Druid", "DRUID", 11 end
    _G.UnitAffectingCombat = overrides.UnitAffectingCombat or function() return false end
    -- overrideSpell models the live client: GetOverrideSpell returns the id it
    -- was given unless a case declares a replacement, which is how the real
    -- API reports "nothing overrides this".
    _G.C_Spell = overrides.C_Spell or {
        GetSpellCooldown = function() return nil end,
        GetSpellCharges = function() return nil end,
        GetSpellInfo = function(id) return { name = "Spell " .. tostring(id) } end,
    }
    _G.C_Spell.overrideSpell = _G.C_Spell.overrideSpell or {}
    _G.C_Spell.GetOverrideSpell = _G.C_Spell.GetOverrideSpell or function(spellId)
        return _G.C_Spell.overrideSpell[spellId] or spellId
    end
    -- Still used for the learned check on non-paired spells. Specs override
    -- .known per-case; everything defaults to unknown.
    _G.C_SpellBook = overrides.C_SpellBook or {
        known = {},
        IsSpellKnownOrInSpellBook = function(_) return false end,
    }
    _G.C_SpellBook.IsSpellKnownOrInSpellBook = function(spellId)
        return _G.C_SpellBook.known[spellId] == true
    end
    _G.Enum = overrides.Enum or {}
    _G.Enum.SpellBookSpellBank = _G.Enum.SpellBookSpellBank or { Player = 0 }

    -- Both are read at CALL time, so a case can swap them per override.
    -- ReadBuffActive reads the aura namespace; SeedGlowState reads the overlay.
    -- An absent aura models the soft-fail this wave exists for; an absent
    -- overlay models a client where the glow API is unavailable.
    _G.C_UnitAuras = overrides.C_UnitAuras or {
        GetPlayerAuraBySpellID = function() return overrides.aura end,
    }
    _G.C_SpellActivationOverlay = overrides.overlay
    -- Absent by default, which is the pre-12.1 client and the broad-only path.
    -- A spec supplies it to exercise the exact-first branch.
    _G.C_Secrets = overrides.C_Secrets

    local KE = {
        Print = function() end,
        IsSecretValue = function() return false end,
        AreAuraIdentitiesHidden = function() return overrides.aurasHidden == true end,
        IsAuraHiddenForSpell = function(self, spellIdentifier)
            if spellIdentifier and _G.C_Secrets and _G.C_Secrets.ShouldSpellAuraBeSecret then
                local ok, secret = pcall(_G.C_Secrets.ShouldSpellAuraBeSecret, spellIdentifier)
                if ok then return secret == true end
            end
            return self:AreAuraIdentitiesHidden()
        end,
        ApplyFontToText = function(_, fontString, face, size, outline)
            rec.fonts[#rec.fonts + 1] =
                { fontString = fontString, face = face, size = size, outline = outline }
        end,
    }
    KE.EditMode = {
        RegisterElement = function(self, config) self.registered[config.key] = config end,
        UnregisterElement = function(self, key)
            self.registered[key] = nil
            self.unregisterCalls[#self.unregisterCalls + 1] = key
        end,
        registered = rec.editMode.registered,
        unregisterCalls = rec.editMode.unregisterCalls,
    }

    helpers.loadModule("Modules/Utilities/NoMovementAlert.lua", KE)
    return modules["NoMovementAlert"], KE, rec
end

-- Modules/Combat/AuraHeaders.lua. Both MakeHeaderModule calls run at file
-- scope and only DEFINE methods -- nothing touches a frame or the db until
-- OnEnable, which this loader never calls -- so the only stubs the spec
-- needs are KE.ShouldNotLoadModule, driven by overrides.shouldNotLoad, and
-- the enchant slot table below.
-- overrides.noHelper omits the ShouldNotLoadModule stub entirely, modelling
-- a build where Core/Globals.lua has not defined it. Returns the
-- BuffTracking module plus KE (the shim's registry also captures
-- PlayerDebuffTracking, reachable off KitnEssentials:GetModule if a spec
-- ever needs it).
function L.loadAuraHeaders(overrides)
    overrides = overrides or {}
    local modules = helpers.installAddonShim()
    -- The buff declaration reads the enchant slot table at file scope, so it
    -- has to exist before the module loads. The values are arbitrary: nothing
    -- in the spec environment reaches the container that consumes them.
    _G.AuraContainerItemEnchantmentSlot = _G.AuraContainerItemEnchantmentSlot or {
        MainHand = 1,
        OffHand  = 2,
        Ranged   = 3,
    }
    local KE = {
        db = { profile = { BuffTracking = {}, PlayerDebuffTracking = {} } },
    }
    if not overrides.noHelper then
        KE.ShouldNotLoadModule = function() return overrides.shouldNotLoad == true end
    end
    helpers.loadModule("Modules/Combat/AuraHeaders.lua", KE)
    return modules["BuffTracking"], KE
end

-- Modules/ClassUtilities/StanceText.lua. EvaluateSpec is a pure decision
-- function reading only its own arguments, so the loader needs no
-- shapeshift/aura stubs -- it exists solely to make the file loadable.
-- overrides.db seeds KE.db.profile.StanceText for specs that want it.
-- Returns ST, KE.
function L.loadStanceText(overrides)
    overrides = overrides or {}
    mock.installSpecInfo()
    local modules = helpers.installAddonShim()
    local KE = {
        db = { profile = { StanceText = overrides.db or {} } },
    }
    helpers.loadModule("Modules/ClassUtilities/StanceText.lua", KE)
    return modules["StanceText"], KE
end

-- Modules/ClassUtilities/PetStatusText.lua. The branch under test lives inside
-- the file-local CheckPetStatus, which is reached from outside only through
-- PS:UpdatePetText -- so the spec drives that and asserts on what was painted.
--
-- OnInitialize MUST be called: petInfo and isGrimoireClass are both set there,
-- and CheckPetStatus returns NONE immediately while petInfo is nil, so a spec
-- that skips it would pass against any implementation at all. SetEnabledState is
-- stubbed first because the addon shim's module table does not have it.
--
-- Enum and strsplit are read at FILE scope, so both must exist before
-- loadModule.
--
-- rec.text is the last painted string and rec.shown the last visibility call.
-- The refusal shows up as shown=false with no text, which is why both are
-- recorded rather than just the string.
function L.loadPetStatusText(overrides)
    overrides = overrides or {}
    local rec = { text = nil, shown = false }

    installMock(overrides, {
        C_Timer = inertTimer(),
    })

    _G.UIParent            = noopFrame()
    _G.UnitClass           = function() return overrides.class or "WARLOCK", overrides.class or "WARLOCK" end
    _G.IsMounted           = function() return false end
    _G.UnitOnTaxi          = function() return false end
    _G.UnitInVehicle       = function() return false end
    _G.UnitHasVehicleUI    = function() return false end
    _G.GetSpecialization   = function() return 1 end
    _G.GetSpecializationInfo = function() return overrides.specID or 265 end
    _G.C_SpellBook         = { IsSpellKnown = function() return true end }
    _G.UnitExists          = function(unit) return unit == "pet" and overrides.hasPet == true end
    _G.UnitIsDeadOrGhost   = function() return false end
    _G.PetHasActionBar     = function() return false end
    _G.GetPetActionInfo    = function() return nil end
    _G.C_UnitAuras         = { GetPlayerAuraBySpellID = function() return overrides.aura end }
    _G.Enum                = { SpellBookSpellBank = { Player = "Player" } }
    _G.strsplit            = function() return nil end
    -- Absent by default, which is the pre-12.1 client and the broad-only path.
    -- A spec supplies it to exercise the exact-first branch.
    _G.C_Secrets = overrides.C_Secrets

    local modules = helpers.installAddonShim()
    local KE = {
        db = { profile = { PetStatusText = overrides.db or {
            Enabled = true, PetMissing = "PET MISSING", MissingColor = { 1, 1, 1, 1 },
        } } },
        AreAuraIdentitiesHidden = function() return overrides.aurasHidden == true end,
        IsAuraHiddenForSpell = function(self, spellIdentifier)
            if spellIdentifier and _G.C_Secrets and _G.C_Secrets.ShouldSpellAuraBeSecret then
                local ok, secret = pcall(_G.C_Secrets.ShouldSpellAuraBeSecret, spellIdentifier)
                if ok then return secret == true end
            end
            return self:AreAuraIdentitiesHidden()
        end,
        GetSafeUnitGUID = function() return nil end,
        ResolveColor = function() return 1, 1, 1, 1 end,
    }
    helpers.loadModule("Modules/ClassUtilities/PetStatusText.lua", KE)

    local PS = modules["PetStatusText"]
    PS.SetEnabledState = function() end
    PS:OnInitialize()
    PS.isPreview = false
    PS.frame = {
        Show = function() rec.shown = true end,
        Hide = function() rec.shown = false end,
    }
    PS.text = {
        SetText = function(_, value) rec.text = value end,
        SetTextColor = function() end,
    }
    return PS, rec
end

-- Modules/ClassUtilities/HavocTracker.lua. Only the GATE is under test. The
-- loader replaces the two sinks EvaluateGate can reach and counts which one
-- fired, so a case reads as a decision rather than as frame state. Nothing here
-- builds a container: the AuraContainer path is engine behaviour, verified in
-- game.
--
-- The spec functions are driven through the bare globals. C_SpecializationInfo
-- delegates to them at call time, so assigning them after installMock still
-- reaches the module's file-scope upvalues.
-- Returns HT, rec.
function L.loadHavocTracker(overrides)
    overrides = overrides or {}
    local rec = { activate = 0, deactivate = 0 }

    installMock(overrides, {
        C_Timer = inertTimer(),
    })

    _G.UIParent  = noopFrame()
    _G.UnitClass = function() return "Warlock", overrides.class or "WARLOCK" end
    _G.GetSpecialization = function() return overrides.specIndex end
    _G.GetSpecializationInfo = function(index) return index and overrides.specID or nil end
    _G.LibStub   = function() return nil end

    local modules = helpers.installAddonShim()
    local KE = {
        db = { profile = { HavocTracker = overrides.db or { Enabled = true } } },
        Print = function() end,
    }
    helpers.loadModule("Modules/ClassUtilities/HavocTracker.lua", KE)

    local HT = modules["HavocTracker"]
    HT.db = KE.db.profile.HavocTracker
    HT.Activate = function() rec.activate = rec.activate + 1 end
    HT.Deactivate = function() rec.deactivate = rec.deactivate + 1 end
    return HT, rec
end

-- Modules/QoL/CombatLogger.lua. The module caches its whole API surface at
-- file scope, so every name it reads has to exist on _G BEFORE loadModule --
-- which is the point of loading it this way: a name cached from the wrong
-- namespace resolves to nil here exactly as it does in game.
--
-- rec.pvp is the mutable answer sheet behind the PvP predicates. The module
-- holds IsArenaSkirmish and IsWargame as upvalues, so reassigning them on _G
-- after the load would not reach it; routing every predicate through one table
-- lets a single load serve every branch. C_PvP deliberately carries only the
-- members the module is supposed to use.
-- Returns CL, rec.
function L.loadCombatLogger(overrides)
    overrides = overrides or {}
    installMock(overrides, { C_Timer = inertTimer() })
    local modules = helpers.installAddonShim()

    local rec = {
        logging = false,
        prints = {},
        popups = {},
        pvp = {
            ratedArena = false,
            skirmish = false,
            soloShuffle = false,
            wargame = false,
            ratedBG = false,
        },
    }

    _G.StaticPopupDialogs = {}
    _G.StaticPopup_Show = function(which) rec.popups[#rec.popups + 1] = which end
    _G.ReloadUI = function() end
    _G.GetInstanceInfo = overrides.GetInstanceInfo
        or function() return "Test", "none", 0, "", 0 end
    _G.LoggingCombat = overrides.LoggingCombat or function(on)
        if on ~= nil then rec.logging = on end
        return rec.logging
    end
    _G.C_CVar = overrides.C_CVar or {
        GetCVar = function() return "1" end,
        SetCVar = function() end,
    }
    _G.IsArenaSkirmish = function() return rec.pvp.skirmish end
    _G.IsWargame = function() return rec.pvp.wargame end
    _G.C_PvP = {
        IsRatedArena = function() return rec.pvp.ratedArena end,
        IsSoloShuffle = function() return rec.pvp.soloShuffle end,
        IsRatedBattleground = function() return rec.pvp.ratedBG end,
    }

    local KE = { Print = function(_, msg) rec.prints[#rec.prints + 1] = msg end }
    helpers.loadModule("Modules/QoL/CombatLogger.lua", KE)

    local CL = modules["CombatLogger"]
    CL.ScheduleTimer = function() return {} end
    CL.CancelTimer = function() end
    return CL, rec
end

-- Modules/DungeonTimers/DungeonRegistry.lua. Pure data + helpers on KE;
-- the shim provides the truthy KitnEssentials global its guard checks.
function L.loadDungeonRegistry()
    helpers.installAddonShim()
    return helpers.loadModule("Modules/DungeonTimers/DungeonRegistry.lua")
end

-- Core/EUIUnlockBridge.lua. No EllesmereUI global is installed on purpose: the
-- translation pair is pure, and the absent-EUI path is the one the specs
-- exercise.
function L.loadEUIUnlockBridge(overrides)
    installMock(overrides, { C_Timer = inertTimer() })
    _G.CreateFrame = function() return noopFrame() end
    local KE = {}
    return helpers.loadModule("Core/EUIUnlockBridge.lua", KE)
end

-- Modules/Skinning/ChatLinks.lua. CL is a file-local never assigned onto KE --
-- the shim registry is the only handle to it. The module captures the WoW
-- string aliases and `ceil` as file-scope upvalues, and Core/Secret.lua
-- captures `issecretvalue` the same way, so every stub must exist BEFORE its
-- loadModule and the secret override must travel through `overrides`.
function L.loadChatLinks(overrides)
    installMock(overrides, { C_Timer = inertTimer() })
    local modules = helpers.installAddonShim()
    _G.format = string.format
    _G.gsub = string.gsub
    _G.strmatch = string.match
    _G.ceil = math.ceil
    _G.strfind = string.find
    _G.strsub = string.sub
    local KE = { db = { profile = { Skinning = { ChatLinks = {} } } } }
    helpers.loadModule("Core/Secret.lua", KE)
    helpers.loadModule("Modules/Skinning/ChatLinks.lua", KE)
    return modules["ChatLinks"], KE
end

-- Returns the module, the private KE table, the shim registry, and the list the
-- geterrorhandler stub appends caught errors into.
--
-- Modules/Skinning/ChatHistory.lua. The module binds KE through select(2, ...),
-- so Core/Secret.lua loads onto the SAME table and db lives there too -- the
-- addon shim's global is only the NewModule/GetModule registry, and its tables
-- do not exist until NewModule or GetModule creates them. The shim runs no Ace
-- lifecycle, so UpdateDB, IsEnabled and ChatSkinActive are supplied here.
-- IsInInstance, GetServerTime, time, tinsert, tremove, strfind, CHAT_FRAMES
-- and geterrorhandler are not in the common mock and are set here. `wipe` IS
-- in the mock; it is set again anyway so this loader reads as a complete list
-- of what the module needs rather than a diff against another file.
-- IsInInstance honours overrides so an instance can be simulated, and both
-- clocks accept `false` to remove the global entirely.
function L.loadChatHistory(overrides)
    overrides = overrides or {}
    installMock(overrides, { C_Timer = inertTimer() })
    local modules = helpers.installAddonShim()
    _G.gsub = string.gsub
    _G.strsub = string.sub
    _G.strfind = string.find
    _G.tinsert = table.insert
    _G.tremove = table.remove
    _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    -- Both clocks are overridable AND removable. PackRow falls back from
    -- GetServerTime to time, and it also guards each function's EXISTENCE, so
    -- `false` has to mean "this global is not there" rather than "use the
    -- default" -- otherwise those two branches cannot be reached from a spec.
    -- The module localises both at file scope, so these must be set before it
    -- loads, which is where they already are.
    local function clock(override, default)
        if override == false then return nil end
        return override or default
    end
    _G.time = clock(overrides.time, function() return 1000 end)
    _G.GetServerTime = clock(overrides.GetServerTime, function() return 2000 end)
    _G.IsInInstance = overrides.IsInInstance or function() return false, "none" end
    _G.CHAT_FRAMES = overrides.CHAT_FRAMES or { "ChatFrame1" }
    -- DisplayChatHistory routes a throwing dispatch to the game's error handler.
    -- The common mock does not install one; loadGlobals installs its own for the
    -- same reason. Errors are collected so a spec can assert one was raised.
    local caught = {}
    _G.geterrorhandler = function() return function(err) caught[#caught + 1] = err end end

    local KE = {
        -- InsideInstance prints once when it cannot read the API, so the seed
        -- needs Print or three of the specs below throw instead of asserting.
        Print = function() end,
        db = {
            char = { ChatHistory = {}, ChatTypingHistory = {} },
            profile = {
                Skinning = {
                    Chat = { Enabled = true },
                    ChatHistory = {
                        Enabled = true,
                        Size = 100,
                        ShowTypes = {
                            WHISPER = true, GUILD = true, OFFICER = true,
                            PARTY = true, RAID = true, INSTANCE = true,
                            CHANNEL = true, SAY = true, YELL = true, EMOTE = true,
                        },
                    },
                },
            },
        },
    }
    helpers.loadModule("Core/Secret.lua", KE)
    helpers.loadModule("Modules/Skinning/ChatHistory.lua", KE)

    local CH = modules["ChatHistory"]
    CH:UpdateDB()
    -- ChatSkinActive asks the Chat module whether it is enabled. There is no
    -- Ace lifecycle here, so it is answered directly; a spec that wants it off
    -- replaces this. IsEnabled is answered the same way and for the same reason.
    CH.ChatSkinActive = function() return true end
    CH.IsEnabled = function() return true end
    return CH, KE, modules, caught
end

-- Modules/Healer/HealerMana.lua. Mode resolution is the spec target, so
-- IsInRaid is the override that matters. The frame stubs serve the functions
-- the specs call, not file load: nothing here creates a frame at load.
function L.loadHealerMana(overrides)
    overrides = overrides or {}
    installMock(managedSubset(overrides), {
        C_Timer = inertTimer(),
        GetTime = function() return 0 end,
        InCombatLockdown = function() return false end,
        CreateFrame = function() return noopFrame() end,
        UnitExists = function() return true end,
    })
    local modules = helpers.installAddonShim()
    _G.UIParent = noopFrame()

    -- The module calls LibStub at file scope. It tolerates a nil RETURN, not a
    -- nil LibStub, and neither the shim nor the mock installs one.
    _G.LibStub = overrides.LibStub or function() return nil end
    _G.IsInRaid = overrides.IsInRaid or function() return false end
    _G.IsInGroup = overrides.IsInGroup or function() return true end
    _G.IsInInstance = overrides.IsInInstance or function() return false, "none" end
    _G.GetNumGroupMembers = overrides.GetNumGroupMembers or function() return 0 end
    _G.UnitPowerPercent = overrides.UnitPowerPercent or function() return 100 end
    _G.GetRaidRosterInfo = overrides.GetRaidRosterInfo or function() return nil end
    -- Defaults to a non-healer, so a spec that drives the live roster scan
    -- finds nobody and stops rather than needing the whole snapshot surface.
    _G.UnitGroupRolesAssigned = overrides.UnitGroupRolesAssigned or function() return "DAMAGER" end

    local profile = {
        Dungeons = {
            HealerMana = {
                Enabled = true,
                EnableInRaid = true,
                SplitPositioning = false,
                Strata = "MEDIUM",
                anchorFrameType = "UIPARENT",
                ParentFrame = "UIParent",
                Position = {},
                RaidPosition = {},
                MaxHealers = 6,
                FrameWidth = 120,
                IconSize = 24,
                IconType = "spec",
                NameFontSize = 14,
                NameXOffset = 4,
                NameYOffset = 2,
                ManaFontSize = 14,
                ManaXOffset = 4,
                ManaYOffset = -2,
                FontOutline = "OUTLINE",
                HighManaColor = { 1, 1, 1, 1 },
                GrowDirection = "DOWN",
                FrameSpacing = 4,
            },
        },
    }
    local KE = {
        db = { profile = profile },
        FONT = "Fonts\\Expressway.TTF",
        GetFontPath = function() return "Fonts\\Expressway.TTF" end,
        GetFontOutline = function() return "OUTLINE" end,
        ApplyFramePosition = function() end,
        AddIconBorders = function() end,
        ApplyIconZoom = function() end,
        IsPlayerHealerSpec = function() return false end,
        Print = function() end,
    }
    helpers.loadModule("Modules/Healer/HealerMana.lua", KE)
    local HM = modules["HealerMana"]
    HM:UpdateDB()
    return HM, KE
end

return L

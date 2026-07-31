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
-- in-game). Returns the KE table, plus a table that the geterrorhandler
-- stub appends xpcall-caught error messages into (used by the
-- KE:RunAfterCombat drain spec to assert an errored closure still reaches
-- the error handler).
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
    }
    return helpers.loadModule("Core/Globals.lua", KE), caughtErrors
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
-- SYNCHRONOUSLY inside the mutating call (AceDB-3.0.lua:452,482,619,658).
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
        -- textureSizeX, textureSizeY, textureColor (Core/Widgets.lua:252-254).
        -- Six would shift every later argument by one and silently capture
        -- closures as button labels.
        CreatePrompt = function(_, title, text, _, _, _, _, _, _, _,
                                onAccept, onCancel, acceptText, cancelText)
            -- ClosePrompt CLEARS the handle at Core/Widgets.lua:167 BEFORE
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
            -- (Core/Widgets.lua:642); the stall-recovery path reads it.
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
    installMock(overrides, {})
    local KE = { db = { profile = { Skinning = { Chat = {} } } } }
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
        db = { profile = { Skinning = { BlizzardFrames = {} } } },
    }
    helpers.loadModule("Core/Secret.lua", KE)
    return helpers.loadModule("Modules/Skinning/SkinAPI.lua", KE)
end

-- Modules/Skinning/Tooltips.lua. TT is a file-local never assigned onto KE --
-- the shim registry is the only handle to it. Returns TT, KE.
-- `opts` carries globals _wow_mock does NOT manage (UnitReaction,
-- IsModifierKeyDown): those go straight on _G, so the `overrides` path cannot
-- reach them. `overrides` is for mock-managed keys only.
function L.loadTooltips(opts, overrides)
    opts = opts or {}
    installMock(overrides, { C_Timer = inertTimer() })
    local modules = helpers.installAddonShim()
    _G.UIParent = noopFrame()
    _G.CreateFrame = function() return noopFrame() end
    _G.hooksecurefunc = function() end
    _G.FACTION_BAR_COLORS = {
        [1] = { r = 0.87, g = 0.37, b = 0.37 },
        [4] = { r = 0.87, g = 0.87, b = 0.37 },
        [5] = { r = 0.37, g = 0.87, b = 0.37 },
    }
    _G.RAID_CLASS_COLORS = {
        EVOKER = { r = 0.20, g = 0.58, b = 0.50 },
    }
    _G.UnitReaction = opts.UnitReaction or function() return 5 end
    _G.IsModifierKeyDown = opts.IsModifierKeyDown or function() return false end
    -- Only the pure helpers (_ShortValue/_ColorsMatch/_ReactionColor/
    -- _WantIDs) are reachable from a spec; nothing here calls OnEnable, so
    -- only the globals those four touch need a stub.
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
-- global LR:ApplyPosition reads. LR._lastPoint() reads the mock's own
-- _points log (see lootroll_spec.lua's makeContainer) so a spec can assert
-- the most recent SetPoint without the mock needing a shared upvalue with
-- this loader. Returns LR, container.
function L.loadLootRoll(overrides)
    installMock(overrides, { C_Timer = inertTimer() })
    local modules = helpers.installAddonShim()
    _G.UIParent = noopFrame()
    _G.CreateFrame = function() return noopFrame() end
    _G.hooksecurefunc = function() end
    _G.InCombatLockdown = function() return false end
    local KE = {
        db = { profile = { Skinning = { LootRoll = {} } } },
        ShouldNotLoadModule = function() return false end,
        Skins = {},
    }
    helpers.loadModule("Modules/Skinning/LootRoll.lua", KE)
    local LR = modules["LootRoll"]

    local function container(mockContainer)
        _G.GroupLootContainer = mockContainer
    end

    LR._lastPoint = function()
        local c = _G.GroupLootContainer
        if not c or not c._points or #c._points == 0 then return nil end
        return c._points[#c._points]
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
            -- The real S.Icon (Modules/Skinning/SkinAPI.lua:1835) applies the
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
    helpers.loadModule("Modules/Skinning/LootRoll.lua", KE)
    helpers.loadModule("Modules/Skinning/LootRollBars.lua", KE)
    local LR = modules["LootRoll"]
    LR:UpdateDB()
    return LR, iconCalls
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
-- Keys _wow_mock.install actually consumes (dev/spec/_wow_mock.lua:51-92).
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
    -- Cursor.lua resolves the spec getter as
    -- `C_SpecializationInfo.GetSpecialization or GetSpecialization`, so it needs
    -- EITHER getter plus GetSpecializationRole. With neither, _isTankSpec
    -- returns false and the tank-positive test FAILS -- it does not pass
    -- vacuously. Because the modern getter is installed by default it would
    -- shadow a caller's legacy override, so pass `C_SpecializationInfo = false`
    -- to remove it and make the legacy global the seam under test.
    if overrides.C_SpecializationInfo == false then
        _G.C_SpecializationInfo = nil
    else
        _G.C_SpecializationInfo = overrides.C_SpecializationInfo
            or { GetSpecialization = function() return 1 end }
    end
    _G.GetSpecialization = overrides.GetSpecialization or function() return 1 end
    _G.GetSpecializationRole = overrides.GetSpecializationRole
        or function() return "TANK" end
    _G.GetCursorPosition = overrides.GetCursorPosition or function() return 0, 0 end
    _G.UnitCastingInfo = overrides.UnitCastingInfo or function() return nil end
    _G.UnitChannelInfo = overrides.UnitChannelInfo or function() return nil end
    _G.IsMouseButtonDown = overrides.IsMouseButtonDown or function() return false end
    _G.IsInRaid = overrides.IsInRaid or function() return false end
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

-- Modules/QoL/SlashCommands.lua. The file guards on a truthy KitnEssentials at
-- load, which installAddonShim supplies, and it indexes C_CVar at file scope
-- (SlashCommands.lua:14-15), so C_CVar must exist before load. Nothing registers
-- a slash command until KE:ApplySlashCommands runs, which this loader
-- deliberately does not call.
--
-- Managed overrides (InCombatLockdown and anything else in MANAGED_MOCK_KEYS)
-- are forwarded to installMock. C_CVar, C_AddOns, ReloadUI, SlashCmdList and
-- NUM_CHAT_WINDOWS are UNMANAGED (dev/spec/_wow_mock.lua:51-92), so they are
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
        or { GetAddOnInfo = function(name) return name end }
    _G.ReloadUI = overrides.ReloadUI or function() end
    _G.SlashCmdList = overrides.SlashCmdList or {}
    _G.NUM_CHAT_WINDOWS = overrides.NUM_CHAT_WINDOWS or 10

    local KE = { db = { profile = { SlashCommands = {} } }, Print = function() end }
    helpers.loadModule("Modules/QoL/SlashCommands.lua", KE)
    return KE
end

return L

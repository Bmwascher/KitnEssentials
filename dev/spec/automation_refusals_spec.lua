-- Tier: invented refusal/lifecycle rules only (tiered test policy). The
-- ported feature bodies (Task 1-3) are covered by the Step 8 structural diff
-- against the reference, not here. Four behaviours:
--   1. Combat deferral on the two Blizzard-window button creators (Task 2).
--   2. The master teardown + return trip (Task 3 Step 10b).
--   3. Master-off startup for Hide Helptips (Task 3 Step 10b).
--   4. The effective-state predicates themselves, in all three
--      (Enabled, feature key) states (Task 3 Step 10b).
--
-- Loaded directly against dev/spec/_helpers.lua (no dedicated _ke_loader.lua
-- entry -- Automation's fixture is specific to this one spec).

local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

-- Walks a function's upvalues by name (same recipe dev/spec/_ke_loader.lua
-- uses for its other module seams).
local function findUpvalue(fn, name)
    local i = 1
    while true do
        local upName, upVal = debug.getupvalue(fn, i)
        if not upName then return nil end
        if upName == name then return upVal end
        i = i + 1
    end
end

-- Builds a fresh module load with a recording spy in place of every frame
-- and hook the seven restructured features (plus the two Task 2 button
-- creators) touch. Every field returned is per-fixture -- nothing is shared
-- across fixtures, so busted's per-file _G reuse never leaks state between
-- cases.
local function newFixture()
    local ledger = {}
    local timers = {}
    local hookedGlobals = {}
    local hookedMethods = {}
    local named = {}
    local cvarSets = {}
    local combat = false
    local createCount = 0

    local function record(label, method, ...)
        ledger[#ledger + 1] = { frame = label, method = method, n = select("#", ...), ... }
    end

    local function newSpy(label)
        local shown, scripts, events = false, {}, {}
        local self_
        self_ = setmetatable({
            Show = function() shown = true; record(label, "Show") end,
            Hide = function() shown = false; record(label, "Hide") end,
            SetShown = function(_, v) shown = v and true or false; record(label, "SetShown", v) end,
            IsShown = function() return shown end,
            RegisterEvent = function(_, e) events[e] = true; record(label, "RegisterEvent", e) end,
            RegisterUnitEvent = function(_, e) events[e] = true; record(label, "RegisterUnitEvent", e) end,
            UnregisterEvent = function(_, e) events[e] = nil; record(label, "UnregisterEvent", e) end,
            UnregisterAllEvents = function() events = {}; record(label, "UnregisterAllEvents") end,
            IsEventRegistered = function(_, e) return events[e] == true end,
            SetScript = function(_, k, fn) scripts[k] = fn; record(label, "SetScript", k) end,
            GetScript = function(_, k) return scripts[k] end,
            HookScript = function(_, k, fn) scripts[k] = fn end,
            Fire = function(_, event, ...) if scripts.OnEvent then scripts.OnEvent(self_, event, ...) end end,
            GetFrameLevel = function() return 1 end,
            CreateTexture = function() return newSpy(label .. ".tex") end,
            CreateFontString = function() return newSpy(label .. ".fs") end,
        }, { __index = function(_, k) return function() record(label, k) end end })
        return self_
    end

    _G.CreateFrame = function(frameType, name)
        createCount = createCount + 1
        local label = name or (tostring(frameType) .. "#anon")
        local f = newSpy(label)
        if name then named[name] = f end
        return f
    end

    _G.hooksecurefunc = function(a, b, c)
        if type(a) == "string" then
            hookedGlobals[a] = b
        else
            hookedMethods[a] = hookedMethods[a] or {}
            hookedMethods[a][b] = c
        end
    end

    _G.C_Timer = {
        After = function(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end,
        NewTicker = function() return { Cancel = function() end } end,
        NewTimer = function() return { Cancel = function() end } end,
    }

    _G.InCombatLockdown = function() return combat end
    _G.UnitAffectingCombat = function() return false end
    _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    _G.issecretvalue = function() return false end

    -- Hide Helptips: minimal truthy HelpTip so the core hook installs and is
    -- observable; the tooltip/tutorial-fingerprint sweep machinery is left
    -- unstubbed on purpose (MainHelpPlateButtonMixin absent), so
    -- TutorialSweepAll/HideOpenTips both no-op safely.
    _G.SetCVar = function(name, val) cvarSets[name] = val end
    _G.HelpTip = { Show = function() end }
    _G.ShowUIPanel = function() end
    _G.MainHelpPlateButtonMixin = nil
    _G.HelpPlateTooltip = nil
    _G.HelpPlate = nil
    _G.EnumerateFrames = function() end
    -- Frozen clock: the sweep's time budget never expires headless, so the
    -- count cap alone decides slice size and the lifecycle cases stay
    -- deterministic. The budget case swaps in an advancing clock itself.
    _G.debugprofilestop = function() return 0 end

    -- Existing Blizzard frames the ported functions act on directly (never
    -- through CreateFrame), so a spy attached only to CreateFrame returns
    -- can't see them.
    _G.BossBanner = newSpy("BossBanner")
    _G.UIParent = newSpy("UIParent")
    _G.UIErrorsFrame = newSpy("UIErrorsFrame")
    local originalErrHandler = function() end
    _G.UIErrorsFrame:SetScript("OnEvent", originalErrHandler)

    _G.ExpansionLandingPageMinimapButton = newSpy("ExpansionLandingPageMinimapButton")
    _G.ActionStatus = newSpy("ActionStatus")
    _G.PaperDollFrame = newSpy("PaperDollFrame")
    _G.CharacterStatsPane = nil
    _G.GameTooltip = newSpy("GameTooltip")
    _G.ClassTrainerFrame = newSpy("ClassTrainerFrame")
    _G.ClassTrainerTrainButton = newSpy("ClassTrainerTrainButton")
    _G.UnitLevel = function() return 80 end
    _G.GetMaxPlayerLevel = function() return 80 end
    _G.C_AddOns = { IsAddOnLoaded = function() return true end }
    _G.EventUtil = nil -- force the already-loaded route, never the continuation
    _G.C_CurrencyInfo = { GetCoinTextureString = function() return "" end }
    _G.GetMoney = function() return 0 end
    _G.GetNumTrainerServices = nil
    _G.GetProfessions = nil

    _G.C_MountJournal = { GetNumMountsNeedingFanfare = function() return 0 end }
    _G.LE_MOUNT_JOURNAL_FILTER_COLLECTED = 1
    _G.LE_MOUNT_JOURNAL_FILTER_UNUSABLE = 3
    _G.CollectionsMicroButton = nil
    _G.CollectionsMicroButton_SetAlertShown = nil
    _G.MainMenuMicroButton_HideAlert = nil
    _G.COLLECTION_UNOPENED_PLURAL = "PLURAL"
    _G.COLLECTION_UNOPENED_SINGULAR = "SINGULAR"

    -- Fishing outfit cancel path: both methods the converted guard's block
    -- calls, so an "exact says readable" case reaches an observable cancel
    -- instead of the same silent nothing a refusal produces.
    local cancels = {}
    _G.C_UnitAuras = {
        GetPlayerAuraBySpellID = function() return { auraInstanceID = 42 } end,
        CancelAuraByInstanceID = function(unit, id) cancels[#cancels + 1] = { unit = unit, id = id } end,
    }
    _G.CancelUnitBuff = function() end
    _G.C_CVar = { GetCVar = function() return "0" end, SetCVar = function() end }
    _G.C_Secrets = nil

    -- File-scope assignment (StaticPopupDialogs["KE_BONUS_ROLL_CONFIRM"] = ...)
    -- needs the table to exist before the chunk runs, not just inside a function.
    _G.StaticPopupDialogs = {}

    local modules = helpers.installAddonShim()
    local KE = {
        Skins = nil,
        IsFullyRestricted = function() return false end,
        -- Core/Secret.lua's real one asks the restriction system; unrestricted
        -- is what these refusal paths need to reach their action.
        AreAuraIdentitiesHidden = function() return false end,
        IsAuraHiddenForSpell = function(self, spellIdentifier)
            if spellIdentifier and _G.C_Secrets and _G.C_Secrets.ShouldSpellAuraBeSecret then
                local ok, secret = pcall(_G.C_Secrets.ShouldSpellAuraBeSecret, spellIdentifier)
                if ok then return secret == true end
            end
            return self:AreAuraIdentitiesHidden()
        end,
    }
    -- The module indexes C_SpecializationInfo at file scope.
    mock.installSpecInfo()
    helpers.loadModule("Modules/QoL/Automation.lua", KE)
    local AU = modules["Automation"]

    -- Neither AceEvent nor AceHook is mixed in by the bare shim; stub only
    -- what the ported paths under test actually call. SecureHook is
    -- pre-empted by presetting the talking-head latch below rather than
    -- stubbed, since nothing in these four behaviours exercises it.
    AU.RegisterEvent = function(_, event) record("AU", "RegisterEvent:" .. event) end
    AU.SetEnabledState = function() end
    AU._talkingHeadHooked = true

    return {
        AU = AU, KE = KE,
        ledger = ledger, timers = timers,
        hookedGlobals = hookedGlobals, hookedMethods = hookedMethods,
        named = named, cvarSets = cvarSets,
        cancels = cancels,
        setSecrets = function(t) _G.C_Secrets = t end,
        setCombat = function(v) combat = v end,
        createCount = function() return createCount end,
        originalErrHandler = originalErrHandler,
        clearLedger = function() for i = #ledger, 1, -1 do ledger[i] = nil end end,
        findFrameCalls = function(label, method)
            local n = 0
            for _, e in ipairs(ledger) do
                if e.frame == label and e.method == method then n = n + 1 end
            end
            return n
        end,
        lastArg = function(label, method)
            for i = #ledger, 1, -1 do
                if ledger[i].frame == label and ledger[i].method == method then return ledger[i][1] end
            end
            return nil
        end,
    }
end

---------------------------------------------------------------------------------
-- Behaviour 1: combat deferral on the two button creators
---------------------------------------------------------------------------------
describe("Automation combat deferral (Task 2 Step 5)", function()
    it("creates neither button in combat, then creates both once combat ends", function()
        local fx = newFixture()
        local AU = fx.AU
        AU.db = { Enabled = true, OmniumCharButton = true, TrainAllButton = true }

        -- Other Automation features create their own frames unconditionally
        -- (their own install-once latches, unrelated to combat), so the
        -- count is compared call-to-call, not against a pre-apply zero.
        fx.setCombat(true)
        AU:ApplySettings()
        local afterFirstCombatCall = fx.createCount()
        assert.is_nil(fx.named["KE_OmniumFoilButton"])
        assert.is_nil(fx.named["KE_TrainAllButton"])
        assert.is_true(fx.findFrameCalls("AU", "RegisterEvent:PLAYER_REGEN_ENABLED") >= 1)

        -- Still in combat: every other feature's latch is already set, so a
        -- second apply must add nothing at all -- proving the count is truly
        -- unchanged, not just "hasn't grown yet".
        AU:ApplySettings()
        assert.equals(afterFirstCombatCall, fx.createCount())
        assert.is_nil(fx.named["KE_OmniumFoilButton"])
        assert.is_nil(fx.named["KE_TrainAllButton"])

        fx.setCombat(false)
        AU:ApplySettings()
        assert.is_true(fx.createCount() > afterFirstCombatCall)
        assert.is_not_nil(fx.named["KE_OmniumFoilButton"])
        assert.is_not_nil(fx.named["KE_TrainAllButton"])
    end)
end)

---------------------------------------------------------------------------------
-- Shared install fixture for behaviours 2 and 4: all seven feature keys plus
-- every window precondition the button creators need, master and combat
-- both in their "everything can install" state.
---------------------------------------------------------------------------------
local function installedFixture()
    local fx = newFixture()
    local AU = fx.AU
    AU.db = {
        Enabled = true,
        HideBossBannerLoot = true,
        AutoUnwrapCollections = true,
        HideScreenshotStatus = true,
        HideErrorMessages = true,
        HideTransforms = true,
        HideTransformItems = {},
        OmniumCharButton = true,
        TrainAllButton = true,
        HideHelptips = true,
    }
    fx.setCombat(false)
    AU:ApplySettings()
    return fx
end

-- Show/hide the subjects back to their pre-callback baseline, THEN clear the
-- ledger -- in that order, so the baseline calls never land in the ledger a
-- refusal assertion reads.
local function normalizeAndClear(fx)
    _G.ExpansionLandingPageMinimapButton:Show()
    _G.ActionStatus:Show()
    local trainBtn = fx.named["KE_TrainAllButton"]
    if trainBtn then trainBtn:Hide() end
    local omniBtn = fx.named["KE_OmniumFoilButton"]
    if omniBtn then omniBtn:Hide() end
    fx.clearLedger()
end

---------------------------------------------------------------------------------
-- Behaviour 2: master teardown and the return trip
---------------------------------------------------------------------------------
describe("Automation master teardown and return trip (Task 3 Step 10b)", function()
    it("installs everything, tears every feature down, then restores it all on return", function()
        local fx = installedFixture()
        local AU = fx.AU

        -- Installed-state proof beyond bare event assertions: Hide Error
        -- Messages replaces UIErrorsFrame's script, and Omnium/Train All
        -- prove themselves through visibility.
        assert.is_false(_G.BossBanner:IsEventRegistered("ENCOUNTER_LOOT_RECEIVED"))
        assert.is_false(_G.UIParent:IsEventRegistered("PING_SYSTEM_ERROR"))
        local filteredHandler = _G.UIErrorsFrame:GetScript("OnEvent")
        assert.is_not_nil(filteredHandler)
        assert.is_not.equal(fx.originalErrHandler, filteredHandler)
        assert.is_true(fx.named["KE_OmniumFoilButton"] ~= nil and fx.named["KE_OmniumFoilButton"]:IsShown())
        assert.is_false(_G.ExpansionLandingPageMinimapButton:IsShown())
        assert.is_true(fx.named["KE_TrainAllButton"] ~= nil and fx.named["KE_TrainAllButton"]:IsShown())

        local unwrapFrame = findUpvalue(AU.ApplySettings, "SetupAutoUnwrapCollections")
        unwrapFrame = findUpvalue(unwrapFrame, "unwrapFrame")
        assert.is_true(unwrapFrame:IsEventRegistered("NEW_MOUNT_ADDED"))
        assert.is_true(unwrapFrame:IsEventRegistered("NEW_PET_ADDED"))
        assert.is_true(unwrapFrame:IsEventRegistered("NEW_TOY_ADDED"))

        local screenshotSetup = findUpvalue(AU.ApplySettings, "SetupHideScreenshotStatus")
        local screenshotFrame = findUpvalue(screenshotSetup, "screenshotFrame")
        assert.is_true(screenshotFrame:IsEventRegistered("SCREENSHOT_SUCCEEDED"))
        assert.is_true(screenshotFrame:IsEventRegistered("SCREENSHOT_FAILED"))

        local applyTransforms = findUpvalue(AU.ApplySettings, "ApplyHideTransforms")
        local transformAuraFrame = findUpvalue(applyTransforms, "transformAuraFrame")
        local transformFishFrame = findUpvalue(applyTransforms, "transformFishFrame")
        assert.is_true(transformAuraFrame:IsEventRegistered("UNIT_AURA"))
        assert.is_true(transformAuraFrame:IsEventRegistered("PLAYER_REGEN_ENABLED"))
        assert.is_true(transformFishFrame:IsEventRegistered("UNIT_SPELLCAST_CHANNEL_STOP"))

        local dbBefore = {}
        for k, v in pairs(AU.db) do dbBefore[k] = v end

        normalizeAndClear(fx)

        AU.db.Enabled = false
        AU:TeardownPorts()

        assert.is_true(_G.BossBanner:IsEventRegistered("ENCOUNTER_LOOT_RECEIVED"))
        assert.is_true(unwrapFrame:IsEventRegistered("NEW_MOUNT_ADDED") == false)
        assert.is_true(screenshotFrame:IsEventRegistered("SCREENSHOT_SUCCEEDED") == false)
        assert.equals(fx.originalErrHandler, _G.UIErrorsFrame:GetScript("OnEvent"))
        assert.is_true(_G.UIParent:IsEventRegistered("PING_SYSTEM_ERROR"))
        assert.is_true(transformAuraFrame:IsEventRegistered("UNIT_AURA") == false)
        assert.is_true(transformAuraFrame:IsEventRegistered("PLAYER_REGEN_ENABLED") == false)
        assert.is_true(transformFishFrame:IsEventRegistered("UNIT_SPELLCAST_CHANNEL_STOP") == false)
        -- Ledger, NOT IsShown(): normalizeAndClear shows this button itself, so a
        -- state read here passes even if the teardown never restores it.
        assert.equals(1, fx.findFrameCalls("ExpansionLandingPageMinimapButton", "Show"))
        assert.equals(1, fx.findFrameCalls("KE_OmniumFoilButton", "SetShown"))
        assert.is_false(fx.lastArg("KE_OmniumFoilButton", "SetShown"))
        assert.equals(1, fx.findFrameCalls("KE_TrainAllButton", "Hide"))
        assert.equals(0, fx.findFrameCalls("KE_TrainAllButton", "Show"))

        -- Enabled is the test's own state-under-test lever, flipped by hand
        -- above -- everything else must survive the transition untouched.
        for k, v in pairs(dbBefore) do
            if k ~= "Enabled" then assert.equals(v, AU.db[k]) end
        end

        normalizeAndClear(fx)

        AU.db.Enabled = true
        AU:ApplySettings()

        assert.is_false(_G.BossBanner:IsEventRegistered("ENCOUNTER_LOOT_RECEIVED"))
        assert.is_true(unwrapFrame:IsEventRegistered("NEW_MOUNT_ADDED"))
        assert.is_true(unwrapFrame:IsEventRegistered("NEW_PET_ADDED"))
        assert.is_true(unwrapFrame:IsEventRegistered("NEW_TOY_ADDED"))
        assert.is_true(screenshotFrame:IsEventRegistered("SCREENSHOT_SUCCEEDED"))
        assert.is_true(screenshotFrame:IsEventRegistered("SCREENSHOT_FAILED"))
        assert.equals(filteredHandler, _G.UIErrorsFrame:GetScript("OnEvent"))
        assert.is_false(_G.UIParent:IsEventRegistered("PING_SYSTEM_ERROR"))
        assert.is_true(transformAuraFrame:IsEventRegistered("UNIT_AURA"))
        assert.is_true(transformAuraFrame:IsEventRegistered("PLAYER_REGEN_ENABLED"))
        assert.is_true(transformFishFrame:IsEventRegistered("UNIT_SPELLCAST_CHANNEL_STOP"))
        assert.equals(1, fx.findFrameCalls("ExpansionLandingPageMinimapButton", "Hide"))
        assert.equals(1, fx.findFrameCalls("KE_OmniumFoilButton", "SetShown"))
        assert.is_true(fx.lastArg("KE_OmniumFoilButton", "SetShown"))
        assert.is_true(fx.named["KE_TrainAllButton"] ~= nil)
        assert.is_true(fx.findFrameCalls("KE_TrainAllButton", "Show") >= 1)

        -- Enabled is the test's own state-under-test lever, flipped by hand
        -- above -- everything else must survive the transition untouched.
        for k, v in pairs(dbBefore) do
            if k ~= "Enabled" then assert.equals(v, AU.db[k]) end
        end

        assert.is_true(AU.db.HideHelptips)
        assert.is_not_nil(fx.hookedMethods[_G.HelpTip] and fx.hookedMethods[_G.HelpTip]["Show"])
    end)
end)

---------------------------------------------------------------------------------
-- Behaviour 3: master-off startup for Hide Helptips
---------------------------------------------------------------------------------
describe("Automation Hide Helptips master-off startup (Task 3 Step 10b)", function()
    it("applies suppression from OnInitialize with the master off, HideHelptips on", function()
        local fx = newFixture()
        local AU = fx.AU
        fx.KE.db = { profile = { Automation = { Enabled = false, HideHelptips = true } } }
        AU:OnInitialize()
        assert.equals("1", fx.cvarSets.hideHelptips)
        assert.equals("0", fx.cvarSets.showTutorials)
        assert.is_not_nil(fx.hookedMethods[_G.HelpTip] and fx.hookedMethods[_G.HelpTip]["Show"])
    end)

    it("does not suppress at startup when HideHelptips is off, master notwithstanding", function()
        local fx = newFixture()
        local AU = fx.AU
        fx.KE.db = { profile = { Automation = { Enabled = false, HideHelptips = false } } }
        AU:OnInitialize()
        assert.is_nil(fx.cvarSets.hideHelptips)
    end)
end)

---------------------------------------------------------------------------------
-- Behaviour 4: the effective-state predicates themselves, in all three
-- (Enabled, feature key) states. Every gated path is supposed to read
-- "Enabled AND its own feature key" -- writing "or" instead passes the Step 8
-- structural diff (same hunk, correctly attributed) while the path keeps
-- running with the master off.
---------------------------------------------------------------------------------
describe("Automation effective-state predicates (Task 3 Step 10b)", function()
    -- The nine callback/helper paths: captured once from a fully-installed,
    -- fully-active fixture, then invoked directly under each of the three
    -- (Enabled, key) states so the predicate under test is what decides the
    -- outcome -- never a gate sitting in front of it.
    local paths = {
        {
            name = "DismissCollectionAlerts",
            key = "AutoUnwrapCollections",
            capture = function(fx)
                for _, t in ipairs(fx.timers) do
                    if t.delay == 3 then return t.fn end
                end
            end,
            check = function(fx, fn, active)
                local before = #fx.timers
                fn()
                local scheduled = false
                for i = before + 1, #fx.timers do
                    if fx.timers[i].delay == 0.2 then scheduled = true end
                end
                assert.equals(active, scheduled)
            end,
        },
        {
            name = "the 0.2 second acknowledgement closure",
            key = "AutoUnwrapCollections",
            capture = function(fx)
                -- Drive DismissCollectionAlerts itself (still fully active)
                -- so it schedules the 0.2s closure to capture.
                local dismiss
                for _, t in ipairs(fx.timers) do
                    if t.delay == 3 then dismiss = t.fn end
                end
                local before = #fx.timers
                dismiss()
                for i = before + 1, #fx.timers do
                    if fx.timers[i].delay == 0.2 then return fx.timers[i].fn end
                end
            end,
            check = function(fx, fn, active)
                if active then
                    _G.C_MountJournal = {
                        GetNumMountsNeedingFanfare = function() return 1 end,
                        GetNumDisplayedMounts = function() return 1 end,
                        GetDisplayedMountID = function() return 99 end,
                        NeedsFanfare = function() return true end,
                        GetCollectedFilterSetting = function() return true end,
                        SetCollectedFilterSetting = function() end,
                        ClearFanfare = function(id) fx.clearedMountID = id end,
                    }
                    fx.clearedMountID = nil
                    fn()
                    assert.equals(99, fx.clearedMountID)
                else
                    fx.clearedMountID = nil
                    fn()
                    assert.is_nil(fx.clearedMountID)
                    -- busy must reset even on refusal, or a later active
                    -- pass stays wedged behind the latch.
                    _G.C_MountJournal = { GetNumMountsNeedingFanfare = function() return 0 end }
                    local before = #fx.timers
                    local dismiss
                    for _, t in ipairs(fx.timers) do
                        if t.delay == 3 then dismiss = t.fn end
                    end
                    fx.AU.db.Enabled, fx.AU.db.AutoUnwrapCollections = true, true
                    dismiss()
                    assert.is_true(#fx.timers > before)
                end
            end,
        },
        {
            name = "the permanent micro-button hook",
            key = "AutoUnwrapCollections",
            capture = function(fx)
                local hookFn = fx.hookedGlobals["MainMenuMicroButton_ShowAlert"]
                local spy = { n = 0 }
                local i = 1
                while true do
                    local upName = debug.getupvalue(hookFn, i)
                    if not upName then error("DismissCollectionAlerts upvalue not found") end
                    if upName == "DismissCollectionAlerts" then
                        debug.setupvalue(hookFn, i, function() spy.n = spy.n + 1 end)
                        break
                    end
                    i = i + 1
                end
                return { hookFn = hookFn, spy = spy }
            end,
            check = function(_, captured, active)
                captured.spy.n = 0
                captured.hookFn(nil, "PLURAL")
                assert.equals(active and 1 or 0, captured.spy.n)
            end,
        },
        {
            name = "the Omnium minimap Show hook",
            key = "OmniumCharButton",
            capture = function(fx)
                return fx.hookedMethods[_G.ExpansionLandingPageMinimapButton]
                    and fx.hookedMethods[_G.ExpansionLandingPageMinimapButton]["Show"]
            end,
            check = function(fx, fn, active)
                fn(_G.ExpansionLandingPageMinimapButton)
                assert.equals(active and 1 or 0, fx.findFrameCalls("ExpansionLandingPageMinimapButton", "Hide"))
            end,
        },
        {
            name = "HideActionStatus",
            key = "HideScreenshotStatus",
            capture = function(fx)
                local setup = findUpvalue(fx.AU.ApplySettings, "SetupHideScreenshotStatus")
                local frame = findUpvalue(setup, "screenshotFrame")
                local before = #fx.timers
                frame:Fire("SCREENSHOT_SUCCEEDED")
                for i = before + 1, #fx.timers do
                    if fx.timers[i].delay == 0 then return fx.timers[i].fn end
                end
            end,
            check = function(fx, fn, active)
                fn()
                assert.equals(active and 1 or 0, fx.findFrameCalls("ActionStatus", "Hide"))
            end,
        },
        {
            name = "the fishing channel closure",
            key = "HideTransforms",
            capture = function(fx)
                local applyTransforms = findUpvalue(fx.AU.ApplySettings, "ApplyHideTransforms")
                local fishFrame = findUpvalue(applyTransforms, "transformFishFrame")
                local FISHING_CHANNEL_ID = findUpvalue(applyTransforms, "FISHING_CHANNEL_ID")
                local before = #fx.timers
                fishFrame:Fire("UNIT_SPELLCAST_CHANNEL_STOP", nil, nil, FISHING_CHANNEL_ID)
                for i = before + 1, #fx.timers do
                    if fx.timers[i].delay == 0.3 then return fx.timers[i].fn end
                end
            end,
            check = function(_, fn, active)
                local called = false
                _G.UnitAffectingCombat = function() return false end
                _G.C_UnitAuras = {
                    GetPlayerAuraBySpellID = function() return { auraInstanceID = 7 } end,
                    CancelAuraByInstanceID = function() called = true end,
                }
                fn()
                assert.equals(active, called)
                _G.C_UnitAuras = nil
            end,
        },
        {
            name = "SpawnButton",
            key = "TrainAllButton",
            capture = function(fx) return fx.AU._deferredTrainAllSpawn end,
            check = function(fx, fn, active)
                local before = fx.createCount()
                fn()
                -- Existing-button branch: show it (and RefreshButton shows it
                -- again) -- never a second CreateFrame, which would mean the
                -- retained handle was lost and a duplicate button built.
                assert.equals(before, fx.createCount())
                if active then
                    assert.is_true(fx.findFrameCalls("KE_TrainAllButton", "Show") >= 1)
                else
                    assert.equals(0, fx.findFrameCalls("KE_TrainAllButton", "Show"))
                end
            end,
        },
        {
            name = "Train All's RefreshButton",
            key = "TrainAllButton",
            capture = function(fx) return fx.hookedGlobals["ClassTrainerFrame_Update"] end,
            check = function(fx, fn, active)
                fn()
                if active then
                    assert.is_true(fx.findFrameCalls("KE_TrainAllButton", "Show") >= 1)
                else
                    assert.equals(1, fx.findFrameCalls("KE_TrainAllButton", "Hide"))
                    assert.equals(0, fx.findFrameCalls("KE_TrainAllButton", "Show"))
                end
            end,
        },
    }

    for _, path in ipairs(paths) do
        describe(path.name, function()
            for _, state in ipairs({
                { enabled = false, key = true,  active = false, label = "(false, true) refuses" },
                { enabled = true,  key = false, active = false, label = "(true, false) refuses" },
                { enabled = true,  key = true,  active = true,  label = "(true, true) acts" },
            }) do
                it(state.label, function()
                    local fx = installedFixture()
                    local captured = path.capture(fx)
                    assert.is_not_nil(captured)
                    normalizeAndClear(fx)
                    fx.AU.db.Enabled = state.enabled
                    fx.AU.db[path.key] = state.key
                    path.check(fx, captured, state.active)
                end)
            end
        end)
    end

    -- OmniumRefreshShown: not capturable (nothing stores a handle to it, and
    -- SetupOmniumButton is a file-local a spec cannot call either). Reached
    -- through TeardownPorts for the master-off state (ApplySettings returns
    -- before reaching it there) and through ApplySettings for the other two.
    describe("OmniumRefreshShown", function()
        it("(false, true) refuses, reached through TeardownPorts", function()
            local fx = installedFixture()
            normalizeAndClear(fx)
            fx.AU.db.Enabled = false
            fx.AU.db.OmniumCharButton = true
            fx.AU:TeardownPorts()
            assert.equals(1, fx.findFrameCalls("KE_OmniumFoilButton", "SetShown"))
            assert.is_false(fx.lastArg("KE_OmniumFoilButton", "SetShown"))
        end)

        it("(true, false) refuses, reached through ApplySettings", function()
            local fx = installedFixture()
            normalizeAndClear(fx)
            fx.AU.db.Enabled = true
            fx.AU.db.OmniumCharButton = false
            fx.AU:ApplySettings()
            assert.equals(1, fx.findFrameCalls("KE_OmniumFoilButton", "SetShown"))
            assert.is_false(fx.lastArg("KE_OmniumFoilButton", "SetShown"))
        end)

        it("(true, true) acts, reached through ApplySettings", function()
            local fx = installedFixture()
            normalizeAndClear(fx)
            fx.AU.db.Enabled = true
            fx.AU.db.OmniumCharButton = true
            fx.AU:ApplySettings()
            assert.equals(1, fx.findFrameCalls("KE_OmniumFoilButton", "SetShown"))
            assert.is_true(fx.lastArg("KE_OmniumFoilButton", "SetShown"))
        end)
    end)

    -- The seven top-level functions: behaviour 2 already drives (false, true)
    -- and (true, true) for all seven. The one quadrant nothing else covers is
    -- (true, false) -- master ON, that function's own key OFF -- reached
    -- through AU:ApplySettings(), asserting the same off-state effect
    -- behaviour 2 asserts for that feature on teardown.
    describe("the seven top-level functions, master on / own key off", function()
        it("ApplyNoBossLoot leaves the loot banner suppressed if HideBossBannerLoot alone is off", function()
            local fx = installedFixture()
            normalizeAndClear(fx)
            fx.AU.db.Enabled = true
            fx.AU.db.HideBossBannerLoot = false
            fx.AU:ApplySettings()
            assert.is_true(_G.BossBanner:IsEventRegistered("ENCOUNTER_LOOT_RECEIVED"))
        end)

        it("ApplyHideErrorMessages restores the original handler if HideErrorMessages alone is off", function()
            local fx = installedFixture()
            local filteredHandler = _G.UIErrorsFrame:GetScript("OnEvent")
            normalizeAndClear(fx)
            fx.AU.db.Enabled = true
            fx.AU.db.HideErrorMessages = false
            fx.AU:ApplySettings()
            assert.is_not.equal(filteredHandler, _G.UIErrorsFrame:GetScript("OnEvent"))
            assert.is_true(_G.UIParent:IsEventRegistered("PING_SYSTEM_ERROR"))
        end)

        it("ApplyHideTransforms unregisters both transform frames if HideTransforms alone is off", function()
            local fx = installedFixture()
            local AU = fx.AU
            local applyTransforms = findUpvalue(AU.ApplySettings, "ApplyHideTransforms")
            local transformAuraFrame = findUpvalue(applyTransforms, "transformAuraFrame")
            local transformFishFrame = findUpvalue(applyTransforms, "transformFishFrame")
            normalizeAndClear(fx)
            AU.db.Enabled = true
            AU.db.HideTransforms = false
            AU:ApplySettings()
            assert.is_false(transformAuraFrame:IsEventRegistered("UNIT_AURA"))
            assert.is_false(transformAuraFrame:IsEventRegistered("PLAYER_REGEN_ENABLED"))
            assert.is_false(transformFishFrame:IsEventRegistered("UNIT_SPELLCAST_CHANNEL_STOP"))
        end)

        it("SetupOmniumButton shows the minimap button and hides the char button if OmniumCharButton alone is off", function()
            local fx = installedFixture()
            normalizeAndClear(fx)
            fx.AU.db.Enabled = true
            fx.AU.db.OmniumCharButton = false
            fx.AU:ApplySettings()
            assert.equals(1, fx.findFrameCalls("ExpansionLandingPageMinimapButton", "Show"))
            assert.is_false(fx.lastArg("KE_OmniumFoilButton", "SetShown"))
        end)

        it("SetupAutoUnwrapCollections unregisters its frame if AutoUnwrapCollections alone is off", function()
            local fx = installedFixture()
            local unwrapSetup = findUpvalue(fx.AU.ApplySettings, "SetupAutoUnwrapCollections")
            local unwrapFrame = findUpvalue(unwrapSetup, "unwrapFrame")
            normalizeAndClear(fx)
            fx.AU.db.Enabled = true
            fx.AU.db.AutoUnwrapCollections = false
            fx.AU:ApplySettings()
            assert.is_false(unwrapFrame:IsEventRegistered("NEW_MOUNT_ADDED"))
            assert.is_false(unwrapFrame:IsEventRegistered("NEW_PET_ADDED"))
            assert.is_false(unwrapFrame:IsEventRegistered("NEW_TOY_ADDED"))
        end)

        it("SetupHideScreenshotStatus unregisters its frame if HideScreenshotStatus alone is off", function()
            local fx = installedFixture()
            local screenshotSetup = findUpvalue(fx.AU.ApplySettings, "SetupHideScreenshotStatus")
            local screenshotFrame = findUpvalue(screenshotSetup, "screenshotFrame")
            normalizeAndClear(fx)
            fx.AU.db.Enabled = true
            fx.AU.db.HideScreenshotStatus = false
            fx.AU:ApplySettings()
            assert.is_false(screenshotFrame:IsEventRegistered("SCREENSHOT_SUCCEEDED"))
            assert.is_false(screenshotFrame:IsEventRegistered("SCREENSHOT_FAILED"))
        end)

        it("SetupTrainAllButton hides trainBtn if TrainAllButton alone is off", function()
            local fx = installedFixture()
            normalizeAndClear(fx)
            fx.AU.db.Enabled = true
            fx.AU.db.TrainAllButton = false
            fx.AU:ApplySettings()
            assert.equals(1, fx.findFrameCalls("KE_TrainAllButton", "Hide"))
            assert.equals(0, fx.findFrameCalls("KE_TrainAllButton", "Show"))
        end)
    end)
end)

---------------------------------------------------------------------------------
-- Behaviour 5: the Hide Helptips sweep lifecycle
---------------------------------------------------------------------------------
-- The sweep walks the client's entire frame list in slices so it cannot trip
-- the script watchdog. Everything asserted here is invented bookkeeping around
-- that walk: slice handoff, once-per-enable, abort-and-retry, generation
-- retirement, per-frame isolation, and restore retention. The walk's TIMING is
-- not under test -- the fixture's C_Timer records callbacks and these cases run
-- them by hand.

-- `count` frames, a tutorial button every `every`th slot, all reachable.
-- Returns the frame list, the buttons in it, a call counter for the
-- enumerator so a case can prove a walk did or did not start, and a call
-- counter for the access checks so a case can prove who paid for one.
local function newSweepWorld(count, every, fingerprint)
    local frames, buttons, index = {}, {}, {}
    local accessCalls = 0
    for i = 1, count do
        local f = {
            alpha = 1,
            mouse = true,
            SetAlpha = function(self, v) self.alpha = v end,
            EnableMouse = function(self, v) self.mouse = v end,
            CanBeAccessedInContext = function() accessCalls = accessCalls + 1; return true end,
        }
        if i % every == 0 then
            f.ShowTooltip = fingerprint
            buttons[#buttons + 1] = f
        end
        frames[i] = f
        index[f] = i
    end

    local calls = 0
    _G.EnumerateFrames = function(prev)
        calls = calls + 1
        if prev == nil then return frames[1] end
        local at = index[prev]
        if not at then return nil end
        return frames[at + 1]
    end

    return frames, buttons, function() return calls end, function() return accessCalls end
end

-- Runs the zero-delay callbacks queued from `from` onward, picking up the ones
-- each slice queues behind it. Bounded: a walk that never terminates must fail
-- the case, not hang the suite.
local function pumpSlices(fx, from)
    local i = from or 1
    local ran = 0
    while i <= #fx.timers do
        local t = fx.timers[i]
        i = i + 1
        if t.delay == 0 and not t.pumped then
            t.pumped = true
            ran = ran + 1
            if ran > 200 then error("sweep did not terminate") end
            t.fn()
        end
    end
    return ran
end

-- Master OFF, feature ON: Hide Helptips is master-independent, so ApplySettings
-- reaches ApplyHideHelptips and returns before every other feature. That keeps
-- the timer list to this walk's own slices.
local function helptipFixture()
    local fx = newFixture()
    _G.MainHelpPlateButtonMixin = { ShowTooltip = function() end }
    fx.fingerprint = _G.MainHelpPlateButtonMixin.ShowTooltip
    fx.AU.db = { Enabled = false, HideHelptips = true }
    return fx
end

local function countHidden(buttons)
    local n = 0
    for _, b in ipairs(buttons) do
        if b.alpha == 0 then n = n + 1 end
    end
    return n
end

local function allHidden(buttons)
    for _, b in ipairs(buttons) do
        if b.alpha ~= 0 or b.mouse ~= false then return false end
    end
    return true
end

describe("Automation Hide Helptips sweep lifecycle", function()
    it("hides every tutorial button across more than one slice", function()
        local fx = helptipFixture()
        local _, buttons = newSweepWorld(1200, 100, fx.fingerprint)
        local from = #fx.timers + 1

        fx.AU:ApplySettings()
        assert.is_true(pumpSlices(fx, from) >= 2) -- 1200 frames cannot be one slice
        assert.equals(12, #buttons)
        assert.is_true(allHidden(buttons))
    end)

    it("asks the access question only of frames that match the fingerprint", function()
        local fx = helptipFixture()
        local _, buttons, _, accessCalls = newSweepWorld(1200, 100, fx.fingerprint)
        local from = #fx.timers + 1

        fx.AU:ApplySettings()
        pumpSlices(fx, from)
        assert.is_true(allHidden(buttons))
        -- The access check is a per-call security query expensive enough to
        -- stall the login frame rate when every frame in the client pays it;
        -- only fingerprint matches may.
        assert.equals(#buttons, accessCalls())
    end)

    it("yields the tick when the time budget runs out before the count does", function()
        local fx = helptipFixture()
        local _, buttons = newSweepWorld(100, 10, fx.fingerprint)
        -- Every clock read advances a full millisecond, so each slice's budget
        -- expires after a single frame. The walk must still finish -- one
        -- frame per tick -- rather than stopping or spinning.
        local now = 0
        _G.debugprofilestop = function() now = now + 1 return now end
        local from = #fx.timers + 1

        fx.AU:ApplySettings()
        -- ~one frame per tick across 100 frames (the first slice runs inside
        -- ApplySettings itself, so the queue holds one fewer). A count-only
        -- slice would finish in a single tick.
        assert.is_true(pumpSlices(fx, from) >= 50)
        assert.is_true(allHidden(buttons))
    end)

    it("does not walk again on a later apply once a walk completed", function()
        local fx = helptipFixture()
        local _, _, calls = newSweepWorld(1200, 100, fx.fingerprint)
        local from = #fx.timers + 1

        fx.AU:ApplySettings()
        pumpSlices(fx, from)
        local afterFirst = calls()

        fx.AU:ApplySettings() -- what every zone load does
        pumpSlices(fx, from)
        assert.equals(afterFirst, calls())
    end)

    it("does not count a walk as done when no fingerprint exists yet", function()
        local fx = newFixture()
        _G.MainHelpPlateButtonMixin = nil
        fx.AU.db = { Enabled = false, HideHelptips = true }
        local from = #fx.timers + 1

        local fingerprint = function() end
        local _, buttons = newSweepWorld(400, 100, fingerprint)
        fx.AU:ApplySettings() -- nothing to match against, so nothing is claimed
        pumpSlices(fx, from)
        assert.equals(0, countHidden(buttons))

        _G.MainHelpPlateButtonMixin = { ShowTooltip = fingerprint }
        fx.AU:ApplySettings()
        pumpSlices(fx, from)
        assert.is_true(allHidden(buttons))
    end)

    it("retries on a later apply after the walk throws part way through", function()
        local fx = helptipFixture()
        local frames, buttons = newSweepWorld(1200, 100, fx.fingerprint)
        local from = #fx.timers + 1

        -- The enumerator itself throwing is the one failure the per-frame guard
        -- cannot absorb: it kills the slice rather than one node.
        local index = {}
        for i, f in ipairs(frames) do index[f] = i end
        local broken = true
        _G.EnumerateFrames = function(prev)
            if prev == nil then return frames[1] end
            local at = index[prev]
            if not at then return nil end
            if broken and at == 700 then error("enumeration blew up") end
            return frames[at + 1]
        end

        fx.AU:ApplySettings()
        pumpSlices(fx, from)
        assert.is_true(countHidden(buttons) < #buttons) -- aborted part way

        broken = false
        fx.AU:ApplySettings() -- an aborted walk is not a finished one
        pumpSlices(fx, from)
        assert.is_true(allHidden(buttons))
    end)

    it("keeps walking when one frame refuses inspection", function()
        local fx = helptipFixture()
        local frames, buttons = newSweepWorld(1200, 100, fx.fingerprint)
        -- 499 is not a multiple of 100, so the refusing frame is not itself one
        -- of the tutorial buttons: every button must still be reached. A
        -- forbidden frame throws on the fingerprint read itself -- the first
        -- thing the inspection does to any frame.
        setmetatable(frames[499], { __index = function() error("no access") end })
        local from = #fx.timers + 1

        fx.AU:ApplySettings()
        pumpSlices(fx, from)
        assert.is_true(allHidden(buttons))
    end)

    it("skips only the button that refuses, not the ones behind it", function()
        local fx = helptipFixture()
        local frames, buttons = newSweepWorld(1200, 100, fx.fingerprint)
        frames[500].CanBeAccessedInContext = function() error("no access") end
        local from = #fx.timers + 1

        fx.AU:ApplySettings()
        pumpSlices(fx, from)
        assert.equals(#buttons - 1, countHidden(buttons))
        assert.equals(1, frames[500].alpha) -- the refusing button, untouched
    end)

    it("retires a queued slice when the feature is switched off mid-walk", function()
        local fx = helptipFixture()
        local _, buttons = newSweepWorld(1200, 100, fx.fingerprint)
        local from = #fx.timers + 1

        fx.AU:ApplySettings()
        -- One slice only, so the rest of the walk is still queued.
        local first = fx.timers[from]
        first.pumped = true
        first.fn()
        assert.is_true(countHidden(buttons) > 0)

        fx.AU.db.HideHelptips = false
        fx.AU:ApplySettings() -- restores what was hidden and retires the walk
        assert.equals(0, countHidden(buttons))

        pumpSlices(fx, from)
        assert.equals(0, countHidden(buttons)) -- the retired slice re-hid nothing
    end)

    it("starts a fresh walk when the feature returns before the retired slice ran", function()
        local fx = helptipFixture()
        local _, buttons = newSweepWorld(1200, 100, fx.fingerprint)
        local from = #fx.timers + 1

        fx.AU:ApplySettings()
        local first = fx.timers[from]
        first.pumped = true
        first.fn()

        fx.AU.db.HideHelptips = false
        fx.AU:ApplySettings()
        fx.AU.db.HideHelptips = true
        fx.AU:ApplySettings() -- must not be refused by the retired walk's guard

        pumpSlices(fx, from)
        assert.is_true(allHidden(buttons))
    end)

    it("keeps a button in the restore set until its restore succeeds", function()
        local fx = helptipFixture()
        local _, buttons = newSweepWorld(400, 100, fx.fingerprint)
        local from = #fx.timers + 1

        fx.AU:ApplySettings()
        pumpSlices(fx, from)
        assert.is_true(allHidden(buttons))

        -- Restoring the mouse is a protected call in game, so it can refuse.
        local stubborn = buttons[2]
        local refusals = 1
        stubborn.EnableMouse = function(self, v)
            if v == true and refusals > 0 then
                refusals = refusals - 1
                error("protected")
            end
            self.mouse = v
        end

        fx.AU.db.HideHelptips = false
        fx.AU:ApplySettings()
        assert.equals(1, stubborn.alpha)  -- alpha went back
        assert.is_false(stubborn.mouse)   -- the mouse did not

        fx.AU:ApplySettings() -- still in the set, so the next pass finishes it
        assert.is_true(stubborn.mouse)
    end)
end)

---------------------------------------------------------------------------------
-- Behaviour 6: per-spell secrecy on the fishing outfit cancel (Task 6)
---------------------------------------------------------------------------------
describe("Automation fishing outfit per-spell secrecy", function()
    -- Same route Behaviour 4's "the fishing channel closure" path uses: obtain
    -- the transform frame via the shared upvalue walk, fire it, then hand back
    -- the queued 0.3s callback for the case to run.
    local function captureFishCancel(fx)
        local applyTransforms = findUpvalue(fx.AU.ApplySettings, "ApplyHideTransforms")
        local fishFrame = findUpvalue(applyTransforms, "transformFishFrame")
        local FISHING_CHANNEL_ID = findUpvalue(applyTransforms, "FISHING_CHANNEL_ID")
        local before = #fx.timers
        fishFrame:Fire("UNIT_SPELLCAST_CHANNEL_STOP", nil, nil, FISHING_CHANNEL_ID)
        for i = before + 1, #fx.timers do
            if fx.timers[i].delay == 0.3 then return fx.timers[i].fn end
        end
    end

    it("exact says secret, broad says readable: the cancel recorder stays empty", function()
        local fx = installedFixture()
        local fn = captureFishCancel(fx)
        assert.is_not_nil(fn)
        fx.KE.AreAuraIdentitiesHidden = function() return false end
        fx.setSecrets({ ShouldSpellAuraBeSecret = function() return true end })
        fn()
        assert.equals(0, #fx.cancels)
    end)

    it("exact says readable, broad says hidden: the cancel recorder has exactly one entry", function()
        local fx = installedFixture()
        local fn = captureFishCancel(fx)
        assert.is_not_nil(fn)
        fx.KE.AreAuraIdentitiesHidden = function() return true end
        fx.setSecrets({ ShouldSpellAuraBeSecret = function() return false end })
        fn()
        assert.equals(1, #fx.cancels)
    end)
end)

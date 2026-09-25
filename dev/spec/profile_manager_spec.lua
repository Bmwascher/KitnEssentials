local L = require("dev.spec._ke_loader")

describe("ProfileManager:RenameProfile", function()
    it("keeps the active profile when renaming a non-active profile", function()
        local PM, _, db = L.loadProfileManager()
        db:SetProfile("A"); db:SetProfile("B"); db:SetProfile("A")
        assert.equal("A", PM:GetCurrentProfile())
        local ok = PM:RenameProfile("B", "C")
        assert.is_true(ok)
        assert.equal("A", PM:GetCurrentProfile())
        assert.is_nil(db.profiles["B"])
        assert.is_table(db.profiles["C"])
    end)

    it("stays on the new name when renaming the active profile", function()
        local PM, _, db = L.loadProfileManager()
        db:SetProfile("A")
        PM:RenameProfile("A", "A2")
        assert.equal("A2", PM:GetCurrentProfile())
        assert.is_nil(db.profiles["A"])
    end)

    it("updates the global-profile pointer when renaming the global profile", function()
        local PM, _, db = L.loadProfileManager()
        db.global.GlobalProfile = "G"
        db:SetProfile("G"); db:SetProfile("Default")
        PM:RenameProfile("G", "G2")
        assert.equal("G2", db.global.GlobalProfile)
    end)
end)

describe("profile operation refresh count", function()
    local function harness()
        local PM, KE, db = L.loadProfileManager()
        local refreshes = 0
        local realRefresh = PM.RefreshAllModules
        PM.RefreshAllModules = function(self, ...)
            refreshes = refreshes + 1
            return realRefresh(self, ...)
        end
        -- Mirror Core/Main.lua's three AceDB callbacks (kept in sync by hand;
        -- Main.lua itself is not headless-loadable).
        local onProfileEvent = function()
            if KE.ProfileManager and not KE.ProfileManager:IsRefreshSuppressed() then
                KE.ProfileManager:RefreshAllModules()
            end
        end
        db.RegisterCallback(KE, "OnProfileChanged", onProfileEvent)
        db.RegisterCallback(KE, "OnProfileCopied", onProfileEvent)
        db.RegisterCallback(KE, "OnProfileReset", onProfileEvent)
        return PM, KE, db, function() return refreshes end
    end

    it("SetProfile refreshes exactly once", function()
        local PM, _, _, count = harness()
        PM:SetProfile("B")
        assert.equal(1, count())
    end)

    it("SetProfile to the current profile refreshes zero times", function()
        local PM, _, _, count = harness()
        PM:SetProfile("Default")
        assert.equal(0, count())
    end)

    it("CreateProfile refreshes zero times and preserves the active profile", function()
        local PM, _, _, count = harness()
        PM:CreateProfile("New")
        assert.equal(0, count())
        assert.equal("Default", PM:GetCurrentProfile())
    end)

    it("CopyProfile to a non-current target refreshes exactly once and restores the active profile", function()
        local PM, _, db, count = harness()
        db.profiles["Src"] = { x = 1 }
        db.profiles["Tgt"] = {}
        PM:CopyProfile("Src", "Tgt")
        assert.equal(1, count())
        assert.equal("Default", PM:GetCurrentProfile())
        assert.equal(1, db.profiles["Tgt"].x)
    end)

    it("RenameProfile refreshes exactly once", function()
        local PM, _, db, count = harness()
        db:SetProfile("B"); db:SetProfile("Default")
        local before = count()
        PM:RenameProfile("B", "C")
        assert.equal(before + 1, count())
    end)

    it("ResetProfile refreshes exactly once", function()
        local PM, _, _, count = harness()
        PM:ResetProfile()
        assert.equal(1, count())
    end)
end)

describe("RefreshAllModules enabled-state sync", function()
    local function fakeModule(name, dbTable)
        local m = {
            name = name, db = dbTable, enabled = false,
            UpdateDB = function() end,
        }
        m.IsEnabled = function(self) return self.enabled end
        m.ApplySettings = function(self) self.applied = (self.applied or 0) + 1 end
        -- Standard KE lifecycle: OnEnable applies its own settings (DragonRiding,
        -- Recuperate, etc.) — the sync loop must NOT apply them a second time.
        m.OnEnable = function(self) self:ApplySettings() end
        return m
    end

    local function harness(mods)
        local PM, KE = L.loadProfileManager()
        KE.ShouldNotLoadModule = function() return false end
        local reg = {}
        for _, m in ipairs(mods) do reg[m.name] = m end
        -- Mirror AceAddon semantics: EnableModule/DisableModule dispatch the
        -- lifecycle methods (AceAddon-3.0.lua), not just a flag flip.
        _G.KitnEssentials = {
            -- Ordered, matching AceAddon's own module list, so an
            -- ordering-sensitive case is deterministic rather than lucky.
            IterateModules = function()
                local i = 0
                return function()
                    i = i + 1
                    local m = mods[i]
                    if m then return m.name, m end
                end
            end,
            EnableModule = function(_, name)
                reg[name].enabled = true
                if reg[name].OnEnable then reg[name]:OnEnable() end
            end,
            DisableModule = function(_, name)
                reg[name].enabled = false
                if reg[name].OnDisable then reg[name]:OnDisable() end
            end,
        }
        return PM, reg, KE
    end

    -- A teardown that reaches a sibling must see the sibling's CURRENT db.
    -- AceDB's SetProfile strips the outgoing profile, so a sibling still
    -- holding the old table reads keys that no longer exist -- while the
    -- non-default flags such a reach usually guards on survive the strip.
    it("rebinds every module's db before any enable or disable runs", function()
        local leaving = fakeModule("A", { Enabled = false })
        leaving.enabled = true
        local sibling = fakeModule("B", { Enabled = false })
        sibling.UpdateDB = function(self) self.db = { Enabled = false, Rebound = true } end
        local seen
        leaving.OnDisable = function() seen = sibling.db.Rebound end
        local PM = harness({ leaving, sibling })
        PM:RefreshAllModules()
        assert.is_true(seen)
    end)

    -- Same guard one step earlier: three HidePreview bodies read self.db, so
    -- stopping previews ahead of the rebind hands them the stripped profile.
    it("stops previews only after the db rebind", function()
        local sibling = fakeModule("B", { Enabled = false })
        sibling.UpdateDB = function(self) self.db = { Enabled = false, Rebound = true } end
        local seen
        local PM, _, KE = harness({ fakeModule("A", { Enabled = false }), sibling })
        KE.PreviewManager = { StopAllPreviews = function() seen = sibling.db.Rebound end }
        PM:RefreshAllModules()
        assert.is_true(seen)
    end)

    it("enables a module the profile marks enabled and disables one it marks disabled", function()
        local on = fakeModule("A", { Enabled = true })
        local off = fakeModule("B", { Enabled = false })
        off.enabled = true
        local PM = harness({ on, off })
        PM:RefreshAllModules()
        assert.is_true(on.enabled)
        assert.is_false(off.enabled)
    end)

    it("applies settings exactly once for newly-enabled and for still-enabled modules", function()
        local newly = fakeModule("A", { Enabled = true })
        local still = fakeModule("B", { Enabled = true })
        still.enabled = true
        local PM = harness({ newly, still })
        PM:RefreshAllModules()
        assert.equal(1, newly.applied)   -- from its own OnEnable only
        assert.equal(1, still.applied)   -- from the sync loop only
    end)

    it("never touches keSelfManagedEnable modules or modules without db.Enabled", function()
        local selfManaged = fakeModule("PC", { Enabled = false })
        selfManaged.keSelfManagedEnable = true
        selfManaged.enabled = true
        local noFlag = fakeModule("Opt", {})
        noFlag.enabled = true
        local PM = harness({ selfManaged, noFlag })
        PM:RefreshAllModules()
        assert.is_true(selfManaged.enabled)
        assert.is_true(noFlag.enabled)
    end)

    it("never live-flips Skin modules; prompts once and skips their ApplySettings", function()
        local skinA = fakeModule("SkinActionBars", { Enabled = false })
        skinA.enabled = true
        local skinB = fakeModule("SkinMicroMenu", { Enabled = false })
        skinB.enabled = true
        local PM, reg, KE = harness({ skinA, skinB })
        local prompts = 0
        KE.SkinningReloadPrompt = function() prompts = prompts + 1 end
        PM:RefreshAllModules()
        assert.is_true(reg["SkinActionBars"].enabled)   -- runtime state untouched
        assert.is_true(reg["SkinMicroMenu"].enabled)
        assert.equal(1, prompts)                        -- once, not per module
        assert.is_nil(skinA.applied)                    -- mismatched profile never applied
        assert.is_nil(skinB.applied)
    end)

    it("skips the SKINNING prompt when ElvUI handles skinning, but still prompts", function()
        local skin = fakeModule("SkinActionBars", { Enabled = true })
        local PM, reg, KE = harness({ skin })
        KE.ShouldNotLoadModule = function() return true end
        local skinPrompts, generic = 0, 0
        KE.SkinningReloadPrompt = function() skinPrompts = skinPrompts + 1 end
        KE.CreateReloadPrompt = function() generic = generic + 1 end
        PM:RefreshAllModules()
        assert.is_false(reg["SkinActionBars"].enabled)
        assert.equal(0, skinPrompts)
        -- A profile operation always prompts; suppressing
        -- the skinning-specific wording does not suppress the prompt itself.
        assert.equal(1, generic)
    end)

    it("prompts for a reload even when no module changed state at all", function()
        local steady = fakeModule("Cursor", { Enabled = true })
        steady.enabled = true
        local PM, _, KE = harness({ steady })
        local skinPrompts, generic = 0, 0
        KE.SkinningReloadPrompt = function() skinPrompts = skinPrompts + 1 end
        KE.CreateReloadPrompt = function() generic = generic + 1 end
        PM:RefreshAllModules()
        assert.equal(0, skinPrompts)
        assert.equal(1, generic)
    end)

    it("issues exactly ONE prompt when a skin change and a reload-deferred module coincide", function()
        local skin = fakeModule("SkinActionBars", { Enabled = false })
        skin.enabled = true
        local deferred = fakeModule("MoveFrames", { Enabled = false })
        deferred.enabled = true
        deferred.keReloadOnDisable = true
        local PM, _, KE = harness({ skin, deferred })
        local skinPrompts, generic = 0, 0
        KE.SkinningReloadPrompt = function() skinPrompts = skinPrompts + 1 end
        KE.CreateReloadPrompt = function() generic = generic + 1 end
        PM:RefreshAllModules()
        -- KE:CreatePrompt stores KE.activePrompt, so a second prompt would
        -- replace the first rather than queue. Never two.
        assert.equal(1, skinPrompts + generic)
    end)

    -- A flag left set would stop the PI pages rebuilding until the next
    -- profile operation.
    it("reports a refresh only while one runs, and clears it when a module errors", function()
        local PM, seen
        local joining = fakeModule("A", { Enabled = true })
        joining.OnEnable = function() seen = PM:IsRefreshingModules() end
        local failing = fakeModule("B", { Enabled = true })
        failing.enabled = true
        failing.ApplySettings = function() error("boom") end
        PM = harness({ joining, failing })
        assert.has_error(function() PM:RefreshAllModules() end)
        assert.is_true(seen)
        assert.is_false(PM:IsRefreshingModules())
    end)
end)

-- The renames run on the imported table before the copy (Core/Defaults.lua
-- KE:MigrateProfileKeys, loaded onto the same KE). Two branches: an old key
-- present is converted; an old key absent is left alone, because the login
-- migration's convert(nil) would overwrite a value already under the new key.
describe("ProfileManager:InstallProfile saved-key renames", function()
    local helpers = require("dev.spec._helpers")

    local function install(profile)
        local PM, KE, db = L.loadProfileManager()
        helpers.loadModule("Core/Defaults.lua", KE)
        local ok, name = PM:InstallProfile(profile, "Imported")
        assert.is_true(ok)
        return db.profiles[name]
    end

    it("converts an old key so nothing un-renamed reaches the profile", function()
        local out = install({ CombatLogger = { ScenarioTorghast = true } })
        assert.is_true(out.CombatLogger.Scenario)
        assert.is_nil(out.CombatLogger.ScenarioTorghast)
    end)

    it("leaves a profile already carrying the new key alone", function()
        local out = install({ CombatLogger = { Scenario = true } })
        assert.is_true(out.CombatLogger.Scenario)
    end)
end)

describe("ProfileManager:DecodeImportString embedded name", function()
    -- The codec is replaced AFTER the load, not seeded before it: the file
    -- defines KE:DecodeFromExport itself. The envelope is handed over as a
    -- table so the case is about the name's type, not the encoding.
    local function decode(envelope)
        local PM, KE = L.loadProfileManager()
        KE.DecodeFromExport = function() return envelope end
        local _, name = PM:DecodeImportString("!KE2!x")
        return name
    end

    it("passes a string name through and drops anything else", function()
        local cases = {
            { name = "Mine", want = "Mine", label = "string" },
            { name = {},     want = nil,    label = "table" },
            { name = nil,    want = nil,    label = "absent" },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.want, decode({ d = {}, _n = c.name }), c.label)
        end
    end)
end)

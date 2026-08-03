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
        -- lifecycle methods (AceAddon-3.0.lua:328,516), not just a flag flip.
        _G.KitnEssentials = {
            IterateModules = function() return pairs(reg) end,
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
        -- A profile operation always prompts (Brandon 2026-08-02); suppressing
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
end)

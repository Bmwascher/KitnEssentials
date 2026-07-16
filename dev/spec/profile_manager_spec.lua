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

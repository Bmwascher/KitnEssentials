-- Tier 2: Core/Globals.lua PreviewManager — enable-toggle preview refresh.
-- OnModuleEnableChanged clears one _moduleStates entry and re-runs the state
-- machine so a module toggled off/on while its GUI section is on screen
-- re-previews immediately (the cache otherwise pins the stale pre-toggle
-- decision until the next section change). Uses the REAL module/section
-- pairing "DragonRiding"/"skinning_section" because PREVIEW_MODULES and
-- SECTION_PREVIEW_MODULES are file locals. The addon shim's GetModule
-- auto-vivifies, so the spec decorates the same table the manager sees.
local L = require("dev.spec._ke_loader")

describe("Core/Globals.lua PreviewManager enable-toggle refresh", function()
    local KE, PM, dr, shown, hidden, inCombat

    before_each(function()
        inCombat = false
        -- UnitClass ("EVOKER") comes from the loader; InCombatLockdown is a
        -- shared-mock override toggled per case via the upvalue.
        KE = L.loadGlobals({
            InCombatLockdown = function() return inCombat end,
        })
        PM = KE.PreviewManager
        shown, hidden = 0, 0
        dr = _G.KitnEssentials:GetModule("DragonRiding")
        dr.db = { Enabled = true }
        dr.ShowPreview = function() shown = shown + 1 end
        dr.HidePreview = function() hidden = hidden + 1 end
        PM.guiOpen = true
        PM:SetActiveSection("skinning_section")
        assert.equals(1, shown)   -- baseline: section activation previews it
    end)

    it("re-previews a module toggled off and back on with its section active", function()
        dr.db.Enabled = false
        PM:OnModuleEnableChanged("DragonRiding")
        assert.equals(1, hidden)  -- disable hides (state bookkeeping, not just OnDisable)

        dr.db.Enabled = true
        PM:OnModuleEnableChanged("DragonRiding")
        assert.equals(2, shown)   -- the fix: no section re-navigation needed
    end)

    it("re-fires ShowPreview even when the cache is stale on 'preview'", function()
        -- Repro of the field bug: disable without PM being told (pre-fix
        -- behavior left the cache at "preview"), then re-enable via the hook.
        PM._moduleStates["DragonRiding"] = "preview"
        dr.db.Enabled = true
        PM:OnModuleEnableChanged("DragonRiding")
        assert.equals(2, shown)
    end)

    it("is a no-op when neither the GUI nor edit mode is showing previews", function()
        PM.guiOpen = false
        PM.editModeActive = false
        PM._moduleStates["DragonRiding"] = "preview"
        PM:OnModuleEnableChanged("DragonRiding")
        assert.equals(1, shown)
        assert.equals(0, hidden)
        -- cache untouched: the method bailed before clearing
        assert.equals("preview", PM._moduleStates["DragonRiding"])
    end)

    it("is a no-op in combat lockdown", function()
        inCombat = true
        PM:OnModuleEnableChanged("DragonRiding")
        assert.equals(1, shown)
        assert.equals(0, hidden)
    end)

    it("keeps the silent no-op for non-applicable classes on enable", function()
        dr.classRestriction = "DRUID"   -- mocked player class is EVOKER
        PM._moduleStates["DragonRiding"] = nil
        PM:OnModuleEnableChanged("DragonRiding")
        assert.equals(1, shown)   -- no new preview forced (project convention)
        assert.equals(1, hidden)  -- state machine parks it hidden instead
    end)
end)

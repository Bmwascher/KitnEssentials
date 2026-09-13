-- Lifecycle spec for LFGReminder's settings pass on enable.
--
-- BuildPopup returns as soon as the popup exists, and its one-time build is
-- the only place the profile's Scale, Pos and ShowDisable reach the frame.
-- ProfileManager skips ApplySettings for modules it just enabled ("newly-
-- enabled modules apply settings inside their own OnEnable"), so a profile
-- switch that turns the module on reaches a popup still configured under the
-- previous profile unless OnEnable itself re-applies. This pins that OnEnable
-- applies the current db to a prebuilt popup, and that LR:ApplySettings (the
-- hook ProfileManager's ON->ON path and Core/Main.lua's PLAYER_ENTERING_WORLD
-- pass call) does the same and stays off the frame in combat, where the
-- popup's anchors are protected through its secure child.
--
-- Loads the REAL Modules/Dungeons/LFGReminder.lua through _ke_loader. The
-- popup is the loader's lfgFrame stub; the spec replaces the three setters
-- it cares about with recorders AFTER the first build, so the assertions are
-- about which db values the module pushes, never about the stub's own
-- behavior.
local loader = require("dev.spec._ke_loader")

describe("LFGReminder OnEnable settings pass", function()
    local LR, seams, popup, applied
    -- The module captures InCombatLockdown at load, so combat is flipped
    -- through the loader's inCombatFn seam rather than _G.
    local inCombat

    -- Builds the popup under the loader's default profile, then swaps in a
    -- new profile table the way ProfileManager's UpdateDB rebind does.
    local function buildThenSwitchProfile(KE, newProfile)
        LR:OnEnable()
        popup = seams.frames["KE_LFGReminderPopup"]
        assert(popup, "first OnEnable did not build the popup")
        applied = {}
        popup.SetScale = function(_, s) applied.scale = s end
        popup.SetHeight = function(_, h) applied.height = h end
        popup.SetPoint = function(_, p, _, rp, x, y)
            applied.point = { p = p, rp = rp, x = x, y = y }
        end
        KE.db.profile.LFGReminder = newProfile
        LR:UpdateDB()
    end

    before_each(function()
        local KE
        inCombat = false
        LR, KE, seams = loader.loadLFGReminder({
            inCombatFn = function() return inCombat end,
        })
        LR.IsEnabled = function() return true end
        buildThenSwitchProfile(KE, {
            Enabled     = true,
            Scale       = 0.8,
            ShowDisable = false,
            Pos         = { p = "TOPLEFT", rp = "TOPLEFT", x = 40, y = -60 },
        })
    end)

    it("re-applies scale, position and the disable row to a prebuilt popup", function()
        LR:OnEnable()
        assert.equals(0.8, applied.scale)
        assert.same({ p = "TOPLEFT", rp = "TOPLEFT", x = 40, y = -60 }, applied.point)
        -- ShowDisable=false trims the window 20px below the full height.
        local trimmed = applied.height
        LR.db.ShowDisable = true
        LR:OnEnable()
        assert.equals(20, applied.height - trimmed)
    end)

    it("ApplySettings reaches the same three setters", function()
        LR:ApplySettings()
        assert.equals(0.8, applied.scale)
        assert.same({ p = "TOPLEFT", rp = "TOPLEFT", x = 40, y = -60 }, applied.point)
        assert.is_number(applied.height)
    end)

    it("ApplySettings leaves the popup alone in combat", function()
        inCombat = true
        LR:ApplySettings()
        assert.same({}, applied)
    end)

    it("does nothing while db.Enabled is off", function()
        LR.db.Enabled = false
        LR:OnEnable()
        assert.same({}, applied)
    end)
end)

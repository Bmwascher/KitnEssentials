-- Tier 1/2: the one-shot retired-font-face clear in MPT:UpdateDB
-- (Modules/Dungeons/MythicPlusTimer/MythicPlusTimer.lua). This module seeds its
-- own defaults straight into the profile instead of registering them with
-- AceDB, so the retired "Expressway" seeds are physically stored in every
-- existing SavedVariables file and would otherwise pin the timer to them
-- forever, defeating the global-font fall-through.
--
-- The ORDERING is the reason this spec exists. MigrateLegacyOverlayDB copies a
-- retired overlay face out of the old forces-overlay table, so the clear has to
-- run after it. Reorder the two blocks and the face resurrects on exactly one
-- login per un-migrated profile and is unreproducible afterwards -- no error,
-- no log line, and the run-once stamp hides it from the next login.
--
-- Loads the REAL module headlessly and stubs only the sibling-file migration,
-- the same seam mpt_reentry_spec stubs.
local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

describe("MPT retired font face clear", function()
    local MPT, KE

    before_each(function()
        mock.install({
            C_Timer = {
                After = function() end,
                NewTicker = function() return { Cancel = function() end } end,
            },
        })
        local modules = helpers.installAddonShim()

        _G.C_ChallengeMode = { GetActiveChallengeMapID = function() return nil end }
        _G.GetInstanceInfo = function() return "Stormwind", "none", 0 end

        KE = helpers.loadModule("Modules/Dungeons/MythicPlusTimer/MythicPlusTimer.lua",
            { Print = function() end, db = { global = {}, profile = {} } })
        MPT = modules["MythicPlusTimer"]
        assert(MPT and MPT.UpdateDB, "real MythicPlusTimer.lua did not load")

        MPT.MigrateLegacyOverlayDB = function() end  -- lives in the Overlay file
    end)

    it("clears every retired face so the timer falls through to the global font", function()
        KE.db.profile.MythicPlusTimer = {
            FontFace = "Expressway", TimerFontFace = "Expressway",
            ForcesFontFace = "Expressway", ObjectiveFontFace = "Expressway",
            DeathsFontFace = "Expressway", OverlayFontFace = "Expressway",
        }
        MPT:UpdateDB()
        for _, key in ipairs({ "FontFace", "TimerFontFace", "ForcesFontFace",
                               "ObjectiveFontFace", "DeathsFontFace", "OverlayFontFace" }) do
            assert.is_nil(MPT.db[key], key .. " should have been cleared")
        end
    end)

    it("leaves a face the user chose alone", function()
        KE.db.profile.MythicPlusTimer = {
            FontFace = "PT Sans Narrow", TimerFontFace = "Expressway",
        }
        MPT:UpdateDB()
        assert.equals("PT Sans Narrow", MPT.db.FontFace)
        assert.is_nil(MPT.db.TimerFontFace)
    end)

    it("runs once, so a retired face picked deliberately survives", function()
        KE.db.profile.MythicPlusTimer = { FontFace = "Expressway" }
        MPT:UpdateDB()

        MPT.db.FontFace = "Expressway"
        MPT:UpdateDB()
        assert.equals("Expressway", MPT.db.FontFace)
    end)

    it("clears a face the legacy overlay migration writes back", function()
        -- The real migration copies the old forces-overlay face into
        -- OverlayFontFace. If the clear ran before it, this would survive.
        MPT.MigrateLegacyOverlayDB = function(self)
            self.db.OverlayFontFace = "Expressway"
        end
        KE.db.profile.MythicPlusTimer = {}
        MPT:UpdateDB()
        assert.is_nil(MPT.db.OverlayFontFace)
    end)

    it("stamps a fresh profile that never carried the seeds", function()
        MPT:UpdateDB()
        assert.is_nil(MPT.db.FontFace)
        assert.is_true(MPT.db.FontFacesCleared)
    end)
end)

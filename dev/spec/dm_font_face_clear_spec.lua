-- Tier 1/2: the one-shot retired-font-face clear in DM:UpdateDB
-- (Modules/DamageMeter/Core.lua). This module seeds its own defaults straight
-- into the profile instead of registering them with AceDB, so the retired
-- "Expressway" seed is physically stored in every existing SavedVariables file
-- and would otherwise pin those profiles to it forever, defeating the
-- global-font fall-through.
--
-- Worth pinning because both failure modes are silent: clear too little and the
-- module never follows the global font; clear too often and a face the user
-- deliberately picks gets wiped on the next login. The run-once stamp is what
-- separates the two, and nothing in game surfaces it.
local L = require("dev.spec._ke_loader")

describe("DamageMeter retired font face clear", function()
    local DM, KE

    before_each(function()
        DM, KE = L.loadDMCore()
        KE.db = { profile = {}, global = {} }
    end)

    it("clears the retired face so the module falls through to the global font", function()
        KE.db.profile.DamageMeter = { FontFace = "Expressway" }
        DM:UpdateDB()
        assert.is_nil(DM.db.FontFace)
    end)

    it("leaves a face the user chose alone", function()
        KE.db.profile.DamageMeter = { FontFace = "PT Sans Narrow" }
        DM:UpdateDB()
        assert.equals("PT Sans Narrow", DM.db.FontFace)
    end)

    it("runs once, so the retired face survives when picked deliberately", function()
        KE.db.profile.DamageMeter = { FontFace = "Expressway" }
        DM:UpdateDB()

        DM.db.FontFace = "Expressway"
        DM:UpdateDB()
        assert.equals("Expressway", DM.db.FontFace)
    end)
end)

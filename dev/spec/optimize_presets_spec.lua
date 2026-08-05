-- Modules/QoL/Optimize.lua -- the preset layer. The cvar TABLES are data and
-- get no assertions here (the tiered test policy skips data tables); what is
-- tested is the branching over them: which value a preset resolves to, and
-- whether a stored preset still describes the live cvars.
local L = require("dev.spec._ke_loader")

-- Sets every cvar in every category to what `balanced` would write, so a test
-- can then move exactly one and see the validation notice.
local function seedBalanced(OPT, rec)
    for _, cat in ipairs(OPT.Categories) do
        for _, entry in ipairs(cat.cvars) do
            rec.cvars[entry.cvar] = entry.optimal
        end
    end
end

local function seedMaxFPS(OPT, rec)
    local ov = OPT:GetMaxFPSOverrides()
    for _, cat in ipairs(OPT.Categories) do
        for _, entry in ipairs(cat.cvars) do
            rec.cvars[entry.cvar] = ov[entry.cvar] or entry.optimal
        end
    end
end

describe("Optimize presets", function()
    describe("the Max FPS override map", function()
        it("maps every raidGraphics cvar onto its base graphics twin", function()
            local OPT = L.loadOptimize()
            local ov = OPT:GetMaxFPSOverrides()
            for _, cat in ipairs(OPT.Categories) do
                if cat.id == "raid" then
                    for _, entry in ipairs(cat.cvars) do
                        local suffix = entry.cvar:match("^raidGraphics(.+)$")
                        if suffix then
                            assert.equals(entry.optimal, ov["graphics" .. suffix])
                        end
                    end
                end
            end
        end)

        it("turns the separate raid profile off and raises the FPS cap", function()
            local OPT = L.loadOptimize()
            local ov = OPT:GetMaxFPSOverrides()
            assert.equals("0", ov["RAIDsettingsEnabled"])
            assert.equals("300", ov["maxFPS"])
        end)

        it("leaves the raidGraphics cvars themselves out of the map", function()
            -- Max FPS lowers the BASE cvars; the raid ones keep their own
            -- listed values, which is why the map is keyed on the base names.
            local OPT = L.loadOptimize()
            assert.is_nil(OPT:GetMaxFPSOverrides()["raidGraphicsShadowQuality"])
        end)
    end)

    describe("applying a preset", function()
        it("balanced writes every listed optimal", function()
            local OPT, rec = L.loadOptimize()
            OPT:ApplyPreset("balanced", nil)
            assert.equals("1", rec.cvars["RAIDsettingsEnabled"])
            assert.equals("200", rec.cvars["maxFPS"])
            assert.equals("3", rec.cvars["graphicsShadowQuality"])
        end)

        it("maxfps writes the override where one exists, the optimal elsewhere", function()
            local OPT, rec = L.loadOptimize()
            OPT:MaxFPS()
            -- Overridden: base shadow quality drops to the Raid & BG value.
            assert.equals("0", rec.cvars["graphicsShadowQuality"])
            assert.equals("0", rec.cvars["RAIDsettingsEnabled"])
            assert.equals("300", rec.cvars["maxFPS"])
            -- Not overridden: still the listed optimal.
            assert.equals("90", rec.cvars["cameraFov"])
        end)

        it("records which preset is now active", function()
            local OPT, rec = L.loadOptimize()
            OPT:OptimizeAll()
            assert.equals("balanced", _G.KitnEssentialsOptimizeDB.ActivePreset)
            OPT:MaxFPS()
            assert.equals("maxfps", _G.KitnEssentialsOptimizeDB.ActivePreset)
            assert.is_true(#rec.prints > 0)
        end)

        it("restores the window mode it found", function()
            -- gxWindow is in no category, so nothing should have changed it --
            -- but the display-mode backup is what guarantees that even if a
            -- future entry did.
            local OPT, rec = L.loadOptimize()
            rec.cvars["gxWindow"] = "1"
            rec.cvars["gxMaximize"] = "0"
            OPT:ApplyPreset("balanced", nil)
            assert.equals("1", rec.cvars["gxWindow"])
            assert.equals("0", rec.cvars["gxMaximize"])
        end)
    end)

    describe("validating the stored preset", function()
        it("returns nil when nothing was ever applied", function()
            local OPT = L.loadOptimize()
            assert.is_nil(OPT:GetActivePreset())
        end)

        it("returns the stored preset while every cvar still matches", function()
            local OPT, rec = L.loadOptimize()
            seedBalanced(OPT, rec)
            _G.KitnEssentialsOptimizeDB = { SavedSettings = {}, ActivePreset = "balanced" }
            assert.equals("balanced", OPT:GetActivePreset())
        end)

        it("keeps balanced through the raid-settings fallback after a hand edit", function()
            local OPT, rec = L.loadOptimize()
            seedBalanced(OPT, rec)
            rec.cvars["graphicsShadowQuality"] = "4"   -- user raised it by hand
            _G.KitnEssentialsOptimizeDB = { SavedSettings = {}, ActivePreset = "balanced" }
            -- RAIDsettingsEnabled is still 1, so this is balanced in spirit.
            assert.equals("balanced", OPT:GetActivePreset())
        end)

        it("drops balanced once the raid split is off as well", function()
            local OPT, rec = L.loadOptimize()
            seedBalanced(OPT, rec)
            rec.cvars["graphicsShadowQuality"] = "4"
            rec.cvars["RAIDsettingsEnabled"] = "0"
            _G.KitnEssentialsOptimizeDB = { SavedSettings = {}, ActivePreset = "balanced" }
            assert.is_nil(OPT:GetActivePreset())
        end)

        it("gives maxfps no fallback at all", function()
            local OPT, rec = L.loadOptimize()
            seedMaxFPS(OPT, rec)
            _G.KitnEssentialsOptimizeDB = { SavedSettings = {}, ActivePreset = "maxfps" }
            assert.equals("maxfps", OPT:GetActivePreset())
            rec.cvars["cameraFov"] = "60"
            assert.is_nil(OPT:GetActivePreset())
        end)

        it("ignores view distance while the Mythic+ override holds it down", function()
            -- Deliberately a maxfps case, and balanced CANNOT replace it.
            -- Balanced's relaxed fallback answers "balanced" on exactly the
            -- states where the exclusion would have, so deleting the exclusion
            -- changes nothing there and a balanced-shaped test would pass
            -- against the very defect it exists to catch. Max FPS has no
            -- fallback, so here the exclusion is the only thing separating
            -- the two answers below.
            local OPT, rec = L.loadOptimize()
            seedMaxFPS(OPT, rec)
            -- A value matching neither preset. The live override forces the
            -- floor instead, but any non-matching value exercises the same
            -- branch and this one cannot be arrived at by accident.
            rec.cvars["graphicsViewDistance"] = "4"
            _G.KitnEssentialsOptimizeDB = {
                SavedSettings = {},
                ActivePreset = "maxfps",
                MythicVD = { active = true, saved = "6" },
            }
            assert.equals("maxfps", OPT:GetActivePreset())
            -- Same state with the override released: the mismatch now counts,
            -- and maxfps has nothing to fall back on.
            _G.KitnEssentialsOptimizeDB.MythicVD.active = false
            assert.is_nil(OPT:GetActivePreset())
        end)
    end)

    describe("applying a preset during an active Mythic+ override", function()
        it("banks the preset's value instead of writing it live", function()
            local OPT, rec = L.loadOptimize()
            _G.KitnEssentialsOptimizeDB = {
                SavedSettings = {},
                MythicVD = { active = true, saved = "3" },
            }
            rec.cvars["graphicsViewDistance"] = "0"
            OPT:ApplyPreset("balanced", nil)
            -- Live value untouched: the key is still holding it at the floor.
            assert.equals("0", rec.cvars["graphicsViewDistance"])
            -- And leaving the key will now restore the preset's value, not the
            -- pre-key one.
            assert.equals("6", _G.KitnEssentialsOptimizeDB.MythicVD.saved)
        end)

        it("does not back the forced value up for revert", function()
            local OPT, rec = L.loadOptimize()
            _G.KitnEssentialsOptimizeDB = {
                SavedSettings = {},
                MythicVD = { active = true, saved = "3" },
            }
            rec.cvars["graphicsViewDistance"] = "0"
            OPT:ApplyPreset("balanced", nil)
            assert.is_nil(_G.KitnEssentialsOptimizeDB.SavedSettings["graphicsViewDistance"])
        end)
    end)

    describe("reverting", function()
        it("clears the recorded preset", function()
            local OPT, rec = L.loadOptimize()
            rec.cvars["cameraFov"] = "70"
            OPT:ApplyPreset("balanced", nil)
            assert.equals("balanced", _G.KitnEssentialsOptimizeDB.ActivePreset)
            OPT:RevertAll()
            assert.is_nil(_G.KitnEssentialsOptimizeDB.ActivePreset)
        end)
    end)

    describe("the Mythic+ view distance override", function()
        local MPLUS = 8   -- Mythic Keystone difficulty

        it("registers no events while the toggle is off", function()
            local OPT, rec = L.loadOptimize()
            OPT:OnInitialize()
            assert.is_nil(rec.events["ZONE_CHANGED_NEW_AREA"])
            assert.is_nil(rec.events["CHALLENGE_MODE_START"])
        end)

        it("registers its four events when the toggle goes on, and drops them again", function()
            local OPT, rec = L.loadOptimize()
            OPT:SetMythicViewDistanceEnabled(true)
            assert.is_true(rec.events["PLAYER_ENTERING_WORLD"])
            assert.is_true(rec.events["ZONE_CHANGED_NEW_AREA"])
            assert.is_true(rec.events["CHALLENGE_MODE_START"])
            assert.is_true(rec.events["CHALLENGE_MODE_COMPLETED"])
            OPT:SetMythicViewDistanceEnabled(false)
            assert.is_nil(rec.events["PLAYER_ENTERING_WORLD"])
            assert.is_nil(rec.events["CHALLENGE_MODE_COMPLETED"])
        end)

        it("drops view distance to the floor on entering a key, remembering the old value", function()
            local OPT, rec = L.loadOptimize()
            rec.cvars["graphicsViewDistance"] = "6"
            OPT:SetMythicViewDistanceEnabled(true)
            rec.difficultyID = MPLUS
            OPT:UpdateMythicViewDistance()
            assert.equals("0", rec.cvars["graphicsViewDistance"])
            assert.equals("6", _G.KitnEssentialsOptimizeDB.MythicVD.saved)
            assert.is_true(OPT:IsMythicOverrideActive())
        end)

        it("restores it on leaving", function()
            local OPT, rec = L.loadOptimize()
            rec.cvars["graphicsViewDistance"] = "6"
            OPT:SetMythicViewDistanceEnabled(true)
            rec.difficultyID = MPLUS
            OPT:UpdateMythicViewDistance()
            rec.difficultyID = 0
            OPT:UpdateMythicViewDistance()
            assert.equals("6", rec.cvars["graphicsViewDistance"])
            assert.is_false(OPT:IsMythicOverrideActive())
        end)

        it("captures the original value once, not once per event", function()
            -- Several of the four events fire on one zone-in. A second capture
            -- would record the floor as the original and lose the real value.
            local OPT, rec = L.loadOptimize()
            rec.cvars["graphicsViewDistance"] = "6"
            OPT:SetMythicViewDistanceEnabled(true)
            rec.difficultyID = MPLUS
            OPT:UpdateMythicViewDistance()
            OPT:UpdateMythicViewDistance()
            OPT:UpdateMythicViewDistance()
            assert.equals("6", _G.KitnEssentialsOptimizeDB.MythicVD.saved)
        end)

        it("survives a reload inside the key and still restores on exit", function()
            -- A reload builds a fresh module against the same SavedVariables.
            local OPT, rec = L.loadOptimize()
            rec.cvars["graphicsViewDistance"] = "6"
            OPT:SetMythicViewDistanceEnabled(true)
            rec.difficultyID = MPLUS
            OPT:UpdateMythicViewDistance()

            local saved = _G.KitnEssentialsOptimizeDB
            local OPT2, rec2 = L.loadOptimize()
            _G.KitnEssentialsOptimizeDB = saved
            rec2.cvars["graphicsViewDistance"] = "0"
            rec2.difficultyID = 0
            OPT2:OnInitialize()
            assert.equals("6", rec2.cvars["graphicsViewDistance"])
            assert.is_false(OPT2:IsMythicOverrideActive())
        end)

        it("releases a held override the moment the toggle goes off", function()
            local OPT, rec = L.loadOptimize()
            rec.cvars["graphicsViewDistance"] = "6"
            OPT:SetMythicViewDistanceEnabled(true)
            rec.difficultyID = MPLUS
            OPT:UpdateMythicViewDistance()
            assert.equals("0", rec.cvars["graphicsViewDistance"])
            OPT:SetMythicViewDistanceEnabled(false)
            assert.equals("6", rec.cvars["graphicsViewDistance"])
        end)

        it("does nothing at all while the toggle is off", function()
            local OPT, rec = L.loadOptimize()
            rec.cvars["graphicsViewDistance"] = "6"
            rec.difficultyID = MPLUS
            OPT:UpdateMythicViewDistance()
            assert.equals("6", rec.cvars["graphicsViewDistance"])
            assert.is_false(OPT:IsMythicOverrideActive())
        end)
    end)
end)

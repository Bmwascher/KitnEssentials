local loader = require("dev.spec._ke_loader")

describe("Modules/Dungeons/LFGQuickCreate.lua", function()

    -- Asserts the REGISTRY module, not the loader's KE table. The module file
    -- returns early when the KitnEssentials global is missing, and a bare
    -- is_table on the KE table would pass anyway -- a test that cannot fail.
    -- Asserts only the two seams: the lifecycle methods do not exist until
    -- Task 6, and the seams already prove the file executed past registration.
    it("registers the module", function()
        local _, _, seams = loader.loadLFGQuickCreate()
        assert.is_function(seams.activeDungeons)
        assert.is_function(seams.currentPlaystyle)
    end)

    describe("ActiveDungeons", function()

        it("falls back to the season-1 slice when the map table is empty", function()
            local _, _, seams = loader.loadLFGQuickCreate({
                C_ChallengeMode = {
                    GetMapTable = function() return {} end,
                    GetMapUIInfo = function() return nil end,
                },
            })
            local list = seams.activeDungeons()
            assert.equals(8, #list)
            assert.equals("windrunner_spire", list[1].key)
            assert.equals("pit_of_saron", list[8].key)
        end)

        it("falls back when the map table is nil", function()
            local _, _, seams = loader.loadLFGQuickCreate({
                C_ChallengeMode = {
                    GetMapTable = function() return nil end,
                    GetMapUIInfo = function() return nil end,
                },
            })
            assert.equals(8, #seams.activeDungeons())
        end)

        it("filters to exactly the live season's dungeons", function()
            -- Three season-2 cmIDs and nothing else.
            local _, _, seams = loader.loadLFGQuickCreate({
                C_ChallengeMode = {
                    GetMapTable = function() return { 588, 249, 585 } end,
                    GetMapUIInfo = function() return nil end,
                },
            })
            local list = seams.activeDungeons()
            assert.equals(3, #list)
            local keys = {}
            for i = 1, #list do keys[list[i].key] = true end
            assert.is_true(keys["altar_of_fangs"])
            assert.is_true(keys["kings_rest"])
            assert.is_true(keys["voidscar_arena"])
            assert.is_nil(keys["skyreach"])
        end)

        it("falls back when the map table matches nothing we know", function()
            local _, _, seams = loader.loadLFGQuickCreate({
                C_ChallengeMode = {
                    GetMapTable = function() return { 99991, 99992 } end,
                    GetMapUIInfo = function() return nil end,
                },
            })
            assert.equals(8, #seams.activeDungeons())
        end)
    end)

    describe("CurrentPlaystyle", function()

        it("prefers the form's own value when it is set", function()
            local _, _, seams = loader.loadLFGQuickCreate({
                LFGListFrame = { EntryCreation = { generalPlaystyle = 3 } },
            })
            assert.equals(3, seams.currentPlaystyle())
        end)

        it("falls back to the saved default when the form value is zero", function()
            local QC, _, seams = loader.loadLFGQuickCreate({
                LFGListFrame = { EntryCreation = { generalPlaystyle = 0 } },
            })
            QC.db = { DefaultPlaystyle = 4 }
            assert.equals(4, seams.currentPlaystyle())
        end)

        it("falls back to the saved default when there is no form at all", function()
            local QC, _, seams = loader.loadLFGQuickCreate()
            QC.db = { DefaultPlaystyle = 2 }
            assert.equals(2, seams.currentPlaystyle())
        end)

        it("returns 0 when neither the form nor a saved default has a value", function()
            local QC, _, seams = loader.loadLFGQuickCreate()
            QC.db = nil
            assert.equals(0, seams.currentPlaystyle())
        end)
    end)

    describe("UpdateDB sanitizer", function()

        local function withPlaystyle(value)
            local QC = loader.loadLFGQuickCreate({
                profile = {
                    LFGQuickCreate = {
                        Enabled = true, QuickCreate = true,
                        DefaultPlaystyle = value, DoubleClickStart = true,
                    },
                },
            })
            QC:UpdateDB()
            return QC.db.DefaultPlaystyle
        end

        it("keeps a valid numeric playstyle", function()
            assert.equals(3, withPlaystyle(3))
        end)

        it("repairs a nonnumeric label value", function()
            assert.equals(1, withPlaystyle("Learning"))
        end)

        it("repairs a value below the enum range", function()
            assert.equals(1, withPlaystyle(0))
        end)

        it("repairs a value above the enum range", function()
            assert.equals(1, withPlaystyle(9))
        end)

        it("repairs a missing value", function()
            assert.equals(1, withPlaystyle(nil))
        end)
    end)
end)

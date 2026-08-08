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

    describe("OwnsKeyFor", function()

        it("matches ownership by map id when available", function()
            local QC = loader.loadLFGQuickCreate()
            local btn = { _mapID = 501, _lfgID = 9999 }
            assert.is_true(QC._OwnsKeyFor(btn, 1234, 501))   -- map match, ids differ
            assert.is_false(QC._OwnsKeyFor(btn, 1234, 502))  -- map mismatch
        end)
        it("falls back to the activity id without a map id", function()
            local QC = loader.loadLFGQuickCreate()
            local btn = { _mapID = nil, _lfgID = 1234 }
            assert.is_true(QC._OwnsKeyFor(btn, 1234, nil))
            assert.is_false(QC._OwnsKeyFor(btn, 5678, nil))
        end)
        it("never matches with no owned key", function()
            local QC = loader.loadLFGQuickCreate()
            assert.is_false(QC._OwnsKeyFor({ _mapID = 501, _lfgID = 1234 }, nil, nil))
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

    describe("OnEnable secret-sender guard (LibKeystone callback)", function()

        -- Same technique as dev/spec/lootroll_spec.lua's local `upvalue`
        -- helper: partyKeys is a file-local in the module with four readers
        -- (LFGQuickCreate.lua) and this callback as a
        -- writer, and no other handle. Reading it off the captured
        -- callback's upvalues observes the real write, without adding a
        -- second production-code surface for it.
        local function upvalue(fn, want)
            local i = 1
            while true do
                local name, value = debug.getupvalue(fn, i)
                if not name then return nil end
                if name == want then return value end
                i = i + 1
            end
        end

        -- Drives QC:OnEnable() with a fake LibKeystone registered through the
        -- loader's overrides.LibStub seam, captures the callback OnEnable
        -- passes to LKS.Register, and returns it along with its partyKeys
        -- upvalue so a test can drive the callback and inspect the result.
        local function enableWithFakeLKS(issecretvalueFn)
            local capturedCallback
            local fakeLKS = {
                Register = function(_, cb) capturedCallback = cb end,
                Unregister = function() end,
                Request = function() end,
            }
            local QC = loader.loadLFGQuickCreate({
                LibStub = { GetLibrary = function() return fakeLKS end },
                issecretvalue = issecretvalueFn,
            })
            -- RegisterEvent is Ace-supplied at runtime; the loader's modules
            -- are bare tables (dev/spec/_ke_loader.lua), so OnEnable's
            -- own RegisterEvent calls need a local stub here.
            QC.RegisterEvent = function() end
            QC:OnEnable()
            assert.is_function(capturedCallback)
            return capturedCallback, upvalue(capturedCallback, "partyKeys")
        end

        it("does not store a key from a secret sender", function()
            local secretSender = { __secret = true }
            local callback, partyKeys = enableWithFakeLKS(
                function(v) return type(v) == "table" and v.__secret == true end)
            callback(10, 500, nil, secretSender, "PARTY")
            assert.is_nil(partyKeys[secretSender])
        end)

        it("stores a key from a clean sender with valid numbers", function()
            local callback, partyKeys = enableWithFakeLKS(
                function(v) return type(v) == "table" and v.__secret == true end)
            callback(10, 500, nil, "Cleansender", "PARTY")
            assert.same({ level = 10, cmID = 500 }, partyKeys["Cleansender"])
        end)

        -- Covers the load-time guard at LFGQuickCreate.lua, never exercised
        -- before. A distinct marker keeps issecretvalue scoped to the
        -- load-time player-name capture (:69), not an unrelated sender.
        it("captures playerShortName as nil when the load-time name is secret", function()
            local secretName = { __secret = true }
            local capturedCallback
            local fakeLKS = {
                Register = function(_, cb) capturedCallback = cb end,
                Unregister = function() end,
                Request = function() end,
            }
            local QC = loader.loadLFGQuickCreate({
                LibStub = { GetLibrary = function() return fakeLKS end },
                UnitNameUnmodified = function() return secretName end,
                issecretvalue = function(v) return v == secretName end,
            })
            QC.RegisterEvent = function() end
            QC:OnEnable()
            assert.is_function(capturedCallback)
            assert.is_nil(upvalue(capturedCallback, "playerShortName"))
        end)
    end)
end)

local loader = require("dev.spec._ke_loader")

describe("Modules/Dungeons/LFGQuickCreate.lua", function()

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

        it("repairs a nonnumeric, out-of-range, or missing playstyle to 1", function()
            for _, value in ipairs({ "Learning", 0, 9 }) do
                assert.equals(1, withPlaystyle(value))
            end
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

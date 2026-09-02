-- Tier 1/2: Modules/QoL/MoveFrames.lua's path resolver and its two public
-- methods (IsRunning, SetMovable). GetFrame is exercised against the REAL _G
-- (the module captures `local _G = _G` at load time, so a stub table swapped
-- in would not be the same object the module walks) -- tests assign directly
-- onto _G and clean up afterward. The frame data tables are linted in
-- dev/spec/lint/moveframes_tables_spec.lua.
local L = require("dev.spec._ke_loader")

describe("MoveFrames.lua", function()
    local MF, seams

    before_each(function()
        local mf, _, s = L.loadMoveFrames()
        MF, seams = mf, s
    end)

    describe("GetFrame", function()
        local getFrame

        before_each(function()
            local _, _, s2 = L.loadMoveFrames()
            getFrame = s2.getFrame
            _G.Alpha = { Beta = { Gamma = {} } }
        end)

        after_each(function()
            _G.Alpha = nil
            _G.NoSuchGlobal = nil
        end)

        it("resolves a single segment", function()
            assert.equal(_G.Alpha, getFrame("Alpha"))
        end)

        it("resolves two segments", function()
            assert.equal(_G.Alpha.Beta, getFrame("Alpha.Beta"))
        end)

        it("resolves three segments", function()
            assert.equal(_G.Alpha.Beta.Gamma, getFrame("Alpha.Beta.Gamma"))
        end)

        it("returns nil without error on a broken mid-path", function()
            assert.is_nil(getFrame("Alpha.Missing.Deep"))
        end)
    end)

    describe("MF:IsRunning", function()
        it("is falsy when db.Enabled is false", function()
            MF.db = { Enabled = false }
            assert.is_falsy(MF:IsRunning())
        end)

        it("is true when db.Enabled is true", function()
            MF.db = { Enabled = true }
            assert.is_true(MF:IsRunning())
        end)

        it("is falsy when db.Enabled is true but StopRunning is set", function()
            MF.db = { Enabled = true }
            MF.StopRunning = "BlizzMove"
            assert.is_falsy(MF:IsRunning())
        end)
    end)

    describe("MF:SetMovable", function()
        local frameStub

        before_each(function()
            frameStub = { GetName = function() end }
        end)

        it("writes nothing while IsRunning() is false", function()
            MF.db = { Enabled = false }
            MF:SetMovable(frameStub, false)
            assert.is_nil(seams.disabled[frameStub])
        end)

        it("marks a frame not-movable", function()
            MF.db = { Enabled = true }
            MF:SetMovable(frameStub, false)
            assert.is_true(seams.disabled[frameStub])
        end)

        it("marks a frame movable again", function()
            MF.db = { Enabled = true }
            MF:SetMovable(frameStub, true)
            assert.is_false(seams.disabled[frameStub])
        end)
    end)
end)

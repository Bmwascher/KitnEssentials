-- Tier 1/2: Modules/QoL/MoveFrames.lua's path resolver and its two public
-- methods (IsRunning, SetMovable). GetFrame is exercised against the REAL _G
-- (the module captures `local _G = _G` at load time, so a stub table swapped
-- in would not be the same object the module walks) -- tests assign directly
-- onto _G and clean up afterward. The frame data tables are linted in
-- dev/spec/lint/moveframes_tables_spec.lua. DragPath is the drag predicate
-- that routes a press to the secure snippet, the native drag, or nothing;
-- MF:SetMovable is also checked for the yield guard that stops a live
-- secure drag on a frame it disables.
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

        it("resolves a dotted path of any depth", function()
            local cases = {
                { path = "Alpha", expect = _G.Alpha },
                { path = "Alpha.Beta", expect = _G.Alpha.Beta },
                { path = "Alpha.Beta.Gamma", expect = _G.Alpha.Beta.Gamma },
            }
            for _, c in ipairs(cases) do
                assert.equal(c.expect, getFrame(c.path))
            end
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

        it("stops a live secure drag on a frame it yields", function()
            MF.db = { Enabled = true }
            seams.secureDrag.frame = frameStub
            MF:SetMovable(frameStub, false)
            assert.is_nil(seams.secureDrag.frame)
        end)
    end)

    describe("ModifierHeld", function()
        it("passes for the configured key only, and always for NONE", function()
            local cases = {
                { modifier = "NONE",  held = nil,     expect = true },
                { modifier = "NONE",  held = "SHIFT", expect = true },
                { modifier = nil,     held = nil,     expect = true },
                { modifier = "SHIFT", held = "SHIFT", expect = true },
                { modifier = "SHIFT", held = "CTRL",  expect = false },
                { modifier = "SHIFT", held = nil,     expect = false },
                { modifier = "CTRL",  held = "CTRL",  expect = true },
                { modifier = "CTRL",  held = nil,     expect = false },
                { modifier = "ALT",   held = "ALT",   expect = true },
                { modifier = "ALT",   held = "SHIFT", expect = false },
            }
            for _, c in ipairs(cases) do
                local function down(key) return function() return c.held == key end end
                local shift = down("SHIFT")
                local _, _, s = L.loadMoveFrames({
                    IsShiftKeyDown = shift, IsControlKeyDown = down("CTRL"), IsAltKeyDown = down("ALT"),
                })
                -- The module captures these at load; a loader that routed them
                -- through the managed mock would drop the override silently.
                assert.equal(shift, _G.IsShiftKeyDown)
                assert.equal(c.expect, s.modifierHeld(c.modifier),
                    tostring(c.modifier) .. " with " .. tostring(c.held) .. " held")
            end
        end)
    end)

    describe("DragPath", function()
        it("routes a press to the secure drag, the native drag, or nothing", function()
            local cases = {
                -- button, modifierHeld, protected, inCombat, isDisabled, expect
                { "RightButton", true,  false, false, nil,  nil,      "right button" },
                { "LeftButton",  false, false, false, nil,  nil,      "modifier not held" },
                { "LeftButton",  true,  true,  false, true, nil,      "yielded frame, even protected" },
                { "LeftButton",  true,  true,  true,  nil,  nil,      "protected in combat" },
                { "LeftButton",  true,  true,  false, nil,  "secure", "protected out of combat" },
                { "LeftButton",  true,  false, false, nil,  "native", "ordinary frame" },
                { "LeftButton",  true,  false, true,  nil,  "native", "ordinary frame in combat" },
            }
            for _, c in ipairs(cases) do
                assert.equal(c[6], seams.dragPath(c[1], c[2], c[3], c[4], c[5]), c[7])
            end
        end)
    end)
end)

local loader = require("dev.spec._ke_loader")

describe("Modules/QoL/CopyAnything.lua", function()

    describe("CheckModifiers", function()
        local checkModifiers

        describe("no modifier configured", function()
            before_each(function()
                local ctrlFn = function() return false end
                local _, _, seams = loader.loadCopyAnything({ IsControlKeyDown = ctrlFn })
                -- IsControlKeyDown is unmanaged; confirm the loader's
                -- assignment actually stuck rather than trusting silence.
                assert.equals(ctrlFn, _G.IsControlKeyDown)
                checkModifiers = seams.checkModifiers
            end)

            it("returns true for a nil mod", function()
                assert.is_true(checkModifiers(nil))
            end)
        end)

        describe("ctrl held down", function()
            before_each(function()
                local ctrlFn = function() return true end
                local shiftFn = function() return false end
                local _, _, seams = loader.loadCopyAnything({
                    IsControlKeyDown = ctrlFn,
                    IsShiftKeyDown = shiftFn,
                })
                assert.equals(ctrlFn, _G.IsControlKeyDown)
                assert.equals(shiftFn, _G.IsShiftKeyDown)
                checkModifiers = seams.checkModifiers
            end)

            it("returns true for mod = 'ctrl'", function()
                assert.is_true(checkModifiers("ctrl"))
            end)

            it("returns false for mod = 'ctrl+shift' when shift is not down", function()
                assert.is_false(checkModifiers("ctrl+shift"))
            end)
        end)

        describe("ctrl not held down", function()
            before_each(function()
                local ctrlFn = function() return false end
                local _, _, seams = loader.loadCopyAnything({ IsControlKeyDown = ctrlFn })
                assert.equals(ctrlFn, _G.IsControlKeyDown)
                checkModifiers = seams.checkModifiers
            end)

            it("returns false for mod = 'ctrl'", function()
                assert.is_false(checkModifiers("ctrl"))
            end)
        end)
    end)

    describe("GetNPCIDFromGUID", function()
        local getNPCIDFromGUID

        before_each(function()
            local _, _, seams = loader.loadCopyAnything()
            getNPCIDFromGUID = seams.getNPCIDFromGUID
        end)

        it("extracts the NPC id from a creature GUID", function()
            assert.equals("112233", getNPCIDFromGUID("Creature-0-1234-5-6-112233-000012ABCD"))
        end)

        it("returns nil for a nil guid", function()
            assert.is_nil(getNPCIDFromGUID(nil))
        end)

        it("returns nil for a GUID with too few segments", function()
            assert.is_nil(getNPCIDFromGUID("Creature-0-1234"))
        end)
    end)
end)

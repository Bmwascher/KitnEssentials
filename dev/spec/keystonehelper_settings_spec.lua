-- The two reminders used to share one appearance block. They now each own
-- ten keys, with a switch that parks Your Key on the Reroll position. That
-- resolution is invented branching logic, and a copy-pasted prefix in the
-- second apply path would be invisible in game until someone set the two
-- reminders differently. Every fixture value below differs between the two
-- prefixes so a wrong prefix cannot pass by coincidence.
local L = require("dev.spec._ke_loader")

describe("KeystoneHelper: per-feature settings resolution", function()
    -- The loader's third return, KE, is not asserted on and is simply dropped.
    -- Naming it would be an unused local, which luacheck rejects, and `_` would
    -- write a global the allowlist hides.
    local KH, rec

    -- Distinct on every key. Shared values would let a wrong prefix pass.
    local function baseDB()
        return {
            Enabled = true,
            ResetEnabled = true,
            ResetMessage = "Instance reset!",
            RerollEnabled = true,
            YourKeyEnabled = true,

            YourKeyUseRerollPosition = true,

            RerollSize = 64,
            RerollFontFace = "RerollFont",
            RerollFontOutline = "OUTLINE",
            RerollFontSize = 30,
            RerollFontColor = { 1, 0, 0, 1 },
            RerollFontColorKey = { 1, 0.5, 0, 1 },
            RerollStrata = "HIGH",
            RerollAnchorFrameType = "PLAYERFRAME",
            RerollParentFrame = "PlayerFrame",
            RerollPosition = { AnchorFrom = "TOP", AnchorTo = "TOP", XOffset = 10, YOffset = 20 },

            YourKeySize = 96,
            YourKeyFontFace = "YourKeyFont",
            YourKeyFontOutline = "THICKOUTLINE",
            YourKeyFontSize = 48,
            YourKeyFontColor = { 0, 1, 0, 1 },
            YourKeyFontColorKey = { 0, 0.5, 1, 1 },
            YourKeyStrata = "LOW",
            YourKeyAnchorFrameType = "SCREEN",
            YourKeyParentFrame = "SomeOtherFrame",
            YourKeyPosition = { AnchorFrom = "BOTTOM", AnchorTo = "BOTTOM", XOffset = 30, YOffset = 40 },

            RerollGlowEnabled = false,
            YourKeyGlowEnabled = false,
        }
    end

    before_each(function()
        KH, rec = L.loadKeystoneHelper()
        KH.db = baseDB()
        -- ApplySettings reaches AceHook; the shim module table has none.
        KH.IsHooked = function() return true end
        KH:CreateRerollFrame()
        KH:CreateYourKeyFrame()
    end)

    describe("resolution", function()
        it("gives Reroll its own ten values", function()
            local s = KH:ResolveReminderSettings("Reroll")
            assert.equals(64, s.size)
            assert.equals("RerollFont", s.fontFace)
            assert.equals("OUTLINE", s.fontOutline)
            assert.equals(30, s.fontSize)
            assert.equals(KH.db.RerollFontColor, s.fontColor)
            assert.equals(KH.db.RerollFontColorKey, s.fontColorKey)
            assert.equals("HIGH", s.strata)
            assert.equals("PLAYERFRAME", s.anchorFrameType)
            assert.equals("PlayerFrame", s.parentFrame)
            assert.equals(KH.db.RerollPosition, s.position)
        end)

        it("never lets Your Key's values leak into Reroll", function()
            KH.db.YourKeyUseRerollPosition = false
            local s = KH:ResolveReminderSettings("Reroll")
            assert.equals(64, s.size)
            assert.equals("RerollFont", s.fontFace)
            assert.equals(KH.db.RerollPosition, s.position)
            assert.equals("HIGH", s.strata)
        end)

        it("gives Your Key its own look even while it follows the position", function()
            local s = KH:ResolveReminderSettings("YourKey")
            assert.equals(96, s.size)
            assert.equals("YourKeyFont", s.fontFace)
            assert.equals("THICKOUTLINE", s.fontOutline)
            assert.equals(48, s.fontSize)
            assert.equals(KH.db.YourKeyFontColor, s.fontColor)
            assert.equals(KH.db.YourKeyFontColorKey, s.fontColorKey)
        end)

        it("resolves the Reroll position for Your Key while following", function()
            local s = KH:ResolveReminderSettings("YourKey")
            assert.equals(KH.db.RerollPosition, s.position)
            assert.equals("PLAYERFRAME", s.anchorFrameType)
            assert.equals("PlayerFrame", s.parentFrame)
            assert.equals("HIGH", s.strata)
        end)

        it("resolves Your Key's own position once the follow is off", function()
            KH.db.YourKeyUseRerollPosition = false
            local s = KH:ResolveReminderSettings("YourKey")
            assert.equals(KH.db.YourKeyPosition, s.position)
            assert.equals("SCREEN", s.anchorFrameType)
            assert.equals("SomeOtherFrame", s.parentFrame)
            assert.equals("LOW", s.strata)
        end)
    end)

    describe("the apply path consumes the resolver", function()
        -- Resolution being right proves nothing if ApplyReminderSettings
        -- still reads KH.db. These read what actually reached the frame.
        it("places each frame with its resolved position and strata", function()
            KH.db.YourKeyUseRerollPosition = false
            KH:ApplyRerollSettings()
            KH:ApplyYourKeySettings()

            local byFrame = {}
            for _, call in ipairs(rec.positions) do byFrame[call.frame] = call end

            local reroll = byFrame[KH.rerollFrame]
            assert.is_not_nil(reroll)
            assert.equals(KH.db.RerollPosition, reroll.position)
            assert.equals("HIGH", reroll.opts.Strata)
            assert.equals("PLAYERFRAME", reroll.opts.anchorFrameType)

            local yourKey = byFrame[KH.yourKeyFrame]
            assert.is_not_nil(yourKey)
            assert.equals(KH.db.YourKeyPosition, yourKey.position)
            assert.equals("LOW", yourKey.opts.Strata)
            assert.equals("SCREEN", yourKey.opts.anchorFrameType)
        end)

        it("parks Your Key on the Reroll position while following", function()
            KH:ApplyYourKeySettings()
            local last = rec.positions[#rec.positions]
            assert.equals(KH.yourKeyFrame, last.frame)
            assert.equals(KH.db.RerollPosition, last.position)
        end)

        it("fonts each frame from its own block", function()
            KH:ApplyRerollSettings()
            KH:ApplyYourKeySettings()

            local faces = {}
            for _, call in ipairs(rec.fonts) do faces[call.face] = (faces[call.face] or 0) + 1 end
            -- Title and key line each get one call per frame.
            assert.equals(2, faces["RerollFont"])
            assert.equals(2, faces["YourKeyFont"])
        end)

        it("stashes each frame's own font size for the key-line icon", function()
            -- The icon is sized off this number. The multiply-and-round is
            -- unchanged code; what is new is WHICH size reaches it.
            KH:ApplyRerollSettings()
            KH:ApplyYourKeySettings()
            assert.equals(30, KH.rerollFrame.keFontSize)
            assert.equals(48, KH.yourKeyFrame.keFontSize)
        end)
    end)
end)

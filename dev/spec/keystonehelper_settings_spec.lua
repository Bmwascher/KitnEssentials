-- The two reminders share one appearance block, one position and one Edit
-- Mode mover. What a later edit breaks silently: a drag that reaches only one
-- frame, a second mover creeping back, the preview picking the wrong frame
-- (or none) for the switches that are on, a reminder going live under the
-- other one's preview and landing on the same pixels, and a live start that
-- dies on a retired method before it arms its watch. Layout, snap and glow
-- are in-game checks.
--
-- Show/Hide on the mock frames are replaced by recorders because the harness
-- frame swallows both; the two lifecycle cases read `_shown`.
local L = require("dev.spec._ke_loader")

describe("KeystoneHelper: shared look", function()
    local KH, rec, events

    local function baseDB()
        return {
            Enabled = true,
            ResetEnabled = true,
            ResetMessage = "Instance reset!",
            RerollEnabled = true,
            YourKeyEnabled = true,

            Size = 64,
            FontFace = "SharedFont",
            FontOutline = "OUTLINE",
            FontSize = 30,
            FontColor = { 1, 0, 0, 1 },
            FontColorKey = { 1, 0.5, 0, 1 },
            Strata = "HIGH",
            AnchorFrameType = "PLAYERFRAME",
            ParentFrame = "PlayerFrame",
            Position = { AnchorFrom = "TOP", AnchorTo = "TOP", XOffset = 10, YOffset = 20 },

            GlowEnabled = false,
        }
    end

    local function trackVisibility(frame)
        frame.Show = function(f) f._shown = true end
        frame.Hide = function(f) f._shown = false end
    end

    before_each(function()
        KH, rec = L.loadKeystoneHelper()
        KH.db = baseDB()
        events = {}
        -- The shim module table carries no AceHook, AceEvent or AceAddon
        -- lifecycle; the four the code paths under test reach are stubbed.
        KH.IsHooked = function() return true end
        KH.IsEnabled = function() return true end
        KH.RegisterEvent = function(_, event) events[event] = true end
        KH.UnregisterEvent = function(_, event) events[event] = nil end
        KH:CreateRerollFrame()
        KH:CreateYourKeyFrame()
        trackVisibility(KH.rerollFrame)
        trackVisibility(KH.yourKeyFrame)
    end)

    describe("Edit Mode", function()
        local function registeredKeys()
            local keys = {}
            for key in pairs(rec.editMode.registered) do keys[#keys + 1] = key end
            table.sort(keys)
            return keys
        end

        it("registers one mover for both reminders, bound to the Reroll frame", function()
            KH.db.RerollEnabled = false
            KH:ApplySettings()
            assert.are.same({ "KeystoneHelper" }, registeredKeys())
            assert.equals(KH.rerollFrame, rec.editMode.registered.KeystoneHelper.frame)
        end)

        it("places both frames on the dragged position", function()
            KH:ApplySettings()
            local element = rec.editMode.registered.KeystoneHelper
            local dragged = { AnchorFrom = "LEFT", AnchorTo = "LEFT", XOffset = 7, YOffset = 8 }
            local before = #rec.positions
            element.setPosition(dragged)

            assert.equals(dragged, KH.db.Position)
            local placed = {}
            for i = before + 1, #rec.positions do
                local call = rec.positions[i]
                assert.equals(dragged, call.position)
                assert.equals("HIGH", call.opts.Strata)
                placed[call.frame] = true
            end
            assert.is_true(placed[KH.rerollFrame])
            assert.is_true(placed[KH.yourKeyFrame])
        end)
    end)

    describe("preview frame", function()
        -- One row per switch state; the frame and title are what the page
        -- shows, nil means no preview at all.
        it("follows the switches: Reroll first, then Your Key, then nothing", function()
            local cases = {
                { reroll = true,  yourKey = true,  frame = "rerollFrame",  title = "REROLL KEY?" },
                { reroll = true,  yourKey = false, frame = "rerollFrame",  title = "REROLL KEY?" },
                { reroll = false, yourKey = true,  frame = "yourKeyFrame", title = "Your Key?" },
                { reroll = false, yourKey = false, frame = nil,            title = nil },
            }
            for _, c in ipairs(cases) do
                KH.db.RerollEnabled = c.reroll
                KH.db.YourKeyEnabled = c.yourKey
                local frame, title = KH:PreviewFrame()
                assert.equals(c.frame and KH[c.frame] or nil, frame,
                    ("reroll=%s yourKey=%s"):format(tostring(c.reroll), tostring(c.yourKey)))
                assert.equals(c.title, title)
            end
        end)

        it("keeps a Your Key that goes live under the Reroll preview hidden until the preview closes", function()
            KH:ShowPreview()
            KH:ShowYourKey()
            assert.is_true(KH.yourKeyActive)
            assert.is_false(KH.yourKeyFrame._shown)

            KH:HidePreview()
            assert.is_true(KH.yourKeyFrame._shown)
        end)
    end)

    describe("live start", function()
        it("shows the Reroll frame and arms the item-change watch", function()
            _G.C_ChallengeMode.GetChallengeCompletionInfo = function()
                return { onTime = true, level = 10 }
            end
            _G.C_MythicPlus.GetOwnedKeystoneLevel = function() return 10 end
            KH:StartRerollTimer()
            assert.is_true(KH.rerollActive)
            assert.is_true(KH.rerollFrame._shown)
            assert.is_true(events.ITEM_CHANGED)
        end)
    end)
end)

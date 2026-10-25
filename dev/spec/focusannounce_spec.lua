-- Modules/DungeonTools/KicksCasts/FocusAnnounce.lua: the party chat line parser and its refusals.
-- The addon message formats are thin wrappers over a pattern and Blizzard's encoding API,
-- checked in review and by the smoke.
local L = require("dev.spec._ke_loader")

describe("FocusAnnounce chat line parser", function()
    it("reads each wording and marker form", function()
        local FA = L.loadFocusAnnounce()
        local rows = {
            { name = "the Focus Kick wording", text = "My Focus Kick is {rt4}", want = 4 },
            { name = "the Focus Marker wording", text = "My Focus Marker is {rt7}", want = 7 },
            { name = "an old line with a marker name", text = "My Focus Marker is {Star}", want = 1 },
            { name = "a marker name in lower case", text = "My Focus Marker is {skull}", want = 8 },
            { name = "a mixed-case phrase with spaces", text = "  my FOCUS marker IS {Triangle} ", want = 4 },
        }
        for _, row in ipairs(rows) do
            assert.equals(row.want, FA.ParseLine(row.text), row.name)
        end
    end)
end)

describe("FocusAnnounce refusals", function()
    it("refuses a line or addon message in a key, a non-teammate, a secret or malformed line, a wrong channel", function()
        local FA = L.loadFocusAnnounce()
        local GOOD = "My Focus Marker is {rt4}"
        -- args: text, textSecret, chatLocked, fromTeammate
        local rows = {
            { name = "a teammate's plain line before a key", args = { GOOD, false, false, true }, want = 4 },
            { name = "chat locked (in a key)", args = { GOOD, false, true, true } },
            { name = "secret text", args = { GOOD, true, false, true } },
            { name = "not a teammate", args = { GOOD, false, false, false } },
            { name = "no token", args = { "My Focus Marker is", false, false, true } },
            { name = "two tokens", args = { "My Focus Marker is {rt4}{rt5}", false, false, true } },
            { name = "rt0", args = { "My Focus Marker is {rt0}", false, false, true } },
            { name = "rt9", args = { "My Focus Marker is {rt9}", false, false, true } },
            { name = "a padded rt04", args = { "My Focus Marker is {rt04}", false, false, true } },
            { name = "an unknown name", args = { "My Focus Marker is {Banana}", false, false, true } },
            { name = "another phrase", args = { "My Focus Target is {rt4}", false, false, true } },
        }
        for _, row in ipairs(rows) do
            assert.equals(row.want, FA.ReadLine(unpack(row.args)), row.name)
        end
        -- The same refusals for addon messages. args: prefix, channel, chatLocked, fromTeammate
        local addonRows = {
            { name = "a teammate's EUIKT on PARTY before a key", args = { "EUIKT", "PARTY", false, true }, want = false },
            { name = "a teammate's MDT message on INSTANCE_CHAT", args = { "MDTFocusMark", "INSTANCE_CHAT", false, true },
              want = false },
            { name = "an addon message in a key", args = { "EUIKT", "PARTY", true, true }, want = true },
            { name = "an addon message from a non-teammate", args = { "MDTFocusMark", "PARTY", false, false }, want = true },
            { name = "EUIKT off PARTY", args = { "EUIKT", "INSTANCE_CHAT", false, true }, want = true },
            { name = "a whispered MDT message", args = { "MDTFocusMark", "WHISPER", false, true }, want = true },
            { name = "another prefix", args = { "OTHER", "PARTY", false, true }, want = true },
        }
        for _, row in ipairs(addonRows) do
            assert.equals(row.want, FA.AddonRefused(unpack(row.args)), row.name)
        end
    end)
end)

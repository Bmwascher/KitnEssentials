-- Tier 1: Modules/Skinning/ChatCopyText.lua. One table-driven case per byte
-- class. Each row is { input, expected, label }; string.char builds the bytes.
local L = require("dev.spec._ke_loader")

local c = string.char

describe("SanitizeCopyLine", function()
    local sanitize

    before_each(function()
        sanitize = L.loadChatCopyText()
    end)

    local function check(rows)
        for _, r in ipairs(rows) do
            assert.are.equal(r[2], sanitize(r[1]), r[3])
        end
    end

    it("drops C0 controls, NUL and DEL", function()
        check({
            { "a" .. c(1) .. "b", "ab", "byte 1" },
            { "a" .. c(31) .. "b", "ab", "byte 31" },
            { "a" .. c(0) .. "b", "ab", "NUL" },
            { "a" .. c(127) .. "b", "ab", "DEL" },
        })
    end)

    it("keeps LF when the byte walk runs", function()
        check({
            { "a\nb" .. c(1), "a\nb", "LF beside a dropped byte" },
        })
    end)

    it("replaces a byte that starts no valid sequence with ?", function()
        check({
            { "a" .. c(255) .. "b", "a?b", "byte 255" },
            { "a" .. c(194), "a?", "lone 194 at the end" },
            { "a" .. c(194) .. "b", "a?b", "194 before ASCII" },
            { "a" .. c(0x80) .. "b", "a?b", "stray continuation" },
            { c(0xC0) .. "A", "?A", "C0 lead" },
            { c(0xC1) .. "A", "?A", "C1 lead" },
            { c(0xF5) .. "A", "?A", "F5 lead" },
        })
    end)

    it("rejects a lead whose second byte is out of range", function()
        check({
            { c(0xE0, 0x80, 0x80), "???", "E0 80" },
            { c(0xED, 0xA0, 0x80), "???", "ED A0" },
            { c(0xF0, 0x80, 0x80, 0x80), "????", "F0 80" },
            { c(0xF4, 0x90, 0x80, 0x80), "????", "F4 90" },
        })
    end)

    it("writes one ? per bad byte and resumes at the next byte", function()
        check({
            { "x" .. c(0xE2, 0x82), "x??", "truncated 3-byte sequence at the end" },
            { c(0xE2) .. "A", "?A", "3-byte lead before ASCII" },
        })
    end)

    it("passes valid UTF-8 and the pipe byte through the byte walk", function()
        local valid = "a"
            .. c(0xC3, 0xA9)
            .. c(0xE2, 0x82, 0xAC)
            .. c(0xE0, 0xA0, 0x80)
            .. c(0xED, 0x9F, 0xBF)
            .. c(0xF0, 0x9F, 0x98, 0x80)
            .. c(0xF4, 0x8F, 0xBF, 0xBF)
            .. "|cffff0000x|r||"
        check({
            { valid .. c(1), valid, "2-, 3- and 4-byte characters, range edges, pipes" },
        })
    end)

    it("returns a line with nothing to fix unchanged", function()
        check({
            { "plain |cffffffffline|r ||", "plain |cffffffffline|r ||", "clean line unchanged" },
        })
    end)
end)

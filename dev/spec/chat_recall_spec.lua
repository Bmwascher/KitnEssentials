-- Tier 1: Modules/Skinning/ChatRecall.lua. Two guard rules, one case each,
-- table-driven over the literal that varies:
--   stores  — secure commands and empty lines stay out of the history
--   refused — a linked line is refused only while chat is restricted
local L = require("dev.spec._ke_loader")

local SECURE = { ["/ping"] = true, ["/cast"] = true }
local function isSecureCmd(cmd) return SECURE[cmd] == true end

describe("ChatRecall", function()
    local stores, refused
    before_each(function()
        stores, refused = L.loadChatRecall(isSecureCmd)
    end)

    it("keeps secure commands and empty lines out of the history", function()
        local cases = {
            { "hello there", true },
            { "/dance", true },
            { "/ping", false },
            { "  /cast Fireball", false },
            { "", false },
            { nil, false },
        }
        for _, c in ipairs(cases) do
            assert.are.equal(c[2], stores(c[1]), tostring(c[1]))
        end
    end)

    it("refuses a linked line only while restricted", function()
        local linked = "look |Hitem:19019|h[Thunderfury]|h"
        local cases = {
            { linked, true, true },
            { linked, false, false },
            { "plain text", true, false },
            { nil, true, false },
        }
        for _, c in ipairs(cases) do
            assert.are.equal(c[3], refused(c[1], c[2]), tostring(c[1]) .. "/" .. tostring(c[2]))
        end
    end)
end)

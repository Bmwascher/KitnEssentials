-- Tier 1: Modules/Skinning/Chat.lua, CHAT.EditBoxRightInset. The header hook
-- that calls it, and the secret insets themselves, are in-game only.
local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })

local function loadChat()
    mock.install({ issecretvalue = function(v) return v == SECRET end })
    local modules = helpers.installAddonShim()
    helpers.loadModule("Modules/Skinning/Chat.lua", {})
    return modules["Chat"]
end

describe("CHAT.EditBoxRightInset", function()
    after_each(function()
        mock.reset()
    end)

    it("refuses when any of the four insets is secret", function()
        local CHAT = loadChat()
        local cases = {
            { SECRET, 13, 0, 0 },
            { 40, SECRET, 0, 0 },
            { 40, 13, SECRET, 0 },
            { 40, 13, 0, SECRET },
        }
        for i, c in ipairs(cases) do
            assert.is_nil(CHAT.EditBoxRightInset(c[1], c[2], c[3], c[4], nil), "secret at " .. i)
        end
    end)

    it("widens the right inset by 30 unless it is the value this hook last wrote", function()
        local CHAT = loadChat()
        local cases = {
            { right = 13, written = nil, want = 43 },
            { right = 13, written = 43,  want = 43 },
            { right = 43, written = 43,  want = nil },
        }
        for _, c in ipairs(cases) do
            assert.equal(c.want, CHAT.EditBoxRightInset(40, c.right, 0, 0, c.written),
                "right=" .. c.right .. " written=" .. tostring(c.written))
        end
    end)
end)

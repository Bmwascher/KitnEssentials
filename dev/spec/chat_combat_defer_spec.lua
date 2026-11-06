-- Tier 2: Modules/Skinning/Chat/Chat.lua, the combat deferral in CHAT:PositionChat
-- and CHAT:FlushPendingChats. The re-anchor itself is in-game only.
local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

describe("CHAT combat deferral", function()
    after_each(function()
        mock.reset()
    end)

    it("repositions every window deferred in combat, the dock primary first", function()
        local inCombat = true
        mock.install({ InCombatLockdown = function() return inCombat end })
        local modules = helpers.installAddonShim()
        helpers.loadModule("Modules/Skinning/Chat/Chat.lua", helpers.loadModule("Core/Colors.lua", {}))
        local CHAT = modules["Chat"]

        local docker, log, other = {}, {}, {}
        _G.GeneralDockManager = { primary = docker }
        local handler
        CHAT.RegisterEvent = function(_, event, method)
            assert.equal("PLAYER_REGEN_ENABLED", event)
            handler = method
        end
        CHAT.UnregisterEvent = function(_, event) if event == "PLAYER_REGEN_ENABLED" then handler = nil end end
        CHAT.panel = {}

        CHAT:PositionChat(docker)
        CHAT:PositionChat(log)
        CHAT:PositionChat(other)
        CHAT:PositionChat(log)

        local placed = {}
        local positionChat = CHAT.PositionChat
        CHAT.PositionChat = function(_, chat) placed[#placed + 1] = chat end
        inCombat = false
        if type(handler) == "string" then CHAT[handler](CHAT) else handler() end
        CHAT.PositionChat = positionChat

        assert.equal(3, #placed)
        assert.equal(docker, placed[1])
        local rest = { [placed[2]] = true, [placed[3]] = true }
        assert.is_true(rest[log] and rest[other])
        assert.is_nil(handler)
    end)
end)

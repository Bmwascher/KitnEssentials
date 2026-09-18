-- Tier 2: Modules/Skinning/Chat.lua, CHAT:ApplyGuildMemberStatus. The filter's
-- rewrite of a system line is in-game only.
local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

describe("CHAT:ApplyGuildMemberStatus", function()
    after_each(function()
        _G.ChatFrameUtil = nil
        mock.reset()
    end)

    it("marks the filter active only once it registers, so a failed apply is retried once", function()
        mock.install({})
        local modules = helpers.installAddonShim()
        helpers.loadModule("Modules/Skinning/Chat.lua", {})
        local CHAT = modules["Chat"]
        CHAT.db = { GuildMemberStatus = true }
        CHAT.SecureHook = function() end

        _G.ChatFrameUtil = nil
        CHAT:ApplyGuildMemberStatus()

        local adds = 0
        _G.ChatFrameUtil = { AddMessageEventFilter = function() adds = adds + 1 end }
        CHAT:ApplyGuildMemberStatus()
        CHAT:ApplyGuildMemberStatus()

        assert.equal(1, adds)
    end)
end)

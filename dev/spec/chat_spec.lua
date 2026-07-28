-- Tier 2: Modules/Skinning/ChatMessageHandler.lua. GetPFlag is pure string
-- logic -- no WoW API -- so it unit-tests directly.
local L = require("dev.spec._ke_loader")

describe("ChatMessageHandler:GetPFlag", function()
    local KE
    before_each(function()
        KE = L.loadChatMessageHandler()
    end)

    it("returns an empty string when there is no special flag", function()
        assert.equals("", KE.ChatMessageHandler:GetPFlag(nil))
        assert.equals("", KE.ChatMessageHandler:GetPFlag(""))
    end)

    it("returns the exact Blizzard icon for GM and DEV", function()
        local expected = "|TInterface\\ChatFrame\\UI-ChatIcon-Blizz:12:20:0:0:32:16:4:28:0:16|t "
        assert.equals(expected, KE.ChatMessageHandler:GetPFlag("GM"))
        assert.equals(expected, KE.ChatMessageHandler:GetPFlag("DEV"))
    end)

    it("returns the exact guide icon for GUIDE", function()
        assert.equals("|TInterface\\ChatFrame\\UI-ChatIcon-Guide:12:12:0:0|t ",
            KE.ChatMessageHandler:GetPFlag("GUIDE"))
    end)

    it("returns the exact newcomer icon for NEWCOMER", function()
        assert.equals("|TInterface\\ChatFrame\\UI-ChatIcon-Newcomer:12:12:0:0|t ",
            KE.ChatMessageHandler:GetPFlag("NEWCOMER"))
    end)

    it("returns an empty string for an unrecognised flag", function()
        assert.equals("", KE.ChatMessageHandler:GetPFlag("SOMETHING_ELSE"))
    end)
end)

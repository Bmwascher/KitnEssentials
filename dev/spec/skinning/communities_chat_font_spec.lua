-- Modules/Skinning/Frames/Communities.lua -- ChatPaneFontSize.
--
-- Nothing else reaches this pane: StyleChat only walks CHAT_FRAMES, and KE
-- sets chat fonts with a direct SetFont, so Blizzard's own sync never fires
-- from KE. The skin reads the chat size itself -- but only while the Chat
-- module is enabled, because it ships off and its size would otherwise be
-- stamped over one Blizzard derived.

local L = require("dev.spec._ke_loader")

describe("Communities chat pane font size", function()
    local ChatPaneFontSize, KE

    before_each(function()
        ChatPaneFontSize, KE = L.loadCommunitiesSkin()
    end)

    local function setChat(tbl)
        KE.db = { profile = { Skinning = { Chat = tbl } } }
    end

    it("asks for no size while the Chat module is disabled", function()
        setChat({ Enabled = false, FontSize = 14 })
        assert.is_nil(ChatPaneFontSize())
    end)

    it("asks for the Chat module's size while it is enabled", function()
        setChat({ Enabled = true, FontSize = 16 })
        assert.equals(16, ChatPaneFontSize())
    end)

    it("treats a non-positive configured size as absent", function()
        for _, size in ipairs({ 0, -1 }) do
            setChat({ Enabled = true, FontSize = size })
            assert.is_nil(ChatPaneFontSize())
        end
    end)
end)

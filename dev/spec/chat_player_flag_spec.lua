-- Modules/Skinning/ChatMessageHandler.lua: the player flag rule. CMH.PlayerFlag
-- reads no game state, so the cases call it directly; the last case covers the
-- saved setting through CMH:GetPFlag.
local L = require("dev.spec._ke_loader")

local BLIZZ = "|TInterface\\ChatFrame\\UI-ChatIcon-Blizz:12:20:0:0:32:16:4:28:0:16|t "
local GUIDE = "|TInterface\\ChatFrame\\UI-ChatIcon-Guide:12:12:0:0|t "
local NEWCOMER = "|TInterface\\ChatFrame\\UI-ChatIcon-Newcomer:12:12:0:0|t "
local DISCORD = "|A:UI-ChatIcon-Discord:0:0:0:0|a "
local AFK = "[|cffFF9900AFK|r] "
local DND = "[|cffFF3333DND|r] "

describe("ChatMessageHandler player flag", function()
    local KE, CMH

    before_each(function()
        KE = L.loadChatMessageHandler()
        CMH = KE.ChatMessageHandler
    end)

    it("routes each known flag to its own tag", function()
        local cases = {
            { "GM", BLIZZ }, { "DEV", BLIZZ }, { "GUIDE", GUIDE }, { "NEWCOMER", NEWCOMER },
            { "DISCORD", DISCORD }, { "AFK", AFK }, { "DND", DND },
        }
        for _, c in ipairs(cases) do
            assert.are.equal(c[2], CMH.PlayerFlag(c[1], true), c[1])
        end
    end)

    it("blanks only AFK and DND when the tags are off", function()
        local cases = { { "AFK", "" }, { "DND", "" }, { "GM", BLIZZ }, { "DISCORD", DISCORD } }
        for _, c in ipairs(cases) do
            assert.are.equal(c[2], CMH.PlayerFlag(c[1], false), c[1])
        end
    end)

    it("returns nothing for no flag or an unknown flag", function()
        assert.are.equal("", CMH.PlayerFlag(nil, true))
        for _, flag in ipairs({ "", "COM" }) do
            assert.are.equal("", CMH.PlayerFlag(flag, true), flag)
        end
    end)

    it("shows the tag when the saved key is absent and hides it when false", function()
        local db = KE.db.profile.Skinning.Chat
        db.AFKDNDTags = nil
        assert.are.equal(AFK, CMH:GetPFlag("AFK"))
        db.AFKDNDTags = false
        assert.are.equal("", CMH:GetPFlag("AFK"))
    end)
end)

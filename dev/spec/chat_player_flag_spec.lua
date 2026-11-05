-- Modules/Skinning/Chat/ChatMessageHandler.lua: the player flag rule. CMH.PlayerFlag
-- reads no game state, so most cases call it directly; the saved setting and the
-- mentor flags go through CMH:GetPFlag.
local L = require("dev.spec._ke_loader")

local BLIZZ = "|TInterface\\ChatFrame\\UI-ChatIcon-Blizz:12:20:0:0:32:16:4:28:0:16|t "
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
            { "GM", BLIZZ }, { "DEV", BLIZZ }, { "DISCORD", DISCORD }, { "AFK", AFK }, { "DND", DND },
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

    describe("mentor flags", function()
        local saved, calls, answer

        before_each(function()
            saved = _G.ChatFrameUtil
            calls = {}
            answer = "TAG"
            _G.ChatFrameUtil = {
                GetPFlag = function(flag, zoneChannelID)
                    calls[#calls + 1] = { flag, zoneChannelID }
                    return answer
                end,
            }
        end)

        after_each(function() _G.ChatFrameUtil = saved end)

        it("takes each mentor tag from Blizzard's rule with the zone channel", function()
            for i, flag in ipairs({ "GUIDE", "NEWCOMER" }) do
                assert.are.equal("TAG", CMH:GetPFlag(flag, 7), flag)
                assert.are.same({ flag, 7 }, calls[i])
            end
        end)

        it("reads a nil answer from the rule as no tag", function()
            answer = nil
            assert.are.equal("", CMH:GetPFlag("NEWCOMER", 7))
        end)

        it("refuses without calling the rule when the line has no channel ID", function()
            for _, flag in ipairs({ "GUIDE", "NEWCOMER" }) do
                assert.are.equal("", CMH:GetPFlag(flag, nil), flag)
            end
            assert.are.equal(0, #calls)
        end)
    end)
end)

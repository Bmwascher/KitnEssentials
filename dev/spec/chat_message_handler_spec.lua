local L = require("dev.spec._ke_loader")

describe("ChatMessageHandler achievement merging", function()
    local KE, CMH, frame, lines
    local INFO = { r = 0.25, g = 1, b = 0.25, id = 3 }
    local MSG = "%s earned |Hachievement:123:|h[Thing]|h!"

    before_each(function()
        KE = L.loadChatMessageHandler()
        CMH = KE.ChatMessageHandler
        KE.db.profile.Skinning.Chat.MergeAchievements = true
        CMH.ResetAchievements()
        lines = {}
        frame = { AddMessage = function(_, msg) table.insert(lines, msg) end }
    end)

    it("captures a mergeable line instead of printing it", function()
        assert.is_true(CMH:CaptureAchievement(frame, "CHAT_MSG_GUILD_ACHIEVEMENT", INFO, MSG, "Ana"))
        assert.are.equal(0, #lines)
    end)

    it("replays one player unchanged, in Blizzard's own wording", function()
        CMH:CaptureAchievement(frame, "CHAT_MSG_GUILD_ACHIEVEMENT", INFO, MSG, "Ana")
        CMH.FlushAchievements()
        assert.are.equal(1, #lines)
        assert.are.equal("Ana earned |Hachievement:123:|h[Thing]|h!", lines[1])
    end)

    it("collapses several players into one label line, sorted", function()
        CMH:CaptureAchievement(frame, "CHAT_MSG_GUILD_ACHIEVEMENT", INFO, MSG, "Zed")
        CMH:CaptureAchievement(frame, "CHAT_MSG_GUILD_ACHIEVEMENT", INFO, MSG, "Ana")
        CMH.FlushAchievements()
        assert.are.equal(1, #lines)
        assert.are.equal("|Hachievement:123:|h[Thing]|h Earned by Ana, Zed", lines[1])
    end)

    it("never names the same player twice", function()
        CMH:CaptureAchievement(frame, "CHAT_MSG_GUILD_ACHIEVEMENT", INFO, MSG, "Ana")
        CMH:CaptureAchievement(frame, "CHAT_MSG_GUILD_ACHIEVEMENT", INFO, MSG, "Ana")
        CMH.FlushAchievements()
        assert.are.equal(1, #lines)
        assert.are.equal("Ana earned |Hachievement:123:|h[Thing]|h!", lines[1])
    end)

    it("keeps the two events apart", function()
        CMH:CaptureAchievement(frame, "CHAT_MSG_GUILD_ACHIEVEMENT", INFO, MSG, "Ana")
        CMH:CaptureAchievement(frame, "CHAT_MSG_ACHIEVEMENT", INFO, MSG, "Bo")
        CMH.FlushAchievements()
        assert.are.equal(2, #lines)
    end)

    it("refuses when the feature is off", function()
        KE.db.profile.Skinning.Chat.MergeAchievements = false
        assert.is_nil(CMH:CaptureAchievement(frame, "CHAT_MSG_GUILD_ACHIEVEMENT", INFO, MSG, "Ana"))
    end)

    it("keeps the icon the incoming filter prepended", function()
        local decorated = "%s earned |Tint:14:14|t |Hachievement:123:|h[Thing]|h!"
        CMH:CaptureAchievement(frame, "CHAT_MSG_GUILD_ACHIEVEMENT", INFO, decorated, "Zed")
        CMH:CaptureAchievement(frame, "CHAT_MSG_GUILD_ACHIEVEMENT", INFO, decorated, "Ana")
        CMH.FlushAchievements()
        assert.are.equal("|Tint:14:14|t |Hachievement:123:|h[Thing]|h Earned by Ana, Zed", lines[1])
    end)

    it("does not swallow an unrelated texture or the prose before the link", function()
        local noisy = "%s |Traid:14|t before |Hachievement:123:|h[Thing]|h!"
        CMH:CaptureAchievement(frame, "CHAT_MSG_GUILD_ACHIEVEMENT", INFO, noisy, "Zed")
        CMH:CaptureAchievement(frame, "CHAT_MSG_GUILD_ACHIEVEMENT", INFO, noisy, "Ana")
        CMH.FlushAchievements()
        assert.are.equal("|Hachievement:123:|h[Thing]|h Earned by Ana, Zed", lines[1])
    end)

    it("pairs the link with its own achievement id", function()
        local two = "%s got |Hachievement:111:|h[A]|h and |Tint:14:14|t |Hachievement:222:|h[B]|h!"
        CMH:CaptureAchievement(frame, "CHAT_MSG_GUILD_ACHIEVEMENT", INFO, two, "Zed")
        CMH:CaptureAchievement(frame, "CHAT_MSG_GUILD_ACHIEVEMENT", INFO, two, "Ana")
        CMH.FlushAchievements()
        assert.are.equal("|Hachievement:111:|h[A]|h Earned by Ana, Zed", lines[1])
    end)

    it("refuses a message carrying no achievement link", function()
        assert.is_nil(CMH:CaptureAchievement(frame, "CHAT_MSG_GUILD_ACHIEVEMENT", INFO, "%s did a thing", "Ana"))
    end)

    -- CaptureAchievement refuses; the branch prints the body raw rather than
    -- merging it.
    it("refuses a secret body so the caller prints it unmerged", function()
        local KE2 = L.loadChatMessageHandler({ issecretvalue = function(v) return v == "SECRET" end })
        KE2.db.profile.Skinning.Chat.MergeAchievements = true
        assert.is_nil(KE2.ChatMessageHandler:CaptureAchievement(
            frame, "CHAT_MSG_GUILD_ACHIEVEMENT", INFO, "SECRET", "Ana"))
    end)

    it("refuses a secret player link so the caller prints it", function()
        local KE2 = L.loadChatMessageHandler({ issecretvalue = function(v) return v == "SECRET" end })
        KE2.db.profile.Skinning.Chat.MergeAchievements = true
        assert.is_nil(KE2.ChatMessageHandler:CaptureAchievement(
            frame, "CHAT_MSG_GUILD_ACHIEVEMENT", INFO, MSG, "SECRET"))
    end)
end)

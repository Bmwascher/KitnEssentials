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

    it("keeps the colour the client wrapped the link in", function()
        local coloured = "%s earned |cffffff00|Hachievement:123:|h[Thing]|h|r!"
        CMH:CaptureAchievement(frame, "CHAT_MSG_GUILD_ACHIEVEMENT", INFO, coloured, "Zed")
        CMH:CaptureAchievement(frame, "CHAT_MSG_GUILD_ACHIEVEMENT", INFO, coloured, "Ana")
        CMH.FlushAchievements()
        assert.are.equal("|cffffff00|Hachievement:123:|h[Thing]|h|r Earned by Ana, Zed", lines[1])
    end)

    it("keeps the colour around an icon the incoming filter prepended", function()
        -- The filter inserts the icon INSIDE the colour scope, so a merged line
        -- that carries only the icon prints the title in the channel's colour.
        local both = "%s earned |cffffff00|Tint:14:14|t |Hachievement:123:|h[Thing]|h|r!"
        CMH:CaptureAchievement(frame, "CHAT_MSG_GUILD_ACHIEVEMENT", INFO, both, "Zed")
        CMH:CaptureAchievement(frame, "CHAT_MSG_GUILD_ACHIEVEMENT", INFO, both, "Ana")
        CMH.FlushAchievements()
        assert.are.equal(
            "|cffffff00|Tint:14:14|t |Hachievement:123:|h[Thing]|h|r Earned by Ana, Zed", lines[1])
    end)

    it("refuses an unterminated link rather than borrowing the next one's text", function()
        -- A message filter can hand this branch text the client would never
        -- send. With a lazy body the first id ran through the SECOND link's
        -- |h terminators and the merged line reported achievement 111 wearing
        -- achievement 222's name. Refusing is the correct outcome: the line
        -- then prints unmerged rather than merged and wrong.
        local broken = "%s got |cffffff00|Hachievement:111:broken " ..
            "|Hachievement:222:|h[B]|h|r"
        assert.is_nil(CMH:CaptureAchievement(frame, "CHAT_MSG_GUILD_ACHIEVEMENT", INFO, broken, "Ana"))
    end)

    it("still pairs a coloured link with its own achievement id", function()
        local two = "%s got |cffffff00|Hachievement:111:|h[A]|h|r and " ..
            "|cffffff00|Tint:14:14|t |Hachievement:222:|h[B]|h|r!"
        CMH:CaptureAchievement(frame, "CHAT_MSG_GUILD_ACHIEVEMENT", INFO, two, "Zed")
        CMH:CaptureAchievement(frame, "CHAT_MSG_GUILD_ACHIEVEMENT", INFO, two, "Ana")
        CMH.FlushAchievements()
        assert.are.equal("|cffffff00|Hachievement:111:|h[A]|h|r Earned by Ana, Zed", lines[1])
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
    --
    -- The flagged body is MSG itself, not a bare "SECRET". A body with no
    -- achievement link would be refused by the no-link check further down, so
    -- the case would pass with the secret guard deleted and would constrain
    -- nothing. Flagging a body that WOULD otherwise capture is what makes the
    -- assertion falsifiable.
    it("refuses a secret body so the caller prints it unmerged", function()
        local KE2 = L.loadChatMessageHandler({ issecretvalue = function(v) return v == MSG end })
        KE2.db.profile.Skinning.Chat.MergeAchievements = true
        assert.is_nil(KE2.ChatMessageHandler:CaptureAchievement(
            frame, "CHAT_MSG_GUILD_ACHIEVEMENT", INFO, MSG, "Ana"))
    end)

    it("refuses a secret player link so the caller prints it", function()
        local KE2 = L.loadChatMessageHandler({ issecretvalue = function(v) return v == "SECRET" end })
        KE2.db.profile.Skinning.Chat.MergeAchievements = true
        assert.is_nil(KE2.ChatMessageHandler:CaptureAchievement(
            frame, "CHAT_MSG_GUILD_ACHIEVEMENT", INFO, MSG, "SECRET"))
    end)
end)

describe("ChatMessageHandler Battle.net player link", function()
    local KE, CMH, frame, info

    before_each(function()
        KE = L.loadChatMessageHandler()
        CMH = KE.ChatMessageHandler
        frame = { defaultLanguage = "Common" }
        info = {}
        _G.CHAT_BN_WHISPER_GET = "%s tells you: "
    end)

    after_each(function()
        _G.CHAT_BN_WHISPER_GET = nil
    end)

    -- arg13 is the id GetBNPlayerLink needs. A live message always carries
    -- one; replay carries one only when the stored BattleTag matched a
    -- current friend.
    local function formatBody(arg13)
        return CMH:MessageFormatter(frame, info, "BN_WHISPER", "BN_WHISPER", "target", 0, "Godling",
            "hello", "Godling", nil, nil, nil, nil, nil, nil, nil, nil, 11, nil, arg13, nil, nil, nil, nil)
    end

    it("links the sender when an id is present", function()
        local body = formatBody(42)
        assert.is_truthy(body:find("|HBNplayer:", 1, true))
    end)

    -- This is the mechanism the no-match replay branch depends on: GetLink
    -- concatenates whatever it is handed, so a nil id yields a malformed link
    -- rather than none, and skipping the call is the only way to omit one.
    it("omits the link and falls back to the plain name when the id is nil", function()
        local body = formatBody(nil)
        assert.is_falsy(body:find("|HBNplayer:", 1, true))
        assert.is_truthy(body:find("Godling", 1, true))
    end)
end)

describe("ChatMessageHandler body highlight", function()
    local KE, CMH, played

    local function setChat(t)
        KE.db.profile.Skinning.Chat = t
    end

    -- Playback needs BOTH a LibStub returning an LSM and a Fetch that yields a
    -- path. Without this fixture every sound assertion passes for the wrong
    -- reason, because nothing could ever have played.
    local function installSound()
        played = false
        _G.PlaySoundFile = function() played = true end
        _G.LibStub = function() return { Fetch = function() return "sound.ogg" end } end
    end

    before_each(function()
        KE = L.loadChatMessageHandler()
        CMH = KE.ChatMessageHandler
        CMH.ResetHighlight()
        setChat({ HighlightKeywords = "", ClassColorMentions = false, HighlightSound = "None" })
    end)

    -- Both of these are installed per case and neither is reinstalled by the
    -- loader, so a case that leaves one standing changes what every later case
    -- runs against -- which is exactly how a spec passes for the wrong reason.
    -- Cleanup belongs here rather than at the end of a case body, because a
    -- failing assertion skips the rest of the body and the leak survives.
    after_each(function()
        _G.KitnEssentials = nil
        _G.GetNormalizedRealmName = nil
        -- installSound's LibStub is not reinstalled by the loader either, so it
        -- would otherwise outlive this file and hand a working Fetch to any
        -- later spec that forgot to stub one.
        _G.LibStub = nil
    end)

    describe("ParseList", function()
        it("trims each token at both ends", function()
            local set = CMH.ParseList("a , b ,c")
            assert.is_true(set.a); assert.is_true(set.b); assert.is_true(set.c)
        end)

        it("expands the name token", function()
            assert.is_true(CMH.ParseList("%MYNAME%").kitn)
        end)

        it("drops empty tokens", function()
            local n = 0
            for _ in pairs(CMH.ParseList("a,,  ,b")) do n = n + 1 end
            assert.are.equal(2, n)
        end)
    end)

    describe("keywords", function()
        it("colours a keyword and preserves its casing", function()
            setChat({ HighlightKeywords = "kitn", HighlightColor = { 1, 0, 0 }, HighlightSound = "None" })
            assert.is_truthy(CMH.Highlight("hey Kitn there"):find("|cffff0000Kitn|r", 1, true))
        end)

        it("does not match inside a word", function()
            setChat({ HighlightKeywords = "kit", HighlightColor = { 1, 0, 0 }, HighlightSound = "None" })
            assert.are.equal("kitten", CMH.Highlight("kitten"))
        end)

        it("does not rewrite inside a hyperlink label", function()
            setChat({ HighlightKeywords = "thing", HighlightColor = { 1, 0, 0 }, HighlightSound = "None" })
            local text = "|Hitem:1|h[Thing]|h"
            assert.are.equal(text, CMH.Highlight(text))
        end)

        it("prefers the longer of two hits starting at the same byte", function()
            setChat({ HighlightKeywords = "foo,foo bar", HighlightColor = { 1, 0, 0 }, HighlightSound = "None" })
            assert.is_truthy(CMH.Highlight("foo bar"):find("|cffff0000foo bar|r", 1, true))
        end)
    end)

    describe("colour-span protection", function()
        it("leaves text that is already coloured alone", function()
            setChat({ HighlightKeywords = "ana", HighlightColor = { 1, 0, 0 }, HighlightSound = "None" })
            local text = "|cff00ff00Ana tail|r"
            assert.are.equal(text, CMH.Highlight(text))
        end)

        it("keeps a nested span closed until its outer reset", function()
            setChat({ HighlightKeywords = "ana", HighlightColor = { 1, 0, 0 }, HighlightSound = "None" })
            local text = "|cffff0000outer |cff00ff00inner|r Ana|r"
            assert.are.equal(text, CMH.Highlight(text))
        end)

        it("still colours a match outside the span", function()
            setChat({ HighlightKeywords = "ana", HighlightColor = { 1, 0, 0 }, HighlightSound = "None" })
            assert.is_truthy(CMH.Highlight("|cff00ff00x|r Ana"):find("|cffff0000Ana|r", 1, true))
        end)

        -- The boss-monster path concatenates the body into a format string, so
        -- splitting an escaped pair there makes format throw.
        it("refuses a hit overlapping an escaped percent pair", function()
            setChat({ HighlightKeywords = "50%", HighlightColor = { 1, 0, 0 } })
            local text = "the boss is at 50%% health"
            assert.are.equal(text, CMH.Highlight(text))
        end)
    end)

    describe("mentions", function()
        before_each(function()
            _G.KitnEssentials = {
                GetModule = function()
                    return { ClassNames = { ana = "MAGE", ["ana-realm"] = "MAGE" } }
                end,
            }
            CMH.ResetHighlight()
        end)

        it("colours a known name", function()
            setChat({ HighlightKeywords = "", ClassColorMentions = true, ExcludedMentions = "", HighlightSound = "None" })
            assert.is_truthy(CMH.Highlight("ping Ana please"):find("Ana|r", 1, true))
        end)

        it("honours the exclusion list", function()
            setChat({ HighlightKeywords = "", ClassColorMentions = true, ExcludedMentions = "Ana", HighlightSound = "None" })
            assert.are.equal("ping Ana please", CMH.Highlight("ping Ana please"))
        end)

        it("prefers the realm-qualified name", function()
            setChat({ HighlightKeywords = "", ClassColorMentions = true, ExcludedMentions = "", HighlightSound = "None" })
            assert.is_truthy(CMH.Highlight("ping Ana-Realm"):find("Ana-Realm|r", 1, true))
        end)

        it("does not fall back to the short name when the long one is excluded", function()
            setChat({ HighlightKeywords = "", ClassColorMentions = true, ExcludedMentions = "Ana-Realm", HighlightSound = "None" })
            assert.are.equal("ping Ana-Realm", CMH.Highlight("ping Ana-Realm"))
        end)
    end)

    describe("sound", function()
        it("plays on a keyword match", function()
            installSound()
            setChat({ HighlightKeywords = "kitn", HighlightColor = { 1, 0, 0 }, HighlightSound = "Bell" })
            CMH.Highlight("kitn")
            assert.is_true(played)
        end)

        it("stays silent when no sound is chosen", function()
            installSound()
            setChat({ HighlightKeywords = "kitn", HighlightColor = { 1, 0, 0 }, HighlightSound = "None" })
            CMH.Highlight("kitn")
            assert.is_false(played)
        end)

        it("refuses in combat when asked to", function()
            installSound()
            _G.InCombatLockdown = function() return true end
            setChat({ HighlightKeywords = "kitn", HighlightColor = { 1, 0, 0 },
                      HighlightSound = "Bell", HighlightNoSoundInCombat = true })
            CMH.Highlight("kitn")
            assert.is_false(played)
        end)

        it("stays silent on your own message", function()
            installSound()
            setChat({ HighlightKeywords = "kitn", HighlightColor = { 1, 0, 0 }, HighlightSound = "Bell" })
            CMH.Highlight("kitn", "Kitn")
            assert.is_false(played)
        end)

        it("stays silent on your own message carrying a realm", function()
            installSound()
            setChat({ HighlightKeywords = "kitn", HighlightColor = { 1, 0, 0 }, HighlightSound = "Bell" })
            CMH.Highlight("kitn", "Kitn-Ravencrest")
            assert.is_false(played)
        end)

        it("plays for your own name on another realm", function()
            installSound()
            setChat({ HighlightKeywords = "kitn", HighlightColor = { 1, 0, 0 }, HighlightSound = "Bell" })
            CMH.Highlight("kitn", "Kitn-Stormrage")
            assert.is_true(played)
        end)

        -- A sender's realm suffix carries no spaces; UnitFullName's does.
        -- Without the stripping these two spellings never match and the user
        -- dings on every one of her own messages.
        it("stays silent on your own message from a multi-word realm", function()
            installSound()
            _G.UnitFullName = function() return "Kitn", "Twisting Nether" end
            setChat({ HighlightKeywords = "kitn", HighlightColor = { 1, 0, 0 }, HighlightSound = "Bell" })
            CMH.Highlight("kitn", "Kitn-TwistingNether")
            assert.is_false(played)
        end)

        it("stays silent on your own message from a parenthesised realm", function()
            installSound()
            _G.UnitFullName = function() return "Kitn", "Aggra (Português)" end
            setChat({ HighlightKeywords = "kitn", HighlightColor = { 1, 0, 0 }, HighlightSound = "Bell" })
            CMH.Highlight("kitn", "Kitn-AggraPortuguês")
            assert.is_false(played)
        end)

        -- The two stubs must DISAGREE. Stubbing both to the same realm would
        -- leave this case green even if the code ignored
        -- GetNormalizedRealmName outright, which is a test that cannot fail on
        -- the behaviour it is named after.
        it("prefers GetNormalizedRealmName when the client offers it", function()
            installSound()
            _G.UnitFullName = function() return "Kitn", "Somewhere Else" end
            _G.GetNormalizedRealmName = function() return "TwistingNether" end
            setChat({ HighlightKeywords = "kitn", HighlightColor = { 1, 0, 0 }, HighlightSound = "Bell" })
            CMH.Highlight("kitn", "Kitn-TwistingNether")
            assert.is_false(played)
        end)

        it("still colours your own message", function()
            installSound()
            setChat({ HighlightKeywords = "kitn", HighlightColor = { 1, 0, 0 }, HighlightSound = "Bell" })
            assert.is_truthy(CMH.Highlight("kitn", "Kitn"):find("|cffff0000kitn|r", 1, true))
        end)

        it("plays for somebody else", function()
            installSound()
            setChat({ HighlightKeywords = "kitn", HighlightColor = { 1, 0, 0 }, HighlightSound = "Bell" })
            CMH.Highlight("kitn", "Ana")
            assert.is_true(played)
        end)

        it("throttles to one play every five seconds", function()
            installSound()
            local now = 0
            _G.GetTime = function() return now end
            setChat({ HighlightKeywords = "kitn", HighlightColor = { 1, 0, 0 }, HighlightSound = "Bell" })

            CMH.Highlight("kitn")
            assert.is_true(played)

            played, now = false, 4
            CMH.Highlight("kitn")
            assert.is_false(played)

            now = 6
            CMH.Highlight("kitn")
            assert.is_true(played)
        end)
    end)
end)

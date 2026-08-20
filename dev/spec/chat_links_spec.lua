-- Tier 1: Modules/Skinning/ChatLinks.lua. Covers the secret refusal and the
-- keystone pattern. The other five decorators are ports checked by diff and in
-- game; where they differ from the source, the plan's deviations list is what
-- enumerates it.
local L = require("dev.spec._ke_loader")

local DB = {
    Enabled = true, Icon = true, IconHeight = 14, IconWidth = 14,
    KeepRatio = true, NumericalQualityTier = true,
    WebAddresses = true, WebAddressColor = { 0.31, 0.71, 1 },
}

local function freshDB()
    local t = {}
    for k, v in pairs(DB) do t[k] = v end
    return t
end

local KEYSTONE = "|cnIQ4:|Hkeystone:180653:399:2:165:0:0:0:0"
    .. "|h[Keystone: Ruby Life Pools (2)]|h|r"
local ICON_4321 = "|T4321:14:14:0:0:64:64:5:59:5:59|t"
local ITEM = "|cnIQ4:|Hitem:240949::::::::90:1480"
    .. "|h[Ring |A:Professions-ChatIcon-Quality-Tier5:17:15::1|a]|h|r"
local ICON_9999 = "|T9999:14:14:0:0:64:64:5:59:5:59|t"

describe("ChatLinks filter", function()
    local CL
    before_each(function()
        CL = L.loadChatLinks()
        CL.db = freshDB()
        _G.C_ChallengeMode = { GetMapUIInfo = function() return nil, nil, nil, 4321 end }
        _G.C_Item = { GetItemInfoInstant = function()
            return 240949, "Armor", "Miscellaneous", "INVTYPE_FINGER", 9999
        end }
    end)

    it("passes a plain message through unchanged when nothing matches", function()
        local _, out = CL:Filter("CHAT_MSG_SAY", "hello")
        assert.equal("hello", out)
    end)

    it("matches a live keystone link, which the colour-prefixed pattern does not", function()
        local _, out = CL:Filter("CHAT_MSG_SAY", KEYSTONE)
        assert.equal("|cnIQ4:" .. ICON_4321
            .. " |Hkeystone:180653:399:2:165:0:0:0:0"
            .. "|h[Keystone: Ruby Life Pools (2)]|h|r", out)
    end)

    it("leaves a keystone alone when the item id is not the keystone item", function()
        local other = "|cnIQ4:|Hkeystone:999999:399:2:165:0:0:0:0|h[Fake]|h|r"
        local _, out = CL:Filter("CHAT_MSG_SAY", other)
        assert.equal(other, out)
    end)

    it("rewrites the quality tier atlas inside an item link", function()
        local _, out = CL:Filter("CHAT_MSG_SAY", ITEM)
        assert.equal("|cnIQ4:" .. ICON_9999 .. " "
            .. "|Hitem:240949::::::::90:1480|h[Ring |cffe8ac1b5|r]|h|r", out)
    end)

    it("leaves the tier atlas alone when the option is off", function()
        CL.db.NumericalQualityTier = false
        local _, out = CL:Filter("CHAT_MSG_SAY", ITEM)
        assert.equal("|cnIQ4:" .. ICON_9999 .. " "
            .. "|Hitem:240949::::::::90:1480"
            .. "|h[Ring |A:Professions-ChatIcon-Quality-Tier5:17:15::1|a]|h|r", out)
    end)

    it("does not transform anything while the module is off", function()
        CL.db.Enabled = false
        local _, out = CL:Filter("CHAT_MSG_SAY", KEYSTONE)
        assert.equal(KEYSTONE, out)
    end)
end)

describe("ChatLinks secret refusal", function()
    -- issecretvalue is captured as a file-scope upvalue by Core/Secret.lua, so
    -- the override has to be in place before the module loads. Assigning it
    -- inside the test would read as a pass even when the guard is broken.
    it("returns a secret message untouched", function()
        local secret = {}
        local CL = L.loadChatLinks({ issecretvalue = function(v) return v == secret end })
        CL.db = freshDB()
        local _, out = CL:Filter("CHAT_MSG_SAY", secret)
        assert.equal(secret, out)
    end)
end)

describe("ChatLinks web addresses", function()
    local CL
    local BLUE = "|cff4fb5ff"

    before_each(function()
        CL = L.loadChatLinks()
        CL.db = freshDB()
    end)

    it("spots a scheme address and a bare www address", function()
        assert.is_truthy(CL.ContainsURL("go to https://example.com now"))
        assert.is_truthy(CL.ContainsURL("go to www.example.com now"))
    end)

    it("ignores text with no address", function()
        assert.is_falsy(CL.ContainsURL("nothing to see here"))
        assert.is_falsy(CL.ContainsURL(""))
        assert.is_falsy(CL.ContainsURL(nil))
    end)

    it("wraps a scheme address as a keurl link", function()
        assert.equal("go to " .. BLUE
            .. "|Hkeurl:https://example.com|h[https://example.com]|h|r now",
            CL.WrapURLs("go to https://example.com now", BLUE))
    end)

    it("wraps an address at the very start of the message", function()
        assert.equal(BLUE .. "|Hkeurl:www.example.com|h[www.example.com]|h|r is it",
            CL.WrapURLs("www.example.com is it", BLUE))
    end)

    -- The frontier pattern is what stops the bare-domain rule re-matching text
    -- an earlier rule already wrapped. Without it the address is wrapped twice.
    it("wraps an address with a path exactly once", function()
        local out = CL.WrapURLs("see www.example.com/page now", BLUE)
        local _, count = out:gsub("|Hkeurl:", "")
        assert.equal(1, count)
    end)

    it("leaves a message with no address unchanged", function()
        assert.equal("nothing here", CL.WrapURLs("nothing here", BLUE))
        assert.equal("", CL.WrapURLs("", BLUE))
        assert.is_nil(CL.WrapURLs(nil, BLUE))
    end)

    -- Regression cases. A flat pass over the whole message wraps an address
    -- inside a link's display text into a NESTED link, and its greedy tail eats
    -- the terminator that closes the outer link or colour escape. Both were
    -- reproduced in Lua 5.1 before the span walk was added.
    it("leaves an address inside an item link's text alone", function()
        local link = "|Hitem:1|h[Foo www.example.com]|h"
        assert.equal(link, CL.WrapURLs(link, BLUE))
    end)

    it("leaves a scheme address inside an item link's text alone", function()
        local link = "|Hitem:1|h[Foo https://example.com]|h"
        assert.equal(link, CL.WrapURLs(link, BLUE))
    end)

    it("wraps an address beside a link without touching the link", function()
        assert.equal("a |Hitem:1|h[Sword]|h and " .. BLUE
            .. "|Hkeurl:https://example.com|h[https://example.com]|h|r",
            CL.WrapURLs("a |Hitem:1|h[Sword]|h and https://example.com", BLUE))
    end)

    it("does not swallow a trailing colour terminator", function()
        assert.equal("look at " .. BLUE
            .. "|Hkeurl:https://example.com|h[https://example.com]|h|r|r",
            CL.WrapURLs("look at https://example.com|r", BLUE))
    end)

    it("wraps two addresses in one message", function()
        local out = CL.WrapURLs("https://a.com and www.b.com/x here", BLUE)
        local _, count = out:gsub("|Hkeurl:", "")
        assert.equal(2, count)
    end)

    -- The span walk's loop only iterates twice when a second link follows the
    -- first, and the fallback colour is the one branch no other case reaches.
    it("keeps two adjacent links intact and wraps the address after them", function()
        local out = CL.WrapURLs(
            "|Hitem:1|h[A]|h |Hitem:2|h[B]|h see www.example.com", BLUE)
        assert.is_truthy(out:find("|Hitem:1|h[A]|h |Hitem:2|h[B]|h ", 1, true))
        assert.is_truthy(out:find("|Hkeurl:www.example.com|h", 1, true))
    end)

    it("falls back to its own colour when none is passed", function()
        assert.equal("|cff4fb5ff|Hkeurl:https://example.com|h[https://example.com]|h|r",
            CL.WrapURLs("https://example.com"))
    end)

    -- The four link shapes. Each of these broke one of the two pattern-based
    -- matchers that were tried before NextLink; all four must stay byte-identical.
    it("is not fooled by a display-less link before a real one", function()
        local msg = "|Htype|h |Hitem:1|h[Foo www.example.com]|h"
        assert.equal(msg, CL.WrapURLs(msg, BLUE))
    end)

    it("protects a link that has display text but no colon in its data", function()
        local msg = "|HGMChat|h[Ready www.example.com]|h"
        assert.equal(msg, CL.WrapURLs(msg, BLUE))
    end)

    it("protects a display-less link whose data does carry a colon", function()
        local msg = "|HurlIndex:24|h |Hitem:1|h[Foo www.example.com]|h"
        assert.equal(msg, CL.WrapURLs(msg, BLUE))
    end)

    it("protects a link whose data contains pipes", function()
        local msg = "|HBNplayer:|Kf1|k:1:2:3|h[|Kf1|k www.example.com]|h"
        assert.equal(msg, CL.WrapURLs(msg, BLUE))
    end)

    it("wraps after an unterminated link marker without dropping text", function()
        local out = CL.WrapURLs("|Hbroken and www.example.com", BLUE)
        assert.is_truthy(out:find("|Hbroken and ", 1, true) == 1)
        assert.is_truthy(out:find("|Hkeurl:www.example.com|h", 1, true))
    end)

    -- Without the resynchronisation, the unterminated marker claims the item
    -- link's two terminators, the whole string is copied through as one link,
    -- and the address never wraps.
    it("resynchronises past an unterminated marker onto a real link", function()
        local out = CL.WrapURLs(
            "|Hbroken see www.example.com |Hitem:1|h[Item]|h", BLUE)
        assert.is_truthy(out:find("|Hkeurl:www.example.com|h", 1, true))
        assert.is_truthy(out:find(" |Hitem:1|h[Item]|h", 1, true))
    end)

    it("rewrites an address through the filter when the option is on", function()
        local _, out = CL:Filter("CHAT_MSG_SAY", "look at https://example.com")
        assert.is_truthy(out:find("|Hkeurl:https://example.com|h", 1, true))
    end)

    it("leaves the address alone when the option is off", function()
        CL.db.WebAddresses = false
        local _, out = CL:Filter("CHAT_MSG_SAY", "look at https://example.com")
        assert.equal("look at https://example.com", out)
    end)

    -- A pattern match on secret text throws, so the existing first-contact guard
    -- must cover the new rewrite too, not just the icon decorators.
    it("refuses a secret message", function()
        local secret = "look at https://example.com"
        CL = L.loadChatLinks({ issecretvalue = function(v) return v == secret end })
        CL.db = freshDB()
        local _, out = CL:Filter("CHAT_MSG_SAY", secret)
        assert.equal(secret, out)
    end)
end)

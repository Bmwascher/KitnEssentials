-- Tier 1: Modules/Skinning/ChatLinks.lua. Covers the secret refusal and the
-- keystone pattern. The other five decorators are ports checked by diff and in
-- game; where they differ from the source, the plan's deviations list is what
-- enumerates it.
local L = require("dev.spec._ke_loader")

local DB = {
    Enabled = true, Icon = true, IconHeight = 14, IconWidth = 14,
    KeepRatio = true, NumericalQualityTier = true,
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

-- Tier: the Better Friendlist skin's KE-invented rules (AGENTS.md tiered test
-- policy). The skin exports its pure predicates on KE.Skins; frames, hooks and
-- secret behavior are checked in game.

local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

-- Declared secrets: a table with __secret == true counts as secret.
local function isSecret(v)
    return type(v) == "table" and v.__secret == true
end

-- The skin reads only KE.Skins at file scope and calls S:Register at the
-- bottom, so a seeded S is the whole fixture. Core/Secret.lua supplies the
-- real KE:IsSecretValue over the declared secrets.
local function loadSkin()
    mock.install({ issecretvalue = isSecret, C_Timer = { After = function() end } })
    helpers.installAddonShim()
    local store = setmetatable({}, { __mode = "k" })
    local S = {
        palette = { brand = { 1, 1, 1 }, hover = { 0.851, 0.851, 0.851, 0.15 } },
        Register = function() end,
        data = function(o)
            store[o] = store[o] or {}
            return store[o]
        end,
    }
    local KE = { Skins = S, Print = function() end }
    helpers.loadModule("Core/Secret.lua", KE)
    helpers.loadModule("Modules/Skinning/DarkTheme/Addons/BetterFriendlist.lua", KE)
    return S
end

describe("Better Friendlist skin: layout choice", function()
    local function ui(applied, pending, modern)
        return {
            appliedStyle = applied,
            pendingStyle = pending,
            IsModernActive = function() return modern end,
        }
    end

    it("dresses only the layout the addon has applied", function()
        local S = loadSkin()
        local cases = {
            { "no layout applied yet", ui(nil, nil, true), nil },
            { "a style deferred in combat", ui("modern", "legacy", true), nil },
            { "Modern applied", ui("modern", nil, true), "modern" },
            { "Legacy applied", ui("legacy", nil, false), "legacy" },
            { "no FriendsUI module", nil, "legacy" },
        }
        for _, c in ipairs(cases) do
            assert.are.equal(c[3], S._BFLLayoutFor(c[2]), c[1])
        end
    end)
end)

describe("Better Friendlist skin: status edge", function()
    it("follows the addon's away-before-busy precedence", function()
        local S = loadSkin()
        local cases = {
            { "offline", { connected = false, isAFK = true }, nil },
            { "away", { connected = true, isAFK = true, isDND = true }, "away" },
            { "busy", { connected = true, dnd = true }, "busy" },
            { "online", { connected = true }, "online" },
        }
        for _, c in ipairs(cases) do
            assert.are.equal(c[3], S._BFLStatusEdge(c[2]), c[1])
        end
    end)
end)

describe("Better Friendlist skin: same zone", function()
    it("matches only two plain, equal zone names", function()
        local S = loadSkin()
        local secret = { __secret = true }
        local cases = {
            { "equal", "Silvermoon City", "Silvermoon City", true },
            { "different", "Silvermoon City", "Dornogal", false },
            { "nil", nil, "Silvermoon City", false },
            { "empty strings", "", "", false },
            { "secret", secret, secret, false },
        }
        for _, c in ipairs(cases) do
            assert.are.equal(c[4], S._BFLSameZone(c[2], c[3]), c[1])
        end
    end)
end)

describe("Better Friendlist skin: header count", function()
    it("colors the first number of a plain count, and recolors only its own", function()
        local S = loadSkin()
        local mine = { countPlain = "(3/10)", countOut = "(|cff00ff003|r/10)" }
        local cases = {
            { "plain count", {}, "(3/10)", "(|cffff80003|r/10)" },
            { "its own earlier output, new accent", mine, "(|cff00ff003|r/10)", "(|cffff80003|r/10)" },
            { "another color code", {}, "(|cff00ff003|r/10)", nil },
            { "no number", {}, "Online", nil },
            { "secret", {}, { __secret = true }, nil },
        }
        for _, c in ipairs(cases) do
            assert.are.equal(c[4], S._BFLAccentCount(c[2], c[3], 1, 0.5, 0), c[1])
        end
    end)
end)

describe("Better Friendlist skin: zone dot", function()
    it("shows only on a shown in-zone line, in the accent, or white for a gray accent", function()
        local S = loadSkin()
        local icecrown, twilight = { 0, 0.749, 1 }, { 0.608, 0.349, 0.714 }
        local white = { 1, 1, 1 }
        -- name, in zone, line shown, accent, dot color
        local cases = {
            { "not in zone", false, true, icecrown, nil },
            { "line hidden", true, false, icecrown, nil },
            { "colored accent", true, true, icecrown, icecrown },
            { "least saturated preset", true, true, twilight, twilight },
            { "Torghast gray", true, true, { 0.627, 0.627, 0.627 }, white },
            { "skin tint off", true, true, { 0.651, 0.651, 0.651 }, white },
            { "near-gray custom", true, true, { 0.5, 0.55, 0.5 }, white },
        }
        for _, c in ipairs(cases) do
            assert.are.same(c[5], S._BFLZoneDot(c[2], c[3], c[4]), c[1])
        end
    end)
end)

describe("Better Friendlist skin: zone dot offset", function()
    it("sits the gap after the text, stops at the box edge, or draws nothing", function()
        local S = loadSkin()
        local secret = { __secret = true }
        -- name, text width, box width, dot x offset
        local cases = {
            { "short text: its width plus the gap", 40, 200, 43 },
            { "text near the box edge clamps", 195, 200, 194 },
            { "text wider than the box clamps", 260, 200, 194 },
            { "zero text width", 0, 200, nil },
            { "no text width", nil, 200, nil },
            { "secret text width", secret, 200, nil },
            { "zero box width", 40, 0, nil },
            { "no box width", 40, nil, nil },
            { "secret box width", 40, secret, nil },
        }
        for _, c in ipairs(cases) do
            assert.are.equal(c[4], S._BFLZoneDotOffset(c[2], c[3]), c[1])
        end
    end)
end)

describe("Better Friendlist skin: selection seed", function()
    it("follows the addon's own selection test", function()
        local S = loadSkin()
        local friend = { uid = "bnet_7" }
        local secret = { __secret = true }
        local resolver = { selectedFriendUID = "bnet_7", GetFriendUID = function() return "bnet_7" end }
        local secretResolver = { selectedFriendUID = "bnet_7", GetFriendUID = function() return secret end }
        local cases = {
            { "same friend table", { selectedFriend = friend }, friend, true },
            { "same ID", { selectedFriendUID = "bnet_7" }, { uid = "bnet_7" }, true },
            { "ID from the addon's resolver", resolver, {}, true },
            { "another ID", { selectedFriendUID = "bnet_8" }, friend, false },
            { "nothing selected", {}, friend, false },
            { "secret selected ID", { selectedFriendUID = secret }, { uid = secret }, false },
            { "secret friend ID, plain selected ID", { selectedFriendUID = "bnet_7" }, { uid = secret }, false },
            { "secret ID from the addon's resolver", secretResolver, {}, false },
            { "no list", nil, friend, false },
        }
        for _, c in ipairs(cases) do
            assert.are.equal(c[4], S._BFLRowSelected(c[2], c[3]), c[1])
        end
    end)
end)

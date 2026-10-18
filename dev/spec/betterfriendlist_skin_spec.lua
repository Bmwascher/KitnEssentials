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

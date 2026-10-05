local L = require("dev.spec._ke_loader")

-- The finder's refusal rules decide whether KE ever calls the info API with a
-- secret, and whether a stale or hidden viewer can hand back a frame. Secrets
-- are tables flagged __secret, as the loader's mock recognizes them through
-- the issecretvalue override.
local SECRET = { __secret = true }
local function isSecret(v) return type(v) == "table" and v.__secret == true end

-- SECRET is a wanted key on purpose: a secret value that is not skipped would
-- find rank 3 here instead of nothing.
local IDS = { [100] = 1, [200] = 2, [SECRET] = 3 }

local function Frame(id, slot, shown)
    return {
        layoutIndex = slot,
        GetCooldownID = function() return id end,
        IsShown = function() return shown ~= false end,
    }
end

local function Viewer(list, shown)
    return {
        IsShown = function() return shown ~= false end,
        itemFramePool = {
            EnumerateActive = function()
                local i = 0
                return function()
                    i = i + 1
                    return list[i]
                end
            end,
        },
    }
end

-- Cooldown id -> info, as GetCooldownViewerCooldownInfo answers. "raise"
-- makes the call error. Every id asked for is recorded in calls.
local function Api(byID, calls)
    return {
        GetCooldownViewerCooldownInfo = function(id)
            if calls then calls[#calls + 1] = id end
            local info = byID[id]
            if info == "raise" then error("unknown cooldown") end
            return info
        end,
    }
end

describe("CDMIcons.Matches", function()
    it("returns the lowest rank among the plain matching fields", function()
        local KE = L.loadCDMIcons({ issecretvalue = isSecret })
        local Matches = KE.CDMIcons.Matches
        local rows = {
            { "spellID", { spellID = 100, linkedSpellIDs = {} }, 1 },
            { "overrideSpellID", { spellID = 9, overrideSpellID = 200, linkedSpellIDs = {} }, 2 },
            { "overrideTooltipSpellID", { overrideTooltipSpellID = 100, linkedSpellIDs = {} }, 1 },
            { "a linked entry", { spellID = 9, linkedSpellIDs = { 8, 200 } }, 2 },
            { "two fields: the lower rank", { spellID = 200, overrideSpellID = 100, linkedSpellIDs = {} }, 1 },
            { "no wanted field", { spellID = 9, overrideSpellID = 8, linkedSpellIDs = { 7 } }, nil },
            { "a secret field skipped, a plain one counts", { spellID = SECRET, overrideSpellID = 200, linkedSpellIDs = {} }, 2 },
            { "only a secret field", { spellID = SECRET, linkedSpellIDs = {} }, nil },
            { "a secret linked entry skipped", { spellID = 9, linkedSpellIDs = { SECRET } }, nil },
            { "a secret linked list not walked", { spellID = 9, linkedSpellIDs = { 200, __secret = true } }, nil },
            { "no info", nil, nil },
        }
        for _, r in ipairs(rows) do
            assert.equals(r[3], Matches(r[2], IDS), r[1])
        end
    end)
end)

describe("CDMIcons.Find", function()
    after_each(function()
        _G.BuffIconCooldownViewer = nil
    end)

    it("refuses without a plain cooldown id or a shown viewer, and asks nothing then", function()
        local wanted = { spellID = 100, linkedSpellIDs = {} }
        local rows = {
            { "secret cooldown id", Viewer({ Frame(SECRET, 1) }), { [SECRET] = wanted }, 0 },
            { "nil cooldown id", Viewer({ Frame(nil, 1) }), {}, 0 },
            { "the info call raises", Viewer({ Frame(7, 1) }), { [7] = "raise" }, 1 },
            { "viewer absent", nil, { [7] = wanted }, 0 },
            { "viewer not shown", Viewer({ Frame(7, 1) }, false), { [7] = wanted }, 0 },
        }
        for _, r in ipairs(rows) do
            local calls = {}
            local KE = L.loadCDMIcons({ issecretvalue = isSecret, C_CooldownViewer = Api(r[3], calls) })
            _G.BuffIconCooldownViewer = r[2]
            assert.is_nil(KE.CDMIcons.Find("BuffIcon", IDS), r[1])
            assert.equals(r[4], #calls, r[1] .. ": info calls")
        end
    end)

    it("picks the lowest rank, then the lowest slot, hidden icons included", function()
        local info = {
            [1] = { spellID = 200, linkedSpellIDs = {} },
            [2] = { spellID = 100, linkedSpellIDs = {} },
            [3] = { spellID = 100, linkedSpellIDs = {} },
        }
        local rows = {
            { "rank 1 at slot 5 beats rank 2 at slot 1", { Frame(1, 1), Frame(2, 5) }, 2 },
            { "equal ranks: the lower slot", { Frame(3, 4), Frame(2, 2) }, 2 },
            { "a hidden icon is still found", { Frame(2, 1, false) }, 1 },
        }
        for _, r in ipairs(rows) do
            local KE = L.loadCDMIcons({ issecretvalue = isSecret, C_CooldownViewer = Api(info) })
            _G.BuffIconCooldownViewer = Viewer(r[2])
            assert.equals(r[2][r[3]], KE.CDMIcons.Find("BuffIcon", IDS), r[1])
        end
    end)
end)

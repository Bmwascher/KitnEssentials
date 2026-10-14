-- Tier 1: Party Potions' pure rules
-- (Modules/AuraTracking/PartyBuffs/PartyPotionsRules.lua): the bars' entry, the
-- watched units, the roster keep, the bar colors and the cover range on the
-- party cooldowns stamp.
local L = require("dev.spec._ke_loader")

describe("PartyPotionsRules.Entry", function()
    it("takes the switched-on potions in ID order, and nothing when none is on", function()
        local R = L.loadPartyPotionsRules()
        local e = R.Entry({ [500] = true, [300] = true, [400] = true, [200] = false })
        assert.are.same({ 300, 400, 500 }, e.buffs)
        assert.is_nil(R.Entry({ [200] = false }), "nothing switched on")
    end)
end)

describe("PartyPotionsRules.Tokens", function()
    it("watches nobody solo, puts you first only when asked, and keeps party order", function()
        local R = L.loadPartyPotionsRules()
        local cases = {
            { name = "solo", self = true, exists = {}, want = {} },
            { name = "you first", self = true, exists = { party1 = true, party3 = true },
              want = { "player", "party1", "party3" } },
            { name = "without you", self = false, exists = { party1 = true, party2 = true },
              want = { "party1", "party2" } },
        }
        for _, case in ipairs(cases) do
            local function exists(token) return case.exists[token] == true end
            assert.are.same(case.want, R.Tokens(case.self, exists), case.name)
        end
    end)
end)

describe("PartyPotionsRules.KeepOnRoster", function()
    it("keeps a count only when both GUIDs are plain and equal", function()
        local R = L.loadPartyPotionsRules()
        -- A plain and a secret GUID that compare equal, so only the secret
        -- guard on that position can refuse the pair.
        local same = { __eq = function() return true end }
        local plain = setmetatable({}, same)
        local hidden = setmetatable({ secret = true }, same)
        local function isSecret(v) return type(v) == "table" and v.secret == true end
        local cases = {
            { name = "same member", old = "Player-1-A", new = "Player-1-A", want = true },
            { name = "someone else", old = "Player-1-A", new = "Player-1-B", want = false },
            { name = "unknown before", new = "Player-1-A", want = false },
            { name = "unknown now", old = "Player-1-A", want = false },
            { name = "hidden before", old = hidden, new = plain, want = false },
            { name = "hidden now", old = plain, new = hidden, want = false },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.want, R.KeepOnRoster(case.old, case.new, isSecret), case.name)
        end
    end)
end)

describe("PartyPotionsRules.Colors", function()
    it("draws the class color darkened unless the bars take their own colors, and a name in it only when known", function()
        local R = L.loadPartyPotionsRules()
        local class, bar, bg = { 0.2, 0.4, 0.6 }, { 0.3, 0.4, 0.5, 1 }, { 0.1, 0.1, 0.1, 1 }
        local white, gray = { 1, 1, 1 }, { 0.5, 0.5, 0.5 }
        local cases = {
            { name = "own colors", style = { barColor = bar, bgColor = bg }, color = class,
              want = { bar, 1, bg, 1, white } },
            { name = "class name", style = { classBars = true, classNames = true }, color = class,
              want = { class, R.DIM, class, R.BG, class } },
            { name = "class hidden", style = { classBars = true, classNames = true },
              want = { gray, R.DIM, gray, R.BG, white } },
        }
        for _, case in ipairs(cases) do
            assert.are.same(case.want, { R.Colors(case.style, case.color) }, case.name)
        end
    end)
end)

describe("PartyPotionsRules.CoverRange", function()
    local function fill(v, lo, hi)
        local f = (v - lo) / (hi - lo)
        if f < 0 then return 0 elseif f > 1 then return 1 end
        return f
    end

    it("drains the cover by one cd-th each second", function()
        local R, KE = L.loadPartyPotionsRules()
        local CD = KE.PartyCooldownsRules
        for _, cd in ipairs({ 120, 300 }) do
            local t = CD.NewTracker(cd, false)
            CD.Clear(t, 0)
            CD.StartPlain(t, 10)
            local sl, u = t.slot[t.cur], t.u
            local start = math.floor(10 / u) * u
            for n = start, start + cd + 2 do
                local e = n - start
                local lo, hi = R.CoverRange(sl, u, cd, n)
                assert.is_true(math.abs(fill(sl.c, lo, hi) - math.min(1, e / cd)) < 1e-9,
                    cd .. " s, cover at second " .. e)
            end
        end
    end)
end)

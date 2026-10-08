-- Tier 1: Party Buffs' pure rules (Modules/Combat/PartyBuffsRules.lua): the
-- place gate, each category's container settings, and which party frame a
-- teammate binds to, including the own-frame fallback that must never hide a
-- teammate.
local L = require("dev.spec._ke_loader")

local function makeDb(overrides)
    local db = {
        Enabled = true,
        MaxPerMember = 4,
        TrackExternal = true,
        TrackBigDefensive = true,
        TrackBurst = true,
        TrackPotion = true,
        TrackTrinket = true,
        ShowInKeys = true,
        ShowInDungeons = true,
        ShowInDelves = true,
        ShowInWorld = true,
        ShowInArenas = true,
        ListExternals = {},
        ListBurst = {},
        ListPotions = {},
        ListTrinkets = {},
    }
    for key, value in pairs(overrides or {}) do db[key] = value end
    return db
end

describe("PartyBuffsRules.ClassifyContent", function()
    it("names each place and gives nil for raids, battlegrounds, brawls and scenarios", function()
        local R = L.loadPartyBuffsRules()
        local cases = {
            { name = "running key", want = "key",
              facts = { challengeActive = true, inInstance = true, instanceType = "party" } },
            { name = "key beats delve", want = "key",
              facts = { challengeActive = true, delveActive = true, inInstance = true, instanceType = "party" } },
            { name = "delve", want = "delve",
              facts = { delveActive = true, inInstance = true, instanceType = "scenario" } },
            { name = "arena by C_PvP", want = "arena",
              facts = { arena = true, inInstance = true, instanceType = "arena" } },
            { name = "arena by instance type", want = "arena",
              facts = { arena = false, inInstance = true, instanceType = "arena" } },
            { name = "brawl arena", want = nil,
              facts = { arena = true, brawl = true, inInstance = true, instanceType = "arena" } },
            { name = "dungeon without a key", want = "dungeon",
              facts = { inInstance = true, instanceType = "party" } },
            { name = "open world", want = "world",
              facts = { inInstance = false, instanceType = "none" } },
            { name = "battleground", want = nil,
              facts = { inInstance = true, instanceType = "pvp" } },
            { name = "raid", want = nil,
              facts = { inInstance = true, instanceType = "raid" } },
            { name = "scenario", want = nil,
              facts = { inInstance = true, instanceType = "scenario" } },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.want, R.ClassifyContent(case.facts), case.name)
        end
    end)
end)

describe("PartyBuffsRules.ShouldActivate", function()
    it("is true when every input holds and false for each single failing input", function()
        local R = L.loadPartyBuffsRules()
        local cases = {
            { name = "all inputs hold", db = makeDb(), content = "dungeon", inGroup = true, want = true },
            { name = "module off", db = makeDb({ Enabled = false }), content = "dungeon", inGroup = true, want = false },
            { name = "not in a group", db = makeDb(), content = "dungeon", inGroup = false, want = false },
            { name = "no content", db = makeDb(), content = nil, inGroup = true, want = false },
            { name = "keys off", db = makeDb({ ShowInKeys = false }), content = "key", inGroup = true, want = false },
            { name = "dungeons off", db = makeDb({ ShowInDungeons = false }), content = "dungeon", inGroup = true, want = false },
            { name = "delves off", db = makeDb({ ShowInDelves = false }), content = "delve", inGroup = true, want = false },
            { name = "world off", db = makeDb({ ShowInWorld = false }), content = "world", inGroup = true, want = false },
            { name = "arenas off", db = makeDb({ ShowInArenas = false }), content = "arena", inGroup = true, inRaid = true, want = false },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.want,
                R.ShouldActivate(case.db, case.content, case.inGroup, case.inRaid == true), case.name)
        end
    end)

    it("in a raid group activates in an arena only", function()
        local R = L.loadPartyBuffsRules()
        for _, content in ipairs({ "key", "dungeon", "delve", "world" }) do
            assert.is_false(R.ShouldActivate(makeDb(), content, true, true), content)
        end
        assert.is_true(R.ShouldActivate(makeDb(), "arena", true, true))
    end)
end)

describe("PartyBuffsRules.BuildGroupConfig", function()
    it("gives each list category HELPFUL, its enabled rows and its position", function()
        local R = L.loadPartyBuffsRules()
        local list = {
            [111] = { enabled = true },
            [222] = { enabled = false },
            [-1]  = { enabled = true },
            [3.5] = { enabled = true },
        }
        for position, category in ipairs(R.CATEGORIES) do
            if category.listKey then
                local filter, candidates, _, layoutIndex =
                    R.BuildGroupConfig(category, makeDb({ [category.listKey] = list }))
                assert.are.equal("HELPFUL", filter, category.key)
                assert.are.same({ [111] = true }, candidates.includeSpellIDs, category.key)
                assert.are.equal(position, layoutIndex, category.key)
                local empty = select(2, R.BuildGroupConfig(category, makeDb({ [category.listKey] = {} })))
                assert.are.same({}, empty.includeSpellIDs, category.key)
            end
        end
    end)

    it("gives big defensives the tag filter and excludes externals only while they are tracked", function()
        local R, KE = L.loadPartyBuffsRules()
        local big
        for _, category in ipairs(R.CATEGORIES) do
            if category.key == "big" then big = category end
        end
        local externals = { [33206] = { enabled = true }, [47788] = { enabled = false } }

        local filter, tracked = R.BuildGroupConfig(big, makeDb({ ListExternals = externals }))
        assert.are.equal("HELPFUL|BIG_DEFENSIVE", filter)
        assert.is_nil(tracked.includeSpellIDs)
        local expected = { [33206] = true }
        for spellID in pairs(KE.AuraRules.HARDCODED_BLOCKLIST_SET) do expected[spellID] = true end
        assert.are.same(expected, tracked.excludeSpellIDs)

        local untracked = select(2, R.BuildGroupConfig(big,
            makeDb({ ListExternals = externals, TrackExternal = false })))
        assert.are.same(KE.AuraRules.HARDCODED_BLOCKLIST_SET, untracked.excludeSpellIDs)
        assert.is_nil(KE.AuraRules.HARDCODED_BLOCKLIST_SET[33206])
    end)

    it("caps each group at MaxPerMember, rounded, while tracked and at 0 while not", function()
        local R = L.loadPartyBuffsRules()
        local caps = { { set = 6, want = 6 }, { set = 4.4, want = 4 }, { set = 4.6, want = 5 } }
        for _, category in ipairs(R.CATEGORIES) do
            for _, cap in ipairs(caps) do
                local tracked = select(3, R.BuildGroupConfig(category, makeDb({ MaxPerMember = cap.set })))
                assert.are.equal(cap.want, tracked, category.key .. " " .. cap.set)
            end
            local untracked = select(3, R.BuildGroupConfig(category,
                makeDb({ MaxPerMember = 6, [category.trackKey] = false })))
            assert.are.equal(0, untracked, category.key)
        end
    end)
end)

describe("PartyBuffsRules.PickFrames", function()
    local function cand(token, family, visible, facts)
        local candidate = {
            token = token, family = family, visible = visible,
            frame = { id = family .. "-" .. token },
        }
        for key, value in pairs(facts or {}) do candidate[key] = value end
        return candidate
    end

    it("binds each token to its first visible frame in family order", function()
        local R = L.loadPartyBuffsRules()
        local got = R.PickFrames({
            cand("party1", "eui", true),
            cand("party2", "eui", false),
            cand("party1", "compact", true),
            cand("party2", "compact", true),
            cand("party3", "portrait", true),
        }, 5)
        assert.are.equal(3, #got)
        assert.are.same({ "party1", "eui", "eui-party1" }, { got[1].token, got[1].family, got[1].frame.id })
        assert.are.same({ "party2", "compact", "compact-party2" }, { got[2].token, got[2].family, got[2].frame.id })
        assert.are.same({ "party3", "portrait", "portrait-party3" }, { got[3].token, got[3].family, got[3].frame.id })
    end)

    it("skips every candidate the own-frame check identifies", function()
        local R = L.loadPartyBuffsRules()
        local got = R.PickFrames({
            cand("player", "compact", true),
            cand("raid1", "eui", true, { raidIndex = 1 }),
            cand("raid2", "eui", true, { raidIndex = 1, compareOk = true, compareSecret = false, compareResult = true }),
            cand("raid3", "eui", true, { raidIndex = 1, compareOk = true, compareSecret = true }),
        }, 5)
        assert.are.equal(1, #got)
        assert.are.equal("raid3", got[1].token)
    end)

    it("returns at most maxSlots bindings", function()
        local R = L.loadPartyBuffsRules()
        local list = {}
        for i = 1, 7 do list[i] = cand("raid" .. i, "eui", true) end
        local got = R.PickFrames(list, 5)
        assert.are.equal(5, #got)
        assert.are.equal("raid5", got[5].token)
    end)

    it("returns an empty list when nothing is visible", function()
        local R = L.loadPartyBuffsRules()
        assert.are.same({}, R.PickFrames({ cand("party1", "eui", false), cand("party2", "compact", false) }, 5))
    end)
end)

describe("PartyBuffsRules.CandidateToken", function()
    it("prefers unit, falls back to the unit attribute, and gives nil when neither is a string", function()
        local R = L.loadPartyBuffsRules()
        assert.are.equal("party1", R.CandidateToken({ unit = "party1", attrUnit = "party2" }))
        assert.are.equal("party2", R.CandidateToken({ unit = 5, attrUnit = "party2" }))
        assert.is_nil(R.CandidateToken({ unit = {}, attrUnit = false }))
    end)
end)

describe("PartyBuffsRules.IsPlayerCandidate", function()
    it("skips only when a check can tell, and tracks otherwise", function()
        local R = L.loadPartyBuffsRules()
        local cases = {
            { name = "player token", want = true, facts = { token = "player" } },
            { name = "own raid index", want = true, facts = { token = "raid3", raidIndex = 3 } },
            { name = "readable true", want = true,
              facts = { token = "raid3", raidIndex = 2, compareOk = true, compareSecret = false, compareResult = true } },
            { name = "secret comparison", want = false,
              facts = { token = "raid3", compareOk = true, compareSecret = true } },
            { name = "failed comparison", want = false, facts = { token = "raid3", compareOk = false } },
            { name = "readable false, no raid index", want = false,
              facts = { token = "raid3", compareOk = true, compareSecret = false, compareResult = false } },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.want, R.IsPlayerCandidate(case.facts), case.name)
        end
    end)
end)

describe("PartyBuffsRules.ActivePlacement", function()
    local function placementDb(overrides)
        local db = {
            Side = "LEFT", XOffset = 0, YOffset = 0, Strata = "FRAME",
            HealerSide = "RIGHT", HealerXOffset = 6, HealerYOffset = -4, HealerStrata = "HIGH",
        }
        for key, value in pairs(overrides or {}) do db[key] = value end
        return db
    end

    it("uses the healer copy only while the toggle is on and the healer answer is true", function()
        local R = L.loadPartyBuffsRules()
        local default = { "LEFT", 0, 0, "FRAME" }
        local healer = { "RIGHT", 6, -4, "HIGH" }
        local cases = {
            { name = "toggle off, healer spec", toggle = false, useHealer = true, want = default },
            { name = "toggle on, other spec", toggle = true, useHealer = false, want = default },
            { name = "toggle on, healer spec", toggle = true, useHealer = true, want = healer },
        }
        for _, case in ipairs(cases) do
            local db = placementDb({ UseHealerPlacement = case.toggle })
            assert.are.same(case.want, { R.ActivePlacement(db, case.useHealer) }, case.name)
        end
    end)

    it("reads the default key for a healer key that is absent", function()
        local R = L.loadPartyBuffsRules()
        local db = placementDb({ UseHealerPlacement = true })
        db.HealerXOffset = nil
        db.HealerStrata = nil
        assert.are.same({ "RIGHT", 0, -4, "FRAME" }, { R.ActivePlacement(db, true) })
    end)
end)

describe("PartyBuffsRules.SeedHealerPlacement", function()
    it("fills each absent healer key from its default and keeps one already set", function()
        local R = L.loadPartyBuffsRules()
        local db = { Side = "ABOVE", XOffset = 3, YOffset = -2, Strata = "LOW", HealerSide = "BELOW" }
        R.SeedHealerPlacement(db)
        assert.are.same({ "BELOW", 3, -2, "LOW" },
            { db.HealerSide, db.HealerXOffset, db.HealerYOffset, db.HealerStrata })
    end)
end)

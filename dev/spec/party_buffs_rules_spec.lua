-- Tier 1: Party Buffs' pure rules (Modules/AuraTracking/PartyBuffs/PartyBuffsRules.lua): the
-- place gate, each category's container settings, and which party frame a
-- teammate binds to, including the own-frame fallback that must never hide a
-- teammate.
local L = require("dev.spec._ke_loader")

local function makeDb(overrides)
    local db = {
        Enabled = true,
        MaxPerMember = 4,
        TrackExternal = true,
        TrackBurst = true,
        TrackPotion = true,
        TrackTrinket = true,
        ShowInKeys = true,
        ShowInDungeons = true,
        ShowInDelves = true,
        ShowInWorld = true,
        ShowInArenas = true,
        ListExternals = {},
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

    it("keeps the own frame only when include-self is on", function()
        local R = L.loadPartyBuffsRules()
        local list = { cand("player", "compact", true), cand("party1", "compact", true) }
        local cases = {
            { includeSelf = false, want = { "party1" } },
            { includeSelf = true, want = { "player", "party1" } },
        }
        for _, case in ipairs(cases) do
            local tokens = {}
            for i, binding in ipairs(R.PickFrames(list, 5, case.includeSelf)) do tokens[i] = binding.token end
            assert.are.same(case.want, tokens, tostring(case.includeSelf))
        end
    end)

    it("keeps only the first own frame when include-self is on, whatever its token", function()
        local R = L.loadPartyBuffsRules()
        local raidSelf = cand("raid3", "eui", true, { raidIndex = 3 })
        local player = cand("player", "player", true)
        local mate = cand("party1", "eui", true)
        local cases = {
            { name = "raid token first", list = { raidSelf, player, mate }, want = { "raid3", "party1" } },
            { name = "player first", list = { player, raidSelf, mate }, want = { "player", "party1" } },
        }
        for _, case in ipairs(cases) do
            local tokens = {}
            for i, binding in ipairs(R.PickFrames(case.list, 2, true)) do tokens[i] = binding.token end
            assert.are.same(case.want, tokens, case.name)
        end
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
            Side = "LEFT", XOffset = 0, YOffset = 0,
            HealerSide = "RIGHT", HealerXOffset = 6, HealerYOffset = -4,
            IconsPerRow = 14, HealerIconsPerRow = 3,
            IconSize = 36, HealerIconSize = 32,
            Grow = "UP", HealerGrow = "DOWN",
        }
        for key, value in pairs(overrides or {}) do db[key] = value end
        return db
    end

    it("uses the healer copy only while the toggle is on and the healer answer is true", function()
        local R = L.loadPartyBuffsRules()
        local default = { "LEFT", 0, 0, 14, 36, "UP" }
        local healer = { "RIGHT", 6, -4, 3, 32, "DOWN" }
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
        db.HealerIconsPerRow = nil
        db.HealerIconSize = nil
        db.HealerGrow = nil
        assert.are.same({ "RIGHT", 0, -4, 14, 36, "UP" }, { R.ActivePlacement(db, true) })
    end)
end)

describe("PartyBuffsRules.Layout", function()
    it("gives the layout the side offers for its Grow, the side's first for any other, and Left's list "
        .. "for an unknown side", function()
        local R = L.loadPartyBuffsRules()
        -- want: the grow of the layout expected; nil expects the list's first layout.
        local cases = {
            { name = "Left, unset", side = "LEFT", grow = nil, list = "LEFT" },
            { name = "Above, unset", side = "ABOVE", grow = nil, list = "ABOVE" },
            { name = "Inside, unset", side = "INSIDE", grow = nil, list = "INSIDE" },
            { name = "Left offers Up", side = "LEFT", grow = "UP", list = "LEFT", want = "UP" },
            { name = "Below offers Left", side = "BELOW", grow = "LEFT", list = "BELOW", want = "LEFT" },
            { name = "Left, toward the frame", side = "LEFT", grow = "RIGHT", list = "LEFT" },
            { name = "Right, toward the frame", side = "RIGHT", grow = "LEFT", list = "RIGHT" },
            { name = "Above, toward the frame", side = "ABOVE", grow = "DOWN", list = "ABOVE" },
            { name = "Below, toward the frame", side = "BELOW", grow = "UP", list = "BELOW" },
            { name = "Inside, out of the frame", side = "INSIDE", grow = "RIGHT", list = "INSIDE" },
            { name = "Above, another side's choice", side = "ABOVE", grow = "UP", list = "ABOVE" },
            { name = "unknown side reads as Left", side = "NOWHERE", grow = "UP", list = "LEFT", want = "UP" },
        }
        for _, case in ipairs(cases) do
            local layout, layouts = R.Layout(case.side, case.grow)
            assert.are.equal(R.LAYOUTS[case.list], layouts, case.name)
            if case.want then
                assert.are.equal(case.want, layout.grow, case.name)
            else
                assert.are.equal(layouts[1], layout, case.name)
            end
        end
    end)
end)

describe("PartyBuffsRules.HolderOffset", function()
    it("lifts a Center layout by half an icon and leaves the others at gap plus offset", function()
        local R = L.loadPartyBuffsRules()
        local cases = {
            { side = "LEFT", grow = "CENTER", want = { 5, 21 } },
            { side = "RIGHT", grow = "CENTER", want = { 9, 21 } },
            { side = "LEFT", grow = "DOWN", want = { 5, 3 } },
            { side = "ABOVE", grow = "RIGHT", want = { 9, 5 } },
        }
        for _, case in ipairs(cases) do
            assert.are.same(case.want, { R.HolderOffset(R.Layout(case.side, case.grow), 2, 7, 3, 36) },
                case.side .. " " .. case.grow)
        end
    end)
end)

describe("PartyBuffsRules.SeedHealerPlacement", function()
    it("fills each absent healer key from its default and keeps one already set", function()
        local R = L.loadPartyBuffsRules()
        local db = {
            Side = "ABOVE", XOffset = 3, YOffset = -2, IconsPerRow = 5, HealerSide = "BELOW",
        }
        R.SeedHealerPlacement(db)
        assert.are.same({ "BELOW", 3, -2, 5 },
            { db.HealerSide, db.HealerXOffset, db.HealerYOffset, db.HealerIconsPerRow })
    end)
end)

describe("PartyBuffsRules.PerRow", function()
    it("rounds a number to a whole count of at least 1 and reads anything else as 14", function()
        local R = L.loadPartyBuffsRules()
        local cases = {
            { value = 2.6, want = 3 },
            { value = 2.4, want = 2 },
            { value = 0, want = 1 },
            { value = -3, want = 1 },
            { value = nil, want = 14 },
            { value = "6", want = 14 },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.want, R.PerRow(case.value), tostring(case.value))
        end
    end)
end)

describe("PartyBuffsRules.GridPosition", function()
    it("keeps index perLine - 1 on line 0 and starts line 1 at index perLine", function()
        local R = L.loadPartyBuffsRules()
        assert.are.same({ 2, 0 }, { R.GridPosition(2, 3) })
        assert.are.same({ 0, 1 }, { R.GridPosition(3, 3) })
    end)
end)

describe("PartyBuffsRules.LineSize", function()
    -- The flow layout's wrap test: the running size carries the trailing
    -- spacing, and an icon wraps when the running size plus it passes the maximum.
    local function iconsOnFirstLine(maxSize, size, spacing, total)
        local line, placed = 0, 0
        for _ = 1, total do
            local nextSize = line > 0 and line + size or size
            if line > 0 and nextSize > maxSize then break end
            line = nextSize + spacing
            placed = placed + 1
        end
        return placed
    end

    it("lets exactly count icons onto one line and wraps the next", function()
        local R = L.loadPartyBuffsRules()
        local cases = {
            { size = 16, spacing = 0, count = 1 },
            { size = 16, spacing = 10, count = 8 },
            { size = 72, spacing = 0, count = 8 },
            { size = 72, spacing = 10, count = 1 },
            { size = 36, spacing = 1, count = 4 },
            { size = 36.6, spacing = 0.4, count = 7 },
            { size = 17.3, spacing = 9.7, count = 8 },
        }
        for _, case in ipairs(cases) do
            local db = { IconSpacing = case.spacing }
            local name = case.size .. "/" .. case.spacing .. "/" .. case.count
            assert.are.equal(case.count,
                iconsOnFirstLine(R.LineSize(db, case.count, case.size), case.size, case.spacing, case.count + 1),
                name)
        end
    end)
end)

describe("PartyBuffsRules.RowLayout", function()
    -- Returns: step, buff column, buff line, buffs per line, holder width, holder height.
    local function layoutDb(buffs)
        return { IconSpacing = 1, MaxPerMember = buffs or 4, MaxCooldownIcons = 4 }
    end

    it("continues the cells' line while cells plus buffs fit in perRow, as every row does at 14", function()
        local R = L.loadPartyBuffsRules()
        local db = layoutDb()
        assert.are.same({ 4, 2 }, { R.CellCount(6, db), R.CellCount(2, db) })
        local cases = {
            { name = "at 14, with cells", cells = 4, perRow = 14, want = { 37, 4, 0, 4, 295, 36 } },
            { name = "at 14, no cells", cells = 0, perRow = 14, want = { 37, 0, 0, 4, 147, 36 } },
            { name = "one column to spare", cells = 1, perRow = 6, want = { 37, 1, 0, 4, 184, 36 } },
            { name = "exactly full", cells = 2, perRow = 6, want = { 37, 2, 0, 4, 221, 36 } },
        }
        for _, case in ipairs(cases) do
            assert.are.same(case.want, { R.RowLayout(db, case.cells, case.perRow, 36) }, case.name)
        end
    end)

    it("starts the buffs at column 0 of the line after the cells when the row overflows", function()
        local R = L.loadPartyBuffsRules()
        local cases = {
            { name = "cells end part-way along a line", cells = 5, perRow = 3, want = { 37, 0, 2, 3, 110, 147 } },
            { name = "cells fill their last line", cells = 3, perRow = 3, want = { 37, 0, 1, 3, 110, 110 } },
            { name = "no cells", cells = 0, perRow = 3, want = { 37, 0, 0, 3, 110, 73 } },
            { name = "fewer buffs than perRow: lines buff-wide, holder exact", cells = 2, buffs = 1, perRow = 2,
              want = { 37, 0, 1, 1, 73, 73 } },
            { name = "no buffs", cells = 4, buffs = 0, perRow = 3, want = { 37, 0, 2, 0, 110, 73 } },
        }
        for _, case in ipairs(cases) do
            assert.are.same(case.want, { R.RowLayout(layoutDb(case.buffs), case.cells, case.perRow, 36) },
                case.name)
        end
    end)
end)

describe("PartyBuffsRules.NeedsPin and RecordPin", function()
    it("re-pins when the corner, x or y alone differs and not when all three match", function()
        local R = L.loadPartyBuffsRules()
        local slot = { corner = "TOPLEFT", pinX = 37, pinY = 0 }
        local cases = {
            { name = "all match", corner = "TOPLEFT", x = 37, y = 0, want = false },
            { name = "corner only", corner = "TOPRIGHT", x = 37, y = 0, want = true },
            { name = "x only", corner = "TOPLEFT", x = 74, y = 0, want = true },
            { name = "y only", corner = "TOPLEFT", x = 37, y = -37, want = true },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.want, R.NeedsPin(slot, case.corner, case.x, case.y), case.name)
        end
    end)

    it("clears the record after a refused pin so the same target pins again, and keeps a placed one", function()
        local R = L.loadPartyBuffsRules()
        local slot = {}
        R.RecordPin(slot, true, "BOTTOMLEFT", 0, 74)
        assert.is_false(R.NeedsPin(slot, "BOTTOMLEFT", 0, 74))
        R.RecordPin(slot, false)
        assert.are.same({}, slot)
        assert.is_true(R.NeedsPin(slot, "BOTTOMLEFT", 0, 74))
    end)
end)

describe("PartyBuffsRules.NeedsLayout", function()
    it("lays the row out again when the cell count, the icons per row or the corner alone moved", function()
        local R = L.loadPartyBuffsRules()
        local slot = { cellCount = 4, layoutPerRow = 14, layoutCorner = "TOPLEFT" }
        local cases = {
            { name = "all match", cells = 4, perRow = 14, corner = "TOPLEFT", want = false },
            { name = "cell count only", cells = 5, perRow = 14, corner = "TOPLEFT", want = true },
            { name = "icons per row only", cells = 4, perRow = 3, corner = "TOPLEFT", want = true },
            { name = "corner only", cells = 4, perRow = 14, corner = "TOPRIGHT", want = true },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.want, R.NeedsLayout(slot, case.cells, case.perRow, case.corner), case.name)
        end
    end)
end)

describe("PartyBuffsRules.NeedsResize", function()
    it("re-dresses when never dressed or dressed at another size, and not at the same size", function()
        local R = L.loadPartyBuffsRules()
        local cases = {
            { name = "never dressed", dressed = nil, size = 32, want = true },
            { name = "same size", dressed = 32, size = 32, want = false },
            { name = "another size", dressed = 36, size = 32, want = true },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.want, R.NeedsResize(case.dressed, case.size), case.name)
        end
    end)
end)

describe("PartyBuffsRules.BuildGroupConfig cell trinkets", function()
    it("leaves trinkets with a cooldown icon out of the Trinkets group only", function()
        local R = L.loadPartyBuffsRules()
        local byKey = {}
        for _, category in ipairs(R.CATEGORIES) do byKey[category.key] = category end
        local cells = { [111] = true }
        local cases = {
            { name = "trinket with cells", key = "trinket", cells = cells, want = cells },
            { name = "trinket without cells", key = "trinket" },
            { name = "potion ignores cells", key = "potion", cells = cells },
        }
        for _, case in ipairs(cases) do
            local _, candidates = R.BuildGroupConfig(byKey[case.key], makeDb({}), case.cells)
            assert.are.equal(case.want, candidates.excludeSpellIDs, case.name)
        end
    end)
end)

describe("PartyBuffsRules.PreviewSamples", function()
    it("lists the switched-on samples from the row's own, with the list's first as the stand-in", function()
        local R = L.loadPartyBuffsRules()
        local samples = { { potion = 30 }, { potion = 40 }, { potion = 50 } }
        local on, off = { enabled = true }, { enabled = false }
        local cases = {
            { name = "starts at the row's own and wraps", k = 2, list = { [30] = on, [40] = on, [50] = on },
              want = { 40, 50, 30 } },
            { name = "switched off, absent or malformed left out", k = 2,
              list = { [30] = on, [40] = off, [50] = true }, want = { 30 } },
            { name = "skip leaves a sample out", k = 1, list = { [30] = on, [40] = on }, skip = { [30] = true },
              want = { 40 } },
            { name = "no sample switched on: the list's first", k = 2, list = { [20] = on, [40] = off },
              want = { 20 } },
            { name = "nothing switched on", k = 2, list = { [40] = off }, want = {} },
        }
        for _, case in ipairs(cases) do
            assert.are.same(case.want, R.PreviewSamples(samples, case.k, "potion", case.list, case.skip), case.name)
        end
    end)
end)

describe("PartyBuffsRules.SplitBuffSamples", function()
    it("deals the cap evenly over the categories, passing a short category's share on", function()
        local R = L.loadPartyBuffsRules()
        local cases = {
            { name = "even, remainder to the earlier", cap = 5, available = { 4, 4, 4 }, want = { 2, 2, 1 } },
            { name = "a short category passes its share on", cap = 6, available = { 1, 4, 4 },
              want = { 1, 3, 2 } },
            { name = "a cap past every sample stops at the samples", cap = 8, available = { 1, 2 },
              want = { 1, 2 } },
        }
        for _, case in ipairs(cases) do
            assert.are.same(case.want, R.SplitBuffSamples(case.cap, case.available), case.name)
        end
    end)
end)

describe("PartyBuffsRules.KeepRow", function()
    it("keeps a row through a roster change only for the same member on a frame still showing its token", function()
        local R = L.loadPartyBuffsRules()
        local bound = { token = "party1" }
        local fixed = { token = "player", fixed = true }
        local cases = {
            { name = "same member, same frame unit", binding = bound, frame = "party1", same = true, want = true },
            { name = "frame re-sorted to another unit", binding = bound, frame = "party2", same = true, want = false },
            { name = "fixed token, frame shows a vehicle", binding = fixed, frame = "vehicle", same = true, want = true },
            { name = "token names someone else", binding = bound, frame = "party1", same = false, want = false },
            { name = "no binding", binding = nil, frame = "party1", same = true, want = false },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.want, R.KeepRow(case.binding, case.frame, case.same), case.name)
        end
    end)
end)

describe("PartyBuffsRules.MatchSlots", function()
    it("returns each binding to the slot holding its token and fills free slots in order", function()
        local R = L.loadPartyBuffsRules()
        local function b(token) return { token = token } end
        local function tokens(placed, n)
            local out = {}
            for k = 1, n do out[k] = placed[k] and placed[k].token or "-" end
            return out
        end
        local cases = {
            { name = "found in a new order", found = { b("party2"), b("party1") }, units = { "party1", "party2" },
              want = { "party1", "party2", "-" } },
            { name = "a newcomer takes the freed slot", found = { b("party3"), b("party1") }, units = { "party1", "party2" },
              want = { "party1", "party3", "-" } },
            { name = "more frames than slots", found = { b("party1"), b("party2"), b("party3") }, units = {},
              want = { "party1", "party2" } },
        }
        for _, case in ipairs(cases) do
            local n = #case.want
            assert.are.same(case.want, tokens(R.MatchSlots(case.found, case.units, n), n), case.name)
        end
    end)
end)

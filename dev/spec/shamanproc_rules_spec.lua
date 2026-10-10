-- Modules/ClassUtilities/ShamanProcRules.lua -- the rules a later edit breaks
-- silently: which trackers a character gets, how long each counts, whose spec
-- change re-reads talents, which cooldown announcement starts which tracker,
-- when an announcement is refused, and how much of a countdown is left. Talent
-- reads and secret flags are passed in, so no Blizzard fake is needed.
local L = require("dev.spec._ke_loader")

describe("shaman proc rules", function()
    local Rules

    before_each(function()
        Rules = L.loadShamanProcRules().ShamanProcRules
    end)

    it("activates a tracker only for a Shaman with its box ticked and its talent known", function()
        local NIL = {}
        local function reader(reads)
            return function(id)
                local value = reads[id]
                if value == NIL then return nil end
                return value
            end
        end
        local both = { TrackNaturesGuardian = true, TrackThunderousPaws = true }
        local talented = { [30884] = true, [378075] = true }
        -- class, db, talent reads, expected keys
        local cases = {
            { "SHAMAN", both, talented, { "NaturesGuardian", "ThunderousPaws" } },
            { "MAGE", both, talented, {} },
            { "SHAMAN", { TrackNaturesGuardian = false, TrackThunderousPaws = true }, talented, { "ThunderousPaws" } },
            { "SHAMAN", { TrackNaturesGuardian = true, TrackThunderousPaws = false }, talented, { "NaturesGuardian" } },
            { "SHAMAN", both, { [30884] = false, [378075] = true }, { "ThunderousPaws" } },
            { "SHAMAN", both, { [30884] = true, [378075] = NIL }, { "NaturesGuardian" } },
        }
        for i, case in ipairs(cases) do
            assert.same(case[4], Rules.ActiveTrackers(case[1], case[2], reader(case[3])), "case " .. i)
        end
    end)

    it("counts 45 s, 30 s with Natural Harmony, 35 s with it in PvP, and 20 s for Paws", function()
        -- key, has Natural Harmony, in PvP, expected seconds
        local cases = {
            { "NaturesGuardian", false, false, 45 },
            { "NaturesGuardian", false, true, 45 },
            { "NaturesGuardian", true, false, 30 },
            { "NaturesGuardian", true, true, 35 },
            { "ThunderousPaws", false, false, 20 },
            { "ThunderousPaws", true, true, 20 },
        }
        for i, case in ipairs(cases) do
            assert.equals(case[4], Rules.Length(case[1], case[2], case[3]), "case " .. i)
        end
    end)

    it("treats arenas and battlegrounds as PvP and nothing else", function()
        local cases = {
            { "arena", true }, { "pvp", true },
            { "party", false }, { "raid", false }, { "scenario", false }, { "none", false },
        }
        for i, case in ipairs(cases) do
            assert.equals(case[2], Rules.IsPvPInstance(case[1]), "case " .. i)
        end
    end)

    it("re-reads talents for the player's own spec change or a unit flagged secret only", function()
        -- unit, unit secret, expected
        local cases = {
            { "player", false, true },
            { "party1", false, false },
            { "party1", true, true },
        }
        for i, case in ipairs(cases) do
            assert.equals(case[3], Rules.IsOwnSpecChange(case[1], case[2]), "case " .. i)
        end
    end)

    it("maps only the proc ids to a tracker and never looks up an id flagged secret", function()
        -- spell id, spell id secret, base id, base id secret, expected key
        local cases = {
            { 31616, false, nil, false, "NaturesGuardian" },
            { 445698, false, nil, false, "NaturesGuardian" },
            { 378076, false, nil, false, "ThunderousPaws" },
            { 2645, false, 2645, false, nil },
            { 382216, false, nil, false, nil },
            { 30884, false, nil, false, nil },
            { 378075, false, nil, false, nil },
            { nil, false, nil, false, nil },
            { 2645, false, 378076, false, "ThunderousPaws" },
            { 31616, true, 378076, false, "ThunderousPaws" },
            { 31616, true, 445698, true, nil },
        }
        for i, case in ipairs(cases) do
            assert.equals(case[5], Rules.TrackerForPing(case[1], case[2], case[3], case[4]), "case " .. i)
        end
    end)

    it("refuses an announcement inside the ignore window or while its clock runs", function()
        -- now, ignore until, started at, length, accepted
        local cases = {
            { 100, 101, nil, nil, false },
            { 101, 101, nil, nil, true },
            { 105, nil, 80, 30, false },
            { 110, nil, 80, 30, true },
            { 50, nil, nil, nil, true },
        }
        for i, case in ipairs(cases) do
            assert.equals(case[5], Rules.AcceptPing(case[1], case[2], case[3], case[4]), "case " .. i)
        end
    end)

    it("reports the time left only while a clock runs", function()
        -- now, started at, length, expected remaining
        local cases = {
            { 100, nil, nil, nil },
            { 100, 80, 30, 10 },
            { 109.5, 80, 30, 0.5 },
            { 110, 80, 30, nil },
            { 120, 80, 30, nil },
        }
        for i, case in ipairs(cases) do
            assert.equals(case[4], Rules.Remaining(case[1], case[2], case[3]), "case " .. i)
        end
    end)
end)

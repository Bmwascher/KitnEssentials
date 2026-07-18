-- Tier 1: DungeonTrash pure inference core (Modules/DungeonTimers/Trash/TrashInference.lua).
-- The engine's identity-scoring, cast-matching, and cd-scheduling math is pure
-- Lua — it takes an identity/observation snapshot and returns a decision, with
-- no WoW API and no per-nameplate state (that lives in DungeonTrash.lua). So it
-- is fully testable headlessly, and MUST be: a wrong tolerance or a flipped
-- reject turns into a silently-missed (or falsely-fired) trash alert in-game
-- with no stack trace. These specs pin the ported ExBoss semantics.

local helpers = require("dev.spec._helpers")

-- Load TrashInference (pure) plus the real data files onto one KE, so the
-- decoder can be round-tripped against the shipped identity tables and
-- BuildCandidates can be smoke-tested against real dungeon data.
local function loadInference()
    _G.KitnEssentials = _G.KitnEssentials or {}
    local KE = {}
    helpers.loadModule("Modules/DungeonTimers/Trash/TrashTraits.lua", KE)
    helpers.loadModule("Modules/DungeonTimers/Trash/TrashData.lua", KE)
    helpers.loadModule("Modules/DungeonTimers/Trash/TrashInference.lua", KE)
    return KE.TrashInference, KE
end

describe("DungeonTrash inference — _r decoder", function()
    local TI, KE
    setup(function() TI, KE = loadInference() end)

    it("round-trips every shipped trait's packedIdentity to its stored identity", function()
        local mismatches = {}
        for npcID, trait in pairs(KE.TrashTraits) do
            local decoded = TI.DecodePackedIdentity(trait.packedIdentity)
            for field, want in pairs(trait.identity) do
                if decoded[field] ~= want then
                    mismatches[#mismatches + 1] = string.format(
                        "npc %s field %s: decoded %s != stored %s",
                        tostring(npcID), field, tostring(decoded[field]), tostring(want))
                end
            end
        end
        assert.same({}, mismatches)
    end)
end)

describe("DungeonTrash inference — Layer1 ScoreTraitRow", function()
    local TI
    setup(function() TI = loadInference() end)

    local function trait(identity, extra)
        local t = { identity = identity, placement = "" }
        for k, v in pairs(extra or {}) do t[k] = v end
        return t
    end
    local BASE = { level = 91, sex = 1, power = 1, classID = 2, buffCount = 0, nonElite = false }

    it("matches an exact identity and scores each field", function()
        local ok, score = TI.ScoreTraitRow(
            { level = 91, sex = 1, power = 1, classID = 2, buffCount = 0, unitClassification = "elite" },
            trait(BASE))
        assert.is_true(ok)
        assert.is_true(score >= 5)
    end)

    it("accepts the level-squish alternate (template - 60)", function()
        local ok = TI.ScoreTraitRow(
            { level = 31, sex = 1, power = 1, classID = 2, buffCount = 0, unitClassification = "elite" },
            trait(BASE))
        assert.is_true(ok)
    end)

    it("hard-rejects an observed level above the row (boss-tier plate)", function()
        local ok, _, _, reason = TI.ScoreTraitRow(
            { level = 92, sex = 1, power = 1, classID = 2, buffCount = 0, unitClassification = "elite" },
            trait(BASE))
        assert.is_false(ok)
        assert.equals("level-above", reason)
    end)

    it("keeps a lower observed level as a soft non-match (downward scaling drift)", function()
        local ok, _, _, reason, levelAgreed = TI.ScoreTraitRow(
            { level = 90, sex = 1, power = 1, classID = 2, buffCount = 0, unitClassification = "elite" },
            trait(BASE))
        assert.is_true(ok)
        assert.is_nil(reason)
        assert.is_false(levelAgreed)
    end)

    it("hard-rejects an observed buff count below the row (Maisara warrior signature)", function()
        local id = { level = 91, sex = 1, power = 1, classID = 1, buffCount = 1, nonElite = false }
        local ok, _, _, reason = TI.ScoreTraitRow(
            { level = 90, sex = 1, power = 1, classID = 1, buffCount = 0, unitClassification = "elite" },
            trait(id))
        assert.is_false(ok)
        assert.equals("buffcount-below", reason)
    end)

    it("keeps an inflated observed buff count as a soft non-match (proto-drake drift)", function()
        local id = { level = 91, sex = 1, power = 1, classID = 1, buffCount = 1, nonElite = false }
        local ok, _, _, reason = TI.ScoreTraitRow(
            { level = 91, sex = 1, power = 1, classID = 1, buffCount = 3, unitClassification = "elite" },
            trait(id))
        assert.is_true(ok)
        assert.is_nil(reason)
    end)

    it("hard-rejects a mismatched exact field", function()
        local ok, _, _, reason = TI.ScoreTraitRow(
            { level = 91, sex = 0, power = 1, classID = 2, buffCount = 0 }, trait(BASE))
        assert.is_false(ok)
        assert.equals("sex", reason)
    end)

    it("rejects an elite row when the plate is not elite", function()
        local ok, _, _, reason = TI.ScoreTraitRow(
            { level = 91, sex = 1, power = 1, classID = 2, buffCount = 0, unitClassification = "normal" },
            trait(BASE))
        assert.is_false(ok)
        assert.equals("classification", reason)
    end)

    it("rejects a row with no cast spell once a cast was seen", function()
        local id = { level = 91, sex = 1, power = 1, classID = 2, buffCount = 0, nonElite = false, hasCastSpell = false }
        local ok, _, _, reason = TI.ScoreTraitRow(
            { level = 91, sex = 1, power = 1, classID = 2, buffCount = 0, unitClassification = "elite", sawCastStart = true },
            trait(id))
        assert.is_false(ok)
        assert.equals("saw-cast-no-cast-spell", reason)
    end)

    it("rejects an interrupt on a cannot-interrupt row", function()
        local id = { level = 91, sex = 1, power = 1, classID = 2, buffCount = 0, nonElite = false, cannotInterrupt = true }
        local ok, _, _, reason = TI.ScoreTraitRow(
            { level = 91, sex = 1, power = 1, classID = 2, buffCount = 0, unitClassification = "elite", sawInterrupted = true },
            trait(id))
        assert.is_false(ok)
        assert.equals("saw-interrupt-but-cannot", reason)
    end)

    -- buffCount is a SOFT tiebreak, NOT a hard reject: a live aura count drifts
    -- across affix/patch/key (12.0 can't source-filter auras), so a mismatch
    -- must still MATCH (Layer2 casts resolve the collision) — only scoring lower.
    it("does not reject a drifted buffCount — soft tiebreak, scores lower", function()
        local match = TI.ScoreTraitRow(
            { level = 91, sex = 1, power = 1, classID = 2, buffCount = 0, unitClassification = "elite" }, trait(BASE))
        local okDrift, scoreDrift = TI.ScoreTraitRow(
            { level = 91, sex = 1, power = 1, classID = 2, buffCount = 3, unitClassification = "elite" }, trait(BASE))
        local _, scoreMatch = TI.ScoreTraitRow(
            { level = 91, sex = 1, power = 1, classID = 2, buffCount = 0, unitClassification = "elite" }, trait(BASE))
        assert.is_true(match)                     -- exact buffCount matches
        assert.is_true(okDrift)                   -- drifted buffCount STILL matches
        assert.is_true(scoreMatch > scoreDrift)   -- but the exact one outscores it
    end)
end)

describe("DungeonTrash inference — placement gate", function()
    local TI
    setup(function() TI = loadInference() end)

    it("allows an empty placement", function()
        assert.is_true(TI.IsPlacementAllowed("", {}))
    end)

    it("exempts Algeth'ar Academy (map 2526)", function()
        assert.is_true(TI.IsPlacementAllowed("1", { mapID = 2526, bossProgressIndex = 5 }))
    end)

    it("matches a stage index", function()
        assert.is_true(TI.IsPlacementAllowed("2,4", { bossProgressIndex = 4 }))
        assert.is_false(TI.IsPlacementAllowed("2,4", { bossProgressIndex = 3 }))
    end)

    it("matches a sub-zone mapID (>20)", function()
        assert.is_true(TI.IsPlacementAllowed("2493,2494", { currentSubZoneMapID = 2494 }))
        assert.is_false(TI.IsPlacementAllowed("2493,2494", { currentSubZoneMapID = 9999 }))
    end)

    it("fails open when the constraint kind's runtime datum is unknown", function()
        assert.is_true(TI.IsPlacementAllowed("2,4", {}))            -- stage constraint, no bossProgressIndex
        assert.is_true(TI.IsPlacementAllowed("2493", {}))          -- map constraint, no sub-zone
    end)

    -- The second tier of the map-token match (reference: IsCurrentPlacementID):
    -- a token that is an areaID, not a uiMapID, matches by its C_Map.GetAreaInfo
    -- NAME against the live zone text. Nexus-Point Xenas ships areaID tokens
    -- (16573-16576) — with only the uiMapID tier, a known sub-zone would
    -- hard-reject all five of its mobs' own rows.
    it("matches an areaID token via the resolveAreaName name tier", function()
        local resolve = function(id) return id == 16573 and "Xenas Deck" or nil end
        assert.is_true(TI.IsPlacementAllowed("16573,16574", {
            currentSubZoneMapID = 2940, currentZoneText = "Xenas Deck", resolveAreaName = resolve }))
        assert.is_false(TI.IsPlacementAllowed("16573,16574", {
            currentSubZoneMapID = 2940, currentZoneText = "Elsewhere", resolveAreaName = resolve }))
    end)

    it("rejects only when both tiers miss with data present; empty zone text is 'unknown'", function()
        local resolve = function() return nil end
        -- sub-zone known + zone text known + neither matches → reject
        assert.is_false(TI.IsPlacementAllowed("16573", {
            currentSubZoneMapID = 2940, currentZoneText = "Elsewhere", resolveAreaName = resolve }))
        -- empty-string zone text counts as unknown; with no sub-zone either → fail open
        assert.is_true(TI.IsPlacementAllowed("16573", {
            currentZoneText = "", resolveAreaName = resolve }))
    end)

    -- Mixed rows AND the two kinds (reference: the map gate rejects BEFORE the
    -- stage check and vice versa — a known-mismatched tier vetoes the other's
    -- match). No shipped row mixes kinds yet; this pins the semantics for the
    -- first extractor/curated row that does.
    it("ANDs the stage and map tiers on a mixed row", function()
        local resolve = function(id) return id == 16575 and "Xenas Deck" or nil end
        -- stage mismatch + map match → reject
        assert.is_false(TI.IsPlacementAllowed("3,16575", {
            bossProgressIndex = 2, currentSubZoneMapID = 2940,
            currentZoneText = "Xenas Deck", resolveAreaName = resolve }))
        -- stage match + map mismatch → reject
        assert.is_false(TI.IsPlacementAllowed("3,16575", {
            bossProgressIndex = 3, currentSubZoneMapID = 2940,
            currentZoneText = "Elsewhere", resolveAreaName = resolve }))
        -- both match → allow
        assert.is_true(TI.IsPlacementAllowed("3,16575", {
            bossProgressIndex = 3, currentSubZoneMapID = 2940,
            currentZoneText = "Xenas Deck", resolveAreaName = resolve }))
        -- a tier with an unknown runtime datum fails open; the other decides
        assert.is_true(TI.IsPlacementAllowed("3,16575", {
            currentSubZoneMapID = 2940, currentZoneText = "Xenas Deck",
            resolveAreaName = resolve }))
    end)
end)

describe("DungeonTrash inference — BuildCandidates", function()
    local TI
    setup(function() TI = loadInference() end)

    local traits = {
        [111] = { npcID = 111, name = "A", dungeonKey = "X", placement = "",
                  identity = { level = 80, sex = 1, power = 0, classID = 1, buffCount = 0, nonElite = true } },
        [222] = { npcID = 222, name = "B", dungeonKey = "X", placement = "",
                  identity = { level = 80, sex = 0, power = 0, classID = 1, buffCount = 0, nonElite = true } },
        [333] = { npcID = 333, name = "C", dungeonKey = "Y", placement = "",
                  identity = { level = 80, sex = 1, power = 0, classID = 1, buffCount = 0, nonElite = true } },
    }

    it("resolves to a single candidate on a unique fingerprint", function()
        local cands, resolved = TI.BuildCandidates(
            { level = 80, sex = 1, power = 0, classID = 1, buffCount = 0, unitClassification = "normal" },
            { traits = traits, dungeonKey = "X" })
        assert.equals(1, #cands)
        assert.equals(111, resolved)
    end)

    it("only considers rows from the requested dungeon", function()
        -- npc 333 is dungeon Y; the same fingerprint must not surface it under X.
        local cands = TI.BuildCandidates(
            { level = 80, sex = 1, power = 0, classID = 1, buffCount = 0, unitClassification = "normal" },
            { traits = traits, dungeonKey = "X" })
        for _, c in ipairs(cands) do assert.not_equals(333, c.npcID) end
    end)

    -- The Pit of Saron drake/Glacieth case: two mobs identical but for buffCount.
    -- Under a drifted live count neither exact-matches, so BOTH survive as
    -- candidates (unresolved) and the observed cast disambiguates downstream —
    -- instead of the old hard reject zeroing the pool and firing nothing.
    it("keeps both buffCount-collision mobs as candidates under aura drift", function()
        local collide = {
            [10] = { npcID = 10, name = "Drake", dungeonKey = "P", placement = "",
                identity = { level = 91, sex = 1, power = 1, classID = 1, buffCount = 1, nonElite = false } },
            [20] = { npcID = 20, name = "Glacieth", dungeonKey = "P", placement = "",
                identity = { level = 91, sex = 1, power = 1, classID = 1, buffCount = 0, nonElite = false } },
        }
        local cands, resolved = TI.BuildCandidates(
            { level = 91, sex = 1, power = 1, classID = 1, buffCount = 3, unitClassification = "elite" },
            { traits = collide, dungeonKey = "P" })
        assert.equals(2, #cands)
        assert.is_nil(resolved)
    end)

    it("Academy forces-% routing keeps only the resolved npc", function()
        local academy = {
            [197219] = { npcID = 197219, name = "Lasher", dungeonKey = "AlgetharAcademy", placement = "",
                identity = { level = 91, sex = 1, power = 1, classID = 1, buffCount = 0, nonElite = false } },
            [192333] = { npcID = 192333, name = "Eagle", dungeonKey = "AlgetharAcademy", placement = "",
                identity = { level = 91, sex = 1, power = 1, classID = 1, buffCount = 0, nonElite = false } },
        }
        local _, resolved = TI.BuildCandidates(
            { level = 91, sex = 1, power = 1, classID = 1, buffCount = 0, unitClassification = "elite" },
            { traits = academy, dungeonKey = "AlgetharAcademy", mapID = 2526,
              forcesPercent = 30 })
        assert.equals(192333, resolved)   -- 30% → >26 && <42 → Eagle
    end)

    -- DA's newer fork (adopted over ExBoss's older 196671 hard-route, which
    -- misidentified eagle/tamer mobs in every non-M+ run): UNKNOWN forces
    -- (nil percent) SKIP the Academy prune entirely — both routed candidates
    -- survive, resolution stays ambiguous, and Layer2 cast behavior decides.
    -- The caller must still pass nil (never 0) for unknown.
    it("Academy routing with unknown forces skips the prune (Layer2 decides)", function()
        local academy = {
            [197219] = { npcID = 197219, name = "Lasher", dungeonKey = "AlgetharAcademy", placement = "",
                identity = { level = 91, sex = 1, power = 1, classID = 1, buffCount = 0, nonElite = false } },
            [196671] = { npcID = 196671, name = "Invalid", dungeonKey = "AlgetharAcademy", placement = "",
                identity = { level = 91, sex = 1, power = 1, classID = 1, buffCount = 0, nonElite = false } },
        }
        local cands, resolved = TI.BuildCandidates(
            { level = 91, sex = 1, power = 1, classID = 1, buffCount = 0, unitClassification = "elite" },
            { traits = academy, dungeonKey = "AlgetharAcademy", mapID = 2526 })
        assert.is_nil(resolved)
        assert.equals(2, #cands)
        assert.is_nil(TI.ResolveAcademyForcesNPC(nil))
    end)

    -- DA-only Skyreach rule: the Suntalon Tamer (76154) only spawns inside
    -- the 52-60% enemy-forces window, so a KNOWN percent outside it prunes
    -- the tamer from MULTI-candidate sets. In-window and unknown percents
    -- keep it; a lone-survivor tamer is never pruned (Layer2 verifies it).
    it("Skyreach tamer prunes outside the 52-60% forces window", function()
        local sky = {
            [76154] = { npcID = 76154, name = "Tamer", dungeonKey = "Skyreach", placement = "",
                identity = { level = 82, sex = 1, power = 1, classID = 1, buffCount = 0, nonElite = false } },
            [76155] = { npcID = 76155, name = "Other", dungeonKey = "Skyreach", placement = "",
                identity = { level = 82, sex = 1, power = 1, classID = 1, buffCount = 0, nonElite = false } },
        }
        local obs = { level = 82, sex = 1, power = 1, classID = 1, buffCount = 0,
            unitClassification = "elite" }
        local cands, resolved = TI.BuildCandidates(obs,
            { traits = sky, dungeonKey = "Skyreach", mapID = 1209, forcesPercent = 70 })
        assert.equals(1, #cands)          -- outside the window: tamer pruned
        assert.equals(76155, resolved)
        cands = TI.BuildCandidates(obs,
            { traits = sky, dungeonKey = "Skyreach", mapID = 1209, forcesPercent = 55 })
        assert.equals(2, #cands)          -- in-window: both survive
        cands = TI.BuildCandidates(obs,
            { traits = sky, dungeonKey = "Skyreach", mapID = 1209 })
        assert.equals(2, #cands)          -- unknown forces: ungated
    end)

    it("a lone-survivor Skyreach tamer is never pruned", function()
        local sky = {
            [76154] = { npcID = 76154, name = "Tamer", dungeonKey = "Skyreach", placement = "",
                identity = { level = 82, sex = 1, power = 1, classID = 1, buffCount = 0, nonElite = false } },
        }
        local cands = TI.BuildCandidates(
            { level = 82, sex = 1, power = 1, classID = 1, buffCount = 0,
              unitClassification = "elite" },
            { traits = sky, dungeonKey = "Skyreach", mapID = 1209, forcesPercent = 70 })
        assert.equals(1, #cands)
        assert.equals(76154, cands[1].npcID)
    end)

    it("smoke: a real Windrunner mob's identity resolves it against shipped data", function()
        local _, KE = loadInference()
        local ti = KE.TrashInference
        -- Spellguard Magus (232113) — pick its identity straight from the data.
        local magus = KE.TrashTraits[232113]
        assert.is_table(magus)
        local obs = {}
        for k, v in pairs(magus.identity) do obs[k] = v end
        obs.unitClassification = magus.identity.nonElite and "normal" or "elite"
        local cands = ti.BuildCandidates(obs, { dungeonKey = "WindrunnerSpire", traits = KE.TrashTraits })
        local found = false
        for _, c in ipairs(cands) do if c.npcID == 232113 then found = true end end
        assert.is_true(found)
    end)

    it("regression: a level-90 read does not collapse the Maisara pull onto the lone level-90 Eagle", function()
        local _, KE = loadInference()
        local ti = KE.TrashInference
        -- The Hexbound Eagle (249020) is the ONLY curated level-90 Maisara mob;
        -- the sex=1/power=1 mobs Hulking Juggernaut (248678) and Bound Defender
        -- (249025) are curated level 91. In the live key these read as level 90, so
        -- a HARD level reject pruned every 91-row and collapsed the whole pull onto
        -- the Eagle. With SOFT level the 91-rows must survive → the Eagle is never a
        -- confident lone resolve; disambiguation defers to Layer2 cast duration.
        local obs = { level = 90, sex = 1, power = 1, unitClassification = "elite" }
        local cands, resolved = ti.BuildCandidates(
            obs, { dungeonKey = "MaisaraCaverns", traits = KE.TrashTraits })
        assert.is_true(#cands >= 2)                 -- Eagle + the 91-rows coexist
        assert.are_not.equal(249020, resolved)      -- never a lone-Eagle collapse
    end)

    it("resolve-confidence: a LONE survivor whose level DISAGREES defers, not resolves", function()
        local _, KE = loadInference()
        local ti = KE.TrashInference
        -- Rokh'zal (253683) is the ONLY sex=2/power=0 Maisara mob → a lone Layer1
        -- survivor. Curated level 91; live read 90. It matched only the coarse
        -- sex/power triple, so it must NOT be rubber-stamped — stays unresolved and
        -- defers to a cast (this was the Rokh'zal false positive in-game 2026-07-07).
        local obs = { level = 90, sex = 2, power = 0, unitClassification = "elite" }
        local cands, resolved = ti.BuildCandidates(
            obs, { dungeonKey = "MaisaraCaverns", traits = KE.TrashTraits })
        assert.equals(1, #cands)                    -- uniquely matches Rokh'zal
        assert.is_nil(resolved)                     -- but level disagreed → deferred
    end)

    it("resolve-confidence: a LONE survivor whose level AGREES still resolves", function()
        local _, KE = loadInference()
        local ti = KE.TrashInference
        -- Dread Souleater (248686) is the ONLY sex=3/power=0 Maisara mob; live read
        -- level 91 matches its curated 91 → level agrees → confident lone resolve.
        local obs = { level = 91, sex = 3, power = 0, unitClassification = "elite" }
        local cands, resolved = ti.BuildCandidates(
            obs, { dungeonKey = "MaisaraCaverns", traits = KE.TrashTraits })
        assert.equals(1, #cands)
        assert.equals(248686, resolved)             -- level agreed → resolves
    end)
end)

describe("DungeonTrash inference — Layer2 SpellMatchesObserved", function()
    local TI
    setup(function() TI = loadInference() end)

    it("matches a cast within tolerance", function()
        assert.is_true(TI.SpellMatchesObserved({ castTime = 3.0 }, { kind = "cast", duration = 3.15 }))
        assert.is_false(TI.SpellMatchesObserved({ castTime = 3.0 }, { kind = "cast", duration = 3.5 }))
    end)

    it("matches a castTimeExtra alternate", function()
        assert.is_true(TI.SpellMatchesObserved(
            { castTime = 4.0, castTimeExtra = { 2.8 } }, { kind = "cast", duration = 2.75 }))
    end)

    it("matches a channel on channelTime", function()
        assert.is_true(TI.SpellMatchesObserved({ castTime = 0, channelTime = 6 }, { kind = "channel", duration = 6.1 }))
        assert.is_false(TI.SpellMatchesObserved({ castTime = 0 }, { kind = "channel", duration = 6.1 }))
    end)

    it("rejects on a disagreeing boolean fingerprint", function()
        assert.is_false(TI.SpellMatchesObserved(
            { castTime = 3, targetExists = true },
            { kind = "cast", duration = 3, fingerprints = { targetExists = false } }))
    end)

    it("ignores a fingerprint that was not sampled", function()
        assert.is_true(TI.SpellMatchesObserved(
            { castTime = 3, targetExists = true },
            { kind = "cast", duration = 3, fingerprints = {} }))
    end)
end)

describe("DungeonTrash inference — MatchesTwoPhaseCast (transition-pairing hold)", function()
    local TI
    setup(function() TI = loadInference() end)

    -- Arcane Sentry shape: a finished 3s bare cast could be the one-phase twin
    -- OR the two-phase spell's cast phase — the caller must hold the credit.
    local MOB = { spells = {
        [473258]  = { first = 24,   castTime = 3 },                  -- one-phase
        [1282050] = { first = 11.9, castTime = 3, channelTime = 5 }, -- two-phase
    } }

    it("is true when the cast duration fits a two-phase spell", function()
        assert.is_true(TI.MatchesTwoPhaseCast(MOB, { kind = "cast", duration = 3.05 }))
    end)

    it("is false when only one-phase spells fit the duration", function()
        local mob = { spells = {
            [1] = { first = 5, castTime = 3 },
            [2] = { first = 5, castTime = 6, channelTime = 4 },
        } }
        assert.is_false(TI.MatchesTwoPhaseCast(mob, { kind = "cast", duration = 3.0 }))
    end)

    it("is false for channels and for nil/short inputs", function()
        assert.is_false(TI.MatchesTwoPhaseCast(MOB, { kind = "channel", duration = 3.0 }))
        assert.is_false(TI.MatchesTwoPhaseCast(nil, { kind = "cast", duration = 3.0 }))
        assert.is_false(TI.MatchesTwoPhaseCast(MOB, nil))
    end)

    it("respects fingerprint disagreement like SpellMatchesObserved", function()
        local mob = { spells = {
            [1] = { first = 5, castTime = 3, channelTime = 5, targetExists = true },
        } }
        assert.is_false(TI.MatchesTwoPhaseCast(mob,
            { kind = "cast", duration = 3.0, fingerprints = { targetExists = false } }))
    end)
end)

describe("DungeonTrash inference — FilterCandidates", function()
    local TI
    setup(function() TI = loadInference() end)

    local DATA = {
        [1] = { spells = { [10] = { castTime = 3 } } },
        [2] = { spells = { [20] = { castTime = 6 } } },
    }
    local function dataByNpc(npc) return DATA[npc] end

    it("narrows to the candidate whose spell matches the duration", function()
        local cands = { { npcID = 1 }, { npcID = 2 } }
        local kept, resolved = TI.FilterCandidates(cands, { kind = "cast", duration = 3.0 }, dataByNpc)
        assert.equals(1, #kept)
        assert.equals(1, resolved)
    end)

    it("returns the original list (unresolved) when nothing matches", function()
        local cands = { { npcID = 1 }, { npcID = 2 } }
        local kept, resolved = TI.FilterCandidates(cands, { kind = "cast", duration = 99 }, dataByNpc)
        assert.equals(2, #kept)
        assert.is_nil(resolved)
    end)

    -- A LONE candidate is verified, not rubber-stamped: a level-disagreed lone
    -- survivor defers to Layer2 (BuildCandidates), and Layer2 resolves it only
    -- via an observed cast matching one of its curated spells — the reference
    -- runs Layer2 on every pass regardless of count. Rubber-stamping here would
    -- resurrect the Rokh'zal false positive through the back door; never
    -- resolving (the old caller-side #>1 gate) deadlocked the mob forever.
    it("verifies a lone candidate: resolves on a cast matching its spells", function()
        local kept, resolved = TI.FilterCandidates({ { npcID = 1 } }, { kind = "cast", duration = 3.0 }, dataByNpc)
        assert.equals(1, #kept)
        assert.equals(1, resolved)
    end)

    it("leaves a lone candidate unresolved when the cast matches none of its spells", function()
        local kept, resolved = TI.FilterCandidates({ { npcID = 1 } }, { kind = "cast", duration = 99 }, dataByNpc)
        assert.equals(1, #kept)
        assert.is_nil(resolved)
    end)

    it("tolerates a nil candidate list without indexing it", function()
        local kept, resolved = TI.FilterCandidates(nil, { kind = "cast", duration = 3 }, dataByNpc)
        assert.is_nil(kept)
        assert.is_nil(resolved)
    end)
end)

describe("DungeonTrash inference — FilterCandidates trait-duration keep tier", function()
    local TI
    setup(function() TI = loadInference() end)

    -- The Phantasmal Mystic class (reference: trait castTimeSet/channelTimeSet
    -- feed the Layer2 keep rules BEFORE curated spells): a mob's KNOWN filler
    -- cast — a duration in its trait set with no curated timer spell — must
    -- KEEP it in the pool / verify it, never read as disconfirming evidence
    -- that collapses the pool onto a same-duration fingerprint sibling (the
    -- Maisara Hexxer mislabel class, generalized).
    local DATA = {
        [111] = { spells = { [10] = { castTime = 4 } } },   -- true mob: curates only 4s
        [222] = { spells = { [20] = { castTime = 2.5 } } }, -- sibling: curates 2.5s
    }
    local TRAITS = {
        [111] = { castTimeSet = { 2.5, 3, 4 } },            -- 111 is KNOWN to cast 2.5/3 too
        [222] = { castTimeSet = { 2.5 } },
    }
    local dataByNpc = function(npc) return DATA[npc] end
    local traitByNpc = function(npc) return TRAITS[npc] end

    it("a known filler cast keeps the true mob — no collapse onto the sibling", function()
        local cands = { { npcID = 111 }, { npcID = 222 } }
        local kept, resolved = TI.FilterCandidates(cands,
            { kind = "cast", duration = 2.5 }, dataByNpc, traitByNpc)
        assert.equals(2, #kept)
        assert.is_nil(resolved)
    end)

    it("control: without the trait tier the same filler cast wrongly collapses", function()
        local cands = { { npcID = 111 }, { npcID = 222 } }
        local kept, resolved = TI.FilterCandidates(cands,
            { kind = "cast", duration = 2.5 }, dataByNpc)
        assert.equals(1, #kept)
        assert.equals(222, resolved)
    end)

    it("verifies a lone survivor on a trait-known filler duration", function()
        local kept, resolved = TI.FilterCandidates({ { npcID = 111 } },
            { kind = "cast", duration = 3.0 }, dataByNpc, traitByNpc)
        assert.equals(1, #kept)
        assert.equals(111, resolved)
    end)

    it("an unknown duration still fails the lone-survivor verify", function()
        local _, resolved = TI.FilterCandidates({ { npcID = 111 } },
            { kind = "cast", duration = 9.9 }, dataByNpc, traitByNpc)
        assert.is_nil(resolved)
    end)

    it("TraitDurationMatches is kind-aware and nil-safe", function()
        local trait = { castTimeSet = { 3 }, channelTimeSet = { 9 } }
        assert.is_true(TI.TraitDurationMatches(trait, { kind = "cast", duration = 3.1 }))
        assert.is_false(TI.TraitDurationMatches(trait, { kind = "channel", duration = 3.1 }))
        assert.is_true(TI.TraitDurationMatches(trait, { kind = "channel", duration = 9.0 }))
        assert.is_false(TI.TraitDurationMatches(nil, { kind = "cast", duration = 3 }))
        assert.is_false(TI.TraitDurationMatches({}, { kind = "cast", duration = 3 }))
    end)

    -- Audit F2 (2026-07-18): the old and/or select fell through to castTimeSet
    -- when a CHANNEL observation met a nil channelTimeSet — a real 2.5s channel
    -- kept a cast-only mob alive under fail-open routing (Riftbreath vs the
    -- cast-only Academy sibling). The reference consumes the sets independently.
    it("a channel observation never borrows castTimeSet when channelTimeSet is absent", function()
        local castOnly = { castTimeSet = { 2.5 } }
        assert.is_false(TI.TraitDurationMatches(castOnly, { kind = "channel", duration = 2.5 }))
        assert.is_true(TI.TraitDurationMatches(castOnly, { kind = "cast", duration = 2.5 }))
    end)

    -- Audit F1 (2026-07-18): the trait keep tier is FILLER-ONLY. In production
    -- both Skyreach twins' trait castTimeSet carry the shared 3s cast, so the
    -- old unconditional trait fallthrough revived the fingerprint-rejected twin
    -- and the pool never narrowed — the Batch E castStartChangeTarget splitter
    -- was dead with traitByNpc wired (the sampler spec above omits traitByNpc,
    -- which is why it stayed green). Reference: fingerprint narrowing is a
    -- separate FIRST stage; duration rules see only its survivors.
    it("the trait tier cannot revive a fingerprint-rejected twin (production shape)", function()
        local DATA2 = {
            [76149] = { spells = { [1258174] = { castTime = 3, castStartChangeTarget = true } } },
            [79303] = { spells = { [1254380] = { castTime = 3, castStartChangeTarget = false } } },
        }
        local TRAITS2 = {
            [76149] = { castTimeSet = { 3 } },
            [79303] = { castTimeSet = { 3 } },
        }
        local dataByNpc2 = function(npc) return DATA2[npc] end
        local traitByNpc2 = function(npc) return TRAITS2[npc] end
        local cands = { { npcID = 76149 }, { npcID = 79303 } }
        local kept, resolved = TI.FilterCandidates(cands,
            { kind = "cast", duration = 3.0, fingerprints = { castStartChangeTarget = true } },
            dataByNpc2, traitByNpc2)
        assert.equals(1, #kept)
        assert.equals(76149, resolved)
        -- An UNSAMPLED fingerprint is not a rejection: both twins full-match
        -- leniently and the pool stays ambiguous (never a false narrow).
        local kept2, resolved2 = TI.FilterCandidates(cands,
            { kind = "cast", duration = 3.0, fingerprints = {} }, dataByNpc2, traitByNpc2)
        assert.equals(2, #kept2)
        assert.is_nil(resolved2)
    end)

    it("a channel with evidence-rejecting channel spells cannot trait-verify (lone survivor)", function()
        -- Pure-channel mob + a PROVEN transition observation: the channel spell
        -- is evidence-rejected, and the trait channelTimeSet must not revive
        -- the verify (filler-only rule on the channel path).
        local mob = function() return { spells = { [1] = { castTime = 0, channelTime = 12 } } } end
        local trait = function() return { channelTimeSet = { 12 } } end
        local _, resolved = TI.FilterCandidates({ { npcID = 7 } },
            { kind = "channel", duration = 12, castIntoChannel = true }, mob, trait)
        assert.is_nil(resolved)
    end)
end)

describe("DungeonTrash inference — lone-survivor channel verification (Pass-2 shape)", function()
    local TI
    setup(function() TI = loadInference() end)

    -- Four shipped mobs' ONLY spell is a CAST_START grab/beam channel whose
    -- caster CHANNEL_STOP measures far short of curated channelTime
    -- (Plungegrip 0.85s vs 12s). A duration-gated lone-survivor verify made
    -- them permanently unresolvable once level disagreed: a kick bypasses the
    -- verify entirely, and a completion failed the gate. Channels verify by
    -- capability + channel evidence + fingerprints — exactly like
    -- InferSucceededSpell's Pass 2 — while casts keep the duration gate.
    local GARGOYLE = { spells = { [1258997] = { first = 9, castTime = 0, channelTime = 12 } } }
    local gargoyleByNpc = function() return GARGOYLE end

    it("verifies a channel-only lone survivor despite a short-measured STOP", function()
        local kept, resolved = TI.FilterCandidates({ { npcID = 252606 } },
            { kind = "channel", duration = 0.85 }, gargoyleByNpc)
        assert.equals(1, #kept)
        assert.equals(252606, resolved)
    end)

    it("does not channel-verify a mob with no channel-capable spell", function()
        local castOnly = function() return { spells = { [1] = { castTime = 3 } } } end
        local _, resolved = TI.FilterCandidates({ { npcID = 7 } },
            { kind = "channel", duration = 0.85 }, castOnly)
        assert.is_nil(resolved)
    end)

    it("channel evidence still discriminates: a PROVEN transition rejects a pure channel", function()
        local _, resolved = TI.FilterCandidates({ { npcID = 252606 } },
            { kind = "channel", duration = 0.85, castIntoChannel = true }, gargoyleByNpc)
        assert.is_nil(resolved)
    end)

    it("a disagreeing fingerprint still rejects the channel verify", function()
        local mob = function() return { spells = {
            [1] = { castTime = 0, channelTime = 12, targetExists = true } } } end
        local _, resolved = TI.FilterCandidates({ { npcID = 7 } },
            { kind = "channel", duration = 0.85,
              fingerprints = { targetExists = false } }, mob)
        assert.is_nil(resolved)
    end)

    it("cast observations keep the duration-gated verify", function()
        local mob = function() return { spells = { [1] = { castTime = 3 } } } end
        local _, resolved = TI.FilterCandidates({ { npcID = 7 } },
            { kind = "cast", duration = 9 }, mob)
        assert.is_nil(resolved)
    end)
end)

describe("DungeonTrash inference — ChannelEvidenceLocks (A5 resolve-without-lock)", function()
    local TI
    setup(function() TI = loadInference() end)

    -- A bare channel (castIntoChannel nil — KE never emits false) passes the
    -- Pass-2 verify shape through a TWO-PHASE spell's channelTime as easily as
    -- a pure channel's. The reference survives that lenient match because it
    -- never locks; KE's castConfirmed must not be earned by it — channel
    -- evidence locks only on a PROVEN transition or a fingerprint-agreeing
    -- PURE channel. Cast evidence is untouched (duration-gated).
    local twoPhaseOnly = { spells = { [1] = { castTime = 2, channelTime = 6 } } }
    local withPure = { spells = { [1] = { castTime = 2, channelTime = 6 },
        [2] = { castTime = 0, channelTime = 4 } } }

    it("cast evidence is always lock-eligible", function()
        assert.is_true(TI.ChannelEvidenceLocks(twoPhaseOnly, { kind = "cast", duration = 2 }))
        assert.is_true(TI.ChannelEvidenceLocks(nil, nil))
    end)

    it("a PROVEN transition locks regardless of the mob's spell shapes", function()
        assert.is_true(TI.ChannelEvidenceLocks(twoPhaseOnly,
            { kind = "channel", duration = 6, castIntoChannel = true }))
    end)

    it("a bare channel locks only on a pure-channel affirmation", function()
        local bare = { kind = "channel", duration = 6 }
        assert.is_false(TI.ChannelEvidenceLocks(twoPhaseOnly, bare))
        assert.is_true(TI.ChannelEvidenceLocks(withPure, bare))
    end)

    it("a trait-only verify (no curated spells) never locks on a bare channel", function()
        assert.is_false(TI.ChannelEvidenceLocks({}, { kind = "channel", duration = 6 }))
        assert.is_false(TI.ChannelEvidenceLocks(nil, { kind = "channel", duration = 6 }))
    end)

    it("a fingerprint-contradicted pure channel cannot ground the lock", function()
        local mob = { spells = { [2] = { castTime = 0, channelTime = 4, targetIsTank = true } } }
        assert.is_false(TI.ChannelEvidenceLocks(mob,
            { kind = "channel", duration = 4, fingerprints = { targetIsTank = false } }))
        assert.is_true(TI.ChannelEvidenceLocks(mob,
            { kind = "channel", duration = 4, fingerprints = {} }))
    end)
end)

describe("DungeonTrash inference — InferSucceededSpell", function()
    local TI
    setup(function() TI = loadInference() end)

    it("picks the spell whose cast time is closest to the observed duration", function()
        local mob = { spells = {
            [10] = { first = 5, castTime = 3 },
            [20] = { first = 5, castTime = 6 },
        } }
        assert.equals(20, TI.InferSucceededSpell(mob, { kind = "cast", duration = 6.05 }))
        assert.equals(10, TI.InferSucceededSpell(mob, { kind = "cast", duration = 2.95 }))
    end)

    -- The Arcane Sentry collision (Magisters' Terrace): Crowd Dispersal (3s cast,
    -- no channel) and Arcane Beam (3s cast + 5s channel) share a castTime, so a 3s
    -- cast is ambiguous. excludeTwoPhase is the PRIMARY cast-kind rule (reference:
    -- cast-kind success inference skips channel-capable spells): a completed bare
    -- cast resolves among one-phase spells only — the two-phase spell is credited
    -- exclusively from its channel phase.
    it("excludeTwoPhase resolves a shared-castTime one-phase twin, skipping the channel spell", function()
        local mob = { spells = {
            [473258]  = { first = 24,   castTime = 3 },              -- Crowd Dispersal (one-phase)
            [1282050] = { first = 11.9, castTime = 3, channelTime = 5 }, -- Arcane Beam (two-phase)
        } }
        -- Arcane Beam is anchored right on schedule, so it would win the normal tie.
        local anchors = { [1282050] = { anchorAt = 88.1, nextSeqIndex = 1 } } -- anchorAt + first = 100
        local obs = { kind = "cast", duration = 3.0, startAt = 100 }
        assert.equals(1282050, TI.InferSucceededSpell(mob, obs, anchors, 100))        -- normal: Arcane Beam
        assert.equals(473258,  TI.InferSucceededSpell(mob, obs, anchors, 100, true))  -- fallback: Crowd Dispersal
    end)

    -- Pass 2 channel fallback: a grab/beam channel's caster CHANNEL_STOP fires far
    -- short of the curated channelTime (Plungegrip 0.85s vs 12s), so the strict
    -- duration gate (Pass 1) drops it. The true duration is unreadable (secret), so
    -- a channel is identified by fingerprint only when Pass 1 finds nothing.
    it("Pass 2: matches a mob's only channel spell when the measured channel is far too short", function()
        local mob = { spells = { [1258997] = { first = 9, castTime = 0, channelTime = 12 } } }  -- Plungegrip
        assert.equals(1258997, TI.InferSucceededSpell(mob, { kind = "channel", duration = 0.85 }))
    end)

    it("Pass 1 still resolves a channel whose measured duration IS reliable", function()
        local mob = { spells = {
            [1] = { first = 5, castTime = 0, channelTime = 3 },
            [2] = { first = 5, castTime = 0, channelTime = 6 },
        } }
        assert.equals(2, TI.InferSucceededSpell(mob, { kind = "channel", duration = 6.05 }))  -- Pass 1 by duration
    end)

    it("Pass 2: a multi-channel mob with no anchors returns nil rather than guessing", function()
        local mob = { spells = {
            [1] = { first = 5, castTime = 0, channelTime = 3 },
            [2] = { first = 5, castTime = 0, channelTime = 6 },
        } }
        assert.is_nil(TI.InferSucceededSpell(mob, { kind = "channel", duration = 0.85 }, nil, 100))
    end)

    it("Pass 2: a multi-channel mob picks the schedule-nearest channel when an anchor exists", function()
        local mob = { spells = {
            [1] = { first = 5, castTime = 0, channelTime = 3 },
            [2] = { first = 8, castTime = 0, channelTime = 6 },
        } }
        local anchors = { [1] = { anchorAt = 95 } }  -- anchorAt + first = 100 == observed.startAt
        assert.equals(1, TI.InferSucceededSpell(mob, { kind = "channel", duration = 0.5, startAt = 100 }, anchors, 100))
    end)

    it("Pass 2 is channel-only — a short CAST stays unresolved", function()
        local mob = { spells = { [1] = { first = 5, castTime = 3, channelTime = 0 } } }
        assert.is_nil(TI.InferSucceededSpell(mob, { kind = "cast", duration = 0.5 }))
    end)

    -- Schedule proximity scores against the PREDICTED NEXT start
    -- (anchor.nextStartAt, the reference's primary term), not the previous
    -- one: among duration-tied spells the one that is DUE wins — the old
    -- previous-start term rewarded recency, so the least-due spell won ties.
    it("prefers the duration-tied spell that is DUE over the most recently cast", function()
        local mob = { spells = {
            [10] = { first = 5, castTime = 2.5, cd = { 20 } },
            [20] = { first = 5, castTime = 2.5, cd = { 20 } },
        } }
        local anchors = {
            [10] = { anchorAt = 95,  nextStartAt = 120 },  -- due exactly at the observed start
            [20] = { anchorAt = 107, nextStartAt = 132 },  -- cast more recently, due later
        }
        assert.equals(10, TI.InferSucceededSpell(mob,
            { kind = "cast", duration = 2.5, startAt = 120 }, anchors, 120))
    end)

    -- Pass 2 shares Pass 1's scoring fix (drift review D1): the tie-break
    -- must score the predicted NEXT start; the old anchorAt+first term
    -- measured time since the PREVIOUS cast for success anchors, so the most
    -- recently credited channel beat the one that was DUE.
    it("Pass 2 prefers the DUE channel over the most recently cast", function()
        local mob = { spells = {
            [10] = { first = 5, castTime = 0, channelTime = 3, cd = { 20 } },
            [20] = { first = 5, castTime = 0, channelTime = 6, cd = { 20 } },
        } }
        local anchors = {
            [10] = { anchorAt = 115, nextStartAt = 140 },  -- recently cast, due later
            [20] = { anchorAt = 95,  nextStartAt = 120 },  -- due exactly now
        }
        -- 0.5s measured channel: Pass 1's duration gate fails both → Pass 2.
        assert.equals(20, TI.InferSucceededSpell(mob,
            { kind = "channel", duration = 0.5, startAt = 120 }, anchors, 120))
    end)

    it("falls back to the engage-anchored first-cast expectation for never-anchored spells", function()
        local mob = { spells = {
            [10] = { first = 20, castTime = 3, cd = { 30 } },  -- due at engage+20
            [20] = { first = 8,  castTime = 3, cd = { 30 } },  -- due at engage+8
        } }
        -- No anchors at all; the cast lands right at engage+20 → spell 10 wins
        -- (the old flat 9999 left this tie to pairs() iteration order).
        local obs = { kind = "cast", duration = 3.0, startAt = 120, engagedAt = 100 }
        assert.equals(10, TI.InferSucceededSpell(mob, obs, nil, 120))
    end)
end)

describe("DungeonTrash inference — Layer2 samplers (Batch E)", function()
    local TI
    setup(function() TI = loadInference() end)

    -- The Skyreach twins (Dread Raven 76149 / Adorned Bladetalon 79303):
    -- byte-identical identity, same placement, and both curate a 3s cast with
    -- targetExists+targetAPIExists true. The ONLY discriminator in the data is
    -- castStartChangeTarget (Dread Wind true / Shear false) — sampled from the
    -- UNIT_TARGET switch ring around cast start.
    it("castStartChangeTarget splits the Skyreach twins in FilterCandidates", function()
        local DATA = {
            [76149] = { spells = { [1258174] = { castTime = 3, targetExists = true,
                targetAPIExists = true, castStartChangeTarget = true } } },
            [79303] = { spells = { [1254380] = { castTime = 3, targetExists = true,
                targetAPIExists = true, castStartChangeTarget = false } } },
        }
        local dataByNpc = function(npc) return DATA[npc] end
        local cands = { { npcID = 76149 }, { npcID = 79303 } }
        local obs = { kind = "cast", duration = 3.0,
            fingerprints = { castStartChangeTarget = true } }
        local _, resolved = TI.FilterCandidates(cands, obs, dataByNpc)
        assert.equals(76149, resolved)
        obs.fingerprints.castStartChangeTarget = false
        local _, resolved2 = TI.FilterCandidates(cands, obs, dataByNpc)
        assert.equals(79303, resolved2)
        -- Unsampled (nil) stays ambiguous — never a false match.
        obs.fingerprints.castStartChangeTarget = nil
        local kept3, resolved3 = TI.FilterCandidates(cands, obs, dataByNpc)
        assert.equals(2, #kept3)
        assert.is_nil(resolved3)
    end)

    -- Phalanx Breaker (232122): Interrupting Screech and Break Ranks are both
    -- 5s casts; Break Ranks curates selfBuffCountDeltaOnSuccess = 1.
    local PHALANX = { spells = {
        [471643] = { first = 18.9, castTime = 5 },                                 -- Interrupting Screech
        [471648] = { first = 5.5,  castTime = 5, selfBuffCountDeltaOnSuccess = 1 }, -- Break Ranks
    } }

    it("a sampled selfBuffCountDelta splits Phalanx Breaker's twin 5s casts", function()
        -- A mismatched delta REJECTS the delta-curating spell outright
        -- (reference semantics: the delta gates credit, it doesn't select).
        assert.equals(471643, TI.InferSucceededSpell(PHALANX,
            { kind = "cast", duration = 5.0, selfBuffCountDelta = 0 }))
        -- With a matching delta both spells survive the fingerprint gate and
        -- schedule proximity decides — here the cast lands at engage+5.5
        -- (Break Ranks' first), which the flat-9999 tie used to leave to
        -- pairs() order.
        assert.equals(471648, TI.InferSucceededSpell(PHALANX,
            { kind = "cast", duration = 5.0, selfBuffCountDelta = 1,
              startAt = 105.5, engagedAt = 100 }, nil, 105.5))
    end)

    -- Reference rule: the success-side delta is STRICT — a delta-curating
    -- spell is only CREDITED with a sampled matching delta; unknown rejects it
    -- (unlike the lenient boolean fingerprints, which pass when unsampled).
    it("an UNSAMPLED delta strictly rejects the delta-curating spell in success inference", function()
        assert.equals(471643, TI.InferSucceededSpell(PHALANX,
            { kind = "cast", duration = 5.0 }))
    end)

    it("mob narrowing stays lenient on an unsampled delta (FilterCandidates never prunes on it)", function()
        local dataByNpc = function() return PHALANX end
        local kept, resolved = TI.FilterCandidates({ { npcID = 232122 } },
            { kind = "cast", duration = 5.0 }, dataByNpc)
        assert.equals(1, #kept)
        assert.equals(232122, resolved)
    end)

    it("NeedsSelfBuffCountDelta is kind-aware and false without the field", function()
        assert.is_true(TI.NeedsSelfBuffCountDelta(PHALANX, "cast"))
        assert.is_false(TI.NeedsSelfBuffCountDelta(PHALANX, "channel"))
        assert.is_false(TI.NeedsSelfBuffCountDelta(
            { spells = { [1] = { castTime = 5 } } }, "cast"))
        assert.is_false(TI.NeedsSelfBuffCountDelta(nil, "cast"))
    end)

    it("targetClearOnCastStart discriminates same-mob spells (Alpha Eagle Gust vs Screech)", function()
        local eagle = { spells = {
            [377383] = { first = 5.3, castTime = 2.5, targetClearOnCastStart = true },
            [377389] = { first = 9,   castTime = 3,   targetClearOnCastStart = false },
        } }
        -- duration alone already splits these; assert the fingerprint REJECTS
        -- the mismatched spell outright (a 3s cast that cleared target at
        -- start matches neither — Gust is 2.5s, Screech says no-clear).
        assert.is_nil(TI.InferSucceededSpell(eagle,
            { kind = "cast", duration = 3.0,
              fingerprints = { targetClearOnCastStart = true } }))
        assert.equals(377389, TI.InferSucceededSpell(eagle,
            { kind = "cast", duration = 3.0,
              fingerprints = { targetClearOnCastStart = false } }))
    end)
end)

describe("DungeonTrash inference — ReconcileTraitCapabilities", function()
    local TI, KE
    setup(function() TI, KE = loadInference() end)

    it("derives hasCastSpell/hasChannelSpell from curated spell durations", function()
        local data = { [1] = { mobs = {
            [100] = { spells = { [1] = { castTime = 3, channelTime = 0 } } },  -- pure cast
            [200] = { spells = { [1] = { castTime = 0, channelTime = 6 } } },  -- pure channel
            [300] = { spells = { [1] = { castTime = 3, channelTime = 5 } } },  -- cast-into-channel (the FN case)
        } } }
        local traits = {
            [100] = { identity = { hasCastSpell = false, hasChannelSpell = false } },
            [200] = { identity = { hasCastSpell = false, hasChannelSpell = false } },
            [300] = { identity = { hasCastSpell = false, hasChannelSpell = false } },
        }
        TI.ReconcileTraitCapabilities(data, traits)
        assert.is_true(traits[100].identity.hasCastSpell)
        assert.is_false(traits[100].identity.hasChannelSpell)  -- pure cast: channel stays false
        assert.is_true(traits[200].identity.hasChannelSpell)
        assert.is_false(traits[200].identity.hasCastSpell)     -- pure channel: cast stays false
        assert.is_true(traits[300].identity.hasCastSpell)
        assert.is_true(traits[300].identity.hasChannelSpell)   -- cast-into-channel: BOTH true (the fix)
    end)

    it("only ever sets true — never clears an existing capability", function()
        local data = { [1] = { mobs = { [100] = { spells = { [1] = { castTime = 3 } } } } } }
        local traits = { [100] = { identity = { hasCastSpell = true, hasChannelSpell = true } } }
        TI.ReconcileTraitCapabilities(data, traits)
        assert.is_true(traits[100].identity.hasChannelSpell)  -- not cleared despite no channel spell
    end)

    it("tolerates nil / missing traits / missing spells without erroring", function()
        assert.has_no.errors(function()
            TI.ReconcileTraitCapabilities(nil, nil)
            TI.ReconcileTraitCapabilities({ [1] = { mobs = { [9] = { spells = { [1] = { channelTime = 5 } } } } } }, {})
            TI.ReconcileTraitCapabilities({ [1] = {} }, { [1] = {} })
        end)
    end)

    -- Regression guard for the Arcane Sentry class of bug (10 mobs, 6 dungeons):
    -- after reconcile against the SHIPPED data, NO mob with a channel (or cast)
    -- curated spell may carry a fingerprint that contradicts it.
    it("leaves no channel/cast false-negative across all shipped dungeons", function()
        TI.ReconcileTraitCapabilities(KE.TrashData, KE.TrashTraits)
        local bad = {}
        for _, dungeon in pairs(KE.TrashData) do
            for npcID, mob in pairs(dungeon.mobs or {}) do
                local trait = KE.TrashTraits[npcID]
                local id = trait and trait.identity
                if id and mob.spells then
                    for _, sp in pairs(mob.spells) do
                        if (sp.channelTime or 0) > 0 and id.hasChannelSpell ~= true then
                            bad[#bad + 1] = string.format("npc %s (%s) channels but hasChannelSpell~=true", tostring(npcID), tostring(mob.name))
                        end
                        if (sp.castTime or 0) > 0 and id.hasCastSpell ~= true then
                            bad[#bad + 1] = string.format("npc %s (%s) casts but hasCastSpell~=true", tostring(npcID), tostring(mob.name))
                        end
                    end
                end
            end
        end
        assert.same({}, bad)
    end)

    it("fixes the reported Arcane Sentry channel false-negative (234062)", function()
        TI.ReconcileTraitCapabilities(KE.TrashData, KE.TrashTraits)
        assert.is_true(KE.TrashTraits[234062].identity.hasChannelSpell)  -- Arcane Beam channels 5s
    end)
end)

describe("DungeonTrash inference — ComputeNextCast", function()
    local TI
    setup(function() TI = loadInference() end)

    it("adds cd[seqIndex] to the last success time", function()
        local nextStart, following = TI.ComputeNextCast({ cd = { 20 } }, 100, 1, 100)
        assert.equals(120, nextStart)
        assert.equals(1, following)   -- single-element cd wraps to itself
    end)

    it("round-robins a multi-step cd and wraps the following index", function()
        local ns, following = TI.ComputeNextCast({ cd = { 19.4, 21 } }, 100, 2, 100)
        assert.equals(121, ns)
        assert.equals(1, following)
    end)

    it("flags a past-due prediction as not future", function()
        local _, _, isFuture = TI.ComputeNextCast({ cd = { 20 } }, 100, 1, 130)
        assert.is_false(isFuture)
    end)

    it("returns nil when cd is absent", function()
        assert.is_nil(TI.ComputeNextCast({}, 100, 1, 100))
    end)
end)

describe("DungeonTrash inference — NextScheduledCast (roll-forward)", function()
    local TI
    setup(function() TI = loadInference() end)

    it("returns the first occurrence unchanged when it is already future", function()
        local nextStart, following, isFuture = TI.NextScheduledCast({ cd = { 20 } }, 100, 1, 100)
        assert.equals(120, nextStart)
        assert.equals(1, following)
        assert.is_true(isFuture)
    end)

    it("walks past-due occurrences forward until one is future", function()
        -- 120 and 140 are past at now=155; 160 is the first future one.
        local nextStart, following, isFuture = TI.NextScheduledCast({ cd = { 20 } }, 100, 1, 155)
        assert.equals(160, nextStart)
        assert.equals(1, following)
        assert.is_true(isFuture)
    end)

    it("advances the round-robin index while rolling forward", function()
        -- cd={10,30}: 110 (seq1→2) is past at now=125; +30 → 140 is future, next index wraps to 1.
        local nextStart, following, isFuture = TI.NextScheduledCast({ cd = { 10, 30 } }, 100, 1, 125)
        assert.equals(140, nextStart)
        assert.equals(1, following)
        assert.is_true(isFuture)
    end)

    it("does not walk when now is nil (everything counts as future)", function()
        local nextStart, _, isFuture = TI.NextScheduledCast({ cd = { 20 } }, 100, 1, nil)
        assert.equals(120, nextStart)
        assert.is_true(isFuture)
    end)

    it("returns nil when unschedulable", function()
        assert.is_nil(TI.NextScheduledCast({}, 100, 1, 100))
    end)
end)

describe("DungeonTrash inference — NextEnterCast (engage anchor)", function()
    local TI
    setup(function() TI = loadInference() end)

    it("predicts the first cast at enterAt + first when it is upcoming", function()
        local nextStart, following, isFuture = TI.NextEnterCast({ first = 9, cd = { 29 } }, 100, 100)
        assert.equals(109, nextStart)
        assert.equals(1, following)
        assert.is_true(isFuture)
    end)

    it("rolls forward when we joined after the first cast was due", function()
        -- firstAt=109 is past at now=115; +cd[1]=29 → 138 is the next future cast.
        local nextStart, following, isFuture = TI.NextEnterCast({ first = 9, cd = { 29 } }, 100, 115)
        assert.equals(138, nextStart)
        assert.equals(1, following)
        assert.is_true(isFuture)
    end)

    it("treats a nil now as future (predicts the first cast)", function()
        local nextStart, _, isFuture = TI.NextEnterCast({ first = 9, cd = { 29 } }, 100, nil)
        assert.equals(109, nextStart)
        assert.is_true(isFuture)
    end)

    it("returns nil when the spell has no curated first", function()
        assert.is_nil(TI.NextEnterCast({ cd = { 29 } }, 100, 100))
    end)

    it("returns nil when enterAt is nil", function()
        assert.is_nil(TI.NextEnterCast({ first = 9, cd = { 29 } }, nil, 100))
    end)
end)

describe("DungeonTrash inference — schedule signature", function()
    local TI
    setup(function() TI = loadInference() end)

    it("is stable for identical inputs and changes with an anchor", function()
        local anchors = { [10] = { mode = "success", anchorAt = 100.04, nextSeqIndex = 1 } }
        local a = TI.BuildScheduleSignature(232113, 50.0, "cast", 100.0, 1, anchors)
        local b = TI.BuildScheduleSignature(232113, 50.0, "cast", 100.0, 1, anchors)
        assert.equals(a, b)
        local anchors2 = { [10] = { mode = "success", anchorAt = 200.0, nextSeqIndex = 1 } }
        assert.not_equals(a, TI.BuildScheduleSignature(232113, 50.0, "cast", 100.0, 1, anchors2))
    end)

    it("ignores sub-0.1s jitter (%.1f rounding)", function()
        local a = TI.BuildScheduleSignature(1, 50.00, nil, 100.00, 0, nil)
        local b = TI.BuildScheduleSignature(1, 50.04, nil, 100.03, 0, nil)
        assert.equals(a, b)
    end)
end)

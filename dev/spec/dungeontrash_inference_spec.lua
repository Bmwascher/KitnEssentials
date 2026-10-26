-- Tier 1: DungeonTrash pure inference core (Modules/DungeonTools/DungeonTimers/Trash/TrashInference.lua).
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
    helpers.loadModule("Modules/DungeonTools/DungeonTimers/Trash/TrashTraits.lua", KE)
    helpers.loadModule("Modules/DungeonTools/DungeonTimers/Trash/TrashData.lua", KE)
    helpers.loadModule("Modules/DungeonTools/DungeonTimers/Trash/TrashInference.lua", KE)
    return KE.TrashInference, KE
end

describe("DungeonTrash inference — _r decoder", function()
    local TI, KE
    setup(function() TI, KE = loadInference() end)

    it("round-trips every legacy trait's packedIdentity to its stored identity", function()
        local mismatches = {}
        for npcID, trait in pairs(KE.TrashTraits) do
            local legacy = trait.schema ~= "named"
            local decoded = legacy and TI.DecodePackedIdentity(trait.packedIdentity) or {}
            for field, want in pairs(legacy and trait.identity or {}) do
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

    -- The second tier of the map-token match:
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

    -- Mixed rows AND the two kinds: the map gate rejects BEFORE the
    -- stage check and vice versa — a known-mismatched tier vetoes the other's
    -- match. No shipped row mixes kinds yet; this pins the semantics for the
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
        -- defers to a cast (this was the Rokh'zal false positive in-game).
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
        -- Every axis its row sets is read: an unread classID or buffCount would
        -- leave the lone survivor incomplete and unresolved.
        local soul = KE.TrashTraits[248686].identity
        local obs = { level = 91, sex = 3, power = 0, classID = soul.classID,
            buffCount = soul.buffCount, unitClassification = "elite" }
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
    -- via an observed cast matching one of its curated spells, so Layer2
    -- runs on every pass regardless of count. Rubber-stamping here would
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

    -- The Phantasmal Mystic class — trait castTimeSet/channelTimeSet
    -- feed the Layer2 keep rules BEFORE curated spells: a mob's KNOWN filler
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

    -- The old and/or select fell through to castTimeSet
    -- when a CHANNEL observation met a nil channelTimeSet — a real 2.5s channel
    -- kept a cast-only mob alive under fail-open routing (Riftbreath vs the
    -- cast-only Academy sibling). The two sets are consumed independently.
    it("a channel observation never borrows castTimeSet when channelTimeSet is absent", function()
        local castOnly = { castTimeSet = { 2.5 } }
        assert.is_false(TI.TraitDurationMatches(castOnly, { kind = "channel", duration = 2.5 }))
        assert.is_true(TI.TraitDurationMatches(castOnly, { kind = "cast", duration = 2.5 }))
    end)

    -- The trait keep tier is FILLER-ONLY. In production
    -- both Skyreach twins' trait castTimeSet carry the shared 3s cast, so the
    -- old unconditional trait fallthrough revived the fingerprint-rejected twin
    -- and the pool never narrowed — the Batch E castStartChangeTarget splitter
    -- was dead with traitByNpc wired (the sampler spec above omits traitByNpc,
    -- which is why it stayed green). Fingerprint narrowing is a
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
        local keptF, resolvedF = TI.FilterCandidates(cands,
            { kind = "cast", duration = 3.0, fingerprints = { castStartChangeTarget = false } },
            dataByNpc2, traitByNpc2)
        assert.equals(1, #keptF)
        assert.equals(79303, resolvedF)               -- the opposite polarity narrows too
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
    -- a pure channel's, so castConfirmed must not be earned by it — channel
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
    -- cast is ambiguous. excludeTwoPhase is the PRIMARY cast-kind rule —
    -- cast-kind success inference skips channel-capable spells: a completed bare
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
    -- (anchor.nextStartAt, the primary term), not the previous
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
        -- (the delta gates credit, it doesn't select).
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

    -- The success-side delta is STRICT — a delta-curating
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

local function named(npcID, identity, extra)
    local t = { npcID = npcID, name = "N" .. npcID, dungeonKey = "S", schema = "named",
        placement = "", identity = identity }
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
end

local function contains(list, value)
    for _, v in ipairs(list or {}) do
        if v == value then return true end
    end
    return false
end

local function npcIDs(cands)
    local out = {}
    for _, c in ipairs(cands) do out[#out + 1] = c.npcID end
    return out
end

describe("DungeonTrash inference — identity completeness", function()
    local TI
    setup(function() TI = loadInference() end)

    it("a complete, level-agreed lone survivor resolves while another row's field stays pending", function()
        local traits = {
            [1] = named(1, { level = 91, power = 1, nonElite = false }),
            [2] = named(2, { level = 91, power = 1, nonElite = false, isLieutenant = true,
                uiMapIDs = { 500 } }),
        }
        local cands, resolved, pending = TI.BuildCandidates(
            { level = 91, power = 1, unitClassification = "elite" },
            { traits = traits, dungeonKey = "S", currentSubZoneMapID = 600 })
        assert.same({ 1 }, npcIDs(cands))
        assert.equals(1, resolved)
        assert.same({ "isLieutenant" }, pending)
    end)

    it("a complete lone survivor that disagrees on level does not resolve at Layer 1", function()
        local traits = { [1] = named(1, { level = 91, power = 1, nonElite = false }) }
        local cands, resolved = TI.BuildCandidates(
            { level = 90, power = 1, unitClassification = "elite" },
            { traits = traits, dungeonKey = "S" })
        assert.same({ 1 }, npcIDs(cands))
        assert.is_false(cands[1].incomplete)
        assert.is_nil(resolved)
    end)

    it("a survivor with a required axis unread resolves at neither Layer 1 nor Layer 2", function()
        local traits = {
            [1] = named(1, { level = 91, power = 1, nonElite = false, isLieutenant = false }),
            [2] = named(2, { level = 91, power = 1, nonElite = false }),
        }
        local spells = {
            [1] = { spells = { [10] = { castTime = 2 } } },
            [2] = { spells = { [20] = { castTime = 5 } } },
        }
        local dataByNpc = function(npc) return spells[npc] end
        local obs = { level = 91, power = 1, unitClassification = "elite" }
        local lone, resolved = TI.BuildCandidates(obs, { traits = { [1] = traits[1] }, dungeonKey = "S" })
        assert.same({ 1 }, npcIDs(lone))
        assert.is_true(lone[1].incomplete)
        assert.is_nil(resolved)
        local _, verified = TI.FilterCandidates(lone, { kind = "cast", duration = 2 }, dataByNpc)
        assert.is_nil(verified)
        local pool = TI.BuildCandidates(obs, { traits = traits, dungeonKey = "S" })
        local kept, narrowed = TI.FilterCandidates(pool, { kind = "cast", duration = 2 }, dataByNpc)
        assert.same({ 1 }, npcIDs(kept))
        assert.is_nil(narrowed)
    end)

    it("a late buffCount read resolves the survivor when equal and rejects it when below", function()
        local traits = { [7] = { npcID = 7, dungeonKey = "L", placement = "",
            identity = { level = 91, sex = 1, power = 1, classID = 1, buffCount = 2, nonElite = false } } }
        local opts = { traits = traits, dungeonKey = "L" }
        local cands, resolved, pending = TI.BuildCandidates(
            { level = 91, sex = 1, power = 1, classID = 1, unitClassification = "elite" }, opts)
        assert.same({ 7 }, npcIDs(cands))
        assert.is_nil(resolved)
        assert.same({ "buffCount" }, pending)
        local cases = {
            { read = 2, want = 7, count = 1 },
            { read = 1, count = 0 },
        }
        for _, c in ipairs(cases) do
            local obs = TI.MergeIdentity({ level = 91, sex = 1, power = 1, classID = 1,
                unitClassification = "elite" }, { buffCount = c.read })
            local late, lateResolved, latePending = TI.BuildCandidates(obs, opts)
            assert.equals(c.count, #late)
            assert.equals(c.want, lateResolved)
            assert.same({}, latePending)
        end
    end)

    it("an axis the row leaves unset never blocks it", function()
        local traits = { [8] = { npcID = 8, dungeonKey = "L", placement = "",
            identity = { level = 91, power = 1, nonElite = false } } }
        local cands, resolved, pending = TI.BuildCandidates(
            { level = 91, power = 1, unitClassification = "elite" },
            { traits = traits, dungeonKey = "L" })
        assert.same({ 8 }, npcIDs(cands))
        assert.equals(8, resolved)
        assert.same({}, pending)
    end)

    it("unread classification rejects elite rows and leaves a nonElite row incomplete", function()
        local traits = {
            [1] = named(1, { level = 91, power = 1, nonElite = false }),
            [2] = named(2, { level = 91, power = 1, nonElite = true }),
        }
        local cands, resolved, pending = TI.BuildCandidates({ level = 91, power = 1 },
            { traits = traits, dungeonKey = "S" })
        assert.same({ 2 }, npcIDs(cands))
        assert.is_true(cands[1].incomplete)
        assert.is_nil(resolved)
        assert.same({ "unitClassification" }, pending)
    end)
end)

describe("DungeonTrash inference — identity recovery", function()
    local TI, savedGate
    setup(function() TI = loadInference() end)
    before_each(function() savedGate = TI.FAMILY_GATE end)
    after_each(function() TI.FAMILY_GATE = savedGate end)

    it("zero survivors: classification decides whether reads continue, resolve or settle", function()
        local traits = {
            [11] = named(11, { level = 91, power = 1, nonElite = false, isLieutenant = true }),
            [12] = named(12, { level = 91, power = 0, nonElite = false }),
        }
        local cases = {
            { obs = { level = 91, power = 1 }, count = 0,
              pending = { "unitClassification", "isLieutenant" } },
            { obs = { level = 91, power = 1, unitClassification = "elite", isLieutenant = true },
              count = 1, resolved = 11, pending = {} },
            { obs = { level = 91, power = 1, unitClassification = "normal" }, count = 0, pending = {} },
        }
        for i, c in ipairs(cases) do
            local cands, resolved, pending = TI.BuildCandidates(c.obs, { traits = traits, dungeonKey = "S" })
            assert.equals(c.count, #cands, "row " .. i)
            assert.equals(c.resolved, resolved, "row " .. i)
            assert.same(c.pending, pending, "row " .. i)
            assert.equals(#c.pending == 0, TI.RecoverySettled(pending), "row " .. i)
        end
    end)

    it("a permanent identity mismatch adds no field, while temporary and recoverable rejections keep theirs", function()
        local base = { level = 91, power = 1, nonElite = false, isLieutenant = true }
        local function row(extra, traitExtra)
            local id = {}
            for k, v in pairs(base) do id[k] = v end
            for k, v in pairs(extra or {}) do id[k] = v end
            return { [5] = named(5, id, traitExtra) }
        end
        local ELITE = { level = 91, power = 1, unitClassification = "elite" }
        local cases = {
            { name = "known power mismatch", traits = row(),
              obs = { level = 91, power = 0, unitClassification = "elite" },
              pending = {}, compatible = false },
            { name = "known lieutenant mismatch with classification unread", traits = row(),
              obs = { level = 91, power = 1, isLieutenant = false },
              pending = {}, compatible = false },
            { name = "placement map tier only", traits = row({ uiMapIDs = { 500 } }), obs = ELITE,
              opts = { currentSubZoneMapID = 600 }, pending = { "isLieutenant" }, compatible = true },
            { name = "encounter only", traits = row({ bossEncounter = true }), obs = ELITE,
              pending = { "isLieutenant" }, compatible = true },
            { name = "channel gate only", traits = row({ hasChannelSpell = false }),
              obs = { level = 91, power = 1, unitClassification = "elite", sawChannelStart = true },
              pending = { "isLieutenant" }, compatible = true },
            { name = "stage only", traits = row(nil, { placement = "2" }), obs = ELITE,
              opts = { bossProgressIndex = 1 }, pending = { "isLieutenant" }, compatible = true },
            { name = "room only", traits = row({ roomNames = { "Hall" } }), obs = ELITE,
              opts = { roomText = "Crypt" }, pending = { "isLieutenant" }, compatible = true },
            { name = "unread classification", traits = row(),
              obs = { level = 91, power = 1, isLieutenant = true },
              pending = { "unitClassification" }, compatible = true },
            { name = "family mismatch with the gate off", gate = false,
              traits = row({ hasCreatureFamily = true }),
              obs = { level = 91, power = 1, unitClassification = "elite", hasCreatureFamily = false },
              pending = { "isLieutenant" }, compatible = true, matched = true },
            { name = "family mismatch with the gate on", gate = true,
              traits = row({ hasCreatureFamily = true }),
              obs = { level = 91, power = 1, unitClassification = "elite", hasCreatureFamily = false },
              pending = {}, compatible = false },
            { name = "unset channel capability", traits = row(),
              obs = { level = 91, power = 1, unitClassification = "elite", isLieutenant = true,
                  sawChannelStart = true },
              pending = {}, compatible = true, matched = true },
        }
        for _, c in ipairs(cases) do
            TI.FAMILY_GATE = (c.gate ~= false)
            local opts = { traits = c.traits, dungeonKey = "S" }
            for k, v in pairs(c.opts or {}) do opts[k] = v end
            local cands, _, pending = TI.BuildCandidates(c.obs, opts)
            assert.same(c.pending, pending, c.name)
            assert.equals(c.matched == true, #cands == 1, c.name)
            assert.equals(c.compatible,
                TI.IdentityCompatibleRows(c.obs, "S", { traits = c.traits })[5] == true, c.name)
        end
    end)

    it("the read plan reads by recovery state and source, and only scheduled reads use the budget", function()
        local all = TI.IdentityReadFields()
        local max = TI.RECOVERY_SCHEDULED_MAX
        local unknown = {}
        for _, f in ipairs(all) do
            if f ~= "level" then unknown[#unknown + 1] = f end
        end
        local snap = { level = 91 }
        local cases = {
            { state = {}, source = "scheduled", fields = all, count = 1, runs = true },
            { state = {}, source = "event", fields = all, count = 0, runs = true },
            { state = { obs = snap }, source = "scheduled", fields = unknown, count = 1, runs = true },
            { state = { obs = snap }, source = "event", count = 0, runs = false },
            { state = { obs = snap, pending = { "isLieutenant" } }, source = "scheduled",
              fields = { "isLieutenant" }, count = 1, runs = true },
            { state = { obs = snap, pending = { "isLieutenant" } }, source = "event",
              fields = { "isLieutenant" }, count = 0, runs = true },
            { state = { obs = snap, pending = {} }, source = "scheduled", count = 0, runs = false },
            { state = { obs = snap, pending = {} }, source = "event", count = 0, runs = false },
            { state = { obs = snap, pending = { "isLieutenant" }, scheduled = max }, source = "scheduled",
              count = max, runs = false },
            { state = { obs = snap, pending = { "isLieutenant" }, scheduled = max }, source = "event",
              fields = { "isLieutenant" }, count = max, runs = true },
        }
        for i, c in ipairs(cases) do
            local fields, count, runs = TI.RecoveryReadPlan(c.state, c.source)
            assert.same(c.fields, fields, "row " .. i)
            assert.equals(c.count, count, "row " .. i)
            assert.equals(c.runs, runs, "row " .. i)
        end
    end)

    it("only a live owner whose runtime is tracked and owned by it passes the callback check", function()
        local function generation(unit)
            local owner = { live = true, scheduled = 0 }
            local rt = { unit = unit, owner = owner }
            owner.runtime = rt
            return owner, rt
        end
        local owner, rt = generation("nameplate1")
        assert.is_true(TI.RecoveryOwnerHolds(owner, { nameplate1 = rt }, true))
        assert.is_false(TI.RecoveryOwnerHolds(owner, { nameplate1 = rt }, false))

        local removed = generation("nameplate1")
        local stopped = generation("nameplate1")
        local replaced = generation("nameplate1")
        local _, newer = generation("nameplate1")
        removed.live, stopped.live, replaced.live = false, false, false
        local dead = {
            { owner = removed, tracked = {}, monitoring = true },
            { owner = stopped, tracked = {}, monitoring = false },
            { owner = replaced, tracked = { nameplate1 = newer }, monitoring = true },
        }
        for i, c in ipairs(dead) do
            assert.is_false(TI.RecoveryOwnerHolds(c.owner, c.tracked, c.monitoring), "row " .. i)
        end

        local old, reused = generation("nameplate2")
        old.live = false
        local fresh = { live = true, scheduled = 2, runtime = reused }
        reused.owner = fresh
        local tracked = { nameplate2 = reused }
        assert.is_false(TI.RecoveryOwnerHolds(old, tracked, true))
        old.live = true
        assert.is_false(TI.RecoveryOwnerHolds(old, tracked, true))
        assert.is_true(TI.RecoveryOwnerHolds(fresh, tracked, true))
    end)

    it("normalizes each read on its own and merges without replacing a known field", function()
        local cases = {
            { "isLieutenant", true, false, false, false },
            { "power", true, 0, false, 0 },
            { "buffCount", true, 0, false, 0 },
            { "unitClassification", true, "elite", false, "elite" },
            { "level", true, 91, true, nil },
            { "sex", false, nil, false, nil },
            { "buffCount", false, nil, false, nil },
            { "unitClassification", true, "", false, nil },
            { "level", true, 0, false, nil },
            { "level", true, -1, false, nil },
            { "hasCreatureFamily", true, true, false, true },
            { "hasCreatureFamily", true, false, false, false },
            { "hasCreatureFamily", false, nil, false, nil },
            { "hasCreatureFamily", true, true, true, nil },
            { "hasCreatureFamily", true, nil, false, nil },
            { "hasCreatureFamily", true, "Beast", false, nil },
        }
        for i, c in ipairs(cases) do
            assert.equals(c[5], TI.NormalizeIdentityField(c[1], c[2], c[3], c[4]), "row " .. i)
        end

        local familyRow = named(9, { level = 91, power = 1, nonElite = false, hasCreatureFamily = true })
        local absent = { level = 91, power = 1, unitClassification = "elite", hasCreatureFamily = false }
        TI.FAMILY_GATE = false
        assert.is_false(contains(TI.IdentityReadFields(), "hasCreatureFamily"))
        assert.is_false(contains(TI.RequiredAxes(familyRow), "hasCreatureFamily"))
        assert.is_true((TI.ScoreTraitRow(absent, familyRow)))
        TI.FAMILY_GATE = true
        assert.is_true(contains(TI.IdentityReadFields(), "hasCreatureFamily"))
        assert.is_true(contains(TI.RequiredAxes(familyRow), "hasCreatureFamily"))
        assert.is_false((TI.ScoreTraitRow(absent, familyRow)))

        local merged = TI.MergeIdentity({ level = 91, power = 1 }, { level = 90, sex = 2, power = 0 })
        assert.same({ level = 91, power = 1, sex = 2 }, merged)
    end)
end)

describe("DungeonTrash inference — S2 Layer 1 predicates", function()
    local TI
    setup(function() TI = loadInference() end)
    local OBS = { level = 91, power = 1, unitClassification = "elite" }

    it("rejects a lieutenant mismatch", function()
        local trait = named(1, { level = 91, power = 1, nonElite = false, isLieutenant = true })
        for _, c in ipairs({ { read = false, ok = false }, { read = true, ok = true } }) do
            local obs = { level = 91, power = 1, unitClassification = "elite", isLieutenant = c.read }
            local ok, _, _, reason = TI.ScoreTraitRow(obs, trait)
            assert.equals(c.ok, ok)
            assert.equals(not c.ok and "lieutenant" or nil, reason)
        end
    end)

    it("applies bossEncounter true, false and unset against the encounter state", function()
        local cases = {
            { row = true, inside = true, ok = true }, { row = true, inside = false, ok = false },
            { row = false, inside = true, ok = false }, { row = false, inside = false, ok = true },
            { inside = true, ok = true }, { inside = false, ok = true },
        }
        for i, c in ipairs(cases) do
            local trait = named(1, { level = 91, power = 1, nonElite = false, bossEncounter = c.row })
            assert.equals(c.ok, (TI.ScoreTraitRow(OBS, trait, { inBossEncounter = c.inside })), "row " .. i)
        end
    end)

    it("allows a uiMapIDs or room row when the runtime value is unknown, and rejects a known miss", function()
        local cases = {
            { id = { uiMapIDs = { 500 } }, ok = true },
            { id = { uiMapIDs = { 500 } }, opts = { currentZoneText = "Deck" }, ok = true },
            { id = { uiMapIDs = { 500 } }, opts = { currentSubZoneMapID = 500 }, ok = true },
            { id = { uiMapIDs = { 500 } }, opts = { currentSubZoneMapID = 600 }, ok = false, reason = "placement" },
            { id = { roomNames = { "Hall" } }, ok = true },
            { id = { roomNames = { "Hall" } }, opts = { roomText = "" }, ok = true },
            { id = { roomNames = { "Hall" } }, opts = { roomText = "Hall" }, ok = true },
            { id = { roomNames = { "Hall" } }, opts = { roomText = "Crypt" }, ok = false, reason = "room" },
        }
        for i, c in ipairs(cases) do
            local id = { level = 91, power = 1, nonElite = false }
            for k, v in pairs(c.id) do id[k] = v end
            local ok, _, _, reason = TI.ScoreTraitRow(OBS, named(1, id), c.opts)
            assert.equals(c.ok, ok, "row " .. i)
            assert.equals(c.reason, reason, "row " .. i)
        end
    end)

    it("prefers rows naming a present trusted companion, never on absence or an untrusted one", function()
        local traits = {
            [1] = named(1, { level = 91, power = 1, nonElite = false, coPresenceNPCIDs = { 900 } }),
            [2] = named(2, { level = 91, power = 1, nonElite = false }),
        }
        local function trustedFrom(runtimes)
            local set = {}
            for _, rt in ipairs(runtimes) do
                if TI.CompanionTrusted(rt) then set[rt.matchedNPCID] = true end
            end
            return set
        end
        local cases = {
            { runtimes = {}, want = { 1, 2 } },
            { runtimes = { { matchedNPCID = 900, castConfirmed = true } }, want = { 1 } },
            { runtimes = { { matchedNPCID = 900, layer1Resolved = true } }, want = { 1 } },
            { runtimes = { { matchedNPCID = 900 } }, want = { 1, 2 } },
            { runtimes = { { matchedNPCID = 900, castConfirmed = true, waveDerived = true } }, want = { 1, 2 } },
            { runtimes = { { castConfirmed = true }, { layer1Resolved = true } }, want = { 1, 2 } },
            { runtimes = { { matchedNPCID = 901, castConfirmed = true } }, want = { 1, 2 } },
        }
        for i, c in ipairs(cases) do
            local cands = TI.BuildCandidates(OBS, { traits = traits, dungeonKey = "S",
                trustedCompanions = trustedFrom(c.runtimes) })
            assert.same(c.want, npcIDs(cands), "row " .. i)
        end
        traits[2].identity.coPresenceNPCIDs = { 900 }
        local both = TI.BuildCandidates(OBS, { traits = traits, dungeonKey = "S",
            trustedCompanions = { [900] = true } })
        assert.same({ 1, 2 }, npcIDs(both))
    end)

    it("narrows to pre-combat channelers only when a channel was seen before combat", function()
        local traits = {
            [1] = named(1, { level = 91, power = 1, nonElite = false, preCombatChanneling = true }),
            [2] = named(2, { level = 91, power = 1, nonElite = false, preCombatChanneling = false }),
            [3] = named(3, { level = 91, power = 1, nonElite = false }),
        }
        for i, c in ipairs({
            { seen = true, want = { 1 } },
            { seen = false, want = { 1, 2, 3 } },
            { want = { 1, 2, 3 } },
        }) do
            local cands = TI.BuildCandidates(OBS, { traits = traits, dungeonKey = "S",
                sawPreCombatChannel = c.seen })
            assert.same(c.want, npcIDs(cands), "row " .. i)
        end
        traits[1].identity.preCombatChanneling = false
        local all = TI.BuildCandidates(OBS, { traits = traits, dungeonKey = "S", sawPreCombatChannel = true })
        assert.same({ 1, 2, 3 }, npcIDs(all))
    end)
end)

describe("DungeonTrash inference — cast ownership", function()
    local TI
    setup(function() TI = loadInference() end)

    -- Applies events to a cast state. An event is { "start", kind, id,
    -- refresh = bool }, { "end", kind, id, event } or { "combat", bool }.
    -- Returns the state and, per event, its class (or "none") and the
    -- recovery state after it.
    local function play(events, capacity, cs)
        cs = cs or TI.NewCastState({})
        local out = {}
        for i, e in ipairs(events) do
            if e[1] == "start" then
                local class, rec = TI.ClassifyStart(cs, e[2], e[3], i, e.refresh, capacity)
                TI.AssignOrder(cs, rec)
                out[i] = { class = class, rec = rec, state = cs.recovery }
            elseif e[1] == "end" then
                local outcome, latch = TI.ClassifyEnd(cs, e[2], e[3], e[4], i, capacity)
                out[i] = { class = outcome, latch = latch, state = cs.recovery }
            else
                out[i] = { class = TI.CombatWindowStep(cs, e[2], capacity) or "none", state = cs.recovery }
            end
        end
        return cs, out
    end

    local function column(out, field)
        local list = {}
        for i, r in ipairs(out) do list[i] = r[field] end
        return list
    end

    local function generation(unit)
        local owner = { live = true, scheduled = 0 }
        local rt = { unit = unit, owner = owner }
        owner.runtime = rt
        rt.castState = TI.NewCastState(owner)
        return owner, rt
    end

    it("never correlates distinct, half-missing or both-missing tokens", function()
        local cases = {
            { 7, 7, true }, { "a", "a", true },
            { 7, 8, false }, { 7, "7", false }, { "a", "b", false },
            { 7, nil, false }, { nil, 7, false }, { nil, nil, false },
        }
        for i, c in ipairs(cases) do
            assert.equals(c[3], TI.TokensCorrelate(c[1], c[2]), "row " .. i)
        end
    end)

    it("a refused end event after a newer START leaves that cast and its count untouched", function()
        local cases = {
            { refused = { "end", "cast", nil, "stop" }, latch = false },
            { refused = { "end", "channel", 1, "stop" }, latch = false },
            { refused = { "end", "cast", 1, "interrupted" }, latch = true },
            { refused = { "end", "cast", 1, "failed" }, latch = false },
        }
        for i, c in ipairs(cases) do
            local cs, out = play({
                { "combat", false }, { "combat", true },
                { "start", "cast", 1 }, { "start", "cast", 2 }, c.refused,
            })
            local newer = out[4].rec
            assert.equals("refused", out[5].class, "row " .. i)
            assert.equals(c.latch, out[5].latch, "row " .. i)
            assert.equals(newer, cs.latest, "row " .. i)
            assert.is_true(newer.open, "row " .. i)
            assert.equals(2, newer.seq, "row " .. i)
            assert.equals(2, newer.order, "row " .. i)
            assert.equals(2, cs.window.count, "row " .. i)
            assert.equals("normal", cs.recovery, "row " .. i)
            assert.is_true(newer.impliedStopVoid, "row " .. i)
            assert.equals("correlated", (TI.ClassifyEnd(cs, "cast", 2, "stop", 9)), "row " .. i)
        end
        local cs, out = play({ { "start", "channel", 3 } })
        out[1].rec.transitionCastStartAt = 0.5
        assert.equals("refused", (TI.ClassifyEnd(cs, "cast", nil, "stop", 2)))
        assert.equals(0.5, out[1].rec.transitionCastStartAt)
        assert.is_nil(out[1].rec.impliedStopVoid)
    end)

    it("A: classifies each START and moves the recovery state", function()
        local S, E, C = "start", "end", "combat"
        local cases = {
            { name = "present ID", events = { { S, "cast", 1 } },
              classes = { "normal" }, state = "normal" },
            { name = "equal present ID", events = { { S, "cast", 1 }, { S, "cast", 1 } },
              classes = { "normal", "duplicate" }, state = "normal" },
            { name = "supported refresh", events = { { S, "channel", 1 }, { S, "channel", 2, refresh = true } },
              classes = { "normal", "refresh" }, state = "normal" },
            { name = "refresh without an ID", events = { { S, "channel", 1 }, { S, "channel", nil, refresh = true } },
              classes = { "normal", "unowned" }, state = "uncertain" },
            { name = "first START with no ID", events = { { S, "cast", nil } },
              classes = { "unowned" }, state = "uncertain" },
            { name = "present then nil", events = { { S, "cast", 1 }, { S, "cast", nil } },
              classes = { "normal", "unowned" }, state = "uncertain" },
            { name = "nil then nil", events = { { S, "cast", nil }, { S, "cast", nil } },
              classes = { "unowned", "unowned" }, state = "uncertain" },
            { name = "nil then present", events = { { S, "cast", nil }, { S, "cast", 5 } },
              classes = { "unowned", "baseline" }, state = "baseline" },
            { name = "baseline replaced by another present ID",
              events = { { S, "cast", nil }, { S, "cast", 5 }, { S, "cast", 6 } },
              classes = { "unowned", "baseline", "baseline" }, state = "baseline" },
            { name = "baseline then nil", events = { { S, "cast", nil }, { S, "cast", 5 }, { S, "cast", nil } },
              classes = { "unowned", "baseline", "unowned" }, state = "uncertain" },
            { name = "closed baseline repeated, then a distinct ID",
              events = { { S, "cast", nil }, { S, "cast", 5 }, { E, "cast", 5, "stop" },
                  { S, "cast", 5 }, { S, "cast", 6 } },
              classes = { "unowned", "baseline", "baseline-close", "duplicate", "normal" }, state = "normal" },
            { name = "departed by correlated STOP", events = { { S, "cast", 1 }, { E, "cast", 1, "stop" }, { S, "cast", 1 } },
              classes = { "normal", "correlated", "duplicate" }, state = "normal" },
            { name = "departed by INTERRUPTED",
              events = { { S, "cast", 1 }, { E, "cast", 1, "interrupted" }, { S, "cast", 1 } },
              classes = { "normal", "correlated", "duplicate" }, state = "normal" },
            { name = "departed by FAILED",
              events = { { S, "cast", 1 }, { E, "cast", 1, "failed" }, { S, "cast", 1 } },
              classes = { "normal", "correlated", "duplicate" }, state = "normal" },
            { name = "departed by same-kind replacement",
              events = { { S, "cast", 1 }, { S, "cast", 2 }, { S, "cast", 1 } },
              classes = { "normal", "normal", "duplicate" }, state = "normal" },
            { name = "cast departed by a channel START",
              events = { { S, "cast", 1 }, { S, "channel", 2 }, { S, "cast", 1 } },
              classes = { "normal", "normal", "duplicate" }, state = "normal" },
            { name = "departed by retirement at a window close",
              events = { { C, false }, { C, true }, { S, "cast", 1 }, { C, false }, { S, "cast", 1 } },
              classes = { "none", "opened", "normal", "closed", "duplicate" }, state = "normal" },
            { name = "a refresh's old ID",
              events = { { S, "channel", 1 }, { S, "channel", 2, refresh = true }, { S, "channel", 1 } },
              classes = { "normal", "refresh", "duplicate" }, state = "normal" },
            { name = "the other kind's departed ID",
              events = { { S, "cast", 1 }, { E, "cast", 1, "stop" }, { S, "channel", 1 } },
              classes = { "normal", "correlated", "normal" }, state = "normal" },
            { name = "two departures back, normal",
              events = { { S, "cast", 1 }, { S, "cast", 2 }, { S, "cast", 3 }, { S, "cast", 1 } },
              classes = { "normal", "normal", "normal", "duplicate" }, state = "normal" },
            { name = "two departures back, uncertain",
              events = { { S, "cast", 1 }, { S, "cast", 2 }, { S, "cast", nil }, { S, "cast", 1 } },
              classes = { "normal", "normal", "unowned", "duplicate" }, state = "uncertain" },
            { name = "two departures back, baseline stays open",
              events = { { S, "cast", 1 }, { S, "cast", 2 }, { S, "cast", nil }, { S, "cast", 3 }, { S, "cast", 1 } },
              classes = { "normal", "normal", "unowned", "baseline", "duplicate" }, state = "baseline",
              check = function(cs) assert.is_true(cs.latest.id == 3 and cs.latest.open) end },
            { name = "replay after an ID-less START",
              events = { { S, "cast", "a" }, { E, "cast", "a", "stop" }, { S, "cast", nil }, { S, "cast", "a" },
                  { E, "cast", "a", "stop" }, { S, "cast", "b" }, { E, "cast", "b", "stop" }, { S, "cast", "c" } },
              classes = { "normal", "correlated", "unowned", "duplicate", "refused", "baseline",
                  "baseline-close", "normal" },
              states = { "normal", "normal", "uncertain", "uncertain", "uncertain", "baseline", "closed", "normal" } },
            { name = "replay after an ID-less START, an older ID",
              events = { { S, "cast", "a" }, { E, "cast", "a", "stop" }, { S, "cast", "x" }, { E, "cast", "x", "stop" },
                  { S, "cast", nil }, { S, "cast", "a" }, { E, "cast", "a", "stop" }, { S, "cast", "b" },
                  { E, "cast", "b", "stop" }, { S, "cast", "c" } },
              classes = { "normal", "correlated", "normal", "correlated", "unowned", "duplicate", "refused",
                  "baseline", "baseline-close", "normal" }, state = "normal" },
            { name = "capacity boundary", capacity = 2,
              events = { { S, "cast", 1 }, { E, "cast", 1, "stop" }, { S, "cast", 2 }, { E, "cast", 2, "stop" },
                  { S, "cast", 3 }, { E, "cast", 3, "stop" }, { S, "cast", 1 }, { S, "cast", 4 },
                  { S, "cast", nil }, { C, false }, { C, true } },
              classes = { "normal", "correlated", "normal", "correlated", "normal", "correlated",
                  "duplicate", "withheld", "unowned", "none", "opened" },
              states = { "normal", "normal", "normal", "normal", "normal", "saturated",
                  "saturated", "saturated", "saturated", "saturated", "saturated" },
              check = function(cs, out)
                  assert.is_false(out[8].rec.eligible)
                  assert.is_nil(out[8].rec.seq)
                  assert.is_false(cs.window.known)
              end },
            { name = "an ID-less START whose replacement saturates", capacity = 2,
              events = { { S, "cast", 1 }, { S, "cast", 2 }, { S, "cast", 3 }, { S, "cast", nil } },
              classes = { "normal", "normal", "normal", "unowned" }, state = "saturated" },
            { name = "a baseline replaced by an ID-less START that saturates", capacity = 1,
              events = { { S, "cast", 1 }, { E, "cast", 1, "stop" }, { S, "cast", nil }, { S, "cast", 5 },
                  { S, "cast", nil } },
              classes = { "normal", "correlated", "unowned", "baseline", "unowned" }, state = "saturated" },
            { name = "a baseline close that saturates", capacity = 1,
              events = { { S, "cast", 1 }, { E, "cast", 1, "stop" }, { S, "cast", nil }, { S, "cast", 5 },
                  { E, "cast", 5, "stop" } },
              classes = { "normal", "correlated", "unowned", "baseline", "baseline-close" }, state = "saturated" },
            { name = "a correlated interrupt that saturates", capacity = 1,
              events = { { S, "cast", 1 }, { E, "cast", 1, "stop" }, { S, "cast", 2 }, { E, "cast", 2, "interrupted" } },
              classes = { "normal", "correlated", "normal", "correlated" }, state = "saturated",
              check = function(_, out) assert.is_true(out[4].latch) end },
            { name = "a START whose replacement saturates", capacity = 1,
              events = { { S, "cast", 1 }, { E, "cast", 1, "stop" }, { S, "cast", 2 }, { S, "cast", 3 } },
              classes = { "normal", "correlated", "normal", "withheld" }, state = "saturated" },
            { name = "a refresh whose old ID saturates, then the withheld ends", capacity = 1,
              events = { { S, "channel", 1 }, { E, "channel", 1, "stop" }, { S, "channel", 2 },
                  { S, "channel", 3, refresh = true }, { E, "channel", 3, "stop" },
                  { S, "cast", 4 }, { E, "cast", 4, "interrupted" } },
              classes = { "normal", "correlated", "normal", "withheld", "withheld-end", "withheld", "withheld-end" },
              state = "saturated",
              check = function(_, out)
                  assert.is_false(out[3].rec.open)
                  assert.is_true(out[7].latch)
              end },
        }
        for _, c in ipairs(cases) do
            local cs, out = play(c.events, c.capacity or 8)
            assert.same(c.classes, column(out, "class"), c.name)
            if c.states then assert.same(c.states, column(out, "state"), c.name) end
            if c.state then assert.equals(c.state, cs.recovery, c.name) end
            if c.check then c.check(cs, out) end
        end

        -- The Avatar openers: a stays order 1, its repeat gets nothing, b is order 2.
        local cs, out = play({ { C, false }, { C, true }, { S, "cast", "a" }, { E, "cast", "a", "stop" },
            { S, "cast", "a" }, { S, "cast", "b" } })
        assert.equals(1, out[3].rec.order)
        assert.is_nil(out[5].rec)
        assert.equals(2, out[6].rec.order)
        assert.equals(2, cs.window.count)

        -- A withheld channel cancels a pending twin hold, and the record leaves
        -- the work list; a withheld cast does neither.
        for _, kind in ipairs({ "cast", "channel" }) do
            local held = TI.NewCastState({})
            play({ { S, "cast", 1 }, { E, "cast", 1, "stop" }, { S, "cast", 2 }, { E, "cast", 2, "stop" } }, 1, held)
            local waiting = { twinHold = true }
            held.records = { waiting }
            assert.equals("withheld", (TI.ClassifyStart(held, kind, 9, 9, false, 1)))
            assert.equals(kind == "channel" and "canceled" or true, waiting.twinHold)
            assert.equals(kind == "channel" and 0 or 1, #held.records)
        end

        local fresh = TI.NewCastState({})
        assert.equals("normal", fresh.recovery)
        assert.same({ cast = {}, channel = {} }, fresh.history)
    end)

    it("B: an unowned START cancels only the work it can no longer attribute", function()
        for _, kind in ipairs({ "cast", "channel" }) do
            local owner, rt = generation("nameplate1")
            local cs = rt.castState
            local tracked = { nameplate1 = rt }
            local _, replaced = TI.ClassifyStart(cs, "channel", 1, 1)
            replaced.cueConsumed = true
            local earlier = { owner = owner, postEnd = true, twinHold = true }
            cs.records = { earlier }
            cs.pendingAdvance = { record = replaced, provenance = "fresh" }
            local class, unowned = TI.ClassifyStart(cs, kind, nil, 2)
            assert.equals("unowned", class)
            assert.is_true(replaced.canceled)
            assert.is_true(replaced.impliedStopVoid)
            assert.is_true(replaced.cueConsumed)
            assert.is_nil(cs.pendingAdvance)
            assert.equals("canceled", earlier.postEnd)
            assert.equals(kind == "channel" and "canceled" or true, earlier.twinHold)
            -- Only a record with work still pending stays on the work list.
            assert.equals(kind == "channel" and 0 or 1, #cs.records)
            assert.is_true(TI.CastCallbackHolds(owner, tracked, true, earlier, "credit"))
            assert.equals(1, cs.seq)
            assert.is_nil(unowned.seq)
            assert.is_false(TI.CastCallbackHolds(owner, tracked, true, unowned, "start"))
            assert.is_false(TI.CastCallbackHolds(owner, tracked, true, unowned, "cue"))
            assert.equals("unowned", (TI.ClassifyStart(cs, kind, nil, 3)))
            assert.equals(1, cs.seq)
            assert.is_nil(cs.pendingAdvance)
        end
        local _, rt = generation("nameplate2")
        local cs = rt.castState
        local _, armed = TI.ClassifyStart(cs, "cast", 1, 1)
        local cached = { provenance = "cached", at = 50, fingerprints = { targetExists = true },
            fingerprintsReady = true }
        cs.pendingAdvance = cached
        TI.ClassifyStart(cs, "cast", nil, 2)
        assert.equals(cached, cs.pendingAdvance)
        assert.equals(50, cached.at)
        assert.is_true(cached.fingerprints.targetExists)
        assert.is_true(armed.canceled)
    end)

    it("C: a baseline closes only on its own correlated end, and never becomes eligible", function()
        local S, E, C = "start", "end", "combat"
        local cases = {
            { ending = { E, "cast", 5, "stop" }, outcome = "baseline-close", state = "closed", latch = false },
            { kind = "channel", ending = { E, "channel", 5, "stop" }, outcome = "baseline-close", state = "closed",
              latch = false },
            { ending = { E, "cast", 5, "interrupted" }, outcome = "baseline-close", state = "closed", latch = true },
            { ending = { E, "cast", 5, "failed" }, outcome = "baseline-close", state = "closed", latch = false },
            { ending = { E, "cast", nil, "stop" }, outcome = "refused", state = "baseline", latch = false },
            { ending = { E, "cast", 6, "stop" }, outcome = "refused", state = "baseline", latch = false },
        }
        for i, c in ipairs(cases) do
            local kind = c.kind or "cast"
            local _, out = play({ { S, kind, nil }, { S, kind, 5 }, c.ending })
            assert.equals(c.outcome, out[3].class, "row " .. i)
            assert.equals(c.state, out[3].state, "row " .. i)
            assert.equals(c.latch, out[3].latch, "row " .. i)
            assert.is_false(out[2].rec.eligible, "row " .. i)
        end

        local retired = play({ { S, "cast", nil }, { C, true }, { S, "cast", 5 }, { C, false } })
        assert.equals("uncertain", retired.recovery)
        assert.equals("refused", (TI.ClassifyEnd(retired, "cast", 5, "stop", 9)))
        assert.equals("uncertain", retired.recovery)

        local cs, out = play({ { C, false }, { S, "cast", nil }, { C, true }, { S, "cast", 5 },
            { E, "cast", 5, "stop" }, { S, "cast", 6 } })
        assert.is_false(out[4].rec.eligible)
        assert.equals("normal", out[6].class)
        assert.is_true(out[6].rec.eligible)
        assert.is_nil(out[6].rec.order)
        assert.is_false(cs.window.known)
    end)

    it("D: the counting window opens known only after a confirmed exit with clean recovery", function()
        local S, E, C = "start", "end", "combat"
        local opens = {
            { events = { { C, false }, { C, true } }, known = true },
            { events = { { C, true } }, known = false },
            { events = { { C, false }, { S, "cast", nil }, { C, true } }, known = false },
            { events = { { C, false }, { S, "cast", nil }, { S, "cast", 5 }, { C, true } }, known = false },
            { capacity = 1, events = { { S, "cast", 1 }, { S, "cast", 2 }, { S, "cast", 3 }, { C, false },
                { C, true } }, known = false },
        }
        for i, c in ipairs(opens) do
            local cs = play(c.events, c.capacity or 2)
            assert.equals(c.known, cs.window.known, "row " .. i)
        end

        local quiet = TI.NewCastState({})
        assert.is_nil(TI.CombatWindowStep(quiet, nil))
        assert.is_nil(quiet.window)
        assert.is_false(quiet.seenFalse)

        local cs, out = play({ { C, false }, { C, true }, { S, "cast", 1 } })
        local open = out[3].rec
        local completed = { window = cs.window, postEnd = true }
        cs.records = { completed }
        cs.pendingAdvance = { record = open, provenance = "fresh" }
        cs.pairing, cs.transition = { at = 1 }, { at = 1 }
        assert.equals("closed", TI.CombatWindowStep(cs, false))
        assert.is_true(open.retired)
        assert.is_false(open.open)
        assert.is_true(completed.retired)
        assert.is_nil(cs.pendingAdvance)
        assert.is_nil(cs.pairing)
        assert.is_nil(cs.transition)

        local _, early = play({ { C, false }, { S, "channel", 1 }, { C, true } })
        assert.is_nil(early[2].rec.order)

        local saturating = play({ { S, "cast", 1 }, { E, "cast", 1, "stop" }, { S, "cast", nil },
            { C, true }, { S, "cast", 5 }, { C, false } }, 1)
        assert.equals("saturated", saturating.recovery)
        TI.CombatWindowStep(saturating, true)
        assert.is_false(saturating.window.known)
        assert.equals("saturated", saturating.recovery)

        local engaging = select(2, play({ { C, false }, { C, true }, { S, "cast", 1 } }))
        assert.equals(1, engaging[3].rec.order)
        local pre = select(2, play({ { C, false }, { S, "cast", 1 }, { C, true }, { S, "cast", 2 } }))
        assert.is_nil(pre[2].rec.order)
        assert.equals(1, pre[4].rec.order)

        local unknown, seq = play({ { C, false }, { C, true }, { S, "cast", 1 }, { S, "cast", nil },
            { S, "cast", 2 }, { E, "cast", 2, "stop" }, { S, "cast", 3 }, { C, false }, { C, true },
            { S, "cast", 4 } })
        assert.equals(1, seq[3].rec.order)
        assert.is_nil(seq[7].rec.order)
        assert.is_true(seq[7].rec.eligible)
        assert.equals(1, seq[10].rec.order)
        assert.is_true(unknown.window.known)

        local firstSeen = select(2, play({ { C, true }, { S, "cast", 1 } }))
        assert.is_true(firstSeen[2].rec.eligible)
        assert.is_nil(firstSeen[2].rec.order)
    end)

    it("E: delayed cast work runs only for its own live owner and a record still owning it", function()
        local owner, rt = generation("nameplate1")
        local cs = rt.castState
        local tracked = { nameplate1 = rt }
        local function holds(rec, work) return TI.CastCallbackHolds(owner, tracked, true, rec, work) end

        local _, a = TI.ClassifyStart(cs, "cast", 1, 1)
        assert.is_true(holds(a, "start"))
        assert.is_true(holds(a, "cue"))
        TI.ClassifyEnd(cs, "cast", 1, "stop", 2)
        assert.is_true(holds(a, "start"))
        assert.is_false(holds(a, "cue"))
        a.postEnd, a.twinHold = true, true
        cs.records = { a }
        local _, b = TI.ClassifyStart(cs, "cast", 2, 3)
        assert.is_false(holds(a, "start"))
        assert.is_true(holds(a, "postEnd"))
        assert.is_true(holds(b, "cue"))
        TI.ClassifyStart(cs, "cast", nil, 4)
        assert.is_false(holds(a, "postEnd"))
        assert.is_true(holds(a, "credit"))
        assert.is_false(holds(b, "start"))

        local works = { "start", "cue", "postEnd", "twinHold", "credit" }
        local _, liveRt = generation("nameplate3")
        local liveCs = liveRt.castState
        local _, c = TI.ClassifyStart(liveCs, "cast", 7, 1)
        c.postEnd, c.twinHold = true, true
        c.retired = true
        local deadOwner, deadRt = generation("nameplate4")
        local _, d = TI.ClassifyStart(deadRt.castState, "cast", 8, 1)
        d.postEnd, d.twinHold = true, true
        deadOwner.live = false
        local reusedOld = { owner = deadOwner, eligible = true, open = true, postEnd = true, twinHold = true }
        for _, work in ipairs(works) do
            assert.is_false(TI.CastCallbackHolds(liveRt.owner, { nameplate3 = liveRt }, true, c, work), work)
            assert.is_false(TI.CastCallbackHolds(deadOwner, { nameplate4 = deadRt }, true, d, work), work)
            assert.is_false(holds(reusedOld, work), work)
        end

        assert.is_false(TI.PendingAdvanceReady({ provenance = "cached", fingerprintsReady = false }, true))
        assert.is_true(TI.PendingAdvanceReady({ provenance = "cached", fingerprintsReady = false }, false))
        assert.is_true(TI.PendingAdvanceReady({ provenance = "cached", fingerprintsReady = true }, true))
        assert.is_false(TI.PendingAdvanceReady({ provenance = "cached", fingerprintsReady = true,
            targetNeeded = true, targetState = "pending" }, true))
        assert.is_false(TI.PendingAdvanceReady({ consumed = true }, false))

        local fresh, adopted = generation("nameplate5")
        local moved = adopted.castState
        local held = { owner = fresh, eligible = true, open = false, twinHold = true, seq = 41 }
        local _, open = TI.ClassifyStart(moved, "cast", 3, 1)
        open.seq = 42
        moved.records = { held, open }
        local adoptedTracked = { nameplate5 = adopted }
        assert.is_true(TI.CastCallbackHolds(fresh, adoptedTracked, true, held, "twinHold"))
        assert.is_true(TI.CastCallbackHolds(fresh, adoptedTracked, true, open, "cue"))
    end)

    it("opening order: what counts, what inherits, and what the order selects", function()
        local S, E, C = "start", "end", "combat"
        local _, counted = play({ { C, false }, { C, true }, { S, "cast", 1 }, { E, "cast", 1, "interrupted" },
            { S, "cast", 2 }, { S, "channel", 3 } })
        assert.equals(1, counted[3].rec.order)
        assert.equals(2, counted[5].rec.order)
        assert.equals(3, counted[6].rec.order)

        local cs, repeats = play({ { C, false }, { C, true }, { S, "channel", 1 }, { S, "channel", 1 },
            { S, "channel", 2, refresh = true } })
        assert.equals(1, repeats[3].rec.order)
        assert.equals(1, cs.window.count)

        local proof = play({ { C, false }, { C, true } })
        local _, source = TI.ClassifyStart(proof, "cast", 1, 1)
        TI.AssignOrder(proof, source)
        local _, phase = TI.ClassifyStart(proof, "channel", 2, 2)
        TI.AssignOrder(proof, phase, source)
        assert.equals(1, phase.order)
        assert.equals(1, proof.window.count)

        local spells = {
            [10] = { castTime = 2, openingCastOrder = 1 },
            [20] = { castTime = 2, openingCastOrder = 2 },
            [30] = { channelTime = 4, openingCastOrder = 1 },
            [40] = { castTime = 3 },
        }
        assert.same({ [10] = spells[10] }, TI.SelectOrderRows(spells, "cast", 1))
        assert.same({ [30] = spells[30] }, TI.SelectOrderRows(spells, "channel", 1))
        assert.equals(spells, TI.SelectOrderRows(spells, "cast", 3))
        assert.equals(spells, TI.SelectOrderRows(spells, "cast", nil))
        local firstSeen = select(2, play({ { C, true }, { S, "cast", 1 } }))
        assert.equals(spells, TI.SelectOrderRows(spells, "cast", firstSeen[2].rec.order))
        local plain = { [50] = { castTime = 2 } }
        assert.equals(plain, TI.SelectOrderRows(plain, "cast", 1))
    end)
end)

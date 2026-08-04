-- ╔══════════════════════════════════════════════════════════╗
-- ║  TrashInference.lua                                      ║
-- ║  Pure inference core for the Dungeon Trash tracker.      ║
-- ║                                                          ║
-- ║  In a 12.0 instance you can read neither a nameplate's   ║
-- ║  npcID (UnitGUID secret) nor a cast's spellID (secret),  ║
-- ║  so trash detection is a behavioral-inference engine:    ║
-- ║    Layer1 — fingerprint the mob from non-secret identity ║
-- ║             (level/sex/power/class/aura-count) against   ║
-- ║             KE.TrashTraits → candidate npcIDs.           ║
-- ║    Layer2 — disambiguate the CAST from measured cast/    ║
-- ║             channel duration + boolean fingerprints.     ║
-- ║    cd walk — predict the next cast from first + cd[].    ║
-- ║                                                          ║
-- ║  This file is PURE (no WoW API, no per-nameplate state); ║
-- ║  DungeonTrash.lua owns the event loop + runtime state    ║
-- ║  and calls these decision functions. Ported from an      ║
-- ║  upstream reference engine; see                          ║
-- ║  dev/docs/dungeon-trash-engine-port-spec.md.             ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local math_floor = math.floor
local table_sort = table.sort
local type = type
local tonumber = tonumber
local pairs = pairs
local ipairs = ipairs
local abs = math.abs

local TI = {}
KE.TrashInference = TI

-- ── Constants (verbatim from the upstream engine) ──────────────────────────
TI.CAST_TIME_TOLERANCE = 0.20   -- measured vs curated cast/channel duration
TI.LEVEL_SQUISH_OFFSET = 60     -- Layer1 accepts obs.level == template-60
TI.MIN_LEAD = 0.20              -- a predicted cast nearer than this is dropped

-- Algeth'ar Academy (map 2526) is the one dungeon whose several eagle/tamer
-- mobs share an identical identity fingerprint; the engine disambiguates
-- them by M+ enemy-forces %. These are the four npcIDs that share the
-- signature.
local ACADEMY_MAP_ID = 2526
local ACADEMY_ROUTED_NPCS = {
    [197219] = true, [192680] = true, [192333] = true, [196671] = true,
}

-- Skyreach (map 1209): an upstream-fork-only Layer1 rule — the Suntalon
-- Tamer spawns only inside the 52-60% enemy-forces window, so a KNOWN
-- percent outside it prunes the tamer from multi-candidate sets. Unknown
-- forces stay ungated.
local SKYREACH_MAP_ID = 1209
local SKYREACH_TAMER_NPC = 76154

-- ╔══════════════════════════════════════════════════════════╗
-- ║  Packed identity decoder (verification / fallback)       ║
-- ╚══════════════════════════════════════════════════════════╝
-- The data already ships decoded `identity` tables; this mirrors the
-- upstream packed-row decoder so a spec can round-trip packedIdentity →
-- identity and catch a generator drift. b(shift,width) = the `width` bits
-- of `p` at `shift`.
function TI.DecodePackedIdentity(p)
    p = tonumber(p) or 0
    local function b(shift, width)
        return math_floor(p / (2 ^ shift)) % (2 ^ width)
    end
    return {
        buffCount        = b(0, 4),
        classID          = b(4, 4),
        sex              = b(8, 3),
        power            = b(11, 3),
        level            = b(14, 7),
        hasCastSkill     = b(37, 1) == 1,
        noCastSkill      = b(38, 1) == 1,
        hasCastSpell     = b(39, 1) == 1,
        hasChannelSpell  = b(40, 1) == 1,
        hasInterruptFlag = b(41, 1) == 1,
        cannotInterrupt  = b(42, 1) == 1,
        nonElite         = b(43, 1) == 1,
    }
end

-- ╔══════════════════════════════════════════════════════════╗
-- ║  Layer 1 — mob candidate scoring                         ║
-- ╚══════════════════════════════════════════════════════════╝

-- Placement gate. `placement` is a CSV: values ≤20 are dungeon boss-progress
-- indices, values >20 are sub-zone map tokens (multi-floor dungeons). The two
-- kinds are independent AND-gates (reference: the map set is checked BEFORE
-- the stage set and BOTH must pass — a known-mismatched tier rejects
-- regardless of the other's match). Map tokens are TWO-TIER (reference
-- behavior): a token is either a uiMapID — equality with
-- opts.currentSubZoneMapID — or an areaID, whose C_Map.GetAreaInfo name (via
-- the opts.resolveAreaName closure; this file stays pure) is compared to the
-- live opts.currentZoneText. Nexus-Point Xenas ships areaID tokens
-- (16573-16576) that can never equal a uiMapID — without the name tier those
-- five mobs would hard-reject their own rows the moment a sub-zone is known.
-- Map 2526 is exempt. Missing/unparseable placement fails OPEN, and each tier
-- fails OPEN when its own runtime datum is unknown (never over-filter on
-- missing data).
function TI.IsPlacementAllowed(placement, opts)
    if opts and opts.mapID == ACADEMY_MAP_ID then return true end
    if type(placement) ~= "string" or placement == "" then return true end

    local bossIndex = opts and opts.bossProgressIndex
    local subZone = opts and opts.currentSubZoneMapID
    local zoneText = opts and opts.currentZoneText
    if zoneText == "" then zoneText = nil end
    local resolveArea = opts and opts.resolveAreaName
    local sawStage, sawMap = false, false
    local stageMatch, mapMatch = false, false
    for token in placement:gmatch("[^,]+") do
        local n = tonumber(token)
        if n then
            if n <= 20 then
                sawStage = true
                if bossIndex and n == bossIndex then stageMatch = true end
            else
                sawMap = true
                if subZone and n == subZone then mapMatch = true end
                if not mapMatch and zoneText and resolveArea then
                    local areaName = resolveArea(n)
                    if areaName and areaName ~= "" and areaName == zoneText then mapMatch = true end
                end
            end
        end
    end
    -- Per-tier verdicts: no tokens of that kind, or the runtime datum is
    -- unknown → the tier allows; otherwise it must have matched.
    local stageAllowed = not sawStage or not bossIndex or stageMatch
    local mapAllowed = not sawMap or not (subZone or zoneText) or mapMatch
    return stageAllowed and mapAllowed
end

-- Score one trait row against an identity snapshot.
-- obs fields (all optional; nil = "not observed", scored leniently):
--   level, sex, power, classID, buffCount, unitClassification,
--   sawCastStart, sawChannelStart, sawInterrupted.
-- Returns matched(bool), score(int), strength(int), reject(string|nil).
-- A present-in-row / present-in-obs exact-mismatch HARD-REJECTS (matched=false).
function TI.ScoreTraitRow(obs, trait, opts)
    local id = trait and trait.identity
    if not id then return false, 0, 0, "no-identity" end
    local score, strength = 0, 0
    -- Resolve-confidence flag (5th return). A lone Layer1 survivor is only trusted
    -- as a CONFIDENT single resolve if it agreed on the level — the one
    -- discriminating soft field — not merely on the coarse sex/power/classID triple
    -- many mobs share. Without it, a mob whose own row is pruned/absent collapses
    -- onto a fingerprint-sibling and gets rubber-stamped (proven in-game:
    -- Rokh'zal/Gnarldin false positives). The reference gets this by HARD-rejecting
    -- level; KE keeps level soft for candidate SURVIVAL (Maisara scaling) but gates
    -- the confident resolve on agreement. buffCount is deliberately NOT counted
    -- here — buffCount 0 is too common to be evidence. See BuildCandidates.
    local levelAgreed = false

    -- level: SOFT tiebreak below the row, HARD reject above it. Curated levels
    -- are a capture-time artifact that drifts DOWNWARD against live scaling:
    -- Maisara mobs captured at 91 read as 90 in the live key, and a hard reject
    -- on that drift pruned every mob's OWN row and collapsed the whole pull onto
    -- the sole curated level-90 row (the Hexbound Eagle, 249020). So a LOWER
    -- observed level scores softly and lets Layer2 cast/channel DURATION —
    -- stable across scaling — disambiguate. An observed level ABOVE the row is
    -- a different animal: downward drift never produces it, but boss plates sit
    -- one level above trash (the reference's boss engine keys on nameplate
    -- level 92 vs trash 91), and the reference's hard level reject is precisely
    -- what keeps bosses out of its trash pool. Going soft in BOTH directions
    -- silently deleted that boss filter (proven in-game: Magisters' Terrace
    -- bosses resolved to Arcane Sentry / Shadowrift Voidcaller). Rejecting only
    -- the above case restores it and fails SAFE — a boss-tier plate produces no
    -- candidates instead of another mob's timers. Secret/unreadable levels stay
    -- fail-open; the encounter blackout list remains the backstop for those and
    -- for encounter units at trash level (Ick & Krick).
    if id.level ~= nil and obs.level ~= nil then
        strength = strength + 1
        if obs.level == id.level or obs.level == (id.level - TI.LEVEL_SQUISH_OFFSET) then
            score = score + 1
            levelAgreed = true
        elseif obs.level > id.level then
            return false, score, strength, "level-above"
        end
    end

    -- sex / power / classID: exact equality; mismatch HARD-REJECTS. These are
    -- stable, non-secret identity — they do not drift.
    local exactFields = { "sex", "power", "classID" }
    for _, f in ipairs(exactFields) do
        if id[f] ~= nil and obs[f] ~= nil then
            strength = strength + 1
            if tonumber(obs[f]) == tonumber(id[f]) then
                score = score + 1
            else
                return false, score, strength, f
            end
        end
    end

    -- buffCount: SOFT above the row, HARD reject below it. In a 12.0 instance
    -- we can COUNT a mob's auras but not read their spellID/source (secret),
    -- so the observed value is a raw HELPFUL count minus a blanket M+ "-1"
    -- (readIdentity). Live counts drift UPWARD past the captured fingerprint
    -- (proven in-game: a proto-drake's passive buffs inflate the count past
    -- its stored value), and a hard reject on that inflation zeroed the
    -- candidate pool — so an observed count ABOVE the row scores softly and
    -- Layer2 cast-duration disambiguation resolves collisions. A count BELOW
    -- the row is a different animal: nothing inflates downward, and a mob
    -- MISSING the fingerprint's own buffs is a different mob. The reference
    -- hard-rejects any buffCount mismatch, and going soft in both directions
    -- let Maisara's uncurated Reanimated Warriors (b0, otherwise
    -- identity-identical) wear Bound Defender's (b1) timers as its lone
    -- surviving sibling (proven in-game). Rejecting only the below case
    -- restores the reference's discriminator where our field evidence never
    -- contradicted it, keeps the proto-drake alive, and fails safe. Same
    -- asymmetric shape as the level axis above; supersedes the all-soft
    -- rationale in dev/docs/dungeon-trash-engine-port-spec.md §3.
    if id.buffCount ~= nil and obs.buffCount ~= nil then
        strength = strength + 1
        local obsCount, idCount = tonumber(obs.buffCount), tonumber(id.buffCount)
        if obsCount == idCount then
            score = score + 1
        elseif obsCount ~= nil and idCount ~= nil and obsCount < idCount then
            return false, score, strength, "buffcount-below"
        end
    end

    -- classification: elite rows need obs "elite"; nonElite rows need not-"elite".
    if obs.unitClassification ~= nil then
        strength = strength + 1
        if id.nonElite == true then
            if obs.unitClassification == "elite" then return false, score, strength, "classification" end
        else
            if obs.unitClassification ~= "elite" then return false, score, strength, "classification" end
        end
    elseif id.nonElite ~= true then
        -- elite row but classification unknown → reject (matches the reference).
        return false, score, strength, "classification-missing"
    end

    -- behavior capability: only gates once the plate was SEEN doing the thing.
    if obs.sawCastStart and not (id.hasCastSpell or id.hasCastSkill) then
        return false, score, strength, "saw-cast-no-cast-spell"
    end
    if obs.sawChannelStart and not (id.hasChannelSpell or obs.sawCastIntoChannel) then
        return false, score, strength, "saw-channel-no-channel-spell"
    end
    if obs.sawInterrupted and id.cannotInterrupt == true then
        return false, score, strength, "saw-interrupt-but-cannot"
    elseif obs.sawInterrupted then
        score = score + 1
    end

    -- placement.
    if not TI.IsPlacementAllowed(trait.placement, opts) then
        return false, score, strength, "placement"
    end

    return true, score, strength, nil, levelAgreed
end

-- Academy shared-signature test: the eagle/tamer mobs collapse to this.
function TI.MatchesAcademySignature(obs)
    return (obs.level == 91 or obs.level == 31)
        and obs.sex == 1 and obs.power == 1
        and obs.classID == 1 and obs.buffCount == 0
end

-- Route the Academy signature to a single npcID by M+ enemy-forces %.
-- Boundaries ported verbatim (note the deliberate gaps → fall to 196671).
-- UNKNOWN forces (nil) return nil: the newer upstream fork deliberately
-- SKIPS the Layer1 prune then, letting Layer2 cast behavior disambiguate —
-- the older upstream 196671 hard-route misidentified the eagle/tamer mobs
-- in every non-M+ Academy run and during forces-criteria blackouts.
function TI.ResolveAcademyForcesNPC(forcesPercent)
    local f = tonumber(forcesPercent)
    if not f then return nil end
    if f < 20 then return 197219 end
    if f > 20 and f < 25 then return 192680 end
    if f > 26 and f < 42 then return 192333 end
    return 196671
end

-- Build the sorted candidate list for a dungeon from an identity snapshot.
-- opts: { traits=KE.TrashTraits, dungeonKey, mapID, forcesPercent,
--         bossProgressIndex, currentSubZoneMapID, currentZoneText,
--         resolveAreaName }
-- Returns candidates (array of {npcID,name,score,strength}) and resolved
-- (single-survivor npcID or nil).
function TI.BuildCandidates(obs, opts)
    opts = opts or {}
    local traits = opts.traits or KE.TrashTraits or {}
    local dungeonKey = opts.dungeonKey
    local out = {}

    for npcID, trait in pairs(traits) do
        if trait.dungeonKey == dungeonKey then
            local matched, score, strength, _, levelAgreed = TI.ScoreTraitRow(obs, trait, opts)
            if matched then
                out[#out + 1] = { npcID = npcID, name = trait.name, score = score,
                    strength = strength, levelAgreed = levelAgreed }
            end
        end
    end

    -- Academy forces-% routing: when the shared signature is active AND a
    -- live forces percent backs the route, drop every routed npc except the
    -- resolved one. Unknown forces (nil percent — outside M+, or during a
    -- forces-criteria blackout) SKIP the prune entirely so Layer2 cast
    -- behavior disambiguates (the upstream fork's forces-invalid branch; the
    -- caller passes nil for unknown, NEVER 0 — 0 would route to the <20% npc).
    if opts.mapID == ACADEMY_MAP_ID and TI.MatchesAcademySignature(obs) then
        local keep = TI.ResolveAcademyForcesNPC(opts.forcesPercent)
        if keep then
            local filtered = {}
            for _, c in ipairs(out) do
                if not ACADEMY_ROUTED_NPCS[c.npcID] or c.npcID == keep then
                    filtered[#filtered + 1] = c
                end
            end
            out = filtered
        end
    end

    -- Skyreach tamer forces-window prune (an upstream-fork-only rule): outside
    -- [52, 60)% the tamer cannot spawn — drop it from MULTI-candidate sets only
    -- (a lone-survivor tamer stays for Layer2 verification), and never on an
    -- unknown percent.
    if opts.mapID == SKYREACH_MAP_ID and #out > 1 then
        local f = tonumber(opts.forcesPercent)
        if f and (f < 52 or f >= 60) then
            local filtered = {}
            for _, c in ipairs(out) do
                if c.npcID ~= SKYREACH_TAMER_NPC then filtered[#filtered + 1] = c end
            end
            out = filtered
        end
    end

    -- score desc → strength desc → npcID asc (stable, deterministic).
    table_sort(out, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if a.strength ~= b.strength then return a.strength > b.strength end
        return a.npcID < b.npcID
    end)

    -- Confident single resolve requires the lone survivor to have AGREED on level,
    -- not just the coarse sex/power/classID triple. A lone survivor that matched
    -- only that triple (level disagreed) stays unresolved and defers to Layer2 cast
    -- disambiguation — killing the Rokh'zal/Gnarldin rubber-stamp while Souleater
    -- (level agrees) still resolves. Multi-candidate sets are unaffected (they were
    -- already nil → Layer2). See ScoreTraitRow's levelAgreed.
    local resolved = (#out == 1 and out[1].levelAgreed) and out[1].npcID or nil
    return out, resolved
end

-- Reconcile each trait's capability fingerprint against its curated spells. The
-- upstream extractor drops hasChannelSpell for cast-into-channel spells (castTime
-- AND channelTime both > 0) — a FALSE NEGATIVE that makes the Layer1 channel gate
-- in ScoreTraitRow ("saw-channel-no-channel-spell") HARD-REJECT the correct mob
-- the instant it channels, flipping the plate to an identical-except-that-bit
-- twin (Arcane Sentry -> Shadowrift Voidcaller) or to zero candidates. Deriving
-- hasChannelSpell from channelTime>0 (and hasCastSpell from castTime>0) at load
-- keeps the fingerprint from ever contradicting a curated ability. Idempotent:
-- only ever SETS true, never clears (the fingerprint may legitimately know a
-- capability outside the curated subset). Pure — busted-testable.
function TI.ReconcileTraitCapabilities(dataByMap, traits)
    if type(dataByMap) ~= "table" or type(traits) ~= "table" then return end
    for _, dungeon in pairs(dataByMap) do
        local mobs = dungeon and dungeon.mobs
        if mobs then
            for npcID, mob in pairs(mobs) do
                local trait = traits[npcID]
                local id = trait and trait.identity
                if id and mob.spells then
                    for _, sp in pairs(mob.spells) do
                        if (sp.castTime or 0) > 0 then id.hasCastSpell = true end
                        if (sp.channelTime or 0) > 0 then id.hasChannelSpell = true end
                    end
                end
            end
        end
    end
end

-- ╔══════════════════════════════════════════════════════════╗
-- ║  Layer 2 — cast disambiguation                           ║
-- ╚══════════════════════════════════════════════════════════╝

-- Data fingerprint field → observed-sample field. Compared only when the
-- data field is present AND both sides are the right type (never reject on an
-- unsampled/nil observation — matches the reference's type()=="boolean" gate).
local BOOL_FINGERPRINTS = {
    { data = "targetExists",           obs = "targetExists" },
    { data = "targetAPIExists",        obs = "targetAPIExists" },
    { data = "castStartChangeTarget",  obs = "castStartChangeTarget" },
    { data = "targetClearOnCastStart", obs = "targetClearOnCastStart" },
    -- castStartAuraDelta additionally carries a PRESENCE-SYMMETRIC clause in
    -- fingerprintsMatch below: a sampled delta with no curating spell rejects.
    { data = "castStartAuraDelta",     obs = "castStartAuraDelta" },
    -- Declared upstream but backed by zero shipped data rows — mapped anyway
    -- so a future TrashData regeneration that adds rows cannot silently
    -- leave them undiscriminable. castStartTargetUnitExists is the same
    -- UnitExists(target) probe fpTargetExists already samples.
    { data = "castStartTargetUnitExists", obs = "targetExists" },
    { data = "targetIsTank",           obs = "targetIsTank" },
}

local function durationWithin(a, b, tol)
    return type(a) == "number" and type(b) == "number" and abs(a - b) <= tol
end

-- Channel-evidence discriminator (ported from upstream): a channel with a
-- PROVEN cast→channel transition can only be a two-phase spell's channel
-- phase — reject pure channels; one whose proof is affirmatively ABSENT
-- cannot be a two-phase spell, whose channel is only reachable through its
-- cast — reject those. Gated on the evidence being present (boolean): an
-- unknown (unreadable castBarID made the proof impossible) stays lenient,
-- like every other fingerprint here.
local function channelEvidenceMatches(spellData, observed)
    if observed.kind ~= "channel" or type(observed.castIntoChannel) ~= "boolean" then
        return true
    end
    local isTwoPhase = (tonumber(spellData.castTime) or 0) > 0
    return observed.castIntoChannel == isTwoPhase
end

-- Do a spell's boolean/numeric fingerprints agree with an observed cast? This is
-- the DURATION-AGNOSTIC tail of matching, shared by SpellMatchesObserved and by
-- InferSucceededSpell's channel fallback (Pass 2), which must identify a channel
-- WITHOUT a duration gate.
local function fingerprintsMatch(spellData, observed)
    local fp = observed.fingerprints
    if fp then
        for _, m in ipairs(BOOL_FINGERPRINTS) do
            local want = spellData[m.data]
            local got = fp[m.obs]
            if type(want) == "boolean" and type(got) == "boolean" and want ~= got then
                return false
            end
        end
        -- castStartAuraDelta is PRESENCE-SYMMETRIC, unlike the rows above
        -- (reference: a RESOLVED aura delta rejects every non-curating spell
        -- when matched AND every curating spell when not — that branch has no
        -- nil-data wildcard). The sampler resolves the observation to a hard
        -- true/false on every sampled cast, so "a fresh party debuff landed
        -- but this spell doesn't curate one" is disconfirming evidence, not
        -- an unknown. An UNSAMPLED nil observation stays lenient (sampler
        -- unavailable, or the needs gate skipped the mob) like every other
        -- fingerprint here.
        if type(fp.castStartAuraDelta) == "boolean"
            and fp.castStartAuraDelta ~= (spellData.castStartAuraDelta == true) then
            return false
        end
    end
    -- numeric success buff-count delta fingerprint.
    if type(spellData.selfBuffCountDeltaOnSuccess) == "number"
        and type(observed.selfBuffCountDelta) == "number"
        and spellData.selfBuffCountDeltaOnSuccess ~= observed.selfBuffCountDelta then
        return false
    end
    return true
end

-- Kind + duration SHAPE alone — no evidence tail (fingerprints / channel
-- evidence). Split out so FilterCandidates can distinguish "this observation
-- is uncurated FILLER for the mob" (no curated spell fits the shape → the
-- trait-duration keep tier may apply) from "a curated spell fits the shape
-- but its EVIDENCE rejects" (affirmative disconfirmation the trait tier must
-- never override — see anySpellMatches).
local function spellShapeMatches(spellData, observed)
    local tol = TI.CAST_TIME_TOLERANCE
    if observed.kind == "channel" then
        if not spellData.channelTime then return false end
        return durationWithin(observed.duration, spellData.channelTime, tol)
    end
    -- cast: primary castTime or any castTimeExtra alternate.
    local ok = durationWithin(observed.duration, spellData.castTime, tol)
    if not ok and type(spellData.castTimeExtra) == "table" then
        for _, alt in ipairs(spellData.castTimeExtra) do
            if durationWithin(observed.duration, alt, tol) then ok = true; break end
        end
    end
    return ok
end

-- Does one curated spell match an observed cast?
-- observed: { kind="cast"|"channel", duration, fingerprints={...}, selfBuffCountDelta }
-- Returns true if kind + duration (± tolerance, incl. castTimeExtra alternates)
-- + every present boolean fingerprint agree.
function TI.SpellMatchesObserved(spellData, observed)
    if not (spellData and observed) then return false end
    if not spellShapeMatches(spellData, observed) then return false end
    if observed.kind == "channel" and not channelEvidenceMatches(spellData, observed) then
        return false
    end
    return fingerprintsMatch(spellData, observed)
end

-- Does an observed CAST's duration (and fingerprints) also fit one of the
-- mob's TWO-PHASE (cast→channel) spells? When true, a finished bare cast is
-- ambiguous between a one-phase twin and a two-phase spell's cast phase until
-- the castBarID pairing window closes — the caller holds the one-phase credit
-- and discards it if the +1 channel pairing claims this cast (4 curated mobs
-- carry a same-duration twin; e.g. Arcane Sentry's 3s Crowd Dispersal vs the
-- 3s+5s Arcane Beam).
function TI.MatchesTwoPhaseCast(mobData, observed)
    if not (mobData and mobData.spells and observed) then return false end
    if observed.kind ~= "cast" then return false end
    for _, spell in pairs(mobData.spells) do
        if (spell.castTime or 0) > 0 and (spell.channelTime or 0) > 0
            and TI.SpellMatchesObserved(spell, observed) then
            return true
        end
    end
    return false
end

-- Does any of the mob's spells of this kind curate a success self-buff-count
-- delta? The caller must then SAMPLE the delta (before/after counts around
-- the stop) before crediting — the reference defers consumption on exactly
-- this need.
function TI.NeedsSelfBuffCountDelta(mobData, kind)
    if not (mobData and mobData.spells) then return false end
    for _, spell in pairs(mobData.spells) do
        local kindMatches
        if kind == "channel" then
            kindMatches = (spell.channelTime or 0) > 0
        else
            kindMatches = (spell.castTime or 0) > 0
        end
        if kindMatches and tonumber(spell.selfBuffCountDeltaOnSuccess) ~= nil then
            return true
        end
    end
    return false
end

local function hasPositiveDuration(v)
    if type(v) == "number" then return v > 0 end
    if type(v) == "table" then
        for _, n in ipairs(v) do
            if type(n) == "number" and n > 0 then return true end
        end
    end
    return false
end

-- Is a CAST_START spell OWNED by the start-advance path? Requires every
-- curated start fingerprint to be one the engine can discriminate with:
-- castStartAuraDelta needs the party aura-delta sampler (TrashAuraDelta.lua,
-- the reference's own discriminator, now ported), which only runs while
-- group auras are readable. auraDeltaUsable answers "can the delta
-- discriminate THIS consult" and callers derive it per site:
--   • the pre-sample WAIT decision (NeedsStartFingerprints) passes the
--     SESSION sampler availability — before the sample lands, availability
--     is the only knowable thing;
--   • MATCH/ownership decisions (start consumption, success-credit swallow)
--     pass the PER-CAST sampled state (type(fp.castStartAuraDelta) ==
--     "boolean") — candidate churn across the sample window can leave the
--     delta unsampled with the ready bit set, and an owned spell matched on
--     a lenient nil would anchor at a start the sample never discriminated
--     (churn guard, review find).
-- Usable → the fingerprint discriminates the start (a Riftbreath start
-- carries no fresh party debuff, so Vicious Ambush 388942 — the one shipped
-- row — cannot cross-anchor on it) and a meld-FAILED Ambush still advances
-- at its observed START. Not usable → the spell keeps the success-path
-- anchor for that cast (the pre-sampler behavior).
function TI.IsStartAdvanceOwned(spellData, auraDeltaUsable)
    if type(spellData) ~= "table" or spellData.cdMode ~= "CAST_START" then
        return false
    end
    if spellData.castStartAuraDelta == true and auraDeltaUsable ~= true then
        return false
    end
    return true
end

-- Does any start-advance-owned spell curate a boolean start fingerprint?
-- The pending start-advance's +0.10s fingerprint wait is NEEDS-BASED
-- (reference: fingerprint waits exist only for spells that curate one): with
-- nothing curated there is nothing to sample, and the wait must not gate
-- consumption — the sampler is the only writer of the ready bit, and a plate
-- blink inside the 0.10s window would otherwise strand the pending forever.
function TI.NeedsStartFingerprints(mobData, auraDeltaUsable)
    if not (mobData and mobData.spells) then return false end
    for _, spell in pairs(mobData.spells) do
        if TI.IsStartAdvanceOwned(spell, auraDeltaUsable) then
            for _, m in ipairs(BOOL_FINGERPRINTS) do
                if type(spell[m.data]) == "boolean" then return true end
            end
        end
    end
    return false
end

-- Does a CAST_START spell match an observed cast START? Kind rule verbatim
-- from the reference: "cast" needs a curated cast duration; "channel" needs
-- channel-ONLY — a two-phase spell start-matches exclusively its cast phase
-- (its channel start is the transition pairing's job, never a fresh advance).
-- Fingerprints reuse the shared duration-agnostic tail; duration itself is
-- unknowable at start.
function TI.MatchesObservedCastStart(spellData, kind, fingerprints, auraDeltaUsable)
    if not TI.IsStartAdvanceOwned(spellData, auraDeltaUsable) then return false end
    local hasCast = hasPositiveDuration(spellData.castTime)
        or hasPositiveDuration(spellData.castTimeExtra)
    if kind == "cast" then
        if not hasCast then return false end
    elseif kind == "channel" then
        if hasCast or not hasPositiveDuration(spellData.channelTime) then return false end
    else
        return false
    end
    return fingerprintsMatch(spellData, { fingerprints = fingerprints })
end

-- Duration-agnostic cast-start fingerprint check for the observed cast-start
-- cue — the +0.10s sampled start fingerprints act as HARD eligibility
-- filters ahead of the cue's nearest-predicted-start scoring, exactly like
-- the reference's voice-time re-resolution. Unsampled (nil) observations
-- stay lenient.
function TI.StartFingerprintsMatch(spellData, fingerprints)
    if type(spellData) ~= "table" then return false end
    return fingerprintsMatch(spellData, { fingerprints = fingerprints })
end

-- Trait-duration keep tier (reference behavior: the trait table's
-- castTimeSet/channelTimeSet — every cast duration the mob is KNOWN to
-- perform, curated timer spells or not — is unioned into the Layer2 keep
-- rules, and Layer2 consults those rules BEFORE curated spells).
-- 16 shipped durations across 10 mobs have no curated timer spell, so without
-- this tier a routine "filler" cast reads as DISCONFIRMING evidence against
-- the true mob: it gets pruned from its own candidate pool (collapsing onto a
-- fingerprint sibling — the Maisara Hexxer mislabel class) or a lone survivor
-- fails its verification on every filler. KEEP evidence only: a trait
-- duration names no spellID and carries no cd, so InferSucceededSpell never
-- consults it — a filler cast keeps the mob alive without crediting a timer.
function TI.TraitDurationMatches(trait, observed)
    if not (trait and observed) then return false end
    -- Explicit per-kind select: the and/or form fell through to castTimeSet
    -- when a CHANNEL observation met a nil channelTimeSet, so a cast-only
    -- mob survived real channel evidence (audit F2 — the same and/or-collapse
    -- class as the alert-group field bug; the reference compiles
    -- and consumes the two sets independently).
    local set
    if observed.kind == "channel" then
        set = trait.channelTimeSet
    else
        set = trait.castTimeSet
    end
    if type(set) ~= "table" then return false end
    for _, dur in ipairs(set) do
        if durationWithin(observed.duration, dur, TI.CAST_TIME_TOLERANCE) then
            return true
        end
    end
    return false
end

-- Resolve-without-lock guard (reference semantics adapted for KE's lock).
-- A bare channel — castIntoChannel nil, the ONLY unproven state KE
-- emits (it can never affirm a transition's absence; see the producer) —
-- verifies a candidate through the lenient Pass-2 shape, and a TWO-PHASE
-- spell's channelTime passes that shape as easily as a pure channel's. The
-- reference survives the same lenient match because it never locks: every
-- pass re-derives, so a coincidental match self-corrects on the next cast.
-- KE's castConfirmed must therefore not be earned by that ambiguity: channel
-- evidence locks only when the transition was PROVEN (castIntoChannel true)
-- or the mob affirms a PURE channel (channelTime without castTime) whose
-- fingerprints agree. A trait-only or two-phase-only match still RESOLVES —
-- output arms — but stays flippable until stronger evidence confirms it.
-- Cast evidence is untouched (duration-gated — never shape-ambiguous).
function TI.ChannelEvidenceLocks(mobData, observed)
    if not observed or observed.kind ~= "channel" then return true end
    if observed.castIntoChannel == true then return true end
    if not (mobData and mobData.spells) then return false end
    for _, spell in pairs(mobData.spells) do
        if (tonumber(spell.channelTime) or 0) > 0
            and (tonumber(spell.castTime) or 0) <= 0
            and fingerprintsMatch(spell, observed) then
            return true
        end
    end
    return false
end

-- Narrow a candidate npcID list by an observed cast. dataByNpc(npcID) returns
-- that mob's data table (with .spells); traitByNpc(npcID), when provided,
-- returns its KE.TrashTraits row for the trait-duration keep tier above.
-- Keeps only candidates having at least one spell (or known trait duration)
-- that matches; if that collapses to a strict subset it wins, else the
-- original list is returned (ambiguous → resolve stays nil upstream).
-- A LONE candidate is VERIFIED, not rubber-stamped: it resolves only when the
-- observed cast matches one of its curated spells or trait durations. This is
-- the "defers to Layer2 cast disambiguation" that BuildCandidates promises
-- for a lone level-disagreed survivor — without it that mob could never
-- resolve at all (the old caller-side #>1 gate made the deferral dead code).
-- The reference engine runs Layer2 on every resolve pass regardless of count.
-- A CHANNEL verifies the lone survivor by the Pass-2 shape — channel
-- capability + channel evidence + fingerprints, NO duration gate: a grab/beam
-- channel's caster CHANNEL_STOP fires at castbar close, far short of curated
-- channelTime (Plungegrip 0.85s vs 12s), so a duration-gated verify left
-- every channel-only mob permanently unresolvable once its level disagreed
-- (a kick bypasses the verify entirely; a completion failed the gate). The
-- reference resolves a lone survivor with NO verification at all — this
-- capability-shaped verify is still strictly stronger.
function TI.FilterCandidates(candidates, observed, dataByNpc, traitByNpc)
    if type(candidates) ~= "table" then return candidates, nil end
    local function traitMatches(npcID)
        local trait = traitByNpc and traitByNpc(npcID)
        return TI.TraitDurationMatches(trait, observed)
    end
    local function anySpellMatches(npcID)
        local mob = dataByNpc and dataByNpc(npcID)
        local shapeRejected = false
        if mob and mob.spells then
            for _, spell in pairs(mob.spells) do
                if TI.SpellMatchesObserved(spell, observed) then return true end
                if spellShapeMatches(spell, observed) then shapeRejected = true end
            end
        end
        -- Trait-duration revival is FILLER-ONLY (audit F1; reference:
        -- fingerprint narrowing is a separate FIRST stage —
        -- NarrowByCurrentFingerprint — and duration rules apply only to its
        -- survivors): a curated spell whose kind+duration fit but whose
        -- EVIDENCE rejected is affirmative disconfirmation, and letting the
        -- fingerprint-blind trait set resurrect the candidate would
        -- neutralize every curated discriminator that shares a trait
        -- duration (the Skyreach twins' castStartChangeTarget: both trait
        -- sets carry the shared 3s cast, so the old fallthrough kept both
        -- twins forever and the Batch E splitter was dead in production).
        if shapeRejected then return false end
        return traitMatches(npcID)
    end
    local function channelVerifies(npcID)
        local mob = dataByNpc and dataByNpc(npcID)
        local evidenceRejected = false
        if mob and mob.spells then
            for _, spell in pairs(mob.spells) do
                if (tonumber(spell.channelTime) or 0) > 0 then
                    if channelEvidenceMatches(spell, observed)
                        and fingerprintsMatch(spell, observed) then
                        return true
                    end
                    -- Same filler-only rule as anySpellMatches; the channel
                    -- verify's "shape" is channel capability (Pass-2 has no
                    -- duration gate), so a channel-capable spell rejected by
                    -- evidence blocks the trait fallback.
                    evidenceRejected = true
                end
            end
        end
        if evidenceRejected then return false end
        return traitMatches(npcID)
    end
    if #candidates <= 1 then
        local c = candidates[1]
        local verified = false
        if c then
            if observed and observed.kind == "channel" then
                verified = channelVerifies(c.npcID)
            else
                verified = anySpellMatches(c.npcID)
            end
        end
        return candidates, (verified and c.npcID) or nil
    end
    local kept = {}
    for _, c in ipairs(candidates) do
        if anySpellMatches(c.npcID) then kept[#kept + 1] = c end
    end
    if #kept > 0 and #kept < #candidates then
        return kept, (#kept == 1) and kept[1].npcID or nil
    end
    return candidates, nil
end

-- Pick which of a mob's spells just SUCCEEDED. Scores each timed spell by
-- durationDelta*100 + scheduleProximity; lowest wins; a spell whose measured
-- duration is outside tolerance, or whose fingerprints disagree, is skipped.
-- anchors[spellID] = { anchorAt } (nil ok). Returns spellID or nil.
function TI.InferSucceededSpell(mobData, observed, anchors, now, excludeTwoPhase)
    if not (mobData and mobData.spells and observed) then return nil end
    local tol = TI.CAST_TIME_TOLERANCE
    local best, bestScore
    for spellID, spell in pairs(mobData.spells) do
        local first = spell.first
        -- excludeTwoPhase: skip cast→channel spells so a shared-castTime one-phase
        -- twin (e.g. Crowd Dispersal vs Arcane Beam) can be resolved on its own.
        local skip = excludeTwoPhase and (spell.channelTime or 0) > 0
        -- Success-side delta is STRICT (reference: a spell curating
        -- selfBuffCountDeltaOnSuccess is only ever CREDITED with a sampled,
        -- matching delta — an unknown delta rejects it here). Mob narrowing
        -- stays lenient: fingerprintsMatch passes on an unsampled delta, so
        -- FilterCandidates — which runs before the delta is sampled — never
        -- prunes on it.
        if tonumber(spell.selfBuffCountDeltaOnSuccess) ~= nil
            and tonumber(observed.selfBuffCountDelta) == nil then
            skip = true
        end
        if first ~= nil and not skip and TI.SpellMatchesObserved(spell, observed) then
            local dur = (observed.kind == "channel") and spell.channelTime or spell.castTime
            local durationDelta = durationWithin(observed.duration, dur, tol)
                and abs(observed.duration - dur) or nil
            -- castTimeExtra: take the closest alternate if the primary missed.
            if durationDelta == nil and type(spell.castTimeExtra) == "table" then
                for _, alt in ipairs(spell.castTimeExtra) do
                    if durationWithin(observed.duration, alt, tol) then
                        local d = abs(observed.duration - alt)
                        if durationDelta == nil or d < durationDelta then durationDelta = d end
                    end
                end
            end
            if durationDelta ~= nil then
                -- Schedule proximity: score against the spell's PREDICTED NEXT
                -- start (anchor.nextStartAt — the reference's primary term),
                -- falling back to the previous start (anchorAt + first) for an
                -- anchor without a prediction, then to the engage-anchored
                -- first-cast expectation for a never-anchored spell. Scoring
                -- the previous start alone rewarded recency — among duration-
                -- ambiguous spells the one NOT due won ties — and a flat 9999
                -- made a never-seen spell always lose to any anchored twin.
                local expectedDelta = 9999
                local startAt = observed.startAt or now
                local anchor = anchors and anchors[spellID]
                if startAt then
                    if anchor and anchor.nextStartAt then
                        expectedDelta = abs(startAt - anchor.nextStartAt)
                    elseif anchor and anchor.anchorAt then
                        expectedDelta = abs(startAt - (anchor.anchorAt + first))
                    elseif observed.engagedAt then
                        expectedDelta = abs(startAt - (observed.engagedAt + first))
                    end
                end
                local s = durationDelta * 100 + expectedDelta
                if not bestScore or s < bestScore then bestScore = s; best = spellID end
            end
        end
    end
    if best then return best end

    -- Pass 2 — channel fallback. A grab/beam channel's caster CHANNEL_STOP fires
    -- when the cast BAR closes, far short of the gameplay channelTime, so Pass 1's
    -- duration gate wrongly drops it (Plungegrip 0.85s vs 12s; Arcane Beam 0.21s
    -- vs 5s). The true channel duration is unreadable in 12.0 (secret), so identify
    -- a channel by FINGERPRINT ONLY, no duration gate: a unique channel spell wins
    -- outright; multiple channels break the tie by schedule proximity (never by the
    -- untrustworthy measured duration) and only when an anchor already exists —
    -- else stay unresolved and let a later anchored cast decide.
    if observed.kind ~= "channel" then return nil end
    local bestC, bestCScore, count = nil, nil, 0
    for spellID, spell in pairs(mobData.spells) do
        local first = spell.first
        local skip = excludeTwoPhase and (spell.channelTime or 0) > 0
        -- Same strict success-side delta rule as Pass 1.
        if tonumber(spell.selfBuffCountDeltaOnSuccess) ~= nil
            and tonumber(observed.selfBuffCountDelta) == nil then
            skip = true
        end
        if first ~= nil and not skip and (spell.channelTime or 0) > 0
            and channelEvidenceMatches(spell, observed)
            and fingerprintsMatch(spell, observed) then
            count = count + 1
            -- Mirror Pass 1's scoring fix: prefer the PREDICTED NEXT start
            -- (anchor.nextStartAt — the reference's only proximity term),
            -- falling back to the previous start for an anchor without a
            -- prediction. For a success anchor, anchorAt + first measures
            -- time since the PREVIOUS cast — the recency inversion that
            -- rewarded the most recently credited channel over the DUE one
            -- (Shadowrift Voidcaller's two channels).
            local expectedDelta = 9999
            local anchor = anchors and anchors[spellID]
            local startAt = observed.startAt or now
            if anchor and startAt then
                if anchor.nextStartAt then
                    expectedDelta = abs(startAt - anchor.nextStartAt)
                elseif anchor.anchorAt then
                    expectedDelta = abs(startAt - (anchor.anchorAt + first))
                end
            end
            if not bestCScore or expectedDelta < bestCScore then
                bestCScore = expectedDelta; bestC = spellID
            end
        end
    end
    if count == 1 then return bestC end
    if count > 1 and bestCScore and bestCScore < 9999 then return bestC end
    return nil
end

-- ╔══════════════════════════════════════════════════════════╗
-- ║  cd walk — next-cast prediction                          ║
-- ╚══════════════════════════════════════════════════════════╝

-- Next cast for a spell given its last success time and the cd[] index.
-- cd[] is a round-robin sequence (last value effectively repeats via wrap).
-- Returns nextStart, followingSeqIndex, isFuture. nil when unschedulable.
function TI.ComputeNextCast(spellData, lastSucceededAt, seqIndex, now, minLead)
    local cd = spellData and spellData.cd
    if type(cd) ~= "table" or #cd == 0 or lastSucceededAt == nil then return nil end
    local n = #cd
    seqIndex = tonumber(seqIndex) or 1
    if seqIndex < 1 or seqIndex > n then seqIndex = ((seqIndex - 1) % n) + 1 end
    local step = cd[seqIndex]
    if not step then return nil end
    local nextStart = lastSucceededAt + step
    local following = (seqIndex % n) + 1
    local isFuture = (now == nil) or (nextStart > now + (minLead or TI.MIN_LEAD))
    return nextStart, following, isFuture
end

-- Roll a spell's schedule forward to the next FUTURE cast: start at
-- lastEventAt + cd[seqIndex] and, while that occurrence is already past, keep
-- adding the successive cd[] steps (round-robin) until it lands in the future.
-- Lets a missed / CC'd / delayed cast advance to the next cycle instead of the
-- prediction going dark. Returns nextStart, followingSeqIndex, isFuture (isFuture
-- false only when the spell is unschedulable). Bounded so a tiny cd can't spin.
function TI.NextScheduledCast(spellData, lastEventAt, seqIndex, now, minLead)
    local nextStart, following, isFuture = TI.ComputeNextCast(spellData, lastEventAt, seqIndex, now, minLead)
    local guard = 0
    while nextStart and not isFuture and guard < 128 do
        nextStart, following, isFuture = TI.ComputeNextCast(spellData, nextStart, following, now, minLead)
        guard = guard + 1
    end
    return nextStart, following, isFuture
end

-- First-cast prediction from mob ENGAGE, before any cast has been observed: the
-- first occurrence is enterAt + first, later occurrences add cd[] round-robin. If
-- we joined after the first cast was already due, it rolls forward. Returns
-- nextStart, followingSeqIndex, isFuture (nil when unschedulable).
function TI.NextEnterCast(spellData, enterAt, now, minLead)
    local first = spellData and spellData.first
    if type(first) ~= "number" or enterAt == nil then return nil end
    local firstAt = enterAt + first
    if now == nil or firstAt > now + (minLead or TI.MIN_LEAD) then
        return firstAt, 1, true  -- first cast still upcoming; next interval is cd[1]
    end
    return TI.NextScheduledCast(spellData, firstAt, 1, now, minLead)
end

-- ╔══════════════════════════════════════════════════════════╗
-- ║  Schedule signature (dirty-gate for reschedules)         ║
-- ╚══════════════════════════════════════════════════════════╝

-- Cheap stable string; identical inputs → identical signature so an unchanged
-- schedule skips the rebuild. anchors: { [spellID] = {mode,anchorAt,nextSeqIndex} }.
function TI.BuildScheduleSignature(npcID, defaultAnchorAt, activeKind, activeStartAt, configRevision, anchors)
    local parts = {
        "npc=" .. tostring(npcID),
        string.format("base=%.1f", tonumber(defaultAnchorAt) or 0),
        string.format("active=%s@%.1f", tostring(activeKind or "-"), tonumber(activeStartAt) or 0),
        "cfg=" .. tostring(configRevision or 0),
    }
    if type(anchors) == "table" then
        local spellParts = {}
        for spellID, a in pairs(anchors) do
            spellParts[#spellParts + 1] = string.format("%s:%s:%.1f:%s",
                tostring(spellID), tostring(a.mode or "-"),
                tonumber(a.anchorAt) or 0, tostring(a.nextSeqIndex or 1))
        end
        table_sort(spellParts)
        for _, sp in ipairs(spellParts) do parts[#parts + 1] = sp end
    end
    return table.concat(parts, "|")
end

return TI

local loader = require("dev.spec._ke_loader")

local PRESCIENCE = 410089
local SHIFTING_SANDS = 413984

-- A readable aura from the player, as the scan path and the event path see it.
local function aura(over)
    local a = {
        auraInstanceID = 1,
        spellId = PRESCIENCE,
        sourceUnit = "player",
        expirationTime = 2000,
        duration = 30,
        points = { 6 },
    }
    for k, v in pairs(over or {}) do a[k] = v end
    return a
end

local function countTracked(PT)
    local n = 0
    for _ in pairs(PT.trackedBuffs) do n = n + 1 end
    return n
end

-- Advance from a base rather than accumulating: summing 0.1 ten times does not
-- reach exactly 1.0 in floating point, and the interval boundary is the thing
-- under test.
local function tick(PT, rec, count)
    local base = rec.now
    for i = 1, count do
        PT:UpdateTimers()
        rec.now = base + i / 10
    end
end

describe("PrescienceTracker restriction refusals", function()
    it("preserves the tracked list when ScanAllUnits runs while hidden", function()
        local PT = loader.loadPrescienceTracker({ aurasHidden = true })
        PT.trackedBuffs[77] = { unit = "player", spellID = PRESCIENCE }
        PT:ScanAllUnits()
        -- The gate has to sit ABOVE the wipe. Below it, the wipe still runs and
        -- the scan that follows finds nothing, so this count would be 0.
        assert.equals(1, countTracked(PT))
    end)

    it("preserves the preview list too -- there is no preview exemption", function()
        local PT = loader.loadPrescienceTracker({ aurasHidden = true })
        PT.isPreview = true
        PT.trackedBuffs[900001] = { unit = "player", spellID = PRESCIENCE }
        PT:ScanAllUnits()
        assert.equals(1, countTracked(PT))
    end)

    it("DOES wipe and rescan when identities are readable", function()
        local PT = loader.loadPrescienceTracker({ aura = nil })
        PT.trackedBuffs[77] = { unit = "player", spellID = PRESCIENCE }
        PT:ScanAllUnits()
        -- Positive control. Without it every refusal above could pass against an
        -- implementation that simply never scans.
        assert.equals(0, countTracked(PT))
    end)
end)

describe("PrescienceTracker secret payload refusals", function()
    it("does not track an aura whose source unit is secret", function()
        -- The sentinel is "player" ITSELF, declared secret. A different sentinel
        -- would make this vacuous: with the guard deleted, the surviving
        -- comparison against "player" would be false in plain Lua and nothing
        -- would be tracked either way.
        local PT = loader.loadPrescienceTracker({
            aura = aura(),
            secret = { player = true },
        })
        PT:ScanUnit("player")
        assert.equals(0, countTracked(PT))
    end)

    it("tracks an aura from a readable player source", function()
        local PT = loader.loadPrescienceTracker({ aura = aura() })
        PT:ScanUnit("player")
        assert.equals(1, countTracked(PT))
    end)

    it("does not track an aura whose instance id is secret", function()
        local PT = loader.loadPrescienceTracker({
            aura = aura({ auraInstanceID = 4242 }),
            secret = { [4242] = true },
        })
        PT:ScanUnit("player")
        -- The instance id becomes the table key. A secret key either raises or
        -- writes an entry no plain lookup can ever find.
        assert.equals(0, countTracked(PT))
    end)

    it("refuses a secret spell id in the added-aura event path", function()
        local PT = loader.loadPrescienceTracker({ secret = { [PRESCIENCE] = true } })
        PT:OnUnitAura(nil, "player", { addedAuras = { aura() } })
        assert.equals(0, countTracked(PT))
    end)

    it("refuses a secret source unit in the added-aura event path", function()
        -- Dispatched for party1, not player: the payload gate refuses a secret
        -- UNIT token, and "player" is the declared-secret sentinel here, so a
        -- player-dispatched event would be rejected before the loop is reached.
        local PT = loader.loadPrescienceTracker({ secret = { player = true } })
        PT:OnUnitAura(nil, "party1", { addedAuras = { aura() } })
        assert.equals(0, countTracked(PT))
    end)

    it("tracks a readable added aura", function()
        local PT = loader.loadPrescienceTracker({})
        PT:OnUnitAura(nil, "player", { addedAuras = { aura() } })
        -- Positive control for the two refusals above.
        assert.equals(1, countTracked(PT))
    end)
end)

describe("PrescienceTracker rescan throttle", function()
    it("rescans once per interval, not once per tick", function()
        local PT, rec = loader.loadPrescienceTracker({})
        tick(PT, rec, 20)
        -- 2.0s of ticks at 0.1s. The first tick rescans because lastRescan is
        -- seeded one interval in the past; the second falls on the boundary.
        assert.equals(2, rec.rescans)
    end)

    it("rescans on the very first tick whatever the clock reads", function()
        local PT, rec = loader.loadPrescienceTracker({})
        rec.now = 0
        PT:UpdateTimers()
        -- Seeded at 0 instead of -RESCAN_INTERVAL, this would wait a full second
        -- on any client whose uptime clock is still below the interval.
        assert.equals(1, rec.rescans)
    end)

    it("never rescans while identities are hidden", function()
        local PT, rec = loader.loadPrescienceTracker({ aurasHidden = true })
        tick(PT, rec, 20)
        assert.equals(0, rec.rescans)
    end)

    it("asks the restriction question once per interval, not once per tick", function()
        local PT, rec = loader.loadPrescienceTracker({ aurasHidden = true })
        tick(PT, rec, 20)
        -- This case pins the WRITE ORDER. The timestamp is written before the
        -- restriction query, so a hidden stretch still advances the clock.
        -- Written after instead, no hidden tick would ever advance it, every
        -- tick would pass the interval check, and this would be 20 -- the
        -- throttle switched off in the state it exists for. The RESCAN counts
        -- are identical under both orderings and cannot separate them.
        assert.equals(2, rec.hiddenChecks)
    end)

    it("does not rescan at all while something is tracked", function()
        local PT, rec = loader.loadPrescienceTracker({})
        PT.trackedBuffs[77] = { unit = "player", expirationTime = 99999 }
        tick(PT, rec, 20)
        assert.equals(0, rec.rescans)
    end)
end)

describe("PrescienceTracker crit detection", function()
    it("is a crit when points[1] is 6 on Prescience", function()
        local PT = loader.loadPrescienceTracker({ aura = aura() })
        PT:ScanUnit("player")
        assert.is_true(PT.trackedBuffs[1].isCrit)
    end)

    it("is NOT a crit on Shifting Sands with the same points", function()
        local PT = loader.loadPrescienceTracker({})
        PT:AddTrackedBuff("player", aura({ spellId = SHIFTING_SANDS }), SHIFTING_SANDS)
        assert.is_false(PT.trackedBuffs[1].isCrit)
    end)

    it("is NOT a crit when the points table is secret", function()
        local pts = { 6 }
        local PT = loader.loadPrescienceTracker({ secretTables = { [pts] = true } })
        PT:AddTrackedBuff("player", aura({ points = pts }), PRESCIENCE)
        -- IsSecretValue does not answer for a table whose ACCESSES produce
        -- secrets. Only the table predicate does.
        assert.is_false(PT.trackedBuffs[1].isCrit)
    end)

    it("is NOT a crit when the points ELEMENT is secret", function()
        local PT = loader.loadPrescienceTracker({ secret = { [6] = true } })
        PT:AddTrackedBuff("player", aura(), PRESCIENCE)
        -- The table is plain and the element is not. This is the case the old
        -- code got wrong: it guarded the table and then compared the element.
        assert.is_false(PT.trackedBuffs[1].isCrit)
    end)

    it("is NOT a crit when no spell is passed and the aura's own id is secret", function()
        local PT = loader.loadPrescienceTracker({ secret = { [PRESCIENCE] = true } })
        -- No third argument: this is the ONLY case that exercises the helper's
        -- nil fallback to aura.spellId, and the secret guard on it.
        PT:AddTrackedBuff("player", aura(), nil)
        assert.is_false(PT.trackedBuffs[1].isCrit)
    end)
end)

describe("PrescienceTracker restriction-release rescan", function()
    it("debounces two events in the same frame into one rescan", function()
        local PT, rec = loader.loadPrescienceTracker({})
        local scans = 0
        PT.ScanAllUnits = function() scans = scans + 1 end
        PT:QueueRestrictionRescan()
        PT:QueueRestrictionRescan()
        rec.flush()
        assert.equals(1, scans)
    end)

    it("does not rescan when the module is not in the tracking spec", function()
        local PT, rec = loader.loadPrescienceTracker({ isAugSpec = false })
        local scans = 0
        PT.ScanAllUnits = function() scans = scans + 1 end
        PT:QueueRestrictionRescan()
        rec.flush()
        assert.equals(0, scans)
    end)
end)

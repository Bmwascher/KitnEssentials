-- The Warlock class slot's honest Soulstone reporting. The state comes from
-- the cooldown struct and one roster pass: a confirmed stone wins over the
-- cooldown, a running cooldown nobody is seen to carry is unconfirmed, and
-- a secret cooldown pair still says the cooldown runs through isActive. The
-- player is never the sticky recipient, a stone from another caster or a
-- secret caster is not a recipient, a hidden aura gate finds no recipient,
-- the sticky name outlives the stone while its owner stays in the group, the
-- macro carries the sticky and healer terms in order, and the Warlock-in-
-- group answer is cached until the roster changes. The roster is a plain
-- loader seam that only the cache case edits between reads; the sticky case
-- seeds the module's own cache field, never the fake.

local L = require("dev.spec._ke_loader")

local function loadWarlock(mode, units)
    local RCC, _, seams = L.loadReadyCheckConsumables()
    seams.playerClass = "WARLOCK"
    seams.group.mode = mode
    seams.group.units = units
    return RCC, seams
end

local function nameTerms(macrotext)
    local terms = {}
    for name in macrotext:gmatch("%[@([^,%]]+),help,nodead%]") do
        terms[#terms + 1] = name
    end
    return terms
end

describe("ReadyCheckConsumables Soulstone state", function()
    it("derives the state from the cooldown struct and the confirmation", function()
        local RCC, _, seams = L.loadReadyCheckConsumables({ GetTime = function() return 1000 end })
        local SECRET = seams.SECRET
        local readable = { startTime = 700, duration = 600, isActive = true }
        local secret   = { startTime = SECRET, duration = SECRET, isActive = true }
        local idle     = { startTime = 0, duration = 0, isActive = false }
        local secretIdle = { startTime = SECRET, duration = SECRET, isActive = false }
        local gcd      = { startTime = 999, duration = 1.5, isActive = true }
        local cases = {
            { cd = readable,   confirmed = true,  state = "protected",   remain = 300 },
            { cd = readable,   confirmed = false, state = "unconfirmed", remain = 300 },
            { cd = idle,       confirmed = false, state = "cast",        remain = nil },
            { cd = idle,       confirmed = true,  state = "protected",   remain = nil },
            { cd = secret,     confirmed = false, state = "unconfirmed", remain = nil },
            { cd = secret,     confirmed = true,  state = "protected",   remain = nil },
            { cd = secretIdle, confirmed = false, state = "cast",        remain = nil },
            { cd = gcd,        confirmed = false, state = "cast",        remain = nil },
            { cd = nil,        confirmed = false, state = "cast",        remain = nil },
        }
        for i, c in ipairs(cases) do
            local state, remain = RCC._SoulstoneState(c.cd, c.confirmed)
            assert.equals(c.state, state, "case " .. i)
            assert.equals(c.remain, remain, "case " .. i)
        end
    end)
end)

describe("ReadyCheckConsumables Soulstone roster pass", function()
    it("never makes the player the sticky recipient, and reports the self-stone for the paint", function()
        local RCC = loadWarlock("raid", {
            raid1 = { name = "Me-Realm", isPlayer = true, stone = "player" },
            raid2 = { name = "Healer-Realm", role = "HEALER" },
        })
        local confirmed, macrotext = RCC:_ResolveSoulstone()
        assert.is_true(confirmed)
        assert.is_nil(RCC._lastSoulstoneTarget)
        assert.same({ "mouseover", "target", "Healer-Realm" }, nameTerms(macrotext))
    end)

    it("confirms and makes sticky a living member carrying the player's stone", function()
        local RCC = loadWarlock("raid", {
            raid1 = { name = "Me-Realm", isPlayer = true },
            raid2 = { name = "Healer-Realm", role = "HEALER" },
            raid3 = { name = "Stoned-Realm", stone = "player" },
        })
        local confirmed, macrotext = RCC:_ResolveSoulstone()
        assert.is_true(confirmed)
        assert.equals("Stoned-Realm", RCC._lastSoulstoneTarget)
        assert.same({ "mouseover", "target", "Stoned-Realm", "Healer-Realm" }, nameTerms(macrotext))
    end)

    it("does not confirm a stone from another caster, a secret caster, or a dead carrier", function()
        local cases = {
            { stone = "raid4" },
            { stone = "SECRET" },
            { stone = "player", dead = true },
        }
        for i, c in ipairs(cases) do
            local RCC, seams = loadWarlock("raid", {
                raid1 = { name = "Me-Realm", isPlayer = true },
                raid2 = { name = "Carrier-Realm", stone = c.stone, dead = c.dead },
            })
            if c.stone == "SECRET" then seams.group.units.raid2.stone = seams.SECRET end
            local confirmed = RCC:_ResolveSoulstone()
            assert.is_false(confirmed, "case " .. i)
            assert.is_nil(RCC._lastSoulstoneTarget, "case " .. i)
        end
    end)

    it("finds no recipient while the per-spell gate hides the aura, and still names the healer", function()
        local RCC, seams = loadWarlock("party", {
            party1 = { name = "Healer-Realm", role = "HEALER", stone = "player" },
        })
        seams.soulstoneHidden = true
        local confirmed, macrotext = RCC:_ResolveSoulstone()
        assert.is_false(confirmed)
        assert.is_nil(RCC._lastSoulstoneTarget)
        assert.same({ "mouseover", "target", "Healer-Realm" }, nameTerms(macrotext))
    end)

    it("keeps the sticky name while its owner is in the group and drops it once they leave", function()
        local RCC = loadWarlock("party", {
            party1 = { name = "Healer-Realm", role = "HEALER" },
            party2 = { name = "Sticky-Realm" },
        })
        RCC._lastSoulstoneTarget = "Sticky-Realm"
        local confirmed, macrotext = RCC:_ResolveSoulstone()
        assert.is_false(confirmed)
        assert.equals("Sticky-Realm", RCC._lastSoulstoneTarget)
        assert.same({ "mouseover", "target", "Sticky-Realm", "Healer-Realm" }, nameTerms(macrotext))

        RCC._lastSoulstoneTarget = "Gone-Realm"
        macrotext = select(2, RCC:_ResolveSoulstone())
        assert.is_nil(RCC._lastSoulstoneTarget)
        assert.same({ "mouseover", "target", "Healer-Realm" }, nameTerms(macrotext))
    end)

    it("emits one term when the healer is the sticky name", function()
        local RCC = loadWarlock("party", {
            party1 = { name = "Healer-Realm", role = "HEALER", stone = "player" },
        })
        local _, macrotext = RCC:_ResolveSoulstone()
        assert.same({ "mouseover", "target", "Healer-Realm" }, nameTerms(macrotext))
    end)
end)

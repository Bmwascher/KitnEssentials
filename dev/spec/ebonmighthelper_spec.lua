local loader = require("dev.spec._ke_loader")

-- Eruption, read from the module's own extender list. A spell the module does
-- not recognise returns at IsExtender before any decision is reached, which
-- would make every case below pass for the wrong reason.
local EXTENDER = 395160
local EBON_MIGHT_CAST = 395152

local function secretPredicate(isSecret)
    return { ShouldSpellAuraBeSecret = function() return isSecret end }
end

describe("EbonMightHelper aura readability", function()
    it("does not warn when a stale stored zero is contradicted by a live aura", function()
        local EM, rec = loader.loadEbonMightHelper({
            C_Secrets = secretPredicate(false),
            aura = { expirationTime = 9999 },
        })
        EM.expirationTime = 0
        EM:OnEvent("UNIT_SPELLCAST_START", "player", nil, EXTENDER)
        assert.equals(0, rec.warnings)
    end)

    it("does not warn when the per-spell flag hides the aura", function()
        local EM, rec = loader.loadEbonMightHelper({
            C_Secrets = secretPredicate(true),
            aura = nil,
        })
        EM.expirationTime = 0
        EM:OnEvent("UNIT_SPELLCAST_START", "player", nil, EXTENDER)
        assert.equals(0, rec.warnings)
    end)

    it("trusts the exact predicate over the broad state when they disagree", function()
        -- The whole point of Task 3a's ordering. The spell says readable, the
        -- broad state says hidden, and the spell wins -- so the live aura is
        -- read and no warning fires. A broad-first implementation passes every
        -- other case in this file and fails only this one.
        local EM, rec = loader.loadEbonMightHelper({
            C_Secrets = secretPredicate(false),
            aurasHidden = true,
            aura = { expirationTime = 9999 },
        })
        EM.expirationTime = 0
        EM:OnEvent("UNIT_SPELLCAST_START", "player", nil, EXTENDER)
        -- The warning count alone CANNOT distinguish the two implementations:
        -- broad-first also declines to warn, it just declines for the wrong
        -- reason. The stored expiration is the observable that separates them.
        -- Correct code reads the live aura and assigns 9999; broad-first
        -- returns nil before the assignment and leaves the seeded 0.
        assert.equals(0, rec.warnings)
        assert.equals(9999, EM.expirationTime)
    end)

    it("does not warn when the broad state hides the aura and the exact API is absent", function()
        local EM, rec = loader.loadEbonMightHelper({
            C_Secrets = nil,
            aurasHidden = true,
            aura = nil,
        })
        EM.expirationTime = 0
        EM:OnEvent("UNIT_SPELLCAST_START", "player", nil, EXTENDER)
        assert.equals(0, rec.warnings)
    end)

    it("DOES warn when the aura is readable and genuinely absent", function()
        local EM, rec = loader.loadEbonMightHelper({
            C_Secrets = secretPredicate(false),
            aura = nil,
        })
        EM.expirationTime = 0
        EM:OnEvent("UNIT_SPELLCAST_START", "player", nil, EXTENDER)
        assert.equals(1, rec.warnings)
    end)
end)

describe("EbonMightHelper spellcast refusals", function()
    -- The token is "player" DECLARED secret. An unguarded branch compares it,
    -- finds it equal, and proceeds -- so a passing assertion here can only be
    -- produced by the guard, never by the early return.
    it("refuses a secret unit on the cast-start branch", function()
        local EM, rec = loader.loadEbonMightHelper({
            C_Secrets = secretPredicate(false),
            aura = nil,
            secret = { player = true },
        })
        EM.expirationTime = 0
        EM:OnEvent("UNIT_SPELLCAST_START", "player", nil, EXTENDER)
        assert.equals(0, rec.warnings)
    end)

    it("refuses a secret unit on the empower-start branch", function()
        local EM, rec = loader.loadEbonMightHelper({
            C_Secrets = secretPredicate(false),
            aura = nil,
            secret = { player = true },
        })
        EM.expirationTime = 0
        EM:OnEvent("UNIT_SPELLCAST_EMPOWER_START", "player", nil, EXTENDER)
        assert.equals(0, rec.warnings)
    end)

    it("refuses a secret unit on the succeeded branch", function()
        local EM = loader.loadEbonMightHelper({
            C_Secrets = secretPredicate(false),
            secret = { player = true },
        })
        EM.lastEbonMightCast = nil
        EM:OnEvent("UNIT_SPELLCAST_SUCCEEDED", "player", nil, EBON_MIGHT_CAST)
        assert.is_nil(EM.lastEbonMightCast)
    end)

    it("refuses a secret spell id on the cast-start branch", function()
        local EM, rec = loader.loadEbonMightHelper({
            C_Secrets = secretPredicate(false),
            aura = nil,
            secret = { [EXTENDER] = true },
        })
        EM.expirationTime = 0
        EM:OnEvent("UNIT_SPELLCAST_START", "player", nil, EXTENDER)
        assert.equals(0, rec.warnings)
    end)

    it("refuses a secret spell id on the succeeded branch", function()
        local EM = loader.loadEbonMightHelper({
            C_Secrets = secretPredicate(false),
            secret = { [EBON_MIGHT_CAST] = true },
        })
        EM.lastEbonMightCast = nil
        EM:OnEvent("UNIT_SPELLCAST_SUCCEEDED", "player", nil, EBON_MIGHT_CAST)
        assert.is_nil(EM.lastEbonMightCast)
    end)
end)

describe("EbonMightHelper timing-check spell id", function()
    it("refuses a secret casting id", function()
        local EM, rec = loader.loadEbonMightHelper({
            C_Secrets = secretPredicate(false),
            aura = nil,
            secret = { [EXTENDER] = true },
            UnitCastingInfo = function() return nil, nil, nil, nil, nil, nil, nil, nil, EXTENDER end,
        })
        EM.expirationTime = 0
        EM:OnTimingCheck(0, 0, 1)
        assert.equals(0, rec.warnings)
    end)

    it("refuses a secret channel id when casting is absent", function()
        local EM, rec = loader.loadEbonMightHelper({
            C_Secrets = secretPredicate(false),
            aura = nil,
            secret = { [EXTENDER] = true },
            UnitCastingInfo = function() return nil end,
            UnitChannelInfo = function() return nil, nil, nil, nil, nil, nil, nil, EXTENDER end,
        })
        EM.expirationTime = 0
        EM:OnTimingCheck(0, 0, 1)
        assert.equals(0, rec.warnings)
    end)

    it("processes a readable channel extender when casting is absent", function()
        local EM, rec = loader.loadEbonMightHelper({
            C_Secrets = secretPredicate(false),
            aura = nil,
            UnitCastingInfo = function() return nil end,
            UnitChannelInfo = function() return nil, nil, nil, nil, nil, nil, nil, EXTENDER end,
        })
        EM.expirationTime = 0
        EM:OnTimingCheck(0, 0, 1)
        assert.equals(1, rec.warnings)
    end)

    it("takes the casting id in preference to the channel id", function()
        local EM, rec = loader.loadEbonMightHelper({
            C_Secrets = secretPredicate(false),
            aura = nil,
            secret = { [777] = true },
            UnitCastingInfo = function() return nil, nil, nil, nil, nil, nil, nil, nil, EXTENDER end,
            UnitChannelInfo = function() return nil, nil, nil, nil, nil, nil, nil, 777 end,
        })
        EM.expirationTime = 0
        EM:OnTimingCheck(0, 0, 1)
        -- The channel id is declared secret. If the channel branch were reached
        -- at all, the refusal would fire and no warning would be recorded, so
        -- the warning is proof the casting id won.
        assert.equals(1, rec.warnings)
    end)

    it("returns quietly when neither a casting nor a channel id is present", function()
        local EM, rec = loader.loadEbonMightHelper({
            C_Secrets = secretPredicate(false),
            aura = nil,
        })
        EM.expirationTime = 0
        EM:OnTimingCheck(0, 0, 1)
        assert.equals(0, rec.warnings)
    end)
end)

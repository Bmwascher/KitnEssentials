-- Tier 2: logic around the 12.0 secret/restriction API. Core/Secret.lua.
-- We drive the restriction state machine through real event transitions, which
-- in-game would require entering combat/M+/encounter to exercise. See the
-- HONESTY BOUNDARY block for what a mock can and cannot vouch for.
local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

describe("Secret.lua restriction state machine", function()
    local KE, frames
    before_each(function()
        frames = mock.install()
        KE = helpers.loadModule("Core/Secret.lua", { Print = function() end })
    end)

    it("starts unrestricted", function()
        assert.equals(0, KE:GetRestrictionState())
        assert.is_false(KE:IsFullyRestricted())
    end)

    it("enters FULL restriction on combat start", function()
        frames[1]:Fire("PLAYER_REGEN_DISABLED")
        assert.is_true(KE:IsFullyRestricted())
        assert.equals(2, KE:GetRestrictionState())
    end)

    it("clears restriction on combat end", function()
        frames[1]:Fire("PLAYER_REGEN_DISABLED")
        frames[1]:Fire("PLAYER_REGEN_ENABLED")
        assert.equals(0, KE:GetRestrictionState())
    end)

    it("defers a callback during combat and flushes it when combat ends", function()
        frames[1]:Fire("PLAYER_REGEN_DISABLED")
        local ran = false
        KE:DeferUntilUnrestricted(0, function() ran = true end)
        assert.is_false(ran) -- queued while restricted
        frames[1]:Fire("PLAYER_REGEN_ENABLED")
        assert.is_true(ran) -- queue flushed on release
    end)

    it("runs a deferred callback immediately when already unrestricted", function()
        local ran = false
        KE:DeferUntilUnrestricted(0, function() ran = true end)
        assert.is_true(ran)
    end)

    it("treats ADDON_RESTRICTION_STATE_CHANGED(Map) as partial restriction", function()
        frames[1]:Fire("ADDON_RESTRICTION_STATE_CHANGED", "Map", true)
        assert.equals(1, KE:GetRestrictionState())
        assert.is_true(KE:IsRestricted())
        assert.is_false(KE:IsFullyRestricted())
    end)
end)

describe("Secret.lua value guards — the HONESTY BOUNDARY", function()
    -- A mock guard test verifies KE's BRANCHING given a value WE declare secret,
    -- not real 12.0 secret semantics. Keep that distinction in mind: the result
    -- is only as true as the mock's fidelity.
    it("rejects a unit name only when the client marks it secret", function()
        mock.install({
            issecretvalue = function(v) return v == "SECRET_NAME" end,
            UnitName = function() return "SECRET_NAME" end,
        })
        local KE = helpers.loadModule("Core/Secret.lua", { Print = function() end })
        assert.is_nil(KE:GetSafeUnitName("target")) -- guard fires

        mock.install({ UnitName = function() return "Realname" end })
        KE = helpers.loadModule("Core/Secret.lua", { Print = function() end })
        assert.equals("Realname", KE:GetSafeUnitName("target")) -- passes through
    end)

    it("IsSafeValue rejects nil and secret, accepts plain values", function()
        local SECRET = {}
        mock.install({ issecretvalue = function(v) return v == SECRET end })
        local KE = helpers.loadModule("Core/Secret.lua", { Print = function() end })
        assert.is_false(KE:IsSafeValue(nil))
        assert.is_false(KE:IsSafeValue(SECRET))
        assert.is_true(KE:IsSafeValue("plain"))
        assert.is_true(KE:IsSafeValue(42))
    end)
end)

-- Tier 1: a refusal rule. KE:CanReanchorNow decides whether the anchor-repair
-- pass and Edit Mode may move a frame, and every wrong answer is silent --
-- refusing too much strands a frame on the wrong anchor, permitting too much
-- moves a frame the game had locked. The combat branch is the half that is
-- easy to break by accident: the gates only apply during lockdown, and a later
-- edit that drops that early return would refuse every frame out of combat.
local L = require("dev.spec._ke_loader")

describe("KE:CanReanchorNow", function()
    local KE
    local inCombat = false
    local SECRET = {}

    setup(function()
        KE = L.loadGlobals({
            InCombatLockdown = function() return inCombat end,
            issecretvalue = function(value) return value == SECRET end,
        })
    end)

    before_each(function() inCombat = false end)

    -- protected / restricted default to the permissive answer so each case
    -- names only the field it is about.
    local function frame(fields)
        fields = fields or {}
        local f = {
            IsProtected = function() return fields.protected or false end,
        }
        if not fields.noAnchoringMethod then
            f.IsAnchoringRestricted = function()
                return fields.restricted or false
            end
        end
        return f
    end

    it("permits out of combat whatever the frame reports", function()
        assert.is_true(KE:CanReanchorNow(frame({
            protected = true, restricted = true,
        })))
    end)

    it("permits in combat when both gates say no", function()
        inCombat = true
        assert.is_true(KE:CanReanchorNow(frame()))
    end)

    it("refuses a protected frame in combat", function()
        inCombat = true
        assert.is_false(KE:CanReanchorNow(frame({ protected = true })))
    end)

    it("refuses an anchoring-restricted frame in combat", function()
        inCombat = true
        assert.is_false(KE:CanReanchorNow(frame({ restricted = true })))
    end)

    it("refuses in combat when the anchoring gate is missing", function()
        inCombat = true
        assert.is_false(KE:CanReanchorNow(frame({ noAnchoringMethod = true })))
    end)
end)

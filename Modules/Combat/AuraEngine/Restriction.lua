-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/Combat/AuraEngine/Restriction.lua               ║
-- ║  Purpose: the deferral gate. One correct implementation  ║
-- ║  of "may I reconfigure now, and what do I owe later".    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local Restriction = {}
KE.AuraRestriction = Restriction

local Gate = {}
Gate.__index = Gate

-- The predicate is injected so the state machine can be tested without
-- standing up C_Secrets and C_RestrictedActions. Production passes the same
-- helper every other module in this programme uses.
function Restriction.New(opts)
    opts = opts or {}
    return setmetatable({
        isHidden = opts.isHidden or function()
            return KE.AreAuraIdentitiesHidden and KE:AreAuraIdentitiesHidden() or false
        end,
        -- A FUNCTION, never a captured value: the registry's answer changes
        -- under the gate, and a value read at construction would be the stale
        -- copy this design exists to avoid. Absent for a display with no
        -- sounds.
        soundIsPending = opts.soundIsPending,
        pending  = {},
    }, Gate)
end

-- Returns true when the caller may act immediately. A false answer means the
-- debt is recorded and the drain will re-run the work from CURRENT settings —
-- the flag records only THAT work is owed, never what the work was.
function Gate:Request(kind)
    if self.isHidden() then
        self.pending[kind] = true
        return false
    end

    -- DISCHARGE an older debt. A settings change that lands after the
    -- restriction lifts but before the drain fires does the owed work right
    -- here; leaving the flag set would make the drain repeat it, which breaks
    -- the exactly-once rule in the least visible way possible.
    --
    -- This makes a demand of the CALLER: a true answer means the work happens
    -- NOW, in the same call, with no branch between here and it. A caller that
    -- took a true answer and then decided not to act would drop the debt
    -- silently, and this file cannot see that happen.
    self.pending[kind] = nil
    return true
end

-- The SOUND debt is not stored here. The sound registry already carries its
-- own pending state, its own restriction check and its own retire-first rule,
-- and a second copy of that flag in the gate is a copy that can disagree —
-- a restricted first sync would set one flag while the drain read the other.
-- The gate reads the registry instead, so there is exactly one place the
-- answer can be wrong. A display with no sounds passes no reader.
function Gate:IsPending(kind)
    if kind == "sound" then
        return self.soundIsPending ~= nil and self.soundIsPending() == true
    end
    return self.pending[kind] == true
end

-- Disable calls this. Clearing the general flag is what stops a later
-- restriction release resurrecting work for a module the user switched off.
-- The sound half of a disable is a retirement, not a flag clear: disable
-- retires every id, which is what makes the registry report no debt.
function Gate:Cancel()
    self.pending = {}
end

-- Each owed handler runs at most once per drain, and only once the
-- restriction has actually lifted. Clearing before the call means a handler
-- that re-requests can legitimately set the flag again.
--
-- Two kinds can resolve to the SAME function, because reapplying settings
-- synchronises the sound on its way past. Collapsing identical handlers is
-- what keeps the design's "synchronised exactly once when both drain
-- together" rule true without the caller having to know it.
function Gate:Drain(handlers)
    if self.isHidden() then return end
    handlers = handlers or {}

    local owed, order = {}, {}
    for _, kind in ipairs({ "general", "sound" }) do
        if self:IsPending(kind) then
            self.pending[kind] = nil
            local fn = handlers[kind]
            if fn and not owed[fn] then
                owed[fn] = true
                order[#order + 1] = fn
            end
        end
    end

    for i = 1, #order do order[i]() end
end

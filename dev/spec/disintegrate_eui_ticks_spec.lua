-- Tier: one invented refusal rule, the decision that governs whether this
-- module writes into another addon's saved settings and whether it may hand
-- them back. It fails silently when broken -- a wrong branch either strands a
-- setting turned off with no path back, or hands back one this module never
-- took -- and neither shows up in a lint or a diff.
--
-- The resolver is the whole spec budget. Everything around it is integration,
-- and the plan for this branch states what the in-game steps actually reach
-- and what they do not: the retry and the refresh call in particular are not
-- proven by them. Do not read this file as covering more than the resolver.

local loader = require("dev.spec._ke_loader")
local mock = require("dev.spec._wow_mock")

describe("DisintegrateTicks EllesmereUI tick-marker resolver", function()
    local DT

    before_each(function()
        DT = loader.loadDisintegrateTicks()
    end)

    after_each(function()
        mock.reset()
    end)

    -- want, current, owned -> action. One row per branch; rows differing only
    -- in a literal are folded into one case.
    local cases = {
        {
            name = "unreachable settings write nothing and keep the record",
            want = false, current = nil, owned = true, expected = "none",
            why = "the only triple where dropping the nil guard changes the "
                .. "answer: without it this falls through to restore, the one "
                .. "action that writes true and clears the record",
        },
        {
            name = "wanted and unowned with the markers on takes them",
            want = true, current = true, owned = false, expected = "hide",
        },
        {
            name = "wanted and unowned with the markers already off takes nothing",
            want = true, current = false, owned = false, expected = "none",
            why = "the user keeps them off; there is no ownership to claim",
        },
        {
            name = "wanted and owned with the markers off is the steady state",
            want = true, current = false, owned = true, expected = "none",
        },
        {
            name = "wanted and owned with the markers back on stands down",
            want = true, current = true, owned = true, expected = "standdown",
            why = "the user re-enabled them; stop owning rather than fight back",
        },
        {
            name = "unwanted and owned with the markers off restores them",
            want = false, current = false, owned = true, expected = "restore",
        },
        {
            name = "unwanted and owned with the markers already on releases",
            want = false, current = true, owned = true, expected = "release",
            why = "nothing to write, but the stale record has to go",
        },
    }

    for _, case in ipairs(cases) do
        it(case.name, function()
            assert.equals(case.expected,
                DT.ResolveEUITickMarkers(case.want, case.current, case.owned))
        end)
    end

    it("never acts on a profile it holds no record for", function()
        -- Both values of current, because the pair is what proves the branch
        -- turns on ownership rather than on the setting's state.
        assert.equals("none", DT.ResolveEUITickMarkers(false, true, false))
        assert.equals("none", DT.ResolveEUITickMarkers(false, false, false))
    end)
end)

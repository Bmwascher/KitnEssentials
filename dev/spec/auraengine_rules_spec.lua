local L = require("dev.spec._ke_loader")

describe("Advanced Debuffs filter-string construction", function()
    it("negates every ordinary enabled filter", function()
        local R = L.loadAuraRules()
        local s = R.BuildDebuffFilter({ PLAYER = true, RAID = true })
        assert.truthy(s:find("!PLAYER", 1, true))
        assert.truthy(s:find("!RAID", 1, true))
    end)

    it("starts from HARMFUL", function()
        local R = L.loadAuraRules()
        assert.equals("HARMFUL", R.BuildDebuffFilter({}):sub(1, 7))
    end)

    -- The whole point of this file. INCLUDE_NAME_PLATE_ONLY is documented
    -- non-negatable and inverted relative to its neighbours: its ABSENCE
    -- filters nameplate-only auras out. A spec that only checked "every
    -- enabled filter is negated" would certify the bug.
    it("OMITS the nameplate token when its checkbox is enabled", function()
        local R = L.loadAuraRules()
        local s = R.BuildDebuffFilter({ INCLUDE_NAME_PLATE_ONLY = true })
        assert.is_nil(s:find("INCLUDE_NAME_PLATE_ONLY", 1, true))
    end)

    it("appends the nameplate token POSITIVELY when its checkbox is disabled", function()
        local R = L.loadAuraRules()
        local s = R.BuildDebuffFilter({ INCLUDE_NAME_PLATE_ONLY = false })
        assert.truthy(s:find("|INCLUDE_NAME_PLATE_ONLY", 1, true))
        assert.is_nil(s:find("!INCLUDE_NAME_PLATE_ONLY", 1, true))
    end)

    it("appends the nameplate token when the key is absent entirely", function()
        local R = L.loadAuraRules()
        assert.truthy(R.BuildDebuffFilter({}):find("|INCLUDE_NAME_PLATE_ONLY", 1, true))
    end)

    it("emits tokens in a stable order regardless of table iteration", function()
        local R = L.loadAuraRules()
        local a = R.BuildDebuffFilter({ PLAYER = true, RAID = true, CROWD_CONTROL = true })
        local b = R.BuildDebuffFilter({ CROWD_CONTROL = true, RAID = true, PLAYER = true })
        assert.equals(a, b)
    end)
end)

describe("blocklist record conversion", function()
    it("includes an enabled user entry", function()
        local R = L.loadAuraRules()
        local set = R.BuildExcludeSpellIDs({ [12345] = { label = "X", enabled = true } })
        assert.is_true(set[12345])
    end)

    it("EXCLUDES an entry the user switched off", function()
        local R = L.loadAuraRules()
        local set = R.BuildExcludeSpellIDs({ [12345] = { label = "X", enabled = false } })
        assert.is_nil(set[12345])
    end)

    it("keeps a hardcoded id even when the user disabled its row", function()
        -- 80354 Time Warp ships as a default row AND is one of the nine, so a
        -- user can switch it off and it must still filter.
        local R = L.loadAuraRules()
        local set = R.BuildExcludeSpellIDs({ [80354] = { label = "TW", enabled = false, default = true } })
        assert.is_true(set[80354])
    end)

    it("contains all nine hardcoded ids given an empty saved table", function()
        local R = L.loadAuraRules()
        local set = R.BuildExcludeSpellIDs({})
        for _, id in ipairs(R.HARDCODED_BLOCKLIST) do
            assert.is_true(set[id])
        end
    end)

    it("tolerates a nil saved table", function()
        local R = L.loadAuraRules()
        assert.is_true(R.BuildExcludeSpellIDs(nil)[57723])
    end)

    -- The alias is the ported behaviour, and it is what makes the
    -- do-not-mutate invariant necessary. A spec that only checked CONTENTS
    -- would pass just as happily against a defensive copy, which is the
    -- deviation the design forbids.
    it("returns the shared constant set BY REFERENCE when the user has no entries", function()
        local R = L.loadAuraRules()
        assert.is_true(R.BuildExcludeSpellIDs(nil) == R.HARDCODED_BLOCKLIST_SET)
        assert.is_true(R.BuildExcludeSpellIDs({}) == R.HARDCODED_BLOCKLIST_SET)
    end)

    it("merges into a NEW set when the user has entries, leaving the constant untouched", function()
        local R = L.loadAuraRules()
        local set = R.BuildExcludeSpellIDs({ [12345] = { enabled = true } })
        assert.is_false(set == R.HARDCODED_BLOCKLIST_SET)
        assert.is_nil(R.HARDCODED_BLOCKLIST_SET[12345])
    end)
end)

describe("Externals icon limit split", function()
    it("gives the whole limit to externals when big defensives are off", function()
        local R = L.loadAuraRules()
        assert.same({ external = 6, big = 0 }, R.SplitExternalsLimit(6, false))
    end)

    it("halves an even limit", function()
        local R = L.loadAuraRules()
        assert.same({ external = 3, big = 3 }, R.SplitExternalsLimit(6, true))
    end)

    it("gives the remainder to externals on an odd limit", function()
        local R = L.loadAuraRules()
        assert.same({ external = 3, big = 2 }, R.SplitExternalsLimit(5, true))
    end)

    it("gives a single slot to externals, not to big defensives", function()
        local R = L.loadAuraRules()
        assert.same({ external = 1, big = 0 }, R.SplitExternalsLimit(1, true))
    end)

    -- The eager-add rule depends on this: every declared key gets a count,
    -- including zero, because the group is added either way.
    it("returns a count for the big key even when it is zero", function()
        local R = L.loadAuraRules()
        assert.equals(0, R.SplitExternalsLimit(4, false).big)
    end)
end)

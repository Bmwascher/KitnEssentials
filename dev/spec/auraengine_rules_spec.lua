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

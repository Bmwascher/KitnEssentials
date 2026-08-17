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

describe("preview timing", function()
    -- One rule for both displays, taken whole from Advanced Debuffs because
    -- its 10-35s range exercises wider duration text than the 6-15s one.
    it("produces the documented duration for the first index", function()
        local R = L.loadAuraRules()
        local duration = R.PreviewTiming(1)
        assert.equals(10 + ((1 * 5) % 30), duration)
    end)

    it("varies the phase across indices so icons are not synchronised", function()
        local R = L.loadAuraRules()
        local _, offsetA = R.PreviewTiming(1)
        local _, offsetB = R.PreviewTiming(2)
        assert.not_equals(offsetA, offsetB)
    end)

    it("keeps every phase offset inside one full duration", function()
        local R = L.loadAuraRules()
        for i = 1, 12 do
            local duration, offset = R.PreviewTiming(i)
            assert.is_true(offset >= 0)
            assert.is_true(offset < duration)
        end
    end)
end)

describe("Externals preview shaping", function()
    local ICONS     = { 1, 2, 3 }
    local ICONS_BIG = { 7, 8, 9 }

    it("yields only external entries when big defensives are off", function()
        local R = L.loadAuraRules()
        local entries = R.BuildExternalsPreview(ICONS, ICONS_BIG, 6, false)
        assert.equals(6, #entries)
        for _, e in ipairs(entries) do
            assert.equals("external", e.groupKey)
        end
    end)

    -- Blocked, not alternating. The container lays groups out as ordered
    -- blocks, so an alternating preview would advertise an interleaving the
    -- live display cannot produce.
    it("yields one external block then one big block when enabled", function()
        local R = L.loadAuraRules()
        local entries = R.BuildExternalsPreview(ICONS, ICONS_BIG, 6, true)
        local keys = {}
        for i, e in ipairs(entries) do keys[i] = e.groupKey end
        assert.same({ "external", "external", "external", "big", "big", "big" }, keys)
    end)

    it("sizes the blocks by the same split the live layout uses", function()
        local R = L.loadAuraRules()
        local entries = R.BuildExternalsPreview(ICONS, ICONS_BIG, 5, true)
        local counts = { external = 0, big = 0 }
        for _, e in ipairs(entries) do counts[e.groupKey] = counts[e.groupKey] + 1 end
        assert.same({ external = 3, big = 2 }, counts)
    end)

    it("emits no big entries when the split gives that group zero", function()
        local R = L.loadAuraRules()
        local entries = R.BuildExternalsPreview(ICONS, ICONS_BIG, 1, true)
        assert.equals(1, #entries)
        assert.equals("external", entries[1].groupKey)
    end)

    it("cycles its icon source rather than running out", function()
        local R = L.loadAuraRules()
        local entries = R.BuildExternalsPreview(ICONS, ICONS_BIG, 5, false)
        assert.equals(ICONS[1], entries[1].icon)
        assert.equals(ICONS[1], entries[4].icon)
    end)

    -- The big block starts at its OWN first icon, not at an offset left over
    -- from the external quota.
    it("starts the big block at the first big icon regardless of the split", function()
        local R = L.loadAuraRules()
        local entries = R.BuildExternalsPreview(ICONS, ICONS_BIG, 6, true)
        assert.equals(ICONS_BIG[1], entries[4].icon)
        assert.equals(ICONS_BIG[2], entries[5].icon)
    end)
end)

local L = require("dev.spec._ke_loader")

describe("Advanced Debuffs filter-string construction", function()
    it("ignores the legacy PLAYER setting while negating optional filters", function()
        local R = L.loadAuraRules()
        local s = R.BuildDebuffFilter({ PLAYER = true, RAID = true })
        assert.is_nil(s:find("PLAYER", 1, true))
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

    -- The literal, and every negatable filter at once. Building the same key
    -- set twice in different source order proves nothing: Lua 5.1 orders a
    -- given set by the key hashes, not by insertion, so an implementation that
    -- iterated the filters unordered would emit the same string both times and
    -- agree with itself. Restating an implementation's output is normally the
    -- assertion this project rejects -- here the fixed order IS the specified
    -- behaviour, so pinning it is the point.
    it("emits tokens in a stable order regardless of table iteration", function()
        local R = L.loadAuraRules()
        assert.equals(
            "HARMFUL|!RAID|!CROWD_CONTROL|!IMPORTANT|!RAID_PLAYER_DISPELLABLE|INCLUDE_NAME_PLATE_ONLY",
            R.BuildDebuffFilter({
                PLAYER                  = true,
                RAID                    = true,
                CROWD_CONTROL           = true,
                IMPORTANT               = true,
                RAID_PLAYER_DISPELLABLE = true,
            })
        )
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
        -- 80354 Time Warp ships as a default row AND is hardcoded, so a
        -- user can switch it off and it must still filter.
        local R = L.loadAuraRules()
        local set = R.BuildExcludeSpellIDs({ [80354] = { label = "TW", enabled = false, default = true } })
        assert.is_true(set[80354])
    end)

    it("contains every hardcoded id given an empty saved table", function()
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
        -- An independent literal, not the formula restated. Repeating the
        -- expression here would let a transcribed constant satisfy its own
        -- test.
        assert.equals(15, duration)
    end)

    -- A pair that SHARES a duration, which is the only case the phase term
    -- exists for. Durations repeat across the index range, and two icons on
    -- the same duration would otherwise open in lockstep. Any other pair
    -- carries differing durations, so their offsets differ on their own and
    -- the assertion holds with no phase term at all.
    it("varies the phase across indices so icons are not synchronised", function()
        local R = L.loadAuraRules()
        local durationA, offsetA = R.PreviewTiming(1)
        local durationB, offsetB = R.PreviewTiming(7)
        assert.equals(durationA, durationB)
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

describe("display state folding", function()
    it("suspends the container in a vehicle but never the sound", function()
        local R = L.loadAuraRules()
        assert.same({ container = false, sound = true }, R.ComputeState(true, true))
    end)

    it("suspends both when the module is switched off", function()
        local R = L.loadAuraRules()
        assert.same({ container = false, sound = false }, R.ComputeState(false, false))
        assert.same({ container = false, sound = false }, R.ComputeState(false, true))
    end)

    it("runs both when nothing suspends either", function()
        local R = L.loadAuraRules()
        assert.same({ container = true, sound = true }, R.ComputeState(true, false))
    end)
end)

describe("ConvertGrowthDirection", function()
    local CASES = {
        RIGHT_DOWN = { "RIGHT", "DOWN", "HORIZONTAL" },
        RIGHT_UP   = { "RIGHT", "UP",   "HORIZONTAL" },
        LEFT_DOWN  = { "LEFT",  "DOWN", "HORIZONTAL" },
        LEFT_UP    = { "LEFT",  "UP",   "HORIZONTAL" },
        DOWN_RIGHT = { "RIGHT", "DOWN", "VERTICAL" },
        DOWN_LEFT  = { "LEFT",  "DOWN", "VERTICAL" },
        UP_RIGHT   = { "RIGHT", "UP",   "VERTICAL" },
        UP_LEFT    = { "LEFT",  "UP",   "VERTICAL" },
    }

    it("converts every direction the old display offered", function()
        local R = L.loadAuraRules()
        for input, want in pairs(CASES) do
            local h, v, axis = R.ConvertGrowthDirection(input)
            assert.are.equal(want[1], h, input .. " horizontal")
            assert.are.equal(want[2], v, input .. " vertical")
            assert.are.equal(want[3], axis, input .. " axis")
        end
    end)

    it("covers all eight directions and nothing else", function()
        local n = 0
        for _ in pairs(CASES) do n = n + 1 end
        assert.are.equal(8, n)
    end)

    it("falls back to the shipped default for an unknown value", function()
        local R = L.loadAuraRules()
        local h, v, axis = R.ConvertGrowthDirection("SIDEWAYS_INWARD")
        assert.are.equal("LEFT", h)
        assert.are.equal("DOWN", v)
        assert.are.equal("HORIZONTAL", axis)
    end)

    it("falls back for nil", function()
        local R = L.loadAuraRules()
        local h, v, axis = R.ConvertGrowthDirection(nil)
        assert.are.equal("LEFT", h)
        assert.are.equal("DOWN", v)
        assert.are.equal("HORIZONTAL", axis)
    end)
end)

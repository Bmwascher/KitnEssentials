local L = require("dev.spec._ke_loader")

describe("Advanced Debuffs filter-string construction", function()
    it("ignores the legacy PLAYER setting while negating optional filters", function()
        local R = L.loadAuraRules()
        local s = R.BuildDebuffFilter({ PLAYER = true, RAID = true })
        assert.is_nil(s:find("PLAYER", 1, true))
        assert.truthy(s:find("!RAID", 1, true))
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
    -- The eager-add rule depends on the zero-limit row: every declared key
    -- gets a count, including zero, because the group is added either way.
    it("splits the limit between externals and big defensives", function()
        local R = L.loadAuraRules()
        local rows = {
            { limit = 6, big = false, want = { external = 6, big = 0 } },
            { limit = 6, big = true,  want = { external = 3, big = 3 } },
            { limit = 5, big = true,  want = { external = 3, big = 2 } },
            { limit = 1, big = true,  want = { external = 1, big = 0 } },
        }
        for _, row in ipairs(rows) do
            assert.same(row.want, R.SplitExternalsLimit(row.limit, row.big))
        end
    end)
end)

describe("preview timing", function()
    -- One rule for both displays, taken whole from Advanced Debuffs because
    -- its 10-35s range exercises wider duration text than the 6-15s one.
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

describe("include spell id set", function()
    it("includes an enabled row", function()
        local R = L.loadAuraRules()
        local set = R.BuildIncludeSpellIDs({
            [33206] = { label = "Pain Suppression", enabled = true },
        })
        assert.is_true(set[33206])
    end)

    it("treats a row with no enabled flag as enabled", function()
        local R = L.loadAuraRules()
        local set = R.BuildIncludeSpellIDs({
            [33206] = { label = "Pain Suppression" },
        })
        assert.is_true(set[33206])
    end)

    it("omits a disabled row while keeping its enabled neighbours", function()
        local R = L.loadAuraRules()
        local set = R.BuildIncludeSpellIDs({
            [33206] = { label = "Pain Suppression", enabled = false },
            [47788] = { label = "Guardian Spirit",  enabled = true },
        })
        assert.is_nil(set[33206])
        assert.is_true(set[47788])
    end)

    it("ignores a non-table row", function()
        local R = L.loadAuraRules()
        local set = R.BuildIncludeSpellIDs({ [33206] = true })
        assert.is_nil(set[33206])
    end)

    it("omits draft and malformed keys from the candidate set", function()
        local R = L.loadAuraRules()
        local set = R.BuildIncludeSpellIDs({
            [-1] = { enabled = true },
            [0] = { enabled = true },
            [44.5] = { enabled = true },
            [444] = { enabled = true },
            ["555"] = { enabled = true },
        })

        assert.same({ [444] = true }, set)
    end)
end)

describe("CanRekeyAllowlistEntry", function()
    -- `R` is loaded per case in this file, not once at the top. Follow that:
    -- a describe-level local would diverge from every other block here.
    local function saved()
        return {
            [111] = { label = "Shipped", enabled = true, default = true },
            [222] = { label = "Custom",  enabled = true },
            [333] = { label = "Other",   enabled = true },
        }
    end

    it("allows moving a custom row to a free id", function()
        local R = L.loadAuraRules()
        assert.is_true(R.CanRekeyAllowlistEntry(saved(), 222, 444))
    end)

    it("refuses to move a shipped row", function()
        local R = L.loadAuraRules()
        assert.is_false(R.CanRekeyAllowlistEntry(saved(), 111, 444))
    end)

    it("refuses a destination that is already taken", function()
        local R = L.loadAuraRules()
        assert.is_false(R.CanRekeyAllowlistEntry(saved(), 222, 333))
    end)

    it("refuses a destination taken by a shipped row", function()
        local R = L.loadAuraRules()
        assert.is_false(R.CanRekeyAllowlistEntry(saved(), 222, 111))
    end)

    it("refuses a row that is not there", function()
        local R = L.loadAuraRules()
        assert.is_false(R.CanRekeyAllowlistEntry(saved(), 999, 444))
    end)

    it("refuses a move onto itself", function()
        local R = L.loadAuraRules()
        assert.is_false(R.CanRekeyAllowlistEntry(saved(), 222, 222))
    end)

    it("refuses non-numeric ids and a missing table", function()
        local R = L.loadAuraRules()
        assert.is_false(R.CanRekeyAllowlistEntry(saved(), "222", 444))
        assert.is_false(R.CanRekeyAllowlistEntry(nil, 222, 444))
    end)

    it("refuses zero, negative, fractional, and non-numeric destinations", function()
        local R = L.loadAuraRules()
        local entries = saved()
        local original = entries[222]

        assert.is_false(R.CanRekeyAllowlistEntry(entries, 222, 0))
        assert.is_false(R.CanRekeyAllowlistEntry(entries, 222, -444))
        assert.is_false(R.CanRekeyAllowlistEntry(entries, 222, 444.5))
        assert.is_false(R.CanRekeyAllowlistEntry(entries, 222, "444"))
        assert.is_true(entries[222] == original)
        assert.is_nil(entries[0])
        assert.is_nil(entries[-444])
        assert.is_nil(entries[444.5])
    end)
end)

describe("allowlist default restoration", function()
    local defaults = {
        [111] = { label = "On", enabled = true, default = true },
        [222] = { enabled = false, default = true },
        [333] = { label = "Implicit On", default = true },
    }

    it("restores shipped rows exactly, repairs missing rows, and preserves custom rows", function()
        local R = L.loadAuraRules()
        local custom = { label = "Custom", enabled = false }
        local entries = {
            [111] = { label = "Changed", enabled = false, default = true },
            [333] = { label = "Changed", enabled = false, default = true },
            [999] = custom,
        }

        assert.is_true(R.RestoreAllowlistDefaults(entries, defaults))
        assert.same({ label = "On", enabled = true, default = true }, entries[111])
        assert.same({ enabled = false, default = true }, entries[222])
        assert.same({ label = "Implicit On", enabled = true, default = true }, entries[333])
        assert.is_true(entries[999] == custom)
    end)

    it("lets a restore action override enabled state without owning row shape", function()
        local R = L.loadAuraRules()
        local entries = { [999] = { label = "Custom", enabled = true } }
        local seen = {}

        R.RestoreAllowlistDefaults(entries, defaults, function(spellID, seed)
            seen[spellID] = seed
            return spellID == 222
        end)

        assert.is_false(entries[111].enabled)
        assert.is_true(entries[222].enabled)
        assert.is_false(entries[333].enabled)
        assert.is_true(seen[111] == defaults[111])
        assert.same({ label = "Custom", enabled = true }, entries[999])
    end)

    it("refuses malformed caller tables without partial mutation", function()
        local R = L.loadAuraRules()
        local entries = { [999] = { enabled = true } }
        assert.is_false(R.RestoreAllowlistDefaults(entries, nil))
        assert.same({ [999] = { enabled = true } }, entries)
        assert.is_false(R.RestoreAllowlistDefaults(nil, defaults))
    end)
end)

describe("sound spell id array", function()
    it("carries only the enabled rows", function()
        local R = L.loadAuraRules()
        local ids = R.BuildSoundSpellIDs({
            [33206] = { label = "Pain Suppression", enabled = true },
            [47788] = { label = "Guardian Spirit",  enabled = false },
            [1022]  = { label = "Blessing of Protection" },
        })
        assert.same({ 1022, 33206 }, ids)
    end)

    it("sorts ascending, so the array is a stable change signature", function()
        local R = L.loadAuraRules()
        local ids = R.BuildSoundSpellIDs({
            [357170] = { enabled = true },
            [6940]   = { enabled = true },
            [102342] = { enabled = true },
        })
        assert.same({ 6940, 102342, 357170 }, ids)
    end)
end)

describe("self-cast candidate filter value", function()
    it("returns false when the setting is on, which is what drops your own casts", function()
        local R = L.loadAuraRules()
        assert.is_false(R.SelfCastFilterValue(true))
    end)

    it("returns nil when the setting is off, so the container filters nothing", function()
        local R = L.loadAuraRules()
        assert.is_nil(R.SelfCastFilterValue(false))
    end)
end)

describe("sound spell id array placeholder handling", function()
    it("drops the negative id the Add New Entry button reserves", function()
        local R = L.loadAuraRules()
        local ids = R.BuildSoundSpellIDs({
            [-1]    = { label = "Entry 1", enabled = true },
            [-2]    = { label = "Entry 2", enabled = true },
            [33206] = { label = "Pain Suppression", enabled = true },
        })
        assert.same({ 33206 }, ids)
    end)

    it("drops a non-numeric key from a hand-edited profile", function()
        local R = L.loadAuraRules()
        local ids = R.BuildSoundSpellIDs({
            ["33206"] = { enabled = true },
            [47788]   = { enabled = true },
        })
        assert.same({ 47788 }, ids)
    end)
end)

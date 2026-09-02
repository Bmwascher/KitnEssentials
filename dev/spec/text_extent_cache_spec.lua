-- Tier 1: refusal rules. Each one decides whether a measurement is allowed to
-- replace another, and every wrong answer is invisible — the box is a few
-- pixels off, or a frame stale, and nobody files that as a bug.
local L = require("dev.spec._ke_loader")

describe("KE:FontKey", function()
    local KE
    setup(function() KE = L.loadGlobals() end)

    local function fs(path, size, flags)
        return { GetFont = function() return path, size, flags end }
    end

    -- All three returns matter. A key built from the path alone leaves a size
    -- or an outline change reading as no change at all.
    it("changes when only the size, flags, or path changes", function()
        local base = KE:FontKey(fs("a.ttf", 12, "OUTLINE"))
        local variants = {
            KE:FontKey(fs("a.ttf", 16, "OUTLINE")),
            KE:FontKey(fs("a.ttf", 12, "")),
            KE:FontKey(fs("b.ttf", 12, "OUTLINE")),
        }
        for _, variant in ipairs(variants) do
            assert.are_not.equals(base, variant)
        end
    end)

    it("returns nil for a missing font string", function()
        assert.is_nil(KE:FontKey(nil))
    end)
end)

describe("KE:CommitTextExtent", function()
    local KE, cache
    setup(function() KE = L.loadGlobals() end)
    before_each(function() cache = {} end)

    it("records a valid sample", function()
        KE:CommitTextExtent(cache, "timer", "k1", 20, 8)

        assert.equals(20, cache.timer.width)
        assert.equals(8, cache.timer.height)
    end)

    -- The text is empty between populates. Letting an empty read shrink the box
    -- under the cursor mid-drag is worse than being a frame stale.
    it("keeps the retained dimensions when the sample is invalid", function()
        KE:CommitTextExtent(cache, "timer", "k1", 20, 8)
        KE:CommitTextExtent(cache, "timer", "k1", nil, nil)

        assert.equals(20, cache.timer.width)
        assert.equals(8, cache.timer.height)
    end)

    it("replaces the dimensions on a new valid sample", function()
        KE:CommitTextExtent(cache, "timer", "k1", 20, 8)
        KE:CommitTextExtent(cache, "timer", "k1", 31, 9)

        assert.equals(31, cache.timer.width)
        assert.equals(9, cache.timer.height)
    end)

    -- The one stale window a user notices: they changed the font and the box
    -- did not move. The old numbers go at once, not when a replacement arrives.
    it("clears the dimensions the moment the font changes", function()
        KE:CommitTextExtent(cache, "timer", "k1", 20, 8)
        KE:CommitTextExtent(cache, "timer", "k2", nil, nil)

        assert.is_nil(cache.timer.width)
        assert.is_nil(cache.timer.height)
        assert.equals("k2", cache.timer.fontKey)
    end)

end)

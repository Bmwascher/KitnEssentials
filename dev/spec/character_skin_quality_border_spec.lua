-- Tier: the two refusals in this file.
--
-- Scope is deliberate (AGENTS.md tiered test policy). Everything else on this
-- branch is a call-through or frame layout and is verified by the structural
-- commands plus an in-game smoke. What IS covered is the two guard rules: whether
-- the rarity border paints at all, including the default-on branch a missing
-- profile section takes; and the gradient painter's idempotence latch, which is
-- what stops a pooled row from stacking a new pair of textures on every reacquire.

local helpers = require("dev.spec._helpers")

-- The module does NOT reach its S through GetModule. It takes it straight off the
-- addon table (`local S = KE.Skins`) and reads `S.palette.brand` at FILE SCOPE,
-- then calls `S:Register` at the bottom -- so both must exist before the chunk
-- runs, and the seed IS the S under test.
local function loadSkin()
    helpers.installAddonShim()

    local store = setmetatable({}, { __mode = "k" })
    local S = {
        palette = { brand = { 1, 1, 1 } },
        Register = function() end,
        data = function(o) store[o] = store[o] or {}; return store[o] end,
    }
    _G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end

    helpers.loadModule("Modules/Skinning/Frames/Character.lua", { Skins = S, Print = function() end })
    return S
end

describe("Character skin: the rarity border refusal", function()
    it("paints when the whole profile section is missing", function()
        assert.is_true(loadSkin()._QualityBordersOn(nil))
    end)

    it("refuses ONLY on an explicit false", function()
        assert.is_false(loadSkin()._QualityBordersOn({ SlotQualityBorders = false }))
    end)
end)

describe("Character skin: the gradient painter's idempotence latch", function()
    -- A counting recorder, not a fake of Blizzard's texture subsystem. It answers
    -- the six distinct methods the painter calls and records nothing else, so it
    -- cannot drift as the painter's layout changes -- only as its METHOD SET does,
    -- which is what the latch is about.
    local function fakeRow()
        local made = 0
        local tex = {
            SetTexture = function() end, SetPoint = function() end,
            SetWidth = function() end, SetGradient = function() end,
        }
        return {
            Background = { SetAlpha = function() end },
            CreateTexture = function() made = made + 1; return tex end,
        }, function() return made end
    end

    it("creates exactly two textures however many times it is called", function()
        local S = loadSkin()
        local row, count = fakeRow()
        S._ColorizeStatPane(row)
        S._ColorizeStatPane(row)
        S._ColorizeStatPane(row)
        assert.equals(2, count())
    end)
end)

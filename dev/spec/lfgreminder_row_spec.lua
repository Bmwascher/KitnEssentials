-- Modules/Dungeons/LFGReminder.lua -- the row's arithmetic and its art
-- lookup. The line count sets the button height, so an undercount overlaps
-- the name with the role line; the art lookup decides whether the row falls
-- back to the teleport icon. Drawing, the secure click and the texture-load
-- fallback are smoke.
local loader = require("dev.spec._ke_loader")

describe("LFGReminder row", function()
    -- A fake metric of 7 px per character, enough to place the wraps.
    local function measure(s) return #s * 7 end

    describe("name line count", function()
        local count
        before_each(function()
            local LR = loader.loadLFGReminder()
            count = LR._NameLineCount
        end)

        it("wraps at the last space that fits", function()
            local cases = {
                { text = "Murder Row",               want = 1 },
                { text = "Ara-Kara, City of Echoes", want = 2 },
            }
            for _, c in ipairs(cases) do
                assert.equals(c.want, count(c.text, 128, measure), c.text)
            end
        end)

        -- ASCII: 17 glyphs of 15 px measure 255 px, two columns' worth, but
        -- only 8 whole glyphs fit in 128 px, so the break needs a third line.
        -- UTF-8: 13 two-byte glyphs at 10 px a byte; 6 whole glyphs fit in
        -- 135 px, so 3 lines, where splitting between bytes would fit 13
        -- bytes a line and give 2.
        it("breaks a word wider than the column at whole glyphs", function()
            local cases = {
                { label = "ascii", word = string.rep("x", 17),        width = 128, perByte = 15 },
                { label = "utf-8", word = string.rep("\195\169", 13), width = 135, perByte = 10 },
            }
            for _, c in ipairs(cases) do
                local perByte = c.perByte
                local byBytes = function(s) return #s * perByte end
                assert.equals(3, count(c.word, c.width, byBytes), c.label)
            end
        end)

        it("counts a missing name as one line", function()
            assert.equals(1, count(nil, 128, measure))
        end)
    end)

    it("holds the row at its floor for one line and grows it for two", function()
        local LR = loader.loadLFGReminder()
        local cases = {
            { lines = 1, rowH = 56, top = 10 },
            { lines = 2, rowH = 68, top = 8 },
        }
        for _, c in ipairs(cases) do
            local rowH, top = LR._RowLayout(c.lines, 17)
            assert.equals(c.rowH, rowH, c.lines .. " line(s)")
            assert.equals(c.top, top, c.lines .. " line(s)")
        end
    end)

    describe("dungeon art", function()
        local function artFor(name, texture)
            local LR = loader.loadLFGReminder({
                GetChallengeMapIDByName = function(_, n)
                    if n == "Ruby Life Pools" then return 399 end
                end,
                C_ChallengeMode = {
                    GetMapUIInfo = function() return "Ruby Life Pools", 399, 1800, texture end,
                },
            })
            return LR._ResolveDungeonArt(name)
        end

        it("returns the map's art for a known name", function()
            assert.equals(4746639, artFor("Ruby Life Pools", 4746639))
        end)

        it("returns nil when the map has no art", function()
            local cases = {
                { label = "nil", texture = nil },
                { label = "0",   texture = 0 },
            }
            for _, c in ipairs(cases) do
                assert.is_nil(artFor("Ruby Life Pools", c.texture), c.label)
            end
        end)

        it("returns nil for a name with no map", function()
            assert.is_nil(artFor("Not A Dungeon", 4746639))
        end)
    end)
end)

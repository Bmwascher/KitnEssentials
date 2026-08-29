-- Modules/Skinning/RoleIconSamples.lua — KE.BuildRoleIconSample. The dropdown
-- entries have no text: each label IS three inline icons, so a wrong escape
-- letter or a missing separator renders as literal junk in the menu rather
-- than failing loudly. That is what these cases are for.
local loader = require("dev.spec._ke_loader")

describe("KE.BuildRoleIconSample", function()
    local build, art

    before_each(function()
        build, art = loader.loadRoleIconSample()
    end)

    it("draws three of the set's own textures, space separated", function()
        local s = build("ringed")
        assert.are.equal(
            ("|T%s:16:16|t |T%s:16:16|t |T%s:16:16|t"):format(
                art.ringed.TANK, art.ringed.HEALER, art.ringed.DAMAGER),
            s)
    end)

    it("uses each art set's own files", function()
        for set in pairs(art) do
            local s = build(set)
            assert.is_truthy(s:find("tank%-" .. set .. "%.png"), set)
            assert.is_truthy(s:find("healer%-" .. set .. "%.png"), set)
            assert.is_truthy(s:find("dps%-" .. set .. "%.png"), set)
        end
    end)

    it("draws blizzard as the three large role atlases", function()
        assert.are.equal(
            "|A:groupfinder-icon-role-large-tank:16:16|a "
            .. "|A:groupfinder-icon-role-large-heal:16:16|a "
            .. "|A:groupfinder-icon-role-large-dps:16:16|a",
            build("blizzard"))
    end)

    -- The one entry that does not show tank, healer and damager. An escape
    -- cannot composite a role glyph over a class ring -- the declared width is
    -- the layout advance -- so the ring alone stands for the set.
    it("draws circle as three class rings", function()
        assert.are.equal(
            "|A:groupfinder-icon-class-color-SHAMAN:16:16|a "
            .. "|A:groupfinder-icon-class-color-MONK:16:16|a "
            .. "|A:groupfinder-icon-class-color-DEATHKNIGHT:16:16|a",
            build("circle"))
    end)

    it("does not draw circle the same as blizzard", function()
        assert.are_not.equal(build("blizzard"), build("circle"))
    end)

    -- An unknown key reaching the builder means the saved set drifted from the
    -- art; the row must still render something rather than an error or a blank.
    it("falls back to the role atlases for an unknown set", function()
        assert.are.equal(build("blizzard"), build("nonsense"))
    end)

    it("emits exactly three escapes and two separators for every entry", function()
        local sets = { "blizzard", "circle", "nonsense" }
        for set in pairs(art) do sets[#sets + 1] = set end
        for _, set in ipairs(sets) do
            local s = build(set)
            local escapes = select(2, s:gsub("|[TA]", ""))
            assert.are.equal(3, escapes, set .. " should carry three icons")
            assert.are.equal(2, select(2, s:gsub(" ", "")), set .. " should have two separators")
        end
    end)
end)

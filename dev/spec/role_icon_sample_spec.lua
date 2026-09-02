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
        local s = build("outlined")
        assert.are.equal(
            ("|T%s:16:16|t |T%s:16:16|t |T%s:16:16|t"):format(
                art.outlined.TANK, art.outlined.HEALER, art.outlined.DAMAGER),
            s)
    end)

    -- An unknown key reaching the builder means the saved set drifted from the
    -- art; the row must still render something rather than an error or a blank.
    it("falls back to the role atlases for an unknown set", function()
        assert.are.equal(build("blizzard"), build("nonsense"))
    end)
end)

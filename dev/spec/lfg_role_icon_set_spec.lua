-- Modules/Skinning/Frames/LFG.lua — S.GetRoleIconSet. The resolver is the
-- single read path for the saved key: five files would otherwise each decide
-- what an absent or unrecognised value means, and they would drift.
local loader = require("dev.spec._ke_loader")

describe("S.GetRoleIconSet", function()
    local function resolverWith(blizzardFrames)
        local _, S = loader.loadLFGSkin({
            Skinning = { BlizzardFrames = blizzardFrames },
        })
        return S.GetRoleIconSet()
    end

    it("returns modern when the key is absent", function()
        assert.are.equal("modern", resolverWith({}))
    end)

    it("returns the stored value when it is recognised", function()
        assert.are.equal("blizzard", resolverWith({ RoleIconSet = "blizzard" }))
        assert.are.equal("circle", resolverWith({ RoleIconSet = "circle" }))
        assert.are.equal("modern", resolverWith({ RoleIconSet = "modern" }))
    end)

    it("falls back to modern for an unrecognised value", function()
        assert.are.equal("modern", resolverWith({ RoleIconSet = "nonsense" }))
    end)

    -- The old key was a TABLE with an .Enabled field. A reader that still
    -- expected that shape would index a string and silently get nil.
    it("falls back to modern for the retired table-shaped value", function()
        assert.are.equal("modern", resolverWith({ RoleIconSet = { Enabled = true } }))
    end)

    it("returns modern when the BlizzardFrames block itself is absent", function()
        local _, S = loader.loadLFGSkin({ Skinning = {} })
        assert.are.equal("modern", S.GetRoleIconSet())
    end)
end)

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

describe("LFG role icons: the display-type gate", function()
    -- Blizzard routes RoleEnumerate and ClassEnumerate activities through the
    -- SAME hook. In ClassEnumerate the icons carry CLASS art, so painting
    -- role art over them is a defect. The two are told apart by iconOrder
    -- IDENTITY -- KE's own ROLE_ORDER holds the same three strings, so a
    -- contents comparison passes while being wrong.
    it("paints when iconOrder is Blizzard's role order table", function()
        local _, S = loader.loadLFGSkin({})
        assert.is_true(S.ShouldPaintEnumerate(_G.LFG_LIST_GROUP_DATA_ROLE_ORDER))
    end)

    it("refuses a different table with identical contents", function()
        local _, S = loader.loadLFGSkin({})
        assert.is_false(S.ShouldPaintEnumerate({ "TANK", "HEALER", "DAMAGER" }))
    end)

    it("refuses when iconOrder is absent", function()
        local _, S = loader.loadLFGSkin({})
        assert.is_false(S.ShouldPaintEnumerate(nil))
    end)
end)

describe("LFG role icons: slot classification", function()
    local function slot(shown) return { shown = shown, IsShown = function(s) return s.shown end } end

    it("skips a slot Blizzard hid", function()
        local _, S = loader.loadLFGSkin({})
        assert.are.equal("hidden", S.ClassifySlot(slot(false), true))
    end)

    it("treats a shown slot with no member left as empty", function()
        local _, S = loader.loadLFGSkin({})
        assert.are.equal("empty", S.ClassifySlot(slot(true), false))
    end)

    it("treats a shown slot with a member as filled", function()
        local _, S = loader.loadLFGSkin({})
        assert.are.equal("filled", S.ClassifySlot(slot(true), true))
    end)

    it("treats a missing slot as hidden", function()
        local _, S = loader.loadLFGSkin({})
        assert.are.equal("hidden", S.ClassifySlot(nil, true))
    end)
end)

describe("LFG role icons: the per-member refusal rule", function()
    -- A sentinel stands in for a secret value: issecretvalue is what
    -- KE:IsSafeValue consults, so overriding it is the whole simulation.
    local SECRET = setmetatable({}, { __tostring = function() return "secret" end })
    local function withSecrets()
        return loader.loadLFGSkin({
            issecretvalue = function(v) return v == SECRET end,
        })
    end

    it("accepts a member whose role and class are both readable", function()
        local _, S = withSecrets()
        local entry = S.AcceptMember("TANK", "DRUID", true)
        assert.are.equal("DRUID", entry[1])
        assert.is_true(entry[2])
    end)

    it("skips a member whose role is secret", function()
        local _, S = withSecrets()
        assert.is_nil(S.AcceptMember(SECRET, "DRUID", false))
    end)

    it("skips a member whose class is secret", function()
        local _, S = withSecrets()
        assert.is_nil(S.AcceptMember("TANK", SECRET, false))
    end)

    it("skips a member with a missing role or class", function()
        local _, S = withSecrets()
        assert.is_nil(S.AcceptMember(nil, "DRUID", false))
        assert.is_nil(S.AcceptMember("TANK", nil, false))
    end)

    -- A secret leader flag is not a reason to lose the member; only the
    -- marker is lost.
    it("keeps a member whose leader flag alone is secret", function()
        local _, S = withSecrets()
        local entry = S.AcceptMember("HEALER", "PRIEST", SECRET)
        assert.are.equal("PRIEST", entry[1])
        assert.is_nil(entry[2])
    end)

    it("refusing one member does not affect the next", function()
        local _, S = withSecrets()
        assert.is_nil(S.AcceptMember(SECRET, "DRUID", false))
        assert.are.equal("MAGE", S.AcceptMember("DAMAGER", "MAGE", false)[1])
    end)
end)

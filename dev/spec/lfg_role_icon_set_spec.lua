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

    it("accepts every key the art table defines", function()
        local KE = loader.loadLFGSkin({})
        local seen = 0
        for set in pairs(KE.ROLE_ICON_ART) do
            assert.are.equal(set, resolverWith({ RoleIconSet = set }))
            seen = seen + 1
        end
        assert.is_true(seen >= 7)
    end)

    -- The case above is NOT enough on its own: a hand-maintained list holding
    -- exactly today's nine keys satisfies it while the derivation is gone. Only
    -- a set the code could not have been written to know about proves the list
    -- is built from the art table.
    it("accepts an art set that did not exist when the code was written", function()
        local _, S = loader.loadLFGSkin({
            extraRoleIconArt = { "sentinel" },
            Skinning = { BlizzardFrames = { RoleIconSet = "sentinel" } },
        })
        assert.are.equal("sentinel", S.GetRoleIconSet())
    end)

    -- The mirror image: absence from the art table is what makes a key
    -- invalid, so a plausible-looking set that was never added still refuses.
    it("still refuses a set the art table does not define", function()
        local _, S = loader.loadLFGSkin({
            extraRoleIconArt = { "sentinel" },
            Skinning = { BlizzardFrames = { RoleIconSet = "notsentinel" } },
        })
        assert.are.equal("modern", S.GetRoleIconSet())
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

-- The one place the PNG-versus-atlas decision is made. The painters that call
-- it are file-local and reachable only through Blizzard's hooks, so this is
-- the seam that makes the routing testable at all.
describe("S.RoleArtPath", function()
    local KE, S

    before_each(function()
        KE, S = loader.loadLFGSkin({})
    end)

    it("returns the set's own art, not modern's", function()
        assert.are.equal(KE.ROLE_ICON_ART.outlined.TANK, S.RoleArtPath("outlined", "TANK"))
        assert.are.equal(KE.ROLE_ICON_ART.shaded.DAMAGER, S.RoleArtPath("shaded", "DAMAGER"))
        assert.are_not.equal(S.RoleArtPath("modern", "TANK"), S.RoleArtPath("framed", "TANK"))
    end)

    it("returns a path for every art set and role", function()
        for set, art in pairs(KE.ROLE_ICON_ART) do
            for _, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
                assert.are.equal(art[role], S.RoleArtPath(set, role))
            end
        end
    end)

    -- nil is the signal to draw an atlas instead, so these two are the whole
    -- reason blizzard and circle keep their current look.
    it("returns nil for the two sets that draw atlases", function()
        assert.is_nil(S.RoleArtPath("blizzard", "TANK"))
        assert.is_nil(S.RoleArtPath("circle", "TANK"))
    end)

    it("returns nil for an unknown set or role", function()
        assert.is_nil(S.RoleArtPath("nonsense", "TANK"))
        assert.is_nil(S.RoleArtPath("modern", "NONSENSE"))
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

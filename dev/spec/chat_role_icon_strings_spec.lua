-- Modules/Skinning/ChatRoleIcons.lua — the per-set role icon strings. The old builder
-- memoised one table for the session, so changing the set would have kept the
-- first set forever; these cases pin the per-set keying that replaces it.
local loader = require("dev.spec._ke_loader")

describe("Chat role icon strings", function()
    local build

    before_each(function()
        build = loader.loadChatRoleIconStrings()
    end)

    it("builds the round badge atlases for blizzard", function()
        local s = build("blizzard")
        assert.are.equal("|A:groupfinder-icon-role-large-tank:14:14|a", s.TANK)
        assert.are.equal("|A:groupfinder-icon-role-large-heal:14:14|a", s.HEALER)
        assert.are.equal("|A:groupfinder-icon-role-large-dps:14:14|a", s.DAMAGER)
    end)

    it("builds texture escapes for modern, because the art is a file path", function()
        local s = build("modern")
        assert.is_truthy(s.TANK:find("^|T"))
        assert.is_truthy(s.TANK:find("tank%-modern%.png"))
        assert.is_truthy(s.TANK:find("|t$"))
    end)

    -- circle is a composite: the class colour block with the borderless role
    -- glyph pulled back over it by a negative offset.
    it("builds a class-keyed composite for circle", function()
        local s = build("circle", { "MAGE", "Adventurer" })
        assert.are.equal(
            "|A:groupfinder-icon-class-color-MAGE:14:14|a"
                .. "|A:groupfinder-icon-role-micro-dps:12:12:-13:0|a",
            s.DAMAGER_MAGE)
    end)

    it("does not case-convert the class token", function()
        local s = build("circle", { "MAGE", "Adventurer" })
        assert.is_truthy(s.TANK_Adventurer)
        assert.is_truthy(s.TANK_Adventurer:find("color%-Adventurer"))
    end)

    -- The memoisation bug this replaces: one cache for the session meant the
    -- first set built won permanently.
    it("returns different strings for different sets", function()
        assert.are_not.equal(build("blizzard").TANK, build("modern").TANK)
    end)
end)

describe("Chat role icons: which set a member can actually be drawn in", function()
    local resolve

    before_each(function()
        resolve = loader.loadChatRoleIconSetResolver()
    end)

    -- Only circle composes the class in, so only circle degrades.
    it("falls circle back to blizzard when the class is unreadable", function()
        assert.are.equal("blizzard", resolve("circle", false))
    end)

    it("keeps circle when the class is readable", function()
        assert.are.equal("circle", resolve("circle", true))
    end)

    it("leaves modern and blizzard alone whatever the class", function()
        assert.are.equal("modern", resolve("modern", false))
        assert.are.equal("modern", resolve("modern", true))
        assert.are.equal("blizzard", resolve("blizzard", false))
    end)
end)

describe("Chat role icons: the identity refusal", function()
    local SECRET = setmetatable({}, { __tostring = function() return "secret" end })
    local accept

    before_each(function()
        accept = loader.loadChatMemberAcceptor({
            issecretvalue = function(v) return v == SECRET end,
        })
    end)

    it("accepts a readable member and returns its keys", function()
        local name, realm = accept("TANK", "Kitn", "Ravencrest")
        assert.are.equal("Kitn", name)
        assert.are.equal("Ravencrest", realm)
    end)

    it("accepts a same-realm member, whose realm is empty", function()
        local name, realm = accept("HEALER", "Kitn", "")
        assert.are.equal("Kitn", name)
        assert.is_nil(realm)
    end)

    it("skips a member whose role is secret", function()
        assert.is_nil(accept(SECRET, "Kitn", "Ravencrest"))
    end)

    it("skips a member whose name is secret", function()
        assert.is_nil(accept("TANK", SECRET, "Ravencrest"))
    end)

    -- The realm forms the second cache key, so a secret realm is refused
    -- even though the name alone would have keyed an entry.
    it("skips a member whose realm is secret", function()
        assert.is_nil(accept("TANK", "Kitn", SECRET))
    end)

    it("refusing one member does not affect the next", function()
        assert.is_nil(accept("TANK", SECRET, nil))
        assert.are.equal("Kitn", (accept("DAMAGER", "Kitn", nil)))
    end)
end)

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

    -- Every art set takes the texture path, not just modern, and each draws
    -- its OWN files. Asserting only that the escape is a texture would pass a
    -- builder that reached for modern's art whatever set it was handed, which
    -- is the failure the shared-decision refactor exists to prevent.
    it("builds texture escapes for every art set", function()
        for _, set in ipairs({ "ringed", "outlined", "framed", "hexagon",
                              "plain", "muted", "shaded" }) do
            local s = build(set)
            assert.is_truthy(s.TANK:find("^|T"), set .. " should draw a texture")
            assert.is_truthy(s.TANK:find("tank%-" .. set .. "%.png"), set .. " should draw its own art")
            assert.is_truthy(s.HEALER:find("healer%-" .. set .. "%.png"))
            assert.is_truthy(s.DAMAGER:find("dps%-" .. set .. "%.png"))
        end
    end)

    -- circle draws the Blizzard badge in chat. Its Group Finder art composes
    -- a class ring and a role glyph, which an |A| escape cannot express: the
    -- declared width IS the advance, so an overlay reserves the sum of both
    -- widths however far back the second is offset, and the surplus reads as
    -- a gap before the name. Dropping the role glyph instead loses the one
    -- thing a role icon is for. Chat therefore needs no class at all.
    it("draws circle as the blizzard role badge", function()
        assert.are.equal(build("blizzard").TANK, build("circle").TANK)
    end)

    it("keeps every string to a single escape", function()
        for _, set in ipairs({ "modern", "blizzard", "circle" }) do
            for _, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
                local s = build(set)[role]
                local _, count = s:gsub("|[TA]", "")
                assert.are.equal(1, count, set .. " " .. role .. " is not one escape: " .. s)
            end
        end
    end)

    it("emits no class-keyed entries", function()
        local s = build("circle")
        for key in pairs(s) do
            assert.is_nil(key:find("_"), "unexpected class-keyed entry: " .. key)
        end
    end)

    -- The memoisation bug this replaces: one cache for the session meant the
    -- first set built won permanently.
    it("returns different strings for different sets", function()
        assert.are_not.equal(build("blizzard").TANK, build("modern").TANK)
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

-- The cache answers to whichever sender-name form chat delivers. A same-realm
-- member reads back from the unit API with NO realm, so keying on the bare
-- name alone left every such member unreachable while the player -- whose own
-- realm is always readable -- kept working. That asymmetry is the bug these
-- cases pin.
describe("Chat role icon cache keys", function()
    local keys

    before_each(function()
        keys = loader.loadChatRoleIconKeys()
    end)

    it("qualifies a same-realm member with the player's realm", function()
        local bare, qualified = keys("Ally", nil, "Stormrage")
        assert.are.equal("Ally", bare)
        assert.are.equal("Ally-Stormrage", qualified)
    end)

    it("treats an empty realm as same-realm", function()
        local _, qualified = keys("Ally", "", "Stormrage")
        assert.are.equal("Ally-Stormrage", qualified)
    end)

    it("keeps a cross-realm member's own realm", function()
        local bare, qualified = keys("Ally", "Draenor", "Stormrage")
        assert.are.equal("Ally", bare)
        assert.are.equal("Ally-Draenor", qualified)
    end)

    -- The unit API returns a DISPLAY realm that keeps its spaces and
    -- punctuation; a chat sender's suffix has both stripped. A key built from
    -- the raw value never matches on any multiword realm, which is most of
    -- the failure the realm fallback was supposed to fix.
    it("strips spaces from a multiword member realm", function()
        local _, qualified = keys("Ally", "Twisting Nether", nil)
        assert.are.equal("Ally-TwistingNether", qualified)
    end)

    it("strips spaces from the player realm fallback too", function()
        local _, qualified = keys("Ally", nil, "Twisting Nether")
        assert.are.equal("Ally-TwistingNether", qualified)
    end)

    it("strips punctuation but keeps accented characters", function()
        local _, qualified = keys("Ally", "Aggra (Português)", nil)
        assert.are.equal("Ally-AggraPortuguês", qualified)
    end)

    -- Case is NOT folded: the chat suffix keeps its capitals, so folding here
    -- would break every realm it was meant to match.
    it("does not change case", function()
        local _, qualified = keys("Ally", "Draenor", nil)
        assert.are.equal("Ally-Draenor", qualified)
    end)

    it("returns the bare key alone when no realm is known at all", function()
        local bare, qualified = keys("Ally", nil, nil)
        assert.are.equal("Ally", bare)
        assert.is_nil(qualified)
    end)

    it("refuses a nameless member", function()
        assert.is_nil(keys(nil, nil, "Stormrage"))
        assert.is_nil(keys("", nil, "Stormrage"))
    end)
end)

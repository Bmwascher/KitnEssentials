-- Tier 2: Core/Nicknames.lua. The external nickname provider (NSAPI) is a
-- one-call stub, not a stateful fake: each case sets what GetName answers.
-- Loader unit identity: player is "Bob" on "Realm".
local helpers = require("dev.spec._helpers")
local L = require("dev.spec._ke_loader")

-- Nicknames.lua captures its unit globals as file-scope upvalues at load, so
-- per-case unit stubs need a _G reassign plus a fresh loadModule AFTER the
-- loader has installed the base environment.
local function reloadWithUnitStubs(stubs)
    for k, v in pairs(stubs) do _G[k] = v end
    return helpers.loadModule("Core/Nicknames.lua", {})
end

-- The precedence rule fails silently when broken: a wrong answer renders a
-- plausible name, not an error. Driven as a pure function.
describe("Nicknames.lua ResolveNicknamePrecedence", function()
    local KE
    before_each(function() KE = L.loadNicknames() end)

    it("returns a usable provider nickname and nil for anything else", function()
        local cases = {
            { name = "a nickname", foreign = "Foreign", want = "Foreign" },
            { name = "nil" },
            { name = "empty",      foreign = "" },
            { name = "a number",   foreign = 42 },
            { name = "false",      foreign = false },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.want, KE:ResolveNicknamePrecedence(c.foreign, "Bob"), c.name)
        end
    end)

    -- NSAPI says "no nickname" by echoing the name back, in two shapes: the
    -- whole string, or the bare name when it resolved the input as a unit.
    -- Both must be refused, or an un-nicknamed cross-realm player reads as
    -- nicknamed and ShowRealm stops working.
    it("refuses a provider value that only echoes the name it was asked about", function()
        assert.is_nil(KE:ResolveNicknamePrecedence("Bob", "Bob"))
        assert.is_nil(KE:ResolveNicknamePrecedence("Bob-Realm", "Bob-Realm"))
        assert.is_nil(KE:ResolveNicknamePrecedence("Bob", "Bob-Realm"))
        -- A real nickname alongside a realm-bearing name still resolves.
        assert.equals("Bobby", KE:ResolveNicknamePrecedence("Bobby", "Bob-Realm"))
    end)
end)

describe("Nicknames.lua GetNicknameOrName", function()
    local saved
    before_each(function() saved = _G.NSAPI end)
    after_each(function() _G.NSAPI = saved end)

    it("returns the provider's nickname for a player unit", function()
        local KE = L.loadNicknames()
        _G.NSAPI = { GetName = function() return "Foreign" end }
        assert.equals("Foreign", KE:GetNicknameOrName("player"))
    end)

    it("falls back to UnitName when no provider is present", function()
        local KE = L.loadNicknames()
        _G.NSAPI = nil
        assert.equals("Bob", KE:GetNicknameOrName("player"))
    end)

    it("survives a provider that throws", function()
        local KE = L.loadNicknames()
        _G.NSAPI = { GetName = function() error("provider exploded") end }
        assert.equals("Bob", KE:GetNicknameOrName("player"))
    end)

    it("returns '' for a nil unit", function()
        assert.equals("", L.loadNicknames():GetNicknameOrName(nil))
    end)

    -- The provider answers "WRONG" in the two refusal cases below, so a
    -- missing gate returns it and the case fails.
    it("asks no provider for a non-player unit, and returns '' when it has no name", function()
        L.loadNicknames()
        _G.NSAPI = { GetName = function() return "WRONG" end }
        local named = reloadWithUnitStubs({
            UnitIsPlayer = function() return false end,
            UnitName = function() return "Ragnaros" end,
        })
        assert.equals("Ragnaros", named:GetNicknameOrName("target"))
        local unnamed = reloadWithUnitStubs({
            UnitIsPlayer = function() return false end,
            UnitName = function() return nil end,
        })
        assert.equals("", unnamed:GetNicknameOrName("target"))
    end)

    -- A DECLARED sentinel: plain Lua compares strings happily, so what is
    -- pinned here is the BRANCH, never the real secret semantics. Those stay
    -- in game.
    it("asks no provider while the name or the realm reads secret", function()
        local SECRET = "<<declared secret>>"
        L.loadNicknames()
        _G.NSAPI = { GetName = function() return "WRONG" end }
        local cases = {
            { name = "secret name",  first = SECRET, second = "Realm" },
            { name = "secret realm", first = "Bob",  second = SECRET },
        }
        for _, c in ipairs(cases) do
            local KE = reloadWithUnitStubs({
                UnitIsPlayer = function() return true end,
                UnitFullName = function() return c.first, c.second end,
                UnitName = function() return "Bob" end,
                issecretvalue = function(v) return v == SECRET end,
            })
            assert.equals("Bob", KE:GetNicknameOrName("party1"), c.name)
        end
    end)
end)

describe("Nicknames.lua BuildNicknameKey", function()
    local KE
    before_each(function()
        KE = L.loadNicknames()
    end)

    it("appends the fallback realm to a bare same-realm name", function()
        -- The probe-confirmed C_DamageMeter shape: same-realm
        -- source names arrive with NO realm suffix.
        assert.equals("Bite-Area52", KE:BuildNicknameKey("Bite", "Area52"))
    end)

    it("passes an already-normalized suffix through, ignoring the fallback", function()
        assert.equals("Bob-TwistingNether", KE:BuildNicknameKey("Bob-TwistingNether", "Area52"))
    end)

    it("normalizes spaces, apostrophes, and inner hyphens in the realm", function()
        assert.equals("Bob-TwistingNether", KE:BuildNicknameKey("Bob-Twisting Nether", "Area52"))
        assert.equals("Bob-MalGanis", KE:BuildNicknameKey("Bob-Mal'Ganis", "Area52"))
        -- First hyphen is the separator; later ones belong to the realm.
        assert.equals("Bob-AzjolNerub", KE:BuildNicknameKey("Bob-Azjol-Nerub", "Area52"))
    end)

    it("normalizes the FALLBACK realm too", function()
        assert.equals("Bite-Area52", KE:BuildNicknameKey("Bite", "Area 52"))
        -- a fallback that normalizes to nothing is unresolvable
        assert.is_nil(KE:BuildNicknameKey("Bite", " ' -"))
    end)

    it("returns nil when either side is unresolvable", function()
        assert.is_nil(KE:BuildNicknameKey(nil, "Area52"))
        assert.is_nil(KE:BuildNicknameKey("", "Area52"))
        assert.is_nil(KE:BuildNicknameKey(42, "Area52"))
        -- bare name with no fallback realm (pre-login GetNormalizedRealmName)
        assert.is_nil(KE:BuildNicknameKey("Bite", nil))
        assert.is_nil(KE:BuildNicknameKey("Bite", ""))
    end)
end)

describe("Nicknames.lua RefreshNicknameTags", function()
    local KE
    before_each(function() KE = L.loadNicknames() end)

    -- Both arms counted: one dropped by a later edit would otherwise fail
    -- nothing. Healer Mana refreshes only with a container, since its finder
    -- faults on a nil frame.
    it("notifies both readers, and no-ops when they are absent", function()
        assert.has_no.errors(function() KE:RefreshNicknameTags() end)
        local dmCalls, hmCalls = 0, 0
        local DM = _G.KitnEssentials:GetModule("DamageMeter", true)
        DM.OnNicknamesChanged = function() dmCalls = dmCalls + 1 end
        local HM = _G.KitnEssentials:GetModule("HealerMana", true)
        HM.FindHealers = function() hmCalls = hmCalls + 1 end
        KE:RefreshNicknameTags()
        assert.equals(1, dmCalls)
        assert.equals(0, hmCalls)
        HM.containerFrame = {}
        KE:RefreshNicknameTags()
        assert.equals(2, dmCalls)
        assert.equals(1, hmCalls)
    end)
end)

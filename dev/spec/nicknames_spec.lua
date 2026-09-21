-- Tier 2: Core/Nicknames.lua. The export string codec (KE:EncodeForExport /
-- KE:DecodeFromExport, Core/ProfileManager.lua) is C_EncodingUtil and is not
-- loaded here: the cases drive the payload collection and the store merge
-- directly, and the import guards that return before any decode. Loader unit
-- identity: player is "Bob" on "Realm" (key "Bob-Realm").
local helpers = require("dev.spec._helpers")
local L = require("dev.spec._ke_loader")

-- Nicknames.lua captures its unit globals as file-scope upvalues at load
-- (Nicknames.lua), so per-case unit stubs need a _G reassign plus a
-- fresh loadModule AFTER the loader has installed the base environment.
local function reloadWithUnitStubs(stubs)
    for k, v in pairs(stubs) do _G[k] = v end
    return helpers.loadModule("Core/Nicknames.lua",
        { db = { global = { Nicknames = {} } } })
end

describe("Nicknames.lua CollectNicknamePayload", function()
    local KE, nicks
    before_each(function()
        KE = L.loadNicknames()
        nicks = KE.db.global.Nicknames
    end)

    it("keeps only string-keyed, non-empty string nicknames", function()
        nicks["Bob-Realm"] = "Bobby"
        nicks[42] = "numeric key"
        nicks["Bad-Realm"] = 7
        nicks["Empty-Realm"] = ""
        local payload, count = KE:CollectNicknamePayload()
        assert.same({ ["Bob-Realm"] = "Bobby" }, payload)
        assert.equals(1, count)
    end)

    it("errors when nothing is exportable", function()
        local payload, err = KE:CollectNicknamePayload()
        assert.is_nil(payload)
        assert.equals("No nicknames to export", err)
        -- invalid-only entries still count as nothing to export
        nicks[1] = "numeric key"
        nicks["Bob-Realm"] = ""
        payload, err = KE:CollectNicknamePayload()
        assert.is_nil(payload)
        assert.equals("No nicknames to export", err)
    end)

    it("errors when the nickname store is missing", function()
        KE.db.global.Nicknames = nil
        local payload, err = KE:CollectNicknamePayload()
        assert.is_nil(payload)
        assert.equals("Nicknames database not available", err)
    end)
end)

describe("Nicknames.lua ApplyNicknamePayload", function()
    local KE, nicks
    before_each(function()
        KE = L.loadNicknames()
        nicks = KE.db.global.Nicknames
    end)

    it("merges additively: one added, one updated, an untouched key survives", function()
        nicks["A-Realm"] = "old"   -- same key, different nick -> updated
        nicks["B-Realm"] = "keep"  -- not in the payload -> untouched
        local added, updated, removed = KE:ApplyNicknamePayload({ ["A-Realm"] = "new", ["C-Realm"] = "fresh" })
        assert.same({ 1, 1, 0 }, { added, updated, removed })
        assert.equals("new", nicks["A-Realm"])
        assert.equals("keep", nicks["B-Realm"])
        assert.equals("fresh", nicks["C-Realm"])
    end)

    it("counts an identical payload as no change and leaves the store intact", function()
        nicks["A-Realm"] = "same"
        local added, updated, removed = KE:ApplyNicknamePayload({ ["A-Realm"] = "same" })
        assert.same({ 0, 0, 0 }, { added, updated, removed })
        assert.equals("same", nicks["A-Realm"])
    end)

    it("replaceAll wipes local-only entries and counts them removed, an overlapping key added", function()
        nicks["A-Realm"] = "stale" -- in the payload too: wiped then re-added
        nicks["X-Realm"] = "gone"  -- absent from the payload -> removed
        local added, updated, removed = KE:ApplyNicknamePayload({ ["A-Realm"] = "a", ["B-Realm"] = "b" }, true)
        assert.same({ 2, 0, 1 }, { added, updated, removed })
        assert.is_nil(nicks["X-Realm"])
        assert.equals("a", nicks["A-Realm"])
        assert.equals("b", nicks["B-Realm"])
    end)

    it("applies only string-keyed, non-empty string payload entries", function()
        local added = KE:ApplyNicknamePayload({ ["Good-Realm"] = "G", [5] = "numeric", ["Bad-Realm"] = 7, ["Empty-Realm"] = "" })
        assert.equals(1, added)
        assert.equals("G", nicks["Good-Realm"])
        assert.is_nil(nicks["Bad-Realm"])
        assert.is_nil(nicks["Empty-Realm"])
    end)

    it("refreshes nickname tags on a change only", function()
        local refreshes = 0
        KE.RefreshNicknameTags = function() refreshes = refreshes + 1 end
        nicks["A-Realm"] = "a"
        KE:ApplyNicknamePayload({ ["A-Realm"] = "a" })
        assert.equals(0, refreshes)
        KE:ApplyNicknamePayload({ ["B-Realm"] = "b" })
        assert.equals(1, refreshes)
    end)
end)

describe("Nicknames.lua ImportNicknames guards", function()
    local KE
    before_each(function()
        KE = L.loadNicknames()
    end)

    it("rejects nil and empty import strings", function()
        local ok, msg = KE:ImportNicknames(nil)
        assert.is_false(ok)
        assert.equals("Import string is empty", msg)
        ok, msg = KE:ImportNicknames("")
        assert.is_false(ok)
        assert.equals("Import string is empty", msg)
    end)

    it("refuses an older-version string with the shared message", function()
        KE.LEGACY_EXPORT_MESSAGE = "older"
        local ok, msg = KE:ImportNicknames("!KEN1!anything")
        assert.is_false(ok)
        assert.equals("older", msg)
    end)

    it("rejects a wrong prefix", function()
        local ok, msg = KE:ImportNicknames("!KEN3!anything")
        assert.is_false(ok)
        assert.is_not_nil(msg:find("Invalid format", 1, true))
    end)

    it("refuses a missing store before decoding", function()
        -- KE.DecodeFromExport is nil here: reaching it would raise, so the
        -- store guard is proven to run first.
        KE.db.global.Nicknames = nil
        local ok, msg = KE:ImportNicknames("!KEN2!anything")
        assert.is_false(ok)
        assert.equals("Nicknames database not available", msg)
    end)

    it("rejects a decoded payload without a d table", function()
        KE.DecodeFromExport = function() return { v = 1 } end
        local ok, msg = KE:ImportNicknames("!KEN2!anything")
        assert.is_false(ok)
        assert.equals("Invalid export data", msg)
    end)
end)

describe("Nicknames.lua GetNicknameOrName", function()
    local KE, nicks
    before_each(function()
        KE = L.loadNicknames()
        nicks = KE.db.global.Nicknames
    end)

    it("returns the stored nickname for the player's Name-Realm key", function()
        nicks["Bob-Realm"] = "Bobby"
        assert.equals("Bobby", KE:GetNicknameOrName("player"))
    end)

    it("falls back to UnitName when no nickname is stored", function()
        assert.equals("Bob", KE:GetNicknameOrName("player"))
    end)

    it("treats an empty-string nickname as unset", function()
        nicks["Bob-Realm"] = ""
        assert.equals("Bob", KE:GetNicknameOrName("player"))
    end)

    it("returns '' for a nil unit", function()
        assert.equals("", KE:GetNicknameOrName(nil))
    end)

    it("bypasses the store entirely for non-player units", function()
        local KE2 = reloadWithUnitStubs({
            UnitIsPlayer = function() return false end,
            UnitName = function() return "Ragnaros" end,
        })
        -- would be the lookup hit if the UnitIsPlayer gate were missing
        KE2.db.global.Nicknames["Bob-Realm"] = "WRONG"
        assert.equals("Ragnaros", KE2:GetNicknameOrName("target"))
    end)

    it("returns '' when a non-player unit has no name", function()
        local KE2 = reloadWithUnitStubs({
            UnitIsPlayer = function() return false end,
            UnitName = function() return nil end,
        })
        assert.equals("", KE2:GetNicknameOrName("target"))
    end)

    it("falls back to GetNormalizedRealmName when UnitFullName omits the realm", function()
        -- Same-realm units return a nil realm from UnitFullName in-game; the
        -- key must still resolve via GetNormalizedRealmName (Nicknames.lua).
        local KE2 = reloadWithUnitStubs({
            UnitIsPlayer = function() return true end,
            UnitFullName = function() return "Bob", nil end,
            GetNormalizedRealmName = function() return "Realm" end,
            UnitName = function() return "Bob" end,
        })
        KE2.db.global.Nicknames["Bob-Realm"] = "Bobby"
        assert.equals("Bobby", KE2:GetNicknameOrName("party1"))
    end)

    -- Refusal rule. These use a DECLARED sentinel, which is the only honest
    -- thing a headless spec can do: plain Lua compares and concatenates
    -- strings happily, so what is pinned here is the BRANCH, never the real
    -- secret semantics. Those stay in game.
    --
    -- Each case plants the nickname under the key the UNGUARDED code would
    -- build. Without that the test proves nothing, because refusing and
    -- looking up a key that is not in the store both end at "Bob".
    local SECRET = "<<declared secret>>"

    it("refuses the store when the name comes back secret", function()
        local KE2 = reloadWithUnitStubs({
            UnitIsPlayer = function() return true end,
            UnitFullName = function() return SECRET, "Realm" end,
            UnitName = function() return "Bob" end,
            issecretvalue = function(v) return v == SECRET end,
        })
        KE2.db.global.Nicknames[SECRET .. "-Realm"] = "WRONG"
        assert.equals("Bob", KE2:GetNicknameOrName("party1"))
    end)

    it("refuses the store when the realm comes back secret", function()
        local KE2 = reloadWithUnitStubs({
            UnitIsPlayer = function() return true end,
            UnitFullName = function() return "Bob", SECRET end,
            UnitName = function() return "Bob" end,
            issecretvalue = function(v) return v == SECRET end,
        })
        KE2.db.global.Nicknames["Bob-" .. SECRET] = "WRONG"
        assert.equals("Bob", KE2:GetNicknameOrName("party1"))
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

    it("built keys resolve against real store writes", function()
        local nicks = KE.db.global.Nicknames
        nicks["Bob-Realm"] = "Bobby"
        assert.equals("Bobby", nicks[KE:BuildNicknameKey("Bob", "Realm")])
        assert.equals("Bobby", nicks[KE:BuildNicknameKey("Bob-Realm", "Elsewhere")])
    end)
end)

describe("Nicknames.lua ClearAllNicknames + tag refresh", function()
    local KE, nicks
    before_each(function()
        KE = L.loadNicknames()
        nicks = KE.db.global.Nicknames
    end)

    it("wipes the store, returns the cleared count, and notifies tags", function()
        local refreshes = 0
        KE.RefreshNicknameTags = function() refreshes = refreshes + 1 end
        nicks["A-Realm"] = "a"
        nicks["B-Realm"] = "b"
        nicks["C-Realm"] = "c"
        assert.equals(3, KE:ClearAllNicknames())
        assert.is_nil(next(nicks))
        assert.equals(1, refreshes)
    end)

    it("returns 0 for an empty or missing store", function()
        assert.equals(0, KE:ClearAllNicknames())
        KE.db.global.Nicknames = nil
        assert.equals(0, KE:ClearAllNicknames())
    end)

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

-- The precedence rule fails silently when broken: a wrong answer renders a
-- plausible name, not an error. Driven as a pure function, so the suite needs
-- no fake of NSAPI.
describe("Nicknames.lua ResolveNicknamePrecedence", function()
    local KE
    before_each(function() KE = L.loadNicknames() end)

    it("prefers KE's own nickname when both sources have one", function()
        assert.equals("Own", KE:ResolveNicknamePrecedence("Own", "Foreign", "Bob"))
    end)

    it("uses whichever single source has a nickname", function()
        assert.equals("Own", KE:ResolveNicknamePrecedence("Own", nil, "Bob"))
        assert.equals("Foreign", KE:ResolveNicknamePrecedence(nil, "Foreign", "Bob"))
    end)

    it("resolves nothing when neither source offers a usable string", function()
        local unusable = { nil, "", 42, false }
        for i = 1, 4 do
            local v = unusable[i]
            assert.is_nil(KE:ResolveNicknamePrecedence(v, v, "Bob"))
        end
        -- An unusable own value must not suppress a good foreign one.
        assert.equals("Foreign", KE:ResolveNicknamePrecedence("", "Foreign", "Bob"))
    end)

    -- NSAPI signals "no nickname" by echoing the name back, in two shapes:
    -- the whole string, or the bare name when it resolved the input as a unit.
    -- Both must be refused, or an un-nicknamed cross-realm player reads as
    -- nicknamed and ShowRealm stops working.
    it("refuses a foreign value that only echoes the name it was asked about", function()
        assert.is_nil(KE:ResolveNicknamePrecedence(nil, "Bob", "Bob"))
        assert.is_nil(KE:ResolveNicknamePrecedence(nil, "Bob-Realm", "Bob-Realm"))
        assert.is_nil(KE:ResolveNicknamePrecedence(nil, "Bob", "Bob-Realm"))
        -- A real nickname alongside a realm-bearing name still resolves.
        assert.equals("Bobby", KE:ResolveNicknamePrecedence(nil, "Bobby", "Bob-Realm"))
    end)
end)

-- The predicate above proves the decision; this proves GetNicknameOrName
-- reaches the foreign source at all and survives it failing. A one-call stub,
-- not a stateful fake: it holds no state.
-- Loader unit identity is "Bob" on "Realm".
describe("Nicknames.lua GetNicknameOrName with a foreign source", function()
    local KE
    before_each(function() KE = L.loadNicknames() end)
    after_each(function() _G.NSAPI = nil end)

    it("returns a foreign nickname when KE's store has none", function()
        _G.NSAPI = { GetName = function() return "Foreign" end }
        assert.equals("Foreign", KE:GetNicknameOrName("player"))
    end)

    it("keeps KE's own nickname ahead of the foreign one", function()
        KE.db.global.Nicknames["Bob-Realm"] = "Bobby"
        _G.NSAPI = { GetName = function() return "Foreign" end }
        assert.equals("Bobby", KE:GetNicknameOrName("player"))
    end)

    it("survives a foreign source that throws", function()
        _G.NSAPI = { GetName = function() error("provider exploded") end }
        assert.equals("Bob", KE:GetNicknameOrName("player"))
    end)
end)

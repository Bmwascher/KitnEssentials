-- Tier 2: Core/Nicknames.lua export/import through the REAL embedded
-- serialization stack (LibStub + CallbackHandler + AceSerializer + LibDeflate,
-- loaded by L.loadNicknames) — round-trips exercise real encoding, not a
-- mirror. Loader unit identity: player is "Bob" on "Realm" (key "Bob-Realm").
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

describe("Nicknames.lua ExportNicknames", function()
    local KE, nicks
    before_each(function()
        KE = L.loadNicknames()
        nicks = KE.db.global.Nicknames
    end)

    it("produces a !KEN1!-prefixed chat-safe string and the entry count", function()
        nicks["Bob-Realm"] = "Bobby"
        nicks["Alice-Realm"] = "Ally"
        local encoded, err, count = KE:ExportNicknames()
        assert.is_nil(err)
        assert.equals("string", type(encoded))
        assert.equals("!KEN1!", encoded:sub(1, 6))
        assert.equals(2, count)
        -- EncodeForPrint output must survive a chat paste: no whitespace/control.
        assert.is_nil(encoded:find("[%c%s]"))
    end)

    it("counts only string-keyed, non-empty string nicknames", function()
        nicks["Bob-Realm"] = "Bobby"
        nicks[42] = "numeric key"
        nicks["Bad-Realm"] = 7
        nicks["Empty-Realm"] = ""
        local encoded, err, count = KE:ExportNicknames()
        assert.is_nil(err)
        assert.equals(1, count)
        assert.equals("!KEN1!", encoded:sub(1, 6))
    end)

    it("errors when nothing is exportable", function()
        local encoded, err = KE:ExportNicknames()
        assert.is_nil(encoded)
        assert.equals("No nicknames to export", err)
        -- invalid-only entries still count as nothing to export
        nicks[1] = "numeric key"
        nicks["Bob-Realm"] = ""
        encoded, err = KE:ExportNicknames()
        assert.is_nil(encoded)
        assert.equals("No nicknames to export", err)
    end)

    it("errors when the nickname store is missing", function()
        KE.db.global.Nicknames = nil
        local encoded, err = KE:ExportNicknames()
        assert.is_nil(encoded)
        assert.equals("Nicknames database not available", err)
    end)
end)

describe("Nicknames.lua ImportNicknames — real-stack round-trips", function()
    local KE, nicks
    before_each(function()
        KE = L.loadNicknames()
        nicks = KE.db.global.Nicknames
    end)

    it("restores an identical table after export -> clear -> import", function()
        local original = {
            ["Bob-Realm"] = "Bobby",
            ["Alice-OtherRealm"] = "Ally",
            ["Chen-Realm"] = "Brewmaster",
        }
        for k, v in pairs(original) do nicks[k] = v end
        local encoded = KE:ExportNicknames()
        KE:ClearAllNicknames()
        local ok, msg = KE:ImportNicknames(encoded)
        assert.is_true(ok)
        assert.equals("3 added", msg)
        assert.same(original, nicks)
    end)

    it("round-trips serializer escape bytes, format delimiters, and non-ASCII", function()
        -- "^"/"~" are AceSerializer's own delimiter/escape bytes; "!KEN1!" is
        -- the wrapper prefix; "-" is the store's Name-Realm key delimiter.
        local original = {
            ["Bob-Realm"] = "^S~lit^^~`caret^",
            ["Alice-Realm"] = "has !KEN1! inside",
            ["Chen-Realm"] = "dash-y like Name-Realm",
            ["Nora-Realm"] = "Bóbby ñ 日本",
        }
        for k, v in pairs(original) do nicks[k] = v end
        local encoded = KE:ExportNicknames()
        KE:ClearAllNicknames()
        local ok, msg = KE:ImportNicknames(encoded)
        assert.is_true(ok)
        assert.equals("4 added", msg)
        assert.same(original, nicks)
    end)

    it("merges additively: '1 added, 1 updated', untouched keys survive", function()
        nicks["A-Realm"] = "new"
        nicks["C-Realm"] = "fresh"
        local encoded = KE:ExportNicknames()
        wipe(nicks)
        nicks["A-Realm"] = "old"   -- same key, different nick -> updated
        nicks["B-Realm"] = "keep"  -- not in the import -> untouched
        local ok, msg = KE:ImportNicknames(encoded)
        assert.is_true(ok)
        assert.equals("1 added, 1 updated", msg)
        assert.equals("new", nicks["A-Realm"])
        assert.equals("keep", nicks["B-Realm"])
        assert.equals("fresh", nicks["C-Realm"])
    end)

    it("rejects an identical re-import as a no-op", function()
        nicks["A-Realm"] = "same"
        local encoded = KE:ExportNicknames()
        local ok, msg = KE:ImportNicknames(encoded)
        assert.is_false(ok)
        assert.equals("No nicknames were imported", msg)
        assert.equals("same", nicks["A-Realm"]) -- store intact
    end)

    it("replaceAll wipes local-only entries: '2 added, 1 removed'", function()
        nicks["A-Realm"] = "a"
        nicks["B-Realm"] = "b"
        local encoded = KE:ExportNicknames()
        wipe(nicks)
        nicks["X-Realm"] = "gone" -- absent from the import -> removed
        local ok, msg = KE:ImportNicknames(encoded, true)
        assert.is_true(ok)
        assert.equals("2 added, 1 removed", msg)
        assert.is_nil(nicks["X-Realm"])
        assert.equals("a", nicks["A-Realm"])
        assert.equals("b", nicks["B-Realm"])
    end)

    it("replaceAll counts overlapping keys as added, never removed", function()
        -- Nicknames.lua: removed counts only keys absent from the
        -- payload; a key present in both is wiped then re-added.
        nicks["A-Realm"] = "a"
        local encoded = KE:ExportNicknames()
        nicks["A-Realm"] = "stale"
        nicks["X-Realm"] = "gone"
        local ok, msg = KE:ImportNicknames(encoded, true)
        assert.is_true(ok)
        assert.equals("1 added, 1 removed", msg)
        assert.equals("a", nicks["A-Realm"])
        assert.is_nil(nicks["X-Realm"])
    end)

    it("applies only string-keyed, non-empty string payload entries", function()
        -- Hand-built payload: the import loop re-filters entry types
        -- (Nicknames.lua) even though export never emits these.
        local Serializer = LibStub("AceSerializer-3.0")
        local Deflate = LibStub("LibDeflate")
        local serialized = Serializer:Serialize({
            v = 1,
            d = { ["Good-Realm"] = "G", [5] = "numeric", ["Bad-Realm"] = 7, ["Empty-Realm"] = "" },
        })
        local encoded = "!KEN1!" .. Deflate:EncodeForPrint(Deflate:CompressDeflate(serialized))
        local ok, msg = KE:ImportNicknames(encoded)
        assert.is_true(ok)
        assert.equals("1 added", msg)
        assert.equals("G", nicks["Good-Realm"])
        assert.is_nil(nicks["Bad-Realm"])
        assert.is_nil(nicks["Empty-Realm"])
    end)

    it("refreshes nickname tags on success only", function()
        local refreshes = 0
        KE.RefreshNicknameTags = function() refreshes = refreshes + 1 end
        nicks["A-Realm"] = "a"
        local encoded = KE:ExportNicknames()
        KE:ImportNicknames("bogus") -- rejected before any write
        assert.equals(0, refreshes)
        wipe(nicks)
        KE:ImportNicknames(encoded)
        assert.equals(1, refreshes)
    end)
end)

describe("Nicknames.lua ImportNicknames rejection paths", function()
    local KE, nicks
    before_each(function()
        KE = L.loadNicknames()
        nicks = KE.db.global.Nicknames
    end)

    it("rejects nil and empty import strings", function()
        local ok, msg = KE:ImportNicknames(nil)
        assert.is_false(ok)
        assert.equals("Import string is empty", msg)
        ok, msg = KE:ImportNicknames("")
        assert.is_false(ok)
        assert.equals("Import string is empty", msg)
    end)

    it("rejects a version-bumped prefix on an otherwise-valid payload", function()
        nicks["A-Realm"] = "a"
        local encoded = KE:ExportNicknames()
        local ok, msg = KE:ImportNicknames("!KEN2!" .. encoded:sub(7))
        assert.is_false(ok)
        assert.is_not_nil(msg:find("Invalid format", 1, true))
    end)

    it("rejects garbage at each real decode layer", function()
        -- decode layer: "@" is outside LibDeflate's EncodeForPrint alphabet
        local ok, msg = KE:ImportNicknames("!KEN1!@@@@")
        assert.is_false(ok)
        assert.equals("Failed to decode string", msg)
        -- decompress layer: printable-encoded but not a deflate stream
        local Deflate = LibStub("LibDeflate")
        ok, msg = KE:ImportNicknames("!KEN1!" .. Deflate:EncodeForPrint("not deflate"))
        assert.is_false(ok)
        assert.equals("Failed to decompress", msg)
        -- deserialize layer: valid deflate of a non-AceSerializer string
        ok, msg = KE:ImportNicknames("!KEN1!" ..
            Deflate:EncodeForPrint(Deflate:CompressDeflate("garbage")))
        assert.is_false(ok)
        assert.equals("Invalid export data", msg)
    end)

    it("rejects a well-formed serialization with the wrong shape", function()
        local Serializer = LibStub("AceSerializer-3.0")
        local Deflate = LibStub("LibDeflate")
        local serialized = Serializer:Serialize({ v = 1 }) -- no .d table
        local encoded = "!KEN1!" .. Deflate:EncodeForPrint(Deflate:CompressDeflate(serialized))
        local ok, msg = KE:ImportNicknames(encoded)
        assert.is_false(ok)
        assert.equals("Invalid export data", msg)
    end)

    it("errors when the nickname store is missing", function()
        nicks["A-Realm"] = "a"
        local encoded = KE:ExportNicknames()
        KE.db.global.Nicknames = nil
        local ok, msg = KE:ImportNicknames(encoded)
        assert.is_false(ok)
        assert.equals("Nicknames database not available", msg)
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

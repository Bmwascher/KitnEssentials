-- ╔══════════════════════════════════════════════════════════╗
-- ║  dev/spec/dm_source_substitution_spec.lua                ║
-- ║  Identity-substitution decision table for DM:GetSource.  ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- DM:GetSource is the single chokepoint every breakdown fetch passes through.
-- In combat the stashed row identity is secret, and the API it calls declares
-- SecretArguments = AllowedWhenUntainted -- so addon code may not hand it that
-- value. For the player's OWN row there is one legal substitute: a plain GUID
-- for the same unit. Every other case must REFUSE rather than guess.
--
-- WHY THIS EARNS A SPEC: it is a refusal rule wrapped around arithmetic-free
-- but branching argument rewriting, and three of its six rows fail silently.
-- A wrong substitution does not throw -- it fetches SOMEONE ELSE'S row and
-- renders it under your name. The two rows that refuse a bad substitute (a
-- secret UnitGUID, a nil UnitGUID) are the two the upstream reference gets
-- wrong, so nothing outside this file defends them.
--
-- The refusal SHAPE is load-bearing and is asserted here too: nil in the
-- first position, the reason in the second. Three of the five live call
-- sites never opt in and test the first return alone; a truthy marker there
-- would be written into the persisted history snapshot as if it were real
-- source data.
--
-- HONESTY BOUNDARY (see dev/README.md): secrecy is DECLARED by a closure over
-- a SECRET table, and C_DamageMeter is a recording stub. A pass verifies which
-- arguments the fetch RECEIVES, never real 12.0 taint semantics. In-game
-- /reload remains the secret-semantics gate.
local L = require("dev.spec._ke_loader")

local SECRET = {}     -- [value] = true  marks a value "secret"
local PLAYER_GUID     -- what UnitGUID("player") returns

local DM
local calls           -- every C_DamageMeter fetch, in order

local SECRET_GUID = { "secret guid" }
local SECRET_CID  = { "secret creature id" }
local TYPE, DMTYPE = "session-type", "meter-type"

before_each(function()
    for k in pairs(SECRET) do SECRET[k] = nil end
    SECRET[SECRET_GUID] = true
    SECRET[SECRET_CID] = true
    PLAYER_GUID = "Player-0000-PLAINGUID"
    calls = {}

    DM = L.loadDMCore({
        issecretvalue = function(v) return SECRET[v] == true end,
        UnitGUID = function() return PLAYER_GUID end,
    })
    assert(DM and DM.GetSource, "loadDMCore did not expose DM:GetSource")

    local function record(kind)
        return function(a, b, guid, cid)
            calls[#calls + 1] = { kind = kind, a = a, b = b, guid = guid, cid = cid }
            return { fetched = kind }
        end
    end
    _G.C_DamageMeter = {
        GetCombatSessionSourceFromType = record("type"),
        GetCombatSessionSourceFromID = record("id"),
    }
    -- The history branch is a different store, not the live API. Record it the
    -- same way so a substitution leaking into it would be visible.
    DM.HistorySource = function(_, sessionID, dmType, guid, cid)
        calls[#calls + 1] = { kind = "history", a = sessionID, b = dmType, guid = guid, cid = cid }
        return { fetched = "history" }
    end
end)

after_each(function() _G.C_DamageMeter = nil end)

local function lastCall()
    return calls[#calls]
end

describe("GetSource with a PLAIN identity -- row 1, pass through unchanged", function()
    it("passes a live type fetch through untouched, own row or not", function()
        for _, own in ipairs({ true, false }) do
            calls = {}
            local src = DM:GetSource(TYPE, DMTYPE, "guid-A", 77, nil, own)
            assert.are.same({ fetched = "type" }, src)
            assert.are.equal("guid-A", lastCall().guid)
            assert.are.equal(77, lastCall().cid)
        end
    end)

    it("passes a live id fetch through untouched", function()
        DM:GetSource(TYPE, DMTYPE, "guid-A", 77, 12, true)
        assert.are.equal("id", lastCall().kind)
        assert.are.equal("guid-A", lastCall().guid)
        assert.are.equal(77, lastCall().cid)
    end)

    it("passes a history fetch through untouched", function()
        local src = DM:GetSource(TYPE, DMTYPE, "guid-A", 77, -3, true)
        assert.are.same({ fetched = "history" }, src)
        assert.are.equal("history", lastCall().kind)
        assert.are.equal("guid-A", lastCall().guid)
        assert.are.equal(77, lastCall().cid)
    end)
end)

describe("GetSource with a SECRET identity", function()
    it("row 2 -- refuses a non-own row, and does not fetch", function()
        local src, why = DM:GetSource(TYPE, DMTYPE, SECRET_GUID, SECRET_CID, nil, false)
        assert.is_nil(src)
        assert.are.equal("refused", why)
        assert.are.equal(0, #calls)
    end)

    it("row 2 -- refuses when the own-row answer was never supplied", function()
        -- The three call sites that do not opt in pass nothing at all.
        local src, why = DM:GetSource(TYPE, DMTYPE, SECRET_GUID, SECRET_CID, nil)
        assert.is_nil(src)
        assert.are.equal("refused", why)
        assert.are.equal(0, #calls)
    end)

    it("row 3 -- refuses the own row on the HISTORY path", function()
        -- A stored snapshot must never be looked up with a live GUID: it would
        -- resolve a different row entirely.
        local src, why = DM:GetSource(TYPE, DMTYPE, SECRET_GUID, SECRET_CID, -3, true)
        assert.is_nil(src)
        assert.are.equal("refused", why)
        assert.are.equal(0, #calls)
    end)

    it("row 4 -- substitutes the plain player GUID with a NIL creature id", function()
        local src = DM:GetSource(TYPE, DMTYPE, SECRET_GUID, SECRET_CID, nil, true)
        assert.are.same({ fetched = "type" }, src)
        assert.are.equal(PLAYER_GUID, lastCall().guid)
        assert.is_nil(lastCall().cid)
    end)

    it("row 4 -- substitutes on the live id path too", function()
        DM:GetSource(TYPE, DMTYPE, SECRET_GUID, SECRET_CID, 12, true)
        assert.are.equal("id", lastCall().kind)
        assert.are.equal(PLAYER_GUID, lastCall().guid)
        assert.is_nil(lastCall().cid)
    end)

    it("row 5 -- refuses when the substitute is ITSELF secret", function()
        local secretSub = { "secret player guid" }
        SECRET[secretSub] = true
        PLAYER_GUID = secretSub
        local src, why = DM:GetSource(TYPE, DMTYPE, SECRET_GUID, SECRET_CID, nil, true)
        assert.is_nil(src)
        assert.are.equal("refused", why)
        assert.are.equal(0, #calls)
    end)

    it("row 6 -- refuses when the substitute comes back NIL", function()
        PLAYER_GUID = nil
        local src, why = DM:GetSource(TYPE, DMTYPE, SECRET_GUID, SECRET_CID, nil, true)
        assert.is_nil(src)
        assert.are.equal("refused", why)
        assert.are.equal(0, #calls)
    end)

    it("substitutes when only the CREATURE ID is secret", function()
        DM:GetSource(TYPE, DMTYPE, "guid-A", SECRET_CID, nil, true)
        assert.are.equal(PLAYER_GUID, lastCall().guid)
        assert.is_nil(lastCall().cid)
    end)

    it("treats a truthy non-boolean own-row answer as NOT the own row", function()
        -- The parameter is specified as a plain boolean. Anything else means a
        -- caller passed the raw field through instead of the resolved answer.
        local src, why = DM:GetSource(TYPE, DMTYPE, SECRET_GUID, SECRET_CID, nil, 1)
        assert.is_nil(src)
        assert.are.equal("refused", why)
    end)
end)

describe("GetSource refusal shape", function()
    it("returns nil FIRST so callers that ignore the reason still see no data", function()
        -- History.lua writes `if detail then` straight into the persisted
        -- snapshot. A truthy marker in the first position would be stored as
        -- if it were real source data.
        local src = DM:GetSource(TYPE, DMTYPE, SECRET_GUID, SECRET_CID, nil, false)
        assert.is_falsy(src)
    end)

    it("reports no reason on an ordinary empty result", function()
        -- "Refused" must stay distinguishable from "the API had nothing".
        _G.C_DamageMeter.GetCombatSessionSourceFromType = function() return nil end
        local src, why = DM:GetSource(TYPE, DMTYPE, "guid-A", 77, nil, true)
        assert.is_nil(src)
        assert.is_nil(why)
    end)
end)

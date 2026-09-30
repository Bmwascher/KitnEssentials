-- Tier 2: logic around the 12.0 secret/restriction API. Core/Secret.lua.
-- We drive the restriction state machine through real event transitions, which
-- in-game would require entering combat/M+/encounter to exercise. See the
-- HONESTY BOUNDARY block for what a mock can and cannot vouch for.
local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

describe("Secret.lua restriction state machine", function()
    local KE, frames, restrictionActive

    before_each(function()
        frames = mock.install()
        restrictionActive = {}
        _G.Enum = {
            AddOnRestrictionType = {
                Combat = 0, Encounter = 1, ChallengeMode = 2,
                PvPMatch = 3, Map = 4, Chat = 5,
            },
            AddOnRestrictionState = { Inactive = 0, Activating = 1, Active = 2 },
        }
        _G.C_RestrictedActions = {
            IsAddOnRestrictionActive = function(t) return restrictionActive[t] or false end,
        }
        KE = helpers.loadModule("Core/Secret.lua", { Print = function() end })
    end)

    after_each(function()
        _G.Enum = nil
        _G.C_RestrictedActions = nil
    end)

    it("starts unrestricted", function()
        assert.equals(0, KE:GetRestrictionState())
        assert.is_false(KE:IsFullyRestricted())
    end)

    it("enters FULL restriction on combat start", function()
        frames[1]:Fire("PLAYER_REGEN_DISABLED")
        assert.is_true(KE:IsFullyRestricted())
        assert.equals(2, KE:GetRestrictionState())
    end)

    it("clears restriction on combat end", function()
        frames[1]:Fire("PLAYER_REGEN_DISABLED")
        frames[1]:Fire("PLAYER_REGEN_ENABLED")
        assert.equals(0, KE:GetRestrictionState())
    end)

    it("defers a callback during combat and flushes it when combat ends", function()
        frames[1]:Fire("PLAYER_REGEN_DISABLED")
        local ran = false
        KE:DeferUntilUnrestricted(0, function() ran = true end)
        assert.is_false(ran) -- queued while restricted
        frames[1]:Fire("PLAYER_REGEN_ENABLED")
        assert.is_true(ran) -- queue flushed on release
    end)

    it("runs a deferred callback immediately when already unrestricted", function()
        local ran = false
        KE:DeferUntilUnrestricted(0, function() ran = true end)
        assert.is_true(ran)
    end)

    it("treats a Map restriction as partial", function()
        frames[1]:Fire("ADDON_RESTRICTION_STATE_CHANGED", 4, 2) -- Map, Active
        assert.equals(1, KE:GetRestrictionState())
        assert.is_true(KE:IsRestricted())
        assert.is_false(KE:IsFullyRestricted())
    end)

    it("treats Encounter, ChallengeMode and PvPMatch as full restriction", function()
        for _, restrictionType in ipairs({ 1, 2, 3 }) do
            frames[1]:Fire("ADDON_RESTRICTION_STATE_CHANGED", restrictionType, 2)
            assert.is_true(KE:IsFullyRestricted())
            frames[1]:Fire("ADDON_RESTRICTION_STATE_CHANGED", restrictionType, 0)
            assert.equals(0, KE:GetRestrictionState())
        end
    end)

    it("treats Activating as already restricted", function()
        frames[1]:Fire("ADDON_RESTRICTION_STATE_CHANGED", 1, 1) -- Encounter, Activating
        assert.is_true(KE:IsFullyRestricted())
    end)

    it("clears on Inactive rather than reading zero as restricted", function()
        frames[1]:Fire("ADDON_RESTRICTION_STATE_CHANGED", 2, 2) -- ChallengeMode, Active
        assert.is_true(KE:IsFullyRestricted())
        frames[1]:Fire("ADDON_RESTRICTION_STATE_CHANGED", 2, 0) -- ChallengeMode, Inactive
        assert.equals(0, KE:GetRestrictionState())
    end)

    it("seeds an already-active restriction on entering world", function()
        restrictionActive[2] = true -- ChallengeMode, e.g. a reload inside a keystone
        frames[1]:Fire("PLAYER_ENTERING_WORLD")
        assert.is_true(KE:IsFullyRestricted())
    end)

    it("flushes a deferred callback when the seeded restriction clears", function()
        restrictionActive[1] = true -- Encounter
        frames[1]:Fire("PLAYER_ENTERING_WORLD")
        local ran = false
        KE:DeferUntilUnrestricted(0, function() ran = true end)
        assert.is_false(ran)
        frames[1]:Fire("ADDON_RESTRICTION_STATE_CHANGED", 1, 0)
        assert.is_true(ran)
    end)

    -- The field case behind the party-action guard: a running key restricts
    -- between pulls while InCombatLockdown() answers false.
    it("refuses protected calls in a running key between pulls", function()
        frames[1]:Fire("ADDON_RESTRICTION_STATE_CHANGED", 2, 2) -- ChallengeMode, Active
        assert.is_false(KE:CanMakeProtectedCalls())
    end)
end)

describe("Secret.lua value guards — the HONESTY BOUNDARY", function()
    -- A mock guard test verifies KE's BRANCHING given a value WE declare secret,
    -- not real 12.0 secret semantics. Keep that distinction in mind: the result
    -- is only as true as the mock's fidelity.
    it("rejects a unit name only when the client marks it secret", function()
        mock.install({
            issecretvalue = function(v) return v == "SECRET_NAME" end,
            UnitName = function() return "SECRET_NAME" end,
        })
        local KE = helpers.loadModule("Core/Secret.lua", { Print = function() end })
        assert.is_nil(KE:GetSafeUnitName("target")) -- guard fires

        mock.install({ UnitName = function() return "Realname" end })
        KE = helpers.loadModule("Core/Secret.lua", { Print = function() end })
        assert.equals("Realname", KE:GetSafeUnitName("target")) -- passes through
    end)

    it("IsSafeValue rejects nil and secret, accepts plain values", function()
        local SECRET = {}
        mock.install({ issecretvalue = function(v) return v == SECRET end })
        local KE = helpers.loadModule("Core/Secret.lua", { Print = function() end })
        assert.is_false(KE:IsSafeValue(nil))
        assert.is_false(KE:IsSafeValue(SECRET))
        assert.is_true(KE:IsSafeValue("plain"))
        assert.is_true(KE:IsSafeValue(42))
    end)

    -- luacheck: globals it assert
    it("checks secrecy before deciding that nil is absent", function()
        local calls = 0
        mock.install()
        local KE = helpers.loadModule("Core/Secret.lua", { Print = function() end })
        KE.IsSecretValue = function()
            calls = calls + 1
            return false
        end

        assert.is_false(KE:IsSafeValue(nil))
        assert.equals(1, calls)
    end)
end)

-- AreAuraIdentitiesHidden gates every aura index scan KE runs, and the API it
-- guards HARD ERRORS rather than returning a secret, so a guard that silently
-- answers "not hidden" is indistinguishable from no guard at all. That is what
-- shipped once already: the previous version asked an API that does not exist,
-- and its nil-check turned the whole guard into `return false` forever.
--
-- HONESTY BOUNDARY: this drives the two predicates through values the test
-- declares. It pins KE's branching and the priority between the two sources.
-- It cannot vouch for when the client actually reports a restriction -- in
-- particular the combat-end instant, which is an in-game question.
describe("Secret.lua aura-restriction guard", function()
    local RESTRICTION_TYPES = {
        Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5,
    }

    -- opts.direct: what ShouldAurasBeSecret returns, or "absent", or "throws"
    -- opts.active: restriction type NAME currently active, if any
    -- opts.noEnum / opts.noRestrictionAPI: drop that half of the fallback
    local function loadWith(opts)
        mock.install()
        -- Explicit if, not `cond and nil or value`: that idiom cannot yield
        -- nil (the `or` swallows it) and silently kept the enum installed.
        if opts.noEnum then
            _G.Enum = nil
        else
            _G.Enum = { AddOnRestrictionType = RESTRICTION_TYPES }
        end
        if opts.direct == "absent" then
            _G.C_Secrets = nil
        elseif opts.direct == "throws" then
            _G.C_Secrets = { ShouldAurasBeSecret = function() error("no access") end }
        else
            _G.C_Secrets = { ShouldAurasBeSecret = function() return opts.direct end }
        end
        if opts.noRestrictionAPI then
            _G.C_RestrictedActions = nil
        else
            _G.C_RestrictedActions = {
                IsAddOnRestrictionActive = function(t)
                    return opts.active ~= nil and t == RESTRICTION_TYPES[opts.active]
                end,
            }
        end
        return helpers.loadModule("Core/Secret.lua", { Print = function() end })
    end

    it("reports hidden when the direct predicate says auras are secret", function()
        assert.is_true(loadWith({ direct = true }):AreAuraIdentitiesHidden())
    end)

    it("reports visible when the direct predicate says they are not", function()
        assert.is_false(loadWith({ direct = false }):AreAuraIdentitiesHidden())
    end)

    -- Conflicting signals resolve fail-closed. The direct predicate only
    -- forecasts whether queries generally return secrets; the hard error this
    -- guards comes from a separate access precondition, so a "no" from it is
    -- not permission, and an active restriction type hides auras on its own
    -- authority. Flip this to expect visible and the guard starts trusting a
    -- forecast over a stated restriction.
    it("stays hidden when a restriction is active despite a negative forecast", function()
        assert.is_true(loadWith({ direct = false, active = "Combat" }):AreAuraIdentitiesHidden())
    end)

    for _, kind in ipairs({ "Combat", "Encounter", "ChallengeMode", "PvPMatch" }) do
        it("falls back to the state list and reports hidden in " .. kind, function()
            assert.is_true(loadWith({ direct = "absent", active = kind }):AreAuraIdentitiesHidden())
        end)
    end

    it("reports visible on the fallback when no restriction is active", function()
        assert.is_false(loadWith({ direct = "absent" }):AreAuraIdentitiesHidden())
    end)

    -- Map and Chat restrict other subsystems. Treating them as aura secrecy
    -- would silently kill these features on every dungeon map.
    for _, kind in ipairs({ "Map", "Chat" }) do
        it("does not treat " .. kind .. " restriction as hidden auras", function()
            assert.is_false(loadWith({ direct = "absent", active = kind }):AreAuraIdentitiesHidden())
        end)
    end

    it("answers visible when the client offers neither predicate", function()
        local KE = loadWith({ direct = "absent", noEnum = true, noRestrictionAPI = true })
        assert.is_false(KE:AreAuraIdentitiesHidden())
    end)

    it("answers visible when the restriction API exists but the enum does not", function()
        local KE = loadWith({ direct = "absent", noEnum = true, active = "Combat" })
        assert.is_false(KE:AreAuraIdentitiesHidden())
    end)

    -- A throwing predicate must not take the caller down with it; the state
    -- list still gets its say.
    it("survives a throwing direct predicate and uses the fallback", function()
        assert.is_true(loadWith({ direct = "throws", active = "Encounter" }):AreAuraIdentitiesHidden())
    end)
end)

describe("Secret.lua UNIT_AURA payload gate", function()
    local function loadWith(secretSet)
        mock.install({
            issecretvalue = function(v) return secretSet[v] == "value" end,
            issecrettable = function(v) return secretSet[v] == "table" end,
        })
        return helpers.loadModule("Core/Secret.lua", { Print = function() end })
    end

    it("refuses a secret unit token", function()
        local unit = {}
        local KE = loadWith({ [unit] = "value" })
        assert.is_true(KE:IsUnreadableAuraPayload(unit, {}))
    end)

    it("refuses a secret outer table", function()
        local info = {}
        local KE = loadWith({ [info] = "table" })
        assert.is_true(KE:IsUnreadableAuraPayload("player", info))
    end)

    it("refuses an outer table that is itself a secret value", function()
        local info = {}
        local KE = loadWith({ [info] = "value" })
        assert.is_true(KE:IsUnreadableAuraPayload("player", info))
    end)

    it("refuses a secret isFullUpdate", function()
        local flag = {}
        local KE = loadWith({ [flag] = "value" })
        assert.is_true(KE:IsUnreadableAuraPayload("player", { isFullUpdate = flag }))
    end)

    for _, field in ipairs({ "addedAuras", "updatedAuraInstanceIDs",
                             "removedAuraInstanceIDs" }) do
        it("refuses a secret " .. field, function()
            local list = {}
            local KE = loadWith({ [list] = "table" })
            assert.is_true(KE:IsUnreadableAuraPayload("player", { [field] = list }))
        end)
    end

    for _, field in ipairs({ "addedAuras", "updatedAuraInstanceIDs",
                             "removedAuraInstanceIDs" }) do
        it("refuses a " .. field .. " that is itself a secret value", function()
            local list = {}
            local KE = loadWith({ [list] = "value" })
            assert.is_true(KE:IsUnreadableAuraPayload("player", { [field] = list }))
        end)
    end

    it("does not refuse a nil updateInfo", function()
        assert.is_false(loadWith({}):IsUnreadableAuraPayload("player", nil))
    end)

    it("does not refuse an ordinary readable payload", function()
        local KE = loadWith({})
        assert.is_false(KE:IsUnreadableAuraPayload("player", {
            isFullUpdate = false, addedAuras = {}, removedAuraInstanceIDs = {},
        }))
    end)
end)

describe("IsAuraHiddenForSpell", function()
    local function loadWith(secrets)
        mock.install()
        -- Decide the broad state through ShouldAurasBeSecret alone: with no
        -- Enum the module's restriction list is nil, so the second half of the
        -- fallback cannot answer and cannot leak in from an earlier block.
        _G.Enum = nil
        _G.C_RestrictedActions = nil
        _G.C_Secrets = secrets
        return helpers.loadModule("Core/Secret.lua", { Print = function() end })
    end

    local function answers(spellAnswer, broadAnswer)
        return {
            ShouldSpellAuraBeSecret = spellAnswer ~= nil
                and function() return spellAnswer end or nil,
            ShouldAurasBeSecret = function() return broadAnswer == true end,
        }
    end

    it("returns hidden when the exact predicate says hidden and the broad state does not", function()
        local KE = loadWith(answers(true, false))
        assert.is_true(KE:IsAuraHiddenForSpell(196099))
    end)

    it("returns visible when the exact predicate says visible and the broad state says hidden", function()
        local KE = loadWith(answers(false, true))
        assert.is_false(KE:IsAuraHiddenForSpell(196099))
    end)

    it("falls back to the broad state when the exact predicate is absent", function()
        local KE = loadWith(answers(nil, true))
        assert.is_true(KE:IsAuraHiddenForSpell(196099))
    end)

    it("falls back to the broad state when the exact predicate throws", function()
        local KE = loadWith({
            ShouldSpellAuraBeSecret = function() error("tainted") end,
            ShouldAurasBeSecret = function() return true end,
        })
        assert.is_true(KE:IsAuraHiddenForSpell(196099))
    end)

    it("falls back to the broad state when no identifier is given", function()
        local KE = loadWith(answers(false, true))
        assert.is_true(KE:IsAuraHiddenForSpell(nil))
    end)

    it("accepts a spell NAME as the identifier", function()
        local seen
        local KE = loadWith({
            ShouldSpellAuraBeSecret = function(id) seen = id return true end,
            ShouldAurasBeSecret = function() return false end,
        })
        assert.is_true(KE:IsAuraHiddenForSpell("Soulstone"))
        assert.are.equal("Soulstone", seen)
    end)
end)

-- KE:IsChatMessagingLocked gates every chat send KE makes.
--
-- HONESTY BOUNDARY: the mock declares what InChatMessagingLockdown answers and
-- which restriction events fire. This pins KE's branching over those sources;
-- it cannot vouch for when the client actually reports a chat lock.
describe("Secret.lua chat-messaging lock", function()
    local RESTRICTION_TYPES = {
        Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5,
    }
    local RESTRICTION_STATES = { Inactive = 0, Activating = 1, Active = 2 }

    -- opts.api: what InChatMessagingLockdown returns, or "absent"
    -- opts.noEnum: drop the restriction enum
    -- opts.seeded: restriction type NAME IsAddOnRestrictionActive reports
    local function loadWith(opts)
        local frames = mock.install()
        if opts.noEnum then
            _G.Enum = nil
        else
            _G.Enum = {
                AddOnRestrictionType = RESTRICTION_TYPES,
                AddOnRestrictionState = RESTRICTION_STATES,
            }
        end
        if opts.api == "absent" then
            _G.C_ChatInfo = nil
        else
            _G.C_ChatInfo = {
                InChatMessagingLockdown = function() return opts.api == true end,
            }
        end
        _G.C_RestrictedActions = {
            IsAddOnRestrictionActive = function(t)
                return opts.seeded ~= nil and t == RESTRICTION_TYPES[opts.seeded]
            end,
        }
        local KE = helpers.loadModule("Core/Secret.lua", { Print = function() end })
        return KE, frames
    end

    after_each(function()
        _G.Enum = nil
        _G.C_ChatInfo = nil
        _G.C_RestrictedActions = nil
    end)

    it("locks when any one chat-lock source is on", function()
        local rows = {
            { name = "API lockdown", opts = { api = true } },
            { name = "Chat restriction", opts = {}, fire = { 5, 2 } },
            { name = "ChallengeMode restriction", opts = {}, fire = { 2, 2 } },
            { name = "Encounter activating", opts = {}, fire = { 1, 1 } },
            { name = "ChallengeMode with no chat API", opts = { api = "absent" }, fire = { 2, 2 } },
            { name = "API lockdown with no restriction enum", opts = { api = true, noEnum = true } },
        }
        for _, row in ipairs(rows) do
            local KE, frames = loadWith(row.opts)
            if row.fire then
                frames[1]:Fire("ADDON_RESTRICTION_STATE_CHANGED", row.fire[1], row.fire[2])
            end
            assert.is_true(KE:IsChatMessagingLocked(), row.name)
        end
    end)

    -- Combat and PvPMatch are deliberately not sources: chat sends work in
    -- open-world combat, and nothing shows a PvP match refuses them.
    it("stays unlocked when no chat-lock source is on", function()
        local rows = {
            { name = "nothing", opts = {} },
            { name = "combat", opts = {}, combat = true },
            { name = "PvPMatch restriction", opts = {}, fire = { 3, 2 } },
            { name = "Map restriction", opts = {}, fire = { 4, 2 } },
            { name = "nothing with no chat API", opts = { api = "absent" } },
        }
        for _, row in ipairs(rows) do
            local KE, frames = loadWith(row.opts)
            if row.combat then frames[1]:Fire("PLAYER_REGEN_DISABLED") end
            if row.fire then
                frames[1]:Fire("ADDON_RESTRICTION_STATE_CHANGED", row.fire[1], row.fire[2])
            end
            assert.is_false(KE:IsChatMessagingLocked(), row.name)
        end
    end)

    it("unlocks when the tracked Chat restriction goes inactive", function()
        local KE, frames = loadWith({})
        frames[1]:Fire("ADDON_RESTRICTION_STATE_CHANGED", 5, 2) -- Chat, Active
        frames[1]:Fire("ADDON_RESTRICTION_STATE_CHANGED", 5, 0) -- Chat, Inactive
        assert.is_false(KE:IsChatMessagingLocked())
    end)

    -- Chat must not join the full-restriction set: that would change what
    -- every existing caller of the state is told.
    it("leaves the restriction state alone under a Chat restriction", function()
        local KE, frames = loadWith({})
        frames[1]:Fire("ADDON_RESTRICTION_STATE_CHANGED", 5, 2) -- Chat, Active
        assert.equals(0, KE:GetRestrictionState())
        assert.is_true(KE:CanMakeProtectedCalls())
    end)

    it("seeds an already-active Chat restriction on entering world", function()
        local KE, frames = loadWith({ seeded = "Chat" })
        frames[1]:Fire("PLAYER_ENTERING_WORLD")
        assert.is_true(KE:IsChatMessagingLocked())
    end)
end)

describe("Secret.lua restriction listener", function()
    local KE, frames

    before_each(function()
        frames = mock.install()
        _G.Enum = {
            AddOnRestrictionType = {
                Combat = 0, Encounter = 1, ChallengeMode = 2,
                PvPMatch = 3, Map = 4, Chat = 5,
            },
            AddOnRestrictionState = { Inactive = 0, Activating = 1, Active = 2 },
        }
        _G.C_RestrictedActions = {
            IsAddOnRestrictionActive = function() return false end,
        }
        KE = helpers.loadModule("Core/Secret.lua", { Print = function() end })
    end)

    after_each(function()
        _G.Enum = nil
        _G.C_RestrictedActions = nil
    end)

    it("runs on entering and on releasing, with the new state already written", function()
        local seen = {}
        KE:RegisterRestrictionListener(function(newState, oldState)
            seen[#seen + 1] = {
                newState, oldState, KE:GetRestrictionState(), KE:CanMakeProtectedCalls(),
            }
        end)
        frames[1]:Fire("ADDON_RESTRICTION_STATE_CHANGED", 2, 2) -- ChallengeMode, Active
        frames[1]:Fire("ADDON_RESTRICTION_STATE_CHANGED", 2, 0) -- ChallengeMode, Inactive
        assert.same({ { 2, 0, 2, false }, { 0, 2, 0, true } }, seen)
    end)

    it("does not run when the state does not change", function()
        local calls = 0
        KE:RegisterRestrictionListener(function() calls = calls + 1 end)
        frames[1]:Fire("ADDON_RESTRICTION_STATE_CHANGED", 5, 2) -- Chat alone
        assert.equals(0, calls)
        frames[1]:Fire("ADDON_RESTRICTION_STATE_CHANGED", 2, 2) -- ChallengeMode: one change
        frames[1]:Fire("ADDON_RESTRICTION_STATE_CHANGED", 1, 2) -- Encounter while already full
        assert.equals(1, calls)
    end)

    it("does not run an unregistered listener", function()
        local calls = 0
        local listener = function() calls = calls + 1 end
        KE:RegisterRestrictionListener(listener)
        KE:UnregisterRestrictionListener(listener)
        frames[1]:Fire("ADDON_RESTRICTION_STATE_CHANGED", 2, 2) -- ChallengeMode, Active
        assert.equals(0, calls)
    end)

    -- Raid Control attaches again while already attached: its post-combat
    -- replay runs the attach step after any roster change or layout it
    -- deferred in combat, so a repeat is ignored.
    it("runs a listener registered twice once per change", function()
        local calls = 0
        local listener = function() calls = calls + 1 end
        KE:RegisterRestrictionListener(listener)
        KE:RegisterRestrictionListener(listener)
        frames[1]:Fire("ADDON_RESTRICTION_STATE_CHANGED", 2, 2) -- ChallengeMode, Active
        assert.equals(1, calls)
    end)

    -- Walking the live list while a listener removes itself would shift the
    -- next one into the removed slot and skip it.
    it("still runs the next listener when one unregisters itself mid-dispatch", function()
        local selfCalls, nextCalls = 0, 0
        local selfRemoving
        selfRemoving = function()
            selfCalls = selfCalls + 1
            KE:UnregisterRestrictionListener(selfRemoving)
        end
        KE:RegisterRestrictionListener(selfRemoving)
        KE:RegisterRestrictionListener(function() nextCalls = nextCalls + 1 end)
        frames[1]:Fire("ADDON_RESTRICTION_STATE_CHANGED", 2, 2) -- ChallengeMode, Active
        assert.equals(1, nextCalls)
        frames[1]:Fire("ADDON_RESTRICTION_STATE_CHANGED", 2, 0) -- ChallengeMode, Inactive
        assert.equals(1, selfCalls)
        assert.equals(2, nextCalls)
    end)
end)

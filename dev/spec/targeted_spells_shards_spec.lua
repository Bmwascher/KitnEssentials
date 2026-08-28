-- Shard arithmetic, the relevance predicate, and the rescan that shares it.
-- The constants are read off the module rather than restated, so a change to
-- the token range or the slice width cannot leave these assertions agreeing
-- with a stale number.

local L = require("dev.spec._ke_loader")

-- UnitExists is a MANAGED mock key; UnitAffectingCombat and UnitCanAttack are
-- not, so they go to _G before the loader call or installMock drops them.
-- The cast-info pair is captured at file scope, so a test that reaches TryStart
-- needs them present before the load or it dies on a nil upvalue rather than
-- failing an assertion.
local function load(opts)
    opts = opts or {}
    _G.UnitAffectingCombat = opts.combat or function() return true end
    _G.UnitCanAttack = opts.canAttack or function() return true end
    _G.UnitCastingInfo = function() return nil end
    _G.UnitChannelInfo = function() return nil end
    return L.loadTargetedSpells({
        UnitExists = opts.exists or function() return true end,
    })
end

describe("TargetedSpells shard arithmetic", function()
    local TS, perShard, maxTokens

    before_each(function()
        TS = load()
        perShard, maxTokens = TS.UNITS_PER_SHARD, TS.MAX_NAMEPLATE_TOKENS
    end)

    it("puts the first token in the first shard", function()
        assert.are.equal("nameplate1", TS.ShardTokens(1, perShard, maxTokens)[1])
    end)

    it("straddles the first boundary at the slice width", function()
        local first = TS.ShardTokens(1, perShard, maxTokens)
        local second = TS.ShardTokens(2, perShard, maxTokens)
        assert.are.equal(perShard, #first)
        assert.are.equal("nameplate" .. perShard, first[perShard])
        assert.are.equal("nameplate" .. (perShard + 1), second[1])
    end)

    it("returns nil past the end of the range", function()
        local count = TS.ShardCount(perShard, maxTokens)
        assert.is_nil(TS.ShardTokens(count + 1, perShard, maxTokens))
    end)

    it("covers the whole range exactly once, with no gaps or repeats", function()
        local seen, total = {}, 0
        for i = 1, TS.ShardCount(perShard, maxTokens) do
            for _, token in ipairs(TS.ShardTokens(i, perShard, maxTokens)) do
                assert.is_nil(seen[token], "repeated token " .. token)
                seen[token] = true
                total = total + 1
            end
        end
        assert.are.equal(maxTokens, total)
        for i = 1, maxTokens do
            assert.is_true(seen["nameplate" .. i] == true, "missing nameplate" .. i)
        end
    end)

    it("gives the final shard the remainder", function()
        local count = TS.ShardCount(perShard, maxTokens)
        local remainder = maxTokens % perShard
        local expected = (remainder ~= 0) and remainder or perShard
        assert.are.equal(expected, #TS.ShardTokens(count, perShard, maxTokens))
    end)
end)

describe("TargetedSpells relevance predicate", function()
    it("accepts an in-combat attackable nameplate that exists", function()
        local TS = load()
        assert.is_truthy(TS.IsRelevantUnit("nameplate3"))
    end)

    it("rejects nil", function()
        local TS = load()
        assert.is_falsy(TS.IsRelevantUnit(nil))
    end)

    it("rejects a unit that is not in combat", function()
        local TS = load({ combat = function() return false end })
        assert.is_falsy(TS.IsRelevantUnit("nameplate3"))
    end)

    it("rejects a unit that does not exist", function()
        local TS = load({ exists = function() return false end })
        assert.is_falsy(TS.IsRelevantUnit("nameplate3"))
    end)

    it("rejects a unit the player cannot attack", function()
        local TS = load({ canAttack = function() return false end })
        assert.is_falsy(TS.IsRelevantUnit("nameplate3"))
    end)

    it("consults combat before either unit lookup and short-circuits", function()
        local existsCalls, attackCalls = 0, 0
        local TS = load({
            combat = function() return false end,
            exists = function() existsCalls = existsCalls + 1 return true end,
            canAttack = function() attackCalls = attackCalls + 1 return true end,
        })
        TS.IsRelevantUnit("nameplate3")
        assert.are.equal(0, existsCalls)
        assert.are.equal(0, attackCalls)
    end)
end)

describe("TargetedSpells shard frames", function()
    it("builds one frame per shard and is idempotent", function()
        local TS = load()
        local expected = TS.ShardCount(TS.UNITS_PER_SHARD, TS.MAX_NAMEPLATE_TOKENS)
        TS:CreateShards()
        assert.are.equal(expected, #TS.shards)
        TS:CreateShards()
        assert.are.equal(expected, #TS.shards)
    end)

    -- The shared mock routes RegisterEvent and RegisterUnitEvent into the same
    -- table and drops the unit arguments, so a plain "is it registered" check
    -- cannot tell the filtered call from the unfiltered one. Record per shard.
    it("registers every event through RegisterUnitEvent over its own tokens", function()
        local TS = load()
        TS:CreateShards()
        local recorded = {}
        for i, shard in ipairs(TS.shards) do
            recorded[i] = {}
            shard.RegisterEvent = function()
                error("shard used RegisterEvent instead of RegisterUnitEvent")
            end
            shard.RegisterUnitEvent = function(_, event, ...)
                recorded[i][event] = { ... }
            end
        end
        TS:RegisterShardEvents()

        for i, shard in ipairs(TS.shards) do
            for _, event in ipairs(TS.SHARD_EVENTS) do
                local units = recorded[i][event]
                assert.is_table(units, "shard " .. i .. " missing " .. event)
                assert.are.same(shard.tokens, units)
            end
        end
    end)
end)

describe("TargetedSpells shard dispatch", function()
    it("routes UNIT_TARGET to OnUnitTarget and the rest to OnCastEvent", function()
        local TS = load()
        local targets, casts = {}, {}
        TS.OnUnitTarget = function(_, _, unit) targets[#targets + 1] = unit end
        TS.OnCastEvent = function(_, event, unit)
            casts[#casts + 1] = { event = event, unit = unit }
        end

        TS.ShardOnEvent(nil, "UNIT_TARGET", "nameplate7")
        assert.are.same({ "nameplate7" }, targets)

        local expected = 0
        for _, event in ipairs(TS.SHARD_EVENTS) do
            if event ~= "UNIT_TARGET" then
                expected = expected + 1
                TS.ShardOnEvent(nil, event, "nameplate9")
                assert.are.equal(event, casts[expected].event)
                assert.are.equal("nameplate9", casts[expected].unit)
            end
        end
        assert.are.equal(7, expected)
        assert.are.equal(1, #targets)
    end)
end)

describe("TargetedSpells enable lifecycle", function()
    -- RebuildEntries and CheckContentGate stay REAL here. They are the call
    -- chain the defect lives in: with either stubbed, OnEnable's own closing
    -- CheckContentGate registers the shards and this passes with shard creation
    -- moved back after SyncStructure.
    local function enableModule()
        _G.IsInInstance = function() return true, "party" end
        _G.GetInstanceInfo = function() return "d", "party", 0 end
        _G.GetCVar = function() return "1" end
        local TS, KE = load()

        KE.db = { profile = {} }
        KE.GetFontPath = function() return "font" end
        KE.GetFontOutline = function() return "" end
        KE.ApplyFramePosition = function() end

        TS.IsEnabled = function() return true end
        TS.RegisterEvent = function() end
        TS.UnregisterEvent = function() end
        TS.UnregisterAllEvents = function() end
        TS.RegisterEditMode = function() end
        TS.CheckCVarPrompt = function() end
        TS.UpdateDB = function(self) self.db = self.db or {} end
        TS.db = {
            Enabled = true, IconSize = 32, Gap = 4, Grow = "DOWN",
            MaxIcons = 5, FontFace = "Expressway", FontSize = 12,
            FontOutline = "", Decimals = 1, ShowInDungeons = true,
        }

        local registered = 0
        local function countRegistrations()
            registered = 0
            for _, shard in ipairs(TS.shards) do
                shard.RegisterUnitEvent = function(s, e)
                    s._events[e] = true
                    registered = registered + 1
                end
            end
        end

        return TS, function() return registered end, countRegistrations
    end

    it("registers shards on enable, clears the gate on disable, and re-registers", function()
        local TS, count, arm = enableModule()

        TS:OnEnable()
        assert.is_true(#TS.shards > 0)
        assert.is_true(TS.contentActive)
        for _, shard in ipairs(TS.shards) do
            assert.is_true(shard:IsEventRegistered("UNIT_SPELLCAST_START"))
        end

        TS:OnDisable()
        assert.is_false(TS.contentActive)

        arm()
        TS:OnEnable()
        assert.is_true(count() > 0)
        assert.is_true(TS.contentActive)
    end)
end)

describe("TargetedSpells drain queue", function()
    local TS

    local function enqueue(unit, token, dueAt)
        local tail = TS.pendingTail + 1
        TS.pendingCasts[tail] = { unit = unit, token = token, dueAt = dueAt }
        TS.pendingTail = tail
    end

    before_each(function()
        TS = load()
        TS.pendingCasts, TS.pendingHead, TS.pendingTail = {}, 1, 0
        TS.drainScheduled, TS.drainEpoch = false, 0
    end)

    describe("FirstNotDue", function()
        it("returns head when nothing is due", function()
            enqueue("nameplate1", 1, 10)
            assert.are.equal(1, TS.FirstNotDue(TS.pendingCasts, 1, 1, 5))
        end)

        it("stops at the first entry not yet due", function()
            enqueue("nameplate1", 1, 1)
            enqueue("nameplate2", 1, 2)
            enqueue("nameplate3", 1, 9)
            assert.are.equal(3, TS.FirstNotDue(TS.pendingCasts, 1, 3, 5))
        end)

        it("returns past the tail when everything is due", function()
            enqueue("nameplate1", 1, 1)
            enqueue("nameplate2", 1, 2)
            assert.are.equal(3, TS.FirstNotDue(TS.pendingCasts, 1, 2, 5))
        end)
    end)

    it("schedules nothing for an empty queue", function()
        local scheduled = 0
        TS.ScheduleDrain = function() scheduled = scheduled + 1 end
        TS:DrainPendingCasts(0)
        assert.are.equal(0, scheduled)
        assert.are.equal(1, TS.pendingHead)
        assert.are.equal(0, TS.pendingTail)
    end)

    it("ignores a stale drain without touching the queue or the flag", function()
        enqueue("nameplate1", 1, 0)
        TS.drainScheduled = true
        local started = 0
        TS.TryStart = function() started = started + 1 end

        TS:DrainPendingCasts(TS.drainEpoch - 1)

        assert.are.equal(0, started)
        assert.are.equal(1, TS.pendingTail)
        assert.is_true(TS.drainScheduled)
    end)

    it("drains to empty in FIFO order and resets without rescheduling", function()
        enqueue("nameplate1", 11, 0)
        enqueue("nameplate2", 22, 0)
        local order, scheduled = {}, 0
        TS.TryStart = function(_, unit, token)
            order[#order + 1] = unit .. ":" .. token
        end
        TS.ScheduleDrain = function() scheduled = scheduled + 1 end

        TS:DrainPendingCasts(0)

        assert.are.same({ "nameplate1:11", "nameplate2:22" }, order)
        assert.are.equal(1, TS.pendingHead)
        assert.are.equal(0, TS.pendingTail)
        assert.are.equal(0, scheduled)
        assert.is_false(TS.drainScheduled)
    end)

    -- Delete the closing ScheduleDrain in DrainPendingCasts and only this case
    -- notices: everything else drains to empty, which takes the reset branch.
    it("reschedules when an entry is not yet due", function()
        enqueue("nameplate1", 11, 0)
        enqueue("nameplate2", 22, 99)
        local started = 0
        TS.TryStart = function() started = started + 1 end

        TS:DrainPendingCasts(0)

        assert.are.equal(1, started)
        assert.are.equal(2, TS.pendingHead)
        assert.are.equal(2, TS.pendingTail)
        assert.is_true(TS.drainScheduled)
    end)

    it("advances the epoch and empties on discard", function()
        enqueue("nameplate1", 1, 0)
        TS.drainScheduled = true
        local before = TS.drainEpoch

        TS:DiscardPendingCasts()

        assert.are.equal(before + 1, TS.drainEpoch)
        assert.are.equal(1, TS.pendingHead)
        assert.are.equal(0, TS.pendingTail)
        assert.is_false(TS.drainScheduled)
    end)

    it("leaves only the new drain scheduled across a gate cycle", function()
        enqueue("nameplate1", 1, 0)
        TS.drainScheduled = true
        local stale = TS.drainEpoch

        TS:DiscardPendingCasts()

        enqueue("nameplate2", 1, 99)
        TS.drainScheduled = true
        local started = 0
        TS.TryStart = function() started = started + 1 end

        TS:DrainPendingCasts(stale)

        assert.are.equal(0, started)
        assert.are.equal(1, TS.pendingTail)
        assert.is_true(TS.drainScheduled)
    end)

    -- The regression the combat gate would otherwise introduce. Asserted on the
    -- token rather than on a visible entry: TryStart builds frames the headless
    -- harness cannot supply, and stubbing it would hide the very defect.
    it("does not supersede a queued dispatch on a pre-combat retarget", function()
        local inCombat = false
        TS = load({ combat = function() return inCombat end })
        TS.pendingCasts, TS.pendingHead, TS.pendingTail = {}, 1, 0
        TS.drainScheduled, TS.drainEpoch = false, 0

        local queuedToken = TS:BumpDispatchToken("nameplate5")
        enqueue("nameplate5", queuedToken, 0)

        TS:OnUnitTarget(nil, "nameplate5")

        inCombat = true
        assert.are.equal(queuedToken, TS.pendingDispatch["nameplate5"])
    end)
end)

describe("TargetedSpells font cache", function()
    it("resolves both values from the current settings", function()
        local TS, KE = load()
        KE.GetFontPath = function(_, face) return "path/" .. face end
        KE.GetFontOutline = function(_, outline) return "OL/" .. outline end
        TS.db = { FontFace = "Expressway", FontOutline = "NONE" }

        TS:RefreshFontCache()

        assert.are.equal("path/Expressway", TS.cachedFontPath)
        assert.are.equal("OL/NONE", TS.cachedFontOutline)

        TS.db.FontFace = "Arial"
        TS:RefreshFontCache()
        assert.are.equal("path/Arial", TS.cachedFontPath)
    end)
end)

describe("TargetedSpells allocation shape", function()
    -- Neither is visible to a behavioural test. The scratch assertion is on the
    -- positive form on purpose: `local list = self.sortScratch` with no wipe
    -- satisfies an absence check while carrying the previous call's entries.
    local source

    setup(function()
        local f = assert(io.open("Modules/Dungeons/TargetedSpells.lua", "r"))
        source = f:read("*a")
        f:close()
    end)

    it("reuses the sort scratch table", function()
        assert.is_truthy(source:find("local list = wipe(self.sortScratch)", 1, true))
    end)

    it("refreshes the font cache from exactly one site", function()
        local sites = select(2, source:gsub("self:RefreshFontCache%(%)", ""))
        assert.are.equal(1, sites)
    end)

    it("builds no table and no closure in UpdateGlow", function()
        local body = source:match("function TS:UpdateGlow%(entry%)(.-)\nend\n")
        assert.is_string(body)
        assert.is_nil(body:find("ipairs({", 1, true))
        assert.is_nil(body:find("function(", 1, true))
    end)

    -- A missing ReleaseGlow in RebuildEntries is the frame leak, and this is the
    -- only automated check that sees it.
    it("parks on the reuse paths and retires only where the entry is discarded", function()
        assert.is_nil(source:find("StopGlow", 1, true))
        assert.are.equal(1, select(2, source:gsub("function TS:HideGlow", "")))
        assert.are.equal(1, select(2, source:gsub("function TS:ReleaseGlow", "")))
        assert.are.equal(4, select(2, source:gsub("self:HideGlow%(entry%)", "")))
        assert.are.equal(2, select(2, source:gsub("self:ReleaseGlow%(entry%)", "")))
    end)
end)

describe("TargetedSpells rescan", function()
    -- Drives the real ScanExistingNameplates. If it kept its own inline
    -- exists+attackable filter, the combat gate would be live on the event path
    -- and absent here, and nothing else in the suite would notice.
    it("dispatches nothing for a unit that is not in combat", function()
        local TS = load({ combat = function() return false end })
        local dispatched = {}
        TS.TryStart = function(_, unit) dispatched[#dispatched + 1] = unit end
        TS.BumpDispatchToken = function() return 1 end
        TS:ScanExistingNameplates()
        assert.are.equal(0, #dispatched)
    end)

    it("dispatches every token in the range when all are relevant", function()
        local TS = load()
        local dispatched = {}
        TS.TryStart = function(_, unit) dispatched[#dispatched + 1] = unit end
        TS.BumpDispatchToken = function() return 1 end
        TS:ScanExistingNameplates()
        assert.are.equal(TS.MAX_NAMEPLATE_TOKENS, #dispatched)
        assert.are.equal("nameplate1", dispatched[1])
        assert.are.equal("nameplate" .. TS.MAX_NAMEPLATE_TOKENS,
            dispatched[#dispatched])
    end)
end)

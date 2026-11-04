-- Tier: rules KE invented for the inspect talent panel (tiered test policy):
-- the open gate with the shared shown predicate, the node keep rule, the hero
-- subtree pick, the compare gate, the hero compare gate, the difference rule,
-- the chip order, the header line width, the window hooks installing once,
-- and the staged read's guards: the stage guard, the answer rule and the
-- read chain, run with a schedule the case pumps by hand. C_Traits reads,
-- layout, tooltips, timer delivery and event timing are smoke-tested, not
-- here.
--
-- The window hook case uses a stub frame that counts HookScript calls: the
-- rule is a call count across a disable and enable, and a predicate lifted
-- out of the latch would restate its one line.
local helpers = require("dev.spec._helpers")

-- A secret stand-in raises only when ordered against a number (< or >) or
-- compared with another secret. In Lua 5.1, == and ~= against a number,
-- true or nil do not reach __eq, so they do not raise; those rows assert
-- the outcome (a missed test gives another answer), and the order of the
-- test is checked by reading the diff and by the api-validator gate.
local SECRET_MT = { __eq = function() error("a secret value was compared") end }
local secrets = setmetatable({}, { __mode = "k" })
local function secret() local v = setmetatable({}, SECRET_MT); secrets[v] = true; return v end

-- Both files capture issecretvalue at load, so the stub goes in first. The
-- gate reads the shown state through InspectPanel's predicate, so that file
-- loads first under the same shim.
local function loadIT()
    local modules = helpers.installAddonShim()
    _G.issecretvalue = function(v) return secrets[v] == true end
    helpers.loadModule("Modules/Skinning/CharacterPanel/InspectPanel.lua", {})
    helpers.loadModule("Modules/Skinning/CharacterPanel/InspectTalents.lua", {})
    return modules["InspectTalents"]
end

local function window(shown) return { IsShown = function() return shown end } end

local function node(fields)
    local n = { isVisible = true, type = 0, posX = 3000, posY = 1500,
        ranksPurchased = 1, activeRank = 1, maxRanks = 1 }
    for k, v in pairs(fields or {}) do n[k] = v end
    return n
end

describe("Inspect talents: the open gate", function()
    it("draws only when the setting, the module, the window and the data all allow it", function()
        local gate = loadIT()._OpenGate
        local open = window(true)
        local cases = {
            { name = "setting off", setting = false, module = true, frame = open, wanted = true, valid = true, read = "ready", want = "hidden" },
            { name = "module down", setting = true, module = false, frame = open, wanted = true, valid = true, read = "ready", want = "hidden" },
            { name = "no frame", setting = true, module = true, wanted = true, valid = true, read = "ready", want = "hidden" },
            { name = "window hidden", setting = true, module = true, frame = window(false), wanted = true, valid = true, read = "ready", want = "hidden" },
            { name = "shown reads secret", setting = true, module = true, frame = window(secret()), wanted = true, valid = true, read = "ready", want = "hidden" },
            { name = "not requested shows the arrow only", setting = true, module = true, frame = open, wanted = false, valid = true, read = "ready", want = "closed" },
            { name = "data flag false", setting = true, module = true, frame = open, wanted = true, valid = false, read = "ready", want = "waiting" },
            { name = "data flag secret", setting = true, module = true, frame = open, wanted = true, valid = secret(), read = "ready", want = "waiting" },
            { name = "no inspect tree read", setting = true, module = true, frame = open, wanted = true, valid = true, want = "waiting" },
            { name = "a node read secret", setting = true, module = true, frame = open, wanted = true, valid = true, read = "secret", want = "unavailable" },
            { name = "no node kept", setting = true, module = true, frame = open, wanted = true, valid = true, read = "empty", want = "unavailable" },
            { name = "all clear", setting = true, module = true, frame = open, wanted = true, valid = true, read = "ready", want = "tree" },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.want, gate(c.setting, c.module, c.frame, c.wanted, c.valid, c.read), c.name)
        end
    end)
end)

describe("Inspect talents: the node keep rule", function()
    it("keeps visible tree nodes and refuses a secret field before any comparison", function()
        local keep = loadIT()._KeepNode
        local cases = {
            { name = "not a table", want = "skip" },
            { name = "invisible", info = node({ isVisible = false }), want = "skip" },
            { name = "subtree selection node", info = node({ type = 3 }), want = "skip" },
            { name = "above the tree", info = node({ posY = -300 }), want = "skip" },
            { name = "secret visibility", info = node({ isVisible = secret() }), want = "secret" },
            { name = "secret position", info = node({ posX = secret() }), want = "secret" },
            { name = "secret rank on a visible node", info = node({ ranksPurchased = secret() }), want = "secret" },
            { name = "secret rank on an invisible node: visibility is decided first", info = node({ isVisible = false, activeRank = secret() }), want = "skip" },
            { name = "secret active entry", info = node({ activeEntry = secret() }), want = "secret" },
            { name = "secret active entry id", info = node({ activeEntry = { entryID = secret() } }), want = "secret" },
            { name = "secret entry list", info = node({ entryIDs = secret() }), want = "secret" },
            { name = "secret id in the entry list", info = node({ entryIDs = { 101, secret() } }), want = "secret" },
            { name = "plain visible node", info = node({ activeEntry = { entryID = 101 }, entryIDs = { 101, 102 } }), want = "keep" },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.want, keep(c.info), c.name)
        end
    end)
end)

describe("Inspect talents: the hero subtree pick", function()
    it("prefers a flagged subtree, then an active one, then the most ranks, lower id on a tie", function()
        local pick = loadIT()._PickHeroSubTree
        local cases = {
            { name = "a flagged subtree wins over more ranks", list = { { id = 12, flagged = true, ranks = 0 }, { id = 11, ranks = 5 } }, want = 12 },
            { name = "two flagged give the lower id", list = { { id = 14, flagged = true }, { id = 12, flagged = true } }, want = 12 },
            { name = "info-active when none is flagged", list = { { id = 13, infoActive = true }, { id = 11, ranks = 9 } }, want = 13 },
            { name = "most ranks when neither", list = { { id = 11, ranks = 2 }, { id = 12, ranks = 7 } }, want = 12 },
            { name = "a ranks tie gives the lower id", list = { { id = 14, ranks = 5 }, { id = 12, ranks = 5 } }, want = 12 },
            { name = "an empty list", list = {}, want = nil },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.want, pick(c.list), c.name)
        end
    end)
end)

describe("Inspect talents: the compare gate", function()
    it("compares only when the setting is on and both plain spec ids match", function()
        local gate = loadIT()._CompareGate
        local cases = {
            { name = "setting off", setting = false, theirs = 253, yours = 253, want = "none" },
            { name = "their spec secret", setting = true, theirs = secret(), yours = 253, want = "unknown" },
            { name = "your spec missing", setting = true, theirs = 253, want = "unknown" },
            { name = "specs differ", setting = true, theirs = 253, yours = 254, want = "differs" },
            { name = "specs match", setting = true, theirs = 253, yours = 253, want = "on" },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.want, gate(c.setting, c.theirs, c.yours), c.name)
        end
    end)
end)

describe("Inspect talents: the difference rule", function()
    it("names who has a talent or that the pick or rank differs, and refuses secrets", function()
        local diff = loadIT()._DiffCategory
        local cases = {
            { name = "both untaken", te = 101, tr = 0, ye = 101, yr = 0, want = nil },
            { name = "theirs only", te = 101, tr = 1, yr = 0, want = "theirs" },
            { name = "yours only", tr = 0, ye = 101, yr = 2, want = "yours" },
            { name = "same entry and rank", te = 101, tr = 2, ye = 101, yr = 2, want = nil },
            { name = "same entry, different rank", te = 101, tr = 2, ye = 101, yr = 1, want = "different" },
            { name = "different entry on a choice node", te = 101, tr = 1, ye = 102, yr = 1, want = "different" },
            { name = "your rank secret, never compared", te = 101, tr = 1, ye = 101, yr = secret(), want = nil },
            { name = "your entry secret, never compared", te = 101, tr = 1, ye = secret(), yr = 1, want = nil },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.want, diff(c.te, c.tr, c.ye, c.yr), c.name)
        end
    end)
end)

describe("Inspect talents: the chip order", function()
    it("puts the largest rating first and keeps the stat order on a tie", function()
        local order = loadIT()._OrderChips
        local cases = {
            { name = "distinct ratings", values = { haste = 100, mastery = 900, crit = 500, vers = 300 }, want = "MAST CRIT VERS HASTE" },
            { name = "a tie keeps the stat order", values = { haste = 400, mastery = 200, crit = 400, vers = 400 }, want = "HASTE CRIT VERS MAST" },
            { name = "a missing rating reads as zero", values = { vers = 50 }, want = "VERS HASTE MAST CRIT" },
            { name = "all zero keeps the stat order", values = {}, want = "HASTE MAST CRIT VERS" },
        }
        for _, c in ipairs(cases) do
            local labels = {}
            for i, def in ipairs(order(c.values, {})) do labels[i] = def.label end
            assert.equals(c.want, table.concat(labels, " "), c.name)
        end
    end)
end)

describe("Inspect talents: the hero compare gate", function()
    it("compares your hero column only on an active signal and nothing against it", function()
        local gate = loadIT()._HeroCompareOn
        local cases = {
            { name = "a node flagged active", active = true, want = true },
            { name = "the subtree info says active", info = true, want = true },
            { name = "ranks alone, no active signal", want = false },
            { name = "a node flagged inactive or secret refuses, even with the info active", active = true, other = true, info = true, want = false },
            { name = "secret subtree info, no flag", info = secret(), want = false },
            { name = "secret subtree info with a flag", active = true, info = secret(), want = true },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.want, gate(c.active == true, c.other == true, c.info), c.name)
        end
    end)
end)

describe("Inspect talents: the window hooks", function()
    it("installs each window hook once across a disable and enable", function()
        _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
        local IT = loadIT()
        local count = {}
        _G.InspectFrame = {
            IsShown = function() return false end,
            HookScript = function(_, script) count[script] = (count[script] or 0) + 1 end,
        }
        IT:InstallWindow()
        IT:OnDisable()
        IT:InstallWindow()
        assert.same({ OnShow = 1, OnHide = 1 }, count)
    end)
end)

describe("Inspect talents: the header line width", function()
    it("measures the header line only when every width reads plain", function()
        local width = loadIT()._LineWidth
        local cases = {
            { name = "plain widths sum with a gap between pieces", widths = { 14, 60, 5 }, n = 3, want = 14 + 60 + 5 + 2 * 3 },
            { name = "no pieces", widths = {}, n = 0, want = 0 },
            { name = "a secret width, never added", widths = { 14, secret(), 5 }, n = 3, want = nil },
            { name = "a width that is not a number", widths = { 14, "60" }, n = 2, want = nil },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.want, width(c.widths, c.n, 3), c.name)
        end
    end)
end)

-- Stands in for the next-frame timer: schedule queues, pump runs what was
-- queued before it, as one frame would, and returns how many it ran.
local function manualSchedule()
    local due = {}
    local function schedule(fn) due[#due + 1] = fn end
    local function pump()
        local now = due
        due = {}
        for _, fn in ipairs(now) do fn() end
        return #now
    end
    return schedule, pump
end

describe("Inspect talents: the stage guard", function()
    it("runs a stage only for the live job, the module on, the window open, the job's player and no foreign answer", function()
        local allowed = loadIT()._StageAllowed
        local cases = {
            { name = "all matching", gen = 3, job = "Player-1", window = "Player-1", enabled = true, shown = true, foreign = false, want = true },
            { name = "stale generation", gen = 2, job = "Player-1", window = "Player-1", enabled = true, shown = true, foreign = false, want = false },
            { name = "window closed", gen = 3, job = "Player-1", window = "Player-1", enabled = true, shown = false, foreign = false, want = false },
            { name = "module disabled", gen = 3, job = "Player-1", window = "Player-1", enabled = false, shown = true, foreign = false, want = false },
            { name = "foreign answer pending", gen = 3, job = "Player-1", window = "Player-1", enabled = true, shown = true, foreign = true, want = false },
            { name = "another player in the window", gen = 3, job = "Player-1", window = "Player-2", enabled = true, shown = true, foreign = false, want = false },
            { name = "no readable GUID on either side: still reads", gen = 3, enabled = true, shown = true, foreign = false, want = true },
            { name = "the window's GUID became readable mid-read", gen = 3, window = "Player-1", enabled = true, shown = true, foreign = false, want = false },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.want, allowed(c.gen, 3, c.job, c.window, c.enabled, c.shown, c.foreign), c.name)
        end
    end)
end)

describe("Inspect talents: the answer rule", function()
    it("re-reads once only for the same player once the read is past its first stage", function()
        local action = loadIT()._ReadAction
        local cases = {
            { name = "no read running", running = false, index = 3, job = "Player-1", guid = "Player-1", want = "start" },
            { name = "first stage not run yet: joins the queued read", running = true, index = 1, job = "Player-1", guid = "Player-1", want = "start" },
            { name = "past the first stage, same player", running = true, index = 3, job = "Player-1", guid = "Player-1", want = "rerun" },
            { name = "past the first stage, another player", running = true, index = 3, job = "Player-1", guid = "Player-2", want = "start" },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.want, action(c.running, c.index, c.job, c.guid), c.name)
        end
    end)
end)

describe("Inspect talents: the read chain", function()
    it("reads as idle after a stage raises, and the next start runs", function()
        local queue, ran = {}, {}
        local chain = loadIT()._NewChain(function(fn) queue[#queue + 1] = fn end, function() return true end)
        local function step() table.remove(queue, 1)() end
        local stages = { function() end, function() error("stage failed") end }
        chain:Start(stages, "Player-1")
        step()
        assert.is_true(chain:Running(stages))
        assert.has_error(step)
        assert.is_false(chain:Running(stages))
        chain:Start({ function() ran[#ran + 1] = "again" end }, "Player-1")
        step()
        assert.same({ "again" }, ran)
    end)

    it("shares one queued call among starts, and a new job replaces the old one", function()
        local NewChain = loadIT()._NewChain
        local schedule, pump = manualSchedule()
        local ran = {}
        local function stage(tag) return function() ran[#ran + 1] = tag end end
        local chain = NewChain(schedule, function() return true end)
        local old = { stage("old1"), stage("old2"), stage("old3") }
        chain:Start(old, "Player-1")
        chain:Start(old, "Player-1")
        chain:Start(old, "Player-1")
        assert.equals(1, pump())
        assert.same({ "old1" }, ran)
        pump()
        chain:Start({ stage("new1"), stage("new2") }, "Player-1")
        for _ = 1, 10 do
            if pump() == 0 then break end
        end
        assert.same({ "old1", "old2", "new1", "new2" }, ran)
    end)

    it("runs the last stage once, after all the others, and never after an invalidate or a refusal", function()
        local NewChain = loadIT()._NewChain
        local cases = {
            { name = "straight through", want = { 1, 2, 3 } },
            { name = "invalidated after the second stage", invalidateAfter = 2, want = { 1, 2 } },
            { name = "refused at the second stage", refuseAt = 2, want = { 1 } },
        }
        for _, c in ipairs(cases) do
            local schedule, pump = manualSchedule()
            local ran, checks = {}, 0
            local chain = NewChain(schedule, function()
                checks = checks + 1
                return checks ~= c.refuseAt
            end)
            local stages = {}
            for i = 1, 3 do stages[i] = function() ran[#ran + 1] = i end end
            chain:Start(stages, "Player-1")
            local frames = 0
            while frames < 10 and pump() > 0 do
                frames = frames + 1
                if frames == c.invalidateAfter then chain:Invalidate() end
            end
            assert.same(c.want, ran, c.name)
        end
    end)
end)

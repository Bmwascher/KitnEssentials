-- Tier: rules KE invented for the inspect talent panel (tiered test policy):
-- the open gate with the shared shown predicate, the node keep rule, the hero
-- subtree pick, the compare gate, the hero compare gate, the difference rule
-- and the chip order. C_Traits reads, layout, tooltips and event timing are
-- smoke-tested, not here.
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

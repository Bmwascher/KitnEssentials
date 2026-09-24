-- Tier: guard logic KE invented for the inspect retry (tiered test policy):
-- which INSPECT_READY counts, the dirty-cache test, and the retry bound.
-- Event timing, tooltip data and rendering are smoke-tested, not here.
local helpers = require("dev.spec._helpers")

-- A comparison against a secret raises in the client. These stand-ins raise
-- when compared with each other: Lua 5.1 calls __eq only when both operands are
-- tables sharing the handler. `secret()` is reported secret; `probe()` shares
-- the handler but is not, so pairing one of each makes a missed secret check on
-- EITHER argument raise. A comparison with nil can never call __eq, so a `== nil`
-- test placed before the secret check cannot be made observable here; that
-- order is checked by reading the diff and by the api-validator gate.
local SECRET_MT = { __eq = function() error("a secret value was compared") end }
local secrets = setmetatable({}, { __mode = "k" })
local function secret() local v = setmetatable({}, SECRET_MT); secrets[v] = true; return v end
local function probe() return setmetatable({}, SECRET_MT) end

-- InspectPanel captures issecretvalue as a file-local at load, so the stub goes
-- in before loadModule.
local function loadIP()
    local modules = helpers.installAddonShim()
    _G.issecretvalue = function(v) return secrets[v] == true end
    helpers.loadModule("Modules/QoL/InspectPanel.lua", {})
    return modules["InspectPanel"]
end

describe("Inspect start: which INSPECT_READY counts", function()
    it("accepts only the inspect frame's own GUID", function()
        local ready = loadIP()._ReadyForFrame
        local cases = {
            { name = "the frame's own unit", guid = "Player-1", frame = "Player-1", want = true },
            { name = "another unit", guid = "Player-2", frame = "Player-1", want = false },
            { name = "a secret payload, refused before any comparison", guid = secret(), frame = probe(), want = false },
            { name = "a secret frame GUID, refused before any comparison", guid = probe(), frame = secret(), want = false },
            { name = "no readable frame GUID", guid = "Player-1", want = false },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.want, ready(c.guid, c.frame), c.name)
        end
    end)
end)

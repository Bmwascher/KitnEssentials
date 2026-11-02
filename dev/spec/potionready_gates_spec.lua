-- Which settings let the potion text show. The combat, instance and healer
-- reads that feed it are WoW calls and stay an in-game check.
local L = require("dev.spec._ke_loader")

describe("PotionReady gates", function()
    it("passes only when every gate that is on is met", function()
        local PR = L.loadPotionReady()
        local cases = {
            { name = "no gate on", db = {},
              inInstance = false, inCombat = false, isHealer = true, want = true },
            { name = "instances only, outside", db = { InstanceOnly = true },
              inInstance = false, inCombat = true, isHealer = false, want = false },
            { name = "instances only, inside", db = { InstanceOnly = true },
              inInstance = true, inCombat = false, isHealer = false, want = true },
            { name = "in combat only, out of combat", db = { CombatOnly = true },
              inInstance = true, inCombat = false, isHealer = false, want = false },
            { name = "in combat only, in combat", db = { CombatOnly = true },
              inInstance = false, inCombat = true, isHealer = false, want = true },
            { name = "hide for healers, as a healer", db = { DisableOnHealer = true },
              inInstance = true, inCombat = true, isHealer = true, want = false },
            { name = "hide for healers, not a healer", db = { DisableOnHealer = true },
              inInstance = false, inCombat = false, isHealer = false, want = true },
        }
        for _, c in ipairs(cases) do
            assert.are.equal(c.want,
                PR.PassesGates(c.db, c.inInstance, c.inCombat, c.isHealer), c.name)
        end
    end)
end)

describe("PotionReady display", function()
    it("shows the display and wants the stat only under its mode's rule", function()
        local PR = L.loadPotionReady()
        local base = {
            mode = "text", gates = true, held = true, ready = true, reckHeld = true,
            reckLeft = 0, onlyReady = false, statOn = true, specOn = true,
        }
        local cases = {
            { name = "text, ready, stat wanted", want = { true, true } },
            { name = "text, not ready", ready = false, reckLeft = 30, want = { false, false } },
            { name = "a failed gate hides the text", gates = false, want = { false, false } },
            { name = "a failed gate hides the icon", mode = "icon", gates = false, want = { false, false } },
            { name = "icon shows while held on cooldown", mode = "icon", ready = false, reckLeft = 30,
              want = { true, false } },
            { name = "only while ready hides the icon on cooldown", mode = "icon", ready = false,
              reckLeft = 5, onlyReady = true, want = { false, false } },
            { name = "icon stat from 10 s before ready", mode = "icon", ready = false, reckLeft = 10,
              want = { true, true } },
            { name = "no icon stat at 11 s", mode = "icon", ready = false, reckLeft = 11,
              want = { true, false } },
            { name = "nothing held", mode = "icon", held = false, ready = false, reckHeld = false,
              want = { false, false } },
            { name = "stat off", statOn = false, want = { true, false } },
            { name = "spec unticked", specOn = false, want = { true, false } },
            { name = "no Recklessness held", reckHeld = false, want = { true, false } },
            { name = "text needs Recklessness ready", reckLeft = 4, want = { true, false } },
        }
        for _, c in ipairs(cases) do
            local function pick(key)
                if c[key] ~= nil then return c[key] end
                return base[key]
            end
            local shown, stat = PR.ResolveDisplay(pick("mode"), pick("gates"), pick("held"),
                pick("ready"), pick("reckHeld"), pick("reckLeft"), pick("onlyReady"),
                pick("statOn"), pick("specOn"))
            assert.are.equal(c.want[1], shown, c.name .. ": shown")
            assert.are.equal(c.want[2], stat, c.name .. ": stat")
        end
    end)
end)

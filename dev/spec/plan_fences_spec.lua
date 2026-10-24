-- Fragment rule of the plan fence lint: anchor fences are skipped, and only
-- the fence right after one may fail to load without failing the run.
local PF = dofile("dev/scripts/_plan_fences.lua")

local BROKEN = 'color = "red",'

local function fence(code)
    return "```lua\n" .. code .. "\n```\n"
end

local function after_anchor(code)
    return "Replace this anchor:\n\n" .. fence("local a = 1") .. "\nwith:\n\n" .. fence(code)
end

describe("plan fence triage (dev/scripts/_plan_fences.lua)", function()
    it("skips an anchor fence even when its code does not load", function()
        for _, prose in ipairs({ "Replace this anchor:", "replace this anchor:", "insert after this anchor:" }) do
            local block = assert(PF.collect(prose .. "\n\n" .. fence(BROKEN)))[1]
            assert.equals("anchor", PF.triage(block), prose)
        end
    end)

    it("reports a fence after an anchor that does not load as a fragment", function()
        local block = assert(PF.collect(after_anchor(BROKEN)))[2]
        assert.equals("fragment", PF.triage(block))
    end)

    it("still lints a fence after an anchor when it loads", function()
        local block = assert(PF.collect(after_anchor("local b = 2")))[2]
        assert.equals("lint", PF.triage(block))
    end)

    it("reports a syntax error in a fence after no anchor, whatever its prose", function()
        local status, err = PF.triage(assert(PF.collect("with:\n\n" .. fence(BROKEN)))[1])
        assert.equals("syntax", status)
        assert.is_string(err)
    end)
end)

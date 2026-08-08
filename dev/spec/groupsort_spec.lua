local loader = require("dev.spec._ke_loader")

-- Same recipe dev/spec/_ke_loader.lua uses for its other module seams:
-- libSpecRegistered is a plain boolean local (not a table), so a read-only
-- upvalue handle can't drive it -- the RegisterLibSpec closure is reached
-- off GS.Run, then its own libSpecRegistered upvalue is written directly.
-- Both closures share the same variable, so writing through either one is
-- visible to the other.
local function findUpvalue(fn, name)
    local i = 1
    while true do
        local upName, upVal = debug.getupvalue(fn, i)
        if not upName then return nil end
        if upName == name then return upVal end
        i = i + 1
    end
end

local function setUpvalue(fn, name, value)
    local i = 1
    while true do
        local upName = debug.getupvalue(fn, i)
        if not upName then error("upvalue " .. name .. " not found") end
        if upName == name then
            debug.setupvalue(fn, i, value)
            return
        end
        i = i + 1
    end
end

describe("GroupSort", function()
    describe("Run gates", function()
        local function scheduled()
            local calls = {}
            return calls, { After = function(delay, fn) calls[#calls + 1] = { delay = delay, fn = fn } end }
        end

        it("refuses to run in combat", function()
            local calls, timer = scheduled()
            local GS, _, seams = loader.loadGroupSort({
                C_Timer = timer,
                InCombatLockdown = function() return true end,
            })
            GS:Run("default")
            assert.are.equal(0, #calls)
            assert.are.equal("Group Sort: not available in combat.", seams.prints[1])
        end)

        it("refuses to run under a chat messaging lockdown", function()
            local calls, timer = scheduled()
            local GS, _, seams = loader.loadGroupSort({
                C_Timer = timer,
                C_ChatInfo = { InChatMessagingLockdown = function() return true end },
            })
            GS:Run("default")
            assert.are.equal(0, #calls)
            assert.are.equal("Group Sort: addon messages are restricted right now; try again shortly.",
                seams.prints[1])
        end)

        it("refuses to run without lead or assist", function()
            local calls, timer = scheduled()
            local GS, _, seams = loader.loadGroupSort({ C_Timer = timer })
            GS:Run("default")
            assert.are.equal(0, #calls)
            assert.are.equal("Group Sort: requires raid lead or assist.", seams.prints[1])
        end)

        it("sorts immediately once spec data has been arriving", function()
            local calls, timer = scheduled()
            local GS = loader.loadGroupSort({
                C_Timer = timer,
                UnitIsGroupLeader = function() return true end,
                UnitInRaid = function() return 1 end,
            })
            local registerLibSpec = findUpvalue(GS.Run, "RegisterLibSpec")
            setUpvalue(registerLibSpec, "libSpecRegistered", true)
            local sorted
            GS.SortGroup = function(_, ...) sorted = { ... } end
            GS:Run("default")
            assert.is_not_nil(sorted)
            assert.are.equal(0, #calls)
        end)

        it("defers two seconds on a cold start", function()
            local calls, timer = scheduled()
            local GS = loader.loadGroupSort({
                C_Timer = timer,
                UnitIsGroupLeader = function() return true end,
                UnitInRaid = function() return 1 end,
            })
            local sorted
            GS.SortGroup = function(_, ...) sorted = { ... } end
            GS:Run("default")
            assert.is_nil(sorted)
            assert.are.equal(1, #calls)
            assert.are.equal(2, calls[1].delay)
        end)

        it("cancel clears a running sort and the run cooldown", function()
            local calls, timer = scheduled()
            local GS, _, seams = loader.loadGroupSort({
                C_Timer = timer,
                UnitIsGroupLeader = function() return true end,
                UnitInRaid = function() return 1 end,
            })
            -- GetTime() is pinned at 1000, so this Run stamps lastRun = 1000
            -- and (cold start) schedules the deferred sort rather than
            -- running it -- the timer call isn't invoked here.
            GS:Run("default")
            seams.groups.Processing = true
            seams.groups.ProcessStart = 1000
            GS:Cancel()
            assert.is_false(seams.groups.Processing)
            assert.is_nil(seams.groups.ProcessStart)
            -- lastRun cleared means the pinned clock's 5s cooldown check
            -- can't refuse this second call the way the cooldown test does.
            GS:Run("default")
            assert.are.equal(2, #calls)
        end)

        it("refuses to start while a sort is still in progress", function()
            local calls, timer = scheduled()
            local GS, _, seams = loader.loadGroupSort({
                C_Timer = timer,
                UnitIsGroupLeader = function() return true end,
                UnitInRaid = function() return 1 end,
            })
            -- GetTime() is pinned at 1000, so a start stamp of 1000 is inside
            -- the 15-second window.
            seams.groups.Processing = true
            seams.groups.ProcessStart = 1000
            GS:Run("default")
            assert.are.equal(0, #calls)
            assert.are.equal("Group Sort: a sort is still in progress, please wait.",
                seams.prints[1])
        end)

        it("enforces the five second cooldown between runs", function()
            local calls, timer = scheduled()
            local GS, _, seams = loader.loadGroupSort({
                C_Timer = timer,
                UnitIsGroupLeader = function() return true end,
                UnitInRaid = function() return 1 end,
            })
            GS:Run("default")
            GS:Run("default")
            assert.are.equal(1, #calls)
            assert.are.equal("Group Sort: please wait 5 seconds between sorts.", seams.prints[1])
        end)
    end)
end)

local loader = require("dev.spec._ke_loader")

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

        it("schedules the sort two seconds out for a raid leader", function()
            local calls, timer = scheduled()
            local GS, _, seams = loader.loadGroupSort({
                C_Timer = timer,
                UnitIsGroupLeader = function() return true end,
                UnitInRaid = function() return 1 end,
            })
            GS:Run("default")
            assert.are.equal(1, #calls)
            assert.are.equal(2, calls[1].delay)
            assert.are.equal(0, #seams.prints)
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

local loader = require("dev.spec._ke_loader")

describe("LFGReminder module", function()
    it("loads in the spec harness", function()
        local LR = loader.loadLFGReminder()
        assert.is_table(LR)
        assert.is_table(LR.db)
        assert.equals(1.05, LR.db.Scale)
    end)

    describe("teleport lookup", function()
        it("resolves an exact lowercase name", function()
            local _, _, seams = loader.loadLFGReminder()
            assert.equals(159898, seams.resolveByName("skyreach"))
        end)

        it("is case-insensitive", function()
            local _, _, seams = loader.loadLFGReminder()
            assert.equals(159898, seams.resolveByName("Skyreach"))
        end)

        it("strips a trailing difficulty suffix", function()
            local _, _, seams = loader.loadLFGReminder()
            assert.equals(393273, seams.resolveByName("Algeth'ar Academy (Mythic)"))
        end)

        it("returns nil for an unknown dungeon", function()
            local _, _, seams = loader.loadLFGReminder()
            assert.is_nil(seams.resolveByName("Not A Dungeon"))
        end)

        it("returns nil for a non-string", function()
            local _, _, seams = loader.loadLFGReminder()
            assert.is_nil(seams.resolveByName(42))
            assert.is_nil(seams.resolveByName(nil))
        end)
    end)

    describe("join handling", function()
        local function joinedWith(fullName, opts)
            opts = opts or {}
            local LR, _, seams = loader.loadLFGReminder({
                C_LFGList = {
                    -- 12.0.7's LfgSearchResultData carries activityIDs and NO
                    -- activityID (LFGListInfoDocumentation.lua:905-910), so the
                    -- DEFAULT stub uses the real shape and every join test below
                    -- exercises the live resolution branch. Override
                    -- opts.searchResult to pin the legacy field instead.
                    GetSearchResultInfo = function()
                        return opts.searchResult or { activityIDs = { 7 } }
                    end,
                    GetActivityInfoTable = function() return { fullName = fullName } end,
                },
                -- Loader-level knobs; the loader keeps returning a usable
                -- frame either way.
                inCombat      = opts.inCombat,
                inCombatFn    = opts.inCombatFn,
                onCreateFrame = opts.onCreateFrame,
                -- MUST be forwarded, not assigned to _G after the fact. The
                -- module captures both at file scope (`local IsInGroup =
                -- IsInGroup`), so a post-load `_G.IsInGroup = ...` never
                -- reaches it and the clearing branches become unreachable.
                -- Pass a closure over a mutable local to change the answer
                -- mid-test.
                IsInGroup     = opts.IsInGroup,
                IsInInstance  = opts.IsInInstance,
            })
            -- Returns seams too: the deferral tests assert on the named
            -- frames, not just on pending state.
            return LR, seams
        end

        it("resolves a known dungeon on join", function()
            local LR = joinedWith("Skyreach")
            LR:LFG_LIST_JOINED_GROUP(nil, 1)
            assert.equals(159898, LR:_GetPendingSpellID())
        end)

        it("still resolves through the legacy activityID field", function()
            local LR = joinedWith("Skyreach", { searchResult = { activityID = 7 } })
            LR:LFG_LIST_JOINED_GROUP(nil, 1)
            assert.equals(159898, LR:_GetPendingSpellID())
        end)

        it("ignores a dungeon with no known teleport", function()
            local LR = joinedWith("Some Raid")
            LR:LFG_LIST_JOINED_GROUP(nil, 1)
            assert.is_nil(LR:_GetPendingSpellID())
        end)

        it("strips the difficulty suffix from the displayed name", function()
            local LR = joinedWith("Skyreach (Mythic)")
            LR:LFG_LIST_JOINED_GROUP(nil, 1)
            assert.equals("Skyreach", LR:_GetPendingName())
        end)

        it("survives a search result that throws", function()
            local LR = loader.loadLFGReminder({
                C_LFGList = {
                    GetSearchResultInfo = function() error("secret") end,
                    GetActivityInfoTable = function() return nil end,
                },
            })
            assert.has_no.errors(function() LR:LFG_LIST_JOINED_GROUP(nil, 1) end)
            assert.is_nil(LR:_GetPendingSpellID())
        end)

        it("clears pending state when the group breaks up", function()
            local inGroup = true
            local LR = joinedWith("Skyreach", {
                IsInGroup = function() return inGroup end,
            })
            LR:LFG_LIST_JOINED_GROUP(nil, 1)
            assert.equals(159898, LR:_GetPendingSpellID())
            inGroup = false
            LR:GROUP_ROSTER_UPDATE()
            assert.is_nil(LR:_GetPendingSpellID())
        end)

        it("clears pending state on entering the dungeon", function()
            local inst = { false, "none" }
            local LR = joinedWith("Skyreach", {
                IsInInstance = function() return inst[1], inst[2] end,
            })
            LR:LFG_LIST_JOINED_GROUP(nil, 1)
            inst = { true, "party" }
            LR:CheckInstance()
            assert.is_nil(LR:_GetPendingSpellID())
        end)

        it("does not clear pending state in a raid instance", function()
            local inst = { false, "none" }
            local LR = joinedWith("Skyreach", {
                IsInInstance = function() return inst[1], inst[2] end,
            })
            LR:LFG_LIST_JOINED_GROUP(nil, 1)
            inst = { true, "raid" }
            LR:CheckInstance()
            assert.equals(159898, LR:_GetPendingSpellID())
        end)

        -- Regression for the deviation-7 fix, covering BOTH halves: a join
        -- during combat must not build the popup (BuildPopup writes a secure
        -- attribute), and combat ending must actually build and show it.
        it("defers a join in combat, then builds it when combat ends", function()
            local inCombat, builds = true, 0
            local LR, seams = joinedWith("Skyreach", {
                inCombatFn    = function() return inCombat end,
                onCreateFrame = function() builds = builds + 1 end,
            })
            LR:LFG_LIST_JOINED_GROUP(nil, 1)
            assert.equals(159898, LR:_GetPendingSpellID())
            assert.equals(0, builds)      -- nothing built during combat
            inCombat = false
            LR:PLAYER_REGEN_ENABLED()
            assert.is_true(builds > 0)    -- built once combat ended
            -- Assert the OUTCOME, not just that a build happened. Without
            -- these two, deleting PLAYER_REGEN_ENABLED's attribute-flush
            -- block or its show block leaves every spec passing.
            local popup = seams.frames["KE_LFGReminderPopup"]
            local btn   = seams.frames["KE_LFGReminderTeleport"]
            assert.is_true(popup:IsShown())
            assert.equals(159898, btn:GetAttribute("spell"))
        end)

        -- A join cancelled during combat must not arm the button later.
        -- This asserts on the DEFERRED ATTRIBUTE, not pendingSpellID:
        -- pendingSpellID is cleared by the pre-existing ClearPending lines,
        -- so asserting on it would pass even without the fix this test
        -- exists to protect.
        it("does not arm the button when a combat join is cancelled", function()
            local inCombat, inGroup = true, true
            local LR = joinedWith("Skyreach", {
                inCombatFn = function() return inCombat end,
                IsInGroup  = function() return inGroup end,
            })
            LR:LFG_LIST_JOINED_GROUP(nil, 1)
            assert.equals(159898, LR:_GetPendingAttrSpellID())  -- armed for later
            inGroup = false
            LR:GROUP_ROSTER_UPDATE()      -- group breaks while still in combat
            assert.is_nil(LR:_GetPendingAttrSpellID())          -- cancelled
            inCombat = false
            LR:PLAYER_REGEN_ENABLED()
            assert.is_nil(LR:_GetPendingSpellID())
        end)

        -- Disable in combat, then re-enable before combat ends, with no new
        -- join. The queued teardown must still hide and disarm the old
        -- popup: a predicate testing only IsEnabled() would keep it.
        -- Asserts on the FRAMES, not on pending state. OnDisable clears
        -- pendingSpellID before queuing, so a pending-state assertion would
        -- pass under the old `not LR:IsEnabled()` predicate too — the exact
        -- false gate this test exists to avoid.
        it("hides and disarms a stranded popup when re-enabled with no new join", function()
            local inCombat = false
            local LR, _, seams = loader.loadLFGReminder({
                inCombatFn = function() return inCombat end,
                C_LFGList = {
                    GetSearchResultInfo = function() return { activityID = 7 } end,
                    GetActivityInfoTable = function() return { fullName = "Skyreach" } end,
                },
            })
            -- Stays enabled throughout: this is the re-enabled-before-combat-
            -- ends case, which is what makes the old predicate keep the popup.
            LR.IsEnabled = function() return true end
            LR:LFG_LIST_JOINED_GROUP(nil, 1)   -- out of combat: popup shows
            local popup = seams.frames["KE_LFGReminderPopup"]
            local btn   = seams.frames["KE_LFGReminderTeleport"]
            assert.is_true(popup:IsShown())
            assert.equals(159898, btn:GetAttribute("spell"))
            inCombat = true
            LR:OnDisable()                     -- queues the teardown
            inCombat = false
            seams.runCombatQueue()             -- combat ends
            assert.is_false(popup:IsShown())
            assert.is_nil(btn:GetAttribute("spell"))
        end)
    end)
end)

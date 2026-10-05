-- The fixture dungeons resolve through the loader's map fixture and the
-- module's map table. These tests are about join handling and cooldown
-- refusal, not about the table.
local loader = require("dev.spec._ke_loader")

describe("LFGReminder module", function()
    describe("teleport lookup", function()
        it("resolves a listing name to its teleport, clean name and map", function()
            local LR = loader.loadLFGReminder()
            local cases = {
                { name = "suffix stripped", full = "Kings' Rest (Mythic)", spell = 1286831, clean = "Kings' Rest", map = 249 },
                { name = "unknown dungeon", full = "Not A Dungeon" },
                { name = "not a string",    full = 42 },
            }
            for _, c in ipairs(cases) do
                local spell, clean, map = LR._ResolveGroupFinderPortal(c.full)
                assert.equals(c.spell, spell, c.name)
                assert.equals(c.clean, clean, c.name)
                assert.equals(c.map, map, c.name)
            end
        end)
    end)

    describe("join handling", function()
        local function joinedWith(fullName, opts)
            opts = opts or {}
            local LR, _, seams = loader.loadLFGReminder({
                C_LFGList = {
                    -- 12.0.7's LfgSearchResultData carries activityIDs and NO
                    -- activityID (LFGListInfoDocumentation.lua), so the
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
            local LR = joinedWith("Murder Row")
            LR:LFG_LIST_JOINED_GROUP(nil, 1)
            assert.equals(1286809, LR:_GetPendingSpellID())
        end)

        it("still resolves through the legacy activityID field", function()
            local LR = joinedWith("Murder Row", { searchResult = { activityID = 7 } })
            LR:LFG_LIST_JOINED_GROUP(nil, 1)
            assert.equals(1286809, LR:_GetPendingSpellID())
        end)

        it("ignores a dungeon with no known teleport", function()
            local LR = joinedWith("Some Raid")
            LR:LFG_LIST_JOINED_GROUP(nil, 1)
            assert.is_nil(LR:_GetPendingSpellID())
        end)

        it("strips the difficulty suffix from the displayed name", function()
            local LR = joinedWith("Murder Row (Mythic)")
            LR:LFG_LIST_JOINED_GROUP(nil, 1)
            assert.equals("Murder Row", LR:_GetPendingName())
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
            local LR = joinedWith("Murder Row", {
                IsInGroup = function() return inGroup end,
            })
            LR:LFG_LIST_JOINED_GROUP(nil, 1)
            assert.equals(1286809, LR:_GetPendingSpellID())
            inGroup = false
            LR:GROUP_ROSTER_UPDATE()
            assert.is_nil(LR:_GetPendingSpellID())
        end)

        it("clears pending state on entering the dungeon", function()
            local inst = { false, "none" }
            local LR = joinedWith("Murder Row", {
                IsInInstance = function() return inst[1], inst[2] end,
            })
            LR:LFG_LIST_JOINED_GROUP(nil, 1)
            inst = { true, "party" }
            LR:CheckInstance()
            assert.is_nil(LR:_GetPendingSpellID())
        end)

        it("does not clear pending state in a raid instance", function()
            local inst = { false, "none" }
            local LR = joinedWith("Murder Row", {
                IsInInstance = function() return inst[1], inst[2] end,
            })
            LR:LFG_LIST_JOINED_GROUP(nil, 1)
            inst = { true, "raid" }
            LR:CheckInstance()
            assert.equals(1286809, LR:_GetPendingSpellID())
        end)

        -- Regression for the deviation-7 fix, covering BOTH halves: a join
        -- during combat must not build the popup (BuildPopup writes a secure
        -- attribute), and combat ending must actually build and show it.
        it("defers a join in combat, then builds it when combat ends", function()
            local inCombat, builds = true, 0
            local LR, seams = joinedWith("Murder Row", {
                inCombatFn    = function() return inCombat end,
                onCreateFrame = function() builds = builds + 1 end,
            })
            LR:LFG_LIST_JOINED_GROUP(nil, 1)
            assert.equals(1286809, LR:_GetPendingSpellID())
            assert.equals(0, builds)      -- nothing built during combat
            inCombat = false
            LR:PLAYER_REGEN_ENABLED()
            assert.is_true(builds > 0)    -- built once combat ended
            -- Assert the OUTCOME, not just that a build happened: without
            -- these two, a show that builds but never arms or shows the
            -- popup leaves every spec passing.
            local popup = seams.frames["KE_LFGReminderPopup"]
            local btn   = seams.frames["KE_LFGReminderTeleport"]
            assert.is_true(popup:IsShown())
            assert.equals(1286809, btn:GetAttribute("spell"))
        end)

        -- A join canceled during combat must not build or arm the button
        -- when combat ends. Nothing was built before the join, so any
        -- secure button here would be one PLAYER_REGEN_ENABLED made for the
        -- canceled dungeon.
        it("does not arm the button when a combat join is canceled", function()
            local inCombat, inGroup = true, true
            local LR, seams = joinedWith("Murder Row", {
                inCombatFn = function() return inCombat end,
                IsInGroup  = function() return inGroup end,
            })
            LR:LFG_LIST_JOINED_GROUP(nil, 1)
            inGroup = false
            LR:GROUP_ROSTER_UPDATE()      -- group breaks while still in combat
            inCombat = false
            LR:PLAYER_REGEN_ENABLED()
            assert.is_nil(seams.frames["KE_LFGReminderTeleport"])
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
                    GetActivityInfoTable = function() return { fullName = "Murder Row" } end,
                },
            })
            -- Stays enabled throughout: this is the re-enabled-before-combat-
            -- ends case, which is what makes the old predicate keep the popup.
            LR.IsEnabled = function() return true end
            LR:LFG_LIST_JOINED_GROUP(nil, 1)   -- out of combat: popup shows
            local popup = seams.frames["KE_LFGReminderPopup"]
            local btn   = seams.frames["KE_LFGReminderTeleport"]
            assert.is_true(popup:IsShown())
            assert.equals(1286809, btn:GetAttribute("spell"))
            inCombat = true
            LR:OnDisable()                     -- queues the teardown
            inCombat = false
            seams.runCombatQueue()             -- combat ends
            assert.is_false(popup:IsShown())
            assert.is_nil(btn:GetAttribute("spell"))
        end)

        -- LFG_LIST_JOINED_GROUP only fires for someone who applied, so the
        -- leader's prompt comes from the game's listing-full event, for the
        -- dungeon their own listing last read as. The game may clear the
        -- entry before the event, and chat lockdown can make it unreadable;
        -- both keep the remembered dungeon. A full raid listing reports the
        -- same event and never prompts.
        it("prompts the leader for the last readable listing when it fills, never in a raid", function()
            for _, c in ipairs({
                { name = "party, entry gone",                  raid = false, last = "gone",       want = 1286809 },
                { name = "raid, entry gone",                   raid = true,  last = "gone",       want = nil },
                { name = "party, entry unreadable",            raid = false, last = "unreadable", want = 1286809 },
                { name = "party, relisted with no teleport",   raid = false, last = "other",      want = nil },
            }) do
                local entry = "readable"
                local LR = loader.loadLFGReminder({
                    C_LFGList = {
                        GetActiveEntryInfo = function()
                            if entry == "gone" then return nil end
                            return { activityID = entry == "other" and 8 or 7 }
                        end,
                        GetActivityInfoTable = function(id)
                            if entry == "unreadable" then return nil end
                            return { fullName = id == 8 and "Not A Dungeon" or "Murder Row" }
                        end,
                    },
                    IsInRaid = function() return c.raid end,
                })
                LR:LFG_LIST_ACTIVE_ENTRY_UPDATE()
                entry = c.last
                LR:LFG_LIST_ACTIVE_ENTRY_UPDATE()
                LR:LFG_LIST_ENTRY_EXPIRED_TOO_MANY_PLAYERS()
                assert.equals(c.want, LR:_GetPendingSpellID(), c.name)
            end
        end)

        it("refuses to open the prompt while the teleport is on cooldown", function()
            local LR, seams = joinedWith("Murder Row")
            LR:LFG_LIST_JOINED_GROUP(nil, 1)
            assert.equals(1286809, LR:_GetPendingSpellID())
            local popup = seams.frames["KE_LFGReminderPopup"]
            popup:Hide()
            _G.C_Spell.GetSpellCooldown = function()
                return { isActive = true, isOnGCD = false, duration = 300 }
            end
            seams.showPrompt()
            assert.is_false(popup:IsShown())
        end)
    end)
end)

describe("LFGReminder preview", function()
    -- The preview draws Ruby Life Pools' teleport from the live map table, so
    -- a data update that drops the map fails here.
    it("draws the teleport the live table gives its dungeon", function()
        local asked
        local LR = loader.loadLFGReminder({
            C_Spell = {
                GetSpellInfo = function(id) asked = id; return nil end,
                GetSpellCooldown = function() return nil end,
                GetSpellCooldownDuration = function() return nil end,
            },
        })
        LR.IsEnabled = function() return true end
        LR:ShowPreview()
        local want = LR._PickOwnPortal(399, function() return true end)
        assert.is_not_nil(want)
        assert.equals(want, asked)
    end)
end)

describe("LFGReminder combat re-show", function()
    -- Lockdown has not begun when PLAYER_REGEN_DISABLED fires, so the hide
    -- lands at once and the end of combat must show the live prompt again.
    -- The preview left the button disarmed, so that show must also arm it.
    it("re-shows a live prompt combat hid, armed, when combat ends", function()
        local LR, _, seams = loader.loadLFGReminder({
            C_LFGList = {
                GetSearchResultInfo = function() return { activityIDs = { 7 } } end,
                GetActivityInfoTable = function() return { fullName = "Murder Row" } end,
            },
        })
        LR.IsEnabled = function() return true end
        LR:LFG_LIST_JOINED_GROUP(nil, 1)
        LR:ShowPreview()
        local popup = seams.frames["KE_LFGReminderPopup"]
        local btn   = seams.frames["KE_LFGReminderTeleport"]
        LR:PLAYER_REGEN_DISABLED()
        LR:HidePreview()  -- the settings window closes as combat starts
        assert.is_false(popup:IsShown())
        LR:PLAYER_REGEN_ENABLED()
        assert.is_true(popup:IsShown())
        assert.equals(1286809, btn:GetAttribute("spell"))
    end)
end)

describe("LFGReminder close with X", function()
    -- X ends the prompt: a preview opened and closed afterward must not
    -- bring it back.
    it("keeps a prompt closed with X closed through a preview", function()
        local LR, _, seams = loader.loadLFGReminder({
            C_LFGList = {
                GetSearchResultInfo = function() return { activityIDs = { 7 } } end,
                GetActivityInfoTable = function() return { fullName = "Murder Row" } end,
            },
        })
        LR.IsEnabled = function() return true end
        LR:LFG_LIST_JOINED_GROUP(nil, 1)
        local popup = seams.frames["KE_LFGReminderPopup"]
        local btn   = seams.frames["KE_LFGReminderTeleport"]
        LR._ClosePrompt()
        LR:ShowPreview()
        LR:HidePreview()
        assert.is_false(popup:IsShown())
        assert.is_nil(btn:GetAttribute("spell"))
    end)

    -- X on the preview popup also ends the preview's hold; otherwise the next
    -- join would wait behind a preview that is no longer on screen.
    it("lets the next join show after X closes the preview", function()
        local LR, _, seams = loader.loadLFGReminder({
            C_LFGList = {
                GetSearchResultInfo = function() return { activityIDs = { 7 } } end,
                GetActivityInfoTable = function() return { fullName = "Murder Row" } end,
            },
        })
        LR.IsEnabled = function() return true end
        LR:LFG_LIST_JOINED_GROUP(nil, 1)
        LR:ShowPreview()
        LR._ClosePrompt()
        LR:LFG_LIST_JOINED_GROUP(nil, 2)
        assert.is_true(seams.frames["KE_LFGReminderPopup"]:IsShown())
        assert.equals(1286809, seams.frames["KE_LFGReminderTeleport"]:GetAttribute("spell"))
    end)
end)

describe("LFGReminder preview hold", function()
    -- While the settings preview is up it owns the popup and the button stays
    -- unarmed; a show of the live prompt waits until the preview closes.
    -- Combat models the order in game: the settings window closes as combat
    -- starts and reopens, showing the preview, before this module's handler
    -- runs at combat end.
    it("keeps the preview unarmed until it closes, then restores the armed prompt", function()
        local LR, _, seams = loader.loadLFGReminder({
            C_LFGList = {
                GetSearchResultInfo = function() return { activityIDs = { 7 } } end,
                GetActivityInfoTable = function() return { fullName = "Murder Row" } end,
            },
        })
        LR.IsEnabled = function() return true end
        LR:LFG_LIST_JOINED_GROUP(nil, 1)
        LR:ShowPreview()
        local popup = seams.frames["KE_LFGReminderPopup"]
        local btn   = seams.frames["KE_LFGReminderTeleport"]
        LR:PLAYER_REGEN_DISABLED()
        LR:HidePreview()
        LR:ShowPreview()
        LR:PLAYER_REGEN_ENABLED()
        assert.is_true(popup:IsShown())
        assert.is_nil(btn:GetAttribute("spell"))
        LR:HidePreview()
        assert.is_true(popup:IsShown())
        assert.equals(1286809, btn:GetAttribute("spell"))
    end)
end)

describe("LFGReminder preview against later events", function()
    local function loadJoinable(opts)
        local LR, _, seams = loader.loadLFGReminder({
            inCombatFn = opts and opts.inCombatFn,
            C_LFGList = {
                GetSearchResultInfo = function() return { activityIDs = { 7 } } end,
                GetActivityInfoTable = function() return { fullName = "Murder Row" } end,
            },
        })
        LR.IsEnabled = function() return true end
        return LR, seams
    end

    -- A join that lands in combat is shown at combat end; the settings window
    -- can reopen its preview first, and nothing may arm that preview.
    it("keeps a reopened preview unarmed when a combat join is shown", function()
        local inCombat = false
        local LR, seams = loadJoinable({ inCombatFn = function() return inCombat end })
        LR:OnEnable()
        inCombat = true
        LR:LFG_LIST_JOINED_GROUP(nil, 1)
        inCombat = false
        LR:ShowPreview()
        LR:PLAYER_REGEN_ENABLED()
        assert.is_true(seams.frames["KE_LFGReminderPopup"]:IsShown())
        assert.is_nil(seams.frames["KE_LFGReminderTeleport"]:GetAttribute("spell"))
    end)

    -- A hide meant for the live prompt must not take the preview away while
    -- the settings page still shows it; the dropped prompt stays dropped.
    it("keeps the preview shown when the live teleport goes on cooldown", function()
        local LR, seams = loadJoinable()
        LR:LFG_LIST_JOINED_GROUP(nil, 1)
        LR:ShowPreview()
        local popup = seams.frames["KE_LFGReminderPopup"]
        _G.C_Spell.GetSpellCooldown = function()
            return { isActive = true, isOnGCD = false, duration = 300 }
        end
        LR:SPELL_UPDATE_COOLDOWN()
        assert.is_true(popup:IsShown())
        LR:HidePreview()
        assert.is_false(popup:IsShown())
        assert.is_nil(seams.frames["KE_LFGReminderTeleport"]:GetAttribute("spell"))
    end)
end)


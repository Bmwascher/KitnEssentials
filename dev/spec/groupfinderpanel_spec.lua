-- `dev.spec.` is the path form busted resolves from the repo root, and it is
-- what all 26 sibling specs use. `spec._ke_loader` does not load.
local loader = require("dev.spec._ke_loader")

describe("GroupFinderPanel pure helpers", function()
    describe("Abbreviate", function()
        local abbrev
        before_each(function()
            local _, _, seams = loader.loadGroupFinderPanel()
            abbrev = seams.abbreviate
        end)

        it("prefers the override table", function()
            assert.equals("WS", abbrev("Windrunner Spire"))
        end)

        it("takes initials of a plain multi-word name", function()
            assert.equals("TD", abbrev("Test Dungeon"))
        end)

        it("drops of/the/and", function()
            assert.equals("HF", abbrev("Halls of the Fallen"))
        end)

        it("splits on hyphens", function()
            assert.equals("BRD", abbrev("Black-Rock Depths"))
        end)

        it("splits on apostrophes", function()
            -- The apostrophe is a word boundary in the gmatch pattern, so
            -- "Kael'thas" is two words ("Kael", "thas"), not one -- initials
            -- are K, T, C, not K, C.
            assert.equals("KTC", abbrev("Kael'thas Citadel"))
        end)

        it("falls back to four uppercased characters when the initials are too short", function()
            -- One word, no stop word: initials give "D", which is under the
            -- two-character floor, so the fallback takes the first four
            -- characters uppercased.
            assert.equals("DEEP", abbrev("Deep"))
        end)
    end)

    describe("GetPartyRoles", function()
        it("counts the player's spec role when solo", function()
            local _, _, seams = loader.loadGroupFinderPanel({
                IsInGroup = function() return false end,
            })
            local roles = seams.getPartyRoles()
            assert.equals(1, roles.DAMAGER)
            assert.equals(0, roles.TANK)
        end)

        it("falls back to the spec role when assigned is NONE in a group", function()
            local _, _, seams = loader.loadGroupFinderPanel({
                IsInGroup = function() return true end,
                GetNumGroupMembers = function() return 1 end,
                UnitGroupRolesAssigned = function() return "NONE" end,
            })
            assert.equals(1, seams.getPartyRoles().DAMAGER)
        end)
    end)

    describe("PlayerSpecRole", function()
        it("returns nil rather than calling a deprecated global when the API is absent", function()
            local _, _, seams = loader.loadGroupFinderPanel({
                C_SpecializationInfo = {},
            })
            assert.is_nil(seams.playerSpecRole())
        end)
    end)
end)

describe("GroupFinderPanel SanitizeScore", function()
    it("fails CLOSED on a secret score", function()
        local GFP = loader.loadGroupFinderPanel({
            issecretvalue = function(v) return v == 2500 end,
        })
        _G.C_LFGList.GetSearchResultInfo = function()
            return { leaderOverallDungeonScore = 2500 }
        end
        assert.is_nil(GFP._SanitizeScore(1))
    end)

    it("returns nil for a zero score", function()
        local GFP = loader.loadGroupFinderPanel()
        _G.C_LFGList.GetSearchResultInfo = function()
            return { leaderOverallDungeonScore = 0 }
        end
        assert.is_nil(GFP._SanitizeScore(1))
    end)

    it("returns the score when readable and non-zero", function()
        local GFP = loader.loadGroupFinderPanel()
        _G.C_LFGList.GetSearchResultInfo = function()
            return { leaderOverallDungeonScore = 1800 }
        end
        assert.equals(1800, GFP._SanitizeScore(1))
    end)
end)

describe("GroupFinderPanel lifecycle", function()
    it("is inactive when PGF is loaded, even with Enabled true", function()
        local GFP = loader.loadGroupFinderPanel({
            C_AddOns = { IsAddOnLoaded = function(n) return n == "PremadeGroupsFilter" end },
        })
        GFP.db.Enabled = true
        assert.is_true(GFP._PGFPresent())
        assert.is_false(GFP._IsActive())
    end)

    it("is inactive when disabled, even without PGF", function()
        local GFP = loader.loadGroupFinderPanel()
        GFP.db.Enabled = false
        assert.is_false(GFP._IsActive())
    end)

    it("is active when enabled and PGF is absent", function()
        local GFP = loader.loadGroupFinderPanel()
        GFP.db.Enabled = true
        assert.is_true(GFP._IsActive())
    end)

    it("takes the FIRST IsAddOnLoaded return, not the second", function()
        -- loadedOrLoading true, loaded false: a conflict bail must still fire.
        local GFP = loader.loadGroupFinderPanel({
            C_AddOns = { IsAddOnLoaded = function() return true, false end },
        })
        assert.is_true(GFP._PGFPresent())
    end)

    it("carries the session keys across an enabled-to-enabled switch", function()
        local GFP, KE = loader.loadGroupFinderPanel()
        GFP.db.Enabled = true
        GFP.db.MinScore = 2500
        GFP.db.HasTank = true
        GFP.db.DungeonFilter[7] = true
        local incoming = { Enabled = true, DungeonFilter = { [99] = true }, MinScore = 0,
                           HasTank = false, HasHealer = false, PartyFit = false }
        KE.db.profile.GroupFinderPanel = incoming
        GFP:UpdateDB()
        assert.equals(2500, GFP.db.MinScore)
        assert.is_true(GFP.db.HasTank)
        assert.is_true(GFP.db.DungeonFilter[7])
        assert.is_nil(GFP.db.DungeonFilter[99])
    end)

    it("COPIES DungeonFilter rather than aliasing it", function()
        local GFP, KE = loader.loadGroupFinderPanel()
        GFP.db.Enabled = true
        GFP.db.DungeonFilter[7] = true
        local old = GFP.db
        KE.db.profile.GroupFinderPanel = { Enabled = true, DungeonFilter = {} }
        GFP:UpdateDB()
        assert.is_false(rawequal(old.DungeonFilter, GFP.db.DungeonFilter))
        GFP.db.DungeonFilter[8] = true
        assert.is_nil(old.DungeonFilter[8])
    end)

    it("does not carry state when the incoming profile has the module off", function()
        local GFP, KE = loader.loadGroupFinderPanel()
        GFP.db.Enabled = true
        GFP.db.HasTank = true
        KE.db.profile.GroupFinderPanel = { Enabled = false, DungeonFilter = {}, HasTank = false }
        GFP:UpdateDB()
        assert.is_false(GFP.db.HasTank)
    end)
end)

-- The advanced-filter mapping and the rules around when a search fires.
-- `saved` is the LAST table handed to SaveAdvancedFilter; `adv` is the table
-- GetAdvancedFilter returns, so a test can seed fields the module does not
-- expose and check they survive.
local function loadWithFilter(opts)
    opts = opts or {}
    local state = { saved = nil, searches = 0, categories = {}, cancels = 0,
                    now = 0, panelShown = opts.panelShown ~= false }
    state.adv = opts.adv or {}
    local GFP, KE, seams = loader.loadGroupFinderPanel({
        -- A clock the test drives, so the search window can expire.
        GetTime = function() return state.now end,
        -- Captures the timer the slider arms instead of running it, so a
        -- test decides when -- and whether -- the callback fires.
        C_Timer = {
            After = function() end,
            NewTicker = function() return { Cancel = function() end } end,
            NewTimer = function(_, fn)
                state.timerFn = fn
                return { Cancel = function() state.cancels = state.cancels + 1 end }
            end,
        },
        C_LFGList = {
            GetAvailableActivityGroups = function() return {} end,
            GetActivityGroupInfo = function() return nil end,
            GetAdvancedFilter = function()
                if opts.nilFilter then return nil end
                return state.adv
            end,
            SaveAdvancedFilter = function(f) state.saved = f end,
            Search = function() state.searches = state.searches + 1 end,
            GetLanguageSearchFilter = function() return nil end,
        },
        C_AddOns = { IsAddOnLoaded = function() return opts.pgf == true end },
        IsInGroup = opts.IsInGroup,
        GetNumGroupMembers = opts.GetNumGroupMembers,
        UnitGroupRolesAssigned = opts.UnitGroupRolesAssigned,
    })
    -- IsDungeonSearchMode reads all four of these; RunSearch needs the panel
    -- shown and a categoryID.
    _G.LFGListPVEStub = {}
    _G.PVEFrame = { activeTabIndex = 1 }
    _G.GroupFinderFrame = { selection = _G.LFGListPVEStub }
    _G.LFGListFrame = {
        baseFilters = 0,
        SearchPanel = {
            categoryID = 2,
            filters = 0,
            IsShown = function() return state.panelShown end,
        },
    }
    _G.LFGListSearchPanel_SetCategory = function(_, categoryID)
        state.categories[#state.categories + 1] = categoryID
    end
    -- AceEvent/AceAddon lifecycle methods are deliberately unstubbed by the
    -- loader, and OnDisable/OnEnable call into them.
    GFP.UnregisterAllEvents = function() end
    GFP.RegisterEvent = function() end
    GFP.SetEnabledState = function() end
    GFP.IsEnabled = function() return GFP.db.Enabled == true end
    GFP.db.Enabled = opts.pgf and false or true
    return GFP, KE, state, seams
end

describe("GroupFinderPanel advanced filter mapping", function()
    it("maps the presence toggles exactly", function()
        local GFP, _, state = loadWithFilter()
        GFP.db.HasTank, GFP.db.HasHealer = true, false
        GFP:ApplyAdvancedFilters()
        assert.is_true(state.saved.hasTank)
        assert.is_false(state.saved.hasHealer)
    end)

    it("clears every needs flag when party fit is off", function()
        local GFP, _, state = loadWithFilter()
        GFP.db.PartyFit = false
        GFP:ApplyAdvancedFilters()
        assert.is_false(state.saved.needsTank)
        assert.is_false(state.saved.needsHealer)
        assert.is_false(state.saved.needsDamage)
    end)

    it("asks for an opening for each role type the party brings", function()
        local GFP, _, state = loadWithFilter({
            IsInGroup = function() return true end,
            GetNumGroupMembers = function() return 2 end,
            UnitGroupRolesAssigned = function(unit)
                return unit == "player" and "HEALER" or "DAMAGER"
            end,
        })
        GFP.db.PartyFit = true
        GFP:ApplyAdvancedFilters()
        assert.is_false(state.saved.needsTank)
        assert.is_true(state.saved.needsHealer)
        assert.is_true(state.saved.needsDamage)
    end)

    it("sends an EMPTY activities list when no dungeon is selected", function()
        -- Blizzard's own "all". Building the season plus expansion list by
        -- hand instead omits the timerunning groups Blizzard adds.
        local GFP, _, state = loadWithFilter()
        GFP.db.DungeonFilter = {}
        GFP:ApplyAdvancedFilters()
        assert.equals(0, #state.saved.activities)
    end)

    it("sends the selected activity group IDs", function()
        local GFP, _, state = loadWithFilter()
        GFP.db.DungeonFilter = { [7] = true, [9] = false }
        GFP:ApplyAdvancedFilters()
        assert.equals(1, #state.saved.activities)
        assert.equals(7, state.saved.activities[1])
    end)

    it("carries the minimum score", function()
        local GFP, _, state = loadWithFilter()
        GFP.db.MinScore = 2500
        GFP:ApplyAdvancedFilters()
        assert.equals(2500, state.saved.minimumRating)
    end)

    it("PRESERVES the fields the module does not expose", function()
        local GFP, _, state = loadWithFilter({
            adv = { needsMyClass = true, playstyle = 3 },
        })
        GFP:ApplyAdvancedFilters()
        assert.is_true(state.saved.needsMyClass)
        assert.equals(3, state.saved.playstyle)
    end)

    it("writes nothing while the module is inactive", function()
        local GFP, _, state = loadWithFilter()
        GFP.db.Enabled = false
        GFP:ApplyAdvancedFilters()
        assert.is_nil(state.saved)
    end)

    it("does NOT claim ownership when the filter structure is unavailable", function()
        -- Ownership follows the write. A flag set with no write behind it
        -- would make the restore clobber a filter we never touched.
        local GFP, KE, state = loadWithFilter({ nilFilter = true })
        GFP:ApplyAdvancedFilters()
        assert.is_nil(state.saved)
        assert.is_falsy(KE.db.global.GroupFinderPanelOwnsFilter)
    end)

    it("claims ownership on a successful write", function()
        local GFP, KE = loadWithFilter()
        GFP:ApplyAdvancedFilters()
        assert.is_true(KE.db.global.GroupFinderPanelOwnsFilter)
    end)
end)

describe("GroupFinderPanel search rules", function()
    it("saves BEFORE it searches, so no search can send stale settings", function()
        local GFP, _, state = loadWithFilter()
        local order = {}
        local realSave = _G.C_LFGList.SaveAdvancedFilter
        _G.C_LFGList.SaveAdvancedFilter = function(f)
            order[#order + 1] = "save"; realSave(f)
        end
        _G.C_LFGList.Search = function()
            order[#order + 1] = "search"; state.searches = state.searches + 1
        end
        GFP:ApplyAndRefresh()
        assert.same({ "save", "search" }, order)
    end)

    it("searches on the first toggle click of a session", function()
        local GFP, _, state = loadWithFilter()
        GFP:ApplyAndRefresh()
        assert.equals(1, state.searches)
    end)

    it("saves but does NOT search on a second toggle inside the window", function()
        local GFP, _, state = loadWithFilter()
        GFP:ApplyAndRefresh()
        state.saved = nil
        GFP:ApplyAndRefresh()
        assert.is_not_nil(state.saved)
        assert.equals(1, state.searches)
    end)

    it("the Search button's action escapes the window", function()
        -- ManualSearch is the whole body of the button's OnClick, so routing
        -- it through the gated path fails here. The one-line handler that
        -- calls it is a GUI closure and is smoke's job.
        local GFP, _, state = loadWithFilter()
        GFP:ApplyAndRefresh()
        assert.equals(1, state.searches)
        GFP:ManualSearch()
        assert.equals(2, state.searches)
    end)

    it("the Search button's action saves BEFORE it searches", function()
        local GFP, _, state = loadWithFilter()
        local order = {}
        _G.C_LFGList.SaveAdvancedFilter = function(f)
            order[#order + 1] = "save"; state.saved = f
        end
        _G.C_LFGList.Search = function()
            order[#order + 1] = "search"; state.searches = state.searches + 1
        end
        GFP:ManualSearch()
        assert.same({ "save", "search" }, order)
    end)

    it("the Search button's action is inert while the module is inactive", function()
        local GFP, _, state = loadWithFilter()
        GFP.db.Enabled = false
        GFP:ManualSearch()
        assert.is_nil(state.saved)
        assert.equals(0, state.searches)
    end)

    it("a toggle searches again once the window EXPIRES", function()
        -- Without the clock this could not tell a ten-second window from a
        -- gate that closes permanently after the first search.
        local GFP, _, state = loadWithFilter()
        GFP:ApplyAndRefresh()
        assert.equals(1, state.searches)
        state.now = 9
        GFP:ApplyAndRefresh()
        assert.equals(1, state.searches)
        state.now = 11
        GFP:ApplyAndRefresh()
        assert.equals(2, state.searches)
    end)

    it("never searches while the module is inactive", function()
        local GFP, _, state = loadWithFilter()
        GFP.db.Enabled = false
        GFP:ApplyAndRefresh()
        assert.equals(0, state.searches)
    end)

    it("does not search when the search panel is not shown", function()
        local GFP, _, state = loadWithFilter({ panelShown = false })
        GFP:RunSearch()
        assert.equals(0, state.searches)
    end)
end)

describe("GroupFinderPanel filter ownership", function()
    local PERMISSIVE = {
        hasTank = false, hasHealer = false,
        needsTank = false, needsHealer = false, needsDamage = false,
        minimumRating = 0,
    }
    local function assertPermissive(saved)
        for k, v in pairs(PERMISSIVE) do assert.equals(v, saved[k]) end
        assert.equals(0, #saved.activities)
    end

    it("restores permissive on disable and gives ownership back", function()
        local GFP, KE, state = loadWithFilter()
        GFP.db.MinScore = 2500
        GFP:ApplyAdvancedFilters()
        state.saved = nil
        GFP:OnDisable()
        assertPermissive(state.saved)
        assert.is_false(KE.db.global.GroupFinderPanelOwnsFilter)
    end)

    it("leaves the filter ALONE on disable when the module never wrote it", function()
        -- The flag is what stops the restore destroying a filter set in
        -- Blizzard's own UI, or by another addon.
        local GFP, _, state = loadWithFilter()
        GFP:OnDisable()
        assert.is_nil(state.saved)
    end)

    it("restores at OnInitialize when this session will not enable the module", function()
        local GFP, KE, state = loadWithFilter()
        GFP:ApplyAdvancedFilters()
        state.saved = nil
        KE.db.profile.GroupFinderPanel.Enabled = false
        GFP:OnInitialize()
        assertPermissive(state.saved)
        assert.is_false(KE.db.global.GroupFinderPanelOwnsFilter)
    end)

    it("leaves the filter alone at OnInitialize when the module WILL enable", function()
        -- OnEnable's one-shot write owns that case; restoring here would
        -- wipe the settings a moment before rewriting them.
        local GFP, _, state = loadWithFilter()
        GFP:ApplyAdvancedFilters()
        state.saved = nil
        GFP:OnInitialize()
        assert.is_nil(state.saved)
    end)

    it("restores when Premade Groups Filter takes over", function()
        -- AceAddon has already marked the module enabled by the time
        -- OnEnable steps aside, so stepping aside is not enough on its own.
        local GFP, KE, state = loadWithFilter()
        GFP:ApplyAdvancedFilters()
        state.saved = nil
        _G.C_AddOns.IsAddOnLoaded = function(n) return n == "PremadeGroupsFilter" end
        GFP:OnEnable()
        assertPermissive(state.saved)
        assert.is_false(KE.db.global.GroupFinderPanelOwnsFilter)
    end)
end)

describe("GroupFinderPanel shortcut buttons", function()
    it("searches even INSIDE the window", function()
        -- A shortcut changes the category, so suppressing its search would
        -- leave the previous category's results under a new heading.
        local GFP, _, state, seams = loadWithFilter()
        GFP:ApplyAndRefresh()
        assert.equals(1, state.searches)
        seams.runQuickSearch(3, 1)
        assert.equals(2, state.searches)
        assert.equals(3, state.categories[#state.categories])
    end)

    it("saves and STOPS when the search panel is not shown", function()
        -- Navigating there ourselves would build Blizzard's provider inside
        -- our execution. The player clicks Premade Groups instead.
        local GFP, _, state, seams = loadWithFilter({ panelShown = false })
        GFP.db.MinScore = 2500
        seams.runQuickSearch(3, 1)
        assert.equals(2500, state.saved.minimumRating)
        assert.equals(0, state.searches)
        assert.equals(0, #state.categories)
    end)

    it("saves BEFORE it searches on the shown path", function()
        local GFP, _, state, seams = loadWithFilter()
        local order = {}
        _G.C_LFGList.SaveAdvancedFilter = function(f)
            order[#order + 1] = "save"; state.saved = f
        end
        _G.C_LFGList.Search = function()
            order[#order + 1] = "search"; state.searches = state.searches + 1
        end
        GFP.db.MinScore = 2500
        seams.runQuickSearch(3, 1)
        assert.same({ "save", "search" }, order)
        assert.equals(2500, state.saved.minimumRating)
    end)

    it("writes nothing at all while the module is inactive", function()
        local GFP, _, state, seams = loadWithFilter()
        GFP.db.Enabled = false
        seams.runQuickSearch(3, 1)
        assert.is_nil(state.saved)
        assert.equals(0, state.searches)
    end)
end)

describe("GroupFinderPanel minimum-score slider", function()
    it("SAVES but never searches -- a timer callback carries no click", function()
        local GFP, _, state, seams = loadWithFilter()
        GFP.db.MinScore = 2500
        seams.armMinScoreSave()
        assert.is_nil(state.saved)      -- arming alone writes nothing
        state.timerFn()
        assert.equals(2500, state.saved.minimumRating)
        assert.equals(0, state.searches)
    end)

    it("the newest interaction owns the one pending save", function()
        local _, _, state, seams = loadWithFilter()
        seams.armMinScoreSave()
        seams.armMinScoreSave()
        assert.equals(1, state.cancels)
    end)

    it("a save armed just before a disable cannot land after the restore", function()
        -- Otherwise it would rewrite the restrictive filter AND re-claim
        -- ownership on a module that is now off, stranding the residue.
        local GFP, KE, state, seams = loadWithFilter()
        GFP:ApplyAdvancedFilters()
        seams.armMinScoreSave()
        GFP.db.Enabled = false
        GFP:OnDisable()
        assert.equals(1, state.cancels)
        state.saved = nil
        state.timerFn()                 -- fires anyway: the gate must hold
        assert.is_nil(state.saved)
        assert.is_false(KE.db.global.GroupFinderPanelOwnsFilter)
    end)
end)

describe("GroupFinderPanel live slider authority", function()
    -- Rule 5(a): whenever a slider row exists it outranks the saved key,
    -- because the widget's throttle can leave the key an interaction behind.
    local function withRow(GFP, value)
        GFP.minScoreRow = { GetValue = function() return value end }
    end

    it("saves the value the ROW shows, not the older one in the key", function()
        local GFP, _, state = loadWithFilter()
        GFP.db.MinScore = 2400
        withRow(GFP, 2500)
        GFP:ApplyAdvancedFilters()
        assert.equals(2500, state.saved.minimumRating)
    end)

    it("writes the reconciled value back into the key", function()
        local GFP, _, state = loadWithFilter()
        GFP.db.MinScore = 2400
        withRow(GFP, 2500)
        GFP:ApplyAdvancedFilters()
        assert.equals(2500, GFP.db.MinScore)
        assert.equals(2500, state.saved.minimumRating)
    end)

    it("falls back to the key before the pane has ever been built", function()
        local GFP, _, state = loadWithFilter()
        GFP.db.MinScore = 2400
        GFP:ApplyAdvancedFilters()
        assert.equals(2400, state.saved.minimumRating)
    end)

    it("carries the ROW value across an enabled-to-enabled profile switch", function()
        -- The carry must reconcile first. A switch inside the slider's
        -- trailing-timer window otherwise copies the stale key, and the
        -- ApplySettings that follows pushes it back into the row -- losing
        -- the value the player chose.
        local GFP, KE = loadWithFilter()
        GFP.db.Enabled = true
        GFP.db.MinScore = 2400
        withRow(GFP, 2500)
        KE.db.profile.GroupFinderPanel = { Enabled = true, DungeonFilter = {}, MinScore = 0 }
        GFP:UpdateDB()
        assert.equals(2500, GFP.db.MinScore)
    end)
end)

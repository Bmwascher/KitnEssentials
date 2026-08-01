-- ╔══════════════════════════════════════════════════════════╗
-- ║  GroupFinderPanel.lua                                    ║
-- ║  Group Finder quick-access side panel                    ║
-- ║  Purpose: affixes, one-click category searches, a M+     ║
-- ║           dungeon/role filter pane, weekly runs footer.  ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- TAINT POSTURE -- read this before changing anything below.
-- This module deliberately taints Blizzard's secure LFGList system, at
-- parity with its reference and by explicit design grant. It rewrites
-- searchPanel.results in place, re-drives LFGListSearchPanel_UpdateResults,
-- calls the restricted C_LFGList.Search directly, and synthesises a click
-- on a Blizzard group button. It steps aside entirely when Premade Groups
-- Filter is installed, because that addon rewrites the same table.
--
-- What it does NOT do: it never reads or writes
-- CategorySelection.selectedCategory or .selectedFilters.
-- Do NOT describe the search as driven "purely" through
-- LFGListSearchPanel_SetCategory/_DoSearch -- the happy path calls
-- C_LFGList.Search directly and only falls back to _DoSearch. The
-- reference's own header says "purely" and is wrong.
--
-- Do not harden any of the above. Do add the secret-value guards -- see
-- SanitizeResult, which exists because GetSearchResultInfo and
-- GetSearchResultPlayerInfo are SecretInChatMessagingLockdown, and
-- browsing the group finder from inside a dungeon is ordinary.

---@class KE
local KE = select(2, ...)
if not KitnEssentials then
    error("GroupFinderPanel: addon object not initialized. Check file load order!")
    return
end

---@class GroupFinderPanel: AceModule, AceEvent-3.0
local GFP = KitnEssentials:NewModule("GroupFinderPanel", "AceEvent-3.0")

local _G = _G
local ipairs = ipairs
local CreateFrame = CreateFrame
local format = string.format
-- These three are NOT in KE's .luacheckrc read_globals, so a bare reference
-- is a W113 (undefined variable) -- which is never acceptable at any stage.
-- Alias them at file scope through _G, the same way both sibling modules do
-- for C_LFGList (Modules/Dungeons/LFGQuickCreate.lua:53,
-- Modules/Dungeons/LFGReminder.lua:56). Do NOT widen .luacheckrc instead.
-- C_SocialQueue may legitimately be nil here; every caller nil-checks it.
local C_LFGList = _G.C_LFGList
local C_SocialQueue = _G.C_SocialQueue
local bit = _G.bit
-- NOTE: KE.Skins is resolved at CALL time, not load time -- Dungeons.xml
-- loads before Skinning.xml in the toc, so a file-top capture is nil.
-- Never hoist it, even though every S.* name it uses does exist.

local PANEL_WIDTH  = 170
local AFFIX_SIZE   = 24
local BUTTON_HEIGHT = 26
local BUTTON_GAP   = 6

-- Themed, not the reference's #7381FF literal -- that was the upstream
-- project's own accent. Read once per function, keep each site's alpha.
local KE_PINK = { 1, 0, 0.549 }
local function Accent()
    return KE.Theme and KE.Theme.accent or KE_PINK
end

-- categoryID/filters pairs as Blizzard's category buttons carry them.
-- 121 (Delves) is a hardcoded magic number with no fallback -- known
-- fragility, carried from the reference deliberately.
local CATEGORY_DATA = {
    { key = "Mythic+", categoryID = _G.GROUP_FINDER_CATEGORY_ID_DUNGEONS or 2, filters = 0 },
    { key = "Raids",   categoryID = 3,   filters = 1 },
    { key = "Delves",  categoryID = 121, filters = 0 },
    { key = "Quest",   categoryID = 1,   filters = 0 },
    { key = "Custom",  categoryID = 6,   filters = 0 },
}

local DUNGEON_CAT = _G.GROUP_FINDER_CATEGORY_ID_DUNGEONS or 2

local panel

-- Preferred short names (Midnight Season 1); anything unlisted falls back
-- to the initials algorithm, so new seasons degrade gracefully.
local ABBREV_OVERRIDE = {
    ["Windrunner Spire"]        = "WRS",
    ["Magisters' Terrace"]      = "MT",
    ["Maisara Caverns"]         = "MRC",
    ["Nexus-Point Xenas"]       = "NPX",
    ["Skyreach"]                = "SKY",
    ["Pit of Saron"]            = "PIT",
    ["Seat of the Triumvirate"] = "SEAT",
    ["Algeth'ar Academy"]       = "AA",
}

-- Lifted verbatim out of CreateFilterPanel so it can be tested. It depends
-- only on its argument and ABBREV_OVERRIDE; the enclosing function
-- contributed no state.
local function Abbreviate(name)
    local abbrev = ABBREV_OVERRIDE[name]
    if abbrev then return abbrev end
    abbrev = ""
    for word in name:gmatch("[^%s%-']+") do
        local lw = word:lower()
        if lw ~= "of" and lw ~= "the" and lw ~= "and" then
            abbrev = abbrev .. word:sub(1, 1):upper()
        end
    end
    if #abbrev < 2 then abbrev = name:sub(1, 4):upper() end
    return abbrev
end

-- 12.0.7 spec mapping. NO fallback to the deprecated globals -- they live in
-- Blizzard_DeprecatedSpecialization and must not be called from new code.
local function PlayerSpecRole()
    local CSI = _G.C_SpecializationInfo
    if not (CSI and CSI.GetSpecialization and CSI.GetSpecializationInfo) then return nil end
    local spec = CSI.GetSpecialization()
    if not spec then return nil end
    return select(5, CSI.GetSpecializationInfo(spec))
end

local function GetPartyRoles()
    local roles = { TANK = 0, HEALER = 0, DAMAGER = 0 }
    if IsInGroup() then
        local r = UnitGroupRolesAssigned("player")
        if r == "NONE" or not roles[r] then r = PlayerSpecRole() end
        if r and roles[r] then roles[r] = roles[r] + 1 end
        for i = 1, GetNumGroupMembers() - 1 do
            r = UnitGroupRolesAssigned("party" .. i)
            if roles[r] then roles[r] = roles[r] + 1 end
        end
    else
        -- Solo: your role comes from your spec. UnitGroupRolesAssigned is
        -- NONE outside a group, which silently no-op'd Needs Role for solo
        -- players (the "healer sees healer groups" report).
        local r = PlayerSpecRole()
        if r and roles[r] then roles[r] = roles[r] + 1 end
    end
    return roles
end

local function SeasonGroups()
    local F = Enum and Enum.LFGListFilter
    if not (F and C_LFGList and C_LFGList.GetAvailableActivityGroups) then return {} end
    return C_LFGList.GetAvailableActivityGroups(DUNGEON_CAT, bit.bor(F.CurrentSeason, F.PvE)) or {}
end

local function ExpansionGroups()
    local F = Enum and Enum.LFGListFilter
    if not (F and C_LFGList and C_LFGList.GetAvailableActivityGroups) then return {} end
    return C_LFGList.GetAvailableActivityGroups(DUNGEON_CAT,
        bit.bor(F.CurrentExpansion, F.NotCurrentSeason, F.PvE)) or {}
end

local function IsDungeonSearchMode()
    local pve, gff, lfg = _G.PVEFrame, _G.GroupFinderFrame, _G.LFGListFrame
    return pve and pve.activeTabIndex == 1
        and gff and gff.selection == _G.LFGListPVEStub
        and lfg and lfg.SearchPanel and lfg.SearchPanel:IsShown()
        and lfg.SearchPanel.categoryID == DUNGEON_CAT
end

local SORT_ORDER = { "DEFAULT", "OVERALL_SCORE", "DUNGEON_SCORE" }
local SORT_MODE = {
    DEFAULT       = { text = "Default" },
    OVERALL_SCORE = { text = "Overall Score",
        func = function(a, b) return a.overall > b.overall and 1 or a.overall < b.overall and -1 or 0 end },
    -- Leader's best score for THIS dungeon.
    DUNGEON_SCORE = { text = "Dungeon Score",
        func = function(a, b) return a.leaderScore > b.leaderScore and 1 or a.leaderScore < b.leaderScore and -1 or 0 end },
}

-- Test seams. Nothing in the module reads these; they exist so the spec can
-- reach file-locals without exporting them into the module's real surface.
GFP._PlayerSpecRole      = PlayerSpecRole
GFP._GetPartyRoles       = GetPartyRoles
GFP._SeasonGroups        = SeasonGroups
GFP._ExpansionGroups     = ExpansionGroups
GFP._IsDungeonSearchMode = IsDungeonSearchMode
GFP._Abbreviate          = Abbreviate
GFP._SORT_ORDER          = SORT_ORDER
GFP._SORT_MODE           = SORT_MODE

------------------------------------------------------------------------
-- Result list: post-hook LFGListSearchPanel_UpdateResultList and reorder
-- searchPanel.results -- pending applications first, friends' groups
-- pinned above strangers, then the chosen comparator.
------------------------------------------------------------------------

-- While BROWSING on Midnight, search-result friend counts come back
-- empty/secret -- even Blizzard's own BATTLENET_FONT_COLOR branch never
-- fires. C_SocialQueue is the authoritative source: build a set of
-- friends' active LFGList searchResultIDs the way Blizzard_QuickJoin
-- does, refreshed per hook run.
local friendResultSet = {}
local function RefreshFriendResultSet()
    wipe(friendResultSet)
    if not (C_SocialQueue and C_SocialQueue.GetAllGroups) then return end
    local ok = pcall(function()
        local groups = C_SocialQueue.GetAllGroups()
        for i = 1, #groups do
            local queues = C_SocialQueue.GetGroupQueues(groups[i])
            if queues then
                for _, q in ipairs(queues) do
                    local qd = q.queueData
                    if qd and qd.queueType == "lfglist" and qd.lfgListID then
                        friendResultSet[qd.lfgListID] = true
                    end
                end
            end
        end
    end)
    if not ok then wipe(friendResultSet) end
end

local resorting = false
-- Snapshot of the last RAW result list Blizzard delivered, before our
-- filtering. ReSort re-runs the whole predicate + sort pass from THIS, so
-- relaxing a filter instantly restores entries without a server
-- re-search -- which also sidesteps the "Search failed, please wait"
-- throttle that per-click re-searches were tripping.
local lastRawResults = {}
-- DELIBERATELY declared here rather than below OnUpdateResultList as the
-- reference does. Lua scopes a local from its declaration onward, so the
-- reference's read compiles as a never-assigned GLOBAL, permanently nil,
-- and the guard below is permanently true -- re-snapshotting from the
-- already-filtered list on every ReSort and defeating the whole
-- resurrect-on-filter-relax design. luacheck reports both halves.
local resortFromSnapshot = false

------------------------------------------------------------------------
-- Secret-value boundary. GetSearchResultInfo and
-- GetSearchResultPlayerInfo are both SecretInChatMessagingLockdown, which
-- includes "the player is on a communication-restricted map such as a
-- dungeon" -- browsing the group finder from inside a dungeon is ordinary,
-- so treat every field except partyGUID as secret-capable.
--
-- FOUR RULES, each of which fixes a design that looked safe and was not:
--  1. A pcall does NOT declassify what it returns. It returns ok=true with
--     a still-secret number. So this boundary does the COMPUTATION, not
--     the extraction.
--  2. A fresh table does not cleanse its contents either. So every scalar
--     is tested, not merely "not a raw field".
--  3. issecretvalue, NOT canaccessvalue. canaccessvalue answers "may THIS
--     function operate on it" -- the wrong scope for a boundary whose job
--     is to hand values to the table.sort comparator later.
--  4. The test is FIRST CONTACT, before any arithmetic, and inside the
--     pcall -- issecretvalue is itself AllowedWhenUntainted, so calling it
--     on an already-tainted path can throw. A throw here is caught and
--     takes the fail-open path.
-- Arithmetic on a secret is recorded as sometimes throwing and sometimes
-- silently propagating, which is why outputs are re-tested on the way out.
------------------------------------------------------------------------

local function Secret(v)
    return _G.issecretvalue and _G.issecretvalue(v)
end

local function SecretTable(t)
    return _G.issecrettable and _G.issecrettable(t)
end

-- Returns a NEWLY CONSTRUCTED record of derived plain values. It never
-- returns a raw API field, and never a value that failed a test.
--   gid / gidKnown  -- nil+false means "unreadable", skip the dungeon predicate
--   roles           -- nil means "unreadable", skip the role predicates
--   friends, overall, leaderScore -- 0 when unreadable
-- FAIL OPEN: an unreadable result is KEPT with neutral values, matching
-- the reference's own policy for the two sites it already guards.
local function SanitizeResult(resultID, info, wantGroups, wantRoles)
    local rec = { gid = nil, gidKnown = false, roles = nil,
                  friends = 0, overall = 0, leaderScore = 0 }

    local ok = pcall(function()
        if wantGroups then
            local ids = info.activityIDs
            -- `info.activityID` singular does not exist on LfgSearchResultData
            -- in 12.0.7; the reference's `or` branch is dead. Kept verbatim.
            local act = (ids and not SecretTable(ids)) and ids[1] or info.activityID
            if act ~= nil and not Secret(act) and C_LFGList.GetActivityInfoTable then
                -- GetActivityInfoTable is AllowedWhenUntainted: the argument
                -- has to clear the test BEFORE this call, not after.
                local t = C_LFGList.GetActivityInfoTable(act)
                local gid = t and t.groupFinderActivityGroupID
                if gid ~= nil and not Secret(gid) then
                    rec.gid, rec.gidKnown = gid, true
                end
            end
        end

        if wantRoles then
            local n = info.numMembers
            if n ~= nil and not Secret(n) then
                local roles = { TANK = 0, HEALER = 0, DAMAGER = 0 }
                for i = 1, n do
                    local pInfo = C_LFGList.GetSearchResultPlayerInfo(resultID, i)
                    local r = pInfo and pInfo.assignedRole
                    -- Table-key behaviour on a secret is UNVERIFIED, which is
                    -- a reason to refuse the key, not to risk it.
                    if r ~= nil and not Secret(r) and roles[r] then
                        roles[r] = roles[r] + 1
                    end
                end
                rec.roles = roles
            end
        end

        local bn, cf, gm = info.numBNetFriends, info.numCharFriends, info.numGuildMates
        if not (Secret(bn) or Secret(cf) or Secret(gm)) then
            rec.friends = (bn or 0) + (cf or 0) + (gm or 0)
        end

        local overall = info.leaderOverallDungeonScore
        if overall ~= nil and not Secret(overall) then rec.overall = overall end

        local best = info.leaderBestDungeonScoreInfo
        if best ~= nil and not SecretTable(best) then
            local ms = best.mapScore
            if ms ~= nil and not Secret(ms) then rec.leaderScore = ms end
        end
    end)

    -- Re-test on the way OUT. The input tests prove the inputs were clean;
    -- they cannot prove a derived value is, because arithmetic on a secret
    -- may propagate rather than throw. The boundary guarantees its outputs.
    local okOut = pcall(function()
        if Secret(rec.friends) then rec.friends = 0 end
        if Secret(rec.overall) then rec.overall = 0 end
        if Secret(rec.leaderScore) then rec.leaderScore = 0 end
        if Secret(rec.gid) then rec.gid, rec.gidKnown = nil, false end
        -- Three explicit checks, not a loop over a table literal: this runs
        -- once per search result and the literal would allocate every time.
        if rec.roles and (Secret(rec.roles.TANK) or Secret(rec.roles.HEALER)
            or Secret(rec.roles.DAMAGER)) then
            rec.roles = nil
        end
    end)

    if not (ok and okOut) then
        return { gid = nil, gidKnown = false, roles = nil,
                 friends = 0, overall = 0, leaderScore = 0 }
    end
    return rec
end

-- Decoration's own boundary. FAIL CLOSED -- never decorate an unreadable
-- value. The constraint that sets the order is NOT SetFormattedText (which
-- is AllowedWhenTainted and accepts secret text by contract) but
-- GetDungeonScoreRarityColor, which is AllowedWhenUntainted and runs
-- first. The score must clear the test before it reaches that call.
local function SanitizeScore(resultID)
    local score
    local ok = pcall(function()
        local info = C_LFGList.GetSearchResultInfo(resultID)
        local s = info and info.leaderOverallDungeonScore
        if s == nil or Secret(s) then return end
        if s == 0 then return end
        score = s
    end)
    if not ok then return nil end
    if Secret(score) then return nil end
    return score
end

local function OnUpdateResultList(searchPanel)
    -- The advanced-filter API owns the dungeon/tank/healer predicates
    -- server-side and every filter change triggers a REAL re-search, so
    -- this hook always receives a fresh list. The client-side pass over
    -- the raw snapshot is the authority and is non-destructive by
    -- construction -- it filters the SNAPSHOT, never the already-shrunk
    -- output. Filtering the output is what monotonically emptied the list
    -- in earlier versions.
    if resorting then return end
    local db = GFP.db
    if not db or not db.Enabled then return end   -- Task 7 converts to IsActive()
    if not IsDungeonSearchMode() then return end
    local results = searchPanel.results
    if not results or #results == 0 then return end

    local sortBy = db.SortBy or "DEFAULT"
    local comparator = SORT_MODE[sortBy] and SORT_MODE[sortBy].func
    local partyRoles = db.PartyFit and GetPartyRoles()
    -- No early-out on Default sort: friend groups pin to the top in EVERY
    -- mode. anyFriends tracks whether a pinning pass is needed at all.
    local anyFriends = false

    local selectedGroups
    for groupID, on in pairs(db.DungeonFilter or {}) do
        if on then
            selectedGroups = selectedGroups or {}
            selectedGroups[groupID] = true
        end
    end
    local wantTank, wantHealer = db.HasTank == true, db.HasHealer == true

    -- Fresh delivery from Blizzard, not our own write-back re-entry:
    -- snapshot it as the raw universe for client-side filtering.
    if not resorting and not resortFromSnapshot then
        wipe(lastRawResults)
        for i = 1, #results do lastRawResults[i] = results[i] end
    end
    results = lastRawResults
    if #results == 0 then return end

    RefreshFriendResultSet()

    local pending, sortable = {}, {}
    for _, resultID in ipairs(results) do
        local pendingStatus = select(3, C_LFGList.GetApplicationInfo(resultID))
        -- EVERY id handed back has to still resolve. Blizzard builds its
        -- entry buttons from this list and reads GetSearchResultInfo on
        -- hover with no nil check. Pending applications are exactly the
        -- entries that outlive their listing: a group you applied to gets
        -- delisted, GetApplicationInfo still reports pending,
        -- GetSearchResultInfo returns nil, and the dead id sits in the
        -- list until someone hovers it.
        local info = C_LFGList.GetSearchResultInfo(resultID)
        if not info then
            -- Dropped entirely: no button, nothing to hover.
        elseif pendingStatus then
            pending[#pending + 1] = resultID
        else
            local ok = true
            -- Friends' groups BYPASS every predicate.
            local isFriend = friendResultSet[resultID] and true or false
            local wantRoles = (partyRoles or wantTank or wantHealer) and true or false
            local rec = SanitizeResult(resultID, info,
                (not isFriend) and selectedGroups ~= nil, (not isFriend) and wantRoles)

            -- Dungeon selection. gidKnown false means unreadable -> KEEP.
            if not isFriend and selectedGroups and rec.gidKnown
                and not selectedGroups[rec.gid] then
                ok = false
            end

            local grpRoles = (not isFriend) and rec.roles or nil
            if ok and grpRoles and wantTank and grpRoles.TANK == 0 then ok = false end
            if ok and grpRoles and wantHealer and grpRoles.HEALER == 0 then ok = false end
            -- Our party's damagers must still fit -- the needs* filters
            -- cannot express this.
            if ok and grpRoles and partyRoles then
                if partyRoles.TANK > 0 and grpRoles.TANK > 0 then ok = false end
                if ok and partyRoles.HEALER > 0 and grpRoles.HEALER > 0 then ok = false end
                if ok and partyRoles.DAMAGER + grpRoles.DAMAGER > 3 then ok = false end
            end

            if ok then
                local friends = isFriend and 1 or rec.friends
                if friends > 0 then anyFriends = true end
                sortable[#sortable + 1] = {
                    id = resultID,
                    idx = #sortable + 1, -- original order for the stable Default fallback
                    overall = rec.overall,
                    leaderScore = rec.leaderScore,
                    friends = friends,
                }
            end
        end
    end

    -- Sorts when a comparator is chosen OR any friend group exists.
    -- Default + friends = pin only; everything else keeps Blizzard's order
    -- via the original-index tiebreak, because table.sort is not stable.
    if comparator or anyFriends then
        table.sort(sortable, function(a, b)
            if not a or not b then return false end
            -- Blizzard's social priority: friends and guildmates on top.
            local aF, bF = a.friends > 0, b.friends > 0
            if aF ~= bF then return aF end
            if comparator then
                local r = comparator(a, b)
                if not db.SortDescending then r = -r end
                if r ~= 0 then return r == 1 end
            end
            return a.idx < b.idx
        end)
    end

    local out = {}
    for _, id in ipairs(pending) do out[#out + 1] = id end
    for _, e in ipairs(sortable) do out[#out + 1] = e.id end
    searchPanel.results = out
    searchPanel.totalResults = #out
    resorting = true
    if _G.LFGListSearchPanel_UpdateResults then _G.LFGListSearchPanel_UpdateResults(searchPanel) end
    resorting = false
end

local function ReSort()
    -- Runs the full pass from the raw snapshot. searchPanel.results holds
    -- our previous filtered output, but the hook body substitutes the
    -- snapshot, so relaxing filters resurrects entries.
    local sp = _G.LFGListFrame and _G.LFGListFrame.SearchPanel
    if sp and sp:IsShown() then
        resortFromSnapshot = true
        OnUpdateResultList(sp)
        resortFromSnapshot = false
    end
end

------------------------------------------------------------------------
-- Leader score on result rows: prepend the coloured overall score to each
-- entry's name line, using Blizzard's own rarity ramp.
------------------------------------------------------------------------
local function DecorateSearchEntry(entry)
    local db = GFP.db
    if not db or not db.Enabled or not IsDungeonSearchMode() then return end  -- Task 7: IsActive()
    if not entry.resultID or not entry.Name then return end
    local score = SanitizeScore(entry.resultID)
    if not score then return end
    local color = C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor
        and C_ChallengeMode.GetDungeonScoreRarityColor(score)
    local hex = color and color:GenerateHexColor() or "ffffffff"
    -- entry.Name:GetText() can return secret TEXT. That is fine and is not
    -- guarded: GetText carries the Text secret aspect and SetFormattedText
    -- is AllowedWhenTainted and accepts it by contract.
    entry.Name:SetFormattedText("|c%s%d|r  %s", hex, score, entry.Name:GetText() or "")
end

GFP._SanitizeResult      = SanitizeResult
GFP._SanitizeScore       = SanitizeScore
GFP._OnUpdateResultList  = OnUpdateResultList
GFP._ReSort              = ReSort
GFP._DecorateSearchEntry = DecorateSearchEntry

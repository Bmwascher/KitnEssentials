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

-- Sizing overhauled 2026-08-01 on Brandon's smoke feedback: the panel read
-- cramped next to the Group Finder. Everything grew; the Mythic+ button grew
-- more than the rest because it is the one people click most.
local PANEL_WIDTH   = 220
local AFFIX_SIZE    = 34
local BUTTON_HEIGHT = 32
local MPLUS_HEIGHT  = 46   -- the headline button, deliberately taller
local BUTTON_GAP    = 6
local TOGGLE_HEIGHT = 30   -- filter-pane toggles, up from 24
local TOGGLE_ICON   = 22   -- dungeon icon, left of the short name

-- The panel's background stays on S.Backdrop, whose carrier is parented to
-- PVEFrame. A self-owned KE:ApplyBackdrop was tried on 2026-08-01 and did
-- not draw in game -- don't retry it without an in-game probe first.

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

-- Forward declared, assigned in the Lifecycle section at the bottom of
-- this file. Every one of the fourteen gate sites above that section
-- closes over this same upvalue -- declaring IsActive inline down there
-- (as `local function IsActive`) would leave every earlier `IsActive()`
-- read resolving to the global namespace instead, which luacheck reports
-- as W113 and which is nil at call time. Same scoping trap as
-- resortFromSnapshot above, same fix: declare where the readers are.
local IsActive

-- Preferred short names (Midnight Season 1); anything unlisted falls back
-- to the initials algorithm, so new seasons degrade gracefully.
local ABBREV_OVERRIDE = {
    ["Windrunner Spire"]        = "WS",
    ["Magisters' Terrace"]      = "MT",
    ["Maisara Caverns"]         = "MC",
    ["Nexus-Point Xenas"]       = "NPX",
    ["Skyreach"]                = "SR",
    ["Pit of Saron"]            = "POS",
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
    if not IsActive() then return end
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
        -- Deviation 15: positive tests, not the reference's empty leading
        -- branch. A nil info means the listing died between Blizzard
        -- building the id list and us reading it back; it is dropped by
        -- falling through, which is safe because no button is built for it
        -- and so nothing can hover it.
        if info and pendingStatus then
            pending[#pending + 1] = resultID
        elseif info then
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
    if not IsActive() or not IsDungeonSearchMode() then return end
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

------------------------------------------------------------------------
-- Weekly runs footer: vault-aware tooltip (top runs + reward levels).
------------------------------------------------------------------------
local function RunsTooltip(footer)
    local history = C_MythicPlus and C_MythicPlus.GetRunHistory and C_MythicPlus.GetRunHistory(false, true)
    if not history or #history == 0 then return end
    local levels = {}
    for _, run in ipairs(history) do levels[#levels + 1] = run.level end
    table.sort(levels, function(a, b) return a > b end)
    local accent = Accent()
    _G.GameTooltip:SetOwner(footer, "ANCHOR_TOP")
    _G.GameTooltip:SetText("Mythic+ Runs", 1, 1, 1)
    for _, slot in ipairs({ 1, 4, 8 }) do
        local lvl = levels[slot]
        if lvl then
            local ilvl = C_MythicPlus.GetRewardLevelForDifficultyLevel
                and select(2, C_MythicPlus.GetRewardLevelForDifficultyLevel(lvl))
            _G.GameTooltip:AddDoubleLine(format("Best %d", slot),
                ilvl and format("+%d (%d)", lvl, ilvl) or ("+" .. lvl),
                0.85, 0.85, 0.85, accent[1], accent[2], accent[3])
        end
    end
    _G.GameTooltip:Show()
end

local function UpdateRuns()
    if not panel or not panel.runsText then return end
    local history = C_MythicPlus and C_MythicPlus.GetRunHistory and C_MythicPlus.GetRunHistory(false, true)
    local n = history and #history or 0
    if n == 0 then
        panel.runsText:SetText("No Mythic+ Runs")
        panel.runsText:SetTextColor(0.486, 0.486, 0.486) -- #7c7c7c
    else
        panel.runsText:SetText(format("%d Mythic+ runs this week", n))
        panel.runsText:SetTextColor(0.85, 0.85, 0.85)
    end
end

local function AffixOnEnter(btn)
    if not btn.affixID then return end
    local name, desc = C_ChallengeMode.GetAffixInfo(btn.affixID)
    if not name then return end
    _G.GameTooltip:SetOwner(btn, "ANCHOR_BOTTOM")
    _G.GameTooltip:SetText(name, 1, 1, 1)
    if desc then _G.GameTooltip:AddLine(desc, nil, nil, nil, true) end
    _G.GameTooltip:Show()
end

local function AffixOnLeave()
    _G.GameTooltip:Hide()
end

local function UpdateAffixes()
    if not panel or not panel.affixes then return end
    local current = C_MythicPlus and C_MythicPlus.GetCurrentAffixes and C_MythicPlus.GetCurrentAffixes()
    local shown = 0
    for i, holder in ipairs(panel.affixes) do
        local info = current and current[i]
        if info and info.id then
            local _, _, filedataid = C_ChallengeMode.GetAffixInfo(info.id)
            holder.icon:SetTexture(filedataid)
            holder.affixID = info.id
            holder:Show()
            shown = shown + 1
        else
            holder:Hide()
        end
    end
    local total = shown * AFFIX_SIZE + (shown - 1) * 4
    for i = 1, shown do
        local holder = panel.affixes[i]
        holder:ClearAllPoints()
        holder:SetPoint("TOPLEFT", panel, "TOP", -total / 2 + (i - 1) * (AFFIX_SIZE + 4), -12)
    end
end

------------------------------------------------------------------------
-- Raider.IO coexistence. RIO parks its profile via a global anchor
-- (RaiderIO_ProfileTooltipAnchor) SetPoint'd against PVEFrame's right
-- edge -- our panel's exact spot. Wrap the anchor's SetPoint so that
-- whenever RIO anchors relative to PVEFrame or to us, we substitute
-- whichever currently owns the right edge, then re-assert the point so
-- the change lands immediately.
--
-- THE LEGAL BASIS IS PARTLY UNVERIFIED. Established: the anchor belongs to
-- RaiderIO, not Blizzard, and this wrapper is idempotent and irreversible
-- (the original is captured in a closure and never restored). NOT
-- established: that the frame is unprotected. Neither RaiderIO's source
-- nor an in-game anchor:IsProtected() probe has been consulted, and
-- ClearAllPoints/SetPoint below are themselves protected functions. The
-- probe is a BLOCKING smoke step -- if it returns true, stop and replan.
local function RepositionRaiderIO()
    -- While inactive, do nothing except the one forced re-anchor the
    -- teardown helper performs.
    if not IsActive() then return end
    local anchor = _G.RaiderIO_ProfileTooltipAnchor
    if not anchor then return end

    if not anchor.__keGFPWrapped then
        anchor.__keGFPWrapped = true
        local orig = anchor.SetPoint
        anchor.SetPoint = function(self, p, rel, rp, x, y)
            -- While inactive this wrapper delegates straight to `orig`
            -- without substituting `rel` or nudging `x`. It stays
            -- installed; it stops changing behaviour.
            if IsActive() and rel and (rel == _G.PVEFrame or rel == panel) then
                local usePanel = panel and panel:IsShown()
                rel = usePanel and panel or _G.PVEFrame
                -- RIO's stock x is -16, a tuck sized for PVEFrame's thick
                -- border art -- flush against our flat panel. Nudge by +1
                -- for a 1px gap ONLY when anchored to us; the native
                -- PVEFrame tuck stays theirs.
                if usePanel and type(x) == "number" then
                    x = x + 1
                end
            end
            if rp == nil and x == nil and y == nil then
                return orig(self, p, rel)
            end
            return orig(self, p, rel, rp, x, y)
        end
    end

    -- Re-assert on THEIR tooltip's show as well: each profile render can
    -- re-point, and this also heals any SetPoint that landed before the
    -- wrap installed.
    local tip = _G.RaiderIO_ProfileTooltip
    if tip and not tip.__keGFPShowHook then
        tip.__keGFPShowHook = true
        tip:HookScript("OnShow", function() RepositionRaiderIO() end)
    end

    local p1, p2, p3, p4, p5 = anchor:GetPoint(1)
    if p1 then
        anchor:ClearAllPoints()
        anchor:SetPoint(p1, p2, p3, p4, p5)
    end
end

-- RIO creates RaiderIO_ProfileTooltipAnchor lazily when a profile first
-- renders -- often AFTER our first OnShow -- so RepositionRaiderIO bailed
-- on the nil anchor and the wrap never installed that session. Reopening
-- worked because the anchor existed by then. Watch for the anchor's
-- creation instead of assuming it.
local rioWatcher
local function EnsureRaiderIOWrap()
    -- Cancelling the ticker is NOT sufficient on its own -- the permanent
    -- panel Show hook can call this again and install the wrapper while
    -- inactive.
    if not IsActive() then return end
    if _G.RaiderIO_ProfileTooltipAnchor then
        RepositionRaiderIO()
        return
    end
    if rioWatcher then return end
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("RaiderIO")
    if not loaded then return end
    rioWatcher = C_Timer.NewTicker(0.25, function(t)
        if _G.RaiderIO_ProfileTooltipAnchor then
            t:Cancel()
            rioWatcher = nil
            RepositionRaiderIO()
        end
    end, 120) -- up to 30s of lazy creation, then give up quietly
end

-- Shared UNCONDITIONAL teardown. Called by OnDisable and by Refresh's
-- inactive branch (deviations 11 and 13). Deliberately NOT gated: the
-- config page clears db.Enabled BEFORE disabling the module, so an
-- IsActive() gate here would skip the very cleanup it exists to do.
-- Never installs a wrapper that is not already there.
local function TeardownRaiderIO()
    if rioWatcher then
        rioWatcher:Cancel()
        rioWatcher = nil
    end
    local anchor = _G.RaiderIO_ProfileTooltipAnchor
    if anchor and anchor.__keGFPWrapped then
        local p1, p2, p3, p4, p5 = anchor:GetPoint(1)
        if p1 then
            anchor:ClearAllPoints()
            anchor:SetPoint(p1, p2, p3, p4, p5)
        end
    end
end

------------------------------------------------------------------------
-- Quick search: navigate to Premade Groups if needed, then set category
-- and fire the search. All calls are Blizzard's own public flow.
------------------------------------------------------------------------
local function RunQuickSearch(categoryID, filters)
    if not IsActive() then return end
    local pve = _G.PVEFrame
    if not pve then return end
    if pve.activeTabIndex ~= 1 and _G.PVEFrame_ShowFrame then
        _G.PVEFrame_ShowFrame("GroupFinderFrame")
    end
    local lfg = _G.LFGListFrame
    local gff = _G.GroupFinderFrame
    if not lfg or not gff then return end
    -- Select the Premade Groups sub-panel if it is not active. The button
    -- index depends on whether the scenarios button is present this season.
    if (not lfg.SearchPanel or not lfg.SearchPanel:IsShown())
        or gff.selection ~= _G.LFGListPVEStub then
        local premade = (pve.ScenariosEnabled and pve:ScenariosEnabled() and gff.groupButton4)
            or gff.groupButton3
        if premade and _G.GroupFinderFrameGroupButton_OnClick then
            _G.GroupFinderFrameGroupButton_OnClick(premade)
        end
    end
    local searchPanel = lfg.SearchPanel
    if not searchPanel then return end
    if _G.LFGListSearchPanel_Clear then _G.LFGListSearchPanel_Clear(searchPanel) end
    if _G.LFGListSearchPanel_SetCategory then
        _G.LFGListSearchPanel_SetCategory(searchPanel, categoryID, filters, lfg.baseFilters or 0)
    end
    if _G.LFGListSearchPanel_DoSearch then _G.LFGListSearchPanel_DoSearch(searchPanel) end
    if _G.LFGListFrame_SetActivePanel then _G.LFGListFrame_SetActivePanel(lfg, searchPanel) end
end

------------------------------------------------------------------------
-- Panel construction (lazy, once)
------------------------------------------------------------------------
local function CreatePanel()
    if panel then return panel end
    local pve = _G.PVEFrame
    local S = KE.Skins            -- CALL time. Never hoist.
    if not pve or not S then return nil end
    local accent = Accent()

    panel = CreateFrame("Frame", "KE_GroupFinderPanel", pve)
    panel:SetPoint("TOPLEFT", pve, "TOPRIGHT", 2, 0)
    panel:SetPoint("BOTTOMLEFT", pve, "BOTTOMRIGHT", 2, 0)
    panel:SetWidth(PANEL_WIDTH)
    S.Backdrop(panel)
    -- The Show/Hide METHODS, not the OnShow/OnHide scripts. Method hooks
    -- fire on every call, including Show() on an already-visible frame --
    -- the born-visible first open, where the OnShow EVENT never fires.
    -- Script hooks kept for implicit visibility changes via the parent.
    hooksecurefunc(panel, "Show", EnsureRaiderIOWrap)
    hooksecurefunc(panel, "Hide", RepositionRaiderIO)
    panel:HookScript("OnShow", EnsureRaiderIOWrap)
    panel:HookScript("OnHide", RepositionRaiderIO)

    -- Affix icon row (this week)
    panel.affixes = {}
    for i = 1, 5 do
        local holder = CreateFrame("Button", nil, panel)
        holder:SetSize(AFFIX_SIZE, AFFIX_SIZE)
        S.Backdrop(holder)
        holder.icon = holder:CreateTexture(nil, "ARTWORK")
        holder.icon:SetPoint("TOPLEFT", 1, -1)
        holder.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        holder.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        holder:SetScript("OnEnter", AffixOnEnter)
        holder:SetScript("OnLeave", AffixOnLeave)
        holder:Hide()
        panel.affixes[i] = holder
    end

    -- Quick Access pane (swapped for the Filters pane in M+ search mode).
    -- Top offset clears the taller affix row.
    panel.quick = CreateFrame("Frame", nil, panel)
    panel.quick:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -(AFFIX_SIZE + 22))
    panel.quick:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)

    local title = panel.quick:CreateFontString(nil, "OVERLAY")
    S.SetFont(title, 16, "")
    title:SetPoint("TOP", panel.quick, "TOP", 0, -6)
    title:SetText("Quick Access")
    title:SetTextColor(accent[1], accent[2], accent[3])

    -- Category buttons. Mythic+ is first and deliberately taller than the
    -- rest -- it is the one people come here for.
    local prev
    for _, data in ipairs(CATEGORY_DATA) do
        local btn = CreateFrame("Button", nil, panel.quick)
        local isMPlus = (data.key == "Mythic+")
        btn:SetHeight(isMPlus and MPLUS_HEIGHT or BUTTON_HEIGHT)
        if not prev then
            btn:SetPoint("TOPLEFT", panel.quick, "TOPLEFT", 10, -32)
            btn:SetPoint("TOPRIGHT", panel.quick, "TOPRIGHT", -10, -32)
        else
            btn:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -BUTTON_GAP)
            btn:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, -BUTTON_GAP)
        end
        prev = btn
        S.Button(btn)
        local fs = btn:CreateFontString(nil, "OVERLAY")
        S.SetFont(fs, isMPlus and 15 or 13, "")
        fs:SetPoint("CENTER")
        fs:SetText(data.key)
        btn:SetScript("OnClick", function()
            RunQuickSearch(data.categoryID, data.filters)
        end)
    end

    -- Weekly runs footer
    local footer = CreateFrame("Frame", nil, panel)
    panel.footer = footer          -- the filter pane anchors its bottom to this
    footer:SetHeight(BUTTON_HEIGHT)
    footer:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 10, 12)
    footer:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 12)
    local fbd = S.Backdrop(footer)
    if fbd then fbd:SetBackdropColor(0.055, 0.055, 0.055, 0.95) end
    panel.runsText = footer:CreateFontString(nil, "OVERLAY")
    S.SetFont(panel.runsText, 12, "")
    panel.runsText:SetPoint("CENTER")
    footer:EnableMouse(true)
    footer:SetScript("OnEnter", RunsTooltip)
    footer:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)

    return panel
end

------------------------------------------------------------------------
-- Mythic+ filter pane: dungeon toggles, Needs Role, Has Tank/Healer, and
-- client-side sorting. Shown in place of the Quick Access buttons
-- whenever the M+ search is active.
------------------------------------------------------------------------

function GFP:ApplyAdvancedFilters()
    -- This reaches C_LFGList.SaveAdvancedFilter, which persists BLIZZARD's
    -- own filter state -- it is the single most important thing to stop
    -- while inactive.
    if not IsActive() then return end
    --
    -- The server-side filter is kept PERMISSIVE: all dungeons, no
    -- has/needs constraints. The client pass over the raw snapshot is the
    -- authority, and a broad server list is what lets friends' groups
    -- bypass filters -- a server-excluded result cannot be resurrected
    -- client-side.
    local db = self.db
    if not db or not (C_LFGList and C_LFGList.GetAdvancedFilter) then return end
    local adv = C_LFGList.GetAdvancedFilter()
    if not adv then return end
    adv.needsTank, adv.needsHealer, adv.needsDamage = false, false, false
    adv.hasTank, adv.hasHealer = false, false
    local activities = {}
    for _, g in ipairs(SeasonGroups()) do activities[#activities + 1] = g end
    for _, g in ipairs(ExpansionGroups()) do activities[#activities + 1] = g end
    adv.activities = activities
    C_LFGList.SaveAdvancedFilter(adv)
end

-- Blizzard's ResolveCategoryFilters is file-local; replicated verbatim
-- (dungeons only display recommended groups).
local function ResolveCategoryFilters(categoryID, filters)
    if categoryID == DUNGEON_CAT then
        return bit.band(bit.bnot(Enum.LFGListFilter.NotRecommended),
            bit.bor(filters or 0, Enum.LFGListFilter.Recommended))
    end
    return filters
end

function GFP:ApplyAndRefresh()
    if not IsActive() then return end
    self:ApplyAdvancedFilters()
    -- The client-side pass over the raw snapshot is authoritative and
    -- INSTANT -- run it unconditionally. The real server re-search is a
    -- freshness assist only, and Blizzard throttles it hard; per-click
    -- DoSearch was tripping "Search failed, please wait a moment". Gate
    -- the server hit to one per 10s window; skipped refreshes cost
    -- nothing because the snapshot filter already answered the click.
    ReSort()
    local now = GetTime()
    if (now - (self._lastServerSearch or 0)) < 10 then return end
    local sp = _G.LFGListFrame and _G.LFGListFrame.SearchPanel
    if not (sp and sp:IsShown()) then return end
    self._lastServerSearch = now
    -- C_LFGList.Search is HasRestrictions. It is reached SYNCHRONOUSLY
    -- from the click handler: deferring to a timer sheds the hardware
    -- context and produces ADDON_ACTION_BLOCKED. Whether an ordinary
    -- OnClick counts as legal provenance is UNVERIFIED -- inherited from
    -- the reference, which ships it working, and exercised by the smoke.
    if C_LFGList and C_LFGList.Search and sp.categoryID then
        local filters = ResolveCategoryFilters(sp.categoryID, sp.filters)
        local languages = C_LFGList.GetLanguageSearchFilter and C_LFGList.GetLanguageSearchFilter()
        local adv = IsDungeonSearchMode() and C_LFGList.GetAdvancedFilter and C_LFGList.GetAdvancedFilter() or nil
        local ok = pcall(C_LFGList.Search, sp.categoryID, filters, sp.preferredFilters, languages, nil, adv)
        if ok then return end
    end
    if _G.LFGListSearchPanel_DoSearch then
        _G.LFGListSearchPanel_DoSearch(sp)
    end
end

-- Re-run a button's own OnEnter so its tooltip redraws IN PLACE after a
-- click. GameTooltip otherwise keeps the lines built on the last
-- mouse-enter, and since the cursor never leaves the button, OnLeave/OnEnter
-- do not fire again -- the user has to move off and back on to see the new
-- state (smoke D-6). The button's own label updates immediately, which is
-- what made the stale tooltip obvious.
--
-- Guarded twice on purpose: still hovered AND the tooltip still belongs to
-- this button, so a programmatic state change can never hijack a tooltip
-- some other frame owns.
local function RefreshTooltip(btn)
    if not (btn and btn.IsMouseOver and btn:IsMouseOver()) then return end
    if _G.GameTooltip:GetOwner() ~= btn then return end
    local onEnter = btn:GetScript("OnEnter")
    if onEnter then onEnter(btn) end
end

-- Dungeon art for a filter toggle, keyed on the activity group's NAME.
--
-- The two IDs are different namespaces and there is no bridge between them:
-- the filter pane works in activityGroupIDs, GetActivityGroupInfo returns a
-- name and nothing else, and the art lives on C_ChallengeMode.GetMapUIInfo,
-- which is keyed on the challenge map. Matching by name is the only route
-- that does not hardcode a per-season table.
--
-- Built once per session and only cached once it actually found something --
-- GetMapTable can come back empty before the map info has arrived, and
-- caching that would leave every toggle iconless for the rest of the session.
local iconByName
local function DungeonIcon(name)
    if not name then return nil end
    if not iconByName then
        local maps = C_ChallengeMode and C_ChallengeMode.GetMapTable
            and C_ChallengeMode.GetMapTable()
        if not maps then return nil end
        local built, found = {}, false
        for _, cmID in ipairs(maps) do
            local mapName, _, _, tex = C_ChallengeMode.GetMapUIInfo(cmID)
            if mapName and tex and tex ~= 0 then
                built[mapName] = tex
                found = true
            end
        end
        if not found then return nil end
        iconByName = built
    end
    return iconByName[name]
end

local function SetToggleVisual(btn, active)
    if btn.selTex then btn.selTex:SetShown(active and true or false) end
end

-- `iconTex` is optional. When given, the dungeon art sits at the LEFT edge
-- and the label centres in the space beside it; without it the label centres
-- across the whole button, which is what the role and sort toggles want.
local function MakeToggle(parent, S, label, getter, onClick, iconTex)
    local btn = CreateFrame("Button", nil, parent)
    local accent = Accent()
    S.Button(btn)
    local t = btn:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(accent[1], accent[2], accent[3], 0.15)
    local anchor = S.GetBackdrop(btn) or btn
    t:SetPoint("TOPLEFT", anchor, "TOPLEFT", 1, -1)
    t:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -1, 1)
    t:Hide()
    btn.selTex = t

    if iconTex then
        -- 1px black frame under the art. KE:AddIconBorders needs a frame and
        -- this is a texture, so the backing plate is drawn by hand; the crop
        -- still goes through the shared helper.
        local border = btn:CreateTexture(nil, "BACKGROUND")
        border:SetColorTexture(0, 0, 0, 1)
        border:SetPoint("LEFT", anchor, "LEFT", 3, 0)
        border:SetSize(TOGGLE_ICON + 2, TOGGLE_ICON + 2)
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("CENTER", border, "CENTER")
        icon:SetSize(TOGGLE_ICON, TOGGLE_ICON)
        icon:SetTexture(iconTex)
        KE:ApplyIconZoom(icon)
        btn.icon = icon
    end

    local fs = btn:CreateFontString(nil, "OVERLAY")
    S.SetFont(fs, 12, "")
    if iconTex then
        fs:SetPoint("LEFT", btn, "LEFT", TOGGLE_ICON + 9, 0)
        fs:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
        fs:SetJustifyH("CENTER")
    else
        fs:SetPoint("CENTER")
    end
    fs:SetText(label)
    fs:SetWordWrap(false)
    btn.text = fs
    btn:SetScript("OnClick", function(b)
        -- Gate goes HERE, before onClick -- not around the refresh. Every
        -- one of these callbacks mutates the profile on its first
        -- statement, and a mutation on a stranded panel outlives the hide.
        if not IsActive() then return end
        onClick(b)
        SetToggleVisual(b, getter())
    end)
    SetToggleVisual(btn, getter())
    return btn
end

local function CreateFilterPanel()
    if panel.filters then return panel.filters end
    local S = KE.Skins
    if not S or not GFP.db then return nil end
    GFP.db.DungeonFilter = GFP.db.DungeonFilter or {}
    local accent = Accent()

    -- Bottom stops ABOVE the weekly-runs footer, which shares the panel and
    -- stays visible in M+ mode -- anchoring to the panel's own bottom edge
    -- put the Reset button on top of the footer text.
    local f = CreateFrame("Frame", nil, panel)
    f:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -(AFFIX_SIZE + 14))
    if panel.footer then
        f:SetPoint("BOTTOMRIGHT", panel.footer, "TOPRIGHT", 0, BUTTON_GAP)
    else
        f:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 12)
    end
    panel.filters = f

    local title = f:CreateFontString(nil, "OVERLAY")
    S.SetFont(title, 14, "")
    -- Sits low in its own space so it reads as a heading for the dungeon
    -- grid below rather than as a caption on the affix row above.
    title:SetPoint("TOP", f, "TOP", 0, -5)
    title:SetText("Filters")
    title:SetTextColor(accent[1], accent[2], accent[3])

    -- Deviation 12: every visual written during construction is collected
    -- here so ApplySettings can re-apply them. CreateFilterPanel returns
    -- the built pane on later calls, so it cannot serve as the refresh.
    local visualRefreshers = {}

    -- Dungeon toggles: two-column grid from the live season groups.
    local groups = SeasonGroups()
    local col, rowN = 0, 0
    local BW = (PANEL_WIDTH - 20 - BUTTON_GAP) / 2
    local ROW_PITCH = TOGGLE_HEIGHT + 4
    for _, groupID in ipairs(groups) do
        local name = C_LFGList.GetActivityGroupInfo and C_LFGList.GetActivityGroupInfo(groupID)
        if name then
            local btn = MakeToggle(f, S, Abbreviate(name),
                function() return GFP.db and GFP.db.DungeonFilter[groupID] end,
                function()
                    local db = GFP.db
                    if not db then return end
                    db.DungeonFilter[groupID] = not db.DungeonFilter[groupID] or nil
                    GFP:ApplyAndRefresh()
                end,
                DungeonIcon(name))
            btn:SetSize(BW, TOGGLE_HEIGHT)
            btn:SetPoint("TOPLEFT", f, "TOPLEFT", col * (BW + BUTTON_GAP), -22 - rowN * ROW_PITCH)
            btn:SetScript("OnEnter", function(b)
                _G.GameTooltip:SetOwner(b, "ANCHOR_TOP")
                _G.GameTooltip:SetText(name, 1, 1, 1)
                _G.GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
            visualRefreshers[#visualRefreshers + 1] = function()
                SetToggleVisual(btn, GFP.db and GFP.db.DungeonFilter[groupID])
            end
            col = col + 1
            if col == 2 then col = 0; rowN = rowN + 1 end
        end
    end
    if col == 1 then rowN = rowN + 1 end
    local y = -22 - rowN * ROW_PITCH - 8

    -- Needs Role / Has Tank / Has Healer
    local pf = MakeToggle(f, S, "Role Available",
        function() return GFP.db and GFP.db.PartyFit end,
        function()
            local db = GFP.db
            if not db then return end
            db.PartyFit = not db.PartyFit
            GFP:ApplyAndRefresh()
        end)
    pf:SetSize(PANEL_WIDTH - 20, TOGGLE_HEIGHT)
    pf:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)
    visualRefreshers[#visualRefreshers + 1] = function()
        SetToggleVisual(pf, GFP.db and GFP.db.PartyFit)
    end
    y = y - (TOGGLE_HEIGHT + BUTTON_GAP)

    local ht = MakeToggle(f, S, "Has Tank",
        function() return GFP.db and GFP.db.HasTank end,
        function()
            local db = GFP.db
            if not db then return end
            db.HasTank = not db.HasTank
            GFP:ApplyAndRefresh()
        end)
    ht:SetSize(BW, TOGGLE_HEIGHT)
    ht:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)
    visualRefreshers[#visualRefreshers + 1] = function()
        SetToggleVisual(ht, GFP.db and GFP.db.HasTank)
    end

    local hh = MakeToggle(f, S, "Has Healer",
        function() return GFP.db and GFP.db.HasHealer end,
        function()
            local db = GFP.db
            if not db then return end
            db.HasHealer = not db.HasHealer
            GFP:ApplyAndRefresh()
        end)
    hh:SetSize(BW, TOGGLE_HEIGHT)
    hh:SetPoint("TOPLEFT", f, "TOPLEFT", BW + BUTTON_GAP, y)
    visualRefreshers[#visualRefreshers + 1] = function()
        SetToggleVisual(hh, GFP.db and GFP.db.HasHealer)
    end
    y = y - (TOGGLE_HEIGHT + 10)

    -- Sort: click cycles the modes; the arrow toggles direction. Reorders
    -- the current list immediately.
    local sortTitle = f:CreateFontString(nil, "OVERLAY")
    S.SetFont(sortTitle, 12, "")
    sortTitle:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)
    sortTitle:SetText("Sort")
    sortTitle:SetTextColor(accent[1], accent[2], accent[3])
    y = y - 18

    local sortBtn = CreateFrame("Button", nil, f)
    S.Button(sortBtn)
    sortBtn:SetSize(PANEL_WIDTH - 20 - TOGGLE_HEIGHT - BUTTON_GAP, TOGGLE_HEIGHT)
    sortBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)
    local sortText = sortBtn:CreateFontString(nil, "OVERLAY")
    S.SetFont(sortText, 12, "")
    sortText:SetPoint("CENTER")
    local function SortLabel()
        local db = GFP.db
        local mode = SORT_MODE[(db and db.SortBy) or "DEFAULT"]
        sortText:SetText(mode and mode.text or "Default")
    end
    SortLabel()
    visualRefreshers[#visualRefreshers + 1] = SortLabel
    sortBtn:SetScript("OnEnter", function(b)
        local db = GFP.db
        _G.GameTooltip:SetOwner(b, "ANCHOR_TOP")
        _G.GameTooltip:SetText("Sort", 1, 1, 1)
        for _, key in ipairs(SORT_ORDER) do
            local isCur = ((db and db.SortBy) or "DEFAULT") == key
            if isCur then
                _G.GameTooltip:AddLine(SORT_MODE[key].text, accent[1], accent[2], accent[3])
            else
                _G.GameTooltip:AddLine(SORT_MODE[key].text, 0.85, 0.85, 0.85)
            end
        end
        _G.GameTooltip:Show()
    end)
    sortBtn:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
    sortBtn:SetScript("OnClick", function()
        -- This handler does not go through MakeToggle, so it needs its own
        -- gate -- and it mutates before it refreshes, same as the toggles.
        if not IsActive() then return end
        local db = GFP.db
        if not db then return end
        local cur = db.SortBy or "DEFAULT"
        for i, key in ipairs(SORT_ORDER) do
            if key == cur then
                db.SortBy = SORT_ORDER[(i % #SORT_ORDER) + 1]
                break
            end
        end
        SortLabel()
        RefreshTooltip(sortBtn)
        GFP:ApplyAndRefresh()
    end)

    local dirBtn = CreateFrame("Button", nil, f)
    S.ArrowButton(dirBtn, "down")
    dirBtn:SetSize(TOGGLE_HEIGHT, TOGGLE_HEIGHT)
    dirBtn:SetPoint("LEFT", sortBtn, "RIGHT", BUTTON_GAP, 0)
    local function DirVisual()
        local a = S.data(dirBtn).arrow
        if a then a:SetRotation((GFP.db and GFP.db.SortDescending ~= false) and 0 or 3.14159) end
    end
    DirVisual()
    visualRefreshers[#visualRefreshers + 1] = DirVisual
    dirBtn:SetScript("OnEnter", function(b)
        _G.GameTooltip:SetOwner(b, "ANCHOR_TOP")
        _G.GameTooltip:SetText((GFP.db and GFP.db.SortDescending ~= false)
            and "Descending" or "Ascending", 1, 1, 1)
        _G.GameTooltip:Show()
    end)
    dirBtn:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
    dirBtn:SetScript("OnClick", function()
        -- Same reason as sortBtn.
        if not IsActive() then return end
        local db = GFP.db
        if not db then return end
        -- Deviation 15. Was `not (db.SortDescending ~= false)`, which
        -- luacheck reports as W581. Identical for every value including
        -- nil: true->false, false->true, nil->false.
        db.SortDescending = (db.SortDescending == false)
        DirVisual()
        RefreshTooltip(dirBtn)  -- same stale-tooltip bug as sortBtn
        GFP:ApplyAndRefresh()
    end)

    -- The two action buttons share ONE row at the BOTTOM of the pane, not the
    -- running `y`. Two reasons: the dungeon grid's height changes with the
    -- season, so a top-down flow can push them into the footer; and stacking
    -- them cost a full row the pane does not have -- they ran into the sort
    -- row above.
    local searchBtn = CreateFrame("Button", nil, f)
    S.Button(searchBtn)
    searchBtn:SetSize(BW, BUTTON_HEIGHT)
    searchBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    local st = searchBtn:CreateFontString(nil, "OVERLAY")
    S.SetFont(st, 13, "")
    st:SetPoint("CENTER")
    st:SetText("Search")
    searchBtn:SetScript("OnClick", function()
        -- This calls ApplyAdvancedFilters directly, so gating
        -- ApplyAndRefresh does not cover it.
        if not IsActive() then return end
        GFP:ApplyAdvancedFilters()
        local sp = _G.LFGListFrame and _G.LFGListFrame.SearchPanel
        if not sp then return end
        if _G.LFGListSearchPanel_DoSearch then
            _G.LFGListSearchPanel_DoSearch(sp) -- hardware event: allowed
        end
    end)

    -- Reset: every filter back to its shipped default, which is the widest
    -- possible result list. Writes the profile directly rather than calling
    -- the individual toggles, so one refresh covers the whole pane.
    local resetBtn = CreateFrame("Button", nil, f)
    S.Button(resetBtn)
    resetBtn:SetSize(BW, BUTTON_HEIGHT)
    resetBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    local rt = resetBtn:CreateFontString(nil, "OVERLAY")
    S.SetFont(rt, 13, "")
    rt:SetPoint("CENTER")
    rt:SetText("Reset")
    resetBtn:SetScript("OnEnter", function(b)
        _G.GameTooltip:SetOwner(b, "ANCHOR_TOP")
        _G.GameTooltip:SetText("Reset Filters", 1, 1, 1)
        _G.GameTooltip:AddLine("Clears every dungeon and role filter and "
            .. "returns the sort to Default.", 0.85, 0.85, 0.85, true)
        _G.GameTooltip:Show()
    end)
    resetBtn:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
    resetBtn:SetScript("OnClick", function()
        -- Mutates the profile, so it needs the same gate the toggles carry.
        if not IsActive() then return end
        local db = GFP.db
        if not db then return end
        db.DungeonFilter = {}
        db.PartyFit = false
        db.HasTank = false
        db.HasHealer = false
        db.SortBy = "DEFAULT"
        db.SortDescending = true
        if f._refreshVisuals then f._refreshVisuals() end
        GFP:ApplyAndRefresh()
    end)

    -- Deviation 12's refresh routine. ApplySettings calls this; nothing
    -- else can, because every visual above is written at construction or
    -- on click.
    f._refreshVisuals = function()
        for _, fn in ipairs(visualRefreshers) do fn() end
    end

    return f
end

function GFP:UpdateMode()
    -- UpdateMode has NO enabled check in the reference and reaches
    -- SaveAdvancedFilter through ApplyAdvancedFilters, so a disabled
    -- module keeps overwriting the user's Blizzard filter settings on
    -- every category change.
    if not panel then return end
    if not IsActive() then return end
    local dungeonMode = IsDungeonSearchMode()
    if dungeonMode then
        local f = CreateFilterPanel()
        if f then f:Show() end
        if panel.quick then panel.quick:Hide() end
        self:ApplyAdvancedFilters()
    else
        if panel.filters then panel.filters:Hide() end
        if panel.quick then panel.quick:Show() end
    end
end

------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------

-- Deviation 13. The ONLY place the PGF question is asked. Evaluated at
-- call time, never cached: a cached boolean would be stale for the rest
-- of the session. Takes the FIRST return, loadedOrLoading -- deliberately
-- the opposite of the two sibling modules, which take `loaded` because
-- they wait for another addon's objects. This is a CONFLICT BAIL: if PGF
-- is merely loading, competing behaviour must still not be installed, or
-- both addons rewrite the same results table in the gap. No fallback to
-- the legacy global IsAddOnLoaded -- the 12.0.7 authority documents this
-- only under C_AddOns.
local function PGFPresent()
    return (C_AddOns and C_AddOns.IsAddOnLoaded
        and C_AddOns.IsAddOnLoaded("PremadeGroupsFilter")) and true or false
end

-- The single gate every resident effect reads. Note what is NOT here:
-- teardown. The config page clears db.Enabled BEFORE disabling the
-- module, so IsActive() is already false when OnDisable runs -- gating
-- teardown on it would skip the cleanup it exists to perform.
--
-- Assigned (not `local function`) because IsActive is forward-declared at
-- file scope, above CATEGORY_DATA -- every gate site earlier in this file
-- closes over that same upvalue, and a fresh `local function IsActive`
-- here would shadow it instead of filling it in.
IsActive = function()
    local db = GFP.db
    return (db and db.Enabled == true and not PGFPresent()) and true or false
end

function GFP:OnInitialize()
    self.db = KE.db and KE.db.profile and KE.db.profile.GroupFinderPanel
    -- Sanitize a sort mode that no longer exists in a saved profile.
    if self.db and self.db.SortBy and not SORT_MODE[self.db.SortBy] then
        self.db.SortBy = "DEFAULT"
    end
    -- Respect the saved toggle at login; Ace defaults modules to enabled.
    self:SetEnabledState((self.db and self.db.Enabled) == true)
end

-- Deviation 12. KE's profile manager calls this on every switch. Without
-- it the module keeps writing to the previous profile's table.
function GFP:UpdateDB()
    local old = self.db
    self.db = KE.db and KE.db.profile and KE.db.profile.GroupFinderPanel
    local new = self.db
    if not new then return end
    -- The six filter/sort keys are MODULE-SESSION state, independent of
    -- profile. On an enabled-to-enabled switch, carry the CURRENT values
    -- across rather than adopting whatever the incoming profile was left
    -- with in some past session -- a bare rebind resurrects stale filters.
    -- Newly enabling still runs the clean reset in OnEnable.
    if old and old ~= new and old.Enabled == true and new.Enabled == true then
        -- COPY DungeonFilter; aliasing would make two profiles share one
        -- table and every later write would land in both.
        local copy = {}
        for k, v in pairs(old.DungeonFilter or {}) do copy[k] = v end
        new.DungeonFilter  = copy
        new.HasTank        = old.HasTank
        new.HasHealer      = old.HasHealer
        new.PartyFit       = old.PartyFit
        new.SortBy         = old.SortBy
        new.SortDescending = old.SortDescending
    end
end

-- Deviation 12. Refresh() cannot do this: CreateFilterPanel returns the
-- already-built pane, and every filter visual is written at construction
-- or on click. Any path where the displayed values change without a click
-- needs this explicit re-apply.
function GFP:ApplySettings()
    if not IsActive() then return end
    if panel and panel.filters and panel.filters._refreshVisuals then
        panel.filters._refreshVisuals()
    end
    self:Refresh()
end

function GFP:Refresh()
    -- IsActive() folds into the existing condition. It does NOT
    -- early-return: the else branch below is what hides a panel stranded
    -- by a late conflict, and an early return would leave it on screen.
    local enabled = self:IsEnabled() and IsActive()
    local pve = _G.PVEFrame
    if enabled and pve and pve:IsShown() then
        local p = CreatePanel()
        if p then
            p:Show()
            -- CreateFrame births frames VISIBLE, so on the session's first
            -- open p:Show() is a no-op on an already-shown frame and the
            -- OnShow hook registered during CreatePanel never fires --
            -- the RIO wrap would only install at first CLOSE. Install
            -- from the show PATH instead of the show EVENT.
            EnsureRaiderIOWrap()
            if C_MythicPlus and C_MythicPlus.RequestMapInfo then C_MythicPlus.RequestMapInfo() end
            UpdateAffixes()
            UpdateRuns()
            self:UpdateMode()
        end
    else
        TeardownRaiderIO()
        if panel then panel:Hide() end
    end
end

function GFP:OnRosterChanged()
    -- No gate of its own: ApplyAdvancedFilters has one, and gating both
    -- would be two places to keep in sync.
    self:ApplyAdvancedFilters()
end

-- Recolour friend-group entry names ourselves -- BATTLENET_FONT_COLOR,
-- exactly what Blizzard's own (currently blind) branch would do.
-- Post-hook so we run after Blizzard's SetTextColor.
local entryHookInstalled = false
local function InstallEntryHook()
    if entryHookInstalled or not _G.LFGListSearchEntry_Update then return end
    entryHookInstalled = true
    hooksecurefunc("LFGListSearchEntry_Update", function(entry)
        if not IsActive() then
            if entry._keFriendBG then entry._keFriendBG:Hide() end
            return
        end
        local id = entry.resultID
        local isFriend = id and friendResultSet[id] or false
        -- Full blue backdrop, not just the name: created once per recycled
        -- button, toggled per update.
        if isFriend and not entry._keFriendBG then
            local bg = entry:CreateTexture(nil, "BACKGROUND", nil, 1)
            bg:SetPoint("TOPLEFT", 0, -1)
            bg:SetPoint("BOTTOMRIGHT", 0, 1)
            local c = _G.BATTLENET_FONT_COLOR
            bg:SetColorTexture(c and c.r or 0.51, c and c.g or 0.77, c and c.b or 1, 0.14)
            entry._keFriendBG = bg
        end
        if entry._keFriendBG then entry._keFriendBG:SetShown(isFriend) end
        if isFriend and entry.Name then
            local c = _G.BATTLENET_FONT_COLOR
            if c then entry.Name:SetTextColor(c.r, c.g, c.b) end
        end
    end)
end

function GFP:OnEnable()
    -- Deviation 6: the PGF bail comes FIRST. In the reference,
    -- InstallEntryHook and the session-state reset run ABOVE the bail, so
    -- a permanent unremovable hook plus six DB writes land even on the
    -- "stepping aside" path. Installing a permanent hook is not stepping
    -- aside. The hook is inert on that path -- friendResultSet is never
    -- populated -- but that is a reason it costs little to move, not a
    -- reason to leave it.
    if PGFPresent() then
        KE:Print("Group Finder Panel disabled: Premade Groups Filter is installed and provides the same filtering.")
        return
    end

    InstallEntryHook()
    -- Filters are session state, not preferences: every login and reload
    -- starts clean. This overwrites six of the seven saved keys -- every
    -- one except Enabled -- which is why the Core/Defaults.lua entries for
    -- SortBy and SortDescending are effectively dead.
    if self.db then
        self.db.DungeonFilter = {}
        self.db.HasTank = false
        self.db.HasHealer = false
        self.db.PartyFit = false
        self.db.SortBy = "OVERALL_SCORE"
        self.db.SortDescending = true
    end

    local pve = _G.PVEFrame
    if pve and not self.hooked then
        self.hooked = true
        pve:HookScript("OnShow", function() self:Refresh() end)
        pve:HookScript("OnHide", function() if panel then panel:Hide() end end)
    end
    self:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE", "Refresh")
    self:RegisterEvent("MYTHIC_PLUS_CURRENT_AFFIX_UPDATE", "Refresh")
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnRosterChanged")
    -- Our UpdateResultList hook fires once, but on first open the search
    -- is still in flight, so searchPanel.results is empty and we bail --
    -- and nothing re-filtered when the async results arrived. A /reload
    -- masked it because results were already cached.
    self:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED", function()
        local sp = _G.LFGListFrame and _G.LFGListFrame.SearchPanel
        if sp and sp:IsShown() then OnUpdateResultList(sp) end
    end)
    -- Pane switching follows the M+ search state. SetCategory covers the
    -- quick buttons and manual navigation; Show/Hide covers back-outs.
    if not self.modeHooks then
        self.modeHooks = true
        if _G.LFGListSearchPanel_SetCategory then
            hooksecurefunc("LFGListSearchPanel_SetCategory", function() self:UpdateMode() end)
        end
        if _G.LFGListSearchPanel_UpdateResultList then
            hooksecurefunc("LFGListSearchPanel_UpdateResultList", OnUpdateResultList)
        end
        if _G.LFGListSearchEntry_Update then
            hooksecurefunc("LFGListSearchEntry_Update", DecorateSearchEntry)
        end
        local sp = _G.LFGListFrame and _G.LFGListFrame.SearchPanel
        if sp then
            sp:HookScript("OnShow", function() self:UpdateMode() end)
            sp:HookScript("OnHide", function() self:UpdateMode() end)
        end
    end
    self:Refresh()
end

function GFP:OnDisable()
    self:UnregisterAllEvents()
    -- UNCONDITIONAL. IsActive() is already false by the time this runs,
    -- because the config page writes db.Enabled = false first.
    TeardownRaiderIO()
    if panel then panel:Hide() end
end

GFP._PGFPresent = PGFPresent
GFP._IsActive   = IsActive

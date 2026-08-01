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

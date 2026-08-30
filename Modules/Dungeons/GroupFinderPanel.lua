-- ╔══════════════════════════════════════════════════════════╗
-- ║  GroupFinderPanel.lua                                    ║
-- ║  Group Finder side panel                                 ║
-- ║  Purpose: affixes, a M+ dungeon/role filter pane and a    ║
-- ║           weekly runs footer, beside the M+ search.       ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- TAINT POSTURE -- read this before changing anything below.
-- Blizzard's Group Finder result provider must be created, populated and
-- assigned with no addon code in that execution. Three in-game probes each
-- showed on their own that violating it poisons the provider for the whole
-- session: later Blizzard-only refreshes then throw on Blizzard's own
-- SecretInChatMessagingLockdown fields with no addon frame on the stack, and
-- the errors follow the player back out of the instance.
--
-- So this module does NOT filter or sort the result list. It pushes the
-- user's choices into Blizzard's own advanced filter and lets Blizzard build
-- the list. Never reintroduce a pass over searchPanel.results, never call
-- LFGListSearchPanel_UpdateResults / _UpdateResultList / _DoSearch / _Clear /
-- _SelectResult, and never reorder Blizzard's table even in place. Never
-- show the search panel yourself either -- LFGListFrame_SetActivePanel onto
-- it is the same fault by another door.
--
-- Two rules, not one, because neither covers the other.
--
-- FIRST: for any write to live Blizzard Lua state, trace the readers. A field
-- written from our execution is not inert however trivial the setter looks --
-- our taint sits on it and travels into every Blizzard handler that reads it
-- later, and THAT handler's reach decides the damage, not ours. Two setters
-- that look harmless and are not: LFGListSearchPanel_SetCategory, whose three
-- fields are read by every UpdateResultList, and
-- LFGListCategorySelection_SelectCategory, whose one field is read by the Find
-- a Group button. Both cost a field failure to learn.
--
-- SECOND, and independent: keep our execution and our values out of any
-- synchronous chain that materializes the result provider. A direct call into
-- a provider builder is dangerous having written no field at all, so the first
-- rule would not catch it.
--
-- Explicit C API payload channels are NOT covered by the first rule and must
-- not be read as violations of it. Mutating the table C_LFGList.GetAdvancedFilter
-- returns and handing it to SaveAdvancedFilter is Blizzard's own idiom, used
-- by its own filter controls; the saved value is re-read through the C API,
-- not off a frame field we left behind. Judge those by their observed
-- boundary.
--
-- What it still does inside Blizzard's row update, as an accepted exception:
-- decorates rows (friend backdrop, leader score). That exception is the
-- design's one blocking assumption, not a proven safe pattern.
--
-- The module OWNS Blizzard's advanced filter while enabled, and restores it
-- when disabled -- see the ownership flag in the Lifecycle section. The filter
-- is account-wide (probed in game), which is why the flag lives in db.global.

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
-- for C_LFGList (Modules/Dungeons/LFGQuickCreate.lua,
-- Modules/Dungeons/LFGReminder.lua). Do NOT widen .luacheckrc instead.
-- C_SocialQueue may legitimately be nil here; every caller nil-checks it.
local C_LFGList = _G.C_LFGList
local C_SocialQueue = _G.C_SocialQueue
local bit = _G.bit
-- NOTE: KE.Skins is resolved at CALL time, not load time -- Dungeons.xml
-- loads before Skinning.xml in the toc, so a file-top capture is nil.
-- Never hoist it, even though every S.* name it uses does exist.

-- Sized to read comfortably next to the Group Finder.
local PANEL_WIDTH   = 220
local AFFIX_SIZE    = 34
local BUTTON_HEIGHT = 32
local BUTTON_GAP    = 6
local TOGGLE_HEIGHT = 30   -- filter-pane toggles, up from 24
local TOGGLE_ICON   = 22   -- dungeon icon, left of the short name

-- The panel's background stays on S.Backdrop, whose carrier is parented to
-- PVEFrame. A self-owned KE:ApplyBackdrop did not draw in game -- don't retry
-- it without an in-game probe first.

-- Themed rather than a hardcoded colour, so it tracks the user's accent. Read
-- once per function, keep each site's alpha.
local KE_PINK = { 1, 0, 0.549 }
local function Accent()
    return KE.Theme and KE.Theme.accent or KE_PINK
end

local DUNGEON_CAT = _G.GROUP_FINDER_CATEGORY_ID_DUNGEONS or 2

local panel

-- Forward declared, assigned in the Lifecycle section at the bottom of
-- this file. Every gate site above that section closes over this same
-- upvalue -- declaring IsActive inline down there (as `local function
-- IsActive`) would leave every earlier `IsActive()` read resolving to the
-- global namespace instead, which luacheck reports as W113 and which is nil
-- at call time. Declare where the readers are.
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

local function IsDungeonSearchMode()
    local pve, gff, lfg = _G.PVEFrame, _G.GroupFinderFrame, _G.LFGListFrame
    return pve and pve.activeTabIndex == 1
        and gff and gff.selection == _G.LFGListPVEStub
        -- IsShown, not IsVisible, only because the two lines above already
        -- walk this panel's ancestors by hand.
        and lfg and lfg.SearchPanel and lfg.SearchPanel:IsShown()
        and lfg.SearchPanel.categoryID == DUNGEON_CAT
end

-- Test seams. Nothing in the module reads these; they exist so the spec can
-- reach file-locals without exporting them into the module's real surface.
GFP._PlayerSpecRole      = PlayerSpecRole
GFP._GetPartyRoles       = GetPartyRoles
GFP._SeasonGroups        = SeasonGroups
GFP._IsDungeonSearchMode = IsDungeonSearchMode
GFP._Abbreviate          = Abbreviate

------------------------------------------------------------------------
-- Friend groups. While BROWSING on Midnight, search-result friend counts
-- come back empty/secret -- even Blizzard's own BATTLENET_FONT_COLOR branch
-- never fires. C_SocialQueue is the authoritative source: build a set of
-- friends' active LFGList searchResultIDs the way Blizzard_QuickJoin does.
--
-- Refreshed from the row decoration hook, throttled on a GetTime() stamp so
-- one provider repaint rebuilds the set once rather than per row. GetTime is
-- frame-cached, so an equality test coalesces a whole repaint; if that ever
-- stops holding the throttle degrades to per-row work, which costs
-- performance and not correctness.
------------------------------------------------------------------------
local friendResultSet = {}
local friendSetStamp = -1
local function RefreshFriendResultSet()
    local now = GetTime()
    if now == friendSetStamp then return end
    friendSetStamp = now
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

------------------------------------------------------------------------
-- Secret-value boundary for the ONE value this module still reads off a
-- search result: the leader's overall score, for row decoration.
--
-- GetSearchResultInfo is SecretInChatMessagingLockdown, and browsing the
-- group finder from inside a dungeon is ordinary. A pcall does not
-- declassify what it returns, so the test is issecretvalue on FIRST
-- CONTACT, inside the pcall -- issecretvalue is itself AllowedWhenUntainted
-- and can throw on an already-tainted path.
------------------------------------------------------------------------

local function Secret(v)
    return _G.issecretvalue and _G.issecretvalue(v)
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

GFP._SanitizeScore       = SanitizeScore
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
-- Re-apply the anchor's point so a changed panel state lands immediately.
-- Prefers the stored request over GetPoint, because GetPoint returns the
-- offset this module already adjusted and feeding that back compounds it.
local function ReassertRaiderIOPoint(anchor)
    local req = anchor.__keGFPReq
    if req then
        anchor:ClearAllPoints()
        anchor:SetPoint(req.p, req.rel, req.rp, req.x, req.y)
        return
    end
    local p1, p2, p3, p4, p5 = anchor:GetPoint(1)
    if p1 then
        anchor:ClearAllPoints()
        anchor:SetPoint(p1, p2, p3, p4, p5)
    end
end

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
            -- Record EVERY request, as it arrived, before any substitution.
            -- Two reasons, and the second is why this sits outside the branch
            -- below. A re-anchor replays this rather than the anchor's
            -- current point, because reading our own adjusted output back
            -- through this wrapper adjusts it again and the gap grows by a
            -- pixel per render. And storing only the requests we adjust would
            -- leave a stale one behind whenever the profile moves to a frame
            -- we do not own, so the next replay would drag it back to our
            -- edge.
            anchor.__keGFPReq = { p = p, rel = rel, rp = rp, x = x, y = y }
            if IsActive() and rel and (rel == _G.PVEFrame or rel == panel) then
                rel = (panel and panel:IsShown()) and panel or _G.PVEFrame
                -- RIO's stock x tucks the profile flush against the frame it
                -- anchors to. One screen pixel of daylight instead, against
                -- whichever frame currently owns the right edge.
                if type(x) == "number" then
                    x = x + KE:GetPixelSize()
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

    ReassertRaiderIOPoint(anchor)
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
        -- Replaying the stored request while inactive hands RIO its own
        -- geometry back, offset included.
        ReassertRaiderIOPoint(anchor)
    end
end

------------------------------------------------------------------------
-- Panel construction (lazy, once)
------------------------------------------------------------------------
local function CreatePanel()
    if panel then return panel end
    local pve = _G.PVEFrame
    local S = KE.Skins            -- CALL time. Never hoist.
    if not pve or not S then return nil end

    panel = CreateFrame("Frame", "KE_GroupFinderPanel", pve)
    panel:SetPoint("TOPLEFT", pve, "TOPRIGHT", 1, 0)
    panel:SetPoint("BOTTOMLEFT", pve, "BOTTOMRIGHT", 1, 0)
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
-- Mythic+ filter pane: dungeon toggles, Role Opening, Has Tank/Healer and
-- a minimum leader score. This is the panel's whole content; the panel is
-- only on screen while the M+ search is.
------------------------------------------------------------------------

-- The slider row is the authority whenever it exists. The widget throttles
-- OnValueChanged leading-edge and DROPS the trailing call, so the saved key
-- can sit one interaction behind what the player sees. Reading the region
-- also refreshes the key, which is what the profile carry then copies.
function GFP:CurrentMinScore()
    local db = self.db
    local row = self.minScoreRow
    if row then
        local v = math.floor(row:GetValue() + 0.5)
        if db then db.MinScore = v end
        return v
    end
    return (db and db.MinScore) or 0
end

-- Must be at least the widget's own 0.1s throttle window. A shorter delay
-- can fire in the gap between the last delivered callback and the dropped
-- one and save the pre-drop value -- and the dropped callback arms nothing,
-- so the final value would never reach the store at all.
local MIN_SCORE_SAVE_DELAY = 0.2
local minScoreTimer

-- NewTimer, not After: After returns no handle, and the invariant here is
-- that the newest interaction owns the one pending save.
local function ArmMinScoreSave()
    if minScoreTimer then minScoreTimer:Cancel() end
    minScoreTimer = C_Timer.NewTimer(MIN_SCORE_SAVE_DELAY, function()
        minScoreTimer = nil
        GFP:ApplyAdvancedFilters()
    end)
end

local function CancelMinScoreSave()
    if minScoreTimer then
        minScoreTimer:Cancel()
        minScoreTimer = nil
    end
end

GFP._ArmMinScoreSave = ArmMinScoreSave

-- The one place the module writes the player's SETTINGS into Blizzard's
-- filter, and the one place ownership is claimed. Every settings write
-- reaches SaveAdvancedFilter through here, so the IsActive() gate covers all
-- of them -- including the slider's trailing timer, which must not land
-- after a disable. RestorePermissiveFilter below is the other writer, and it
-- is ungated on purpose; do not fold the two together.
-- Returns whether the filter was actually written. Searching without that
-- write would send whichever settings the last owner left in place, so the
-- callers refuse rather than search on someone else's filter.
function GFP:ApplyAdvancedFilters()
    if not IsActive() then return false end
    local db = self.db
    if not db or not (C_LFGList and C_LFGList.GetAdvancedFilter) then return false end
    local adv = C_LFGList.GetAdvancedFilter()
    if not adv then return false end

    -- Only the fields this module exposes are written. Everything else --
    -- needsMyClass, the difficulty flags, the playstyles -- is whatever the
    -- player set in Blizzard's own filter UI, and stays.
    adv.hasTank    = db.HasTank == true
    adv.hasHealer  = db.HasHealer == true

    -- Party fit, degraded and deliberately so. Blizzard's needs* fields are
    -- single booleans: needsDamage means "fewer than three damagers", not
    -- "room for MINE". Exact for a party bringing 0-1 damagers, too
    -- permissive for 2-3. AdvancedFilterOptions has no vacancy count.
    if db.PartyFit then
        local roles = GetPartyRoles()
        adv.needsTank   = roles.TANK > 0
        adv.needsHealer = roles.HEALER > 0
        adv.needsDamage = roles.DAMAGER > 0
    else
        adv.needsTank, adv.needsHealer, adv.needsDamage = false, false, false
    end

    adv.minimumRating = self:CurrentMinScore()

    -- An EMPTY activities list is Blizzard's own "all" -- its default check
    -- is #activities == 0, and the list it would otherwise build includes
    -- timerunning groups a hand-rolled season+expansion list would miss.
    local activities = {}
    for groupID, on in pairs(db.DungeonFilter or {}) do
        if on then activities[#activities + 1] = groupID end
    end
    adv.activities = activities

    C_LFGList.SaveAdvancedFilter(adv)
    -- Ownership follows the WRITE, not the caller: everything above can
    -- return early, and a flag set without a write behind it would make the
    -- restore clobber a filter this module never touched.
    local g = KE.db and KE.db.global
    if g then g.GroupFinderPanelOwnsFilter = true end
    return true
end

-- The restore writer. Deliberately NOT gated by IsActive(): every caller
-- runs when the module is already off, standing down, or was never enabled
-- this session, so the gate would skip the cleanup it exists to perform.
--
-- Only writes when the ownership flag says this module put the current
-- filter there, so a filter set in Blizzard's own UI or by another addon is
-- never clobbered. An absent API leaves the flag set: clearing it would
-- relinquish ownership without restoring anything.
local function RestorePermissiveFilter()
    local g = KE.db and KE.db.global
    if not (g and g.GroupFinderPanelOwnsFilter) then return end
    if not (C_LFGList and C_LFGList.GetAdvancedFilter) then return end
    local adv = C_LFGList.GetAdvancedFilter()
    if not adv then return end
    adv.hasTank, adv.hasHealer = false, false
    adv.needsTank, adv.needsHealer, adv.needsDamage = false, false, false
    adv.minimumRating = 0
    adv.activities = {}
    C_LFGList.SaveAdvancedFilter(adv)
    g.GroupFinderPanelOwnsFilter = false
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

-- C_LFGList.Search is HasRestrictions and needs the click that asked for it
-- still on the stack: deferring to a timer sheds the hardware context and
-- produces ADDON_ACTION_BLOCKED. Whether an ordinary OnClick counts as legal
-- provenance is UNVERIFIED -- it works in practice and the smoke exercises it.
--
-- There is NO fallback, and never LFGListSearchPanel_DoSearch: it builds
-- the provider synchronously.
function GFP:RunSearch()
    local sp = _G.LFGListFrame and _G.LFGListFrame.SearchPanel
    -- IsVisible, not IsShown: only LFGListFrame_SetActivePanel hides this
    -- panel, so a shown-but-hidden one would take a real server search
    -- nobody can see.
    if not (sp and sp:IsVisible()) then return end
    if not (C_LFGList and C_LFGList.Search and sp.categoryID) then return end
    self._lastServerSearch = GetTime()
    local filters = ResolveCategoryFilters(sp.categoryID, sp.filters)
    local languages = C_LFGList.GetLanguageSearchFilter and C_LFGList.GetLanguageSearchFilter()
    local adv = IsDungeonSearchMode() and C_LFGList.GetAdvancedFilter
        and C_LFGList.GetAdvancedFilter() or nil
    pcall(C_LFGList.Search, sp.categoryID, filters, sp.preferredFilters, languages, nil, adv)
end

-- The Search button's action, and the escape from the window: always saves,
-- always searches. Named rather than inlined in the button's OnClick so the
-- rule can be verified without a frame.
function GFP:ManualSearch()
    if not IsActive() then return end
    if not self:ApplyAdvancedFilters() then return end
    self:RunSearch()
end

-- Toggle clicks: save first, then search only if the window has elapsed.
-- Saving always precedes searching, so no search can send stale state.
-- Inside the window the save still lands and nothing visible happens --
-- Blizzard re-reads the saved filter only when it repaints a row, which is
-- why its own filter UI repaints them by hand. We cannot copy that repaint:
-- LFGListSearchEntry_Update reads searchResultInfo.activityIDs from OUR
-- execution, which is the original failure signature inside a lockdown.
local SEARCH_WINDOW = 10
function GFP:ApplyAndRefresh()
    if not IsActive() then return end
    if not self:ApplyAdvancedFilters() then return end
    -- nil, not 0, is "never searched": GetTime counts from login, so a zero
    -- baseline would swallow every toggle for the first ten seconds of a
    -- session.
    local last = self._lastServerSearch
    if last and (GetTime() - last) < SEARCH_WINDOW then return end
    self:RunSearch()
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
    local pf = MakeToggle(f, S, "Role Opening",
        function() return GFP.db and GFP.db.PartyFit end,
        function()
            local db = GFP.db
            if not db then return end
            db.PartyFit = not db.PartyFit
            GFP:ApplyAndRefresh()
        end)
    pf:SetSize(PANEL_WIDTH - 20, TOGGLE_HEIGHT)
    pf:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)
    pf:SetScript("OnEnter", function(b)
        _G.GameTooltip:SetOwner(b, "ANCHOR_TOP")
        _G.GameTooltip:SetText("Role Opening", 1, 1, 1)
        -- Worded to promise exactly what the server filter delivers. Its
        -- needs* fields are single booleans, so a party bringing two or
        -- three damagers still matches a group with one open damage slot.
        _G.GameTooltip:AddLine("Show only groups with one opening for each "
            .. "role type your party brings.", 0.85, 0.85, 0.85, true)
        _G.GameTooltip:Show()
    end)
    pf:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
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

    -- Minimum leader score. Blizzard applies this as a floor on the leader's
    -- OVERALL Mythic+ rating, not a per-dungeon one.
    local G = KE.GUIFrame
    if G then
        local scoreRow = G:CreateSlider(f, "Min Score", {
            min = 0,
            max = 4000,
            step = 50,
            value = (GFP.db and GFP.db.MinScore) or 0,
            tooltip = "Hide groups whose leader is below this Mythic+ rating.",
            callback = function()
                -- The callback never writes the filter itself. It is
                -- throttled leading-edge and the trailing call is dropped,
                -- so the value handed to us can already be stale; the timer
                -- re-reads the slider region instead. One slider writer.
                if not IsActive() then return end
                ArmMinScoreSave()
            end,
        })
        scoreRow:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)
        scoreRow:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, y)
        GFP.minScoreRow = scoreRow
        visualRefreshers[#visualRefreshers + 1] = function()
            -- Silent: the display is what the save reads, so it must track
            -- the key without arming a save of its own.
            scoreRow:SetValue((GFP.db and GFP.db.MinScore) or 0, true)
        end
    end

    -- The two action buttons share ONE row at the BOTTOM of the pane, not the
    -- running `y`: the dungeon grid's height changes with the season, so a
    -- top-down flow can push them into the footer.
    local searchBtn = CreateFrame("Button", nil, f)
    S.Button(searchBtn)
    searchBtn:SetSize(BW, BUTTON_HEIGHT)
    searchBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    local st = searchBtn:CreateFontString(nil, "OVERLAY")
    S.SetFont(st, 13, "")
    st:SetPoint("CENTER")
    st:SetText("Search")
    searchBtn:SetScript("OnClick", function() GFP:ManualSearch() end)

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
            .. "removes the score floor.", 0.85, 0.85, 0.85, true)
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
        db.MinScore = 0
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
-- Assigned (not `local function`) because IsActive is forward-declared near
-- the top of the file -- every gate site earlier in this file closes over
-- that same upvalue, and a fresh `local function IsActive` here would shadow
-- it instead of filling it in.
IsActive = function()
    local db = GFP.db
    return (db and db.Enabled == true and not PGFPresent()) and true or false
end

function GFP:OnInitialize()
    self.db = KE.db and KE.db.profile and KE.db.profile.GroupFinderPanel
    -- Blizzard's advanced filter is account-wide, so a restrictive filter
    -- written on one character is live on every character -- including ones
    -- where this module never enables and OnEnable never runs. AceAddon
    -- calls OnInitialize regardless of enabled state, which makes it the
    -- only place that catches those. When the module WILL enable, OnEnable's
    -- one-shot write handles it and this does nothing.
    if not ((self.db and self.db.Enabled) == true and not PGFPresent()) then
        RestorePermissiveFilter()
    end
    -- Respect the saved toggle at login; Ace defaults modules to enabled.
    self:SetEnabledState((self.db and self.db.Enabled) == true)
end

-- Deviation 12. KE's profile manager calls this on every switch. Without
-- it the module keeps writing to the previous profile's table.
function GFP:UpdateDB()
    local old = self.db
    -- Reconcile BEFORE rebinding. The slider's save rides a trailing timer,
    -- so between the last drag and that timer the row holds a newer value
    -- than the key. Carrying the key would copy the older one, and the
    -- ApplySettings that follows this rebind would then push it back into
    -- the row -- losing the value the player actually chose.
    self:CurrentMinScore()
    self.db = KE.db and KE.db.profile and KE.db.profile.GroupFinderPanel
    local new = self.db
    if not new then return end
    -- The filter keys are MODULE-SESSION state, independent of
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
        new.MinScore       = old.MinScore
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

-- The WHOLE body is deferred. Its main driver is the PVEFrame OnShow hook,
-- and Blizzard materializes the result provider inside that same Show
-- execution -- so the RaiderIO reposition, the map info request, the affix
-- and run refreshes all sit in it too. Deferring one of four would not be a
-- rule. Nothing Blizzard does next reads any of this and the OnShow hook
-- discards the result, so a frame's delay costs nothing.
--
-- This is also the module's only visibility decision. The panel is the M+
-- filter pane and nothing else, so it is on screen exactly while the M+
-- search is, and RaiderIO gets the right edge back the rest of the time.
--
-- Widget show/hide only. NEVER write the filter from here, and deferring the
-- write does not make it safe. Most callers reach a provider build, where
-- Blizzard runs Clear, SetCategory, DoSearch and SetActivePanel back to back
-- and DoSearch reads the saved filter in that same execution -- a deferred
-- write lands a frame too late for it. Nothing needs writing: the filter
-- already holds the player's settings from login, their last control click,
-- or their last roster change.
function GFP:Refresh()
    C_Timer.After(0, function()
        -- IsActive() folds into the existing condition. It does NOT
        -- early-return: the else branch below is what hides a panel stranded
        -- by a late conflict, and an early return would leave it on screen.
        local enabled = self:IsEnabled() and IsActive()
        local pve = _G.PVEFrame
        if not (enabled and pve and pve:IsShown()) then
            -- A conflict can arrive mid-session. The conflict predicate is
            -- evaluated at call time, so a competing addon loading after
            -- OnEnable stands this module down here rather than through a
            -- disable, and the filter would otherwise stay claimed until the
            -- next reload. The restore is gated on the ownership flag, so it
            -- is a no-op on the ordinary closed-frame path.
            if not IsActive() then RestorePermissiveFilter() end
            TeardownRaiderIO()
            if panel then panel:Hide() end
            return
        end

        if IsDungeonSearchMode() then
            local p = CreatePanel()
            if p then
                p:Show()
                if C_MythicPlus and C_MythicPlus.RequestMapInfo then C_MythicPlus.RequestMapInfo() end
                UpdateAffixes()
                UpdateRuns()
                local f = CreateFilterPanel()
                if f then f:Show() end
            end
        elseif panel then
            panel:Hide()
        end

        -- OUTSIDE the mode branch, and after the panel has settled. The
        -- profile anchor needs its gap whether or not our panel is up, and
        -- the panel is absent in most views -- installing the wrapper from
        -- the panel's own show path would leave it unwrapped there.
        --
        -- Called from the show PATH rather than the show EVENT because
        -- CreateFrame births frames VISIBLE: on the session's first open
        -- p:Show() is a no-op on an already-shown frame, so the OnShow hook
        -- never fires and the wrapper would wait for the first CLOSE.
        EnsureRaiderIOWrap()
    end)
end

-- The trigger for a mid-session conflict. Refresh answers the question, but
-- nothing was asking it: a competing addon loading changes the call-time
-- predicate without touching the panel, the category, the roster or the
-- affixes, so no other input fires.
--
-- ADDON_LOADED fires once per addon, dozens of times at login, so the cheap
-- checks happen here rather than deferring a Refresh for each. Both are
-- needed: the restore hands the filter back, and the Refresh clears a panel
-- left on screen when the Group Finder was already open.
function GFP:OnAddonLoaded()
    if IsActive() then return end
    -- Two jobs, and only the first is about ownership. The panel can be on
    -- screen without the flag set, because the one-shot write at enable is
    -- allowed to fail and the panel does not depend on it -- so gating the
    -- refresh on ownership would leave that panel up.
    local g = KE.db and KE.db.global
    if g and g.GroupFinderPanelOwnsFilter then
        RestorePermissiveFilter()
    end
    -- Costs one deferred no-op per addon load while the module is off,
    -- dozens of times at login. Refresh's first act is a handful of nil
    -- checks, so that is cheaper than the addon query above it.
    self:Refresh()
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
        -- Throttled on the frame stamp, so one full list repaint costs one
        -- rebuild rather than one per row.
        RefreshFriendResultSet()
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
    -- The PGF bail comes FIRST. With InstallEntryHook and the session-state
    -- reset above it, a permanent unremovable hook and the whole key reset
    -- land even on the "stepping aside" path, and installing a permanent
    -- hook is not stepping aside.
    if PGFPresent() then
        -- Stepping aside is not enough on its own. AceAddon has already
        -- marked the module enabled and will not undo that, so a restrictive
        -- filter this module wrote in an earlier session would otherwise
        -- survive with our pane gone and no indication why results are thin.
        RestorePermissiveFilter()
        KE:Print("Group Finder Panel disabled: Premade Groups Filter is installed and provides the same filtering.")
        return
    end

    InstallEntryHook()
    -- Filters are session state, not preferences: every login and reload
    -- starts clean. This overwrites every LIVE filter key -- all except
    -- Enabled and the two dead sort keys nothing reads.
    if self.db then
        self.db.DungeonFilter = {}
        self.db.HasTank = false
        self.db.HasHealer = false
        self.db.PartyFit = false
        self.db.MinScore = 0
    end
    -- The pane survives a live disable, so its slider can still be showing
    -- the old value against the key just reset above -- and the slider is
    -- what every save reads. Push the reset into the display first.
    if panel and panel.filters and panel.filters._refreshVisuals then
        panel.filters._refreshVisuals()
    end
    -- One-shot write. Our keys reset every login while Blizzard's filter
    -- persists, so without this the two disagree until the player touches
    -- something. This is also what claims ownership.
    self:ApplyAdvancedFilters()

    local pve = _G.PVEFrame
    if pve and not self.hooked then
        self.hooked = true
        pve:HookScript("OnShow", function() self:Refresh() end)
        pve:HookScript("OnHide", function() if panel then panel:Hide() end end)
    end
    self:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE", "Refresh")
    self:RegisterEvent("MYTHIC_PLUS_CURRENT_AFFIX_UPDATE", "Refresh")
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnRosterChanged")
    self:RegisterEvent("ADDON_LOADED", "OnAddonLoaded")
    -- The panel follows the M+ search state, so every edge that can change
    -- it re-asks Refresh. SetCategory covers arriving at a category,
    -- Show/Hide covers back-outs. Refresh defers itself, so these do not.
    if not self.modeHooks then
        self.modeHooks = true
        if _G.LFGListSearchPanel_SetCategory then
            hooksecurefunc("LFGListSearchPanel_SetCategory", function() self:Refresh() end)
        end
        if _G.LFGListSearchEntry_Update then
            hooksecurefunc("LFGListSearchEntry_Update", DecorateSearchEntry)
        end
        local sp = _G.LFGListFrame and _G.LFGListFrame.SearchPanel
        if sp then
            sp:HookScript("OnShow", function() self:Refresh() end)
            sp:HookScript("OnHide", function() self:Refresh() end)
        end
    end
    self:Refresh()
end

function GFP:OnDisable()
    self:UnregisterAllEvents()
    -- Before the restore: a save armed just before this would otherwise land
    -- after it, rewrite the restrictive filter, and re-claim ownership on a
    -- module that is now off.
    CancelMinScoreSave()
    -- The filter this module writes CAN be restrictive, so leaving it behind
    -- would keep a player's score floor and dungeon picks active in
    -- Blizzard's own Group Finder with the module off.
    RestorePermissiveFilter()
    -- UNCONDITIONAL. IsActive() is already false by the time this runs,
    -- because the config page writes db.Enabled = false first.
    TeardownRaiderIO()
    if panel then panel:Hide() end
end

GFP._PGFPresent = PGFPresent
GFP._IsActive   = IsActive

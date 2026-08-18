-- ===========================================================================
-- Group Sort
--
-- Raid-lead tool that rearranges the raid into subgroups. Three modes:
--   default  one sorted list: tanks, melee, ranged, healers
--   split    two balanced halves
--   odds     groups 1/3/5 against groups 2/4/6
--
-- The sorting engine is reimplemented here rather than driven: the established
-- implementation of it lives in a private namespace with no public API and no
-- slash entry, so calling it is impossible.
--
-- Spec data comes from LibSpecialization, BigWigs's broadcast lib, so the
-- raid-wide broadcast network already exists wherever BigWigs does. Unknown
-- specs sort last, at spec order 100.
--
-- Two deliberate departures from the established behaviour, both mechanical:
--   * A read of an undeclared `indextosubgroup` global in one ArrangeGroups
--     branch is an `indexlink` read here; indexlink carries the same data.
--   * SplitGroupInit's MythicFlex flag is passed all the way through to
--     GetSortedGroup rather than dropped at the SortGroup hop.
--
-- The only user surface is the three sort buttons inside the Raid Control
-- panel (Modules/QoL/RaidControl.lua), which look for KE.GroupSort before
-- drawing them. There is no separate setting and no config page.
--
-- Reconciliation: one SetRaidSubgroup or SwapRaidSubgroup per pass, then wait
-- for the server's GROUP_ROSTER_UPDATE and recompute, repeating until the
-- roster matches the goal. 15-second backstop, 5-second cooldown between runs,
-- hard combat gate, lead/assist gate, and a chat-lockdown gate.
--
-- Performance: no OnUpdate anywhere. Work happens on a button press and on
-- GROUP_ROSTER_UPDATE while a sort is in flight.
-- ===========================================================================

---@class KE
local KE = select(2, ...)

local GS = {}
KE.GroupSort = GS

local _G = _G
local ipairs = ipairs
local GetTime = GetTime
local UnitGUID = UnitGUID
local UnitName = UnitName
local UnitClass = UnitClass
local UnitExists = UnitExists
local UnitInRaid = UnitInRaid
local UnitIsUnit = UnitIsUnit
local UnitFullName = UnitFullName
local GetInstanceInfo = GetInstanceInfo
local GetRaidRosterInfo = GetRaidRosterInfo
local GetRaidDifficultyID = GetRaidDifficultyID
local SetRaidSubgroup = _G.SetRaidSubgroup
local SwapRaidSubgroup = _G.SwapRaidSubgroup
local UnitIsGroupLeader = UnitIsGroupLeader
local UnitAffectingCombat = UnitAffectingCombat
local UnitIsGroupAssistant = _G.UnitIsGroupAssistant
local UnitGroupRolesAssigned = UnitGroupRolesAssigned

-- --- Classification tables --------------------------------------------------

local MELEE = { -- ignoring tanks for this
    [263]  = true, -- Shaman: Enhancement
    [255]  = true, -- Hunter: Survival
    [259]  = true, -- Rogue: Assassination
    [260]  = true, -- Rogue: Outlaw
    [261]  = true, -- Rogue: Subtlety
    [71]   = true, -- Warrior: Arms
    [72]   = true, -- Warrior: Fury
    [251]  = true, -- Death Knight: Frost
    [252]  = true, -- Death Knight: Unholy
    [103]  = true, -- Druid: Feral
    [70]   = true, -- Paladin: Retribution
    [269]  = true, -- Monk: Windwalker
    [577]  = true, -- Demon Hunter: Havoc
    [65]   = true, -- Paladin: Holy
    [270]  = true, -- Monk: Mistweaver
}

local LUST = {
    [263]  = true, [255]  = true, [1473] = true, [1467] = true,
    [253]  = true, [254]  = true, [262]  = true, [64]   = true,
    [62]   = true, [63]   = true, [1468] = true, [264]  = true,
}

local BRESS = {
    [66]   = true, [104]  = true, [250]  = true, [251]  = true,
    [252]  = true, [103]  = true, [70]   = true, [102]  = true,
    [265]  = true, [266]  = true, [267]  = true, [65]   = true,
    [105]  = true,
}

local SPEC_ORDER = {
    [0] = 100, -- offline / no data: sorted last
    -- Tanks
    [268] = 1, [66] = 2, [104] = 3, [73] = 4, [581] = 5, [250] = 6,
    -- Melee
    [263] = 7, [255] = 8, [251] = 9, [252] = 10, [259] = 11, [260] = 12,
    [261] = 13, [71] = 14, [72] = 15, [103] = 16, [70] = 17, [269] = 18,
    [577] = 19,
    -- Ranged
    [1480] = 20, [1473] = 21, [1467] = 22, [262] = 23, [258] = 24,
    [102] = 25, [265] = 26, [266] = 27, [267] = 28, [64] = 29, [62] = 30,
    [63] = 31, [253] = 32, [254] = 33,
    -- Healers
    [65] = 34, [270] = 35, [1468] = 36, [105] = 37, [264] = 38,
}
setmetatable(SPEC_ORDER, { __index = function() return 100 end })

-- --- Spec data via LibSpecialization ----------------------------------------

local specs = {} -- [GUID] = specID
local libSpecRegistered = false

local function RegisterLibSpec()
    if libSpecRegistered then return end
    local LS = LibStub and LibStub("LibSpecialization", true)
    if not LS then return end
    libSpecRegistered = true
    local _, myrealm = UnitFullName("player")
    LS.RegisterGroup(GS, function(specId, _, _, playerName)
        local name, realm = strsplit("-", playerName)
        if (not realm) or realm == "" then realm = myrealm end
        local found
        for i = 1, 40 do
            local unit = "raid" .. i
            if not UnitExists(unit) then break end
            local uname, urealm = UnitFullName(unit)
            if not urealm then urealm = myrealm end
            if uname == name and urealm == realm then found = unit break end
        end
        if not found and UnitExists("player") then
            local pname = UnitFullName("player")
            if pname == name then found = "player" end
        end
        if found then
            local G = UnitGUID(found)
            if G then specs[G] = specId end
        end
    end)
end

local function GetSpec(unit)
    local G = UnitGUID(unit)
    if not G or (issecretvalue and issecretvalue(G)) then return 0 end
    return specs[G] or 0
end

-- --- Engine state ------------------------------------------------------------

local Groups = { Processing = false }

-- --- Sorting -----------------------------------------------------------------

local function SpecCompare(a, b)
    if a.specid == b.specid then
        return a.GUID < b.GUID
    end
    return SPEC_ORDER[a.specid] < SPEC_ORDER[b.specid]
end

function GS:ShiftLeader(group)
    if not group then return end
    local currentpos, goalpos = 0, 0
    for i, v in ipairs(group) do
        if v.unitid and UnitIsGroupLeader(v.unitid) then
            currentpos = i
            -- tanks stay first in their current group; others go first in a
            -- non-first group so they don't sit above the tanks (unless the
            -- raid is tiny)
            goalpos = (v.role == "TANK" and math.floor((i - 1) / 5) * 5 + 1)
                or (i > 5 and math.floor((i - 1) / 5) * 5 + 1)
                or (#group > 5 and 6) or 1
        end
    end
    if goalpos ~= 0 and currentpos ~= goalpos then
        local leaderunit = group[currentpos]
        if currentpos > goalpos then
            for i = currentpos, goalpos + 1, -1 do group[i] = group[i - 1] end
        else
            for i = currentpos, goalpos - 1 do group[i] = group[i + 1] end
        end
        group[goalpos] = leaderunit
    end
    return group
end

function GS:GetSortedGroup(Flex, default, odds, MythicFlex)
    local units = {}
    local lastgroup = (MythicFlex and 5) or (Flex and 6) or 4
    local total = { ALL = 0, TANK = 0, HEALER = 0, DAMAGER = 0, NONE = 0 }
    local poscount = { 0, 0, 0, 0, 0 }
    for i = 1, 40 do
        local subgroup = select(3, GetRaidRosterInfo(i))
        local unit = "raid" .. i
        if not UnitExists(unit) then break end
        local specid = GetSpec(unit)
        local class = select(3, UnitClass(unit))
        local role = UnitGroupRolesAssigned(unit)
        if subgroup and subgroup <= lastgroup then
            total[role] = (total[role] or 0) + 1
            total.ALL = total.ALL + 1
            local melee = MELEE[specid]
            local pos = (role == "TANK" and 5)
                or (melee and (role == "DAMAGER" and 1 or 2))
                or (role == "DAMAGER" and 3) or 4
            poscount[pos] = poscount[pos] + 1
            units[#units + 1] = {
                name = UnitName(unit), processed = false, unitid = unit,
                specid = specid, index = i, role = role, class = class,
                pos = pos, canlust = LUST[specid], canress = BRESS[specid],
                GUID = UnitGUID(unit) or "",
            }
        end
    end
    table.sort(units, SpecCompare)
    Groups.total = total.ALL

    if default then
        return self:ShiftLeader(units)
    end

    -- Split: balance two sides by role, position, class, bress, lust, spec.
    local sides = { left = {}, right = {} }
    local classes = { left = {}, right = {} }
    local specsSeen = { left = {}, right = {} }
    local pos = { left = { 0, 0, 0, 0, 0 }, right = { 0, 0, 0, 0, 0 } }
    local roles = { left = {}, right = {} }
    local lust = { left = false, right = false }
    local bress = { left = 0, right = 0 }
    for i = 1, 3 do
        local role = (i == 1 and "TANK") or (i == 2 and "HEALER") or "DAMAGER"
        roles.left.role, roles.right.role = 0, 0
        for _, v in ipairs(units) do
            if v.role == role then
                local side
                if role == "TANK" then side = roles.left.role <= roles.right.role and "left" or "right"
                elseif #sides.left >= total.ALL / 2 then side = "right"
                elseif #sides.right >= total.ALL / 2 then side = "left"
                elseif roles.left.role >= (total[role] or 0) / 2 then side = "right"
                elseif roles.right.role >= (total[role] or 0) / 2 then side = "left"
                elseif pos.left[v.pos] >= poscount[v.pos] / 2 then side = "right"
                elseif pos.right[v.pos] >= poscount[v.pos] / 2 then side = "left"
                elseif classes.right[v.class] and not classes.left[v.class] then side = "left"
                elseif classes.left[v.class] and not classes.right[v.class] then side = "right"
                elseif (not classes.left[v.class]) and (not classes.right[v.class]) then
                    side = (pos.left[v.pos] > pos.right[v.pos] and "right") or "left"
                elseif v.canress and (bress.left <= 1 or bress.right <= 1) then
                    side = (bress.left <= 1 and bress.left <= bress.right and "left") or "right"
                elseif v.canlust and ((not lust.left) or (not lust.right)) then
                    side = ((not lust.left) and "left") or "right"
                elseif specsSeen.left[v.specid] and not specsSeen.right[v.specid] then side = "right"
                elseif specsSeen.right[v.specid] and not specsSeen.left[v.specid] then side = "left"
                elseif (not specsSeen.left[v.specid]) and (not specsSeen.right[v.specid]) then
                    side = (pos.left[v.pos] > pos.right[v.pos] and "right") or "left"
                else
                    side = (#sides.left > #sides.right and "right") or "left"
                end

                sides[side][#sides[side] + 1] = v
                classes[side][v.class] = true
                pos[side][v.pos] = pos[side][v.pos] + 1
                if v.canlust then lust[side] = true end
                if v.canress then bress[side] = bress[side] + 1 end
                specsSeen[side][v.specid] = (specsSeen[side][v.specid] or 0) + 1
                roles[side].role = (roles[side].role or 0) + 1
            end
        end
    end
    table.sort(sides.left, SpecCompare)
    table.sort(sides.right, SpecCompare)
    sides.left = self:ShiftLeader(sides.left)
    sides.right = self:ShiftLeader(sides.right)

    units = {}
    if odds then -- groups 1/3/5 vs 2/4/6
        for i, v in ipairs(sides.left) do
            if i > 10 then i = i + 10 elseif i > 5 then i = i + 5 end
            units[i] = v
        end
        for i, v in ipairs(sides.right) do
            if i > 10 then i = i + 15 elseif i > 5 then i = i + 10 else i = i + 5 end
            units[i] = v
        end
    else -- contiguous halves
        for i, v in ipairs(sides.left) do units[i] = v end
        local offset = (total.ALL > 20 and 15) or (total.ALL > 10 and 10) or 5
        for i, v in ipairs(sides.right) do units[i + offset] = v end
    end
    return units
end

function GS:SortGroup(Flex, default, odds, MythicFlex)
    Groups.units = self:GetSortedGroup(Flex, default, odds, MythicFlex)
    self:ArrangeGroups(true)
end

-- --- Server reconciliation ---------------------------------------------------

function GS:ArrangeGroups(firstcall, finalcheck)
    if not firstcall and not Groups.Processing then return end
    local now = GetTime()
    if firstcall then
        Groups.Processing = true
        Groups.Processed = 0
        Groups.ProcessStart = now
        for i = 1, 40 do
            local group = math.ceil(i / 5)
            local subgrouppos = i % 5 == 0 and 5 or i % 5
            if Groups.units[i] then
                Groups.units[i].group = group
                Groups.units[i].subgrouppos = subgrouppos
                Groups.units[i].pos = ((group - 1) * 5) + subgrouppos
                if Groups.units[i].processed then Groups.Processed = Groups.Processed + 1 end
            end
        end
    end
    if Groups.ProcessStart and now > Groups.ProcessStart + 15 then
        Groups.Processing = false
        return -- backstop: probably looping
    end

    local groupSize = { 0, 0, 0, 0, 0, 0, 0, 0 }
    local postoindex = {}
    local indexlink = {}
    for i = 1, 40 do indexlink[i] = {} end
    for i = 1, 40 do
        local name, _, subgroup = GetRaidRosterInfo(i)
        if not name then break end
        groupSize[subgroup] = groupSize[subgroup] + 1
        postoindex[((subgroup - 1) * 5) + groupSize[subgroup]] = i
        indexlink[i] = { subgroup = subgroup, pos = ((subgroup - 1) * 5) + groupSize[subgroup] }
    end

    if Groups.Processed >= Groups.total then
        if finalcheck then
            local allprocessed = true
            for i = 1, 40 do
                local v = Groups.units[i]
                if v and v.name then
                    local index = UnitInRaid(v.name)
                    if postoindex[v.pos] ~= index then
                        v.processed = false
                        allprocessed = false
                        Groups.Processed = Groups.Processed - 1
                    end
                end
            end
            if allprocessed then
                Groups.Processing = false
                return
            end
        else
            self:ArrangeGroups(false, true)
            return
        end
    end

    for i = 1, 40 do -- table position == goal position
        local v = Groups.units[i]
        if v and (not v.processed) and v.name and (not UnitAffectingCombat(v.name)) then
            local index = UnitInRaid(v.name)
            local indexgoal = postoindex[v.pos]
            if indexgoal ~= index then
                if index and groupSize[v.group] < v.subgrouppos and indexlink[index].subgroup ~= v.group then
                    if groupSize[v.group] + 1 == v.subgrouppos then
                        -- next free spot is the right one (verified again next call)
                        SetRaidSubgroup(index, v.group)
                        break
                    else
                        -- group too empty to land this player in the right slot:
                        -- move someone not-yet-correct into it first
                        for j = 1, 40 do
                            if i ~= j then
                                local u = Groups.units[j]
                                local uidx = u and u.name and UnitInRaid(u.name)
                                if u and (not u.processed) and uidx and indexlink[uidx]
                                    and v.group ~= indexlink[uidx].subgroup then
                                    SetRaidSubgroup(uidx, v.group)
                                    break
                                end
                            end
                        end
                        break
                    end
                elseif indexgoal and index and indexlink[index] and indexlink[index].subgroup
                    and indexlink[indexgoal] and indexlink[indexgoal].subgroup
                    and indexlink[index].subgroup ~= indexlink[indexgoal].subgroup
                    and UnitExists("raid" .. indexgoal)
                    and (not UnitAffectingCombat("raid" .. indexgoal)) then
                    SwapRaidSubgroup(indexgoal, index)
                    v.processed = true
                    Groups.Processed = Groups.Processed + 1
                    break
                elseif index then -- swap targets share a group: swap via a third
                    local found = false
                    local u = Groups.units[indexlink[index].pos]
                    local uidx = u and u.name and UnitInRaid(u.name)
                    if u and u.name and (not UnitAffectingCombat(u.name))
                        and (not UnitIsUnit(v.name, u.name)) and u.pos == indexlink[index].pos
                        and uidx and indexlink[uidx]
                        and indexlink[index].subgroup ~= indexlink[uidx].subgroup then
                        SwapRaidSubgroup(uidx, index)
                        found = true
                    end
                    if not found then
                        for j = 1, 40 do
                            local w = Groups.units[j]
                            local widx = w and w.name and UnitInRaid(w.name)
                            if w and (not w.processed) and w.name and (not UnitAffectingCombat(w.name))
                                and (not UnitIsUnit(v.name, w.name)) and widx and indexlink[widx]
                                and indexlink[index].subgroup ~= indexlink[widx].subgroup then
                                SwapRaidSubgroup(widx, index)
                                found = true
                                break
                            end
                        end
                    end
                    if not found then
                        for j = 1, 40 do
                            local w = Groups.units[j]
                            local widx = w and w.name and UnitInRaid(w.name)
                            if w and w.name and (not UnitIsGroupLeader(w.name))
                                and (not UnitAffectingCombat(w.name))
                                and (not UnitIsUnit(v.name, w.name)) and widx and indexlink[widx]
                                and indexlink[index].subgroup ~= indexlink[widx].subgroup then
                                SwapRaidSubgroup(widx, index)
                                found = true
                                break
                            end
                        end
                    end
                    if not found then
                        for j = 1, 8 do
                            if indexlink[index].subgroup ~= j and groupSize[j] < 5 then
                                SetRaidSubgroup(index, j)
                                break
                            end
                        end
                    end
                    break
                end
            else
                v.processed = true
                Groups.Processed = Groups.Processed + 1
                self:ArrangeGroups(false, true)
                break
            end
        end
    end
end

-- --- Public entry ------------------------------------------------------------

local lastRun

-- Shift-click on either arrangement button. The 15s in-progress lock is a
-- backstop against a sort that loops, but until it expires every press is
-- refused -- so there has to be a way out that is not waiting it out.
function GS:Cancel()
    if not Groups.Processing then
        KE:Print("Group Sort: nothing running.")
        return
    end
    Groups.Processing = false
    Groups.ProcessStart = nil
    lastRun = nil -- do not also make them sit out the run cooldown
    KE:Print("Group Sort: cancelled.")
end

function GS:Run(mode) -- "default" | "split" | "odds"
    -- Whether spec broadcasts have already been arriving decides whether the
    -- sort can start immediately -- see the delay at the end of this function.
    local hadSpecData = libSpecRegistered
    RegisterLibSpec()
    -- Hard combat gate: the buttons grey out too, but keybinds, macros, and
    -- edge-of-combat clicks all land here.
    if _G.InCombatLockdown() or UnitAffectingCombat("player") then
        KE:Print("Group Sort: not available in combat.")
        return
    end
    if _G.C_ChatInfo and _G.C_ChatInfo.InChatMessagingLockdown
        and _G.C_ChatInfo.InChatMessagingLockdown() then
        KE:Print("Group Sort: addon messages are restricted right now; try again shortly.")
        return
    end
    if not ((UnitIsGroupAssistant("player") or UnitIsGroupLeader("player")) and UnitInRaid("player")) then
        KE:Print("Group Sort: requires raid lead or assist.")
        return
    end
    local now = GetTime()
    if Groups.Processing and Groups.ProcessStart and now < Groups.ProcessStart + 15 then
        KE:Print("Group Sort: a sort is still in progress, please wait.")
        return
    end
    if lastRun and lastRun > now - 5 then
        KE:Print("Group Sort: please wait 5 seconds between sorts.")
        return
    end
    lastRun = now
    local default = mode == "default"
    local odds = mode == "odds"
    local Flex, MythicFlex = true, false
    local _, instanceType, difficultyID = GetInstanceInfo()
    difficultyID = (instanceType == "raid" and difficultyID) or GetRaidDifficultyID() or 0
    if difficultyID == 16 then Flex = false end
    if difficultyID == 233 then MythicFlex = true end
    -- RegisterLibSpec runs at login, so by the time anyone presses a button
    -- the data has normally been arriving all session. The fixed 2s pause was
    -- why a press looked like it did nothing: every refusal prints, so
    -- silence meant the sort was accepted and sitting in a timer.
    if hadSpecData then
        self:SortGroup(Flex, default, odds, MythicFlex)
    else
        _G.C_Timer.After(2, function() self:SortGroup(Flex, default, odds, MythicFlex) end)
    end
end

-- --- Continuation driver -----------------------------------------------------

local driver = CreateFrame("Frame")
driver:RegisterEvent("GROUP_ROSTER_UPDATE")
driver:RegisterEvent("PLAYER_LOGIN")
driver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        RegisterLibSpec() -- start collecting broadcasts early
    elseif Groups.Processing then
        GS:ArrangeGroups()
    end
end)

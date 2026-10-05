-- ╔══════════════════════════════════════════════════════════╗
-- ║  Core/CDMIcons.lua                                       ║
-- ║  Purpose: find an icon in Blizzard's Cooldown Manager by ║
-- ║           spell id, and call back after a re-layout.     ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- Reads only. Viewer icons are pooled and handed other cooldowns on every
-- re-layout, so a consumer finds its icon again on each Watch callback,
-- never keeps one across callbacks, and parents only its own frames to it.

---@class KE
local KE = select(2, ...)

local _G = _G
local CreateFrame = CreateFrame
local C_Timer = C_Timer
local hooksecurefunc = hooksecurefunc
local issecretvalue = issecretvalue
local next, pairs, ipairs, pcall, type = next, pairs, ipairs, pcall, type
local math_huge = math.huge

local ADDON = "Blizzard_CooldownViewer"

-- RefreshLayout re-deals the pooled frames, RefreshData re-assigns cooldowns
-- in place, and UpdateShownState is the only path a viewer hides through.
-- Each viewer copies these from its mixin at creation, so only a hook on the
-- viewer frame itself is ever reached.
local HOOKED_METHODS = { "RefreshLayout", "RefreshData", "UpdateShownState" }

local CDMIcons = {}
KE.CDMIcons = CDMIcons

CDMIcons.VIEWERS = {
    Essential = "EssentialCooldownViewer",
    Utility   = "UtilityCooldownViewer",
    BuffIcon  = "BuffIconCooldownViewer",
    BuffBar   = "BuffBarCooldownViewer",
}
CDMIcons.hooked = false

---------------------------------------------------------------------------------
-- Matching
---------------------------------------------------------------------------------
local function RankOf(ids, v, best)
    if issecretvalue(v) or v == nil then return best end
    local rank = ids[v]
    if rank and (not best or rank < best) then return rank end
    return best
end

-- ids maps spell id -> rank, 1 preferred. Returns the lowest rank found, or nil.
function CDMIcons.Matches(info, ids)
    if type(info) ~= "table" then return nil end
    local best = RankOf(ids, info.spellID, nil)
    best = RankOf(ids, info.overrideSpellID, best)
    best = RankOf(ids, info.overrideTooltipSpellID, best)
    local linked = info.linkedSpellIDs
    if not issecretvalue(linked) and type(linked) == "table" then
        for i = 1, #linked do
            best = RankOf(ids, linked[i], best)
        end
    end
    return best
end

-- A secret id is never passed on: the info API refuses secret arguments from
-- addon code.
local function InfoFor(frame)
    local getID = frame.GetCooldownID
    if not getID then return nil end
    local id = getID(frame)
    if issecretvalue(id) or id == nil then return nil end
    local api = _G.C_CooldownViewer
    local get = api and api.GetCooldownViewerCooldownInfo
    if not get then return nil end
    local ok, info = pcall(get, id)
    if not ok or type(info) ~= "table" then return nil end
    return info
end

-- The pool, not GetItemFrames: a buff icon is hidden while its buff is down,
-- and GetItemFrames lists shown icons only.
function CDMIcons.Find(viewerKey, ids)
    local name = CDMIcons.VIEWERS[viewerKey]
    local viewer = name and _G[name]
    if not viewer or not viewer:IsShown() then return nil end
    local pool = viewer.itemFramePool
    if not pool then return nil end
    local best, bestRank, bestSlot
    for frame in pool:EnumerateActive() do
        local rank = CDMIcons.Matches(InfoFor(frame), ids)
        if rank then
            local slot = frame.layoutIndex
            if type(slot) ~= "number" then slot = math_huge end
            if not best or rank < bestRank or (rank == bestRank and slot < bestSlot) then
                best, bestRank, bestSlot = frame, rank, slot
            end
        end
    end
    return best
end

---------------------------------------------------------------------------------
-- Watch
---------------------------------------------------------------------------------
local watchers = {}
local onRefreshes = {}
local runKeys = {}
local queued = false
local hookedViewers = {}
local waiter

-- Keys are copied first, so a callback may Watch or Unwatch during the run.
local function RunWatchers()
    queued = false
    local n = 0
    for key in next, watchers do
        n = n + 1
        runKeys[n] = key
    end
    for i = 1, n do
        local key = runKeys[i]
        runKeys[i] = nil
        local fn = watchers[key]
        if fn then fn() end
    end
end

-- Runs on every refresh of every viewer for the rest of the session once
-- hooked, so with nothing watched it is one table check. Blizzard has already
-- re-dealt the icons when this runs, and they are drawn only after the caller
-- returns: onRefresh is the one chance to pull a frame off a re-dealt icon
-- before it shows there. The search waits for the next frame, once.
local function OnViewerRefresh()
    if next(watchers) == nil then return end
    for _, onRefresh in next, onRefreshes do
        onRefresh()
    end
    if queued then return end
    queued = true
    C_Timer.After(0, RunWatchers)
end

local function HookViewers()
    for _, name in pairs(CDMIcons.VIEWERS) do
        local viewer = _G[name]
        if viewer and not hookedViewers[viewer] then
            hookedViewers[viewer] = true
            for _, method in ipairs(HOOKED_METHODS) do
                local original = viewer[method]
                if type(original) == "function" then
                    hooksecurefunc(viewer, method, OnViewerRefresh)
                end
            end
        end
    end
    CDMIcons.hooked = true
end

local function EnsureHooks()
    if CDMIcons.hooked or waiter then return end
    local _, loaded = C_AddOns.IsAddOnLoaded(ADDON)
    if loaded then
        HookViewers()
        return
    end
    -- The viewers' first refreshes ran during their own load, before these
    -- hooks existed, so a watcher already on its fallback is told once here.
    waiter = CreateFrame("Frame")
    waiter:RegisterEvent("ADDON_LOADED")
    waiter:SetScript("OnEvent", function(self, _, addonName)
        if addonName ~= ADDON then return end
        self:UnregisterEvent("ADDON_LOADED")
        HookViewers()
        OnViewerRefresh()
    end)
end

-- fn runs on the next frame after any viewer refresh. onRefresh, optional,
-- runs inside every refresh: it may touch only the caller's own frames and
-- must not Watch or Unwatch.
function CDMIcons.Watch(key, fn, onRefresh)
    watchers[key] = fn
    onRefreshes[key] = onRefresh
    EnsureHooks()
end

function CDMIcons.Unwatch(key)
    watchers[key] = nil
    onRefreshes[key] = nil
end

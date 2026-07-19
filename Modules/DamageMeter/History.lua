-- ╔══════════════════════════════════════════════════════════╗
-- ║  DamageMeter/History.lua                                 ║
-- ║  Module: Damage Meter                                    ║
-- ║  Purpose: Runtime-only key-history snapshot store. At    ║
-- ║          CHALLENGE_MODE_START (before KE's wipe) every   ║
-- ║          stored session × 11 meter types (+ per-source   ║
-- ║          details) is RETAINED verbatim as one bundle;    ║
-- ║          Core.lua's GetSession/GetSource serve entries   ║
-- ║          by NEGATIVE session id. Spec:                   ║
-- ║          dev/docs/superpowers/specs/                     ║
-- ║          2026-07-18-dm-snapshot-store-design.md          ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...) -- luacheck: ignore 211
if not KitnEssentials then return end

---@class DamageMeter: AceModule
local DM = KitnEssentials:GetModule("DamageMeter")

local ipairs = ipairs -- luacheck: ignore 211
local type = type -- luacheck: ignore 211
local wipe = wipe
local issecretvalue = issecretvalue
local tremove = table.remove -- luacheck: ignore 211
local tinsert = table.insert -- luacheck: ignore 211

local DEBUG_DMH = false -- luacheck: ignore 211

-- Lazy store. nextID decreases monotonically and is NEVER reused (a stale
-- window pin can never alias a newer snapshot); HistoryClear keeps it.
local function store(self) -- luacheck: ignore 211
    local h = self._history
    if not h then
        h = { bundles = {}, byID = {}, nextID = -1 }
        self._history = h
    end
    return h
end

-- Shared nil-safe source key — capture and lookup MUST use the same mapping
-- [C3]. Both fields are Nilable in the API contract; a source with neither
-- is skipped by the deep pass (its bar row still renders from byType).
-- Secret guard mirrors Detail.lua's enemy-key idiom (never key a table on a
-- possibly-secret value); capture runs OOC where these are plain, so a
-- secret here is a contract surprise and the source is simply skipped.
function DM.HistorySourceKey(sourceGUID, sourceCreatureID)
    if sourceGUID ~= nil and not issecretvalue(sourceGUID) then
        return sourceGUID
    end
    if sourceCreatureID ~= nil and not issecretvalue(sourceCreatureID) then
        return "c:" .. tostring(sourceCreatureID)
    end
    return nil
end

-- Chokepoint serves (Core.lua GetSession/GetSource negative-id branch).
-- Plain table reads — an evicted or unknown id falls out as nil, which every
-- caller already treats as "no session".
function DM:HistorySession(sessionID, dmType)
    local h = self._history
    local entry = h and h.byID[sessionID]
    local byType = entry and entry.byType
    return byType and byType[dmType] or nil
end

function DM:HistorySource(sessionID, dmType, sourceGUID, sourceCreatureID)
    local h = self._history
    local entry = h and h.byID[sessionID]
    if not entry then return nil end
    local key = DM.HistorySourceKey(sourceGUID, sourceCreatureID)
    local perSource = key ~= nil and entry.sources[key] or nil
    return perSource and perSource[dmType] or nil
end

-- Newest-first bundle list for the segment menu. nil = no history yet.
function DM:HistoryBundles()
    local h = self._history
    if not h or #h.bundles == 0 then return nil end
    return h.bundles
end

-- Full clear: header reset only (plus /reload implicitly). The
-- DAMAGE_METER_RESET event handler must NOT call this — our own key-start
-- wipe fires that event right after capture, and external resets must not
-- erase captured history either (spec: store clears only on eviction,
-- header reset, /reload).
function DM:HistoryClear()
    local h = self._history
    if not h then return end
    wipe(h.bundles)
    wipe(h.byID)
end

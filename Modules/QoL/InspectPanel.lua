-- ╔══════════════════════════════════════════════════════════╗
-- ║  InspectPanel.lua                                        ║
-- ║  Module: Inspect Panel                                   ║
-- ║  Purpose: Inspect-side overlays (warnings, slot details, ║
-- ║           track indicators, item level). Shares render   ║
-- ║           helpers with CharacterPanel; owns the inspect  ║
-- ║           event lifecycle and per-target dirty cache.    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class InspectPanel: AceModule, AceEvent-3.0, AceHook-3.0
local InspectPanel = KitnEssentials:NewModule("InspectPanel", "AceEvent-3.0", "AceHook-3.0")

local _G = _G
local CreateFrame = CreateFrame
local GetInventoryItemLink = GetInventoryItemLink
local GetInventoryItemTexture = GetInventoryItemTexture
local GetInspectSpecialization = GetInspectSpecialization
local UnitGUID = UnitGUID
local C_Timer = C_Timer
local C_Item = C_Item
local C_Map = C_Map
local C_AddOns = C_AddOns
local pairs, ipairs = pairs, ipairs
local next = next
local hooksecurefunc = hooksecurefunc
local wipe = wipe
local string = string
local math = math
local table = table
local tostring = tostring
local GetTime = GetTime

---------------------------------------------------------------------------------
-- Debug
---------------------------------------------------------------------------------
-- Inspect socket-scan tracing. Flip true, /reload, inspect a target with gemmed
-- gear, paste the chat log. NOTE: CharacterPanel.lua has its own DEBUG_CP flag
-- for CP:ScanItemSockets traces; both must be enabled together for full tracing.
local DEBUG_CP = false

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
-- Inspect paperdoll mirrors the player slot layout; names swap Character->Inspect.
-- Mirrors the SLOT_FRAMES table in CharacterPanel.lua. Hardcoded here to avoid
-- cross-module table-read coupling for what is effectively a constant.
local INSPECT_SLOT_FRAMES = {
    [1]  = "InspectHeadSlot",      [2]  = "InspectNeckSlot",
    [3]  = "InspectShoulderSlot",
    [5]  = "InspectChestSlot",     [6]  = "InspectWaistSlot",
    [7]  = "InspectLegsSlot",      [8]  = "InspectFeetSlot",
    [9]  = "InspectWristSlot",     [10] = "InspectHandsSlot",
    [11] = "InspectFinger0Slot",   [12] = "InspectFinger1Slot",
    [13] = "InspectTrinket0Slot",  [14] = "InspectTrinket1Slot",
    [15] = "InspectBackSlot",
    [16] = "InspectMainHandSlot",  [17] = "InspectSecondaryHandSlot",
}

-- Average-item-level computation, ported from ElvUI (Game/Shared/General/
-- ItemLevel.lua CalculateAverageItemLevel). C_PaperDollInfo.GetInspectItemLevel
-- only returns a rounded integer, so to show real decimals we sum the equipped
-- slots and divide by 16 ourselves — the same arithmetic ElvUI displays.
local AVG_ARMOR_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 }
local AVG_X2_INVTYPES = {
    INVTYPE_2HWEAPON = true,
    INVTYPE_RANGEDRIGHT = true,
    INVTYPE_RANGED = true,
}
local AVG_X2_EXCEPTIONS = { [2] = 19 }  -- wands report RANGEDRIGHT but are 1H

---------------------------------------------------------------------------------
-- File-locals
---------------------------------------------------------------------------------
local inspectUpdatePending = false

---------------------------------------------------------------------------------
-- Dirty cache (GUID-keyed)
---------------------------------------------------------------------------------
-- Per-target per-slot cache. Frame-attributed state lives in CP's shared FFD
-- (accessed via self.CP:GetFFD); this _inspectCache is dirty-cache state only.
-- Wipes on InspectFrame:OnHide and on InspectPanel:OnDisable (bounded memory).
local _inspectCache = {}  -- [guid] = { [slotID] = { itemLink, enchantID, ilvl, gemHash, paintPasses } }
local _currentInspectGUID = nil

local function _inspectSlotState(guid, slotID)
    local g = _inspectCache[guid]
    if not g then g = {}; _inspectCache[guid] = g end
    local s = g[slotID]
    if not s then s = {}; g[slotID] = s end
    return s
end

-- Compact deterministic hash of socket state for the dirty cache. Changes when
-- gems are filled/unfilled OR when a gem's itemID changes. Cheap (string concat
-- over ≤3 sockets). Takes a pre-computed ScanItemSockets result so the caller
-- can reuse the same scan for suspect detection — ScanItemSockets internally
-- allocates a C_TooltipInfo table, so each call has real cost.
local function ComputeGemHash(result)
    if not result or not result.sockets then return "" end
    local parts = {}
    for i, socket in ipairs(result.sockets) do
        parts[i] = (socket.filled and ("F1G" .. (socket.gemID or "0"))) or "F0"
    end
    return table.concat(parts, "_")
end

---------------------------------------------------------------------------------
-- Gem-race fix (grace-period gated + hybrid retry)
---------------------------------------------------------------------------------
-- When ITEM_DATA_LOAD_RESULT fires but the inspect packet's per-player gem
-- data hasn't fully resolved yet, ScanItemSockets returns totalCount > 0 with
-- filledCount == 0 even on items that DO have filled gems. But that exact
-- observation also describes a GENUINELY EMPTY socket (player chose not to
-- gem their neck/rings — common). We can't tell them apart from a single read.
--
-- Discriminator: time since INSPECT_READY for this GUID. Inspect packets
-- finish hydrating within ~1.5s of INSPECT_READY in normal conditions; if
-- sockets are still empty after the grace period, treat as genuinely empty
-- and render the red cue. Within the grace period, treat as suspect:
--
--   1. Primary path (event-driven): re-issue C_Item.RequestLoadItemDataByID
--      so ITEM_DATA_LOAD_RESULT re-fires when gem bytes hydrate. Mirrors the
--      EUI CharacterSheet player-path pattern.
--   2. Fallback path (timer): single dedup'd C_Timer per (guid, slotID) in
--      case the event chain stalls. RETRY_DELAY = 0.5s.
--
-- Per-slot paintPasses still caps the suppression within the grace window so
-- a pathological re-request loop can't suppress past MAX_PAINT_PASSES tries.
local MAX_PAINT_PASSES = 5
local RETRY_DELAY = 0.5
local INSPECT_PACKET_GRACE = 1.0  -- seconds; suspect-empty triggers retry within this window

local _inspectReadyTime = {}  -- [guid] = GetTime() at last INSPECT_READY

local function ScheduleSocketRetry(self, button, slotID, guid)
    local s = _inspectSlotState(guid, slotID)
    if s.retryPending then return end  -- dedup: one timer per (guid, slot) at a time
    s.retryPending = true
    C_Timer.After(RETRY_DELAY, function()
        -- Read state fresh; the cache table is the same one OnHide may have
        -- wiped, so a re-fetch yields a new sub-table after wipe + we'll
        -- bail anyway on the guid mismatch below.
        if not InspectFrame or not InspectFrame:IsShown() then
            local st = _inspectCache[guid] and _inspectCache[guid][slotID]
            if st then st.retryPending = false end
            return
        end
        if _currentInspectGUID ~= guid then
            local st = _inspectCache[guid] and _inspectCache[guid][slotID]
            if st then st.retryPending = false end
            return
        end
        local st = _inspectSlotState(guid, slotID)
        st.retryPending = false
        self:RenderInspectSlot(button)
    end)
end

-- Resolve the unit + slotID for an inspect button, applying the shared guards
-- (db enabled, frame unit available, same-map). Returns (unit, slotID) or nil.
local function ResolveInspectSlot(button)
    if not InspectPanel.CP or not InspectPanel.CP.db or not InspectPanel.CP.db.Enabled then return end
    if not button then return end
    local unit = InspectFrame and InspectFrame.unit
    if not unit then return end
    -- Long-range inspect returns incomplete gear; skip only on a CONFIRMED
    -- cross-map mismatch (both maps known and different). An unknown (nil) map
    -- is not treated as a mismatch, so normal same-zone inspects still render.
    local pm = C_Map.GetBestMapForUnit("player")
    local um = C_Map.GetBestMapForUnit(unit)
    if pm and um and pm ~= um then return end

    local slotID = button:GetID()
    if not slotID or slotID == 0 then return end
    return unit, slotID
end

-- Debounced, next-frame batch of the full inspect refresh. A first inspect fires
-- a burst (per-slot button updates + INSPECT_READY + UNIT_INVENTORY_CHANGED) on the
-- same frame Blizzard loads + renders the inspect UI; collapsing it into ONE
-- deferred pass keeps that heavy tooltip-scan work off the busy load frame.
local function QueueInspectUpdate()
    if inspectUpdatePending then return end
    if not (InspectPanel.CP and InspectPanel.CP.db and InspectPanel.CP.db.Enabled) then return end
    if not (InspectFrame and InspectFrame:IsShown()) then return end
    inspectUpdatePending = true
    -- 0.2s (not 0.05) collapses bursty late-data events into far fewer full re-scans.
    -- Each re-scan allocates a C_TooltipInfo table per socketable slot, so a higher
    -- debounce directly cuts the transient garbage generated while inspecting.
    C_Timer.After(0.2, function()
        inspectUpdatePending = false
        if InspectPanel.CP and InspectPanel.CP.db and InspectPanel.CP.db.Enabled
            and InspectFrame and InspectFrame:IsShown() then
            InspectPanel:UpdateAllInspectSlots()
        end
    end)
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function InspectPanel:OnInitialize()
    -- Cache the CharacterPanel module reference; InspectPanel reuses CP's
    -- shared render helpers and FFD accessor. If CharacterPanel was removed
    -- via custom .toc editing, degrade silently.
    self.CP = KitnEssentials:GetModule("CharacterPanel", true)
    if not self.CP then
        KE:Print("InspectPanel disabled: CharacterPanel module not found.")
        self:SetEnabledState(false)
        return
    end
    -- Enabled by CharacterPanel:OnEnable cascade.
    self:SetEnabledState(false)
end

function InspectPanel:OnEnable()
    if not self.CP or not self.CP.db or not self.CP.db.Enabled then return end
    self:SetupInspectSupport()

    -- Re-arm events that OnDisable stripped via UnregisterAllEvents. The OnEvent
    -- script + InspectFrame OnShow/OnHide hooks remain installed from the original
    -- SetupInspectSupport call (which short-circuits on re-enable via _inspectSetup),
    -- so this is just re-registration on the existing frame.
    if self.eventFrame then
        self.eventFrame:RegisterEvent("ADDON_LOADED")
        -- If InspectFrame is already shown at re-enable time, the OnShow hook
        -- won't fire, so re-register the data events manually and refresh the
        -- currently-visible overlays.
        if InspectFrame and InspectFrame:IsShown() then
            self.eventFrame:RegisterEvent("INSPECT_READY")
            self.eventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
            self.eventFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
            self:UpdateAllInspectSlots()
        end
    end
end

function InspectPanel:OnDisable()
    if self._inspectQueue then wipe(self._inspectQueue) end
    wipe(_inspectCache)
    wipe(_inspectReadyTime)
    _currentInspectGUID = nil
    inspectUpdatePending = false
    if self.eventFrame then self.eventFrame:UnregisterAllEvents() end
    self:HideAllInspectOverlays()
end

---------------------------------------------------------------------------------
-- Inspect orchestration
---------------------------------------------------------------------------------

-- Render the overlays (warning + per-slot detail + track letter) for one inspect
-- slot. Pure render: assumes the item's data is already cached. Driven by
-- RequestInspectSlot synchronously (cached items) or by ITEM_DATA_LOAD_RESULT
-- (items that had to load).
function InspectPanel:RenderInspectSlot(button)
    local unit, slotID = ResolveInspectSlot(button)
    if not unit then return end
    local guid = UnitGUID(unit)
    if not guid then return end

    local CP = self.CP
    local link = GetInventoryItemLink(unit, slotID)
    local enchantID = link and CP:GetSlotEnchantID(unit, slotID) or nil
    local ilvl = link and CP:GetSlotItemLevel(unit, slotID) or nil
    -- Single ScanItemSockets call; reused for both dirty-check (via ComputeGemHash)
    -- and suspect detection. Each call allocates a C_TooltipInfo tooltip table,
    -- so deduping cuts inspect-render allocations notably.
    local result = link and CP:ScanItemSockets(unit, slotID)
    local gemHash = ComputeGemHash(result)

    local s = _inspectSlotState(guid, slotID)
    if s.itemLink == link
        and s.enchantID == enchantID
        and s.ilvl == ilvl
        and s.gemHash == gemHash
    then
        return  -- dirty-cache short-circuit
    end

    -- Gem-race detection: sockets exist but ALL read empty AND it's within the
    -- inspect-packet grace window → suspect the gem bytes haven't hydrated yet.
    -- Outside the grace window, an empty socket is treated as genuinely empty
    -- (player chose not to gem — common on necks/rings).
    local readyAge = _inspectReadyTime[guid] and (GetTime() - _inspectReadyTime[guid])
    local suspect = result and result.totalCount and result.totalCount > 0
                    and result.filledCount == 0
                    and readyAge and readyAge < INSPECT_PACKET_GRACE

    if suspect then
        s.paintPasses = (s.paintPasses or 0) + 1
        if s.paintPasses < MAX_PAINT_PASSES then
            -- Re-request item data so ITEM_DATA_LOAD_RESULT re-fires with the
            -- now-hydrated gem bytes (EUI player-path pattern).
            local itemID = C_Item.GetItemInfoInstant(link)
            if itemID then C_Item.RequestLoadItemDataByID(itemID) end
            -- Timer fallback in case the event chain stalls.
            ScheduleSocketRetry(self, button, slotID, guid)
            -- Render everything EXCEPT gems; suppressGems hides the icon row
            -- instead of flashing red empty-socket cues. Skip the cache write so
            -- the next retry re-evaluates fresh.
            CP:UpdateSlotWarning(button, unit, slotID)
            if CP.db.ShowSlotItemLevel or CP.db.ShowEnchantNames
                or CP.db.ShowSlotGems or CP.db.ShowMissingGems then
                CP:UpdateSlotDetail(button, slotID, unit, true)
            end
            if CP.db.TrackIndicatorsEnabled then
                CP:UpdateSlotTrackIndicator(button, slotID, unit)
            end
            return
        end
        -- Exhausted retry budget; treat as genuinely empty. Reset so a future
        -- re-inspect of the same slot starts fresh.
        s.paintPasses = 0
    end

    -- Normal render path: write the cache then render everything (gems included).
    s.itemLink, s.enchantID, s.ilvl, s.gemHash = link, enchantID, ilvl, gemHash

    CP:UpdateSlotWarning(button, unit, slotID)
    if CP.db.ShowSlotItemLevel or CP.db.ShowEnchantNames
        or CP.db.ShowSlotGems or CP.db.ShowMissingGems then
        CP:UpdateSlotDetail(button, slotID, unit)
    end
    if CP.db.TrackIndicatorsEnabled then
        CP:UpdateSlotTrackIndicator(button, slotID, unit)
    end
end

-- Request side of the keyed-queue model: resolve the inspect slot's equipped
-- item, queue {slotID -> itemID}, and ask Blizzard to load its full data.
-- ITEM_DATA_LOAD_RESULT then renders just that slot and drains the queue entry
-- — no blanket re-scan, no self-sustaining loop. Keyed by slotID (not itemID)
-- so two slots sharing an itemID (duplicate rings) both resolve. Reference:
-- BetterCharacterPanel's itemLoadQueue model.
--
-- Always queue + request, never short-circuit on a cache check: C_Item's cache
-- predicates report BASE item data (name, icon, base stats), NOT inspect-specific
-- socket/gem data, which arrives in the inspect packet for THIS player. Items
-- whose base was cached from prior contexts would otherwise render synchronously
-- before the inspect packet's gems loaded, leaving red sockets on filled slots.
-- ITEM_DATA_LOAD_RESULT for the equipped itemID is what signals the inspect
-- packet is ready; for already-base-cached items it fires within ~1 frame, so the
-- deferral is imperceptible. Total C_TooltipInfo allocations per inspect are
-- unchanged — only the timing shifts from "now" to "next event."
function InspectPanel:RequestInspectSlot(button)
    local unit, slotID = ResolveInspectSlot(button)
    if not unit then return end

    self._inspectQueue = self._inspectQueue or {}
    local link = GetInventoryItemLink(unit, slotID)
    if not link then
        -- Empty slot: nothing to wait on; clear any pending entry and render.
        self._inspectQueue[slotID] = nil
        self:RenderInspectSlot(button)
        return
    end

    local itemID = C_Item.GetItemInfoInstant(link)
    if not itemID then return end

    -- Skip re-issuing if this slot is already waiting on the same itemID — avoids
    -- piling duplicate requests during a re-pass while the slot's still loading.
    if self._inspectQueue[slotID] ~= itemID then
        self._inspectQueue[slotID] = itemID
        C_Item.RequestLoadItemDataByID(itemID)
    end
end

-- Re-run every inspect slot through the keyed queue (the level hook, INSPECT_READY,
-- UNIT_INVENTORY_CHANGED, etc. all funnel here via QueueInspectUpdate). Cached items
-- render synchronously; uncached items render later via ITEM_DATA_LOAD_RESULT. The
-- average ilvl is full-paperdoll so it only computes when the queue is fully drained.
function InspectPanel:UpdateAllInspectSlots()
    self._inspectQueue = self._inspectQueue or {}
    for _, frameName in pairs(INSPECT_SLOT_FRAMES) do
        self:RequestInspectSlot(_G[frameName])
    end
    if next(self._inspectQueue) == nil then
        self:UpdateInspectItemLevel()
    end
end

-- Returns the equipped average item level to 2 decimals, or nil if the inspect
-- data isn't ready yet (caller retries on the next INSPECT_READY / late-data event).
function InspectPanel:GetInspectAverageItemLevel(unit)
    local spec = GetInspectSpecialization(unit)
    if not spec or spec == 0 then return nil end  -- inspect data not resolved yet

    local total = 0
    for _, id in ipairs(AVG_ARMOR_SLOTS) do
        if GetInventoryItemLink(unit, id) then
            local cur = self.CP:GetSlotItemLevel(unit, id)
            if not cur then return nil end            -- item data still loading
            if cur > 0 then total = total + cur end
        elseif GetInventoryItemTexture(unit, id) then
            return nil                                -- slot filled but link not ready
        end
    end

    local _
    local mainLevel = 0
    local mainQuality, mainEquipLoc, mainClass, mainSubClass
    local mainLink = GetInventoryItemLink(unit, 16)
    if mainLink then
        mainLevel = self.CP:GetSlotItemLevel(unit, 16)
        if not mainLevel then return nil end
        _, _, mainQuality, _, _, _, _, _, mainEquipLoc, _, _, mainClass, mainSubClass = C_Item.GetItemInfo(mainLink)
    elseif GetInventoryItemTexture(unit, 16) then
        return nil
    end

    local offLevel = 0
    local offEquipLoc
    local offLink = GetInventoryItemLink(unit, 17)
    if offLink then
        offLevel = self.CP:GetSlotItemLevel(unit, 17)
        if not offLevel then return nil end
        _, _, _, _, _, _, _, _, offEquipLoc = C_Item.GetItemInfo(offLink)
    elseif GetInventoryItemTexture(unit, 17) then
        return nil
    end

    -- 2H / Titan's Grip handling: count the main hand twice when there's no off
    -- hand and the weapon occupies both slots (excluding wands and Fury warriors).
    if mainQuality == 6 or (not offEquipLoc and AVG_X2_INVTYPES[mainEquipLoc]
        and AVG_X2_EXCEPTIONS[mainClass] ~= mainSubClass and spec ~= 72) then
        mainLevel = math.max(mainLevel, offLevel)
        total = total + mainLevel * 2
    else
        total = total + mainLevel + offLevel
    end

    if total == 0 then return nil end
    return math.floor((total / 16) * 100 + 0.5) / 100
end

-- Blizzard's inspect frame shows no average item level, so render our own.
-- (Mirrors BetterCharacterPanel: a custom FontString on the inspect items frame;
-- there is no native element to restyle the way the player panel reuses
-- CharacterStatsPane.ItemLevelFrame.)
function InspectPanel:UpdateInspectItemLevel()
    if not self.CP.db.Enabled then return end
    local unit = InspectFrame and InspectFrame.unit
    if not unit then return end
    -- Same cross-map guard as the slot overlays: long-range inspect returns
    -- incomplete gear, so only render on a confirmed same-map (or unknown) target.
    local pm = C_Map.GetBestMapForUnit("player")
    local um = C_Map.GetBestMapForUnit(unit)
    if pm and um and pm ~= um then return end

    local parent = _G.InspectPaperDollItemsFrame or InspectFrame
    if not parent then return end

    if not self._inspectIlvl then
        local fs = parent:CreateFontString(nil, "OVERLAY")
        fs:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -4, 4)
        fs:SetJustifyH("RIGHT")
        self._inspectIlvl = fs
    end

    local ilvl = self:GetInspectAverageItemLevel(unit)
    if not ilvl or ilvl <= 0 then
        self._inspectIlvl:Hide()
        return
    end

    self.CP:ApplyFont(self._inspectIlvl, self.CP.db.IlvlValueSize or 16)
    local accent = KE.Theme.accent
    self._inspectIlvl:SetTextColor(accent[1], accent[2], accent[3])
    self._inspectIlvl:SetText(string.format("%.2f", ilvl))
    self._inspectIlvl:Show()
end

function InspectPanel:SetupInspectSupport()
    if self._inspectSetup then return end
    self._inspectSetup = true

    -- Capture self for use in nested closures (installHooks, regData, unregData,
    -- OnEvent dispatcher). Nested closures don't have direct access to method-scope
    -- self; using _self is the safer Lua pattern.
    local _self = self

    -- Forward-declared so installHooks can toggle the data events on it.
    local f
    -- Events gated on InspectFrame Show/Hide. All three handlers below
    -- already early-out when the inspect frame isn't visible, so listening
    -- while hidden was idle-time waste. ADDON_LOADED stays on the persistent
    -- frame (the inspect frame doesn't exist yet at addon-load time).
    --
    -- ITEM_DATA_LOAD_RESULT fires with the equipped itemID once Blizzard has
    -- fully loaded an item we requested (incl. its socketed gems). The Task 0
    -- trace confirmed SOCKET_INFO_UPDATE and GET_ITEM_INFO_RECEIVED never fired
    -- in the inspect path with active requests in place.
    local INSPECT_DATA_EVENTS = {
        "ITEM_DATA_LOAD_RESULT",
        "INSPECT_READY",
        "UNIT_INVENTORY_CHANGED",
    }

    -- Best-effort per-slot hooks. These only exist once Blizzard_InspectUI is
    -- loaded, and may not fire on every code path, so they are NOT the primary
    -- render trigger — INSPECT_READY (below) is. Idempotent: safe to call again.
    local function installHooks()
        if _self._inspectHooked then return end
        if not InspectPaperDollItemSlotButton_Update then return end
        _self._inspectHooked = true
        hooksecurefunc("InspectPaperDollItemSlotButton_Update", function()
            QueueInspectUpdate()
        end)
        if InspectPaperDollFrame_SetLevel then
            hooksecurefunc("InspectPaperDollFrame_SetLevel", function()
                QueueInspectUpdate()
            end)
        end
        -- ITEM_DATA_LOAD_RESULT fires per item we requested via RequestInspectSlot;
        -- it lands gem data with the equipped item's itemID. Registered only while
        -- the inspect frame is shown so we don't react to player-side item loads.
        if InspectFrame then
            local function regData()   for _, e in ipairs(INSPECT_DATA_EVENTS) do f:RegisterEvent(e) end end
            local function unregData()
                for _, e in ipairs(INSPECT_DATA_EVENTS) do f:UnregisterEvent(e) end
                if _self._inspectQueue then wipe(_self._inspectQueue) end
                wipe(_inspectCache)
                wipe(_inspectReadyTime)
                _currentInspectGUID = nil
            end
            InspectFrame:HookScript("OnShow", regData)
            InspectFrame:HookScript("OnHide", unregData)
            if InspectFrame:IsShown() then regData() end
        end
    end

    -- Persistent frame: always alive so it catches the events regardless of when
    -- Blizzard_InspectUI loads relative to this module's init. The late-data events
    -- (INSPECT_READY, UNIT_INVENTORY_CHANGED, ITEM_DATA_LOAD_RESULT) are registered
    -- on demand via INSPECT_DATA_EVENTS only while the inspect frame is shown.
    f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(_, event, arg1, arg2)
        -- Task 0 trace: log every inspect-related event with its args + timestamp so
        -- it can be correlated against the "FLIP" lines from ScanItemSockets to learn
        -- which event drives a late gem's resolution.
        if DEBUG_CP then
            KE:Print(string.format("[CP] EVT %s a1=%s a2=%s t=%.2f",
                event, tostring(arg1), tostring(arg2), GetTime()))
        end
        if event == "ADDON_LOADED" then
            if arg1 == "Blizzard_InspectUI" then installHooks() end
        elseif event == "INSPECT_READY" then
            -- Track the inspected unit's GUID for dirty-cache scoping + retry guards.
            -- INSPECT_READY's arg1 is the GUID of the inspected unit.
            _currentInspectGUID = arg1
            -- Stamp the time so the gem-race suspect window can gate on
            -- "within INSPECT_PACKET_GRACE seconds of this event."
            if arg1 then _inspectReadyTime[arg1] = GetTime() end
            -- New inspect target: clear the per-slot pending queue so the new unit's
            -- gear gets requested fresh, then ensure the hooks exist and queue a pass.
            if _self._inspectQueue then wipe(_self._inspectQueue) end
            -- _cpDbg / _cpDbgFilled live on CP (used by CP:ScanItemSockets which
            -- stays in CharacterPanel.lua); wipe via the CP module reference.
            if _self.CP and _self.CP._cpDbg then wipe(_self.CP._cpDbg) end          -- debug: re-allow dumps
            if _self.CP and _self.CP._cpDbgFilled then wipe(_self.CP._cpDbgFilled) end
            installHooks()
            -- Render SYNCHRONOUSLY on INSPECT_READY (not via QueueInspectUpdate's
            -- 0.2s debounce). On target switch, A's stale overlay FontStrings/icons
            -- stay visible on the reused frames until a render overwrites them; the
            -- debounce adds 0.2s of perceived "old gear" lag. Data is ready now.
            -- Follow-up burst events (UNIT_INVENTORY_CHANGED, per-slot hooks) still
            -- go through the debounced path; dirty cache makes those near-free.
            _self:UpdateAllInspectSlots()
        elseif event == "UNIT_INVENTORY_CHANGED" then
            -- Inspected unit's gear changed mid-inspect — re-pass to pick up the new
            -- item(s). RequestInspectSlot handles changed-itemID per slot correctly.
            if arg1 and InspectFrame and arg1 == InspectFrame.unit then
                QueueInspectUpdate()
            end
        elseif event == "ITEM_DATA_LOAD_RESULT" then
            -- A requested item finished loading. Render only the slot(s) that were
            -- waiting on this exact itemID (targeted, not blanket), and recompute the
            -- average once the last pending slot drains.
            local itemID = arg1
            if itemID and _self._inspectQueue and InspectFrame and InspectFrame:IsShown() then
                for slotID, queuedID in pairs(_self._inspectQueue) do
                    if queuedID == itemID then
                        _self._inspectQueue[slotID] = nil
                        local slotFrameName = INSPECT_SLOT_FRAMES[slotID]
                        local b = slotFrameName and _G[slotFrameName]
                        if b then _self:RenderInspectSlot(b) end
                    end
                end
                if next(_self._inspectQueue) == nil then
                    _self:UpdateInspectItemLevel()
                end
            end
        end
    end)
    self.eventFrame = f

    -- If the inspect UI is already loaded at setup, hook immediately.
    if C_AddOns.IsAddOnLoaded("Blizzard_InspectUI") then installHooks() end
end

-- Hide all inspect-side overlays. Mirrors CP:HideAllSlotDetails /
-- CP:HideAllTrackIndicators for inspect frames. Reads from CP's shared FFD via
-- the promoted accessor.
function InspectPanel:HideAllInspectOverlays()
    if self._inspectIlvl then self._inspectIlvl:Hide() end
    if not self.CP then return end
    for _, frameName in pairs(INSPECT_SLOT_FRAMES) do
        local slotFrame = _G[frameName]
        if slotFrame then
            local d = self.CP:GetFFD(slotFrame)
            if d.detail then d.detail:Hide() end
            if d.track then d.track:Hide() end
            if d.warning then d.warning:SetText("") end
        end
    end
end

-- ╔══════════════════════════════════════════════════════════╗
-- ║  KickTrackerMarkers.lua                                  ║
-- ║  Module: Interrupt Tracker                               ║
-- ║  Purpose: teammates' announced focus markers, from party ║
-- ║           chat lines and the EUIKT and MDTFocusMark      ║
-- ║           addon messages, for the nameplate icons. It    ║
-- ║           sends nothing.                                 ║
-- ╚══════════════════════════════════════════════════════════╝
-- The cache is saved per character with the party instance it was learned
-- in, and comes back only on a reload or login inside that instance; a
-- zone-in starts it empty.

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@type KickTracker
local KT = KitnEssentials:GetModule("KickTracker")

local FA = KE.FocusAnnounce
local GetInstanceInfo = GetInstanceInfo
---@type fun(unit: string): string?
local UnitGUID = UnitGUID
local issecretvalue = issecretvalue
local pairs = pairs
local type = type
local wipe = wipe

local function CurrentInstance()
    local _, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
    if instanceType ~= "party" then return nil end
    return instanceID
end

local function SavedRecord(create)
    local me = UnitGUID("player")
    local all = KE.db.global.KickMarkers
    if not me or type(all) ~= "table" then return nil end
    local rec = all[me]
    if type(rec) ~= "table" then
        if not create then return nil end
        rec = {}
        all[me] = rec
    end
    return rec
end

function KT:SaveMarkers()
    local rec = SavedRecord(true)
    if not rec then return end
    local m = {}
    for guid, marker in pairs(self.markerOf) do m[guid] = marker end
    rec.inst, rec.m = CurrentInstance(), m
end

-- A later message for the same member replaces an earlier one, whatever its
-- source; 0 clears.
function KT:LearnMarker(guid, marker)
    local value = (type(marker) == "number" and marker >= 1 and marker <= 8) and marker or nil
    if self.markerOf[guid] == value then return end
    self.markerOf[guid] = value
    self:SaveMarkers()
    self:RailsResync()
end

-- After a reload or login inside the instance the record was saved in, it
-- comes back; otherwise the cache starts empty and the record is written over.
function KT:RestoreMarkers()
    wipe(self.markerOf)
    local inst, rec = CurrentInstance(), SavedRecord(false)
    if self._zoneReload and inst and rec and rec.inst == inst and type(rec.m) == "table" then
        for guid, marker in pairs(rec.m) do
            if type(guid) == "string" and type(marker) == "number" and marker >= 1 and marker <= 8 then
                self.markerOf[guid] = marker
            end
        end
    else
        self:SaveMarkers()
    end
end

-- A zone-in: the last visit's markers are gone.
function KT:ForgetMarkers()
    wipe(self.markerOf)
    self:SaveMarkers()
    self:RailsResync()
end

-- Focus Marker's message moves the player's own lane: a marker change, or
-- Focus Marker turned on or off.
function KT:MarkersActivate()
    self.markersOn = true
    FA.RegisterPrefixes()
    self:RegisterEvent("CHAT_MSG_PARTY", "OnMarkerChat")
    self:RegisterEvent("CHAT_MSG_PARTY_LEADER", "OnMarkerChat")
    self:RegisterEvent("CHAT_MSG_ADDON", "OnMarkerAddon")
    self:RegisterMessage(FA.MARKER_CHANGED, "RailsResync")
    self:RestoreMarkers()
    self:RailsResync()
end

function KT:MarkersDeactivate()
    self.markersOn = false
    self:UnregisterEvent("CHAT_MSG_PARTY")
    self:UnregisterEvent("CHAT_MSG_PARTY_LEADER")
    self:UnregisterEvent("CHAT_MSG_ADDON")
    self:UnregisterMessage(FA.MARKER_CHANGED)
end

-- The sender's GUID is the payload's twelfth argument. Inside a key the chat
-- lock is on and the text is secret, so every line there is refused.
function KT:OnMarkerChat(_, text, _, _, _, _, _, _, _, _, _, _, guid)
    local mate = FA.TeammateGuid(guid)
    local index = FA.ReadLine(text, issecretvalue(text), KE:IsChatMessagingLocked(), mate ~= nil)
    if index then self:LearnMarker(mate, index) end
end

-- EUIKT: a teammate's F or R with their marker. MDTFocusMark: a teammate's
-- own state, or a teammate's single-part sync of several players' markers.
-- Addon text is not made secret by the chat lock, so the lock is tested here:
-- inside a key nothing is read. The player's own messages and anyone
-- outside the party are refused.
function KT:OnMarkerAddon(_, prefix, text, channel, sender)
    if issecretvalue(prefix) or issecretvalue(text) or issecretvalue(channel) then return end
    local locked = KE:IsChatMessagingLocked()
    if prefix == FA.EUIKT_PREFIX then
        local kind, marker, guid = FA.ParseEUIKT(text)
        local mate = kind and FA.TeammateGuid(guid)
        if FA.AddonRefused(prefix, channel, locked, mate ~= nil) then return end
        self:LearnMarker(mate, marker)
    elseif prefix == FA.MDT_PREFIX then
        local from = FA.TeammateByName(sender)
        if FA.AddonRefused(prefix, channel, locked, from ~= nil) then return end
        local payload = FA.DecodeMDT(text)
        if not payload then return end
        local kind = payload.kind
        if kind == "stateUpdate" or kind == "stateResponse" then
            if payload.marker then self:LearnMarker(from, payload.marker) end
        elseif kind == "syncV2" and type(payload.markers) == "table" then
            for fullName, marker in pairs(payload.markers) do
                local mate = type(fullName) == "string" and FA.TeammateByName(fullName) or nil
                local value = FA.MDTMarker(marker)
                if mate and value then self:LearnMarker(mate, value) end
            end
        end
    end
end

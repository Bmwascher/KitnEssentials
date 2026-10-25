-- ╔══════════════════════════════════════════════════════════╗
-- ║  KickTrackerMarkers.lua                                  ║
-- ║  Module: Interrupt Tracker                               ║
-- ║  Purpose: teammates' announced focus markers, from party ║
-- ║           chat lines and the EUIKT and MDTFocusMark      ║
-- ║           addon messages, for the nameplate icons. It    ║
-- ║           sends nothing.                                 ║
-- ╚══════════════════════════════════════════════════════════╝
-- The cache belongs to one dungeon visit, a party instance and its zone-in
-- time, and is saved per character with it: an activation inside the visit
-- reads it back, and a move to another visit, or out of any, empties it.

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@type KickTracker
local KT = KitnEssentials:GetModule("KickTracker")

local FA = KE.FocusAnnounce
local GetInstanceInfo = GetInstanceInfo
local GetServerTime = GetServerTime
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

-- KT.visitInst, KT.visitAt: the visit the player is in, its party instance
-- and zone-in time. GetServerTime() is plain server epoch time, not this
-- machine's uptime, so a saved visit keeps its identity across sessions.
-- After a reload or login there is no runtime copy, and the saved record is
-- the visit before. A move empties the cache; a record of another visit is
-- cleared, and a player with no record gets none.
function KT:MoveVisit()
    local rec = SavedRecord(false)
    local fromInst, fromAt = self.visitInst, self.visitAt
    if fromAt == nil and rec then fromInst, fromAt = rec.inst, rec.at end
    local inst, at = KT.VisitAfter(fromInst, fromAt, CurrentInstance(), GetServerTime())
    local moved = inst ~= self.visitInst or at ~= self.visitAt
    self.visitInst, self.visitAt = inst, at
    if rec and (rec.inst ~= inst or rec.at ~= at) then rec.inst, rec.at, rec.m = nil, nil, nil end
    if moved then
        wipe(self.markerOf)
        self:RailsResync()
    end
end

-- Saved under the visit the player is in; outside any, nothing is saved.
function KT:SaveMarkers()
    if self.visitAt == nil then return end
    local rec = SavedRecord(true)
    if not rec then return end
    local m = {}
    for guid, marker in pairs(self.markerOf) do m[guid] = marker end
    rec.inst, rec.at, rec.m = self.visitInst, self.visitAt, m
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

-- The visit's record comes back at any activation inside it. The visit moves
-- first: at a reload or login the activation can come before the event.
function KT:RestoreMarkers()
    self:MoveVisit()
    wipe(self.markerOf)
    local rec = SavedRecord(false)
    if not (rec and self.visitAt ~= nil and rec.at == self.visitAt and type(rec.m) == "table") then return end
    for guid, marker in pairs(rec.m) do
        if type(guid) == "string" and type(marker) == "number" and marker >= 1 and marker <= 8 then
            self.markerOf[guid] = marker
        end
    end
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

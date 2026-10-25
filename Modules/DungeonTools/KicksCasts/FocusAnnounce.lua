-- ╔══════════════════════════════════════════════════════════╗
-- ║  FocusAnnounce.lua                                       ║
-- ║  Purpose: the focus marker announce formats, both ways:  ║
-- ║           the party chat line, the EUIKT addon message   ║
-- ║           and the MDTFocusMark payload. Focus Marker     ║
-- ║           sends with it; the Kick Tracker reads with it. ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local string_match = string.match
local string_lower = string.lower
local string_sub = string.sub
local math_floor = math.floor
local tonumber = tonumber
local type = type
local pcall = pcall
local issecretvalue = issecretvalue
local UnitFullName = UnitFullName
local GetNormalizedRealmName = GetNormalizedRealmName
---@type fun(unit: string): string?
local UnitGUID = UnitGUID

local FA = {}
KE.FocusAnnounce = FA

FA.EUIKT_PREFIX = "EUIKT"
FA.MDT_PREFIX = "MDTFocusMark"
-- Sent by Focus Marker when its effective marker may have changed (a setting,
-- enable or disable); the Kick Tracker's own lane follows it.
FA.MARKER_CHANGED = "KitnEssentials_FocusMarkerChanged"
local MDT_HEAD = "!~MDT2~"
local MESSAGE_MAX = 255  -- one addon message; a longer text would need a multi-part send

-- The eight markers' English names, as Focus Marker has always sent them.
local NAME_INDEX = {
    star = 1, circle = 2, diamond = 3, triangle = 4,
    moon = 5, square = 6, cross = 7, skull = 8,
}

local PHRASES = { ["my focus kick is"] = true, ["my focus marker is"] = true }

-- A lower-case token, rt1 to rt8 (one digit) or a marker's name; nil for
-- anything else, rt0, rt9 and rt04 included.
local function TokenIndex(token)
    local digit = string_match(token, "^rt([1-8])$")
    if digit then return tonumber(digit) end
    return NAME_INDEX[token]
end

-- A marker name in any case ("Star") as its index; nil for None.
function FA.NameIndex(name)
    if type(name) ~= "string" then return nil end
    return NAME_INDEX[string_lower(name)]
end

function FA.ChatLine(index)
    return "My Focus Marker is {rt" .. index .. "}"
end

-- The event text keeps the braces as typed: a chat frame turns a tag into an
-- icon only when it displays the line.
function FA.ParseLine(text)
    if type(text) ~= "string" then return nil end
    local phrase, token = string_match(string_lower(text), "^%s*(my focus %a+ is)%s+{(%w+)}%s*$")
    if not phrase or not PHRASES[phrase] then return nil end
    return TokenIndex(token)
end

-- Read only when plain, outside a chat lock (a running key) and from a
-- teammate; the player's own echo is no teammate's.
function FA.ReadLine(text, textSecret, chatLocked, fromTeammate)
    if textSecret or chatLocked or not fromTeammate then return nil end
    return FA.ParseLine(text)
end

-- The channels each prefix is read on.
local ADDON_CHANNELS = {
    [FA.EUIKT_PREFIX] = { PARTY = true },
    [FA.MDT_PREFIX] = { PARTY = true, INSTANCE_CHAT = true },
}

-- An addon message (plain prefix and channel) is refused inside a chat lock,
-- a running key, where CHAT_MSG_ADDON is not made secret; from anyone but a
-- teammate; and on a channel its prefix is not read on.
function FA.AddonRefused(prefix, channel, chatLocked, fromTeammate)
    if chatLocked or not fromTeammate then return true end
    local channels = ADDON_CHANNELS[prefix]
    return not (channels and channels[channel])
end

function FA.EUIKTMessage(kind, marker, guid)
    return kind .. "\t" .. marker .. "\t" .. guid
end

-- kind ("F" tells, "R" tells and asks), marker (0 clears), the sender's GUID.
function FA.ParseEUIKT(text)
    if type(text) ~= "string" then return nil end
    local kind, marker, guid = string_match(text, "^([FR])\t([0-8])\t(Player%-%d+%-%x+)$")
    if not kind then return nil end
    return kind, tonumber(marker), guid
end

-- An integer 0 to 8, else nil.
function FA.MDTMarker(value)
    if type(value) ~= "number" or value ~= math_floor(value) or value < 0 or value > 8 then return nil end
    return value
end

-- The fields MDT's own sender builds. A request carries no marker.
function FA.MDTPayload(kind, fullName, name, class, marker)
    local payload = { kind = kind, senderFullName = fullName, senderName = name, senderClass = class }
    if kind ~= "stateRequest" then payload.marker = marker end
    return payload
end

local function Encode(E, payload)
    return MDT_HEAD .. E.EncodeBase64(E.CompressString(E.SerializeCBOR(payload), Enum.CompressionMethod.Deflate))
end

-- Blizzard's own encoding behind a fixed head; nil when a step fails or the
-- text does not fit one message.
function FA.EncodeMDT(payload)
    local E = C_EncodingUtil
    if not E then return nil end
    local ok, text = pcall(Encode, E, payload)
    if not ok or type(text) ~= "string" or #text > MESSAGE_MAX then return nil end
    return text
end

local function Decode(E, body)
    local raw = E.DecodeBase64(body)
    if not raw then return nil end
    local plain = E.DecompressString(raw, Enum.CompressionMethod.Deflate)
    if not plain then return nil end
    return E.DeserializeCBOR(plain)
end

-- Single-part messages only: each part of a split one starts with a control
-- byte, never the head.
function FA.DecodeMDT(text)
    local E = C_EncodingUtil
    if not E or type(text) ~= "string" or string_sub(text, 1, #MDT_HEAD) ~= MDT_HEAD then return nil end
    local ok, payload = pcall(Decode, E, string_sub(text, #MDT_HEAD + 1))
    if not ok or type(payload) ~= "table" or type(payload.kind) ~= "string" then return nil end
    payload.marker = FA.MDTMarker(payload.marker)
    return payload
end

-- Both prefixes, once, so their messages reach CHAT_MSG_ADDON.
function FA.RegisterPrefixes()
    if FA.prefixesRegistered or not (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) then return end
    FA.prefixesRegistered = true
    C_ChatInfo.RegisterAddonMessagePrefix(FA.EUIKT_PREFIX)
    C_ChatInfo.RegisterAddonMessagePrefix(FA.MDT_PREFIX)
end

-- The senders both readers accept. A party1 to party4 member's GUID: the
-- player's own echo and anyone outside the party are no teammate.
function FA.TeammateGuid(guid)
    if issecretvalue(guid) or type(guid) ~= "string" then return nil end
    for i = 1, 4 do
        if UnitGUID("party" .. i) == guid then return guid end
    end
    return nil
end

local function UnitKey(unit, realm)
    local name, unitRealm = UnitFullName(unit)
    if issecretvalue(name) or issecretvalue(unitRealm) or type(name) ~= "string" then return nil end
    if type(unitRealm) == "string" and unitRealm ~= "" then name = name .. "-" .. unitRealm end
    return KE:BuildNicknameKey(name, realm)
end

-- The teammate's GUID an addon message's "Name-Realm" sender names; nil for
-- the player and anyone outside the party.
function FA.TeammateByName(fullName)
    if issecretvalue(fullName) or type(fullName) ~= "string" then return nil end
    local realm = GetNormalizedRealmName()
    local key = KE:BuildNicknameKey(fullName, realm)
    if not key then return nil end
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitKey(unit, realm) == key then return FA.TeammateGuid(UnitGUID(unit)) end
    end
    return nil
end

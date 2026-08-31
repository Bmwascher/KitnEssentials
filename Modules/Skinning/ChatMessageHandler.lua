-- ╔══════════════════════════════════════════════════════════╗
-- ║  ChatMessageHandler.lua                                  ║
-- ║  Module: Chat                                            ║
-- ║  Purpose: Secret-safe message routing and formatting for ║
-- ║           the Chat module's styled chat frames. Runs as  ║
-- ║           the frame's MessageEventHandler only; config   ║
-- ║           and system events stay on Blizzard's path.     ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

---@class ChatMessageHandler
local CMH = {}
KE.ChatMessageHandler = CMH

local _G = _G
local format = format
local strsub = strsub
local strlower = strlower
local strupper = strupper
local tostring = tostring
local strlen = strlen
local gsub = _G.gsub
local pairs = pairs
local next = next
local pcall = pcall
local GetCVar = GetCVar
local GetCVarBool = C_CVar and C_CVar.GetCVarBool or _G.GetCVarBool
local Ambiguate = Ambiguate
local GetPlayerInfoByGUID = GetPlayerInfoByGUID
local GetNumGroupMembers = GetNumGroupMembers
local GetRaidRosterInfo = GetRaidRosterInfo
local FlashClientIcon = _G.FlashClientIcon
local BNGetNumFriendInvites = _G.BNGetNumFriendInvites
local wipe = wipe
local gmatch = _G.gmatch
local tonumber = tonumber
local GetChannelShortcutForChannelID = _G.GetChannelShortcutForChannelID
local IsChannelRegionalForChannelID = _G.IsChannelRegionalForChannelID
local GetChatCategory = _G.Chat_GetChatCategory or _G.ChatFrame_GetChatCategory or _G.GetChatCategory
local RemoveExtraSpaces = _G.RemoveExtraSpaces
local RemoveNewlines = _G.RemoveNewlines
local GMChatFrame_IsGM = _G.GMChatFrame_IsGM
local C_ClassColor_GetClassColor = C_ClassColor and C_ClassColor.GetClassColor
local IsChatLineCensored = C_ChatInfo and C_ChatInfo.IsChatLineCensored
local SafePack = _G.SafePack
local strmatch = strmatch
local sort = sort
local strjoin = strjoin
local tinsert = tinsert
local tconcat = table.concat

-- Blizzard globals not on KE's read_globals allowlist -- read through _G.
-- per family convention rather than growing .luacheckrc for this port
-- (Modules/Skinning/Chat.lua is the sibling precedent).
local ChatEditSetLastTellTarget = (_G.ChatFrameUtil and _G.ChatFrameUtil.SetLastTellTarget) or _G.ChatEdit_SetLastTellTarget
local ShouldColorChatByClass = (_G.ChatFrameUtil and _G.ChatFrameUtil.ShouldColorChatByClass) or _G.Chat_ShouldColorChatByClass or function(info) return info and info.colorNameByClass end
local ResolvePrefixedChannelName = (_G.ChatFrameUtil and _G.ChatFrameUtil.ResolvePrefixedChannelName) or
    _G.ChatFrame_ResolvePrefixedChannelName
local GetMobileEmbeddedTexture = (_G.ChatFrameUtil and _G.ChatFrameUtil.GetMobileEmbeddedTexture) or
    _G.ChatFrame_GetMobileEmbeddedTexture

local UNKNOWN = _G.UNKNOWN

-- Flip to true, /reload, enter an instance, and read the printed lines to see
-- exactly which chat arguments the client hides there and whether joining text
-- onto them is legal. Revert to false after diagnosing; the instrumentation
-- stays.
local DEBUG_CHAT = false

-- Answers the four open questions in one line per message: which arguments are
-- secret, whether the sender's class is still readable from a secret GUID, and
-- whether plain concatenation and format() actually throw on a secret sender.
-- The two joins are probed under pcall precisely because their legality is the
-- thing being measured.
---@param arg1 string? message body
---@param arg2 string? sender name
local function ChatDebugLine(event, arg1, arg2, arg12, chatType)
    if not DEBUG_CHAT then return end

    local msgSecret = KE:IsSecretValue(arg1) and "SECRET" or "plain"
    local nameSecret = KE:IsSecretValue(arg2) and "SECRET" or "plain"
    local guidSecret = KE:IsSecretValue(arg12) and "SECRET" or "plain"

    local class = "nil"
    if arg12 then
        local _, englishClass = GetPlayerInfoByGUID(arg12)
        if englishClass then
            class = KE:IsSecretValue(englishClass) and "SECRET" or tostring(englishClass)
        end
    end

    local concatOk = "n/a"
    local formatOk = "n/a"
    if arg2 then
        concatOk = pcall(function() return "x" .. arg2 end) and "ok" or "THROWS"
        formatOk = pcall(format, "[%s]", arg2) and "ok" or "THROWS"
    end

    -- Can two secrets be joined to EACH OTHER? A chat line inside an instance
    -- carries a secret sender AND a secret body, so any fix that assembles the
    -- two needs this answer and nothing on record supplies it. Probed with
    -- WrapString under pcall, so a refusal is recorded rather than
    -- escaping the diagnostic.
    local wrapTwoOk = "n/a"
    local wrap = C_StringUtil and C_StringUtil.WrapString
    if wrap and arg1 and arg2 then
        local ok, joined = pcall(wrap, arg1, arg2)
        wrapTwoOk = (ok and type(joined) ~= "nil") and "ok" or "NO"
    end

    KE:Print(format(
        "CHATDBG %s type=%s msg=%s name=%s guid=%s class=%s concat=%s format=%s wraptwo=%s",
        tostring(event), tostring(chatType), msgSecret, nameSecret, guidSecret,
        class, concatOk, formatOk, wrapTwoOk))
end

-- Role icons before names in group
-- chat. CMH.lfgRoles is keyed by sender name (short AND name-realm keys,
-- both written at cache-build time in Modules/Skinning/Chat.lua on
-- GROUP_ROSTER_UPDATE); values are ready-made |T|t texture strings.
CMH.lfgRoles = {}

-- Set for the duration of a history replay. Every place in THIS file that
-- treats a message as new checks it, which is wider than sound and light: the
-- reply target neither speaks nor flashes and still has to be guarded. It says
-- nothing about third-party message filters, which run during replay and have
-- no reason to know the flag exists.
CMH.replaying = false
local GROUP_CHAT_TYPES = {
    PARTY = true, PARTY_LEADER = true,
    RAID = true, RAID_LEADER = true,
    INSTANCE_CHAT = true, INSTANCE_CHAT_LEADER = true,
}

local accessIndex = 1
local accessInfo = {}
local accessType = {}
local accessTarget = {}
local accessSender = {}

local function GetToken(chatType, chatTarget, chanSender)
    return format('%s;;%s;;%s', strlower(chatType), chatTarget or '', chanSender or '')
end

function CMH:GetAccessID(chatType, chatTarget, chanSender)
    local token = GetToken(chatType, chatTarget, chanSender)

    if KE:IsSecretValue(token) then return end

    if not accessInfo[token] then
        accessInfo[token] = accessIndex
        accessType[accessIndex] = chatType
        accessTarget[accessIndex] = chatTarget
        accessSender[accessIndex] = chanSender
        accessIndex = accessIndex + 1
    end

    return accessInfo[token]
end

function CMH:GetAccessType(accessID)
    return accessType[accessID], accessTarget[accessID], accessSender[accessID]
end

function CMH:GetAllAccessIDsByChanSender(chanSender)
    local senders = {}
    local chanSenderLower = strlower(chanSender)
    for accessID, sender in next, accessSender do
        if strlower(sender) == chanSenderLower then
            senders[#senders + 1] = accessID
        end
    end
    return senders
end

-- Player link functions
local function GetLink(linkType, displayText, ...)
    local text = ''
    for i, value in next, { ... } do text = text .. (i == 1 and format('|H%s:', linkType) or ':') .. value end
    return text .. (displayText and format('|h%s|h', displayText) or '|h')
end

function CMH:GetPlayerLink(characterName, displayText, lineID, chatType, chatTarget)
    if lineID or chatType or chatTarget then
        return GetLink('player', displayText, characterName, lineID or 0, chatType or 0,
            KE:NotSecretValue(chatTarget) and chatTarget or '')
    else
        return GetLink('player', displayText, characterName)
    end
end

function CMH:GetBNPlayerLink(name, displayText, bnetIDAccount, lineID, chatType, chatTarget)
    return GetLink('BNplayer', displayText, name, bnetIDAccount, lineID or 0, chatType, chatTarget)
end

-- Secret-safe chat target
function CMH:FCFManager_GetChatTarget(chatGroup, playerTarget, channelTarget)
    local chatTarget
    if chatGroup == 'CHANNEL' then
        chatTarget = tostring(channelTarget)
    elseif chatGroup == 'WHISPER' or chatGroup == 'BN_WHISPER' then
        chatTarget = KE:NotSecretValue(playerTarget) and strsub(playerTarget, 1, 2) ~= '|K' and
            strupper(playerTarget) or playerTarget
    end
    return chatTarget
end

-- Flash tab for new messages
local function FlashTabIfNotShown(frame, info, chatType, chatGroup, chatTarget)
    if frame:IsShown() then return end

    local allowAlerts = ((frame ~= _G.DEFAULT_CHAT_FRAME and info.flashTab) or (frame == _G.DEFAULT_CHAT_FRAME and info.flashTabOnGeneral)) and
        ((chatType == 'WHISPER' or chatType == 'BN_WHISPER') or (_G.CHAT_OPTIONS and not _G.CHAT_OPTIONS.HIDE_FRAME_ALERTS))
    if allowAlerts and KE:NotSecretValue(chatTarget) and not _G.FCFManager_ShouldSuppressMessageFlash(frame, chatGroup, chatTarget) then
        _G.FCF_StartAlertFlash(frame)
    end
end

-- Get class-colored name
function CMH:GetColoredName(event, _, arg2, _, _, _, _, _, arg8, _, _, _, arg12)
    if KE:IsSecretValue(arg12) then
        local _, englishClass = GetPlayerInfoByGUID(arg12)
        if englishClass and C_ClassColor_GetClassColor then
            local classColor = C_ClassColor_GetClassColor(englishClass)
            return (classColor and classColor:WrapTextInColorCode(arg2)) or arg2
        end
        return arg2
    elseif KE:IsSecretValue(arg2) then
        return arg2
    end

    if not arg2 then return end

    local chatType = strsub(event, 10)
    local subType = strsub(chatType, 1, 7)
    if subType == 'WHISPER' then
        chatType = 'WHISPER'
    elseif subType == 'CHANNEL' then
        chatType = 'CHANNEL' .. arg8
    end

    local name = Ambiguate(arg2, (chatType == 'GUILD' and 'guild') or 'none')

    local info = name and arg12 and _G.ChatTypeInfo[chatType]
    if info and ShouldColorChatByClass and ShouldColorChatByClass(info) then
        local _, englishClass = GetPlayerInfoByGUID(arg12)
        if englishClass then
            local classColor = C_ClassColor_GetClassColor and C_ClassColor_GetClassColor(englishClass)
            if classColor then
                return classColor:WrapTextInColorCode(name)
            end
        end
    end

    return name
end

-- Get player flags
function CMH:GetPFlag(specialFlag, _, _)
    local flag = ''

    if specialFlag and specialFlag ~= '' then
        if specialFlag == 'GM' or specialFlag == 'DEV' then
            flag = '|TInterface\\ChatFrame\\UI-ChatIcon-Blizz:12:20:0:0:32:16:4:28:0:16|t '
        elseif specialFlag == 'GUIDE' then
            flag = '|TInterface\\ChatFrame\\UI-ChatIcon-Guide:12:12:0:0|t '
        elseif specialFlag == 'NEWCOMER' then
            flag = '|TInterface\\ChatFrame\\UI-ChatIcon-Newcomer:12:12:0:0|t '
        end
    end

    return flag
end

-- Check if channel should be added
local function ChatFrame_CheckAddChannel(frame, eventType, channelID)
    if frame ~= _G.DEFAULT_CHAT_FRAME then return false end
    if KE:IsSecretValue(eventType) then return false end
    if eventType ~= "YOU_CHANGED" then return false end
    if not IsChannelRegionalForChannelID or not IsChannelRegionalForChannelID(channelID) then return false end

    if frame.AddChannel then
        return frame:AddChannel(GetChannelShortcutForChannelID(channelID)) ~= nil
    elseif _G.ChatFrame_AddChannel then
        return _G.ChatFrame_AddChannel(frame, GetChannelShortcutForChannelID(channelID)) ~= nil
    end
    return false
end

-- Safe zone channel access
function CMH:ChatFrame_GetZoneChannel(frame, index)
    return frame.zoneChannelList and frame.zoneChannelList[index]
end

-- Icon replacement
local seenGroups = {}
function CMH:ChatFrame_ReplaceIconAndGroupExpressions(message, noIconReplacement, noGroupReplacement)
    if not message then return message end

    local ICON_LIST = _G.ICON_LIST
    local ICON_TAG_LIST = _G.ICON_TAG_LIST
    local GROUP_TAG_LIST = _G.GROUP_TAG_LIST

    if not ICON_LIST or not ICON_TAG_LIST then return message end

    wipe(seenGroups)

    for tag in gmatch(message, '%b{}') do
        local term = strlower(gsub(tag, '[{}]', ''))
        if not noIconReplacement and ICON_TAG_LIST[term] and ICON_LIST[ICON_TAG_LIST[term]] then
            message = gsub(message, tag, ICON_LIST[ICON_TAG_LIST[term]] .. '0|t')
        elseif not noGroupReplacement and GROUP_TAG_LIST and GROUP_TAG_LIST[term] then
            local groupIndex = GROUP_TAG_LIST[term]
            if not seenGroups[groupIndex] then
                seenGroups[groupIndex] = true
                local groupList = '['
                for i = 1, GetNumGroupMembers() do
                    local name, _, subgroup, _, _, classFilename = GetRaidRosterInfo(i)
                    if name and subgroup == groupIndex then
                        local classColor = C_ClassColor_GetClassColor and C_ClassColor_GetClassColor(classFilename)
                        if classColor then
                            name = classColor:WrapTextInColorCode(name)
                        end
                        groupList = groupList .. (groupList == '[' and '' or _G.PLAYER_LIST_DELIMITER) .. name
                    end
                end
                if groupList ~= '[' then
                    groupList = groupList .. ']'
                    message = gsub(message, tag, groupList, 1)
                end
            end
        end
    end

    return message
end

---------------------------------------------------------------------------------
-- Achievement merging
---------------------------------------------------------------------------------

-- Groups PLAYERS ONLY: several people earning the same achievement collapse into
-- one line. One person earning several achievements stays several lines, because
-- the merged line reuses Blizzard's own localised format string and there is no
-- published wording for that case.
--
-- cache[frame][event][achievementID] = {
--     order    = { playerLink, ... },   -- insertion order, sorted before use
--     seen     = { [playerLink] = true },
--     link     = <the achievement link lifted from arg1, already decorated>,
--     rendered = <exactly what the caller would have printed>,
--     info     = <ChatTypeInfo entry the caller would have coloured with>,
-- }
local achievementCache = {}
local ACHIEVEMENT_WINDOW = 0.3

local function AchievementBucket(frame, event)
    local perFrame = achievementCache[frame]
    if not perFrame then
        perFrame = {}
        achievementCache[frame] = perFrame
    end

    local perEvent = perFrame[event]
    if not perEvent then
        perEvent = {}
        perFrame[event] = perEvent
    end

    return perEvent
end

-- The client publishes no plural "have earned the achievement" string, so a
-- merged line is a LABEL rather than a sentence: link, label, names. The label
-- is read from the client so it is localised; the two-word fallback exists only
-- because a GlobalString absent from the local reference clone is a coverage
-- gap rather than proof it is missing, and a nil label must not produce "nil".
-- GUILD_ACHIEVEMENT_EARNED_BY is a plain label and the live client uses it, so
-- the fallback is a last resort against a client that does not publish it -- NOT
-- ACHIEVEMENT_EARNED_BY, which is a format string and would render a literal %s.
local function EarnedByLabel()
    return _G.GUILD_ACHIEVEMENT_EARNED_BY or "Earned by"
end

local function EmitAchievement(frame, event, achievementID)
    local perEvent = AchievementBucket(frame, event)
    local entry = perEvent[achievementID]
    if not entry then return end
    perEvent[achievementID] = nil

    local info = entry.info
    if not info then return end

    if #entry.order <= 1 then
        -- Anchor 4: the common case is never re-worded. Replay exactly what the
        -- caller would have printed, in the client's own language.
        frame:AddMessage(entry.rendered, info.r, info.g, info.b, info.id)
        return
    end

    -- Sorted, because an unordered join lets the same group of people produce
    -- two different lines on two occasions.
    sort(entry.order)
    -- Blizzard's own list separator, which this file already uses elsewhere.
    -- Hardcoding ", " would put English punctuation on every locale.
    local delimiter = _G.PLAYER_LIST_DELIMITER or ", "
    frame:AddMessage(format("%s %s %s", entry.link, EarnedByLabel(),
        strjoin(delimiter, unpack(entry.order))), info.r, info.g, info.b, info.id)
end

-- Returns true when the line has been captured and the caller must not print it.
-- Every refusal returns nil, so the caller prints normally -- a message that
-- cannot be merged is never a message that gets swallowed.
function CMH:CaptureAchievement(frame, event, info, message, playerLink)
    -- Secret guards come FIRST, before any truth test -- and here that is
    -- load-bearing, not defensive. The achievement branch deliberately hands
    -- this helper a possibly-secret playerLink rather than splitting into two
    -- paths, so THIS is the first contact. Refusing sends the line back to the
    -- caller to print unmerged.
    if not (KE:NotSecretValue(message) and KE:NotSecretValue(playerLink)) then return end

    if not (frame and event and info and message and playerLink) then return end

    local db = KE.db and KE.db.profile.Skinning.Chat
    if not (db and db.MergeAchievements) then return end

    local achievementID = strmatch(message, "|Hachievement:(%d+):")
    if not achievementID then return end

    -- The whole link INCLUDING any icon the incoming filter prepended AND the
    -- colour escape that wraps both -- the client sends
    -- "|cffffff00<link>|r" and the incoming filter builds
    -- "|cffffff00<icon> <link>|r", so a pattern anchored at |T or |H drops the
    -- icon, the colour, or both. Losing the colour is not cosmetic in one
    -- place only: the merged line is printed in the channel's colour, so a
    -- guild achievement rendered its title green while the identical personal
    -- announcement rendered it gold.
    --
    -- Four alternatives, widest first, all bound to THIS achievement's id. The
    -- uncoloured pair stays because a caller that strips colour must still
    -- merge. The texture is [^|]- rather than .- so it cannot swallow an
    -- earlier unrelated escape or the prose between them. An unbound pattern
    -- captured "|Traid:14|t before |Tachievement:14|t |Hachievement:123..." as
    -- the link, and paired a second achievement's decorated link with the first
    -- one's id. Nothing may sit between |c and the icon or |H, so the colour
    -- cannot be borrowed from an unrelated escape earlier in the line. The id
    -- is digits only, so splicing it into a pattern is safe.
    -- [^|]* rather than .-: an unterminated prefix followed by a VALID link let
    -- the lazy form run through the neighbour's |h terminators and report the
    -- first id with the second link's text. Neither achievement link data nor a
    -- display name can contain a bar -- one would break the client's own parser
    -- -- so excluding it cannot cross into an adjacent escape. Well-formed
    -- announcements match exactly as before; only text a filter has mangled
    -- now refuses instead of mis-pairing.
    local body = "|Hachievement:" .. achievementID .. ":[^|]*|h[^|]*|h"
    local decorated = "|T[^|]-|t " .. body
    local link = strmatch(message, "(|c%x%x%x%x%x%x%x%x" .. decorated .. "|r)")
        or strmatch(message, "(|c%x%x%x%x%x%x%x%x" .. body .. "|r)")
        or strmatch(message, "(" .. decorated .. ")")
        or strmatch(message, "(" .. body .. ")")
    if not link then return end

    -- arg1 is a FORMAT string, so a literal percent in the title arrives
    -- doubled. The merged line passes the link as an argument rather than a
    -- format, so undo the doubling or it renders as %%.
    link = gsub(link, "%%%%", "%%")

    local perEvent = AchievementBucket(frame, event)
    local entry = perEvent[achievementID]

    if not entry then
        entry = {
            order = {},
            seen = {},
            link = link,
            rendered = format(message, playerLink),
            info = info,
        }
        perEvent[achievementID] = entry
    end

    -- A repeated announcement for the same person must not name them twice.
    if not entry.seen[playerLink] then
        entry.seen[playerLink] = true
        tinsert(entry.order, playerLink)
    end

    -- Scheduled AFTER the first player is recorded, so a synchronous timer --
    -- which the spec harness installs -- still finds a populated group.
    if not entry.scheduled then
        entry.scheduled = true
        C_Timer.After(ACHIEVEMENT_WINDOW, function()
            EmitAchievement(frame, event, achievementID)
        end)
    end

    return true
end

function CMH.FlushAchievements()
    for frame, perFrame in pairs(achievementCache) do
        for event, perEvent in pairs(perFrame) do
            for achievementID in pairs(perEvent) do
                EmitAchievement(frame, event, achievementID)
            end
        end
    end
end

function CMH.ResetAchievements()
    wipe(achievementCache)
end

---------------------------------------------------------------------------------
-- Body highlight
---------------------------------------------------------------------------------

local MYNAME_TOKEN = "%MYNAME%"
local SOUND_THROTTLE = 5

-- Module-scope scratch. A chat line is rewritten once per frame that displays
-- it, so allocating five tables per line is measurable.
local protectStart, protectEnd = {}, {}
local hitStart, hitEnd, hitColor = {}, {}, {}

local keywordSet, keywordSource = {}, nil
local excludeSet, excludeSource = {}, nil
local soundReadyAt = 0

-- Trimmed at both ends. Stripping only one space after each comma -- as the
-- reference does -- stores "a " for "a , b", and a stored trailing space can
-- never match a candidate, so those entries are silently dead.
function CMH.ParseList(raw)
    local set = {}
    if not raw or raw == "" then return set end

    local myName = _G.UnitName("player")

    for token in gmatch(raw, "[^,]+") do
        token = gsub(token, "^%s*(.-)%s*$", "%1")
        if token == MYNAME_TOKEN then token = myName end
        if token and token ~= "" then set[strlower(token)] = true end
    end

    return set
end

local function Keywords(raw)
    if raw ~= keywordSource then
        keywordSource = raw
        keywordSet = CMH.ParseList(raw)
    end
    return keywordSet
end

local function Exclusions(raw)
    if raw ~= excludeSource then
        excludeSource = raw
        excludeSet = CMH.ParseList(raw)
    end
    return excludeSet
end

-- The Chat module is an Ace module; there is no KE.Chat. Resolved at call time
-- and never cached as a miss, because this file loads before Chat registers.
local chatModule
local function ChatModule()
    if not chatModule then
        chatModule = _G.KitnEssentials and _G.KitnEssentials:GetModule("Chat", true)
    end
    return chatModule
end

-- Records the byte range of every escape sequence so no rewrite can land inside
-- one. A colour span protects its CONTENT as well as its markers: colouring text
-- that is already coloured inserts a |r that closes the OUTER colour early, so
-- the rest of the original span silently loses its colour.
function CMH.CollectProtected(text)
    local count, pos = 0, 1
    local colorOpen, colorDepth = nil, 0

    while true do
        local p = text:find("|", pos, true)
        if not p then break end

        local c = text:sub(p + 1, p + 1)
        local e

        if c == "c" then
            if text:sub(p + 2, p + 2) == "n" then
                local colon = text:find(":", p + 3, true)
                e = colon or (p + 2)
            else
                e = p + 9
            end
            -- Depth, not a single flag: a nested |c inside an open span must
            -- not let the inner |r close the outer one, or the tail of the
            -- outer span becomes eligible for rewriting again.
            colorOpen = colorOpen or p
            colorDepth = colorDepth + 1
        elseif c == "r" then
            e = p + 1
            if colorOpen then
                colorDepth = colorDepth - 1
                if colorDepth <= 0 then
                    count = count + 1
                    protectStart[count] = colorOpen
                    protectEnd[count] = e
                    colorOpen, colorDepth = nil, 0
                end
            end
        elseif c == "H" then
            local first = text:find("|h", p + 2, true)
            local second = first and text:find("|h", first + 2, true)
            e = (second and second + 1) or (first and first + 1) or (p + 1)
        elseif c == "T" then
            local close = text:find("|t", p + 2, true)
            e = (close and close + 1) or (p + 1)
        elseif c == "A" then
            local close = text:find("|a", p + 2, true)
            e = (close and close + 1) or (p + 1)
        elseif c == "|" then
            e = p + 1
        else
            pos = p + 1
        end

        if e then
            count = count + 1
            protectStart[count] = p
            protectEnd[count] = e
            pos = e + 1
        end
    end

    -- An unterminated colour protects everything to the end of the line.
    if colorOpen then
        count = count + 1
        protectStart[count] = colorOpen
        protectEnd[count] = #text
    end

    -- Escaped percent pairs. On the boss-monster path the finished body is
    -- concatenated INTO a format string rather than passed as an argument, and
    -- the percent escaping that runs earlier in MessageFormatter leaves %%
    -- pairs behind. A colour code inserted between the two bytes makes that
    -- format call throw, so a hit overlapping a pair is refused. On every other
    -- path the pairs are simply absent and this loop exits at once.
    local pp = 1
    while true do
        local p = text:find("%%", pp, true)
        if not p then break end
        count = count + 1
        protectStart[count] = p
        protectEnd[count] = p + 1
        pp = p + 2
    end

    return count
end

-- Byte level, because a Lua pattern class would split a multi-byte name. Any
-- byte at or above 128 belongs to a UTF-8 sequence and counts as a word
-- character, so accented names stay whole.
---@param text string
---@param index number
---@return boolean
function CMH.IsBoundary(text, index)
    if index < 1 or index > #text then return true end

    local b = text:byte(index)
    if b >= 128 then return false end
    if b >= 48 and b <= 57 then return false end
    if b >= 65 and b <= 90 then return false end
    if b >= 97 and b <= 122 then return false end

    return true
end

local function Blocked(s, e, protectCount)
    for i = 1, protectCount do
        if s <= protectEnd[i] and e >= protectStart[i] then return true end
    end
    return false
end

local function HexFrom(r, g, b)
    return format("|cff%02x%02x%02x", (r or 1) * 255, (g or 1) * 255, (b or 0) * 255)
end

local function ClassColorString(class)
    local colors = _G.RAID_CLASS_COLORS
    local color = colors and class and colors[class]
    if not color then return nil end
    return HexFrom(color.r, color.g, color.b)
end

local function RecordHit(count, s, e, colorString)
    count = count + 1
    hitStart[count] = s
    hitEnd[count] = e
    hitColor[count] = colorString
    return count
end

-- Plain find, never a pattern, so a keyword carrying a magic character needs no
-- escaping and cannot corrupt the search. KEYWORDS only: the set is user-typed
-- and small, and a keyword may be a phrase containing spaces, which the
-- candidate walk below cannot see.
local function ScanFor(text, lowered, needle, colorString, protectCount, hitCount)
    local length = #needle
    if length == 0 then return hitCount end

    local from = 1
    while true do
        local s = lowered:find(needle, from, true)
        if not s then break end

        local e = s + length - 1
        from = e + 1

        if CMH.IsBoundary(text, s - 1) and CMH.IsBoundary(text, e + 1)
            and not Blocked(s, e, protectCount) then
            hitCount = RecordHit(hitCount, s, e, colorString)
        end
    end

    return hitCount
end

-- Walks the body ONCE, cuts it into boundary-delimited candidates, and looks
-- each one up directly. Scanning once per cached name instead would be up to a
-- thousand full-body searches per frame per message, because the class-name
-- cache holds up to two entries for each cached GUID.
---@param text string
---@param lowered string
local function ScanMentions(text, lowered, classNames, excluded, protectCount, hitCount)
    local length = #text
    local i = 1

    while i <= length do
        if CMH.IsBoundary(text, i) then
            i = i + 1
        else
            local s = i
            while i <= length and not CMH.IsBoundary(text, i) do i = i + 1 end
            local e = i - 1

            -- A realm-qualified name spans one hyphen. Try the long form first
            -- so "Ana-Realm" wins over "Ana".
            local longEnd = e
            if text:sub(e + 1, e + 1) == "-" and not CMH.IsBoundary(text, e + 2) then
                local j = e + 2
                while j <= length and not CMH.IsBoundary(text, j) do j = j + 1 end
                longEnd = j - 1
            end

            local tries = (longEnd ~= e) and 2 or 1
            for attempt = 1, tries do
                local stop = (attempt == 1) and longEnd or e
                local candidate = lowered:sub(s, stop)

                -- Exclusion is read BEFORE the class lookup. Checking it only
                -- for a cached name would let "Ana-Realm" fall through to
                -- "Ana" whenever the realm-qualified form was never cached,
                -- colouring exactly the name the user excluded.
                if excluded[candidate] then break end

                local class = classNames[candidate]
                if class then
                    local colorString = ClassColorString(class)
                    if colorString and not Blocked(s, stop, protectCount) then
                        hitCount = RecordHit(hitCount, s, stop, colorString)
                        break
                    end
                end
            end

            if longEnd ~= e then i = longEnd + 1 end
        end
    end

    return hitCount
end

-- The SOUND is gated on the sender, not the colour: your keyword still
-- colours in a line you typed, it just does not ding you. An unreadable sender
-- counts as somebody else -- a missed alert is worse than an occasional
-- self-ding, and your own name is not identity-restricted.
--
-- The realm half is compared rather than discarded. Comparing names alone would
-- silence a same-named player from another realm, which is the missed alert the
-- line above says to avoid.
--
-- The two realm spellings are not the same string. A chat sender's suffix is
-- the NORMALIZED realm, stripped of spaces and punctuation; UnitFullName's
-- second return is the display realm, which keeps them. Blizzard compares a
-- chat-style server token against GetNormalizedRealmName for exactly this
-- reason (Blizzard_UnitPopup/Mainline/UnitPopupUtils.lua). That call is nil
-- before PLAYER_LOGIN, so the display realm is stripped as a fallback.
local function StripRealm(realm)
    if not realm then return nil end
    -- Whitespace AND punctuation: "Aggra (Português)" is a live realm name, so
    -- stripping only space, hyphen and apostrophe leaves the parentheses behind
    -- and the two spellings never meet. Lua's %p is ASCII under the C locale,
    -- so bytes at or above 128 pass through and accented realms still match.
    return strlower(gsub(realm, "[%s%p]", ""))
end

---@param author string?
local function IsSelf(author)
    if KE:IsSecretValue(author) or not author then return false end

    -- Fetched in an if, not through `and`. Lua's `and` and `or` collapse to a
    -- SINGLE value, so `x and f()` discards every return past the first --
    -- displayRealm would be permanently nil, silently defeating the realm
    -- comparison below. See amendment A2.
    local me, displayRealm
    if _G.UnitFullName then me, displayRealm = _G.UnitFullName("player") end
    if not me then return false end

    local name, realm = author:match("^([^-]+)-?(.*)$")
    if not name or strlower(name) ~= strlower(me) then return false end

    -- Blizzard omits the realm for a sender on your own realm and appends it
    -- otherwise, so an empty realm here means the sender shares yours.
    if realm == "" then return true end

    local myRealm = (_G.GetNormalizedRealmName and _G.GetNormalizedRealmName())
        or displayRealm
    myRealm = StripRealm(myRealm)

    return myRealm ~= nil and StripRealm(realm) == myRealm
end

---@param text string
---@param author string?
function CMH.Highlight(text, author)
    if not text or text == "" then return text end

    local db = KE.db and KE.db.profile.Skinning.Chat
    if not db then return text end

    local keywords = Keywords(db.HighlightKeywords)
    local wantKeywords = next(keywords) ~= nil

    local chat = ChatModule()
    local classNames = db.ClassColorMentions and chat and chat.ClassNames
    local wantMentions = classNames and next(classNames) ~= nil

    if not (wantKeywords or wantMentions) then return text end

    local lowered = strlower(text)
    local protectCount = CMH.CollectProtected(text)
    local hitCount = 0
    local matchedKeyword = false

    if wantKeywords then
        local c = db.HighlightColor
        local colorString = HexFrom(c and c[1], c and c[2], c and c[3])
        for keyword in pairs(keywords) do
            local before = hitCount
            hitCount = ScanFor(text, lowered, keyword, colorString, protectCount, hitCount)
            if hitCount > before then matchedKeyword = true end
        end
    end

    if wantMentions then
        hitCount = ScanMentions(text, lowered, classNames,
            Exclusions(db.ExcludedMentions), protectCount, hitCount)
    end

    if hitCount == 0 then return text end

    -- Insertion sort by start, then by DESCENDING end. Two hits starting at the
    -- same byte must always resolve to the longer one, or the output depends on
    -- hash iteration order.
    for i = 2, hitCount do
        local s, e, c = hitStart[i], hitEnd[i], hitColor[i]
        local j = i - 1
        while j >= 1 and (hitStart[j] > s or (hitStart[j] == s and hitEnd[j] < e)) do
            hitStart[j + 1], hitEnd[j + 1], hitColor[j + 1] = hitStart[j], hitEnd[j], hitColor[j]
            j = j - 1
        end
        hitStart[j + 1], hitEnd[j + 1], hitColor[j + 1] = s, e, c
    end

    local pieces, np, pos = {}, 0, 1
    for i = 1, hitCount do
        local s, e = hitStart[i], hitEnd[i]
        -- Overlaps are dropped rather than nested: nesting breaks the |r
        -- pairing, and two colours over the same bytes render as one anyway.
        if s >= pos then
            np = np + 1; pieces[np] = text:sub(pos, s - 1)
            np = np + 1; pieces[np] = hitColor[i]
            np = np + 1; pieces[np] = text:sub(s, e)
            np = np + 1; pieces[np] = "|r"
            pos = e + 1
        end
    end
    np = np + 1
    pieces[np] = text:sub(pos)

    if matchedKeyword and not IsSelf(author) and not CMH.replaying then CMH.PlayKeywordSound(db) end

    return tconcat(pieces)
end

-- Every global here is read through _G at CALL time. LibStub may not exist when
-- this file loads, and a spec that swaps one of these in after the module has
-- loaded cannot reach an upvalue.
function CMH.PlayKeywordSound(db)
    local sound = db.HighlightSound
    if not sound or sound == "None" then return end
    if db.HighlightNoSoundInCombat and _G.InCombatLockdown() then return end

    local now = _G.GetTime()
    if now < soundReadyAt then return end
    soundReadyAt = now + SOUND_THROTTLE

    local LSM = _G.LibStub and _G.LibStub("LibSharedMedia-3.0", true)
    local path = LSM and LSM:Fetch("sound", sound, true)
    if path then _G.PlaySoundFile(path, "Master") end
end

function CMH.ResetHighlight()
    keywordSource, excludeSource, soundReadyAt = nil, nil, 0
    keywordSet, excludeSet = {}, {}
    chatModule = nil
end

-- Message formatter, formats the message body
function CMH:MessageFormatter(frame, info, chatType, chatGroup, chatTarget, channelLength, coloredName, arg1, arg2, arg3,
                              arg4, _, arg6, arg7, arg8, _, _, arg11, arg12, arg13, arg14, _, _, arg17)
    local body

    -- Only return early if message itself is nil
    if not arg1 then return end

    if chatType == 'WHISPER_INFORM' and GMChatFrame_IsGM and GMChatFrame_IsGM(arg2) then return end

    -- Check if message content is protected
    local isProtected = KE:IsSecretValue(arg1)
    local bossMonster = strsub(chatType, 1, 9) == 'RAID_BOSS' or strsub(chatType, 1, 7) == 'MONSTER'

    -- Protected boss messages can't be safely formatted, skip custom formatting
    if isProtected and bossMonster then return end

    if bossMonster and not isProtected then
        arg1 = gsub(arg1, '(%d%s?%%)([^%%%a])', '%1%%%2')
        arg1 = gsub(arg1, '(%d%s?%%)$', '%1%%')
    end

    if not isProtected then
        if RemoveExtraSpaces then arg1 = RemoveExtraSpaces(arg1) end

        if _G.ChatFrameUtil and _G.ChatFrameUtil.CanChatGroupPerformExpressionExpansion then
            arg1 = self:ChatFrame_ReplaceIconAndGroupExpressions(arg1, arg17,
                not _G.ChatFrameUtil.CanChatGroupPerformExpressionExpansion(chatGroup))
        elseif _G.ChatFrame_CanChatGroupPerformExpressionExpansion then
            arg1 = self:ChatFrame_ReplaceIconAndGroupExpressions(arg1, arg17,
                not _G.ChatFrame_CanChatGroupPerformExpressionExpansion(chatGroup))
        end

        -- Inside the existing secret guard on purpose: a plain string rewrite
        -- must never touch a protected body.
        arg1 = CMH.Highlight(arg1, arg2)
    end

    -- Player link, use fallbacks for nil values
    coloredName = coloredName or arg2 or UNKNOWN
    local playerLink
    local playerLinkDisplayText = coloredName
    local relevantDefaultLanguage = frame.defaultLanguage
    if chatType == 'SAY' or chatType == 'YELL' then relevantDefaultLanguage = frame.alternativeDefaultLanguage end
    local usingDifferentLanguage = (arg3 and arg3 ~= '') and (arg3 ~= relevantDefaultLanguage)
    local usingEmote = (chatType == 'EMOTE') or (chatType == 'TEXT_EMOTE')

    if usingDifferentLanguage or not usingEmote then playerLinkDisplayText = format('[%s]', coloredName) end

    local playerName = arg2 or UNKNOWN
    if chatType == 'BN_WHISPER' or chatType == 'BN_WHISPER_INFORM' then
        playerLink = self:GetBNPlayerLink(playerName, playerLinkDisplayText, arg13, arg11, chatGroup, chatTarget)
    elseif not bossMonster then
        playerLink = self:GetPlayerLink(playerName, playerLinkDisplayText, arg11, chatGroup, chatTarget)
    end

    -- Ensure we have valid values for formatting
    local sender = (not bossMonster and playerLink) or arg2 or UNKNOWN
    local isMobile = arg14 and GetMobileEmbeddedTexture and GetMobileEmbeddedTexture(info.r, info.g, info.b)
    local message = format('%s%s', isMobile or '', arg1 or '')

    local pflag = self:GetPFlag(arg6, arg7, arg12) or ''

    -- lfgRoles injection point (pflag..icon..sender).
    -- playerName (arg2) can be a SECRET value in group content on
    -- Midnight; plain tables cannot be indexed with secret keys (26x
    -- party-chat error in dungeons). Guard with the canonical helper --
    -- secret senders simply skip the icon, same policy as the rest of
    -- this file's arg2 handling.
    if GROUP_CHAT_TYPES[chatType] and not KE:IsSecretValue(playerName) then
        local roleIcon = CMH.lfgRoles[playerName]
        if roleIcon then pflag = pflag .. roleIcon end
    end

    local chatFormat = _G['CHAT_' .. chatType .. '_GET']
    if not chatFormat then return message end

    if usingDifferentLanguage then
        body = format(chatFormat .. '[%s] %s', pflag .. sender, arg3 or '', message)
    elseif chatType == 'TEXT_EMOTE' then
        body = message
    elseif bossMonster then
        body = format(chatFormat .. message, pflag .. sender, sender)
    else
        body = format(chatFormat .. '%s', pflag .. sender, message)
    end

    if channelLength and channelLength > 0 and arg8 and arg4 then
        body = '|Hchannel:channel:' .. arg8 .. '|h[' .. ResolvePrefixedChannelName(arg4) .. ']|h ' .. body
    end

    return body
end

-- Main message event handler
function CMH:ChatFrame_MessageEventHandler(frame, event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10,
                                           arg11, arg12, arg13, arg14, arg15, arg16, arg17, arg18, isHistory,
                                           historyTime)
    if not event then return true end

    local isProtected = KE:IsSecretValue(arg2)

    -- Text to speech
    if _G.TextToSpeechFrame_MessageEventHandler and not CMH.replaying then
        _G.TextToSpeechFrame_MessageEventHandler(frame, event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9,
            arg10, arg11, arg12, arg13, arg14, arg15, arg16, arg17, arg18)
    end

    if strsub(event, 1, 8) == 'CHAT_MSG' then
        if arg16 then return true end -- hiding sender in letterbox

        local chatType = strsub(event, 10)
        local info = _G.ChatTypeInfo[chatType]
        if not info then return end

        ChatDebugLine(event, arg1, arg2, arg12, chatType)

        if arg6 == 'GM' and chatType == 'WHISPER' then return end

        -- Process message filters
        if _G.ChatFrameUtil and _G.ChatFrameUtil.ProcessMessageEventFilters then
            -- The filter chain carries arg1..arg14 only. Asking for more
            -- assigned nil over arg15..arg17, and arg17 is the flag that
            -- suppresses raid-icon conversion further down.
            local filtered, new1, new2, new3, new4, new5, new6, new7, new8, new9, new10, new11, new12, new13, new14 =
                _G.ChatFrameUtil.ProcessMessageEventFilters(frame, event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8,
                    arg9, arg10, arg11, arg12, arg13, arg14)
            if filtered then
                return true
            else
                arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14 =
                    new1, new2, new3, new4, new5, new6, new7, new8, new9, new10, new11, new12, new13, new14
            end
        elseif _G.ChatFrame_GetMessageEventFilters then
            local chatFilters = _G.ChatFrame_GetMessageEventFilters(event)
            if chatFilters then
                for _, filterFunc in next, chatFilters do
                    local filtered, new1, new2, new3, new4, new5, new6, new7, new8, new9, new10, new11, new12, new13, new14, new15, new16, new17 =
                        filterFunc(frame, event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11,
                            arg12,
                            arg13, arg14, arg15, arg16, arg17)
                    if filtered then
                        return true
                    elseif new1 then
                        arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14, arg15, arg16, arg17 =
                            new1, new2, new3, new4, new5, new6, new7, new8, new9, new10, new11, new12, new13, new14,
                            new15,
                            new16, new17
                    end
                end
            end
        end

        local coloredName = self:GetColoredName(event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11,
            arg12, arg13, arg14)
        local channelLength = strlen(arg4 or '')
        local infoType = chatType

        -- Voice text check
        if chatType == 'VOICE_TEXT' and not GetCVarBool('speechToText') then return true end

        -- Channel handling
        if chatType == 'COMMUNITIES_CHANNEL' or ((strsub(chatType, 1, 7) == 'CHANNEL') and (chatType ~= 'CHANNEL_LIST') and ((KE:NotSecretValue(arg1) and arg1 ~= 'INVITE') or (chatType ~= 'CHANNEL_NOTICE_USER'))) then
            if KE:NotSecretValue(arg1) and arg1 == 'WRONG_PASSWORD' then
                local _, popup = _G.StaticPopup_Visible('CHAT_CHANNEL_PASSWORD')
                if popup and strupper(popup.data) == strupper(arg9) then
                    return true
                end
            end

            local found = false
            if frame.channelList and KE:NotSecretValue(arg9) then
                for index, value in pairs(frame.channelList) do
                    if channelLength > strlen(value) then
                        local match = strupper(value) == strupper(arg9)
                        if not match then
                            local success, zoneChannel = pcall(self.ChatFrame_GetZoneChannel, self, frame, index)
                            match = success and arg7 and arg7 > 0 and arg7 == zoneChannel
                        end

                        if match then
                            found = true
                            infoType = 'CHANNEL' .. arg8
                            info = _G.ChatTypeInfo[infoType]

                            if chatType == 'CHANNEL_NOTICE' and KE:NotSecretValue(arg1) and arg1 == 'YOU_LEFT' then
                                frame.channelList[index] = nil
                                if frame.zoneChannelList then frame.zoneChannelList[index] = nil end
                            end

                            break
                        end
                    end
                end
            end

            if not found or not info then
                local eventType, channelID = arg1, arg7
                if not ChatFrame_CheckAddChannel(frame, eventType, channelID) then return true end
            end
        end

        local chatGroup = GetChatCategory and GetChatCategory(chatType) or chatType
        local chatTarget = self:FCFManager_GetChatTarget(chatGroup, arg2, arg8)

        if chatTarget and KE:NotSecretValue(chatTarget) and _G.FCFManager_ShouldSuppressMessage then
            local success, shouldSuppress = pcall(_G.FCFManager_ShouldSuppressMessage, frame, chatGroup, chatTarget)
            if success and shouldSuppress then
                return true
            end
        end

        -- Whisper filtering
        if not isProtected and (chatGroup == 'WHISPER' or chatGroup == 'BN_WHISPER') and KE:NotSecretValue(arg2) then
            local nameLower = strlower(arg2)
            if frame.privateMessageList and not frame.privateMessageList[nameLower] then
                return true
            elseif frame.excludePrivateMessageList and frame.excludePrivateMessageList[nameLower] then
                if GetCVar('whisperMode') ~= 'popout_and_inline' then return true end
            end
        end

        -- System messages for dedicated whisper windows
        if frame.privateMessageList then
            if chatGroup == 'SYSTEM' then
                local msg = KE:NotSecretValue(arg1) and strlower(arg1)
                local found = false
                if msg then
                    for playerName in pairs(frame.privateMessageList) do
                        local notFound = strlower(format(_G.ERR_CHAT_PLAYER_NOT_FOUND_S, playerName))
                        local charOnline = strlower(format(_G.ERR_FRIEND_ONLINE_SS, playerName, playerName))
                        local charOffline = strlower(format(_G.ERR_FRIEND_OFFLINE_S, playerName))
                        if msg == notFound or msg == charOnline or msg == charOffline then
                            found = true
                            break
                        end
                    end
                end

                if not found then return true end
            elseif not isProtected and (chatGroup == 'BN_INLINE_TOAST_ALERT' or chatGroup == 'BN_WHISPER_PLAYER_OFFLINE') and KE:NotSecretValue(arg2) then
                local nameLower = strlower(arg2)
                if not frame.privateMessageList[nameLower] then return true end
            end
        end

        -- Handle different message types
        if (chatType == 'SYSTEM' or chatType == 'SKILL' or chatType == 'CURRENCY' or chatType == 'MONEY' or
                chatType == 'OPENING' or chatType == 'TRADESKILLS' or chatType == 'PET_INFO' or chatType == 'TARGETICONS' or chatType == 'BN_WHISPER_PLAYER_OFFLINE') then
            frame:AddMessage(arg1, info.r, info.g, info.b, info.id)
        elseif chatType == 'LOOT' then
            frame:AddMessage(arg1, info.r, info.g, info.b, info.id)
        elseif strsub(chatType, 1, 7) == 'COMBAT_' then
            frame:AddMessage(arg1, info.r, info.g, info.b, info.id)
        elseif strsub(chatType, 1, 6) == 'SPELL_' then
            frame:AddMessage(arg1, info.r, info.g, info.b, info.id)
        elseif strsub(chatType, 1, 10) == 'BG_SYSTEM_' then
            frame:AddMessage(arg1, info.r, info.g, info.b, info.id)
        elseif strsub(chatType, 1, 11) == 'ACHIEVEMENT' or strsub(chatType, 1, 18) == 'GUILD_ACHIEVEMENT' then
            if KE:NotSecretValue(arg1) then
                -- Both senders take this path. A secret one is substituted
                -- into a plain format string exactly as the shipped formatter
                -- already does it, and CaptureAchievement refuses a
                -- secret-derived playerLink on first contact, so it prints
                -- unmerged rather than being swallowed.
                local playerLink = self:GetPlayerLink(arg2, format('[%s]', coloredName or arg2))
                if not self:CaptureAchievement(frame, event, info, arg1, playerLink) then
                    frame:AddMessage(format(arg1, playerLink), info.r, info.g, info.b, info.id)
                end
            else
                -- A secret BODY does need its own path, and this is the whole
                -- of it. It cannot be a format string -- that is unverified --
                -- and it cannot be searched for the name slot, because a pattern
                -- match on a secret DOES throw. So it goes to the frame exactly
                -- as it arrived, which is what the neighbouring LOOT and SPELL_
                -- branches already do with an unguarded arg1. Anchor 5 says
                -- never dropped, and that covers a secret body as much as a
                -- secret sender.
                frame:AddMessage(arg1, info.r, info.g, info.b, info.id)
            end
        -- Blizzard's own branch is `format(CHAT_PING_GET, arg2) .. arg1`, with
        -- arg2 used RAW -- it is formatted natively for pings and can carry
        -- role text, so it is never turned into a player link.
        --
        -- No timestamp, unlike theirs: they AddMessage directly and stamp their
        -- own, where AddMessageEdits stamps every line of ours. The joins go
        -- through KE:WrapSecretText because BOTH parts can be secret here, and
        -- a plain `..` between two secrets is unverified -- unlike a plain-to-
        -- secret join, which is measured safe.
        elseif chatType == 'PING' then
            local pingBody = arg1
            local fmt = _G.CHAT_PING_GET or '%s '
            local pre, post = fmt:match('^(.-)%%s(.*)$')
            if not pre then pre, post = '', ' ' end

            local sender = arg2 ~= nil and KE:WrapSecretText(arg2, pre, post)
            if sender then
                pingBody = KE:WrapSecretText(arg1, sender, '') or arg1
            end

            frame:AddMessage(pingBody, info.r, info.g, info.b, info.id)
        elseif chatType == 'IGNORED' then
            if KE:NotSecretValue(arg2) then
                frame:AddMessage(format(_G.CHAT_IGNORED, arg2), info.r, info.g, info.b, info.id)
            end
        elseif chatType == 'FILTERED' then
            if KE:NotSecretValue(arg2) then
                frame:AddMessage(format(_G.CHAT_FILTERED, arg2), info.r, info.g, info.b, info.id)
            end
        elseif chatType == 'RESTRICTED' then
            frame:AddMessage(_G.CHAT_RESTRICTED_TRIAL, info.r, info.g, info.b, info.id)
        elseif chatType == 'CHANNEL_LIST' then
            if channelLength > 0 then
                frame:AddMessage(format(_G['CHAT_' .. chatType .. '_GET'] .. arg1, tonumber(arg8), arg4), info.r, info.g,
                    info.b, info.id)
            else
                frame:AddMessage(arg1, info.r, info.g, info.b, info.id)
            end
        elseif chatType == 'CHANNEL_NOTICE_USER' then
            local globalstring = KE:NotSecretValue(arg1) and
                (_G['CHAT_' .. arg1 .. '_NOTICE_BN'] or _G['CHAT_' .. arg1 .. '_NOTICE'])
            if not globalstring then return true end

            if arg5 ~= '' then
                frame:AddMessage(format(globalstring, arg8, arg4, arg2, arg5), info.r, info.g, info.b, info.id)
            elseif arg1 == 'INVITE' then
                frame:AddMessage(format(globalstring, arg4, arg2), info.r, info.g, info.b, info.id)
            else
                frame:AddMessage(format(globalstring, arg8, arg4, arg2), info.r, info.g, info.b, info.id)
            end

            if arg1 == 'INVITE' and GetCVarBool('blockChannelInvites') then
                frame:AddMessage(_G.CHAT_MSG_BLOCK_CHAT_CHANNEL_INVITE, info.r, info.g, info.b, info.id)
            end
        elseif chatType == 'CHANNEL_NOTICE' then
            if KE:IsSecretValue(arg1) then
                return true
            else
                local globalstring = _G['CHAT_' .. arg1 .. '_NOTICE_TRIAL'] or _G['CHAT_' .. arg1 .. '_NOTICE_BN'] or
                    _G['CHAT_' .. arg1 .. '_NOTICE']
                if not globalstring then return true end

                local accessID = self:GetAccessID(chatGroup, arg8)
                local typeID = self:GetAccessID(infoType, arg8, arg12)
                frame:AddMessage(format(globalstring, arg8, ResolvePrefixedChannelName(arg4)), info.r, info.g, info.b,
                    info.id, accessID, typeID)
            end
        elseif chatType == 'BN_INLINE_TOAST_ALERT' then
            local globalstring = KE:NotSecretValue(arg1) and _G['BN_INLINE_TOAST_' .. arg1]
            if not globalstring then return true end

            local message
            local arg2Safe = KE:NotSecretValue(arg2) and arg2 or UNKNOWN
            if arg1 == 'FRIEND_REQUEST' then
                message = globalstring
            elseif arg1 == 'FRIEND_PENDING' then
                message = format(_G.BN_INLINE_TOAST_FRIEND_PENDING, BNGetNumFriendInvites())
            elseif arg1 == 'FRIEND_REMOVED' or arg1 == 'BATTLETAG_FRIEND_REMOVED' then
                message = format(globalstring, arg2Safe)
            elseif arg1 == 'FRIEND_ONLINE' or arg1 == 'FRIEND_OFFLINE' then
                local linkDisplayText = format('[%s]', arg2Safe)
                local playerLink = self:GetBNPlayerLink(arg2Safe, linkDisplayText, arg13, arg11, chatGroup, 0)
                message = format(globalstring, playerLink)
            else
                local linkDisplayText = format('[%s]', arg2Safe)
                local playerLink = self:GetBNPlayerLink(arg2Safe, linkDisplayText, arg13, arg11, chatGroup, 0)
                message = format(globalstring, playerLink)
            end

            frame:AddMessage(message, info.r, info.g, info.b, info.id)
        elseif chatType == 'BN_INLINE_TOAST_BROADCAST' then
            if KE:NotSecretValue(arg1) and arg1 ~= '' then
                if RemoveNewlines then arg1 = RemoveNewlines(RemoveExtraSpaces(arg1)) end

                local arg2Safe = KE:NotSecretValue(arg2) and arg2 or UNKNOWN
                local linkDisplayText = format('[%s]', arg2Safe)
                local playerLink = self:GetBNPlayerLink(arg2Safe, linkDisplayText, arg13, arg11, chatGroup, 0)
                frame:AddMessage(format(_G.BN_INLINE_TOAST_BROADCAST, playerLink, arg1), info.r, info.g, info.b, info.id)
            end
        elseif chatType == 'BN_INLINE_TOAST_BROADCAST_INFORM' then
            if KE:NotSecretValue(arg1) and arg1 ~= '' then
                frame:AddMessage(_G.BN_INLINE_TOAST_BROADCAST_INFORM,
                    info.r, info.g, info.b, info.id)
            end
        else
            -- Default case, regular chat messages including whispers
            -- Check if this message is censored and prepare formatter for "Show Message" click
            local eventArgs, msgFormatter
            -- Blizzard declares chatLine non-nilable, so a message without a
            -- line ID throws rather than returning false.
            local isChatLineCensored = arg11 and IsChatLineCensored and IsChatLineCensored(arg11)
            if isChatLineCensored then
                eventArgs = SafePack(arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14, arg15, arg16, arg17, arg18)

                msgFormatter = function(msg)
                    return self:MessageFormatter(frame, info, chatType, chatGroup, chatTarget, channelLength, coloredName,
                        msg, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14, arg15, arg16, arg17)
                end
            end

            local accessID = self:GetAccessID(chatGroup, chatTarget)
            local typeID = self:GetAccessID(infoType, chatTarget, arg12 or arg13)
            local body = isChatLineCensored and arg1 or self:MessageFormatter(frame, info, chatType, chatGroup, chatTarget, channelLength, coloredName,
                arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14, arg15, arg16,
                arg17)

            if body then
                frame:AddMessage(body, info.r, info.g, info.b, info.id, accessID, typeID, event, eventArgs,
                    msgFormatter, isHistory, historyTime)
            end
        end

        -- Whisper-specific handling
        if (chatType == 'WHISPER' or chatType == 'BN_WHISPER') then
            if not isProtected and not CMH.replaying then ChatEditSetLastTellTarget(arg2, chatType) end
            if FlashClientIcon and not CMH.replaying then FlashClientIcon() end
        end

        if not CMH.replaying then FlashTabIfNotShown(frame, info, chatType, chatGroup, chatTarget) end

        return true
    elseif event == 'VOICE_CHAT_CHANNEL_TRANSCRIBING_CHANGED' then
        if not frame.isTranscribing and arg2 then
            local info = _G.ChatTypeInfo.SYSTEM
            frame:AddMessage(_G.SPEECH_TO_TEXT_STARTED, info.r, info.g, info.b, info.id)
        end
        frame.isTranscribing = arg2
        return true
    end
end


-- ╔══════════════════════════════════════════════════════════╗
-- ║  ChatLinks.lua                                           ║
-- ║  Module: Chat Link Decoration                            ║
-- ║  Purpose: Prepend an icon to chat hyperlinks and render  ║
-- ║           the profession quality tier as a coloured digit║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local CL = KitnEssentials:NewModule("ChatLinks", "AceEvent-3.0")

local _G = _G
local ceil = ceil
local format = format
local gsub = _G.gsub
local ipairs = ipairs
local select = select
local strfind = _G.strfind
local strmatch = strmatch
local strsub = strsub
local tconcat = table.concat
local tonumber = tonumber

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------

function CL:UpdateDB()
    self.db = KE.db.profile.Skinning.ChatLinks
end

---------------------------------------------------------------------------------
-- Icon strings
---------------------------------------------------------------------------------

-- Inline texture escapes, cropped 5/64 on each edge to trim the icon border.
-- keepRatio crops the longer axis further instead of stretching the art.
local ICON_TEMPLATE = "|T%s:%d:%d:0:0:64:64:5:59:5:59|t"
local ICON_RATIO_TEMPLATE = "|T%s:%d:%d:0:0:64:64:%d:%d:%d:%d|t"
local ICON_DEFAULT_SIZE = 14

function CL.BuildIconString(texture, height, width, keepRatio)
    if keepRatio and height and height > 0 and width and width > 0 then
        local proportionality = height / width
        local offset = ceil((54 - 54 * proportionality) / 2)
        if proportionality > 1 then
            return format(ICON_RATIO_TEMPLATE, texture, height, width,
                5 + offset, 59 - offset, 5, 59)
        elseif proportionality < 1 then
            return format(ICON_RATIO_TEMPLATE, texture, height, width,
                5, 59, 5 + offset, 59 - offset)
        end
    end

    width = width or height
    return format(ICON_TEMPLATE, texture, height or ICON_DEFAULT_SIZE,
        width or ICON_DEFAULT_SIZE)
end

---------------------------------------------------------------------------------
-- Link decorators
---------------------------------------------------------------------------------

local TIER_COLOR = {
    ["1"] = "|cffa5493b",
    ["2"] = "|cffaaaeb2",
    ["3"] = "|cffe4c55b",
    ["4"] = "|cff09d3ff",
    ["5"] = "|cffe8ac1b",
}

local function IconFor(texture)
    local db = CL.db
    if not (texture and db) then return nil end
    return CL.BuildIconString(texture, db.IconHeight, db.IconWidth, db.KeepRatio)
end

local function AddItemInfo(link)
    local itemID, _, _, _, icon = _G.C_Item.GetItemInfoInstant(link)
    if not itemID then
        return
    end

    if CL.db.NumericalQualityTier then
        link = gsub(link, "|A:Professions%-ChatIcon%-Quality%-Tier(%d):(%d+):(%d+)::1|a",
            function(tier, width, height)
                if TIER_COLOR[tier] then
                    return TIER_COLOR[tier] .. tier .. "|r"
                end
                return format("|A:Professions-ChatIcon-Quality-Tier%s:%s:%s::1|a",
                    tier, width, height)
            end)
    end

    if CL.db.Icon then
        local iconString = IconFor(icon)
        if iconString then
            link = iconString .. " " .. link
        end
    end

    return link
end

-- The art comes from the challenge-mode map rather than the item, and the map
-- lookup's texture return is documented nilable.
local function AddKeystoneIcon(link)
    local itemID, mapID, level = strmatch(link, "Hkeystone:(%d-):(%d-):(%d-):")
    if not (itemID and mapID and level and itemID == "180653") then
        return
    end

    if CL.db.Icon then
        local mapIDNum = tonumber(mapID)
        local texture = mapIDNum and select(4, _G.C_ChallengeMode.GetMapUIInfo(mapIDNum))
        local iconString = IconFor(texture)
        if iconString then
            link = iconString .. " " .. link
        end
    end

    return link
end

local function AddSpellInfo(link)
    local id = strmatch(link, "Hspell:(%d-):")
    if not id then
        return
    end

    if CL.db.Icon then
        local spellIDNum = tonumber(id)
        local texture = spellIDNum and _G.C_Spell.GetSpellTexture(spellIDNum)
        local iconString = IconFor(texture)
        if iconString then
            link = iconString .. " " .. link
        end
    end

    return link
end

local function AddPvPTalentInfo(link)
    local id = strmatch(link, "Hpvptal:(%d-)|")
    if not id then
        return
    end

    if CL.db.Icon then
        local talentIDNum = tonumber(id)
        local texture = talentIDNum and select(3, _G.GetPvpTalentInfoByID(talentIDNum))
        local iconString = IconFor(texture)
        if iconString then
            link = iconString .. " " .. link
        end
    end

    return link
end

local function AddAchievementInfo(link)
    local id = strmatch(link, "Hachievement:(%d+)")
    if not id then
        return
    end

    if CL.db.Icon then
        local achievementIDNum = tonumber(id)
        local texture = achievementIDNum and select(10, _G.GetAchievementInfo(achievementIDNum))
        local iconString = IconFor(texture)
        if iconString then
            link = iconString .. " " .. link
        end
    end

    return link
end

local function AddCurrencyInfo(link)
    local id = strmatch(link, "Hcurrency:(%d+)")
    if not id then
        return
    end

    if CL.db.Icon then
        local info = _G.C_CurrencyInfo.GetCurrencyInfo(id)
        local iconString = info and info.iconFileID and IconFor(info.iconFileID)
        if iconString then
            link = iconString .. " " .. link
        end
    end

    return link
end

---------------------------------------------------------------------------------
-- Web addresses
---------------------------------------------------------------------------------

-- Ordered longest-first so a path-bearing address is not cut short by the
-- bare-domain rule below it. `%f[%S]` is a frontier match: it anchors to the
-- start of a word without consuming the space before it, which is also what
-- stops a later rule re-matching text an earlier one already wrapped -- inside
-- a wrapped link the address is preceded by `:` or `[`, so no frontier exists.
--
-- The tail is `[^%s|]+`, not `%S+`. A pipe cannot appear in an address, and a
-- greedy `%S+` swallows the `|r` that closes a colour escape or the `]|h` that
-- closes a hyperlink, producing a link whose text carries the terminator and
-- leaving the outer escape unclosed.
local URL_PATTERNS = {
    "%f[%S](%a[%w+.-]+://[^%s|]+)",
    "^(%a[%w+.-]+://[^%s|]+)",
    "%f[%S](www%.[-%w_%%]+%.%a%a+/[^%s|]+)",
    "^(www%.[-%w_%%]+%.%a%a+/[^%s|]+)",
    "%f[%S](www%.[-%w_%%]+%.%a%a+)",
    "^(www%.[-%w_%%]+%.%a%a+)",
}

local URL_COLOR_FALLBACK = "|cff4fb5ff"

-- Literal pre-check, so the pattern passes are skipped entirely for the
-- overwhelming majority of messages, which carry no address at all.
function CL.ContainsURL(text)
    if not text or text == "" then return false end
    return strfind(text, "://", 1, true) ~= nil
        or strfind(text, "www.", 1, true) ~= nil
end

function CL.URLColor()
    local c = CL.db and CL.db.WebAddressColor
    if not c then return URL_COLOR_FALLBACK end
    return format("|cff%02x%02x%02x", (c[1] or 0.31) * 255, (c[2] or 0.71) * 255,
        (c[3] or 1) * 255)
end

local function WrapSpan(span, substitution)
    for _, pattern in ipairs(URL_PATTERNS) do
        span = gsub(span, pattern, substitution)
    end
    return span
end

-- Locates the next complete hyperlink, using PLAIN finds only -- there is no
-- pattern that gets this right. A link is `|H<data>|h<display>|h` OR
-- `|H<data>|h` with no display at all, and the data may or may not contain a
-- colon: `|HGMChat|h[...]|h` is a real Blizzard link with display text and no
-- colon, and `|Hitem:1|h` is a real one with a colon and no display.
--
-- So the shape cannot be decided from the data. It is decided STRUCTURALLY: the
-- second `|h` closes a display span only when it comes before the next `|H`.
-- Otherwise this link had no display and the next `|h` belongs to the NEXT link.
-- Getting that wrong pairs one link's terminator with another's, which leaves a
-- real link's display text exposed as plain text and nests a link inside it.
local function NextLink(text, pos)
    local open = strfind(text, "|H", pos, true)
    while open do
        local dataEnd = strfind(text, "|h", open + 2, true)
        if not dataEnd then return nil end

        -- An unterminated `|H` is not a link. Left alone it would claim the NEXT
        -- link's terminators and swallow everything between, so resynchronise on
        -- the later marker and let the broken one fall through as plain text.
        local laterOpen = strfind(text, "|H", open + 2, true)
        if laterOpen and laterOpen < dataEnd then
            open = laterOpen
        else
            local displayEnd = strfind(text, "|h", dataEnd + 2, true)
            local following = strfind(text, "|H", dataEnd + 2, true)
            if displayEnd and (not following or displayEnd < following) then
                return open, displayEnd + 1
            end
            return open, dataEnd + 1
        end
    end
    return nil
end

function CL.WrapURLs(text, hexColor)
    if not text or text == "" then return text end
    if not CL.ContainsURL(text) then return text end

    -- gsub inserts a capture literally, so a `%` inside the matched address is
    -- not re-read as an escape. The colour prefix carries no `%` either.
    local substitution = (hexColor or URL_COLOR_FALLBACK) .. "|Hkeurl:%1|h[%1]|h|r"

    -- Complete hyperlinks are copied through byte for byte and never scanned.
    -- An address inside a link's display text would otherwise be wrapped into a
    -- NESTED link, which does not render as either link.
    local out, pos = {}, 1
    while true do
        local first, last = NextLink(text, pos)
        if not first then break end
        out[#out + 1] = WrapSpan(strsub(text, pos, first - 1), substitution)
        out[#out + 1] = strsub(text, first, last)
        pos = last + 1
    end
    out[#out + 1] = WrapSpan(strsub(text, pos), substitution)
    return tconcat(out)
end

---------------------------------------------------------------------------------
-- Filter
---------------------------------------------------------------------------------

-- Blizzard dispatches a chat filter as fn(chatFrame, event, msg, ...), so the
-- colon definition puts the frame in `self`. The body reads CL.db rather than
-- self.db for exactly that reason; changing either half breaks the other.
--
-- The keystone pattern deliberately carries no colour prefix. Live keystone
-- links open with a named-quality colour, so matching on the old literal hex
-- colour matches nothing at all. No other type's pattern depends on colour.
function CL:Filter(event, msg, ...)
    -- First contact. A pattern match on secret text throws, so this cannot move
    -- below the transforms, and a type check is no substitute: a secret string
    -- still reports type "string".
    local db = CL.db
    if db and db.Enabled and KE:NotSecretValue(msg) then
        msg = gsub(msg, "(|Hkeystone:%d+:.-|h.-|h)", AddKeystoneIcon)
        msg = gsub(msg, "(|Hitem:%d+:.-|h.-|h)", AddItemInfo)
        msg = gsub(msg, "(|Hcurrency:%d+:.-|h.-|h)", AddCurrencyInfo)
        msg = gsub(msg, "(|Hspell:%d+:%d+|h.-|h)", AddSpellInfo)
        msg = gsub(msg, "(|Hpvptal:%d+|h.-|h)", AddPvPTalentInfo)
        msg = gsub(msg, "(|Hachievement:%d+:.-|h.-|h)", AddAchievementInfo)

        if db.WebAddresses then
            msg = CL.WrapURLs(msg, CL.URLColor())
        end
    end
    return false, msg, ...
end

local FILTER_EVENTS = {
    "CHAT_MSG_ACHIEVEMENT",
    "CHAT_MSG_BATTLEGROUND",
    "CHAT_MSG_BN_WHISPER",
    "CHAT_MSG_CHANNEL",
    "CHAT_MSG_COMMUNITIES_CHANNEL",
    "CHAT_MSG_EMOTE",
    "CHAT_MSG_GUILD",
    -- The guild variant is a separate event from CHAT_MSG_ACHIEVEMENT, and the
    -- port source omits it, so guild achievement lines arrived undecorated
    -- while a hand-linked achievement worked.
    "CHAT_MSG_GUILD_ACHIEVEMENT",
    "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_LOOT",
    "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_SAY",
    "CHAT_MSG_TRADESKILLS",
    "CHAT_MSG_WHISPER",
    "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_YELL",
}

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------

function CL:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function CL:OnEnable()
    -- ElvUI users get link decoration from that side, so this stands down
    -- rather than doubling every icon.
    if KE:ShouldNotLoadModule() then return end
    if not self.db then self:UpdateDB() end
    if not self.db.Enabled then return end
    if self.filtersRegistered then return end

    -- Resolved at call time rather than cached at file scope, so the fallback
    -- stays reachable on a client that has only the older global.
    local add = (_G.ChatFrameUtil and _G.ChatFrameUtil.AddMessageEventFilter)
        or _G.ChatFrame_AddMessageEventFilter
    if not add then return end

    for _, event in ipairs(FILTER_EVENTS) do
        add(event, self.Filter)
    end
    self.filtersRegistered = true
end

function CL:OnDisable()
end

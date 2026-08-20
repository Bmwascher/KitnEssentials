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
local strmatch = strmatch
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

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

-- The chat skin owns the panel this module's popup anchors to. Silent form: the
-- popup falls back to a chat frame, then to screen centre, if the skin is off.
local CHAT = KitnEssentials:GetModule("Chat", true)

local _G = _G
local ceil = ceil
local C_Timer = C_Timer
local CreateFrame = CreateFrame
local format = format
local gsub = _G.gsub
local GetCursorPosition = GetCursorPosition
local ipairs = ipairs
local IsControlKeyDown = IsControlKeyDown
local select = select
local strfind = _G.strfind
local strmatch = strmatch
local strsub = strsub
local tconcat = table.concat
local tonumber = tonumber
local UIParent = UIParent
local Theme = KE.Theme

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
-- Address copy popup
---------------------------------------------------------------------------------

local urlPopup, urlBackdrop

-- The popup parks one pixel above the chat window rather than at the cursor: a
-- fixed home is easier to find, and it never covers the line you were reading.
-- It takes the chat window's width, so MIN_WIDTH only applies to the fallback
-- position when no chat window can be resolved.
-- HEIGHT is a floor, not a fixed size: the address box wraps, and the popup
-- grows to show the whole address rather than scrolling it out of sight.
local POPUP_MIN_HEIGHT = 64
local POPUP_MIN_WIDTH = 340
local POPUP_PADDING = 14
local POPUP_GAP = 1
local POPUP_HINT_TOP = 10
local POPUP_HINT_GAP = 8
local POPUP_FIELD_PAD = 6

-- More opaque than the copy window's backdrop. That one floats over the world;
-- this one sits directly on chat text, which has to stay out of the address.
local POPUP_BG = { 0.0627, 0.0627, 0.0627, 0.95 }

function CL:HideURLPopup()
    if urlPopup then urlPopup:Hide() end
    if urlBackdrop then urlBackdrop:Hide() end
end

local function BuildURLPopup()
    -- A full-screen click catcher behind the popup, so a click that reaches it
    -- dismisses the popup and no close button is needed. A frame at a higher
    -- strata sits above it and takes the click instead.
    urlBackdrop = CreateFrame("Button", "KE_ChatURLBackdrop", UIParent)
    urlBackdrop:SetFrameStrata("DIALOG")
    urlBackdrop:SetFrameLevel(499)
    urlBackdrop:SetAllPoints(UIParent)
    urlBackdrop:RegisterForClicks("AnyUp")
    urlBackdrop:SetScript("OnClick", function() CL:HideURLPopup() end)
    urlBackdrop:Hide()

    urlPopup = CreateFrame("Frame", "KE_ChatURLPopup", UIParent, "BackdropTemplate")
    urlPopup:SetFrameStrata("DIALOG")
    urlPopup:SetFrameLevel(500)
    urlPopup:SetSize(POPUP_MIN_WIDTH, POPUP_MIN_HEIGHT)
    urlPopup:EnableMouse(true)
    urlPopup:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    urlPopup:SetBackdropColor(POPUP_BG[1], POPUP_BG[2], POPUP_BG[3], POPUP_BG[4])
    -- The border colour is set per show, not here: the theme accent it takes can
    -- change without a reload.

    local hint = urlPopup:CreateFontString(nil, "OVERLAY")
    KE:ApplyFontToText(hint, nil, 10, "NONE")
    hint:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 0.8)
    hint:SetPoint("TOP", urlPopup, "TOP", 0, -POPUP_HINT_TOP)
    hint:SetText("Ctrl+C to copy, Escape to close")
    urlPopup.hint = hint

    -- The address sits in its own inset field. Without it the address and the
    -- hint above it read as one block of text on a flat panel.
    local field = CreateFrame("Frame", nil, urlPopup, "BackdropTemplate")
    field:SetPoint("TOP", hint, "BOTTOM", 0, -POPUP_HINT_GAP)
    field:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    field:SetBackdropColor(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], 1)
    field:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
    urlPopup.field = field

    -- EnableKeyboard is PROTECTED. Focus plus key scripts is how the copy
    -- window takes Ctrl+C, and this follows it.
    local box = CreateFrame("EditBox", nil, field)
    box:SetSize(POPUP_MIN_WIDTH - POPUP_PADDING * 2 - POPUP_FIELD_PAD * 2, 20)
    box:SetPoint("TOPLEFT", field, "TOPLEFT", POPUP_FIELD_PAD, -POPUP_FIELD_PAD)
    KE:ApplyFontToText(box, nil, 13, "NONE")
    box:SetAutoFocus(false)
    box:SetMultiLine(true)
    box:SetJustifyH("CENTER")
    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        CL:HideURLPopup()
    end)
    box:SetScript("OnKeyDown", function(_, key)
        if key == "C" and IsControlKeyDown() then
            C_Timer.After(0.05, function() CL:HideURLPopup() end)
        end
    end)
    box:SetScript("OnMouseUp", function(self) self:HighlightText() end)

    urlPopup:SetScript("OnMouseDown", function()
        urlPopup.box:SetFocus()
        urlPopup.box:HighlightText()
    end)
    urlPopup.box = box

    -- An EditBox will not report how tall its wrapped text is, so an invisible
    -- FontString carrying the same font measures it instead.
    local ruler = urlPopup:CreateFontString(nil, "OVERLAY")
    KE:ApplyFontToText(ruler, nil, 13, "NONE")
    ruler:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
    -- An address has no spaces, so without this the ruler reports one line for
    -- text the box will have broken across several.
    ruler:SetNonSpaceWrap(true)
    ruler:SetWordWrap(true)
    ruler:Hide()
    urlPopup.ruler = ruler
end

-- The skinned panel is preferred over the message frame it holds. The panel
-- carries the visible window and draws its border; the ScrollingMessageFrame is
-- inset within it, so anchoring to that one puts the popup INSIDE the border and
-- short of the window's real width.
--
-- Ownership is asked, never inferred. The chat skin reparents exactly one frame
-- into the panel and records it, and the dock rides along when that frame is
-- docked. Geometry cannot stand in for that: a window the user has dragged so it
-- happens to sit inside the panel's rectangle is still its own window, and the
-- popup belongs to it.
local function PanelFor(chatFrame)
    local panel = CHAT and CHAT.panel
    if not panel or not panel:IsShown() then return chatFrame end

    local owner = CHAT.ChatWindow
    if not owner then return chatFrame end
    if chatFrame == owner then return panel end
    if chatFrame.isDocked and owner.isDocked then return panel end
    return chatFrame
end

-- Blizzard names the originating chat frame: ChatFrameMixin:OnHyperlinkClick
-- passes itself to SetItemRef, which puts it in contextData.frame, and LinkUtil
-- hands contextData to the registered handler. That is authoritative, so it wins
-- over anything inferred.
local function ChatAnchorUnderCursor()
    local cx, cy = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    if not cx or not cy or not scale or scale <= 0 then return nil end
    cx, cy = cx / scale, cy / scale

    local function Contains(frame)
        if not frame or not frame:IsShown() then return false end
        local left, right = frame:GetLeft(), frame:GetRight()
        local top, bottom = frame:GetTop(), frame:GetBottom()
        return left and right and top and bottom
            and cx >= left and cx <= right and cy >= bottom and cy <= top
    end

    -- Frames before the panel: the most specific thing under the cursor wins,
    -- and PanelFor decides whether it maps up.
    for _, frameName in ipairs(_G.CHAT_FRAMES) do
        local chat = _G[frameName]
        if Contains(chat) then return PanelFor(chat) end
    end

    local panel = CHAT and CHAT.panel
    if Contains(panel) then return panel end

    return panel or _G.DEFAULT_CHAT_FRAME
end

-- The cursor route is the fallback for a dispatch that carries no frame, and it
-- is only a heuristic: a listener on ChatFrame.OnHyperlinkClick that moves or
-- hides the frame before this runs would send it to the wrong window.
local function AnchorFor(sourceFrame)
    if sourceFrame and sourceFrame.GetLeft then return PanelFor(sourceFrame) end
    return ChatAnchorUnderCursor()
end

-- The addon theme's accent, read live so a preset or class-colour change reaches
-- the popup without a reload. The chat panel's own border is usually near-black,
-- which leaves the popup indistinguishable from the window it sits on.
local function PopupBorderColor()
    local accent = Theme.accent
    if accent and accent[1] then return accent[1], accent[2], accent[3], accent[4] or 1 end
    return Theme.border[1], Theme.border[2], Theme.border[3], 1
end

function CL:ShowURLPopup(url, sourceFrame)
    -- First contact, and NOT redundant. The filter never wraps a secret body, so
    -- no keurl link should carry one -- but this is fed by Blizzard's dispatch,
    -- not by us, and a shipping addon's click handler was amended to refuse a
    -- secret link at exactly this boundary. IsSafeValue covers nil and secrecy
    -- in one call; the nil comparison it makes first is a different-type
    -- compare, which is not the same-type case that throws.
    if not KE:IsSafeValue(url) then return end
    if not urlPopup then BuildURLPopup() end

    urlPopup.box:SetText(url)
    urlPopup:SetBackdropBorderColor(PopupBorderColor())
    urlPopup:ClearAllPoints()

    local anchor = AnchorFor(sourceFrame)
    local width = anchor and anchor:GetWidth()
    if anchor and width and width > 0 then
        urlPopup:SetWidth(width)
        urlPopup:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, POPUP_GAP)
    else
        urlPopup:SetWidth(POPUP_MIN_WIDTH)
        urlPopup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    -- Width first, then measure the wrapped address at that width, then grow to
    -- fit it. A wider chat window shows more of the address per line and needs
    -- fewer of them.
    local fieldWidth = urlPopup:GetWidth() - POPUP_PADDING * 2
    local boxWidth = fieldWidth - POPUP_FIELD_PAD * 2
    urlPopup.box:SetWidth(boxWidth)
    urlPopup.ruler:SetWidth(boxWidth)
    urlPopup.ruler:SetText(url)

    local textHeight = urlPopup.ruler:GetStringHeight() or 0
    local boxHeight = textHeight > 0 and textHeight + 4 or 20
    urlPopup.box:SetHeight(boxHeight)
    urlPopup.field:SetSize(fieldWidth, boxHeight + POPUP_FIELD_PAD * 2)

    local hintHeight = urlPopup.hint:GetStringHeight() or 12
    local needed = POPUP_HINT_TOP + hintHeight + POPUP_HINT_GAP
        + urlPopup.field:GetHeight() + POPUP_PADDING
    urlPopup:SetHeight(needed > POPUP_MIN_HEIGHT and needed or POPUP_MIN_HEIGHT)

    urlBackdrop:Show()
    urlPopup:Show()
    urlPopup.box:SetFocus()
    urlPopup.box:HighlightText()
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

    -- Registered once and never removed: LinkUtil has no unregister call, and
    -- it asserts on a duplicate registration. A handler with nothing to handle
    -- costs nothing.
    local linkUtil = _G.LinkUtil
    if linkUtil and linkUtil.RegisterLinkHandler and linkUtil.IsLinkHandlerRegistered
        and not linkUtil.IsLinkHandlerRegistered("keurl") then
        linkUtil.RegisterLinkHandler("keurl", function(_, _, linkData, contextData)
            CL:ShowURLPopup(linkData and linkData.options, contextData and contextData.frame)
        end)
    end

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

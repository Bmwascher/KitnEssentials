-- KitnEssentials — Tooltips
--
-- the brief: high performance, more customization, and enough coverage
-- to replace a standalone tooltip-skinning addon.
--
-- Architecture:
--   * Visual-only changes -- alpha/backdrop/font. No Hide/Show/SetParent on
--     Blizzard frames, all post-hooks. Class recolor works on
--     GameTooltipTextLeft1 directly instead of rebuilding the unit block.
--   * TooltipDataProcessor.AddTooltipPostCall for unit/spell/item data,
--     GameTooltip_SetDefaultAnchor hook for anchoring,
--     NineSlice:SetAlpha(0) + own backdrop for the style, global font
--     objects for text, statusbar height/texture/text.
-- Zero idle cost: every code path is a tooltip event or hook; no
-- OnUpdate, no timers.
---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local TT = KitnEssentials:NewModule("SkinTooltips", "AceEvent-3.0", "AceHook-3.0")

-- Hoisted locals ------------------------------------------------------
local _G = _G
local pairs = pairs
local format = string.format
local strlower = string.lower
local unpack = unpack
local CreateFrame = CreateFrame
local UnitExists = UnitExists
local UnitIsPlayer = UnitIsPlayer
local UnitClass = UnitClass
local UnitName = UnitName
local UnitGUID = UnitGUID
local UnitReaction = UnitReaction
local UnitLevel = UnitLevel
local UnitEffectiveLevel = UnitEffectiveLevel
local UnitRace = UnitRace
local UnitPVPName = UnitPVPName
local UnitRealmRelationship = UnitRealmRelationship
local UnitIsAFK = UnitIsAFK
local UnitIsDND = UnitIsDND
local GetCreatureDifficultyColor = GetCreatureDifficultyColor
local GetGuildInfo = GetGuildInfo
local InCombatLockdown = InCombatLockdown
local IsModifierKeyDown = IsModifierKeyDown
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local FACTION_BAR_COLORS = FACTION_BAR_COLORS
local hooksecurefunc = hooksecurefunc
local UnitTokenFromGUID = UnitTokenFromGUID
local GetMouseFoci = GetMouseFoci
local GetPlayerInfoByGUID = GetPlayerInfoByGUID
local CreateColor = CreateColor
local type = type
local S = KE.Skins

-- Fallback for a unit whose colour cannot be resolved, so a display sink
-- always has something with :GetRGB().
local WHITE_COLOR = CreateColor(1, 1, 1)

-- KE:GetEffectiveFont returns the LSM NAME, not a file path -- passing the raw
-- name straight to SetFont throws "Invalid font asset". KE:GetFontPath does the
-- resolution and carries its own fallback, and it is also what turns an unset
-- face into the global font; fetching here directly would silently skip that.
local function ResolveFont(db)
    return KE:GetFontPath(KE:GetEffectiveFont(db))
end

-- The tooltips that get the visual style. Existence-guarded at wire
-- time; embedded tooltips are excluded like ElvUI's SetStyle does.
local STYLE_LIST = {
    "GameTooltip",
    "ItemRefTooltip",
    "ItemRefShoppingTooltip1",
    "ItemRefShoppingTooltip2",
    "ShoppingTooltip1",
    "ShoppingTooltip2",
    "QuickKeybindTooltip",
    "SettingsTooltip",
    "GameSmallHeaderTooltip",
}

function TT:UpdateDB()
    self.db = KE.db and KE.db.profile and KE.db.profile.Skinning
        and KE.db.profile.Skinning.Tooltips
end

-- Style ---------------------------------------------------------------

-- The overlay technique --
-- plain textures on the tooltip, no BackdropTemplate. The old
-- BackdropTemplate child ran SetupTextureCoordinates (width/edgeSize
-- arithmetic) on every tooltip resize, and Midnight world-quest
-- tooltips resize with SECRET widths: 196x "arithmetic on secret
-- width, tainted by an addon" (field BugSack). Textures
-- anchored to the frame resize in C -- zero Lua size math, nothing to
-- go secret.
--
-- The styler handle lives in S.data, never on the tooltip itself. Doctrine
-- (SkinAPI.lua): a field we write onto a Blizzard frame plants a tainted
-- key in a secure table, which contaminates the iteration and field-fallback
-- reads Blizzard's own code performs -- the combat
-- ADDON_ACTION_BLOCKED. S.data is a weak-keyed side table, so nothing of ours
-- ever lands on the frame.
local function EnsureStyler(tt)
    local d = S.data(tt)
    local s = d.tooltipStyle
    if s then return s end
    s = { regions = {} }

    local bg = tt:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetPoint("TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", -1, 1)
    s.bg = bg
    s.regions[#s.regions + 1] = bg

    local function Edge()
        local t = tt:CreateTexture(nil, "BACKGROUND", nil, -7)
        s.regions[#s.regions + 1] = t
        return t
    end
    local top = Edge()
    top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(1)
    local bottom = Edge()
    bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT"); bottom:SetHeight(1)
    local left = Edge()
    left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT"); left:SetWidth(1)
    local right = Edge()
    right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT"); right:SetWidth(1)
    s.edges = { top, bottom, left, right }

    function s.SetColors(bgC, bdC)
        bg:SetColorTexture(bgC[1], bgC[2], bgC[3], bgC[4] or 0.9)
        for _, e in ipairs(s.edges) do
            e:SetColorTexture(bdC[1], bdC[2], bdC[3], bdC[4] or 1)
        end
    end
    function s.Show()
        for _, r in ipairs(s.regions) do r:Show() end
    end
    function s.Hide()
        for _, r in ipairs(s.regions) do r:Hide() end
    end

    d.tooltipStyle = s
    return s
end

-- this runs from GameTooltip's OnShow, so it executes on EVERY
-- tooltip -- including map POI hovers, where Blizzard follows the show
-- with GameTooltip_AddWidgetSet. Any insecure work here taints that
-- execution, and the widget layout then dies on a secret number:
--
--   Blizzard_UIWidgetTemplateTextWithState.lua: attempt to perform
--   arithmetic on local 'textHeight' (a secret number value, while
--   execution tainted by an addon)
--
-- The styling is idempotent -- the same textures with the same colours
-- every time -- so after the first show there is nothing to do. Bailing
-- out before touching anything means the OnShow hook is inert on all
-- subsequent shows, and the tainted window shrinks to the very first
-- tooltip of the session instead of every one.
local function ColorsMatch(a, b)
    if not a or not b then return false end
    for i = 1, 4 do
        if (a[i] or 0) ~= (b[i] or 0) then return false end
    end
    return true
end

function TT:StyleTooltip(tt)
    if not self.db or not tt or tt:IsForbidden() then return end

    local s = S.data(tt).tooltipStyle
    if s and s.shown and ColorsMatch(s.bgApplied, self.db.BackdropColor)
        and ColorsMatch(s.bdApplied, self.db.BorderColor) then
        return
    end

    -- ElvUI: secrets crash the comparison/money paths; a secret width is
    -- the tell that this tooltip is in that state -- leave it native.
    if KE:IsSecretValue(tt:GetWidth()) then return end

    if tt.NineSlice then tt.NineSlice:SetAlpha(0) end
    s = EnsureStyler(tt)
    s.SetColors(self.db.BackdropColor, self.db.BorderColor)
    s.bgApplied = { unpack(self.db.BackdropColor) }
    s.bdApplied = { unpack(self.db.BorderColor) }
    s.Show()
    s.shown = true
end

local function UnstyleTooltip(tt)
    if tt.NineSlice then tt.NineSlice:SetAlpha(1) end
    local s = S.data(tt).tooltipStyle
    if s then
        s.Hide()
        -- Clear the fast-path flag so the next StyleTooltip re-shows.
        s.shown = nil
    end
end

-- Fonts ---------------------------------------------------------------

-- The shared font objects cover every tooltip line at zero per-line cost.
-- 12.0.7 shadow doctrine: shadows untouched.
--
-- This module is the SOLE owner of all six tooltip font objects. The Blizzard
-- base-size pass and the global-font pass each used to scale three of them, so
-- whichever ran last won and this module's own sizes were silently overwritten.
-- Both lists dropped them; do not add them back. With this module disabled the
-- six stay stock, which is the point of single ownership.
function TT:ApplyFonts()
    local db = self.db
    if not db then return end
    local path = ResolveFont(db)
    local outline = db.FontOutline or "OUTLINE"
    if outline == "NONE" then outline = "" end
    if _G.GameTooltipHeaderText then
        _G.GameTooltipHeaderText:SetFont(path, db.HeaderFontSize or 14, outline)
    end
    if _G.GameTooltipText then
        _G.GameTooltipText:SetFont(path, db.FontSize or 12, outline)
    end
    if _G.GameTooltipTextSmall then
        _G.GameTooltipTextSmall:SetFont(path, db.SmallFontSize or 11, outline)
    end
    -- Paired with the three above by role, not by stock size: header, body,
    -- small. Tooltip templates draw from these rather than the *Text objects.
    if _G.GameTooltipHeader then
        _G.GameTooltipHeader:SetFont(path, db.HeaderFontSize or 14, outline)
    end
    if _G.Tooltip_Med then
        _G.Tooltip_Med:SetFont(path, db.FontSize or 12, outline)
    end
    if _G.Tooltip_Small then
        _G.Tooltip_Small:SetFont(path, db.SmallFontSize or 11, outline)
    end
end

-- Health bar ----------------------------------------------------------

function TT:StyleHealthBar()
    local bar = _G.GameTooltipStatusBar
    if not bar or not self.db then return end
    local db = self.db
    -- fully remove the bar. Blizzard re-shows it per
    -- unit tooltip, so the OnShow hook in OnEnable keeps it hidden.
    if db.HealthBarHidden then
        bar:Hide()
        return
    end
    bar:SetHeight(db.HealthBarHeight or 7)
    local tex = KE.LSM and KE.LSM:Fetch("statusbar", db.HealthBarTexture or "Blizzard", true)
    if tex then bar:SetStatusBarTexture(tex) end
end

-- No current/max readout on this bar, and there cannot be one.
--
-- 12.0 rebuilt it: GameTooltipUnitHealthBarMixin:OnLoad fixes the range at
-- 0..1 and drives the value from UnitPercentHealthFromGUID
-- (Blizzard_GameTooltip/Mainline/GameTooltip.lua), so the bar
-- carries a FRACTION, not health. That function is declared
-- SecretReturns = true with no condition attached
-- (UnitDocumentation.lua), and UnitHealth is unconditionally
-- secret too, so the real numbers are unreachable from here.
--
-- A percentage is out as well: SetText and SetFormattedText do accept
-- secret arguments, but scaling 0.57 to 57 is arithmetic on a secret and
-- throws, and there is no C-side scaler.
--
-- The readout shipped for a while regardless: blank on every unit, behind a
-- toggle that could never do anything. Probed while hovering a unit,
-- GetMinMaxValues returned 0, 1 and issecretvalue(GetValue()) was true. Toggle,
-- size slider and handler are all removed. HealthBarText and HealthTextSize survive in
-- Core/Defaults.lua only so no profile needs migrating.

-- Unit extras ---------------------------------------------------------

local function ReactionColor(unit)
    local reaction = UnitReaction(unit, "player")
    local c = reaction and FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- 12.1 made the class token SECRET for a restricted unit, and
-- RAID_CLASS_COLORS[class] with a secret key throws -- a table lookup keyed by
-- a secret is the same banned comparison as `==`. C_ClassColor.GetClassColor
-- accepts a secret token and hands back a colour whose components may
-- themselves be secret, which is fine: every consumer feeds them to a sink.
local function ClassColorFor(class)
    if type(class) == "nil" then return nil end
    local get = C_ClassColor and C_ClassColor.GetClassColor
    if get then
        local ok, c = pcall(get, class)
        if ok and c then return c end
    end
    if KE:IsSafeValue(class) then return RAID_CLASS_COLORS[class] end
    return nil
end

-- GetPlayerInfoByGUID on a CREATURE guid does not fail cleanly -- it answers
-- with the first class, so every hostile NPC comes back WARRIOR and wears that
-- tan class colour instead of red. Only a Player- GUID may be asked for a
-- class. IsSafeValue runs the secrecy check before the string work, so the
-- guard holds whether or not the field arrives secret.
local function IsPlayerGUID(guid)
    if not KE:IsSafeValue(guid) then return false end
    return type(guid) == "string" and guid:sub(1, 7) == "Player-"
end

-- Returns a colour OBJECT, never bare components. A caller handed components
-- would have to work out, per call site, whether this particular value is safe
-- to test; the object is always a plain table, so the test never touches a
-- component and they reach nothing but sinks. Nothing returned means "leave
-- Blizzard's own colour alone", which is what puts hostile names back to red.
local function UnitColor(unit, guid)
    -- Preferred: GetPlayerInfoByGUID is AllowedWhenTainted, so it resolves a
    -- class even over a raid frame, where the token is secret but the GUID is
    -- not.
    if IsPlayerGUID(guid) and GetPlayerInfoByGUID then
        local _, class = GetPlayerInfoByGUID(guid)
        local c = ClassColorFor(class)
        if c then return c end
    end
    if not unit then return end

    -- Midnight secret units. UnitName returning a secret is the tell (ElvUI's
    -- IsSecretUnit); on that branch UnitIsPlayer and UnitReaction give secret
    -- booleans and branching on them is the crash class.
    --
    -- Class-colour ONLY when the GUID says this is a player. Without that this
    -- branch class-coloured every secret-named NPC too -- the same wrong-
    -- Warrior bug by a second route.
    if KE:IsSecretValue(UnitName(unit)) then
        if not IsPlayerGUID(guid) then return end
        local _, class = UnitClass(unit)
        return ClassColorFor(class) or WHITE_COLOR
    end
    if UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        local c = ClassColorFor(class)
        if c then return c end
    end
    local r, g, b = ReactionColor(unit)
    if r then return CreateColor(r, g, b) end
end

-- EllesmereUI's Blizzard skin adds both of these to GameTooltip already, and
-- its Mythic+ line is ON by default (tooltipMythicScore ~= false). It dedupes
-- against a line containing "M+ Score", which will not match our label -- so
-- without a check of our own, anyone running the package who enables these
-- gets the score twice and the rank in two different styles. Scanning the
-- rendered lines catches it regardless of which addon drew first, and works
-- for any other addon doing the same thing.
local function TipHasText(tt, needle)
    if not needle or needle == "" then return false end

    local name = tt.GetName and tt:GetName()
    local lines = tt.NumLines and tt:NumLines() or 0
    if not name then return false end

    for i = 1, lines do
        local fs = _G[name .. "TextLeft" .. i]
        local text = fs and fs:GetText()
        if text and not KE:IsSecretValue(text) and text:find(needle, 1, true) then
            return true
        end
        fs = _G[name .. "TextRight" .. i]
        text = fs and fs:GetText()
        if text and not KE:IsSecretValue(text) and text:find(needle, 1, true) then
            return true
        end
    end
    return false
end

-- Locating the level row.
--
-- Blizzard publishes no line type for it: TooltipDataLineType has UnitName,
-- UnitThreat and UnitOwner but nothing for level
-- (TooltipInfoSharedDocumentation.lua, 12.0.7). So the row is found
-- by matching the localized level template against each
-- line's text. The templates are GlobalStrings and are reduced to plain
-- substrings once, on first use rather than at file scope, so load order
-- cannot matter.
local levelMatchA, levelMatchB
local function LevelMatchers()
    if levelMatchA == nil then
        local plain = _G.TOOLTIP_UNIT_LEVEL
        local raced = _G.TOOLTIP_UNIT_LEVEL_RACE or _G.TOOLTIP_UNIT_LEVEL_CLASS
        levelMatchA = plain and strlower(plain:gsub("%s?%%s%s?%-?", "")) or false
        -- The second chain strips the reordered "%2$s ... %1$s" form some
        -- locales use, then the leading Russian ordinal, then the remaining
        -- specifiers. Transcribed from ElvUI rather than re-derived --
        -- getting it wrong only shows up in one locale.
        levelMatchB = raced
            and strlower(raced:gsub("^%%2$s%s?(.-)%s?%%1$s", "%1")
                              :gsub("^%-?г?о?%s?", "")
                              :gsub("%s?%%s%s?%-?", ""))
            or false
    end
    return levelMatchA, levelMatchB
end

-- Returns the level row and the row directly after it (the spec/class row),
-- both as FontStrings, or nil when the tooltip has no level row.
--
-- `offset` is the last row to SKIP, not the first to read: a guild row pushes
-- the level down one, and starting the scan too early matches the guild name
-- in locales where it can contain the level word.
local function FindLevelLine(tt, offset)
    local ok, info = pcall(tt.GetTooltipData, tt)
    if not ok or not info or not info.lines then return nil end

    local matchA, matchB = LevelMatchers()
    if not matchA and not matchB then return nil end

    for i = offset + 1, #info.lines do
        local line = info.lines[i]
        local text = line and line.leftText
        if text and not KE:IsSecretValue(text) then
            if text == "" then return nil end
            local lower = strlower(text)
            if (matchA and lower:find(matchA, 1, true))
                or (matchB and lower:find(matchB, 1, true)) then
                return _G["GameTooltipTextLeft" .. i],
                       _G["GameTooltipTextLeft" .. (i + 1)]
            end
        end
    end
end

-- Reading a unit's name is only safe when its identity is not restricted.
-- UnitName and UnitPVPName are both SecretWhenUnitIdentityRestricted, and
-- C_Secrets.ShouldUnitIdentityBeSecret is the predicate that matches them
-- (SecretPredicateAPIDocumentation.lua, 12.0.7 -- it returns a
-- plain bool, so testing it directly is safe).
--
-- This is a STRICTER test than KE:IsSecretValue(unit), which only asks
-- whether the token is a secret value. The two are NOT interchangeable, and
-- only this one licenses concatenating a name.
--
-- Deliberately NOT copied from oUF, whose NotSecretUnit calls the BARE global
-- `ShouldUnitIdentityBeSecret` (ElvUI_Libraries/.../oUF/init.lua). That
-- global does not exist: the system declares Namespace = "C_Secrets", so it
-- only ever exports under C_Secrets. oUF's `ShouldUnitIdentityBeSecret and`
-- short-circuit therefore always yields nil, making NotSecretUnit constantly
-- true and ElvUI's name rebuild effectively unguarded. Caught by KE's
-- luacheckrc drift check. Fail CLOSED here: no predicate, no
-- rebuild.
local function CanReadIdentity(unit)
    local fn = C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret
    if not fn then return false end

    local ok, restricted = pcall(fn, unit)
    return ok and not restricted
end

-- The " [AFK]" / " [DND]" suffix.
--
-- These two strings are OURS, not Blizzard's. There is no AFK_LABEL or
-- DND_LABEL global -- ElvUI builds its own file-locals at Tooltip.lua
-- and this reads as though they were globals until you look. Colours and
-- bracket form are copied from there; the words are literals, per the port
-- convention against locale tables.
local AFK_LABEL = " |cffFFFFFF[|r|cffFF9900AFK|r|cffFFFFFF]|r"
local DND_LABEL = " |cffFFFFFF[|r|cffFF3333DND|r|cffFFFFFF]|r"

-- UnitIsAFK and UnitIsDND are SecretInChatMessagingLockdown -- a DIFFERENT
-- condition from identity restriction, so CanReadIdentity does not cover
-- them and they need their own check. The secret test has to come first: a
-- truth test on a secret boolean throws. Same shape as ElvUI's E:UnitIsAFK
-- wrapper (ElvUI/Game/Shared/General/API.lua).
local function AwayLabel(unit)
    local afk = UnitIsAFK(unit)
    if not KE:IsSecretValue(afk) and afk then return AFK_LABEL end

    local dnd = UnitIsDND(unit)
    if not KE:IsSecretValue(dnd) and dnd then return DND_LABEL end

    return ""
end

-- Embedded tooltips (UIWidgetBaseItemEmbeddedTooltip*, the reward previews
-- inside UI widgets) must not be written to. Blizzard sizes the host widget
-- from them -- Blizzard_UIWidgetTemplateBase.lua does
--
--   widgetHeight = math.max(iconSize, self.Tooltip:GetHeight())
--
-- and an AddLine from us makes that height a secret number, so the arithmetic
-- fails with "execution tainted by an addon". StyleTooltip
-- already excluded them; the TooltipDataProcessor post-calls did not, so an
-- item ID line landed in widget reward tooltips on the world map.
local function IsEmbeddedTip(tt)
    if not tt then return true end
    if tt.IsEmbedded then return true end

    if tt.IsForbidden and tt:IsForbidden() then return true end

    -- GetName on a widget-owned tooltip throws "forbidden object" when the
    -- post-call runs from tainted code. A name we cannot read is a tooltip we
    -- cannot prove is safe to write to, so treat the failure as embedded.
    local ok, name = pcall(tt.GetName, tt)
    if not ok then return true end

    -- Matches both UIWidgetBaseItemEmbeddedTooltip* and EmbeddedItemTooltip.
    return name and name:find("Embedded", 1, true) and true or false
end

-- Resolving a USABLE unit token.
--
-- tt:GetUnit() alone is not enough. Over a secure group frame the token comes
-- back SECRET, and the single-source read below then bailed on the whole
-- handler -- class colour, guild colour, guild rank, level row, M+ score and
-- the target line were all skipped, on raid frames and on plenty of ordinary
-- hovers besides. The tooltip's own data pass still carries a CLEAN guid in
-- exactly that case, and UnitTokenFromGUID turns it back into a real,
-- non-secret token: the step that was missing.
--
-- Three sources, in order:
--   1. data.guid (or the tooltip's primary data) through UnitTokenFromGUID.
--   2. "mouseover", when the derived token is secret or has gone away.
--   3. the moused-over frame's own `unit` attribute, for frames that never
--      went through the tooltip data path at all.
--
-- A secret token never reaches UnitExists or any Unit* API: every candidate
-- passes KE:IsSafeValue first. This widens WHICH token is used; it adds no
-- new read of unit identity -- the existing CanReadIdentity gate on the name
-- rebuild still decides that.
local function ResolveUnit(tt, data)
    local mouseover = UnitExists("mouseover") and "mouseover" or nil

    local unit
    if UnitTokenFromGUID then
        local guid = data and data.guid
        if not guid and tt.GetPrimaryTooltipData then
            local okData, d = pcall(tt.GetPrimaryTooltipData, tt)
            guid = okData and d and d.guid or nil
        end
        if KE:IsSafeValue(guid) then
            local okToken, token = pcall(UnitTokenFromGUID, guid)
            unit = okToken and token or nil
        end
    end

    if not unit then
        local okUnit, _, u = pcall(tt.GetUnit, tt)
        if okUnit then unit = u end
    end

    if unit then
        if KE:IsSafeValue(unit) and UnitExists(unit) then return unit end
        return mouseover
    end

    local foci = GetMouseFoci and GetMouseFoci()
    local focus = foci and foci[1]
    local focusUnit = focus and focus.GetAttribute and focus:GetAttribute("unit")
    if KE:IsSafeValue(focusUnit) and UnitExists(focusUnit) then
        return focusUnit
    end
    return mouseover
end

function TT:OnTooltipSetUnit(tt, data)
    if IsEmbeddedTip(tt) then return end
    local db = self.db
    if not db or tt ~= _G.GameTooltip or tt:IsForbidden() then return end

    if db.HideInCombat and InCombatLockdown() and not IsModifierKeyDown() then
        tt:Hide()
        return
    end

    local unit = ResolveUnit(tt, data)
    if not unit then return end

    -- Class/reaction color: recolor the existing name line (no text rebuild,
    -- so secret name strings never touch our code) and the health bar.
    local unitColor = UnitColor(unit, data and data.guid)
    if db.ClassColorNames and unitColor then
        local line1 = _G.GameTooltipTextLeft1
        if line1 then line1:SetTextColor(unitColor:GetRGB()) end
        local bar = _G.GameTooltipStatusBar
        if bar then bar:SetStatusBarColor(unitColor:GetRGB()) end
    end

    -- Name row rebuild: player title, realm suffix and the Away/Busy label,
    -- none of which Blizzard's own row carries. Ports ElvUI SetUnitText
    -- (Tooltip.lua) minus its ElvUI-version lookup and its gender
    -- prefix.
    --
    -- Colour is deliberately NOT set here. SetText does not clear a
    -- SetTextColor, so the ClassColorNames block above stays the single
    -- owner of the colour instead of two paths fighting over it.
    --
    -- CanReadIdentity is the only guard: it is the
    -- documented predicate for exactly these returns, so re-checking each
    -- value with KE:IsSecretValue would be the over-guarding that has
    -- silently killed features in this project before.
    if UnitIsPlayer(unit) and CanReadIdentity(unit) then
        local name, realm = UnitName(unit)
        if name then
            local pvpName = UnitPVPName(unit)
            if pvpName and pvpName ~= "" then name = pvpName end

            -- AlwaysShowRealm spells the realm out in full; otherwise
            -- Blizzard's own compact marker says "different realm" without
            -- the width.
            --
            -- Deliberately a SETTING and not a Shift modifier.
            -- MODIFIER_STATE_CHANGED below refuses to
            -- refresh unit tooltips on purpose (see the note there: the
            -- refresh re-runs Blizzard's line builders on our tainted
            -- execution and throws on a secret unit), so a modifier would be
            -- read once on hover and never again -- a dead control.
            --
            -- Shaped after Blizzard's GetUnitName
            -- (Blizzard_UnitFrame/Mainline/UnitFrame.lua): a
            -- virtual realm is one you are effectively already on, so it
            -- gets no marker, and every other cross-realm case gets the
            -- foreign-server suffix. No second branch on
            -- INTERACTIVE_SERVER_LABEL / LE_REALM_RELATION_COALESCED:
            -- neither name exists in 12.0.7, and
            -- comparing against a nil constant would also make a nil
            -- relationship match by accident.
            if realm and realm ~= "" then
                if db.AlwaysShowRealm then
                    name = name .. "-" .. realm
                elseif UnitRealmRelationship(unit) ~= _G.LE_REALM_RELATION_VIRTUAL then
                    name = name .. (_G.FOREIGN_SERVER_LABEL or "")
                end
            end

            local line1 = _G.GameTooltipTextLeft1
            if line1 then line1:SetText(name .. AwayLabel(unit)) end
        end
    end

    -- Guild line color: for players with a guild, Blizzard's line 2 is
    -- the guild name. Recolor only -- no text compare, no rewrite.
    if db.GuildColorEnabled and UnitIsPlayer(unit) and GetGuildInfo(unit) then
        local line2 = _G.GameTooltipTextLeft2
        if line2 then
            local gc = db.GuildColor
            line2:SetTextColor(gc.r or 0, gc.g or 0.8, gc.b or 0.4)
        end
    end

    -- Guild rank, appended to the guild line itself: "Lucid - Officer".
    --
    -- The guild line is re-found every call rather than assumed to be line 2:
    -- a player title shifts it down, and a cached index would decorate the
    -- wrong row on the next unit. Appending means concatenating the existing
    -- text, which is only safe once it is known not to be a secret value --
    -- everywhere else this module recolours rather than rewrites for exactly
    -- that reason.
    if (db.GuildRankLine or db.HideGuildRealm) and UnitIsPlayer(unit) then
        local guildName, rankName, _, guildRealm = GetGuildInfo(unit)
        if guildName
            and not KE:IsSecretValue(guildName)
            and not (rankName and KE:IsSecretValue(rankName)) then

            -- Blizzard writes a cross-realm guild as "Guild - Realm", and the
            -- rank would land after it: "Instant Dollars - Mal'Ganis -
            -- Officer". Realm is trimmed first so the rank attaches to the
            -- guild name itself. Plain string ops, not patterns -- realm
            -- names carry apostrophes and hyphens.
            -- "Instant Dollars [Officer]". Same form EllesmereUI and ElvUI
            -- use, and it survives guild names that contain a dash --
            -- "Knights - of - Ni - Officer" is ambiguous, the bracketed form
            -- is not. Because EUI writes the identical form, this one check
            -- both defers to EUI and stops us re-appending on refresh ticks.
            local wantRank = db.GuildRankLine and rankName
                and not TipHasText(tt, "[" .. rankName .. "]")
            local suffix = wantRank and (" [" .. rankName .. "]") or nil

            for i = 2, tt:NumLines() do
                local line = _G["GameTooltipTextLeft" .. i]
                local text = line and line:GetText()
                if text and not KE:IsSecretValue(text)
                    and text:find(guildName, 1, true) then

                    local out = text
                    if db.HideGuildRealm and guildRealm and guildRealm ~= "" then
                        local at = out:find(guildRealm, 1, true)
                        if at then
                            out = out:sub(1, at - 1)
                            -- drop the separator the realm hung off
                            while out ~= "" do
                                local last = out:sub(-1)
                                if last == " " or last == "-" then
                                    out = out:sub(1, -2)
                                else
                                    break
                                end
                            end
                        end
                    end

                    -- Angle brackets around the guild name itself, before
                    -- the rank is appended: "<Instant Dollars> [Officer]".
                    -- Same form ElvUI writes (Tooltip.lua). Guarded on
                    -- the first character so refresh ticks cannot nest them.
                    if out:sub(1, 1) ~= "<" then
                        out = "<" .. out .. ">"
                    end

                    -- Refresh ticks re-run this on text that may already
                    -- carry the rank, so re-appending has to be guarded.
                    if suffix and out:sub(-#suffix) ~= suffix then
                        out = out .. suffix
                    end

                    if out ~= text and out ~= "" then line:SetText(out) end
                    break
                end
            end
        end
    end

    -- Level row rebuild: "90 Dark Iron Dwarf" in place of Blizzard's
    -- "Level 90 Dark Iron Dwarf (Player)", with the number tinted by how
    -- dangerous the unit is. Ports ElvUI's SetUnitText/GetLevelLine pair
    -- (Tooltip.lua).
    --
    -- The name row above is rebuilt separately, behind CanReadIdentity.
    -- The same gate is needed here: 12.1 puts UnitRace (and GetGuildInfo's
    -- name) under identity restriction, and a secret race inside format()
    -- throws. Fail closed -- Blizzard's own level line stays.
    if UnitIsPlayer(unit) and CanReadIdentity(unit) then
        local guildName = GetGuildInfo(unit)
        local levelLine, specLine = FindLevelLine(tt, guildName and 2 or 1)

        if levelLine then
            -- Effective level is what the unit fights at (scaled content);
            -- real level is what it actually is. ElvUI shows both when they
            -- differ, so a scaled-down 80 reads "80 (90) Night Elf".
            local level = UnitEffectiveLevel(unit)
            local realLevel = UnitLevel(unit)
            local race = UnitRace(unit)
            local diff = GetCreatureDifficultyColor(level)
            local r = (diff and diff.r or 1) * 255
            local g = (diff and diff.g or 1) * 255
            local b = (diff and diff.b or 1) * 255

            local shown = (level and level > 0) and level or "??"
            local text
            if level and realLevel and level < realLevel then
                text = format("|cff%02x%02x%02x%s|r |cffFFFFFF(%s)|r %s",
                    r, g, b, tostring(shown), tostring(realLevel), race or "")
            else
                text = format("|cff%02x%02x%02x%s|r %s",
                    r, g, b, tostring(shown), race or "")
            end
            levelLine:SetText(text)
        end

        -- The row after the level row is the spec/class row ("Protection
        -- Paladin"). ElvUI rewrites it wrapped in a colour code; a plain
        -- SetTextColor gets the same look without reading the text, so no
        -- secret check is needed here.
        if specLine and db.ClassColorNames and unitColor then
            specLine:SetTextColor(unitColor:GetRGB())
        end
    end

    -- Faction row. "Alliance" / "Horde" duplicates what the name and level
    -- rows already convey, so the clean look drops it. The PvP tag on the
    -- same line is left alone.
    if db.HideFactionLine then
        local okData, info = pcall(tt.GetTooltipData, tt)
        if okData and info and info.lines then
            for i = 3, #info.lines do
                local text = info.lines[i] and info.lines[i].leftText
                if text and not KE:IsSecretValue(text) then
                    if text == "" then break end
                    if text == _G.FACTION_ALLIANCE or text == _G.FACTION_HORDE then
                        local left = _G["GameTooltipTextLeft" .. i]
                        if left then
                            left:SetText("")
                            left:Hide()
                        end
                    end
                end
            end
        end
    end

    -- Mythic+ score. Blizzard only fills this in for units it already has
    -- rating data for (group members, inspected players), so a stranger
    -- returns nothing and the line is simply skipped rather than showing 0.
    if db.MythicPlusLine and UnitIsPlayer(unit) and C_PlayerInfo
        and C_PlayerInfo.GetPlayerMythicPlusRatingSummary then
        local ok, summary = pcall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, unit)
        local score = ok and summary and summary.currentSeasonScore
        if score and score > 0
            and not TipHasText(tt, "M+ Score")
            and not TipHasText(tt, _G.DUNGEON_SCORE or "Mythic+ Score") then
            local r, g, b = 1, 1, 1
            if C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor then
                local c = C_ChallengeMode.GetDungeonScoreRarityColor(score)
                if c then r, g, b = c.r, c.g, c.b end
            end
            tt:AddDoubleLine(format("%s:", _G.DUNGEON_SCORE or "Mythic+ Score"),
                tostring(score), 1, 1, 1, r, g, b)
        end
    end

    -- Target line (ElvUI AddTargetInfo, retail branch).
    if db.TargetLine then
        local unitTarget = unit .. "target"
        if unit ~= "player" and UnitExists(unitTarget) then
            -- the v891 IsSecretValue skip suppressed the line
            -- for every secret target (most of Midnight group content).
            -- AddDoubleLine is a DISPLAY SINK -- secret text is allowed
            -- through it; what is forbidden is format/concat on the
            -- name, which this deliberately never does.
            local name = UnitName(unitTarget)
            if name then
                -- AddDoubleLine is a display sink, so secret colour
                -- components pass through it untouched.
                --
                -- The target's own GUID is passed as well as its token, so a
                -- player target still class-colours when the token is secret
                -- but the GUID is not. UnitGUID is SecretWhenUnitIdentity-
                -- Restricted, so under a restriction it degrades to white --
                -- which is the honest answer, not a guess at the class.
                local c = UnitColor(unitTarget, UnitGUID(unitTarget))
                tt:AddDoubleLine(format("%s:", _G.TARGET or "Target"),
                    name, 1, 1, 1, (c or WHITE_COLOR):GetRGB())
            end
        end
    end
end

-- Spell / item IDs ----------------------------------------------------

local function WantIDs(db)
    local mode = db.ShowIDs or "MODIFIER"
    if mode == "NEVER" then return false end
    if mode == "MODIFIER" then return IsModifierKeyDown() end
    return true
end

-- (field: no Spell ID on macro tooltips despite #showtooltip):
-- a macro's tooltip is TooltipDataType.MACRO, not SPELL, so the Spell
-- post-call never fired -- the same disease as the buff frame
-- and talent tooltips. ElvUI routes MACRO into this very
-- handler and reads the id off the first tooltip LINE (Tooltip.lua
-- ~1000): data.id on a macro is the macro slot, not the spell.
function TT:OnTooltipSetSpell(tt, data)
    local db = self.db
    if IsEmbeddedTip(tt) then return end
    if not db or tt:IsForbidden() or not WantIDs(db) then return end

    local id
    local T = _G.Enum and _G.Enum.TooltipDataType
    local dtype = data and data.type
    if T and dtype == T.Macro then
        local ok, info = pcall(tt.GetTooltipData, tt)
        local line = ok and info and info.lines and info.lines[1]
        id = line and line.tooltipID
    else
        id = data and data.id
    end

    if not id or KE:IsSecretValue(id) then return end
    tt:AddLine(format("|cff7c7c7cSpell ID:|r %d", id))
    tt:Show()
end

-- 12.1 renders aura spell IDs ENGINE-SIDE, and that is the only route that ever
-- reaches an aura-container tooltip: those buttons show a forbidden clone of
-- GameTooltip that no AddLine of ours can touch.
--
-- It also reaches where the Lua line cannot: under aura restriction the id is a
-- SECRET, so AddAuraIDLine bails and combat aura tooltips lose the line
-- entirely. The engine formats it itself and is unaffected.
--
-- The CVar is session-only, so it needs re-asserting. Other addons drive the
-- same one; writes are read-gated and event-driven, so two of them agreeing or
-- disagreeing settles rather than loops.
local AURA_ID_CVAR = "tooltipShowAuraSpellIDs"
local auraIDCVarPresent

function TT:SyncAuraSpellIDCVar()
    if auraIDCVarPresent == nil then
        local okProbe, cur = pcall(C_CVar.GetCVar, AURA_ID_CVAR)
        auraIDCVarPresent = (okProbe and cur ~= nil) and true or false
    end
    if not auraIDCVarPresent then return end

    -- Engine rendering is unconditional, so it can only stand in for ALWAYS.
    -- Under MODIFIER the line is meant to appear while a key is held, which the
    -- engine cannot honour -- the Lua hooks keep that mode, and forbidden aura
    -- tooltips simply have no ID there.
    local db = self.db
    local on = (db and self:IsEnabled() and db.ShowIDs == "ALWAYS") and "1" or "0"
    -- Read first: writing a CVar makes the client flush its config, and
    -- ApplySettings runs on every options edit.
    local ok, cur = pcall(C_CVar.GetCVar, AURA_ID_CVAR)
    if ok and cur ~= on then pcall(C_CVar.SetCVar, AURA_ID_CVAR, on) end
    self.engineAuraIDs = (on == "1")
end

local function AddAuraIDLine(tt, _, spellId)
    -- The engine already put the line there; a second one would be a duplicate.
    if TT.engineAuraIDs then return end
    if not spellId or (KE.IsSecretValue and KE:IsSecretValue(spellId)) then return end
    tt:AddLine(format("|cff7c7c7cSpell ID:|r %d", spellId))
    tt:Show()
end

function TT:AuraIDByInstance(tt, unit, auraInstanceID)
    local db = self.db
    if not db or tt ~= _G.GameTooltip or tt:IsForbidden() or not WantIDs(db) then return end
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID) then return end
    local ok, aura = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, auraInstanceID)
    if ok and aura then AddAuraIDLine(tt, db, aura.spellId) end
end

function TT:AuraIDByIndex(tt, unit, index, filter)
    local db = self.db
    if not db or tt ~= _G.GameTooltip or tt:IsForbidden() or not WantIDs(db) then return end
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
    local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
    if ok and aura then AddAuraIDLine(tt, db, aura.spellId) end
end

function TT:OnTooltipSetItem(tt, data)
    local db = self.db
    if IsEmbeddedTip(tt) then return end
    if not db or tt:IsForbidden() or not WantIDs(db) then return end
    local id = data and data.id
    if not id or KE:IsSecretValue(id) then return end
    tt:AddLine(format("|cff7c7c7cItem ID:|r %d", id))
end

-- Anchor --------------------------------------------------------------

function TT:SetDefaultAnchor(tt, parent)
    local db = self.db
    if not db or tt ~= _G.GameTooltip or tt:IsForbidden() then return end
    if db.CursorAnchor then
        tt:SetOwner(parent, "ANCHOR_CURSOR_RIGHT",
            db.CursorOffsetX or 10, db.CursorOffsetY or -10)
    elseif self.anchorFrame then
        -- Default-anchored tooltips dock to this addon's own movable anchor
        -- instead of Blizzard's screen corner.
        tt:SetOwner(parent, "ANCHOR_NONE")
        tt:ClearAllPoints()
        tt:SetPoint("BOTTOMRIGHT", self.anchorFrame, "BOTTOMRIGHT", 0, 0)
    end
end

function TT:EnsureAnchor()
    if not self.anchorFrame then
        local f = CreateFrame("Frame", "KE_TooltipAnchor", UIParent)
        f:SetSize(130, 20)
        self.anchorFrame = f
        self:ApplyPosition()
    end
    -- Registration is deliberately outside the frame guard. The frame is
    -- created once and never destroyed, so leaving registration inside it
    -- meant a disable/enable cycle could never register again.
    self:RegisterEditMode()
end

function TT:RegisterEditMode()
    if not (KE.EditMode and KE.EditMode.RegisterElement) then return end
    if not self.anchorFrame or self.editModeRegistered then return end
    self.editModeRegistered = true
    KE.EditMode:RegisterElement({
        key = "TooltipAnchor",
        module = self,
        -- Cursor anchoring bypasses this frame entirely, so there is nothing
        -- for a drag to place.
        isEligible = function() return self.db.CursorAnchor ~= true end,
        displayName = "Tooltip",
        frame = self.anchorFrame,
        getPosition = function() return self.db.Position end,
        setPosition = function(pos)
            local p = self.db.Position
            p.AnchorFrom = pos.AnchorFrom
            p.AnchorTo = pos.AnchorTo
            p.XOffset = pos.XOffset
            p.YOffset = pos.YOffset
            self:ApplyPosition()
        end,
        getParentFrame = function()
            local p = self.db.Position
            return KE:ResolveAnchorFrame(p.AnchorFrameType, p.ParentFrame)
        end,
        guiPath = "SkinTooltips",
    })
end

-- The position card offers a parent frame and a strata, and both need somewhere
-- to land. Before EnsureAnchor has run there is no frame to move, so only
-- the strata pass does anything.
function TT:ApplyPosition()
    local p = self.db and self.db.Position
    if not p then return end

    if self.anchorFrame then
        local parent = KE:ResolveAnchorFrame(p.AnchorFrameType, p.ParentFrame)
        self.anchorFrame:ClearAllPoints()
        self.anchorFrame:SetPoint(p.AnchorFrom or "BOTTOMRIGHT", parent,
            p.AnchorTo or "BOTTOMRIGHT", p.XOffset or -120, p.YOffset or 220)
    end

    if p.Strata then
        for _, name in pairs(STYLE_LIST) do
            local tt = _G[name]
            if tt and tt.SetFrameStrata then tt:SetFrameStrata(p.Strata) end
        end
    end
end

-- Lifecycle -----------------------------------------------------------

function TT:ApplySettings()
    if not self:IsEnabled() then return end
    self:UpdateDB()
    self:ApplyFonts()
    self:StyleHealthBar()
    self:ApplyPosition()
    self:SyncAuraSpellIDCVar()
    -- Restyle anything currently shown so color edits apply live.
    for _, name in pairs(STYLE_LIST) do
        local tt = _G[name]
        if tt and tt:IsShown() then self:StyleTooltip(tt) end
    end
end

function TT:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function TT:OnEnable()
    self:UpdateDB()

    if not self.hooked then
        self.hooked = true

        for _, name in pairs(STYLE_LIST) do
            local tt = _G[name]
            if tt and tt.HookScript then
                tt:HookScript("OnShow", function(frame) TT:StyleTooltip(frame) end)
            end
        end
        -- Retail resets tooltip style per content (item-quality borders
        -- etc.) through this shared path; restyle after it runs.
        if _G.SharedTooltip_SetBackdropStyle then
            hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tt, _, isEmbedded)
                if not isEmbedded and not tt.IsEmbedded and TT:IsEnabled() then
                    TT:StyleTooltip(tt)
                end
            end)
        end

        if _G.TooltipDataProcessor and _G.TooltipDataProcessor.AddTooltipPostCall then
            local T = _G.Enum.TooltipDataType
            _G.TooltipDataProcessor.AddTooltipPostCall(T.Unit, function(tt, data)
                if TT:IsEnabled() then TT:OnTooltipSetUnit(tt, data) end
            end)
            _G.TooltipDataProcessor.AddTooltipPostCall(T.Spell, function(tt, data)
                if TT:IsEnabled() then TT:OnTooltipSetSpell(tt, data) end
            end)
            -- macros are their own data type; ElvUI feeds them
            -- through the same handler (Tooltip.lua ~1217).
            if T.Macro then
                _G.TooltipDataProcessor.AddTooltipPostCall(T.Macro, function(tt, data)
                    if TT:IsEnabled() then TT:OnTooltipSetSpell(tt, data) end
                end)
            end
            _G.TooltipDataProcessor.AddTooltipPostCall(T.Item, function(tt, data)
                if TT:IsEnabled() then TT:OnTooltipSetItem(tt, data) end
            end)
        end

        if _G.GameTooltipStatusBar then
            _G.GameTooltipStatusBar:HookScript("OnShow", function(bar)
                if TT:IsEnabled() and TT.db and TT.db.HealthBarHidden then bar:Hide() end
            end)
        end
    end

    -- AceHook's UnhookAll (OnEmbedDisable) strips every SecureHook when the
    -- module disables, but self.hooked stays true -- so these live outside
    -- the guard above and re-register on every enable.
    self:SecureHook("GameTooltip_SetDefaultAnchor", "SetDefaultAnchor")

    -- (buff frame missing Spell IDs with shift): the modern
    -- BuffFrame builds its tooltips through SetUnitBuffByAuraInstanceID,
    -- which is TooltipDataType.UnitAura -- the Spell post-call never
    -- fires. ElvUI hooks the aura setters directly; same here, with
    -- the spellId resolved from C_UnitAuras at hook time.
    if _G.GameTooltip.SetUnitBuffByAuraInstanceID then
        self:SecureHook(_G.GameTooltip, "SetUnitBuffByAuraInstanceID", "AuraIDByInstance")
        self:SecureHook(_G.GameTooltip, "SetUnitDebuffByAuraInstanceID", "AuraIDByInstance")
    end
    self:SecureHook(_G.GameTooltip, "SetUnitAura", "AuraIDByIndex")
    self:SecureHook(_G.GameTooltip, "SetUnitBuff", "AuraIDByIndex")
    self:SecureHook(_G.GameTooltip, "SetUnitDebuff", "AuraIDByIndex")

    -- (holding a modifier after the tooltip was already
    -- up never added the ID lines): ElvUI's mechanism -- on modifier
    -- change, RefreshData() re-fires the tooltip data processors, so the
    -- Unit/Spell/Item post-calls re-run with the new modifier state.
    self:RegisterEvent("MODIFIER_STATE_CHANGED")
    -- Not PLAYER_LOGIN: the client settles its session CVars after login and
    -- clobbers a write made that early. Kept registered so a later reset is
    -- answered too -- one guarded read per zone-in.
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "SyncAuraSpellIDCVar")

    self:EnsureAnchor()
    self:ApplySettings()
    S.InstallTooltipStatusBarHook()
end

function TT:MODIFIER_STATE_CHANGED()
    local tt = _G.GameTooltip
    if not (tt and not tt:IsForbidden() and tt:IsShown() and tt.RefreshData) then return end
    -- NEVER RefreshData a UNIT tooltip from addon code. The
    -- rebuild re-runs Blizzard's own line processors on OUR (tainted)
    -- execution -- GameTooltip_UnitColor then feeds a secret unit into
    -- UnitPlayerControlled, which secrets forbid outside untainted
    -- execution (1x error). The live ID toggle only matters for
    -- spell/item tooltips anyway; detect those via GetItem/GetSpell
    -- (nil,nil on unit tooltips -- no secret branching involved).
    local itemLink = select(2, tt:GetItem())
    local spellID = select(2, tt:GetSpell())
    -- action-button/macro
    -- tooltips get their NAME line from the action layer, so a forced
    -- RefreshData rebuilds them lossily (title + rank vanish). They also
    -- self-refresh every ~0.1s through the proper SetAction path, so the
    -- modifier toggle works there WITHOUT us -- skip owners that carry
    -- an action slot and only force-refresh static tooltips (spellbook,
    -- talents) that never refresh on their own.
    local owner = tt:GetOwner()
    if owner and owner.action then return end
    if itemLink or spellID then
        -- (talent NAME vanished with
        -- shift held): raw RefreshData is lossy for ANY tooltip whose
        -- title is added by the owning frame rather than the spell data
        -- -- hit this on macro buttons, talents are the same
        -- disease (TalentDisplay mixins add the name line themselves).
        -- ElvUI's actual handler never force-refreshes these: it
        -- re-fires the owner's own tooltip builder. Generalized here:
        -- when the owner has an OnEnter, re-run it -- the frame rebuilds
        -- its tooltip through the CORRECT path, nothing is lost, and our
        -- data processor re-fires with the new modifier state. Raw
        -- RefreshData remains only as the ownerless fallback.
        -- still applies: 12.x hands SECRET color tables to
        -- ordinary lines and the rebuild runs on our tainted execution,
        -- so both paths stay pcall'd -- on failure the tooltip re-renders
        -- securely on its own next natural update.
        local onEnter = owner and owner.GetScript and owner:GetScript("OnEnter")
        if onEnter then
            pcall(onEnter, owner)
        else
            pcall(tt.RefreshData, tt)
        end
    end
end

function TT:OnDisable()
    self:UnregisterEvent("MODIFIER_STATE_CHANGED")
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    -- AceAddon clears enabledState before dispatching this, so the sync
    -- computes "off" and the engine stops drawing the line.
    self:SyncAuraSpellIDCVar()
    -- The anchor frame survives, so the guard has to be cleared or a later
    -- enable would skip registration and leave the tool holding a dead key.
    if KE.EditMode then KE.EditMode:UnregisterElement("TooltipAnchor") end
    self.editModeRegistered = nil
    -- Hooks stay installed (hooksecurefunc/HookScript cannot be removed)
    -- but every handler gates on IsEnabled, so disabled = inert. Undo
    -- the visual state; fonts and bar height need a reload to fully
    -- revert to stock (the GUI prompts for it).
    for _, name in pairs(STYLE_LIST) do
        local tt = _G[name]
        if tt then UnstyleTooltip(tt) end
    end
end

-- Test seams. dev/spec/tooltips_spec.lua reaches the pure helpers through
-- these; nothing in the addon calls them.
TT._ColorsMatch = ColorsMatch
TT._ReactionColor = ReactionColor
TT._WantIDs = WantIDs
TT._UnitColor = UnitColor
TT._AddAuraIDLine = AddAuraIDLine

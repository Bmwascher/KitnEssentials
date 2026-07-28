-- KitnEssentials — Tooltips (v3.5.891)
--
-- the brief: EUI-grade performance, more customization, and enough
-- coverage to retire EllesmereUIBlizzardSkin ("BlizzUI Enhanced") from
-- the pack, since tooltip skinning is all it is used for.
--
-- Architecture notes (both references studied):
--   * EUI BlizzardSkin: visual-only changes -- alpha/backdrop/font, no
--     Hide/Show/SetParent on Blizzard frames, all post-hooks. Class
--     recolor works on GameTooltipTextLeft1 directly instead of
--     rebuilding the unit block. That discipline is kept 1:1.
--   * ElvUI TT: TooltipDataProcessor.AddTooltipPostCall for unit/spell/
--     item data, GameTooltip_SetDefaultAnchor hook for anchoring,
--     NineSlice:SetAlpha(0) + own backdrop for the style, global font
--     objects for text, statusbar height/texture/text. Feature set and
--     secret-value guards transcribed from there.
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
local unpack = unpack
local CreateFrame = CreateFrame
local UnitExists = UnitExists
local UnitIsPlayer = UnitIsPlayer
local UnitClass = UnitClass
local UnitName = UnitName
local UnitReaction = UnitReaction
local GetGuildInfo = GetGuildInfo
local InCombatLockdown = InCombatLockdown
local IsModifierKeyDown = IsModifierKeyDown
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local FACTION_BAR_COLORS = FACTION_BAR_COLORS
local hooksecurefunc = hooksecurefunc
local S = KE.Skins

-- Compact number formatting for the health text (no AE-level helper
-- exists; local keeps it allocation-free on the hot path).
local function ShortValue(v)
    if v >= 1e9 then return format("%.1fB", v / 1e9)
    elseif v >= 1e6 then return format("%.1fM", v / 1e6)
    elseif v >= 1e3 then return format("%.1fK", v / 1e3)
    else return format("%d", v) end
end

-- v3.5.892: AE:GetEffectiveFont returns the LSM NAME, not a file path
-- (every consumer resolves it through LSM; v891 passed the raw name to
-- SetFont -> "Invalid font asset (Expressway)"). Silent fetch + stock
-- fallback so a missing registration degrades instead of erroring.
local function ResolveFont(db)
    local name = db and (db.FontFace or db.Font or db.fontFace) or "Friz Quadrata TT"
    local path = KE.LSM and KE.LSM:Fetch("font", name, true)
    return path or _G.STANDARD_TEXT_FONT
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

-- v4.0.12: EUI's ACTUAL overlay technique (BlizzardSkin.lua:207-215) --
-- plain textures on the tooltip, no BackdropTemplate. The old
-- BackdropTemplate child ran SetupTextureCoordinates (width/edgeSize
-- arithmetic) on every tooltip resize, and Midnight world-quest
-- tooltips resize with SECRET widths: 196x "arithmetic on secret
-- width, tainted by atrocityEssentials" (field BugSack). Textures
-- anchored to the frame resize in C -- zero Lua size math, nothing to
-- go secret.
local function EnsureStyler(tt)
    local s = tt.AESTooltipStyle
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

    tt.AESTooltipStyle = s
    return s
end

-- v4.0.147: this runs from GameTooltip's OnShow, so it executes on EVERY
-- tooltip -- including map POI hovers, where Blizzard follows the show
-- with GameTooltip_AddWidgetSet. Any insecure work here taints that
-- execution, and the widget layout then dies on a secret number:
--
--   Blizzard_UIWidgetTemplateTextWithState.lua:35: attempt to perform
--   arithmetic on local 'textHeight' (a secret number value, while
--   execution tainted by 'atrocityEssentials')
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

    local s = tt.AESTooltipStyle
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
    if tt.AESTooltipStyle then
        tt.AESTooltipStyle.Hide()
        -- Clear the fast-path flag so the next StyleTooltip re-shows.
        tt.AESTooltipStyle.shown = nil
    end
end

-- Fonts ---------------------------------------------------------------

-- ElvUI's approach: the shared font objects cover every tooltip line at
-- zero per-line cost. 12.0.7 shadow doctrine: shadows untouched.
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
end

-- Health bar ----------------------------------------------------------

function TT:StyleHealthBar()
    local bar = _G.GameTooltipStatusBar
    if not bar or not self.db then return end
    local db = self.db
    -- v3.5.893: fully remove the bar. Blizzard re-shows it per
    -- unit tooltip, so the OnShow hook in OnEnable keeps it hidden.
    if db.HealthBarHidden then
        bar:Hide()
        if bar.AESText then bar.AESText:Hide() end
        return
    end
    bar:SetHeight(db.HealthBarHeight or 7)
    local tex = KE.LSM and KE.LSM:Fetch("statusbar", db.HealthBarTexture or "Blizzard", true)
    if tex then bar:SetStatusBarTexture(tex) end
    if db.HealthBarText and not bar.AESText then
        local text = bar:CreateFontString(nil, "OVERLAY")
        text:SetPoint("CENTER", bar, "CENTER", 0, 0)
        bar.AESText = text
    end
    if bar.AESText then
        bar.AESText:SetFont(ResolveFont(db), db.HealthTextSize or 10, "OUTLINE")
        bar.AESText:SetShown(db.HealthBarText and true or false)
    end
end

function TT:HealthBarValueChanged(bar, value)
    local text = bar and bar.AESText
    if not text or not self.db or not self.db.HealthBarText then return end
    -- Health can be SECRET in Midnight content: arithmetic or format on
    -- it would throw. Secret -> show nothing rather than error.
    if KE:IsSecretValue(value) then text:SetText("") return end
    local _, maxv = bar:GetMinMaxValues()
    if KE:IsSecretValue(maxv) or not maxv or maxv == 0 then text:SetText("") return end
    if value <= 0 then
        text:SetText(_G.DEAD or "Dead")
    else
        text:SetFormattedText("%s / %s", ShortValue(value), ShortValue(maxv))
    end
end

-- Unit extras ---------------------------------------------------------

local function ReactionColor(unit)
    local reaction = UnitReaction(unit, "player")
    local c = reaction and FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function UnitColor(unit)
    -- v3.5.893: Midnight secret units. UnitName returning a secret is
    -- the tell (ElvUI's IsSecretUnit); on that branch UnitIsPlayer /
    -- UnitReaction results are secret booleans -- branching on them is
    -- the crash class -- but UnitClass's classFile stays usable, so
    -- resolve color through it (ElvUI AddTargetInfo secret branch).
    if KE:IsSecretValue(UnitName(unit)) then
        local _, class = UnitClass(unit)
        local c = class and RAID_CLASS_COLORS[class]
        if c then return c.r, c.g, c.b end
        return 1, 1, 1
    end
    if UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        local c = class and RAID_CLASS_COLORS[class]
        if c then return c.r, c.g, c.b end
    end
    return ReactionColor(unit)
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

-- Embedded tooltips (UIWidgetBaseItemEmbeddedTooltip*, the reward previews
-- inside UI widgets) must not be written to. Blizzard sizes the host widget
-- from them -- Blizzard_UIWidgetTemplateBase.lua:1638 does
--
--   widgetHeight = math.max(iconSize, self.Tooltip:GetHeight())
--
-- and an AddLine from us makes that height a secret number, so the arithmetic
-- fails with "execution tainted by 'atrocityEssentials'". StyleTooltip
-- already excluded them; the TooltipDataProcessor post-calls did not, so an
-- item ID line landed in widget reward tooltips on the world map.
local function IsEmbeddedTip(tt)
    if not tt then return true end
    if tt.IsEmbedded then return true end

    local name = tt.GetName and tt:GetName()
    return name and name:find("EmbeddedTooltip", 1, true) and true or false
end

function TT:OnTooltipSetUnit(tt)
    if IsEmbeddedTip(tt) then return end
    local db = self.db
    if not db or tt ~= _G.GameTooltip or tt:IsForbidden() then return end

    if db.HideInCombat and InCombatLockdown() and not IsModifierKeyDown() then
        tt:Hide()
        return
    end

    local unitOk, _, unit = pcall(tt.GetUnit, tt)
    if not unitOk then return end
    if not unit or KE:IsSecretValue(unit) or not UnitExists(unit) then return end

    -- Class/reaction color: recolor the existing name line (EUI's
    -- technique -- no text rebuild, so secret name strings never touch
    -- our code) and the health bar.
    if db.ClassColorNames then
        local r, g, b = UnitColor(unit)
        local line1 = _G.GameTooltipTextLeft1
        if line1 then line1:SetTextColor(r, g, b) end
        local bar = _G.GameTooltipStatusBar
        if bar then bar:SetStatusBarColor(r, g, b) end
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
            -- v3.5.893: the v891 IsSecretValue skip suppressed the line
            -- for every secret target (most of Midnight group content).
            -- AddDoubleLine is a DISPLAY SINK -- secret text is allowed
            -- through it; what is forbidden is format/concat on the
            -- name, which this deliberately never does.
            local name = UnitName(unitTarget)
            if name then
                local r, g, b = UnitColor(unitTarget)
                tt:AddDoubleLine(format("%s:", _G.TARGET or "Target"),
                    name, 1, 1, 1, r, g, b)
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

-- v4.0.41 (field: no Spell ID on macro tooltips despite #showtooltip):
-- a macro's tooltip is TooltipDataType.MACRO, not SPELL, so the Spell
-- post-call never fired -- the same disease as the buff frame (v4.0.7)
-- and talent tooltips (v4.0.5). ElvUI routes MACRO into this very
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

local function AddAuraIDLine(tt, _, spellId)
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
        -- v3.5.897 (the ORIGINAL ask, ElvUI TooltipMover
        -- pattern): default-anchored tooltips dock to the movable AES
        -- Tooltip anchor instead of Blizzard's corner.
        tt:SetOwner(parent, "ANCHOR_NONE")
        tt:ClearAllPoints()
        tt:SetPoint("BOTTOMRIGHT", self.anchorFrame, "BOTTOMRIGHT", 0, 0)
    end
end

function TT:EnsureAnchor()
    if self.anchorFrame then return end
    local f = CreateFrame("Frame", "KE_TooltipAnchor", UIParent)
    f:SetSize(130, 20)
    self.anchorFrame = f
    self:ApplyPosition()
    if KE.EditMode and KE.EditMode.RegisterElement then
        KE.EditMode:RegisterElement({
            key = "TooltipAnchor",
            displayName = "Tooltip",
            frame = f,
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
end

-- KE-only. The reference anchors to UIParent and never repositions; KE's
-- position card offers a parent frame and a strata, and both need somewhere
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
            -- v4.0.41: macros are their own data type; ElvUI feeds them
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
            _G.GameTooltipStatusBar:HookScript("OnValueChanged", function(bar, value)
                if TT:IsEnabled() then TT:HealthBarValueChanged(bar, value) end
            end)
            _G.GameTooltipStatusBar:HookScript("OnShow", function(bar)
                if TT:IsEnabled() and TT.db and TT.db.HealthBarHidden then bar:Hide() end
            end)
        end
    end

    -- AceHook's UnhookAll (OnEmbedDisable) strips every SecureHook when the
    -- module disables, but self.hooked stays true -- so these live outside
    -- the guard above and re-register on every enable.
    self:SecureHook("GameTooltip_SetDefaultAnchor", "SetDefaultAnchor")

    -- v4.0.7 (buff frame missing Spell IDs with shift): the modern
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

    -- v3.5.893 (holding a modifier after the tooltip was already
    -- up never added the ID lines): ElvUI's mechanism -- on modifier
    -- change, RefreshData() re-fires the tooltip data processors, so the
    -- Unit/Spell/Item post-calls re-run with the new modifier state.
    self:RegisterEvent("MODIFIER_STATE_CHANGED")

    self:EnsureAnchor()
    self:ApplySettings()
    S.InstallTooltipStatusBarHook()
end

function TT:MODIFIER_STATE_CHANGED()
    local tt = _G.GameTooltip
    if not (tt and not tt:IsForbidden() and tt:IsShown() and tt.RefreshData) then return end
    -- v3.5.899: NEVER RefreshData a UNIT tooltip from addon code. The
    -- rebuild re-runs Blizzard's own line processors on OUR (tainted)
    -- execution -- GameTooltip_UnitColor then feeds a secret unit into
    -- UnitPlayerControlled, which secrets forbid outside untainted
    -- execution (1x error). The live ID toggle only matters for
    -- spell/item tooltips anyway; detect those via GetItem/GetSpell
    -- (nil,nil on unit tooltips -- no secret branching involved).
    local itemLink = select(2, tt:GetItem())
    local spellID = select(2, tt:GetSpell())
    -- v3.5.913: action-button/macro
    -- tooltips get their NAME line from the action layer, so a forced
    -- RefreshData rebuilds them lossily (title + rank vanish). They also
    -- self-refresh every ~0.1s through the proper SetAction path, so the
    -- modifier toggle works there WITHOUT us -- skip owners that carry
    -- an action slot and only force-refresh static tooltips (spellbook,
    -- talents) that never refresh on their own.
    local owner = tt:GetOwner()
    if owner and owner.action then return end
    if itemLink or spellID then
        -- v4.0.5 (talent NAME vanished with
        -- shift held): raw RefreshData is lossy for ANY tooltip whose
        -- title is added by the owning frame rather than the spell data
        -- -- v3.5.913 hit this on macro buttons, talents are the same
        -- disease (TalentDisplay mixins add the name line themselves).
        -- ElvUI's actual handler never force-refreshes these: it
        -- re-fires the owner's own tooltip builder. Generalized here:
        -- when the owner has an OnEnter, re-run it -- the frame rebuilds
        -- its tooltip through the CORRECT path, nothing is lost, and our
        -- data processor re-fires with the new modifier state. Raw
        -- RefreshData remains only as the ownerless fallback.
        -- v3.5.911 still applies: 12.x hands SECRET color tables to
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
    -- Hooks stay installed (hooksecurefunc/HookScript cannot be removed)
    -- but every handler gates on IsEnabled, so disabled = inert. Undo
    -- the visual state; fonts and bar height need a reload to fully
    -- revert to stock (the GUI prompts for it).
    for _, name in pairs(STYLE_LIST) do
        local tt = _G[name]
        if tt then UnstyleTooltip(tt) end
    end
    local bar = _G.GameTooltipStatusBar
    if bar and bar.AESText then bar.AESText:Hide() end
end

-- Test seams. dev/spec/tooltips_spec.lua reaches the pure helpers through
-- these; nothing in the addon calls them.
TT._ShortValue = ShortValue
TT._ColorsMatch = ColorsMatch
TT._ReactionColor = ReactionColor
TT._WantIDs = WantIDs

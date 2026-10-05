-- ╔══════════════════════════════════════════════════════════╗
-- ║  LFGReminder.lua                                         ║
-- ║  Module: LFG Reminder                                    ║
-- ║  Purpose: When you join a Group Finder group for a       ║
-- ║           dungeon with a known teleport, show a small    ║
-- ║           popup with the dungeon name and a one-click    ║
-- ║           teleport button. Hides on entering the         ║
-- ║           dungeon, leaving the group, or entering        ║
-- ║           combat.                                        ║
-- ║                                                          ║
-- ║  Taint / secret-value safety -- critical, read before    ║
-- ║  editing:                                                ║
-- ║    * The teleport spellID fed to SetAttribute("spell")   ║
-- ║      is ALWAYS a static integer from our own map->spell  ║
-- ║      table, never an LFG field or an addon message.      ║
-- ║    * The dungeon resolves on LFG_LIST_JOINED_GROUP,      ║
-- ║      where the search result is readable (browse/apply-  ║
-- ║      phase secrecy is lifted once joined). Every field   ║
-- ║      is still issecretvalue-guarded and the whole lookup ║
-- ║      pcall'd: a secret can only skip the prompt, never   ║
-- ║      error. So the dungeon name is always plain, and the ║
-- ║      row may measure it (the measure takes no secrets).  ║
-- ║    * The secure button is created ONCE and ALWAYS out of ║
-- ║      combat: normally at enable, else on the next        ║
-- ║      PLAYER_REGEN_ENABLED. NOTHING may call BuildPopup   ║
-- ║      during combat -- it writes SetAttribute("type",     ║
-- ║      "spell") on a protected frame. Only the "spell"     ║
-- ║      attribute is rewritten later, also only out of      ║
-- ║      combat (deferred when a join lands mid-combat).     ║
-- ║    * No Blizzard Group Finder frame is ever hooked or    ║
-- ║      SetScript-ed.                                       ║
-- ║    * The role reads are issecretvalue-guarded and the    ║
-- ║      role row is only ever written out of combat.        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class LFGReminder: AceModule, AceEvent-3.0
local LR = KitnEssentials:NewModule("LFGReminder", "AceEvent-3.0")

local type = type
local pcall = pcall
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local C_SpellBook = C_SpellBook
local SpellBookBank_Player = Enum.SpellBookSpellBank.Player
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local GetNumGroupMembers = GetNumGroupMembers
local IsInInstance = IsInInstance
local UIParent = UIParent
local C_Spell = C_Spell
-- Indexed off _G, unlike its neighbors: C_LFGList is the one API this file
-- touches that is NOT in .luacheckrc's allowlist, so a bare capture is a
-- W113 (accessing undefined global) and every task gates on zero warnings.
-- Modules/Skinning/Frames/LFG.lua already reaches this same API this way.
-- Do NOT widen .luacheckrc instead.
local C_LFGList = _G.C_LFGList
local GameTooltip = GameTooltip
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local GetSpecializationRole = GetSpecializationRole
-- Both secret predicates get the same fallback: an environment missing one
-- would be missing both, and a bare call to either throws.
local issecretvalue = issecretvalue or function() return false end
local issecrettable = issecrettable or function() return false end

-- Challenge-mode map ID -> every teleport spell that reaches it (faction
-- variants, re-issued IDs); maps that share one entrance share one teleport.
-- The player's own spell is picked at use, so the table carries every season.
local PORTALS_BY_MAP = {
    [2] = { 131204 }, -- Temple of the Jade Serpent
    [56] = { 131205 }, -- Stormstout Brewery
    [57] = { 131225 }, -- Gate of the Setting Sun
    [58] = { 131206 }, -- Shado-Pan Monastery
    [59] = { 131228 }, -- Siege of Niuzao Temple
    [60] = { 131222 }, -- Mogu'shan Palace
    [76] = { 131232 }, -- Scholomance
    [77] = { 131231 }, -- Scarlet Halls
    [78] = { 131229 }, -- Scarlet Monastery
    [161] = { 159898, 1254557 }, -- Skyreach
    [163] = { 159895 }, -- Bloodmaul Slag Mines
    [164] = { 159897 }, -- Auchindoun
    [165] = { 159899 }, -- Shadowmoon Burial Grounds
    [166] = { 159900 }, -- Grimrail Depot
    [167] = { 159902 }, -- Upper Blackrock Spire
    [168] = { 159901 }, -- The Everbloom
    [169] = { 159896 }, -- Iron Docks
    [198] = { 424163 }, -- Darkheart Thicket
    [199] = { 424153 }, -- Black Rook Hold
    [200] = { 393764 }, -- Halls of Valor
    [206] = { 410078 }, -- Neltharion's Lair
    [210] = { 393766 }, -- Court of Stars
    [227] = { 373262 }, -- Return to Karazhan: Lower
    [234] = { 373262 }, -- Return to Karazhan: Upper
    [239] = { 1254551 }, -- Seat of the Triumvirate
    [244] = { 424187 }, -- Atal'Dazar
    [245] = { 410071 }, -- Freehold
    [247] = { 467553, 467555 }, -- The MOTHERLODE!!
    [248] = { 424167 }, -- Waycrest Manor
    [249] = { 1286831 }, -- Kings' Rest
    [250] = { 1286828 }, -- Temple of Sethraliss
    [251] = { 410074 }, -- The Underrot
    [353] = { 445418, 464256 }, -- Siege of Boralus
    [369] = { 373274 }, -- Operation: Mechagon - Junkyard
    [370] = { 373274 }, -- Operation: Mechagon - Workshop
    [375] = { 354464 }, -- Mists of Tirna Scithe
    [376] = { 354462 }, -- The Necrotic Wake
    [377] = { 354468 }, -- De Other Side
    [378] = { 354465 }, -- Halls of Atonement
    [379] = { 354463 }, -- Plaguefall
    [380] = { 354469 }, -- Sanguine Depths
    [381] = { 354466 }, -- Spires of Ascension
    [382] = { 354467 }, -- Theater of Pain
    [391] = { 367416 }, -- Tazavesh: Streets of Wonder
    [392] = { 367416 }, -- Tazavesh: So'leah's Gambit
    [399] = { 393256 }, -- Ruby Life Pools
    [400] = { 393262 }, -- The Nokhud Offensive
    [401] = { 393279 }, -- The Azure Vault
    [402] = { 393273 }, -- Algeth'ar Academy
    [403] = { 393222 }, -- Uldaman: Legacy of Tyr
    [404] = { 393276 }, -- Neltharus
    [405] = { 393267 }, -- Brackenhide Hollow
    [406] = { 393283 }, -- Halls of Infusion
    [438] = { 410080 }, -- The Vortex Pinnacle
    [456] = { 424142 }, -- Throne of the Tides
    [463] = { 424197 }, -- Dawn of the Infinite: Galakrond's Fall
    [464] = { 424197 }, -- Dawn of the Infinite: Murozond's Rise
    [499] = { 445444 }, -- Priory of the Sacred Flame
    [500] = { 445443 }, -- The Rookery
    [501] = { 445269 }, -- The Stonevault
    [502] = { 445416 }, -- City of Threads
    [503] = { 445417 }, -- Ara-Kara, City of Echoes
    [504] = { 445441 }, -- Darkflame Cleft
    [505] = { 445414 }, -- The Dawnbreaker
    [506] = { 445440, 467546 }, -- Cinderbrew Meadery
    [507] = { 445424 }, -- Grim Batol
    [525] = { 1216786 }, -- Operation: Floodgate
    [542] = { 1237215 }, -- Eco-Dome Al'dani
    [556] = { 1254555 }, -- Pit of Saron
    [557] = { 1254400 }, -- Windrunner Spire
    [558] = { 1254572 }, -- Magisters' Terrace
    [559] = { 1254563 }, -- Nexus-Point Xenas
    [560] = { 1254559 }, -- Maisara Caverns
    [583] = { 1254551 }, -- Seat of the Triumvirate
    [584] = { 1286801 }, -- The Blinding Vale
    [585] = { 1286804 }, -- Voidscar Arena
    [586] = { 1286807 }, -- Den of Nalorakk
    [587] = { 1286809 }, -- Murder Row
    [588] = { 1286812 }, -- Altar of Fangs
}

-- Teleport spell -> every map it reaches, lowest first. Built on first use.
local mapsBySpell

local function MapsForSpell(spellID)
    if not mapsBySpell then
        mapsBySpell = {}
        for mapID, spells in pairs(PORTALS_BY_MAP) do
            for _, sid in ipairs(spells) do
                local maps = mapsBySpell[sid]
                if not maps then
                    maps = {}
                    mapsBySpell[sid] = maps
                end
                maps[#maps + 1] = mapID
            end
        end
        for _, maps in pairs(mapsBySpell) do table.sort(maps) end
    end
    return mapsBySpell[spellID]
end

-- The dungeon a plain teleport spell ID leads to. A spell two maps share
-- resolves to the one in the inSeason set, else the lowest ID, so the drawn
-- name does not change between calls.
local function MapForPortalSpell(spellID, inSeason)
    local maps = MapsForSpell(spellID)
    if not maps then return nil end
    if inSeason then
        for _, mapID in ipairs(maps) do
            if inSeason[mapID] then return mapID end
        end
    end
    return maps[1]
end

-- The player's own teleport for a map: the first of its spells isKnown
-- accepts, else the first, which the row draws as not learned.
local function PickOwnPortal(mapID, isKnown)
    local spells = mapID and PORTALS_BY_MAP[mapID]
    if not spells then return nil end
    for _, sid in ipairs(spells) do
        if isKnown(sid) then return sid end
    end
    return spells[1]
end

local function KnowsSpell(spellID)
    return C_SpellBook.IsSpellKnown(spellID, SpellBookBank_Player) == true
end

-- A Group Finder activity name, difficulty suffix and all, to the player's
-- teleport, the clean dungeon name and its map. The name is matched against
-- the client's own map list, so it needs no per-season table.
local function ResolveGroupFinderPortal(fullName)
    if type(fullName) ~= "string" then return nil end
    local name = fullName:gsub("%s*%b()%s*$", "")
    local mapID = KE:GetChallengeMapIDByName(name)
    local spellID = PickOwnPortal(mapID, KnowsSpell)
    if not spellID then return nil end
    return spellID, name, mapID
end

-- Test seams: pure file-locals with no other handle.
LR._MapForPortalSpell = MapForPortalSpell
LR._PickOwnPortal = PickOwnPortal
LR._ResolveGroupFinderPortal = ResolveGroupFinderPortal

-- Keyed by the role strings Blizzard's role APIs return; membership is what
-- makes a read a usable role.
local ROLE_LABEL = { TANK = "Tank", HEALER = "Healer", DAMAGER = "Damage" }

-- Tested for secrecy before anything else: a secret cannot index a table.
local function UsableRole(role)
    if issecretvalue(role) or type(role) ~= "string" then return nil end
    return ROLE_LABEL[role] and role or nil
end

-- The application role is the one the player was accepted as; the assigned
-- role is the fallback, and the only source on the leader path.
local function PickRole(applicationRole, assignedRole)
    return UsableRole(applicationRole) or UsableRole(assignedRole)
end

LR._PickRole = PickRole

-- Row geometry: the name block and a 14 px role line, centered in a row at
-- least 56 px tall.
local ROW_MIN_H = 56
local ROW_PAD   = 8
local LINE_GAP  = 4
local LINE2_H   = 14

local function MeasuredWidth(measure, s)
    local w = measure(s)
    return type(w) == "number" and w or 0
end

-- A word wider than the column breaks between whole UTF-8 characters, so
-- width / column undercounts its lines. Returns the lines the word spans and
-- the text on its last line.
local function PackGlyphs(word, width, measure)
    local lines, current = 1, ""
    for glyph in word:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        local candidate = current .. glyph
        if current ~= "" and MeasuredWidth(measure, candidate) > width then
            lines = lines + 1
            current = glyph
        else
            current = candidate
        end
    end
    return lines, current
end

-- Lines a word-wrapping FontString gives text in a column `width` wide;
-- measure(s) is the unbounded width of s. Words pack greedily at spaces; the
-- next word may continue on the last line of a broken one.
local function NameLineCount(text, width, measure)
    if type(text) ~= "string" then return 1 end
    local lines, current = 0, nil
    for word in text:gmatch("%S+") do
        local candidate = current and (current .. " " .. word) or word
        if MeasuredWidth(measure, candidate) <= width then
            current = candidate
        else
            if current then lines = lines + 1 end
            if MeasuredWidth(measure, word) > width then
                local wordLines, rest = PackGlyphs(word, width, measure)
                lines = lines + wordLines - 1
                current = rest
            else
                current = word
            end
        end
    end
    if current then lines = lines + 1 end
    return math.max(lines, 1)
end

-- Row height and the name's top offset for a name of `lines` lines.
local function RowLayout(lines, lineH)
    local textH = lines * lineH + LINE_GAP + LINE2_H
    local rowH = math.max(ROW_MIN_H, textH + ROW_PAD * 2)
    return rowH, math.floor((rowH - textH) / 2)
end

-- Challenge-mode art for a map, or nil: no map, or a map without art (the
-- client's own dungeon list treats 0 as none).
local function ResolveDungeonArt(mapID)
    if not (mapID and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo) then return nil end
    local ok, _, _, _, texture = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
    if not ok or type(texture) ~= "number" or texture == 0 then return nil end
    return texture
end

LR._NameLineCount = NameLineCount
LR._RowLayout = RowLayout
LR._ResolveDungeonArt = ResolveDungeonArt

-- The prompt IS a teleport button, so it is pointless once the teleport is
-- on cooldown -- which it always is straight after using it.
--
-- C_Spell.GetSpellCooldown is SecretWhenCooldownsRestricted and neither
-- startTime nor duration carries NeverSecret, so comparing duration against
-- a number is the very pattern the button-visual path already avoids.
-- isActive and isOnGCD on the same struct ARE NeverSecret: isActive reliably
-- says whether a cooldown exists; isOnGCD == true can exclude the GCD, but
-- false/nil is not decisive outside SPELL_UPDATE_COOLDOWN.
-- GetSpellCooldownDuration is not usable here: it hands back an object even
-- when the spell is ready.
--
-- Fails OPEN: an unreadable cooldown offers a button that may not work,
-- which beats hiding one that would have.
local function TeleportOnCooldown(spellID)
    if not (spellID and C_Spell and C_Spell.GetSpellCooldown) then return false end
    local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
    if not ok or type(info) ~= "table" then return false end
    if info.isActive ~= true then return false end -- NeverSecret
    if info.isOnGCD == true then return false end  -- NeverSecret: the GCD only
    -- isOnGCD is only trustworthy inside SPELL_UPDATE_COOLDOWN handling, and
    -- this also runs from LFG and regen paths -- so false/nil never decides
    -- on its own. A plain duration settles it; a secret one fails OPEN (a
    -- button that may not work beats hiding one that would).
    local dur = info.duration
    if KE:IsSecretValue(dur) then return false end
    return type(dur) == "number" and dur > 1.5
end

-- State (plain upvalues; never keyed by a possibly-secret resultID)
local popup, secureBtn
local pendingSpellID       -- resolved teleport spell (static integer)
local pendingName          -- dungeon display name (clean)
local pendingMapID         -- challenge-mode map of the pending prompt
local pendingShow          -- join landed in combat; show on REGEN_ENABLED
local pendingHide          -- hide requested in combat; flush on REGEN_ENABLED
local combatHidden         -- the hide came from combat, not from the user
local pendingRole          -- role captured with the prompt, or nil
local shownRole            -- role the popup is drawing, or nil
local previewState         -- settings preview: nil, "empty", or "prompt" (a live prompt waits behind it)


local BuildPopup, ShowPrompt, HidePrompt, ClearPending
local UpdateButtonVisuals, ResolveDungeon
local SavePosition, ApplySavedPosition, ApplyPopupLayout

-- Read-only test seams. The pending state stays in the upvalues above --
-- these expose it without creating a second source of truth that could
-- drift from it.
function LR:_GetPendingSpellID()     return pendingSpellID end
function LR:_GetPendingName()        return pendingName end

-- The X close. It ends the prompt rather than hiding it, so nothing that
-- brings a hidden prompt back (the combat re-show, a preview closing) can
-- show or re-arm it. The combat hide calls HidePrompt alone, because the
-- end of combat must bring the prompt back.
local function ClosePrompt()
    ClearPending()
    -- On the preview, X also ends the preview's hold, so a later prompt is
    -- not kept behind a preview that is no longer on screen.
    previewState = nil
    HidePrompt()
end

LR._ClosePrompt = ClosePrompt

function LR:UpdateDB()
    if KE.db and KE.db.profile then
        self.db = KE.db.profile.LFGReminder
    end
end

-- ANCHOR_RIGHT places the tooltip from the owner's rect without reconciling
-- the two scales, and this popup carries its own SetScale (default 1.05, user
-- adjustable). At any scale but 1.0 the tooltip lands offset from the button.
-- Anchor it explicitly instead: SetPoint resolves across differing scales.
local function ShowTip(owner, text)
    GameTooltip:SetOwner(owner, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("TOPLEFT", owner, "TOPRIGHT", 4, 0)
    GameTooltip:SetText(text, 1, 1, 1, 1, true)
    GameTooltip:Show()
end

SavePosition = function()
    if not (popup and LR.db) then return end
    local p, _, rp, x, yo = popup:GetPoint()
    if p then LR.db.Pos = { p = p, rp = rp, x = x, y = yo } end
end

ApplySavedPosition = function()
    if not popup then return end
    popup:ClearAllPoints()
    local pos = LR.db and LR.db.Pos
    if pos and pos.p then
        popup:SetPoint(pos.p, UIParent, pos.rp or pos.p, pos.x or 0, pos.y or 0)
    else
        popup:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    end
end

-- Popup geometry. The row sits below the header; the footer line under it
-- holds "Disable Feature" and the watermark.
local POPUP_W     = 210
local TITLE_H     = 27
local PAD         = 10
local BTN_TOP     = TITLE_H + 11
local ART_SIZE    = 40
local ART_PAD     = 8
local TEXT_LEFT   = ART_PAD + ART_SIZE + ART_PAD
local TEXT_RIGHT  = 6
local TEXT_W      = POPUP_W - PAD * 2 - TEXT_LEFT - TEXT_RIGHT
local NAME_LINE_H = 17  -- used when the font reports no line height
local FOOT_GAP    = 8
local FOOT_H      = 16
local FOOT_PAD    = 8
local DISABLE_W   = 90  -- used when the label reports no width

-- Dungeon name the popup is drawing; every show path sets it before layout.
---@type string?
local shownName = nil

local function MeasureName(s)
    return secureBtn._name:GetUnboundedStringWidthForText(s)
end

-- The one writer of the popup's geometry: the row height, the text inside the
-- secure button, the footer and the popup height. The popup parents a secure
-- button, so every caller runs out of combat.
ApplyPopupLayout = function()
    if not popup then return end
    local showDisable = not LR.db or LR.db.ShowDisable ~= false
    local showRole = shownRole ~= nil and (not LR.db or LR.db.ShowRole ~= false)

    local nameFS = secureBtn._name
    nameFS:SetText(shownName or "")
    local lineH = nameFS:GetLineHeight()
    lineH = (type(lineH) == "number" and lineH > 0) and math.ceil(lineH) or NAME_LINE_H
    local lines = NameLineCount(shownName, TEXT_W, MeasureName)
    local rowH, nameTop = RowLayout(lines, lineH)
    local line2Y = -(nameTop + lines * lineH + LINE_GAP + LINE2_H / 2)

    secureBtn:SetHeight(rowH)
    nameFS:ClearAllPoints()
    nameFS:SetPoint("TOPLEFT", secureBtn, "TOPLEFT", TEXT_LEFT, -nameTop)
    nameFS:SetPoint("TOPRIGHT", secureBtn, "TOPRIGHT", -TEXT_RIGHT, -nameTop)

    local roleFS = secureBtn._role
    if showRole then
        local set = KE.Skins and KE.Skins.GetRoleIconSet and KE.Skins.GetRoleIconSet() or "modern"
        local icons = KE.BuildChatRoleIconStrings and KE.BuildChatRoleIconStrings(set)
        local icon = icons and icons[shownRole]
        local word = ROLE_LABEL[shownRole]
        roleFS:SetText(icon and (icon .. " " .. word) or word)
    end
    roleFS:ClearAllPoints()
    roleFS:SetPoint("LEFT", secureBtn, "TOPLEFT", TEXT_LEFT, line2Y)
    roleFS:SetShown(showRole)

    -- "Teleport" ends the role line, or starts it when no role shows.
    local label = secureBtn._label
    label:ClearAllPoints()
    if showRole then
        label:SetPoint("RIGHT", secureBtn, "TOPRIGHT", -TEXT_RIGHT, line2Y)
        label:SetJustifyH("RIGHT")
    else
        label:SetPoint("LEFT", secureBtn, "TOPLEFT", TEXT_LEFT, line2Y)
        label:SetJustifyH("LEFT")
    end

    local footTop = BTN_TOP + rowH + FOOT_GAP
    local disableBtn = popup._disableBtn
    local disableW = disableBtn._label:GetUnboundedStringWidth()
    disableW = (type(disableW) == "number" and disableW > 0) and math.ceil(disableW) or DISABLE_W
    disableBtn:SetSize(disableW, FOOT_H)
    disableBtn:ClearAllPoints()
    disableBtn:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD, -footTop)
    disableBtn:SetShown(showDisable)
    popup._mark:ClearAllPoints()
    popup._mark:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -PAD, -footTop)

    popup:SetHeight(footTop + FOOT_H + FOOT_PAD)
end

-- Build the popup + secure button (once, out of combat)
BuildPopup = function()
    if popup then return popup end
    -- Resolved HERE, not at file scope: Dungeons.xml loads before
    -- Skinning.xml in the toc, so a file-top capture
    -- is nil and every skin call silently no-ops.
    local S = KE.Skins

    popup = CreateFrame("Frame", "KE_LFGReminderPopup", UIParent)
    popup:SetWidth(POPUP_W)
    popup:SetFrameStrata("DIALOG")
    popup:SetMovable(true)
    popup:EnableMouse(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", function(s) s:StartMoving() end)
    popup:SetScript("OnDragStop", function(s) s:StopMovingOrSizing(); SavePosition() end)

    if S and S.Backdrop then S.Backdrop(popup) end

    -- Header bar with the static title
    local hdrBg = popup:CreateTexture(nil, "BORDER")
    hdrBg:SetColorTexture(0, 0, 0, 0.25)
    hdrBg:SetPoint("TOPLEFT", 1, -1); hdrBg:SetPoint("TOPRIGHT", -1, 0); hdrBg:SetHeight(TITLE_H)

    local title = popup:CreateFontString(nil, "OVERLAY")
    if S and S.SetFont then S.SetFont(title, 11, "") end
    title:SetPoint("TOPLEFT", PAD, -8)
    title:SetPoint("TOPRIGHT", -(PAD + 16), -8)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetText("LFG Reminder")

    -- Close (X) in the header
    local xBtn = CreateFrame("Button", nil, popup)
    xBtn:SetSize(16, 16)
    xBtn:SetPoint("RIGHT", hdrBg, "RIGHT", -6, 0)
    if S and S.CloseButton then S.CloseButton(xBtn, 12) end
    xBtn:SetScript("OnClick", ClosePrompt)

    -- Secure teleport button (once; type + clicks set here and NEVER
    -- touched again; only "spell" is rewritten, out of combat).
    secureBtn = CreateFrame("Button", "KE_LFGReminderTeleport", popup, "SecureActionButtonTemplate")
    -- ApplyPopupLayout sets the height: the row grows with the name.
    secureBtn:SetWidth(POPUP_W - PAD * 2)
    -- A protected frame can only be anchored to another FRAME, never a
    -- region -- anchor to the popup, below the header.
    secureBtn:SetPoint("TOP", popup, "TOP", 0, -BTN_TOP)
    secureBtn:RegisterForClicks("AnyUp", "AnyDown")
    secureBtn:SetAttribute("type", "spell")

    -- A child frame parented to the secure button is legal, and the button
    -- is only ever created out of combat.
    if S and S.Backdrop then
        S.Backdrop(secureBtn)
    else
        local btnBg = secureBtn:CreateTexture(nil, "BACKGROUND")
        btnBg:SetAllPoints()
        btnBg:SetColorTexture(0.04, 0.04, 0.06, 0.9)
    end

    local icon = secureBtn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ART_SIZE, ART_SIZE)
    icon:SetPoint("LEFT", ART_PAD, 0)
    if S and S.Icon then S.Icon(icon, true) else icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    secureBtn._icon = icon

    -- Anchored top-left and top-right only, with no height and no line limit,
    -- so a long name wraps instead of truncating.
    local nameFS = secureBtn:CreateFontString(nil, "OVERLAY")
    if S and S.SetFont then S.SetFont(nameFS, 14, "") end
    nameFS:SetJustifyH("LEFT")
    nameFS:SetWordWrap(true)
    nameFS:SetNonSpaceWrap(true)
    secureBtn._name = nameFS

    local roleFS = secureBtn:CreateFontString(nil, "OVERLAY")
    if S and S.SetFont then S.SetFont(roleFS, 12, "") end
    roleFS:SetJustifyH("LEFT")
    roleFS:SetWordWrap(false)
    roleFS:Hide()
    secureBtn._role = roleFS

    local btnLabel = secureBtn:CreateFontString(nil, "OVERLAY")
    if S and S.SetFont then S.SetFont(btnLabel, 10, "") end
    btnLabel:SetWordWrap(false)
    btnLabel:SetText("Teleport")
    secureBtn._label = btnLabel

    local hover = secureBtn:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.12)

    -- Cooldown inherits the button's protection: anchor to the button
    -- FRAME matching the icon's rect, never to the icon texture.
    local cd = CreateFrame("Cooldown", nil, secureBtn, "CooldownFrameTemplate")
    cd:SetPoint("LEFT", secureBtn, "LEFT", ART_PAD, 0)
    cd:SetSize(ART_SIZE, ART_SIZE)
    cd:SetHideCountdownNumbers(true)
    cd:SetDrawSwipe(true); cd:SetDrawBling(false); cd:SetDrawEdge(false)
    secureBtn._cd = cd

    secureBtn:SetScript("OnEnter", function(self)
        local sid = pendingSpellID
        if not sid then return end
        if not C_SpellBook.IsSpellKnown(sid, SpellBookBank_Player) then
            ShowTip(self, "You have not learned this dungeon teleport yet.")
            return
        end
        if TeleportOnCooldown(sid) then
            ShowTip(self, "Teleport on Cooldown")
        else
            ShowTip(self, "Teleport to " .. (pendingName or "dungeon"))
        end
    end)
    secureBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- "Disable Feature" text: turns the whole feature off immediately
    local disableBtn = CreateFrame("Button", nil, popup)
    local disableLbl = disableBtn:CreateFontString(nil, "OVERLAY")
    if S and S.SetFont then S.SetFont(disableLbl, 10, "") end
    disableLbl:SetAllPoints()
    disableLbl:SetJustifyH("LEFT")
    disableLbl:SetText("Disable Feature")
    disableLbl:SetTextColor(0.6, 0.6, 0.6, 1)
    disableBtn:SetScript("OnEnter", function() disableLbl:SetTextColor(1, 0.3, 0.3, 1) end)
    disableBtn:SetScript("OnLeave", function() disableLbl:SetTextColor(0.6, 0.6, 0.6, 1) end)
    disableBtn._label = disableLbl
    disableBtn:SetScript("OnClick", function()
        if LR.db then LR.db.Enabled = false end
        KitnEssentials:DisableModule("LFGReminder")
        -- The DB write and the disable both land, but nothing redraws an
        -- open config page, so its master toggle kept showing ON until a
        -- reload. EnableModule/DisableModule's posthook only refreshes
        -- previews, not content. The IsShown guard is load-bearing:
        -- RefreshContent refuses to rebuild while hidden and defers instead,
        -- because a hidden rebuild orphaned frames in a past leak.
        if KE.GUIFrame and KE.GUIFrame:IsShown() then
            KE.GUIFrame:RefreshContent()
        end
    end)
    popup._disableBtn = disableBtn

    local mark = popup:CreateFontString(nil, "OVERLAY")
    if S and S.SetFont then S.SetFont(mark, 10, "") end
    mark:SetText("KitnEssentials")
    mark:SetTextColor(1, 1, 1, 0.22)
    popup._mark = mark

    -- Intentionally NOT Escape-closable: stays until teleport, dungeon
    -- entry, group leave, or disable.
    popup:SetScale((LR.db and LR.db.Scale) or 1.05)
    ApplySavedPosition()
    ApplyPopupLayout()
    popup:Hide()
    return popup
end

-- GetSpellInfo may return nothing; the slot then shows this, never an empty box.
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Dungeon art when the map has some and it loads, else the teleport's icon.
-- Always writes, so one dungeon's image never carries over to the next.
local function SetRowIcon(mapID, spellID)
    local icon = secureBtn._icon
    local art = ResolveDungeonArt(mapID)
    if art and icon:SetTexture(art) then return end
    local info = spellID and C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    icon:SetTexture(info and info.iconID or FALLBACK_ICON)
end

local function SetRowKnown(known)
    local icon = secureBtn._icon
    icon:SetDesaturated(not known)
    icon:SetAlpha(known and 1 or 0.4)
    local nc = known and 1 or 0.5
    secureBtn._name:SetTextColor(nc, nc, nc, 1)
    secureBtn._label:SetTextColor(0.55, 0.55, 0.55, known and 1 or 0.5)
end

UpdateButtonVisuals = function()
    if not secureBtn or not pendingSpellID then return end
    local sid = pendingSpellID
    SetRowIcon(pendingMapID, sid)
    local known = C_SpellBook.IsSpellKnown(sid, SpellBookBank_Player)
    SetRowKnown(known)
    if known then
        -- Duration object, not the startTime/duration pair: those two carry no
        -- NeverSecret flag, so under SecretWhenCooldownsRestricted the
        -- comparison throws and a live cooldown renders as ready.
        -- GetSpellCooldownDuration is AllowedWhenTainted and returns a handle we
        -- only truth-test, never read (SpellDocumentation.lua). Same
        -- shape as Modules/Combat/Cursor.lua.
        local duration = C_Spell and C_Spell.GetSpellCooldownDuration
            and C_Spell.GetSpellCooldownDuration(sid)
        if duration then
            secureBtn._cd:SetCooldownFromDurationObject(duration, true)
        else
            secureBtn._cd:Clear()
        end
    else
        secureBtn._cd:Clear()
    end
end

-- Resolve the accepted dungeon via a CLEAN string chain. The pcall below is
-- LOAD-BEARING, not belt-and-braces: GetSearchResultInfo and
-- GetActivityInfoTable are both SecretArguments = "AllowedWhenUntainted"
-- (LFGListInfoDocumentation.lua), so a secret resultID throws.
ResolveDungeon = function(resultID)
    if not (C_LFGList and C_LFGList.GetSearchResultInfo) then return end
    local wantRole = LR.db and LR.db.ShowRole ~= false
    local applicationRole
    pcall(function()
        local info = C_LFGList.GetSearchResultInfo(resultID)
        if type(info) ~= "table" then return end
        local activityID = info.activityID
        -- issecretTABLE, not issecretvalue: a table can be non-secret itself
        -- while its reads produce secrets (FrameScriptDocumentation.lua).
        -- This is the only live path -- LfgSearchResultData has no
        -- activityID field in 12.0.7 (LFGListInfoDocumentation.lua).
        if activityID == nil and info.activityIDs and not issecrettable(info.activityIDs) then
            activityID = info.activityIDs[1]
        end
        if issecretvalue(activityID) or activityID == nil then return end
        local act = C_LFGList.GetActivityInfoTable(activityID)
        if type(act) ~= "table" then return end
        local fullName = act.fullName
        if type(fullName) ~= "string" or issecretvalue(fullName) then return end
        local spellID, name, mapID = ResolveGroupFinderPortal(fullName)
        if spellID then
            pendingSpellID, pendingName, pendingMapID = spellID, name, mapID
            -- Last, so an error here can cost the role but never the prompt.
            if wantRole and C_LFGList.GetApplicationInfo then
                applicationRole = select(5, C_LFGList.GetApplicationInfo(resultID))
            end
        end
    end)
    if pendingSpellID and wantRole then
        pendingRole = PickRole(applicationRole,
            UnitGroupRolesAssigned and UnitGroupRolesAssigned("player"))
    end
end

-- LFG_LIST_JOINED_GROUP only fires for someone who APPLIED, so the person
-- who made the group never got the prompt. Arm while our own listing is up,
-- and fire when that listing ends WITH a full group: the game delists
-- automatically at that point, which is when the group is actually ready to
-- move. A listing that ends any other way -- canceled by hand, group broke
-- up -- leaves the group short and prompts nothing.
local armedSpellID, armedName, armedMapID, armedPending

local function GroupIsFull()
    if IsInRaid() then return false end
    return GetNumGroupMembers() >= 5
end

local function ClearArmed()
    armedSpellID, armedName, armedMapID, armedPending = nil, nil, nil, nil
end

-- Same clean-string chain as ResolveDungeon, against our own active entry.
-- The active-entry read can return secret data in chat-messaging lockdown,
-- so the guards are not optional.
local function ResolveListing()
    if not (C_LFGList and C_LFGList.GetActiveEntryInfo) then return nil end
    local spellID, name, mapID
    pcall(function()
        local info = C_LFGList.GetActiveEntryInfo()
        if type(info) ~= "table" then return end
        local activityID = info.activityID
        if activityID == nil and info.activityIDs and not issecrettable(info.activityIDs) then
            activityID = info.activityIDs[1]
        end
        if activityID == nil or issecretvalue(activityID) then return end
        local act = C_LFGList.GetActivityInfoTable(activityID)
        if type(act) ~= "table" then return end
        local fullName = act.fullName
        if type(fullName) ~= "string" or issecretvalue(fullName) then return end
        spellID, name, mapID = ResolveGroupFinderPortal(fullName)
    end)
    return spellID, name, mapID
end

-- Every popup:Show() pairs with registering SPELL_UPDATE_COOLDOWN, and every
-- popup:Hide() with unregistering it, regardless of which path reaches the
-- popup (real prompt, the deferred regen re-show, or the preview) -- shared
-- helpers keep that symmetric instead of repeating the pair per site.
local function ShowPopup()
    popup:Show()
    LR:RegisterEvent("SPELL_UPDATE_COOLDOWN")
end

local function HidePopup()
    popup:Hide()
    LR:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
end

ShowPrompt = function()
    if not (LR.db and LR.db.Enabled ~= false) or not pendingSpellID then return end
    if TeleportOnCooldown(pendingSpellID) then return end
    if InCombatLockdown() then
        -- Deferral comes BEFORE BuildPopup, because BuildPopup calls
        -- secureBtn:SetAttribute("type", "spell") on a protected frame,
        -- which combat blocks -- and OnEnable skips the build in
        -- combat, so this path IS reachable with no popup at all: enable or
        -- /reload during combat, then join a group before it ends.
        -- PLAYER_REGEN_ENABLED builds it and finishes the show.
        pendingShow = true
        pendingHide = nil  -- a deferred show supersedes a deferred hide
        return
    end
    if previewState then
        -- The settings preview owns the popup and keeps the button unarmed;
        -- HidePreview shows the prompt when the preview closes.
        previewState = "prompt"
        return
    end
    BuildPopup()
    shownName = pendingName
    shownRole = pendingRole
    ApplyPopupLayout()
    -- The only write that arms the button, so the preview hold above covers
    -- every path that arms it.
    secureBtn:SetAttribute("spell", pendingSpellID)  -- static integer
    pendingHide = nil
    UpdateButtonVisuals()
    ShowPopup()
end

HidePrompt = function()
    pendingShow = nil
    -- popup parents a SecureActionButton, so popup:Hide() is protected
    -- in combat. Already hidden = nothing to do (the common case when
    -- leaving an instance in combat); genuinely shown in combat = defer.
    if not (popup and popup:IsShown()) then pendingHide = nil; return end
    if InCombatLockdown() then pendingHide = true; return end
    pendingHide = nil
    HidePopup()
end

ClearPending = function()
    pendingSpellID     = nil
    pendingName        = nil
    pendingMapID       = nil
    pendingRole        = nil
    -- A combat join sets pendingShow; a group that breaks before combat ends
    -- must leave PLAYER_REGEN_ENABLED nothing to build or arm.
    pendingShow        = nil
    -- Whatever combat took away is no longer wanted either: this runs on
    -- group-leave and instance-entry, both of which invalidate the prompt.
    combatHidden       = nil
end

-- Live refresh for the GUI (scale, disable and role rows). The popup parents
-- a secure button, so its scale and height are protected in combat.
function LR:RefreshVisuals()
    if not popup or InCombatLockdown() then return end
    popup:SetScale((self.db and self.db.Scale) or 1.05)
    ApplyPopupLayout()
end

-- BuildPopup returns an existing popup untouched, so a profile switch reaches
-- it only through here. OnEnable calls it itself: ProfileManager skips
-- ApplySettings for modules it just enabled. The popup parents a secure
-- button, so its anchors and scale are protected in combat.
function LR:ApplySettings()
    if not popup or InCombatLockdown() then return end
    self:RefreshVisuals()
    ApplySavedPosition()
end

function LR:LFG_LIST_JOINED_GROUP(_, resultID)
    -- Fires the moment the player joins a Group Finder group; unlike
    -- browse/apply, the search result is readable here. Capture
    -- immediately -- the result can expire shortly after joining.
    ClearPending()
    ResolveDungeon(resultID)
    if pendingSpellID then ShowPrompt() end
end

function LR:LFG_LIST_ACTIVE_ENTRY_UPDATE()
    local spellID, name, mapID = ResolveListing()
    if spellID then
        armedSpellID, armedName, armedMapID, armedPending = spellID, name, mapID, nil
        return
    end
    -- Entry gone. Arm the check rather than deciding here: the fifth player
    -- joining can update the listing before the roster, so the member count
    -- may still read four at this instant. GROUP_ROSTER_UPDATE retries it.
    if armedSpellID then
        armedPending = true
        self:TryLeaderPrompt()
    end
end

function LR:TryLeaderPrompt()
    if not (armedPending and armedSpellID) then return end
    if not GroupIsFull() then return end
    pendingSpellID, pendingName, pendingMapID = armedSpellID, armedName, armedMapID
    pendingRole = nil
    if self.db and self.db.ShowRole ~= false then
        pendingRole = PickRole(nil, UnitGroupRolesAssigned and UnitGroupRolesAssigned("player"))
    end
    ClearArmed()
    ShowPrompt()
end

-- The live prompt is no longer wanted. While the settings preview is up the
-- popup is the preview's and the page still shows it, so only the prompt
-- waiting behind it is dropped.
local function DropPrompt()
    if previewState then
        previewState = "empty"
        return
    end
    HidePrompt()
end

function LR:SPELL_UPDATE_COOLDOWN()
    if not (popup and popup:IsShown()) then return end
    if TeleportOnCooldown(pendingSpellID) then DropPrompt() end
end

function LR:GROUP_ROSTER_UPDATE()
    if not IsInGroup() then
        ClearArmed()
        ClearPending(); DropPrompt()
        return
    end
    self:TryLeaderPrompt()
end

function LR:CheckInstance()
    local inInstance, instanceType = IsInInstance()
    if inInstance and instanceType == "party" then
        ClearPending(); DropPrompt()
    end
end

function LR:PLAYER_REGEN_DISABLED()
    -- Teleports cannot be cast in combat, so the prompt goes, and
    -- PLAYER_REGEN_ENABLED brings it back while it is still live. Lockdown
    -- has not begun when this event fires, so the hide normally lands at
    -- once; HidePrompt defers it if lockdown has begun. A prompt waiting
    -- behind the settings preview passes to that same re-show.
    combatHidden = previewState == "prompt"
        or (popup and popup:IsShown() and not previewState) or nil
    if previewState then previewState = "empty" end
    HidePrompt()
end

function LR:PLAYER_REGEN_ENABLED()
    -- Bring the prompt back if it is still wanted: a join that landed in
    -- combat, or a shown prompt combat hid. Leaving the group or entering the
    -- dungeon ran ClearPending, which clears pendingSpellID and both flags,
    -- so a stale prompt never gets here. ShowPrompt refuses a disabled module
    -- or a teleport on cooldown, builds the popup if combat kept it from being
    -- built, waits behind a settings preview, and otherwise arms the spell.
    local wantShow = pendingShow or combatHidden
    pendingShow, combatHidden = nil, nil
    if wantShow then ShowPrompt() end
    -- A hide requested during lockdown that no show superseded.
    if pendingHide then
        pendingHide = nil
        if popup and popup:IsShown() then HidePopup() end
    end
end

function LR:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function LR:OnEnable()
    self:UpdateDB()
    if not (self.db and self.db.Enabled ~= false) then return end
    if not InCombatLockdown() then
        BuildPopup()  -- secure button needs out-of-combat creation
    end
    self:ApplySettings()
    self:RegisterEvent("LFG_LIST_JOINED_GROUP")
    self:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")
    self:RegisterEvent("GROUP_ROSTER_UPDATE")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "CheckInstance")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "CheckInstance")
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function LR:OnDisable()
    ClearArmed()
    ClearPending()
    pendingHide = nil
    -- Do NOT use HidePrompt here. AceAddon disables our embeds immediately
    -- after this returns, and AceEvent's OnEmbedDisable calls
    -- UnregisterAllEvents (Libs/AceEvent-3.0/AceEvent-3.0.lua) --
    -- so a hide that HidePrompt deferred via pendingHide could never be
    -- flushed: our PLAYER_REGEN_ENABLED is gone.
    --
    -- KE:RunAfterCombat (Core/Globals.lua) owns its own frame and its
    -- own PLAYER_REGEN_ENABLED registration, so it survives our disable.
    -- It runs the closure immediately when out of combat.
    if popup and popup:IsShown() then
        KE:RunAfterCombat(function()
            -- Keep the popup ONLY if the module came back AND has a fresh
            -- live prompt. "Enabled" alone is not enough: this disable just
            -- cleared the pending state, so a re-enable with no new join
            -- would strand the old popup on screen with its old teleport
            -- still armed.
            if LR:IsEnabled() and pendingSpellID then return end
            -- Out of combat here, so both writes are safe.
            if secureBtn then secureBtn:SetAttribute("spell", nil) end
            if popup and popup:IsShown() then HidePopup() end
        end)
    end
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------

-- Force-show the popup with sample contents so the user can drag it into
-- place from the config panel. It exists
-- because dragging is the only way to position this frame and the only
-- other route to seeing it is joining a real dungeon group.
--
-- The "spell" attribute is CLEARED here, not just left unwritten. This is
-- the same secure button a real prompt arms, and nothing on the teardown
-- path unsets it -- so without this line a preview shown after any real
-- prompt would still cast that dungeon's teleport on click, from a config
-- screen. Combat-gated like every other write to this button.
function LR:ShowPreview()
    if not self:IsEnabled() then return end
    if InCombatLockdown() then return end
    BuildPopup()
    if not popup then return end
    -- Whether a live prompt was on screen decides what closing the preview
    -- brings back.
    if not previewState then
        previewState = (popup:IsShown() and pendingSpellID) and "prompt" or "empty"
    end
    pendingHide = nil  -- the preview supersedes a deferred hide
    if secureBtn then secureBtn:SetAttribute("spell", nil) end
    -- Ruby Life Pools' map: the preview draws the live table's teleport.
    local dungeon, mapID = "Ruby Life Pools", 399
    shownName = dungeon
    -- Read whether or not Show Role is on, so ticking it with the preview open
    -- shows the row through the page's refresh.
    local specIndex = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization()
    local specRole = specIndex and specIndex > 0 and GetSpecializationRole
        and GetSpecializationRole(specIndex)
    shownRole = PickRole(specRole, nil) or "DAMAGER"
    ApplyPopupLayout()
    SetRowIcon(mapID, PickOwnPortal(mapID, KnowsSpell))
    SetRowKnown(true)
    ShowPopup()
end

function LR:HidePreview()
    if not previewState then return end
    local restore = previewState == "prompt"
    previewState = nil
    shownName, shownRole = nil, nil
    if InCombatLockdown() then
        -- The popup parents a secure button: hide it when combat ends, and
        -- let the combat re-show bring back a prompt that was waiting.
        pendingHide = true
        if restore then combatHidden = true end
        return
    end
    HidePopup()
    -- ShowPrompt re-arms the live prompt, or refuses one that has since gone
    -- on cooldown, been closed with X, or ended with the group.
    if restore then ShowPrompt() end
end

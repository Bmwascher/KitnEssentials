-- ╔══════════════════════════════════════════════════════════╗
-- ║  LFGQuickCreate.lua                                      ║
-- ║  Module: LFG Quick Create                                ║
-- ║  Purpose: A row of season-dungeon icon buttons on the    ║
-- ║           Group Finder's Entry Creation form. One click  ║
-- ║           lists a group for that dungeon. The dungeon    ║
-- ║           matching your own keystone glows gold with     ║
-- ║           its level; a party member's key glows blue.    ║
-- ║                                                          ║
-- ║  Taint safety -- critical, read before editing:          ║
-- ║    * C_LFGList.CreateListing() MUST be called directly   ║
-- ║      from the hardware click. It is HasRestrictions in   ║
-- ║      12.0.7; routing it through                          ║
-- ║      LFGListEntryCreation_ListGroup() taints and causes  ║
-- ║      ADDON_ACTION_BLOCKED.                               ║
-- ║    * NEVER write ec.generalPlaystyle from addon code.    ║
-- ║      SetEntryTitle is protected and not hardware-event-  ║
-- ║      exempt, and writing the field TAINTS THE FIELD      ║
-- ║      ITSELF -- Blizzard's own later reads then pass a    ║
-- ║      tainted value into SetEntryTitle and get blocked,   ║
-- ║      on Blizzard's path, where no shim can help. The     ║
-- ║      Default Playstyle setting reaches only the          ║
-- ║      CreateListing payload, which is clean.              ║
-- ║    * The double-click feature is a SECURE CLICK RELAY,   ║
-- ║      not an insecure Click(). A SecureActionButton       ║
-- ║      overlay is armed over the tile for 0.35s and the    ║
-- ║      second physical click drives Blizzard's own Start   ║
-- ║      button, so the whole flow stays secure. Its         ║
-- ║      RegisterForClicks MUST include the DOWN edge --     ║
-- ║      modern secure buttons ignore up-only registration.  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class LFGQuickCreate: AceModule, AceEvent-3.0
local QC = KitnEssentials:NewModule("LFGQuickCreate", "AceEvent-3.0")

local _G = _G
local ipairs = ipairs
local pcall = pcall
local type = type
local pairs = pairs
local math_max = math.max
local CreateFrame = CreateFrame
local C_Timer = C_Timer
-- Indexed off _G, unlike its neighbours: C_LFGList is the one API this file
-- touches that is NOT in .luacheckrc's allowlist, so a bare capture is a
-- W113 (accessing undefined global) and every task gates on zero warnings.
-- Modules/Skinning/Frames/LFG.lua:122 already reaches this same API this way.
-- Do NOT widen .luacheckrc instead.
local C_LFGList = _G.C_LFGList
local C_ChallengeMode = C_ChallengeMode
local C_MythicPlus = C_MythicPlus
local GameTooltip = GameTooltip
local IsInGroup = IsInGroup
local LibStub = LibStub
local hooksecurefunc = hooksecurefunc
local InCombatLockdown = InCombatLockdown

-- The party-keystone library is OPTIONAL. Every call site is guarded, so
-- without it the module still works -- the player's own gold key glow is
-- read directly from the API and never goes through the library.
local LKS = LibStub and LibStub:GetLibrary("LibKeystone", true)
local partyKeys = {}   -- [senderShortName] = { level = n, cmID = n }

-- Flip to true, /reload, click a category tile, read the chat log. Reports
-- why the double-click overlay did or did not arm for that tile. Left in
-- place after diagnosis, per the debug-first workflow.
local DEBUG_QC = false
local function qcdbg(msg)
    if DEBUG_QC then KE:Print("QuickCreate: " .. msg) end
end

local issecretvalue = issecretvalue
local playerShortName = UnitNameUnmodified and UnitNameUnmodified("player") or UnitName("player")
-- Both name APIs are SecretWhenUnitIdentityRestricted (UnitDocumentation.lua
-- :2367-2382 and :2401-2415). By that predicate's own documented text
-- (SecretPredicatesDocumentation.lua:108-111: secret only when the unit
-- isn't player-controlled or in the party/raid) the "player" token should
-- never trigger it -- this guard is belt-and-braces against an undocumented
-- restriction state, not a known one. Kept anyway: failing closed costs
-- nothing at file load, while an unguarded secret would throw at the
-- tooltip concatenation and at the sender comparison that guards the
-- partyKeys table write.
if issecretvalue and issecretvalue(playerShortName) then playerShortName = nil end

local ICON_SIZE = 32
local ICON_GAP  = 4

-- Season dungeon data. ActiveDungeons() filters to the live season via
-- C_ChallengeMode.GetMapTable(), so no manual source switch is needed when
-- the next season goes live.
local DUNGEONS = {
    -- Season 1
    { key = "windrunner_spire",     mapID = 2805, cmID = 557, lfgID = 1542 },
    { key = "maisara_caverns",      mapID = 2874, cmID = 560, lfgID = 1764 },
    { key = "magisters_terrace",    mapID = 2811, cmID = 558, lfgID = 1760 },
    { key = "nexus_point_xenas",    mapID = 2915, cmID = 559, lfgID = 1768 },
    { key = "algeth_ar_academy",    mapID = 2526, cmID = 402, lfgID = 1160 },
    { key = "seat_of_triumvirate",  mapID = 1753, cmID = 239, lfgID = 486  },
    { key = "skyreach",             mapID = 1209, cmID = 161, lfgID = 182  },
    { key = "pit_of_saron",         mapID = 658,  cmID = 556, lfgID = 1770 },
    -- Season 2
    { key = "altar_of_fangs",       mapID = 2993, cmID = 588, lfgID = 1933 },
    { key = "kings_rest",           mapID = 1762, cmID = 249, lfgID = 514  },
    { key = "ruby_life_pools",      mapID = 2521, cmID = 399, lfgID = 1176 },
    { key = "temple_of_sethraliss", mapID = 1877, cmID = 250, lfgID = 504  },
    { key = "murder_row",           mapID = 2813, cmID = 587, lfgID = 1950 },
    { key = "den_of_nalorakk",      mapID = 2825, cmID = 586, lfgID = 1952 },
    { key = "blinding_vale",        mapID = 2859, cmID = 584, lfgID = 1949 },
    { key = "voidscar_arena",       mapID = 2923, cmID = 585, lfgID = 1951 },
}
local SEASON1_COUNT = 8 -- fallback slice when GetMapTable is empty

local initialized  = false
local buttons      = {}
local container    = nil
local updateTicker = nil

local Init, MakeButton, RefreshGlow, SyncVisibility
local SaveLayout, PushLayout, PopLayout
-- Assigned inside Init (Task 5). Forward-declared so OnDisable can reach the
-- secure overlay, which otherwise lives only in Init's closure.
local HideDoubleClickOverlay

-- Filters DUNGEONS to those active in the current season. Falls back to the
-- season-1 slice when the active set is empty, which happens at early login
-- before map info resolves.
local function ActiveDungeons()
    local fallback = {}
    for i = 1, SEASON1_COUNT do fallback[i] = DUNGEONS[i] end
    if not C_ChallengeMode then return fallback end
    local cmIDs = C_ChallengeMode.GetMapTable()
    if not cmIDs or #cmIDs == 0 then return fallback end

    local active = {}
    for i = 1, #cmIDs do active[cmIDs[i]] = true end

    local out = {}
    for i = 1, #DUNGEONS do
        local d = DUNGEONS[i]
        if d.cmID and d.cmID > 0 and active[d.cmID] then
            out[#out + 1] = d
        end
    end
    return #out > 0 and out or fallback
end

-- Returns the playstyle set in the Entry Creation frame, falling back to the
-- saved default when the frame's value is unset. READ ONLY -- see the header:
-- writing ec.generalPlaystyle taints the field.
local function CurrentPlaystyle()
    local ec = _G.LFGListFrame and _G.LFGListFrame.EntryCreation
    if ec and type(ec.generalPlaystyle) == "number" and ec.generalPlaystyle > 0 then
        return ec.generalPlaystyle
    end
    return (QC.db and QC.db.DefaultPlaystyle) or 0
end

-- Read-only test seams. Both helpers are pure file-locals with no other
-- handle; exporting them creates no second source of truth.
QC._ActiveDungeons   = ActiveDungeons
QC._CurrentPlaystyle = CurrentPlaystyle

-- Highlights the dungeon matching the player's own keystone in gold, and any
-- dungeon a party member holds a key for in blue (best level among holders).
RefreshGlow = function()
    if not C_LFGList then return end
    local ok, ownLfgID, _, ownLevel = pcall(C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel)
    if not ok then ownLfgID, ownLevel = nil, nil end
    -- Themed: this was the reference project's own accent literal, now KE's.
    -- Read once per call, not once per button -- KE.Theme.accent[4] is the
    -- theme's alpha, not this glow's; the glow keeps its own measured 0.38.
    -- Fallback is KE's own brand pink (VantusRune.lua:184 precedent), not the
    -- old literal -- that literal was the reference project's own accent.
    -- A live theme switch repaints on the next 2s ticker, not instantly.
    local accent = KE.Theme and KE.Theme.accent or { 1, 0, 0.549 }
    for i = 1, #buttons do
        local btn = buttons[i]
        local ownMatch = ownLfgID and (btn._lfgID == ownLfgID)
        local partyLevel = nil
        for _, info in pairs(partyKeys) do
            if info.cmID == btn._cmID and info.level and info.level > 0 then
                if not partyLevel or info.level > partyLevel then
                    partyLevel = info.level
                end
            end
        end
        if ownMatch then
            btn._glow:SetColorTexture(1, 0.82, 0, 0.38)          -- own: gold
            btn._glow:Show()
            btn._lvlText:SetText(ownLevel and ("+" .. ownLevel) or "")
            btn._lvlText:Show()
        elseif partyLevel then
            btn._glow:SetColorTexture(accent[1], accent[2], accent[3], 0.38) -- party: themed accent
            btn._glow:Show()
            btn._lvlText:SetText("+" .. partyLevel)
            btn._lvlText:Show()
        else
            btn._glow:Hide()
            btn._lvlText:Hide()
        end
    end
end

-- Debounced, because the library's callback arrives once per party member.
local glowRefreshPending = false
local function QueueGlowRefresh()
    if glowRefreshPending then return end
    glowRefreshPending = true
    C_Timer.After(0.2, function()
        glowRefreshPending = false
        RefreshGlow()
    end)
end

-- Class token for the party member LibKeystone named, so their tooltip line
-- can carry their class colour. The library sends no class, so the roster is
-- the only source.
--
-- UnitName is SecretWhenUnitIdentityRestricted
-- (.wow-api-reference Interface/AddOns/Blizzard_APIDocumentationGenerated/
-- UnitDocumentation.lua:2368-2371), so inside a dungeon the name comes back
-- secret and comparing it would throw -- that unit is skipped and the line
-- keeps the accent colour. UnitClass's SECOND return (classFilename) has no
-- ConditionalSecret flag (same file :908-913); the first one does, so it is
-- deliberately not read.
local function PartyClassToken(shortName)
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) then
            local n = UnitName(unit)
            if not (issecretvalue and issecretvalue(n)) and n == shortName then
                local _, classFile = UnitClass(unit)
                return classFile
            end
        end
    end
    return nil
end

local function RequestPartyKeys()
    if LKS and IsInGroup() then
        LKS.Request("PARTY") -- library-throttled at 3s; replies land in the callback
    end
end

MakeButton = function(parent, dungeon, index)
    local _, _, _, iconTex = C_ChallengeMode.GetMapUIInfo(dungeon.cmID)
    local actInfo = C_LFGList.GetActivityInfoTable(dungeon.lfgID)
    local label   = actInfo and actInfo.fullName ~= "" and actInfo.fullName or dungeon.key

    local btn = CreateFrame("Button", "KE_LFGQC_" .. dungeon.key, parent)
    btn:SetSize(ICON_SIZE, ICON_SIZE)
    btn:SetPoint("TOPLEFT", (index - 1) * (ICON_SIZE + ICON_GAP), 0)

    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    -- The shared helpers, not a hand-rolled crop and border: KE's standard
    -- icon treatment is a 0.3 zoom and a pixel-snapped 1px black frame.
    KE:ApplyIconZoom(tex)
    if iconTex and iconTex ~= 0 then tex:SetTexture(iconTex) end
    KE:AddIconBorders(btn)

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.18)

    local glow = btn:CreateTexture(nil, "OVERLAY", nil, 1)
    glow:SetAllPoints()
    glow:SetColorTexture(1, 0.82, 0, 0.38)
    glow:Hide()

    local lvl = btn:CreateFontString(nil, "OVERLAY")
    lvl:SetFont(KE.FONT or "Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    lvl:SetPoint("CENTER")
    lvl:Hide()

    btn._lfgID   = dungeon.lfgID
    btn._cmID    = dungeon.cmID
    btn._glow    = glow
    btn._lvlText = lvl
    btn._label   = label

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:ClearLines()
        GameTooltip:SetText(self._label, 1, 1, 1, 1, true)
        local ok, ownLfgID, _, ownLevel = pcall(C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel)
        if ok and ownLfgID and ownLfgID == self._lfgID and ownLevel then
            -- playerShortName is nil when the load-time capture was secret
            -- (see the file header). The line still carries the useful half.
            GameTooltip:AddLine((playerShortName or "You") .. ": +" .. ownLevel, 1, 0.82, 0)
        end
        -- Themed: this was the reference project's own accent literal, now
        -- KE's. Fallback is KE's own brand pink (VantusRune.lua:184
        -- precedent), not the old literal. A live theme switch repaints on
        -- the next hover, not instantly.
        local accent = KE.Theme and KE.Theme.accent or { 1, 0, 0.549 }
        for name, info in pairs(partyKeys) do
            if info.cmID == self._cmID and info.level and info.level > 0 then
                -- Class colour when the roster gave one up, accent when it
                -- did not. KE:GetClassColor falls back to the PLAYER's colour
                -- on a nil token, which would be wrong here, so the nil case
                -- never reaches it.
                local c = info.class and KE:GetClassColor(info.class) or accent
                GameTooltip:AddLine(name .. ": +" .. info.level, c[1], c[2], c[3])
            end
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn:SetScript("OnClick", function(self, mb)
        if mb ~= "LeftButton" then return end
        -- No typed-name gate: the CreateListing payload has no name or title
        -- field at all. M+ titles are generated server-side as
        -- "+<level> <playstyle>", so one click lists immediately with the key
        -- level as the title. The form's own dropdown staying blank is
        -- cosmetic; this path bypasses the form entirely.
        --
        -- CreateListing is HasRestrictions and MUST be called directly from
        -- this hardware event -- see the file header.
        --
        -- BOTH playstyle enums are required. `playstyle` is the legacy
        -- LFGEntryPlaystyle and `generalPlaystyle` is the current
        -- LFGEntryGeneralPlaystyle. Putting the general value in the legacy
        -- field and leaving generalPlaystyle at None makes the server reject
        -- the listing silently. This mirrors Blizzard's own assembly.
        C_LFGList.CreateListing({
            activityIDs           = { self._lfgID },
            questID               = nil,
            isAutoAccept          = false,
            isCrossFactionListing = true,
            isPrivateGroup        = false,
            newPlayerFriendly     = false,
            playstyle             = (Enum.LFGEntryPlaystyle and Enum.LFGEntryPlaystyle.None) or 0,
            generalPlaystyle      = CurrentPlaystyle(),
            requiredDungeonScore  = 0,
            requiredItemLevel     = 0,
            requiredPvpRating     = 0,
        })

        -- DO NOT call LFGListEntryCreation_Select here to pre-fill the form.
        -- Tried 2026-08-01 and it is BLOCKED: Select reaches
        -- LFGListEntryCreation_SetTitleFromActivityInfo
        -- (.wow-api-reference Interface/AddOns/Blizzard_GroupFinder/
        -- Mainline/LFGList.lua:1104, :1311), which calls the protected
        -- SetEntryTitle. In-game trace: ADDON_ACTION_BLOCKED, 'SetEntryTitle()'.
        -- The form staying blank is cosmetic and stays that way.
    end)

    return btn
end

-- Saves the form's original layout, then pushes two labels down to make room
-- for the button row.
local origLayout = {}

SaveLayout = function(ec)
    if origLayout.done then return end
    if ec.DescriptionLabel then
        local _, _, _, ox, oy = ec.DescriptionLabel:GetPoint()
        origLayout.dlX, origLayout.dlY = ox, oy
    end
    if ec.Description then
        origLayout.dH = ec.Description:GetHeight()
    end
    if ec.PlayStyleLabel then
        local _, _, _, ox, oy = ec.PlayStyleLabel:GetPoint()
        origLayout.plX, origLayout.plY = ox, oy
    end
    origLayout.done = true
end

PushLayout = function(ec)
    if ec.DescriptionLabel and ec.NameLabel then
        ec.DescriptionLabel:SetPoint("TOPLEFT", ec.NameLabel, "TOPLEFT", 0, -85)
    end
    if ec.Description then
        ec.Description:SetHeight(25)
    end
    if ec.PlayStyleLabel and ec.DescriptionLabel then
        ec.PlayStyleLabel:SetPoint("TOPLEFT", ec.DescriptionLabel, "TOPLEFT", 0, -55)
    end
end

PopLayout = function(ec)
    if not origLayout.done then return end
    if ec.DescriptionLabel and ec.NameLabel then
        ec.DescriptionLabel:SetPoint("TOPLEFT", ec.NameLabel, "TOPLEFT",
            origLayout.dlX or 0, origLayout.dlY or -55)
    end
    if ec.Description and origLayout.dH then
        ec.Description:SetHeight(origLayout.dH)
    end
    if ec.PlayStyleLabel and ec.DescriptionLabel and origLayout.plY then
        ec.PlayStyleLabel:SetPoint("TOPLEFT", ec.DescriptionLabel, "TOPLEFT",
            origLayout.plX or 0, origLayout.plY)
    end
end

-- The row belongs to the Dungeons category (2) only.
SyncVisibility = function()
    if not container then return end
    if not (QC.db and QC.db.Enabled ~= false and QC.db.QuickCreate ~= false) then
        container:Hide()
        return
    end
    local cs = _G.LFGListFrame and _G.LFGListFrame.CategorySelection
    container:SetShown(cs ~= nil and cs.selectedCategory == 2)
end

-- One-time initialization, deferred until LFGListFrame exists.
Init = function()
    if initialized then return end
    if not (QC.db and QC.db.Enabled ~= false) then return end

    local ec = _G.LFGListFrame and _G.LFGListFrame.EntryCreation
    if not ec then return end

    -- GetCurrentSeason() returns -1 until RequestMapInfo resolves, and the
    -- dungeon filter is worthless until it does.
    if not C_MythicPlus then return end
    C_MythicPlus.RequestMapInfo()
    if C_MythicPlus.GetCurrentSeason() == -1 then
        C_Timer.After(0.5, Init)
        return
    end

    initialized = true

    SaveLayout(ec)

    local list    = ActiveDungeons()
    local totalW  = #list * ICON_SIZE + math_max(0, #list - 1) * ICON_GAP
    local nameBox = ec.Name or ec.NameBox

    container = CreateFrame("Frame", "KE_LFGQCContainer", ec)
    container:SetSize(totalW, ICON_SIZE)
    -- Centered under the name box. The 1px borders add a pixel each side and
    -- centering absorbs it.
    container:SetPoint("TOP", nameBox, "BOTTOM", 0, -3)
    container:Hide()

    for i, d in ipairs(list) do
        buttons[#buttons + 1] = MakeButton(container, d, i)
    end

    -- Secure click relay -- see the file header. The overlay exists only while
    -- the Group Finder is in use, is armed for 0.35s after a category click,
    -- and hides after firing or on timeout. Every secure-frame write is
    -- combat-guarded.
    local dblOverlay, dblTimer

    -- DEVIATION from the reference, and it fixes a live defect there. The
    -- reference hides the overlay only when out of combat and never retries
    -- (<REF>:426, :444), so combat starting inside the 0.35s window leaves the
    -- overlay SHOWN indefinitely, still covering that category tile and still
    -- armed to click Start a Group. Route every hide through KE:RunAfterCombat
    -- (Core/Globals.lua:154-170), which owns its own frame and its own
    -- PLAYER_REGEN_ENABLED registration and therefore survives module disable.
    HideDoubleClickOverlay = function()
        if not dblOverlay then return end
        if InCombatLockdown() then
            KE:RunAfterCombat(function()
                if dblOverlay then dblOverlay:Hide() end
            end)
            return
        end
        dblOverlay:Hide()
    end

    local function EnsureDoubleClickOverlay(cs)
        if dblOverlay then return dblOverlay end
        if InCombatLockdown() then return nil end
        dblOverlay = CreateFrame("Button", "KE_LFGQCDblClick", cs, "SecureActionButtonTemplate")
        -- MUST include the DOWN edge: modern secure buttons ignore mouse
        -- input registered up-only, which is what stopped the relay working.
        dblOverlay:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
        dblOverlay:SetAttribute("type", "click")
        dblOverlay:SetAttribute("clickbutton", cs.StartGroupButton)
        dblOverlay:SetFrameLevel(cs:GetFrameLevel() + 100)
        dblOverlay:Hide()
        dblOverlay:SetScript("PostClick", function()
            if dblTimer then dblTimer:Cancel(); dblTimer = nil end
            HideDoubleClickOverlay()
        end)
        return dblOverlay
    end
    local function ArmDoubleClick(catBtn)
        qcdbg("tile clicked, categoryID=" .. tostring(catBtn and catBtn.categoryID)
            .. " filters=" .. tostring(catBtn and catBtn.filters))
        if not (QC.db and QC.db.Enabled ~= false and QC.db.DoubleClickStart ~= false) then
            qcdbg("bail: feature off")
            return
        end
        if InCombatLockdown() then
            qcdbg("bail: in combat")
            return
        end
        local cs = catBtn:GetParent()
        local sgb = cs and cs.StartGroupButton
        if not (sgb and sgb:IsEnabled()) then
            qcdbg("bail: start button missing or disabled, tooltip="
                .. tostring(sgb and sgb.tooltip))
            return
        end
        local ov = EnsureDoubleClickOverlay(cs)
        if not ov then
            qcdbg("bail: overlay could not be created")
            return
        end
        qcdbg("armed over the tile")
        ov:ClearAllPoints()
        ov:SetAllPoints(catBtn)
        ov:Show()
        if dblTimer then dblTimer:Cancel() end
        dblTimer = C_Timer.NewTimer(0.35, function()
            dblTimer = nil
            HideDoubleClickOverlay()
        end)
    end
    if _G.LFGListCategorySelectionButton_OnClick then
        hooksecurefunc("LFGListCategorySelectionButton_OnClick", ArmDoubleClick)
    end

    local function HookDD(dd)
        if not dd then return end
        dd:HookScript("OnHide", function()
            C_Timer.After(0.05, SyncVisibility)
        end)
    end
    HookDD(ec.GroupDropdown)
    HookDD(ec.ActivityDropdown)
    if ec.CategoryDropdown and ec.CategoryDropdown ~= ec.GroupDropdown then
        HookDD(ec.CategoryDropdown)
    end

    ec:HookScript("OnShow", function()
        local db = QC.db
        local moduleOn = db and db.Enabled ~= false
        if moduleOn and db.QuickCreate ~= false then
            PushLayout(ec)
            SyncVisibility()
            RefreshGlow()
            RequestPartyKeys()
            if not updateTicker then
                updateTicker = C_Timer.NewTicker(2, RefreshGlow)
            end
        else
            PopLayout(ec)
            container:Hide()
        end
    end)

    ec:HookScript("OnHide", function()
        if updateTicker then updateTicker:Cancel(); updateTicker = nil end
    end)

    if ec:IsShown() then
        if QC.db.QuickCreate ~= false then
            PushLayout(ec)
            SyncVisibility()
            RefreshGlow()
        end
    end
end

function QC:UpdateDB()
    if KE.db and KE.db.profile then
        self.db = KE.db.profile.LFGQuickCreate
    end
    -- Generic saved-variables validation, NOT a migration: KE has never
    -- shipped this module, so no user can be holding a bad value from an
    -- older build. It is here because this key is user-editable through
    -- saved variables, because a plain string-array dropdown would return
    -- the LABEL (GUI-KEDropdown.lua:198-202 -- the ordered form in the config
    -- page is what avoids that), and because the value feeds a protected API
    -- call where a string is a usage error.
    -- Enum.LFGEntryGeneralPlaystyle runs 0-4; 0 is None and never valid here.
    if self.db then
        local ps = self.db.DefaultPlaystyle
        if type(ps) ~= "number" or ps < 1 or ps > 4 then
            self.db.DefaultPlaystyle = 1
        end
    end
end

function QC:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function QC:OnAddonLoaded()
    -- Same reasoning as the OnEnable gate: wait for the OBJECT, not a name.
    -- Fires for every addon load, so it is cheap and it cannot miss.
    if not _G.LFGListFrame then return end
    self:UnregisterEvent("ADDON_LOADED")
    C_Timer.After(0.1, Init)
end

function QC:OnRosterUpdate()
    -- Drop leavers, then re-request so current members repopulate.
    for k in pairs(partyKeys) do partyKeys[k] = nil end
    RequestPartyKeys()
    QueueGlowRefresh()
end

function QC:OnEnable()
    self:UpdateDB()
    if not (self.db and self.db.Enabled ~= false) then return end
    if LKS then
        LKS.Register(QC, function(keyLevel, keyChallengeMapID, _, sender, channel)
            if channel ~= "PARTY" then return end
            -- Fail closed on a secret sender: it is used as a TABLE KEY below
            -- and concatenated into tooltip text, both of which throw. Losing
            -- one party member's blue glow beats an error.
            if issecretvalue and issecretvalue(sender) then return end
            if playerShortName and sender == playerShortName then return end -- own key is read directly
            if type(keyLevel) == "number" and type(keyChallengeMapID) == "number"
                and keyLevel > 0 and keyChallengeMapID > 0 then
                partyKeys[sender] = {
                    level = keyLevel,
                    cmID  = keyChallengeMapID,
                    class = PartyClassToken(sender),
                }
            else
                partyKeys[sender] = nil
            end
            QueueGlowRefresh()
        end)
        self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnRosterUpdate")
    end
    -- Gate on the OBJECT, not on an addon name.
    --
    -- This used to wait for "Blizzard_LFGList" to load. That addon DOES NOT
    -- EXIST in 12.0 -- the Group Finder UI moved into Blizzard_GroupFinder,
    -- which is `DefaultState: enabled` with no LoadOnDemand and is therefore
    -- always present. So the wait never ended: enabling the module at runtime
    -- registered ADDON_LOADED for a name that never arrives, Init never ran,
    -- and no buttons appeared until a /reload took a different path in.
    -- (Smoke C-3/C-10, 2026-08-01.)
    --
    -- The object is what Init actually needs, and gating on it does not
    -- depend on how Blizzard lays its files out next patch.
    if _G.LFGListFrame then
        C_Timer.After(0.1, Init)
    else
        self:RegisterEvent("ADDON_LOADED", "OnAddonLoaded")
    end
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPEW")
end

function QC:OnPEW()
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    C_Timer.After(0.5, Init)
end

function QC:OnDisable()
    self:UnregisterAllEvents()
    if LKS then LKS.Unregister(QC) end
    for k in pairs(partyKeys) do partyKeys[k] = nil end
    if updateTicker then updateTicker:Cancel(); updateTicker = nil end
    if container then container:Hide() end
    -- Deviation, paired with Task 5's: the secure overlay must not survive a
    -- disable still armed over a category tile. Routed through the same
    -- combat-safe helper, which queues on KE's own frame -- Ace has already
    -- unregistered this module's events by the time OnDisable runs, so the
    -- module could never flush a deferred hide itself.
    if HideDoubleClickOverlay then HideDoubleClickOverlay() end
    local ec = _G.LFGListFrame and _G.LFGListFrame.EntryCreation
    if ec then PopLayout(ec) end
end

-- Live-settings hook for the config page.
function QC:ApplySettings()
    self:UpdateDB()
    if self.db and self.db.Enabled ~= false then
        Init()
        local ec = _G.LFGListFrame and _G.LFGListFrame.EntryCreation
        if ec and ec:IsShown() and container then
            if self.db.QuickCreate ~= false then
                PushLayout(ec); SyncVisibility(); RefreshGlow()
            else
                PopLayout(ec); container:Hide()
            end
        end
    else
        if container then container:Hide() end
    end
end

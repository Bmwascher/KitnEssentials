-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-DungeonTimersDungeon.lua                            ║
-- ║  Purpose: Per-dungeon settings page generator. Registers ║
-- ║  one content callback per known dungeon key              ║
-- ║  (DTimers_Dungeon_<KEY>). Each page renders the curated  ║
-- ║  encounters for that dungeon as a list+detail editor:    ║
-- ║                                                          ║
-- ║    ┌──────────────┬─────────────────────────────────┐    ║
-- ║    │ B1 Spell A   │ [Visibility][Display][Actions]  │    ║
-- ║    │ B1 Spell B   │                                 │    ║
-- ║    │ B1 Spell C   │  Visibility tab body            │    ║
-- ║    │ B2 Spell D   │  ─────────────────────          │    ║
-- ║    │ ...          │  Show for: T  H  D              │    ║
-- ║    └──────────────┴─────────────────────────────────┘    ║
-- ║                                                          ║
-- ║  Mirrors BigWigsTimers' editor UX so users have a        ║
-- ║  consistent mental model. Three tabs map to logical      ║
-- ║  groupings:                                              ║
-- ║                                                          ║
-- ║    Visibility — Enable, role allow-list, showAtSeconds   ║
-- ║    Display    — bar/text mode, custom label, format,     ║
-- ║                 colors                                   ║
-- ║    Actions    — sounds (future)                          ║
-- ║                                                          ║
-- ║  N13c (this commit): shape locked in; Visibility tab     ║
-- ║  populated with role overrides only (the only existing   ║
-- ║  user-configurable knob today). Future N13d-g sub-phases ║
-- ║  fill remaining fields without further rebuilds.         ║
-- ║                                                          ║
-- ║  Memory: list rows are pooled via KE.FramePool; detail-  ║
-- ║  pane widgets are built per render but persist in pool   ║
-- ║  via the same ReleaseAll hook so RefreshContent doesn't  ║
-- ║  churn allocations across spell/tab clicks.              ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame

local pairs = pairs
local ipairs = ipairs
local table_insert = table.insert
local table_sort = table.sort
local string_format = string.format
local CreateFrame = CreateFrame

KE.GUI = KE.GUI or {}
KE.GUI.DungeonTimers = KE.GUI.DungeonTimers or {}

---------------------------------------------------------------------------------
-- Static dungeon registry. Mirrors BigWigsTimers' DUNGEON_DISPLAY_NAMES — keep
-- in sync when EncounterData adds a new dungeon key. The order here is the
-- order the sidebar items appear in GUI-MainFrame.lua.
---------------------------------------------------------------------------------
local DUNGEONS = {
    { key = "AlgetharAcademy",    name = "Algeth'ar Academy" },
    { key = "MagistersTerrace",   name = "Magisters' Terrace" },
    { key = "MaisaraCaverns",     name = "Maisara Caverns" },
    { key = "NexusPointXenas",    name = "Nexus-Point Xenas" },
    { key = "PitOfSaron",         name = "Pit of Saron" },
    { key = "SeatOfTriumvirate",  name = "Seat of the Triumvirate" },
    { key = "Skyreach",           name = "Skyreach" },
    { key = "WindrunnerSpire",    name = "Windrunner Spire" },
}

local PLAYER_ROLE_TOKENS = {
    { token = "TANK",    label = "Tank" },
    { token = "HEALER",  label = "Healer" },
    { token = "DAMAGER", label = "DPS" },
}

-- User-friendly translation of the curator's role tag → "Default: ..." text
-- shown on the Visibility tab. Drops the technical tank/heal/mechanic/other
-- vocabulary in favor of who-sees-it semantics. mechanic and other both
-- collapse to "Everyone" since both mean "no role gating by default".
local ROLE_TAG_FRIENDLY = {
    tank     = "Tanks only",
    heal     = "Healers only",
    mechanic = "Everyone",
    other    = "Everyone",
}

local DETAIL_TABS = {
    { id = "Visibility", label = "Visibility" },
    { id = "Display",    label = "Display" },
    { id = "Actions",    label = "Actions" },
}

-- Layout constants. Left column is fixed-width; right column eats the rest of
-- the content area. Scrollable behavior is inherited from the GUIFrame's outer
-- scrollChild — both columns just stack into it.
local LEFT_COL_WIDTH    = 200
local COL_GAP           = 8
local LIST_ROW_HEIGHT   = 28
local ENC_HEADER_HEIGHT = 30
local DETAIL_PADDING    = 12

local CURATED_TAG_COLOR = { 0.65, 0.65, 0.65 }
-- Destructive-action color, matches GUI-Nicknames Remove buttons + Reset
-- All Triggers in BigWigsTimers. Used for the per-spell Reset button so
-- destructive UX is consistent across the addon.
local REMOVE_COLOR = { 0.9, 0.2, 0.2, 1 }

-- Section header for the Visibility tab body. Small accent-colored label
-- followed by a thin underline that runs to the right edge — gives clear
-- semantic grouping ("WHO SEES IT", "WHEN IT APPEARS") without nesting
-- full cards. Returns the header FontString so the caller can anchor
-- subsequent content to its BOTTOMLEFT.
local function CreateSectionHeader(parent, anchorFrame, text, yPad)
    local T = KE.Theme
    local label = parent:CreateFontString(nil, "OVERLAY")
    KE:ApplyFontToText(label, "Expressway", 13, "OUTLINE")
    label:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
    label:SetText(text)
    label:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -(yPad or 14))

    local underline = parent:CreateTexture(nil, "ARTWORK")
    underline:SetHeight(1)
    underline:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.4)
    underline:SetPoint("LEFT", label, "RIGHT", 6, 0)
    underline:SetPoint("RIGHT", parent, "RIGHT", -DETAIL_PADDING, 0)
    underline:SetPoint("TOP", label, "TOP", 0, -8)
    return label
end

local function GetSettingsDB()
    if not KE.db or not KE.db.profile then return nil end
    return KE.db.profile.Dungeons and KE.db.profile.Dungeons.DungeonTimers
end

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("DungeonTimers", true)
    end
    return nil
end

---------------------------------------------------------------------------------
-- Per-spell preview thunks. Wrap the DT module methods so callers can use
-- them as `KE.GUI.DungeonTimers.<name>()` from sibling DT settings pages
-- (Bars/Texts/Cfg) and the GUIFrame's onCloseCallbacks dispatch — same
-- pattern as HideBarPreviews / HideTextPreviews exposed by those files.
---------------------------------------------------------------------------------
local function HideSpellPreview()
    local mod = GetModule()
    if mod and mod.HideSpellPreview then
        mod:HideSpellPreview()
    end
end

local function RefreshSpellPreview()
    local mod = GetModule()
    if mod and mod.RefreshSpellPreview then
        mod:RefreshSpellPreview()
    end
end

local function ShowSpellPreview(spellId)
    if not GUIFrame or not GUIFrame:IsShown() then return end
    local sel = GUIFrame.selectedSidebarItem or ""
    -- Only render the preview while a per-dungeon page is active. If the
    -- user navigated away mid-build (rare), don't accidentally spawn a
    -- preview into a settings page's preview group.
    if not sel:find("^DTimers_Dungeon_") then return end
    local mod = GetModule()
    if mod and mod.ShowSpellPreview then
        mod:ShowSpellPreview(spellId)
    end
end

KE.GUI.DungeonTimers.HideSpellPreview = HideSpellPreview

---------------------------------------------------------------------------------
-- Per-dungeon sticky state. Survives RefreshContent rebuilds so spell + tab
-- selection persist as the user clicks around. Reset only when EncounterData
-- changes shape (rare; runtime-static).
---------------------------------------------------------------------------------
local _state = {}

local function GetState(dungeonKey)
    local s = _state[dungeonKey]
    if not s then
        s = { selectedSpellId = nil, selectedTab = "Visibility" }
        _state[dungeonKey] = s
    end
    return s
end

---------------------------------------------------------------------------------
-- Encounter list cache. EncounterData is static at runtime; first render of a
-- dungeon walks + sorts, subsequent renders read directly. Built lazily because
-- EncounterData.lua may not have populated KE.EncounterData when this file's
-- top-level code runs (XML load order).
---------------------------------------------------------------------------------
local _encListCache = {}

local function CollectEncountersForDungeon(dungeonKey)
    if not dungeonKey then return {} end
    local cached = _encListCache[dungeonKey]
    if cached then return cached end

    local encList = {}
    for encId, enc in pairs(KE.EncounterData or {}) do
        if enc.dungeon == dungeonKey then
            local spellPairs = {}
            if enc.spells then
                for spellId, spell in pairs(enc.spells) do
                    table_insert(spellPairs, { id = spellId, data = spell })
                end
            end
            table_sort(spellPairs, function(a, b) return a.id < b.id end)
            table_insert(encList, {
                id        = encId,
                name      = enc.name or string_format("Encounter %d", encId),
                bossOrder = enc.bossOrder,
                spells    = spellPairs,
            })
        end
    end
    -- Sort by explicit bossOrder when present (older dungeons whose
    -- encounterIDs don't reflect in-dungeon order, e.g. Pit of Saron),
    -- otherwise fall back to encounterID-ascending. Two-key sort keeps
    -- ordering deterministic when bossOrder is partially populated.
    table_sort(encList, function(a, b)
        local ao = a.bossOrder or a.id
        local bo = b.bossOrder or b.id
        if ao ~= bo then return ao < bo end
        return a.id < b.id
    end)
    _encListCache[dungeonKey] = encList
    return encList
end

local function ResolveSpellDisplayName(spellId, spell)
    if spell.name and spell.name ~= "" then return spell.name end
    if spell.displayText and spell.displayText ~= "" then return spell.displayText end
    return string_format("Spell %d", spellId)
end

-- Resolves the first selectable spellId in a dungeon. Used to default the
-- sticky selection when the user hasn't clicked anything yet OR when a stale
-- selection points to a spell no longer in EncounterData (rare).
local function ResolveFirstSpellId(encounters)
    for _, enc in ipairs(encounters) do
        if enc.spells[1] then return enc.spells[1].id end
    end
    return nil
end

---------------------------------------------------------------------------------
-- Frame pool: spell list row. Click handler captures `kit` in a closure
-- created once at factory time; per-render Configure mutates kit fields.
---------------------------------------------------------------------------------

-- Override stripe color logic. Three states:
--   disabled spell      → red stripe (most destructive override)
--   other overrides     → yellow stripe (role/showAt deviation)
--   no overrides        → stripe hidden
-- Cheap: 2 boolean DB lookups per call; never on render hot path.
local STRIPE_RED    = { 1.0, 0.25, 0.25, 1.0 }
local STRIPE_YELLOW = { 1.0, 0.85, 0.0,  1.0 }

local function ApplyOverrideStripe(kit, spellId)
    if not (kit and kit.overrideStripe) then return end
    local DT = GetModule()
    local hasOverrides = (DT and DT.HasSpellOverrides and DT:HasSpellOverrides(spellId)) or false
    if not hasOverrides then
        kit.overrideStripe:Hide()
        return
    end
    local isDisabled = (DT and DT.IsSpellDisabled and DT:IsSpellDisabled(spellId)) or false
    local c = isDisabled and STRIPE_RED or STRIPE_YELLOW
    kit.overrideStripe:SetColorTexture(c[1], c[2], c[3], c[4])
    kit.overrideStripe:Show()
end

local function ConfigureListRow(kit, spellId, spell, isSelected)
    kit._spellId = spellId
    -- Cache curated role on the kit so future hover handlers don't pay a
    -- DT helper lookup at hover time — pure-table read.
    kit._roleTag = spell.role

    kit.label:SetText(ResolveSpellDisplayName(spellId, spell))

    -- Override marker: 2px-wide stripe on the LEFT edge of the row.
    -- Red when the spell is disabled (most destructive override),
    -- yellow when any other override exists, hidden otherwise. Visible
    -- against any row state (idle / hover / selected). Setters auto-
    -- prune redundant overrides, so this stripe stays accurate when
    -- users toggle a value back to its curated default.
    ApplyOverrideStripe(kit, spellId)

    -- Display-mode tag — colored mini-label on the right. "Bar" = filled
    -- bar with countdown overlay; "Text" = plain text-only line (no
    -- fill texture). Both render through the same DungeonTimers pipeline;
    -- the difference is just visual style. Colors match BigWigsTimers'
    -- tag palette so the two modules feel consistent.
    -- Reads via DT:GetSpellDisplay so the user's per-spell override wins
    -- over the curator's default; the tag flips live when the override
    -- changes (RefreshListRowTag is the targeted update from the Display
    -- tab's toggle).
    if kit.tagLabel then
        local DT = GetModule()
        local effectiveDisplay = (DT and DT:GetSpellDisplay(spellId)) or spell.display or "text"
        if effectiveDisplay == "bar" then
            kit.tagLabel:SetText("Bar")
            kit.tagLabel:SetTextColor(0.4, 0.7, 1.0, 0.9)
        else
            kit.tagLabel:SetText("Text")
            kit.tagLabel:SetTextColor(0.4, 1.0, 0.5, 0.9)
        end
    end

    -- Sound indicator — "S" appears on the right when the spell has any
    -- onShow or onHide sound configured. Empty string keeps the
    -- FontString width zero when no sound is set so the label can grow
    -- into the slot.
    if kit.soundLabel then
        local DT_mod = GetModule()
        local hasSound = (DT_mod and DT_mod.HasSpellSound and DT_mod:HasSpellSound(spellId)) or false
        if hasSound then
            kit.soundLabel:SetText("S")
            kit.soundLabel:SetTextColor(1.0, 0.8, 0.3, 0.9)
        else
            kit.soundLabel:SetText("")
        end
    end

    -- Spell icon. C_Spell.GetSpellTexture is clean (no secret-value taint)
    -- for curated spellIds since they're well-defined boss spells with
    -- entries in the spell DB.
    if kit.icon then
        local tex = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellId))
                    or 134400
        kit.icon:SetTexture(tex)
    end

    if isSelected then
        local a = KE.Theme.accent
        kit.bg:SetColorTexture(a[1], a[2], a[3], 0.25)
        kit.label:SetTextColor(a[1], a[2], a[3])
    else
        kit.bg:SetColorTexture(0, 0, 0, 0)
        kit.label:SetTextColor(1, 1, 1, 0.9)
    end
end

local function ResetListRow(kit)
    kit._spellId = nil
    kit._roleTag = nil
    if kit.label then kit.label:SetText("") end
    if kit.bg then kit.bg:SetColorTexture(0, 0, 0, 0) end
    if kit.icon then kit.icon:SetTexture(134400) end
    if kit.tagLabel then kit.tagLabel:SetText("") end
    if kit.soundLabel then kit.soundLabel:SetText("") end
    if kit.overrideStripe then kit.overrideStripe:Hide() end
    -- Clear anchors so re-Acquire's SetPoint starts from a clean slate. Without
    -- this, in rare cases the kit can hold a stale TOPLEFT anchor referencing
    -- the previous render's leftCol (which has since been SetParent(nil)'d
    -- during ClearContent). The new SetPoint usually replaces cleanly, but if
    -- WoW's frame system delivers a layout pass between the SetParent + SetPoint
    -- calls, the row can render at the stale position (off-screen relative to
    -- the new leftCol) and look "missing".
    if kit.row and kit.row.ClearAllPoints then kit.row:ClearAllPoints() end
end

local function CreateListRowKit(holder)
    local kit = {}
    local row = CreateFrame("Button", nil, holder)
    row:SetHeight(LIST_ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp")
    kit.row = row

    -- Background fill — stays transparent until the row is selected; flips to
    -- accent-tinted on selection.
    kit.bg = row:CreateTexture(nil, "BACKGROUND")
    kit.bg:SetAllPoints()
    kit.bg:SetColorTexture(0, 0, 0, 0)

    -- Override stripe — 2px-wide yellow bar on the LEFT edge, only shown
    -- when DT:HasSpellOverrides(spellId). ARTWORK draw layer keeps it
    -- visible above the BACKGROUND bg fill (selected accent tint).
    kit.overrideStripe = row:CreateTexture(nil, "ARTWORK", nil, 1)
    kit.overrideStripe:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    kit.overrideStripe:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    kit.overrideStripe:SetWidth(2)
    kit.overrideStripe:SetColorTexture(1.0, 0.85, 0.0, 1.0)
    kit.overrideStripe:Hide()

    -- Spell icon container. Pixel-perfect 1px black border via
    -- KE:AddIconBorders + standard zoom crop via KE:ApplyIconZoom — same
    -- helpers used everywhere else for icon UX consistency.
    local iconSize = LIST_ROW_HEIGHT - 6
    kit.iconFrame = CreateFrame("Frame", nil, row, "BackdropTemplate")
    kit.iconFrame:SetSize(iconSize, iconSize)
    kit.iconFrame:SetPoint("LEFT", row, "LEFT", 6, 0)
    kit.iconFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    kit.iconFrame:SetBackdropColor(0, 0, 0, 0.8)
    if KE.AddIconBorders then KE:AddIconBorders(kit.iconFrame) end

    kit.icon = kit.iconFrame:CreateTexture(nil, "ARTWORK")
    kit.icon:SetPoint("TOPLEFT", 1, -1)
    kit.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    if KE.ApplyIconZoom then KE:ApplyIconZoom(kit.icon) end
    kit.icon:SetTexture(134400)

    -- Right-cluster indicators (mirrors BigWigsTimers' typeIndicator +
    -- soundIndicator chain). Created right-to-left so each anchors to
    -- the LEFT edge of the widget to its right; empty FontStrings have
    -- zero width, so the label.RIGHT anchor naturally absorbs the space
    -- when soundLabel is empty.
    kit.tagLabel = row:CreateFontString(nil, "OVERLAY")
    KE:ApplyFontToText(kit.tagLabel, "Expressway", 12, "OUTLINE")
    kit.tagLabel:SetPoint("RIGHT", row, "RIGHT", -8, 0)

    kit.soundLabel = row:CreateFontString(nil, "OVERLAY")
    KE:ApplyFontToText(kit.soundLabel, "Expressway", 12, "OUTLINE")
    kit.soundLabel:SetPoint("RIGHT", kit.tagLabel, "LEFT", -4, 0)

    kit.label = row:CreateFontString(nil, "OVERLAY")
    KE:ApplyFontToText(kit.label, "Expressway", 12, "OUTLINE")
    kit.label:SetPoint("LEFT", kit.iconFrame, "RIGHT", 6, 0)
    kit.label:SetPoint("RIGHT", kit.soundLabel, "LEFT", -4, 0)
    kit.label:SetJustifyH("LEFT")
    kit.label:SetWordWrap(false)

    row:SetScript("OnEnter", function(b)
        if b._spellId and b._spellId ~= b._currentSelected then
            kit.bg:SetColorTexture(1, 1, 1, 0.06)
        end
    end)
    row:SetScript("OnLeave", function(b)
        if b._spellId and b._spellId ~= b._currentSelected then
            kit.bg:SetColorTexture(0, 0, 0, 0)
        end
    end)

    -- Click handler: writes selected spellId to the per-dungeon state and
    -- triggers RefreshContent so the right detail pane reconfigures. Captures
    -- `kit._dungeonKey` (set in Configure) so the same factory closure works
    -- across all 8 dungeon pages — no per-dungeon factory.
    row:SetScript("OnClick", function()
        if not kit._spellId or not kit._dungeonKey then return end
        local s = GetState(kit._dungeonKey)
        if s.selectedSpellId == kit._spellId then return end
        s.selectedSpellId = kit._spellId
        if GUIFrame.RefreshContent then GUIFrame:RefreshContent() end
    end)

    return kit
end

local listRowPool = KE.FramePool:New(CreateListRowKit, ResetListRow)

GUIFrame:RegisterContentRebuildCallback("__DTimersListRowPool", function()
    listRowPool:ReleaseAll()
end)

-- Targeted refresh: walks active kits in the pool and recolors the
-- override stripe for the kit matching `spellId`. Cheap (~13 iterations
-- max); avoids a full RefreshContent on every per-spell toggle tick.
local function RefreshOverrideStripe(spellId)
    if not spellId then return end
    for i = 1, listRowPool._activeCount do
        local kit = listRowPool._kits[i]
        if kit and kit._spellId == spellId then
            ApplyOverrideStripe(kit, spellId)
            return
        end
    end
end

-- Targeted refresh: walks active kits in the pool and re-applies the
-- "S" sound indicator on the kit matching `spellId`. Called from the
-- Actions tab's sound dropdowns so the indicator flips on/off
-- immediately when a sound is set or cleared.
local function RefreshListRowSound(spellId)
    if not spellId then return end
    local DT = GetModule()
    local hasSound = (DT and DT.HasSpellSound and DT:HasSpellSound(spellId)) or false
    for i = 1, listRowPool._activeCount do
        local kit = listRowPool._kits[i]
        if kit and kit._spellId == spellId and kit.soundLabel then
            if hasSound then
                kit.soundLabel:SetText("S")
                kit.soundLabel:SetTextColor(1.0, 0.8, 0.3, 0.9)
            else
                kit.soundLabel:SetText("")
            end
            return
        end
    end
end

-- Targeted refresh: walks active kits in the pool and re-applies the
-- "Bar" / "Text" tag (text + color) on the kit matching `spellId`. Used
-- by the Display tab's mode toggle so the left-pane tag flips
-- immediately on click without a full RefreshContent (which would
-- destroy the toggle widget mid-animation).
local function RefreshListRowTag(spellId)
    if not spellId then return end
    local DT = GetModule()
    local effectiveDisplay = (DT and DT:GetSpellDisplay(spellId)) or "text"
    for i = 1, listRowPool._activeCount do
        local kit = listRowPool._kits[i]
        if kit and kit._spellId == spellId and kit.tagLabel then
            if effectiveDisplay == "bar" then
                kit.tagLabel:SetText("Bar")
                kit.tagLabel:SetTextColor(0.4, 0.7, 1.0, 0.9)
            else
                kit.tagLabel:SetText("Text")
                kit.tagLabel:SetTextColor(0.4, 1.0, 0.5, 0.9)
            end
            return
        end
    end
end

---------------------------------------------------------------------------------
-- Detail pane (right column). Built fresh per render — Show/Hide on tab
-- content frames toggles which body is visible. State writes go straight
-- through to DT helpers; selection (which spell) lives in _state.
---------------------------------------------------------------------------------

-- Builds the Visibility tab body. Today: a friendly "Default: X" subtitle +
-- three role toggle widgets + a Reset button. Future N13d/N13e slot below
-- the toggle row (Enable toggle, showAtSeconds slider).
--
-- Toggles use GUIFrame:CreateCheckbox (KE's slider-style toggle widget),
-- not bare UICheckButtonTemplate. Each occupies a fixed 110px column so
-- the three labels (Tank / Healer / DPS) line up cleanly without overlap.
local function BuildVisibilityTabBody(parent, spellId, spell)
    local DT = GetModule()
    local body = CreateFrame("Frame", nil, parent)
    body:SetAllPoints()

    -- Section: Master — section header above the Enable toggle for
    -- consistency with the two sections below.
    local masterHeader = body:CreateFontString(nil, "OVERLAY")
    KE:ApplyFontToText(masterHeader, "Expressway", 13, "OUTLINE")
    masterHeader:SetTextColor(KE.Theme.accent[1], KE.Theme.accent[2], KE.Theme.accent[3])
    masterHeader:SetText("Master")
    masterHeader:SetPoint("TOPLEFT", body, "TOPLEFT", DETAIL_PADDING, -DETAIL_PADDING)
    do
        local underline = body:CreateTexture(nil, "ARTWORK")
        underline:SetHeight(1)
        underline:SetColorTexture(KE.Theme.accent[1], KE.Theme.accent[2], KE.Theme.accent[3], 0.4)
        underline:SetPoint("LEFT", masterHeader, "RIGHT", 6, 0)
        underline:SetPoint("RIGHT", body, "RIGHT", -DETAIL_PADDING, 0)
        underline:SetPoint("TOP", masterHeader, "TOP", 0, -8)
    end

    -- Forward-declared list of "secondary" widgets (role toggles + slider).
    -- Populated AFTER they're created below; the Enable callback iterates
    -- this table to flip SetEnabled on each. Keeps the Enable toggle's
    -- click flow allocation-free — no RefreshContent destroys it mid-
    -- animation, no widget glitches.
    local secondaryWidgets = {}

    -- Enable toggle (top of Visibility tab body). Hard-disable filter that
    -- runs always-on (independent of the role master toggle). Default
    -- follows the curator's `disabled` flag (false unless set), with the
    -- user's tristate override winning when present.
    -- Don't collapse this to `DT and (not IsSpellDisabled) or true` —
    -- Lua's `and/or` precedence makes `false or true` always `true`,
    -- erasing the disabled-state read.
    local enableState = true
    if DT then enableState = not DT:IsSpellDisabled(spellId) end
    local enableToggle = GUIFrame:CreateCheckbox(body, "Enable this spell", {
        value = enableState,
        callback = function(checked)
            if not (DT and DT.SetSpellDisabled) then return end
            DT:SetSpellDisabled(spellId, not checked)
            RefreshOverrideStripe(spellId)
            -- Direct SetEnabled on captured secondary widgets — no
            -- RefreshContent needed (which would destroy this toggle
            -- mid-click-animation and leave it visually stuck).
            for _, w in ipairs(secondaryWidgets) do
                if w.SetEnabled then w:SetEnabled(checked) end
            end
        end,
    })
    enableToggle:SetPoint("TOPLEFT", masterHeader, "BOTTOMLEFT", 0, -10)
    enableToggle:SetWidth(200)

    -- Section: Who Sees It
    local whoHeader = CreateSectionHeader(body, enableToggle, "Who Sees It", 16)

    -- Sub-label for the role toggles (small grey caption, not a section
    -- header — the section header above already groups this content).
    local sectionLabel = body:CreateFontString(nil, "OVERLAY")
    KE:ApplyFontToText(sectionLabel, "Expressway", 12, "OUTLINE")
    sectionLabel:SetPoint("TOPLEFT", whoHeader, "BOTTOMLEFT", 0, -10)
    sectionLabel:SetTextColor(0.85, 0.85, 0.85)
    sectionLabel:SetText("Show this bar for:")

    -- Three role toggles laid out horizontally. Each toggle widget is a
    -- 36-tall row containing label-on-top + slider-toggle below; we anchor
    -- each one at a fixed column stride so labels align consistently.
    local TOGGLE_COL_STRIDE = 110
    local prev = nil
    local firstToggle = nil
    for i, roleEntry in ipairs(PLAYER_ROLE_TOKENS) do
        local startedOn = DT and DT:IsSpellAllowedForRole(spellId, roleEntry.token) or false
        local togRow = GUIFrame:CreateCheckbox(body, roleEntry.label, {
            value = startedOn,
            callback = function(checked)
                if not (DT and DT.SetSpellRoleOverride) then return end
                DT:SetSpellRoleOverride(spellId, roleEntry.token,
                                        checked and true or false)
                RefreshOverrideStripe(spellId)
            end,
        })
        if prev then
            togRow:SetPoint("TOPLEFT", prev, "TOPLEFT", TOGGLE_COL_STRIDE, 0)
        else
            togRow:SetPoint("TOPLEFT", sectionLabel, "BOTTOMLEFT", 0, -8)
            firstToggle = togRow
        end
        -- Toggle row's internal layout (label + slider) is 48px wide; row
        -- frame itself has no width set. Force a reasonable width so the
        -- column stride math is predictable across font widths.
        togRow:SetWidth(TOGGLE_COL_STRIDE - 8)
        prev = togRow
        secondaryWidgets[#secondaryWidgets + 1] = togRow
        -- Suppress luacheck unused (`i` reserved for future per-column tweaks)
        _ = i
    end

    -- Curator default — anchored BELOW the first toggle (Tank column),
    -- left-justified. The label can extend past the column's 110px width
    -- since "Default: Everyone (uncurated)" is wider than that; SetWordWrap
    -- false keeps it on one line. The next section (When It Appears)
    -- anchors to this label, not firstToggle, so it sits below correctly.
    local defaultLabel
    if firstToggle then
        defaultLabel = body:CreateFontString(nil, "OVERLAY")
        KE:ApplyFontToText(defaultLabel, "Expressway", 12, "OUTLINE")
        defaultLabel:SetPoint("TOPLEFT", firstToggle, "BOTTOMLEFT", 0, -8)
        defaultLabel:SetTextColor(CURATED_TAG_COLOR[1], CURATED_TAG_COLOR[2], CURATED_TAG_COLOR[3])
        defaultLabel:SetJustifyH("LEFT")
        defaultLabel:SetWordWrap(false)
        if spell.role then
            local friendly = ROLE_TAG_FRIENDLY[spell.role] or spell.role
            defaultLabel:SetText(string_format("Default: %s", friendly))
        else
            defaultLabel:SetText("Default: Everyone (uncurated)")
        end
    end

    -- Section: WHEN IT APPEARS — anchored to the defaultLabel so the
    -- section header sits below it (instead of overlapping). When the
    -- toggle list is empty (no firstToggle), fall back to sectionLabel.
    local whenHeader
    local whenAnchor = defaultLabel or firstToggle or sectionLabel
    if whenAnchor then
        whenHeader = CreateSectionHeader(body, whenAnchor, "When It Appears", 18)
    end

    -- "Reveal at (s remaining)" slider — per-spell visibility threshold.
    -- Resolves through DT:GetSpellShowAtSeconds (user override → curator
    -- default → group fallback). Slider directly sets the user override;
    -- Reset button clears it. 0 = always visible (overrides group hide).
    -- Range 0–30s, step 1 — matches the group sliders for consistency.
    -- Effective display drives which group's defaults apply. If the user
    -- has overridden bar→text, the showAt slider should default to the
    -- TextGroup's value, not the curator's BarGroup default.
    local effectiveDisplayForGroup = (DT and DT:GetSpellDisplay(spellId)) or spell.display or "text"
    local groupCfgKey = (effectiveDisplayForGroup == "bar") and "BarGroup" or "TextGroup"
    local groupCfg = (KE.db and KE.db.profile and KE.db.profile.Dungeons
                      and KE.db.profile.Dungeons.DungeonTimers
                      and KE.db.profile.Dungeons.DungeonTimers[groupCfgKey])
    local groupDefault = (groupCfg and groupCfg.ShowAtSeconds) or 0
    local effectiveValue = (DT and DT:GetSpellShowAtSeconds(spellId)) or groupDefault

    local revealSliderRow = GUIFrame:CreateRow(body, 36)
    if whenHeader then
        revealSliderRow:SetPoint("TOPLEFT", whenHeader, "BOTTOMLEFT", 0, -8)
        revealSliderRow:SetPoint("RIGHT", body, "RIGHT", -DETAIL_PADDING, 0)
    else
        revealSliderRow:SetPoint("TOPLEFT", body, "TOPLEFT", DETAIL_PADDING, -160)
        revealSliderRow:SetPoint("RIGHT", body, "RIGHT", -DETAIL_PADDING, 0)
    end
    local revealSlider = GUIFrame:CreateSlider(revealSliderRow, "Reveal at (s remaining)", {
        min = 0, max = 30, step = 1,
        value = effectiveValue,
        labelWidth = 140,
        callback = function(val)
            if not (DT and DT.SetSpellShowAtOverride) then return end
            DT:SetSpellShowAtOverride(spellId, val)
            RefreshOverrideStripe(spellId)
            -- Reveal-at value drives the preview's visible-window
            -- duration (countdown + cast = showAt), so re-render to
            -- match what the user will see in a real fight.
            RefreshSpellPreview()
        end,
    })
    revealSliderRow:AddWidget(revealSlider, 1.0, 0)
    secondaryWidgets[#secondaryWidgets + 1] = revealSlider

    -- Caption under the slider — explains the 0-position semantic and the
    -- group-default fallback so users don't have to guess.
    local sliderCaption = body:CreateFontString(nil, "OVERLAY")
    KE:ApplyFontToText(sliderCaption, "Expressway", 11, "OUTLINE")
    sliderCaption:SetPoint("TOPLEFT", revealSliderRow, "BOTTOMLEFT", 8, -12)
    sliderCaption:SetPoint("RIGHT", body, "RIGHT", -DETAIL_PADDING, 0)
    sliderCaption:SetJustifyH("LEFT")
    sliderCaption:SetTextColor(CURATED_TAG_COLOR[1], CURATED_TAG_COLOR[2], CURATED_TAG_COLOR[3])
    sliderCaption:SetText(string_format("0 = always visible. Group default: %d.", groupDefault))

    -- Inter-slider divider — visually separates the two timing knobs in
    -- the same section so they don't read as one continuous slider stack.
    -- Indented from the section edges so it reads as "inside" rather than
    -- a section break (which would imply a new section header).
    local sliderSpacer = body:CreateTexture(nil, "ARTWORK")
    sliderSpacer:SetHeight(1)
    sliderSpacer:SetColorTexture(KE.Theme.border[1], KE.Theme.border[2], KE.Theme.border[3], 0.35)
    sliderSpacer:SetPoint("LEFT",  body, "LEFT",  DETAIL_PADDING + 16, 0)
    sliderSpacer:SetPoint("RIGHT", body, "RIGHT", -DETAIL_PADDING - 16, 0)
    sliderSpacer:SetPoint("TOP",   sliderCaption, "BOTTOM", 0, -10)

    -- Time offset slider — per-spell adjustment to the curator's cast
    -- duration. Negative values shorten the bar's lifetime (curator
    -- overshot the impact moment); positive values extend it (curator
    -- undershot). Slider min adapts to the curated value: can't drop
    -- below -curated (which would create undefined negative-extension
    -- math). Setter also defensively clamps. Step 0.5 for fractional-
    -- second precision since cast times are often X.5s.
    local curatedCast = (DT and DT:GetSpellCuratorCastDuration(spellId)) or 0
    local timeOffsetMin = math.max(-3, -curatedCast)
    local timeOffsetMax = 5
    local timeOffsetValue = (DT and DT:GetSpellTimeOffset(spellId)) or 0

    local timeOffsetRow = GUIFrame:CreateRow(body, 36)
    timeOffsetRow:SetPoint("TOPLEFT", sliderSpacer, "BOTTOMLEFT", -16, -10)
    timeOffsetRow:SetPoint("RIGHT", body, "RIGHT", -DETAIL_PADDING, 0)
    local timeOffsetSlider = GUIFrame:CreateSlider(timeOffsetRow, "Time offset (s)", {
        min = timeOffsetMin, max = timeOffsetMax, step = 0.5,
        value = timeOffsetValue,
        labelWidth = 140,
        callback = function(val)
            if not (DT and DT.SetSpellTimeOffset) then return end
            DT:SetSpellTimeOffset(spellId, val)
            RefreshOverrideStripe(spellId)
            -- Time offset changes the bar's total duration (and
            -- therefore its visible drain rate during the cast phase),
            -- so re-render the preview to match.
            RefreshSpellPreview()
        end,
    })
    timeOffsetRow:AddWidget(timeOffsetSlider, 1.0, 0)
    secondaryWidgets[#secondaryWidgets + 1] = timeOffsetSlider

    -- Caption: branches on whether the curator set a cast extension at
    -- all. Spells with curated=0 (channels, no-cast spells) only support
    -- positive offsets, so the negative half of the explanation would
    -- mislead. Show only the relevant direction.
    local timeOffsetCaption = body:CreateFontString(nil, "OVERLAY")
    KE:ApplyFontToText(timeOffsetCaption, "Expressway", 11, "OUTLINE")
    timeOffsetCaption:SetPoint("TOPLEFT", timeOffsetRow, "BOTTOMLEFT", 8, -12)
    timeOffsetCaption:SetPoint("RIGHT", body, "RIGHT", -DETAIL_PADDING, 0)
    timeOffsetCaption:SetJustifyH("LEFT")
    timeOffsetCaption:SetTextColor(CURATED_TAG_COLOR[1], CURATED_TAG_COLOR[2], CURATED_TAG_COLOR[3])
    if curatedCast > 0 then
        timeOffsetCaption:SetText(string_format(
            "Negative = ends earlier. Positive = ends later. Built-in cast: %.1fs.",
            curatedCast))
    else
        timeOffsetCaption:SetText("Positive = ends later. No built-in cast extension.")
    end

    -- Reset overrides button — clears BOTH role overrides AND disable
    -- state for this spell so toggles return to curated default values.
    -- Uses GUIFrame:CreateButton (KE button factory) so hover styling
    -- matches the rest of the addon (Nicknames Remove, Reset All Triggers).
    -- Red text + StaticPopup confirmation signal destructive intent.
    --
    -- Anchored TOP-down (under the time-offset caption) instead of
    -- bottom-up. The rightCol's min height is sized for the tallest tab
    -- (Display) and dominates when listY < that minimum, so a bottom-
    -- anchored Reset button leaves a big visual gap between the
    -- "When It Appears" sliders and the button. Top-down anchoring
    -- keeps the button right below the content; empty space (when any)
    -- now accumulates at the bottom edge of the panel where it reads
    -- as natural margin rather than a layout glitch.
    local resetRow = GUIFrame:CreateRow(body, 28)
    resetRow:SetPoint("LEFT", body, "LEFT", DETAIL_PADDING, 0)
    resetRow:SetPoint("RIGHT", body, "RIGHT", -DETAIL_PADDING, 0)
    resetRow:SetPoint("TOP", timeOffsetCaption, "BOTTOM", 0, -16)
    local resetBtn = GUIFrame:CreateButton(resetRow, "Reset spell to default", {
        height = 26,
        callback = function()
            if not (DT and DT.ResetSpellOverrides) then return end
            KE:CreatePrompt(
                "Reset spell to default",
                "Clear all overrides for this spell?\n\nVisibility, display, and actions overrides will revert to curated defaults. This cannot be undone.",
                false, nil, false, nil, nil, nil, nil,
                function()
                    DT:ResetSpellOverrides(spellId)
                    -- Force the preview to re-render. RefreshContent's
                    -- ShowSpellPreview call would short-circuit on the
                    -- same spellId guard otherwise, leaving the preview
                    -- stuck on pre-reset visuals.
                    if DT.RefreshSpellPreview then DT:RefreshSpellPreview() end
                    if GUIFrame.RefreshContent then GUIFrame:RefreshContent() end
                end,
                nil, "Reset", "Cancel"
            )
        end,
    })
    if resetBtn.text then
        resetBtn.text:SetTextColor(REMOVE_COLOR[1], REMOVE_COLOR[2], REMOVE_COLOR[3], REMOVE_COLOR[4])
    end
    resetRow:AddWidget(resetBtn, 1.0, 0)

    -- Initial disabled-state propagation. When the spell starts off
    -- disabled, role toggles + reveal slider are inert — grey them out
    -- so the UX signals that. The Enable toggle's callback handles
    -- subsequent toggles via the same secondaryWidgets list.
    if not enableState then
        for _, w in ipairs(secondaryWidgets) do
            if w.SetEnabled then w:SetEnabled(false) end
        end
    end

    return body
end

-- Builds the Actions tab body. Two sound dropdowns: "On Show" plays
-- when the bar becomes visible (after the showAt delay if any); "On
-- Hide" plays when it expires or is cancelled. Selecting a sound also
-- previews it so users can hear what they're picking. "None" entry
-- clears the override.
local function BuildActionsTabBody(parent, spellId)
    local DT = GetModule()
    local body = CreateFrame("Frame", nil, parent)
    body:SetAllPoints()

    -- Build sound list from LibSharedMedia. "None" prepended explicitly
    -- since LSM doesn't include it; the setter recognizes "None" as
    -- "no sound" and prunes the entry.
    local soundList = { ["None"] = "None" }
    local LSM = KE.LSM
    if LSM then
        for name in pairs(LSM:HashTable("sound")) do soundList[name] = name end
    end

    local function PreviewSound(soundKey)
        if not soundKey or soundKey == "None" or soundKey == "" then return end
        if not LSM then return end
        local file = LSM:Fetch("sound", soundKey)
        if file then PlaySoundFile(file, "Master") end
    end

    local secondaryWidgets = {}

    ---------------------------------------------------------------------------
    -- Section: On Show
    ---------------------------------------------------------------------------
    local showHeader = body:CreateFontString(nil, "OVERLAY")
    KE:ApplyFontToText(showHeader, "Expressway", 13, "OUTLINE")
    showHeader:SetTextColor(KE.Theme.accent[1], KE.Theme.accent[2], KE.Theme.accent[3])
    showHeader:SetText("On Show")
    showHeader:SetPoint("TOPLEFT", body, "TOPLEFT", DETAIL_PADDING, -DETAIL_PADDING)
    do
        local underline = body:CreateTexture(nil, "ARTWORK")
        underline:SetHeight(1)
        underline:SetColorTexture(KE.Theme.accent[1], KE.Theme.accent[2], KE.Theme.accent[3], 0.4)
        underline:SetPoint("LEFT", showHeader, "RIGHT", 6, 0)
        underline:SetPoint("RIGHT", body, "RIGHT", -DETAIL_PADDING, 0)
        underline:SetPoint("TOP", showHeader, "TOP", 0, -8)
    end

    local showRow = GUIFrame:CreateRow(body, 36)
    showRow:SetPoint("TOPLEFT", showHeader, "BOTTOMLEFT", 0, -10)
    showRow:SetPoint("RIGHT", body, "RIGHT", -DETAIL_PADDING, 0)
    local showDropdown = GUIFrame:CreateDropdown(showRow, "Sound when bar appears", {
        options = soundList,
        value = (DT and DT:GetSpellSoundOnShow(spellId)) or "None",
        callback = function(key)
            if not (DT and DT.SetSpellSoundOnShow) then return end
            DT:SetSpellSoundOnShow(spellId, key)
            PreviewSound(key)
            RefreshOverrideStripe(spellId)
            RefreshListRowSound(spellId)
        end,
        searchable = true,
    })
    showRow:AddWidget(showDropdown, 0.7)
    secondaryWidgets[#secondaryWidgets + 1] = showDropdown

    -- Test button — replays whatever sound is currently saved (or no-op
    -- when set to "None"). Reads from DB so it always reflects the
    -- current selection without needing a dropdown:GetValue() call.
    -- yOffset=-12 vertically centers the 28px button on the dropdown
    -- bar (which sits at row + (0, -14) and is 24px tall, center y=-26;
    -- button top at -12 puts its center at -26).
    local showTestBtn = GUIFrame:CreateButton(showRow, "Test", {
        height = 28,
        callback = function()
            if not (DT and DT.GetSpellSoundOnShow) then return end
            PreviewSound(DT:GetSpellSoundOnShow(spellId))
        end,
    })
    showRow:AddWidget(showTestBtn, 0.3, 0, 0, -12)
    secondaryWidgets[#secondaryWidgets + 1] = showTestBtn

    local showCaption = body:CreateFontString(nil, "OVERLAY")
    KE:ApplyFontToText(showCaption, "Expressway", 11, "OUTLINE")
    showCaption:SetPoint("TOPLEFT", showRow, "BOTTOMLEFT", 0, -8)
    showCaption:SetPoint("RIGHT", body, "RIGHT", -DETAIL_PADDING, 0)
    showCaption:SetJustifyH("LEFT")
    showCaption:SetTextColor(CURATED_TAG_COLOR[1], CURATED_TAG_COLOR[2],
                             CURATED_TAG_COLOR[3])
    showCaption:SetText(
        "Plays when the bar appears on screen (after the Reveal at delay if set).")

    ---------------------------------------------------------------------------
    -- Section: On Hide
    ---------------------------------------------------------------------------
    local hideHeader = CreateSectionHeader(body, showCaption, "On Hide", 22)

    local hideRow = GUIFrame:CreateRow(body, 36)
    hideRow:SetPoint("TOPLEFT", hideHeader, "BOTTOMLEFT", 0, -10)
    hideRow:SetPoint("RIGHT", body, "RIGHT", -DETAIL_PADDING, 0)
    local hideDropdown = GUIFrame:CreateDropdown(hideRow, "Sound when bar disappears", {
        options = soundList,
        value = (DT and DT:GetSpellSoundOnHide(spellId)) or "None",
        callback = function(key)
            if not (DT and DT.SetSpellSoundOnHide) then return end
            DT:SetSpellSoundOnHide(spellId, key)
            PreviewSound(key)
            RefreshOverrideStripe(spellId)
            RefreshListRowSound(spellId)
        end,
        searchable = true,
    })
    hideRow:AddWidget(hideDropdown, 0.7)
    secondaryWidgets[#secondaryWidgets + 1] = hideDropdown

    local hideTestBtn = GUIFrame:CreateButton(hideRow, "Test", {
        height = 28,
        callback = function()
            if not (DT and DT.GetSpellSoundOnHide) then return end
            PreviewSound(DT:GetSpellSoundOnHide(spellId))
        end,
    })
    hideRow:AddWidget(hideTestBtn, 0.3, 0, 0, -12)
    secondaryWidgets[#secondaryWidgets + 1] = hideTestBtn

    local hideCaption = body:CreateFontString(nil, "OVERLAY")
    KE:ApplyFontToText(hideCaption, "Expressway", 11, "OUTLINE")
    hideCaption:SetPoint("TOPLEFT", hideRow, "BOTTOMLEFT", 0, -8)
    hideCaption:SetPoint("RIGHT", body, "RIGHT", -DETAIL_PADDING, 0)
    hideCaption:SetJustifyH("LEFT")
    hideCaption:SetTextColor(CURATED_TAG_COLOR[1], CURATED_TAG_COLOR[2],
                             CURATED_TAG_COLOR[3])
    hideCaption:SetText(
        "Plays when the bar finishes naturally or is interrupted. "
        .. "Doesn't fire on encounter wipes (mass cleanup).")

    -- Initial disabled-state propagation. Mirror the other tabs.
    if DT and DT:IsSpellDisabled(spellId) then
        for _, w in ipairs(secondaryWidgets) do
            if w.SetEnabled then w:SetEnabled(false) end
        end
    end

    return body
end

---------------------------------------------------------------------------------
-- Segmented two-button widget. Used by the Display tab's bar/text toggle.
-- One button per option; clicking a non-active option flips the state and
-- fires the onChange callback. Active button gets accent border + accent-
-- tinted fill; inactive gets the standard border with a hover-to-accent
-- effect (same visual grammar as CreateButton's hover). Lighter than two
-- CreateButton widgets because we don't need the animation group — one
-- click = one repaint, no transition.
--
-- Returns the row frame and a `SetActive(id)` method on the row so the
-- caller can flip selection without rebuilding. SetEnabled toggles the
-- whole widget's interactivity (used by the disabled-spell propagation).
---------------------------------------------------------------------------------
local SEG_BTN_WIDTH    = 100
local SEG_BTN_HEIGHT   = 30
local SEG_BTN_SPACING  = 4

local function CreateSegmentedToggle(parent, options, currentId, onChange)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(SEG_BTN_HEIGHT)
    row:SetWidth((#options * SEG_BTN_WIDTH) + ((#options - 1) * SEG_BTN_SPACING))

    local buttons = {}
    local enabled = true

    local function PaintButton(btn, isActive, isHover)
        local T = KE.Theme
        if not enabled then
            btn:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
            btn:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
            btn:SetAlpha(0.5)
            if btn.text then btn.text:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1) end
            return
        end
        btn:SetAlpha(1)
        if isActive then
            -- Active = accent-tinted fill + accent border. Brighter than hover
            -- so the selected option reads as "stuck on" not "transient hover".
            btn:SetBackdropColor(T.accent[1] * 0.35, T.accent[2] * 0.35, T.accent[3] * 0.35, 0.9)
            btn:SetBackdropBorderColor(T.accent[1], T.accent[2], T.accent[3], 1)
            if btn.text then btn.text:SetTextColor(1, 1, 1, 1) end
        elseif isHover then
            -- Hover on inactive: accent border only, fill stays neutral.
            btn:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
            btn:SetBackdropBorderColor(T.accent[1], T.accent[2], T.accent[3], 1)
            if btn.text then btn.text:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1) end
        else
            -- Idle inactive
            btn:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
            btn:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
            if btn.text then btn.text:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1) end
        end
    end

    local activeId = currentId

    local function RepaintAll()
        for _, btn in ipairs(buttons) do
            PaintButton(btn, btn._id == activeId, false)
        end
    end

    for i, opt in ipairs(options) do
        local btn = CreateFrame("Button", nil, row, "BackdropTemplate")
        btn:SetSize(SEG_BTN_WIDTH, SEG_BTN_HEIGHT)
        btn:SetPoint("LEFT", row, "LEFT",
            (i - 1) * (SEG_BTN_WIDTH + SEG_BTN_SPACING), 0)
        btn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        btn._id = opt.id

        btn.text = btn:CreateFontString(nil, "OVERLAY")
        KE:ApplyThemeFont(btn.text, "normal")
        btn.text:SetPoint("CENTER")
        btn.text:SetText(opt.label)

        btn:SetScript("OnEnter", function(self)
            if not enabled then return end
            if self._id ~= activeId then
                PaintButton(self, false, true)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if not enabled then return end
            if self._id ~= activeId then
                PaintButton(self, false, false)
            end
        end)
        btn:SetScript("OnClick", function(self)
            if not enabled then return end
            if self._id == activeId then return end
            activeId = self._id
            RepaintAll()
            if onChange then onChange(self._id) end
        end)

        buttons[#buttons + 1] = btn
    end

    RepaintAll()

    function row:SetActive(newId)
        if newId == activeId then return end
        activeId = newId
        RepaintAll()
    end

    function row:SetEnabled(isEnabled)
        enabled = isEnabled and true or false
        RepaintAll()
        for _, btn in ipairs(buttons) do
            btn:EnableMouse(enabled)
        end
    end

    return row
end

-- Builds the Display tab body. N13f's first knob: bar/text mode toggle.
-- Future knobs (custom displayText, format string, color override) slot
-- below the mode section as additional CreateSectionHeader blocks.
local function BuildDisplayTabBody(parent, spellId, spell)
    local DT = GetModule()
    local body = CreateFrame("Frame", nil, parent)
    body:SetAllPoints()

    -- Section: Display Mode
    local modeHeader = body:CreateFontString(nil, "OVERLAY")
    KE:ApplyFontToText(modeHeader, "Expressway", 13, "OUTLINE")
    modeHeader:SetTextColor(KE.Theme.accent[1], KE.Theme.accent[2], KE.Theme.accent[3])
    modeHeader:SetText("Display Mode")
    modeHeader:SetPoint("TOPLEFT", body, "TOPLEFT", DETAIL_PADDING, -DETAIL_PADDING)
    do
        local underline = body:CreateTexture(nil, "ARTWORK")
        underline:SetHeight(1)
        underline:SetColorTexture(KE.Theme.accent[1], KE.Theme.accent[2], KE.Theme.accent[3], 0.4)
        underline:SetPoint("LEFT", modeHeader, "RIGHT", 6, 0)
        underline:SetPoint("RIGHT", body, "RIGHT", -DETAIL_PADDING, 0)
        underline:SetPoint("TOP", modeHeader, "TOP", 0, -8)
    end

    -- Sub-label above the toggle row.
    local sectionLabel = body:CreateFontString(nil, "OVERLAY")
    KE:ApplyFontToText(sectionLabel, "Expressway", 12, "OUTLINE")
    sectionLabel:SetPoint("TOPLEFT", modeHeader, "BOTTOMLEFT", 0, -14)
    sectionLabel:SetTextColor(0.85, 0.85, 0.85)
    sectionLabel:SetText("Render this ability as:")

    local secondaryWidgets = {}

    -- Forward declared. Assigned after the Color section's ColorPicker is
    -- built (see end of this function). Re-syncs the picker swatch when
    -- the EFFECTIVE color changes — e.g. user picks a different preset via
    -- the EditBox or chip grid, and the picker should now reflect the
    -- preset-color fallback instead of the old preset's color. Called from
    -- displayText change handlers below; nil-checked because the picker
    -- doesn't exist when those handlers are first wired up.
    local refreshColorPicker

    local currentMode = (DT and DT:GetSpellDisplay(spellId)) or "text"
    local toggle = CreateSegmentedToggle(body,
        { { id = "bar", label = "Bar" }, { id = "text", label = "Text" } },
        currentMode,
        function(newId)
            if not (DT and DT.SetSpellDisplayOverride) then return end
            DT:SetSpellDisplayOverride(spellId, newId)
            -- Live updates without RefreshContent: the override stripe
            -- on the list row + the Bar/Text tag on that same row both
            -- need to reflect the new state, and the in-game preview
            -- bar needs to re-render in the new mode.
            RefreshOverrideStripe(spellId)
            RefreshListRowTag(spellId)
            RefreshSpellPreview()
        end)
    toggle:SetPoint("TOPLEFT", sectionLabel, "BOTTOMLEFT", 0, -8)
    secondaryWidgets[#secondaryWidgets + 1] = toggle

    -- Curator default caption — anchored next to the buttons, vertically
    -- centered on the toggle row. Sits ~16px right of the segmented
    -- toggle's RIGHT edge (which is at the second button's right side)
    -- so the "Default: X" reads as a label for the button cluster, not
    -- a floating tag at the panel's far edge.
    local curatedDisplay = (DT and DT:GetSpellCuratorDisplay(spellId)) or "text"
    local curatedFriendly = (curatedDisplay == "bar") and "Bar" or "Text"
    local defaultLabel = body:CreateFontString(nil, "OVERLAY")
    KE:ApplyFontToText(defaultLabel, "Expressway", 12, "OUTLINE")
    defaultLabel:SetPoint("LEFT", toggle, "RIGHT", 16, 0)
    defaultLabel:SetTextColor(CURATED_TAG_COLOR[1], CURATED_TAG_COLOR[2], CURATED_TAG_COLOR[3])
    defaultLabel:SetJustifyH("LEFT")
    defaultLabel:SetText(string_format("Default: %s", curatedFriendly))

    -- Caption below the toggle — explains what each mode looks like.
    local caption = body:CreateFontString(nil, "OVERLAY")
    KE:ApplyFontToText(caption, "Expressway", 11, "OUTLINE")
    caption:SetPoint("TOPLEFT", toggle, "BOTTOMLEFT", 0, -12)
    caption:SetPoint("RIGHT", body, "RIGHT", -DETAIL_PADDING, 0)
    caption:SetJustifyH("LEFT")
    caption:SetTextColor(CURATED_TAG_COLOR[1], CURATED_TAG_COLOR[2], CURATED_TAG_COLOR[3])
    caption:SetText(
        "Bar = filled progress bar with icon and timer overlay.\n"
        .. "Text = single-line label that updates each second.")

    ---------------------------------------------------------------------------
    -- Section: Custom Label
    ---------------------------------------------------------------------------
    local labelHeader = CreateSectionHeader(body, caption, "Custom Label", 22)

    -- EditBox row. CreateEditBox renders a label-on-top + 24px input field
    -- inside a self-anchored row frame; we stuff it into a CreateRow + AddWidget
    -- so it stretches to fill the right pane width, mirroring how
    -- DisintegrateTicks / FocusMarker use the widget.
    local labelEditRow = GUIFrame:CreateRow(body, 40)
    labelEditRow:SetPoint("TOPLEFT", labelHeader, "BOTTOMLEFT", 0, -12)
    labelEditRow:SetPoint("RIGHT", body, "RIGHT", -DETAIL_PADDING, 0)

    local currentOverride = (DT and DT:GetSpellDisplayTextOverride(spellId)) or ""
    local labelEdit = GUIFrame:CreateEditBox(labelEditRow, "Override", {
        value = currentOverride,
        callback = function(text)
            if not (DT and DT.SetSpellDisplayTextOverride) then return end
            DT:SetSpellDisplayTextOverride(spellId, text)
            -- Live updates: override stripe + color picker (preset fallback
            -- changed) + preview bar's label. The list-row tag (Bar/Text)
            -- doesn't depend on displayText, so no RefreshListRowTag here.
            RefreshOverrideStripe(spellId)
            if refreshColorPicker then refreshColorPicker() end
            RefreshSpellPreview()
        end,
        tooltip = "Custom short label for the bar (e.g. DODGE, HIDE, SOAK).\n"
               .. "Empty = use built-in label.\n"
               .. "Typing a preset name (DODGE, FEET, KICK, etc.) picks up\n"
               .. "the matching color automatically.",
    })
    labelEditRow:AddWidget(labelEdit, 1)
    secondaryWidgets[#secondaryWidgets + 1] = labelEdit

    -- Caption below the editbox. Reads the curator's default. When no
    -- curated value exists, the bar falls back to the BigWigs spell name —
    -- explain that so users know what "default" looks like.
    local labelCaption = body:CreateFontString(nil, "OVERLAY")
    KE:ApplyFontToText(labelCaption, "Expressway", 11, "OUTLINE")
    labelCaption:SetPoint("TOPLEFT", labelEditRow, "BOTTOMLEFT", 0, -8)
    labelCaption:SetPoint("RIGHT", body, "RIGHT", -DETAIL_PADDING, 0)
    labelCaption:SetJustifyH("LEFT")
    labelCaption:SetTextColor(CURATED_TAG_COLOR[1], CURATED_TAG_COLOR[2], CURATED_TAG_COLOR[3])
    local curatedLabel = (DT and DT:GetSpellCuratorDisplayText(spellId))
    if curatedLabel and curatedLabel ~= "" then
        labelCaption:SetText(string_format(
            "Empty = use the built-in label. Default: %s.", curatedLabel))
    else
        labelCaption:SetText(
            "Empty = show the spell's full name. No built-in short label.")
    end

    ---------------------------------------------------------------------------
    -- Section: Available Presets
    -- Clickable chips, one per DISPLAY_PRESET. Click writes the preset's
    -- canonical label into the override + updates the editbox + refreshes
    -- the preview. Presets render in their own preset color so users can
    -- see the palette at a glance.
    ---------------------------------------------------------------------------
    local presetHeader = CreateSectionHeader(body, labelCaption, "Available Presets", 22)

    -- Sort preset keys alphabetically for stable display order. pairs()
    -- is hash-order which shuffles across reloads.
    local presetKeys = {}
    if DT and DT.DISPLAY_PRESETS then
        for k in pairs(DT.DISPLAY_PRESETS) do presetKeys[#presetKeys + 1] = k end
        table_sort(presetKeys)
    end

    -- Layout grid: 5 chips per row. Each chip is 80×24 with 4px gap. Last
    -- row left-aligned even if not full. Anchored to the section header
    -- and stacked downward.
    local CHIP_WIDTH   = 80
    local CHIP_HEIGHT  = 24
    local CHIP_HGAP    = 4
    local CHIP_VGAP    = 4
    local CHIPS_PER_ROW = 5

    local presetGrid = CreateFrame("Frame", nil, body)
    presetGrid:SetPoint("TOPLEFT", presetHeader, "BOTTOMLEFT", 0, -10)
    presetGrid:SetPoint("RIGHT", body, "RIGHT", -DETAIL_PADDING, 0)

    for i, key in ipairs(presetKeys) do
        local p = DT.DISPLAY_PRESETS[key]
        local row = math.floor((i - 1) / CHIPS_PER_ROW)
        local col = (i - 1) % CHIPS_PER_ROW

        local chip = CreateFrame("Button", nil, presetGrid, "BackdropTemplate")
        chip:SetSize(CHIP_WIDTH, CHIP_HEIGHT)
        chip:SetPoint("TOPLEFT", presetGrid, "TOPLEFT",
            col * (CHIP_WIDTH + CHIP_HGAP),
            -row * (CHIP_HEIGHT + CHIP_VGAP))
        chip:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        chip:SetBackdropColor(KE.Theme.bgMedium[1], KE.Theme.bgMedium[2],
                              KE.Theme.bgMedium[3], 1)
        chip:SetBackdropBorderColor(KE.Theme.border[1], KE.Theme.border[2],
                                    KE.Theme.border[3], 1)

        local txt = chip:CreateFontString(nil, "OVERLAY")
        KE:ApplyFontToText(txt, "Expressway", 12, "OUTLINE")
        txt:SetPoint("CENTER")
        txt:SetText(p.label)
        -- Render the chip text in the preset's own color so the palette
        -- is self-documenting — DODGE shows orange, TANK HIT shows red,
        -- etc. The bar will look identical when this preset is applied.
        txt:SetTextColor(p.color[1], p.color[2], p.color[3], 1)
        chip._txt = txt

        chip:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(KE.Theme.accent[1], KE.Theme.accent[2],
                                        KE.Theme.accent[3], 1)
        end)
        chip:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(KE.Theme.border[1], KE.Theme.border[2],
                                        KE.Theme.border[3], 1)
        end)

        local chipLabel = p.label  -- captured for the click closure
        chip:SetScript("OnClick", function()
            if not (DT and DT.SetSpellDisplayTextOverride) then return end
            DT:SetSpellDisplayTextOverride(spellId, chipLabel)
            -- Sync the editbox with whatever was actually stored. If the
            -- click matched the curator's default, the setter pruned and
            -- the editbox should clear; otherwise it shows the new value.
            local actual = DT:GetSpellDisplayTextOverride(spellId) or ""
            if labelEdit.SetValue then labelEdit:SetValue(actual, true) end
            RefreshOverrideStripe(spellId)
            if refreshColorPicker then refreshColorPicker() end
            RefreshSpellPreview()
        end)

        function chip:SetEnabled(enabled)
            if enabled then
                self:Enable()
                self:EnableMouse(true)
                self:SetAlpha(1)
            else
                self:Disable()
                self:EnableMouse(false)
                self:SetAlpha(0.5)
            end
        end

        secondaryWidgets[#secondaryWidgets + 1] = chip
    end

    -- Size the grid frame to its content height.
    if #presetKeys > 0 then
        local totalRows = math.ceil(#presetKeys / CHIPS_PER_ROW)
        presetGrid:SetHeight(totalRows * CHIP_HEIGHT
                             + (totalRows - 1) * CHIP_VGAP)
    else
        presetGrid:SetHeight(1)
    end

    -- Caption under the grid — explains the click + custom-text behavior.
    local presetCaption = body:CreateFontString(nil, "OVERLAY")
    KE:ApplyFontToText(presetCaption, "Expressway", 11, "OUTLINE")
    presetCaption:SetPoint("TOPLEFT", presetGrid, "BOTTOMLEFT", 0, -8)
    presetCaption:SetPoint("RIGHT", body, "RIGHT", -DETAIL_PADDING, 0)
    presetCaption:SetJustifyH("LEFT")
    presetCaption:SetTextColor(CURATED_TAG_COLOR[1], CURATED_TAG_COLOR[2],
                               CURATED_TAG_COLOR[3])
    presetCaption:SetText(
        "Click a preset to use it. Each preset comes with its own color.")

    ---------------------------------------------------------------------------
    -- Section: Time Format
    -- Per-spell decimal threshold. Below the threshold, timer text shows
    -- one decimal ("0.8"); at or above, whole seconds ("5"). Slider 0 →
    -- always integer; slider 30 (max) → always decimal (preserves the
    -- pre-knob behavior, matches the module default).
    ---------------------------------------------------------------------------
    local timeFmtHeader = CreateSectionHeader(body, presetCaption, "Time Format", 22)

    local currentThreshold = (DT and DT:GetSpellDecimalThreshold(spellId)) or 30
    local thresholdRow = GUIFrame:CreateRow(body, 36)
    thresholdRow:SetPoint("TOPLEFT", timeFmtHeader, "BOTTOMLEFT", 0, -10)
    thresholdRow:SetPoint("RIGHT", body, "RIGHT", -DETAIL_PADDING, 0)
    local thresholdSlider = GUIFrame:CreateSlider(thresholdRow,
        "Show decimals under (s)", {
        min = 0, max = 30, step = 1,
        value = currentThreshold,
        labelWidth = 160,
        callback = function(val)
            if not (DT and DT.SetSpellDecimalThreshold) then return end
            DT:SetSpellDecimalThreshold(spellId, val)
            RefreshOverrideStripe(spellId)
            -- Threshold changes the timer string format; re-render the
            -- preview so the user sees the effect immediately.
            RefreshSpellPreview()
        end,
    })
    thresholdRow:AddWidget(thresholdSlider, 1.0, 0)
    secondaryWidgets[#secondaryWidgets + 1] = thresholdSlider

    -- Caption under the slider — explains the boundary semantics.
    -- x=0 (not 8) so subsequent CreateSectionHeader chains don't inherit
    -- an indent. Other Display-tab captions all use x=0; mirroring keeps
    -- the section-header anchor chain at body.left + DETAIL_PADDING.
    local thresholdCaption = body:CreateFontString(nil, "OVERLAY")
    KE:ApplyFontToText(thresholdCaption, "Expressway", 11, "OUTLINE")
    thresholdCaption:SetPoint("TOPLEFT", thresholdRow, "BOTTOMLEFT", 0, -12)
    thresholdCaption:SetPoint("RIGHT", body, "RIGHT", -DETAIL_PADDING, 0)
    thresholdCaption:SetJustifyH("LEFT")
    thresholdCaption:SetTextColor(CURATED_TAG_COLOR[1], CURATED_TAG_COLOR[2],
                                  CURATED_TAG_COLOR[3])
    thresholdCaption:SetText(
        "0 = always show whole seconds. 30 = always show decimals (default).")

    ---------------------------------------------------------------------------
    -- Section: Spell Color
    -- Per-spell color override. Applies in BOTH display modes — bar mode
    -- uses it as the StatusBar fill; text mode uses it as the label
    -- color. ColorPicker shows the EFFECTIVE color (override → preset →
    -- default) so users see the current color regardless of override
    -- state. "Reset to default" button clears the override and the
    -- picker re-syncs to the preset/default chain. Section name avoids
    -- "Bar Color" because it'd misleadingly suggest bar-mode-only scope.
    ---------------------------------------------------------------------------
    local colorHeader = CreateSectionHeader(body, thresholdCaption, "Color", 22)

    -- Resolve the effective color for the picker's initial value:
    -- override → preset (from effective displayText) → default blue.
    local DEFAULT_BAR_COLOR_LOCAL = { 0.3, 0.5, 0.9 }
    local function ResolveEffectiveColor()
        if not DT then return DEFAULT_BAR_COLOR_LOCAL end
        local override = DT:GetSpellColorOverride(spellId)
        if override then return override end
        -- Effective displayText = override → curator. Find a matching
        -- preset and use its color; otherwise fall back to default.
        local effectiveText = DT:GetSpellDisplayText(spellId)
        if effectiveText and DT.DISPLAY_PRESETS then
            local upper = effectiveText:upper()
            local preset = DT.DISPLAY_PRESETS[upper]
            if not preset then
                for _, p in pairs(DT.DISPLAY_PRESETS) do
                    if p.label:upper() == upper then preset = p; break end
                end
            end
            -- Alias check ("ADDS" → ADD's color) when no direct match.
            -- Mirrors ResolveDisplayPreset's alias path so the picker
            -- swatch matches what the bar will actually render.
            if not preset and DT.DISPLAY_PRESET_ALIASES then
                local aliasKey = DT.DISPLAY_PRESET_ALIASES[upper]
                if aliasKey then preset = DT.DISPLAY_PRESETS[aliasKey] end
            end
            if preset then return preset.color end
        end
        return DEFAULT_BAR_COLOR_LOCAL
    end

    local effectiveColor = ResolveEffectiveColor()

    -- Bar Color row uses direct positioning instead of CreateRow + AddWidget
    -- because AddWidget stretches widgets to fill their widthPct slice,
    -- which forces the swatch's row to be ~half the body width (lots of
    -- dead space on the swatch's right) AND stretches the Reset button
    -- from its natural 130px to ~220px. Direct positioning lets each
    -- widget keep its natural width and the swatch sits next to the
    -- button instead of half a screen apart.
    local colorRow = CreateFrame("Frame", nil, body)
    colorRow:SetHeight(36)
    colorRow:SetPoint("TOPLEFT", colorHeader, "BOTTOMLEFT", 0, -10)
    colorRow:SetPoint("RIGHT", body, "RIGHT", -DETAIL_PADDING, 0)

    local colorPicker = GUIFrame:CreateColorPicker(colorRow, "Color", {
        color = { effectiveColor[1], effectiveColor[2], effectiveColor[3], 1 },
        callback = function(r, g, b)
            if not (DT and DT.SetSpellColorOverride) then return end
            DT:SetSpellColorOverride(spellId, { r, g, b })
            RefreshOverrideStripe(spellId)
            RefreshSpellPreview()
        end,
        tooltip = "Custom spell color. Applies to the bar fill in Bar mode and the label in Text mode.\n"
               .. "Overrides the preset color (e.g. DODGE for orange).\n"
               .. "Click 'Reset to default' to clear the override and use the preset.",
    })
    -- Picker's natural content (label + swatch + hex) is ~120px; pin to
    -- the row's left edge with a fixed width so the swatch lands exactly
    -- where other left-aligned content lives.
    colorPicker:ClearAllPoints()
    colorPicker:SetPoint("TOPLEFT", colorRow, "TOPLEFT", 0, 0)
    colorPicker:SetWidth(150)

    local resetColorBtn = GUIFrame:CreateButton(colorRow, "Reset to default", {
        height = 24,
        width = 130,
        callback = function()
            if not (DT and DT.SetSpellColorOverride) then return end
            DT:SetSpellColorOverride(spellId, nil)
            -- Re-sync the picker to the now-effective color (preset or
            -- default). SetColor invokes the picker's UpdateColor which
            -- fires our callback — but our callback would WRITE that
            -- color as a new override, defeating the reset. Use silent
            -- write: temporarily clear _callback, SetColor, restore.
            local saved = colorPicker._callback
            colorPicker._callback = nil
            local newColor = ResolveEffectiveColor()
            colorPicker:SetColor(newColor[1], newColor[2], newColor[3], 1)
            colorPicker._callback = saved
            RefreshOverrideStripe(spellId)
            RefreshSpellPreview()
        end,
    })
    -- Sit the button next to the picker, vertically centered on the
    -- swatch (picker's swatch is at row + (0, -14), 24px tall, so its
    -- vertical center is at y = -14 - 12 = -26 from row top; button is
    -- 24px tall, top at y = -26 + 12 = -14).
    resetColorBtn:ClearAllPoints()
    resetColorBtn:SetPoint("LEFT", colorPicker, "RIGHT", 12, -7)

    secondaryWidgets[#secondaryWidgets + 1] = colorPicker
    secondaryWidgets[#secondaryWidgets + 1] = resetColorBtn

    -- Assign the forward-declared refreshColorPicker now that the picker
    -- itself exists. Same silent-write pattern as Reset (clear _callback,
    -- SetColor, restore) so the re-sync doesn't fire a feedback-write
    -- that would store the resolved color as a fresh override.
    refreshColorPicker = function()
        if not colorPicker then return end
        local newColor = ResolveEffectiveColor()
        local saved = colorPicker._callback
        colorPicker._callback = nil
        colorPicker:SetColor(newColor[1], newColor[2], newColor[3], 1)
        colorPicker._callback = saved
    end

    -- Caption under the color row — explains the resolution chain so
    -- users understand what "default" means in this context.
    local colorCaption = body:CreateFontString(nil, "OVERLAY")
    KE:ApplyFontToText(colorCaption, "Expressway", 11, "OUTLINE")
    colorCaption:SetPoint("TOPLEFT", colorRow, "BOTTOMLEFT", 0, -8)
    colorCaption:SetPoint("RIGHT", body, "RIGHT", -DETAIL_PADDING, 0)
    colorCaption:SetJustifyH("LEFT")
    colorCaption:SetTextColor(CURATED_TAG_COLOR[1], CURATED_TAG_COLOR[2],
                              CURATED_TAG_COLOR[3])
    -- ASCII-only — WoW fonts don't render U+2192 →; use » or plain text.
    colorCaption:SetText(
        "Default = the matching preset color (DODGE \194\187 orange, etc.), "
        .. "or blue if there's no preset.")

    -- Suppress the unused-variable luacheck — `spell` is available for
    -- future knobs that need curator-side data.
    _ = spell

    -- Initial disabled-state propagation. Mirror the Visibility tab:
    -- when the spell starts disabled, the mode toggle is inert and
    -- greyed out so the UX signals that overrides won't render.
    if DT and DT:IsSpellDisabled(spellId) then
        for _, w in ipairs(secondaryWidgets) do
            if w.SetEnabled then w:SetEnabled(false) end
        end
    end

    return body
end

---------------------------------------------------------------------------------
-- Page builder. Called from the per-dungeon RegisterContent factory below.
---------------------------------------------------------------------------------
local function BuildDungeonPage(scrollChild, yOffset, dungeonKey, dungeonName)
    local Theme = KE.Theme
    local db = GetSettingsDB()
    if not db then return yOffset end

    local encounters = CollectEncountersForDungeon(dungeonKey)

    -- Empty-state for uncurated dungeons.
    if #encounters == 0 then
        local card = GUIFrame:CreateCard(scrollChild, dungeonName, yOffset)
        local row = GUIFrame:CreateRow(card.content, Theme.rowHeightLast)
        local label = row:CreateFontString(nil, "OVERLAY")
        KE:ApplyFontToText(label, "Expressway", 13, "OUTLINE")
        label:SetPoint("LEFT", row, "LEFT", 8, 0)
        label:SetText("No curated encounters yet for this dungeon.")
        card:AddRow(row, Theme.rowHeightLast, 0)
        return card:GetNextOffset()
    end

    -- Header card with dungeon name + master-toggle reminder.
    local hintCard = GUIFrame:CreateCard(scrollChild, dungeonName, yOffset)
    local hintRow = GUIFrame:CreateRow(hintCard.content, Theme.rowHeightLast)
    local hint = hintRow:CreateFontString(nil, "OVERLAY")
    KE:ApplyFontToText(hint, "Expressway", 13, "OUTLINE")
    hint:SetPoint("LEFT", hintRow, "LEFT", 8, 0)
    hint:SetPoint("RIGHT", hintRow, "RIGHT", -8, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText("Pick a spell on the left to edit its overrides. Role filter must be enabled on the General page.")
    hint:SetTextColor(0.85, 0.85, 0.85)
    hintCard:AddRow(hintRow, Theme.rowHeightLast, 0)
    yOffset = hintCard:GetNextOffset()

    -- Resolve sticky selection. If the previous selection no longer maps to
    -- an existing spell (data shape changed), fall back to first spell.
    local state = GetState(dungeonKey)
    local validSpellIds = {}
    for _, enc in ipairs(encounters) do
        for _, sItem in ipairs(enc.spells) do validSpellIds[sItem.id] = true end
    end
    if not (state.selectedSpellId and validSpellIds[state.selectedSpellId]) then
        state.selectedSpellId = ResolveFirstSpellId(encounters)
    end
    if not state.selectedTab then state.selectedTab = "Visibility" end

    -- Live preview of the selected spell. ShowSpellPreview is idempotent
    -- on identical spellId — re-calls from RefreshContent (tab switches,
    -- toggle clicks) don't restart the loop. Different spellId tears the
    -- old preview down and recreates with the new one's effective
    -- settings. Internally hides the group settings previews so the two
    -- systems don't double-render.
    if state.selectedSpellId then
        ShowSpellPreview(state.selectedSpellId)
    else
        HideSpellPreview()
    end

    ---------------------------------------------------------------------------
    -- LEFT COLUMN: spell list, encounter-grouped via section-header rows.
    ---------------------------------------------------------------------------
    local leftCol = CreateFrame("Frame", nil, scrollChild)
    leftCol:SetWidth(LEFT_COL_WIDTH)
    leftCol:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", Theme.paddingSmall, -yOffset)

    local listY = 0
    local lastEncounterId = nil
    for encIndex, enc in ipairs(encounters) do
        -- Encounter header row (not pooled — low count, transient).
        -- Prefix with "B1 - ", "B2 - ", etc. so users can quickly map
        -- spell rows back to which boss they belong to (matches the
        -- BigWigs in-fight shorthand convention).
        local header = leftCol:CreateFontString(nil, "OVERLAY")
        KE:ApplyFontToText(header, "Expressway", 15, "OUTLINE")
        header:SetPoint("TOPLEFT", leftCol, "TOPLEFT", 4, -listY - 6)
        header:SetText(string_format("B%d - %s", encIndex, enc.name))
        header:SetTextColor(KE.Theme.accent[1], KE.Theme.accent[2], KE.Theme.accent[3])
        listY = listY + ENC_HEADER_HEIGHT
        lastEncounterId = enc.id

        for _, sItem in ipairs(enc.spells) do
            local kit = listRowPool:Acquire(leftCol)
            kit._dungeonKey = dungeonKey
            kit._currentSelected = state.selectedSpellId  -- for hover paint
            kit.row:SetWidth(LEFT_COL_WIDTH)
            kit.row:SetPoint("TOPLEFT", leftCol, "TOPLEFT", 0, -listY)
            ConfigureListRow(kit, sItem.id, sItem.data,
                             sItem.id == state.selectedSpellId)
            listY = listY + LIST_ROW_HEIGHT
        end
    end
    leftCol:SetHeight(listY + Theme.paddingSmall)
    -- Suppress luacheck unused — kept for future "expand encounter" affordance
    _ = lastEncounterId

    ---------------------------------------------------------------------------
    -- RIGHT COLUMN: tab bar + tab body for selected spell.
    ---------------------------------------------------------------------------
    local rightCol = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
    rightCol:SetPoint("TOPLEFT", leftCol, "TOPRIGHT", COL_GAP, 0)
    rightCol:SetPoint("RIGHT", scrollChild, "RIGHT", -Theme.paddingSmall, 0)
    rightCol:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    rightCol:SetBackdropColor(Theme.bgLight[1], Theme.bgLight[2], Theme.bgLight[3], Theme.bgLight[4])
    rightCol:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], Theme.border[4])

    -- Spell title at top of right pane.
    local selectedSpell, selectedSpellData
    for _, enc in ipairs(encounters) do
        for _, sItem in ipairs(enc.spells) do
            if sItem.id == state.selectedSpellId then
                selectedSpell = sItem
                selectedSpellData = sItem.data
                break
            end
        end
        if selectedSpell then break end
    end

    -- Title row: spell icon + spell name wrapped in a single Frame so the
    -- whole "icon-and-name area" is one tooltip hover target. Wrapping the
    -- two pieces (FontStrings can't catch mouse events on their own) gives
    -- a single OnEnter / OnLeave anchor and a generous hit zone — hovering
    -- anywhere across the icon-or-name fires the tooltip.
    local TITLE_ICON_SIZE = 26
    local titleRow = CreateFrame("Frame", nil, rightCol)
    titleRow:SetHeight(TITLE_ICON_SIZE)
    titleRow:SetPoint("TOPLEFT", rightCol, "TOPLEFT", DETAIL_PADDING, -DETAIL_PADDING)
    titleRow:SetPoint("RIGHT", rightCol, "RIGHT", -DETAIL_PADDING, 0)

    local titleIconFrame = CreateFrame("Frame", nil, titleRow, "BackdropTemplate")
    titleIconFrame:SetSize(TITLE_ICON_SIZE, TITLE_ICON_SIZE)
    titleIconFrame:SetPoint("LEFT", titleRow, "LEFT", 0, 0)
    titleIconFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    titleIconFrame:SetBackdropColor(0, 0, 0, 0.8)
    if KE.AddIconBorders then KE:AddIconBorders(titleIconFrame) end

    local titleIcon = titleIconFrame:CreateTexture(nil, "ARTWORK")
    titleIcon:SetPoint("TOPLEFT", 1, -1)
    titleIcon:SetPoint("BOTTOMRIGHT", -1, 1)
    if KE.ApplyIconZoom then KE:ApplyIconZoom(titleIcon) end
    if selectedSpell then
        titleIcon:SetTexture(
            (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(selectedSpell.id))
            or 134400
        )
    else
        titleIcon:SetTexture(134400)
    end

    local titleFs = titleRow:CreateFontString(nil, "OVERLAY")
    KE:ApplyFontToText(titleFs, "Expressway", 16, "OUTLINE")
    titleFs:SetPoint("LEFT", titleIconFrame, "RIGHT", 8, 0)
    if selectedSpell then
        titleFs:SetText(ResolveSpellDisplayName(selectedSpell.id, selectedSpellData))
    else
        titleFs:SetText("(no selection)")
    end

    -- Tooltip on hover. titleRow is the hover target so both icon AND
    -- name area trigger the tooltip. GameTooltip is Blizzard's singleton —
    -- no per-frame OnUpdate, no per-row allocation. Lifecycle is per-hover
    -- only; cost scales with mouse interaction rate. Closure captures the
    -- selected spellId at render time which is fine since titleRow is
    -- recreated each RefreshContent (one frame per click).
    if selectedSpell then
        local hoverSpellId = selectedSpell.id
        local hoverRoleTag = selectedSpellData and selectedSpellData.role
        titleRow:EnableMouse(true)
        titleRow:SetScript("OnEnter", function(b)
            -- ANCHOR_CURSOR_RIGHT places the tooltip's left edge at the
            -- cursor's right side, top-aligned with cursor — "top-right of
            -- cursor". Standard for hover-context tooltips so the popup
            -- doesn't fly to a fixed screen corner.
            GameTooltip:SetOwner(b, "ANCHOR_CURSOR_RIGHT")
            GameTooltip:SetSpellByID(hoverSpellId)
            if hoverRoleTag then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(string_format("Curated role: %s", hoverRoleTag),
                                    0.7, 0.7, 0.7)
            end
            GameTooltip:AddLine(string_format("Spell ID: %d", hoverSpellId),
                                1, 1, 1)
            GameTooltip:Show()
        end)
        titleRow:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- Tab bar — uses CreateSubTabs which handles active state + RefreshContent.
    local tabBar = CreateFrame("Frame", nil, rightCol)
    tabBar:SetPoint("TOPLEFT", titleRow, "BOTTOMLEFT", 0, -10)
    tabBar:SetPoint("RIGHT", rightCol, "RIGHT", -DETAIL_PADDING, 0)
    tabBar:SetHeight(28)

    GUIFrame:CreateSubTabs(tabBar, 0, {
        tabs     = DETAIL_TABS,
        activeId = state.selectedTab,
        onSwitch = function(newId) state.selectedTab = newId end,
        fill     = true,
    })

    -- Subtle 1px line below the tab bar — visually anchors the tabs to
    -- the body content below them so they don't feel like floating
    -- buttons drifting into empty space.
    local tabSeparator = rightCol:CreateTexture(nil, "ARTWORK")
    tabSeparator:SetHeight(1)
    tabSeparator:SetColorTexture(Theme.border[1], Theme.border[2], Theme.border[3], 0.5)
    tabSeparator:SetPoint("LEFT",  rightCol, "LEFT",  DETAIL_PADDING, 0)
    tabSeparator:SetPoint("RIGHT", rightCol, "RIGHT", -DETAIL_PADDING, 0)
    tabSeparator:SetPoint("TOP",   tabBar, "BOTTOM", 0, -4)

    -- Tab content area — anchored below the separator, fills remaining height.
    local tabBody = CreateFrame("Frame", nil, rightCol)
    tabBody:SetPoint("TOPLEFT", tabSeparator, "BOTTOMLEFT", 0, -4)
    tabBody:SetPoint("BOTTOMRIGHT", rightCol, "BOTTOMRIGHT", -DETAIL_PADDING, DETAIL_PADDING)

    if selectedSpell then
        if state.selectedTab == "Visibility" then
            BuildVisibilityTabBody(tabBody, selectedSpell.id, selectedSpellData)
        elseif state.selectedTab == "Display" then
            BuildDisplayTabBody(tabBody, selectedSpell.id, selectedSpellData)
        elseif state.selectedTab == "Actions" then
            BuildActionsTabBody(tabBody, selectedSpell.id)
        end
    end

    -- Right column height — match left column so the page footprint is
    -- predictable. Min sized to fit the tallest tab body:
    --   Visibility ~408px stack + 97px chrome → 510
    --   Display    ~640px stack + 97px chrome → 760 (with breathing room)
    -- Display grew with Available Presets + Time Format + Bar Color
    -- sections. Below this, content overflows the rightCol's BOTTOM
    -- anchor and the Reset button row's hit zone.
    local rightHeight = math.max(listY + Theme.paddingSmall, 760)
    rightCol:SetHeight(rightHeight)

    return yOffset + math.max(listY, rightHeight) + Theme.paddingSmall
end

---------------------------------------------------------------------------------
-- Register one content callback per dungeon key. Closures capture key + name
-- once at file-load time — per-render allocation is just the function-call
-- frame, no per-render closure or table allocation.
---------------------------------------------------------------------------------
GUIFrame.onCloseCallbacks = GUIFrame.onCloseCallbacks or {}
GUIFrame.contentCleanupCallbacks = GUIFrame.contentCleanupCallbacks or {}
for _, d in ipairs(DUNGEONS) do
    local dungeonKey  = d.key
    local dungeonName = d.name
    GUIFrame:RegisterContent("DTimers_Dungeon_" .. dungeonKey, function(scrollChild, yOffset)
        return BuildDungeonPage(scrollChild, yOffset, dungeonKey, dungeonName)
    end)
    -- Each dungeon ID points at the same HideSpellPreview thunk. The
    -- onCloseCallbacks dispatch is keyed by id, so registering all 8
    -- means GUI-close cleanup fires regardless of which dungeon page
    -- was last visited (FireOnCloseCallbacks iterates all entries).
    GUIFrame.onCloseCallbacks["DTimers_Dungeon_" .. dungeonKey] = HideSpellPreview
end
-- Single contentCleanupCallback (separate from per-dungeon onClose entries).
-- contentCleanupCallbacks fires on REAL sidebar item switches; we want a
-- spell preview started in any dungeon page to vanish when the user clicks
-- a non-DungeonTimers sidebar entry. RefreshContent iterates ALL cleanup
-- callbacks unconditionally, so one entry suffices regardless of which
-- dungeon was active. Keyed distinct from "DungeonTimers" (used by
-- DungeonTimersCfg for Settings previews) so the two don't clobber.
GUIFrame.contentCleanupCallbacks["DTimers_Dungeon_SpellPreview"] = HideSpellPreview

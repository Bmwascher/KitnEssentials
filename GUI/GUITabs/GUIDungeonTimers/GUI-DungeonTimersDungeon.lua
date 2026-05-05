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
                id     = encId,
                name   = enc.name or string_format("Encounter %d", encId),
                spells = spellPairs,
            })
        end
    end
    table_sort(encList, function(a, b) return a.id < b.id end)
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
    if kit.tagLabel then
        if spell.display == "bar" then
            kit.tagLabel:SetText("Bar")
            kit.tagLabel:SetTextColor(0.4, 0.7, 1.0, 0.9)
        else
            kit.tagLabel:SetText("Text")
            kit.tagLabel:SetTextColor(0.4, 1.0, 0.5, 0.9)
        end
    end

    -- Sound indicator — placeholder slot anchored left of the tag. Today
    -- nothing turns this on (no Actions tab yet); when N13g lands the
    -- check below flips to read DT:HasSpellSound(spellId) or similar.
    -- Empty string keeps the FontString width zero so the label can grow
    -- into the slot when no sound is set.
    if kit.soundLabel then
        local hasSound = false  -- TODO N13g: check DT.SpellSounds[spellId]
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
    KE:ApplyFontToText(kit.label, "Expressway", 13, "OUTLINE")
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
    -- runs always-on (independent of the role master toggle). Default = on
    -- (no DB entry); flipping off writes db.SpellDisabled[spellId] = true.
    local enableState = DT and (not DT:IsSpellDisabled(spellId)) or true
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

    -- Curator default — anchored to the RIGHT side of the body, centered
    -- vertically on the toggle BOX (not the label above it). Toggle row
    -- is 36px tall: label ~14px at top, then box ~22px below; centering
    -- on the box puts this at -25 from the row top.
    if firstToggle then
        local defaultLabel = body:CreateFontString(nil, "OVERLAY")
        KE:ApplyFontToText(defaultLabel, "Expressway", 12, "OUTLINE")
        defaultLabel:SetPoint("RIGHT", body, "RIGHT", -DETAIL_PADDING, 0)
        defaultLabel:SetPoint("TOP", firstToggle, "TOP", 0, -25)
        defaultLabel:SetTextColor(CURATED_TAG_COLOR[1], CURATED_TAG_COLOR[2], CURATED_TAG_COLOR[3])
        defaultLabel:SetJustifyH("RIGHT")
        if spell.role then
            local friendly = ROLE_TAG_FRIENDLY[spell.role] or spell.role
            defaultLabel:SetText(string_format("Default: %s", friendly))
        else
            defaultLabel:SetText("Default: Everyone (uncurated)")
        end
    end

    -- Section: WHEN IT APPEARS — anchored to firstToggle, leaves the
    -- toggle-row's vertical footprint between this header and the toggles.
    local whenHeader
    if firstToggle then
        whenHeader = CreateSectionHeader(body, firstToggle, "When It Appears", 18)
    end

    -- "Reveal at (s remaining)" slider — per-spell visibility threshold.
    -- Resolves through DT:GetSpellShowAtSeconds (user override → curator
    -- default → group fallback). Slider directly sets the user override;
    -- Reset button clears it. 0 = always visible (overrides group hide).
    -- Range 0–30s, step 1 — matches the group sliders for consistency.
    local groupCfgKey = (spell.display == "bar") and "BarGroup" or "TextGroup"
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
    local resetRow = GUIFrame:CreateRow(body, 28)
    resetRow:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", DETAIL_PADDING, 4)
    resetRow:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -DETAIL_PADDING, 4)
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

-- Builds a placeholder tab body with a "Coming soon" notice. Used for the
-- Display + Actions tabs until N13f / N13g land.
local function BuildPlaceholderTabBody(parent, message)
    local body = CreateFrame("Frame", nil, parent)
    body:SetAllPoints()
    local label = body:CreateFontString(nil, "OVERLAY")
    KE:ApplyFontToText(label, "Expressway", 12, "OUTLINE")
    label:SetPoint("CENTER", body, "CENTER", 0, 0)
    label:SetText(message)
    label:SetTextColor(0.65, 0.65, 0.65)
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
        KE:ApplyFontToText(header, "Expressway", 16, "OUTLINE")
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
            BuildPlaceholderTabBody(tabBody, "Display options coming soon (N13f).")
        elseif state.selectedTab == "Actions" then
            BuildPlaceholderTabBody(tabBody, "Action options coming soon (N13g).")
        end
    end

    -- Right column height — match left column so the page footprint is
    -- predictable. Min 280 so empty-tab placeholders aren't squished.
    -- Right column min height needs to fit the Visibility tab content
    -- (master + who sees + when appears + reset). Calculated empirically:
    -- ~408px body required at the bottom of the time-offset caption +
    -- ~97px chrome (title row + tab bar + separator + paddings) → 510.
    -- Below this, the reset row's frame would draw over the time-offset
    -- caption since they'd share the same y-band.
    local rightHeight = math.max(listY + Theme.paddingSmall, 510)
    rightCol:SetHeight(rightHeight)

    return yOffset + math.max(listY, rightHeight) + Theme.paddingSmall
end

---------------------------------------------------------------------------------
-- Register one content callback per dungeon key. Closures capture key + name
-- once at file-load time — per-render allocation is just the function-call
-- frame, no per-render closure or table allocation.
---------------------------------------------------------------------------------
for _, d in ipairs(DUNGEONS) do
    local dungeonKey  = d.key
    local dungeonName = d.name
    GUIFrame:RegisterContent("DTimers_Dungeon_" .. dungeonKey, function(scrollChild, yOffset)
        return BuildDungeonPage(scrollChild, yOffset, dungeonKey, dungeonName)
    end)
end

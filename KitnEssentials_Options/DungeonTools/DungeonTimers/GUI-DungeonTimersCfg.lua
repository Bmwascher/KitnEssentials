-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-DungeonTimersCfg.lua                                ║
-- ║  DTimers_General page — module enable, role filter,      ║
-- ║  sound master controls, curated-coverage stats, and      ║
-- ║  override maintenance (module-wide + per-dungeon Reset). ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame

local pairs = pairs
local ipairs = ipairs
local string_format = string.format
local table_concat = table.concat

local function GetSettingsDB()
    if not KE.db or not KE.db.profile then return nil end
    return KE.db.profile.DungeonTimers
end

-- A dungeon's icon in a one-pixel black frame, for the Reset Overrides rows.
local function ConstructDungeonIcon(parent)
    local holder = CreateFrame("Frame", nil, parent)

    local icon = holder:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", holder, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -1, 1)

    local border = CreateFrame("Frame", nil, holder, "BackdropTemplate")
    border:SetAllPoints()
    border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })

    function holder.Configure(_, size, iconID)
        holder:SetSize(size, size)
        if iconID then
            icon:SetTexture(iconID)
            if KE.ApplyIconZoom then KE:ApplyIconZoom(icon) end
        else
            -- The question mark is drawn uncropped, so the crop a reused
            -- icon carries is taken off.
            icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            icon:SetTexCoord(0, 1, 0, 1)
        end
        border:SetBackdropBorderColor(0, 0, 0, 1)
    end

    holder._keOwned = { holder, border }
    return holder
end

GUIFrame:NewWidgetPool("dtcfg:icon", ConstructDungeonIcon, function() end)

KE.GUI = KE.GUI or {}
KE.GUI.DungeonTimers = KE.GUI.DungeonTimers or {}
local DT_GUI = KE.GUI.DungeonTimers

-- First tab of the DTimers_Main tabbed page; RegisterTabbedContent falls
-- back to the first tab when no tab was clicked yet, so "is this tab
-- active" must apply the same fallback.
local FIRST_TAB = "DTimers_Dungeons"

-- True while the Dungeon Timers host page is the selected sidebar item AND
-- the given tab is the one being rendered. Preview show-paths gate on this
-- so a preview never spawns into another tab's page.
function KE.GUI.DungeonTimers.IsTabActive(tabId)
    if not GUIFrame or GUIFrame.selectedSidebarItem ~= "DTimers_Main" then return false end
    local active = GUIFrame.tabbedPageState and GUIFrame.tabbedPageState["DTimers_Main"]
    return (active or FIRST_TAB) == tabId
end

-- Module-level preview teardown. Fires whenever the user switches to ANY
-- other sidebar item (contentCleanupCallbacks) or closes the GUI window
-- (onCloseCallbacks). Per-page onCloseCallbacks in Bars/Texts only cover the
-- close path; without this hook, leaving DTimers_Bars for an unrelated module
-- leaves the preview bars stranded on screen.
local function HideAllPreviews()
    if not KitnEssentials then return end
    local mod = KitnEssentials:GetModule("DungeonTimers", true)
    if not mod then return end
    if mod.HideSettingsBarPreviews then mod:HideSettingsBarPreviews() end
    if mod.HideSettingsTextPreviews then mod:HideSettingsTextPreviews() end
    if DT_GUI.HideDungeonPreviews then DT_GUI.HideDungeonPreviews() end
    if DT_GUI.HideNameplatePreview then DT_GUI.HideNameplatePreview() end
end

local PROVIDER_SETUP_TEXT = {
    satisfied = "%s: BigWigs Messages or Emphasize is |cff44ff44on|r.",
    missing = "%s (%s): BigWigs Messages is |cffff4444off|r, so this alert cannot show.",
    ["not-loaded"] = "%s: BigWigs has not loaded %s. It loads when you enter the dungeon, or press Check now.",
    unreadable = "%s: its BigWigs setting could not be read. Open BigWigs > Dungeon Bosses > %s.",
    ["no-provider"] = "%s: BigWigs is not installed or not enabled.",
    disabled = "%s: this alert is disabled, so its BigWigs setting is not checked.",
    ["not-applicable"] = "%s: this alert is only available on Mythic or Mythic+.",
}
local PROVIDER_SETUP_BUTTON = {
    missing = "Enable Messages",
    ["not-loaded"] = "Check now",
    unreadable = "Check now",
}

local function ProviderTextFor(key, info)
    local detail = (key == "unreadable") and info.manualPath or info.dungeonName
    return string_format(PROVIDER_SETUP_TEXT[key], info.label, detail)
end

function KE.GUI.DungeonTimers.ProviderSetupText(status, reason, info)
    local key = DT_GUI.ProviderSetupKey(status, reason)
    return ProviderTextFor(key, info), PROVIDER_SETUP_BUTTON[key]
end

local PROVIDER_BUTTON_GAP = 6
local PROVIDER_BUTTON_HEIGHT = 24
local PROVIDER_ICON_SIZE = 16
local PROVIDER_ICON_GAP = 6
local providerRows = {}
local providerSummaryRow, providerControlsRow
local providerRefreshPending = false

-- The per-alert details start collapsed whenever the page is opened again.
local providerDetailsExpanded = false

local function CollapseProviderDetails()
    providerDetailsExpanded = false
end
GUIFrame:RegisterContentCleanup("DTimers_ProviderDetails", CollapseProviderDetails)
GUIFrame:RegisterOnCloseCallback("DTimers_ProviderDetails", CollapseProviderDetails)

local function RefreshProviderHeader()
    if providerRefreshPending or GUIFrame.selectedSidebarItem ~= "DTimers_Main" then return end
    if GUIFrame._contentDirtyWhileHidden then return end
    providerRefreshPending = true
    C_Timer.After(0, function()
        providerRefreshPending = false
        if GUIFrame.selectedSidebarItem == "DTimers_Main" then GUIFrame:RefreshContent() end
    end)
end

-- Card rebuilds detach plain frames, which the client never frees. Reuse this row.
local function GetProviderSetupRow(cueKey)
    if providerRows[cueKey] then return providerRows[cueKey] end
    local block = CreateFrame("Frame")
    block:Hide()

    local icon = block:CreateTexture(nil, "ARTWORK")
    icon:SetSize(PROVIDER_ICON_SIZE, PROVIDER_ICON_SIZE)
    icon:SetPoint("TOPLEFT", block, "TOPLEFT", 0, 0)
    KE:ApplyIconZoom(icon)
    block.icon = icon

    local text = block:CreateFontString(nil, "OVERLAY")
    text:SetPoint("TOPLEFT", block, "TOPLEFT", PROVIDER_ICON_SIZE + PROVIDER_ICON_GAP, 0)
    text:SetPoint("RIGHT", block, "RIGHT", 0, 0)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetWordWrap(true)
    block.text = text

    local button = GUIFrame:CreateButton(block, "", {
        width = 160,
        height = PROVIDER_BUTTON_HEIGHT,
        callback = function()
            block.DT:_OpenCueProviderPrompt(block.cueKey, "explicit")
        end,
    })
    button:SetPoint("BOTTOMLEFT", block, "BOTTOMLEFT", PROVIDER_ICON_SIZE + PROVIDER_ICON_GAP, 0)
    block.button = button

    function block.Paint(status, reason)
        local label, buttonLabel = KE.GUI.DungeonTimers.ProviderSetupText(status, reason, block.info)
        text:SetText(label)
        local height = math.max(PROVIDER_ICON_SIZE, text:GetStringHeight() or 0)
        if status == "missing" then
            button:SetLabel(buttonLabel)
            button:Show()
            height = height + PROVIDER_BUTTON_GAP + PROVIDER_BUTTON_HEIGHT
        else
            button:Hide()
        end
        return height
    end

    function block.Reconcile()
        if not block:IsShown() or GUIFrame._contentDirtyWhileHidden then return end
        local fresh, _, reason = block.DT:_GetProviderSetupNotice(block.cueKey)
        if not fresh or fresh == "disabled" then
            RefreshProviderHeader()
        elseif math.abs(block.Paint(fresh, reason) - block:GetHeight()) >= 0.5 then
            RefreshProviderHeader()
        end
    end

    block:SetScript("OnShow", block.Reconcile)
    providerRows[cueKey] = block
    return block
end

-- A passive read of every alert: the summary, plus the non-disabled cue keys
-- joined, which tells an expanded section when its rows must change.
local function ReadProviderStates(DT)
    local states, keys = {}, {}
    for _, cueKey in ipairs(DT:_ProviderSetupCueKeys()) do
        local status, _, reason = DT:_GetProviderSetupNotice(cueKey)
        if status then
            states[#states + 1] = { status = status, reason = reason }
            if status ~= "disabled" then keys[#keys + 1] = tostring(cueKey) end
        end
    end
    return DT_GUI.SummarizeProviderSetup(states), table_concat(keys, "\n")
end

local function ProviderSummaryText(summary, expanded)
    if summary.kind == "no-provider" then return "BigWigs is not installed or not enabled." end
    if summary.kind == "all-on" then
        return string_format("All applicable alerts are |cff44ff44on|r (%d).", summary.total)
    end
    local parts = {}
    if summary.on > 0 then parts[#parts + 1] = string_format("%d |cff44ff44on|r", summary.on) end
    if summary.off > 0 then parts[#parts + 1] = string_format("%d |cffff4444off|r", summary.off) end
    if summary.notLoaded > 0 then parts[#parts + 1] = string_format("%d not loaded", summary.notLoaded) end
    if summary.unreadable > 0 then parts[#parts + 1] = string_format("%d unreadable", summary.unreadable) end
    local text = table_concat(parts, ", ") .. "."
    -- Expanded, each off alert's Enable Messages button is already on screen.
    if summary.off > 0 and not expanded then text = text .. " Show details to turn them on." end
    return text
end

-- Cached like the per-alert rows. Every provider notice reconciles it, so the
-- summary and Check now stay current while the details are collapsed.
local function GetProviderSummaryRow()
    if providerSummaryRow then return providerSummaryRow end
    local row = CreateFrame("Frame")
    row:Hide()

    local text = row:CreateFontString(nil, "OVERLAY")
    text:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    text:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetWordWrap(true)
    row.text = text

    function row.Paint(summary)
        text:SetText(ProviderSummaryText(summary, row.expanded))
        return math.max(PROVIDER_ICON_SIZE, text:GetStringHeight() or 0)
    end

    function row.Reconcile()
        if not row:IsShown() or GUIFrame._contentDirtyWhileHidden then return end
        local summary, keys = ReadProviderStates(row.DT)
        if summary.kind == "none" or (row.expanded and keys ~= row.keys) then
            RefreshProviderHeader()
            return
        end
        row.keys = keys
        if math.abs(row.Paint(summary) - row:GetHeight()) >= 0.5 then
            RefreshProviderHeader()
            return
        end
        if providerControlsRow then providerControlsRow.check:SetEnabled(summary.canCheck) end
    end

    row:SetScript("OnShow", row.Reconcile)
    providerSummaryRow = row
    return row
end

local function GetProviderControlsRow()
    if providerControlsRow then return providerControlsRow end
    local row = CreateFrame("Frame")
    row:Hide()
    row:SetHeight(PROVIDER_BUTTON_HEIGHT)
    row.toggle = GUIFrame:CreateButton(row, "Show details", {
        width = 160,
        height = PROVIDER_BUTTON_HEIGHT,
        callback = function()
            providerDetailsExpanded = not providerDetailsExpanded
            GUIFrame:RefreshContent()
        end,
    })
    row.toggle:SetPoint("LEFT", row, "LEFT", 0, 0)
    -- Eligibility is read again at click time; a notice may have changed it.
    row.check = GUIFrame:CreateButton(row, "Check now", {
        width = 160,
        height = PROVIDER_BUTTON_HEIGHT,
        callback = function()
            local reportedFailures = {}
            for _, cueKey in ipairs(row.DT:_ProviderSetupCueKeys()) do
                local status, _, reason = row.DT:_GetProviderSetupNotice(cueKey)
                if status and DT_GUI.ProviderCheckEligible(DT_GUI.ProviderSetupKey(status, reason)) then
                    row.DT:_CheckProviderSetupNow(cueKey, reportedFailures)
                end
            end
        end,
    })
    row.check:SetPoint("LEFT", row.toggle, "RIGHT", PROVIDER_BUTTON_GAP, 0)
    providerControlsRow = row
    return row
end

-- Card release would orphan these reused rows on every rebuild and count them
-- as leaks. Detached first, the release skips them; the header card parents
-- them again when it is built.
GUIFrame:RegisterContentRebuildCallback("__DTimersProviderRows", function()
    for _, block in pairs(providerRows) do
        block:Hide()
        block:SetParent(nil)
    end
    if providerSummaryRow then
        providerSummaryRow:Hide()
        providerSummaryRow:SetParent(nil)
    end
    if providerControlsRow then
        providerControlsRow:Hide()
        providerControlsRow:SetParent(nil)
    end
end)

local function AddProviderSetupRow(card, DT, cueKey, info, status, reason)
    local Theme = KE.Theme
    local block = GetProviderSetupRow(cueKey)
    block.DT, block.cueKey, block.info = DT, cueKey, info
    block.icon:SetTexture(DT:_ResolveProviderIcon(cueKey) or 134400)
    -- Cached widgets need their fonts and colors refreshed after a theme change.
    KE:ApplyThemeFont(block.text, "normal")
    block.text:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
    KE:ApplyThemeFont(block.button.text, "normal")
    -- Measure at the card's width before AddRow advances its layout.
    block:SetParent(card.content)
    block:ClearAllPoints()
    block:SetPoint("TOPLEFT", card.content, "TOPLEFT", 0, -card.currentY)
    block:SetPoint("TOPRIGHT", card.content, "TOPRIGHT", 0, -card.currentY)
    local rowHeight = block.Paint(status, reason)
    block:SetHeight(rowHeight)
    card:AddRow(block, rowHeight)
    block:Show()
    block.button:ApplyThemeColors()
end

local function AddProviderSection(card, DT)
    local Theme = KE.Theme
    local summary, keys = ReadProviderStates(DT)
    if summary.kind == "none" then return end

    card:AddSeparator()
    card:AddLabel(KE:ColorTextByTheme("BigWigs Messages"))
    card:AddLabel("Some timers start from a BigWigs message, so that message must be on in BigWigs.")

    local row = GetProviderSummaryRow()
    row.DT, row.keys, row.expanded = DT, keys, providerDetailsExpanded
    KE:ApplyThemeFont(row.text, "normal")
    row.text:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
    -- Measure at the card's width before AddRow advances its layout.
    row:SetParent(card.content)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", card.content, "TOPLEFT", 0, -card.currentY)
    row:SetPoint("TOPRIGHT", card.content, "TOPRIGHT", 0, -card.currentY)
    local rowHeight = row.Paint(summary)
    row:SetHeight(rowHeight)
    card:AddRow(row, rowHeight)
    row:Show()

    local controls = GetProviderControlsRow()
    controls.DT = DT
    controls.toggle:SetLabel(providerDetailsExpanded and "Hide details" or "Show details")
    KE:ApplyThemeFont(controls.toggle.text, "normal")
    KE:ApplyThemeFont(controls.check.text, "normal")
    card:AddRow(controls, PROVIDER_BUTTON_HEIGHT)
    controls:Show()
    controls.toggle:ApplyThemeColors()
    controls.check:ApplyThemeColors()
    controls.check:SetEnabled(summary.canCheck)

    if not providerDetailsExpanded then return end
    for _, cueKey in ipairs(DT:_ProviderSetupCueKeys()) do
        local status, info, reason = DT:_GetProviderSetupNotice(cueKey)
        if status and status ~= "disabled" and info then
            AddProviderSetupRow(card, DT, cueKey, info, status, reason)
        end
    end
end

local function NotifyProviderSetupRow(cueKey)
    if GUIFrame.selectedSidebarItem ~= "DTimers_Main" then return end
    local block = providerRows[cueKey]
    if block and block:IsShown() then block.Reconcile() end
    if providerSummaryRow and providerSummaryRow:IsShown() then
        providerSummaryRow.Reconcile()
    else
        local DT = KitnEssentials and KitnEssentials:GetModule("DungeonTimers", true)
        local status = DT and DT:_GetProviderSetupNotice(cueKey)
        if status and status ~= "disabled" then RefreshProviderHeader() end
    end
end

-- Labels are measured at the scroll width of the build. A scrollbar that
-- appears or goes once the page height is known changes that width, so the
-- page is built again; text never gets shorter as it narrows, so that settles.
local function RebuildIfWidthChanges(scrollChild)
    local builtWidth = scrollChild:GetWidth()
    C_Timer.After(0, function()
        if GUIFrame.selectedSidebarItem ~= "DTimers_Main" then return end
        local width = scrollChild:GetWidth()
        if not width or not builtWidth or math.abs(width - builtWidth) < 0.5 then return end
        GUIFrame:RefreshContent()
    end)
end

-- Header card shared by every tab of the host page: module toggle +
-- reload prompt. collapse=true (module off) makes the host show this card
-- alone and skip the tab strip entirely.
function KE.GUI.DungeonTimers.BuildHeaderCard(scrollChild, yOffset)
    for _, block in pairs(providerRows) do block:Hide() end
    if providerSummaryRow then providerSummaryRow:Hide() end
    if providerControlsRow then providerControlsRow:Hide() end
    local db = GetSettingsDB()
    if not db then return yOffset, true end
    local DT = KitnEssentials and KitnEssentials:GetModule("DungeonTimers", true)

    local function ApplyModuleState(enabled)
        db.Enabled = enabled
        if not DT then return end
        if enabled then
            KitnEssentials:EnableModule("DungeonTimers")
        else
            KitnEssentials:DisableModule("DungeonTimers")
        end
    end

    local card = GUIFrame:CreateCard(scrollChild, "Dungeon Timers", yOffset)
    card:AddHeaderToggle(db.Enabled ~= false, function(checked)
        -- The toggle's own refresh is same-item and skips cleanup, and the
        -- collapsed header returns before any tab builder can run its
        -- hides — tear previews down here or they strand on screen.
        if not checked then HideAllPreviews() end
        ApplyModuleState(checked)
        KE:CreateReloadPrompt("Enabling/Disabling this module requires a reload to take full effect.")
    end)
    card:AddLabel("Hand-tuned timers and reminder sounds for each season's dungeon bosses. With it on, " ..
        "the Bars, Texts and Nameplates tabs set how they look.\n\n" ..
        "Needs |cffffd100BigWigs|r and |cffffd100LittleWigs|r. In BigWigs Timeline settings, show BigWigs " ..
        "enhanced timers as BigWigs bars. Blizzard's timeline display can stay off.")
    if db.Enabled == false then
        -- Also covers arriving here already-disabled (e.g. a profile
        -- switch landing on a profile with the module off).
        HideAllPreviews()
        return card:GetNextOffset(), true
    end
    if DT and DT._GetProviderSetupNotice and DT._ProviderSetupCueKeys then
        AddProviderSection(card, DT)
        DT._providerSetupHeaderNotice = NotifyProviderSetupRow
    end
    RebuildIfWidthChanges(scrollChild)
    return card:GetNextOffset(), false
end

GUIFrame.contentCleanupCallbacks = GUIFrame.contentCleanupCallbacks or {}
GUIFrame.contentCleanupCallbacks["DungeonTimers"] = HideAllPreviews

GUIFrame.onCloseCallbacks = GUIFrame.onCloseCallbacks or {}
GUIFrame.onCloseCallbacks["DungeonTimers"] = HideAllPreviews

-- Sound channel dropdown options. Matches Blizzard's PlaySoundFile second
-- argument — channels are gated by their respective volume sliders, so
-- "SFX" lets the user mute timer sounds independently of dialog/music.
-- Array-of-tables form preserves dropdown order (hash form is pairs()-iterated
-- and unordered).
local SOUND_CHANNELS = {
    { key = "Master",   text = "Master" },
    { key = "SFX",      text = "SFX" },
    { key = "Dialog",   text = "Dialog" },
    { key = "Music",    text = "Music" },
    { key = "Ambience", text = "Ambience" },
}

-- Clears every per-spell + per-phase override entry whose owner encounter
-- lives in the given dungeon. Leaves global display settings (BarDisplay /
-- TextDisplay / BarGroup / TextGroup) alone — those are shared across all
-- dungeons, so a per-dungeon reset that touched them would be misleading.
-- Pass dungeonKey = nil to reset everything.
local function ResetOverridesForDungeon(DT, dungeonKey)
    if not DT then return end
    for encID, enc in pairs(KE.EncounterData or {}) do
        if not dungeonKey or enc.dungeon == dungeonKey then
            if enc.spells and DT.ResetSpellOverrides then
                for spellId in pairs(enc.spells) do
                    DT:ResetSpellOverrides(spellId)
                end
            end
            if DT.ResetSpellOverrides then
                local State = KE._DungeonTimerState
                if State and type(enc.phaseCues) == "table" then
                    for name in pairs(enc.phaseCues) do
                        DT:ResetSpellOverrides(State.CueKey(encID, name))
                    end
                end
                if DT.MakeAuraKey and type(enc.auraSounds) == "table" then
                    for _, rule in ipairs(enc.auraSounds) do
                        if DT.IsWellFormedAuraRule(rule) then
                            DT:ResetSpellOverrides(DT.MakeAuraKey(encID, rule.spellID, rule.trigger))
                        end
                    end
                end
            end
            if enc.phases and DT.ResetPhaseOverrides and DT.MakePhaseRuleKey then
                for i in ipairs(enc.phases) do
                    local key = DT:MakePhaseRuleKey(encID, i)
                    if key then DT:ResetPhaseOverrides(key) end
                end
            end
        end
    end

    -- Also clear standalone trash-tracker overrides for the same dungeon(s).
    -- Keyed by mapID; dungeonKey == nil resets every dungeon's trash too.
    local DTrash = KitnEssentials and KitnEssentials:GetModule("DungeonTrash", true)
    if DTrash and DTrash.ResetTrashOverridesForDungeon and KE.TrashData then
        for mapID, d in pairs(KE.TrashData) do
            if not dungeonKey or d.dungeonKey == dungeonKey then
                DTrash:ResetTrashOverridesForDungeon(mapID)
            end
        end
    end
end

-- General's season filter, independent of the Dungeon Bosses/Trash selection.
-- It starts at the newest season when the page opens and survives tab
-- switches and rebuilds, which are same-item refreshes that fire neither
-- callback below. It resets on leaving the page, on GUI close, and when a
-- profile hands the page a different settings table.
local generalSeason, generalSeasonDB

local function ResetGeneralSeason()
    generalSeason, generalSeasonDB = nil, nil
end
GUIFrame:RegisterContentCleanup("DTimers_General_season", ResetGeneralSeason)
GUIFrame:RegisterOnCloseCallback("DTimers_General_season", ResetGeneralSeason)

GUIFrame:RegisterContent("DTimers_General", function(scrollChild, yOffset)
    local Theme = KE.Theme

    -- General has no previews of its own, so it hides all four kinds when
    -- it activates: bar, text, dungeon, nameplate.
    if DT_GUI.HideBarPreviews then DT_GUI.HideBarPreviews() end
    if DT_GUI.HideTextPreviews then DT_GUI.HideTextPreviews() end
    if DT_GUI.HideDungeonPreviews then DT_GUI.HideDungeonPreviews() end
    if DT_GUI.HideNameplatePreview then DT_GUI.HideNameplatePreview() end

    local db = GetSettingsDB()
    if not db then return yOffset end

    local DT = KitnEssentials and KitnEssentials:GetModule("DungeonTimers", true)
    local registry = KE.DungeonTimerDungeons
    local seasons = KE.GetDungeonTimerSeasons(registry)
    if db ~= generalSeasonDB then generalSeason, generalSeasonDB = nil, db end
    if not generalSeason then generalSeason = seasons[#seasons] end

    ---------------------------------------------------------------------------
    -- Card 2: Role Filter
    ---------------------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Role Filter", yOffset)
    local row2 = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local roleCheck = GUIFrame:CreateCheckbox(row2, "Filter bars by your role/spec", {
        value = db.RoleFilterEnabled == true,
        callback = function(checked)
            db.RoleFilterEnabled = checked
        end,
    })
    row2:AddWidget(roleCheck, 1)
    card2:AddRow(row2, Theme.rowHeightLast, 0)
    yOffset = card2:GetNextOffset()

    ---------------------------------------------------------------------------
    -- Card 3: Sound — mute toggle + channel dropdown side by side
    ---------------------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Sound", yOffset)

    local row3 = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local muteCheck = GUIFrame:CreateCheckbox(row3, "Mute all preset sounds", {
        value = db.MutePresetSounds == true,
        callback = function(checked)
            db.MutePresetSounds = checked
            if DT and DT.SyncAuraSounds then DT:SyncAuraSounds() end
        end,
    })
    row3:AddWidget(muteCheck, 0.5)
    local channelDropdown = GUIFrame:CreateDropdown(row3, "Sound channel", {
        options = SOUND_CHANNELS,
        value = db.SoundChannel or "Master",
        callback = function(key)
            db.SoundChannel = key
            if DT and DT.SyncAuraSounds then DT:SyncAuraSounds() end
        end,
    })
    row3:AddWidget(channelDropdown, 0.5)
    card3:AddRow(row3, Theme.rowHeightLast, 0)
    yOffset = card3:GetNextOffset()

    ---------------------------------------------------------------------------
    -- Card 4: Reset Overrides
    -- A season dropdown filters the per-dungeon rows: [icon] [name] ...
    -- [Reset btn flush-right]. Module-wide "Reset All Dungeons" sits at the
    -- BOTTOM of the card and always covers both seasons (least-frequent /
    -- most-destructive action goes last). All Reset buttons use red text
    -- (REMOVE_COLOR), the house convention for a destructive action.
    ---------------------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Reset Overrides", yOffset)

    local seasonOptions = {}
    for _, s in ipairs(seasons) do
        seasonOptions[#seasonOptions + 1] = { key = s, text = "Season " .. s }
    end
    local seasonRow = GUIFrame:CreateRow(card4.content, Theme.rowHeightLast)
    local seasonDropdown = GUIFrame:CreateDropdown(seasonRow, "Season", {
        options = seasonOptions,
        value = generalSeason,
        callback = function(key)
            if key == generalSeason then return end
            generalSeason = key
            GUIFrame:RefreshContent()
        end,
    })
    seasonRow:AddWidget(seasonDropdown, 0.5)
    card4:AddRow(seasonRow, Theme.rowHeightLast)

    card4:AddLabel("Clears your timer, reminder sound and trash-ability overrides: enable, role, color, sound, " ..
        "display and the rest. Bar and text style and position are not touched.")

    -- Separator between the description header and the dungeon list.
    local rowDescSep = GUIFrame:CreateRow(card4.content, Theme.rowHeightSeparator)
    local descSep = GUIFrame:CreateSeparator(rowDescSep)
    rowDescSep:AddWidget(descSep, 1)
    card4:AddRow(rowDescSep, Theme.rowHeightSeparator)

    -- Per-dungeon row metrics. Manual positioning for icon/label/button so
    -- the button's right edge aligns precisely with the separator + Reset
    -- All button below (both end at row-right - paddingSmall via AddWidget's
    -- default-spacing math). AddWidget's per-widget width calculation made
    -- the button visually shorter than Reset All in practice, so this path
    -- skips it for the button.
    local ROW_H           = 36
    local BTN_H           = 30
    local BTN_W           = 140
    local ICON_SIZE       = 28
    local RIGHT_INSET     = Theme.paddingSmall   -- match AddWidget(widget, 1)'s effective right inset
    local REMOVE_COLOR    = { 0.9, 0.2, 0.2, 1 } -- destructive-action red

    for _, dungeon in ipairs(KE.GetDungeonTimerDungeonsForSeason(registry, generalSeason)) do
        local row = GUIFrame:CreateRow(card4.content, ROW_H)

        local iconHolder = GUIFrame:AcquirePooled("dtcfg:icon", row)
        iconHolder:ClearAllPoints()
        iconHolder:SetPoint("LEFT", row, "LEFT", 0, 0)
        iconHolder:Configure(ICON_SIZE, dungeon.iconID)

        local btn = GUIFrame:CreateButton(row, "Reset", {
            width  = BTN_W,
            height = BTN_H,
            callback = function()
                KE:CreatePrompt(
                    "Reset " .. dungeon.name,
                    "Clear every timer, reminder sound and trash-ability override for " ..
                    dungeon.name .. "?",
                    false, nil, false, nil, nil, nil, nil,
                    function() ResetOverridesForDungeon(DT, dungeon.key) end,
                    nil,
                    "Reset",
                    "Cancel"
                )
            end,
        })
        if btn.text then
            btn.text:SetTextColor(REMOVE_COLOR[1], REMOVE_COLOR[2], REMOVE_COLOR[3], REMOVE_COLOR[4])
        end
        -- Manual anchor — RIGHT-to-RIGHT vertically centers both edges' midpoints,
        -- so no yOffset hack is needed for vertical alignment.
        btn:SetParent(row)
        btn:ClearAllPoints()
        btn:SetPoint("RIGHT", row, "RIGHT", -RIGHT_INSET, 0)
        btn:SetSize(BTN_W, BTN_H)

        local label = row:GetLabel("large")
        label:SetPoint("LEFT",   iconHolder, "RIGHT", Theme.paddingMedium, 0)
        label:SetPoint("RIGHT",  btn,        "LEFT",  -Theme.paddingMedium, 0)
        label:SetPoint("TOP",    row,        "TOP",    0, 0)
        label:SetPoint("BOTTOM", row,        "BOTTOM", 0, 0)
        label:SetJustifyH("LEFT")
        label:SetText(dungeon.name)

        card4:AddRow(row, ROW_H, 2)
    end

    -- Separator before the destructive Reset-All action.
    local rowSep = GUIFrame:CreateRow(card4.content, Theme.rowHeightSeparator)
    local sep = GUIFrame:CreateSeparator(rowSep)
    rowSep:AddWidget(sep, 1)
    card4:AddRow(rowSep, Theme.rowHeightSeparator)

    -- Module-wide Reset All at the BOTTOM of the card, whatever the filter shows.
    local rowAll = GUIFrame:CreateRow(card4.content, Theme.rowHeightLast)
    local resetAllBtn = GUIFrame:CreateButton(rowAll, "Reset All Dungeons (Both Seasons)", {
        callback = function()
            KE:CreatePrompt(
                "Reset All Overrides",
                "Clear every timer, reminder sound and trash-ability override in every dungeon of both seasons?\n" ..
                "Bar and text style and position are kept.",
                false, nil, false, nil, nil, nil, nil,
                function() ResetOverridesForDungeon(DT, nil) end,
                nil,
                "Reset",
                "Cancel"
            )
        end,
    })
    if resetAllBtn.text then
        resetAllBtn.text:SetTextColor(REMOVE_COLOR[1], REMOVE_COLOR[2], REMOVE_COLOR[3], REMOVE_COLOR[4])
    end
    rowAll:AddWidget(resetAllBtn, 1)
    card4:AddRow(rowAll, Theme.rowHeightLast, 0)

    yOffset = card4:GetNextOffset()

    ---------------------------------------------------------------------------
    -- Card 5: Curated Coverage (footer-style info card, read-only), scoped to
    -- the season chosen above.
    ---------------------------------------------------------------------------
    if generalSeason then
        local isReminder = (DT and DT.IsWellFormedAuraRule) or function() return false end
        local c = KE.CountDungeonTimerCoverage(registry, KE.EncounterData or {}, KE.TrashData or {},
            generalSeason, isReminder)
        local card5 = GUIFrame:CreateCard(scrollChild, "Curated Coverage", yOffset)
        card5:AddLabel(string_format(
            "Season %d: %d dungeons, %d bosses, %d boss timers and %d reminder sounds.",
            generalSeason, c.dungeons, c.bosses, c.timers, c.reminders))
        if c.trashAbilities > 0 then
            card5:AddLabel(string_format(
                "Season %d trash: %d abilities tracked across %d enemies.",
                generalSeason, c.trashAbilities, c.trashEnemies))
        end
        card5:AddLabel("All hand-tuned by Cruzer's Kittens.")
        yOffset = card5:GetNextOffset()
    end

    return yOffset
end)

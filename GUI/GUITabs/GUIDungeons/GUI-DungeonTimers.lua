-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-DungeonTimers.lua                                   ║
-- ║  Purpose: Per-dungeon panel — sidebar trigger list +     ║
-- ║  4 sub-tabs (Trigger / Display / Load / Actions).        ║
-- ║  Module-level pages (DT_General, DT_Bars, DT_Texts) live ║
-- ║  in their own files (GUI-DungeonTimersCfg/Bars/Texts).   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame

local table_insert = table.insert
local pairs, ipairs = pairs, ipairs
local tonumber, tostring = tonumber, tostring
local wipe = wipe
local CreateFrame = CreateFrame
local C_Spell = C_Spell
local C_Timer = C_Timer

local DUNGEON_INFO = {
    Dungeon_MagistersTerrace  = { key = "MagistersTerrace",   name = "Magisters' Terrace" },
    Dungeon_MaisaraCaverns    = { key = "MaisaraCaverns",     name = "Maisara Caverns" },
    Dungeon_NexusPointXenas   = { key = "NexusPointXenas",    name = "Nexus-Point Xenas" },
    Dungeon_WindrunnerSpire   = { key = "WindrunnerSpire",    name = "Windrunner Spire" },
    Dungeon_AlgetharAcademy   = { key = "AlgetharAcademy",    name = "Algeth'ar Academy" },
    Dungeon_PitOfSaron        = { key = "PitOfSaron",         name = "Pit of Saron" },
    Dungeon_SeatOfTriumvirate = { key = "SeatOfTriumvirate",  name = "Seat of the Triumvirate" },
    Dungeon_Skyreach          = { key = "Skyreach",           name = "Skyreach" },
}

local SUB_TABS = {
    { id = "trigger", text = "Trigger" },
    { id = "display", text = "Display" },
    { id = "load",    text = "Load" },
    { id = "actions", text = "Actions" },
}

local TRIGGER_TYPE_OPTIONS = {
    { key = "timer",    text = "Timer" },
    { key = "announce", text = "Announce" },
}

local MESSAGE_OPERATOR_OPTIONS = {
    { key = "find",  text = "Contains" },
    { key = "==",    text = "Exact Match" },
    { key = "match", text = "Pattern" },
}

local COMPARISON_OPTIONS = {
    { key = "<",  text = "< (less than)" },
    { key = "<=", text = "<= (less or equal)" },
    { key = "==", text = "= (equal)" },
    { key = ">=", text = ">= (greater or equal)" },
    { key = ">",  text = "> (greater than)" },
}

local DISPLAY_TYPE_OPTIONS = {
    { key = "bar",  text = "Bar" },
    { key = "text", text = "Text Only" },
}

local SIDEBAR_WIDTH = 191
local BUTTON_HEIGHT = 28
local LIST_PADDING = 4
local TAB_BAR_HEIGHT = 30

local dungeonStates = {}
local currentPreviewDungeon = nil
local previewActive = false

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("DungeonTimers", true)
    end
    return nil
end

local function StopPreview()
    previewActive = false
    currentPreviewDungeon = nil
    local mod = GetModule()
    if mod then
        if mod.DisablePreviews then mod:DisablePreviews() end
        if mod.HideAll then mod:HideAll() end
    end
end

local function StartDungeonPreview(dungeonKey)
    if not GUIFrame or not GUIFrame:IsShown() then return end

    StopPreview()
    if not dungeonKey then return end

    currentPreviewDungeon = dungeonKey
    previewActive = true

    local mod = GetModule()
    if not mod then return end

    if mod.EnablePreviews then mod:EnablePreviews() end

    local function loopCallback()
        if not GUIFrame or not GUIFrame:IsShown() then return end
        if previewActive and currentPreviewDungeon == dungeonKey then
            local m = GetModule()
            if m and m.PreviewDungeon and m.previewsAllowed then
                m:PreviewDungeon(dungeonKey, loopCallback)
            end
        end
    end

    if mod.PreviewDungeon then
        mod:PreviewDungeon(dungeonKey, loopCallback)
    end
end

GUIFrame.contentCleanupCallbacks = GUIFrame.contentCleanupCallbacks or {}
GUIFrame.contentCleanupCallbacks["DungeonTimers"] = StopPreview

GUIFrame.onCloseCallbacks = GUIFrame.onCloseCallbacks or {}
GUIFrame.onCloseCallbacks["DungeonTimers"] = StopPreview

local VALID_SUB_TABS = { trigger = true, display = true, load = true, actions = true }

local function GetDungeonState(dungeonKey)
    if not dungeonStates[dungeonKey] then
        dungeonStates[dungeonKey] = {
            selectedTriggerId = nil,
            currentSubTab = "trigger",
            spellSearchFilter = "",
        }
    end
    if not VALID_SUB_TABS[dungeonStates[dungeonKey].currentSubTab] then
        dungeonStates[dungeonKey].currentSubTab = "trigger"
    end
    return dungeonStates[dungeonKey]
end

---------------------------------------------------------------------------------
-- Sidebar trigger-list button pool (KE.FramePool adoption)
---------------------------------------------------------------------------------
-- Pre-pool: every BuildTimerList() called btn:Hide() + btn:SetParent(nil) on
-- each existing button, then CreateFrame'd a new one per trigger. SetParent(nil)
-- doesn't free a frame — it reparents to UIParent — so the addon leaked one
-- WoW frame per trigger per panel-rebuild. The pool reuses kit instances.

local function CreateTimerButtonKit(holder)
    local btn = CreateFrame("Button", nil, holder)
    btn:SetHeight(BUTTON_HEIGHT)

    local hover = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.05)
    hover:Hide()

    local selected = btn:CreateTexture(nil, "BACKGROUND", nil, 2)
    selected:SetAllPoints()
    selected:Hide()

    local accentBar = btn:CreateTexture(nil, "OVERLAY")
    accentBar:SetWidth(2)
    accentBar:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    accentBar:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    accentBar:Hide()

    local iconSize = BUTTON_HEIGHT - 6
    local iconBorder = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    iconBorder:SetSize(iconSize + 2, iconSize + 2)
    iconBorder:SetPoint("LEFT", btn, "LEFT", 5, 0)
    iconBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })

    local spellIcon = btn:CreateTexture(nil, "ARTWORK")
    spellIcon:SetSize(iconSize, iconSize)
    spellIcon:SetPoint("CENTER", iconBorder, "CENTER", 0, 0)

    local typeIndicator = btn:CreateFontString(nil, "OVERLAY")
    typeIndicator:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
    KE:ApplyThemeFont(typeIndicator, "small")

    local soundIndicator = btn:CreateFontString(nil, "OVERLAY")
    soundIndicator:SetPoint("RIGHT", typeIndicator, "LEFT", -2, 0)
    KE:ApplyThemeFont(soundIndicator, "small")

    local label = btn:CreateFontString(nil, "OVERLAY")
    label:SetPoint("LEFT", iconBorder, "RIGHT", 6, 0)
    label:SetPoint("RIGHT", soundIndicator, "LEFT", -2, 0)
    label:SetJustifyH("LEFT")
    KE:ApplyThemeFont(label, "small")

    local kit = {
        row = btn,
        btn = btn,
        hover = hover,
        selected = selected,
        accentBar = accentBar,
        iconBorder = iconBorder,
        spellIcon = spellIcon,
        typeIndicator = typeIndicator,
        soundIndicator = soundIndicator,
        label = label,
        -- per-render mutable state, updated by ConfigureTimerButtonKit
        _triggerId = nil,
        _state = nil,    -- per-panel state table (we read selectedTriggerId from it)
        _onClick = nil,  -- per-panel OnClick closure
    }

    -- Wire scripts ONCE; they read mutable state from kit slots that
    -- Configure updates per-render. Avoids the closure-per-render trap.
    btn:SetScript("OnEnter", function()
        local s = kit._state
        if s and s.selectedTriggerId ~= kit._triggerId then
            kit.hover:Show()
            kit.label:SetTextColor(1, 1, 1, 1)
        end
    end)
    btn:SetScript("OnLeave", function()
        kit.hover:Hide()
        local s = kit._state
        if s and s.selectedTriggerId ~= kit._triggerId then
            local t = KE.Theme
            kit.label:SetTextColor(t.textSecondary[1], t.textSecondary[2], t.textSecondary[3], 1)
        end
    end)
    btn:SetScript("OnClick", function()
        if kit._onClick then kit._onClick(kit._triggerId) end
    end)

    return kit
end

local function ConfigureTimerButtonKit(kit, parent, index, triggerId, triggerData, panelState, panelOnClick)
    local Theme = KE.Theme

    kit._triggerId = triggerId
    kit._state = panelState
    kit._onClick = panelOnClick

    -- Position relative to current parent. Acquire just reparented kit to
    -- `parent`, but sub-anchor refs need re-pinning explicitly.
    kit.btn:ClearAllPoints()
    local y = -(index - 1) * (BUTTON_HEIGHT + 2)
    kit.btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    kit.btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)

    -- Theme-tinted textures (re-applied each render in case theme changed
    -- while a kit was idle in the pool).
    kit.selected:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.15)
    kit.accentBar:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    kit.iconBorder:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)

    -- Spell icon
    local spellId = triggerData.spellId and tonumber(triggerData.spellId)
    if spellId and spellId > 0 and C_Spell and C_Spell.GetSpellTexture then
        kit.spellIcon:SetTexture(C_Spell.GetSpellTexture(spellId) or 134400)
    else
        kit.spellIcon:SetTexture(134400)
    end
    if KE.ApplyIconZoom then KE:ApplyIconZoom(kit.spellIcon, 0.1) end

    -- Type indicator
    if triggerData.displayType == "bar" then
        kit.typeIndicator:SetText("Bar")
        kit.typeIndicator:SetTextColor(0.4, 0.7, 1.0, 0.9)
    else
        kit.typeIndicator:SetText("Text")
        kit.typeIndicator:SetTextColor(0.4, 1.0, 0.5, 0.9)
    end

    -- Sound indicator
    local hasSound = (triggerData.actionOnShowSound and triggerData.actionOnShowSound ~= "" and triggerData.actionOnShowSound ~= "None")
        or (triggerData.actionOnHideSound and triggerData.actionOnHideSound ~= "" and triggerData.actionOnHideSound ~= "None")
    if hasSound then
        kit.soundIndicator:SetText("S")
        kit.soundIndicator:SetTextColor(1.0, 0.8, 0.3, 0.9)
    else
        kit.soundIndicator:SetText("")
    end

    -- Label
    local displayName = triggerData.name or ("Timer " .. triggerId)
    if #displayName > 21 then displayName = displayName:sub(1, 21) .. ".." end
    kit.label:SetText(displayName)
    kit.label:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)

    -- Reset transient visuals; UpdateTimerListSelectionVisuals re-shows
    -- selected/accentBar for the active row.
    kit.hover:Hide()
end

local timerButtonPool = KE.FramePool:New(CreateTimerButtonKit)

---------------------------------------------------------------------------------
-- Detail-pane card pools
--
-- Every card in the right-side detail pane (Trigger / Display / Load / Actions
-- sub-tabs) used to be rebuilt from scratch on every render. The outer
-- contentArea:ClearContent() does Hide() + SetParent(nil) on each old child,
-- which orphans WoW frames to UIParent — they're never GC'd. Heavy widgets
-- (dropdowns, toggles, edit boxes) ended up costing ~370–455 KB per detail
-- render, which compounded across the M+ dungeon-tab navigation users do.
--
-- Pattern: build the entire card kit (card frame, rows, widgets) ONCE in a
-- factory under the pool's hidden holder. Wire script callbacks ONCE so they
-- read mutable kit slots (_trigger, _applySettings, _refreshContentDeferred)
-- that Configure swaps per render. Sets values via the widget's silent /
-- instant API path so callbacks don't fire during programmatic refresh.
---------------------------------------------------------------------------------

local function CreateBasicSettingsCardKit(holder)
    local T = KE.Theme
    local card = GUIFrame:CreateCard(holder, "Basic Settings", 0)

    local row1 = GUIFrame:CreateRow(card.content, T.rowHeight)
    local enableTrigger = GUIFrame:CreateCheckbox(row1, "Enabled", { value = true })
    row1:AddWidget(enableTrigger, 1)
    card:AddRow(row1, T.rowHeight)

    local separator1 = GUIFrame:CreateSeparator(card.content)
    card:AddRow(separator1, T.rowHeightSeparator)

    local row2 = GUIFrame:CreateRow(card.content, T.rowHeightLast)
    local nameInput = GUIFrame:CreateEditBox(row2, "Timer Name", { value = "" })
    row2:AddWidget(nameInput, 0.5)
    local typeDropdown = GUIFrame:CreateDropdown(row2, "Trigger Type", {
        options = TRIGGER_TYPE_OPTIONS,
        value = "timer",
    })
    row2:AddWidget(typeDropdown, 0.5)
    card:AddRow(row2, T.rowHeightLast, 0)

    local kit = {
        row = card,                  -- pool reads kit.row as the root frame
        card = card,
        enableTrigger = enableTrigger,
        nameInput = nameInput,
        typeDropdown = typeDropdown,
        -- per-render mutable state, updated by Configure
        _trigger = nil,
        _applySettings = nil,
        _refreshContentDeferred = nil,
    }

    -- Wire callbacks ONCE; they read kit slots that Configure swaps per
    -- render. This keeps closure count bounded to kit lifetime, not render
    -- count, and avoids the leak where each render allocated 3 fresh
    -- closures over the prior selectedTrigger.
    enableTrigger:SetCallback(function(checked)
        local t = kit._trigger
        if t then t.enabled = checked end
        if kit._applySettings then kit._applySettings() end
    end)
    nameInput:SetCallback(function(text)
        local t = kit._trigger
        if t then t.name = text end
        if kit._applySettings then kit._applySettings() end
        if kit._refreshContentDeferred then kit._refreshContentDeferred() end
    end)
    typeDropdown:SetCallback(function(key)
        local t = kit._trigger
        if t then t.triggerType = key end
        if kit._applySettings then kit._applySettings() end
    end)

    return kit
end

local function ConfigureBasicSettingsCardKit(kit, parent, yOffset, trigger, applySettings, refreshContentDeferred)
    local T = KE.Theme

    -- Re-anchor the card to its new parent at the requested yOffset.
    -- Acquire reparented kit.card to `parent`, but card's TOPLEFT/RIGHT
    -- points still reference the pool's hidden holder — they need to be
    -- re-set explicitly.
    kit.card:ClearAllPoints()
    kit.card:SetPoint("TOPLEFT", parent, "TOPLEFT", T.paddingSmall, -(yOffset or 0) + T.paddingSmall)
    kit.card:SetPoint("RIGHT", parent, "RIGHT", -T.paddingSmall, 0)
    kit.card._yOffset = yOffset or 0

    -- Update slots BEFORE setting widget values so the silent/instant set
    -- path doesn't fire stale callbacks even if a widget bypasses silent.
    kit._trigger = trigger
    kit._applySettings = applySettings
    kit._refreshContentDeferred = refreshContentDeferred

    -- Set values without firing callbacks:
    -- - Toggle.SetValue(value, instant=true) skips the deferred callback fire
    -- - EditBox.SetValue → editBox:SetText, which doesn't fire OnEnterPressed
    -- - Dropdown.SetValue(value, silent=true) skips the callback
    kit.enableTrigger.toggle:SetValue(trigger.enabled ~= false, true)
    kit.nameInput:SetValue(trigger.name or "")
    kit.typeDropdown:SetValue(trigger.triggerType or "timer", true)

    return kit.card
end

local basicSettingsCardPool = KE.FramePool:New(CreateBasicSettingsCardKit)

local function CreateTriggerFiltersCardKit(holder)
    local T = KE.Theme
    local card = GUIFrame:CreateCard(holder, "Trigger Filters", 0)

    -- Row 1: spell ID input + spell icon preview
    local row3 = GUIFrame:CreateRow(card.content, T.rowHeight)
    local spellInput = GUIFrame:CreateEditBox(row3, "Spell ID (optional)", { value = "" })
    row3:AddWidget(spellInput, 0.5)

    -- Inline spell-icon-preview kit: container + icon + border + name label,
    -- with the texture/name/tooltip-spellId driven by Configure-set kit slots
    -- so a single instance can swap spells without re-allocating frames.
    local previewContainer = CreateFrame("Frame", nil, row3)
    previewContainer:SetHeight(32)

    local iconFrame = CreateFrame("Frame", nil, previewContainer)
    iconFrame:SetSize(24, 24)
    iconFrame:SetPoint("LEFT", previewContainer, "LEFT", 0, -6)

    local iconTexture = iconFrame:CreateTexture(nil, "ARTWORK")
    iconTexture:SetPoint("TOPLEFT", 1, -1)
    iconTexture:SetPoint("BOTTOMRIGHT", -1, 1)

    local iconBorder = CreateFrame("Frame", nil, iconFrame, "BackdropTemplate")
    iconBorder:SetAllPoints()
    iconBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    iconBorder:SetBackdropBorderColor(0, 0, 0, 1)

    local nameLabel = previewContainer:CreateFontString(nil, "OVERLAY")
    nameLabel:SetPoint("LEFT", iconFrame, "RIGHT", T.paddingSmall, 0)
    nameLabel:SetFont(KE.FONT or "Fonts\\FRIZQT__.TTF", T.fontSizeSmall, "OUTLINE")
    nameLabel:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)

    row3:AddWidget(previewContainer, 0.5)
    card:AddRow(row3, T.rowHeight)

    -- Row 2: message filter + match-mode dropdown
    local row4 = GUIFrame:CreateRow(card.content, T.rowHeight)
    local msgInput = GUIFrame:CreateEditBox(row4, "Message Filter (optional)", { value = "" })
    row4:AddWidget(msgInput, 0.5)

    local msgOpDropdown = GUIFrame:CreateDropdown(row4, "Match", {
        options = MESSAGE_OPERATOR_OPTIONS,
        value = "find",
    })
    row4:AddWidget(msgOpDropdown, 0.5)
    card:AddRow(row4, T.rowHeightLast, 0)

    local kit = {
        row = card,
        card = card,
        spellInput = spellInput,
        previewContainer = previewContainer,
        iconTexture = iconTexture,
        nameLabel = nameLabel,
        msgInput = msgInput,
        msgOpDropdown = msgOpDropdown,
        -- per-render mutable state
        _trigger = nil,
        _applySettings = nil,
        _refreshContentDeferred = nil,
        _previewSpellId = nil,
    }

    -- Wire callbacks ONCE; read kit slots updated by Configure.
    spellInput:SetCallback(function(text)
        local t = kit._trigger
        if t then t.spellId = text end
        if kit._applySettings then kit._applySettings() end
        if kit._refreshContentDeferred then kit._refreshContentDeferred() end
    end)
    msgInput:SetCallback(function(text)
        local t = kit._trigger
        if t then t.message = text end
        if kit._applySettings then kit._applySettings() end
    end)
    msgOpDropdown:SetCallback(function(key)
        local t = kit._trigger
        if t then t.messageOperator = key end
        if kit._applySettings then kit._applySettings() end
    end)

    -- Tooltip wired ONCE; reads kit._previewSpellId set by Configure.
    previewContainer:SetScript("OnEnter", function(self)
        local sid = kit._previewSpellId
        if not sid or sid == "" then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT", 30, 0)
        GameTooltip:SetSpellByID(tonumber(sid))
        GameTooltip:Show()
    end)
    previewContainer:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return kit
end

local function ConfigureTriggerFiltersCardKit(kit, parent, yOffset, trigger, applySettings, refreshContentDeferred)
    local T = KE.Theme

    kit.card:ClearAllPoints()
    kit.card:SetPoint("TOPLEFT", parent, "TOPLEFT", T.paddingSmall, -(yOffset or 0) + T.paddingSmall)
    kit.card:SetPoint("RIGHT", parent, "RIGHT", -T.paddingSmall, 0)
    kit.card._yOffset = yOffset or 0

    kit._trigger = trigger
    kit._applySettings = applySettings
    kit._refreshContentDeferred = refreshContentDeferred
    kit._previewSpellId = trigger.spellId

    -- Update spell icon preview based on current trigger.spellId.
    local spellIdNum = trigger.spellId and trigger.spellId ~= "" and tonumber(trigger.spellId)
    local texture = spellIdNum and C_Spell.GetSpellTexture(spellIdNum)
    if texture then
        kit.iconTexture:SetTexture(texture)
        if KE.ApplyIconZoom then KE:ApplyIconZoom(kit.iconTexture, 0.1) end
    else
        kit.iconTexture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end

    local spellInfo = spellIdNum and C_Spell.GetSpellInfo(spellIdNum)
    kit.nameLabel:SetText((spellInfo and spellInfo.name) or "No spell selected")

    -- Set values without firing callbacks (editbox SetText is silent;
    -- dropdown SetValue with silent=true skips callback).
    kit.spellInput:SetValue(trigger.spellId or "")
    kit.msgInput:SetValue(trigger.message or "")
    kit.msgOpDropdown:SetValue(trigger.messageOperator or "find", true)

    return kit.card
end

local triggerFiltersCardPool = KE.FramePool:New(CreateTriggerFiltersCardKit)

local function CreateTimeConditionsCardKit(holder)
    local T = KE.Theme
    local card = GUIFrame:CreateCard(holder, "Time Conditions", 0)

    -- Row 6: remaining-time enable checkbox (always visible)
    local row6 = GUIFrame:CreateRow(card.content, T.rowHeight)
    local remCheck = GUIFrame:CreateCheckbox(row6, "Enable remaining time condition", { value = false })
    row6:AddWidget(remCheck, 1)
    card:AddRow(row6, T.rowHeight)

    -- Row 7: operator + seconds (conditionally visible based on remainingEnabled).
    -- Built once at factory time; Configure shows/hides it and re-anchors
    -- separator/row8 so the layout matches the old conditional-build behavior.
    local row7 = GUIFrame:CreateRow(card.content, T.rowHeight)
    local remOpDropdown = GUIFrame:CreateDropdown(row7, "Operator", {
        options = COMPARISON_OPTIONS,
        value = "<",
    })
    row7:AddWidget(remOpDropdown, 0.5)
    local remSlider = GUIFrame:CreateSlider(row7, "Seconds", {
        min = 1, max = 60, step = 1,
        value = 5,
        labelWidth = 60,
    })
    row7:AddWidget(remSlider, 0.5)
    card:AddRow(row7, T.rowHeight)

    -- Separator
    local separator2 = GUIFrame:CreateSeparator(card.content)
    card:AddRow(separator2, T.rowHeightSeparator)

    -- Row 8: timer offset slider
    local row8 = GUIFrame:CreateRow(card.content, T.rowHeightLast)
    local offsetSlider = GUIFrame:CreateSlider(row8, "Timer Offset (seconds)", {
        min = -10, max = 10, step = 0.5,
        value = 0,
        labelWidth = 80,
    })
    row8:AddWidget(offsetSlider, 1)
    card:AddRow(row8, T.rowHeightLast, 0)

    local kit = {
        row = card,
        card = card,
        remCheck = remCheck,
        row7 = row7,
        remOpDropdown = remOpDropdown,
        remSlider = remSlider,
        separator2 = separator2,
        row8 = row8,
        offsetSlider = offsetSlider,
        _trigger = nil,
        _applySettings = nil,
        _refreshContentDeferred = nil,
    }

    -- Wire callbacks ONCE; read kit slots updated by Configure.
    remCheck:SetCallback(function(checked)
        local t = kit._trigger
        if t then t.remainingEnabled = checked end
        if kit._applySettings then kit._applySettings() end
        if kit._refreshContentDeferred then kit._refreshContentDeferred() end
    end)
    remOpDropdown:SetCallback(function(key)
        local t = kit._trigger
        if t then t.remainingOperator = key end
        if kit._applySettings then kit._applySettings() end
    end)
    remSlider:SetCallback(function(val)
        local t = kit._trigger
        if t then t.remainingValue = val end
        if kit._applySettings then kit._applySettings() end
    end)
    offsetSlider:SetCallback(function(val)
        local t = kit._trigger
        if t then t.extendTimer = val end
        if kit._applySettings then kit._applySettings() end
    end)

    return kit
end

local function ConfigureTimeConditionsCardKit(kit, parent, yOffset, trigger, applySettings, refreshContentDeferred)
    local T = KE.Theme

    kit.card:ClearAllPoints()
    kit.card:SetPoint("TOPLEFT", parent, "TOPLEFT", T.paddingSmall, -(yOffset or 0) + T.paddingSmall)
    kit.card:SetPoint("RIGHT", parent, "RIGHT", -T.paddingSmall, 0)
    kit.card._yOffset = yOffset or 0

    kit._trigger = trigger
    kit._applySettings = applySettings
    kit._refreshContentDeferred = refreshContentDeferred

    -- Set values without firing callbacks.
    kit.remCheck.toggle:SetValue(trigger.remainingEnabled == true, true)
    kit.remOpDropdown:SetValue(trigger.remainingOperator or "<", true)
    kit.remSlider:SetValue(trigger.remainingValue or 5, true)
    kit.offsetSlider:SetValue(trigger.extendTimer or 0, true)

    -- Show/hide row7 and re-anchor downstream rows so the card matches the
    -- old conditional-build layout (no gap when row7 is hidden).
    local showRow7 = trigger.remainingEnabled == true
    local content = kit.card.content
    local padding = T.paddingSmall

    local y7 = T.rowHeight + padding
    local ySep = showRow7
        and (T.rowHeight * 2 + padding * 2)
        or (T.rowHeight + padding)
    local y8 = ySep + T.rowHeightSeparator + padding

    kit.row7:ClearAllPoints()
    if showRow7 then
        kit.row7:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y7)
        kit.row7:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y7)
        kit.row7:Show()
    else
        kit.row7:Hide()
    end

    kit.separator2:ClearAllPoints()
    kit.separator2:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -ySep)
    kit.separator2:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -ySep)

    kit.row8:ClearAllPoints()
    kit.row8:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y8)
    kit.row8:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y8)

    -- Recompute total content height for GetContentHeight()/GetNextOffset().
    local totalContent = y8 + T.rowHeightLast
    content:SetHeight(totalContent)
    kit.card.currentY = totalContent
    kit.card:UpdateHeight()

    return kit.card
end

local timeConditionsCardPool = KE.FramePool:New(CreateTimeConditionsCardKit)

local function CreateDisplayTypeCardKit(holder)
    local T = KE.Theme
    local card = GUIFrame:CreateCard(holder, "Display Type", 0)

    local row1 = GUIFrame:CreateRow(card.content, T.rowHeightLast)
    local displayDropdown = GUIFrame:CreateDropdown(row1, "Style", {
        options = DISPLAY_TYPE_OPTIONS,
        value = "bar",
    })
    row1:AddWidget(displayDropdown, 1)
    card:AddRow(row1, T.rowHeightLast, 0)

    local kit = {
        row = card,
        card = card,
        displayDropdown = displayDropdown,
        _trigger = nil,
        _applySettings = nil,
        _refreshContentDeferred = nil,
    }

    displayDropdown:SetCallback(function(key)
        local t = kit._trigger
        if t then t.displayType = key end
        if kit._applySettings then kit._applySettings() end
        if kit._refreshContentDeferred then kit._refreshContentDeferred() end
    end)

    return kit
end

local function ConfigureDisplayTypeCardKit(kit, parent, yOffset, trigger, applySettings, refreshContentDeferred)
    local T = KE.Theme

    kit.card:ClearAllPoints()
    kit.card:SetPoint("TOPLEFT", parent, "TOPLEFT", T.paddingSmall, -(yOffset or 0) + T.paddingSmall)
    kit.card:SetPoint("RIGHT", parent, "RIGHT", -T.paddingSmall, 0)
    kit.card._yOffset = yOffset or 0

    kit._trigger = trigger
    kit._applySettings = applySettings
    kit._refreshContentDeferred = refreshContentDeferred

    kit.displayDropdown:SetValue(trigger.displayType or "bar", true)

    return kit.card
end

local displayTypeCardPool = KE.FramePool:New(CreateDisplayTypeCardKit)

local function CreateRoleCardKit(holder)
    local T = KE.Theme
    local card = GUIFrame:CreateCard(holder, "Role", 0)

    -- Row 1: filter toggle (always shown)
    local row1 = GUIFrame:CreateRow(card.content, T.rowHeight)
    local roleToggle = GUIFrame:CreateCheckbox(row1, "Filter by Role", { value = false })
    row1:AddWidget(roleToggle, 1)
    card:AddRow(row1, T.rowHeight)

    -- Separator + 3 role rows: built once, shown/hidden per Configure based
    -- on loadRoleEnabled. Layout uses GUIFrame:CreateSeparator (a Frame) so
    -- we can Hide it cleanly; AddSeparator creates a Texture which is
    -- harder to manage in a conditional layout.
    local separator = GUIFrame:CreateSeparator(card.content)
    card:AddRow(separator, T.rowHeightSeparator)

    local row2 = GUIFrame:CreateRow(card.content, T.rowHeight)
    local tankCheck = GUIFrame:CreateCheckbox(row2, "Tank", { value = true })
    row2:AddWidget(tankCheck, 1)
    card:AddRow(row2, T.rowHeight)

    local row3 = GUIFrame:CreateRow(card.content, T.rowHeight)
    local healerCheck = GUIFrame:CreateCheckbox(row3, "Healer", { value = true })
    row3:AddWidget(healerCheck, 1)
    card:AddRow(row3, T.rowHeight)

    local row4 = GUIFrame:CreateRow(card.content, T.rowHeightLast)
    local dpsCheck = GUIFrame:CreateCheckbox(row4, "DPS", { value = true })
    row4:AddWidget(dpsCheck, 1)
    card:AddRow(row4, T.rowHeightLast, 0)

    local kit = {
        row = card,
        card = card,
        roleToggle = roleToggle,
        separator = separator,
        row2 = row2, tankCheck = tankCheck,
        row3 = row3, healerCheck = healerCheck,
        row4 = row4, dpsCheck = dpsCheck,
        _trigger = nil,
        _applySettings = nil,
        _refreshContentDeferred = nil,
    }

    roleToggle:SetCallback(function(checked)
        local t = kit._trigger
        if t then t.loadRoleEnabled = checked end
        if kit._applySettings then kit._applySettings() end
        if kit._refreshContentDeferred then kit._refreshContentDeferred() end
    end)
    tankCheck:SetCallback(function(checked)
        local t = kit._trigger
        if t then t.loadRoleTank = checked end
        if kit._applySettings then kit._applySettings() end
    end)
    healerCheck:SetCallback(function(checked)
        local t = kit._trigger
        if t then t.loadRoleHealer = checked end
        if kit._applySettings then kit._applySettings() end
    end)
    dpsCheck:SetCallback(function(checked)
        local t = kit._trigger
        if t then t.loadRoleDPS = checked end
        if kit._applySettings then kit._applySettings() end
    end)

    return kit
end

local function ConfigureRoleCardKit(kit, parent, yOffset, trigger, applySettings, refreshContentDeferred)
    local T = KE.Theme

    kit.card:ClearAllPoints()
    kit.card:SetPoint("TOPLEFT", parent, "TOPLEFT", T.paddingSmall, -(yOffset or 0) + T.paddingSmall)
    kit.card:SetPoint("RIGHT", parent, "RIGHT", -T.paddingSmall, 0)
    kit.card._yOffset = yOffset or 0

    kit._trigger = trigger
    kit._applySettings = applySettings
    kit._refreshContentDeferred = refreshContentDeferred

    kit.roleToggle.toggle:SetValue(trigger.loadRoleEnabled == true, true)
    kit.tankCheck.toggle:SetValue(trigger.loadRoleTank ~= false, true)
    kit.healerCheck.toggle:SetValue(trigger.loadRoleHealer ~= false, true)
    kit.dpsCheck.toggle:SetValue(trigger.loadRoleDPS ~= false, true)

    local enabled = trigger.loadRoleEnabled == true
    local padding = T.paddingSmall

    if enabled then
        kit.separator:Show()
        kit.row2:Show(); kit.row3:Show(); kit.row4:Show()
        -- Recompute card content height using the factory's full layout:
        -- row1 + padding + sep + padding + row2 + padding + row3 + padding + row4
        local total = T.rowHeight + padding
            + T.rowHeightSeparator + padding
            + T.rowHeight + padding
            + T.rowHeight + padding
            + T.rowHeightLast
        kit.card.content:SetHeight(total)
        kit.card.currentY = total
    else
        kit.separator:Hide()
        kit.row2:Hide(); kit.row3:Hide(); kit.row4:Hide()
        -- Only row1 visible. Use rowHeightLast spacing to match the original
        -- "shape A" branch (`card1:AddRow(row1, Theme.rowHeightLast, 0)`).
        local total = T.rowHeightLast
        kit.card.content:SetHeight(total)
        kit.card.currentY = total
    end
    kit.card:UpdateHeight()

    return kit.card
end

local roleCardPool = KE.FramePool:New(CreateRoleCardKit)

local function CreateDungeonPanel(dungeonId)
    local info = DUNGEON_INFO[dungeonId]
    if not info then return nil end

    local dungeonKey = info.key
    local state = GetDungeonState(dungeonKey)

    return function(container)
        local Theme = KE.Theme

        -- Hide module-level previews when entering a dungeon page
        local DT_GUI = KE.GUI and KE.GUI.DungeonTimers
        if DT_GUI then
            if DT_GUI.HideBarPreviews then DT_GUI.HideBarPreviews() end
            if DT_GUI.HideTextPreviews then DT_GUI.HideTextPreviews() end
        end

        local db = KE.db and KE.db.profile.Dungeons and KE.db.profile.Dungeons.DungeonTimers
        if not db then return nil end

        if not db.Dungeons then db.Dungeons = {} end
        if not db.Dungeons[dungeonKey] then
            db.Dungeons[dungeonKey] = { Enabled = true, Triggers = {} }
        end

        local dungeonDb = db.Dungeons[dungeonKey]
        if not dungeonDb.Triggers then dungeonDb.Triggers = {} end

        if state.selectedTriggerId and not dungeonDb.Triggers[state.selectedTriggerId] then
            state.selectedTriggerId = nil
            StopPreview()
        end

        local selectedTrigger = state.selectedTriggerId and dungeonDb.Triggers[state.selectedTriggerId] or nil

        local function ApplySettings()
            local mod = GetModule()
            local previewAlreadyRunning = previewActive and currentPreviewDungeon == dungeonKey
            if mod then
                if state.selectedTriggerId and mod.UpdateFrameVisuals then
                    mod:UpdateFrameVisuals(dungeonKey, state.selectedTriggerId)
                elseif mod.ApplySettings then
                    mod:ApplySettings()
                end
            end
            -- Skip preview restart when one's already running for this dungeon —
            -- UpdateFrameVisuals applies visual changes in place, and non-visual
            -- config changes (extendTimer, remainingValue) get picked up on the
            -- next loop iteration. Explicit Add/Del/Move/Select handlers still
            -- call StartDungeonPreview themselves to force a fresh preview.
            if state.selectedTriggerId and not previewAlreadyRunning then
                StartDungeonPreview(dungeonKey)
            end
        end

        local function RefreshContentDeferred()
            C_Timer.After(0.05, function()
                if GUIFrame.RefreshContent then GUIFrame:RefreshContent() end
            end)
        end

        local panel = CreateFrame("Frame", nil, container)
        panel:SetAllPoints()

        panel:SetScript("OnHide", function()
            if currentPreviewDungeon == dungeonKey then
                StopPreview()
            end
        end)

        local RenderContent
        local BuildTimerList
        local UpdateTimerListSelection

        local function MoveTrigger(direction)
            if not state.selectedTriggerId then return end
            local mod = GetModule()
            if not mod then return end
            local newId
            if direction == "up" and mod.MoveTriggerUp then
                newId = mod:MoveTriggerUp(dungeonKey, state.selectedTriggerId)
            elseif direction == "down" and mod.MoveTriggerDown then
                newId = mod:MoveTriggerDown(dungeonKey, state.selectedTriggerId)
            end
            if newId then
                state.selectedTriggerId = newId
                selectedTrigger = dungeonDb.Triggers[newId]
                BuildTimerList()
                RenderContent(state.currentSubTab)
                StartDungeonPreview(dungeonKey)
            end
        end

        local miniSidebar = KE.GUI.CreateMiniSidebar(panel, {
            sidebarWidth = SIDEBAR_WIDTH,
            listPadding = LIST_PADDING,
            itemHeight = BUTTON_HEIGHT,
            itemSpacing = 2,
            customListRendering = true,
            buttonArea = {
                layout = "horizontal",
                buttonHeight = BUTTON_HEIGHT,
                spacing = LIST_PADDING,
                rowSpacing = 2,
                rows = {
                    {
                        {
                            text = "New",
                            tooltip = "Create New Timer",
                            onClick = function()
                                local mod = GetModule()
                                if mod and mod.CreateTrigger then
                                    local newId = mod:CreateTrigger(dungeonKey)
                                    if newId then
                                        state.selectedTriggerId = newId
                                        selectedTrigger = dungeonDb.Triggers[newId]
                                        BuildTimerList()
                                        RenderContent(state.currentSubTab)
                                        StartDungeonPreview(dungeonKey)
                                    end
                                end
                            end,
                        },
                        {
                            text = "Dup",
                            tooltip = "Duplicate Selected Timer",
                            onClick = function()
                                if state.selectedTriggerId then
                                    local mod = GetModule()
                                    if mod and mod.DuplicateTrigger then
                                        local newId = mod:DuplicateTrigger(dungeonKey, state.selectedTriggerId)
                                        if newId then
                                            state.selectedTriggerId = newId
                                            selectedTrigger = dungeonDb.Triggers[newId]
                                            BuildTimerList()
                                            RenderContent(state.currentSubTab)
                                            StartDungeonPreview(dungeonKey)
                                        end
                                    end
                                end
                            end,
                        },
                        {
                            text = "Del",
                            tooltip = "Delete Selected Timer",
                            onClick = function()
                                if state.selectedTriggerId then
                                    local mod = GetModule()
                                    if mod and mod.DeleteTrigger then
                                        mod:DeleteTrigger(dungeonKey, state.selectedTriggerId)
                                        state.selectedTriggerId = nil
                                        selectedTrigger = nil
                                        BuildTimerList()
                                        RenderContent(state.currentSubTab)
                                        StopPreview()
                                    end
                                end
                            end,
                        },
                    },
                    {
                        {
                            icon = "Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\collapse.tga",
                            iconRotation = 180,
                            tooltip = "Move Timer Up",
                            onClick = function() MoveTrigger("up") end,
                        },
                        {
                            icon = "Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\collapse.tga",
                            tooltip = "Move Timer Down",
                            onClick = function() MoveTrigger("down") end,
                        },
                    },
                },
            },
            contentType = "tabbed",
            tabs = SUB_TABS,
            tabBarHeight = TAB_BAR_HEIGHT,
            defaultTab = state.currentSubTab,
            onTabChanged = function(tabId)
                state.currentSubTab = tabId
                RenderContent(tabId)
            end,
        })

        local listChild = miniSidebar.listChild
        local contentArea = miniSidebar.contentArea
        local scrollChild = contentArea.scrollChild
        local activeCards = contentArea.activeCards or {}

        local isModuleDisabled = db.Enabled == false
        if isModuleDisabled then
            miniSidebar.panel:SetAlpha(0.5)
            for _, btn in ipairs(miniSidebar.actionButtons or {}) do
                btn:EnableMouse(false)
            end
        end

        local timerButtons = {}

        -- Captured ONCE per panel and assigned to every kit's _onClick slot.
        -- Reused across every BuildTimerList call. RenderContent / dungeonDb /
        -- selectedTrigger are upvalues that are bound late-style — they may
        -- be nil when this closure is created but are populated by the time
        -- a button actually fires. UpdateTimerListSelection / dungeonKey are
        -- already in scope here.
        local panelOnTimerClick = function(triggerId)
            state.selectedTriggerId = triggerId
            selectedTrigger = dungeonDb.Triggers[triggerId]
            UpdateTimerListSelection()
            RenderContent(state.currentSubTab)
            StartDungeonPreview(dungeonKey)
        end

        local function UpdateTimerListSelectionVisuals()
            -- timerButtons holds kits (not buttons) post-pool-refactor: the
            -- kit has the textures, the kit's btn has the click target.
            for _, kit in ipairs(timerButtons) do
                if kit._triggerId == state.selectedTriggerId then
                    kit.selected:Show()
                    kit.accentBar:Show()
                    kit.label:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
                else
                    kit.selected:Hide()
                    kit.accentBar:Hide()
                    kit.label:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
                end
            end
        end

        BuildTimerList = function()
            -- ReleaseAll reparents every prior kit back to the pool's hidden
            -- holder, so when listChild is later cleared (or this panel is
            -- closed) those kits are NOT orphaned to UIParent. Then Acquire
            -- borrows them back to listChild for the new render pass.
            timerButtonPool:ReleaseAll()
            wipe(timerButtons)

            local sortedTriggers = {}
            for id, trigger in pairs(dungeonDb.Triggers) do
                table_insert(sortedTriggers, { id = id, data = trigger })
            end
            table.sort(sortedTriggers, function(a, b) return tonumber(a.id) < tonumber(b.id) end)

            for i, item in ipairs(sortedTriggers) do
                local kit = timerButtonPool:Acquire(listChild)
                ConfigureTimerButtonKit(kit, listChild, i, item.id, item.data, state, panelOnTimerClick)
                table_insert(timerButtons, kit)
            end

            local listHeight = #sortedTriggers * (BUTTON_HEIGHT + 2)
            miniSidebar.SetListHeight(math.max(listHeight, 1))
            UpdateTimerListSelectionVisuals()
        end

        UpdateTimerListSelection = function()
            UpdateTimerListSelectionVisuals()
        end

        BuildTimerList()

        ----------------------------------------------------------------
        -- Render: Trigger sub-tab
        ----------------------------------------------------------------
        local function RenderTriggerTab(yOffset)
            if not selectedTrigger then
                local card = GUIFrame:CreateCard(scrollChild, "No Timer Selected", yOffset)
                card:AddLabel("Click + to create a new timer or select one from the list on the left.")
                table_insert(activeCards, card)
                return yOffset + card:GetContentHeight() + Theme.paddingSmall
            end

            local padding = Theme.paddingSmall

            -- Card 1: Basic Settings (pooled — see CreateBasicSettingsCardKit)
            basicSettingsCardPool:ReleaseAll()
            local basicKit = basicSettingsCardPool:Acquire(scrollChild)
            local card1 = ConfigureBasicSettingsCardKit(basicKit, scrollChild, yOffset,
                selectedTrigger, ApplySettings, RefreshContentDeferred)
            table_insert(activeCards, card1)

            yOffset = yOffset + card1:GetContentHeight() + padding

            -- Card 2: Trigger Filters (pooled — see CreateTriggerFiltersCardKit)
            triggerFiltersCardPool:ReleaseAll()
            local filtersKit = triggerFiltersCardPool:Acquire(scrollChild)
            local card2 = ConfigureTriggerFiltersCardKit(filtersKit, scrollChild, yOffset,
                selectedTrigger, ApplySettings, RefreshContentDeferred)
            table_insert(activeCards, card2)

            yOffset = yOffset + card2:GetContentHeight() + padding

            -- Card 3: Time Conditions (pooled — see CreateTimeConditionsCardKit)
            timeConditionsCardPool:ReleaseAll()
            local timeKit = timeConditionsCardPool:Acquire(scrollChild)
            local card3 = ConfigureTimeConditionsCardKit(timeKit, scrollChild, yOffset,
                selectedTrigger, ApplySettings, RefreshContentDeferred)
            table_insert(activeCards, card3)

            yOffset = yOffset + card3:GetContentHeight() + padding

            -- Card 4: BigWigs Spell Browser (forceRefresh=true to dodge stale cache)
            local mod = GetModule()
            local spells = mod and mod.GetSpellsForDungeon and mod:GetSpellsForDungeon(dungeonKey, true) or {}

            -- Self-heal: if BigWigs cache was cold (0 spells), reschedule one refresh
            -- so the user doesn't see an empty browser when they first open the tab.
            state.spellSelfHealScheduled = state.spellSelfHealScheduled or {}
            if (not spells or #spells == 0) and not state.spellSelfHealScheduled[dungeonKey] then
                state.spellSelfHealScheduled[dungeonKey] = true
                C_Timer.After(0.6, function()
                    if GUIFrame.RefreshContent then GUIFrame:RefreshContent() end
                end)
            end

            local browserCard
            browserCard, yOffset = GUIFrame:CreateSpellBrowserCard(scrollChild, yOffset, {
                spells = spells,
                searchFilter = state.spellSearchFilter or "",
                onSearchChange = function(text)
                    -- Persist the filter only. The spell-browser kit pools
                    -- the outer card + searchInput, so RebuildSpellList runs
                    -- inline on every (debounced) keystroke without tearing
                    -- down the EditBox — focus survives across live-typing.
                    -- A RefreshContentDeferred() here would re-render the
                    -- whole tab and reset the trigger detail-pane scroll.
                    state.spellSearchFilter = text
                end,
                onSpellSelect = function(spellId)
                    if selectedTrigger then
                        selectedTrigger.spellId = tostring(spellId)
                        ApplySettings()
                        RefreshContentDeferred()
                    end
                end,
            })
            table_insert(activeCards, browserCard)

            return yOffset
        end

        ----------------------------------------------------------------
        -- Render: Display sub-tab
        ----------------------------------------------------------------
        local function RenderDisplayTab(yOffset)
            if not selectedTrigger then
                local card = GUIFrame:CreateCard(scrollChild, "No Timer Selected", yOffset)
                card:AddLabel("Click + to create a new timer, or select one from the list on the left.")
                table_insert(activeCards, card)
                return yOffset + card:GetContentHeight() + Theme.paddingSmall
            end

            local padding = Theme.paddingSmall
            local isBar = (selectedTrigger.displayType or "bar") == "bar"

            -- Card 1: Display Type (pooled — see CreateDisplayTypeCardKit)
            displayTypeCardPool:ReleaseAll()
            local displayKit = displayTypeCardPool:Acquire(scrollChild)
            local card1 = ConfigureDisplayTypeCardKit(displayKit, scrollChild, yOffset,
                selectedTrigger, ApplySettings, RefreshContentDeferred)
            table_insert(activeCards, card1)

            yOffset = yOffset + card1:GetContentHeight() + padding

            if isBar then
                local card3
                card3, yOffset = GUIFrame:CreateTextFormatCard(scrollChild, yOffset, {
                    title = "Text 1",
                    db = selectedTrigger,
                    dbKeys = {
                        format = "barText1Format",
                        justify = "barText1Justify",
                        xOffset = "barText1XOffset",
                        yOffset = "barText1YOffset",
                    },
                    defaults = { format = "%n", justify = "LEFT", xOffset = 4, yOffset = 0 },
                    onChangeCallback = ApplySettings,
                })
                table_insert(activeCards, card3)

                local card3b
                card3b, yOffset = GUIFrame:CreateTextFormatCard(scrollChild, yOffset, {
                    title = "Text 2",
                    db = selectedTrigger,
                    dbKeys = {
                        format = "barText2Format",
                        justify = "barText2Justify",
                        xOffset = "barText2XOffset",
                        yOffset = "barText2YOffset",
                    },
                    defaults = { format = "%p", justify = "RIGHT", xOffset = -4, yOffset = 0 },
                    onChangeCallback = ApplySettings,
                })
                table_insert(activeCards, card3b)

                local card3c = GUIFrame:CreateCard(scrollChild, "Time Display", yOffset)
                table_insert(activeCards, card3c)

                local row3e = GUIFrame:CreateRow(card3c.content, Theme.rowHeightLast)
                local showDecimalsCheck = GUIFrame:CreateCheckbox(row3e, "Show Decimals", {
                    value = selectedTrigger.showDecimals == true,
                    callback = function(checked)
                        selectedTrigger.showDecimals = checked
                        ApplySettings()
                        RefreshContentDeferred()
                    end,
                })
                row3e:AddWidget(showDecimalsCheck, selectedTrigger.showDecimals and 0.5 or 1)

                if selectedTrigger.showDecimals then
                    local decimalThresholdSlider = GUIFrame:CreateSlider(row3e, "Below (seconds)", {
                        min = 1, max = 30, step = 1,
                        value = selectedTrigger.decimalThreshold or 3,
                        labelWidth = 50,
                        callback = function(val) selectedTrigger.decimalThreshold = val; ApplySettings() end,
                    })
                    row3e:AddWidget(decimalThresholdSlider, 0.5)
                end
                card3c:AddRow(row3e, Theme.rowHeightLast, 0)

                yOffset = yOffset + card3c:GetContentHeight() + padding
            else
                local card3 = GUIFrame:CreateCard(scrollChild, "Text Format", yOffset)
                table_insert(activeCards, card3)

                local row3 = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
                local formatInput = GUIFrame:CreateEditBox(row3, "Format String", {
                    value = selectedTrigger.textFormat or "%i %n %p",
                    callback = function(text)
                        selectedTrigger.textFormat = text
                        ApplySettings()
                        RefreshContentDeferred()
                    end,
                })
                row3:AddWidget(formatInput, 1)
                card3:AddRow(row3, Theme.rowHeight)

                local row3c = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
                local showDecimalsCheck = GUIFrame:CreateCheckbox(row3c, "Show Decimals", {
                    value = selectedTrigger.showDecimals == true,
                    callback = function(checked)
                        selectedTrigger.showDecimals = checked
                        ApplySettings()
                        RefreshContentDeferred()
                    end,
                })
                row3c:AddWidget(showDecimalsCheck, selectedTrigger.showDecimals and 0.5 or 1)

                if selectedTrigger.showDecimals then
                    local decimalThresholdSlider = GUIFrame:CreateSlider(row3c, "Below (seconds)", {
                        min = 1, max = 30, step = 1,
                        value = selectedTrigger.decimalThreshold or 3,
                        labelWidth = 50,
                        callback = function(val) selectedTrigger.decimalThreshold = val; ApplySettings() end,
                    })
                    row3c:AddWidget(decimalThresholdSlider, 0.5)
                end
                card3:AddRow(row3c, Theme.rowHeightLast, 0)

                yOffset = yOffset + card3:GetContentHeight() + padding
            end

            -- Card: Colors
            local card4 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
            table_insert(activeCards, card4)

            if isBar then
                local row4 = GUIFrame:CreateRow(card4.content, Theme.rowHeightLast)
                local bwColorCheck = GUIFrame:CreateCheckbox(row4, "Sync With BigWigs Bar Coloring", {
                    value = selectedTrigger.useBigWigsColors ~= false,
                    callback = function(checked)
                        selectedTrigger.useBigWigsColors = checked
                        ApplySettings()
                        RefreshContentDeferred()
                    end,
                })
                row4:AddWidget(bwColorCheck, 1)

                if selectedTrigger.useBigWigsColors then
                    card4:AddRow(row4, Theme.rowHeightLast, 0)
                else
                    card4:AddRow(row4, Theme.rowHeight)

                    local separator = GUIFrame:CreateSeparator(card4.content)
                    card4:AddRow(separator, Theme.rowHeightSeparator)

                    local row5 = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
                    local barColorPicker = GUIFrame:CreateColorPicker(row5, "Bar Color", {
                        color = selectedTrigger.barColor,
                        callback = function(r, g, b, a) selectedTrigger.barColor = { r, g, b, a }; ApplySettings() end,
                    })
                    row5:AddWidget(barColorPicker, 1)
                    card4:AddRow(row5, Theme.rowHeight)

                    local row5b = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
                    local bgColorPicker = GUIFrame:CreateColorPicker(row5b, "Background Color", {
                        color = selectedTrigger.backgroundColor,
                        callback = function(r, g, b, a) selectedTrigger.backgroundColor = { r, g, b, a }; ApplySettings() end,
                    })
                    row5b:AddWidget(bgColorPicker, 1)
                    card4:AddRow(row5b, Theme.rowHeight)

                    local row6 = GUIFrame:CreateRow(card4.content, Theme.rowHeightLast)
                    local textColorPicker = GUIFrame:CreateColorPicker(row6, "Text Color", {
                        color = selectedTrigger.textColor,
                        callback = function(r, g, b, a) selectedTrigger.textColor = { r, g, b, a }; ApplySettings() end,
                    })
                    row6:AddWidget(textColorPicker, 1)
                    card4:AddRow(row6, Theme.rowHeightLast, 0)
                end
            else
                local row4 = GUIFrame:CreateRow(card4.content, Theme.rowHeightLast)
                local textColorPicker = GUIFrame:CreateColorPicker(row4, "Text Color", {
                    color = selectedTrigger.textColor,
                    callback = function(r, g, b, a) selectedTrigger.textColor = { r, g, b, a }; ApplySettings() end,
                })
                row4:AddWidget(textColorPicker, 1)
                card4:AddRow(row4, Theme.rowHeightLast, 0)
            end

            yOffset = yOffset + card4:GetContentHeight() + padding

            return yOffset
        end

        ----------------------------------------------------------------
        -- Render: Load sub-tab (role filter only — pos filter deferred)
        ----------------------------------------------------------------
        local function RenderLoadTab(yOffset)
            if not selectedTrigger then
                local card = GUIFrame:CreateCard(scrollChild, "No Timer Selected", yOffset)
                card:AddLabel("Click + to create a new timer, or select one from the list on the left.")
                table_insert(activeCards, card)
                return yOffset + card:GetContentHeight() + Theme.paddingSmall
            end

            local padding = Theme.paddingSmall

            -- Card 1: Role filter (pooled — see CreateRoleCardKit)
            roleCardPool:ReleaseAll()
            local roleKit = roleCardPool:Acquire(scrollChild)
            local card1 = ConfigureRoleCardKit(roleKit, scrollChild, yOffset,
                selectedTrigger, ApplySettings, RefreshContentDeferred)
            table_insert(activeCards, card1)

            yOffset = yOffset + card1:GetContentHeight() + padding

            return yOffset
        end

        ----------------------------------------------------------------
        -- Render: Actions sub-tab
        ----------------------------------------------------------------
        local function RenderActionsTab(yOffset)
            if not selectedTrigger then
                local card = GUIFrame:CreateCard(scrollChild, "No Timer Selected", yOffset)
                card:AddLabel("Click + to create a new timer, or select one from the list on the left.")
                table_insert(activeCards, card)
                return yOffset + card:GetContentHeight() + Theme.paddingSmall
            end

            local card1
            card1, yOffset = GUIFrame:CreateSoundSettingsCard(scrollChild, yOffset, {
                db = selectedTrigger,
                onChangeCallback = ApplySettings,
            })
            table_insert(activeCards, card1)

            return yOffset
        end

        RenderContent = function(tabId)
            contentArea:ClearContent()
            local yOffset = Theme.paddingSmall
            if tabId == "trigger" then
                yOffset = RenderTriggerTab(yOffset)
            elseif tabId == "display" then
                yOffset = RenderDisplayTab(yOffset)
            elseif tabId == "load" then
                yOffset = RenderLoadTab(yOffset)
            elseif tabId == "actions" then
                yOffset = RenderActionsTab(yOffset)
            end
            contentArea:SetContentHeight(yOffset)
        end

        RenderContent(state.currentSubTab)

        if isModuleDisabled then
            for _, card in ipairs(activeCards) do
                if card.SetEnabled then card:SetEnabled(false) end
            end
            for _, btn in ipairs(timerButtons) do
                btn:EnableMouse(false)
            end
        end

        C_Timer.After(0.1, function()
            if panel:IsShown() and not isModuleDisabled then
                StartDungeonPreview(dungeonKey)
            end
        end)

        return panel
    end
end

for sidebarId in pairs(DUNGEON_INFO) do
    GUIFrame:RegisterPanel(sidebarId, CreateDungeonPanel(sidebarId))
end

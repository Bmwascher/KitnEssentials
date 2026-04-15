-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-DungeonTimers.lua                                   ║
-- ║  GUI: Dungeon Timers                                     ║
-- ║  Purpose: Configuration panel for the DungeonTimers      ║
-- ║           module with per-dungeon trigger editor.        ║
-- ╚══════════════════════════════════════════════════════════╝
-- KE namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme or {}

-- Localization
local table_insert = table.insert
local pairs, ipairs = pairs, ipairs
local tonumber, tostring = tonumber, tostring
local wipe = wipe
local CreateFrame = CreateFrame
local C_Spell = C_Spell
local PlaySoundFile = PlaySoundFile

-- Dungeon mapping (sidebar ID -> db key -> display name)
local DUNGEON_INFO = {
    Dungeon_MagistersTerrace   = { key = "MagistersTerrace",   name = "Magisters' Terrace" },
    Dungeon_MaisaraCaverns     = { key = "MaisaraCaverns",     name = "Maisara Caverns" },
    Dungeon_NexusPointXenas    = { key = "NexusPointXenas",    name = "Nexus-Point Xenas" },
    Dungeon_WindrunnerSpire    = { key = "WindrunnerSpire",    name = "Windrunner Spire" },
    Dungeon_AlgetharAcademy    = { key = "AlgetharAcademy",    name = "Algeth'ar Academy" },
    Dungeon_PitOfSaron         = { key = "PitOfSaron",         name = "Pit of Saron" },
    Dungeon_SeatOfTriumvirate  = { key = "SeatOfTriumvirate",  name = "Seat of the Triumvirate" },
    Dungeon_Skyreach           = { key = "Skyreach",           name = "Skyreach" },
}

-- Check if a sidebar ID is a dungeon
local function IsDungeonId(id)
    return DUNGEON_INFO[id] ~= nil
end

-- Sub-tab definitions
local SUB_TABS = {
    { id = "trigger", text = "Trigger" },
    { id = "display", text = "Display" },
    { id = "load", text = "Load" },
    { id = "actions", text = "Actions" },
}

-- Constants
local TAB_BAR_HEIGHT = 32

-- Display presets: quick-apply label + color for common warning types
local DISPLAY_PRESETS = {
    { key = "_none",    text = "None (Custom)" },
    { key = "ADD",      text = "ADD",      label = "ADD",      format = "ADD \194\187 %p",     color = { 1.0, 0.3, 0.8, 1 } },
    { key = "AMP",      text = "AMP",      label = "AMP",      format = "AMP \194\187 %p",     color = { 0.9, 0.5, 1.0, 1 } },
    { key = "AOE",      text = "AOE",      label = "AOE",      format = "AOE \194\187 %p",     color = { 1.0, 1.0, 0.2, 1 } },
    { key = "DODGE",    text = "DODGE",    label = "DODGE",    format = "DODGE \194\187 %p",   color = { 1.0, 0.6, 0.0, 1 } },
    { key = "FEET",     text = "FEET",     label = "FEET",     format = "FEET \194\187 %p",    color = { 1.0, 0.6, 0.0, 1 } },
    { key = "FRONTAL",  text = "FRONTAL",  label = "FRONTAL",  format = "FRONTAL \194\187 %p", color = { 0.77, 0.17, 0.17, 1 } },
    { key = "HIDE",     text = "HIDE",     label = "HIDE",     format = "HIDE \194\187 %p",    color = { 0.3, 0.9, 1.0, 1 } },
    { key = "KICK",     text = "KICK",     label = "KICK",     format = "KICK \194\187 %p",    color = { 1.0, 0.85, 0.0, 1 } },
    { key = "PULL",     text = "PULL",     label = "PULL",     format = "PULL \194\187 %p",    color = { 0.3, 0.9, 1.0, 1 } },
    { key = "SOAK",     text = "SOAK",     label = "SOAK",     format = "SOAK \194\187 %p",    color = { 0.2, 1.0, 0.4, 1 } },
    { key = "SPREAD",   text = "SPREAD",   label = "SPREAD",   format = "SPREAD \194\187 %p",  color = { 1.0, 0.6, 0.0, 1 } },
    { key = "STACK",    text = "STACK",    label = "STACK",    format = "STACK \194\187 %p",   color = { 0.2, 1.0, 0.4, 1 } },
    { key = "TANK",     text = "TANK HIT", label = "TANK HIT", format = "TANK HIT \194\187 %p", color = { 0.77, 0.17, 0.17, 1 } },
}

-- State per dungeon
local dungeonStates = {}

-- Preview state
local currentPreviewDungeon = nil
local currentPreviewTimer = nil
local previewActive = false

-- Get module reference
local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("DungeonTimers", true)
    end
    return nil
end

-- Stop preview
local function StopPreview()
    previewActive = false
    currentPreviewDungeon = nil
    currentPreviewTimer = nil
    local mod = GetModule()
    if mod then
        -- Disable previews first (this also hides preview frames)
        if mod.DisablePreviews then
            mod:DisablePreviews()
        end
        -- Also call HideAll for good measure
        if mod.HideAll then
            mod:HideAll()
        end
    end
end

-- Start looping preview for all timers in a dungeon
local function StartDungeonPreview(dungeonKey)
    -- CRITICAL: Only allow previews if GUI is actually open
    if not GUIFrame or not GUIFrame:IsShown() then
        return
    end

    -- Stop any existing preview first
    StopPreview()

    if not dungeonKey then return end

    currentPreviewDungeon = dungeonKey
    previewActive = true

    local mod = GetModule()
    if not mod then return end

    -- Enable previews before starting
    if mod.EnablePreviews then
        mod:EnablePreviews()
    end

    -- Create the loop callback with closure over current state
    local function loopCallback()
        -- CRITICAL: Only restart if GUI is still open
        if not GUIFrame or not GUIFrame:IsShown() then
            return
        end
        -- Only restart if still previewing the same dungeon and preview is active
        if previewActive and currentPreviewDungeon == dungeonKey then
            local m = GetModule()
            if m and m.PreviewDungeon and m.previewsAllowed then
                m:PreviewDungeon(dungeonKey, loopCallback)
            end
        end
    end

    -- Start the preview with the loop callback
    if mod.PreviewDungeon then
        mod:PreviewDungeon(dungeonKey, loopCallback)
    end
end

-- Register global cleanup callbacks (once, at load time)
GUIFrame.contentCleanupCallbacks = GUIFrame.contentCleanupCallbacks or {}
GUIFrame.contentCleanupCallbacks["DungeonTimers"] = StopPreview

GUIFrame.onCloseCallbacks = GUIFrame.onCloseCallbacks or {}
GUIFrame.onCloseCallbacks["DungeonTimers"] = StopPreview

-- Valid sub-tab IDs
local VALID_SUB_TABS = { trigger = true, display = true, load = true, actions = true }

-- Get or init dungeon state
local function GetDungeonState(dungeonKey)
    if not dungeonStates[dungeonKey] then
        dungeonStates[dungeonKey] = {
            selectedTriggerId = nil,
            currentSubTab = "trigger",
            spellSearchFilter = "",
        }
    end
    -- Validate current sub-tab (in case old state had removed tabs)
    if not VALID_SUB_TABS[dungeonStates[dungeonKey].currentSubTab] then
        dungeonStates[dungeonKey].currentSubTab = "trigger"
    end
    return dungeonStates[dungeonKey]
end

-- Dropdown options
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

local TEXT_JUSTIFY_OPTIONS = {
    { key = "LEFT",   text = "Left" },
    { key = "CENTER", text = "Center" },
    { key = "RIGHT",  text = "Right" },
}

-- Helper to create spell icon preview
local function CreateSpellIconPreview(parent, spellId, size)
    size = size or 32
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(size)

    local iconFrame = CreateFrame("Frame", nil, container)
    iconFrame:SetSize(size, size)
    iconFrame:SetPoint("LEFT", container, "LEFT", 4, 0)

    iconFrame.texture = iconFrame:CreateTexture(nil, "ARTWORK")
    iconFrame.texture:SetPoint("TOPLEFT", 1, -1)
    iconFrame.texture:SetPoint("BOTTOMRIGHT", -1, 1)

    local texture = spellId and spellId ~= "" and C_Spell.GetSpellTexture(tonumber(spellId))
    if texture then
        iconFrame.texture:SetTexture(texture)
    else
        iconFrame.texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
    KE:ApplyIconZoom(iconFrame.texture)
    KE:AddIconBorders(iconFrame)

    local spellInfo = spellId and spellId ~= "" and C_Spell.GetSpellInfo(tonumber(spellId))
    local spellName = spellInfo and spellInfo.name or "No spell selected"

    local nameLabel = container:CreateFontString(nil, "OVERLAY")
    nameLabel:SetPoint("LEFT", iconFrame, "RIGHT", 8, 0)
    nameLabel:SetFont(KE.FONT or "Fonts\\FRIZQT__.TTF", (Theme.fontSizeSmall or 11), "OUTLINE")
    nameLabel:SetTextColor((Theme.textPrimary or {1,1,1})[1], (Theme.textPrimary or {1,1,1})[2], (Theme.textPrimary or {1,1,1})[3], 1)
    nameLabel:SetText(spellName)

    return container
end

-- Create dungeon panel
local function CreateDungeonPanel(dungeonId)
    local info = DUNGEON_INFO[dungeonId]
    if not info then return nil end

    local dungeonKey = info.key
    local dungeonName = info.name
    local state = GetDungeonState(dungeonKey)

    return function(container)
        local db = KE.db and KE.db.profile.Dungeons.DungeonTimers
        if not db then return nil end

        if not db.Dungeons then db.Dungeons = {} end
        if not db.Dungeons[dungeonKey] then
            db.Dungeons[dungeonKey] = { Enabled = true, Triggers = {} }
        end

        local dungeonDb = db.Dungeons[dungeonKey]
        if not dungeonDb.Triggers then dungeonDb.Triggers = {} end

        -- Validate selected trigger
        if state.selectedTriggerId and not dungeonDb.Triggers[state.selectedTriggerId] then
            state.selectedTriggerId = nil
            StopPreview()
        end

        local selectedTrigger = state.selectedTriggerId and dungeonDb.Triggers[state.selectedTriggerId] or nil

        local function ApplySettings()
            local mod = GetModule()
            if mod then
                if state.selectedTriggerId then
                    local frameKey = dungeonKey .. "_" .. state.selectedTriggerId
                    if mod.triggerFrames and mod.triggerFrames[frameKey] then
                        mod.triggerFrames[frameKey]:Hide()
                        mod.triggerFrames[frameKey] = nil
                    end
                end
                if mod.ApplySettings then
                    mod:ApplySettings()
                end
            end
            -- Restart preview with updated settings
            if state.selectedTriggerId then
                StartDungeonPreview(dungeonKey)
            end
        end

        local function RefreshContent()
            C_Timer.After(0.05, function()
                GUIFrame:RefreshContent()
            end)
        end

        -- Full panel frame
        local panel = CreateFrame("Frame", nil, container)
        panel:SetAllPoints()

        -- Stop preview when panel is hidden
        panel:SetScript("OnHide", function()
            if currentPreviewDungeon == dungeonKey then
                StopPreview()
            end
        end)

        ----------------------------------------------------------------
        -- Forward declarations for functions used before definition
        ----------------------------------------------------------------
        local RenderContent
        local BuildTimerList
        local UpdateTimerListSelection

        ----------------------------------------------------------------
        -- Timer List Sidebar (Left side, full height)
        ----------------------------------------------------------------
        local SIDEBAR_WIDTH = 180
        local BUTTON_HEIGHT = 24
        local LIST_PADDING = 4

        local sidebar = CreateFrame("Frame", nil, panel)
        sidebar:SetWidth(SIDEBAR_WIDTH)
        sidebar:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
        sidebar:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)

        -- Sidebar background
        local sidebarBg = sidebar:CreateTexture(nil, "BACKGROUND")
        sidebarBg:SetAllPoints()
        sidebarBg:SetColorTexture((Theme.bgDark or {0.08,0.08,0.08,1})[1], (Theme.bgDark or {0.08,0.08,0.08,1})[2], (Theme.bgDark or {0.08,0.08,0.08,1})[3], 1)

        -- Sidebar right border
        local sidebarBorder = sidebar:CreateTexture(nil, "ARTWORK")
        sidebarBorder:SetWidth(1)
        sidebarBorder:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, 0)
        sidebarBorder:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)
        sidebarBorder:SetColorTexture((Theme.border or {0.3,0.3,0.3,1})[1], (Theme.border or {0.3,0.3,0.3,1})[2], (Theme.border or {0.3,0.3,0.3,1})[3], 1)

        ----------------------------------------------------------------
        -- Sub-tab bar (next to sidebar)
        ----------------------------------------------------------------
        local tabBar = CreateFrame("Frame", nil, panel)
        tabBar:SetHeight(TAB_BAR_HEIGHT)
        tabBar:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 0, 0)
        tabBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)

        local tabBarBg = tabBar:CreateTexture(nil, "BACKGROUND")
        tabBarBg:SetAllPoints()
        tabBarBg:SetColorTexture((Theme.bgMedium or {0.12,0.12,0.12,1})[1], (Theme.bgMedium or {0.12,0.12,0.12,1})[2], (Theme.bgMedium or {0.12,0.12,0.12,1})[3], 1)

        local tabBarBorder = tabBar:CreateTexture(nil, "ARTWORK")
        tabBarBorder:SetHeight(1)
        tabBarBorder:SetPoint("BOTTOMLEFT", tabBar, "BOTTOMLEFT", 0, 0)
        tabBarBorder:SetPoint("BOTTOMRIGHT", tabBar, "BOTTOMRIGHT", 0, 0)
        tabBarBorder:SetColorTexture((Theme.border or {0.3,0.3,0.3,1})[1], (Theme.border or {0.3,0.3,0.3,1})[2], (Theme.border or {0.3,0.3,0.3,1})[3], 1)

        -- Timer list scroll area (below buttons)
        local listArea = CreateFrame("ScrollFrame", nil, sidebar, "UIPanelScrollFrameTemplate")
        listArea:SetPoint("TOPLEFT", sidebar, "TOPLEFT", LIST_PADDING, -(BUTTON_HEIGHT + LIST_PADDING * 2 + 1))
        listArea:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -LIST_PADDING, LIST_PADDING)

        -- Hide list area scrollbar decorations and set up visibility control
        local listScrollbarVisible = false
        if listArea.ScrollBar then
            local lsb = listArea.ScrollBar
            lsb:SetWidth(8)
            lsb:ClearAllPoints()
            lsb:SetPoint("TOPRIGHT", listArea, "TOPRIGHT", 0, -2)
            lsb:SetPoint("BOTTOMRIGHT", listArea, "BOTTOMRIGHT", 0, 2)
            if lsb.Background then lsb.Background:Hide() end
            if lsb.Top then lsb.Top:Hide() end
            if lsb.Middle then lsb.Middle:Hide() end
            if lsb.Bottom then lsb.Bottom:Hide() end
            if lsb.trackBG then lsb.trackBG:Hide() end
            if lsb.ScrollUpButton then lsb.ScrollUpButton:Hide() end
            if lsb.ScrollDownButton then lsb.ScrollDownButton:Hide() end
            -- Start hidden
            lsb:SetAlpha(0)
        end

        local listChild = CreateFrame("Frame", nil, listArea)
        listChild:SetHeight(1)
        listArea:SetScrollChild(listChild)

        -- Function to update list scrollbar visibility
        local function UpdateListScrollbarVisibility()
            if listArea.ScrollBar then
                local contentHeight = listChild:GetHeight()
                local frameHeight = listArea:GetHeight()
                local needsScrollbar = contentHeight > frameHeight
                listScrollbarVisible = needsScrollbar
                listArea.ScrollBar:SetAlpha(needsScrollbar and 1 or 0)
                -- Adjust child width based on scrollbar visibility
                if needsScrollbar then
                    listChild:SetWidth(SIDEBAR_WIDTH - LIST_PADDING * 2 - 10)
                else
                    listChild:SetWidth(SIDEBAR_WIDTH - LIST_PADDING * 2)
                end
            end
        end

        -- Hook events for list scrollbar visibility
        listArea:HookScript("OnScrollRangeChanged", UpdateListScrollbarVisibility)
        listChild:HookScript("OnSizeChanged", UpdateListScrollbarVisibility)
        listArea:HookScript("OnSizeChanged", UpdateListScrollbarVisibility)

        -- Initial width
        listChild:SetWidth(SIDEBAR_WIDTH - LIST_PADDING * 2)

        -- Track timer buttons for refreshing
        local timerButtons = {}

        -- Create a timer button
        local function CreateTimerButton(index, triggerId, triggerData)
            local btn = CreateFrame("Button", nil, listChild)
            btn:SetHeight(BUTTON_HEIGHT)
            btn:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -(index - 1) * (BUTTON_HEIGHT + 2))
            btn:SetPoint("TOPRIGHT", listChild, "TOPRIGHT", 0, -(index - 1) * (BUTTON_HEIGHT + 2))
            btn.triggerId = triggerId

            -- Background
            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0, 0, 0, 0)
            btn.bg = bg

            -- Hover highlight
            local hover = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
            hover:SetAllPoints()
            hover:SetColorTexture(1, 1, 1, 0.05)
            hover:Hide()
            btn.hover = hover

            -- Selected highlight
            local selected = btn:CreateTexture(nil, "BACKGROUND", nil, 2)
            selected:SetAllPoints()
            selected:SetColorTexture((Theme.accent or {0.4,0.7,1})[1], (Theme.accent or {0.4,0.7,1})[2], (Theme.accent or {0.4,0.7,1})[3], 0.2)
            selected:Hide()
            btn.selected = selected

            -- Spell icon (left side)
            local iconSize = BUTTON_HEIGHT - 4
            local iconFrame = CreateFrame("Frame", nil, btn)
            iconFrame:SetSize(iconSize, iconSize)
            iconFrame:SetPoint("LEFT", btn, "LEFT", 4, 0)

            local spellIcon = iconFrame:CreateTexture(nil, "ARTWORK")
            spellIcon:SetPoint("TOPLEFT", 1, -1)
            spellIcon:SetPoint("BOTTOMRIGHT", -1, 1)

            -- Try to get spell texture from spellId
            local spellId = triggerData.spellId and tonumber(triggerData.spellId)
            if spellId and spellId > 0 then
                local iconTexture = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellId)
                if iconTexture then
                    spellIcon:SetTexture(iconTexture)
                else
                    spellIcon:SetTexture(134400)  -- Default question mark icon
                end
            else
                spellIcon:SetTexture(134400)  -- Default question mark icon
            end
            KE:ApplyIconZoom(spellIcon)
            KE:AddIconBorders(iconFrame)
            btn.spellIcon = spellIcon

            -- Display type indicator (right side)
            local typeIndicator = btn:CreateFontString(nil, "OVERLAY")
            typeIndicator:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
            typeIndicator:SetFont(KE.FONT or "Fonts\\FRIZQT__.TTF", 12, "OUTLINE")

            local isBar = triggerData.displayType == "bar"
            if isBar then
                typeIndicator:SetText("Bar")
                typeIndicator:SetTextColor(0.4, 0.7, 1.0, 0.9)  -- Blue for bars
            else
                typeIndicator:SetText("Text")
                typeIndicator:SetTextColor(0.4, 1.0, 0.5, 0.9)  -- Green for text
            end
            btn.typeIndicator = typeIndicator

            -- Sound indicator (S) - shown if trigger has sound actions
            local hasSound = (triggerData.actionOnShowSound and triggerData.actionOnShowSound ~= "" and triggerData.actionOnShowSound ~= "None")
                          or (triggerData.actionOnHideSound and triggerData.actionOnHideSound ~= "" and triggerData.actionOnHideSound ~= "None")
            local soundIndicator = btn:CreateFontString(nil, "OVERLAY")
            soundIndicator:SetPoint("RIGHT", typeIndicator, "LEFT", -2, 0)
            soundIndicator:SetFont(KE.FONT or "Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
            if hasSound then
                soundIndicator:SetText("S")
                soundIndicator:SetTextColor(1.0, 0.8, 0.3, 0.9)  -- Yellow/gold for sound
            else
                soundIndicator:SetText("")
            end
            btn.soundIndicator = soundIndicator

            -- Label (between icon and indicators)
            local label = btn:CreateFontString(nil, "OVERLAY")
            label:SetPoint("LEFT", spellIcon, "RIGHT", 4, 0)
            label:SetPoint("RIGHT", soundIndicator, "LEFT", -2, 0)
            label:SetJustifyH("LEFT")
            label:SetFont(KE.FONT or "Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
            local displayName = triggerData.name or ("Timer " .. triggerId)
            if #displayName > 24 then
                displayName = displayName:sub(1, 24) .. ".."
            end
            label:SetText(displayName)
            label:SetTextColor((Theme.textSecondary or {0.7,0.7,0.7})[1], (Theme.textSecondary or {0.7,0.7,0.7})[2], (Theme.textSecondary or {0.7,0.7,0.7})[3], 1)
            btn.label = label

            -- Events
            btn:SetScript("OnEnter", function(self)
                if state.selectedTriggerId ~= self.triggerId then
                    self.hover:Show()
                    self.label:SetTextColor(1, 1, 1, 1)
                end
            end)

            btn:SetScript("OnLeave", function(self)
                self.hover:Hide()
                if state.selectedTriggerId ~= self.triggerId then
                    self.label:SetTextColor((Theme.textSecondary or {0.7,0.7,0.7})[1], (Theme.textSecondary or {0.7,0.7,0.7})[2], (Theme.textSecondary or {0.7,0.7,0.7})[3], 1)
                end
            end)

            btn:SetScript("OnClick", function(self)
                state.selectedTriggerId = self.triggerId
                selectedTrigger = dungeonDb.Triggers[state.selectedTriggerId]
                UpdateTimerListSelection()
                RenderContent(state.currentSubTab)
                StartDungeonPreview(dungeonKey)
            end)

            return btn
        end

        -- Update timer list selection visuals
        local function UpdateTimerListSelectionVisuals()
            for _, btn in ipairs(timerButtons) do
                if btn.triggerId == state.selectedTriggerId then
                    btn.selected:Show()
                    btn.label:SetTextColor((Theme.accent or {0.4,0.7,1})[1], (Theme.accent or {0.4,0.7,1})[2], (Theme.accent or {0.4,0.7,1})[3], 1)
                else
                    btn.selected:Hide()
                    btn.label:SetTextColor((Theme.textSecondary or {0.7,0.7,0.7})[1], (Theme.textSecondary or {0.7,0.7,0.7})[2], (Theme.textSecondary or {0.7,0.7,0.7})[3], 1)
                end
            end
        end

        -- Build the timer list
        BuildTimerList = function()
            -- Clear existing buttons
            for _, btn in ipairs(timerButtons) do
                btn:Hide()
                btn:SetParent(nil)
            end
            wipe(timerButtons)

            -- Build sorted list
            local sortedTriggers = {}
            for id, trigger in pairs(dungeonDb.Triggers) do
                table_insert(sortedTriggers, { id = id, data = trigger })
            end
            table.sort(sortedTriggers, function(a, b) return tonumber(a.id) < tonumber(b.id) end)

            -- Create buttons
            for i, item in ipairs(sortedTriggers) do
                local btn = CreateTimerButton(i, item.id, item.data)
                table_insert(timerButtons, btn)
            end

            -- Update list height
            local listHeight = #sortedTriggers * (BUTTON_HEIGHT + 2)
            listChild:SetHeight(math.max(listHeight, 1))

            -- Update selection
            UpdateTimerListSelectionVisuals()
        end

        -- Forward declaration for circular reference
        function UpdateTimerListSelection()
            UpdateTimerListSelectionVisuals()
        end

        -- Top buttons container
        local buttonArea = CreateFrame("Frame", nil, sidebar)
        buttonArea:SetHeight(BUTTON_HEIGHT + LIST_PADDING)
        buttonArea:SetPoint("TOPLEFT", sidebar, "TOPLEFT", LIST_PADDING, -LIST_PADDING)
        buttonArea:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -LIST_PADDING, -LIST_PADDING)

        -- Bottom border for button area
        local buttonAreaBorder = buttonArea:CreateTexture(nil, "ARTWORK")
        buttonAreaBorder:SetHeight(1)
        buttonAreaBorder:SetPoint("BOTTOMLEFT", buttonArea, "BOTTOMLEFT", 0, 0)
        buttonAreaBorder:SetPoint("BOTTOMRIGHT", buttonArea, "BOTTOMRIGHT", 0, 0)
        buttonAreaBorder:SetColorTexture((Theme.border or {0.3,0.3,0.3,1})[1], (Theme.border or {0.3,0.3,0.3,1})[2], (Theme.border or {0.3,0.3,0.3,1})[3], 0.5)

        -- Button width for 5 buttons
        local btnWidth = (SIDEBAR_WIDTH - LIST_PADDING * 6) / 5

        -- Helper to add border to a button
        local function AddButtonBorder(btn)
            local borderColor = Theme.border or {0.3, 0.3, 0.3, 1}
            local r, g, b, a = borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1

            local top = btn:CreateTexture(nil, "BORDER")
            top:SetHeight(1)
            top:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
            top:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
            top:SetColorTexture(r, g, b, a)

            local bottom = btn:CreateTexture(nil, "BORDER")
            bottom:SetHeight(1)
            bottom:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
            bottom:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
            bottom:SetColorTexture(r, g, b, a)

            local left = btn:CreateTexture(nil, "BORDER")
            left:SetWidth(1)
            left:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
            left:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
            left:SetColorTexture(r, g, b, a)

            local right = btn:CreateTexture(nil, "BORDER")
            right:SetWidth(1)
            right:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
            right:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
            right:SetColorTexture(r, g, b, a)
        end

        -- New Timer Button (+)
        local newBtn = CreateFrame("Button", nil, buttonArea)
        newBtn:SetSize(btnWidth, BUTTON_HEIGHT)
        newBtn:SetPoint("TOPLEFT", buttonArea, "TOPLEFT", 0, 0)

        local newBtnBg = newBtn:CreateTexture(nil, "BACKGROUND")
        newBtnBg:SetAllPoints()
        newBtnBg:SetColorTexture((Theme.bgLight or {0.18,0.18,0.18,1})[1], (Theme.bgLight or {0.18,0.18,0.18,1})[2], (Theme.bgLight or {0.18,0.18,0.18,1})[3], 1)
        AddButtonBorder(newBtn)

        local newBtnLabel = newBtn:CreateFontString(nil, "OVERLAY")
        newBtnLabel:SetPoint("CENTER")
        if KE.ApplyThemeFont then
            KE:ApplyThemeFont(newBtnLabel, "small")
        else
            newBtnLabel:SetFont(KE.FONT or "Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        end
        newBtnLabel:SetText("+")
        newBtnLabel:SetTextColor((Theme.textPrimary or {1,1,1})[1], (Theme.textPrimary or {1,1,1})[2], (Theme.textPrimary or {1,1,1})[3], 1)

        newBtn:SetScript("OnEnter", function(self)
            newBtnBg:SetColorTexture((Theme.accent or {0.4,0.7,1})[1], (Theme.accent or {0.4,0.7,1})[2], (Theme.accent or {0.4,0.7,1})[3], 0.3)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Create New Timer")
            GameTooltip:Show()
        end)
        newBtn:SetScript("OnLeave", function(self)
            newBtnBg:SetColorTexture((Theme.bgLight or {0.18,0.18,0.18,1})[1], (Theme.bgLight or {0.18,0.18,0.18,1})[2], (Theme.bgLight or {0.18,0.18,0.18,1})[3], 1)
            GameTooltip:Hide()
        end)
        newBtn:SetScript("OnClick", function()
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
        end)

        -- Duplicate Timer Button (D)
        local dupBtn = CreateFrame("Button", nil, buttonArea)
        dupBtn:SetSize(btnWidth, BUTTON_HEIGHT)
        dupBtn:SetPoint("LEFT", newBtn, "RIGHT", LIST_PADDING, 0)

        local dupBtnBg = dupBtn:CreateTexture(nil, "BACKGROUND")
        dupBtnBg:SetAllPoints()
        dupBtnBg:SetColorTexture((Theme.bgLight or {0.18,0.18,0.18,1})[1], (Theme.bgLight or {0.18,0.18,0.18,1})[2], (Theme.bgLight or {0.18,0.18,0.18,1})[3], 1)
        AddButtonBorder(dupBtn)

        local dupBtnLabel = dupBtn:CreateFontString(nil, "OVERLAY")
        dupBtnLabel:SetPoint("CENTER")
        if KE.ApplyThemeFont then
            KE:ApplyThemeFont(dupBtnLabel, "small")
        else
            dupBtnLabel:SetFont(KE.FONT or "Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        end
        dupBtnLabel:SetText("D")
        dupBtnLabel:SetTextColor((Theme.textPrimary or {1,1,1})[1], (Theme.textPrimary or {1,1,1})[2], (Theme.textPrimary or {1,1,1})[3], 1)

        dupBtn:SetScript("OnEnter", function(self)
            dupBtnBg:SetColorTexture((Theme.accent or {0.4,0.7,1})[1], (Theme.accent or {0.4,0.7,1})[2], (Theme.accent or {0.4,0.7,1})[3], 0.3)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Duplicate Selected Timer")
            GameTooltip:Show()
        end)
        dupBtn:SetScript("OnLeave", function(self)
            dupBtnBg:SetColorTexture((Theme.bgLight or {0.18,0.18,0.18,1})[1], (Theme.bgLight or {0.18,0.18,0.18,1})[2], (Theme.bgLight or {0.18,0.18,0.18,1})[3], 1)
            GameTooltip:Hide()
        end)
        dupBtn:SetScript("OnClick", function()
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
        end)

        -- Delete Timer Button (-)
        local delBtn = CreateFrame("Button", nil, buttonArea)
        delBtn:SetSize(btnWidth, BUTTON_HEIGHT)
        delBtn:SetPoint("LEFT", dupBtn, "RIGHT", LIST_PADDING, 0)

        local delBtnBg = delBtn:CreateTexture(nil, "BACKGROUND")
        delBtnBg:SetAllPoints()
        delBtnBg:SetColorTexture((Theme.bgLight or {0.18,0.18,0.18,1})[1], (Theme.bgLight or {0.18,0.18,0.18,1})[2], (Theme.bgLight or {0.18,0.18,0.18,1})[3], 1)
        AddButtonBorder(delBtn)

        local delBtnLabel = delBtn:CreateFontString(nil, "OVERLAY")
        delBtnLabel:SetPoint("CENTER")
        if KE.ApplyThemeFont then
            KE:ApplyThemeFont(delBtnLabel, "small")
        else
            delBtnLabel:SetFont(KE.FONT or "Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        end
        delBtnLabel:SetText("-")
        delBtnLabel:SetTextColor((Theme.textPrimary or {1,1,1})[1], (Theme.textPrimary or {1,1,1})[2], (Theme.textPrimary or {1,1,1})[3], 1)

        delBtn:SetScript("OnEnter", function(self)
            delBtnBg:SetColorTexture(0.8, 0.2, 0.2, 0.3)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Remove Selected Timer")
            GameTooltip:Show()
        end)
        delBtn:SetScript("OnLeave", function(self)
            delBtnBg:SetColorTexture((Theme.bgLight or {0.18,0.18,0.18,1})[1], (Theme.bgLight or {0.18,0.18,0.18,1})[2], (Theme.bgLight or {0.18,0.18,0.18,1})[3], 1)
            GameTooltip:Hide()
        end)
        delBtn:SetScript("OnClick", function()
            if state.selectedTriggerId then
                local mod = GetModule()
                if mod and mod.DeleteTrigger then
                    mod:DeleteTrigger(dungeonKey, state.selectedTriggerId)
                    state.selectedTriggerId = nil
                    selectedTrigger = nil
                    BuildTimerList()
                    RenderContent(state.currentSubTab)
                    -- Restart preview to show remaining triggers
                    StartDungeonPreview(dungeonKey)
                end
            end
        end)

        -- Move Up Button (▲)
        local upBtn = CreateFrame("Button", nil, buttonArea)
        upBtn:SetSize(btnWidth, BUTTON_HEIGHT)
        upBtn:SetPoint("LEFT", delBtn, "RIGHT", LIST_PADDING, 0)

        local upBtnBg = upBtn:CreateTexture(nil, "BACKGROUND")
        upBtnBg:SetAllPoints()
        upBtnBg:SetColorTexture((Theme.bgLight or {0.18,0.18,0.18,1})[1], (Theme.bgLight or {0.18,0.18,0.18,1})[2], (Theme.bgLight or {0.18,0.18,0.18,1})[3], 1)
        AddButtonBorder(upBtn)

        local upBtnIcon = upBtn:CreateTexture(nil, "OVERLAY")
        upBtnIcon:SetSize(12, 12)
        upBtnIcon:SetPoint("CENTER")
        upBtnIcon:SetTexture(KE.PATH .. "GUITextures\\collapse.tga")
        upBtnIcon:SetRotation(math.pi)  -- Rotate 180 degrees to point up
        upBtnIcon:SetVertexColor((Theme.textPrimary or {1,1,1})[1], (Theme.textPrimary or {1,1,1})[2], (Theme.textPrimary or {1,1,1})[3], 1)

        upBtn:SetScript("OnEnter", function(self)
            upBtnBg:SetColorTexture((Theme.accent or {0.4,0.7,1})[1], (Theme.accent or {0.4,0.7,1})[2], (Theme.accent or {0.4,0.7,1})[3], 0.3)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Move Timer Up")
            GameTooltip:Show()
        end)
        upBtn:SetScript("OnLeave", function(self)
            upBtnBg:SetColorTexture((Theme.bgLight or {0.18,0.18,0.18,1})[1], (Theme.bgLight or {0.18,0.18,0.18,1})[2], (Theme.bgLight or {0.18,0.18,0.18,1})[3], 1)
            GameTooltip:Hide()
        end)
        upBtn:SetScript("OnClick", function()
            if state.selectedTriggerId then
                local mod = GetModule()
                if mod and mod.MoveTriggerUp then
                    local newId = mod:MoveTriggerUp(dungeonKey, state.selectedTriggerId)
                    if newId then
                        state.selectedTriggerId = newId
                        selectedTrigger = dungeonDb.Triggers[newId]
                        BuildTimerList()
                        RenderContent(state.currentSubTab)
                        StartDungeonPreview(dungeonKey)
                    end
                end
            end
        end)

        -- Move Down Button (▼)
        local downBtn = CreateFrame("Button", nil, buttonArea)
        downBtn:SetSize(btnWidth, BUTTON_HEIGHT)
        downBtn:SetPoint("LEFT", upBtn, "RIGHT", LIST_PADDING, 0)

        local downBtnBg = downBtn:CreateTexture(nil, "BACKGROUND")
        downBtnBg:SetAllPoints()
        downBtnBg:SetColorTexture((Theme.bgLight or {0.18,0.18,0.18,1})[1], (Theme.bgLight or {0.18,0.18,0.18,1})[2], (Theme.bgLight or {0.18,0.18,0.18,1})[3], 1)
        AddButtonBorder(downBtn)

        local downBtnIcon = downBtn:CreateTexture(nil, "OVERLAY")
        downBtnIcon:SetSize(12, 12)
        downBtnIcon:SetPoint("CENTER")
        downBtnIcon:SetTexture(KE.PATH .. "GUITextures\\collapse.tga")
        -- No rotation needed - collapse.tga already points down
        downBtnIcon:SetVertexColor((Theme.textPrimary or {1,1,1})[1], (Theme.textPrimary or {1,1,1})[2], (Theme.textPrimary or {1,1,1})[3], 1)

        downBtn:SetScript("OnEnter", function(self)
            downBtnBg:SetColorTexture((Theme.accent or {0.4,0.7,1})[1], (Theme.accent or {0.4,0.7,1})[2], (Theme.accent or {0.4,0.7,1})[3], 0.3)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Move Timer Down")
            GameTooltip:Show()
        end)
        downBtn:SetScript("OnLeave", function(self)
            downBtnBg:SetColorTexture((Theme.bgLight or {0.18,0.18,0.18,1})[1], (Theme.bgLight or {0.18,0.18,0.18,1})[2], (Theme.bgLight or {0.18,0.18,0.18,1})[3], 1)
            GameTooltip:Hide()
        end)
        downBtn:SetScript("OnClick", function()
            if state.selectedTriggerId then
                local mod = GetModule()
                if mod and mod.MoveTriggerDown then
                    local newId = mod:MoveTriggerDown(dungeonKey, state.selectedTriggerId)
                    if newId then
                        state.selectedTriggerId = newId
                        selectedTrigger = dungeonDb.Triggers[newId]
                        BuildTimerList()
                        RenderContent(state.currentSubTab)
                        StartDungeonPreview(dungeonKey)
                    end
                end
            end
        end)

        -- Build initial timer list
        BuildTimerList()

        ----------------------------------------------------------------
        -- Scroll frame for content (Right side)
        ----------------------------------------------------------------
        local scrollbarWidth = Theme.scrollbarWidth or 16
        local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -1)
        scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)

        -- Style scrollbar
        if scrollFrame.ScrollBar then
            local sb = scrollFrame.ScrollBar
            sb:ClearAllPoints()
            sb:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", -3, -13)
            sb:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", -3, 13)
            sb:SetWidth(scrollbarWidth - 4)

            -- Hide default scrollbar decorations
            if sb.Background then sb.Background:Hide() end
            if sb.Top then sb.Top:Hide() end
            if sb.Middle then sb.Middle:Hide() end
            if sb.Bottom then sb.Bottom:Hide() end
            if sb.trackBG then sb.trackBG:Hide() end
            if sb.ScrollUpButton then sb.ScrollUpButton:Hide() end
            if sb.ScrollDownButton then sb.ScrollDownButton:Hide() end

            -- Hide thumb when not needed
            sb:SetAlpha(0)

            -- Pixel snapping for smooth scrolling
            local isSnapping = false
            local PIXEL_STEP = 8 / 15
            sb:HookScript("OnValueChanged", function(self, value)
                if isSnapping then return end
                local scale = scrollFrame:GetEffectiveScale()
                local screenPixels = value * scale
                local snappedPixels = math.floor(screenPixels / PIXEL_STEP + 0.5) * PIXEL_STEP
                local snappedValue = snappedPixels / scale
                if math.abs(value - snappedValue) > 0.001 then
                    isSnapping = true
                    self:SetValue(snappedValue)
                    isSnapping = false
                end
            end)
        end

        -- Scroll child (dynamic width based on scrollbar visibility)
        local scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetHeight(1)
        scrollFrame:SetScrollChild(scrollChild)

        -- Track scrollbar visibility state
        local scrollbarVisible = false

        -- Track cards for width updates
        local activeCards = {}

        -- Update scrollChild width dynamically from panel width
        local function UpdateScrollChildWidth()
            local panelWidth = panel:GetWidth() or 540
            local baseWidth = panelWidth - SIDEBAR_WIDTH - 1
            if scrollbarVisible then
                scrollChild:SetWidth(baseWidth - scrollbarWidth)
            else
                scrollChild:SetWidth(baseWidth)
            end
        end

        -- Update all card widths when scrollChild resizes
        local function UpdateCardWidths()
            local newWidth = scrollChild:GetWidth()
            for _, card in ipairs(activeCards) do
                if card and card.SetWidth then
                    card:SetWidth(newWidth)
                end
            end
        end

        -- Show/hide scrollbar and adjust content width based on content height
        local function UpdateScrollBarVisibility()
            if scrollFrame.ScrollBar then
                local contentHeight = scrollChild:GetHeight()
                local frameHeight = scrollFrame:GetHeight()
                local needsScrollbar = contentHeight > frameHeight

                scrollbarVisible = needsScrollbar
                scrollFrame.ScrollBar:SetAlpha(needsScrollbar and 1 or 0)
                UpdateScrollChildWidth()
            end
        end

        -- Initial width setup
        UpdateScrollChildWidth()

        -- Hook events for visibility updates
        scrollFrame:HookScript("OnScrollRangeChanged", UpdateScrollBarVisibility)
        scrollChild:HookScript("OnSizeChanged", function(self, width, height)
            UpdateScrollBarVisibility()
            UpdateCardWidths()
        end)
        scrollFrame:HookScript("OnSizeChanged", UpdateScrollBarVisibility)
        panel:HookScript("OnSizeChanged", function()
            UpdateScrollChildWidth()
            UpdateCardWidths()
        end)

        -- Also update on show (in case content changed while hidden)
        scrollFrame:HookScript("OnShow", function()
            C_Timer.After(0, UpdateScrollBarVisibility)
        end)

        ----------------------------------------------------------------
        -- Tab render functions
        ----------------------------------------------------------------
        local function RenderTriggerTab(yOffset)
            if not selectedTrigger then
                local card = GUIFrame:CreateCard(scrollChild, "No Timer Selected", yOffset)
                card:AddLabel("Click + to create a new timer, or select one from the list on the left.")
                table_insert(activeCards, card)
                return yOffset + card:GetContentHeight() + (Theme.paddingSmall or 8)
            end

            local padding = Theme.paddingSmall or 8

            -- Basic Settings Card
            local card1 = GUIFrame:CreateCard(scrollChild, "Basic Settings", yOffset)
            table_insert(activeCards, card1)

            local row1 = GUIFrame:CreateRow(card1.content, 40)
            local nameInput = GUIFrame:CreateEditBox(row1, "Timer Name", selectedTrigger.name or "",
                function(text)
                    selectedTrigger.name = text
                    ApplySettings()
                    RefreshContent()
                end)
            row1:AddWidget(nameInput, 0.5)

            local enableTrigger = GUIFrame:CreateCheckbox(row1, "Enabled", selectedTrigger.enabled ~= false,
                function(checked)
                    selectedTrigger.enabled = checked
                    ApplySettings()
                end)
            row1:AddWidget(enableTrigger, 0.5)
            card1:AddRow(row1, 40)

            local row2 = GUIFrame:CreateRow(card1.content, 40)
            local typeDropdown = GUIFrame:CreateDropdown(row2, "Trigger Type", TRIGGER_TYPE_OPTIONS,
                selectedTrigger.triggerType or "timer", 100,
                function(key)
                    selectedTrigger.triggerType = key
                    ApplySettings()
                end)
            row2:AddWidget(typeDropdown, 1)
            card1:AddRow(row2, 40)

            yOffset = yOffset + card1:GetContentHeight() + padding

            -- Filter Card
            local card2 = GUIFrame:CreateCard(scrollChild, "Trigger Filters", yOffset)
            table_insert(activeCards, card2)

            local row3 = GUIFrame:CreateRow(card2.content, 40)
            local spellInput = GUIFrame:CreateEditBox(row3, "Spell ID (optional)", selectedTrigger.spellId or "",
                function(text)
                    selectedTrigger.spellId = text
                    ApplySettings()
                    RefreshContent()
                end)
            row3:AddWidget(spellInput, 0.5)

            local iconPreview = CreateSpellIconPreview(row3, selectedTrigger.spellId, 32)
            row3:AddWidget(iconPreview, 0.5)
            card2:AddRow(row3, 40)

            local row4 = GUIFrame:CreateRow(card2.content, 40)
            local msgInput = GUIFrame:CreateEditBox(row4, "Message Filter (optional)", selectedTrigger.message or "",
                function(text)
                    selectedTrigger.message = text
                    ApplySettings()
                end)
            row4:AddWidget(msgInput, 0.5)

            local msgOpDropdown = GUIFrame:CreateDropdown(row4, "Match", MESSAGE_OPERATOR_OPTIONS,
                selectedTrigger.messageOperator or "find", 80,
                function(key)
                    selectedTrigger.messageOperator = key
                    ApplySettings()
                end)
            row4:AddWidget(msgOpDropdown, 0.5)
            card2:AddRow(row4, 40)

            local row5 = GUIFrame:CreateRow(card2.content, 40)
            local offsetSlider = GUIFrame:CreateSlider(row5, "Timer Offset (seconds)", -10, 10, 0.5,
                selectedTrigger.extendTimer or 0, 80,
                function(val)
                    selectedTrigger.extendTimer = val
                    ApplySettings()
                end)
            row5:AddWidget(offsetSlider, 1)
            card2:AddRow(row5, 40)

            yOffset = yOffset + card2:GetContentHeight() + padding

            -- Remaining Time Filter Card
            local card3 = GUIFrame:CreateCard(scrollChild, "Remaining Time Condition", yOffset)
            table_insert(activeCards, card3)

            local row6 = GUIFrame:CreateRow(card3.content, 36)
            local remCheck = GUIFrame:CreateCheckbox(row6, "Enable remaining time condition",
                selectedTrigger.remainingEnabled == true,
                function(checked)
                    selectedTrigger.remainingEnabled = checked
                    ApplySettings()
                    RefreshContent()
                end)
            row6:AddWidget(remCheck, 1)
            card3:AddRow(row6, 36)

            if selectedTrigger.remainingEnabled then
                local row7 = GUIFrame:CreateRow(card3.content, 40)
                local remOpDropdown = GUIFrame:CreateDropdown(row7, "Operator", COMPARISON_OPTIONS,
                    selectedTrigger.remainingOperator or "<", 140,
                    function(key)
                        selectedTrigger.remainingOperator = key
                        ApplySettings()
                    end)
                row7:AddWidget(remOpDropdown, 0.5)

                local remSlider = GUIFrame:CreateSlider(row7, "Seconds", 1, 60, 1,
                    selectedTrigger.remainingValue or 5, 60,
                    function(val)
                        selectedTrigger.remainingValue = val
                        ApplySettings()
                    end)
                row7:AddWidget(remSlider, 0.5)
                card3:AddRow(row7, 40)
            end

            yOffset = yOffset + card3:GetContentHeight() + padding

            -- BigWigs Spell Browser Card
            local mod = GetModule()
            local spells = mod and mod.GetSpellsForDungeon and mod:GetSpellsForDungeon(dungeonKey) or {}

            if #spells > 0 then
                local browserCard = GUIFrame:CreateCard(scrollChild, "Browse BigWigs Spells", yOffset)
                table_insert(activeCards, browserCard)

                -- Search input
                local searchRow = GUIFrame:CreateRow(browserCard.content, 40)
                local searchValue = state.spellSearchFilter or ""
                local searchInput = GUIFrame:CreateEditBox(searchRow, "Search spells...", searchValue,
                    function(text)
                        state.spellSearchFilter = text
                        RefreshContent()
                    end)
                searchRow:AddWidget(searchInput, 1)
                browserCard:AddRow(searchRow, 40)

                -- Filter spells by search term
                local filteredSpells = {}
                local searchLower = (state.spellSearchFilter or ""):lower()
                for _, spell in ipairs(spells) do
                    if searchLower == "" or (spell.name and spell.name:lower():find(searchLower, 1, true)) then
                        table_insert(filteredSpells, spell)
                    end
                end

                -- Group spells by boss (using sortKey for ordering)
                local bossGroups = {}
                local bossOrder = {}
                local bossInfo = {} -- Store boss info for header display
                for _, spell in ipairs(filteredSpells) do
                    local bossKey = spell.sortKey or 999999
                    if not bossGroups[bossKey] then
                        bossGroups[bossKey] = {}
                        table_insert(bossOrder, bossKey)
                        bossInfo[bossKey] = {
                            name = spell.bossName or "Unknown",
                            num = spell.bossNum or 0,
                        }
                    end
                    table_insert(bossGroups[bossKey], spell)
                end

                -- Sort boss order by engageId
                table.sort(bossOrder)

                -- Render each boss group
                for _, bossKey in ipairs(bossOrder) do
                    local boss = bossInfo[bossKey]
                    local headerText = boss.num > 0
                        and string.format("— B%d: %s —", boss.num, boss.name)
                        or string.format("— %s —", boss.name)

                    -- Boss header row
                    local headerRow = GUIFrame:CreateRow(browserCard.content, 24)
                    local headerLabel = headerRow:CreateFontString(nil, "OVERLAY")
                    headerLabel:SetPoint("LEFT", headerRow, "LEFT", 4, 0)
                    if KE.ApplyThemeFont then
                        KE:ApplyThemeFont(headerLabel, "small")
                    else
                        headerLabel:SetFont(KE.FONT or "Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
                    end
                    headerLabel:SetText(headerText)
                    headerLabel:SetTextColor((Theme.textSecondary or {0.7,0.7,0.7})[1], (Theme.textSecondary or {0.7,0.7,0.7})[2], (Theme.textSecondary or {0.7,0.7,0.7})[3], 1)
                    browserCard:AddRow(headerRow, 24)

                    -- Spell rows for this boss
                    for _, spell in ipairs(bossGroups[bossKey]) do
                        local spellRow = GUIFrame:CreateRow(browserCard.content, 28)

                        -- Enable mouse for tooltip on entire row
                        spellRow:EnableMouse(true)
                        local capturedSpellIdForTooltip = spell.spellId
                        spellRow:SetScript("OnEnter", function(self)
                            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                            GameTooltip:SetSpellByID(capturedSpellIdForTooltip)
                            GameTooltip:Show()
                        end)
                        spellRow:SetScript("OnLeave", function(self)
                            GameTooltip:Hide()
                        end)

                        -- Spell icon
                        local iconFrame = CreateFrame("Frame", nil, spellRow)
                        iconFrame:SetSize(24, 24)
                        iconFrame:SetPoint("LEFT", spellRow, "LEFT", 4, 0)

                        local iconTexture = iconFrame:CreateTexture(nil, "ARTWORK")
                        iconTexture:SetPoint("TOPLEFT", 1, -1)
                        iconTexture:SetPoint("BOTTOMRIGHT", -1, 1)
                        iconTexture:SetTexture(spell.icon or 134400)
                        if KE.ApplyIconZoom then
                            KE:ApplyIconZoom(iconTexture, 0.1)
                        end

                        local iconBorder = CreateFrame("Frame", nil, iconFrame, "BackdropTemplate")
                        iconBorder:SetAllPoints()
                        iconBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
                        iconBorder:SetBackdropBorderColor(0, 0, 0, 1)

                        -- Spell name and ID
                        local spellLabel = spellRow:CreateFontString(nil, "OVERLAY")
                        spellLabel:SetPoint("LEFT", iconFrame, "RIGHT", 6, 0)
                        spellLabel:SetPoint("RIGHT", spellRow, "RIGHT", -70, 0)
                        spellLabel:SetJustifyH("LEFT")
                        if KE.ApplyThemeFont then
                            KE:ApplyThemeFont(spellLabel, "small")
                        else
                            spellLabel:SetFont(KE.FONT or "Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
                        end
                        spellLabel:SetText(spell.name .. " (" .. spell.spellId .. ")")
                        spellLabel:SetTextColor((Theme.textPrimary or {1,1,1})[1], (Theme.textPrimary or {1,1,1})[2], (Theme.textPrimary or {1,1,1})[3], 1)

                        -- Use button
                        local useBtn = CreateFrame("Button", nil, spellRow)
                        useBtn:SetSize(50, 22)
                        useBtn:SetPoint("RIGHT", spellRow, "RIGHT", -4, 0)

                        local useBtnBg = useBtn:CreateTexture(nil, "BACKGROUND")
                        useBtnBg:SetAllPoints()
                        useBtnBg:SetColorTexture((Theme.bgLight or {0.18,0.18,0.18,1})[1], (Theme.bgLight or {0.18,0.18,0.18,1})[2], (Theme.bgLight or {0.18,0.18,0.18,1})[3], 1)

                        -- Border for use button
                        local borderColor = Theme.border or {0.3, 0.3, 0.3, 1}
                        local useBtnBorderTop = useBtn:CreateTexture(nil, "BORDER")
                        useBtnBorderTop:SetHeight(1)
                        useBtnBorderTop:SetPoint("TOPLEFT", 0, 0)
                        useBtnBorderTop:SetPoint("TOPRIGHT", 0, 0)
                        useBtnBorderTop:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)

                        local useBtnBorderBottom = useBtn:CreateTexture(nil, "BORDER")
                        useBtnBorderBottom:SetHeight(1)
                        useBtnBorderBottom:SetPoint("BOTTOMLEFT", 0, 0)
                        useBtnBorderBottom:SetPoint("BOTTOMRIGHT", 0, 0)
                        useBtnBorderBottom:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)

                        local useBtnBorderLeft = useBtn:CreateTexture(nil, "BORDER")
                        useBtnBorderLeft:SetWidth(1)
                        useBtnBorderLeft:SetPoint("TOPLEFT", 0, 0)
                        useBtnBorderLeft:SetPoint("BOTTOMLEFT", 0, 0)
                        useBtnBorderLeft:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)

                        local useBtnBorderRight = useBtn:CreateTexture(nil, "BORDER")
                        useBtnBorderRight:SetWidth(1)
                        useBtnBorderRight:SetPoint("TOPRIGHT", 0, 0)
                        useBtnBorderRight:SetPoint("BOTTOMRIGHT", 0, 0)
                        useBtnBorderRight:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)

                        local useBtnLabel = useBtn:CreateFontString(nil, "OVERLAY")
                        useBtnLabel:SetPoint("CENTER")
                        if KE.ApplyThemeFont then
                            KE:ApplyThemeFont(useBtnLabel, "small")
                        else
                            useBtnLabel:SetFont(KE.FONT or "Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
                        end
                        useBtnLabel:SetText("Use")
                        useBtnLabel:SetTextColor((Theme.textPrimary or {1,1,1})[1], (Theme.textPrimary or {1,1,1})[2], (Theme.textPrimary or {1,1,1})[3], 1)

                        useBtn:SetScript("OnEnter", function(self)
                            useBtnBg:SetColorTexture((Theme.accent or {0.4,0.7,1})[1], (Theme.accent or {0.4,0.7,1})[2], (Theme.accent or {0.4,0.7,1})[3], 0.3)
                            -- Also show spell tooltip when hovering button
                            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                            GameTooltip:SetSpellByID(capturedSpellIdForTooltip)
                            GameTooltip:Show()
                        end)
                        useBtn:SetScript("OnLeave", function(self)
                            useBtnBg:SetColorTexture((Theme.bgLight or {0.18,0.18,0.18,1})[1], (Theme.bgLight or {0.18,0.18,0.18,1})[2], (Theme.bgLight or {0.18,0.18,0.18,1})[3], 1)
                            GameTooltip:Hide()
                        end)

                        local capturedSpellId = spell.spellId
                        useBtn:SetScript("OnClick", function()
                            if selectedTrigger then
                                selectedTrigger.spellId = tostring(capturedSpellId)
                                ApplySettings()
                                RefreshContent()
                            end
                        end)

                        browserCard:AddRow(spellRow, 28)
                    end
                end

                -- Show message if no spells match search
                if #filteredSpells == 0 and state.spellSearchFilter and state.spellSearchFilter ~= "" then
                    local noMatchRow = GUIFrame:CreateRow(browserCard.content, 30)
                    local noMatchLabel = noMatchRow:CreateFontString(nil, "OVERLAY")
                    noMatchLabel:SetPoint("LEFT", noMatchRow, "LEFT", 4, 0)
                    if KE.ApplyThemeFont then
                        KE:ApplyThemeFont(noMatchLabel, "small")
                    else
                        noMatchLabel:SetFont(KE.FONT or "Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
                    end
                    noMatchLabel:SetText("No spells match your search.")
                    noMatchLabel:SetTextColor((Theme.textSecondary or {0.7,0.7,0.7})[1], (Theme.textSecondary or {0.7,0.7,0.7})[2], (Theme.textSecondary or {0.7,0.7,0.7})[3], 1)
                    browserCard:AddRow(noMatchRow, 30)
                end

                yOffset = yOffset + browserCard:GetContentHeight() + padding
            else
                -- No BigWigs data available - show info message
                local noBwCard = GUIFrame:CreateCard(scrollChild, "BigWigs Spell Browser", yOffset)
                table_insert(activeCards, noBwCard)
                noBwCard:AddLabel("No BigWigs data available for this dungeon. Make sure BigWigs is installed and the dungeon module is loaded.")
                yOffset = yOffset + noBwCard:GetContentHeight() + padding
            end

            return yOffset
        end

        local function RenderDisplayTab(yOffset)
            if not selectedTrigger then
                local card = GUIFrame:CreateCard(scrollChild, "No Timer Selected", yOffset)
                card:AddLabel("Click + to create a new timer, or select one from the list on the left.")
                table_insert(activeCards, card)
                return yOffset + card:GetContentHeight() + (Theme.paddingSmall or 8)
            end

            local padding = Theme.paddingSmall or 8
            local isBar = (selectedTrigger.displayType or "bar") == "bar"

            -- Style Card (display type only - other display settings are global)
            local card1 = GUIFrame:CreateCard(scrollChild, "Display Type", yOffset)
            table_insert(activeCards, card1)

            local row1 = GUIFrame:CreateRow(card1.content, 40)
            local displayDropdown = GUIFrame:CreateDropdown(row1, "Style", DISPLAY_TYPE_OPTIONS,
                selectedTrigger.displayType or "bar", 100,
                function(key)
                    selectedTrigger.displayType = key
                    ApplySettings()
                    RefreshContent()
                end)
            row1:AddWidget(displayDropdown, 1)
            card1:AddRow(row1, 40)

            yOffset = yOffset + card1:GetContentHeight() + padding

            -- Quick Preset Card
            local presetCard = GUIFrame:CreateCard(scrollChild, "Quick Preset", yOffset)
            table_insert(activeCards, presetCard)

            presetCard:AddLabel("|cff888888Apply a preset label and color. You can still customize after.|r")

            -- Detect current preset from textFormat
            local currentPreset = "_none"
            for _, p in ipairs(DISPLAY_PRESETS) do
                if p.format and selectedTrigger.textFormat == p.format then
                    currentPreset = p.key
                    break
                end
            end

            local presetRow = GUIFrame:CreateRow(presetCard.content, 40)
            local presetDropdown = GUIFrame:CreateDropdown(presetRow, "Preset", DISPLAY_PRESETS,
                currentPreset, nil,
                function(key)
                    if key == "_none" then return end
                    for _, p in ipairs(DISPLAY_PRESETS) do
                        if p.key == key and p.format then
                            selectedTrigger.textFormat = p.format
                            selectedTrigger.barText1Format = p.label
                            selectedTrigger.barColor = { p.color[1], p.color[2], p.color[3], p.color[4] or 1 }
                            -- Text mode: color the text. Bar mode: keep text white, color the bar.
                            if (selectedTrigger.displayType or "bar") == "bar" then
                                selectedTrigger.textColor = { 1, 1, 1, 1 }
                            else
                                selectedTrigger.textColor = { p.color[1], p.color[2], p.color[3], p.color[4] or 1 }
                            end
                            selectedTrigger.useBigWigsColors = false
                            ApplySettings()
                            RefreshContent()
                            break
                        end
                    end
                end)
            presetRow:AddWidget(presetDropdown, 1)
            presetCard:AddRow(presetRow, 40)

            yOffset = yOffset + presetCard:GetContentHeight() + padding

            -- Text Settings - Different for Bar vs Text mode
            if isBar then
                -- BAR MODE: Two separate text elements
                local card3 = GUIFrame:CreateCard(scrollChild, "Text 1", yOffset)
                table_insert(activeCards, card3)

                local row3a = GUIFrame:CreateRow(card3.content, 40)
                local format1Input = GUIFrame:CreateEditBox(row3a, "Format", selectedTrigger.barText1Format or "%n",
                    function(text)
                        selectedTrigger.barText1Format = text
                        ApplySettings()
                    end)
                row3a:AddWidget(format1Input, 0.5)

                local justify1Dropdown = GUIFrame:CreateDropdown(row3a, "Align", TEXT_JUSTIFY_OPTIONS,
                    selectedTrigger.barText1Justify or "LEFT", 80,
                    function(key)
                        selectedTrigger.barText1Justify = key
                        ApplySettings()
                    end)
                row3a:AddWidget(justify1Dropdown, 0.5)
                card3:AddRow(row3a, 40)

                local row3b = GUIFrame:CreateRow(card3.content, 40)
                local xOffset1Slider = GUIFrame:CreateSlider(row3b, "X Offset", -100, 100, 1,
                    selectedTrigger.barText1XOffset or 4, 50,
                    function(val)
                        selectedTrigger.barText1XOffset = val
                        ApplySettings()
                    end)
                row3b:AddWidget(xOffset1Slider, 0.5)

                local yOffset1Slider = GUIFrame:CreateSlider(row3b, "Y Offset", -20, 20, 1,
                    selectedTrigger.barText1YOffset or 0, 50,
                    function(val)
                        selectedTrigger.barText1YOffset = val
                        ApplySettings()
                    end)
                row3b:AddWidget(yOffset1Slider, 0.5)
                card3:AddRow(row3b, 40)

                yOffset = yOffset + card3:GetContentHeight() + padding

                -- Text 2
                local card3b = GUIFrame:CreateCard(scrollChild, "Text 2", yOffset)
                table_insert(activeCards, card3b)

                local row3c = GUIFrame:CreateRow(card3b.content, 40)
                local format2Input = GUIFrame:CreateEditBox(row3c, "Format", selectedTrigger.barText2Format or "%p",
                    function(text)
                        selectedTrigger.barText2Format = text
                        ApplySettings()
                    end)
                row3c:AddWidget(format2Input, 0.5)

                local justify2Dropdown = GUIFrame:CreateDropdown(row3c, "Align", TEXT_JUSTIFY_OPTIONS,
                    selectedTrigger.barText2Justify or "RIGHT", 80,
                    function(key)
                        selectedTrigger.barText2Justify = key
                        ApplySettings()
                    end)
                row3c:AddWidget(justify2Dropdown, 0.5)
                card3b:AddRow(row3c, 40)

                local row3d = GUIFrame:CreateRow(card3b.content, 40)
                local xOffset2Slider = GUIFrame:CreateSlider(row3d, "X Offset", -100, 100, 1,
                    selectedTrigger.barText2XOffset or -4, 50,
                    function(val)
                        selectedTrigger.barText2XOffset = val
                        ApplySettings()
                    end)
                row3d:AddWidget(xOffset2Slider, 0.5)

                local yOffset2Slider = GUIFrame:CreateSlider(row3d, "Y Offset", -20, 20, 1,
                    selectedTrigger.barText2YOffset or 0, 50,
                    function(val)
                        selectedTrigger.barText2YOffset = val
                        ApplySettings()
                    end)
                row3d:AddWidget(yOffset2Slider, 0.5)
                card3b:AddRow(row3d, 40)

                yOffset = yOffset + card3b:GetContentHeight() + padding

                -- Decimals option
                local card3c = GUIFrame:CreateCard(scrollChild, "Time Display", yOffset)
                table_insert(activeCards, card3c)

                local row3e = GUIFrame:CreateRow(card3c.content, 40)
                local showDecimalsCheck = GUIFrame:CreateCheckbox(row3e, "Show Decimals", selectedTrigger.showDecimals == true,
                    function(checked)
                        selectedTrigger.showDecimals = checked
                        ApplySettings()
                        RefreshContent()
                    end)
                row3e:AddWidget(showDecimalsCheck, selectedTrigger.showDecimals and 0.5 or 1)

                if selectedTrigger.showDecimals then
                    local decimalThresholdSlider = GUIFrame:CreateSlider(row3e, "Below (seconds)", 1, 30, 1,
                        selectedTrigger.decimalThreshold or 3, 50,
                        function(val)
                            selectedTrigger.decimalThreshold = val
                            ApplySettings()
                        end)
                    row3e:AddWidget(decimalThresholdSlider, 0.5)
                end
                card3c:AddRow(row3e, 40)

                yOffset = yOffset + card3c:GetContentHeight() + padding
            else
                -- TEXT MODE: Single format with %i support
                local card3 = GUIFrame:CreateCard(scrollChild, "Text Format", yOffset)
                table_insert(activeCards, card3)

                local row3 = GUIFrame:CreateRow(card3.content, 40)
                local formatInput = GUIFrame:CreateEditBox(row3, "Format String", selectedTrigger.textFormat or "%i %n %p",
                    function(text)
                        selectedTrigger.textFormat = text
                        ApplySettings()
                        RefreshContent() -- Refresh to show/hide Custom Text Function card based on %c
                    end)
                row3:AddWidget(formatInput, 1)
                card3:AddRow(row3, 40)

                local row3c = GUIFrame:CreateRow(card3.content, 40)
                local showDecimalsCheck = GUIFrame:CreateCheckbox(row3c, "Show Decimals", selectedTrigger.showDecimals == true,
                    function(checked)
                        selectedTrigger.showDecimals = checked
                        ApplySettings()
                        RefreshContent()
                    end)
                row3c:AddWidget(showDecimalsCheck, selectedTrigger.showDecimals and 0.5 or 1)

                if selectedTrigger.showDecimals then
                    local decimalThresholdSlider = GUIFrame:CreateSlider(row3c, "Below (seconds)", 1, 30, 1,
                        selectedTrigger.decimalThreshold or 3, 50,
                        function(val)
                            selectedTrigger.decimalThreshold = val
                            ApplySettings()
                        end)
                    row3c:AddWidget(decimalThresholdSlider, 0.5)
                end
                card3:AddRow(row3c, 40)

                yOffset = yOffset + card3:GetContentHeight() + padding
            end

            -- Colors Card
            local card4 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
            table_insert(activeCards, card4)

            if isBar then
                -- Bar mode: BigWigs colors option + bar/bg/text colors
                local row4 = GUIFrame:CreateRow(card4.content, 36)
                local bwColorCheck = GUIFrame:CreateCheckbox(row4, "Use BigWigs Colors", selectedTrigger.useBigWigsColors ~= false,
                    function(checked)
                        selectedTrigger.useBigWigsColors = checked
                        ApplySettings()
                        RefreshContent()
                    end)
                row4:AddWidget(bwColorCheck, 1)
                card4:AddRow(row4, 36)

                if not selectedTrigger.useBigWigsColors then
                    local row5 = GUIFrame:CreateRow(card4.content, 36)
                    local barColorPicker = GUIFrame:CreateColorPicker(row5, "Bar",
                        selectedTrigger.barColor or { 0.2, 0.6, 1.0, 1 },
                        function(r, g, b, a)
                            selectedTrigger.barColor = { r, g, b, a }
                            ApplySettings()
                        end)
                    row5:AddWidget(barColorPicker, 0.5)

                    local bgColorPicker = GUIFrame:CreateColorPicker(row5, "Background",
                        selectedTrigger.backgroundColor or { 0.1, 0.1, 0.1, 0.8 },
                        function(r, g, b, a)
                            selectedTrigger.backgroundColor = { r, g, b, a }
                            ApplySettings()
                        end)
                    row5:AddWidget(bgColorPicker, 0.5)
                    card4:AddRow(row5, 36)

                    local row6 = GUIFrame:CreateRow(card4.content, 36)
                    local textColorPicker = GUIFrame:CreateColorPicker(row6, "Text",
                        selectedTrigger.textColor or { 1, 1, 1, 1 },
                        function(r, g, b, a)
                            selectedTrigger.textColor = { r, g, b, a }
                            ApplySettings()
                        end)
                    row6:AddWidget(textColorPicker, 1)
                    card4:AddRow(row6, 36)
                end
            else
                -- Text mode: only text color
                local row4 = GUIFrame:CreateRow(card4.content, 36)
                local textColorPicker = GUIFrame:CreateColorPicker(row4, "Text Color",
                    selectedTrigger.textColor or { 1, 1, 1, 1 },
                    function(r, g, b, a)
                        selectedTrigger.textColor = { r, g, b, a }
                        ApplySettings()
                    end)
                row4:AddWidget(textColorPicker, 1)
                card4:AddRow(row4, 36)
            end

            yOffset = yOffset + card4:GetContentHeight() + padding

            -- Custom Text Function Card (only shown if %c is used in format string)
            local textFormat = selectedTrigger.textFormat or ""
            if string.find(textFormat, "%%c") then
                local card5 = GUIFrame:CreateCard(scrollChild, "Custom Text Function", yOffset)
                table_insert(activeCards, card5)

                -- Help text showing function signature
                local helpRow = GUIFrame:CreateRow(card5.content, 28)
                local helpText = helpRow:CreateFontString(nil, "OVERLAY")
                helpText:SetPoint("LEFT", helpRow, "LEFT", 4, 0)
                KE:ApplyThemeFont(helpText, "small")
                helpText:SetText("function(expirationTime, duration, remaining, name, icon, stacks)")
                helpText:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 0.8)
                card5:AddRow(helpRow, 28)

                -- Multi-line code editor
                local codeRow = GUIFrame:CreateRow(card5.content, 134)
                local codeEditor = GUIFrame:CreateMultiLineEditBox(codeRow, {
                    label = "Lua Code (returns value for %c placeholder)",
                    value = selectedTrigger.customText or "",
                    height = 120,
                    syntaxHighlight = true,
                    onTextChanged = function(text)
                        selectedTrigger.customText = text
                        ApplySettings()
                    end,
                })
                codeRow:AddWidget(codeEditor, 1)
                card5:AddRow(codeRow, 134)

                -- Error display + Test button row
                local testRow = GUIFrame:CreateRow(card5.content, 28)

                -- Error/status label
                local errorLabel = testRow:CreateFontString(nil, "OVERLAY")
                errorLabel:SetPoint("LEFT", testRow, "LEFT", 4, 0)
                KE:ApplyThemeFont(errorLabel, "small")
                errorLabel:SetText("")

                -- Validation helper
                local function ValidateCustomText(luaCode)
                    if not luaCode or luaCode == "" then
                        return true
                    end

                    local func, err = loadstring("return " .. luaCode)
                    if not func then
                        -- Clean up error message
                        local cleanErr = err and err:gsub('%[string ".-"%]:', '') or "Syntax error"
                        return false, cleanErr
                    end

                    local ok, result = pcall(func)
                    if not ok then
                        return false, result
                    end
                    if type(result) ~= "function" then
                        return false, "Must be a function"
                    end

                    return true
                end

                -- Test button (using config table format)
                local testBtn = GUIFrame:CreateButton(testRow, "Test", {
                    width = 60,
                    callback = function()
                        local code = codeEditor:GetValue()
                        local valid, errMsg = ValidateCustomText(code)
                        if valid then
                            if code == "" then
                                errorLabel:SetText("")
                            else
                                errorLabel:SetText("Valid!")
                                errorLabel:SetTextColor(0.2, 0.8, 0.2, 1)
                            end
                        else
                            errorLabel:SetText(errMsg or "Invalid")
                            errorLabel:SetTextColor(0.9, 0.2, 0.2, 1)
                        end
                    end,
                })
                testBtn:SetPoint("RIGHT", testRow, "RIGHT", 0, 0)
                card5:AddRow(testRow, 28)

                yOffset = yOffset + card5:GetContentHeight() + padding
            end

            return yOffset
        end

        local function RenderLoadTab(yOffset)
            if not selectedTrigger then
                local card = GUIFrame:CreateCard(scrollChild, "No Timer Selected", yOffset)
                card:AddLabel("Click + to create a new timer, or select one from the list on the left.")
                table_insert(activeCards, card)
                return yOffset + card:GetContentHeight() + (Theme.paddingSmall or 8)
            end

            local padding = Theme.paddingSmall or 8

            -- Role Load Conditions Card
            local card1 = GUIFrame:CreateCard(scrollChild, "Role", yOffset)
            table_insert(activeCards, card1)

            -- Enable/Disable role filtering (height 40 if more rows follow, 36 if last)
            local row1Height = selectedTrigger.loadRoleEnabled and 40 or 36
            local row1 = GUIFrame:CreateRow(card1.content, row1Height)
            local roleToggle = GUIFrame:CreateCheckbox(row1, "Filter by Role", selectedTrigger.loadRoleEnabled or false,
                function(checked)
                    selectedTrigger.loadRoleEnabled = checked
                    ApplySettings()
                    RefreshContent()
                end)
            row1:AddWidget(roleToggle, 1)
            card1:AddRow(row1, row1Height)

            -- Role checkboxes (only show if role filtering is enabled)
            if selectedTrigger.loadRoleEnabled then
                card1:AddSeparator()

                -- Tank row
                local row2 = GUIFrame:CreateRow(card1.content, 40)
                local tankCheck = GUIFrame:CreateCheckbox(row2, "Tank", selectedTrigger.loadRoleTank ~= false,
                    function(checked)
                        selectedTrigger.loadRoleTank = checked
                        ApplySettings()
                    end)
                row2:AddWidget(tankCheck, 1)
                card1:AddRow(row2, 40)

                -- Healer row
                local row3 = GUIFrame:CreateRow(card1.content, 40)
                local healerCheck = GUIFrame:CreateCheckbox(row3, "Healer", selectedTrigger.loadRoleHealer ~= false,
                    function(checked)
                        selectedTrigger.loadRoleHealer = checked
                        ApplySettings()
                    end)
                row3:AddWidget(healerCheck, 1)
                card1:AddRow(row3, 40)

                -- DPS row (last row, height 36)
                local row4 = GUIFrame:CreateRow(card1.content, 36)
                local dpsCheck = GUIFrame:CreateCheckbox(row4, "DPS", selectedTrigger.loadRoleDPS ~= false,
                    function(checked)
                        selectedTrigger.loadRoleDPS = checked
                        ApplySettings()
                    end)
                row4:AddWidget(dpsCheck, 1)
                card1:AddRow(row4, 36)
            end

            yOffset = yOffset + card1:GetContentHeight() + padding

            return yOffset
        end

        local function RenderActionsTab(yOffset)
            if not selectedTrigger then
                local card = GUIFrame:CreateCard(scrollChild, "No Timer Selected", yOffset)
                card:AddLabel("Click + to create a new timer, or select one from the list on the left.")
                table_insert(activeCards, card)
                return yOffset + card:GetContentHeight() + (Theme.paddingSmall or 8)
            end

            local padding = Theme.paddingSmall or 8
            local LSM = KE.LSM

            -- Build sound list from LibSharedMedia
            local soundList = { ["None"] = "None" }
            if LSM then
                for name in pairs(LSM:HashTable("sound")) do
                    soundList[name] = name
                end
            end

            -- Sound Actions Card
            local card1 = GUIFrame:CreateCard(scrollChild, "Sound", yOffset)
            table_insert(activeCards, card1)

            -- On Show Sound
            local row1 = GUIFrame:CreateRow(card1.content, 40)
            local onShowDropdown = GUIFrame:CreateDropdown(row1, "On Show", soundList,
                selectedTrigger.actionOnShowSound or "None", 100,
                function(key)
                    selectedTrigger.actionOnShowSound = key
                    ApplySettings()
                end)
            row1:AddWidget(onShowDropdown, 0.7)

            local testShowBtn = GUIFrame:CreateButton(row1, "Test", {
                width = 60,
                height = 24,
                callback = function()
                    local soundName = selectedTrigger.actionOnShowSound
                    if soundName and soundName ~= "None" and LSM then
                        local file = LSM:Fetch("sound", soundName)
                        if file then PlaySoundFile(file, "Master") end
                    end
                end,
            })
            row1:AddWidget(testShowBtn, 0.3, nil, 0, -14)
            card1:AddRow(row1, 40)

            -- On Hide Sound
            local row2 = GUIFrame:CreateRow(card1.content, 36)
            local onHideDropdown = GUIFrame:CreateDropdown(row2, "On Hide", soundList,
                selectedTrigger.actionOnHideSound or "None", 100,
                function(key)
                    selectedTrigger.actionOnHideSound = key
                    ApplySettings()
                end)
            row2:AddWidget(onHideDropdown, 0.7)

            local testHideBtn = GUIFrame:CreateButton(row2, "Test", {
                width = 60,
                height = 24,
                callback = function()
                    local soundName = selectedTrigger.actionOnHideSound
                    if soundName and soundName ~= "None" and LSM then
                        local file = LSM:Fetch("sound", soundName)
                        if file then PlaySoundFile(file, "Master") end
                    end
                end,
            })
            row2:AddWidget(testHideBtn, 0.3, nil, 0, -14)
            card1:AddRow(row2, 36)

            yOffset = yOffset + card1:GetContentHeight() + padding

            return yOffset
        end

        -- Render content
        RenderContent = function(tabId)
            -- Clear active cards tracking
            wipe(activeCards)

            -- Clear all existing children
            for _, child in ipairs({ scrollChild:GetChildren() }) do
                child:Hide()
                child:SetParent(nil)
            end

            -- Clear any regions (font strings, textures)
            for _, region in ipairs({ scrollChild:GetRegions() }) do
                if region:GetObjectType() == "FontString" or region:GetObjectType() == "Texture" then
                    region:Hide()
                end
            end

            local yOffset = Theme.paddingMedium or 12

            -- Render selected tab content
            if tabId == "trigger" then
                yOffset = RenderTriggerTab(yOffset)
            elseif tabId == "display" then
                yOffset = RenderDisplayTab(yOffset)
            elseif tabId == "load" then
                yOffset = RenderLoadTab(yOffset)
            elseif tabId == "actions" then
                yOffset = RenderActionsTab(yOffset)
            end

            -- Update scroll child height
            scrollChild:SetHeight(yOffset + (Theme.paddingLarge or 20))
        end

        -- Update tab visuals
        local function UpdateTabVisuals(buttons, selectedId)
            for _, btn in ipairs(buttons) do
                if btn.tabId == selectedId then
                    btn.label:SetTextColor((Theme.accent or {0.4,0.7,1})[1], (Theme.accent or {0.4,0.7,1})[2], (Theme.accent or {0.4,0.7,1})[3], 1)
                    btn.underline:Show()
                    btn.selectedOverlay:Show()
                else
                    btn.label:SetTextColor((Theme.textSecondary or {0.7,0.7,0.7})[1], (Theme.textSecondary or {0.7,0.7,0.7})[2], (Theme.textSecondary or {0.7,0.7,0.7})[3], 1)
                    btn.underline:Hide()
                    btn.selectedOverlay:Hide()
                end
            end
        end

        -- Create tab buttons
        local tabButtons = {}
        local minPadding = (Theme.paddingMedium or 12) * 2
        local totalTextWidth = 0

        -- First pass: create buttons and measure text
        for i, tabDef in ipairs(SUB_TABS) do
            local btn = CreateFrame("Button", nil, tabBar)
            btn:SetHeight(TAB_BAR_HEIGHT)
            btn.tabId = tabDef.id
            btn.tabIndex = i

            -- Hover background
            local hoverBg = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
            hoverBg:SetAllPoints()
            hoverBg:SetColorTexture(1, 1, 1, 0.05)
            hoverBg:Hide()
            btn.hoverBg = hoverBg

            -- Selected overlay
            local selectedOverlay = btn:CreateTexture(nil, "BACKGROUND", nil, 2)
            selectedOverlay:SetAllPoints()
            selectedOverlay:SetColorTexture((Theme.accent or {0.4,0.7,1})[1], (Theme.accent or {0.4,0.7,1})[2], (Theme.accent or {0.4,0.7,1})[3], 0.1)
            selectedOverlay:Hide()
            btn.selectedOverlay = selectedOverlay

            -- Label
            local label = btn:CreateFontString(nil, "OVERLAY")
            label:SetPoint("CENTER")
            if KE.ApplyThemeFont then
                KE:ApplyThemeFont(label, "small")
            else
                label:SetFont(KE.FONT or "Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
            end
            label:SetText(tabDef.text)
            label:SetTextColor((Theme.textSecondary or {0.7,0.7,0.7})[1], (Theme.textSecondary or {0.7,0.7,0.7})[2], (Theme.textSecondary or {0.7,0.7,0.7})[3], 1)
            btn.label = label

            -- Measure text width
            local textWidth = label:GetStringWidth()
            btn.textWidth = textWidth
            totalTextWidth = totalTextWidth + textWidth

            -- Underline (selected indicator)
            local underline = btn:CreateTexture(nil, "OVERLAY")
            underline:SetHeight(2)
            underline:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
            underline:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
            underline:SetColorTexture((Theme.accent or {0.4,0.7,1})[1], (Theme.accent or {0.4,0.7,1})[2], (Theme.accent or {0.4,0.7,1})[3], 1)
            underline:Hide()
            btn.underline = underline

            -- Mouse events
            btn:SetScript("OnEnter", function(self)
                if state.currentSubTab ~= self.tabId then
                    self.hoverBg:Show()
                    self.label:SetTextColor(1, 1, 1, 1)
                end
            end)

            btn:SetScript("OnLeave", function(self)
                self.hoverBg:Hide()
                if state.currentSubTab ~= self.tabId then
                    self.label:SetTextColor((Theme.textSecondary or {0.7,0.7,0.7})[1], (Theme.textSecondary or {0.7,0.7,0.7})[2], (Theme.textSecondary or {0.7,0.7,0.7})[3], 1)
                end
            end)

            btn:SetScript("OnClick", function(self)
                if state.currentSubTab ~= self.tabId then
                    state.currentSubTab = self.tabId
                    UpdateTabVisuals(tabButtons, state.currentSubTab)
                    RenderContent(state.currentSubTab)
                end
            end)

            table_insert(tabButtons, btn)
        end

        -- Layout tabs proportionally based on text width
        local function LayoutTabs(barWidth)
            if barWidth <= 0 then return end

            local numTabs = #tabButtons
            local totalMinWidth = totalTextWidth + (minPadding * numTabs)
            local extraSpace = math.max(0, barWidth - totalMinWidth)
            local extraPerTab = extraSpace / numTabs

            local xOffset = 0
            for _, btn in ipairs(tabButtons) do
                local tabWidth = btn.textWidth + minPadding + extraPerTab

                btn:ClearAllPoints()
                btn:SetPoint("TOP", tabBar, "TOP", 0, 0)
                btn:SetPoint("BOTTOM", tabBar, "BOTTOM", 0, 0)
                btn:SetPoint("LEFT", tabBar, "LEFT", xOffset, 0)
                btn:SetWidth(tabWidth)

                xOffset = xOffset + tabWidth
            end
        end

        -- Initial layout
        LayoutTabs(tabBar:GetWidth())

        -- Update on resize
        tabBar:SetScript("OnSizeChanged", function(self, width, height)
            LayoutTabs(width)
        end)

        -- Initial render
        UpdateTabVisuals(tabButtons, state.currentSubTab)
        RenderContent(state.currentSubTab)

        -- Start preview for this dungeon
        C_Timer.After(0.1, function()
            if panel:IsShown() then
                StartDungeonPreview(dungeonKey)
            end
        end)

        return panel
    end
end

-- Register wide panel for each dungeon (needs extra width for timer sidebar + content)
for sidebarId, info in pairs(DUNGEON_INFO) do
    GUIFrame:RegisterWidePanel(sidebarId, CreateDungeonPanel(sidebarId))
end

----------------------------------------------------------------
-- Global Settings Panel
----------------------------------------------------------------
-- Settings panel sub-tab state (persists across content rebuilds)
local settingsCurrentSubTab = "general"
local settingsCachedTabBar = nil
local settingsCachedTabButtons = nil

-- Settings sub-tab definitions
local SETTINGS_SUB_TABS = {
    { id = "general", text = "General" },
    { id = "bars",    text = "Bars" },
    { id = "texts",   text = "Texts" },
}

-- Settings tab bar height
local SETTINGS_TAB_BAR_HEIGHT = 32

-- Preview frames (persist across rebuilds)
local settingsPreviewBarFrames = {}
local settingsPreviewTextFrames = {}

-- Preview data with different colors for bars
local SETTINGS_BAR_PREVIEWS = {
    { name = "Tank Hit", time = 12.4, icon = 136116, color = { 0.2, 0.6, 1.0 } },      -- Blue
    { name = "Soak", time = 8.7, icon = 135994, color = { 1.0, 0.5, 0.0 } },           -- Orange
    { name = "Frontal", time = 5.2, icon = 132155, color = { 1.0, 0.2, 0.2 } },        -- Red
    { name = "Spread", time = 18.1, icon = 136197, color = { 0.6, 0.2, 1.0 } },        -- Purple
    { name = "Dodge", time = 3.8, icon = 132307, color = { 0.2, 1.0, 0.4 } },          -- Green
}
local SETTINGS_TEXT_PREVIEWS = {
    { name = "Adds", time = 14.3, icon = 136116, color = { 1.0, 0.5, 0.2 } },   -- Orange
    { name = "Heal", time = 6.9, icon = 135915, color = { 0.4, 0.8, 1.0 } },    -- Light Blue
    { name = "Kick", time = 2.1, icon = 132219, color = { 0.9, 0.3, 0.9 } },    -- Purple
}

-- Options tables
local SETTINGS_GROWTH_OPTIONS = {
    { key = "DOWN", text = "Down" },
    { key = "UP", text = "Up" },
}

local SETTINGS_BAR_OUTLINE_OPTIONS = {
    { key = "NONE",         text = "None" },
    { key = "OUTLINE",      text = "Outline" },
    { key = "THICKOUTLINE", text = "Thick" },
}

local SETTINGS_TEXT_OUTLINE_OPTIONS = {
    { key = "NONE",         text = "None" },
    { key = "OUTLINE",      text = "Outline" },
    { key = "THICKOUTLINE", text = "Thick" },
    { key = "SOFTOUTLINE",  text = "Soft" },
}

local SETTINGS_TEXT_ALIGN_OPTIONS = {
    { key = "LEFT",   text = "Left" },
    { key = "CENTER", text = "Center" },
    { key = "RIGHT",  text = "Right" },
}

-- Get settings database
local function GetSettingsDB()
    if not KE.db or not KE.db.profile then return nil end
    return KE.db.profile.Dungeons.DungeonTimers
end

-- Apply settings helper
local function ApplySettingsChanges()
    local mod = GetModule()
    if mod then
        if mod.Refresh then mod:Refresh() end
        if mod.ApplySettings then mod:ApplySettings() end
        if mod.RefreshPositions then mod:RefreshPositions() end
    end
end

-- Hide all preview frames (keeps them for reuse)
local function HideSettingsPreviews()
    for _, frame in pairs(settingsPreviewBarFrames) do
        frame:Hide()
    end
    for _, frame in pairs(settingsPreviewTextFrames) do
        frame:Hide()
    end
end

-- Register settings preview cleanup on GUI close
GUIFrame.onCloseCallbacks["DungeonTimers_Settings"] = HideSettingsPreviews

-- Create bar preview frame
local function CreateSettingsBarPreview(index, data)
    local db = GetSettingsDB()
    if not db then return nil end

    local barWidth = db.BarDisplay.barWidth or 200
    local barHeight = db.BarDisplay.barHeight or 20
    local fontSize = db.BarDisplay.fontSize or 12
    local fontOutline = db.BarDisplay.fontOutline or "OUTLINE"
    local barTexture = db.BarDisplay.barTexture or "KitnUI"
    local showIcon = db.BarDisplay.iconEnabled ~= false

    local actualOutline = (fontOutline == "NONE" or fontOutline == "SOFTOUTLINE") and "" or fontOutline
    local fontFace = db.BarDisplay.fontFace or "Expressway"
    local fontPath = KE:GetFontPath(fontFace) or KE.FONT or "Fonts\\FRIZQT__.TTF"
    local texturePath = KE:GetStatusbarPath(barTexture) or "Interface\\Buttons\\WHITE8x8"
    local iconSize = showIcon and barHeight or 0

    local frame = settingsPreviewBarFrames[index]
    if not frame then
        frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        frame:SetFrameStrata("HIGH")
        settingsPreviewBarFrames[index] = frame

        frame.barContainer = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        frame.bar = CreateFrame("StatusBar", nil, frame.barContainer)
        frame.bar:SetPoint("TOPLEFT", 1, -1)
        frame.bar:SetPoint("BOTTOMRIGHT", -1, 1)

        frame.iconFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        frame.iconFrame:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        frame.iconFrame:SetBackdropBorderColor(0, 0, 0, 1)
        frame.iconFrame.bg = frame.iconFrame:CreateTexture(nil, "BACKGROUND")
        frame.iconFrame.bg:SetAllPoints()
        frame.iconFrame.bg:SetColorTexture(0, 0, 0, 1)
        frame.icon = frame.iconFrame:CreateTexture(nil, "ARTWORK")
        frame.icon:SetPoint("TOPLEFT", 1, -1)
        frame.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        if KE.ApplyIconZoom then KE:ApplyIconZoom(frame.icon, 0.1) end

        frame.text1 = frame.bar:CreateFontString(nil, "OVERLAY")
        frame.text2 = frame.bar:CreateFontString(nil, "OVERLAY")
    end

    frame:SetSize(barWidth, barHeight)
    frame.iconFrame:SetSize(barHeight, barHeight)
    frame.iconFrame:ClearAllPoints()
    frame.iconFrame:SetPoint("LEFT", frame, "LEFT", 0, 0)
    frame.iconFrame:SetShown(showIcon)
    frame.icon:SetTexture(data.icon)

    frame.barContainer:ClearAllPoints()
    frame.barContainer:SetPoint("TOPLEFT", iconSize, 0)
    frame.barContainer:SetPoint("BOTTOMRIGHT", 0, 0)
    frame.barContainer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame.barContainer:SetBackdropColor(0, 0, 0, 0.8)
    frame.barContainer:SetBackdropBorderColor(0, 0, 0, 1)

    frame.bar:SetStatusBarTexture(texturePath)
    local barColor = data.color or { 0.2, 0.6, 1.0 }
    frame.bar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], 1)
    frame.bar:SetMinMaxValues(0, 20)
    frame.bar:SetValue(data.time)

    frame.text1:SetFont(fontPath, fontSize, actualOutline)
    frame.text1:ClearAllPoints()
    frame.text1:SetPoint("LEFT", frame.bar, "LEFT", 4, 0)
    frame.text1:SetPoint("RIGHT", frame.bar, "RIGHT", -40, 0)
    frame.text1:SetJustifyH("LEFT")
    frame.text1:SetTextColor(1, 1, 1, 1)
    frame.text1:SetText(data.name)

    frame.text2:SetFont(fontPath, fontSize, actualOutline)
    frame.text2:ClearAllPoints()
    frame.text2:SetPoint("LEFT", frame.bar, "LEFT", 4, 0)
    frame.text2:SetPoint("RIGHT", frame.bar, "RIGHT", -4, 0)
    frame.text2:SetJustifyH("RIGHT")
    frame.text2:SetTextColor(1, 1, 1, 1)
    frame.text2:SetText(string.format("%.1f", data.time))

    return frame
end

-- Create or reuse text preview frame
local function CreateSettingsTextPreview(index, data)
    local db = GetSettingsDB()
    if not db then return nil end

    if not db.TextDisplay then db.TextDisplay = {} end

    local fontSize = db.TextDisplay.fontSize or 14
    local fontOutline = db.TextDisplay.fontOutline or "SOFTOUTLINE"
    local textAlign = db.TextDisplay.textAlign or "LEFT"

    local useSoftOutline = fontOutline == "SOFTOUTLINE"
    local actualOutline = useSoftOutline and "" or (fontOutline == "NONE" and "" or fontOutline)
    local fontFace = db.TextDisplay.fontFace or "Expressway"
    local fontPath = KE:GetFontPath(fontFace) or KE.FONT or "Fonts\\FRIZQT__.TTF"
    local iconSize = 0
    local lineHeight = fontSize + 6
    local textWidth = 200 - iconSize - 4

    local frame = settingsPreviewTextFrames[index]
    if not frame then
        frame = CreateFrame("Frame", nil, UIParent)
        frame:SetFrameStrata("HIGH")
        settingsPreviewTextFrames[index] = frame

        frame.iconFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        frame.iconFrame:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        frame.iconFrame:SetBackdropBorderColor(0, 0, 0, 1)
        frame.iconFrame:SetShown(false)

        frame.icon = frame.iconFrame:CreateTexture(nil, "ARTWORK")
        frame.icon:SetPoint("TOPLEFT", 1, -1)
        frame.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        KE:ApplyIconZoom(frame.icon)

        frame.displayText = frame:CreateFontString(nil, "OVERLAY")
        frame.displayText:SetPoint("LEFT", frame, "LEFT", iconSize + 4, 0)
    end

    -- Update properties (runs every call, whether frame is new or reused)
    frame:SetSize(200, lineHeight)
    frame.iconFrame:SetSize(fontSize + 2, fontSize + 2)
    frame.iconFrame:ClearAllPoints()
    frame.iconFrame:SetPoint("LEFT", 0, 0)
    frame.icon:SetTexture(data.icon)

    frame.displayText:SetFont(fontPath, fontSize, actualOutline)
    frame.displayText:SetWidth(textWidth)
    frame.displayText:SetJustifyH(textAlign)
    local textColor = data.color or { 1, 1, 1 }
    frame.displayText:SetTextColor(textColor[1], textColor[2], textColor[3], 1)
    frame.displayText:SetText(string.format("%s \194\187 %.1f", data.name, data.time))

    -- Soft outline (CreateSoftOutline reuses existing internally)
    if useSoftOutline then
        local outline = KE:CreateSoftOutline(frame.displayText, {
            thickness = 1,
            color = { 0, 0, 0 },
            alpha = 0.9,
            fontPath = fontPath,
            fontSize = fontSize,
        })
        if outline and outline.shadows then
            for _, shadow in ipairs(outline.shadows) do
                shadow:SetWidth(textWidth)
                shadow:SetJustifyH(textAlign)
            end
            outline:SetShown(true)
        end
    elseif frame.displayText._keSoftOutline then
        frame.displayText._keSoftOutline:SetShown(false)
    end

    return frame
end

-- Show bar previews
local function ShowSettingsBarPreviews()
    local db = GetSettingsDB()
    if not db then return end

    local barHeight = db.BarDisplay.barHeight or 20
    local barPos = db.BarGroup.Position or {}
    local barGrowth = db.BarGroup.GrowthDirection or "DOWN"
    local barSpacing = db.BarGroup.Spacing or 2
    local barGrowUp = barGrowth == "UP"

    local barParent = KE:ResolveAnchorFrame(db.BarGroup.anchorFrameType, db.BarGroup.ParentFrame)

    for i, data in ipairs(SETTINGS_BAR_PREVIEWS) do
        local frame = CreateSettingsBarPreview(i, data)
        if frame then
            frame:ClearAllPoints()
            local offset = (i - 1) * (barHeight + barSpacing)
            if barGrowUp then
                frame:SetPoint(barPos.AnchorFrom or "CENTER", barParent, barPos.AnchorTo or "CENTER",
                    barPos.XOffset or 0, (barPos.YOffset or 100) + offset)
            else
                frame:SetPoint(barPos.AnchorFrom or "CENTER", barParent, barPos.AnchorTo or "CENTER",
                    barPos.XOffset or 0, (barPos.YOffset or 100) - offset)
            end
            frame:Show()
        end
    end
end

-- Show text previews
local function ShowSettingsTextPreviews()
    local db = GetSettingsDB()
    if not db then return end

    local fontSize = db.TextDisplay.fontSize or 14
    local textLineHeight = fontSize + 6
    local textPos = db.TextGroup.Position or {}
    local textGrowth = db.TextGroup.GrowthDirection or "DOWN"
    local textSpacing = db.TextGroup.Spacing or 2
    local textGrowUp = textGrowth == "UP"

    local textParent = KE:ResolveAnchorFrame(db.TextGroup.anchorFrameType, db.TextGroup.ParentFrame)

    for i, data in ipairs(SETTINGS_TEXT_PREVIEWS) do
        local frame = CreateSettingsTextPreview(i, data)
        if frame then
            frame:ClearAllPoints()
            local offset = (i - 1) * (textLineHeight + textSpacing)
            if textGrowUp then
                frame:SetPoint(textPos.AnchorFrom or "CENTER", textParent, textPos.AnchorTo or "CENTER",
                    textPos.XOffset or 0, (textPos.YOffset or -100) + offset)
            else
                frame:SetPoint(textPos.AnchorFrom or "CENTER", textParent, textPos.AnchorTo or "CENTER",
                    textPos.XOffset or 0, (textPos.YOffset or -100) - offset)
            end
            frame:Show()
        end
    end
end

-- Update previews based on current sub-tab
local function UpdateSettingsPreviews()
    HideSettingsPreviews()
    -- Only show previews if GUI is actually open
    if not KE.GUIOpen then return end
    if settingsCurrentSubTab == "bars" then
        ShowSettingsBarPreviews()
    else
        ShowSettingsTextPreviews()
    end
end

----------------------------------------------------------------
-- Sub-Tab: General
----------------------------------------------------------------
local function RenderGeneralTab(scrollChild, yOffset, activeCards)
    local db = GetSettingsDB()
    if not db then return yOffset end

    local Theme = KE.Theme or {}
    local DT = KitnEssentials:GetModule("DungeonTimers", true)

    -- Helper to apply module state
    local function ApplyModuleState(enabled)
        if not DT then return end
        db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("DungeonTimers")
        else
            KitnEssentials:DisableModule("DungeonTimers")
        end
    end

    ----------------------------------------------------------------
    -- Card 1: Module Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Dungeon Timers", yOffset)
    table_insert(activeCards, card1)

    local row1 = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Dungeon Timers", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            -- Refresh sidebar to update greyed-out state
            if GUIFrame.RefreshSidebar then
                GUIFrame:RefreshSidebar()
            end
            KE:CreateReloadPrompt("Enabling/Disabling this module requires a reload to take full effect.")
        end,
        true, "Dungeon Timers", "On", "Off"
    )
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, 36)
    yOffset = yOffset + card1:GetContentHeight() + (Theme.paddingSmall or 8)

    ----------------------------------------------------------------
    -- Card 2: Import / Export
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Import / Export", yOffset)
    table_insert(activeCards, card2)

    -- Description
    local bullet = KE:ColorTextByTheme("-")
    card2:AddLabel("|cff888888" .. bullet .. " Includes triggers, display overrides, and load conditions.\n" ..
        bullet .. " Bar/Text appearance (Bars/Texts tabs) is saved per-profile, not per-export.|r")

    -- Dungeon dropdown
    local scopeOptions = {
        { key = "_all", text = "All Dungeons" },
    }
    for _, info in pairs(DUNGEON_INFO) do
        table_insert(scopeOptions, { key = info.key, text = info.name })
    end
    table.sort(scopeOptions, function(a, b)
        if a.key == "_all" then return true end
        if b.key == "_all" then return false end
        return a.text < b.text
    end)

    local selectedScope = "_all"

    local scopeRow = GUIFrame:CreateRow(card2.content, 28)
    local scopeDropdown = GUIFrame:CreateDropdown(scopeRow, "Dungeon", scopeOptions, selectedScope, nil,
        function(key) selectedScope = key end)
    scopeRow:AddWidget(scopeDropdown, 1)
    card2:AddRow(scopeRow, 28)
    card2:AddSeparator()

    -- Edit box
    local editBoxRow = GUIFrame:CreateRow(card2.content, 50)
    local importExportBox = GUIFrame:CreateEditBox(editBoxRow, "Paste import string or click Export...", "", function() end)
    editBoxRow:AddWidget(importExportBox, 1)
    card2:AddRow(editBoxRow, 50)

    -- Export / Import buttons
    local buttonRow = GUIFrame:CreateRow(card2.content, 28)

    local exportBtn = GUIFrame:CreateButton(buttonRow, "Export", { callback = function()
        local DT_mod = KitnEssentials:GetModule("DungeonTimers", true)
        if not DT_mod then return end
        local dungeonKey = selectedScope ~= "_all" and selectedScope or nil
        local result, err = DT_mod:ExportTriggers(dungeonKey)
        if result then
            KE:CreatePrompt(
                "Export Timers",
                result,
                true,
                "Copy the string above (Ctrl+C)",
                false
            )
        else
            KE:Print("Export failed: " .. (err or "unknown error"))
        end
    end })
    buttonRow:AddWidget(exportBtn, 0.5)

    local importBtn = GUIFrame:CreateButton(buttonRow, "Import", { callback = function()
        local DT_mod = KitnEssentials:GetModule("DungeonTimers", true)
        if not DT_mod then return end
        local text = (importExportBox.GetValue and importExportBox:GetValue()) or ""
        if text == "" then
            KE:Print("Paste an import string first.")
            return
        end
        local ok, msg = DT_mod:ImportTriggers(text)
        if ok then
            KE:Print(msg)
            importExportBox:SetValue("")
        else
            KE:Print("Import failed: " .. (msg or "unknown error"))
        end
    end })
    buttonRow:AddWidget(importBtn, 0.5)
    card2:AddRow(buttonRow, 28)
    card2:AddLabel("|cff888888" .. bullet .. " Importing adds to your existing timers — use Reset below to start fresh.|r")

    yOffset = yOffset + card2:GetContentHeight() + (Theme.paddingSmall or 8)

    ----------------------------------------------------------------
    -- Card 3: Reset
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Reset", yOffset)
    table_insert(activeCards, card3)

    card3:AddLabel("|cff888888Remove all timer configurations across every dungeon. This cannot be undone.|r")

    local resetRow = GUIFrame:CreateRow(card3.content, 28)
    local resetBtn = GUIFrame:CreateButton(resetRow, "Reset All Triggers", { callback = function()
        KE:CreatePrompt(
            "Reset All Triggers",
            "This will permanently remove all timer configurations for every dungeon.\n\nAre you sure?",
            false, nil, false, nil, nil, nil, nil,
            function()
                local dtDb = GetSettingsDB()
                if dtDb and dtDb.Dungeons then
                    for _, dungeon in pairs(dtDb.Dungeons) do
                        if dungeon.Triggers then
                            wipe(dungeon.Triggers)
                        end
                    end
                end
                KE:Print("All triggers have been reset.")
            end,
            nil, "Reset", "Cancel"
        )
    end })
    if resetBtn.text then resetBtn.text:SetTextColor(0.9, 0.2, 0.2, 1) end
    resetRow:AddWidget(resetBtn, 1)
    card3:AddRow(resetRow, 28)

    yOffset = yOffset + card3:GetContentHeight() + (Theme.paddingSmall or 8)

    return yOffset
end

----------------------------------------------------------------
-- Sub-Tab: Bars
----------------------------------------------------------------
local function RenderBarsTab(scrollChild, yOffset, activeCards)
    local db = GetSettingsDB()
    if not db then return yOffset end

    local Theme = KE.Theme or {}
    local padding = Theme.paddingSmall or 8

    -- Build texture options from LSM
    local TEXTURE_OPTIONS = {}
    local LSM = KE.LSM
    if LSM then
        local textures = LSM:List("statusbar")
        for _, name in ipairs(textures) do
            table_insert(TEXTURE_OPTIONS, { key = name, text = name })
        end
    else
        TEXTURE_OPTIONS = {{ key = "KitnUI", text = "KitnUI" }}
    end

    -- Build font list from LSM
    local fontList = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do
            fontList[name] = name
        end
    else
        fontList["Expressway"] = "Expressway"
    end

    local function ApplyAndUpdate()
        ApplySettingsChanges()
        UpdateSettingsPreviews()
    end

    ----------------------------------------------------------------
    -- Card 1: Bar Display Settings
    ----------------------------------------------------------------
    local displayCard = GUIFrame:CreateCard(scrollChild, "Bar Display Settings", yOffset)
    table_insert(activeCards, displayCard)

    -- Row 1: Bar Width + Bar Height
    local row1 = GUIFrame:CreateRow(displayCard.content, 40)
    local widthSlider = GUIFrame:CreateSlider(row1, "Bar Width", 100, 400, 1,
        db.BarDisplay.barWidth or 200, 60,
        function(val)
            db.BarDisplay.barWidth = val
            ApplyAndUpdate()
        end)
    row1:AddWidget(widthSlider, 0.5)

    local heightSlider = GUIFrame:CreateSlider(row1, "Bar Height", 12, 40, 1,
        db.BarDisplay.barHeight or 20, 60,
        function(val)
            db.BarDisplay.barHeight = val
            ApplyAndUpdate()
        end)
    row1:AddWidget(heightSlider, 0.5)
    displayCard:AddRow(row1, 40)

    -- Row 2: Font + Font Size
    local row2 = GUIFrame:CreateRow(displayCard.content, 40)
    local fontDropdown = GUIFrame:CreateDropdown(row2, "Font", fontList,
        db.BarDisplay.fontFace or "Expressway", 60,
        function(key)
            db.BarDisplay.fontFace = key
            ApplyAndUpdate()
        end, true)
    row2:AddWidget(fontDropdown, 0.5)

    local fontSizeSlider = GUIFrame:CreateSlider(row2, "Font Size", 8, 24, 1,
        db.BarDisplay.fontSize or 12, 60,
        function(val)
            db.BarDisplay.fontSize = val
            ApplyAndUpdate()
        end)
    row2:AddWidget(fontSizeSlider, 0.5)
    displayCard:AddRow(row2, 40)

    -- Row 3: Font Outline + Bar Texture
    local row3 = GUIFrame:CreateRow(displayCard.content, 40)
    local outlineDropdown = GUIFrame:CreateDropdown(row3, "Font Outline", SETTINGS_BAR_OUTLINE_OPTIONS,
        db.BarDisplay.fontOutline or "OUTLINE", 80,
        function(key)
            db.BarDisplay.fontOutline = key
            ApplyAndUpdate()
        end)
    row3:AddWidget(outlineDropdown, 0.5)

    local textureDropdown = GUIFrame:CreateDropdown(row3, "Bar Texture", TEXTURE_OPTIONS,
        db.BarDisplay.barTexture or "KitnUI", 120,
        function(key)
            db.BarDisplay.barTexture = key
            ApplyAndUpdate()
        end)
    row3:AddWidget(textureDropdown, 0.5)
    displayCard:AddRow(row3, 40)

    -- Row 4: Show Icon (last row)
    local row4 = GUIFrame:CreateRow(displayCard.content, 36)
    local iconCheck = GUIFrame:CreateCheckbox(row4, "Show Icon", db.BarDisplay.iconEnabled ~= false,
        function(checked)
            db.BarDisplay.iconEnabled = checked
            ApplyAndUpdate()
        end)
    row4:AddWidget(iconCheck, 1)
    displayCard:AddRow(row4, 36)

    yOffset = yOffset + displayCard:GetContentHeight() + padding

    ----------------------------------------------------------------
    -- Card 2: Bar Group Settings
    ----------------------------------------------------------------
    local barGroupCard = GUIFrame:CreateCard(scrollChild, "Bar Group", yOffset)
    table_insert(activeCards, barGroupCard)

    local barRow1 = GUIFrame:CreateRow(barGroupCard.content, 40)
    local barGrowthDropdown = GUIFrame:CreateDropdown(barRow1, "Growth Direction", SETTINGS_GROWTH_OPTIONS,
        db.BarGroup.GrowthDirection or "DOWN", 100,
        function(key)
            db.BarGroup.GrowthDirection = key
            ApplyAndUpdate()
        end)
    barRow1:AddWidget(barGrowthDropdown, 0.5)

    local barSpacingSlider = GUIFrame:CreateSlider(barRow1, "Spacing", 0, 20, 1,
        db.BarGroup.Spacing or 2, 50,
        function(val)
            db.BarGroup.Spacing = val
            ApplyAndUpdate()
        end)
    barRow1:AddWidget(barSpacingSlider, 0.5)
    barGroupCard:AddRow(barRow1, 40)

    yOffset = yOffset + barGroupCard:GetContentHeight() + padding

    ----------------------------------------------------------------
    -- Card 3: Bar Group Position
    ----------------------------------------------------------------
    local barPosCard, barPosYOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Bar Group Position",
        db = db.BarGroup,
        dbKeys = {
            xOffset = "XOffset",
            yOffset = "YOffset",
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
        },
        showAnchorFrameType = true,
        showStrata = true,
        sliderRange = { -800, 800 },
        onChangeCallback = ApplyAndUpdate,
    })
    table_insert(activeCards, barPosCard)
    yOffset = barPosYOffset

    return yOffset
end

----------------------------------------------------------------
-- Sub-Tab: Texts
----------------------------------------------------------------
local function RenderTextsTab(scrollChild, yOffset, activeCards)
    local db = GetSettingsDB()
    if not db then return yOffset end

    -- Ensure TextDisplay exists
    if not db.TextDisplay then db.TextDisplay = {} end

    local Theme = KE.Theme or {}
    local padding = Theme.paddingSmall or 8

    local function ApplyAndUpdate()
        ApplySettingsChanges()
        UpdateSettingsPreviews()
    end

    ----------------------------------------------------------------
    -- Card 1: Text Display Settings
    ----------------------------------------------------------------
    local displayCard = GUIFrame:CreateCard(scrollChild, "Text Display Settings", yOffset)
    table_insert(activeCards, displayCard)

    -- Build font list from LSM
    local fontList = {}
    local LSM = KE.LSM
    if LSM then
        for name in pairs(LSM:HashTable("font")) do
            fontList[name] = name
        end
    else
        fontList["Expressway"] = "Expressway"
    end

    -- Row 1: Font + Font Size
    local row1 = GUIFrame:CreateRow(displayCard.content, 40)
    local fontDropdown = GUIFrame:CreateDropdown(row1, "Font", fontList,
        db.TextDisplay.fontFace or "Expressway", 60,
        function(key)
            db.TextDisplay.fontFace = key
            ApplyAndUpdate()
        end, true)
    row1:AddWidget(fontDropdown, 0.5)

    local fontSizeSlider = GUIFrame:CreateSlider(row1, "Font Size", 8, 32, 1,
        db.TextDisplay.fontSize or 14, 60,
        function(val)
            db.TextDisplay.fontSize = val
            ApplyAndUpdate()
        end)
    row1:AddWidget(fontSizeSlider, 0.5)
    displayCard:AddRow(row1, 40)

    -- Row 2: Font Outline + Text Align
    local row2 = GUIFrame:CreateRow(displayCard.content, 36)
    local outlineDropdown = GUIFrame:CreateDropdown(row2, "Font Outline", SETTINGS_TEXT_OUTLINE_OPTIONS,
        db.TextDisplay.fontOutline or "SOFTOUTLINE", 80,
        function(key)
            db.TextDisplay.fontOutline = key
            ApplyAndUpdate()
        end)
    row2:AddWidget(outlineDropdown, 0.5)

    local alignDropdown = GUIFrame:CreateDropdown(row2, "Text Align", SETTINGS_TEXT_ALIGN_OPTIONS,
        db.TextDisplay.textAlign or "LEFT", 80,
        function(key)
            local freshDb = GetSettingsDB()
            if freshDb and freshDb.TextDisplay then
                freshDb.TextDisplay.textAlign = key
            end
            ApplyAndUpdate()
        end)
    row2:AddWidget(alignDropdown, 0.5)
    displayCard:AddRow(row2, 36)

    yOffset = yOffset + displayCard:GetContentHeight() + padding

    ----------------------------------------------------------------
    -- Card 2: Text Group Settings
    ----------------------------------------------------------------
    local textGroupCard = GUIFrame:CreateCard(scrollChild, "Text Group", yOffset)
    table_insert(activeCards, textGroupCard)

    local textRow1 = GUIFrame:CreateRow(textGroupCard.content, 40)
    local textGrowthDropdown = GUIFrame:CreateDropdown(textRow1, "Growth Direction", SETTINGS_GROWTH_OPTIONS,
        db.TextGroup.GrowthDirection or "DOWN", 100,
        function(key)
            db.TextGroup.GrowthDirection = key
            ApplyAndUpdate()
        end)
    textRow1:AddWidget(textGrowthDropdown, 0.5)

    local textSpacingSlider = GUIFrame:CreateSlider(textRow1, "Spacing", 0, 20, 1,
        db.TextGroup.Spacing or 2, 50,
        function(val)
            db.TextGroup.Spacing = val
            ApplyAndUpdate()
        end)
    textRow1:AddWidget(textSpacingSlider, 0.5)
    textGroupCard:AddRow(textRow1, 40)

    yOffset = yOffset + textGroupCard:GetContentHeight() + padding

    ----------------------------------------------------------------
    -- Card 3: Text Group Position
    ----------------------------------------------------------------
    local textPosCard, textPosYOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Text Group Position",
        db = db.TextGroup,
        dbKeys = {
            xOffset = "XOffset",
            yOffset = "YOffset",
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
        },
        showAnchorFrameType = true,
        showStrata = true,
        sliderRange = { -800, 800 },
        onChangeCallback = ApplyAndUpdate,
    })
    table_insert(activeCards, textPosCard)
    yOffset = textPosYOffset

    return yOffset
end

----------------------------------------------------------------
-- Create Settings Panel (with secondary tab bar)
----------------------------------------------------------------
local function CreateSettingsPanel(container)
    local db = GetSettingsDB()
    if not db then return nil end

    -- Ensure global settings exist
    if not db.BarDisplay then db.BarDisplay = {} end
    if not db.TextDisplay then db.TextDisplay = {} end
    if not db.BarGroup then db.BarGroup = {} end
    if not db.TextGroup then db.TextGroup = {} end
    if not db.BarGroup.Position then
        db.BarGroup.Position = { AnchorFrom = "CENTER", AnchorTo = "CENTER", XOffset = 0, YOffset = 100 }
    end
    if not db.TextGroup.Position then
        db.TextGroup.Position = { AnchorFrom = "CENTER", AnchorTo = "CENTER", XOffset = 0, YOffset = -100 }
    end

    local Theme = KE.Theme or {}

    -- Full-size frame to take over content area
    local panel = CreateFrame("Frame", nil, container)
    panel:SetAllPoints()

    -- Tab bar at top
    local tabBar = CreateFrame("Frame", nil, panel)
    tabBar:SetHeight(SETTINGS_TAB_BAR_HEIGHT)
    tabBar:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    tabBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)

    -- Tab bar background
    local tabBarBg = tabBar:CreateTexture(nil, "BACKGROUND")
    tabBarBg:SetAllPoints()
    tabBarBg:SetColorTexture(Theme.bgMedium[1], Theme.bgMedium[2], Theme.bgMedium[3], 1)

    -- Tab bar bottom border
    local tabBarBorder = tabBar:CreateTexture(nil, "ARTWORK")
    tabBarBorder:SetHeight(1)
    tabBarBorder:SetPoint("BOTTOMLEFT", tabBar, "BOTTOMLEFT", 0, 0)
    tabBarBorder:SetPoint("BOTTOMRIGHT", tabBar, "BOTTOMRIGHT", 0, 0)
    tabBarBorder:SetColorTexture(Theme.border[1], Theme.border[2], Theme.border[3], 1)

    -- Cache tab bar
    settingsCachedTabBar = tabBar

    -- Scroll frame below tab bar
    local scrollbarWidth = Theme.scrollbarWidth or 16
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -1)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)

    -- Style scrollbar
    if scrollFrame.ScrollBar then
        local sb = scrollFrame.ScrollBar
        sb:ClearAllPoints()
        sb:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -3, -(SETTINGS_TAB_BAR_HEIGHT + Theme.paddingSmall + 13))
        sb:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -3, Theme.paddingSmall + 13)
        sb:SetWidth(scrollbarWidth - 4)

        if sb.Background then sb.Background:Hide() end
        if sb.Top then sb.Top:Hide() end
        if sb.Middle then sb.Middle:Hide() end
        if sb.Bottom then sb.Bottom:Hide() end
        if sb.trackBG then sb.trackBG:Hide() end
        if sb.ScrollUpButton then sb.ScrollUpButton:Hide() end
        if sb.ScrollDownButton then sb.ScrollDownButton:Hide() end
        sb:SetAlpha(0)

        local isSnapping = false
        local PIXEL_STEP = 8 / 15
        sb:HookScript("OnValueChanged", function(self, value)
            if isSnapping then return end
            local scale = scrollFrame:GetEffectiveScale()
            local screenPixels = value * scale
            local snappedPixels = math.floor(screenPixels / PIXEL_STEP + 0.5) * PIXEL_STEP
            local snappedValue = snappedPixels / scale
            if math.abs(value - snappedValue) > 0.001 then
                isSnapping = true
                self:SetValue(snappedValue)
                isSnapping = false
            end
        end)
    end

    -- Scroll child
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    local scrollbarVisible = false
    local baseWidth = Theme.contentWidth

    local function UpdateScrollChildWidth()
        if scrollbarVisible then
            scrollChild:SetWidth(baseWidth - scrollbarWidth)
        else
            scrollChild:SetWidth(baseWidth)
        end
    end

    local function UpdateScrollBarVisibility()
        if scrollFrame.ScrollBar then
            local contentHeight = scrollChild:GetHeight()
            local frameHeight = scrollFrame:GetHeight()
            local needsScrollbar = contentHeight > frameHeight
            scrollbarVisible = needsScrollbar
            scrollFrame.ScrollBar:SetAlpha(needsScrollbar and 1 or 0)
            UpdateScrollChildWidth()
        end
    end

    UpdateScrollChildWidth()

    scrollFrame:HookScript("OnScrollRangeChanged", UpdateScrollBarVisibility)
    scrollChild:HookScript("OnSizeChanged", UpdateScrollBarVisibility)
    scrollFrame:HookScript("OnSizeChanged", UpdateScrollBarVisibility)

    scrollFrame:HookScript("OnShow", function()
        C_Timer.After(0, UpdateScrollBarVisibility)
    end)

    local activeCards = {}

    local function UpdateCardWidths()
        local newWidth = scrollChild:GetWidth()
        for _, card in ipairs(activeCards) do
            if card and card.SetWidth then
                card:SetWidth(newWidth)
            end
        end
    end

    scrollChild:HookScript("OnSizeChanged", function(self, width, height)
        UpdateCardWidths()
    end)

    -- Render content into scroll child
    local function RenderContentIntoScrollChild(tabId)
        wipe(activeCards)

        for _, child in ipairs({ scrollChild:GetChildren() }) do
            child:Hide()
            child:SetParent(nil)
        end

        for _, region in ipairs({ scrollChild:GetRegions() }) do
            if region:GetObjectType() == "FontString" or region:GetObjectType() == "Texture" then
                region:Hide()
            end
        end

        local yOffset = Theme.paddingMedium

        if tabId == "general" then
            yOffset = RenderGeneralTab(scrollChild, yOffset, activeCards)
        elseif tabId == "bars" then
            yOffset = RenderBarsTab(scrollChild, yOffset, activeCards)
        elseif tabId == "texts" then
            yOffset = RenderTextsTab(scrollChild, yOffset, activeCards)
        end

        scrollChild:SetHeight(yOffset + Theme.paddingLarge)

        -- Update previews after rendering
        UpdateSettingsPreviews()
    end

    -- Helper to update tab button visuals
    local function UpdateTabVisuals(buttons, selectedId)
        for _, btn in ipairs(buttons) do
            if btn.tabId == selectedId then
                btn.label:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
                btn.underline:Show()
                btn.selectedOverlay:Show()
            else
                btn.label:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
                btn.underline:Hide()
                btn.selectedOverlay:Hide()
            end
        end
    end

    -- Create tab buttons
    local tabButtons = {}
    local minPadding = Theme.paddingMedium * 2
    local totalTextWidth = 0

    for i, tabDef in ipairs(SETTINGS_SUB_TABS) do
        local btn = CreateFrame("Button", nil, tabBar)
        btn:SetHeight(SETTINGS_TAB_BAR_HEIGHT)
        btn.tabId = tabDef.id
        btn.tabIndex = i

        local hoverBg = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
        hoverBg:SetAllPoints()
        hoverBg:SetColorTexture(1, 1, 1, 0.05)
        hoverBg:Hide()
        btn.hoverBg = hoverBg

        local selectedOverlay = btn:CreateTexture(nil, "BACKGROUND", nil, 2)
        selectedOverlay:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
        selectedOverlay:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
        selectedOverlay:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.1)
        selectedOverlay:Hide()
        btn.selectedOverlay = selectedOverlay

        local label = btn:CreateFontString(nil, "OVERLAY")
        label:SetPoint("CENTER", btn, "CENTER", 0, 0)
        if KE.ApplyThemeFont then
            KE:ApplyThemeFont(label, "small")
        else
            label:SetFontObject("GameFontNormalSmall")
        end
        label:SetText(tabDef.text)
        label:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
        btn.label = label

        local textWidth = label:GetStringWidth()
        btn.textWidth = textWidth
        totalTextWidth = totalTextWidth + textWidth

        local underline = btn:CreateTexture(nil, "OVERLAY")
        underline:SetHeight(2)
        underline:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
        underline:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
        underline:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
        underline:Hide()
        btn.underline = underline

        btn:SetScript("OnEnter", function(self)
            if settingsCurrentSubTab ~= self.tabId then
                self.hoverBg:Show()
            end
        end)

        btn:SetScript("OnLeave", function(self)
            self.hoverBg:Hide()
        end)

        btn:SetScript("OnClick", function(self)
            if settingsCurrentSubTab ~= self.tabId then
                settingsCurrentSubTab = self.tabId
                UpdateTabVisuals(settingsCachedTabButtons, settingsCurrentSubTab)
                RenderContentIntoScrollChild(settingsCurrentSubTab)
            end
        end)

        table_insert(tabButtons, btn)
    end

    settingsCachedTabButtons = tabButtons

    local function LayoutTabs(barWidth)
        if barWidth <= 0 then return end

        local numTabs = #tabButtons
        local totalMinWidth = totalTextWidth + (minPadding * numTabs)
        local extraSpace = math.max(0, barWidth - totalMinWidth)
        local extraPerTab = extraSpace / numTabs

        local xOffset = 0
        for _, btn in ipairs(tabButtons) do
            local tabWidth = btn.textWidth + minPadding + extraPerTab

            btn:ClearAllPoints()
            btn:SetPoint("TOP", tabBar, "TOP", 0, 0)
            btn:SetPoint("BOTTOM", tabBar, "BOTTOM", 0, 0)
            btn:SetPoint("LEFT", tabBar, "LEFT", xOffset, 0)
            btn:SetWidth(tabWidth)

            xOffset = xOffset + tabWidth
        end
    end

    LayoutTabs(tabBar:GetWidth())

    tabBar:SetScript("OnSizeChanged", function(self, width, height)
        LayoutTabs(width)
    end)

    UpdateTabVisuals(tabButtons, settingsCurrentSubTab)
    RenderContentIntoScrollChild(settingsCurrentSubTab)

    -- Hide previews when panel is hidden
    panel:HookScript("OnHide", HideSettingsPreviews)

    return panel
end

-- Register global settings panel
GUIFrame:RegisterPanel("Dungeon_Settings", CreateSettingsPanel)

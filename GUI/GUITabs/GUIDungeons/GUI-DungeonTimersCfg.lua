-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-DungeonTimersCfg.lua                                ║
-- ║  Purpose: DT_General sidebar page — module enable +      ║
-- ║  per-dungeon import / export / preset / reset.           ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame

local ipairs = ipairs
local pairs = pairs
local wipe = wipe
local CreateFrame = CreateFrame
local C_Timer = C_Timer

local DUNGEON_ORDER = {
    { key = "MagistersTerrace",  name = "Magisters' Terrace",      iconID = 7439625 },
    { key = "MaisaraCaverns",    name = "Maisara Caverns",         iconID = 7322719 },
    { key = "NexusPointXenas",   name = "Nexus-Point Xenas",       iconID = 7553062 },
    { key = "WindrunnerSpire",   name = "Windrunner Spire",        iconID = 7266215 },
    { key = "AlgetharAcademy",   name = "Algeth'ar Academy",       iconID = 4578414 },
    { key = "PitOfSaron",        name = "Pit of Saron",            iconID = 343641 },
    { key = "SeatOfTriumvirate", name = "Seat of the Triumvirate", iconID = 1711340 },
    { key = "Skyreach",          name = "Skyreach",                iconID = 1002596 },
}

local function GetSettingsDB()
    if not KE.db or not KE.db.profile then return nil end
    return KE.db.profile.Dungeons and KE.db.profile.Dungeons.DungeonTimers
end

local function CreateSpellIconPreview(parent, iconId, size)
    size = size or 32
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(size)

    local iconFrame = CreateFrame("Frame", nil, container)
    iconFrame:SetSize(size, size)
    iconFrame:SetPoint("LEFT", container, "LEFT", 0, 0)

    iconFrame.texture = iconFrame:CreateTexture(nil, "ARTWORK")
    iconFrame.texture:SetPoint("TOPLEFT", 1, -1)
    iconFrame.texture:SetPoint("BOTTOMRIGHT", -1, 1)

    if iconId then
        iconFrame.texture:SetTexture(iconId)
        if KE.ApplyIconZoom then KE:ApplyIconZoom(iconFrame.texture) end
    else
        iconFrame.texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end

    local border = CreateFrame("Frame", nil, iconFrame, "BackdropTemplate")
    border:SetAllPoints()
    border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    border:SetBackdropBorderColor(0, 0, 0, 1)

    return container
end

GUIFrame:RegisterContent("DT_General", function(scrollChild, yOffset)
    local Theme = KE.Theme
    local db = GetSettingsDB()
    if not db then return yOffset end

    local DT = KitnEssentials and KitnEssentials:GetModule("DungeonTimers", true)
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplyModuleState(enabled)
        db.Enabled = enabled
        if not DT then return end
        if enabled then
            KitnEssentials:EnableModule("DungeonTimers")
        else
            KitnEssentials:DisableModule("DungeonTimers")
        end
        manager:UpdateAll(enabled)
    end

    local card1 = GUIFrame:CreateCard(scrollChild, "Dungeon Timers", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Dungeon Timers", {
        value = db.Enabled ~= false,
        callback = function(checked)
            ApplyModuleState(checked)
        end,
        msgPopup = true,
        msgText = "Dungeon Timers",
    })
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, Theme.rowHeightLast, 0)
    yOffset = card1:GetNextOffset()

    local card2 = GUIFrame:CreateCard(scrollChild, "Import / Export", yOffset)
    manager:Register(card2, "all")

    local padding = 0
    local buttonWidth = 100
    local buttonHeight = 28
    local buttonSpacing = Theme.paddingSmall

    local function RefreshAfterImport()
        if DT and DT.ApplySettings then DT:ApplySettings() end
        C_Timer.After(0.1, function()
            if GUIFrame.RefreshContent then GUIFrame:RefreshContent() end
        end)
    end

    -- All Dungeons row
    local rowAll = GUIFrame:CreateRow(card2.content, 32)

    local iconAll = CreateSpellIconPreview(rowAll, 525134, 28)
    rowAll:AddWidget(iconAll, 0.5)

    local labelAll = rowAll:CreateFontString(nil, "OVERLAY")
    KE:ApplyThemeFont(labelAll, "normal")
    labelAll:SetText("All Dungeons")
    labelAll:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
    labelAll:SetPoint("LEFT", rowAll, "LEFT", padding + 28 + Theme.paddingSmall, 0)

    local exportAllBtn = GUIFrame:CreateButton(rowAll, "Export", {
        tooltip = "Export timers for all dungeons",
        width = buttonWidth,
        height = buttonHeight,
        callback = function()
            if not DT then return end
            local exportString, err = DT:ExportTriggers()
            if exportString then
                KE:CreatePrompt("Export All Timers", exportString, true,
                    "Copy this string to share", false, nil, nil, nil, nil, nil, nil, "Close", nil)
            else
                KE:Print("Export failed: " .. (err or "Unknown error"))
            end
        end,
    })
    exportAllBtn:SetPoint("RIGHT", rowAll, "RIGHT", -padding - (buttonWidth + buttonSpacing) * 3, 0)
    manager:Register(exportAllBtn, "all")

    local importAllBtn = GUIFrame:CreateButton(rowAll, "Import", {
        width = buttonWidth,
        height = buttonHeight,
        tooltip = "Import timers for all dungeons (paste a multi-dungeon export string)",
        callback = function()
            KE:CreatePrompt("Import All Timers", "", true, "Paste import string",
                false, nil, nil, nil, nil,
                function(inputText)
                    if not DT then return end
                    local ok, msg = DT:ImportTriggers(inputText)
                    if ok then
                        KE:Print("Import successful: " .. (msg or ""))
                        RefreshAfterImport()
                    else
                        KE:Print("Import failed: " .. (msg or "Unknown error"))
                    end
                end,
                nil, "Import", "Cancel")
        end,
    })
    importAllBtn:SetPoint("RIGHT", rowAll, "RIGHT", -padding - (buttonWidth + buttonSpacing) * 2, 0)
    manager:Register(importAllBtn, "all")

    local importKESAllBtn = GUIFrame:CreateButton(rowAll, "KES", {
        width = buttonWidth,
        height = buttonHeight,
        tooltip = "Import KES presets for all dungeons",
        callback = function()
            if not DT then return end
            local imported = 0
            for _, dungeon in ipairs(DUNGEON_ORDER) do
                local ok = DT:ImportKESPresets(dungeon.key)
                if ok then imported = imported + 1 end
            end
            KE:Print(string.format("KES presets imported for %d dungeons", imported))
            RefreshAfterImport()
        end,
    })
    importKESAllBtn:SetPoint("RIGHT", rowAll, "RIGHT", -padding - (buttonWidth + buttonSpacing), 0)
    manager:Register(importKESAllBtn, "all")

    local resetAllBtn = GUIFrame:CreateButton(rowAll, "Reset", {
        tooltip = "Reset timers for all dungeons",
        width = buttonWidth,
        height = buttonHeight,
        callback = function()
            KE:CreatePrompt("Reset All Timers",
                "Are you sure you want to clear ALL timers from ALL dungeons?\n\nThis cannot be undone.",
                false, nil, false, nil, nil, nil, nil,
                function()
                    local dtDb = GetSettingsDB()
                    if dtDb and dtDb.Dungeons then
                        for _, dungeon in pairs(dtDb.Dungeons) do
                            if dungeon.Triggers then wipe(dungeon.Triggers) end
                        end
                    end
                    KE:Print("All triggers reset")
                    RefreshAfterImport()
                end,
                nil, "Reset All", "Cancel")
        end,
    })
    resetAllBtn:SetPoint("RIGHT", rowAll, "RIGHT", 0, 0)
    manager:Register(resetAllBtn, "all")

    card2:AddRow(rowAll, 32)

    -- Separator
    local sepRow = GUIFrame:CreateRow(card2.content, 8)
    local sep = GUIFrame:CreateSeparator(sepRow)
    sepRow:AddWidget(sep, 1)
    card2:AddRow(sepRow, 8)

    -- Per-dungeon rows
    for i, dungeon in ipairs(DUNGEON_ORDER) do
        local dungeonKey = dungeon.key
        local dungeonName = dungeon.name
        local iconID = dungeon.iconID
        local isLast = (i == #DUNGEON_ORDER)
        local rowHeight = 32

        local dungeonRow = GUIFrame:CreateRow(card2.content, rowHeight)

        local iconPreview = CreateSpellIconPreview(dungeonRow, iconID, 26)
        dungeonRow:AddWidget(iconPreview, 0.5)

        local dungeonLabel = dungeonRow:CreateFontString(nil, "OVERLAY")
        KE:ApplyThemeFont(dungeonLabel, "small")
        dungeonLabel:SetText(dungeonName)
        dungeonLabel:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
        dungeonLabel:SetPoint("LEFT", dungeonRow, "LEFT", padding + 28 + Theme.paddingSmall, 0)

        local exportBtn = GUIFrame:CreateButton(dungeonRow, "Export", {
            width = buttonWidth,
            height = buttonHeight - 2,
            tooltip = "Export timers for " .. dungeonName,
            callback = function()
                if not DT then return end
                local exportString, err = DT:ExportTriggers(dungeonKey)
                if exportString then
                    KE:CreatePrompt("Export: " .. dungeonName, exportString, true,
                        "Copy this string to share", false, nil, nil, nil, nil, nil, nil, "Close", nil)
                else
                    KE:Print("Export failed: " .. (err or "Unknown error"))
                end
            end,
        })
        exportBtn:SetPoint("RIGHT", dungeonRow, "RIGHT", -padding - (buttonWidth + buttonSpacing) * 3, 0)
        manager:Register(exportBtn, "all")

        local importBtn = GUIFrame:CreateButton(dungeonRow, "Import", {
            width = buttonWidth,
            height = buttonHeight - 2,
            tooltip = "Import timers for " .. dungeonName,
            callback = function()
                KE:CreatePrompt("Import: " .. dungeonName, "", true, "Paste import string",
                    false, nil, nil, nil, nil,
                    function(inputText)
                        if not DT then return end
                        local ok, msg = DT:ImportTriggers(inputText)
                        if ok then
                            KE:Print("Import successful: " .. (msg or ""))
                            RefreshAfterImport()
                        else
                            KE:Print("Import failed: " .. (msg or "Unknown error"))
                        end
                    end,
                    nil, "Import", "Cancel")
            end,
        })
        importBtn:SetPoint("RIGHT", dungeonRow, "RIGHT", -padding - (buttonWidth + buttonSpacing) * 2, 0)
        manager:Register(importBtn, "all")

        local importKESBtn = GUIFrame:CreateButton(dungeonRow, "KES", {
            width = buttonWidth,
            height = buttonHeight - 2,
            tooltip = "Import KES presets for " .. dungeonName,
            callback = function()
                if not DT then return end
                local ok, msg = DT:ImportKESPresets(dungeonKey)
                if ok then
                    KE:Print("KES preset imported: " .. (msg or dungeonName))
                    RefreshAfterImport()
                else
                    KE:Print("Import failed: " .. (msg or "No presets available"))
                end
            end,
        })
        importKESBtn:SetPoint("RIGHT", dungeonRow, "RIGHT", -padding - (buttonWidth + buttonSpacing), 0)
        manager:Register(importKESBtn, "all")

        local resetBtn = GUIFrame:CreateButton(dungeonRow, "Reset", {
            tooltip = "Reset timers for " .. dungeonName,
            width = buttonWidth,
            height = buttonHeight - 2,
            callback = function()
                KE:CreatePrompt("Reset: " .. dungeonName,
                    "Are you sure you want to clear all timers for " .. dungeonName .. "?\n\nThis cannot be undone.",
                    false, nil, false, nil, nil, nil, nil,
                    function()
                        local dtDb = GetSettingsDB()
                        if dtDb and dtDb.Dungeons and dtDb.Dungeons[dungeonKey]
                            and dtDb.Dungeons[dungeonKey].Triggers then
                            wipe(dtDb.Dungeons[dungeonKey].Triggers)
                        end
                        KE:Print("Triggers reset for " .. dungeonName)
                        RefreshAfterImport()
                    end,
                    nil, "Reset", "Cancel")
            end,
        })
        resetBtn:SetPoint("RIGHT", dungeonRow, "RIGHT", -padding, 0)
        manager:Register(resetBtn, "all")

        card2:AddRow(dungeonRow, rowHeight, isLast and 0 or nil)
    end

    yOffset = card2:GetNextOffset()
    manager:UpdateAll(db.Enabled ~= false)

    return yOffset
end)

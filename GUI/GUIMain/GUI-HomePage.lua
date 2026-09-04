-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-HomePage.lua                                        ║
-- ║  Purpose: Home page with general settings and            ║
-- ║  minimap/chat toggles.                                   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local UnitName = UnitName
local UnitClass = UnitClass
local ipairs = ipairs
local string_format = string.format
local ReloadUI = ReloadUI
local pairs = pairs

---------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------

local function BuildFontList()
    local list = {}
    if KE.LSM then
        for name in pairs(KE.LSM:HashTable("font")) do
            list[name] = name
        end
    else
        list["Expressway"] = "Expressway"
    end
    return list
end

---------------------------------------------------------------------------------
-- Card Sections
---------------------------------------------------------------------------------

GUIFrame:RegisterContent("HomePage", function(scrollChild, yOffset)
    local T = Theme
    local _, class = UnitClass("player")
    local classColor = RAID_CLASS_COLORS[class] or { r = 1, g = 1, b = 1 }
    local playerName = UnitName("player") or "Adventurer"

    ---------------------------------------------------------------------------------
    -- Card 1: Welcome
    ---------------------------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Welcome to " .. KE:ColorTextByTheme("Kitn") .. "Essentials", yOffset)

    -- Player greeting with class color
    local colorHex = string_format("%02x%02x%02x", classColor.r * 255, classColor.g * 255, classColor.b * 255)
    card1:AddLabel("Hello, |cff" .. colorHex .. playerName .. "|r!")
    card1:AddSpacing(4)

    -- Version and author
    local version = KE.Version or "@project-version@"
    local infoLabel = card1:AddLabel("Version: |cffffffff" .. version .. "|r  -  Author: |cffffffffBitebtw|r")
    infoLabel:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)
    card1:AddSpacing(2)

    -- Active profile
    local profileName = KE.db and KE.db.GetCurrentProfile and KE.db:GetCurrentProfile() or "Default"
    card1:AddLabel("Active Profile: |cff4dff4d" .. profileName .. "|r")
    card1:AddSpacing(2)

    -- Credit
    local creditLabel = card1:AddLabel("Built on the foundation of |cffffffffNorsken|r and Atrocity")
    creditLabel:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)

    yOffset = card1:GetNextOffset()

    ---------------------------------------------------------------------------------
    -- Card 2: General
    ---------------------------------------------------------------------------------
    local db = KE.db and KE.db.profile
    local themeDb = KE.db and KE.db.global and KE.db.global.Theme
    local themeMode = (themeDb and themeDb.Mode) or "preset"
    local card2 = GUIFrame:CreateCard(scrollChild, "General", yOffset)

    local row1 = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)

    -- Edit Mode Button
    local editModeBtn = GUIFrame:CreateButton(row1, "Toggle Anchors", {
        width = 140,
        height = 32,
        callback = function()
            if KE.EditMode then
                KE.EditMode:Toggle()
            end
        end
    })
    row1:AddWidget(editModeBtn, 0.5)

    -- Reload UI Button
    local reloadBtn = GUIFrame:CreateButton(row1, "Reload UI", {
        width = 140,
        height = 32,
        callback = function()
            ReloadUI()
        end
    })
    row1:AddWidget(reloadBtn, 0.5)

    card2:AddRow(row1, Theme.rowHeightLast)

    card2:AddSpacing(4)
    local tipLabel = card2:AddLabel(
        "Use " .. KE:ColorTextByTheme("/kes") .. " to open settings, " ..
        KE:ColorTextByTheme("/kes edit") .. " to toggle Edit Mode, " ..
        KE:ColorTextByTheme("/rl") .. " to reload.")
    tipLabel:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)

    local sepRow = GUIFrame:CreateRow(card2.content, Theme.rowHeightSeparator)
    local sep = GUIFrame:CreateSeparator(sepRow)
    sepRow:AddWidget(sep, 1)
    card2:AddRow(sepRow, Theme.rowHeightSeparator)

    local row3a = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local minimapCheck = GUIFrame:CreateCheckbox(row3a, "Show Minimap Button", {
        value = not (db and db.Minimap and db.Minimap.hide),
        callback = function(checked)
            if not db then return end
            db.Minimap = db.Minimap or {}
            db.Minimap.hide = not checked
            local icon = LibStub and LibStub("LibDBIcon-1.0", true)
            if icon then
                if checked then
                    icon:Show("KitnEssentials")
                else
                    icon:Hide("KitnEssentials")
                end
            end
        end,
    })
    row3a:AddWidget(minimapCheck, 0.5)

    local chatCheck = GUIFrame:CreateCheckbox(row3a, "Show Command in Chat on Login", {
        value = db and db.ShowChatMessage ~= false,
        callback = function(checked)
            if not db then return end
            db.ShowChatMessage = checked
        end,
    })
    row3a:AddWidget(chatCheck, 0.5)
    card2:AddRow(row3a, Theme.rowHeight)

    local row3b = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local slugCheck = GUIFrame:CreateCheckbox(row3b, "Use Slug Font Rendering", {
        value = not (db and db.UseSlugFonts == false),
        tooltip = "Renders text with the GPU glyph renderer for crisper edges.",
        callback = function(checked)
            if not db then return end
            db.UseSlugFonts = checked
            KE:CreateReloadPrompt("Changing Slug rendering requires a UI reload to reach every module.")
        end,
    })
    row3b:AddWidget(slugCheck, 0.5)

    local fontDropdown = GUIFrame:CreateDropdown(row3b, "Global Font", {
        options = BuildFontList(),
        searchable = true,
        value = KE:GetGlobalFont(),
        tooltip = "Used by every module and skin that has not been given a font of its own.",
        callback = function(name)
            if not db or not name then return end
            db.GlobalFont = name
            KE:CreateReloadPrompt("Changing the global font requires a UI reload to reach every module.")
        end,
    })
    row3b:AddWidget(fontDropdown, 0.5)
    card2:AddRow(row3b, Theme.rowHeight)

    local sepRow2 = GUIFrame:CreateRow(card2.content, Theme.rowHeightSeparator)
    local sep2 = GUIFrame:CreateSeparator(sepRow2)
    sepRow2:AddWidget(sep2, 1)
    card2:AddRow(sepRow2, Theme.rowHeightSeparator)

    local themeManager = GUIFrame:CreateWidgetStateManager()
    themeManager:SetCondition("preset", function() return themeMode == "preset" end)

    local row4 = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local themeDropdown = GUIFrame:CreateDropdown(row4, "Theme Mode", {
        options = KE.ThemeModeOptions,
        value = themeMode,
        callback = function(mode) KE:SetThemeMode(mode) end,
    })
    row4:AddWidget(themeDropdown, 0.30)

    local presetSwatches = GUIFrame:CreatePresetSwatches(row4, {
        value = (themeDb and themeDb.Preset) or "KitnUI",
        callback = function(presetName) KE:SetThemePreset(presetName) end,
    })
    -- Aligned with the dropdown's control box rather than centred in the row:
    -- GUI-KEDropdown.lua drops its button 14 below the row top to clear the
    -- label, and the chips are the same height as that button.
    row4:AddWidget(presetSwatches, 0.42, nil, 0, -14)
    themeManager:Register(presetSwatches, "preset")

    local customizeBtn = GUIFrame:CreateButton(row4, "Customize...", {
        callback = function() GUIFrame:ToggleThemePopup() end,
    })
    row4:AddWidget(customizeBtn, 0.28)
    GUIFrame:RegisterThemePopupOpener("home", customizeBtn)

    card2:AddRow(row4, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    ---------------------------------------------------------------------------------
    -- Card 4: Getting Started
    ---------------------------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Getting Started", yOffset)

    local tips = {
        "Use the sidebar to navigate between different module settings.",
        "Edit Mode allows you to drag and reposition UI elements.",
        "Most changes apply instantly without needing a reload. Modules where a reload is required will prompt you.",
    }
    for _, tip in ipairs(tips) do
        local tipLabel2 = card3:AddLabel(KE:ColorTextByTheme("- ") .. tip)
        tipLabel2:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
        card3:AddSpacing(2)
    end

    yOffset = card3:GetNextOffset()

    ---------------------------------------------------------------------------------
    -- Card 5: ElvUI Integration (only when ElvUI is loaded)
    ---------------------------------------------------------------------------------
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("ElvUI") then
        local elvCard = GUIFrame:CreateCard(scrollChild, "ElvUI Integration", yOffset)
        local useElvUI = KE.db and KE.db.profile and KE.db.profile.UseElvUI and KE.db.profile.UseElvUI.Enabled
        local statusText = useElvUI and "|cff4dff4dEnabled|r" or "|cffff4d4dDisabled|r"
        elvCard:AddLabel("ElvUI Skinning: " .. statusText)
        elvCard:AddSpacing(4)
        local elvDesc = elvCard:AddLabel(
            KE:ColorTextByTheme("- ") .. "Disables all skinning modules when ElvUI is loaded.\n" ..
            "This way you can still use the non skinning features of the addon without conflict.")
        elvDesc:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)

        yOffset = elvCard:GetNextOffset()
    end

    ---------------------------------------------------------------------------------
    -- Card 6: Support
    ---------------------------------------------------------------------------------
    local card6 = GUIFrame:CreateCard(scrollChild, "Support", yOffset)

    card6:AddLabel("Found a bug or have a suggestion?")
    card6:AddSpacing(4)
    local discordLabel = card6:AddLabel("Send a message for support directly on Discord: |cff20d00bglizzygordo|r or |cff20d00bdunnni|r")
    discordLabel:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)

    yOffset = card6:GetNextOffset()

    themeManager:UpdateAll(true)

    yOffset = yOffset - (T.paddingSmall * 3)
    return yOffset
end)

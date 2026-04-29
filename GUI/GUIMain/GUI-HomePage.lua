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
local GetRealmName = GetRealmName
local ipairs = ipairs
local string_format = string.format
local ReloadUI = ReloadUI

---------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------

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
    local greetingLabel = card1:AddLabel("Hello, |cff" .. colorHex .. playerName .. "|r!")
    card1:AddSpacing(4)

    -- Version and author
    local version = KE.Version or "@project-version@"
    local infoLabel = card1:AddLabel("Version: |cffffffff" .. version .. "|r  -  Author: |cffffffffBitebtw|r")
    infoLabel:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)
    card1:AddSpacing(2)

    -- Credit
    local creditLabel = card1:AddLabel("Built on the foundation of |cffffffffNorsken|r and Atrocity")
    creditLabel:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)

    yOffset = card1:GetNextOffset()

    ---------------------------------------------------------------------------------
    -- Card 2: Quick Actions
    ---------------------------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Quick Actions", yOffset)

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

    card2:AddRow(row1, Theme.rowHeightLast, 0)

    card2:AddSpacing(4)
    local tipLabel = card2:AddLabel(
        "Use " .. KE:ColorTextByTheme("/kes") .. " to open settings, " ..
        KE:ColorTextByTheme("/kes edit") .. " to toggle Edit Mode, " ..
        KE:ColorTextByTheme("/rl") .. " to reload.")
    tipLabel:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)

    yOffset = card2:GetNextOffset()

    ---------------------------------------------------------------------------------
    -- Card 3: General Settings
    ---------------------------------------------------------------------------------
    local db = KE.db and KE.db.profile
    local cardSettings = GUIFrame:CreateCard(scrollChild, "General Settings", yOffset)

    local row3a = GUIFrame:CreateRow(cardSettings.content, Theme.rowHeightLast)
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
    cardSettings:AddRow(row3a, Theme.rowHeightLast, 0)

    yOffset = cardSettings:GetNextOffset()

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
    -- Card 5: Profile
    ---------------------------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Profile", yOffset)

    local profileName = KE.db and KE.db.GetCurrentProfile and KE.db:GetCurrentProfile() or "Default"
    card4:AddLabel("Active Profile: |cff4dff4d" .. profileName .. "|r")
    card4:AddSpacing(4)

    local realmName = GetRealmName() or "Unknown"
    local charLabel = card4:AddLabel("Character: |cff" .. colorHex .. playerName .. "|r - " .. realmName)
    charLabel:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)

    yOffset = card4:GetNextOffset()

    ---------------------------------------------------------------------------------
    -- Card 6: ElvUI Integration (only when ElvUI is loaded)
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
    -- Card 7: Support
    ---------------------------------------------------------------------------------
    local card6 = GUIFrame:CreateCard(scrollChild, "Support", yOffset)

    card6:AddLabel("Found a bug or have a suggestion?")
    card6:AddSpacing(4)
    local discordLabel = card6:AddLabel("Send a message for support directly on Discord: |cff20d00bglizzygordo|r or |cff20d00bdunnni|r")
    discordLabel:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)

    yOffset = card6:GetNextOffset()

    yOffset = yOffset - (T.paddingSmall * 3)
    return yOffset
end)

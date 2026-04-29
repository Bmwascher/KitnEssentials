-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-Auras.lua                                           ║
-- ║  GUI: Buffs, Debuffs & Externals                         ║
-- ║  Purpose: Configuration panel for the Auras module.      ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)

local pairs = pairs

local SETTINGS_OUTLINE_OPTIONS = {
    { key = "NONE",         text = "None" },
    { key = "OUTLINE",      text = "Outline" },
    { key = "THICKOUTLINE", text = "Thick" },
}

local function GetAurasModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("SkinAuras", true)
    end
    return nil
end

GUIFrame:RegisterContent("SkinAuras", function(scrollChild, yOffset)
    if KE:ShouldNotLoadModule() then return end
    local db = KE.db and KE.db.profile.Skinning.Auras
    if not db then return yOffset end

    local AURAS = GetAurasModule()
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if not AURAS or not AURAS:IsEnabled() then return end
        AURAS:Refresh()
    end

    local function ApplyAurasState(enabled)
        if not AURAS then return end
        AURAS.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("SkinAuras")
        else
            KitnEssentials:DisableModule("SkinAuras")
        end
    end

    local fontList = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do fontList[name] = name end
    else
        fontList["Friz Quadrata TT"] = "Friz Quadrata TT"
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Buffs, Debuffs & Externals", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Buffs, Debuffs & Externals Skinning", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyAurasState(checked)
            manager:UpdateAll(checked)
            if not checked then
                KE:CreateReloadPrompt("Enabling/Disabling this UI element requires a reload to take full effect.")
            end
        end,
        msgPopup = true,
        msgText = "Buffs, Debuffs & Externals Skinning",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 0.5)
    card1:AddRow(row1, Theme.rowHeight, 0)

    card1:AddLabel("|cff888888" .. KE:ColorTextByTheme("Tip:") .. " Use Blizzard Edit Mode to adjust icon size and positioning.|r")

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: General Settings
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "General Settings", yOffset)
    manager:Register(card2, "all")

    local row2 = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local disableFlashing = GUIFrame:CreateCheckbox(row2, "Disable flashing when low duration", {
        value = db.disableFlashing ~= false,
        callback = function(checked)
            db.disableFlashing = checked
            ApplySettings()
            if not checked then
                KE:CreateReloadPrompt("Disabling this UI element requires a reload to take full effect.")
            end
        end,
    })
    row2:AddWidget(disableFlashing, 0.5)
    manager:Register(disableFlashing, "all")
    card2:AddRow(row2, Theme.rowHeight)

    local sepRow = GUIFrame:CreateRow(card2.content, Theme.rowHeightSeparator)
    local sepWidget = GUIFrame:CreateSeparator(sepRow)
    sepRow:AddWidget(sepWidget, 1)
    card2:AddRow(sepRow, Theme.rowHeightSeparator)

    local row2c = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local fontColor = GUIFrame:CreateColorPicker(row2c, "Font color", {
        color = db.FontColor,
        callback = function(r, g, b, a)
            db.FontColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row2c:AddWidget(fontColor, 1)
    manager:Register(fontColor, "all")
    card2:AddRow(row2c, Theme.rowHeight)

    local row2a = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local fontDropdown = GUIFrame:CreateDropdown(row2a, "Font", {
        options = fontList,
        value = db.FontFace,
        callback = function(key)
            db.FontFace = key
            ApplySettings()
        end,
        searchable = true,
        isFontPreview = true,
    })
    row2a:AddWidget(fontDropdown, 0.5)
    manager:Register(fontDropdown, "all")

    local outlineDropdown = GUIFrame:CreateDropdown(row2a, "Outline", {
        options = SETTINGS_OUTLINE_OPTIONS,
        value = db.FontOutline or "OUTLINE",
        callback = function(key)
            db.FontOutline = key
            ApplySettings()
        end,
    })
    row2a:AddWidget(outlineDropdown, 0.5)
    manager:Register(outlineDropdown, "all")
    card2:AddRow(row2a, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Buff Settings
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Buff Settings", yOffset)
    manager:Register(card3, "all")

    local row3 = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local buffBorderColor = GUIFrame:CreateColorPicker(row3, "Buff border color", {
        color = db.buffBorderColor,
        callback = function(r, g, b, a)
            db.buffBorderColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row3:AddWidget(buffBorderColor, 0.5)
    manager:Register(buffBorderColor, "all")
    card3:AddRow(row3, Theme.rowHeightLast, 0)

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Debuff Settings
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Debuff Settings", yOffset)
    manager:Register(card4, "all")

    local row4 = GUIFrame:CreateRow(card4.content, Theme.rowHeightLast)
    local debuffBorderColor = GUIFrame:CreateColorPicker(row4, "Debuff border color", {
        color = db.debuffBorderColor,
        callback = function(r, g, b, a)
            db.debuffBorderColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row4:AddWidget(debuffBorderColor, 0.5)
    manager:Register(debuffBorderColor, "all")
    card4:AddRow(row4, Theme.rowHeightLast, 0)

    yOffset = card4:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: External Defensive Settings
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "External Defensive Settings", yOffset)
    manager:Register(card5, "all")

    local row5 = GUIFrame:CreateRow(card5.content, Theme.rowHeightLast)
    local defBorderColor = GUIFrame:CreateColorPicker(row5, "External Defensive border color", {
        color = db.defBorderColor,
        callback = function(r, g, b, a)
            db.defBorderColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row5:AddWidget(defBorderColor, 0.5)
    manager:Register(defBorderColor, "all")
    card5:AddRow(row5, Theme.rowHeightLast, 0)

    yOffset = card5:GetNextOffset()

    manager:UpdateAll(db.Enabled ~= false)
    return yOffset
end)

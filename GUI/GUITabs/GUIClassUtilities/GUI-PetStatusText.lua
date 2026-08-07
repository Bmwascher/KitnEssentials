-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-PetStatusText.lua                                   ║
-- ║  GUI: Pet Status Text                                    ║
-- ║  Purpose: Configuration panel for the PetStatusText      ║
-- ║  module.                                                 ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("PetStatusText", true)
    end
    return nil
end

GUIFrame:RegisterContent("PetStatusText", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.PetStatusText
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local mod = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if mod and mod.ApplySettings then mod:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("PetStatusText")
        else
            KitnEssentials:DisableModule("PetStatusText")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Pet Status Texts", yOffset)
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        ApplyModuleState(checked)
        KE:Print("Pet Status Texts: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
    end)

    yOffset = card1:GetNextOffset()

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if db.Enabled == false then return yOffset end

    ----------------------------------------------------------------
    -- Card 2: Position Settings
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            anchorFrameType = "anchorFrameType",
            anchorFrameFrame = "ParentFrame",
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
            strata = "Strata",
        },
        showAnchorFrameType = true,
        showStrata = true,
        onChangeCallback = ApplySettings,
    })

    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    manager:Register(posCard, "all")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 3: Font Settings
    ----------------------------------------------------------------
    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            fontFace = "FontFace",
            fontSize = "FontSize",
            fontOutline = "FontOutline",
        },
        onChangeCallback = ApplySettings,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then
        manager:RegisterGroup(fontWidgets, "all")
    end
    yOffset = fontOffset

    ----------------------------------------------------------------
    -- Card 4: State Settings
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "State Settings", yOffset)
    manager:Register(card4, "all")

    local states = {
        { dbText = "PetMissing",  defaultText = "PET MISSING",  textLabel = "Pet Missing Text",
          dbColor = "MissingColor", defaultColor = { 1, 0.82, 0, 1 }, colorLabel = "Missing Color" },
        { dbText = "PetDead",     defaultText = "PET DEAD",     textLabel = "Pet Dead Text",
          dbColor = "DeadColor",    defaultColor = { 1, 0.2, 0.2, 1 }, colorLabel = "Dead Color" },
        { dbText = "PetPassive",  defaultText = "PET PASSIVE",  textLabel = "Pet Passive Text",
          dbColor = "PassiveColor", defaultColor = { 1, 0, 0.549, 1 }, colorLabel = "Passive Color" },
        { dbText = "PetWrong",    defaultText = "WRONG PET",    textLabel = "Wrong Pet Text",
          dbColor = "WrongColor",   defaultColor = { 1, 0.4, 0, 1 }, colorLabel = "Wrong Color" },
    }

    for i, state in ipairs(states) do
        local isLast = i == #states
        local rowHeight = isLast and Theme.rowHeightLast or Theme.rowHeight
        local row = GUIFrame:CreateRow(card4.content, rowHeight)

        local textBox = GUIFrame:CreateEditBox(row, state.textLabel, {
            value = db[state.dbText] or state.defaultText,
            callback = function(val) db[state.dbText] = val; ApplySettings() end,
        })
        row:AddWidget(textBox, 0.5)
        manager:Register(textBox, "all")

        local colorPicker = GUIFrame:CreateColorPicker(row, state.colorLabel, {
            color = db[state.dbColor] or state.defaultColor,
            callback = function(r, g, b, a)
                db[state.dbColor] = { r, g, b, a }
                ApplySettings()
            end,
        })
        row:AddWidget(colorPicker, 0.5)
        manager:Register(colorPicker, "all")

        if isLast then
            card4:AddRow(row, rowHeight, 0)
        else
            card4:AddRow(row, rowHeight)
        end
    end

    yOffset = card4:GetNextOffset()

    RefreshStates()
    return yOffset
end)

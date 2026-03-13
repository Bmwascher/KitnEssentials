-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local table_insert = table.insert
local ipairs = ipairs

local C_CVar = C_CVar

local function GetAutomationModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("Automation", true)
    end
    return nil
end

GUIFrame:RegisterContent("CVars", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.Automation
    if not db then return yOffset end

    local AU = GetAutomationModule()
    local allWidgets = {}

    ----------------------------------------------------------------
    -- Card 1: CVars Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "CVars", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Apply CVars on Login", db.CVarsEnabled ~= false,
        function(checked)
            db.CVarsEnabled = checked
            if AU and checked then AU:ApplyCVars() end
        end,
        true, "CVars", "On", "Off")
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, 36)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 2: Floating Combat Text
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Floating Combat Text", yOffset)
    table_insert(allWidgets, card2)

    -- Helper to add a CVar checkbox + desc/note to a card
    local function AddCVarCheckbox(card, def)
        local key = def.key
        local label = def.label
        if def.desc then
            label = label .. "  |cff888888- " .. def.desc .. "|r"
        end
        local row = GUIFrame:CreateRow(card.content, 38)
        local checkbox = GUIFrame:CreateCheckbox(row, label, db[key],
            function(checked)
                db[key] = checked
                AU._suppressCVarUpdate = true
                AU:ApplyCVars()
                AU._suppressCVarUpdate = false
            end)
        row:AddWidget(checkbox, 1.0)
        table_insert(allWidgets, checkbox)
        card:AddRow(row, 38)
    end

    if AU then
        for _, def in ipairs(AU.CVAR_DEFS) do
            if def.key:find("^floatingCombatText") or def.key == "enableFloatingCombatText" then
                AddCVarCheckbox(card2, def)
            end
        end
    end

    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 3: Character & Effects
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Character & Effects", yOffset)
    table_insert(allWidgets, card3)

    if AU then
        local charEffectKeys = {
            findYourselfModeOutline = true,
            occludedSilhouettePlayer = true,
            ffxDeath = true,
            ffxGlow = true,
            ResampleAlwaysSharpen = true,
        }
        for _, def in ipairs(AU.CVAR_DEFS) do
            if charEffectKeys[def.key] then
                AddCVarCheckbox(card3, def)
            end
        end
    end

    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 4: Nameplates
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Nameplates", yOffset)
    table_insert(allWidgets, card4)

    card4:AddLabel("|cffCC8800Friendly Player Nameplates must be " .. KE:ColorTextByTheme("enabled") .. " for these to work.|r")

    if AU then
        for _, def in ipairs(AU.CVAR_DEFS) do
            if def.key:find("^nameplate") then
                AddCVarCheckbox(card4, def)
            end
        end
    end

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 5: Sliders
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Sliders", yOffset)
    table_insert(allWidgets, card5)

    if AU then
        for i, def in ipairs(AU.CVAR_SLIDER_DEFS) do
            local key = def.key
            local currentVal = db[key]
            if currentVal == nil then
                currentVal = tonumber(C_CVar.GetCVar(key)) or 0
            end

            local isFirstInPair = (i % 2 == 1)
            local isLastDef = (i == #AU.CVAR_SLIDER_DEFS)

            if isFirstInPair then
                card5._currentSliderRow = GUIFrame:CreateRow(card5.content, 60)
            end

            local slider = GUIFrame:CreateSlider(card5._currentSliderRow, def.label,
                def.min, def.max, def.step, currentVal, 60,
                function(val)
                    db[key] = val
                    AU._suppressCVarUpdate = true
                    C_CVar.SetCVar(key, tostring(val))
                    AU._suppressCVarUpdate = false
                end)
            card5._currentSliderRow:AddWidget(slider, 0.5)
            table_insert(allWidgets, slider)

            if not isFirstInPair or isLastDef then
                card5:AddRow(card5._currentSliderRow, 60)
            end
        end
    end

    yOffset = yOffset + card5:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    local function UpdateAllWidgetStates()
        local enabled = db.CVarsEnabled ~= false
        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then widget:SetEnabled(enabled) end
        end
    end
    UpdateAllWidgetStates()

    yOffset = yOffset - (Theme.paddingSmall * 2)
    return yOffset
end)

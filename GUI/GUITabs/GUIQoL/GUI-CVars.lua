-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-CVars.lua                                           ║
-- ║  GUI: CVars                                              ║
-- ║  Purpose: Configuration panel for the CVars module.      ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

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
    local manager = GUIFrame:CreateWidgetStateManager()

    local function RefreshStates()
        manager:UpdateAll(db.CVarsEnabled ~= false)
    end

    local function AddCVarCheckbox(card, def, existingRow, widthPct)
        local key = def.key
        local label = def.label
        if def.desc then
            label = label .. "  |cff888888- " .. def.desc .. "|r"
        end
        local row = existingRow or GUIFrame:CreateRow(card.content, Theme.rowHeight)
        local checkbox = GUIFrame:CreateCheckbox(row, label, {
            value = db[key],
            callback = function(checked)
                db[key] = checked
                if AU then
                    AU._suppressCVarUpdate = true
                    AU:ApplyCVars()
                    AU._suppressCVarUpdate = false
                end
            end,
        })
        row:AddWidget(checkbox, widthPct or 1)
        manager:Register(checkbox, "all")
        if not existingRow then
            card:AddRow(row, Theme.rowHeight)
        end
    end

    ----------------------------------------------------------------
    -- Card 1: CVars Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "CVars", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Apply CVars on Login", {
        value = db.CVarsEnabled ~= false,
        callback = function(checked)
            db.CVarsEnabled = checked
            if AU and checked then AU:ApplyCVars() end
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "CVars",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Floating Combat Text
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Floating Combat Text", yOffset)
    manager:Register(card2, "all")

    if AU then
        for _, def in ipairs(AU.CVAR_DEFS) do
            if def.key:find("^floatingCombatText") or def.key == "enableFloatingCombatText" then
                AddCVarCheckbox(card2, def)
            end
        end
    end

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Character & Effects
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Character & Effects", yOffset)
    manager:Register(card3, "all")

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

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Tooltips
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Tooltips", yOffset)
    manager:Register(card4, "all")

    if AU then
        for _, def in ipairs(AU.CVAR_DEFS) do
            if def.key == "alwaysCompareItems" then
                AddCVarCheckbox(card4, def)
            end
        end
    end

    yOffset = card4:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Nameplates
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Nameplates", yOffset)
    manager:Register(card5, "all")

    card5:AddLabel("|cffCC8800Friendly Player Nameplates must be |cff33ff33enabled|r|cffCC8800 for these to work.|r")

    if AU then
        local nameplateDefs = {}
        for _, def in ipairs(AU.CVAR_DEFS) do
            if def.key:find("^nameplate") then
                nameplateDefs[#nameplateDefs + 1] = def
            end
        end
        local n = #nameplateDefs
        for i = 1, n, 2 do
            local isLastPair = (i + 1 >= n)
            local rowHeight = isLastPair and Theme.rowHeightLast or Theme.rowHeight
            local row = GUIFrame:CreateRow(card5.content, rowHeight)
            AddCVarCheckbox(card5, nameplateDefs[i], row, 0.5)
            if nameplateDefs[i + 1] then
                AddCVarCheckbox(card5, nameplateDefs[i + 1], row, 0.5)
            end
            if isLastPair then
                card5:AddRow(row, rowHeight, 0)
            else
                card5:AddRow(row, rowHeight)
            end
        end
    end

    yOffset = card5:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 6: Sliders
    ----------------------------------------------------------------
    local card6 = GUIFrame:CreateCard(scrollChild, "Sliders", yOffset)
    manager:Register(card6, "all")

    if AU then
        local currentSliderRow
        for i, def in ipairs(AU.CVAR_SLIDER_DEFS) do
            local key = def.key
            local currentVal = db[key]
            if currentVal == nil then
                currentVal = tonumber(C_CVar.GetCVar(key)) or 0
            end

            local isFirstInPair = (i % 2 == 1)
            local isLastDef = (i == #AU.CVAR_SLIDER_DEFS)

            if isFirstInPair then
                currentSliderRow = GUIFrame:CreateRow(card6.content, 60)
            end

            local slider = GUIFrame:CreateSlider(currentSliderRow, def.label, {
                min = def.min, max = def.max, step = def.step,
                value = currentVal,
                callback = function(val)
                    db[key] = val
                    if AU then
                        AU._suppressCVarUpdate = true
                        C_CVar.SetCVar(key, tostring(val))
                        AU._suppressCVarUpdate = false
                    end
                end,
            })
            currentSliderRow:AddWidget(slider, 0.5)
            manager:Register(slider, "all")

            if not isFirstInPair or isLastDef then
                if isLastDef then
                    card6:AddRow(currentSliderRow, 60, 0)
                else
                    card6:AddRow(currentSliderRow, 60)
                end
            end
        end
    end

    yOffset = card6:GetNextOffset()

    RefreshStates()
    return yOffset
end)

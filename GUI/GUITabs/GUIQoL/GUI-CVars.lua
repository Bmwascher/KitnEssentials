-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-CVars.lua                                           ║
-- ║  GUI: CVars                                              ║
-- ║  Purpose: Configuration panel for the CVars module, and  ║
-- ║  the host page for the Map Scale card (its own module).  ║
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

local function GetMapScaleModule()
    return KitnEssentials and KitnEssentials:GetModule("MapScale", true)
end

GUIFrame:RegisterContent("CVars", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.Automation
    if not db then return yOffset end

    -- Map scale lives in its own profile block (KE.db.profile.MapScale), not
    -- in `db` above — a separate module keeps its own enable lifecycle.
    local mapDB = KE.db and KE.db.profile.MapScale

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
            value = AU and AU:GetLiveCVar(def) or false,
            callback = function(checked)
                -- The write still goes through the profile as well as the
                -- client, so the value keeps travelling with the profile and
                -- "Apply CVars on Login" keeps working. Only the display source
                -- changed.
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

    -- The rule itself lives on the module so it can be tested; this only covers
    -- the page being built before Automation exists.
    local function LiveDefs(defs, match)
        if not AU then return {} end
        return AU:FilterLiveDefs(defs, match)
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
    local ftDefs = LiveDefs(AU and AU.CVAR_DEFS or {}, function(def)
        return def.key:find("^floatingCombatText") ~= nil or def.key == "enableFloatingCombatText"
    end)
    if #ftDefs > 0 then
        local card2 = GUIFrame:CreateCard(scrollChild, "Floating Combat Text", yOffset)
        manager:Register(card2, "all")
        for _, def in ipairs(ftDefs) do
            AddCVarCheckbox(card2, def)
        end
        yOffset = card2:GetNextOffset()
    end

    ----------------------------------------------------------------
    -- Card 3: Character Visibility
    ----------------------------------------------------------------
    local charEffectKeys = {
        findYourselfModeOutline = true,
        occludedSilhouettePlayer = true,
    }
    local charDefs = LiveDefs(AU and AU.CVAR_DEFS or {}, function(def)
        return charEffectKeys[def.key] == true
    end)
    if #charDefs > 0 then
        local card3 = GUIFrame:CreateCard(scrollChild, "Character Visibility", yOffset)
        manager:Register(card3, "all")
        for _, def in ipairs(charDefs) do
            AddCVarCheckbox(card3, def)
        end
        yOffset = card3:GetNextOffset()
    end

    ----------------------------------------------------------------
    -- Card 4: Tooltips
    ----------------------------------------------------------------
    local tooltipDefs = LiveDefs(AU and AU.CVAR_DEFS or {}, function(def)
        return def.key == "alwaysCompareItems"
    end)
    if #tooltipDefs > 0 then
        local card4 = GUIFrame:CreateCard(scrollChild, "Tooltips", yOffset)
        manager:Register(card4, "all")
        for _, def in ipairs(tooltipDefs) do
            AddCVarCheckbox(card4, def)
        end
        yOffset = card4:GetNextOffset()
    end

    ----------------------------------------------------------------
    -- Card 5: Nameplates
    ----------------------------------------------------------------
    local nameplateDefs = LiveDefs(AU and AU.CVAR_DEFS or {}, function(def)
        return def.key:find("^nameplate") ~= nil
    end)
    if #nameplateDefs > 0 then
        local card5 = GUIFrame:CreateCard(scrollChild, "Nameplates", yOffset)
        manager:Register(card5, "all")

        card5:AddLabel("|cffCC8800Friendly Player Nameplates must be |cff33ff33enabled|r|cffCC8800 for these to work.|r")

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
        yOffset = card5:GetNextOffset()
    end

    ----------------------------------------------------------------
    -- Card 6: Sliders
    ----------------------------------------------------------------
    local sliderDefs = LiveDefs(AU and AU.CVAR_SLIDER_DEFS or {})
    if #sliderDefs > 0 then
        local card6 = GUIFrame:CreateCard(scrollChild, "Sliders", yOffset)
        manager:Register(card6, "all")

        local currentSliderRow
        for i, def in ipairs(sliderDefs) do
            local key = def.key
            local currentVal = AU:GetLiveCVar(def) or 0

            local isFirstInPair = (i % 2 == 1)
            local isLastDef = (i == #sliderDefs)

            if isFirstInPair then
                currentSliderRow = GUIFrame:CreateRow(card6.content, 60)
            end

            local slider = GUIFrame:CreateSlider(currentSliderRow, def.label, {
                min = def.min, max = def.max, step = def.step,
                value = currentVal,
                callback = function(val)
                    db[key] = val
                    AU._suppressCVarUpdate = true
                    C_CVar.SetCVar(key, tostring(val))
                    AU._suppressCVarUpdate = false
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
        yOffset = card6:GetNextOffset()
    end

    ----------------------------------------------------------------
    -- Card 7: Map Scale
    ----------------------------------------------------------------
    if mapDB then
        -- Not registered with `manager` — MapScale has its own independent
        -- enable lifecycle (see the module-vs-Automation note above), so this
        -- card must not grey out when "Apply CVars on Login" is off.
        local card7 = GUIFrame:CreateCard(scrollChild, "Map Scale", yOffset)

        local function ApplyMapScale()
            local MS = GetMapScaleModule()
            if MS and MS.ApplyScale then MS:ApplyScale() end
        end

        card7:AddHeaderToggle(mapDB.Enabled ~= false, function(checked)
            mapDB.Enabled = checked
            if checked then KitnEssentials:EnableModule("MapScale")
            else KitnEssentials:DisableModule("MapScale") end
            ApplyMapScale()
            KE:Print("Map Scale: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
        end)
        yOffset = card7:GetNextOffset()

        if mapDB.Enabled ~= false then
            -- Not a CVar: this drives WorldMapFrame:SetScale() directly, unlike
            -- every other slider on this page.
            local row7b = GUIFrame:CreateRow(card7.content, Theme.rowHeightLast)
            local mapScaleSlider = GUIFrame:CreateSlider(row7b, "Scale", {
                min = 0.5, max = 2.0, step = 0.05,
                value = mapDB.Scale or 1.2,
                callback = function(val)
                    mapDB.Scale = val
                    ApplyMapScale()
                end,
            })
            row7b:AddWidget(mapScaleSlider, 1)
            card7:AddRow(row7b, Theme.rowHeightLast, 0)

            yOffset = card7:GetNextOffset()
        end
    end

    RefreshStates()
    return yOffset
end)

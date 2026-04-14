-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-BossDebuffs.lua                                     ║
-- ║  GUI: Boss Debuffs                                       ║
-- ║  Purpose: Configuration panel for the BossDebuffs module.║
-- ║  Credit: Bitebtw                                         ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame     = KE.GUIFrame
local Theme        = KE.Theme
local table_insert = table.insert

-- Encounter ID reference data (update each tier)
local ENCOUNTER_DATA = {
    { header = "Midnight",           bosses = { { "Lu'ashai", 3454 }, { "Thorm'belan", 3459 }, { "Predaxas", 3431 }, { "Cragpine", 3436 } } },
    { header = "The Dreamrift",      bosses = { { "Chimaerus the Undreamt God", 3306 } } },
    { header = "The Voidspire",      bosses = { { "Imperator Averzian", 3176 }, { "Vorasius", 3177 }, { "Fallen-King Salhadaar", 3179 }, { "Vaelgor & Ezzorak", 3178 }, { "Lightblinded Vanguard", 3180 }, { "Crown of the Cosmos", 3181 } } },
    { header = "March on Quel'Danas", bosses = { { "Belo'ren, Child of Al'ar", 3182 }, { "Midnight Falls", 3183 } } },
}

GUIFrame:RegisterContent("BossDebuffs", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.BossDebuffs
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return yOffset + errorCard:GetContentHeight() + Theme.paddingMedium
    end

    local allWidgets = {}

    local function ApplySettings()
        local mod = KitnEssentials and KitnEssentials:GetModule("BossDebuffs", true)
        if mod and mod.ApplySettings then mod:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        local mod = KitnEssentials:GetModule("BossDebuffs", true)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("BossDebuffs")
        else
            KitnEssentials:DisableModule("BossDebuffs")
        end
    end

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then widget:SetEnabled(mainEnabled) end
        end
    end

    ---------------------------------------------------------------------------------
    -- Card 1: Boss Debuffs (Enable)
    ---------------------------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Boss Debuffs", yOffset)

    local row1a = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1a,
        "Enable Boss Debuffs", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
        end,
        true, "Boss Debuffs", "On", "Off"
    )
    row1a:AddWidget(enableCheck, 1)
    card1:AddRow(row1a, 36)

    card1:AddLabel("|cff888888Shows large icons for debuffs applied to you by bosses and mobs. Filters out self-cast debuffs. Duration spiral and text may be unavailable due to Blizzard restrictions.|r")

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 2: Visibility
    ---------------------------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Visibility", yOffset)
    table_insert(allWidgets, card2)

    -- VisibilityMode dropdown
    local visiModeOptions = {
        { key = "boss",     text = "Boss Encounters" },
        { key = "instance", text = "Instance Combat"  },
        { key = "always",   text = "Always in Combat"  },
    }

    local row2a = GUIFrame:CreateRow(card2.content, 40)
    local visiDropdown = GUIFrame:CreateDropdown(row2a, "Visibility Mode", visiModeOptions,
        db.VisibilityMode or "boss", 70,
        function(key)
            db.VisibilityMode = key
            ApplySettings()
        end)
    row2a:AddWidget(visiDropdown, 1)
    table_insert(allWidgets, visiDropdown)
    card2:AddRow(row2a, 40)

    card2:AddLabel("|cff888888Encounter Blacklist — comma-separated IDs to exclude (boss mode only). Hover for IDs.|r")

    -- Encounter Blacklist edit box
    local row2c = GUIFrame:CreateRow(card2.content, 40)
    local blacklistUpdating = false
    local blacklistBox = GUIFrame:CreateEditBox(row2c, "e.g. 3306,3454",
        db.EncounterBlacklist or "",
        function(text)
            if blacklistUpdating then return end
            -- Clean input: keep only valid numeric IDs
            local valid = {}
            for entry in text:gmatch("[^,]+") do
                local trimmed = entry:match("^%s*(.-)%s*$")
                if trimmed and trimmed ~= "" then
                    if tonumber(trimmed) then
                        valid[#valid + 1] = trimmed
                    else
                        KE:Print("Boss Debuffs: Ignored invalid entry '" .. trimmed .. "' — use numeric encounter IDs only.")
                    end
                end
            end
            local cleaned = table.concat(valid, ",")
            db.EncounterBlacklist = cleaned
            -- Update edit box to show cleaned text
            blacklistUpdating = true
            if blacklistBox then blacklistBox:SetValue(cleaned) end
            blacklistUpdating = false
            local mod = KitnEssentials and KitnEssentials:GetModule("BossDebuffs", true)
            if mod and mod.RefreshBlacklist then mod:RefreshBlacklist() end
        end)
    row2c:AddWidget(blacklistBox, 1)
    table_insert(allWidgets, blacklistBox)
    card2:AddRow(row2c, 40)

    -- Encounter ID tooltip — hook into the editBox's existing OnEnter
    local tooltipTarget = blacklistBox.editBox
    if tooltipTarget then
        tooltipTarget:HookScript("OnEnter", function(self)
            local a = Theme.accent
            local ar, ag, ab = a[1], a[2], a[3]
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Encounter IDs", 1, 0.82, 0)
            for _, raid in ipairs(ENCOUNTER_DATA) do
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(raid.header, ar, ag, ab)
                for _, boss in ipairs(raid.bosses) do
                    GameTooltip:AddDoubleLine(boss[1], tostring(boss[2]), 1,1,1, 0.7,0.7,0.7)
                end
            end
            GameTooltip:Show()
        end)
        tooltipTarget:HookScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 3: Display
    ---------------------------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Display", yOffset)
    table_insert(allWidgets, card3)

    -- MaxDebuffs and IconSize on one row
    local row3a = GUIFrame:CreateRow(card3.content, 40)
    local maxSlider = GUIFrame:CreateSlider(row3a, "Max Icons", 1, 5, 1,
        db.MaxDebuffs or 3, 60,
        function(val)
            db.MaxDebuffs = val
            ApplySettings()
        end)
    row3a:AddWidget(maxSlider, 0.5)
    table_insert(allWidgets, maxSlider)

    local sizeSlider = GUIFrame:CreateSlider(row3a, "Icon Size", 48, 128, 1,
        db.IconSize or 32, 60,
        function(val)
            db.IconSize = val
            ApplySettings()
        end)
    row3a:AddWidget(sizeSlider, 0.5)
    table_insert(allWidgets, sizeSlider)
    card3:AddRow(row3a, 40)

    -- Spacing and GrowthDirection on one row
    local row3b = GUIFrame:CreateRow(card3.content, 40)
    local spacingSlider = GUIFrame:CreateSlider(row3b, "Spacing", 0, 20, 1,
        db.Spacing or 4, 60,
        function(val)
            db.Spacing = val
            ApplySettings()
        end)
    row3b:AddWidget(spacingSlider, 0.5)
    table_insert(allWidgets, spacingSlider)

    local growthOptions = {
        { key = "RIGHT", text = "Right" },
        { key = "LEFT",  text = "Left"  },
        { key = "UP",    text = "Up"    },
        { key = "DOWN",  text = "Down"  },
    }
    local growthDropdown = GUIFrame:CreateDropdown(row3b, "Growth Direction", growthOptions,
        db.GrowthDirection or "RIGHT", 45,
        function(key)
            db.GrowthDirection = key
            ApplySettings()
        end)
    row3b:AddWidget(growthDropdown, 0.5)
    table_insert(allWidgets, growthDropdown)
    card3:AddRow(row3b, 40)

    -- ShowDuration and ShowTooltip toggles
    local row3c = GUIFrame:CreateRow(card3.content, 36)
    local durationCheck = GUIFrame:CreateCheckbox(row3c,
        "Show Duration Spiral", db.ShowDuration ~= false,
        function(checked)
            db.ShowDuration = checked
            ApplySettings()
        end
    )
    row3c:AddWidget(durationCheck, 0.5)
    table_insert(allWidgets, durationCheck)

    local tooltipCheck = GUIFrame:CreateCheckbox(row3c,
        "Show Mouseover Tooltip", db.ShowTooltip ~= false,
        function(checked)
            db.ShowTooltip = checked
            ApplySettings()
        end
    )
    row3c:AddWidget(tooltipCheck, 0.5)
    table_insert(allWidgets, tooltipCheck)
    card3:AddRow(row3c, 36)

    -- ShowDurationText toggle
    local row3d = GUIFrame:CreateRow(card3.content, 36)
    local durationTextCheck = GUIFrame:CreateCheckbox(row3d,
        "Show Duration Text", db.ShowDurationText ~= false,
        function(checked)
            db.ShowDurationText = checked
            ApplySettings()
        end
    )
    row3d:AddWidget(durationTextCheck, 1)
    table_insert(allWidgets, durationTextCheck)
    card3:AddRow(row3d, 36)

    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 4: Position Settings
    ---------------------------------------------------------------------------------
    local card4, newOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            anchorFrameType = "anchorFrameType",
            anchorFrameFrame = "ParentFrame",
            selfPoint   = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset     = "XOffset",
            yOffset     = "YOffset",
            strata      = "Strata",
        },
        showAnchorFrameType = true,
        showStrata          = true,
        onChangeCallback    = ApplySettings,
    })

    if card4.positionWidgets then
        for _, widget in ipairs(card4.positionWidgets) do
            table_insert(allWidgets, widget)
        end
    end
    table_insert(allWidgets, card4)
    yOffset = newOffset

    ---------------------------------------------------------------------------------
    -- Final widget state sync
    ---------------------------------------------------------------------------------
    UpdateAllWidgetStates()
    yOffset = yOffset - (Theme.paddingSmall * 3)
    return yOffset
end)

-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-BossDebuffs.lua                                     ║
-- ║  GUI: Boss Debuffs                                       ║
-- ║  Purpose: Configuration panel for the BossDebuffs module.║                                       
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme    = KE.Theme

-- Encounter ID reference data (update each tier)
local ENCOUNTER_DATA = {
    { header = "Midnight",            bosses = { { "Lu'ashai", 3454 }, { "Thorm'belan", 3459 }, { "Predaxas", 3431 }, { "Cragpine", 3436 } } },
    { header = "The Dreamrift",       bosses = { { "Chimaerus the Undreamt God", 3306 } } },
    { header = "The Voidspire",       bosses = { { "Imperator Averzian", 3176 }, { "Vorasius", 3177 }, { "Fallen-King Salhadaar", 3179 }, { "Vaelgor & Ezzorak", 3178 }, { "Lightblinded Vanguard", 3180 }, { "Crown of the Cosmos", 3181 } } },
    { header = "March on Quel'Danas", bosses = { { "Belo'ren, Child of Al'ar", 3182 }, { "Midnight Falls", 3183 } } },
}

GUIFrame:RegisterContent("BossDebuffs", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.BossDebuffs
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local manager = GUIFrame:CreateWidgetStateManager()

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

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Boss Debuffs", yOffset)

    local row1a = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1a, "Enable Boss Debuffs", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Boss Debuffs",
        msgOn = "On",
        msgOff = "Off",
    })
    row1a:AddWidget(enableCheck, 1)
    card1:AddRow(row1a, Theme.rowHeight)

    local noteRow = GUIFrame:CreateRow(card1.content, 65)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Shows large icons for debuffs applied to you by bosses and mobs.\n" ..
        KE:ColorTextByTheme("-") .. " Filters out self-cast debuffs.\n" ..
        KE:ColorTextByTheme("-") .. " Duration spiral and text may be unavailable due to Blizzard restrictions.",
        65, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, 65, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Visibility
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Visibility", yOffset)
    manager:Register(card2, "all")

    local row2a = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local visiDropdown = GUIFrame:CreateDropdown(row2a, "Visibility Mode", {
        options = {
            { key = "boss",     text = "Boss Encounters" },
            { key = "instance", text = "Instance Combat" },
            { key = "always",   text = "Always in Combat" },
        },
        value = db.VisibilityMode or "boss",
        callback = function(key) db.VisibilityMode = key; ApplySettings() end,
    })
    row2a:AddWidget(visiDropdown, 1)
    manager:Register(visiDropdown, "all")
    card2:AddRow(row2a, Theme.rowHeight)

    local rowBlacklistNote = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local blacklistNote = GUIFrame:CreateText(rowBlacklistNote,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Encounter Blacklist — comma-separated IDs to exclude (boss mode only). Hover for IDs.",
        Theme.rowHeight, "hide")
    rowBlacklistNote:AddWidget(blacklistNote, 1)
    manager:Register(blacklistNote, "all")
    card2:AddRow(rowBlacklistNote, Theme.rowHeight)

    local row2c = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local blacklistUpdating = false
    local blacklistBox
    blacklistBox = GUIFrame:CreateEditBox(row2c, "e.g. 3306,3454", {
        value = db.EncounterBlacklist or "",
        callback = function(text)
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
            blacklistUpdating = true
            if blacklistBox then blacklistBox:SetValue(cleaned) end
            blacklistUpdating = false
            local mod = KitnEssentials and KitnEssentials:GetModule("BossDebuffs", true)
            if mod and mod.RefreshBlacklist then mod:RefreshBlacklist() end
        end,
    })
    row2c:AddWidget(blacklistBox, 1)
    manager:Register(blacklistBox, "all")
    card2:AddRow(row2c, Theme.rowHeightLast, 0)

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
                    GameTooltip:AddDoubleLine(tostring(boss[1]), tostring(boss[2]), 1, 1, 1, 0.7, 0.7, 0.7)
                end
            end
            GameTooltip:Show()
        end)
        tooltipTarget:HookScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Display
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Display", yOffset)
    manager:Register(card3, "all")

    local row3a = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local maxSlider = GUIFrame:CreateSlider(row3a, "Max Icons", {
        min = 1, max = 5, step = 1,
        value = db.MaxDebuffs or 3,
        callback = function(val) db.MaxDebuffs = val; ApplySettings() end,
    })
    row3a:AddWidget(maxSlider, 0.5)
    manager:Register(maxSlider, "all")

    local sizeSlider = GUIFrame:CreateSlider(row3a, "Icon Size", {
        min = 48, max = 128, step = 1,
        value = db.IconSize or 32,
        callback = function(val) db.IconSize = val; ApplySettings() end,
    })
    row3a:AddWidget(sizeSlider, 0.5)
    manager:Register(sizeSlider, "all")
    card3:AddRow(row3a, Theme.rowHeight)

    local row3b = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local spacingSlider = GUIFrame:CreateSlider(row3b, "Spacing", {
        min = 0, max = 20, step = 1,
        value = db.Spacing or 4,
        callback = function(val) db.Spacing = val; ApplySettings() end,
    })
    row3b:AddWidget(spacingSlider, 0.5)
    manager:Register(spacingSlider, "all")

    local growthDropdown = GUIFrame:CreateDropdown(row3b, "Growth Direction", {
        options = {
            { key = "RIGHT", text = "Right" },
            { key = "LEFT",  text = "Left"  },
            { key = "UP",    text = "Up"    },
            { key = "DOWN",  text = "Down"  },
        },
        value = db.GrowthDirection or "RIGHT",
        callback = function(key) db.GrowthDirection = key; ApplySettings() end,
    })
    row3b:AddWidget(growthDropdown, 0.5)
    manager:Register(growthDropdown, "all")
    card3:AddRow(row3b, Theme.rowHeight)

    local row3bsep = GUIFrame:CreateRow(card3.content, Theme.rowHeightSeparator)
    local sep3b = GUIFrame:CreateSeparator(row3bsep)
    row3bsep:AddWidget(sep3b, 1)
    manager:Register(sep3b, "all")
    card3:AddRow(row3bsep, Theme.rowHeightSeparator)

    local row3c = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local durationCheck = GUIFrame:CreateCheckbox(row3c, "Show Duration Spiral", {
        value = db.ShowDuration ~= false,
        callback = function(checked) db.ShowDuration = checked; ApplySettings() end,
    })
    row3c:AddWidget(durationCheck, 1/3)
    manager:Register(durationCheck, "all")

    local tooltipCheck = GUIFrame:CreateCheckbox(row3c, "Show Mouseover Tooltip", {
        value = db.ShowTooltip ~= false,
        callback = function(checked) db.ShowTooltip = checked; ApplySettings() end,
    })
    row3c:AddWidget(tooltipCheck, 1/3)
    manager:Register(tooltipCheck, "all")

    local durationTextCheck = GUIFrame:CreateCheckbox(row3c, "Show Duration Text", {
        value = db.ShowDurationText ~= false,
        callback = function(checked) db.ShowDurationText = checked; ApplySettings() end,
    })
    row3c:AddWidget(durationTextCheck, 1/3)
    manager:Register(durationTextCheck, "all")
    card3:AddRow(row3c, Theme.rowHeightLast, 0)

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Position Settings
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
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

    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    manager:Register(posCard, "all")
    yOffset = posOffset

    RefreshStates()
    return yOffset
end)

-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-SpellAlerts.lua                                     ║
-- ║  GUI: Spell Alert Opacity                                ║
-- ║  Purpose: Configuration panel for the SpellAlerts module.║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local table_insert = table.insert
local ipairs = ipairs
local pcall = pcall
local tonumber = tonumber
local math_floor = math.floor
local tostring = tostring

local GetSpecializationInfo = GetSpecializationInfo

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("SpellAlerts", true)
    end
    return nil
end

GUIFrame:RegisterContent("SpellAlerts", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.SpellAlerts
    if not db then return yOffset end

    local SA = GetModule()
    local allWidgets = {}

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("SpellAlerts")
        else
            KitnEssentials:DisableModule("SpellAlerts")
        end
    end

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then
                widget:SetEnabled(mainEnabled)
            end
        end
    end

    ---------------------------------------------------------------------------------
    -- Card 1: Enable
    ---------------------------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Spell Alert Opacity", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 40)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Spell Alert Opacity", db.Enabled ~= false,
        function(checked)
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
        end,
        true, "Spell Alert Opacity", "On", "Off")
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, 40)

    local noteHeight = 40
    local noteRow = GUIFrame:CreateRow(card1.content, noteHeight)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Toggles Blizzard's spell activation overlay (proc flashes) per spec.",
        noteHeight, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, noteHeight)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 2: Per-spec toggles
    ---------------------------------------------------------------------------------
    local numSpecs = _G.GetNumSpecializations and _G.GetNumSpecializations() or 0
    if numSpecs > 0 then
        local card2 = GUIFrame:CreateCard(scrollChild, "Enable Alerts per Spec", yOffset)
        table_insert(allWidgets, card2)

        if not db.EnabledSpecs then
            db.EnabledSpecs = {}
        end

        -- All specs on a single horizontal row with the spec icon inline before
        -- the name. For 3-spec classes that's 1x3, 2-spec is 1x2, druid is 1x4.
        -- We post-shift the label and toggle within each cell for some
        -- breathing room: icon nudged right, toggle dropped lower below the
        -- label so the spec name and the checkbox aren't crowded together.
        local LABEL_INDENT = 8   -- horizontal nudge of icon+name
        local TOGGLE_GAP   = 18  -- y-offset of toggle below row top (default 14)
        local specRow = GUIFrame:CreateRow(card2.content, 40)
        for i = 1, numSpecs do
            local _, specName, _, specIcon = GetSpecializationInfo(i)
            if specName then
                local label = specName
                if specIcon then
                    label = "|T" .. specIcon .. ":16:16:0:0:64:64:5:59:5:59|t " .. specName
                end
                local current = db.EnabledSpecs[i] ~= false  -- default ON
                local specCheck = GUIFrame:CreateCheckbox(specRow, label, current,
                    function(checked)
                        db.EnabledSpecs[i] = checked
                        if SA and SA.ApplyForCurrentSpec then
                            SA:ApplyForCurrentSpec()
                        end
                    end,
                    true, specName, "Show", "Hide")
                if specCheck.label then
                    specCheck.label:ClearAllPoints()
                    specCheck.label:SetPoint("TOPLEFT", specCheck, "TOPLEFT", LABEL_INDENT, 1)
                end
                if specCheck.toggle then
                    specCheck.toggle:ClearAllPoints()
                    specCheck.toggle:SetPoint("TOPLEFT", specCheck, "TOPLEFT", LABEL_INDENT, -TOGGLE_GAP)
                end
                specRow:AddWidget(specCheck, 1 / numSpecs)
                table_insert(allWidgets, specCheck)
            end
        end
        card2:AddRow(specRow, 40)

        yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall
    end

    ---------------------------------------------------------------------------------
    -- Card 3: Spell Alert Opacity
    ---------------------------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Opacity", yOffset)
    table_insert(allWidgets, card3)

    local currentOpacity = tonumber(C_CVar.GetCVar("spellActivationOverlayOpacity")) or 0.65
    local row3 = GUIFrame:CreateRow(card3.content, 40)
    local opacitySlider = GUIFrame:CreateSlider(row3, "Opacity", 0, 100, 5,
        math_floor(currentOpacity * 100), nil,
        function(val)
            pcall(C_CVar.SetCVar, "spellActivationOverlayOpacity", tostring(val / 100))
        end)
    row3:AddWidget(opacitySlider, 1)
    table_insert(allWidgets, opacitySlider)
    card3:AddRow(row3, 40)

    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    UpdateAllWidgetStates()
    yOffset = yOffset - Theme.paddingSmall
    return yOffset
end)

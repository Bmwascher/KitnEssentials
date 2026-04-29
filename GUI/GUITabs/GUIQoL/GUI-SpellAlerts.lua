-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-SpellAlerts.lua                                     ║
-- ║  GUI: Spell Alert Opacity                                ║
-- ║  Purpose: Configuration panel for the SpellAlerts module.║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local pcall = pcall
local tonumber = tonumber
local tostring = tostring
local math_floor = math.floor

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
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("SpellAlerts")
        else
            KitnEssentials:DisableModule("SpellAlerts")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Spell Alert Opacity", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Spell Alert Opacity", {
        value = db.Enabled ~= false,
        callback = function(checked)
            ApplyModuleState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Spell Alert Opacity",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, Theme.rowHeight)

    local noteRow = GUIFrame:CreateRow(card1.content, 40)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Toggles Blizzard's spell activation overlay (proc flashes) per spec.",
        40, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, 40, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Per-spec toggles
    ----------------------------------------------------------------
    local numSpecs = _G.GetNumSpecializations and _G.GetNumSpecializations() or 0
    if numSpecs > 0 then
        local card2 = GUIFrame:CreateCard(scrollChild, "Enable Alerts per Spec", yOffset)
        manager:Register(card2, "all")

        if not db.EnabledSpecs then db.EnabledSpecs = {} end

        -- Single horizontal row: spec icon + name on top, toggle below.
        -- Manual re-anchoring of checkbox internals for breathing room.
        local LABEL_INDENT = 8
        local TOGGLE_GAP = 18
        local specRow = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
        for i = 1, numSpecs do
            local _, specName, _, specIcon = GetSpecializationInfo(i)
            if specName then
                local label = specName
                if specIcon then
                    label = "|T" .. specIcon .. ":16:16:0:0:64:64:5:59:5:59|t " .. specName
                end
                local current = db.EnabledSpecs[i] ~= false  -- default ON
                local specCheck = GUIFrame:CreateCheckbox(specRow, label, {
                    value = current,
                    callback = function(checked)
                        db.EnabledSpecs[i] = checked
                        if SA and SA.ApplyForCurrentSpec then
                            SA:ApplyForCurrentSpec()
                        end
                    end,
                    msgPopup = true,
                    msgText = specName,
                    msgOn = "Show",
                    msgOff = "Hide",
                })
                if specCheck.label then
                    specCheck.label:ClearAllPoints()
                    specCheck.label:SetPoint("TOPLEFT", specCheck, "TOPLEFT", LABEL_INDENT, 1)
                end
                if specCheck.toggle then
                    specCheck.toggle:ClearAllPoints()
                    specCheck.toggle:SetPoint("TOPLEFT", specCheck, "TOPLEFT", LABEL_INDENT, -TOGGLE_GAP)
                end
                specRow:AddWidget(specCheck, 1 / numSpecs)
                manager:Register(specCheck, "all")
            end
        end
        card2:AddRow(specRow, Theme.rowHeightLast, 0)

        yOffset = card2:GetNextOffset()
    end

    ----------------------------------------------------------------
    -- Card 3: Opacity (CVar slider)
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Opacity", yOffset)
    manager:Register(card3, "all")

    local currentOpacity = tonumber(C_CVar.GetCVar("spellActivationOverlayOpacity")) or 0.65
    local row3 = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local opacitySlider = GUIFrame:CreateSlider(row3, "Opacity", {
        min = 0, max = 100, step = 5,
        value = math_floor(currentOpacity * 100),
        callback = function(val)
            pcall(C_CVar.SetCVar, "spellActivationOverlayOpacity", tostring(val / 100))
        end,
    })
    row3:AddWidget(opacitySlider, 1)
    manager:Register(opacitySlider, "all")
    card3:AddRow(row3, Theme.rowHeightLast, 0)

    yOffset = card3:GetNextOffset()

    RefreshStates()
    return yOffset
end)

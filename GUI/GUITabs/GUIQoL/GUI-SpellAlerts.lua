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

local GetNumClasses = GetNumClasses
local GetSpecializationInfoForClassID = GetSpecializationInfoForClassID
local C_CreatureInfo = C_CreatureInfo
local RAID_CLASS_COLORS = RAID_CLASS_COLORS

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
    -- Card 2: Enable Alerts per Spec (all classes, 4-column grid)
    ----------------------------------------------------------------
    if not db.EnabledSpecs then db.EnabledSpecs = {} end

    local card2 = GUIFrame:CreateCard(scrollChild, "Enable Alerts per Spec", yOffset)
    manager:Register(card2, "all")

    local COLUMNS = 4
    local numClasses = GetNumClasses and GetNumClasses() or 0

    for classID = 1, numClasses do
        local classInfo = C_CreatureInfo and C_CreatureInfo.GetClassInfo(classID)
        local className = classInfo and classInfo.className
        local classFile = classInfo and classInfo.classFile

        if className then
            local color = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
            local classHex = (color and color.colorStr) and ("|c" .. color.colorStr) or "|cffffffff"
            card2:AddLabel(classHex .. className .. "|r")

            -- Collect this class's specs
            local specs = {}
            for specNum = 1, 4 do
                local specID, specName, _, specIcon = GetSpecializationInfoForClassID(classID, specNum)
                if specID and specName then
                    local iconStr = specIcon and ("|T" .. specIcon .. ":16:16:0:0:64:64:5:59:5:59|t ") or ""
                    specs[#specs + 1] = {
                        id    = specID,
                        name  = specName,
                        label = iconStr .. classHex .. specName .. "|r",
                    }
                end
            end

            -- Lay specs out in rows of COLUMNS
            local idx = 1
            while idx <= #specs do
                local specRow = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
                for _ = 1, COLUMNS do
                    local spec = specs[idx]
                    if spec then
                        local sID = spec.id
                        local current = db.EnabledSpecs[sID] ~= false  -- default ON
                        local specCheck = GUIFrame:CreateCheckbox(specRow, spec.label, {
                            value = current,
                            callback = function(checked)
                                -- Store explicit false for opt-out; nil for default-on
                                db.EnabledSpecs[sID] = checked and nil or false
                                if SA and SA.ApplyForCurrentSpec then
                                    SA:ApplyForCurrentSpec()
                                end
                            end,
                            msgPopup = true,
                            msgText  = spec.name,
                            msgOn    = "Show",
                            msgOff   = "Hide",
                        })
                        specRow:AddWidget(specCheck, 1 / COLUMNS)
                        manager:Register(specCheck, "all")
                    end
                    idx = idx + 1
                end
                card2:AddRow(specRow, Theme.rowHeight)
            end
        end
    end

    yOffset = card2:GetNextOffset()

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

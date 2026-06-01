-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-DispelGlow.lua                                      ║
-- ║  GUI: Dispel Glow (ElvUI-gated)                          ║
-- ║  Enable + Note, Border thickness, and a cross-linked      ║
-- ║  Dispel Type Colors card (shared with Aura Debuffs).      ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    return KitnEssentials and KitnEssentials:GetModule("DispelGlow", true)
end

GUIFrame:RegisterContent("DispelGlow", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.DispelGlow
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available.")
        return errorCard:GetNextOffset()
    end

    local hasElv = _G.ElvUI ~= nil

    local manager = GUIFrame:CreateWidgetStateManager()
    -- The shared palette card edits AuraDebuffs.DispelColors, which is useful
    -- even when the glow is off (it also drives the Aura Debuffs highlight),
    -- so register it under an always-true group rather than the master enable.
    manager:SetCondition("paletteAlways", function() return true end)

    local function RefreshStates()
        manager:UpdateAll(db.Enabled == true)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable + Note
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Dispel Glow", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Dispel Glow", {
        value = db.Enabled == true,
        callback = function(checked)
            db.Enabled = checked
            local mod = GetModule()
            if mod then
                if checked then KitnEssentials:EnableModule("DispelGlow")
                else KitnEssentials:DisableModule("DispelGlow") end
            end
            RefreshStates()
        end,
        msgPopup = true,
        msgText  = "Dispel Glow",
        msgOn    = "On",
        msgOff   = "Off",
    })
    -- No ElvUI → the module can't start; gray the toggle so it reads as
    -- unavailable rather than broken.
    if not hasElv and enableCheck.SetEnabled then enableCheck:SetEnabled(false) end
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, Theme.rowHeight)

    local noteHeight = 90
    local noteBody = hasElv
        and (KE:ColorTextByTheme("-") .. " Highlights ElvUI party/raid/tank frames when a dispellable " ..
             "debuff is present, including private auras (dungeon-mechanic debuffs the normal aura " ..
             "API can't see).\n" ..
             KE:ColorTextByTheme("-") .. " Uses Blizzard's native dispel overlay anchored to each frame.\n" ..
             KE:ColorTextByTheme("-") .. " Border color uses the Dispel Type Colors below (shared with Aura Debuffs).")
        or  (KE:ColorTextByTheme("-") .. " Dispel Glow requires ElvUI. Install/enable ElvUI to use this feature.")

    local noteRow = GUIFrame:CreateRow(card1.content, noteHeight)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        noteBody,
        noteHeight, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, noteHeight, 0)

    yOffset = card1:GetNextOffset()

    -- ElvUI absent: nothing else to configure (the border + palette only
    -- affect the glow). The palette stays editable from the Aura Debuffs page.
    if not hasElv then
        RefreshStates()
        return yOffset
    end

    ----------------------------------------------------------------
    -- Card 2: Border (greys out with the module enable)
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Border", yOffset)
    manager:Register(card2, "all")

    local row2 = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local borderSlider = GUIFrame:CreateSlider(row2, "Border Thickness (px)", {
        min = 1, max = 4, step = 1,
        value = db.BorderSize or 2,
        callback = function(val)
            db.BorderSize = val
            local mod = GetModule()
            if mod and mod.ApplySettings then mod:ApplySettings() end
        end,
    })
    row2:AddWidget(borderSlider, 1)
    manager:Register(borderSlider, "all")
    card2:AddRow(row2, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Dispel Type Colors (shared with Aura Debuffs)
    -- Bound to the AuraDebuffs profile so both consumers stay in sync;
    -- always editable (paletteAlways group) regardless of the glow toggle.
    ----------------------------------------------------------------
    local adb = KE.db.profile.AuraDebuffs
    if adb then
        yOffset = GUIFrame:CreateDispelTypeColorsCard(scrollChild, yOffset, {
            db         = adb,
            manager    = manager,
            stateGroup = "paletteAlways",
        })
    end

    RefreshStates()
    return yOffset
end)

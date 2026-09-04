-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-Optimize.lua                                        ║
-- ║  GUI: CVars (Optimize Panel)                             ║
-- ║  Purpose: Configuration panel for the Optimize module.   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local CreateFrame = CreateFrame
local C_Timer = C_Timer

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("Optimize", true)
    end
    return nil
end

------------------------------------------------------------------------
-- Persistent dirty flag — survives content rebuilds, clears on reload prompt
------------------------------------------------------------------------
local optimizeDirty = false
local hookInstalled = false

-- The preset the user is previewing: "maxfps", "balanced" or nil. File-local so
-- it survives a content rebuild inside one session. Nil until a preset button is
-- pressed, which is what keeps Apply All hidden and the Recommended column
-- blank on a first visit.
local selectedPreset

local function InstallCloseHook()
    if hookInstalled then return end
    C_Timer.After(0, function()
        local frame = GUIFrame.mainFrame
        if not frame then return end
        frame:HookScript("OnHide", function()
            if optimizeDirty then
                optimizeDirty = false
                StaticPopup_Show("KE_OPTIMIZE_RELOAD")
            end
        end)
        hookInstalled = true
    end)
end

GUIFrame:RegisterContent("Optimize", function(scrollChild, yOffset)
    local OPT = GetModule()
    if not OPT then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Optimize module not available")
        return errorCard:GetNextOffset()
    end

    InstallCloseHook()

    local function MarkDirty()
        optimizeDirty = true
    end

    ----------------------------------------------------------------
    -- Card 1: Presets
    ----------------------------------------------------------------
    -- Reopen in the state the module remembers: a preset that was actually
    -- APPLIED comes back selected after a reload. A preview-only selection
    -- deliberately does not -- nothing was applied, so nothing is owed.
    selectedPreset = selectedPreset or OPT:GetActivePreset()

    local card1 = GUIFrame:CreateCard(scrollChild, "Presets", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)

    local maxFpsBtn, balancedBtn, applyAllBtn

    -- Selection reads as a fill inside the button, the same recipe the sidebar
    -- uses for its selected row, so it follows a theme change on its own.
    local function EnsureSelectedFill(btn)
        if not btn.keSelectedFill then
            local fill = btn:CreateTexture(nil, "ARTWORK", nil, 1)
            fill:SetPoint("TOPLEFT", 1, -1)
            fill:SetPoint("BOTTOMRIGHT", -1, 1)
            fill:SetColorTexture(Theme.selectedBg[1], Theme.selectedBg[2],
                Theme.selectedBg[3], Theme.selectedBg[4])
            btn.keSelectedFill = fill
        end
        return btn.keSelectedFill
    end

    local function PaintSelection()
        EnsureSelectedFill(maxFpsBtn):SetShown(selectedPreset == "maxfps")
        EnsureSelectedFill(balancedBtn):SetShown(selectedPreset == "balanced")
        applyAllBtn:SetShown(selectedPreset ~= nil)
    end

    -- The preset buttons SELECT, they do not apply. Choosing one loads that
    -- preset's values into the Recommended column below as a preview; Apply All
    -- is what sets them. The rebuild is not optional -- the Mythic+ card below
    -- exists only under Balanced.
    maxFpsBtn = GUIFrame:CreateButton(row1, "Max FPS", {
        width = 120,
        height = 28,
        tooltip = "Preview this preset's values below, then use Apply All.",
        callback = function()
            selectedPreset = "maxfps"
            GUIFrame:RefreshContent()
        end,
    })
    row1:AddWidget(maxFpsBtn, 1 / 4)

    balancedBtn = GUIFrame:CreateButton(row1, "Balanced", {
        width = 120,
        height = 28,
        tooltip = "Preview this preset's values below, then use Apply All.",
        callback = function()
            selectedPreset = "balanced"
            GUIFrame:RefreshContent()
        end,
    })
    row1:AddWidget(balancedBtn, 1 / 4)

    applyAllBtn = GUIFrame:CreateButton(row1, "Apply All", {
        width = 120,
        height = 28,
        tooltip = "Apply every previewed value.",
        callback = function()
            if selectedPreset == "maxfps" then
                OPT:MaxFPS()
            else
                OPT:OptimizeAll()
                -- The Mythic+ drop is part of what Balanced means, so it comes
                -- on with the preset.
                OPT:SetMythicViewDistanceEnabled(true)
            end
            MarkDirty()
            GUIFrame:RefreshContent()
        end,
    })
    row1:AddWidget(applyAllBtn, 1 / 4)

    local revertBtn = GUIFrame:CreateButton(row1, "Revert All", {
        width = 120,
        height = 28,
        callback = function()
            OPT:RevertAll()   -- also clears the recorded preset
            selectedPreset = nil
            MarkDirty()
            GUIFrame:RefreshContent()
        end,
    })
    row1:AddWidget(revertBtn, 1 / 4)

    card1:AddRow(row1, Theme.rowHeightLast)
    PaintSelection()

    card1:AddLabel("\226\128\162 " .. KE:ColorTextByTheme("Max FPS") ..
        " gives the highest FPS without sacrificing visual clarity in raids, dungeons and outdoors.")
    card1:AddLabel("\226\128\162 " .. KE:ColorTextByTheme("Balanced") ..
        " uses the Raid & BG setting for a more immersive world and outdoor experience, while maximising in-raid performance. There is also a Lower View Distance option for Mythic+ to help FPS in some outdoor dungeons.")
    if not selectedPreset then
        card1:AddLabel("Select a preset above to load its recommended values.")
    end

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Mythic+ (Balanced only)
    ----------------------------------------------------------------
    -- Balanced-gated on purpose: Max FPS already runs View Distance at its
    -- floor, so the toggle would do nothing there.
    if selectedPreset == "balanced" then
        local mvdCard = GUIFrame:CreateCard(scrollChild, "Mythic+", yOffset)
        -- Label ABOVE the toggle. A trailing label measures against the row and
        -- clips into the checkbox.
        mvdCard:AddLabel("Drops View Distance to its floor while inside a Mythic+ dungeon and restores it on exit. Helps FPS in some outdoor dungeons.")
        local mvdRow = GUIFrame:CreateRow(mvdCard.content, Theme.rowHeightLast)
        local mvdToggle = GUIFrame:CreateCheckbox(mvdRow, "Lower View Distance in Mythic+", {
            value = OPT:IsMythicViewDistanceEnabled(),
            callback = function(newState)
                OPT:SetMythicViewDistanceEnabled(newState)
            end,
        })
        mvdRow:AddWidget(mvdToggle, 1)
        mvdCard:AddRow(mvdRow, Theme.rowHeightLast, 0)
        yOffset = mvdCard:GetNextOffset()
    end

    ----------------------------------------------------------------
    -- Helper: column headers row
    ----------------------------------------------------------------
    local function AddColumnHeaders(card)
        local row = GUIFrame:CreateRow(card.content, 20)

        local container = CreateFrame("Frame", nil, row)
        container:SetAllPoints()

        local settingHeader = container:CreateFontString(nil, "OVERLAY")
        settingHeader:SetPoint("LEFT", container, "LEFT", 4, 0)
        settingHeader:SetWidth(150)
        settingHeader:SetJustifyH("LEFT")
        KE:ApplyThemeFont(settingHeader, "normal")
        settingHeader:SetText("Setting")
        settingHeader:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 0.7)

        local currentHeader = container:CreateFontString(nil, "OVERLAY")
        currentHeader:SetPoint("LEFT", settingHeader, "RIGHT", 4, 0)
        currentHeader:SetWidth(90)
        currentHeader:SetJustifyH("LEFT")
        KE:ApplyThemeFont(currentHeader, "normal")
        currentHeader:SetText("Current")
        currentHeader:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 0.7)

        local spacer = container:CreateFontString(nil, "OVERLAY")
        spacer:SetPoint("LEFT", currentHeader, "RIGHT", 2, 0)
        KE:ApplyThemeFont(spacer, "normal")
        spacer:SetText(" ")

        local recHeader = container:CreateFontString(nil, "OVERLAY")
        recHeader:SetPoint("LEFT", spacer, "RIGHT", 2, 0)
        recHeader:SetWidth(90)
        recHeader:SetJustifyH("LEFT")
        KE:ApplyThemeFont(recHeader, "normal")
        recHeader:SetText("Recommended")
        recHeader:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 0.7)

        row:AddWidget(container, 1)
        card:AddRow(row, 20)
    end

    ----------------------------------------------------------------
    -- Helper: bespoke per-CVar status row (Apply/Revert + tooltip)
    ----------------------------------------------------------------
    local function AddCVarRow(card, entry)
        local row = GUIFrame:CreateRow(card.content, 32)

        local container = CreateFrame("Frame", nil, row)
        container:SetAllPoints()

        local nameLabel = container:CreateFontString(nil, "OVERLAY")
        nameLabel:SetPoint("LEFT", container, "LEFT", 4, 0)
        nameLabel:SetWidth(150)
        nameLabel:SetJustifyH("LEFT")
        KE:ApplyThemeFont(nameLabel, "normal")
        nameLabel:SetText(entry.name)
        nameLabel:SetTextColor(Theme.textPrimary[1], Theme.textPrimary[2], Theme.textPrimary[3], 1)

        local currentLabel = container:CreateFontString(nil, "OVERLAY")
        currentLabel:SetPoint("LEFT", nameLabel, "RIGHT", 4, 0)
        currentLabel:SetWidth(90)
        currentLabel:SetJustifyH("LEFT")
        KE:ApplyThemeFont(currentLabel, "normal")

        local optimalLabel = container:CreateFontString(nil, "OVERLAY")
        optimalLabel:SetPoint("LEFT", currentLabel, "RIGHT", 30, 0)

        local arrowTex = "Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\collapse.png"
        local arrowRot = math.pi / 2
        local arrowR, arrowG, arrowB = Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3]

        local arrow1 = container:CreateTexture(nil, "OVERLAY")
        arrow1:SetSize(10, 10)
        arrow1:SetPoint("LEFT", currentLabel, "RIGHT", 0, 0)
        arrow1:SetTexture(arrowTex)
        arrow1:SetRotation(arrowRot)
        arrow1:SetVertexColor(arrowR, arrowG, arrowB, 0.6)

        local arrow2 = container:CreateTexture(nil, "OVERLAY")
        arrow2:SetSize(10, 10)
        arrow2:SetPoint("LEFT", arrow1, "RIGHT", -3, 0)
        arrow2:SetTexture(arrowTex)
        arrow2:SetRotation(arrowRot)
        arrow2:SetVertexColor(arrowR, arrowG, arrowB, 0.6)
        optimalLabel:SetWidth(90)
        optimalLabel:SetJustifyH("LEFT")
        KE:ApplyThemeFont(optimalLabel, "normal")

        local applyBtn = CreateFrame("Button", nil, container, "BackdropTemplate")
        applyBtn:SetSize(50, 20)
        applyBtn:SetPoint("RIGHT", container, "RIGHT", -60, 0)
        applyBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        applyBtn:SetBackdropColor(Theme.bgMedium[1], Theme.bgMedium[2], Theme.bgMedium[3], 1)
        applyBtn:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
        local applyText = applyBtn:CreateFontString(nil, "OVERLAY")
        KE:ApplyThemeFont(applyText, "normal")
        applyText:SetPoint("CENTER")
        applyText:SetText("Apply")
        applyText:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)

        local revertBtnSmall = CreateFrame("Button", nil, container, "BackdropTemplate")
        revertBtnSmall:SetSize(50, 20)
        revertBtnSmall:SetPoint("RIGHT", container, "RIGHT", -4, 0)
        revertBtnSmall:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        revertBtnSmall:SetBackdropColor(Theme.bgMedium[1], Theme.bgMedium[2], Theme.bgMedium[3], 1)
        revertBtnSmall:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
        local revertText = revertBtnSmall:CreateFontString(nil, "OVERLAY")
        KE:ApplyThemeFont(revertText, "normal")
        revertText:SetPoint("CENTER")
        revertText:SetText("Revert")
        revertText:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)

        local optimalStatusLabel = container:CreateFontString(nil, "OVERLAY")
        KE:ApplyThemeFont(optimalStatusLabel, "normal")
        optimalStatusLabel:SetPoint("CENTER", applyBtn, "CENTER", 0, 0)
        optimalStatusLabel:SetText("Optimal")
        optimalStatusLabel:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
        optimalStatusLabel:Hide()

        local function SetupHover(btn)
            btn:SetScript("OnEnter", function(self)
                self:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
            end)
            btn:SetScript("OnLeave", function(self)
                self:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
            end)
        end
        SetupHover(applyBtn)
        SetupHover(revertBtnSmall)

        -- What the selected preset wants for this cvar, or nil while no preset
        -- is selected. Max FPS falls through to the listed optimal for every
        -- cvar it does not override.
        local function PreviewValue()
            if not selectedPreset then return nil end
            if selectedPreset == "maxfps" then
                local v = OPT:GetMaxFPSOverrides()[entry.cvar]
                if v ~= nil then return v end
            end
            return entry.optimal
        end

        local function RefreshRow()
            local current = OPT:GetCurrentValue(entry.cvar) or "?"
            local rec = PreviewValue()
            currentLabel:SetText(OPT:GetValueLabel(entry.cvar, current))

            if rec == nil then
                -- No preset selected: there is nothing to recommend and nothing
                -- for Apply to apply, so the row reads neutral.
                currentLabel:SetTextColor(Theme.textPrimary[1], Theme.textPrimary[2],
                    Theme.textPrimary[3], 1)
                optimalLabel:SetText("-")
                optimalLabel:SetTextColor(0.5, 0.5, 0.5, 1)
                optimalStatusLabel:Hide()
                applyBtn:Show()
                applyBtn:SetAlpha(0.35)
                applyBtn:EnableMouse(false)
            else
                local isOpt = OPT:IsOptimal(entry.cvar, rec)
                if isOpt then
                    currentLabel:SetTextColor(0.3, 1, 0.3, 1)
                else
                    currentLabel:SetTextColor(1, 0.55, 0, 1)
                end
                optimalLabel:SetText(OPT:GetValueLabel(entry.cvar, rec))
                optimalLabel:SetTextColor(0.3, 1, 0.3, 1)
                if isOpt then
                    applyBtn:Hide()
                    optimalStatusLabel:Show()
                else
                    applyBtn:Show()
                    applyBtn:SetAlpha(1)
                    applyBtn:EnableMouse(true)
                    optimalStatusLabel:Hide()
                end
            end

            -- Revert now depends on the backup alone. It used to be hidden
            -- outright on an optimal row with no backup, but "optimal" is a
            -- per-preset answer since this change, so that rule would flick the
            -- button in and out of existence as the user compares presets.
            revertBtnSmall:Show()
            if OPT:HasBackup(entry.cvar) then
                revertBtnSmall:SetAlpha(1)
                revertBtnSmall:EnableMouse(true)
            else
                revertBtnSmall:SetAlpha(0.35)
                revertBtnSmall:EnableMouse(false)
            end
        end

        applyBtn:SetScript("OnClick", function()
            local rec = PreviewValue()
            if rec == nil then return end
            OPT:ApplyCVar(entry.cvar, rec)
            C_Timer.After(0.1, RefreshRow)
            MarkDirty()
        end)

        revertBtnSmall:SetScript("OnClick", function()
            OPT:RevertCVar(entry.cvar)
            C_Timer.After(0.1, RefreshRow)
            MarkDirty()
        end)

        container:EnableMouse(true)
        container:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(entry.name, 1, 0.82, 0, 1)
            GameTooltip:AddLine(" ")
            local cur = OPT:GetCurrentValue(entry.cvar) or "?"
            GameTooltip:AddLine("Current: " .. OPT:GetValueLabel(entry.cvar, cur), 0.7, 0.7, 0.7)
            local recTip = PreviewValue()
            if recTip ~= nil then
                GameTooltip:AddLine("Recommended: " .. OPT:GetValueLabel(entry.cvar, recTip), 0.3, 1, 0.3)
            else
                GameTooltip:AddLine("Select a preset above to load its recommended values.", 0.5, 0.5, 0.5)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("CVar: " .. entry.cvar, 0.5, 0.5, 0.5)
            if entry.desc then
                GameTooltip:AddLine(entry.desc, 0.5, 0.5, 0.5)
            end
            GameTooltip:Show()
        end)
        container:SetScript("OnLeave", function() GameTooltip:Hide() end)

        row:AddWidget(container, 1)
        card:AddRow(row, 32)

        RefreshRow()
    end

    ----------------------------------------------------------------
    -- Cards 2-N: One card per category
    ----------------------------------------------------------------
    for _, cat in ipairs(OPT.Categories) do
        local card = GUIFrame:CreateCard(scrollChild, cat.name, yOffset)
        AddColumnHeaders(card)
        for _, entry in ipairs(cat.cvars) do
            AddCVarRow(card, entry)
        end
        yOffset = card:GetNextOffset()
    end

    return yOffset
end)

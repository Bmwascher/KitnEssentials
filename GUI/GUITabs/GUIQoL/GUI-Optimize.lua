-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local table_insert = table.insert
local ipairs = ipairs
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

------------------------------------------------------------------------
-- Content builder
------------------------------------------------------------------------
GUIFrame:RegisterContent("Optimize", function(scrollChild, yOffset)
    local OPT = GetModule()
    if not OPT then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Optimize module not available")
        return yOffset + errorCard:GetContentHeight() + Theme.paddingMedium
    end

    InstallCloseHook()

    local refreshCallbacks = {}

    local function RefreshAllRows()
        for _, fn in ipairs(refreshCallbacks) do
            fn()
        end
    end

    local function MarkDirty()
        optimizeDirty = true
    end

    --------------------------------------------------------------------------
    -- Card 1: Presets (Optimize All / Revert All)
    --------------------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Presets", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 40)

    local optimizeBtn = GUIFrame:CreateButton(row1, "Optimize All", {
        width = 140,
        height = 28,
        callback = function()
            OPT:OptimizeAll()
            C_Timer.After(0.2, RefreshAllRows)
            MarkDirty()
        end,
    })
    row1:AddWidget(optimizeBtn, 0.5)

    local revertBtn = GUIFrame:CreateButton(row1, "Revert All", {
        width = 140,
        height = 28,
        callback = function()
            OPT:RevertAll()
            C_Timer.After(0.2, RefreshAllRows)
            MarkDirty()
        end,
    })
    row1:AddWidget(revertBtn, 0.5)

    card1:AddRow(row1, 40)
    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    --------------------------------------------------------------------------
    -- Helper: add column header row to a card
    --------------------------------------------------------------------------
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

    --------------------------------------------------------------------------
    -- Helper: build a single CVar status row inside a card
    --------------------------------------------------------------------------
    local function AddCVarRow(card, entry, widgets)
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

        local arrowTex = "Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\collapse"
        local arrowRot = math.pi / 2
        local arrowR, arrowG, arrowB = Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3]

        -- Center the arrow pair in the 30px gap between currentLabel and optimalLabel
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

        -- Apply button
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

        -- Revert button
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

        -- "Optimal" label (shown when current matches recommended)
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

        --[[ BACKUP: Original RefreshRow
        local function RefreshRow()
            local current = OPT:GetCurrentValue(entry.cvar) or "?"
            local isOpt = OPT:IsOptimal(entry.cvar, entry.optimal)
            local currentDisplay = OPT:GetValueLabel(entry.cvar, current)
            local optimalDisplay = OPT:GetValueLabel(entry.cvar, entry.optimal)
            if isOpt then
                currentLabel:SetTextColor(0.3, 1, 0.3, 1)
            else
                currentLabel:SetTextColor(1, 0.55, 0, 1)
            end
            currentLabel:SetText(currentDisplay)
            optimalLabel:SetText(optimalDisplay)
            optimalLabel:SetTextColor(0.3, 1, 0.3, 1)
            if OPT:HasBackup(entry.cvar) then
                revertBtnSmall:SetAlpha(1)
                revertBtnSmall:EnableMouse(true)
            else
                revertBtnSmall:SetAlpha(0.35)
                revertBtnSmall:EnableMouse(false)
            end
        end
        --]]

        local function RefreshRow()
            local current = OPT:GetCurrentValue(entry.cvar) or "?"
            local isOpt = OPT:IsOptimal(entry.cvar, entry.optimal)
            local hasBackup = OPT:HasBackup(entry.cvar)
            local currentDisplay = OPT:GetValueLabel(entry.cvar, current)
            local optimalDisplay = OPT:GetValueLabel(entry.cvar, entry.optimal)

            if isOpt then
                currentLabel:SetTextColor(0.3, 1, 0.3, 1)
            else
                currentLabel:SetTextColor(1, 0.55, 0, 1)
            end
            currentLabel:SetText(currentDisplay)
            optimalLabel:SetText(optimalDisplay)
            optimalLabel:SetTextColor(0.3, 1, 0.3, 1)

            if isOpt then
                -- Optimal: hide Apply, show checkmark
                applyBtn:Hide()
                optimalStatusLabel:Show()
                if hasBackup then
                    -- User applied this session, allow revert
                    revertBtnSmall:Show()
                    revertBtnSmall:SetAlpha(1)
                    revertBtnSmall:EnableMouse(true)
                else
                    -- Already optimal, nothing to revert
                    revertBtnSmall:Hide()
                end
            else
                -- Not optimal: show Apply, hide checkmark
                applyBtn:Show()
                optimalStatusLabel:Hide()
                if hasBackup then
                    revertBtnSmall:Show()
                    revertBtnSmall:SetAlpha(1)
                    revertBtnSmall:EnableMouse(true)
                else
                    revertBtnSmall:Show()
                    revertBtnSmall:SetAlpha(0.35)
                    revertBtnSmall:EnableMouse(false)
                end
            end
        end

        applyBtn:SetScript("OnClick", function()
            OPT:ApplyCVar(entry.cvar, entry.optimal)
            C_Timer.After(0.1, function()
                RefreshRow()
            end)
            MarkDirty()
        end)

        revertBtnSmall:SetScript("OnClick", function()
            OPT:RevertCVar(entry.cvar)
            C_Timer.After(0.1, function()
                RefreshRow()
            end)
            MarkDirty()
        end)

        container:EnableMouse(true)
        container:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(entry.name, 1, 0.82, 0, 1)
            GameTooltip:AddLine(" ")
            local cur = OPT:GetCurrentValue(entry.cvar) or "?"
            GameTooltip:AddLine("Current: " .. OPT:GetValueLabel(entry.cvar, cur), 0.7, 0.7, 0.7)
            GameTooltip:AddLine("Recommended: " .. OPT:GetValueLabel(entry.cvar, entry.optimal), 0.3, 1, 0.3)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("CVar: " .. entry.cvar, 0.5, 0.5, 0.5)
            if entry.desc then
                GameTooltip:AddLine(entry.desc, 0.5, 0.5, 0.5)
            end
            GameTooltip:Show()
        end)
        container:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        row:AddWidget(container, 1)
        card:AddRow(row, 32)
        table_insert(widgets, row)
        table_insert(refreshCallbacks, RefreshRow)

        RefreshRow()
    end

    --------------------------------------------------------------------------
    -- Build a card per category
    --------------------------------------------------------------------------
    for _, cat in ipairs(OPT.Categories) do
        local card = GUIFrame:CreateCard(scrollChild, cat.name, yOffset)
        local widgets = {}

        AddColumnHeaders(card)

        for _, entry in ipairs(cat.cvars) do
            AddCVarRow(card, entry, widgets)
        end

        yOffset = yOffset + card:GetContentHeight() + Theme.paddingSmall
    end

    return yOffset
end)

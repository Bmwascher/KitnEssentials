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

local function MarkDirty()
    optimizeDirty = true
end

-- What the selected preset wants for this cvar, or nil while no preset is
-- selected. Max FPS falls through to the listed optimal for every cvar it does
-- not override.
local function PreviewValue(OPT, entry)
    if not selectedPreset then return nil end
    if selectedPreset == "maxfps" then
        local v = OPT:GetMaxFPSOverrides()[entry.cvar]
        if v ~= nil then return v end
    end
    return entry.optimal
end

------------------------------------------------------------------------
-- Column header and per-CVar status lines: built once, reused by every
-- page build through the settings widget pools.
------------------------------------------------------------------------
local function ConstructHeaderLine(parent)
    local container = CreateFrame("Frame", nil, parent)

    local settingHeader = container:CreateFontString(nil, "OVERLAY")
    settingHeader:SetPoint("LEFT", container, "LEFT", 4, 0)
    settingHeader:SetWidth(150)
    settingHeader:SetJustifyH("LEFT")
    KE:ApplyThemeFont(settingHeader, "normal")
    settingHeader:SetText("Setting")

    local currentHeader = container:CreateFontString(nil, "OVERLAY")
    currentHeader:SetPoint("LEFT", settingHeader, "RIGHT", 4, 0)
    currentHeader:SetWidth(90)
    currentHeader:SetJustifyH("LEFT")
    KE:ApplyThemeFont(currentHeader, "normal")
    currentHeader:SetText("Current")

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

    local headers = { settingHeader, currentHeader, recHeader }
    function container:Configure()
        self:SetAllPoints()
        KE:ApplyThemeFont(spacer, "normal")
        local c = Theme.textSecondary
        for _, header in ipairs(headers) do
            KE:ApplyThemeFont(header, "normal")
            header:SetTextColor(c[1], c[2], c[3], 0.7)
        end
    end

    container._keOwned = { container }
    return container
end

local ARROW_TEX = "Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\collapse.png"

local function SetupHover(btn)
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
    end)
end

local function PaintSmallButton(btn, text, textColor)
    local TT = Theme
    btn:SetBackdropColor(TT.bgButton[1], TT.bgButton[2], TT.bgButton[3], TT.bgButton[4])
    btn:SetBackdropBorderColor(TT.border[1], TT.border[2], TT.border[3], 1)
    KE:ApplyThemeFont(text, "normal")
    text:SetTextColor(textColor[1], textColor[2], textColor[3], 1)
end

-- The cvar and the module the line serves are read from line._entry and
-- line._opt at use time, so a reused line never acts for its last cvar.
local function ConstructCVarLine(parent)
    local line = CreateFrame("Frame", nil, parent)

    local nameLabel = line:CreateFontString(nil, "OVERLAY")
    nameLabel:SetPoint("LEFT", line, "LEFT", 4, 0)
    nameLabel:SetWidth(150)
    nameLabel:SetJustifyH("LEFT")
    KE:ApplyThemeFont(nameLabel, "normal")

    local currentLabel = line:CreateFontString(nil, "OVERLAY")
    currentLabel:SetPoint("LEFT", nameLabel, "RIGHT", 4, 0)
    currentLabel:SetWidth(90)
    currentLabel:SetJustifyH("LEFT")
    KE:ApplyThemeFont(currentLabel, "normal")

    local optimalLabel = line:CreateFontString(nil, "OVERLAY")
    optimalLabel:SetPoint("LEFT", currentLabel, "RIGHT", 30, 0)

    local arrow1 = line:CreateTexture(nil, "OVERLAY")
    arrow1:SetSize(10, 10)
    arrow1:SetPoint("LEFT", currentLabel, "RIGHT", 0, 0)
    arrow1:SetTexture(ARROW_TEX)
    arrow1:SetRotation(math.pi / 2)

    local arrow2 = line:CreateTexture(nil, "OVERLAY")
    arrow2:SetSize(10, 10)
    arrow2:SetPoint("LEFT", arrow1, "RIGHT", -3, 0)
    arrow2:SetTexture(ARROW_TEX)
    arrow2:SetRotation(math.pi / 2)
    optimalLabel:SetWidth(90)
    optimalLabel:SetJustifyH("LEFT")
    KE:ApplyThemeFont(optimalLabel, "normal")

    local applyBtn = CreateFrame("Button", nil, line, "BackdropTemplate")
    applyBtn:SetSize(50, 20)
    applyBtn:SetPoint("RIGHT", line, "RIGHT", -60, 0)
    applyBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    local applyText = applyBtn:CreateFontString(nil, "OVERLAY")
    KE:ApplyThemeFont(applyText, "normal")
    applyText:SetPoint("CENTER")
    applyText:SetText("Apply")

    local revertBtnSmall = CreateFrame("Button", nil, line, "BackdropTemplate")
    revertBtnSmall:SetSize(50, 20)
    revertBtnSmall:SetPoint("RIGHT", line, "RIGHT", -4, 0)
    revertBtnSmall:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    local revertText = revertBtnSmall:CreateFontString(nil, "OVERLAY")
    KE:ApplyThemeFont(revertText, "normal")
    revertText:SetPoint("CENTER")
    revertText:SetText("Revert")

    local optimalStatusLabel = line:CreateFontString(nil, "OVERLAY")
    KE:ApplyThemeFont(optimalStatusLabel, "normal")
    optimalStatusLabel:SetPoint("CENTER", applyBtn, "CENTER", 0, 0)
    optimalStatusLabel:SetText("Optimal")
    optimalStatusLabel:Hide()

    SetupHover(applyBtn)
    SetupHover(revertBtnSmall)

    function line:Refresh()
        local OPT, entry = self._opt, self._entry
        local current = OPT:GetCurrentValue(entry.cvar) or "?"
        local rec = PreviewValue(OPT, entry)
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

    -- A line released and reused before the timer fires skips the refresh.
    local function RefreshSoon()
        local gen = line._keGen
        C_Timer.After(0.1, function()
            if line._keGen == gen then line:Refresh() end
        end)
    end

    applyBtn:SetScript("OnClick", function()
        local rec = PreviewValue(line._opt, line._entry)
        if rec == nil then return end
        line._opt:ApplyCVar(line._entry.cvar, rec)
        RefreshSoon()
        MarkDirty()
    end)

    revertBtnSmall:SetScript("OnClick", function()
        line._opt:RevertCVar(line._entry.cvar)
        RefreshSoon()
        MarkDirty()
    end)

    line:EnableMouse(true)
    line:SetScript("OnEnter", function(self)
        local OPT, entry = self._opt, self._entry
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(entry.name, 1, 0.82, 0, 1)
        GameTooltip:AddLine(" ")
        local cur = OPT:GetCurrentValue(entry.cvar) or "?"
        GameTooltip:AddLine("Current: " .. OPT:GetValueLabel(entry.cvar, cur), 0.7, 0.7, 0.7)
        local recTip = PreviewValue(OPT, entry)
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
    line:SetScript("OnLeave", function() GameTooltip:Hide() end)

    function line:Configure(OPT, entry)
        self._opt = OPT
        self._entry = entry
        self:SetAllPoints()
        local TT = Theme
        KE:ApplyThemeFont(nameLabel, "normal")
        KE:ApplyThemeFont(currentLabel, "normal")
        KE:ApplyThemeFont(optimalLabel, "normal")
        nameLabel:SetText(entry.name)
        nameLabel:SetTextColor(TT.textPrimary[1], TT.textPrimary[2], TT.textPrimary[3], 1)
        local s = TT.textSecondary
        arrow1:SetVertexColor(s[1], s[2], s[3], 0.6)
        arrow2:SetVertexColor(s[1], s[2], s[3], 0.6)
        PaintSmallButton(applyBtn, applyText, TT.accent)
        PaintSmallButton(revertBtnSmall, revertText, TT.textSecondary)
        KE:ApplyThemeFont(optimalStatusLabel, "normal")
        optimalStatusLabel:SetTextColor(TT.accent[1], TT.accent[2], TT.accent[3], 1)
        self:Refresh()
    end

    line._keOwned = { line, applyBtn, revertBtnSmall }
    return line
end

local headerPool = GUIFrame:NewWidgetPool("optimize:header", ConstructHeaderLine, function() end)
local cvarLinePool = GUIFrame:NewWidgetPool("optimize:cvar", ConstructCVarLine, function(line)
    if GameTooltip:IsOwned(line) then GameTooltip:Hide() end
end)

local function AcquireLine(pool, construct, row)
    if GUIFrame:IsPoolParent(row) then
        return pool:Acquire(row)
    end
    return construct(row)
end

GUIFrame:RegisterContent("Optimize", function(scrollChild, yOffset)
    local OPT = GetModule()
    if not OPT then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Optimize module not available")
        return errorCard:GetNextOffset()
    end

    InstallCloseHook()

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

    local function PaintSelection()
        maxFpsBtn:SetSelected(selectedPreset == "maxfps")
        balancedBtn:SetSelected(selectedPreset == "balanced")
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

    local function AddColumnHeaders(card)
        local row = GUIFrame:CreateRow(card.content, 20)
        local header = AcquireLine(headerPool, ConstructHeaderLine, row)
        header:Configure()
        row:AddWidget(header, 1)
        card:AddRow(row, 20)
    end

    local function AddCVarRow(card, entry)
        local row = GUIFrame:CreateRow(card.content, 32)
        local line = AcquireLine(cvarLinePool, ConstructCVarLine, row)
        line:Configure(OPT, entry)
        row:AddWidget(line, 1)
        card:AddRow(row, 32)
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

-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-KEText.lua                                          ║
-- ║  Purpose: Text display widget with header and body.      ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

-- Localization Setup
local CreateFrame = CreateFrame
local CreateColor = CreateColor
local type = type
local ipairs = ipairs

---------------------------------------------------------------------------------
-- Widget Creation
---------------------------------------------------------------------------------

local function ResolveLabelText(input)
    if type(input) == "function" then
        input = input()
    end

    if type(input) == "table" then
        for i, v in ipairs(input) do
            input[i] = KE:ColorTextByTheme("• ") .. v
        end
        return table.concat(input, "\n")
    end

    return input or ""
end

-- Builds one text block. Title, body, height and background are applied by
-- ConfigureText.
local function ConstructText(parent)
    local row = CreateFrame("Frame", nil, parent)

    local container = CreateFrame("Frame", nil, row, "BackdropTemplate")
    container:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    container:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    container:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })

    -- Label
    local title = container:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOPLEFT", container, "TOPLEFT", 1, -1)
    title:SetPoint("TOPRIGHT", container, "TOPRIGHT", -1, -1)
    title:SetHeight(18)
    title:SetJustifyH("LEFT")

    -- Label
    local label = container:CreateFontString(nil, "OVERLAY")
    label:SetJustifyH("LEFT")
    label:SetSpacing(4)
    label:SetWordWrap(true)
    label:SetNonSpaceWrap(true)

    function row:SetEnabled(enabled)
        if enabled then
            row:SetAlpha(1)
        else
            row:SetAlpha(0.4)
        end
    end

    row.container = container
    row._title = title
    container.label = label
    row._keOwned = { row, container }
    return row
end

local function ConfigureText(row, titleTex, labelText, customRowHeight, bgShow)
    local rowHeight = customRowHeight or 34
    local container = row.container
    row:SetHeight(rowHeight)
    container:SetHeight(rowHeight)

    if bgShow == "show" then
        container:SetBackdropColor(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], 1)
        container:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
    elseif bgShow == "border" then
        container:SetBackdropColor(0, 0, 0, 0)
        container:SetBackdropBorderColor(0, 0, 0, 1)
    elseif bgShow == "hide" then
        container:SetBackdropColor(0, 0, 0, 0)
        container:SetBackdropBorderColor(0, 0, 0, 0)
    else
        -- The colours SetBackdrop itself leaves, which a fresh block showed.
        container:SetBackdropColor(1, 1, 1, 1)
        container:SetBackdropBorderColor(1, 1, 1, 1)
    end

    -- ApplyThemeFont sets the theme's shadow, so the block's no-shadow look is
    -- applied after it on every use.
    local title = row._title
    KE:ApplyThemeFont(title, "large")
    title:SetText(titleTex or "")
    title:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
    title:SetShadowColor(0, 0, 0, 0)

    local titleHeight = title:GetStringHeight()
    local smolSpacer = 2
    local totSpacer = titleHeight + smolSpacer

    local label = container.label
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -totSpacer)
    label:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    KE:ApplyThemeFont(label, "small")
    label:SetText(ResolveLabelText(labelText))
    label:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
    label:SetShadowColor(0, 0, 0, 0)

    row:SetEnabled(true)
end

local textPool = GUIFrame:NewWidgetPool("text", ConstructText, function() end)

-- Text widget
function GUIFrame:CreateText(parent, titleTex, labelText, customRowHeight, bgShow, wrapOn)
    local row
    if self:IsPoolParent(parent) then
        row = textPool:Acquire(parent)
    else
        row = ConstructText(parent)
    end
    ConfigureText(row, titleTex, labelText, customRowHeight, bgShow)
    return row
end

-- Separator widget
local function ConstructSeparator(parent)
    local separator = CreateFrame("Frame", nil, parent, "BackdropTemplate")

    -- Left half
    local left = separator:CreateTexture(nil, "ARTWORK")
    left:SetHeight(2)
    left:SetPoint("LEFT", separator, "LEFT", 3, 0)
    left:SetPoint("RIGHT", separator, "CENTER", 0, 0)
    left:SetColorTexture(1, 1, 1, 1)
    left:SetTexelSnappingBias(0)
    left:SetSnapToPixelGrid(false)

    -- Right half
    local right = separator:CreateTexture(nil, "ARTWORK")
    right:SetHeight(2)
    right:SetPoint("LEFT", separator, "CENTER", 0, 0)
    right:SetPoint("RIGHT", separator, "RIGHT", -3, 0)
    right:SetColorTexture(1, 1, 1, 1)
    right:SetTexelSnappingBias(0)
    right:SetSnapToPixelGrid(false)

    function separator:SetEnabled(enabled)
        if enabled then
            separator:SetAlpha(1)
        else
            separator:SetAlpha(0.5)
        end
    end

    separator._left = left
    separator._right = right
    separator._keOwned = { separator }
    return separator
end

local function ConfigureSeparator(separator, parent)
    -- Every use: row:AddWidget sizes a widget to its row.
    separator:SetHeight(6)
    separator:ClearAllPoints()
    separator:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    separator:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)

    local r, g, b = Theme.bgMedium[1] + 0.06, Theme.bgMedium[2] + 0.06, Theme.bgMedium[3] + 0.06
    separator._left:SetGradient("HORIZONTAL", CreateColor(r, g, b, 1), CreateColor(r, g, b, 1))
    separator._right:SetGradient("HORIZONTAL", CreateColor(r, g, b, 1), CreateColor(r, g, b, 1))
    separator:SetEnabled(true)
end

local separatorPool = GUIFrame:NewWidgetPool("separator", ConstructSeparator, function() end)

function GUIFrame:CreateSeparator(parent)
    local separator
    if self:IsPoolParent(parent) then
        separator = separatorPool:Acquire(parent)
    else
        separator = ConstructSeparator(parent)
    end
    ConfigureSeparator(separator, parent)
    return separator
end

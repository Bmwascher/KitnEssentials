-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-PresetSwatches.lua                                  ║
-- ║  Purpose: Theme preset selector — labelled grid or        ║
-- ║  compact chip strip.                                     ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local CreateFrame = CreateFrame
local table_insert = table.insert
local ipairs = ipairs
local math_floor = math.floor
local type = type

---------------------------------------------------------------------------------
-- Widget Creation
---------------------------------------------------------------------------------

-- Preset swatch selector — config-table API: { compact, value, callback }.
-- `compact` renders a fixed-spacing chip strip with tooltips instead of
-- labels; the default is a labelled 4-column grid.
function GUIFrame:CreatePresetSwatches(parent, config)
    if type(config) ~= "table" then
        config = {}
    end
    local compact = config.compact
    local currentPreset = config.value
    local onSelect = config.callback
    local presets = KE.ThemePresets
    local presetOrder = KE.ThemePresetOrder

    local container = CreateFrame("Frame", nil, parent)
    local buttons = {}

    if compact then
        local CHIP = 22
        local GAP = 6

        for i, presetName in ipairs(presetOrder) do
            local preset = presets[presetName]
            if not preset then break end

            local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
            btn:SetSize(CHIP, CHIP)
            btn:SetBackdrop({
                bgFile = "Interface\\BUTTONS\\WHITE8X8",
                edgeFile = "Interface\\BUTTONS\\WHITE8X8",
                edgeSize = 2,
            })
            btn:SetBackdropColor(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], 1)
            btn.presetName = presetName

            local swatch = btn:CreateTexture(nil, "ARTWORK")
            swatch:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -3)
            swatch:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -3, 3)
            swatch:SetTexture("Interface\\BUTTONS\\WHITE8X8")
            local ac = preset.accent
            swatch:SetVertexColor(ac[1], ac[2], ac[3], ac[4])
            btn.swatch = swatch

            local function UpdateVisuals()
                local isSelected = currentPreset == btn.presetName
                if btn.disabled then
                    btn:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 0.6)
                elseif isSelected then
                    btn:SetBackdropBorderColor(1, 1, 1, 1)
                elseif btn.hover then
                    btn:SetBackdropBorderColor(Theme.accentDim[1], Theme.accentDim[2], Theme.accentDim[3], 1)
                else
                    btn:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
                end
            end
            btn.UpdateVisuals = UpdateVisuals

            btn:SetScript("OnEnter", function(self)
                self.hover = true
                UpdateVisuals()
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(presetName, ac[1], ac[2], ac[3])
                GameTooltip:Show()
            end)

            btn:SetScript("OnLeave", function(self)
                self.hover = false
                UpdateVisuals()
                GameTooltip:Hide()
            end)

            btn:SetScript("OnClick", function(self)
                if self.disabled then return end
                currentPreset = self.presetName
                for _, b in ipairs(buttons) do b.UpdateVisuals() end
                if onSelect then onSelect(self.presetName) end
            end)

            btn:SetPoint("TOPLEFT", container, "TOPLEFT", (i - 1) * (CHIP + GAP), 0)

            UpdateVisuals()
            table_insert(buttons, btn)
        end

        local numButtons = #buttons
        container:SetSize(numButtons * CHIP + math.max(numButtons - 1, 0) * GAP, CHIP)
        -- Tells row:AddWidget to leave the height alone; without it the strip
        -- stretches to the row height and the chips park at the top of it.
        container.explicitHeight = CHIP
    else
        local buttonWidth = 110
        local buttonHeight = 36
        local maxColumns = 4
        local rowSpacing = 4
        local colSpacing = 6

        for _, presetName in ipairs(presetOrder) do
            local preset = presets[presetName]
            if not preset then break end

            local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
            btn:SetSize(buttonWidth, buttonHeight)
            btn:SetBackdrop({
                bgFile = "Interface\\BUTTONS\\WHITE8X8",
                edgeFile = "Interface\\BUTTONS\\WHITE8X8",
                edgeSize = 1,
            })
            btn:SetBackdropColor(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], 1)
            btn.presetName = presetName

            local swatch = btn:CreateTexture(nil, "ARTWORK")
            swatch:SetSize(14, 14)
            swatch:SetPoint("LEFT", btn, "LEFT", 8, 0)
            swatch:SetTexture("Interface\\BUTTONS\\WHITE8X8")
            local ac = preset.accent
            swatch:SetVertexColor(ac[1], ac[2], ac[3], ac[4])
            btn.swatch = swatch

            local label = btn:CreateFontString(nil, "OVERLAY")
            label:SetPoint("LEFT", swatch, "RIGHT", 6, 0)
            label:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
            label:SetJustifyH("LEFT")
            KE:ApplyThemeFont(label, "small")
            label:SetText(presetName)
            btn.label = label

            local function UpdateVisuals()
                local isSelected = currentPreset == btn.presetName
                if btn.disabled then
                    btn:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 0.6)
                    label:SetTextColor(0.4, 0.4, 0.4, 1)
                elseif isSelected then
                    local a = preset.accent
                    btn:SetBackdropBorderColor(a[1], a[2], a[3], 1)
                    label:SetTextColor(1, 1, 1, 1)
                elseif btn.hover then
                    btn:SetBackdropBorderColor(Theme.accentDim[1], Theme.accentDim[2], Theme.accentDim[3], 1)
                    label:SetTextColor(0.9, 0.9, 0.9, 1)
                else
                    btn:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
                    label:SetTextColor(0.7, 0.7, 0.7, 1)
                end
            end
            btn.UpdateVisuals = UpdateVisuals

            btn:SetScript("OnEnter", function(self)
                self.hover = true
                UpdateVisuals()
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(presetName, ac[1], ac[2], ac[3])
                GameTooltip:Show()
            end)

            btn:SetScript("OnLeave", function(self)
                self.hover = false
                UpdateVisuals()
                GameTooltip:Hide()
            end)

            btn:SetScript("OnClick", function(self)
                if self.disabled then return end
                currentPreset = self.presetName
                for _, b in ipairs(buttons) do b.UpdateVisuals() end
                if onSelect then onSelect(self.presetName) end
            end)

            UpdateVisuals()
            table_insert(buttons, btn)
        end

        local numButtons = #buttons
        local numRows = math.ceil(numButtons / maxColumns)
        container:SetHeight(numRows * buttonHeight + (numRows - 1) * rowSpacing)

        container:SetScript("OnSizeChanged", function(self, width)
            if not width or width <= 0 then return end
            local cols = math.min(maxColumns, numButtons)
            local totalBtnWidth = cols * buttonWidth
            local availSpacing = width - totalBtnWidth
            local spacing = math.max(colSpacing, math_floor(availSpacing / math.max(cols - 1, 1)))

            for i, btn in ipairs(buttons) do
                btn:ClearAllPoints()
                local col = (i - 1) % maxColumns
                local row = math_floor((i - 1) / maxColumns)
                local x = col * (buttonWidth + spacing)
                local y = -(row * (buttonHeight + rowSpacing))
                btn:SetPoint("TOPLEFT", self, "TOPLEFT", x, y)
            end
        end)
    end

    function container:SetEnabled(enabled)
        for _, btn in ipairs(buttons) do
            btn.disabled = not enabled
            btn:EnableMouse(enabled)
            btn.UpdateVisuals()
        end
    end

    function container:SetValue(presetName)
        currentPreset = presetName
        for _, btn in ipairs(buttons) do btn.UpdateVisuals() end
    end

    container.buttons = buttons
    return container
end

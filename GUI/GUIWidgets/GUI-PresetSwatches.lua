-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-PresetSwatches.lua                                  ║
-- ║  Purpose: Theme preset selector — a strip of colour      ║
-- ║  chips with the preset name on hover.                    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local CreateFrame = CreateFrame
local table_insert = table.insert
local ipairs = ipairs
local type = type

---------------------------------------------------------------------------------
-- Widget Creation
---------------------------------------------------------------------------------

-- Preset swatch selector — config-table API: { value, callback }.
function GUIFrame:CreatePresetSwatches(parent, config)
    if type(config) ~= "table" then
        config = {}
    end
    local currentPreset = config.value
    local onSelect = config.callback
    local presets = KE.ThemePresets
    local presetOrder = KE.ThemePresetOrder

    local container = CreateFrame("Frame", nil, parent)
    local buttons = {}

    -- Matches the dropdown control box in GUI-KEDropdown.lua, so a strip
    -- placed beside one lines up with it.
    local CHIP = 24
    local GAP = 6

    for i, presetName in ipairs(presetOrder) do
        local preset = presets[presetName]
        if not preset then break end

        local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
        btn:SetSize(CHIP, CHIP)
        btn:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], 1)
        btn.presetName = presetName

        local swatch = btn:CreateTexture(nil, "ARTWORK")
        swatch:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
        swatch:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
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
    function container:SetEnabled(enabled)
        -- The swatch fills the chip, so a border colour alone barely reads as
        -- disabled. Fading the strip is what makes the state visible.
        self:SetAlpha(enabled and 1 or 0.4)
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

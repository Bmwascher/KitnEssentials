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
local ipairs = ipairs
local type = type
local math_max = math.max

-- Matches the dropdown control box in GUI-KEDropdown.lua, so a strip
-- placed beside one lines up with it.
local CHIP = 24
local GAP = 6

local function UpdateChip(btn)
    if btn.disabled then
        btn:SetBackdropBorderColor(Theme.controlBorder[1], Theme.controlBorder[2], Theme.controlBorder[3], 0.6)
    elseif btn._strip._value == btn.presetName then
        btn:SetBackdropBorderColor(1, 1, 1, 1)
    elseif btn.hover then
        btn:SetBackdropBorderColor(Theme.accentDim[1], Theme.accentDim[2], Theme.accentDim[3], 1)
    else
        btn:SetBackdropBorderColor(Theme.controlBorder[1], Theme.controlBorder[2], Theme.controlBorder[3], 1)
    end
end

---------------------------------------------------------------------------------
-- Widget Creation
---------------------------------------------------------------------------------

local function ConstructPresetSwatches(parent)
    local container = CreateFrame("Frame", nil, parent)
    local buttons = {}
    local owned = { container }

    for i, presetName in ipairs(KE.ThemePresetOrder) do
        if not KE.ThemePresets[presetName] then break end

        local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
        btn:SetSize(CHIP, CHIP)
        btn:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeSize = 1,
        })
        btn:SetPoint("TOPLEFT", container, "TOPLEFT", (i - 1) * (CHIP + GAP), 0)
        btn.presetName = presetName
        btn._strip = container

        local swatch = btn:CreateTexture(nil, "ARTWORK")
        swatch:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
        swatch:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
        swatch:SetTexture("Interface\\BUTTONS\\WHITE8X8")
        btn.swatch = swatch

        btn:SetScript("OnEnter", function(self)
            self.hover = true
            UpdateChip(self)
            local ac = KE.ThemePresets[self.presetName].accent
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.presetName, ac[1], ac[2], ac[3])
            GameTooltip:Show()
        end)

        btn:SetScript("OnLeave", function(self)
            self.hover = false
            UpdateChip(self)
            GameTooltip:Hide()
        end)

        btn:SetScript("OnClick", function(self)
            if self.disabled then return end
            -- Read first, and nothing runs after the callback: it rebuilds
            -- the page, which puts this strip back in its pool and takes it
            -- out again before returning.
            local onSelect = container._onSelect
            container._value = self.presetName
            for _, b in ipairs(buttons) do UpdateChip(b) end
            if onSelect then onSelect(self.presetName) end
        end)

        buttons[#buttons + 1] = btn
        owned[#owned + 1] = btn
    end

    local numButtons = #buttons
    container:SetSize(numButtons * CHIP + math_max(numButtons - 1, 0) * GAP, CHIP)
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
            UpdateChip(btn)
        end
    end

    function container:SetValue(presetName)
        self._value = presetName
        for _, btn in ipairs(buttons) do UpdateChip(btn) end
    end

    function container:Configure(config)
        self:SetHeight(CHIP)
        self._value = config.value
        self._onSelect = config.callback
        for _, btn in ipairs(buttons) do
            local ac = KE.ThemePresets[btn.presetName].accent
            btn.swatch:SetVertexColor(ac[1], ac[2], ac[3], ac[4])
            btn:SetBackdropColor(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], 1)
            btn.hover = false
            btn.disabled = false
            btn:EnableMouse(true)
            UpdateChip(btn)
        end
    end

    container.buttons = buttons
    container._keOwned = owned
    return container
end

GUIFrame:NewWidgetPool("presetswatches", ConstructPresetSwatches, function(container)
    for _, btn in ipairs(container.buttons) do
        btn.hover = false
        btn.disabled = false
        btn:EnableMouse(true)
        if GameTooltip:IsOwned(btn) then GameTooltip:Hide() end
    end
end)

-- Preset swatch selector — config-table API: { value, callback }.
function GUIFrame:CreatePresetSwatches(parent, config)
    if type(config) ~= "table" then
        config = {}
    end
    local container = self:AcquirePooled("presetswatches", parent)
    container:Configure(config)
    return container
end

-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-Castbars.lua                                        ║
-- ║  GUI: Focus & Target Castbar                             ║
-- ║  Purpose: Configuration panel for the Castbars module.   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local CreateFrame = CreateFrame

---------------------------------------------------------------------------------
-- Tab State
---------------------------------------------------------------------------------
local activeTab = "TargetCastbar"

---------------------------------------------------------------------------------
-- Tab Bar
---------------------------------------------------------------------------------
local function BuildTabBar(scrollChild, yOffset)
    local T = Theme
    local a = T.accent

    local tabHeight = 28
    local tabRow = CreateFrame("Frame", nil, scrollChild)
    tabRow:SetHeight(tabHeight)
    tabRow:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", T.paddingSmall, -yOffset)
    tabRow:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -T.paddingSmall, -yOffset)

    local tabs = {
        { id = "TargetCastbar", label = "Target" },
        { id = "FocusCastbar",  label = "Focus" },
    }

    local tabWidth = 120
    local spacing = 4

    for i, def in ipairs(tabs) do
        local btn = CreateFrame("Button", nil, tabRow, "BackdropTemplate")
        btn:SetSize(tabWidth, tabHeight)
        btn:SetPoint("TOPLEFT", tabRow, "TOPLEFT", (i - 1) * (tabWidth + spacing), 0)

        local isActive = (def.id == activeTab)

        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })

        if isActive then
            btn:SetBackdropColor(a[1], a[2], a[3], 0.25)
            btn:SetBackdropBorderColor(a[1], a[2], a[3], 0.8)
        else
            btn:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], T.bgMedium[4] or 0.6)
            btn:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], T.border[4] or 0.4)
        end

        local label = btn:CreateFontString(nil, "OVERLAY")
        label:SetPoint("CENTER")
        KE:ApplyThemeFont(label, "normal")
        label:SetText(def.label)

        if isActive then
            label:SetTextColor(a[1], a[2], a[3], 1)
        else
            label:SetTextColor(1, 1, 1, 0.6)
        end

        btn:SetScript("OnClick", function()
            if activeTab ~= def.id then
                activeTab = def.id
                GUIFrame:RefreshContent()
            end
        end)

        btn:SetScript("OnEnter", function(self)
            if def.id ~= activeTab then
                self:SetBackdropColor(a[1], a[2], a[3], 0.12)
                label:SetTextColor(1, 1, 1, 0.9)
            end
        end)

        btn:SetScript("OnLeave", function(self)
            if def.id ~= activeTab then
                self:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], T.bgMedium[4] or 0.6)
                label:SetTextColor(1, 1, 1, 0.6)
            end
        end)
    end

    return yOffset + tabHeight + T.paddingSmall
end

---------------------------------------------------------------------------------
-- Content Registration
---------------------------------------------------------------------------------
GUIFrame:RegisterContent("Castbars", function(scrollChild, yOffset)
    yOffset = BuildTabBar(scrollChild, yOffset)

    local builder = GUIFrame.registeredContent[activeTab]
    if builder then
        return builder(scrollChild, yOffset)
    end
    return yOffset
end)

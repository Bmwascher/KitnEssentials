-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-KESubTabs.lua                                       ║
-- ║  Purpose: Reusable horizontal sub-tab bar for tabbed     ║
-- ║           module GUI pages.                              ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local CreateFrame = CreateFrame
local ipairs = ipairs
local C_Timer = C_Timer

-- File-local debounce: rapid tab clicks (e.g. clicking through every tab in a
-- single frame) can race against RefreshContent's teardown/build cycle and
-- leave the tab row partially rendered. Collapse multiple clicks within the
-- same frame into a single end-of-frame refresh.
local refreshScheduled = false

local function ScheduleRefresh()
    if refreshScheduled then return end
    refreshScheduled = true
    C_Timer.After(0, function()
        refreshScheduled = false
        if GUIFrame.RefreshContent then
            GUIFrame:RefreshContent()
        end
    end)
end

---------------------------------------------------------------------------------
-- Sub-tab widget
---------------------------------------------------------------------------------
-- Usage:
--   local _, newOffset = GUIFrame:CreateSubTabs(scrollChild, yOffset, {
--       tabs = {
--           { id = "TargetCastbar", label = "Target" },
--           { id = "FocusCastbar",  label = "Focus"  },
--       },
--       activeId = currentTab,
--       onSwitch = function(newId)
--           currentTab = newId
--       end,
--       tabWidth = 120,  -- optional, default 120 (ignored when fill = true)
--       fill = false,    -- optional, when true tabs evenly fill container width
--   })
--
-- onSwitch is called BEFORE the frame refresh schedules; callers only need to
-- update their state. The widget handles RefreshContent internally.
--
-- Returns: (container frame, new yOffset after the sub-tab row)
function GUIFrame:CreateSubTabs(parent, yOffset, config)
    config = config or {}
    local tabs = config.tabs or {}
    local activeId = config.activeId
    local onSwitch = config.onSwitch
    local tabWidth = config.tabWidth or 120
    local tabHeight = config.tabHeight or 28
    local spacing = config.spacing or 4
    local fill = config.fill == true

    local T = Theme
    local a = T.accent

    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(tabHeight)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", T.paddingSmall, -yOffset)
    container:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -T.paddingSmall, -yOffset)

    local buttons = {}
    local numTabs = #tabs
    local btnList = {}

    for i, def in ipairs(tabs) do
        local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
        btn:SetHeight(tabHeight)
        btnList[i] = btn

        if fill then
            -- Evenly distribute tabs to fill container width
            if i == 1 then
                btn:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
            else
                btn:SetPoint("TOPLEFT", btnList[i - 1], "TOPRIGHT", spacing, 0)
            end
            if i == numTabs then
                btn:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
            else
                local totalSpacing = spacing * (numTabs - 1)
                btn:SetWidth((540 - totalSpacing) / numTabs)
            end
        else
            btn:SetSize(tabWidth, tabHeight)
            btn:SetPoint("TOPLEFT", container, "TOPLEFT", (i - 1) * (tabWidth + spacing), 0)
        end

        local isActive = (def.id == activeId)

        btn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
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
        label:SetText(def.label or def.id)

        if isActive then
            label:SetTextColor(a[1], a[2], a[3], 1)
        else
            label:SetTextColor(1, 1, 1, 0.6)
        end

        btn.tabId = def.id
        btn.label = label

        btn:SetScript("OnClick", function(b)
            if b.tabId == activeId then return end
            if onSwitch then onSwitch(b.tabId) end
            ScheduleRefresh()
        end)

        btn:SetScript("OnEnter", function(b)
            if b.tabId ~= activeId then
                b:SetBackdropColor(a[1], a[2], a[3], 0.12)
                b.label:SetTextColor(1, 1, 1, 0.9)
            end
        end)

        btn:SetScript("OnLeave", function(b)
            if b.tabId ~= activeId then
                b:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], T.bgMedium[4] or 0.6)
                b.label:SetTextColor(1, 1, 1, 0.6)
            end
        end)

        buttons[def.id] = btn
    end

    container.buttons = buttons
    return container, yOffset + tabHeight + T.paddingSmall
end

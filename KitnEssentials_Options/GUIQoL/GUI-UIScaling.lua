-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-UIScaling.lua                                       ║
-- ║  GUI: UI Scaling                                         ║
-- ║  Purpose: Panel Scaling settings and the World Map card, ║
-- ║  a tab of the Core > CVars page.                         ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local ipairs = ipairs
local table_concat = table.concat

local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.5, 2.0, 0.05

local CATEGORY_PAGES = {
    { id = "UIScalingCore",     label = "Core Panels",       category = "Core" },
    { id = "UIScalingServices", label = "Services",          category = "Services" },
    { id = "UIScalingHousing",  label = "Housing",           category = "Housing" },
    { id = "UIScalingLegacy",   label = "Legacy / Optional", category = "Legacy" },
}

local function GetPanelScaleModule()
    return KitnEssentials and KitnEssentials:GetModule("PanelScale", true)
end

local function GetMapScaleModule()
    return KitnEssentials and KitnEssentials:GetModule("MapScale", true)
end

GUIFrame:RegisterContent("UIScalingGeneral", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.PanelScale
    if not db then return yOffset end
    local manager = GUIFrame:CreateWidgetStateManager()

    ----------------------------------------------------------------
    -- Card 1: Blizzard Panel Scaling
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Blizzard Panel Scaling", yOffset)
    card1:AddHeaderToggle(db.Enabled == true, function(checked)
        db.Enabled = checked
        if checked then KitnEssentials:EnableModule("PanelScale")
        else KitnEssentials:DisableModule("PanelScale") end
    end)

    card1:AddLabel("Scales Blizzard windows such as the character, professions and auction house panels as a whole. The game's UI Scale is not changed.")

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local scaleSlider = GUIFrame:CreateSlider(row1, "Panel Scale", {
        min = SCALE_MIN, max = SCALE_MAX, step = SCALE_STEP,
        value = db.Scale or 1,
        callback = function(val)
            db.Scale = val
            local PS = GetPanelScaleModule()
            if PS then PS:ApplySettings() end
        end,
    })
    row1:AddWidget(scaleSlider, 1)
    manager:Register(scaleSlider, "all")
    card1:AddRow(row1, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: World Map Scale
    ----------------------------------------------------------------
    local mapDB = KE.db.profile.MapScale
    if mapDB then
        -- Not registered with `manager`: MapScale has its own enable
        -- lifecycle, so this card must not gray out with Panel Scaling.
        local card2 = GUIFrame:CreateCard(scrollChild, "World Map Scale", yOffset)

        local function ApplyMapScale()
            local MS = GetMapScaleModule()
            if MS and MS.ApplySettings then MS:ApplySettings() end
        end

        card2:AddHeaderToggle(mapDB.Enabled ~= false, function(checked)
            mapDB.Enabled = checked
            if checked then KitnEssentials:EnableModule("MapScale")
            else KitnEssentials:DisableModule("MapScale") end
            ApplyMapScale()
        end)
        yOffset = card2:GetNextOffset()

        if mapDB.Enabled ~= false then
            card2:AddLabel("Scales the world map window, with a separate scale for when it is maximized.")

            local row2b = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
            local mapScaleSlider = GUIFrame:CreateSlider(row2b, "Scale", {
                min = 0.5, max = 2.0, step = 0.05,
                value = mapDB.Scale or 1.2,
                callback = function(val)
                    mapDB.Scale = val
                    ApplyMapScale()
                end,
            })
            row2b:AddWidget(mapScaleSlider, 1)
            card2:AddRow(row2b, Theme.rowHeight)

            local row2c = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
            local maxScaleSlider = GUIFrame:CreateSlider(row2c, "Maximized Scale", {
                min = 0.5, max = 1.0, step = 0.05,
                value = mapDB.MaximizedScale or 1,
                callback = function(val)
                    mapDB.MaximizedScale = val
                    ApplyMapScale()
                end,
            })
            row2c:AddWidget(maxScaleSlider, 1)
            card2:AddRow(row2c, Theme.rowHeightLast, 0)

            card2:AddLabel("Changes apply the next time you open the map.")

            yOffset = card2:GetNextOffset()
        end
    end

    manager:UpdateAll(db.Enabled == true)
    return yOffset
end)

-- One builder for the four category pages. The enable box needs the master,
-- the override needs the category too, and the slider needs the override.
local function BuildCategoryPage(page, scrollChild, yOffset)
    local db = KE.db and KE.db.profile.PanelScale
    if not db then return yOffset end
    local category = page.category
    local enabledKey = category .. "Enabled"
    local overrideKey = category .. "Override"
    local scaleKey = category .. "Scale"

    local manager = GUIFrame:CreateWidgetStateManager()
    manager:SetCondition("category", function() return db[enabledKey] ~= false end)
    manager:SetCondition("override", function()
        return db[enabledKey] ~= false and db[overrideKey] == true
    end)

    local function RefreshStates()
        manager:UpdateAll(db.Enabled == true)
    end

    local function Reconcile()
        local PS = GetPanelScaleModule()
        if PS and PS:IsEnabled() then PS:ReconcileCategory(category) end
    end

    local card = GUIFrame:CreateCard(scrollChild, page.label, yOffset)

    local row1 = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Scale " .. page.label, {
        value = db[enabledKey] ~= false,
        callback = function(checked)
            db[enabledKey] = checked
            Reconcile()
            RefreshStates()
        end,
    })
    row1:AddWidget(enableCheck, 0.5)
    manager:Register(enableCheck, "all")

    local overrideCheck = GUIFrame:CreateCheckbox(row1, "Override Shared Scale", {
        value = db[overrideKey] == true,
        callback = function(checked)
            db[overrideKey] = checked
            Reconcile()
            RefreshStates()
        end,
    })
    row1:AddWidget(overrideCheck, 0.5)
    manager:Register(overrideCheck, "category")
    card:AddRow(row1, Theme.rowHeight)

    local row2 = GUIFrame:CreateRow(card.content, Theme.rowHeightLast)
    local scaleSlider = GUIFrame:CreateSlider(row2, page.label .. " Scale", {
        min = SCALE_MIN, max = SCALE_MAX, step = SCALE_STEP,
        value = db[scaleKey] or 1,
        callback = function(val)
            db[scaleKey] = val
            Reconcile()
        end,
    })
    row2:AddWidget(scaleSlider, 1)
    manager:Register(scaleSlider, "override")
    card:AddRow(row2, Theme.rowHeightLast, 0)

    yOffset = card:GetNextOffset()

    local registry = KE.PanelScaleRegistry
    local labels = registry and registry.labelsByCategory[category]
    if labels then
        local listCard = GUIFrame:CreateCard(scrollChild, "Included Panels", yOffset)
        listCard:AddLabel(table_concat(labels, ", "))
        yOffset = listCard:GetNextOffset()
    end

    RefreshStates()
    return yOffset
end

local SCALING_TABS = { { id = "UIScalingGeneral", label = "General" } }
for _, page in ipairs(CATEGORY_PAGES) do
    SCALING_TABS[#SCALING_TABS + 1] = { id = page.id, label = page.label }
    GUIFrame:RegisterContent(page.id, function(scrollChild, yOffset)
        return BuildCategoryPage(page, scrollChild, yOffset)
    end)
end

GUIFrame:RegisterTabbedContent("UIScaling", SCALING_TABS)

-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-PartyBuffsGeneral.lua                               ║
-- ║  GUI: Party Cooldowns, General tab                       ║
-- ║  Purpose: the settings several displays share.           ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame

local PLACES = {
    { "Mythic+", "ShowInKeys" },
    { "All Other Dungeon Types", "ShowInDungeons" },
    { "Delves", "ShowInDelves" },
    { "Open World", "ShowInWorld" },
    { "Arenas", "ShowInArenas" },
}

-- The raid cooldowns box reads the Externals color, so it alone stays on
-- colorsOn and live with Party Frame Icons off.
local COLORS = {
    { key = "ColorExternal",     label = "Externals",     group = "colorsOn" },
    { key = "ColorBigDefensive", label = "Defensive CDs", group = "defensiveOn" },
    { key = "ColorBurst",        label = "Offensive CDs", group = "rowColorsOn" },
    { key = "ColorPotion",       label = "Potion",        group = "rowColorsOn" },
    { key = "ColorTrinket",      label = "Trinket",       group = "rowColorsOn" },
}

local function GetModule() return KitnEssentials and KitnEssentials:GetModule("PartyBuffs", true) end

GUIFrame:RegisterContent("PartyBuffsGeneral", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.PartyBuffs
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local PB = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if PB and PB.ApplySettings then PB:ApplySettings() end
    end

    -- A color drag calls back on every mouse move.
    local function QueueApply()
        if PB and PB.QueueApplySettings then PB:QueueApplySettings() end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled == true)
    end

    -- Only the cooldown cells use the defensive color.
    manager:SetCondition("colorsOn", function() return db.CategoryColors == true end)
    manager:SetCondition("rowColorsOn", function()
        return db.CategoryColors == true and db.FrameIcons == true
    end)
    manager:SetCondition("defensiveOn", function()
        return db.CategoryColors == true and KE.PartyCooldownsSensor ~= nil and db.FrameIcons == true
    end)

    ----------------------------------------------------------------
    -- Card: Show In
    ----------------------------------------------------------------
    local cardShow = GUIFrame:CreateCard(scrollChild, "Show In", yOffset)
    cardShow:AddLabel("Where the party frame icons, Potion bars and Raid Cooldowns show. All three use the "
        .. KE:Gold("Font Settings") .. " font and outline; the party frame icons and Raid Cooldowns use the "
        .. KE:Gold("Colors") .. "."
        .. "\n\nNot shown in raids, battlegrounds or other raid groups.")
    local grid = {}
    for i, place in ipairs(PLACES) do
        local key = place[2]
        grid[i] = {
            label = place[1],
            config = {
                value = db[key] == true,
                callback = function(checked)
                    db[key] = checked
                    ApplySettings()
                end,
            },
        }
    end
    cardShow:AddCheckboxGrid(grid, { isLast = true })
    yOffset = cardShow:GetNextOffset()

    ----------------------------------------------------------------
    -- Card: Font Settings, face and outline only
    ----------------------------------------------------------------
    local _, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        title = "Font Settings",
        db = db,
        dbKeys = {
            fontFace    = "FontFace",
            fontOutline = "FontOutline",
        },
        showSize = false,
        onChangeCallback = ApplySettings,
    })
    if fontWidgets then manager:RegisterGroup(fontWidgets, "all") end
    yOffset = fontOffset

    ----------------------------------------------------------------
    -- Card: Colors
    ----------------------------------------------------------------
    yOffset = GUIFrame:CreateColorsCard(scrollChild, yOffset, {
        db = db,
        manager = manager,
        onChange = QueueApply,
        sources = {
            { label = "Border Color by Category", key = "CategoryColors", onChange = RefreshStates },
        },
        colors = COLORS,
        perRow = 3,
        isLast = true,
    })

    RefreshStates()
    return yOffset
end)

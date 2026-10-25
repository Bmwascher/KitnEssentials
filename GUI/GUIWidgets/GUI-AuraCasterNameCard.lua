-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-AuraCasterNameCard.lua                              ║
-- ║  Purpose: Shared Caster Name card for the aura displays  ║
-- ║           that show the game's caster name.              ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local POSITION_OPTIONS = {
    { key = "TOP",    text = "Top" },
    { key = "BOTTOM", text = "Bottom" },
    { key = "LEFT",   text = "Left" },
    { key = "RIGHT",  text = "Right" },
    { key = "CENTER", text = "Center" },
}

----------------------------------------------------------------
-- Caster Name card
--
-- config.ownNameBlocked, when given, grays Hide My Own Name while it returns
-- true. The page re-runs its own states after changing what it reads, which
-- reaches this card through SetEnabled.
----------------------------------------------------------------
function GUIFrame:CreateAuraCasterNameCard(scrollChild, yOffset, config)
    config = config or {}
    assert(type(config.db) == "table", "CreateAuraCasterNameCard requires db")

    local db = config.db
    local function Apply()
        if config.onChangeCallback then config.onChangeCallback() end
    end

    local card = GUIFrame:CreateCard(scrollChild, config.title or "Caster Name", yOffset)
    local innerManager = GUIFrame:CreateWidgetStateManager()
    local cardEnabled = true

    innerManager:SetCondition("casterOn", function() return db.ShowCasterName == true end)
    innerManager:SetCondition("casterOwn", function()
        if db.ShowCasterName ~= true then return false end
        return not (config.ownNameBlocked and config.ownNameBlocked())
    end)

    local function RefreshInner()
        innerManager:UpdateAll(cardEnabled)
    end

    local row1 = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local showCheck = GUIFrame:CreateCheckbox(row1, "Show Caster Name", {
        value = db.ShowCasterName == true,
        callback = function(checked)
            db.ShowCasterName = checked
            Apply()
            RefreshInner()
        end,
        tooltip = "Writes the name of the player who cast each buff under its icon.",
    })
    row1:AddWidget(showCheck, 0.5)
    innerManager:Register(showCheck, "all")

    local hideOwnCheck = GUIFrame:CreateCheckbox(row1, "Hide My Own Name", {
        value = db.HideOwnCasterName == true,
        callback = function(checked) db.HideOwnCasterName = checked; Apply() end,
        tooltip = "Moves buffs you, your pet or your totems cast into their own block, with no name. "
            .. "Each block then gets a share of the icon slots, so fewer of one kind can show at once.",
    })
    row1:AddWidget(hideOwnCheck, 0.5)
    innerManager:Register(hideOwnCheck, "casterOwn")
    card:AddRow(row1, Theme.rowHeight)

    local row2 = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local classColorCheck = GUIFrame:CreateCheckbox(row2, "Class Color", {
        value = db.CasterClassColor ~= false,
        callback = function(checked) db.CasterClassColor = checked; Apply() end,
        tooltip = "Writes each name in its caster's class color.",
    })
    row2:AddWidget(classColorCheck, 0.5)
    innerManager:Register(classColorCheck, "casterOn")

    local realmCheck = GUIFrame:CreateCheckbox(row2, "Show Realm", {
        value = db.CasterShowRealm == true,
        callback = function(checked) db.CasterShowRealm = checked; Apply() end,
        tooltip = "Adds the realm to the name of a player from another realm.",
    })
    row2:AddWidget(realmCheck, 0.5)
    innerManager:Register(realmCheck, "casterOn")
    card:AddRow(row2, Theme.rowHeight)

    local row3 = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local colorPicker = GUIFrame:CreateColorPicker(row3, "Name Color", {
        color = db.CasterNameColor or { 1, 1, 1, 1 },
        callback = function(r, g, b, a) db.CasterNameColor = { r, g, b, a }; Apply() end,
        tooltip = "Used for every name when Class Color is off, and for a caster with no class, "
            .. "such as a totem, when it is on.",
    })
    row3:AddWidget(colorPicker, 0.5)
    innerManager:Register(colorPicker, "casterOn")

    local sizeSlider = GUIFrame:CreateSlider(row3, "Name Size", {
        min = 8, max = 48, step = 1,
        value = KE.AuraRules.CasterFontSize(db) or 14,
        callback = function(val) db.CasterFontSize = val; Apply() end,
    })
    row3:AddWidget(sizeSlider, 0.5)
    innerManager:Register(sizeSlider, "casterOn")
    card:AddRow(row3, Theme.rowHeight)

    db.CasterPosition = db.CasterPosition
        or { AnchorFrom = "TOP", AnchorTo = "BOTTOM", XOffset = 0, YOffset = -1 }
    local pos = db.CasterPosition

    local row4 = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local positionDropdown = GUIFrame:CreateDropdown(row4, "Name Position", {
        options = POSITION_OPTIONS,
        value = pos.AnchorTo or "BOTTOM",
        callback = function(key)
            pos.AnchorTo = key
            pos.AnchorFrom = KE.AuraRules.CASTER_OPPOSITE_POINT[key] or "TOP"
            Apply()
        end,
        tooltip = "The side of the icon the name sits on.",
    })
    row4:AddWidget(positionDropdown, 1 / 3)
    innerManager:Register(positionDropdown, "casterOn")

    local xSlider = GUIFrame:CreateSlider(row4, "Name X", {
        min = -50, max = 50, step = 1,
        value = pos.XOffset or 0,
        callback = function(val) pos.XOffset = val; Apply() end,
    })
    row4:AddWidget(xSlider, 1 / 3)
    innerManager:Register(xSlider, "casterOn")

    local ySlider = GUIFrame:CreateSlider(row4, "Name Y", {
        min = -50, max = 50, step = 1,
        value = pos.YOffset or -1,
        callback = function(val) pos.YOffset = val; Apply() end,
    })
    row4:AddWidget(ySlider, 1 / 3)
    innerManager:Register(ySlider, "casterOn")
    card:AddRow(row4, Theme.rowHeight)

    local row5 = GUIFrame:CreateRow(card.content, Theme.rowHeightLast)
    local widthSlider = GUIFrame:CreateSlider(row5, "Name Width", {
        min = 0, max = 200, step = 1,
        value = db.CasterWidth or 0,
        callback = function(val) db.CasterWidth = val; Apply() end,
        tooltip = "Names longer than this are cut. 0 follows the icon width.",
    })
    row5:AddWidget(widthSlider, 0.5)
    innerManager:Register(widthSlider, "casterOn")
    card:AddRow(row5, Theme.rowHeightLast, 0)

    local baseSetEnabled = card.SetEnabled
    function card:SetEnabled(enabled)
        if baseSetEnabled then baseSetEnabled(self, enabled) end
        cardEnabled = enabled
        RefreshInner()
    end

    RefreshInner()
    return card, card:GetNextOffset()
end

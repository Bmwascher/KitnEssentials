-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-DispelCursorCard.lua                                ║
-- ║  Purpose: Shared "Dispel Countdown" card builder.        ║
-- ║  Used by Combat Utilities > Cursor Effects AND the       ║
-- ║  Healer Utilities > Dispel on Cursor cross-link page.    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

-- config = {
--   db             : Cursor profile table (KE.db.profile.Cursor)
--   manager        : WidgetStateManager for this page
--   refresh        : function() -- calls the module's Refresh (optional)
--   refreshStates  : function() -- updates the page's full widget state (optional)
--   getModule      : function() returns the Cursor module (optional)
-- }
-- Returns: newYOffset
function GUIFrame:CreateDispelCursorCard(scrollChild, yOffset, config)
    local db           = config.db
    local manager      = config.manager
    local refresh      = config.refresh or function() end
    local refreshStates = config.refreshStates or function() end
    local getMod       = config.getModule or function() return nil end

    db.Dispel = db.Dispel or {}
    manager:SetCondition("dispelEnabled", function() return db.Dispel.Enabled == true end)

    ----------------------------------------------------------------
    -- Card: Dispel Countdown
    ----------------------------------------------------------------
    local card6 = GUIFrame:CreateCard(scrollChild, "Dispel Countdown", yOffset)
    manager:Register(card6, "all")

    local row6a = GUIFrame:CreateRow(card6.content, Theme.rowHeight)
    local dispelEnable = GUIFrame:CreateCheckbox(row6a, "Enable Dispel Countdown", {
        value = db.Dispel.Enabled == true,
        callback = function(checked)
            db.Dispel.Enabled = checked
            refresh()
            refreshStates()
        end,
    })
    row6a:AddWidget(dispelEnable, 0.6)
    manager:Register(dispelEnable, "all")

    -- Test button: 7-second preview so users can verify placement without
    -- waiting for a real dispel cooldown. Always enabled (works with feature off too).
    local dispelTest = GUIFrame:CreateButton(row6a, "Test (7s countdown)", {
        height = 30,
        callback = function()
            local mod = getMod()
            if mod and mod.DispelPreview then mod:DispelPreview() end
        end,
    })
    row6a:AddWidget(dispelTest, 0.4)
    manager:Register(dispelTest, "all")
    card6:AddRow(row6a, Theme.rowHeight)

    local row6sep = GUIFrame:CreateRow(card6.content, Theme.rowHeightSeparator)
    local sep6 = GUIFrame:CreateSeparator(row6sep)
    row6sep:AddWidget(sep6, 1)
    manager:Register(sep6, "all")
    card6:AddRow(row6sep, Theme.rowHeightSeparator)

    local row6b = GUIFrame:CreateRow(card6.content, Theme.rowHeight)
    local dispelAnchor = GUIFrame:CreateDropdown(row6b, "Anchor Point", {
        options = {
            { key = "TOP",    text = "Top" },
            { key = "BOTTOM", text = "Bottom" },
            { key = "LEFT",   text = "Left" },
            { key = "RIGHT",  text = "Right" },
            { key = "CENTER", text = "Center" },
        },
        value = db.Dispel.AnchorPoint or "BOTTOM",
        callback = function(key) db.Dispel.AnchorPoint = key; refresh() end,
    })
    row6b:AddWidget(dispelAnchor, 1)
    manager:Register(dispelAnchor, "dispelEnabled")
    card6:AddRow(row6b, Theme.rowHeight)

    local row6c = GUIFrame:CreateRow(card6.content, Theme.rowHeight)
    local dispelX = GUIFrame:CreateSlider(row6c, "X Offset", {
        min = -50, max = 50, step = 1,
        value = db.Dispel.XOffset or 10,
        callback = function(val) db.Dispel.XOffset = val; refresh() end,
    })
    row6c:AddWidget(dispelX, 0.5)
    manager:Register(dispelX, "dispelEnabled")

    local dispelY = GUIFrame:CreateSlider(row6c, "Y Offset", {
        min = -50, max = 50, step = 1,
        value = db.Dispel.YOffset or 10,
        callback = function(val) db.Dispel.YOffset = val; refresh() end,
    })
    row6c:AddWidget(dispelY, 0.5)
    manager:Register(dispelY, "dispelEnabled")
    card6:AddRow(row6c, Theme.rowHeight)

    local row6d = GUIFrame:CreateRow(card6.content, Theme.rowHeightLast)
    local dispelFontSize = GUIFrame:CreateSlider(row6d, "Font Size", {
        min = 8, max = 48, step = 1,
        value = db.Dispel.FontSize or 18,
        callback = function(val) db.Dispel.FontSize = val; refresh() end,
    })
    row6d:AddWidget(dispelFontSize, 0.5)
    manager:Register(dispelFontSize, "dispelEnabled")

    local dispelTextColor = GUIFrame:CreateColorPicker(row6d, "Text Color", {
        color = db.Dispel.TextColor or { 1, 1, 1, 1 },
        callback = function(r, g, b, a)
            db.Dispel.TextColor = { r, g, b, a }
            refresh()
        end,
    })
    row6d:AddWidget(dispelTextColor, 0.5)
    manager:Register(dispelTextColor, "dispelEnabled")
    card6:AddRow(row6d, Theme.rowHeightLast, 0)

    return card6:GetNextOffset()
end

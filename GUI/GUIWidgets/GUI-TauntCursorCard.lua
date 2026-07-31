-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-TauntCursorCard.lua                                 ║
-- ║  Purpose: Shared "Taunt Countdown" card builder.         ║
-- ║  Used by Combat Utilities > Cursor Effects > Taunt —     ║
-- ║  the only place these settings live.                     ║
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
function GUIFrame:CreateTauntCursorCard(scrollChild, yOffset, config)
    local db            = config.db
    local manager       = config.manager
    local refresh       = config.refresh or function() end
    local refreshStates = config.refreshStates or function() end
    local getMod        = config.getModule or function() return nil end

    db.Taunt = db.Taunt or {}
    manager:SetCondition("tauntEnabled", function() return db.Taunt.Enabled == true end)

    ----------------------------------------------------------------
    -- Card: Taunt Countdown
    ----------------------------------------------------------------
    local card = GUIFrame:CreateCard(scrollChild, "Taunt Countdown", yOffset)
    manager:Register(card, "all")

    card:AddLabel("|cff888888Shows your taunt cooldown at the cursor. Tank specs only; your class taunt is detected automatically. Nothing is drawn on a non-tank spec.|r")

    local row1 = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local tauntEnable = GUIFrame:CreateCheckbox(row1, "Enable Taunt Countdown", {
        value = db.Taunt.Enabled == true,
        callback = function(checked)
            db.Taunt.Enabled = checked
            refresh()
            refreshStates()
        end,
    })
    row1:AddWidget(tauntEnable, 0.6)
    manager:Register(tauntEnable, "all")

    -- Test button: 7-second preview so users can verify placement without being
    -- on a tank spec. Always enabled (works with the feature off too).
    local tauntTest = GUIFrame:CreateButton(row1, "Test (7s countdown)", {
        height = 30,
        callback = function()
            local mod = getMod()
            if mod and mod.TauntPreview then mod:TauntPreview() end
        end,
    })
    row1:AddWidget(tauntTest, 0.4)
    manager:Register(tauntTest, "all")
    card:AddRow(row1, Theme.rowHeight)

    local rowSep = GUIFrame:CreateRow(card.content, Theme.rowHeightSeparator)
    local sep = GUIFrame:CreateSeparator(rowSep)
    rowSep:AddWidget(sep, 1)
    manager:Register(sep, "all")
    card:AddRow(rowSep, Theme.rowHeightSeparator)

    local row2 = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local tauntAnchor = GUIFrame:CreateDropdown(row2, "Anchor Point", {
        options = {
            { key = "TOP",    text = "Top" },
            { key = "BOTTOM", text = "Bottom" },
            { key = "LEFT",   text = "Left" },
            { key = "RIGHT",  text = "Right" },
            { key = "CENTER", text = "Center" },
        },
        value = db.Taunt.AnchorPoint or "CENTER",
        callback = function(key) db.Taunt.AnchorPoint = key; refresh() end,
    })
    row2:AddWidget(tauntAnchor, 1)
    manager:Register(tauntAnchor, "tauntEnabled")
    card:AddRow(row2, Theme.rowHeight)

    local row3 = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local tauntX = GUIFrame:CreateSlider(row3, "X Offset", {
        min = -50, max = 50, step = 1,
        value = db.Taunt.XOffset or 10,
        callback = function(val) db.Taunt.XOffset = val; refresh() end,
    })
    row3:AddWidget(tauntX, 0.5)
    manager:Register(tauntX, "tauntEnabled")

    local tauntY = GUIFrame:CreateSlider(row3, "Y Offset", {
        min = -50, max = 50, step = 1,
        value = db.Taunt.YOffset or 10,
        callback = function(val) db.Taunt.YOffset = val; refresh() end,
    })
    row3:AddWidget(tauntY, 0.5)
    manager:Register(tauntY, "tauntEnabled")
    card:AddRow(row3, Theme.rowHeight)

    local row4 = GUIFrame:CreateRow(card.content, Theme.rowHeightLast)
    local tauntFontSize = GUIFrame:CreateSlider(row4, "Font Size", {
        min = 8, max = 48, step = 1,
        value = db.Taunt.FontSize or 18,
        callback = function(val) db.Taunt.FontSize = val; refresh() end,
    })
    row4:AddWidget(tauntFontSize, 0.5)
    manager:Register(tauntFontSize, "tauntEnabled")

    local tauntTextColor = GUIFrame:CreateColorPicker(row4, "Text Color", {
        color = db.Taunt.TextColor or { 1, 1, 1, 1 },
        callback = function(r, g, b, a)
            db.Taunt.TextColor = { r, g, b, a }
            refresh()
        end,
    })
    row4:AddWidget(tauntTextColor, 0.5)
    manager:Register(tauntTextColor, "tauntEnabled")
    card:AddRow(row4, Theme.rowHeightLast, 0)

    return card:GetNextOffset()
end

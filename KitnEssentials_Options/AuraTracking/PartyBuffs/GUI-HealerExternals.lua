-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-HealerExternals.lua                                 ║
-- ║  GUI: Party Cooldowns, Healer Externals tab              ║
-- ║  Purpose: the healer externals box and its settings.     ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme    = KE.Theme

local C_Timer = C_Timer

local GROW_OPTIONS = GUIFrame.GrowDirectionOptions

-- Healer Mana's display, keyed by the side the box attaches to. Both draw
-- their borders inside their frames, so an offset of 1 leaves one empty
-- pixel between the two border lines.
local HEALER_MANA = "KitnEssentialsHealerMana"
local ATTACHED = {
    TOP    = { AnchorFrom = "BOTTOMLEFT", AnchorTo = "TOPLEFT",    XOffset = 0, YOffset = 1 },
    BOTTOM = { AnchorFrom = "TOPLEFT",    AnchorTo = "BOTTOMLEFT", XOffset = 0, YOffset = -1 },
}
-- The box's Icon Size slider range; a copied Healer Mana size is held to it.
local ICON_MIN, ICON_MAX = 16, 64

local SIDE_OPTIONS = {
    { key = "TOP",    text = "Top" },
    { key = "BOTTOM", text = "Bottom" },
}

local function GetModule() return KitnEssentials and KitnEssentials:GetModule("PartyBuffs", true) end

GUIFrame:RegisterContent("PartyBuffsHealerExternals", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.PartyBuffs
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local PB = GetModule()
    local Sensor = KE.PartyCooldownsSensor
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if PB and PB.ApplySettings then PB:ApplySettings() end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled == true)
    end

    -- The pressed button is released by the redraw, so the redraw waits a
    -- frame.
    local function RebuildPage()
        if GUIFrame.RefreshContent then
            C_Timer.After(0, function() GUIFrame:RefreshContent() end)
        end
    end

    manager:SetCondition("on", function() return db.HealerExternals == true end)
    manager:SetCondition("text", function() return db.HealerExternals == true and db.HealerExtShowText == true end)

    local function AddCheck(row, label, key, state, tooltip)
        local check = GUIFrame:CreateCheckbox(row, label, {
            value = db[key] == true,
            callback = function(checked)
                db[key] = checked
                ApplySettings()
                RefreshStates()
            end,
            tooltip = tooltip,
        })
        row:AddWidget(check, 0.5)
        manager:Register(check, state)
    end

    local function AddSlider(row, label, key, low, high, state)
        local slider = GUIFrame:CreateSlider(row, label, {
            min = low, max = high, step = 1,
            value = db[key],
            callback = function(val) db[key] = val; ApplySettings() end,
        })
        row:AddWidget(slider, 0.5)
        manager:Register(slider, state)
    end

    ----------------------------------------------------------------
    -- Card: Healer Externals
    ----------------------------------------------------------------
    local cardMain = GUIFrame:CreateCard(scrollChild, "Healer Externals", yOffset)
    cardMain:AddHeaderToggle(db.HealerExternals == true, function(checked)
        db.HealerExternals = checked
        ApplySettings()
    end)
    if Sensor and Sensor.door and not Sensor.DoorOpen() then
        cardMain:AddNote("Healer external timers are unavailable on this client.")
    end
    cardMain:AddLabel("One icon per party healer: full color when their external is ready, gray with the " ..
        "time left once its buff appears on anyone in your party. Your own external is not shown. Shown in a " ..
        "party where the Cooldowns tab's Where It Shows allows, never in a raid or an arena. Another " ..
        "player's cast of the same spell, such as a Retribution Paladin's Blessing of Sacrifice, starts it too.")
    cardMain:AddNote("Move it with /kes edit.")
    local function Attach()
        local points = ATTACHED[db.HealerExtAttachSide] or ATTACHED.TOP
        db.HealerExtAnchorFrameType = "SELECTFRAME"
        db.HealerExtParentFrame = HEALER_MANA
        local p = db.HealerExtPosition
        p.AnchorFrom, p.AnchorTo = points.AnchorFrom, points.AnchorTo
        p.XOffset, p.YOffset = points.XOffset, points.YOffset
        -- The box shows only in a party, so Healer Mana's party size is the
        -- one to match, not its raid twin.
        local hm = KE.db.profile.Dungeons and KE.db.profile.Dungeons.HealerMana
        local size = hm and tonumber(hm.IconSize)
        if size then db.HealerExtIconSize = math.min(ICON_MAX, math.max(ICON_MIN, math.floor(size + 0.5))) end
        ApplySettings()
        RebuildPage()
    end

    local rowM1 = GUIFrame:CreateRow(cardMain.content, Theme.rowHeightLast)
    local attach = GUIFrame:CreateButton(rowM1, "Attach to Healer Mana", {
        height = 24,
        tooltip = "Places the box against the chosen side of the Healer Mana display and keeps it there when " ..
            "that display moves. Also sets the box's Icon Size to Healer Mana's once; you can change it afterward.",
        callback = Attach,
    })
    -- Level with the Side box, which sits 14 px below the dropdown's top.
    rowM1:AddWidget(attach, 0.5, nil, 0, -14)
    manager:Register(attach, "on")
    local side = GUIFrame:CreateDropdown(rowM1, "Side", {
        options = SIDE_OPTIONS,
        value = db.HealerExtAttachSide,
        tooltip = "The side of the Healer Mana display the box attaches to. Grow is not changed: with Top and " ..
            "Grow Down, or Bottom and Grow Up, the icons after the first cover Healer Mana. While attached, a change " ..
            "here attaches again and copies Healer Mana's Icon Size again.",
        callback = function(choice)
            db.HealerExtAttachSide = choice
            if db.HealerExtAnchorFrameType == "SELECTFRAME" and db.HealerExtParentFrame == HEALER_MANA then
                Attach()
            end
        end,
    })
    rowM1:AddWidget(side, 0.5)
    manager:Register(side, "on")
    cardMain:AddRow(rowM1, Theme.rowHeightLast, 0)
    yOffset = cardMain:GetNextOffset()

    ----------------------------------------------------------------
    -- Card: Display
    ----------------------------------------------------------------
    local cardDisplay = GUIFrame:CreateCard(scrollChild, "Display", yOffset)
    cardDisplay:AddLabel("Font face and outline follow the Cooldowns tab's Font Settings.")
    local rowD1 = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeight)
    AddSlider(rowD1, "Icon Size", "HealerExtIconSize", ICON_MIN, ICON_MAX, "on")
    AddSlider(rowD1, "Spacing", "HealerExtSpacing", 0, 20, "on")
    cardDisplay:AddRow(rowD1, Theme.rowHeight)
    local rowD2 = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeight)
    local grow = GUIFrame:CreateDropdown(rowD2, "Grow", {
        options = GROW_OPTIONS,
        value = db.HealerExtGrowth,
        callback = function(choice) db.HealerExtGrowth = choice; ApplySettings() end,
    })
    rowD2:AddWidget(grow, 0.5)
    manager:Register(grow, "on")
    AddCheck(rowD2, "Timer Text", "HealerExtShowText", "on")
    cardDisplay:AddRow(rowD2, Theme.rowHeight)
    local rowD3 = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeightLast)
    AddSlider(rowD3, "Text Size", "HealerExtTextSize", 8, 30, "text")
    cardDisplay:AddRow(rowD3, Theme.rowHeightLast, 0)
    yOffset = cardDisplay:GetNextOffset()

    ----------------------------------------------------------------
    -- Card: Position
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Position",
        db = db,
        positionKey = "HealerExtPosition",
        dbKeys = {
            anchorFrameType = "HealerExtAnchorFrameType", anchorFrameFrame = "HealerExtParentFrame",
            strata = "HealerExtStrata",
        },
        defaults = { anchorFrameType = "UIPARENT", strata = "MEDIUM" },
        showStrata = true,
        onChangeCallback = ApplySettings,
    })
    -- The card's own SetEnabled drives its widgets.
    manager:Register(posCard, "on")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card: Externals
    ----------------------------------------------------------------
    local listCard, listOffset = KE.PartyCooldownsPage.ExternalsCard(scrollChild, yOffset, {
        db = db, apply = ApplySettings,
    })
    manager:Register(listCard, "on")
    yOffset = listOffset

    RefreshStates()
    return yOffset
end)

-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-Tooltips.lua                                        ║
-- ║  GUI: Blizzard Tooltips                                  ║
-- ║  Purpose: Configuration panel for the Tooltips module.   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)

local pairs = pairs
local ipairs = ipairs

local ID_OPTIONS = {
    { key = "NEVER",    text = "Never" },
    { key = "MODIFIER", text = "Holding a Modifier" },
    { key = "ALWAYS",   text = "Always" },
}

local function GetTooltipsModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("SkinTooltips", true)
    end
    return nil
end

local function BuildFontOptions()
    local list = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do list[name] = name end
    else
        list["Expressway"] = "Expressway"
    end
    return list
end

local function BuildStatusbarOptions()
    local list = {}
    if LSM then
        for name in pairs(LSM:HashTable("statusbar")) do list[name] = name end
    else
        list["Blizzard"] = "Blizzard"
    end
    return list
end

GUIFrame:RegisterContent("SkinTooltips", function(scrollChild, yOffset)
    if KE:ShouldNotLoadModule() then return end
    local db = KE.db and KE.db.profile.Skinning.Tooltips
    if not db then return yOffset end

    local TT = GetTooltipsModule()
    local manager = GUIFrame:CreateWidgetStateManager()
    -- Cursor anchoring bypasses the anchor frame, so its controls and the
    -- cursor offsets are never both in use.
    manager:SetCondition("position", function() return db.CursorAnchor ~= true end)
    manager:SetCondition("cursor", function() return db.CursorAnchor == true end)
    -- Every icon-ID line sits behind the Show Spell/Item IDs mode.
    manager:SetCondition("iconIDs", function() return (db.ShowIDs or "MODIFIER") ~= "NEVER" end)
    manager:SetCondition("guildColor", function() return db.GuildColorEnabled ~= false end)
    manager:SetCondition("healthBar", function() return db.HealthBarHidden ~= true end)

    local function ApplySettings()
        if TT and TT.ApplySettings then TT:ApplySettings() end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled == true)
    end

    ----------------------------------------------------------------
    -- Card 1: Tooltips (master enable)
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Tooltips", yOffset)
    card1:AddHeaderToggle(db.Enabled == true, function(checked)
        db.Enabled = checked
        if checked then
            KitnEssentials:EnableModule("SkinTooltips")
        else
            KitnEssentials:DisableModule("SkinTooltips")
            KE:FlagReloadNeeded()
        end
        -- AddHeaderToggle's own OnClick already calls RefreshContent.
    end)
    card1:AddLabel("Skins the game tooltip and its companions: dark backdrop, custom fonts, health bar styling, class-colored names, target line, and spell/item IDs. Visual-only post-hooks; near-zero cost while no tooltip is shown.")

    -- Say WHY it is off when another addon owns the feature -- the
    -- sidebar goes red, but the page itself would otherwise be silent.
    local conflictSrc = KE:GetModuleConflict("SkinTooltips")
    if conflictSrc then
        card1:AddLabel(("|cffff5555Disabled due to a conflict with %s.|r Turn that addon (or its module) off, or enable this one to be prompted again."):format(conflictSrc))
    end

    if db.Enabled ~= true then
        return yOffset + card1:GetContentHeight() + Theme.paddingSmall
    end
    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Position Settings
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        db = db.Position,
        dbKeys = {
            anchorFrameType = "AnchorFrameType",
            anchorFrameFrame = "ParentFrame",
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
            strata = "Strata",
        },
        showAnchorFrameType = true,
        showStrata = true,
        onChangeCallback = function() ApplySettings() end,
    })
    -- Strata still applies to every tooltip under cursor anchoring. The card
    -- itself joins no group: its SetEnabled would grey Strata with it.
    if posCard.positionWidgets then
        for _, widget in ipairs(posCard.positionWidgets) do
            if widget == posCard.strataWidget then
                manager:Register(widget, "all")
            else
                manager:Register(widget, "position")
            end
        end
    end
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 3: General
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "General", yOffset)
    manager:Register(card3, "all")

    local row3a = GUIFrame:CreateRow(card3.content, 40)
    local cursorAnchorCheck = GUIFrame:CreateCheckbox(row3a, "Anchor To Cursor", {
        value = db.CursorAnchor == true,
        tooltip = "Default-anchored tooltips follow the mouse cursor instead.",
        callback = function(checked)
            db.CursorAnchor = checked
            -- Also decides whether the Tooltip mover deserves a box.
            if KE.EditMode then KE.EditMode:RefreshLiveState() end
            ApplySettings()
            RefreshStates()
        end,
    })
    row3a:AddWidget(cursorAnchorCheck, 0.5)
    manager:Register(cursorAnchorCheck, "all")

    local hideInCombatCheck = GUIFrame:CreateCheckbox(row3a, "Hide In Combat", {
        value = db.HideInCombat == true,
        tooltip = "Hides unit tooltips during combat. Hold any modifier key to show them anyway.",
        callback = function(checked) db.HideInCombat = checked; ApplySettings() end,
    })
    row3a:AddWidget(hideInCombatCheck, 0.5)
    manager:Register(hideInCombatCheck, "all")
    card3:AddRow(row3a, 40)

    -- No ApplySettings: the anchor reads both offsets for every tooltip.
    local row3b = GUIFrame:CreateRow(card3.content, 44)
    local cursorXSlider = GUIFrame:CreateSlider(row3b, "Cursor X Offset", {
        min = -128, max = 128, step = 1,
        value = db.CursorOffsetX or 10,
        callback = function(value) db.CursorOffsetX = value end,
    })
    row3b:AddWidget(cursorXSlider, 0.5)
    manager:Register(cursorXSlider, "cursor")

    local cursorYSlider = GUIFrame:CreateSlider(row3b, "Cursor Y Offset", {
        min = -128, max = 128, step = 1,
        value = db.CursorOffsetY or -10,
        callback = function(value) db.CursorOffsetY = value end,
    })
    row3b:AddWidget(cursorYSlider, 0.5)
    manager:Register(cursorYSlider, "cursor")
    card3:AddRow(row3b, 44)

    local row3c = GUIFrame:CreateRow(card3.content, 40)
    local showIDsDropdown = GUIFrame:CreateDropdown(row3c, "Show Spell/Item IDs", {
        options = ID_OPTIONS,
        value = db.ShowIDs or "MODIFIER",
        callback = function(value)
            db.ShowIDs = value
            ApplySettings()
            RefreshStates()
        end,
    })
    row3c:AddWidget(showIDsDropdown, 0.5)
    manager:Register(showIDsDropdown, "all")

    local showIconIDsCheck = GUIFrame:CreateCheckbox(row3c, "Show Icon IDs", {
        value = db.ShowIconIDs == true,
        tooltip = "Adds the icon's file ID beneath the Spell ID and Item ID lines. Needs Show Spell/Item IDs to be showing.",
        callback = function(checked) db.ShowIconIDs = checked; ApplySettings() end,
    })
    row3c:AddWidget(showIconIDsCheck, 0.5)
    manager:Register(showIconIDsCheck, "iconIDs")
    card3:AddRow(row3c, 40, 0)
    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Unit Lines
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Unit Lines", yOffset)
    manager:Register(card4, "all")

    local row4a = GUIFrame:CreateRow(card4.content, 40)
    local classColorCheck = GUIFrame:CreateCheckbox(row4a, "Class Color Names", {
        value = db.ClassColorNames ~= false,
        tooltip = "Colors unit names and the health bar by class (players) or reaction (NPCs).",
        callback = function(checked) db.ClassColorNames = checked; ApplySettings() end,
    })
    row4a:AddWidget(classColorCheck, 0.5)
    manager:Register(classColorCheck, "all")

    local targetLineCheck = GUIFrame:CreateCheckbox(row4a, "Target Line", {
        value = db.TargetLine ~= false,
        tooltip = "Adds a 'Target:' line showing what the unit is targeting.",
        callback = function(checked) db.TargetLine = checked; ApplySettings() end,
    })
    row4a:AddWidget(targetLineCheck, 0.5)
    manager:Register(targetLineCheck, "all")
    card4:AddRow(row4a, 40)

    local row4b = GUIFrame:CreateRow(card4.content, 40)
    local mythicPlusCheck = GUIFrame:CreateCheckbox(row4b, "Mythic+ Score", {
        value = db.MythicPlusLine == true,
        tooltip = "Adds the player's current season Mythic+ rating, coloured by score. Only shows for players the game already has rating data for.",
        callback = function(checked) db.MythicPlusLine = checked; ApplySettings() end,
    })
    row4b:AddWidget(mythicPlusCheck, 0.5)
    manager:Register(mythicPlusCheck, "all")

    local alwaysRealmCheck = GUIFrame:CreateCheckbox(row4b, "Always Show Realm", {
        value = db.AlwaysShowRealm == true,
        tooltip = "Spells out a cross-realm player's realm in full. Off shows Blizzard's short marker instead, which keeps the tooltip narrow.",
        callback = function(checked) db.AlwaysShowRealm = checked; ApplySettings() end,
    })
    row4b:AddWidget(alwaysRealmCheck, 0.5)
    manager:Register(alwaysRealmCheck, "all")
    card4:AddRow(row4b, 40)

    local row4c = GUIFrame:CreateRow(card4.content, 40)
    local hideFactionCheck = GUIFrame:CreateCheckbox(row4c, "Hide Faction Line", {
        value = db.HideFactionLine ~= false,
        tooltip = "Removes the plain 'Alliance' or 'Horde' line. The name and level lines already carry it.",
        callback = function(checked) db.HideFactionLine = checked; ApplySettings() end,
    })
    row4c:AddWidget(hideFactionCheck, 1)
    manager:Register(hideFactionCheck, "all")
    card4:AddRow(row4c, 40)

    card4:AddSeparator()

    local row4d = GUIFrame:CreateRow(card4.content, 40)
    local guildRankCheck = GUIFrame:CreateCheckbox(row4d, "Guild Rank", {
        value = db.GuildRankLine == true,
        tooltip = "Appends the player's guild rank to the guild line: Instant Dollars [Officer].",
        callback = function(checked) db.GuildRankLine = checked; ApplySettings() end,
    })
    row4d:AddWidget(guildRankCheck, 0.5)
    manager:Register(guildRankCheck, "all")

    local hideGuildRealmCheck = GUIFrame:CreateCheckbox(row4d, "Hide Guild Realm", {
        value = db.HideGuildRealm == true,
        tooltip = "Trims the realm from cross-realm guild names: 'Instant Dollars - Mal'Ganis' becomes 'Instant Dollars'.",
        callback = function(checked) db.HideGuildRealm = checked; ApplySettings() end,
    })
    row4d:AddWidget(hideGuildRealmCheck, 0.5)
    manager:Register(hideGuildRealmCheck, "all")
    card4:AddRow(row4d, 40)

    local row4e = GUIFrame:CreateRow(card4.content, 46)
    local guildColorCheck = GUIFrame:CreateCheckbox(row4e, "Custom Guild Color", {
        value = db.GuildColorEnabled ~= false,
        callback = function(checked)
            db.GuildColorEnabled = checked
            ApplySettings()
            RefreshStates()
        end,
    })
    row4e:AddWidget(guildColorCheck, 0.5)
    manager:Register(guildColorCheck, "all")

    local guildColor = db.GuildColor
    local guildColorPicker = GUIFrame:CreateColorPicker(row4e, "Guild Color", {
        color = { guildColor.r or 1, guildColor.g or 1, guildColor.b or 1, 1 },
        callback = function(r, g, b)
            guildColor.r, guildColor.g, guildColor.b = r, g, b
            ApplySettings()
        end,
    })
    row4e:AddWidget(guildColorPicker, 0.5)
    manager:Register(guildColorPicker, "guildColor")
    card4:AddRow(row4e, 46, 0)
    yOffset = card4:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Health Bar
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Health Bar", yOffset)
    manager:Register(card5, "all")

    local row5a = GUIFrame:CreateRow(card5.content, 40)
    local hideHealthBarCheck = GUIFrame:CreateCheckbox(row5a, "Hide Health Bar", {
        value = db.HealthBarHidden == true,
        tooltip = "Fully removes the health bar from unit tooltips.",
        callback = function(checked)
            db.HealthBarHidden = checked
            ApplySettings()
            RefreshStates()
        end,
    })
    row5a:AddWidget(hideHealthBarCheck, 1)
    manager:Register(hideHealthBarCheck, "all")
    card5:AddRow(row5a, 40)

    local row5b = GUIFrame:CreateRow(card5.content, 44)
    local barHeightSlider = GUIFrame:CreateSlider(row5b, "Bar Height", {
        min = 3, max = 20, step = 1,
        value = db.HealthBarHeight or 7,
        callback = function(value) db.HealthBarHeight = value; ApplySettings() end,
    })
    row5b:AddWidget(barHeightSlider, 0.5)
    manager:Register(barHeightSlider, "healthBar")

    local barTextureDropdown = GUIFrame:CreateDropdown(row5b, "Bar Texture", {
        options = BuildStatusbarOptions(),
        searchable = true,
        value = db.HealthBarTexture or "Blizzard",
        callback = function(value) db.HealthBarTexture = value; ApplySettings() end,
    })
    row5b:AddWidget(barTextureDropdown, 0.5)
    manager:Register(barTextureDropdown, "healthBar")
    card5:AddRow(row5b, 44, 0)
    -- No health-text control: the bar carries a 0..1 fraction from
    -- UnitPercentHealthFromGUID, which is SecretReturns, so no current/max
    -- readout is reachable. See StyleHealthBar in Modules/Skinning/Tooltips.lua.
    yOffset = card5:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 6: Font Settings
    ----------------------------------------------------------------
    local card6 = GUIFrame:CreateCard(scrollChild, "Font Settings", yOffset)
    manager:Register(card6, "all")

    local row6a = GUIFrame:CreateRow(card6.content, 40)
    local fontDropdown = GUIFrame:CreateDropdown(row6a, "Font", {
        options = KE:AddFollowGlobalFont(BuildFontOptions()),
        searchable = true,
        value = db.FontFace or KE.FONT_FOLLOW_GLOBAL,
        callback = function(value) db.FontFace = KE:StoredFontFace(value); ApplySettings() end,
    })
    row6a:AddWidget(fontDropdown, 0.5)
    manager:Register(fontDropdown, "all")

    local outlineDropdown = GUIFrame:CreateDropdown(row6a, "Outline", {
        options = KE:GetFontOutlineOptions(),
        value = KE:NormalizeFontOutline(db.FontOutline or "OUTLINE"),
        callback = function(value) db.FontOutline = value; ApplySettings() end,
    })
    row6a:AddWidget(outlineDropdown, 0.5)
    manager:Register(outlineDropdown, "all")
    card6:AddRow(row6a, 40)

    local row6b = GUIFrame:CreateRow(card6.content, 44)
    local fontSizeSlider = GUIFrame:CreateSlider(row6b, "Font Size", {
        min = 8, max = 20, step = 1,
        value = db.FontSize or 12,
        callback = function(value) db.FontSize = value; ApplySettings() end,
    })
    row6b:AddWidget(fontSizeSlider, 0.5)
    manager:Register(fontSizeSlider, "all")

    local headerSizeSlider = GUIFrame:CreateSlider(row6b, "Header Size", {
        min = 8, max = 22, step = 1,
        value = db.HeaderFontSize or 14,
        callback = function(value) db.HeaderFontSize = value; ApplySettings() end,
    })
    row6b:AddWidget(headerSizeSlider, 0.5)
    manager:Register(headerSizeSlider, "all")
    card6:AddRow(row6b, 44)

    local row6c = GUIFrame:CreateRow(card6.content, 44)
    local smallSizeSlider = GUIFrame:CreateSlider(row6c, "Small Text Size", {
        min = 7, max = 18, step = 1,
        value = db.SmallFontSize or 11,
        callback = function(value) db.SmallFontSize = value; ApplySettings() end,
    })
    row6c:AddWidget(smallSizeSlider, 1)
    manager:Register(smallSizeSlider, "all")
    card6:AddRow(row6c, 44, 0)
    yOffset = card6:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 7: Colors
    ----------------------------------------------------------------
    local card7 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    manager:Register(card7, "all")

    local row7a = GUIFrame:CreateRow(card7.content, 46)
    local backdrop = db.BackdropColor
    local backdropPicker = GUIFrame:CreateColorPicker(row7a, "Backdrop Color", {
        color = { backdrop[1] or 0, backdrop[2] or 0, backdrop[3] or 0, backdrop[4] or 0.9 },
        callback = function(r, g, b, a)
            backdrop[1], backdrop[2], backdrop[3], backdrop[4] = r, g, b, a
            ApplySettings()
        end,
    })
    row7a:AddWidget(backdropPicker, 0.5)
    manager:Register(backdropPicker, "all")

    local border = db.BorderColor
    local borderPicker = GUIFrame:CreateColorPicker(row7a, "Border Color", {
        color = { border[1] or 0, border[2] or 0, border[3] or 0, border[4] or 1 },
        callback = function(r, g, b, a)
            border[1], border[2], border[3], border[4] = r, g, b, a
            ApplySettings()
        end,
    })
    row7a:AddWidget(borderPicker, 0.5)
    manager:Register(borderPicker, "all")
    card7:AddRow(row7a, 46, 0)
    yOffset = card7:GetNextOffset()

    RefreshStates()
    return yOffset
end)

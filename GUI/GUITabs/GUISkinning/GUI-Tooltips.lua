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

    local function ApplySettings()
        if TT and TT.ApplySettings then TT:ApplySettings() end
    end

    ----------------------------------------------------------------
    -- Local widget builders — config-table calls only (no positional
    -- GUIFrame:Create* arguments).
    ----------------------------------------------------------------
    local function MkCheck(label, get, set, tooltip)
        return function(row)
            return GUIFrame:CreateCheckbox(row, label, {
                value = get(),
                tooltip = tooltip,
                callback = function(checked) set(checked); ApplySettings() end,
            })
        end, 40
    end
    local function MkSlider(label, min, max, step, get, set)
        return function(row)
            return GUIFrame:CreateSlider(row, label, {
                min = min, max = max, step = step, value = get(),
                callback = function(value) set(value); ApplySettings() end,
            })
        end, 44
    end
    local function MkDropdown(label, options, get, set)
        return function(row)
            return GUIFrame:CreateDropdown(row, label, {
                options = options,
                value = get(),
                callback = function(value) set(value); ApplySettings() end,
            })
        end, 40
    end
    local function MkColor(label, tbl, defaultA)
        return function(row)
            return GUIFrame:CreateColorPicker(row, label, {
                color = { tbl[1] or 0, tbl[2] or 0, tbl[3] or 0, tbl[4] or defaultA or 1 },
                callback = function(r, g, b, a)
                    tbl[1], tbl[2], tbl[3], tbl[4] = r, g, b, a
                    ApplySettings()
                end,
            })
        end, 46
    end
    local function MkKeyedColor(label, tbl)
        return function(row)
            return GUIFrame:CreateColorPicker(row, label, {
                color = { tbl.r or 1, tbl.g or 1, tbl.b or 1, 1 },
                callback = function(r, g, b)
                    tbl.r, tbl.g, tbl.b = r, g, b
                    ApplySettings()
                end,
            })
        end, 46
    end
    -- isLast passes 0 as the row's trailing spacing (the current KE idiom
    -- for a card's final row — Theme.paddingMedium already separates the
    -- card from the next one, so a further paddingSmall would double up).
    local function PairRow(card, builderA, heightA, builderB, heightB, isLast)
        local height = heightB and (heightA > heightB and heightA or heightB) or heightA
        local row = GUIFrame:CreateRow(card.content, height)
        local widgetA = builderA(row)
        row:AddWidget(widgetA, builderB and 0.5 or 1)
        manager:Register(widgetA, "all")
        if builderB then
            local widgetB = builderB(row)
            row:AddWidget(widgetB, 0.5)
            manager:Register(widgetB, "all")
        end
        card:AddRow(row, height, isLast and 0 or nil)
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
    card1:AddLabel("Skins the game tooltip and its companions: dark backdrop, custom fonts, health bar styling, class-colored names, target line, and spell/item IDs. Visual-only post-hooks in the EllesmereUI performance style -- zero cost while no tooltip is shown.")

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
    -- Card 2: Display Settings
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)
    manager:Register(card2, "all")
    PairRow(card2,
        MkCheck("Class Color Names",
            function() return db.ClassColorNames ~= false end,
            function(v) db.ClassColorNames = v end,
            "Colors unit names and the health bar by class (players) or reaction (NPCs)."), 40,
        MkCheck("Target Line",
            function() return db.TargetLine ~= false end,
            function(v) db.TargetLine = v end,
            "Adds a 'Target:' line showing what the unit is targeting."), 40)
    PairRow(card2,
        MkCheck("Guild Rank",
            function() return db.GuildRankLine == true end,
            function(v) db.GuildRankLine = v end,
            "Appends the player's guild rank to the guild line: Instant Dollars [Officer]."), 40,
        MkCheck("Hide Guild Realm",
            function() return db.HideGuildRealm == true end,
            function(v) db.HideGuildRealm = v end,
            "Trims the realm from cross-realm guild names: 'Instant Dollars - Mal'Ganis' becomes 'Instant Dollars'."), 40)
    PairRow(card2,
        MkCheck("Mythic+ Score",
            function() return db.MythicPlusLine == true end,
            function(v) db.MythicPlusLine = v end,
            "Adds the player's current season Mythic+ rating, coloured by score. Only shows for players the game already has rating data for."), 40,
        MkCheck("Hide Faction Line",
            function() return db.HideFactionLine ~= false end,
            function(v) db.HideFactionLine = v end,
            "Removes the plain 'Alliance' or 'Horde' line. The name and level lines already carry it."), 40)
    PairRow(card2,
        MkCheck("Hide In Combat",
            function() return db.HideInCombat == true end,
            function(v) db.HideInCombat = v end,
            "Hides unit tooltips during combat. Hold any modifier key to show them anyway."), 40,
        MkDropdown("Show Spell/Item IDs", ID_OPTIONS,
            function() return db.ShowIDs or "MODIFIER" end,
            function(v) db.ShowIDs = v end), 40)
    PairRow(card2,
        MkCheck("Anchor To Cursor",
            function() return db.CursorAnchor == true end,
            function(v) db.CursorAnchor = v end,
            "Default-anchored tooltips follow the mouse cursor instead."), 40,
        MkCheck("Always Show Realm",
            function() return db.AlwaysShowRealm == true end,
            function(v) db.AlwaysShowRealm = v end,
            "Spells out a cross-realm player's realm in full. Off shows Blizzard's short marker instead, which keeps the tooltip narrow."), 40,
        true)
    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Font
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Font Settings", yOffset)
    manager:Register(card3, "all")
    PairRow(card3,
        MkDropdown("Font", BuildFontOptions(),
            function() return db.FontFace or "Expressway" end,
            function(v) db.FontFace = v end), 40,
        MkDropdown("Outline", KE:GetFontOutlineOptions(),
            function() return db.FontOutline or "OUTLINE" end,
            function(v) db.FontOutline = v end), 40)
    PairRow(card3,
        MkSlider("Font Size", 8, 20, 1,
            function() return db.FontSize or 12 end,
            function(v) db.FontSize = v end), 44,
        MkSlider("Header Size", 8, 22, 1,
            function() return db.HeaderFontSize or 14 end,
            function(v) db.HeaderFontSize = v end), 44)
    PairRow(card3,
        MkSlider("Small Text Size", 7, 18, 1,
            function() return db.SmallFontSize or 11 end,
            function(v) db.SmallFontSize = v end), 44,
        nil, nil, true)
    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Colors
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    manager:Register(card4, "all")
    PairRow(card4,
        MkColor("Backdrop Color", db.BackdropColor, 0.9), 46,
        MkColor("Border Color", db.BorderColor, 1), 46)
    PairRow(card4,
        MkCheck("Custom Guild Color",
            function() return db.GuildColorEnabled ~= false end,
            function(v) db.GuildColorEnabled = v end), 40,
        MkKeyedColor("Guild Color", db.GuildColor), 46,
        true)
    yOffset = card4:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Health Bar
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Health Bar", yOffset)
    manager:Register(card5, "all")

    local healthBarShown = db.HealthBarHidden ~= true
    PairRow(card5,
        MkCheck("Hide Health Bar",
            function() return db.HealthBarHidden == true end,
            function(v) db.HealthBarHidden = v; GUIFrame:RefreshContent() end,
            "Fully removes the health bar from unit tooltips."), 40,
        nil, nil, not healthBarShown)
    -- The bar's appearance rows are meaningless once the bar is hidden --
    -- collapse them like the module card collapses when the module is off
    -- (same RefreshContent pattern as the header toggle).
    if healthBarShown then
        PairRow(card5,
            MkSlider("Bar Height", 3, 20, 1,
                function() return db.HealthBarHeight or 7 end,
                function(v) db.HealthBarHeight = v end), 44,
            MkDropdown("Bar Texture", BuildStatusbarOptions(),
                function() return db.HealthBarTexture or "Blizzard" end,
                function(v) db.HealthBarTexture = v end), 40,
            true)
        -- A "Health Text" toggle and its size slider used to sit here. They
        -- were removed 2026-08-03: 12.0 rebuilt this bar to carry a 0..1
        -- fraction driven by UnitPercentHealthFromGUID, which is declared
        -- SecretReturns unconditionally, so no current/max readout is
        -- reachable. See Modules/Skinning/Tooltips.lua StyleHealthBar.
    end
    yOffset = card5:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 6: Position (KE-only -- appended after the reference's five)
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
    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    manager:Register(posCard, "all")
    yOffset = posOffset

    manager:UpdateAll(db.Enabled == true)
    return yOffset
end)

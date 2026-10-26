-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-PartyStops.lua                                      ║
-- ║  GUI: Party Stops                                        ║
-- ║  Purpose: Configuration panel for the                    ║
-- ║           PartyStops module.                             ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local C_Spell = C_Spell
local C_Timer = C_Timer
local math_pi = math.pi
local pcall, type = pcall, type

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("PartyStops", true)
    end
    return nil
end

-- The compact checkbox is a 22px cell; the arrows sit level with it.
local ROW_HEIGHT = 26
local FOOTER_HEIGHT = 28
-- Unrotated, the arrow points down.
local ARROW_TEXTURE = "Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\collapse.png"

local function SpellLabel(id, className)
    local ok, name = pcall(C_Spell.GetSpellName, id)
    if not (ok and type(name) == "string") then name = "Spell " .. id end
    local okIcon, icon = pcall(C_Spell.GetSpellTexture, id)
    return GUIFrame.IconText(okIcon and icon or nil) .. name .. " (" .. className .. ")"
end

GUIFrame:RegisterContent("PartyStops", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.PartyStops
    if not db then return yOffset end

    local PS = GetModule()
    local Rules = KE.PartyStopsRules
    local Data = KE.PartyStopsData
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if PS then PS:ApplySettings() end
    end

    manager:SetCondition("names", function() return db.ShowNames ~= false end)

    ----------------------------------------------------------------
    -- Card 1: Party Stops
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Party Stops", yOffset)
    card1:AddHeaderToggle(db.Enabled == true, function(checked)
        db.Enabled = checked
        if PS then
            if checked then KitnEssentials:EnableModule("PartyStops")
            else KitnEssentials:DisableModule("PartyStops") end
        end
    end)
    card1:AddLabel("Shows each party member's crowd-control stops (stuns, fears, knockbacks and grips) as " ..
        "icons that count down their cooldowns. A teammate's stop is seen from its debuff on an enemy " ..
        "nameplate, so two teammates of one class both start and a resisted stop shows nothing. Your own " ..
        "stops start from your cast. Works with Party Cooldowns off. Each watched enemy costs one sensor " ..
        "per tracked stop a teammate can have.")
    yOffset = card1:GetNextOffset()

    -- A disabled module shows only this card: its switch and description.
    if db.Enabled ~= true then return yOffset end

    ----------------------------------------------------------------
    -- Card 2: Show In
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Show In", yOffset)
    local row2 = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    row2:AddWidget(GUIFrame:CreateCheckbox(row2, "Only in a Party", {
        value = db.OnlyInParty ~= false,
        tooltip = "Hides the icons while you are solo. They never show in a raid.",
        callback = function(checked)
            db.OnlyInParty = checked
            ApplySettings()
        end,
    }), 0.5)
    row2:AddWidget(GUIFrame:CreateCheckbox(row2, "Only in Dungeons", {
        value = db.OnlyInDungeons == true,
        tooltip = "Shows the icons only inside a 5-player dungeon.",
        callback = function(checked)
            db.OnlyInDungeons = checked
            ApplySettings()
        end,
    }), 0.5)
    card2:AddRow(row2, Theme.rowHeightLast, 0)
    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Spells
    ----------------------------------------------------------------
    db.SpellOff = db.SpellOff or {}
    local card3 = GUIFrame:CreateCard(scrollChild, "Spells", yOffset)
    local row3 = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    row3:AddWidget(GUIFrame:CreateCheckbox(row3, "Include Yourself", {
        value = db.IncludeSelf ~= false,
        callback = function(checked)
            db.IncludeSelf = checked
            ApplySettings()
        end,
    }), 0.5)
    card3:AddRow(row3, Theme.rowHeight)

    local row3b = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    row3b:AddWidget(GUIFrame:CreateSlider(row3b, "Enemies Watched", {
        min = 4, max = 20, step = 1,
        value = Rules.Watched(db.EnemiesWatched),
        tooltip = "How many enemies in combat a single-target stop, like Blind or Hammer of Justice, is read on.",
        callback = function(value)
            db.EnemiesWatched = value
            ApplySettings()
        end,
    }), 0.5)
    row3b:AddWidget(GUIFrame:CreateSlider(row3b, "Enemies Watched, Area Stops", {
        min = 1, max = 20, step = 1,
        value = Rules.Reach(true, db.EnemiesWatched, db.EnemiesWatchedArea),
        tooltip = "How many enemies an area stop, like Shockwave or Chaos Nova, is read on. It lands on " ..
            "several at once, so a few are enough, and each one watched costs frame time in big pulls. " ..
            "Never more than Enemies Watched.",
        callback = function(value)
            db.EnemiesWatchedArea = value
            ApplySettings()
        end,
    }), 0.5)
    card3:AddRow(row3b, Theme.rowHeight)
    card3:AddSeparator()

    -- The spell rows are released by each redraw, so they have a manager of
    -- their own, cleared with them.
    local rowManager = GUIFrame:CreateWidgetStateManager()
    local mark, DrawSpells

    local function Redraw()
        local oldHeight = card3:GetContentHeight()
        card3:TruncateBody(mark)
        rowManager:Clear()
        DrawSpells()
        GUIFrame:ResizeCardInPlace(card3, oldHeight)
    end

    -- The pressed button is released by the redraw, so the redraw waits a
    -- frame.
    local function Move(list, i, delta)
        list[i], list[i + delta] = list[i + delta], list[i]
        db.Spells = list
        ApplySettings()
        C_Timer.After(0, Redraw)
    end

    local function AddSpellRow(list, i)
        local id = list[i]
        local row = GUIFrame:CreateRow(card3.content, ROW_HEIGHT)
        local check = GUIFrame:CreateCompactCheckbox(row, SpellLabel(id, Data.CLASS_NAMES[Data.STOPS[id].class]), {
            value = db.SpellOff[id] ~= true,
            callback = function(checked)
                db.SpellOff[id] = (not checked) or nil
                ApplySettings()
            end,
        })
        row:AddWidget(check, 0.76)
        local up = GUIFrame:CreateButton(row, "", {
            image = ARROW_TEXTURE, imageRotation = math_pi,
            height = 24,
            callback = function() Move(list, i, -1) end,
        })
        row:AddWidget(up, 0.12)
        local down = GUIFrame:CreateButton(row, "", {
            image = ARROW_TEXTURE,
            height = 24,
            callback = function() Move(list, i, 1) end,
        })
        row:AddWidget(down, 0.12)
        rowManager:Register(check, "all")
        if i > 1 then rowManager:Register(up, "all") else up:SetEnabled(false) end
        if i < #list then rowManager:Register(down, "all") else down:SetEnabled(false) end
        card3:AddRow(row, ROW_HEIGHT)
    end

    DrawSpells = function()
        local list = Rules.SpellList(db, Data)
        for i = 1, #list do AddSpellRow(list, i) end
        local footer = GUIFrame:CreateRow(card3.content, FOOTER_HEIGHT)
        local defaults = GUIFrame:CreateButton(footer, "Kitn Defaults", {
            tooltip = "Tracks every stop again, in the shipped order.",
            callback = function()
                db.Spells = nil
                db.SpellOff = {}
                ApplySettings()
                C_Timer.After(0, Redraw)
            end,
        })
        footer:AddWidget(defaults, 0.3)
        rowManager:Register(defaults, "all")
        card3:AddRow(footer, FOOTER_HEIGHT, 0)
        rowManager:UpdateAll(true)
    end

    mark = card3:MarkBody()
    DrawSpells()
    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Display Settings
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)
    local row4a = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    row4a:AddWidget(GUIFrame:CreateSlider(row4a, "Icon Size", {
        min = 16, max = 64, step = 1,
        value = db.IconSize or 38,
        callback = function(value)
            db.IconSize = value
            ApplySettings()
        end,
    }), 0.5)
    row4a:AddWidget(GUIFrame:CreateSlider(row4a, "Spacing", {
        min = -1, max = 20, step = 1,
        value = db.Spacing or 1,
        callback = function(value)
            db.Spacing = value
            ApplySettings()
        end,
    }), 0.5)
    card4:AddRow(row4a, Theme.rowHeight)

    local row4b = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    row4b:AddWidget(GUIFrame:CreateDropdown(row4b, "Grow", {
        options = GUIFrame.GrowDirectionOptions,
        value = db.Grow or "RIGHT",
        callback = function(key)
            db.Grow = key
            ApplySettings()
        end,
    }), 0.5)
    row4b:AddWidget(GUIFrame:CreateSlider(row4b, "Icons Per Row", {
        min = 1, max = 20, step = 1,
        value = Rules.PerRow(db.IconsPerRow),
        callback = function(value)
            db.IconsPerRow = value
            ApplySettings()
        end,
    }), 0.5)
    card4:AddRow(row4b, Theme.rowHeight)

    local row4c = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    row4c:AddWidget(GUIFrame:CreateCheckbox(row4c, "Timer Text", {
        value = db.ShowText ~= false,
        callback = function(checked)
            db.ShowText = checked
            ApplySettings()
        end,
    }), 0.5)
    row4c:AddWidget(GUIFrame:CreateCheckbox(row4c, "Show Names", {
        value = db.ShowNames ~= false,
        tooltip = "Each icon shows its member's nickname, or name, in their class color.",
        callback = function(checked)
            db.ShowNames = checked
            manager:UpdateAll(true)
            ApplySettings()
        end,
    }), 0.5)
    card4:AddRow(row4c, Theme.rowHeight)

    local row4d = GUIFrame:CreateRow(card4.content, Theme.rowHeightLast)
    local nameSize = GUIFrame:CreateSlider(row4d, "Name Size", {
        min = 8, max = 20, step = 1,
        value = db.NameSize or 10,
        callback = function(value)
            db.NameSize = value
            ApplySettings()
        end,
    })
    row4d:AddWidget(nameSize, 0.5)
    manager:Register(nameSize, "names")
    local nameLength = GUIFrame:CreateSlider(row4d, "Name Length (0 = full name)", {
        min = 0, max = 12, step = 1,
        value = db.NameLength or 4,
        callback = function(value)
            db.NameLength = value
            ApplySettings()
        end,
    })
    row4d:AddWidget(nameLength, 0.5)
    manager:Register(nameLength, "names")
    card4:AddRow(row4d, Theme.rowHeightLast, 0)
    yOffset = card4:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Position Settings
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        db = db,
        positionKey = "Position",
        dbKeys = {
            anchorFrameType = "anchorFrameType",
            anchorFrameFrame = "ParentFrame",
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
            strata = "Strata",
        },
        showStrata = true,
        onChangeCallback = ApplySettings,
    })
    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    manager:Register(posCard, "all")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 6: Font Settings
    ----------------------------------------------------------------
    local fontCard, _, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            fontFace    = "FontFace",
            fontOutline = "FontOutline",
        },
        fontSizes = {
            { label = "Text Size", dbKey = "TextSize" },
        },
        fontSizeRange = { 8, 30 },
        onChangeCallback = ApplySettings,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then
        manager:RegisterGroup(fontWidgets, "all")
    end
    yOffset = fontCard:GetNextOffset()

    manager:UpdateAll(true)
    return yOffset
end)

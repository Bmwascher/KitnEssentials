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

local C_Timer = C_Timer
local ipairs = ipairs

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("PartyStops", true)
    end
    return nil
end

local FOOTER_HEIGHT = 28

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
        "stops start from your cast. Works with Party Cooldowns off. A single-target stop, like Blind, " ..
        "watches up to " .. Rules.Reach(false) .. " enemies; an area stop, like Shockwave, lands on several " ..
        "at once and watches up to " .. Rules.Reach(true) .. ".")
    yOffset = card1:GetNextOffset()

    -- A disabled module shows only this card: its switch and description.
    if db.Enabled ~= true then return yOffset end

    ----------------------------------------------------------------
    -- Card 2: Show In
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Show In", yOffset)
    local row2 = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    row2:AddWidget(GUIFrame:CreateCheckbox(row2, "Hide While Solo", {
        value = db.OnlyInParty ~= false,
        tooltip = "Solo, only your own stops can show, and only with Include Yourself ticked. Never shows in a raid.",
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
    card3:AddSeparator()

    -- The pick lives for this build of the page and is never saved.
    local picked
    local classMark, stripMark, DrawRows, DrawStrip

    local function Ticked()
        local off, ids = db.SpellOff, {}
        for _, id in ipairs(Rules.SpellList(db, Data)) do
            if off[id] ~= true then ids[#ids + 1] = id end
        end
        return ids
    end

    local function RedrawStrip()
        local oldHeight = card3:GetContentHeight()
        card3:TruncateBody(stripMark)
        DrawStrip()
        GUIFrame:ResizeCardInPlace(card3, oldHeight)
    end

    local function RedrawAll()
        local oldHeight = card3:GetContentHeight()
        card3:TruncateBody(classMark)
        DrawRows()
        GUIFrame:ResizeCardInPlace(card3, oldHeight)
    end

    -- A clicked icon or a pressed button is released by the redraw, so the
    -- redraw waits a frame.
    local function Pick(id)
        picked = id
        C_Timer.After(0, RedrawStrip)
    end

    local function Move(step)
        local list = Rules.MoveStop(Rules.SpellList(db, Data), db.SpellOff, picked, step)
        if list then
            db.Spells = list
            ApplySettings()
        end
        C_Timer.After(0, RedrawStrip)
    end

    local function StatusLabel(row)
        local label = row:GetLabel("normal")
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        label:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
        return label
    end

    -- Every row here has a fixed height, so a strip redraw never moves the
    -- cards below.
    DrawStrip = function()
        local ids = Ticked()
        local rowHeight = KE.ClassSpellRows.STRIP_ROW_HEIGHT
        local stripRow = GUIFrame:CreateRow(card3.content, rowHeight)
        if #ids > 0 then
            local strip = KE.ClassSpellRows.AcquireOrderStrip("partystops:orderstrip", #Data.ORDER, stripRow)
            strip:ClearAllPoints()
            strip:SetPoint("LEFT", stripRow, "LEFT", 0, 0)
            strip:Configure(ids, picked, Pick)
        else
            local note = StatusLabel(stripRow)
            note:SetPoint("LEFT", stripRow, "LEFT", 0, 0)
            note:SetPoint("RIGHT", stripRow, "RIGHT", 0, 0)
            note:SetText("Nothing is ticked, so Party Stops shows no icons. Tick a stop, or press Kitn Defaults.")
        end
        card3:AddRow(stripRow, rowHeight)

        local moveRow = GUIFrame:CreateRow(card3.content, FOOTER_HEIGHT)
        local left = GUIFrame:CreateButton(moveRow, "Move Left", { callback = function() Move(-1) end })
        moveRow:AddWidget(left, 0.2)
        local right = GUIFrame:CreateButton(moveRow, "Move Right", { callback = function() Move(1) end })
        moveRow:AddWidget(right, 0.2)
        local list = Rules.SpellList(db, Data)
        left:SetEnabled(Rules.MoveStop(list, db.SpellOff, picked, -1) ~= nil)
        right:SetEnabled(Rules.MoveStop(list, db.SpellOff, picked, 1) ~= nil)
        local status = StatusLabel(moveRow)
        status:SetPoint("LEFT", right, "RIGHT", 8, 0)
        status:SetPoint("RIGHT", moveRow, "RIGHT", 0, 0)
        local place = 0
        for i, id in ipairs(ids) do
            if id == picked then place = i end
        end
        if place > 0 then
            status:SetText("Picked: " .. KE.ClassSpellRows.SpellName(picked) .. " (" .. place .. " of " .. #ids .. ")")
        elseif #ids > 0 then
            status:SetText("No icon picked.")
        end
        card3:AddRow(moveRow, FOOTER_HEIGHT)

        local footer = GUIFrame:CreateRow(card3.content, FOOTER_HEIGHT)
        footer:AddWidget(GUIFrame:CreateButton(footer, "Kitn Defaults", {
            tooltip = "Tracks every stop again, in the shipped order.",
            callback = function()
                db.Spells = nil
                db.SpellOff = {}
                picked = nil
                ApplySettings()
                C_Timer.After(0, RedrawAll)
            end,
        }), 0.3)
        card3:AddRow(footer, FOOTER_HEIGHT, 0)
    end

    -- A class lists its stops in shipped order, so the rows stay put when the
    -- icon order moves.
    DrawRows = function()
        local picks = {}
        for _, id in ipairs(Data.ORDER) do
            picks[#picks + 1] = {
                class = Data.STOPS[id].class,
                label = GUIFrame.IconText(KE.ClassSpellRows.SpellIcon(id)) .. KE.ClassSpellRows.SpellName(id),
                value = db.SpellOff[id] ~= true,
                onChange = function(checked)
                    db.SpellOff[id] = (not checked) or nil
                    if not checked and picked == id then picked = nil end
                    ApplySettings()
                    RedrawStrip()
                end,
            }
        end
        KE.ClassSpellRows.Add(card3, picks)
        card3:AddSeparator()
        card3:AddLabel("Icon order, left to right as the icons show. Click an icon, then move it.")
        stripMark = card3:MarkBody()
        DrawStrip()
    end

    classMark = card3:MarkBody()
    DrawRows()
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

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
local CreateFrame = CreateFrame
local GameTooltip = GameTooltip
local ipairs, pcall, type = ipairs, pcall, type

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("PartyStops", true)
    end
    return nil
end

local FOOTER_HEIGHT = 28
-- A 24 px icon, its pick ring 1 px outside it and 2 px thick, then 3 px clear
-- of the next icon: 20 icons take 600 px.
local STRIP_ICON = 24
local STRIP_PITCH = 30
local STRIP_INSET = 3
local STRIP_ROW_HEIGHT = 30
local NO_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local EDGE = "Interface\\Buttons\\WHITE8X8"

local function SpellName(id)
    local ok, name = pcall(C_Spell.GetSpellName, id)
    if ok and type(name) == "string" then return name end
    return "Spell " .. id
end

local function SpellIcon(id)
    local ok, icon = pcall(C_Spell.GetSpellTexture, id)
    if ok then return icon end
    return nil
end

-- One slot per shipped stop, all made here: a pooled object that grows parts
-- after it is built fails its release check.
local function ConstructOrderStrip(parent)
    local strip = CreateFrame("Frame", nil, parent)
    local count = #KE.PartyStopsData.ORDER
    strip:SetSize(2 * STRIP_INSET + count * STRIP_PITCH - (STRIP_PITCH - STRIP_ICON), STRIP_ROW_HEIGHT)
    local slots, owned = {}, { strip }

    for i = 1, count do
        local slot = CreateFrame("Button", nil, strip)
        slot:SetSize(STRIP_ICON, STRIP_ICON)
        slot:SetPoint("TOPLEFT", strip, "TOPLEFT", STRIP_INSET + (i - 1) * STRIP_PITCH, -STRIP_INSET)

        local edge = slot:CreateTexture(nil, "BACKGROUND")
        edge:SetAllPoints(slot)
        edge:SetColorTexture(0, 0, 0, 1)

        local icon = slot:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", slot, "TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -1, 1)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        slot.icon = icon

        local highlight = slot:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints(icon)
        slot.highlight = highlight

        local ring = CreateFrame("Frame", nil, slot, "BackdropTemplate")
        ring:SetPoint("TOPLEFT", slot, "TOPLEFT", -STRIP_INSET, STRIP_INSET)
        ring:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", STRIP_INSET, -STRIP_INSET)
        ring:SetBackdrop({ edgeFile = EDGE, edgeSize = 2 })
        ring:EnableMouse(false)
        ring:Hide()
        slot.ring = ring

        slot:SetScript("OnClick", function(self)
            local onPick = strip._onPick
            if onPick and self.id then onPick(self.id) end
        end)
        slot:SetScript("OnEnter", function(self)
            if not self.id then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(SpellName(self.id), 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        slot:SetScript("OnLeave", function() GameTooltip:Hide() end)

        slots[i] = slot
        owned[#owned + 1] = slot
    end

    -- ids in on-screen order; picked gets the ring; onPick(id) on a click.
    function strip:Configure(ids, picked, onPick)
        self._onPick = onPick
        local accent = Theme.accent
        for i, slot in ipairs(slots) do
            local id = ids[i]
            slot.id = id
            if id then
                slot.icon:SetTexture(SpellIcon(id) or NO_ICON)
                slot.highlight:SetColorTexture(accent[1], accent[2], accent[3], 0.3)
                slot.ring:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
                slot.ring:SetShown(id == picked)
                slot:Show()
            else
                slot:Hide()
            end
        end
    end

    strip._keOwned = owned
    return strip
end

GUIFrame:NewWidgetPool("partystops:orderstrip", ConstructOrderStrip, function(strip)
    strip._onPick = nil
end)

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
        local stripRow = GUIFrame:CreateRow(card3.content, STRIP_ROW_HEIGHT)
        if #ids > 0 then
            local strip = GUIFrame:AcquirePooled("partystops:orderstrip", stripRow)
            strip:ClearAllPoints()
            strip:SetPoint("LEFT", stripRow, "LEFT", 0, 0)
            strip:Configure(ids, picked, Pick)
        else
            local note = StatusLabel(stripRow)
            note:SetPoint("LEFT", stripRow, "LEFT", 0, 0)
            note:SetPoint("RIGHT", stripRow, "RIGHT", 0, 0)
            note:SetText("Nothing is ticked, so Party Stops shows no icons. Tick a stop, or press Kitn Defaults.")
        end
        card3:AddRow(stripRow, STRIP_ROW_HEIGHT)

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
            status:SetText("Picked: " .. SpellName(picked) .. " (" .. place .. " of " .. #ids .. ")")
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
                label = GUIFrame.IconText(SpellIcon(id)) .. SpellName(id),
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

-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-PartySkips.lua                                      ║
-- ║  GUI: Party Cooldowns, Skips tab                         ║
-- ║  Purpose: Shroud and Mass Invisibility countdown bars.   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme    = KE.Theme

local C_Timer = C_Timer

local GROW_OPTIONS = GUIFrame.GrowVerticalOptions

local function GetModule() return KitnEssentials and KitnEssentials:GetModule("PartyBuffs", true) end

GUIFrame:RegisterContent("PartyBuffsSkips", function(scrollChild, yOffset)
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

    -- The Skip Bars card says when no spell is switched on, so a spell switch
    -- also rebuilds the page.
    local function RebuildPage()
        if GUIFrame.RefreshContent then
            C_Timer.After(0, function() GUIFrame:RefreshContent() end)
        end
    end

    manager:SetCondition("skipsOn", function() return db.SkipBars == true end)

    local function AddCheck(row, label, key, tooltip, onChange)
        local check = GUIFrame:CreateCheckbox(row, label, {
            value = db[key] == true,
            callback = function(checked)
                db[key] = checked
                ApplySettings()
                if onChange then onChange() end
            end,
            tooltip = tooltip,
        })
        row:AddWidget(check, 0.5)
        manager:Register(check, "skipsOn")
    end

    local function AddSlider(row, label, key, low, high)
        local slider = GUIFrame:CreateSlider(row, label, {
            min = low, max = high, step = 1,
            value = db[key],
            callback = function(val) db[key] = val; ApplySettings() end,
        })
        row:AddWidget(slider, 0.5)
        manager:Register(slider, "skipsOn")
    end

    local function AddColor(row, label, key)
        local picker = GUIFrame:CreateColorPicker(row, label, {
            color = db[key],
            callback = function(r, g, b, a)
                db[key] = { r, g, b, a }
                QueueApply()
            end,
        })
        row:AddWidget(picker, 0.5)
        manager:Register(picker, "skipsOn")
    end

    ----------------------------------------------------------------
    -- Card: Skip Bars
    ----------------------------------------------------------------
    local cardBars = GUIFrame:CreateCard(scrollChild, "Skip Bars", yOffset)
    cardBars:AddHeaderToggle(db.SkipBars == true, function(checked)
        db.SkipBars = checked
        ApplySettings()
        RefreshStates()
    end)
    cardBars:AddLabel("Countdown bars for Shroud of Concealment and Mass Invisibility on you, whoever cast them. "
        .. "The game draws the time left, so it stays exact in combat and in keys. Where they show is set by the "
        .. KE:Gold("Show In") .. " card on the " .. KE:Gold("General") .. " tab.")
    if db.SkipShroud ~= true and db.SkipMassInvis ~= true then
        cardBars:AddNote("No spell is switched on, so no bar can show.")
    end
    yOffset = cardBars:GetNextOffset()

    ----------------------------------------------------------------
    -- Card: Tracked Spells
    ----------------------------------------------------------------
    local cardSpells = GUIFrame:CreateCard(scrollChild, "Tracked Spells", yOffset)
    local rowS1 = GUIFrame:CreateRow(cardSpells.content, Theme.rowHeight)
    AddCheck(rowS1, "Shroud of Concealment", "SkipShroud", nil, RebuildPage)
    AddColor(rowS1, "Color", "SkipShroudColor")
    cardSpells:AddRow(rowS1, Theme.rowHeight)
    local rowS2 = GUIFrame:CreateRow(cardSpells.content, Theme.rowHeightLast)
    AddCheck(rowS2, "Mass Invisibility", "SkipMassInvis", nil, RebuildPage)
    AddColor(rowS2, "Color", "SkipMassInvisColor")
    cardSpells:AddRow(rowS2, Theme.rowHeightLast, 0)
    yOffset = cardSpells:GetNextOffset()

    ----------------------------------------------------------------
    -- Card: Bar Display
    ----------------------------------------------------------------
    local cardDisplay = GUIFrame:CreateCard(scrollChild, "Bar Display", yOffset)
    local rowD1 = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeight)
    AddSlider(rowD1, "Width", "SkipWidth", 80, 400)
    AddSlider(rowD1, "Height", "SkipHeight", 10, 50)
    cardDisplay:AddRow(rowD1, Theme.rowHeight)
    local rowD2 = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeight)
    AddSlider(rowD2, "Spacing", "SkipSpacing", 0, 20)
    AddSlider(rowD2, "Text Size", "SkipTextSize", 8, 30)
    cardDisplay:AddRow(rowD2, Theme.rowHeight)
    local rowD3 = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeight)
    local grow = GUIFrame:CreateDropdown(rowD3, "Grow", {
        options = GROW_OPTIONS,
        value = db.SkipGrowth,
        callback = function(choice) db.SkipGrowth = choice; ApplySettings() end,
    })
    rowD3:AddWidget(grow, 0.5)
    manager:Register(grow, "skipsOn")
    AddCheck(rowD3, "Show Icon", "SkipShowIcon")
    cardDisplay:AddRow(rowD3, Theme.rowHeight)
    local rowD4 = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeight)
    AddCheck(rowD4, "Show Name", "SkipShowName")
    AddCheck(rowD4, "Show Seconds", "SkipShowTimer")
    cardDisplay:AddRow(rowD4, Theme.rowHeight)
    local rowD5 = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeightLast)
    AddCheck(rowD5, "Show Caster Name", "SkipShowCaster",
        "Writes the name of the player who cast the spell, in their class color, right of the spell name.")
    cardDisplay:AddRow(rowD5, Theme.rowHeightLast, 0)
    yOffset = cardDisplay:GetNextOffset()

    ----------------------------------------------------------------
    -- Card: Position Settings (the same saved position /kes edit moves)
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Position Settings",
        db = db,
        positionKey = "SkipPosition",
        dbKeys = {
            anchorFrameType = "SkipAnchorFrameType", anchorFrameFrame = "SkipParentFrame",
            strata = "SkipStrata",
        },
        defaults = { anchorFrameType = "UIPARENT", strata = "MEDIUM" },
        showStrata = true,
        onChangeCallback = ApplySettings,
    })
    manager:Register(posCard, "skipsOn")
    yOffset = posOffset

    RefreshStates()
    return yOffset
end)

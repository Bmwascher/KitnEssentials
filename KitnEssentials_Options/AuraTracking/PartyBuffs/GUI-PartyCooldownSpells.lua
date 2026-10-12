-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-PartyCooldownSpells.lua                             ║
-- ║  GUI: Party Cooldowns, spell editors                     ║
-- ║  Purpose: the per-class, per-spec cooldown list, each    ║
-- ║           spell with a toggle, seconds and order arrows. ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame

local C_Spell = C_Spell
local C_Timer = C_Timer
local GetSpecializationInfoForSpecID = GetSpecializationInfoForSpecID
local ipairs = ipairs
local pairs = pairs
local tostring = tostring

local Rules = KE.PartyCooldownsRules

local Page = {}
KE.PartyCooldownsPage = Page

-- Tall enough for the seconds box under its label; the checkbox and the
-- arrows sit level with the box.
local ROW_HEIGHT = 40
local BOX_TOP = -14
local CHECK_TOP = -15
local HEADER_HEIGHT = 26
local FOOTER_HEIGHT = 28

local function SpellLabel(spellID, name)
    local icon = C_Spell.GetSpellTexture(spellID)
    name = name or C_Spell.GetSpellName(spellID) or ("Spell " .. spellID)
    if icon then return "|T" .. icon .. ":16:16:0:0:64:64:5:59:5:59|t " .. name end
    return name
end

-- ctx: { db, apply }. The caller registers the card under the Class
-- Cooldowns condition; its rows follow the card's state.
function Page.ClassCooldownsCard(scrollChild, yOffset, ctx)
    local db, apply = ctx.db, ctx.apply
    db.CooldownOff = db.CooldownOff or {}
    db.CooldownSeconds = db.CooldownSeconds or {}
    db.CooldownOrder = db.CooldownOrder or {}

    local card = GUIFrame:CreateCard(scrollChild, "Spells and Cooldowns", yOffset)
    local Sensor = KE.PartyCooldownsSensor
    if not Sensor then
        card:AddNote("This client cannot show cooldown timers, so a ticked spell shows only while its buff is up. Seconds and order do not apply, and every class buff uses the Offensive CDs border color.")
    elseif Sensor.door and not Sensor.DoorOpen() then
        card:AddNote("Cooldown timers for party members are unavailable on this client: their uses show while active but start no gray count.")
    end
    card:AddLabel("Each ticked spell is one more thing watched on every party member. Two or three per spec keeps the cost low.")

    local specsByClass = GUIFrame.GetClassSpecs()
    local classTokens = {}
    for token in pairs(specsByClass) do classTokens[#classTokens + 1] = token end

    -- Two managers: the class row outlives a redraw, the spell rows do not.
    local classManager = GUIFrame:CreateWidgetStateManager()
    local rowManager = GUIFrame:CreateWidgetStateManager()
    local lastEnabled, mark, shownClass, DrawSpecs

    local function Redraw()
        local oldHeight = card:GetContentHeight()
        card:TruncateBody(mark)
        rowManager:Clear()
        DrawSpecs(shownClass)
        GUIFrame:ResizeCardInPlace(card, oldHeight)
    end

    -- The pressed button is released by the redraw, so the redraw waits a
    -- frame.
    local function Move(specID, list, i, delta)
        local order = {}
        for j, entry in ipairs(list) do order[j] = entry.id end
        order[i], order[i + delta] = order[i + delta], order[i]
        db.CooldownOrder[specID] = order
        apply()
        C_Timer.After(0, Redraw)
    end

    -- The first row's up arrow and the last row's down arrow are drawn grayed.
    local function AddSpellRow(specID, list, i)
        local entry = list[i]
        local row = GUIFrame:CreateRow(card.content, ROW_HEIGHT)
        local check = GUIFrame:CreateCompactCheckbox(row, SpellLabel(entry.id), {
            value = not entry.off,
            callback = function(checked)
                if checked then db.CooldownOff[entry.key] = nil else db.CooldownOff[entry.key] = true end
                apply()
            end,
        })
        row:AddWidget(check, 0.5, nil, 0, CHECK_TOP)
        local box
        box = GUIFrame:CreateEditBox(row, "Seconds", {
            value = tostring(entry.cd),
            callback = function(text)
                local value = Rules.ClampSeconds(text)
                if not value then
                    box:SetValue(tostring(entry.cd))
                    return
                end
                if value == entry.listed then
                    db.CooldownSeconds[entry.key] = nil
                else
                    db.CooldownSeconds[entry.key] = value
                end
                box:SetValue(tostring(value))
                if value ~= entry.cd then
                    entry.cd = value
                    apply()
                end
            end,
        })
        row:AddWidget(box, 0.2)
        local up = GUIFrame:CreateButton(row, "^", {
            height = 24,
            callback = function() Move(specID, list, i, -1) end,
        })
        row:AddWidget(up, 0.12, nil, 0, BOX_TOP)
        local down = GUIFrame:CreateButton(row, "v", {
            height = 24,
            callback = function() Move(specID, list, i, 1) end,
        })
        row:AddWidget(down, 0.12, nil, 0, BOX_TOP)
        rowManager:Register(check, "all")
        rowManager:Register(box, "cells")
        if i > 1 then rowManager:Register(up, "cells") else up:SetEnabled(false) end
        if i < #list then rowManager:Register(down, "cells") else down:SetEnabled(false) end
        card:AddRow(row, ROW_HEIGHT)
    end

    DrawSpecs = function(classToken)
        -- Seconds and order apply only where the cooldown cells exist.
        rowManager:SetCondition("cells", function() return KE.PartyCooldownsSensor ~= nil end)
        local currentSpec = KE:GetPlayerSpecId()
        local specs = specsByClass[classToken] or {}
        for _, specID in ipairs(specs) do
            local _, name, _, icon = GetSpecializationInfoForSpecID(specID)
            local header = GUIFrame:CreateSpecHeaderRow(card.content, name or ("Spec " .. specID),
                { icon = icon, current = specID == currentSpec })
            card:AddRow(header, HEADER_HEIGHT)
            local list = Rules.SpellList(specID, db, true)
            if #list == 0 then card:AddLabel("No cooldowns listed for this spec.") end
            for i = 1, #list do AddSpellRow(specID, list, i) end
        end
        local footer = GUIFrame:CreateRow(card.content, FOOTER_HEIGHT)
        local defaults = GUIFrame:CreateButton(footer, "Kitn Defaults", {
            tooltip = "Restores every spell of this class: switched on, at its listed length, in its listed order.",
            callback = function()
                for _, specID in ipairs(specs) do
                    for _, entry in ipairs(Rules.SpellList(specID, {}, true)) do
                        db.CooldownOff[entry.key] = nil
                        db.CooldownSeconds[entry.key] = nil
                    end
                    db.CooldownOrder[specID] = nil
                end
                apply()
                C_Timer.After(0, Redraw)
            end,
        })
        footer:AddWidget(defaults, 0.3)
        rowManager:Register(defaults, "all")
        card:AddRow(footer, FOOTER_HEIGHT, 0)
        if lastEnabled ~= nil then rowManager:UpdateAll(lastEnabled) end
    end

    local classRow
    classRow, shownClass = GUIFrame:CreateClassPickerRow(card.content, {
        scope = "PartyBuffsCooldowns",
        classTokens = classTokens,
        onPick = function(key)
            shownClass = key
            Redraw()
        end,
    })
    classManager:Register(classRow, "all")
    card:AddRow(classRow, 36)
    mark = card:MarkBody()
    DrawSpecs(shownClass)

    local baseSetEnabled = card.SetEnabled
    function card:SetEnabled(enabled)
        if baseSetEnabled then baseSetEnabled(self, enabled) end
        lastEnabled = enabled
        classManager:UpdateAll(enabled)
        rowManager:UpdateAll(enabled)
    end

    return card, card:GetNextOffset()
end

-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-PartyCooldownSpells.lua                             ║
-- ║  GUI: Party Cooldowns, spell editors                     ║
-- ║  Purpose: the per-class, per-spec cooldown list, each    ║
-- ║           spell with a toggle and order arrows.          ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame

local C_CreatureInfo = C_CreatureInfo
local C_Spell = C_Spell
local C_Timer = C_Timer
local GetSpecializationInfoForSpecID = GetSpecializationInfoForSpecID
local ipairs = ipairs
local math_pi = math.pi
local pairs = pairs
local pcall = pcall
local table_sort = table.sort
local type = type

local Rules = KE.PartyCooldownsRules

local Page = {}
KE.PartyCooldownsPage = Page

-- A list as Kitn Defaults ships it.
function Page.ShippedList(listKey)
    if not KE.GetDefaultDB then return {} end
    local root = KE:GetDefaultDB()
    local section = root and root.profile and root.profile.PartyBuffs
    return (section and section[listKey]) or {}
end

-- The compact checkbox is a 22px cell; the arrows sit level with it.
local ROW_HEIGHT = 26
local HEADER_HEIGHT = 26
local FOOTER_HEIGHT = 28
-- Unrotated, the arrow points down.
local ARROW_TEXTURE = "Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\collapse.png"

local function SpellLabel(spellID, name)
    local icon = C_Spell.GetSpellTexture(spellID)
    name = name or C_Spell.GetSpellName(spellID) or ("Spell " .. spellID)
    if icon then return "|T" .. icon .. ":16:16:0:0:64:64:5:59:5:59|t " .. name end
    return name
end

local function RacialLabel(spellID, raceID)
    local ok, info = pcall(C_CreatureInfo.GetRaceInfo, raceID)
    local race = ok and type(info) == "table" and info.raceName or nil
    local name = C_Spell.GetSpellName(spellID) or ("Spell " .. spellID)
    if type(race) == "string" and race ~= "" then name = name .. " (" .. race .. ")" end
    return SpellLabel(spellID, name)
end

local function ChargeText(entry, specID)
    if (entry.charges or 1) >= 2 then return " (2 charges)" end
    for _, mod in ipairs(entry.spell and entry.spell.mods or {}) do
        if mod.charges and mod[1] and not (mod.spec and mod.spec ~= specID) then
            local talent = C_Spell.GetSpellName(mod[1])
            if type(talent) ~= "string" or talent == "" then talent = "a talent" end
            return " (2 charges with " .. talent .. ")"
        end
    end
    return ""
end

local function AddToggle(row, label, entry, db, apply, width)
    local check = GUIFrame:CreateCompactCheckbox(row, label, {
        value = not entry.off,
        callback = function(checked)
            if not checked then
                db.CooldownOff[entry.key] = true
            elseif entry.spell and entry.spell.off then
                -- false keeps a row that starts switched off on.
                db.CooldownOff[entry.key] = false
            else
                db.CooldownOff[entry.key] = nil
            end
            apply()
        end,
    })
    row:AddWidget(check, width)
    return check
end

-- ctx: { db, apply }. The caller registers the card under the Class
-- Cooldowns condition; its rows follow the card's state.
function Page.ClassCooldownsCard(scrollChild, yOffset, ctx)
    local db, apply = ctx.db, ctx.apply
    db.CooldownOff = db.CooldownOff or {}
    db.CooldownOrder = db.CooldownOrder or {}

    local card = GUIFrame:CreateCard(scrollChild, "Spells and Cooldowns", yOffset)
    local Sensor = KE.PartyCooldownsSensor
    if not Sensor then
        card:AddNote("This client cannot show cooldown timers, so a ticked spell shows only while its buff is up. Order does not apply, and every class buff uses the " .. KE:Gold("Offensive CDs") .. " border color on the " .. KE:Gold("General") .. " tab.")
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

    local function AddSpellRow(specID, list, i)
        local entry = list[i]
        local row = GUIFrame:CreateRow(card.content, ROW_HEIGHT)
        local name = (C_Spell.GetSpellName(entry.id) or ("Spell " .. entry.id)) .. ChargeText(entry, specID)
        local check = AddToggle(row, SpellLabel(entry.id, name), entry, db, apply, 0.76)
        local up = GUIFrame:CreateButton(row, "", {
            image = ARROW_TEXTURE, imageRotation = math_pi,
            height = 24,
            callback = function() Move(specID, list, i, -1) end,
        })
        row:AddWidget(up, 0.12)
        local down = GUIFrame:CreateButton(row, "", {
            image = ARROW_TEXTURE,
            height = 24,
            callback = function() Move(specID, list, i, 1) end,
        })
        row:AddWidget(down, 0.12)
        rowManager:Register(check, "all")
        if i > 1 then rowManager:Register(up, "cells") else up:SetEnabled(false) end
        if i < #list then rowManager:Register(down, "cells") else down:SetEnabled(false) end
        card:AddRow(row, ROW_HEIGHT)
    end

    DrawSpecs = function(classToken)
        -- Order applies only where the cooldown cells exist.
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
            tooltip = "Restores every spell of this class: switched on or off as it starts, in its listed order.",
            callback = function()
                for _, specID in ipairs(specs) do
                    for _, entry in ipairs(Rules.SpellList(specID, {}, true)) do
                        db.CooldownOff[entry.key] = nil
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

-- ctx: { db, apply }. The caller registers the card under the racialsOn
-- state group. A member has one racial, so the rows have no order arrows.
function Page.RacialsCard(scrollChild, yOffset, ctx)
    local db, apply = ctx.db, ctx.apply
    db.CooldownOff = db.CooldownOff or {}
    local card = GUIFrame:CreateCard(scrollChild, "Racials", yOffset)
    card:AddLabel("A party member of one of these races shows the racial after their spec's spells.")
    local manager = GUIFrame:CreateWidgetStateManager()
    for _, racial in ipairs(KE.PartyCooldownsData.RACIALS) do
        local entry = Rules.RacialEntry(racial.id, db, true)
        if entry then
            local row = GUIFrame:CreateRow(card.content, ROW_HEIGHT)
            manager:Register(AddToggle(row, RacialLabel(racial.id, racial.raceID), entry, db, apply, 1), "all")
            card:AddRow(row, ROW_HEIGHT)
        end
    end
    local footer = GUIFrame:CreateRow(card.content, FOOTER_HEIGHT)
    local defaults = GUIFrame:CreateButton(footer, "Kitn Defaults", {
        tooltip = "Restores every racial: switched on.",
        callback = function()
            for key in pairs(db.CooldownOff) do
                if type(key) == "string" and key:sub(1, 5) == "race:" then db.CooldownOff[key] = nil end
            end
            apply()
            C_Timer.After(0, function() GUIFrame:RefreshContent() end)
        end,
    })
    footer:AddWidget(defaults, 0.3)
    manager:Register(defaults, "all")
    card:AddRow(footer, FOOTER_HEIGHT, 0)

    local baseSetEnabled = card.SetEnabled
    function card:SetEnabled(enabled)
        if baseSetEnabled then baseSetEnabled(self, enabled) end
        manager:UpdateAll(enabled)
    end

    return card, card:GetNextOffset()
end

-- A box row's owner as its label names it: the spec with one spec, else the
-- class.
local function BoxRowOwner(row)
    local only, count = nil, 0
    for specID in pairs(row.specs) do
        only, count = specID, count + 1
    end
    if count == 1 then
        local _, specName = GetSpecializationInfoForSpecID(only)
        if type(specName) == "string" and specName ~= "" then return specName end
    end
    local names = _G.LOCALIZED_CLASS_NAMES_MALE
    return (names and names[row.class]) or row.class
end

-- ctx: { db, apply }. The caller registers the card under the Raid
-- Cooldowns condition. One row per healer spec's external, by spec ID (the
-- data is keyed by spec), then one per box row in table order.
function Page.ExternalsCard(scrollChild, yOffset, ctx)
    local db, apply = ctx.db, ctx.apply
    db.CooldownOff = db.CooldownOff or {}
    local HXRules = KE.HealerExternalsRules
    local card = GUIFrame:CreateCard(scrollChild, "Spells", yOffset)
    card:AddLabel("The time counts from the moment the buff appears, for the caster's cooldown with their talents once they are read.")
    local manager = GUIFrame:CreateWidgetStateManager()
    local function AddSpell(entry, name)
        local row = GUIFrame:CreateRow(card.content, ROW_HEIGHT)
        manager:Register(AddToggle(row, SpellLabel(entry.id, name), entry, db, apply, 1), "all")
        card:AddRow(row, ROW_HEIGHT)
    end
    local specs = {}
    for specID in pairs(KE.PartyCooldownsData.HEALER_SPECS) do specs[#specs + 1] = specID end
    table_sort(specs)
    for _, specID in ipairs(specs) do
        local _, specName = GetSpecializationInfoForSpecID(specID)
        for _, entry in ipairs(HXRules.Entries(specID, db, true)) do
            local name = C_Spell.GetSpellName(entry.id) or ("Spell " .. entry.id)
            name = name .. ChargeText(entry, specID)
            if type(specName) == "string" and specName ~= "" then name = name .. " (" .. specName .. ")" end
            AddSpell(entry, name)
        end
    end
    for _, boxRow in ipairs(KE.PartyCooldownsData.BOX_ROWS) do
        local entry = HXRules.BoxEntry(boxRow, nil, db, true)
        if entry then
            local name = (C_Spell.GetSpellName(entry.id) or ("Spell " .. entry.id)) .. " (" .. BoxRowOwner(boxRow) .. ")"
            local swap = entry.spell.swap
            if swap then
                name = name .. " (" .. (C_Spell.GetSpellName(swap.id) or ("Spell " .. swap.id)) .. " with that talent)"
            end
            AddSpell(entry, name)
        end
    end
    local footer = GUIFrame:CreateRow(card.content, FOOTER_HEIGHT)
    local defaults = GUIFrame:CreateButton(footer, "Kitn Defaults", {
        tooltip = "Restores every spell: switched on.",
        callback = function()
            for key in pairs(db.CooldownOff) do
                if type(key) == "string" and (key:sub(1, 7) == "healer:" or key:sub(1, 4) == "box:") then
                    db.CooldownOff[key] = nil
                end
            end
            apply()
            C_Timer.After(0, function() GUIFrame:RefreshContent() end)
        end,
    })
    footer:AddWidget(defaults, 0.3)
    manager:Register(defaults, "all")
    card:AddRow(footer, FOOTER_HEIGHT, 0)

    local baseSetEnabled = card.SetEnabled
    function card:SetEnabled(enabled)
        if baseSetEnabled then baseSetEnabled(self, enabled) end
        manager:UpdateAll(enabled)
    end

    return card, card:GetNextOffset()
end


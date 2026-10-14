-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-PartyCooldownSpells.lua                             ║
-- ║  GUI: Party Cooldowns, spell editors                     ║
-- ║  Purpose: the per-class, per-spec cooldown list, each    ║
-- ║           spell with a toggle, seconds and order arrows. ║
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
local tostring = tostring
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

-- Tall enough for the seconds box under its label; the checkbox and the
-- arrows sit level with the box.
local ROW_HEIGHT = 40
local BOX_TOP = -14
local CHECK_TOP = -15
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

-- An editor row's toggle and seconds box, for an entry with key, off, cd and
-- listed. A length typed equal to the listed one is stored as no override.
local function AddToggle(row, label, entry, db, apply)
    local check = GUIFrame:CreateCompactCheckbox(row, label, {
        value = not entry.off,
        callback = function(checked)
            if checked then db.CooldownOff[entry.key] = nil else db.CooldownOff[entry.key] = true end
            apply()
        end,
    })
    row:AddWidget(check, 0.5, nil, 0, CHECK_TOP)
    return check
end

-- clamp limits a typed length: the party cooldowns clamp unless given.
local function AddSecondsBox(row, entry, db, apply, clamp)
    clamp = clamp or Rules.ClampSeconds
    local box
    box = GUIFrame:CreateEditBox(row, "Spell CD", {
        value = tostring(entry.cd),
        callback = function(text)
            local value = clamp(text)
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
    return box
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
        card:AddNote("This client cannot show cooldown timers, so a ticked spell shows only while its buff is up. Spell CD and order do not apply, and every class buff uses the Offensive CDs border color.")
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
        local check = AddToggle(row, SpellLabel(entry.id), entry, db, apply)
        local box = AddSecondsBox(row, entry, db, apply)
        local up = GUIFrame:CreateButton(row, "", {
            image = ARROW_TEXTURE, imageRotation = math_pi,
            height = 24,
            callback = function() Move(specID, list, i, -1) end,
        })
        row:AddWidget(up, 0.12, nil, 0, BOX_TOP)
        local down = GUIFrame:CreateButton(row, "", {
            image = ARROW_TEXTURE,
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

-- ctx: { db, apply }. The caller registers the card under the Show Racials
-- condition. A member has one racial, so the rows have no order arrows.
function Page.RacialsCard(scrollChild, yOffset, ctx)
    local db, apply = ctx.db, ctx.apply
    db.CooldownOff = db.CooldownOff or {}
    db.CooldownSeconds = db.CooldownSeconds or {}
    local card = GUIFrame:CreateCard(scrollChild, "Racials", yOffset)
    card:AddLabel("A party member of one of these races shows the racial after their spec's spells.")
    local manager = GUIFrame:CreateWidgetStateManager()
    for _, racial in ipairs(KE.PartyCooldownsData.RACIALS) do
        local entry = Rules.RacialEntry(racial.id, db, true)
        if entry then
            local row = GUIFrame:CreateRow(card.content, ROW_HEIGHT)
            manager:Register(AddToggle(row, RacialLabel(racial.id, racial.raceID), entry, db, apply), "all")
            manager:Register(AddSecondsBox(row, entry, db, apply), "all")
            card:AddRow(row, ROW_HEIGHT)
        end
    end
    local footer = GUIFrame:CreateRow(card.content, FOOTER_HEIGHT)
    local defaults = GUIFrame:CreateButton(footer, "Kitn Defaults", {
        tooltip = "Restores every racial: switched on, at its listed length.",
        callback = function()
            for _, saved in ipairs({ db.CooldownOff, db.CooldownSeconds }) do
                for key in pairs(saved) do
                    if type(key) == "string" and key:sub(1, 5) == "race:" then saved[key] = nil end
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

-- ctx: { db, apply }. The caller registers the card under the Healer
-- Externals condition. One row per healer spec's external, by spec ID (the
-- data is keyed by spec); a typed length stops at the box's own cap.
function Page.ExternalsCard(scrollChild, yOffset, ctx)
    local db, apply = ctx.db, ctx.apply
    db.CooldownOff = db.CooldownOff or {}
    db.CooldownSeconds = db.CooldownSeconds or {}
    local HXRules = KE.HealerExternalsRules
    local card = GUIFrame:CreateCard(scrollChild, "Externals", yOffset)
    card:AddLabel("The time counts from the moment the buff appears, for the Spell CD set here, which can differ from the healer's real cooldown.")
    local manager = GUIFrame:CreateWidgetStateManager()
    local specs = {}
    for specID in pairs(KE.PartyCooldownsData.HEALER_SPECS) do specs[#specs + 1] = specID end
    table_sort(specs)
    for _, specID in ipairs(specs) do
        local _, specName = GetSpecializationInfoForSpecID(specID)
        for _, entry in ipairs(HXRules.Entries(specID, db, true)) do
            local name = C_Spell.GetSpellName(entry.id) or ("Spell " .. entry.id)
            if type(specName) == "string" and specName ~= "" then name = name .. " (" .. specName .. ")" end
            local row = GUIFrame:CreateRow(card.content, ROW_HEIGHT)
            manager:Register(AddToggle(row, SpellLabel(entry.id, name), entry, db, apply), "all")
            manager:Register(AddSecondsBox(row, entry, db, apply, HXRules.ClampSeconds), "all")
            card:AddRow(row, ROW_HEIGHT)
        end
    end
    local footer = GUIFrame:CreateRow(card.content, FOOTER_HEIGHT)
    local defaults = GUIFrame:CreateButton(footer, "Kitn Defaults", {
        tooltip = "Restores every external: switched on, at its listed length.",
        callback = function()
            for _, saved in ipairs({ db.CooldownOff, db.CooldownSeconds }) do
                for key in pairs(saved) do
                    if type(key) == "string" and key:sub(1, 7) == "healer:" then saved[key] = nil end
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

-- One seconds box per switched-on row of the Trinkets list. Empty means the
-- length is read from the item in the game.
function Page.TrinketCooldownsCard(scrollChild, yOffset, ctx)
    local db, apply = ctx.db, ctx.apply
    db.CooldownSeconds = db.CooldownSeconds or {}
    local card = GUIFrame:CreateCard(scrollChild, "Trinket Cooldowns", yOffset)
    card:AddLabel("A trinket's cooldown is read from the item itself. Type seconds only to replace it.")
    card:AddNote("A row's seconds apply only to a trinket whose use spell is that row's buff. A trinket whose buff has another ID gets no cooldown icon, shows while active, and ignores its row's seconds.")
    local ids = {}
    for spellID in pairs(KE.AuraRules.BuildIncludeSpellIDs(db.ListTrinkets)) do ids[#ids + 1] = spellID end
    table_sort(ids)
    if #ids == 0 then card:AddLabel("No trinket on the list above is switched on.") end
    local manager = GUIFrame:CreateWidgetStateManager()
    for _, spellID in ipairs(ids) do
        local key = Rules.TrinketKey(spellID)
        local saved = db.ListTrinkets[spellID]
        local row = GUIFrame:CreateRow(card.content, ROW_HEIGHT)
        local name = GUIFrame:CreateText(row, "", SpellLabel(spellID, saved and saved.label),
            ROW_HEIGHT + CHECK_TOP, "hide")
        row:AddWidget(name, 0.6, nil, 0, CHECK_TOP)
        local function Shown()
            local typed = db.CooldownSeconds[key]
            return typed and tostring(typed) or ""
        end
        local box
        box = GUIFrame:CreateEditBox(row, "Seconds", {
            value = Shown(),
            callback = function(text)
                if text == "" then
                    if db.CooldownSeconds[key] ~= nil then
                        db.CooldownSeconds[key] = nil
                        apply()
                    end
                    return
                end
                local value = Rules.ClampSeconds(text)
                if not value then
                    box:SetValue(Shown())
                    return
                end
                if db.CooldownSeconds[key] ~= value then
                    db.CooldownSeconds[key] = value
                    apply()
                end
                box:SetValue(tostring(value))
            end,
        })
        row:AddWidget(box, 0.2)
        manager:Register(box, "all")
        card:AddRow(row, ROW_HEIGHT)
    end
    local footer = GUIFrame:CreateRow(card.content, FOOTER_HEIGHT)
    local defaults = GUIFrame:CreateButton(footer, "Kitn Defaults", {
        tooltip = "Clears every typed trinket length, so each is read from the item again.",
        callback = function()
            for typedKey in pairs(db.CooldownSeconds) do
                if type(typedKey) == "string" and typedKey:sub(1, 8) == "trinket:" then
                    db.CooldownSeconds[typedKey] = nil
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

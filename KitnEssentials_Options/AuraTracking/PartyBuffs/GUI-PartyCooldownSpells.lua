-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-PartyCooldownSpells.lua                             ║
-- ║  GUI: Party Cooldowns, spell editors                     ║
-- ║  Purpose: the per-class, per-spec cooldown list, each    ║
-- ║           spell with a toggle and order arrows.          ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local C_CreatureInfo = C_CreatureInfo
local C_Spell = C_Spell
local C_Timer = C_Timer
local GetSpecializationInfoForSpecID = GetSpecializationInfoForSpecID
local ipairs = ipairs
local math_pi = math.pi
local pairs = pairs
local pcall = pcall
local table_concat = table.concat
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

local function ChargePhrase(entry, specID)
    if (entry.charges or 1) >= 2 then return "2 charges" end
    for _, mod in ipairs(entry.spell and entry.spell.mods or {}) do
        if mod.charges and mod[1] and not (mod.spec and mod.spec ~= specID) then
            local talent = C_Spell.GetSpellName(mod[1])
            if type(talent) ~= "string" or talent == "" then talent = "a talent" end
            return "2 charges with " .. talent
        end
    end
    return nil
end

local function ChargeText(entry, specID)
    local phrase = ChargePhrase(entry, specID)
    if phrase then return " (" .. phrase .. ")" end
    return ""
end

local function WriteSwitch(db, entry, checked)
    if not checked then
        db.CooldownOff[entry.key] = true
    elseif entry.spell and entry.spell.off then
        -- false keeps a row that starts switched off on.
        db.CooldownOff[entry.key] = false
    else
        db.CooldownOff[entry.key] = nil
    end
end

local function AddToggle(row, label, entry, db, apply, width)
    local check = GUIFrame:CreateCompactCheckbox(row, label, {
        value = not entry.off,
        callback = function(checked)
            WriteSwitch(db, entry, checked)
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

-- The spec of a box row with exactly one, else nil.
local function BoxRowSpec(row)
    local only, count = nil, 0
    for specID in pairs(row.specs) do
        only, count = specID, count + 1
    end
    if count == 1 then return only end
    return nil
end

local function SpecSentence(specID)
    local _, name = GetSpecializationInfoForSpecID(specID)
    if type(name) == "string" and name ~= "" then return name .. "." end
    return nil
end

-- The hover text a label no longer carries: the owner spec, a healer
-- external's charge talent, a box row's talent swap.
local function SpellTooltip(entry, specID, boxRow)
    local parts = {}
    if boxRow then
        local only = BoxRowSpec(boxRow)
        if only then
            parts[#parts + 1] = SpecSentence(only)
        else
            parts[#parts + 1] = "Any spec."
        end
        local swap = entry.spell.swap
        if swap then
            parts[#parts + 1] = "Shows " .. (C_Spell.GetSpellName(swap.id) or ("Spell " .. swap.id)) .. " with that talent."
        end
    else
        parts[#parts + 1] = SpecSentence(specID)
        local charges = ChargePhrase(entry, specID)
        if charges then parts[#parts + 1] = charges .. "." end
    end
    if #parts == 0 then return nil end
    return table_concat(parts, " ")
end

local STRIP_KIND = "raidcd:orderstrip"
-- 24 icons at the strip's default 30 px overrun the card at the narrowest
-- window; 28 still keeps the pick ring clear of the next icon.
local STRIP_PITCH = 28

-- ctx: { db, apply }. The caller registers the card under the Raid
-- Cooldowns condition. The class rows list each class's spells as
-- CastOrder ships them; the strip under them sets the box's icon order.
function Page.ExternalsCard(scrollChild, yOffset, ctx)
    local db, apply = ctx.db, ctx.apply
    db.CooldownOff = db.CooldownOff or {}
    local HXRules = KE.HealerExternalsRules
    local data = KE.PartyCooldownsData
    local MoveStop = KE.PartyStopsRules.MoveStop
    local Rows = KE.ClassSpellRows
    local card = GUIFrame:CreateCard(scrollChild, "Spells", yOffset)
    card:AddLabel("The time counts from the moment the buff appears, for the caster's cooldown with their talents once they are read.")

    -- Two managers: the class rows outlive a strip redraw, the strip rows do
    -- not.
    local rowManager = GUIFrame:CreateWidgetStateManager()
    local stripManager = GUIFrame:CreateWidgetStateManager()
    -- The pick lives for this build of the page and is never saved.
    local picked, lastEnabled, stripMark, DrawStrip, left, right
    local casts = {}

    local function OffSet()
        local off = {}
        for id, entry in pairs(casts) do
            if Rules.IsOff(db.CooldownOff, entry.key, entry.spell) then off[id] = true end
        end
        return off
    end

    local function Ticked(full, off)
        local ids = {}
        for _, id in ipairs(full) do
            if casts[id] and not off[id] then ids[#ids + 1] = id end
        end
        return ids
    end

    -- A move button is enabled only where the move rule allows the move.
    local function MoveState()
        if not (left and right) then return end
        local full, off = HXRules.CastOrder(db.HealerExtOrder), OffSet()
        local on = lastEnabled ~= false
        left:SetEnabled(on and MoveStop(full, off, picked, -1) ~= nil)
        right:SetEnabled(on and MoveStop(full, off, picked, 1) ~= nil)
    end

    local function RedrawStrip()
        local oldHeight = card:GetContentHeight()
        card:TruncateBody(stripMark)
        DrawStrip()
        GUIFrame:ResizeCardInPlace(card, oldHeight)
    end

    -- A clicked icon or a pressed button is released by the redraw, so the
    -- redraw waits a frame.
    local function Pick(id)
        picked = id
        C_Timer.After(0, RedrawStrip)
    end

    local function Move(step)
        local list = MoveStop(HXRules.CastOrder(db.HealerExtOrder), OffSet(), picked, step)
        if list then
            db.HealerExtOrder = list
            apply()
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
        stripManager:Clear()
        local full, off = HXRules.CastOrder(db.HealerExtOrder), OffSet()
        local ids = Ticked(full, off)
        local rowHeight = Rows.STRIP_ROW_HEIGHT
        local stripRow = GUIFrame:CreateRow(card.content, rowHeight)
        if #ids > 0 then
            local strip = Rows.AcquireOrderStrip(STRIP_KIND, #HXRules.CastOrder(nil), stripRow, STRIP_PITCH)
            strip:ClearAllPoints()
            strip:SetPoint("LEFT", stripRow, "LEFT", 0, 0)
            strip:Configure(ids, picked, Pick)
        else
            local note = StatusLabel(stripRow)
            note:SetPoint("LEFT", stripRow, "LEFT", 0, 0)
            note:SetPoint("RIGHT", stripRow, "RIGHT", 0, 0)
            note:SetText("Nothing is ticked, so the box shows no icons. Tick a spell, or press Kitn Defaults.")
        end
        card:AddRow(stripRow, rowHeight)

        local moveRow = GUIFrame:CreateRow(card.content, FOOTER_HEIGHT)
        left = GUIFrame:CreateButton(moveRow, "Move Left", { callback = function() Move(-1) end })
        moveRow:AddWidget(left, 0.2)
        right = GUIFrame:CreateButton(moveRow, "Move Right", { callback = function() Move(1) end })
        moveRow:AddWidget(right, 0.2)
        local status = StatusLabel(moveRow)
        status:SetPoint("LEFT", right, "RIGHT", 8, 0)
        status:SetPoint("RIGHT", moveRow, "RIGHT", 0, 0)
        local place = 0
        for i, id in ipairs(ids) do
            if id == picked then place = i end
        end
        if place > 0 then
            local name = C_Spell.GetSpellName(picked) or ("Spell " .. picked)
            status:SetText("Picked: " .. name .. " (" .. place .. " of " .. #ids .. ")")
        elseif #ids > 0 and type(db.HealerExtOrder) == "table" then
            status:SetText("No icon picked.")
        elseif #ids > 0 then
            status:SetText("Shipped order: your own first, then each party member.")
        end
        card:AddRow(moveRow, FOOTER_HEIGHT)

        local footer = GUIFrame:CreateRow(card.content, FOOTER_HEIGHT)
        local defaults = GUIFrame:CreateButton(footer, "Kitn Defaults", {
            tooltip = "Tracks every spell again, in the shipped order.",
            callback = function()
                for key in pairs(db.CooldownOff) do
                    if type(key) == "string" and (key:sub(1, 7) == "healer:" or key:sub(1, 4) == "box:") then
                        db.CooldownOff[key] = nil
                    end
                end
                -- false keeps a spell that ships off ticked.
                for _, entry in pairs(casts) do
                    if entry.spell.off then db.CooldownOff[entry.key] = false end
                end
                db.HealerExtOrder = nil
                picked = nil
                apply()
                C_Timer.After(0, function() GUIFrame:RefreshContent() end)
            end,
        })
        footer:AddWidget(defaults, 0.3)
        stripManager:Register(defaults, "all")
        card:AddRow(footer, FOOTER_HEIGHT, 0)
        if lastEnabled ~= nil then stripManager:UpdateAll(lastEnabled) end
        MoveState()
    end

    local picks = {}
    local function AddPick(entry, class, specID, boxRow)
        casts[entry.id] = entry
        picks[#picks + 1] = {
            class = class,
            label = SpellLabel(entry.id),
            value = not entry.off,
            tooltip = SpellTooltip(entry, specID, boxRow),
            onChange = function(checked)
                WriteSwitch(db, entry, checked)
                if not checked and picked == entry.id then picked = nil end
                apply()
                RedrawStrip()
            end,
        }
    end
    local specs = {}
    for specID in pairs(data.HEALER_SPECS) do specs[#specs + 1] = specID end
    table_sort(specs)
    for _, specID in ipairs(specs) do
        for _, entry in ipairs(HXRules.Entries(specID, db, true)) do
            AddPick(entry, data.HEALER_SPECS[specID].class, specID, nil)
        end
    end
    for _, boxRow in ipairs(data.BOX_ROWS) do
        local entry = HXRules.BoxEntry(boxRow, nil, db, true)
        if entry then AddPick(entry, boxRow.class, nil, boxRow) end
    end
    rowManager:RegisterGroup(Rows.Add(card, picks).widgets, "all")
    card:AddSeparator()
    card:AddLabel("Icon order, left to right as the icons show. Click an icon, then move it.")
    stripMark = card:MarkBody()
    DrawStrip()

    local baseSetEnabled = card.SetEnabled
    function card:SetEnabled(enabled)
        if baseSetEnabled then baseSetEnabled(self, enabled) end
        lastEnabled = enabled
        rowManager:UpdateAll(enabled)
        stripManager:UpdateAll(enabled)
        MoveState()
    end

    return card, card:GetNextOffset()
end


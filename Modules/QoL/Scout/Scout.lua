-- ╔══════════════════════════════════════════════════════════╗
-- ║  Scout.lua                                               ║
-- ║  Module: Scout                                           ║
-- ║  Purpose: Adds what a hostile mob can do to its tooltip, ║
-- ║           from a table loaded on enable.                 ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class Scout: AceModule, AceEvent-3.0
local Scout = KitnEssentials:NewModule("Scout", "AceEvent-3.0")

local Rules = KE.ScoutRules

local CreateFrame = CreateFrame
local C_AddOns = C_AddOns
local C_Spell = C_Spell
local C_Timer = C_Timer
local GameTooltip = GameTooltip
local InCombatLockdown = InCombatLockdown
local IsAltKeyDown = IsAltKeyDown
local IsControlKeyDown = IsControlKeyDown
local IsInInstance = IsInInstance
local IsShiftKeyDown = IsShiftKeyDown
local UIParent = UIParent
local UnitCanAttack = UnitCanAttack
local UnitClass = UnitClass
local UnitClassification = UnitClassification
local UnitCreatureFamily = UnitCreatureFamily
local UnitEffectiveLevel = UnitEffectiveLevel
local UnitGUID = UnitGUID
local UnitLevel = UnitLevel
local debugprofilestop = debugprofilestop
local ipairs = ipairs
local issecretvalue = issecretvalue
local pcall = pcall
local type = type
local wipe = wipe

local DATA_ADDON = "KitnEssentials_Data"
local MOB_SOURCE = "ScoutMobs"
local SPELL_SOURCE = "ScoutSpells"
local DETAILS_MIN_WIDTH = 262
local DETAILS_GAP = 2
local NO_DESCRIPTION = "No description in the game's data."
local INCOMPLETE_DATA = "a data file is missing"
local MISSING_REASON = "MISSING"
-- The chat history replay lands just after login and would bury an earlier
-- line; KE:Init's welcome line waits the same time.
local FAILURE_PRINT_DELAY = 2
local HUNTER = "HUNTER"

local PALETTE = {
    gold = "ffd100",
    amber = "ffb454",
    red = "ff6b6b",
    muted = "a9a9a9",
    green = "4dcc66",
    white = "ffffff",
}

local KEY_DOWN = { ctrl = IsControlKeyDown, alt = IsAltKeyDown, shift = IsShiftKeyDown }
local KEY_OF_EVENT = {
    LCTRL = "ctrl", RCTRL = "ctrl",
    LALT = "alt", RALT = "alt",
    LSHIFT = "shift", RSHIFT = "shift",
}

local NO_ROWS = {}

-- The post call and the tooltip hooks cannot be removed, so all gate on this.
local active = false
local hooked = false
-- Apart from the record: a settings change clears that and leaves the lines up.
local linesOnTooltip = false
local loadFailureSaid = false
local scoutData
local block
local record = { on = false, ids = {}, immunity = nil }
local requested = {}
local opts = {}

local function Paint(key, text)
    local hex = key == "accent" and KE:GetThemeColorHex() or PALETTE[key]
    return "|cff" .. hex .. text .. "|r"
end

local function PlainNumber(value)
    if issecretvalue(value) or type(value) ~= "number" then return nil end
    return value
end

local function PlainString(value)
    if issecretvalue(value) or type(value) ~= "string" then return nil end
    return value
end

-- A secret boolean errors on a truth test, so an unreadable flag counts as forbidden.
local function IsUsable(frame)
    local forbidden = frame:IsForbidden()
    return not issecretvalue(forbidden) and not forbidden
end

local function HideBlock()
    if block then block:Hide() end
end

local function ForgetRecord()
    record.on = false
    record.immunity = nil
    wipe(record.ids)
end

local function ClearRecord()
    ForgetRecord()
    HideBlock()
end

-- The next-frame draw handles a record with something to show; anything else
-- leaves no block.
local function SettleBlock()
    if record.on and (#record.ids > 0 or record.immunity) then return end
    HideBlock()
end

-- A shown unit tooltip is rebuilt about once a second: cleared, then the post
-- call runs again in the same frame. Hiding at once would leave the block off
-- screen until the next-frame draw, so the hide waits a frame as well.
local function ForgetSoon()
    ForgetRecord()
    if not block then return end
    local shown = block:IsShown()
    if issecretvalue(shown) or shown then C_Timer.After(0, SettleBlock) end
end

local function IsKeyHeld()
    local isDown = KEY_DOWN[Scout.db.DetailsKey]
    return isDown and isDown()
end

local function ShownHere()
    return Rules.ShownHere(Scout.db, IsInInstance(), InCombatLockdown(), Rules.SHOW_IN)
end

local function IsUnitData(tooltipData)
    local kind = tooltipData and tooltipData.type
    return not issecretvalue(kind) and kind == Enum.TooltipDataType.Unit
end

---------------------------------------------------------------------------------
-- Details block
---------------------------------------------------------------------------------
local function GetBlock()
    if block then return block end
    block = CreateFrame("GameTooltip", "KitnEssentialsScoutDetails", UIParent, "GameTooltipTemplate")
    block:SetClampedToScreen(true)
    return block
end

local function DescriptionOf(id)
    local text = C_Spell.GetSpellDescription(id)
    if type(text) == "string" and text ~= "" then return text end
    return nil
end

local function Scaled(frame, value)
    local plain = PlainNumber(value)
    local scale = PlainNumber(frame:GetEffectiveScale())
    return plain and scale and plain * scale or nil
end

local function PlaceBlock(b)
    local below = Rules.DetailsBelow(
        Scaled(GameTooltip, GameTooltip:GetBottom()),
        Scaled(b, b:GetHeight()),
        Scaled(b, DETAILS_GAP))
    b:ClearAllPoints()
    if below then
        b:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 0, -DETAILS_GAP)
    else
        b:SetPoint("BOTTOMLEFT", GameTooltip, "TOPLEFT", 0, DETAILS_GAP)
    end
end

local ShowDetails

local function RequestDescription(id)
    requested[id] = true
    Spell:CreateFromSpellID(id):ContinueOnSpellLoad(function()
        -- Loaded data can be evicted, so a later draw may need to ask again. A
        -- spell still uncached here stays latched, so the two cannot loop.
        if C_Spell.IsSpellDataCached(id) then requested[id] = nil end
        if record.on then ShowDetails() end
    end)
end

-- Tested at draw time: key down, the next-frame timer and a late description
-- all come through here, and any of them can land after the state changed.
local function CanShowDetails()
    if not active or not record.on or not IsKeyHeld() or not ShownHere() then return false end
    if not IsUsable(GameTooltip) then return false end
    if not Rules.PlainTrue(GameTooltip:IsShown(), issecretvalue) then return false end
    return IsUnitData(GameTooltip:GetPrimaryTooltipData())
end

ShowDetails = function()
    if not CanShowDetails() then
        HideBlock()
        return
    end
    if #record.ids == 0 and not record.immunity then return end

    local b = GetBlock()
    b:SetOwner(UIParent, "ANCHOR_NONE")
    b:ClearLines()
    b:SetMinimumWidth(DETAILS_MIN_WIDTH)
    for _, id in ipairs(record.ids) do
        local name = C_Spell.GetSpellName(id)
        if name then
            b:AddLine(Rules.AbilityTitle(C_Spell.GetSpellTexture(id), name, Paint))
            b:AddLine(Paint("muted", DescriptionOf(id) or NO_DESCRIPTION), nil, nil, nil, true)
        end
    end
    if record.immunity then
        b:AddLine(record.immunity, nil, nil, nil, true)
    end
    b:Show()
    PlaceBlock(b)

    -- Uncached only: a cached spell's callback runs at once and would redraw
    -- from the top for a description that is really blank.
    for _, id in ipairs(record.ids) do
        if not requested[id] and C_Spell.DoesSpellExist(id) and not DescriptionOf(id)
            and not C_Spell.IsSpellDataCached(id) then
            RequestDescription(id)
        end
    end
end

---------------------------------------------------------------------------------
-- Tooltip lines
---------------------------------------------------------------------------------
local function ReadAbilities(npcId, data)
    local ids = data.abilities[npcId]
    if not ids then return NO_ROWS end
    local rows = {}
    for _, id in ipairs(ids) do
        local info = not Rules.IsScriptSpell(id) and C_Spell.GetSpellInfo(id)
        if info and info.name then
            rows[#rows + 1] = {
                id = id,
                name = info.name,
                icon = C_Spell.GetSpellTexture(id),
                minRange = info.minRange,
                maxRange = info.maxRange,
                castTime = info.castTime,
                scope = data.scopes[id],
                word = data.words[id],
            }
            if #rows == Rules.MAX_ABILITY_ROWS then break end
        end
    end
    return rows
end

local function ReadEffectiveness(armor)
    if not (C_PaperDollInfo and C_PaperDollInfo.GetArmorEffectiveness) then return nil end
    local level = PlainNumber(UnitEffectiveLevel("player"))
    if not level then return nil end
    return PlainNumber(C_PaperDollInfo.GetArmorEffectiveness(armor, level))
end

local function ReadView(unit, npcId, data, db)
    local row = data.stats[npcId]
    local _, schoolMask, mechanicMask, resists = Rules.UnpackStats(row)
    local mobLevel = PlainNumber(UnitLevel(unit))
    local playerLevel = PlainNumber(UnitLevel("player")) or 1
    local view = {
        mobLevel = mobLevel,
        playerLevel = playerLevel,
        abilities = db.Abilities and ReadAbilities(npcId, data) or NO_ROWS,
        schoolMask = schoolMask,
        mechanicMask = mechanicMask,
        resists = resists,
    }
    if db.Armor then
        local classification = PlainString(UnitClassification(unit))
        local armor, estimated = Rules.ArmorInput(row, mobLevel, classification, playerLevel, data.armor)
        if armor then
            view.armor = armor
            view.estimated = estimated
            view.effectiveness = ReadEffectiveness(armor)
        end
    end
    if db.PetFamily and Scout.playerClass == HUNTER then
        view.family = PlainString(UnitCreatureFamily(unit))
        view.tameKnown = Rules.TameKnown(data, npcId)
        view.tameable = data.tame[npcId] == true
    end
    return view
end

local function KeyName(key)
    for _, entry in ipairs(Rules.DETAILS_KEYS) do
        if entry.key == key then return entry.text end
    end
    return key
end

local function FillOpts(db)
    opts.abilities = db.Abilities
    opts.controlWords = db.ControlWords
    opts.armor = db.Armor
    opts.immunities = db.Immunities
    opts.petFamily = db.PetFamily
    opts.keyHint = db.KeyHint
    opts.class = Scout.playerClass
    opts.keyName = KeyName(db.DetailsKey)
end

local function OnUnit(tooltip, tooltipData)
    if not active then return end
    if tooltip ~= GameTooltip or not IsUsable(tooltip) then return end
    ForgetSoon()

    if not scoutData or not ShownHere() then return end

    local guid = tooltipData and tooltipData.guid
    local npcId = Rules.NpcId(guid, issecretvalue)
    if not npcId then return end

    local _, _, token = pcall(tooltip.GetUnit, tooltip)
    local unit = Rules.PickUnit(token, issecretvalue, UnitGUID("mouseover"), guid)
    if not unit then return end
    if not Rules.PlainTrue(UnitCanAttack("player", unit), issecretvalue) then return end

    local db = Scout.db
    FillOpts(db)
    local view = ReadView(unit, npcId, scoutData, db)
    local lines, fullImmunity = Rules.BuildLines(view, opts, Paint)
    for _, line in ipairs(lines) do
        if line.right then
            tooltip:AddDoubleLine(line.left, line.right)
        else
            tooltip:AddLine(line.left, nil, nil, nil, line.wrap)
        end
    end
    if #lines > 0 then linesOnTooltip = true end

    for i, ability in ipairs(view.abilities) do
        record.ids[i] = ability.id
    end
    record.immunity = fullImmunity
    record.on = true

    if (#record.ids > 0 or record.immunity) and IsKeyHeld() then
        C_Timer.After(0, ShowDetails)
    end
end

-- A rebuild clears the lines without hiding the tooltip, and a plain-text one
-- never reaches a post call. Reads no tooltip data.
local function OnTooltipCleared()
    if not active then return end
    linesOnTooltip = false
    ForgetSoon()
end

local function OnTooltipHidden()
    if not active then return end
    linesOnTooltip = false
    ClearRecord()
end

---------------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------------
local function BuildScoutData()
    if not KE.BuildData then return nil, INCOMPLETE_DATA end
    local mobs, mobReason = KE.BuildData(MOB_SOURCE)
    if not mobs then return nil, mobReason end
    local spells, spellReason = KE.BuildData(SPELL_SOURCE)
    if not spells then return nil, spellReason end
    mobs.words = spells.words
    mobs.scopes = spells.scopes
    if not Rules.DataComplete(mobs) then return nil, INCOMPLETE_DATA end
    return mobs
end

function Scout:LoadData()
    if scoutData then return end
    if InCombatLockdown() then
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    local start = debugprofilestop()
    local loaded, reason
    if C_AddOns.DoesAddOnExist(DATA_ADDON) then
        loaded, reason = C_AddOns.LoadAddOn(DATA_ADDON)
    else
        reason = MISSING_REASON
    end
    local data, buildReason
    if loaded then data, buildReason = BuildScoutData() end
    self.loadMs = debugprofilestop() - start
    if data then
        scoutData = data
        KE.ScoutData = data
        return
    end
    if loadFailureSaid then return end
    loadFailureSaid = true
    local text = buildReason
    if not loaded then
        text = reason and _G["ADDON_" .. reason]
        if type(text) ~= "string" then
            text = reason or "unknown"
        end
    end
    C_Timer.After(FAILURE_PRINT_DELAY, function()
        KE:Print("Scout could not load its mob table: " .. text)
    end)
end

function Scout:PLAYER_REGEN_ENABLED()
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    if active then self:LoadData() end
end

function Scout:MODIFIER_STATE_CHANGED(_, key, down)
    if not active or not record.on then return end
    if KEY_OF_EVENT[key] ~= self.db.DetailsKey then return end
    if down == 1 then
        ShowDetails()
    else
        HideBlock()
    end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function Scout:UpdateDB()
    self.db = KE.db.profile.Scout
end

function Scout:ApplySettings()
    if not active then return end
    ClearRecord()
    if self.db.Abilities or self.db.Immunities then
        self:RegisterEvent("MODIFIER_STATE_CHANGED")
    else
        self:UnregisterEvent("MODIFIER_STATE_CHANGED")
    end
end

function Scout:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function Scout:OnEnable()
    if not self.db.Enabled then return end
    active = true
    if not hooked then
        hooked = true
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnit)
        GameTooltip:HookScript("OnTooltipCleared", OnTooltipCleared)
        GameTooltip:HookScript("OnHide", OnTooltipHidden)
    end
    local _, class = UnitClass("player")
    self.playerClass = PlainString(class)
    self:LoadData()
    self:ApplySettings()
end

function Scout:OnDisable()
    active = false
    local hadLines = linesOnTooltip
    linesOnTooltip = false
    ClearRecord()
    self:UnregisterAllEvents()
    -- The lines cannot be taken back out of a built tooltip.
    if hadLines and IsUsable(GameTooltip) then GameTooltip:Hide() end
end

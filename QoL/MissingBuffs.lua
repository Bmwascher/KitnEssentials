-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class MissingBuffs: AceModule, AceEvent-3.0
local MBUFFS = KitnEssentials:NewModule("MissingBuffs", "AceEvent-3.0")

-- Localization
local ipairs, pairs = ipairs, pairs
local wipe = wipe
local UnitClass, UnitExists, UnitIsDeadOrGhost = UnitClass, UnitExists, UnitIsDeadOrGhost
local UnitIsConnected, UnitCanAssist, UnitIsPlayer = UnitIsConnected, UnitCanAssist, UnitIsPlayer
local UnitPosition = UnitPosition
local InCombatLockdown = InCombatLockdown
local GetNumGroupMembers = GetNumGroupMembers
local IsInRaid = IsInRaid
local GetTime = GetTime
local GetSpecialization, GetSpecializationInfo = GetSpecialization, GetSpecializationInfo
local CreateFrame = CreateFrame
local GetInventorySlotInfo, GetInventoryItemLink = GetInventorySlotInfo, GetInventoryItemLink
local GetItemInfo, GetInventoryItemTexture = GetItemInfo, GetInventoryItemTexture
local GetWeaponEnchantInfo = GetWeaponEnchantInfo
local issecretvalue = issecretvalue
local GetShapeshiftForm, GetShapeshiftFormInfo = GetShapeshiftForm, GetShapeshiftFormInfo
local tostring, tonumber = tostring, tonumber
local C_Spell, C_SpellBook, C_SpellActivationOverlay = C_Spell, C_SpellBook, C_SpellActivationOverlay
local C_PetBattles, C_ChallengeMode = C_PetBattles, C_ChallengeMode
local AuraUtil = AuraUtil
local UIParent = UIParent
local C_Timer = C_Timer

-- Constants
local CHECK_THROTTLE = 0.25
local MISSING_TEXT = "MISSING"
local REAPPLY_TEXT = ""
local GENERALBUFF_TEXT = ""

-- Default icon for weapon enchants
local WEAPON_ENCHANT_ICON = 136244

--------------------------------------------------------------------------------
-- Inline helpers (KE has no core CreateIconFrame/CreateTextFrame)
--------------------------------------------------------------------------------
local function ApplyZoom(texture, zoom)
    local texMin = 0.25 * zoom
    local texMax = 1 - 0.25 * zoom
    texture:SetTexCoord(texMin, texMax, texMin, texMax)
end

local function AddBorders(frame, color)
    local r, g, b, a = color[1], color[2], color[3], color[4] or 1

    local top = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    top:SetHeight(1)
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    top:SetColorTexture(r, g, b, a)
    top:SetTexelSnappingBias(0)
    top:SetSnapToPixelGrid(false)

    local bottom = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    bottom:SetHeight(1)
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    bottom:SetColorTexture(r, g, b, a)
    bottom:SetTexelSnappingBias(0)
    bottom:SetSnapToPixelGrid(false)

    local left = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    left:SetWidth(1)
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    left:SetColorTexture(r, g, b, a)
    left:SetTexelSnappingBias(0)
    left:SetSnapToPixelGrid(false)

    local right = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    right:SetWidth(1)
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    right:SetColorTexture(r, g, b, a)
    right:SetTexelSnappingBias(0)
    right:SetSnapToPixelGrid(false)
end

local function CreateIconFrame(parent, iconSize, name)
    local frame = CreateFrame("Frame", name, parent)
    frame:SetSize(iconSize, iconSize)
    AddBorders(frame, { 0, 0, 0, 1 })
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetAllPoints(frame)
    ApplyZoom(frame.icon, 0.3)
    frame.text = frame:CreateFontString(nil, "OVERLAY")
    frame.text:SetFont(KE.FONT, 12, "")
    frame.text:SetPoint("CENTER", frame, "CENTER", 1, 0)
    function frame:SetIconSize(newSize)
        self:SetSize(newSize, newSize)
        self.icon:SetAllPoints(self)
    end
    return frame
end

local function CreateTextFrame(parent, width, height, name)
    local frame = CreateFrame("Frame", name, parent)
    frame:SetSize(width, height)
    frame.text = frame:CreateFontString(nil, "OVERLAY")
    frame.text:SetFont(KE.FONT, 12, "")
    frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    return frame
end

--------------------------------------------------------------------------------
-- Category / Buff definitions
--------------------------------------------------------------------------------
local CATEGORY_TO_DB_KEY = {
    FLASK = "Flask",
    FOOD = "Food",
    MH_ENCHANT = "MHEnchant",
    OH_ENCHANT = "OHEnchant",
    RUNE = "Rune",
}

local CLASS_BUFFS = {
    ["DRUID"] = {
        { spellId = 1126, text = GENERALBUFF_TEXT },
    },
    ["EVOKER"] = {
        {
            spellId = 381748,
            spellbookId = 364342,
            text = GENERALBUFF_TEXT,
            ignoreRangeCheck = true,
            extraBuffSpellIds = { 381732, 381741, 381746, 381749, 381750, 381751, 381752, 381753, 381754, 381756, 381757, 381758, 442744, 432658, 432652, 432655 },
        },
    },
    ["MAGE"] = {
        { spellId = 1459, text = GENERALBUFF_TEXT },
        { spellId = 210126, spellbookId = 205022, text = GENERALBUFF_TEXT, specIds = { 62 }, onlySelf = true },
    },
    ["PRIEST"] = {
        { spellId = 21562, text = GENERALBUFF_TEXT },
    },
    ["SHAMAN"] = {
        { spellId = 462854, text = GENERALBUFF_TEXT },
    },
    ["WARRIOR"] = {
        { spellId = 6673, text = GENERALBUFF_TEXT, ignoreRangeCheck = true },
    },
}

-- Rogue poison spell IDs
local ROGUE_POISONS = {
    { spellId = 381637, poisonType = "nonlethal" },
    { spellId = 5761,   poisonType = "nonlethal" },
    { spellId = 3408,   poisonType = "nonlethal" },
    { spellId = 381664, poisonType = "lethal" },
    { spellId = 2823,   poisonType = "lethal" },
    { spellId = 315584, poisonType = "lethal" },
    { spellId = 8679,   poisonType = "lethal" },
}

local POISON_IDS = {
    ATROPHIC = 381637,
    NUMBING = 5761,
    CRIPPLING = 3408,
    AMPLIFYING = 381664,
    DEADLY = 2823,
    INSTANT = 315584,
    WOUND = 8679,
}

local ASSA_DOUBLE_POISON_TALENT = 381801

local CUSTOM_BUFFS = {
    -- Midnight Flasks
    { category = "FLASK",      spellId = 1235110,   enabled = true },
    { category = "FLASK",      spellId = 1235057,   enabled = true },
    { category = "FLASK",      spellId = 1235111,   enabled = true },
    { category = "FLASK",      spellId = 1235108,   enabled = true },
    -- TWW Flasks
    { category = "FLASK",      spellId = 432021,    enabled = true },
    { category = "FLASK",      spellId = 431971,    enabled = true },
    { category = "FLASK",      spellId = 431972,    enabled = true },
    { category = "FLASK",      spellId = 431974,    enabled = true },
    { category = "FLASK",      spellId = 431973,    enabled = true },
    -- Food
    { category = "FOOD",       spellId = 457284,    enabled = true },
    { category = "FOOD",       spellId = 1232585,   enabled = true },
    { category = "FOOD",       spellId = 461959,    enabled = true },
    { category = "FOOD",       spellId = 461960,    enabled = true },
    { category = "FOOD",       spellId = 462210,    enabled = true },
    { category = "FOOD",       spellId = 462181,    enabled = true },
    { category = "FOOD",       spellId = 462183,    enabled = true },
    { category = "FOOD",       spellId = 462180,    enabled = true },
    -- Weapon enchants
    { category = "MH_ENCHANT", weaponSlot = "main", text = "MH",   enabled = true },
    { category = "OH_ENCHANT", weaponSlot = "off",  text = "OH",   enabled = true },
}

local SPEC_ID_TO_NAME = {
    [71] = "Arms", [72] = "Fury", [73] = "Protection",
    [65] = "Holy", [66] = "Protection", [70] = "Retribution",
    [102] = "Balance", [103] = "Feral", [104] = "Guardian", [105] = "Restoration",
    [256] = "Discipline", [257] = "Holy", [258] = "Shadow",
    [1467] = "Devastation", [1468] = "Preservation", [1473] = "Augmentation",
}

-- Unit strings for group checking
local UNIT_STRINGS = { raid = {}, party = {} }
for i = 1, 40 do
    UNIT_STRINGS.raid[i] = "raid" .. i
    if i <= 5 then
        UNIT_STRINGS.party[i] = "party" .. i
    end
end

-- Module state
local playerClass = nil
local playerBuffs = nil
local isThrottled = false
local lastCheckTime = 0

-- Frame state
local containerFrame = nil
local stanceFrame = nil
local stanceTextFrame = nil
local iconPool = {}
local activeIcons = {}
local currentMissingBuffs = {}

-- Preview state
local isPreviewActive = false

-- Warrior stance spell IDs
local WARRIOR_STANCE_SPELLS = {
    [386164] = true, -- Battle Stance
    [386196] = true, -- Berserker Stance
    [386208] = true, -- Defensive Stance
}
local STANCE_TIMER_DURATION = 3
local stanceTimerHandle = nil
local stanceTimerActive = false

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local function IsLoadConditionMet(loadCondition)
    if not loadCondition or loadCondition == "ALWAYS" then return true end
    local groupSize = GetNumGroupMembers()
    local inRaid = IsInRaid()
    local inGroup = groupSize > 0
    if loadCondition == "ANYGROUP" then return inGroup
    elseif loadCondition == "PARTY" then return inGroup and not inRaid
    elseif loadCondition == "RAID" then return inRaid
    elseif loadCondition == "NOGROUP" then return not inGroup
    end
    return true
end

local function IsSpellKnown(spellId)
    return spellId and C_SpellBook.IsSpellKnown(spellId)
end

local function GetSpellTexture(spellId)
    if spellId and spellId > 0 then
        return C_Spell.GetSpellTexture(spellId)
    end
    return nil
end

local function IsValidTarget(unit)
    if not UnitExists(unit) then return false end
    if UnitIsDeadOrGhost(unit) then return false end
    if not UnitIsConnected(unit) then return false end
    if not UnitIsPlayer(unit) then return false end
    if not UnitCanAssist("player", unit) then return false end
    local _, _, _, playerInstanceId = UnitPosition("player")
    local _, _, _, unitInstanceId = UnitPosition(unit)
    if playerInstanceId and unitInstanceId and playerInstanceId ~= unitInstanceId then
        return false
    end
    return true
end

local function PlayerHasBuff(spellId, extraSpellIds)
    if not spellId then return false, nil end
    if issecretvalue(spellId) or issecretvalue(extraSpellIds) then return end

    local hasBuff = false
    local expirationTime = nil

    AuraUtil.ForEachAura("player", "HELPFUL", nil, function(auraInfo)
        if not auraInfo or not auraInfo.spellId then return false end
        local auraSpellId = auraInfo.spellId
        if issecretvalue(auraSpellId) then return false end

        if auraSpellId == spellId then
            hasBuff = true
            expirationTime = auraInfo.expirationTime
            return true
        end

        if extraSpellIds then
            for _, extraId in ipairs(extraSpellIds) do
                if auraSpellId == extraId then
                    hasBuff = true
                    expirationTime = auraInfo.expirationTime
                    return true
                end
            end
        end
        return false
    end, true)

    return hasBuff, expirationTime
end

local function UnitHasBuff(unit, spellId, extraSpellIds)
    if issecretvalue(unit) then return end
    if not unit or not IsValidTarget(unit) then return true end
    if issecretvalue(spellId) or issecretvalue(extraSpellIds) then return end

    local hasBuff = false

    AuraUtil.ForEachAura(unit, "HELPFUL", nil, function(auraInfo)
        if not auraInfo or not auraInfo.spellId then return false end
        local auraSpellId = auraInfo.spellId
        if issecretvalue(auraSpellId) then return false end

        if auraSpellId == spellId then
            hasBuff = true
            return true
        end

        if extraSpellIds then
            for _, extraId in ipairs(extraSpellIds) do
                if auraSpellId == extraId then
                    hasBuff = true
                    return true
                end
            end
        end
        return false
    end, true)

    return hasBuff
end

local function GetGroupBuffClasses()
    local classesInGroup = {}
    local groupSize = GetNumGroupMembers()
    local _, _, _, playerInstanceId = UnitPosition("player")

    if groupSize == 0 then
        if playerClass then classesInGroup[playerClass] = true end
        return classesInGroup
    end

    if IsInRaid() then
        for i = 1, groupSize do
            local unit = UNIT_STRINGS.raid[i]
            if UnitExists(unit) and UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit) then
                local _, _, _, unitInstanceId = UnitPosition(unit)
                if not playerInstanceId or not unitInstanceId or playerInstanceId == unitInstanceId then
                    local _, class = UnitClass(unit)
                    if class and CLASS_BUFFS[class] then
                        classesInGroup[class] = true
                    end
                end
            end
        end
    else
        if playerClass then classesInGroup[playerClass] = true end
        for i = 1, groupSize - 1 do
            local unit = UNIT_STRINGS.party[i]
            if UnitExists(unit) and UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit) then
                local _, _, _, unitInstanceId = UnitPosition(unit)
                if not playerInstanceId or not unitInstanceId or playerInstanceId == unitInstanceId then
                    local _, class = UnitClass(unit)
                    if class and CLASS_BUFFS[class] then
                        classesInGroup[class] = true
                    end
                end
            end
        end
    end

    return classesInGroup
end

--------------------------------------------------------------------------------
-- Buff checking functions
--------------------------------------------------------------------------------
local function CheckMissingRaidBuffsFromGroup()
    local missing = {}
    local groupSize = GetNumGroupMembers()
    if groupSize == 0 then return missing end

    local classesInGroup = GetGroupBuffClasses()

    for class, _ in pairs(classesInGroup) do
        if class ~= playerClass then
            local classBuffs = CLASS_BUFFS[class]
            if classBuffs then
                for _, buff in ipairs(classBuffs) do
                    if not buff.onlySelf then
                        local hasBuff = PlayerHasBuff(buff.spellId, buff.extraBuffSpellIds)
                        if not hasBuff then
                            missing[#missing + 1] = { buff = buff, text = GENERALBUFF_TEXT }
                        end
                    end
                end
            end
        end
    end

    return missing
end

local function CheckBuffStatus(buff)
    if InCombatLockdown() then return false, false end
    if issecretvalue(buff) then return end

    if buff.onlySelf then
        local hasBuff, expirationTime = PlayerHasBuff(buff.spellId, buff.extraBuffSpellIds)
        if not hasBuff then return true, false end
        local needsReapply = false
        if expirationTime and expirationTime > 0 then
            local timeLeft = expirationTime - GetTime()
            local durationMinutes = timeLeft / 60
            if MBUFFS.db and MBUFFS.db.NotifyLowDuration and durationMinutes <= MBUFFS.db.LowDurationThreshold then
                needsReapply = true
            end
        end
        return false, needsReapply
    end

    local hasBuff, expirationTime = PlayerHasBuff(buff.spellId, buff.extraBuffSpellIds)
    if not hasBuff then return true, false end

    local needsReapply = false
    if expirationTime and expirationTime > 0 then
        local timeLeft = expirationTime - GetTime()
        local durationMinutes = timeLeft / 60
        if MBUFFS.db and MBUFFS.db.NotifyLowDuration and durationMinutes <= MBUFFS.db.LowDurationThreshold then
            needsReapply = true
        end
    end

    local groupSize = GetNumGroupMembers()
    if groupSize > 0 then
        if IsInRaid() then
            for i = 1, groupSize do
                local unit = UNIT_STRINGS.raid[i]
                if IsValidTarget(unit) and not UnitHasBuff(unit, buff.spellId, buff.extraBuffSpellIds) then
                    if buff.ignoreRangeCheck or C_Spell.IsSpellInRange(buff.spellId, unit) then
                        return true, false
                    end
                end
            end
        else
            for i = 1, groupSize - 1 do
                local unit = UNIT_STRINGS.party[i]
                if IsValidTarget(unit) and not UnitHasBuff(unit, buff.spellId, buff.extraBuffSpellIds) then
                    if buff.ignoreRangeCheck or C_Spell.IsSpellInRange(buff.spellId, unit) then
                        return true, false
                    end
                end
            end
        end
    end

    return false, needsReapply
end

local function HasWeaponEnchant(slot)
    local hasMain, _, _, _, hasOff = GetWeaponEnchantInfo()
    local slotName = slot == "main" and "MAINHANDSLOT" or slot == "off" and "SECONDARYHANDSLOT"
    if not slotName then return nil, nil, false end
    local slotID = GetInventorySlotInfo(slotName)
    local itemLink = GetInventoryItemLink("player", slotID)
    if not itemLink then return nil, nil, false end

    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(itemLink)
    if not equipLoc then return nil, nil, false end
    if equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_HOLDABLE" then
        return nil, nil, false
    end

    local hasEnchant
    if slot == "main" then hasEnchant = hasMain
    else hasEnchant = hasOff end
    local icon = GetInventoryItemTexture("player", slotID)
    if not icon then return hasEnchant, nil, false end
    return hasEnchant, icon, true
end

local function CheckCustomBuffs()
    local db = MBUFFS.db
    if not db then return {} end
    local consumablesDb = db.Consumables or {}
    local missing = {}
    local categorySeen = {}
    local categorySatisfied = {}
    local categoryIcon = {}
    local categoryEnabled = {}

    for category, dbKey in pairs(CATEGORY_TO_DB_KEY) do
        local catSettings = consumablesDb[dbKey]
        if catSettings then
            local enabled = catSettings.Enabled ~= false
            local loadMet = IsLoadConditionMet(catSettings.LoadCondition)
            categoryEnabled[category] = enabled and loadMet
        else
            categoryEnabled[category] = true
        end
    end

    for _, buff in ipairs(CUSTOM_BUFFS) do
        local category = buff.category
        if category and categoryEnabled[category] then
            if buff.weaponSlot then
                local hasEnchant, icon, hasItem = HasWeaponEnchant(buff.weaponSlot)
                if hasItem then
                    if hasEnchant ~= nil then
                        categoryIcon[category] = icon or WEAPON_ENCHANT_ICON
                    end
                    if hasEnchant == true then
                        categorySatisfied[category] = true
                    end
                end
            elseif buff.spellId then
                if PlayerHasBuff(buff.spellId, buff.extraBuffSpellIds) then
                    categorySatisfied[category] = true
                end
            end
        end
    end

    for _, buff in ipairs(CUSTOM_BUFFS) do
        local category = buff.category
        if category and categoryEnabled[category] then
            if not categorySatisfied[category] and not categorySeen[category] then
                categorySeen[category] = true
                local icon = categoryIcon[category]
                if buff.weaponSlot and not icon then
                    -- Skip if no weapon
                else
                    missing[#missing + 1] = {
                        buff = {
                            spellId = buff.spellId or 0,
                            text = buff.text,
                            iconTexture = buff.iconTexture or icon,
                        },
                        text = buff.text,
                        isCustom = true,
                    }
                end
            end
        end
    end

    return missing
end

local function CheckRoguePoisons()
    if playerClass ~= "ROGUE" then return {} end
    local db = MBUFFS.db
    if not db then return {} end

    local consumablesDb = db.Consumables or {}
    local poisonSettings = consumablesDb.Poisons or {}
    if poisonSettings.Enabled == false then return {} end
    if not IsLoadConditionMet(poisonSettings.LoadCondition) then return {} end

    local missing = {}
    local spec = GetSpecialization()
    if not spec then return missing end
    local specId = GetSpecializationInfo(spec)

    local isAssassination = specId == 259
    local hasDoublePoisonTalent = isAssassination and IsSpellKnown(ASSA_DOUBLE_POISON_TALENT)

    local requiredLethal = hasDoublePoisonTalent and 2 or 1
    local requiredNonLethal = hasDoublePoisonTalent and 2 or 1

    local lethalCount = 0
    local nonLethalCount = 0

    for _, poison in ipairs(ROGUE_POISONS) do
        if PlayerHasBuff(poison.spellId) then
            if poison.poisonType == "lethal" then
                lethalCount = lethalCount + 1
            else
                nonLethalCount = nonLethalCount + 1
            end
        end
    end

    local lethalMissing = requiredLethal - lethalCount
    local nonLethalMissing = requiredNonLethal - nonLethalCount

    if lethalMissing > 0 then
        local lethalIcons = {}
        if isAssassination then
            lethalIcons[1] = POISON_IDS.DEADLY
            if hasDoublePoisonTalent then
                lethalIcons[2] = IsSpellKnown(POISON_IDS.AMPLIFYING) and POISON_IDS.AMPLIFYING or POISON_IDS.INSTANT
            end
        else
            lethalIcons[1] = POISON_IDS.INSTANT
        end
        for i = 1, lethalMissing do
            local iconSpellId = lethalIcons[i] or lethalIcons[1]
            missing[#missing + 1] = {
                buff = { spellId = iconSpellId, text = "" },
                text = "",
                isCustom = true,
            }
        end
    end

    if nonLethalMissing > 0 then
        local nonLethalIcons = {}
        nonLethalIcons[1] = POISON_IDS.ATROPHIC
        if hasDoublePoisonTalent then
            nonLethalIcons[2] = POISON_IDS.CRIPPLING
        end
        for i = 1, nonLethalMissing do
            local iconSpellId = nonLethalIcons[i] or nonLethalIcons[1]
            missing[#missing + 1] = {
                buff = { spellId = iconSpellId, text = "" },
                text = "",
                isCustom = true,
            }
        end
    end

    return missing
end

--------------------------------------------------------------------------------
-- Icon pool system
--------------------------------------------------------------------------------
local function CreateIcon()
    local raidDb = MBUFFS.db.RaidBuffDisplay
    local iconFrame = CreateIconFrame(containerFrame, raidDb.IconSize)
    KE:ApplyFontToText(iconFrame.text, raidDb.FontFace, raidDb.FontSize, raidDb.FontOutline)
    iconFrame.text:SetTextColor(1, 1, 1, 1)
    iconFrame:Hide()
    return iconFrame
end

local function AcquireIcon()
    for _, icon in ipairs(iconPool) do
        if not icon.inUse then
            icon.inUse = true
            return icon
        end
    end
    local newIcon = CreateIcon()
    newIcon.inUse = true
    iconPool[#iconPool + 1] = newIcon
    return newIcon
end

local function ReleaseIcon(icon)
    icon.inUse = false
    icon:Hide()
    icon:ClearAllPoints()
end

local function ReleaseAllIcons()
    for _, icon in ipairs(activeIcons) do
        ReleaseIcon(icon)
    end
    wipe(activeIcons)
end

--------------------------------------------------------------------------------
-- Container frame (raid buff icons)
--------------------------------------------------------------------------------
local function CreateContainerFrame()
    if containerFrame then return end
    local raidDb = MBUFFS.db.RaidBuffDisplay
    containerFrame = CreateFrame("Frame", "KE_MissingBuffContainer", UIParent)
    containerFrame:SetSize(400, raidDb.IconSize)
    KE:ApplyFramePosition(containerFrame, raidDb.Position, raidDb)
    containerFrame:Hide()
    MBUFFS.raidBuffContainer = containerFrame
end

--------------------------------------------------------------------------------
-- Stance icon frame
--------------------------------------------------------------------------------
local function CreateStanceFrame()
    if stanceFrame then return end
    local stanceDb = MBUFFS.db.StanceDisplay

    stanceFrame = CreateIconFrame(UIParent, stanceDb.IconSize, "KE_MissingStanceIcon")

    -- Position text above the icon
    stanceFrame.text:ClearAllPoints()
    stanceFrame.text:SetPoint("BOTTOM", stanceFrame, "TOP", 1, 4)

    -- Cooldown frame for stance timer
    local cooldown = CreateFrame("Cooldown", nil, stanceFrame, "CooldownFrameTemplate")
    cooldown:SetAllPoints(stanceFrame)
    cooldown:SetFrameLevel(stanceFrame:GetFrameLevel() + 1)
    cooldown:SetDrawEdge(false)
    cooldown:SetDrawBling(false)
    cooldown:SetSwipeColor(0, 0, 0, 0.6)
    cooldown:SetReverse(true)
    cooldown:SetHideCountdownNumbers(false)

    local cdText = cooldown:GetRegions()
    if cdText and cdText.SetFont then
        cdText:SetFont(KE.FONT or STANDARD_TEXT_FONT, stanceDb.IconSize * 0.5, "OUTLINE")
        cdText:SetShadowColor(0, 0, 0, 0)
        cdText:SetShadowOffset(0, 0)
        cdText:ClearAllPoints()
        cdText:SetPoint("CENTER", stanceFrame, "CENTER", 1, 0)
    end

    stanceFrame.cooldown = cooldown

    KE:ApplyFramePosition(stanceFrame, stanceDb.Position, stanceDb)
    KE:ApplyFontToText(stanceFrame.text, stanceDb.FontFace, stanceDb.FontSize, stanceDb.FontOutline)
    stanceFrame.text:SetTextColor(1, 1, 1, 1)
    stanceFrame:Hide()
    MBUFFS.stanceContainer = stanceFrame
end

--------------------------------------------------------------------------------
-- Stance text frame
--------------------------------------------------------------------------------
local function CreateStanceTextFrame()
    if stanceTextFrame then return end
    local textDb = MBUFFS.db.StanceText

    stanceTextFrame = CreateTextFrame(UIParent, 200, 30, "KE_StanceTextDisplay")

    KE:ApplyFramePosition(stanceTextFrame, textDb.Position, textDb)
    KE:ApplyFontToText(stanceTextFrame.text, textDb.FontFace, textDb.FontSize, textDb.FontOutline)

    local textPoint = KE:GetTextPointFromAnchor(textDb.Position.AnchorFrom)
    local textJustify = KE:GetTextJustifyFromAnchor(textDb.Position.AnchorFrom)
    stanceTextFrame.text:ClearAllPoints()
    stanceTextFrame.text:SetPoint(textPoint, stanceTextFrame, textPoint, 0, 0)
    stanceTextFrame.text:SetJustifyH(textJustify)
    stanceTextFrame.text:SetTextColor(1, 1, 1, 1)

    stanceTextFrame:Hide()
    MBUFFS.stanceTextContainer = stanceTextFrame
end

--------------------------------------------------------------------------------
-- Show stance icon
--------------------------------------------------------------------------------
local function ShowStanceIcon(spellId, reverseIcon, currentSpellId)
    if not stanceFrame then CreateStanceFrame() end
    local stanceDb = MBUFFS.db.StanceDisplay
    if stanceFrame then
        local displaySpellId = (reverseIcon and currentSpellId) and currentSpellId or spellId
        local texture = GetSpellTexture(displaySpellId)
        stanceFrame.icon:SetTexture(texture)

        KE:ApplyFontToText(stanceFrame.text, stanceDb.FontFace, stanceDb.FontSize, stanceDb.FontOutline)
        stanceFrame.text:SetText(reverseIcon and "" or MISSING_TEXT)

        stanceFrame:SetSize(stanceDb.IconSize, stanceDb.IconSize)
        stanceFrame.icon:SetSize(stanceDb.IconSize, stanceDb.IconSize)

        KE:ApplyFramePosition(stanceFrame, stanceDb.Position, stanceDb)
        stanceFrame:Show()
    end
end

--------------------------------------------------------------------------------
-- Stance text display
--------------------------------------------------------------------------------
local function UpdateStanceTextDisplay()
    if not MBUFFS.db then return end
    local textDb = MBUFFS.db.StanceText

    if not textDb.Enabled then
        if stanceTextFrame then stanceTextFrame:Hide() end
        return
    end

    if playerClass ~= "WARRIOR" and playerClass ~= "PALADIN" then
        if stanceTextFrame then stanceTextFrame:Hide() end
        return
    end

    if not stanceTextFrame then CreateStanceTextFrame() end

    local currentForm = GetShapeshiftForm()
    local currentSpellId = nil

    if currentForm > 0 then
        local _, _, _, formSpellId = GetShapeshiftFormInfo(currentForm)
        currentSpellId = formSpellId
    end

    -- For paladin, check auras via buff
    if playerClass == "PALADIN" then
        local paladinAuras = { 465, 317920, 32223 }
        for _, auraId in ipairs(paladinAuras) do
            if PlayerHasBuff(auraId) then
                currentSpellId = auraId
                break
            end
        end
    end

    if stanceTextFrame then
        if not currentSpellId then
            stanceTextFrame:Hide()
            return
        end

        local classData = textDb[playerClass]
        if not classData then
            stanceTextFrame:Hide()
            return
        end

        local stanceKey = tostring(currentSpellId)
        local stanceSettings = classData[stanceKey]

        if not stanceSettings or not stanceSettings.Enabled then
            stanceTextFrame:Hide()
            return
        end

        local text = stanceSettings.Text or "Stance"
        local color = stanceSettings.Color or { 1, 1, 1, 1 }

        stanceTextFrame.text:SetText(text)
        stanceTextFrame.text:SetTextColor(color[1], color[2], color[3], color[4] or 1)

        KE:ApplyFontToText(stanceTextFrame.text, textDb.FontFace, textDb.FontSize, textDb.FontOutline)
        KE:ApplyFramePosition(stanceTextFrame, textDb.Position, textDb)

        local textPoint = KE:GetTextPointFromAnchor(textDb.Position.AnchorFrom)
        local textJustify = KE:GetTextJustifyFromAnchor(textDb.Position.AnchorFrom)
        stanceTextFrame.text:ClearAllPoints()
        stanceTextFrame.text:SetPoint(textPoint, stanceTextFrame, textPoint, 0, 0)
        stanceTextFrame.text:SetJustifyH(textJustify)
        stanceTextFrame:Show()
    end
end

--------------------------------------------------------------------------------
-- Icon appearance and arrangement
--------------------------------------------------------------------------------
local function UpdateIconAppearance(iconFrame, buff, text)
    local texture = GetSpellTexture(buff.spellId)
    if not texture then texture = buff.iconTexture or WEAPON_ENCHANT_ICON end
    iconFrame.icon:SetTexture(texture)

    KE:ApplyFontToText(iconFrame.text, MBUFFS.db.RaidBuffDisplay.FontFace, MBUFFS.db.RaidBuffDisplay.FontSize, MBUFFS.db.RaidBuffDisplay.FontOutline)
    iconFrame.text:SetText(text or buff.text or GENERALBUFF_TEXT)

    iconFrame:SetSize(MBUFFS.db.RaidBuffDisplay.IconSize, MBUFFS.db.RaidBuffDisplay.IconSize)
    iconFrame.icon:SetAllPoints(iconFrame)
end

local function ArrangeIcons()
    if not containerFrame then return end
    local raidDb = MBUFFS.db.RaidBuffDisplay or {}
    local count = #activeIcons

    if count == 0 then
        containerFrame:Hide()
        return
    end

    local totalWidth = (raidDb.IconSize * count) + (raidDb.IconSpacing * (count - 1))
    containerFrame:SetSize(totalWidth, raidDb.IconSize)

    local startX = -totalWidth / 2 + raidDb.IconSize / 2
    for i, iconFrame in ipairs(activeIcons) do
        iconFrame:ClearAllPoints()
        iconFrame:SetPoint("CENTER", containerFrame, "CENTER", startX + (i - 1) * (raidDb.IconSize + raidDb.IconSpacing), 0)
        iconFrame:Show()
    end

    KE:ApplyFramePosition(containerFrame, raidDb.Position, raidDb)
    containerFrame:Show()
end

--------------------------------------------------------------------------------
-- Stance checking
--------------------------------------------------------------------------------
local function CheckStances()
    if playerClass == "WARRIOR" and stanceTimerActive then
        UpdateStanceTextDisplay()
        return
    end

    if stanceFrame then stanceFrame:Hide() end
    UpdateStanceTextDisplay()
    if not MBUFFS.db then return end

    local stancesDb = MBUFFS.db.Stances
    if not stancesDb then return end
    if stancesDb.Enabled == false then return end

    if stancesDb.HideInRestedArea and IsResting() then return end

    local spec = GetSpecialization()
    if not spec then return end
    local currentSpecId = GetSpecializationInfo(spec)
    local specName = SPEC_ID_TO_NAME[currentSpecId]

    local classSettings = stancesDb[playerClass]
    if not classSettings then return end

    -- Priest: Shadowform
    if playerClass == "PRIEST" then
        if not classSettings.ShadowEnabled then return end
        if currentSpecId ~= 258 then return end
        if InCombatLockdown() or C_ChallengeMode.IsChallengeModeActive() then return end

        local shadowformSpellId = 232698
        local hasShadowform = PlayerHasBuff(shadowformSpellId, { 194249 })
        if not hasShadowform and IsSpellKnown(shadowformSpellId) then
            ShowStanceIcon(shadowformSpellId)
        end
        return
    end

    -- Druid: Form check
    if playerClass == "DRUID" then
        local druidSpecs = {
            [102] = { toggleKey = "BalanceEnabled", spellId = 24858 },
            [103] = { toggleKey = "FeralEnabled", spellId = 768 },
            [104] = { toggleKey = "GuardianEnabled", spellId = 5487 },
        }

        local specData = druidSpecs[currentSpecId]
        if not specData then return end
        if not classSettings[specData.toggleKey] then return end

        local currentForm = GetShapeshiftForm()
        local currentSpellId = nil
        if currentForm > 0 then
            local _, _, _, formSpellId = GetShapeshiftFormInfo(currentForm)
            currentSpellId = formSpellId
        end

        if currentSpellId ~= specData.spellId then
            if IsSpellKnown(specData.spellId) then
                ShowStanceIcon(specData.spellId)
            end
        end
        return
    end

    -- Evoker: Augmentation attunement
    if playerClass == "EVOKER" then
        if not classSettings.AugmentationEnabled then return end
        if currentSpecId ~= 1473 then return end

        local requiredSpellId = tonumber(classSettings.Augmentation) or 403264
        local hasAttunement = PlayerHasBuff(requiredSpellId)
        if not hasAttunement and IsSpellKnown(requiredSpellId) then
            ShowStanceIcon(requiredSpellId)
        end
        return
    end

    -- Warrior and Paladin: per-spec stances
    if not specName then return end

    local DEFAULT_STANCES = {
        WARRIOR = {
            Arms = 386164, Fury = 386196, Protection = 386208,
        },
        PALADIN = {
            Holy = 465, Protection = 465, Retribution = 32223,
        },
    }

    local specEnabledKey = specName .. "Enabled"
    if not classSettings[specEnabledKey] then return end

    local classDefaults = DEFAULT_STANCES[playerClass]
    local defaultStance = classDefaults and classDefaults[specName]
    local requiredStanceId = tonumber(classSettings[specName]) or defaultStance
    if not requiredStanceId then return end

    local reverseIconKey = specName .. "ReverseIcon"
    local reverseIcon = classSettings[reverseIconKey] and true or false

    local currentForm = GetShapeshiftForm()
    local currentSpellId = nil
    if currentForm > 0 then
        local _, _, _, formSpellId = GetShapeshiftFormInfo(currentForm)
        currentSpellId = formSpellId
    end

    -- Paladin: check auras via buffs
    if playerClass == "PALADIN" then
        local paladinAuras = { 465, 317920, 32223 }
        for _, auraId in ipairs(paladinAuras) do
            if PlayerHasBuff(auraId) then
                currentSpellId = auraId
                break
            end
        end
    end

    if currentSpellId ~= requiredStanceId then
        if IsSpellKnown(requiredStanceId) then
            ShowStanceIcon(requiredStanceId, reverseIcon, currentSpellId)
        end
    end
end

--------------------------------------------------------------------------------
-- Stance timer (warrior)
--------------------------------------------------------------------------------
local function ShowStanceTimer(spellId)
    if not stanceFrame then CreateStanceFrame() end
    if not stanceFrame then return end
    if not stanceFrame.cooldown then return end

    stanceTimerActive = true

    local texture = GetSpellTexture(spellId)
    if texture then stanceFrame.icon:SetTexture(texture) end
    stanceFrame.text:SetText("")

    stanceFrame.cooldown:SetAllPoints(stanceFrame)
    stanceFrame.cooldown:SetCooldown(GetTime(), STANCE_TIMER_DURATION)
    stanceFrame:Show()

    if stanceTimerHandle then stanceTimerHandle:Cancel() end

    stanceTimerHandle = C_Timer.NewTimer(STANCE_TIMER_DURATION, function()
        stanceTimerHandle = nil
        stanceTimerActive = false
        if stanceFrame and not isPreviewActive then
            CheckStances()
        end
    end)
end

--------------------------------------------------------------------------------
-- Show / Hide helpers
--------------------------------------------------------------------------------
local function ShowMissingBuffs(missingList)
    ReleaseAllIcons()
    for _, entry in ipairs(missingList) do
        local iconFrame = AcquireIcon()
        UpdateIconAppearance(iconFrame, entry.buff, entry.text)
        activeIcons[#activeIcons + 1] = iconFrame
    end
    ArrangeIcons()
end

local function HideMissingBuffIcons()
    ReleaseAllIcons()
    if containerFrame then containerFrame:Hide() end
end

local function HideAllNotifications()
    HideMissingBuffIcons()
    if stanceFrame then stanceFrame:Hide() end
    if stanceTextFrame then stanceTextFrame:Hide() end
end

--------------------------------------------------------------------------------
-- Weapon enchant check
--------------------------------------------------------------------------------
local function CheckWeaponEnchants()
    if not MBUFFS.db then return end
    local consumablesDb = MBUFFS.db.Consumables or {}
    local raidDb = MBUFFS.db.RaidBuffDisplay or {}
    for _, buff in ipairs(CUSTOM_BUFFS) do
        if buff.weaponSlot and buff.category then
            local dbKey = CATEGORY_TO_DB_KEY[buff.category]
            local catSettings = dbKey and consumablesDb[dbKey]
            local enabled = not catSettings or catSettings.Enabled ~= false
            local loadMet = not catSettings or IsLoadConditionMet(catSettings.LoadCondition)
            if enabled and loadMet then
                local hasEnchant, icon, hasItem = HasWeaponEnchant(buff.weaponSlot)
                if hasItem and not hasEnchant then
                    local iconFrame = AcquireIcon()
                    local displayIcon = icon or WEAPON_ENCHANT_ICON
                    local text = buff.text or GENERALBUFF_TEXT
                    local iconSize = raidDb.IconSize

                    iconFrame.icon:SetTexture(displayIcon)
                    iconFrame:SetSize(iconSize, iconSize)
                    iconFrame.icon:SetSize(iconSize, iconSize)
                    KE:ApplyFontToText(iconFrame.text, raidDb.FontFace, raidDb.FontSize, raidDb.FontOutline)
                    iconFrame.text:SetText(text)
                    activeIcons[#activeIcons + 1] = iconFrame
                    currentMissingBuffs[#currentMissingBuffs + 1] = { buff = buff, text = text }
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Glow-based raid buff detection (M+)
--------------------------------------------------------------------------------
local function CheckGlowBasedRaidBuffs()
    local consumablesDb = MBUFFS.db.Consumables or {}
    local raidBuffsSettings = consumablesDb.RaidBuffs or {}
    local raidBuffsEnabled = raidBuffsSettings.Enabled ~= false
    local raidBuffsLoadMet = IsLoadConditionMet(raidBuffsSettings.LoadCondition)
    if playerBuffs and raidBuffsEnabled and raidBuffsLoadMet then
        for _, buff in ipairs(playerBuffs) do
            local spellToCheck = buff.spellbookId or buff.spellId
            if IsSpellKnown(spellToCheck) then
                if C_SpellActivationOverlay.IsSpellOverlayed(buff.spellId) then
                    local iconFrame = AcquireIcon()
                    UpdateIconAppearance(iconFrame, buff, GENERALBUFF_TEXT)
                    activeIcons[#activeIcons + 1] = iconFrame
                    currentMissingBuffs[#currentMissingBuffs + 1] = { buff = buff, text = GENERALBUFF_TEXT }
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Combat-safe checks
--------------------------------------------------------------------------------
local function CheckCombatSafeElements()
    if isPreviewActive then return end
    if not MBUFFS.db or not MBUFFS.db.Enabled then return end
    if UnitIsDeadOrGhost("player") or C_PetBattles.IsInBattle() then return end
    ReleaseAllIcons()
    wipe(currentMissingBuffs)
    if C_ChallengeMode.IsChallengeModeActive() then
        CheckGlowBasedRaidBuffs()
    end
    CheckWeaponEnchants()
    if stanceFrame then stanceFrame:Hide() end
    if stanceTextFrame then stanceTextFrame:Hide() end
    CheckStances()
    ArrangeIcons()
end

local function CheckMissingBuffsViaGlow()
    ReleaseAllIcons()
    wipe(currentMissingBuffs)
    CheckGlowBasedRaidBuffs()
    CheckWeaponEnchants()
    CheckStances()
    ArrangeIcons()
end

local function IsTrackingPaused()
    return isPreviewActive
end

--------------------------------------------------------------------------------
-- Main check function
--------------------------------------------------------------------------------
local function CheckForMissingBuffs()
    if IsTrackingPaused() then return end
    if C_ChallengeMode.IsChallengeModeActive() then
        CheckMissingBuffsViaGlow()
        return
    end

    local currentTime = GetTime()
    if currentTime - lastCheckTime < CHECK_THROTTLE then
        if not isThrottled then
            isThrottled = true
            C_Timer.After(CHECK_THROTTLE, function()
                isThrottled = false
                CheckForMissingBuffs()
            end)
        end
        return
    end
    lastCheckTime = currentTime

    if not MBUFFS.db or not MBUFFS.db.Enabled then
        HideAllNotifications()
        return
    end

    if InCombatLockdown() then
        CheckCombatSafeElements()
        return
    end

    if UnitIsDeadOrGhost("player") or C_PetBattles.IsInBattle() then
        HideAllNotifications()
        return
    end

    wipe(currentMissingBuffs)

    local customMissing = CheckCustomBuffs()
    for _, entry in ipairs(customMissing) do
        currentMissingBuffs[#currentMissingBuffs + 1] = entry
    end

    local poisonMissing = CheckRoguePoisons()
    for _, entry in ipairs(poisonMissing) do
        currentMissingBuffs[#currentMissingBuffs + 1] = entry
    end

    local consumablesDb = MBUFFS.db.Consumables or {}
    local raidBuffsSettings = consumablesDb.RaidBuffs or {}
    local raidBuffsEnabled = raidBuffsSettings.Enabled ~= false
    local raidBuffsLoadMet = IsLoadConditionMet(raidBuffsSettings.LoadCondition)

    if raidBuffsEnabled and raidBuffsLoadMet then
        local addedBuffs = {}

        if playerBuffs then
            for _, buff in ipairs(playerBuffs) do
                local spellToCheck = buff.spellbookId or buff.spellId
                if IsSpellKnown(spellToCheck) then
                    local specOk = true
                    if buff.specIds then
                        specOk = false
                        local spec = GetSpecialization()
                        if spec then
                            local specId = GetSpecializationInfo(spec)
                            for _, id in ipairs(buff.specIds) do
                                if specId == id then
                                    specOk = true
                                    break
                                end
                            end
                        end
                    end
                    local talentOk = true
                    if buff.requiresSpellKnown then
                        talentOk = IsSpellKnown(buff.requiresSpellKnown)
                    end
                    if specOk and talentOk then
                        local isMissing, needsReapply = CheckBuffStatus(buff)
                        if isMissing then
                            currentMissingBuffs[#currentMissingBuffs + 1] = { buff = buff, text = GENERALBUFF_TEXT }
                            addedBuffs[buff.spellId] = true
                        elseif needsReapply then
                            currentMissingBuffs[#currentMissingBuffs + 1] = { buff = buff, text = REAPPLY_TEXT }
                            addedBuffs[buff.spellId] = true
                        end
                    end
                end
            end
        end

        local groupMissing = CheckMissingRaidBuffsFromGroup()
        for _, entry in ipairs(groupMissing) do
            if not addedBuffs[entry.buff.spellId] then
                currentMissingBuffs[#currentMissingBuffs + 1] = entry
                addedBuffs[entry.buff.spellId] = true
            end
        end
    end

    CheckStances()
    if #currentMissingBuffs > 0 then
        ShowMissingBuffs(currentMissingBuffs)
    else
        HideMissingBuffIcons()
    end
end

--------------------------------------------------------------------------------
-- Event handler
--------------------------------------------------------------------------------
local function OnAuraChange(unit, updateInfo)
    if not MBUFFS.db or not MBUFFS.db.Enabled then return end
    if IsTrackingPaused() then return end
    if unit ~= "player" and not (unit and (unit:find("party") or unit:find("raid"))) then return end
    if InCombatLockdown() then return end
    if updateInfo and not updateInfo.isFullUpdate then
        local hasRelevant = false
        if updateInfo.addedAuras then
            for _, aura in ipairs(updateInfo.addedAuras) do
                if issecretvalue(aura.isHelpful) then return end
                if aura.isHelpful then
                    hasRelevant = true
                    break
                end
            end
        end
        if updateInfo.removedAuraInstanceIDs and #updateInfo.removedAuraInstanceIDs > 0 then
            hasRelevant = true
        end
        if not hasRelevant then return end
    end
    CheckForMissingBuffs()
end

--------------------------------------------------------------------------------
-- DB
--------------------------------------------------------------------------------
function MBUFFS:UpdateDB()
    self.db = KE.db.profile.MissingBuffs
end

function MBUFFS:OnInitialize()
    self:UpdateDB()
    local _, class = UnitClass("player")
    playerClass = class
    playerBuffs = CLASS_BUFFS[class]
    self:SetEnabledState(false)
end

--------------------------------------------------------------------------------
-- Enable / Disable
--------------------------------------------------------------------------------
function MBUFFS:OnEnable()
    if not self.db or not self.db.Enabled then return end

    CreateContainerFrame()
    CreateStanceFrame()
    CreateStanceTextFrame()
    self:RegWithEditMode()

    C_Timer.After(0.5, function() self:ApplySettings() end)

    self:RegisterEvent("UNIT_AURA", function(_, unit, updateInfo) OnAuraChange(unit, updateInfo) end)
    self:RegisterEvent("GROUP_ROSTER_UPDATE", function() CheckForMissingBuffs() end)
    self:RegisterEvent("PLAYER_REGEN_DISABLED", function()
        HideAllNotifications()
        CheckCombatSafeElements()
    end)
    self:RegisterEvent("PLAYER_REGEN_ENABLED", function() CheckForMissingBuffs() end)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function() C_Timer.After(1, CheckForMissingBuffs) end)
    self:RegisterEvent("PLAYER_ALIVE", function() CheckForMissingBuffs() end)
    self:RegisterEvent("PLAYER_DEAD", function() CheckForMissingBuffs() end)
    self:RegisterEvent("PLAYER_UNGHOST", function() CheckForMissingBuffs() end)
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() C_Timer.After(0.5, CheckForMissingBuffs) end)
    self:RegisterEvent("SCENARIO_UPDATE", function() C_Timer.After(1, CheckForMissingBuffs) end)
    self:RegisterEvent("START_TIMER", function() C_Timer.After(1, CheckForMissingBuffs) end)
    self:RegisterEvent("UNIT_INVENTORY_CHANGED", function() C_Timer.After(0, CheckForMissingBuffs) end)
    self:RegisterEvent("TRAIT_CONFIG_UPDATED", function() C_Timer.After(0.5, CheckForMissingBuffs) end)
    self:RegisterEvent("SPELLS_CHANGED", function() C_Timer.After(0.5, CheckForMissingBuffs) end)
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function() C_Timer.After(1, CheckForMissingBuffs) end)
    self:RegisterEvent("CHALLENGE_MODE_COMPLETED", function() C_Timer.After(1, CheckForMissingBuffs) end)
    self:RegisterEvent("PLAYER_UPDATE_RESTING", function() C_Timer.After(0.5, CheckForMissingBuffs) end)
    self:RegisterEvent("UPDATE_SHAPESHIFT_FORM", function()
        CheckForMissingBuffs()
        UpdateStanceTextDisplay()
    end)
    self:RegisterEvent("UPDATE_SHAPESHIFT_FORMS", function()
        CheckForMissingBuffs()
        UpdateStanceTextDisplay()
    end)

    -- Warrior stance changes
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
        if unit ~= "player" then return end
        if playerClass ~= "WARRIOR" then return end
        if not WARRIOR_STANCE_SPELLS[spellID] then return end
        if isPreviewActive then return end

        local stanceDb = self.db and self.db.StanceDisplay
        if not stanceDb or not stanceDb.Enabled then return end

        local stancesDb = self.db and self.db.Stances
        local classSettings = stancesDb and stancesDb.WARRIOR
        if not classSettings then return end

        local spec = GetSpecialization()
        if not spec then return end
        local specId = GetSpecializationInfo(spec)
        local specName = SPEC_ID_TO_NAME[specId]
        if not specName then return end

        local specEnabledKey = specName .. "Enabled"
        if not classSettings[specEnabledKey] then return end

        local DEFAULT_STANCES = {
            Arms = 386164, Fury = 386196, Protection = 386208,
        }
        local requiredStanceId = tonumber(classSettings[specName]) or DEFAULT_STANCES[specName]

        if spellID == requiredStanceId then
            if stanceTimerHandle then
                stanceTimerHandle:Cancel()
                stanceTimerHandle = nil
            end
            stanceTimerActive = false
            if stanceFrame then stanceFrame:Hide() end
        else
            ShowStanceTimer(spellID)
        end
    end)

    -- M+ events
    self:RegisterEvent("CHALLENGE_MODE_START", function() C_Timer.After(1, CheckForMissingBuffs) end)
    self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", function() C_Timer.After(0.1, CheckForMissingBuffs) end)
    self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", function() C_Timer.After(0.1, CheckForMissingBuffs) end)

    C_Timer.After(2, CheckForMissingBuffs)
end

function MBUFFS:OnDisable()
    self:UnregisterAllEvents()
    HideAllNotifications()

    if stanceTimerHandle then
        stanceTimerHandle:Cancel()
        stanceTimerHandle = nil
    end
    stanceTimerActive = false
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------
function MBUFFS:Refresh()
    if self.db and self.db.Enabled then
        self:OnEnable()
        if not IsTrackingPaused() then
            CheckForMissingBuffs()
        end
    else
        self:OnDisable()
    end
end

function MBUFFS:ApplySettings()
    if not self.db then return end
    if not self.db.Enabled then return end

    if IsTrackingPaused() then
        self:RefreshPreview()
        return
    end

    local raidDb = self.db.RaidBuffDisplay
    local stanceDb = self.db.StanceDisplay
    local textDb = self.db.StanceText

    if containerFrame then
        KE:ApplyFramePosition(containerFrame, raidDb.Position, raidDb)
    end

    if stanceFrame then
        stanceFrame:SetSize(stanceDb.IconSize, stanceDb.IconSize)
        KE:ApplyFramePosition(stanceFrame, stanceDb.Position, stanceDb)
        KE:ApplyFontToText(stanceFrame.text, stanceDb.FontFace, stanceDb.FontSize, stanceDb.FontOutline)
    end

    if stanceTextFrame then
        KE:ApplyFontToText(stanceTextFrame.text, textDb.FontFace, textDb.FontSize, textDb.FontOutline)
        KE:ApplyFramePosition(stanceTextFrame, textDb.Position, textDb)

        local textPoint = KE:GetTextPointFromAnchor(textDb.Position.AnchorFrom)
        local textJustify = KE:GetTextJustifyFromAnchor(textDb.Position.AnchorFrom)
        stanceTextFrame.text:ClearAllPoints()
        stanceTextFrame.text:SetPoint(textPoint, stanceTextFrame, textPoint, 0, 0)
        stanceTextFrame.text:SetJustifyH(textJustify)

        if not textDb.Enabled then stanceTextFrame:Hide() end
    end

    for i, iconFrame in ipairs(activeIcons) do
        if currentMissingBuffs[i] then
            UpdateIconAppearance(iconFrame, currentMissingBuffs[i].buff, currentMissingBuffs[i].text)
        end
    end
    ArrangeIcons()
    UpdateStanceTextDisplay()
end

--------------------------------------------------------------------------------
-- Preview
--------------------------------------------------------------------------------
local function ShowPreviewIcons()
    if not containerFrame then CreateContainerFrame() end
    if not stanceFrame then CreateStanceFrame() end
    if not stanceTextFrame then CreateStanceTextFrame() end

    local raidDb = MBUFFS.db.RaidBuffDisplay or {}
    local stanceDb = MBUFFS.db.StanceDisplay or {}
    local textDb = MBUFFS.db.StanceText or {}

    local previewBuffs = {
        { buff = { spellId = 381748, text = "" },   text = "" },
        { buff = { spellId = 1126, text = "" },     text = "" },
        { buff = { spellId = 21562, text = "" },    text = "" },
        { buff = { spellId = 1459, text = "" },     text = "" },
        { buff = { spellId = 462854, text = "" },   text = "" },
        { buff = { spellId = 6673, text = "" },     text = "" },
        { buff = { spellId = 1235110, text = "" },  text = "" },
        { buff = { spellId = 462181, text = "" },   text = "" },
        { buff = { spellId = 1264426, text = "" },  text = "" },
        { buff = { spellId = 180608, text = "MH" }, text = "MH" },
        { buff = { spellId = 180608, text = "OH" }, text = "OH" },
    }

    wipe(currentMissingBuffs)
    for _, entry in ipairs(previewBuffs) do
        currentMissingBuffs[#currentMissingBuffs + 1] = entry
    end
    ShowMissingBuffs(previewBuffs)

    -- Stance icon preview
    local previewStanceSpell = 386164
    local texture = GetSpellTexture(previewStanceSpell)
    if texture and stanceFrame then
        stanceFrame.icon:SetTexture(texture)
        stanceFrame.text:SetText(MISSING_TEXT)
        stanceFrame:SetSize(stanceDb.IconSize, stanceDb.IconSize)
        KE:ApplyFontToText(stanceFrame.text, stanceDb.FontFace, stanceDb.FontSize, stanceDb.FontOutline)
        KE:ApplyFramePosition(stanceFrame, stanceDb.Position, stanceDb)
        stanceFrame:Show()
    end

    -- Stance text preview
    if stanceTextFrame then
        if not textDb.Enabled then
            stanceTextFrame:Hide()
        else
            KE:ApplyFontToText(stanceTextFrame.text, textDb.FontFace, textDb.FontSize, textDb.FontOutline)

            local previewText = "Battle Stance"
            local previewColor = { 1, 1, 1, 1 }

            local classData = textDb["WARRIOR"]
            if classData then
                local stanceSettings = classData["386164"]
                if stanceSettings then
                    if stanceSettings.Text and stanceSettings.Text ~= "" then
                        previewText = stanceSettings.Text
                    end
                    if stanceSettings.Color then
                        previewColor = stanceSettings.Color
                    end
                end
            end

            stanceTextFrame.text:SetText(previewText)
            stanceTextFrame.text:SetTextColor(previewColor[1], previewColor[2], previewColor[3], previewColor[4] or 1)

            KE:ApplyFramePosition(stanceTextFrame, textDb.Position, textDb)

            local textPoint = KE:GetTextPointFromAnchor(textDb.Position.AnchorFrom)
            local textJustify = KE:GetTextJustifyFromAnchor(textDb.Position.AnchorFrom)
            stanceTextFrame.text:ClearAllPoints()
            stanceTextFrame.text:SetPoint(textPoint, stanceTextFrame, textPoint, 0, 0)
            stanceTextFrame.text:SetJustifyH(textJustify)
            stanceTextFrame:Show()
        end
    end
end

function MBUFFS:IsPaused()
    return IsTrackingPaused()
end

function MBUFFS:RefreshPreview()
    if not IsTrackingPaused() then return end
    ShowPreviewIcons()
end

function MBUFFS:RegWithEditMode()
    if not KE.EditMode then return end

    if self.raidBuffContainer and not self.editModeRegistered_raid then
        KE.EditMode:RegisterElement({
            key = "MissingBuffs", displayName = "Missing Buffs", frame = self.raidBuffContainer,
            getPosition = function() return self.db.RaidBuffDisplay.Position end,
            setPosition = function(pos) self.db.RaidBuffDisplay.Position = pos; KE:ApplyFramePosition(self.raidBuffContainer, self.db.RaidBuffDisplay.Position, self.db.RaidBuffDisplay) end,
            getParentFrame = function() return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) end,
            guiPath = "MissingBuffs",
        })
        self.editModeRegistered_raid = true
    end

    if self.stanceContainer and not self.editModeRegistered_stance then
        KE.EditMode:RegisterElement({
            key = "MissingStanceIcon", displayName = "Stance Icon", frame = self.stanceContainer,
            getPosition = function() return self.db.StanceDisplay.Position end,
            setPosition = function(pos) self.db.StanceDisplay.Position = pos; KE:ApplyFramePosition(self.stanceContainer, self.db.StanceDisplay.Position, self.db.StanceDisplay) end,
            getParentFrame = function() return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) end,
            guiPath = "MissingBuffs",
        })
        self.editModeRegistered_stance = true
    end

    if self.stanceTextContainer and not self.editModeRegistered_text then
        KE.EditMode:RegisterElement({
            key = "StanceText", displayName = "Stance Text", frame = self.stanceTextContainer,
            getPosition = function() return self.db.StanceText.Position end,
            setPosition = function(pos) self.db.StanceText.Position = pos; KE:ApplyFramePosition(self.stanceTextContainer, self.db.StanceText.Position, self.db.StanceText) end,
            getParentFrame = function() return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) end,
            guiPath = "MissingBuffs",
        })
        self.editModeRegistered_text = true
    end
end

function MBUFFS:ShowPreview()
    if not containerFrame then CreateContainerFrame() end
    if not stanceFrame then CreateStanceFrame() end
    if not stanceTextFrame then CreateStanceTextFrame() end
    self:RegWithEditMode()
    isPreviewActive = true
    ShowPreviewIcons()
end

function MBUFFS:HidePreview()
    isPreviewActive = false
    HideAllNotifications()
    wipe(currentMissingBuffs)
    if self.db and self.db.Enabled then C_Timer.After(0.1, CheckForMissingBuffs) end
end

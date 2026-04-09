-- ╔══════════════════════════════════════════════════════════╗
-- ║  WarpDepleteForces.lua                                   ║
-- ║  Module: WarpDeplete Forces Tracker                      ║
-- ║  Purpose: Injects live pull forces tracking into         ║
-- ║           WarpDeplete using fingerprint-based mob ID.    ║
-- ║  Fixes: Death tooltip missing in M+ (secret GUID),      ║
-- ║         death names not class-colored (wrong API return).║
-- ║  Requires: WarpDeplete addon                             ║
-- ║  Data: MythicPlusCount (Midnight Season 1)               ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local WDF = KitnEssentials:NewModule("WarpDepleteForces", "AceEvent-3.0")

-- Local references
local CreateFrame = CreateFrame
local UnitExists = UnitExists
local UnitIsDead = UnitIsDead
local UnitCanAttack = UnitCanAttack
local UnitAffectingCombat = UnitAffectingCombat
local UnitLevel = UnitLevel
local UnitClassification = UnitClassification
local UnitSex = UnitSex
local UnitClass = UnitClass
local UnitPowerType = UnitPowerType
local C_ChallengeMode = C_ChallengeMode
local C_UnitAuras = C_UnitAuras
local UnitGUID = UnitGUID
local UnitName = UnitName
local GetNumGroupMembers = GetNumGroupMembers
local IsInRaid = IsInRaid
local wipe = wipe
local C_Timer = C_Timer
local pcall = pcall
local tonumber = tonumber
local format = string.format
local strsplit = strsplit
local issecretvalue = issecretvalue or function() return false end

---------------------------------------------------------------------------------
-- Dungeon Data (Midnight Season 1 — from MythicPlusCount / MDT)
---------------------------------------------------------------------------------

local DUNGEON_DATA = {
    [558] = { -- Magisters' Terrace
        totalForces = 585,
        mobs = {
            [232369] = 7, [251861] = 12, [240973] = 12, [234069] = 1,
            [234065] = 5, [234064] = 7, [234068] = 12, [234066] = 12,
            [249086] = 7, [232106] = 1, [234062] = 16, [234124] = 5,
            [234486] = 5, [241354] = 1, [257447] = 5,
        },
    },
    [560] = { -- Maisara Caverns
        totalForces = 607,
        mobs = {
            [248684] = 5, [242964] = 7, [248686] = 15, [248685] = 7,
            [249020] = 3, [253302] = 15, [249002] = 2, [249022] = 5,
            [248693] = 1, [248678] = 15, [254740] = 5, [249030] = 15,
            [248692] = 2, [248690] = 2, [249036] = 7, [253683] = 10,
            [249025] = 15, [249024] = 15, [253458] = 7, [253473] = 5,
        },
    },
    [559] = { -- Nexus-Point Xenas
        totalForces = 596,
        mobs = {
            [241643] = 6, [248501] = 1, [241644] = 5, [241645] = 3,
            [241647] = 6, [248708] = 7, [248373] = 15, [248706] = 3,
            [248506] = 8, [241660] = 15, [251853] = 7, [248502] = 15,
            [241642] = 15, [254932] = 2, [254926] = 7, [254928] = 3,
        },
    },
    [557] = { -- Windrunner Spire
        totalForces = 591,
        mobs = {
            [232070] = 7, [232071] = 4, [232113] = 15, [232116] = 5,
            [232173] = 5, [232171] = 6, [232232] = 4, [232175] = 15,
            [232176] = 20, [232056] = 7, [234673] = 1, [232067] = 7,
            [232063] = 15, [238099] = 1, [236894] = 17, [238049] = 5,
            [232119] = 7, [232122] = 15, [232283] = 5, [232147] = 6,
            [232148] = 7, [232146] = 15, [258868] = 4, [250883] = 2,
        },
    },
    [402] = { -- Algeth'ar Academy
        totalForces = 460,
        mobs = {
            [196045] = 5, [196577] = 5, [196671] = 15, [196694] = 4,
            [196044] = 4, [192680] = 18, [192329] = 2, [192333] = 15,
            [197406] = 4, [197219] = 9, [197398] = 2, [196200] = 15,
            [196202] = 5,
        },
    },
    [239] = { -- Seat of the Triumvirate
        totalForces = 568,
        mobs = {
            [124171] = 10, [122571] = 20, [122413] = 9, [255320] = 8,
            [122421] = 15, [122404] = 8, [252756] = 15, [122423] = 15,
            [122322] = 1, [122403] = 3, [122405] = 7,
        },
    },
    [161] = { -- Skyreach
        totalForces = 431,
        mobs = {
            [76132] = 5, [78932] = 7, [250992] = 1, [75976] = 1,
            [79462] = 5, [79466] = 7, [79467] = 7, [78933] = 15,
            [76087] = 12, [79093] = 2, [76154] = 5, [76149] = 15,
            [76205] = 5, [79303] = 12,
        },
    },
    [556] = { -- Pit of Saron
        totalForces = 643,
        mobs = {
            [252551] = 15, [252567] = 7, [252561] = 5, [252563] = 15,
            [252558] = 5, [252610] = 11, [252559] = 2, [252606] = 6,
            [252555] = 6, [257190] = 9, [252565] = 5, [252566] = 7,
            [252564] = 20,
        },
    },
}

---------------------------------------------------------------------------------
-- Fingerprint Data (Midnight Season 1 — from MythicPlusCount)
---------------------------------------------------------------------------------

local FINGERPRINTS = {
    [402] = {
        ["1102558:0:elite:1:WARRIOR:1"] = 196694,
        ["3952432:0:elite:1:WARRIOR:1"] = 196045,
        ["3951256:0:elite:1:WARRIOR:1"] = 197406,
        ["4077816:1:elite:1:WARRIOR:1"] = 192333,
        ["4033880:1:elite:1:WARRIOR:1"] = 192680,
        ["1100483:0:minus:1:WARRIOR:1"] = 192329,
        ["4216711:0:elite:3:PALADIN:0"] = 196202,
        ["617127:0:elite:1:WARRIOR:1"] = 196044,
        ["4217881:1:elite:3:WARRIOR:1"] = 196200,
        ["1382579:0:elite:2:WARRIOR:1"] = 196577,
        ["1722688:0:normal:1:WARRIOR:1"] = 197398,
        ["1722688:1:elite:1:WARRIOR:1"] = 197219,
    },
    [560] = {
        ["6875167:0:elite:3:WARRIOR:1"] = 249036,
        ["6875167:0:elite:3:PALADIN:0"] = 254740,
        ["6366139:0:elite:3:WARRIOR:1"] = 242964,
        ["6366139:0:elite:3:WARRIOR:1:0"] = 248693,
        ["6366139:0:elite:3:WARRIOR:1:1"] = 242964,
        ["6366139:1:elite:3:PALADIN:0"] = 248686,
        ["6366141:0:elite:2:WARRIOR:1"] = 248684,
        ["6366141:1:elite:2:PALADIN:0"] = 253458,
        ["1716306:0:elite:1:WARRIOR:1"] = 248690,
        ["1716306:0:elite:1:WARRIOR:1:1"] = 248690,
        ["6875165:0:elite:2:PALADIN:0"] = 248685,
        ["6875165:1:elite:2:PALADIN:0"] = 253683,
        ["6875165:0:elite:2:WARRIOR:1"] = 249036,
        ["7127711:1:elite:2:WARRIOR:1"] = 249030,
        ["7127711:1:elite:2:WARRIOR:1:1"] = 249030,
        ["4034801:1:elite:1:WARRIOR:1"] = 248678,
        ["1695668:1:elite:1:PALADIN:0"] = 249024,
        ["804504:0:elite:1:WARRIOR:1"] = 253473,
        ["6163242:0:elite:1:WARRIOR:1"] = 249020,
        ["1266661:0:elite:1:WARRIOR:1"] = 249022,
        ["1719446:1:elite:1:WARRIOR:1"] = 249025,
        ["1719446:1:elite:1:WARRIOR:1:1"] = 249025,
        ["124640:0:normal:1:WARRIOR:1"] = 249002,
        ["124640:0:normal:1:WARRIOR:1:1"] = 249002,
        ["124640:1:elite:1:PALADIN:0"] = 253302,
        ["1716306:0:elite:1:WARRIOR:1:0"] = 248692,
    },
    [239] = {
        ["6152557:0:elite:3:PALADIN:0"] = 122404,
        ["6152557:1:elite:3:PALADIN:0"] = 122423,
        ["6152557:0:elite:3:WARRIOR:1"] = 122403,
        ["1572365:0:elite:2:WARRIOR:1"] = 122413,
        ["5926159:1:elite:2:WARRIOR:1"] = 122421,
        ["6705352:1:elite:1:WARRIOR:1"] = 122571,
        ["6705352:1:elite:1:WARRIOR:1:1"] = 122571,
        ["6254042:1:elite:1:WARRIOR:1"] = 252756,
        ["1574725:0:normal:0:?:-1:0"] = 255320,
        ["1570694:0:elite:1:WARRIOR:1"] = 255320,
        ["1574725:0:normal:1:WARRIOR:1"] = 122322,
        ["1572377:1:elite:3:PALADIN:0"] = 124171,
        ["6152557:0:elite:3:PALADIN:0:1"] = 122405,
    },
    [557] = {
        ["1100258:0:elite:3:WARRIOR:1"] = 232070,
        ["1100087:0:elite:2:WARRIOR:1"] = 232071,
        ["1100087:1:elite:2:PALADIN:0"] = 232113,
        ["6251997:1:elite:1:PALADIN:0"] = 232122,
        ["997378:0:elite:3:WARRIOR:1"] = 232173,
        ["959310:0:elite:2:WARRIOR:1"] = 232171,
        ["1252028:1:elite:3:WARRIOR:1"] = 232175,
        ["1598184:1:elite:1:WARRIOR:1"] = 232176,
        ["6119019:0:elite:1:WARRIOR:1"] = 232056,
        ["1513629:0:normal:1:WARRIOR:1"] = 234673,
        ["1513629:0:elite:1:WARRIOR:1"] = 232067,
        ["6338575:1:elite:1:WARRIOR:1"] = 232063,
        ["5095674:0:normal:1:WARRIOR:1"] = 238099,
        ["5095674:1:elite:1:ROGUE:3"] = 236894,
        ["1373320:0:elite:1:WARRIOR:1"] = 232283,
        ["6366139:0:elite:3:WARRIOR:1"] = 232148,
        ["930099:1:elite:2:PALADIN:0"] = 232146,
        ["917116:0:elite:2:WARRIOR:1"] = 258868,
    },
    [559] = {
        ["6152557:0:elite:3:WARRIOR:1"] = 241643,
        ["6152557:0:elite:3:WARRIOR:1:1"] = 241643,
        ["6152557:0:elite:3:PALADIN:0"] = 241644,
        ["6152557:0:elite:3:PALADIN:0:1"] = 241644,
        ["6377937:0:elite:1:WARRIOR:1"] = 241645,
        ["6377937:0:elite:1:WARRIOR:1:1"] = 241645,
        ["5926159:0:elite:2:WARRIOR:1"] = 241647,
        ["5926159:0:elite:2:WARRIOR:1:1"] = 241647,
        ["5926159:0:normal:2:PALADIN:0"] = 248708,
        ["5926159:1:elite:1:MAGE:0"] = 248373,
        ["5926159:1:elite:1:MAGE:0:1"] = 248373,
        ["6705352:0:normal:1:PALADIN:0"] = 248706,
        ["6705352:0:normal:1:PALADIN:0:1"] = 248706,
        ["6705352:0:elite:1:PALADIN:0"] = 251853,
        ["6705352:0:elite:1:PALADIN:0:1"] = 251853,
        ["6181818:1:elite:1:WARRIOR:1"] = 248506,
        ["6181816:1:elite:1:MAGE:0"] = 241660,
        ["6181814:1:elite:1:WARRIOR:1"] = 248502,
        ["6730408:1:elite:2:PALADIN:0"] = 241642,
        ["124640:0:minus:1:WARRIOR:1"] = 254932,
        ["124640:0:minus:1:WARRIOR:1:1"] = 254932,
        ["3952432:0:elite:1:WARRIOR:1"] = 254926,
        ["2966279:0:normal:1:WARRIOR:1"] = 254928,
        ["2966279:0:normal:1:WARRIOR:1:1"] = 254928,
        ["7344962:0:normal:1:WARRIOR:1"] = 248501,
        ["7344962:0:normal:1:WARRIOR:1:1"] = 248501,
    },
    [161] = {
        ["986699:0:elite:1:WARRIOR:1"] = 76132,
        ["986699:0:elite:1:PALADIN:0"] = 78932,
        ["986699:1:elite:1:WARRIOR:1"] = 79303,
        ["1033563:0:elite:1:WARRIOR:1"] = 75976,
        ["1000727:1:elite:1:PALADIN:0"] = 76087,
        ["3952432:1:elite:1:PALADIN:0"] = 78933,
        ["1031301:1:normal:1:WARRIOR:1"] = 79093,
        ["948417:1:elite:1:WARRIOR:1"] = 76149,
        ["3946582:0:elite:1:ROGUE:3"] = 250992,
    },
    [556] = {
        ["3087468:0:elite:2:WARRIOR:1"] = 252551,
        ["3487358:0:elite:2:PALADIN:0"] = 252566,
        ["3487358:0:elite:2:WARRIOR:1"] = 252561,
        ["1574421:0:elite:1:WARRIOR:1"] = 252558,
        ["125234:0:normal:1:WARRIOR:1"] = 252559,
        ["122815:1:elite:2:WARRIOR:1"] = 252610,
        ["124131:0:elite:3:WARRIOR:1"] = 252606,
        ["3197237:0:elite:1:WARRIOR:1"] = 252555,
        ["4672491:1:elite:1:WARRIOR:1"] = 257190,
        ["3482565:1:elite:2:WARRIOR:1"] = 252563,
        ["1709401:1:elite:1:WARRIOR:1"] = 252564,
    },
    [558] = {
        ["1100258:0:elite:3:PALADIN:0"] = 232369,
        ["1100258:1:elite:3:PALADIN:0"] = 251861,
        ["1100087:0:elite:2:WARRIOR:1"] = 234124,
        ["1100087:0:elite:2:PALADIN:0"] = 234486,
        ["6705352:1:elite:1:ROGUE:3"] = 234068,
        ["1410362:1:elite:1:WARRIOR:1"] = 234066,
        ["3087474:0:elite:1:PALADIN:0"] = 234064,
        ["7344962:0:normal:1:WARRIOR:1"] = 234069,
        ["6316091:1:elite:1:ROGUE:3"] = 234062,
        ["6253063:0:normal:1:PALADIN:0"] = 232106,
        ["1102558:0:normal:1:PALADIN:0"] = 241354,
        ["6377937:0:elite:1:WARRIOR:1"] = 257447,
    },
}

---------------------------------------------------------------------------------
-- Fingerprint System
---------------------------------------------------------------------------------

local modelFrame = nil

local function safeRead(fn, default)
    local ok, val = pcall(fn)
    if ok and val ~= nil and not issecretvalue(val) then return val end
    return default
end

local function GetModelFileID(unit)
    if not modelFrame then
        modelFrame = CreateFrame("PlayerModel")
    end
    local ok, fileID = pcall(function()
        modelFrame:SetUnit(unit)
        local id = modelFrame:GetModelFileID()
        if id and not issecretvalue(id) and id > 0 then return id end
        return nil
    end)
    if ok then return fileID end
    return nil
end

local function GetBuffCount(unit)
    if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then return 0 end
    local count = 0
    for i = 1, 20 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
        if ok and aura then
            count = count + 1
        else
            break
        end
    end
    return count
end

local function GetFingerprint(unit)
    local modelID = GetModelFileID(unit)
    if not modelID then return nil end

    local level  = safeRead(function() return UnitLevel(unit) end, 0)
    local classn = safeRead(function() return UnitClassification(unit) end, "?")
    local sex    = safeRead(function() return UnitSex(unit) end, 0)
    local class  = safeRead(function() return select(2, UnitClass(unit)) end, "?")
    local ptype  = safeRead(function() return UnitPowerType(unit) end, -1)

    local relLevel = level % 10
    return format("%d:%d:%s:%d:%s:%d", modelID, relLevel, classn, sex, class, ptype)
end

local function GetNpcIDFromGUID(guid)
    if not guid or issecretvalue(guid) then return nil end
    if type(guid) ~= "string" then return nil end
    local guidType = strsplit("-", guid)
    if guidType ~= "Creature" and guidType ~= "Vehicle" then return nil end
    local _, _, _, _, _, npcID = strsplit("-", guid)
    return npcID and tonumber(npcID)
end

local function GetNpcIDForUnit(unit, mapID)
    if not unit or not mapID then return nil end
    local fpMap = FINGERPRINTS[mapID]
    if not fpMap then return nil end

    -- Strategy 1: GUID (works outside instances)
    local guid = UnitGUID(unit)
    if guid and not issecretvalue(guid) then
        local npcID = GetNpcIDFromGUID(guid)
        if npcID then return npcID end
    end

    -- Strategy 2: Extended fingerprint (with buff count tiebreaker)
    local baseFP = GetFingerprint(unit)
    if not baseFP then return nil end
    local extFP = baseFP .. ":" .. GetBuffCount(unit)
    if fpMap[extFP] then return fpMap[extFP] end

    -- Strategy 3: Primary fingerprint
    if fpMap[baseFP] then return fpMap[baseFP] end

    return nil
end

local function GetMobForces(npcID, mapID)
    local dungeon = DUNGEON_DATA[mapID]
    if not dungeon then return 0 end
    return dungeon.mobs[npcID] or 0
end

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------

function WDF:UpdateDB()
    self.db = KE.db.profile.Dungeons.WarpDepleteForces
end

---------------------------------------------------------------------------------
-- Pull Tracking State
---------------------------------------------------------------------------------

local inCombat = false
local currentMapID = nil
local ticker = nil

local function GetActiveMapID()
    if C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID then
        local mapID = C_ChallengeMode.GetActiveChallengeMapID()
        if mapID and not issecretvalue(mapID) then return mapID end
    end
    return nil
end

local function ScanPullForces()
    if not inCombat or not currentMapID then return 0 end

    -- Only count ALIVE mobs in combat on nameplates.
    -- WarpDeplete already tracks killed forces via its own
    -- SCENARIO_CRITERIA_UPDATE → SetForcesCurrent() pipeline.
    -- SetForcesPull is the OVERLAY showing what's still alive.
    local aliveCount = 0
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) and not UnitIsDead(unit)
           and UnitCanAttack("player", unit) and UnitAffectingCombat(unit) then
            -- Skip bosses (level 92+)
            local level = safeRead(function() return UnitLevel(unit) end, 0)
            if level < 92 then
                local npcID = GetNpcIDForUnit(unit, currentMapID)
                if npcID then
                    local forces = GetMobForces(npcID, currentMapID)
                    if forces > 0 then
                        aliveCount = aliveCount + forces
                    end
                end
            end
        end
    end

    return aliveCount
end

local function PushToWarpDeplete(pullCount)
    if not WarpDeplete then return end
    if WarpDeplete.SetForcesPull then
        WarpDeplete:SetForcesPull(pullCount)
    end
end

local function OnCombatTick()
    if not inCombat then return end
    local mapID = GetActiveMapID()
    if not mapID then return end
    currentMapID = mapID

    local pullForces = ScanPullForces()
    PushToWarpDeplete(pullForces)
end

---------------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------------

local function SetupTooltip()
    if not WDF.db.Tooltip then return end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
        if not WDF.db or not WDF.db.Tooltip then return end
        if not currentMapID then return end
        if not C_ChallengeMode.IsChallengeModeActive() then return end

        local npcID = nil

        -- Try GUID first
        if data and data.guid and not issecretvalue(data.guid) then
            npcID = GetNpcIDFromGUID(data.guid)
        end

        -- Try fingerprint via mouseover
        if not npcID and UnitExists("mouseover") then
            npcID = GetNpcIDForUnit("mouseover", currentMapID)
        end

        if not npcID then return end

        local forces = GetMobForces(npcID, currentMapID)
        if forces <= 0 then return end

        local dungeon = DUNGEON_DATA[currentMapID]
        if not dungeon then return end

        local pct = (forces / dungeon.totalForces) * 100
        local themeHex = KE:GetThemeColorHex()
        tooltip:AddLine(format("|cff%sCount:|r |cffffffff+%d / %.2f%%|r", themeHex, forces, pct))
        tooltip:Show()
    end)
end

---------------------------------------------------------------------------------
-- Death Tracking Fix
-- WarpDeplete's UNIT_DIED bails when guid is secret (Midnight M+).
-- We register our own UNIT_DIED and scan the roster for dead players,
-- injecting directly into WarpDeplete.state.deathDetails with the
-- correct class token from UnitClass (not UnitClassFromGUID).
---------------------------------------------------------------------------------

local deathFixApplied = false
local recentDeaths = {} -- [name] = true, prevents duplicate entries per death

local function SetupDeathClassFix()
    if deathFixApplied then return end
    if not WarpDeplete then return end

    -- Our own UNIT_DIED handler — bypasses WarpDeplete's GUID check
    local deathFrame = CreateFrame("Frame")
    deathFrame:RegisterEvent("UNIT_DIED")
    deathFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    deathFrame:SetScript("OnEvent", function(_, event)
        if not WarpDeplete or not WarpDeplete.state then return end

        if event == "PLAYER_REGEN_ENABLED" then
            wipe(recentDeaths)
            return
        end

        -- UNIT_DIED: scan roster for who just died
        local timer = WarpDeplete.state.timer or 0

        -- Check player
        if UnitIsDead("player") and not recentDeaths[UnitName("player")] then
            local name = UnitName("player")
            local _, classToken = UnitClass("player")
            if name and classToken then
                recentDeaths[name] = true
                WarpDeplete:AddDeathDetails(timer, name, classToken)
            end
        end

        -- Check party/raid
        local size = GetNumGroupMembers()
        if size > 0 then
            local token = IsInRaid() and "raid" or "party"
            for i = 1, size do
                local unit = token .. i
                if UnitExists(unit) and UnitIsDead(unit) then
                    local name = UnitName(unit)
                    if name and not recentDeaths[name] then
                        local _, classToken = UnitClass(unit)
                        if classToken then
                            recentDeaths[name] = true
                            WarpDeplete:AddDeathDetails(timer, name, classToken)
                        end
                    end
                end
            end
        end
    end)

    deathFixApplied = true
end

---------------------------------------------------------------------------------
-- Event Handlers
---------------------------------------------------------------------------------

function WDF:PLAYER_REGEN_DISABLED()
    currentMapID = GetActiveMapID()
    if not currentMapID then return end
    inCombat = true
    OnCombatTick()

    -- Start nameplate scan ticker for this combat
    if not ticker then
        ticker = C_Timer.NewTicker(0.5, function()
            if inCombat and currentMapID then
                OnCombatTick()
            end
        end)
    end
end

function WDF:PLAYER_REGEN_ENABLED()
    -- Stop ticker
    if ticker then
        ticker:Cancel()
        ticker = nil
    end

    C_Timer.After(0.5, function()
        inCombat = false
        PushToWarpDeplete(0)
    end)
end

function WDF:SCENARIO_CRITERIA_UPDATE()
    if inCombat then
        OnCombatTick()
    end
end

function WDF:CHALLENGE_MODE_START()
    currentMapID = GetActiveMapID()
    inCombat = false
    PushToWarpDeplete(0)
end

function WDF:CHALLENGE_MODE_COMPLETED()
    inCombat = false
    currentMapID = nil
    PushToWarpDeplete(0)
end

function WDF:CHALLENGE_MODE_RESET()
    currentMapID = nil
    inCombat = false
end

function WDF:ZONE_CHANGED_NEW_AREA()
    currentMapID = GetActiveMapID()
end

function WDF:PLAYER_ENTERING_WORLD()
    currentMapID = GetActiveMapID()
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------

function WDF:ApplySettings()
    -- No visual settings to apply — this module feeds WarpDeplete
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------

function WDF:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function WDF:OnEnable()
    -- Require WarpDeplete
    if not WarpDeplete then
        KE:Print("WarpDeplete+: WarpDeplete addon not found. Module disabled.")
        self:SetEnabledState(false)
        return
    end

    if not self.db.Enabled then return end

    -- Register events
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    self:RegisterEvent("SCENARIO_CRITERIA_UPDATE")
    self:RegisterEvent("CHALLENGE_MODE_START")
    self:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    self:RegisterEvent("CHALLENGE_MODE_RESET")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")

    -- Detect current dungeon (covers /reload inside M+)
    currentMapID = GetActiveMapID()

    -- Tooltip hook
    SetupTooltip()

    -- Fix WarpDeplete death class colors (uses className instead of classFilename)
    SetupDeathClassFix()
end

function WDF:OnDisable()
    self:UnregisterAllEvents()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    inCombat = false
    PushToWarpDeplete(0)
end

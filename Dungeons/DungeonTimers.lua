-- ╔══════════════════════════════════════════════════════════╗
-- ║  DungeonTimers.lua                                       ║
-- ║  Module: Dungeon Timers                                  ║
-- ║  Purpose: BigWigs-integrated dungeon timer system with   ║
-- ║           per-dungeon triggers, bar/text groups, and     ║
-- ║           role-based load conditions.                    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class DungeonTimers: AceModule, AceEvent-3.0, AceTimer-3.0
local DT = KitnEssentials:NewModule("DungeonTimers", "AceEvent-3.0", "AceTimer-3.0")

local CreateFrame = CreateFrame
local GetTime = GetTime
local C_Timer = C_Timer
local unpack = unpack
local floor = math.floor
local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local type = type
local select = select
local IsInInstance = IsInInstance
local GetInstanceInfo = GetInstanceInfo
local CopyTable = CopyTable
local pcall = pcall
local issecretvalue = issecretvalue
local tostring = tostring
local tonumber = tonumber
local math_min = math.min
local table_insert = table.insert
local GetSpecialization = GetSpecialization
local GetSpecializationRole = GetSpecializationRole
local PlaySoundFile = PlaySoundFile
local C_Spell = C_Spell

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------

DT.triggerFrames = {}
DT.triggerBars = {}
DT.barGroupFrame = nil
DT.textGroupFrame = nil
DT.previewsAllowed = false
DT.spellCache = {}
DT.currentDungeonKey = nil
DT.nextExpire = nil
DT.recheckTimer = nil
DT.scheduledScans = {}
DT.visualTicker = nil
DT.positionDirty = false
local instanceIdToDungeonKey = nil
local VISUAL_UPDATE_INTERVAL = 0.033

-- Flip to true to trace BigWigs events, bar lifecycle, and extendTimer guards.
local DEBUG_DT = false

-- Preview-teardown investigation tick counter — every Nth OnVisualUpdate emits
-- a state snapshot. Cheap when DEBUG_DT is false (single increment + compare).
local _dtTickCounter = 0
local DT_TICK_LOG_EVERY = 30   -- ~once/second at 0.033s interval

-- BigWigs events to register
local BIGWIGS_EVENTS = {
    "BigWigs_Timer",
    "BigWigs_TargetTimer",
    "BigWigs_CastTimer",
    "BigWigs_StartBreak",
    "BigWigs_StartPull",
    "BigWigs_StopBar",
    "BigWigs_StopBars",
    "BigWigs_PauseBar",
    "BigWigs_ResumeBar",
    "BigWigs_OnBossDisable",
    "BigWigs_Message_echo",
}

---------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------

-- Get current player role
local function GetPlayerRole()
    local role = GetSpecializationRole(GetSpecialization())
    return role or "DAMAGER"
end

-- Check if trigger should load based on load conditions
local function CheckLoadConditions(trigger, isPreview)
    if isPreview then return true end
    if not trigger.loadRoleEnabled then return true end
    local role = GetPlayerRole()
    if role == "TANK" and trigger.loadRoleTank then return true end
    if role == "HEALER" and trigger.loadRoleHealer then return true end
    if role == "DAMAGER" and trigger.loadRoleDPS then return true end
    return false
end

-- Play a sound by LSM name
local function PlayTriggerSound(soundName, isPreview)
    if isPreview then return end
    if not soundName or soundName == "" or soundName == "None" then return end
    local LSM = KE.LSM
    if not LSM then return end
    local file = LSM:Fetch("sound", soundName)
    if file then
        PlaySoundFile(file, "Master")
    end
end

---------------------------------------------------------------------------------
-- Initialization
---------------------------------------------------------------------------------

function DT:UpdateDB()
    if KE.db and KE.db.profile then
        self.db = KE.db.profile.Dungeons.DungeonTimers
        if self.db and not self.db.Dungeons then
            self.db.Dungeons = {}
        end
    end
end

-- Build reverse lookup table from instanceId to dungeonKey
local function BuildInstanceIdLookup(dungeons)
    if instanceIdToDungeonKey then return end
    instanceIdToDungeonKey = {}
    for dungeonKey, dungeonData in pairs(dungeons) do
        if dungeonData.instanceId then
            instanceIdToDungeonKey[dungeonData.instanceId] = dungeonKey
        end
    end
end

---------------------------------------------------------------------------------
-- Dungeon Detection
---------------------------------------------------------------------------------

function DT:UpdateCurrentDungeon()
    local inInstance, instanceType = IsInInstance()
    if not inInstance or (instanceType ~= "party" and instanceType ~= "raid") then
        if self.currentDungeonKey then
            self.currentDungeonKey = nil
            self:StopAllBars()
        end
        return
    end

    local instanceId = select(8, GetInstanceInfo())
    if not instanceId then
        self.currentDungeonKey = nil
        return
    end

    if self.db and self.db.Dungeons then
        BuildInstanceIdLookup(self.db.Dungeons)
    end

    local newDungeonKey = instanceIdToDungeonKey and instanceIdToDungeonKey[instanceId] or nil

    if self.currentDungeonKey ~= newDungeonKey then
        self:StopAllBars()
        self.currentDungeonKey = newDungeonKey
    end
end

function DT:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

---------------------------------------------------------------------------------
-- Display Settings
---------------------------------------------------------------------------------

function DT:GetBarDisplaySettings()
    self:UpdateDB()
    return self.db and self.db.BarDisplay or {}
end

function DT:GetTextDisplaySettings()
    self:UpdateDB()
    return self.db and self.db.TextDisplay or {}
end

function DT:GetGroupSettings(groupType)
    self:UpdateDB()
    if not self.db then return {} end
    return groupType == "bar" and self.db.BarGroup or self.db.TextGroup
end

---------------------------------------------------------------------------------
-- Group Frames
---------------------------------------------------------------------------------

function DT:GetBarGroupFrame()
    if not self.barGroupFrame then
        local frame = CreateFrame("Frame", "KE_DungeonTimers_BarGroup", UIParent)
        frame:SetSize(1, 1)
        frame:SetFrameStrata("HIGH")
        frame:Show()
        self.barGroupFrame = frame
    end
    return self.barGroupFrame
end

function DT:GetTextGroupFrame()
    if not self.textGroupFrame then
        local frame = CreateFrame("Frame", "KE_DungeonTimers_TextGroup", UIParent)
        frame:SetSize(1, 1)
        frame:SetFrameStrata("HIGH")
        frame:Show()
        self.textGroupFrame = frame
    end
    return self.textGroupFrame
end

function DT:UpdateBarGroupPosition()
    local group = self:GetBarGroupFrame()
    local settings = self:GetGroupSettings("bar")
    local pos = settings.Position
    local parent = KE:ResolveAnchorFrame(settings.anchorFrameType, settings.ParentFrame)

    -- 1x1 anchor pattern (matches DungeonCasts/KickTracker):
    -- Group stays parented to UIParent to avoid clipping by anchor frame parents
    -- (e.g. ElvUI unit frames clip descendants), but anchors TO the resolved
    -- parent for positioning. Individual bars anchor to the group frame.
    group:ClearAllPoints()
    group:SetPoint(pos.AnchorFrom, parent, pos.AnchorTo, pos.XOffset, pos.YOffset)
    group:SetFrameStrata(settings.Strata or "HIGH")
end

function DT:UpdateTextGroupPosition()
    local group = self:GetTextGroupFrame()
    local settings = self:GetGroupSettings("text")
    local pos = settings.Position
    local parent = KE:ResolveAnchorFrame(settings.anchorFrameType, settings.ParentFrame)

    group:ClearAllPoints()
    group:SetPoint(pos.AnchorFrom, parent, pos.AnchorTo, pos.XOffset, pos.YOffset)
    group:SetFrameStrata(settings.Strata or "HIGH")
end

---------------------------------------------------------------------------------
-- Positioning
---------------------------------------------------------------------------------

function DT:PositionAllBars()
    self:UpdateBarGroupPosition()

    local settings = self:GetGroupSettings("bar")
    local spacing = settings.Spacing
    local growUp = settings.GrowthDirection == "UP"
    local barDisplay = self:GetBarDisplaySettings()
    local barHeight = barDisplay.barHeight or 20
    local barWidth = barDisplay.barWidth or 200
    local group = self:GetBarGroupFrame()

    local frames = {}
    local scannedFrames = 0
    for _, frame in pairs(self.triggerFrames) do
        scannedFrames = scannedFrames + 1
        if frame and frame:IsShown() and frame.isBarDisplay == true then
            table_insert(frames, frame)
        end
    end

    if DEBUG_DT then
        KE:Print(string.format("[DT] PositionAllBars scanned=%d positioned=%d",
            scannedFrames, #frames))
    end

    table.sort(frames, function(a, b)
        if a.dungeonKey ~= b.dungeonKey then
            return (a.dungeonKey or "") < (b.dungeonKey or "")
        end
        return (tonumber(a.triggerId) or 0) < (tonumber(b.triggerId) or 0)
    end)

    -- 1x1 anchor pattern: bars grow outward from the group anchor point.
    -- Use the user's AnchorFrom so CENTER stays centered, TOPLEFT stays left-aligned, etc.
    local anchorFrom = settings.Position.AnchorFrom or "CENTER"

    for i, frame in ipairs(frames) do
        frame:SetSize(barWidth, barHeight)
        frame:ClearAllPoints()

        local offset = (i - 1) * (barHeight + spacing)
        if growUp then
            frame:SetPoint(anchorFrom, group, anchorFrom, 0, offset)
        else
            frame:SetPoint(anchorFrom, group, anchorFrom, 0, -offset)
        end
    end
end

function DT:PositionAllTexts()
    self:UpdateTextGroupPosition()

    local settings = self:GetGroupSettings("text")
    local spacing = settings.Spacing
    local growUp = settings.GrowthDirection == "UP"
    local textDisplay = self:GetTextDisplaySettings()
    local textFontSize = textDisplay.fontSize or 14
    local textHeight = textFontSize + 4
    local textWidth = 400
    local group = self:GetTextGroupFrame()

    local frames = {}
    for _, frame in pairs(self.triggerFrames) do
        if frame and frame:IsShown() and frame.isBarDisplay == false then
            table_insert(frames, frame)
        end
    end

    table.sort(frames, function(a, b)
        if a.dungeonKey ~= b.dungeonKey then
            return (a.dungeonKey or "") < (b.dungeonKey or "")
        end
        return (tonumber(a.triggerId) or 0) < (tonumber(b.triggerId) or 0)
    end)

    local anchorFrom = settings.Position.AnchorFrom or "CENTER"

    for i, frame in ipairs(frames) do
        frame:SetSize(textWidth, textHeight)
        frame:ClearAllPoints()

        local offset = (i - 1) * (textHeight + spacing)
        if growUp then
            frame:SetPoint(anchorFrom, group, anchorFrom, 0, offset)
        else
            frame:SetPoint(anchorFrom, group, anchorFrom, 0, -offset)
        end
    end
end

function DT:PositionAllFrames()
    -- Eager call clears any pending deferred call so the next-frame timer
    -- (scheduled by _RequestPositionUpdate) skips redundant work.
    self._pendingPositionUpdate = false
    self:PositionAllBars()
    self:PositionAllTexts()
end

-- Coalesce per-trigger position updates into one call per frame. Inside
-- ShowTriggerDisplay/HideTriggerDisplay each call would otherwise scan the
-- full triggerFrames cache (which grows with every visited dungeon panel),
-- so a 12-trigger dungeon click did 12+ scans. The deferred timer fires on
-- the next frame so multiple show/hide calls within one frame collapse to a
-- single PositionAllFrames pass.
function DT:_RequestPositionUpdate()
    if self._pendingPositionUpdate then return end
    self._pendingPositionUpdate = true
    C_Timer.After(0, function()
        if self._pendingPositionUpdate then
            self:PositionAllFrames()
        end
    end)
end

---------------------------------------------------------------------------------
-- Trigger CRUD
---------------------------------------------------------------------------------

function DT:CreateTrigger(dungeonKey)
    self:UpdateDB()
    if not self.db or not self.db.Dungeons then return nil end

    if not self.db.Dungeons[dungeonKey] then
        self.db.Dungeons[dungeonKey] = { Enabled = true, Triggers = {} }
    end

    local dungeonDb = self.db.Dungeons[dungeonKey]
    if not dungeonDb.Triggers then
        dungeonDb.Triggers = {}
    end

    local maxId = 0
    for id in pairs(dungeonDb.Triggers) do
        local numId = tonumber(id)
        if numId and numId > maxId then
            maxId = numId
        end
    end
    local newId = maxId + 1

    local trigger = CopyTable(self.db.TriggerDefaults)
    trigger.id = newId
    trigger.name = "New Timer " .. newId
    dungeonDb.Triggers[newId] = trigger

    return newId
end

function DT:GetTriggerConfig(trigger)
    local isBar = trigger.displayType == "bar"
    local barDisplay = self:GetBarDisplaySettings()
    local textDisplay = self:GetTextDisplaySettings()

    return {
        id = trigger.id,
        name = trigger.name,
        enabled = trigger.enabled ~= false,
        triggerType = trigger.triggerType,
        spellId = trigger.spellId,
        message = trigger.message,
        messageOperator = trigger.messageOperator,
        remainingEnabled = trigger.remainingEnabled,
        remainingOperator = trigger.remainingOperator,
        remainingValue = trigger.remainingValue,
        countEnabled = trigger.countEnabled,
        countOperator = trigger.countOperator,
        countValue = trigger.countValue,
        extendTimer = trigger.extendTimer,
        displayType = trigger.displayType,
        barWidth = barDisplay.barWidth,
        barHeight = barDisplay.barHeight,
        barTexture = barDisplay.barTexture,
        fontFace = isBar and barDisplay.fontFace or textDisplay.fontFace,
        fontSize = isBar and barDisplay.fontSize or textDisplay.fontSize,
        fontOutline = isBar and barDisplay.fontOutline or textDisplay.fontOutline,
        iconEnabled = barDisplay.iconEnabled,
        textJustify = textDisplay.textAlign,
        useBigWigsColors = trigger.useBigWigsColors ~= false,
        barColor = trigger.barColor,
        textColor = trigger.textColor,
        barText1Format = trigger.barText1Format,
        barText1Justify = trigger.barText1Justify,
        barText1XOffset = trigger.barText1XOffset,
        barText1YOffset = trigger.barText1YOffset,
        barText2Format = trigger.barText2Format,
        barText2Justify = trigger.barText2Justify,
        barText2XOffset = trigger.barText2XOffset,
        barText2YOffset = trigger.barText2YOffset,
        textFormat = trigger.textFormat,
        showDecimals = trigger.showDecimals,
        decimalThreshold = trigger.decimalThreshold,
        customText = trigger.customText,
        actionOnShowSound = trigger.actionOnShowSound,
        actionOnHideSound = trigger.actionOnHideSound,
    }
end

---------------------------------------------------------------------------------
-- BigWigs Integration
---------------------------------------------------------------------------------

function DT:CheckBigWigs()
    return BigWigsLoader ~= nil
end

DT.IsBigWigsAvailable = DT.CheckBigWigs

function DT:RegisterBigWigsCallbacks()
    if not self:CheckBigWigs() then return false end
    for _, event in ipairs(BIGWIGS_EVENTS) do
        BigWigsLoader.RegisterMessage(self, event, "EventCallback")
    end
    return true
end

function DT:UnregisterBigWigsCallbacks()
    if not BigWigsLoader then return end
    for _, event in ipairs(BIGWIGS_EVENTS) do
        BigWigsLoader.UnregisterMessage(self, event)
    end
end

function DT:GetStatusbarPath(textureKey)
    textureKey = textureKey or self:GetBarDisplaySettings().barTexture or "KitnUI"
    return KE:GetStatusbarPath(textureKey) or "Interface\\Buttons\\WHITE8x8"
end

---------------------------------------------------------------------------------
-- Text Formatting
---------------------------------------------------------------------------------

function DT:FormatHasIcon(config)
    local format = config.textFormat or "%i %n %p"
    return format:find("%%i") ~= nil
end

function DT:GetIconPosition(config)
    local format = config.textFormat or "%i %n %p"
    local trimmed = format:gsub("^%s+", "")
    if trimmed:sub(1, 2) == "%i" then return "LEFT" end
    local trimmedEnd = format:gsub("%s+$", "")
    if trimmedEnd:sub(-2) == "%i" then return "RIGHT" end
    return "LEFT"
end

function DT:FormatTime(remaining, showDecimals, decimalThreshold)
    decimalThreshold = decimalThreshold or 3
    if remaining < 1 then return string.format("%.1f", remaining) end
    if showDecimals and remaining <= decimalThreshold then return string.format("%.1f", remaining) end
    return tostring(floor(remaining + 0.5))
end

-- File-local replacements buffer reused across all FormatText calls.
-- OnVisualUpdate fires at 30 FPS × N visible bars × 2 (text1+text2) — a fresh
-- table per call would burn ~600 tables/sec for a typical dungeon preview.
local replacementsBuf = {}

function DT:BuildReplacements(config, barData, remaining)
    local r = replacementsBuf
    wipe(r)

    if barData.icon then
        r["i"] = string.format("|T%s:0:0:0:0:64:64:4:60:4:60|t", barData.icon)
    else
        r["i"] = ""
    end

    r["n"] = barData.text or config.name or ""
    r["p"] = remaining and self:FormatTime(remaining, config.showDecimals, config.decimalThreshold) or ""
    r["s"] = barData.count and tostring(barData.count) or "0"
    r["d"] = barData.duration and tostring(floor(barData.duration + 0.5)) or ""

    if barData.customValues then
        r["c"] = tostring(barData.customValues[1] or "")
        for i, val in ipairs(barData.customValues) do
            r["c" .. i] = tostring(val or "")
        end
    else
        r["c"] = ""
    end

    return r
end

-- gsub-based replacement. The previous per-char state machine allocated a
-- new string for every character via the `result = result .. char` pattern;
-- on a 30 FPS preview that was the dominant source of GC churn (memory
-- climbing 25→60 MB before each GC sweep). One gsub call = one alloc.
local function ReplacementLookup(key)
    return replacementsBuf[key] or ""
end

function DT:FormatText(formatStr, config, barData, remaining)
    if not formatStr or formatStr == "" then return "" end

    self:BuildReplacements(config, barData, remaining)

    -- %%(%w+) catches placeholders like %i, %n, %p, %c1. To preserve the
    -- old behavior of `%%` → literal `%`, swap escaped pairs to a sentinel
    -- byte first and restore after. Most format strings have no `%%`, so
    -- the fast path is a single gsub.
    local result
    if formatStr:find("%%", 1, true) then
        result = formatStr:gsub("%%%%", "\1"):gsub("%%(%w+)", ReplacementLookup):gsub("\1", "%%")
    else
        result = formatStr:gsub("%%(%w+)", ReplacementLookup)
    end

    if result:find("\\n", 1, true) then
        result = result:gsub("\\n", "\n")
    end

    return result
end

function DT:LoadCustomTextFunc(luaCode, triggerId)
    if not luaCode or luaCode == "" then return nil end

    local funcStr = "return " .. luaCode
    local func, _ = loadstring(funcStr)
    if not func then return nil end

    local ok, result = pcall(func)
    if not ok or type(result) ~= "function" then
        return nil
    end

    return result
end

function DT:RunCustomTextFunc(customFunc, barData, remaining)
    if not customFunc then return nil end

    local ok, result = pcall(customFunc,
        barData.expirationTime or 0,
        barData.duration or 0,
        remaining or 0,
        barData.text or "",
        barData.icon or "",
        barData.count or 0
    )

    if not ok then return nil end

    if type(result) ~= "table" then
        return { result }
    end
    return result
end

function DT:GetDisplayText(config, barData, remaining)
    local format = config.textFormat or "%i %n %p"
    return self:FormatText(format, config, barData, remaining)
end

function DT:GetBarText1(config, barData, remaining)
    local format = config.barText1Format or "%n"
    return self:FormatText(format, config, barData, remaining)
end

function DT:GetBarText2(config, barData, remaining)
    local format = config.barText2Format or "%p"
    return self:FormatText(format, config, barData, remaining)
end

function DT:GetEffectiveBarDuration(config, barData)
    if config.remainingEnabled then
        return config.remainingValue or barData.duration
    end
    return barData.duration
end

---------------------------------------------------------------------------------
-- Condition Checking
---------------------------------------------------------------------------------

function DT:CompareValue(value, operator, target)
    if operator == "==" then return value == target
    elseif operator == ">" then return value > target
    elseif operator == "<" then return value < target
    elseif operator == ">=" then return value >= target
    elseif operator == "<=" then return value <= target
    end
    return false
end

function DT:CheckRemainingTime(config, remaining)
    if not config.remainingEnabled then return true end
    local target = config.remainingValue or 5
    local operator = config.remainingOperator or "<="
    return self:CompareValue(remaining, operator, target)
end

function DT:CheckMessage(trigger, text)
    if not trigger.message or trigger.message == "" then return true end
    if not text then return false end

    if issecretvalue and issecretvalue(text) then return false end
    if issecretvalue and issecretvalue(trigger.message) then return false end

    local operator = trigger.messageOperator or "find"
    if operator == "==" then
        return text == trigger.message
    elseif operator == "find" then
        return text:find(trigger.message, 1, true) ~= nil
    elseif operator == "match" then
        local ok, result = pcall(function() return text:match(trigger.message) end)
        return ok and result ~= nil
    end
    return false
end

function DT:CheckSpellId(trigger, spellId)
    if not trigger.spellId or trigger.spellId == "" then return true end
    return tostring(spellId) == tostring(trigger.spellId)
end

function DT:CheckCount(trigger, count)
    if not trigger.countEnabled then return true end
    local target = trigger.countValue or 0
    local operator = trigger.countOperator or "=="
    local countNum = tonumber(count) or 0
    return self:CompareValue(countNum, operator, target)
end

function DT:MatchesTrigger(trigger, barData)
    if not CheckLoadConditions(trigger, barData.isPreview) then return false end
    -- Pull/break timers only match triggers that explicitly target them
    if (barData.spellId == "-2" or barData.spellId == "-1") and (not trigger.spellId or trigger.spellId == "") then
        return false
    end
    if not self:CheckSpellId(trigger, barData.spellId) then return false end
    if not self:CheckMessage(trigger, barData.text) then return false end
    if not self:CheckCount(trigger, barData.count) then return false end
    return true
end

---------------------------------------------------------------------------------
-- BigWigs Colors
---------------------------------------------------------------------------------

function DT:GetBigWigsColors(addon, spellId)
    local barColor, textColor, bgColor

    if BigWigs and BigWigs.GetPlugin then
        -- silent=true: when Plugins addon isn't loaded yet (e.g. previewing
        -- in town with only Core force-loaded) GetPlugin would otherwise
        -- error("No plugin named 'Colors' found").
        local colorModule = BigWigs:GetPlugin("Colors", true)
        if colorModule and colorModule.GetColorTable then
            barColor = colorModule:GetColorTable("barColor", addon, spellId)
            textColor = colorModule:GetColorTable("barText", addon, spellId)
            bgColor = colorModule:GetColorTable("barBackground", addon, spellId)
        end
    end

    return barColor, textColor, bgColor
end

---------------------------------------------------------------------------------
-- Bar Data
---------------------------------------------------------------------------------

function DT:CreateBarData(addon, spellId, duration, text, count, icon, event)
    local barColor, textColor, bgColor = self:GetBigWigsColors(addon, spellId)

    local spellName, spellIcon
    local spellIdNum = tonumber(spellId)
    if spellIdNum and spellIdNum > 0 then
        local spellInfo = C_Spell.GetSpellInfo(spellIdNum)
        if spellInfo then
            spellName = spellInfo.name
            spellIcon = spellInfo.iconID
        end
    end

    return {
        addon = addon,
        spellId = tostring(spellId or ""),
        text = text or "",
        duration = duration or 0,
        expirationTime = GetTime() + (duration or 0),
        icon = icon or spellIcon,
        count = count or 0,
        paused = nil,
        pausedTime = nil,
        bwBarColor = barColor,
        bwTextColor = textColor,
        bwBgColor = bgColor,
        spellName = spellName,
    }
end

---------------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------------

function DT:CreateBarFrame(dungeonKey, triggerId, trigger)
    local config = self:GetTriggerConfig(trigger)
    local frameKey = dungeonKey .. "_" .. triggerId
    local frameName = "KE_DungeonTimer_" .. frameKey
    local showIcon = config.iconEnabled
    local iconSize = showIcon and config.barHeight or 0

    local group = self:GetBarGroupFrame()
    local frame = CreateFrame("Frame", frameName, group, "BackdropTemplate")
    frame:SetSize(config.barWidth, config.barHeight)
    frame:SetFrameStrata("HIGH")
    frame:Hide()

    local px = KE:GetPixelSize()
    frame.barContainer = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.barContainer:SetPoint("TOPLEFT", iconSize, 0)
    frame.barContainer:SetPoint("BOTTOMRIGHT", 0, 0)
    frame.barContainer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = px,
    })
    frame.barContainer:SetBackdropColor(0, 0, 0, 0.8)
    frame.barContainer:SetBackdropBorderColor(0, 0, 0, 1)

    frame.bar = CreateFrame("StatusBar", nil, frame.barContainer)
    frame.bar:SetPoint("TOPLEFT", px, -px)
    frame.bar:SetPoint("BOTTOMRIGHT", -px, px)
    frame.bar:SetStatusBarTexture(self:GetStatusbarPath())
    frame.bar:SetStatusBarColor(unpack(config.barColor))
    frame.bar:SetMinMaxValues(0, 1)
    frame.bar:SetValue(1)

    if showIcon then
        frame.iconFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        frame.iconFrame:SetSize(config.barHeight, config.barHeight)
        frame.iconFrame:SetPoint("LEFT", frame, "LEFT", 0, 0)
        frame.iconFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        frame.iconFrame:SetBackdropColor(0, 0, 0, 0.8)
        KE:AddBorders(frame.iconFrame)

        frame.icon = frame.iconFrame:CreateTexture(nil, "ARTWORK")
        frame.icon:SetPoint("TOPLEFT", px, -px)
        frame.icon:SetPoint("BOTTOMRIGHT", -px, px)
        KE:ApplyIconZoom(frame.icon)
    end

    local fontPath = KE:GetFontPath(config.fontFace) or KE.FONT or "Fonts\\FRIZQT__.TTF"
    local fontSize = config.fontSize or 12
    local fontOutline = config.fontOutline or "OUTLINE"
    local useSoftOutline = fontOutline == "SOFTOUTLINE"
    local actualOutline = useSoftOutline and "" or (fontOutline == "NONE" and "" or fontOutline)

    frame.text1 = frame.bar:CreateFontString(nil, "OVERLAY")
    frame.text1:SetFont(fontPath, fontSize, actualOutline)
    frame.text1:SetPoint("LEFT", frame.bar, "LEFT", config.barText1XOffset or 4, config.barText1YOffset or 0)
    frame.text1:SetPoint("RIGHT", frame.bar, "RIGHT", (config.barText1XOffset or 4) - 8, config.barText1YOffset or 0)
    frame.text1:SetJustifyH(config.barText1Justify or "LEFT")
    frame.text1:SetTextColor(unpack(config.textColor))

    if useSoftOutline then
        frame.text1.softOutline = KE:CreateSoftOutline(frame.text1, { thickness = 2 })
    end

    frame.text2 = frame.bar:CreateFontString(nil, "OVERLAY")
    frame.text2:SetFont(fontPath, fontSize, actualOutline)
    frame.text2:SetPoint("LEFT", frame.bar, "LEFT", (config.barText2XOffset or -4) + 8, config.barText2YOffset or 0)
    frame.text2:SetPoint("RIGHT", frame.bar, "RIGHT", config.barText2XOffset or -4, config.barText2YOffset or 0)
    frame.text2:SetJustifyH(config.barText2Justify or "RIGHT")
    frame.text2:SetTextColor(unpack(config.textColor))

    if useSoftOutline then
        frame.text2.softOutline = KE:CreateSoftOutline(frame.text2, { thickness = 2 })
    end

    frame.config = config
    frame.dungeonKey = dungeonKey
    frame.triggerId = triggerId
    frame.showIcon = showIcon
    frame.isBarDisplay = true

    return frame
end

function DT:CreateTextFrame(dungeonKey, triggerId, trigger)
    local config = self:GetTriggerConfig(trigger)
    local frameKey = dungeonKey .. "_" .. triggerId
    local frameName = "KE_DungeonText_" .. frameKey
    local fontSize = config.fontSize or 14

    local group = self:GetTextGroupFrame()
    local frame = CreateFrame("Frame", frameName, group)
    frame:SetSize(config.barWidth or 200, fontSize + 4)
    frame:SetFrameStrata("HIGH")
    frame:Hide()

    local fontPath = KE:GetFontPath(config.fontFace) or KE.FONT or "Fonts\\FRIZQT__.TTF"
    local justify = config.textJustify or "LEFT"
    local fontOutline = config.fontOutline or "OUTLINE"
    local useSoftOutline = fontOutline == "SOFTOUTLINE"
    local actualOutline = useSoftOutline and "" or (fontOutline == "NONE" and "" or fontOutline)

    frame.displayText = frame:CreateFontString(nil, "OVERLAY")
    frame.displayText:SetFont(fontPath, fontSize, actualOutline)
    frame.displayText:SetPoint("LEFT", frame, "LEFT", 0, 0)
    frame.displayText:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    frame.displayText:SetJustifyH(justify)
    frame.displayText:SetTextColor(unpack(config.textColor))

    if useSoftOutline then
        -- Manual TOPLEFT/BOTTOMRIGHT re-anchoring used to live here as a
        -- workaround for _ApplyOffsets' single-CENTER anchoring (which
        -- caused ghosting on left/right-justified text in a wide container).
        -- That fix now lives in _ApplyOffsets itself, applying universally
        -- to every soft outline call site (including the bar text1/text2
        -- which had the same bug).
        frame.displayText.softOutline = KE:CreateSoftOutline(frame.displayText, {
            thickness = 1,
            color = { 0, 0, 0 },
            alpha = 0.9,
            fontPath = fontPath,
            fontSize = fontSize,
        })
    end

    frame.config = config
    frame.dungeonKey = dungeonKey
    frame.triggerId = triggerId
    frame.isBarDisplay = false

    return frame
end

function DT:GetTriggerFrame(dungeonKey, triggerId, trigger)
    local frameKey = dungeonKey .. "_" .. triggerId
    local frame = self.triggerFrames[frameKey]
    local config = self:GetTriggerConfig(trigger)
    local wantBar = config.displayType == "bar"

    if frame then
        local isBar = frame.isBarDisplay
        if (wantBar and not isBar) or (not wantBar and isBar) then
            frame:Hide()
            self.triggerFrames[frameKey] = nil
            self.triggerBars[frameKey] = nil
            frame = nil
        end
    end

    if not frame then
        if wantBar then
            frame = self:CreateBarFrame(dungeonKey, triggerId, trigger)
        else
            frame = self:CreateTextFrame(dungeonKey, triggerId, trigger)
        end
        if frame then
            self.triggerFrames[frameKey] = frame
        end
    end

    return frame
end

---------------------------------------------------------------------------------
-- Bar Colors
---------------------------------------------------------------------------------

function DT:ApplyBarColors(frame, config, barData)
    if not frame.bar then return end

    local barColor = config.barColor
    local textColor = config.textColor

    if config.useBigWigsColors and barData.bwBarColor then
        barColor = barData.bwBarColor
    end
    if config.useBigWigsColors and barData.bwTextColor then
        textColor = barData.bwTextColor
    end

    if barColor and type(barColor) == "table" then
        frame.bar:SetStatusBarColor(barColor[1] or 1, barColor[2] or 1, barColor[3] or 1, barColor[4] or 1)
    end

    if textColor and type(textColor) == "table" then
        local r, g, b, a = textColor[1] or 1, textColor[2] or 1, textColor[3] or 1, textColor[4] or 1
        if frame.text1 then frame.text1:SetTextColor(r, g, b, a) end
        if frame.text2 then frame.text2:SetTextColor(r, g, b, a) end
        if frame.displayText then frame.displayText:SetTextColor(r, g, b, a) end
    end
end

---------------------------------------------------------------------------------
-- Show/Hide Trigger Display
---------------------------------------------------------------------------------

function DT:ShowTriggerDisplay(dungeonKey, triggerId, trigger, barData)
    local config = self:GetTriggerConfig(trigger)
    local frame = self:GetTriggerFrame(dungeonKey, triggerId, trigger)
    local frameKey = dungeonKey .. "_" .. triggerId

    if not frame then return end

    local now = GetTime()

    -- Overwrite-race guard: if BigWigs sends the next cast's Timer while the
    -- previous cast's extension is still visible, overwriting here would
    -- silently hide the visible extension (new bar's remaining > threshold
    -- triggers the HIDE branch below). Defer the new bar until the existing
    -- extension naturally expires via RecheckTimers.
    local existingBarData = self.triggerBars[frameKey]
    if existingBarData
       and not barData.isPreview
       and existingBarData.extendTimer and existingBarData.extendTimer > 0
       and existingBarData.expirationTime > now
       and frame:IsShown()
       and config.remainingEnabled then
        local newRemaining = barData.expirationTime - now
        if not self:CheckRemainingTime(config, newRemaining) then
            local delay = (existingBarData.expirationTime - now) + 0.05
            if DEBUG_DT then
                KE:Print(string.format("[DT] ShowTriggerDisplay DEFER new=%s delay=%.2f (existing=%s still extending)",
                    tostring(barData.text), delay, tostring(existingBarData.text)))
            end
            self:ScheduleTimer(function()
                if self.currentDungeonKey ~= dungeonKey then return end
                local d = self.db and self.db.Dungeons and self.db.Dungeons[dungeonKey]
                local t = d and d.Triggers and d.Triggers[triggerId]
                if t and t.enabled ~= false then
                    self:ShowTriggerDisplay(dungeonKey, triggerId, t, barData)
                end
            end, delay)
            return
        end
    end

    frame.config = config

    local effectiveDuration = self:GetEffectiveBarDuration(config, barData)
    barData.effectiveDuration = effectiveDuration

    if frame.icon and barData.icon then
        frame.icon:SetTexture(barData.icon)
    end

    self:ApplyBarColors(frame, config, barData)

    local remaining = barData.expirationTime - now

    if config.customText and config.customText ~= "" then
        if frame.customTextCode ~= config.customText then
            frame.customTextFunc = self:LoadCustomTextFunc(config.customText, triggerId)
            frame.customTextCode = config.customText
        end
        if frame.customTextFunc then
            barData.customValues = self:RunCustomTextFunc(frame.customTextFunc, barData, remaining)
        end
    else
        frame.customTextFunc = nil
        frame.customTextCode = nil
    end

    if frame.isBarDisplay then
        if frame.text1 then
            frame.text1:SetText(self:GetBarText1(config, barData, remaining))
        end
        if frame.text2 then
            frame.text2:SetText(self:GetBarText2(config, barData, remaining))
        end
    else
        if frame.displayText then
            frame.displayText:SetText(self:GetDisplayText(config, barData, remaining))
        end
    end

    if frame.bar then
        frame.bar:SetMinMaxValues(0, effectiveDuration)
        frame.bar:SetValue(math_min(remaining, effectiveDuration))
    end

    frame.barData = barData
    self.triggerBars[frameKey] = barData

    self:ScheduleNextExpire(barData.expirationTime)

    local shouldShowNow = true
    if config.remainingEnabled and not barData.isPreview then
        shouldShowNow = self:CheckRemainingTime(config, remaining)

        if not shouldShowNow and remaining > 0 then
            local remainingThreshold = config.remainingValue or 5
            local showTime = barData.expirationTime - remainingThreshold
            if showTime > now then
                self:ScheduleCheck(showTime)
            end
        end
    end

    if shouldShowNow then
        if not frame:IsShown() then
            if DEBUG_DT then
                KE:Print(string.format("[DT] ShowTriggerDisplay SHOW key=%s text=%s remain=%.2f",
                    tostring(frameKey), tostring(barData.text), remaining))
            end
            PlayTriggerSound(config.actionOnShowSound, barData.isPreview)
        end
        frame:Show()

        self:_RequestPositionUpdate()
        self:StartVisualUpdates()
    else
        if DEBUG_DT then
            KE:Print(string.format("[DT] ShowTriggerDisplay HIDE(threshold) key=%s text=%s remain=%.2f",
                tostring(frameKey), tostring(barData.text), remaining))
        end
        frame:Hide()
        self:_RequestPositionUpdate()
    end
end

function DT:HideTriggerDisplay(frameKey)
    if DEBUG_DT then
        local bd = self.triggerBars[frameKey]
        KE:Print(string.format("[DT] HideTriggerDisplay key=%s text=%s",
            tostring(frameKey), tostring(bd and bd.text)))
    end
    local frame = self.triggerFrames[frameKey]
    if frame then
        local isPreview = frame.barData and frame.barData.isPreview

        if frame:IsShown() and frame.config then
            PlayTriggerSound(frame.config.actionOnHideSound, isPreview)
        end

        frame:Hide()
        frame.barData = nil
    end

    self.triggerBars[frameKey] = nil
    self.positionDirty = true

    local anyRemaining = false
    for _ in pairs(self.triggerBars) do
        anyRemaining = true
        break
    end

    if anyRemaining then
        self:_RequestPositionUpdate()
        self.positionDirty = false
    else
        self:StopAllTimers()
    end
end

---------------------------------------------------------------------------------
-- Trigger Processing
---------------------------------------------------------------------------------

function DT:ProcessTimerTriggers(barData)
    if not self.db or not self.db.Dungeons then return end

    local dungeonKey = self.currentDungeonKey
    if not dungeonKey then return end

    local dungeonData = self.db.Dungeons[dungeonKey]
    if not dungeonData or not dungeonData.Enabled or not dungeonData.Triggers then return end

    for triggerId, trigger in pairs(dungeonData.Triggers) do
        if trigger.enabled ~= false and trigger.triggerType == "timer" then
            if self:MatchesTrigger(trigger, barData) then
                local adjustedBar = {}
                for k, v in pairs(barData) do adjustedBar[k] = v end
                adjustedBar.extendTimer = trigger.extendTimer or 0
                adjustedBar.expirationTime = adjustedBar.expirationTime + adjustedBar.extendTimer
                adjustedBar.duration = adjustedBar.duration + adjustedBar.extendTimer
                if DEBUG_DT and adjustedBar.extendTimer > 0 then
                    KE:Print(string.format("[DT] trigger match text=%s extend=%.1fs totalRemain=%.2f",
                        tostring(adjustedBar.text), adjustedBar.extendTimer,
                        adjustedBar.expirationTime - GetTime()))
                end
                self:ShowTriggerDisplay(dungeonKey, triggerId, trigger, adjustedBar)
            end
        end
    end
end

function DT:ProcessAnnounceTriggers(addon, spellId, text, icon)
    if not self.db or not self.db.Dungeons then return end

    local dungeonKey = self.currentDungeonKey
    if not dungeonKey then return end

    local dungeonData = self.db.Dungeons[dungeonKey]
    if not dungeonData or not dungeonData.Enabled or not dungeonData.Triggers then return end

    for triggerId, trigger in pairs(dungeonData.Triggers) do
        if trigger.enabled ~= false and trigger.triggerType == "announce" then
            local data = { spellId = tostring(spellId or ""), text = text, icon = icon }
            if self:MatchesTrigger(trigger, data) then
                local barData = {
                    text = text or "",
                    icon = icon,
                    duration = 3,
                    expirationTime = GetTime() + 3,
                    spellId = tostring(spellId or ""),
                }
                self:ShowTriggerDisplay(dungeonKey, triggerId, trigger, barData)
            end
        end
    end
end

---------------------------------------------------------------------------------
-- Bar Control
---------------------------------------------------------------------------------

function DT:StopBar(text)
    local now = GetTime()
    local matched = false
    for frameKey, barData in pairs(self.triggerBars) do
        if barData and barData.text == text then
            matched = true
            -- Only HOLD when we're inside the extension tail — i.e. the original
            -- BigWigs bar has already elapsed and only the extendTimer remains.
            -- If BW stops the bar mid-countdown (cancel, phase end, boss death),
            -- originalEnd > now and we HIDE so the tail doesn't ride through.
            local extend = barData.extendTimer or 0
            local originalEnd = barData.expirationTime - extend
            if extend > 0 and barData.expirationTime > now and originalEnd <= now then
                if DEBUG_DT then
                    KE:Print(string.format("[DT] StopBar HOLD text=%s remain=%.2f extend=%.1f",
                        tostring(text), barData.expirationTime - now, extend))
                end
            else
                if DEBUG_DT then
                    local reason
                    if extend <= 0 then
                        reason = "no-extend"
                    elseif barData.expirationTime <= now then
                        reason = "already-expired"
                    else
                        reason = "mid-countdown"
                    end
                    KE:Print(string.format("[DT] StopBar HIDE text=%s reason=%s extend=%.1f origRemain=%.2f",
                        tostring(text), reason, extend, originalEnd - now))
                end
                self:HideTriggerDisplay(frameKey)
            end
        end
    end
    if DEBUG_DT and not matched then
        KE:Print(string.format("[DT] StopBar ORPHAN (no matching bar) text=%s", tostring(text)))
    end
end

function DT:StopAllBars()
    if DEBUG_DT then KE:Print("[DT] StopAllBars (unconditional)") end
    for frameKey, _ in pairs(self.triggerBars) do
        local frame = self.triggerFrames[frameKey]
        if frame then
            frame:Hide()
            frame.barData = nil
        end
    end
    wipe(self.triggerBars)
    self:StopAllTimers()
end

-- Like StopAllBars, but honors extendTimer: bars whose original BigWigs end has
-- already passed (i.e. we're inside the extension tail) are left alone. Used
-- for BigWigs cleanup events (StopBars, OnBossDisable) so a naturally-ending
-- bar's tail rides through. If BW stops bars while countdowns are still
-- running (boss dies mid-fight), HIDE so stale warnings don't fire post-death.
function DT:StopAllBarsRespectExtend()
    local now = GetTime()
    for frameKey, barData in pairs(self.triggerBars) do
        local extend = barData and barData.extendTimer or 0
        local originalEnd = barData and (barData.expirationTime - extend)
        if barData and extend > 0 and barData.expirationTime > now and originalEnd <= now then
            if DEBUG_DT then
                KE:Print(string.format("[DT] StopAllBarsRespectExtend HOLD text=%s remain=%.2f",
                    tostring(barData.text), barData.expirationTime - now))
            end
        else
            if DEBUG_DT then
                local reason
                if not barData then
                    reason = "no-data"
                elseif extend <= 0 then
                    reason = "no-extend"
                elseif barData.expirationTime <= now then
                    reason = "already-expired"
                else
                    reason = "mid-countdown"
                end
                KE:Print(string.format("[DT] StopAllBarsRespectExtend HIDE text=%s reason=%s origRemain=%.2f",
                    tostring(barData and barData.text), reason,
                    originalEnd and (originalEnd - now) or 0))
            end
            self:HideTriggerDisplay(frameKey)
        end
    end
end

function DT:PauseBar(text)
    local now = GetTime()
    for _, barData in pairs(self.triggerBars) do
        if barData and barData.text == text and not barData.paused then
            barData.paused = true
            barData.pausedTime = now
            barData.remaining = barData.expirationTime - now
        end
    end

    if self.recheckTimer then
        self:CancelTimer(self.recheckTimer)
        self.recheckTimer = nil
    end
    self:RecheckTimers()
end

function DT:ResumeBar(text)
    local now = GetTime()
    local anyResumed = false

    for frameKey, barData in pairs(self.triggerBars) do
        if barData and barData.text == text and barData.paused then
            barData.expirationTime = now + (barData.remaining or 0)
            barData.paused = nil
            barData.pausedTime = nil
            barData.remaining = nil
            anyResumed = true

            self:ScheduleNextExpire(barData.expirationTime)

            local frame = self.triggerFrames[frameKey]
            if frame and frame.config and frame.config.remainingEnabled then
                local remainingThreshold = frame.config.remainingValue or 5
                local showTime = barData.expirationTime - remainingThreshold
                if showTime > now then
                    self:ScheduleCheck(showTime)
                end
            end
        end
    end

    if anyResumed then
        self:StartVisualUpdates()
    end
end

---------------------------------------------------------------------------------
-- Event Callback
---------------------------------------------------------------------------------

function DT:EventCallback(event, ...)
    if DEBUG_DT then KE:Print("[DT] event=" .. tostring(event)) end
    if event == "BigWigs_Timer" or event == "BigWigs_TargetTimer" or event == "BigWigs_CastTimer" then
        local addon, spellId, duration, _, text, count, icon = ...
        local barData = self:CreateBarData(addon, spellId, duration, text, count, icon, event)
        self:ProcessTimerTriggers(barData)
    elseif event == "BigWigs_StartBreak" then
        local addon, duration, _, _, _, text, icon = ...
        local barData = self:CreateBarData(addon, -1, duration, text or "Break", 0, icon, event)
        self:ProcessTimerTriggers(barData)
    elseif event == "BigWigs_StartPull" then
        local addon, duration, _, text, icon = ...
        local barData = self:CreateBarData(addon, -2, duration, text or "Pull", 0, icon or 136116, event)
        self:ProcessTimerTriggers(barData)
    elseif event == "BigWigs_Message_echo" then
        local addon, spellId, text, _, icon = ...
        self:ProcessAnnounceTriggers(addon, spellId, text, icon)
    elseif event == "BigWigs_StopBar" then
        local _, text = ...
        self:StopBar(text)
    elseif event == "BigWigs_StopBars" or event == "BigWigs_OnBossDisable" then
        self:StopAllBarsRespectExtend()
    elseif event == "BigWigs_PauseBar" then
        local _, text = ...
        self:PauseBar(text)
    elseif event == "BigWigs_ResumeBar" then
        local _, text = ...
        self:ResumeBar(text)
    end
end

---------------------------------------------------------------------------------
-- Scheduling
---------------------------------------------------------------------------------

function DT:ScheduleCheck(fireTime)
    if not fireTime or fireTime <= GetTime() then return end

    if self.scheduledScans[fireTime] then return end

    local delay = fireTime - GetTime()
    if delay > 0 then
        self.scheduledScans[fireTime] = self:ScheduleTimer("DoScheduledScan", delay, fireTime)
    end
end

function DT:DoScheduledScan(fireTime)
    self.scheduledScans[fireTime] = nil

    local now = GetTime()
    local anyBecameVisible = false

    for frameKey, barData in pairs(self.triggerBars) do
        if barData and not barData.paused then
            local frame = self.triggerFrames[frameKey]
            if frame then
                local config = frame.config
                local remaining = barData.expirationTime - now

                if config.remainingEnabled and remaining > 0 then
                    local shouldShow = self:CheckRemainingTime(config, remaining)
                    if shouldShow and not frame:IsShown() then
                        if DEBUG_DT then
                            KE:Print(string.format("[DT] DoScheduledScan SHOW key=%s text=%s remain=%.2f",
                                tostring(frameKey), tostring(barData.text), remaining))
                        end
                        PlayTriggerSound(config.actionOnShowSound, barData.isPreview)
                        frame:Show()
                        self.positionDirty = true
                        anyBecameVisible = true
                    end
                end
            end
        end
    end

    if self.positionDirty then
        self:PositionAllFrames()
        self.positionDirty = false
    end

    if anyBecameVisible then
        self:StartVisualUpdates()
    end
end

function DT:RecheckTimers()
    local now = GetTime()
    self.nextExpire = nil
    local callbacksToRun = {}

    for frameKey, barData in pairs(self.triggerBars) do
        if barData and not barData.paused then
            local expirationTime = barData.expirationTime

            if expirationTime <= now then
                if DEBUG_DT then
                    KE:Print(string.format("[DT] RecheckTimers EXPIRE text=%s extend=%.1f",
                        tostring(barData.text), barData.extendTimer or 0))
                end
                if barData.isPreview and barData.loopCallback and self.previewsAllowed then
                    table_insert(callbacksToRun, barData.loopCallback)
                end
                self:HideTriggerDisplay(frameKey)
            else
                if self.nextExpire == nil or expirationTime < self.nextExpire then
                    self.nextExpire = expirationTime
                end
            end
        end
    end

    if self.nextExpire then
        local delay = self.nextExpire - now
        if delay > 0 then
            self.recheckTimer = self:ScheduleTimer("RecheckTimers", delay)
        end
    end

    for _, callback in ipairs(callbacksToRun) do
        callback()
    end
end

function DT:ScheduleNextExpire(expirationTime)
    local now = GetTime()

    if self.nextExpire == nil or expirationTime < self.nextExpire then
        if self.recheckTimer then
            self:CancelTimer(self.recheckTimer)
        end

        self.nextExpire = expirationTime
        local delay = expirationTime - now
        if delay > 0 then
            self.recheckTimer = self:ScheduleTimer("RecheckTimers", delay)
        end
    end
end

---------------------------------------------------------------------------------
-- Visual Updates
---------------------------------------------------------------------------------

function DT:OnVisualUpdate()
    local now = GetTime()
    local anyVisible = false

    if DEBUG_DT then
        _dtTickCounter = _dtTickCounter + 1
        if _dtTickCounter >= DT_TICK_LOG_EVERY then
            _dtTickCounter = 0
            local barCount, frameCount, shownCount = 0, 0, 0
            for _ in pairs(self.triggerBars) do barCount = barCount + 1 end
            for _, f in pairs(self.triggerFrames) do
                frameCount = frameCount + 1
                if f:IsShown() then shownCount = shownCount + 1 end
            end
            KE:Print(string.format("[DT] tick: triggerBars=%d triggerFrames=%d shown=%d",
                barCount, frameCount, shownCount))
        end
    end

    for frameKey, barData in pairs(self.triggerBars) do
        if barData then
            local frame = self.triggerFrames[frameKey]
            if frame and frame:IsShown() then
                anyVisible = true
                local remaining = barData.paused
                    and (barData.expirationTime - barData.pausedTime)
                    or (barData.expirationTime - now)

                if remaining > 0 then
                    local config = frame.config

                    -- Bar fill: keep updating every frame for smooth animation.
                    if frame.bar then
                        local effectiveDuration = barData.effectiveDuration or barData.duration
                        frame.bar:SetValue(math_min(remaining, effectiveDuration))
                    end

                    -- Text updates: gate by whether the displayed time string
                    -- would actually change. SetText invalidates font-string
                    -- layout, the dominant per-tick CPU cost. Computing
                    -- FormatTime is one string.format call; comparing the
                    -- result to the last value short-circuits both FormatText
                    -- and SetText for the ~96% of frames where the rendered
                    -- value is identical (integer mode = once/sec change;
                    -- decimal mode = once/100ms change). Updates fire on the
                    -- exact frame the digit flips, no drift.
                    -- Custom-text funcs can return time-independent values,
                    -- so we can't skip them — always update when present.
                    local needTextUpdate = false
                    if frame.customTextFunc then
                        barData.customValues = self:RunCustomTextFunc(frame.customTextFunc, barData, remaining)
                        needTextUpdate = true
                    else
                        local timeStr = self:FormatTime(remaining, config.showDecimals, config.decimalThreshold)
                        if timeStr ~= barData._lastTimeStr then
                            barData._lastTimeStr = timeStr
                            needTextUpdate = true
                        end
                    end

                    if needTextUpdate then
                        if frame.isBarDisplay then
                            if frame.text1 then
                                frame.text1:SetText(self:GetBarText1(config, barData, remaining))
                            end
                            if frame.text2 then
                                frame.text2:SetText(self:GetBarText2(config, barData, remaining))
                            end
                        else
                            if frame.displayText then
                                frame.displayText:SetText(self:GetDisplayText(config, barData, remaining))
                            end
                        end
                    end
                end
            end
        end
    end

    if not anyVisible then
        self:StopVisualUpdates()
    end
end

function DT:StartVisualUpdates()
    if not self.visualTicker then
        self.visualTicker = self:ScheduleRepeatingTimer("OnVisualUpdate", VISUAL_UPDATE_INTERVAL)
    end
end

function DT:StopVisualUpdates()
    if self.visualTicker then
        self:CancelTimer(self.visualTicker)
        self.visualTicker = nil
    end
end

function DT:CancelAllScheduledScans()
    for _, handle in pairs(self.scheduledScans) do
        self:CancelTimer(handle)
    end
    wipe(self.scheduledScans)
end

function DT:StopAllTimers()
    self:StopVisualUpdates()
    self:CancelAllScheduledScans()
    if self.recheckTimer then
        self:CancelTimer(self.recheckTimer)
        self.recheckTimer = nil
    end
    self.nextExpire = nil
end

---------------------------------------------------------------------------------
-- Module Lifecycle
---------------------------------------------------------------------------------

function DT:OnEnable()
    self:UpdateDB()
    if not self.db or not self.db.Enabled then return end

    self:RegisterEvent("PLAYER_ENTERING_WORLD", "UpdateCurrentDungeon")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "UpdateCurrentDungeon")

    self:UpdateCurrentDungeon()

    if not self:RegisterBigWigsCallbacks() then
        self:RegisterEvent("ADDON_LOADED", function(_, addonName)
            if addonName == "BigWigs" or addonName == "BigWigs_Core" then
                self:RegisterBigWigsCallbacks()
            end
        end)
    end
end

function DT:OnDisable()
    self:UnregisterBigWigsCallbacks()
    self:StopAllBars()
    self:StopAllTimers()
    self:UnregisterAllEvents()
    self.currentDungeonKey = nil
    for _, frame in pairs(self.triggerFrames) do
        frame:Hide()
    end
end

---------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------

function DT:ApplySettings()
    self:UpdateDB()
    if self.db and self.db.Enabled then
        if not self:IsEnabled() then
            KitnEssentials:EnableModule("DungeonTimers")
        else
            self:RegisterBigWigsCallbacks()
        end
    else
        if self:IsEnabled() then
            KitnEssentials:DisableModule("DungeonTimers")
        end
    end
end

function DT:Refresh()
    self:StopAllTimers()

    for _, frame in pairs(self.triggerFrames) do
        frame:Hide()
    end
    wipe(self.triggerFrames)
    wipe(self.triggerBars)

    if self.barGroupFrame then
        self.barGroupFrame:Hide()
        self.barGroupFrame = nil
    end
    if self.textGroupFrame then
        self.textGroupFrame:Hide()
        self.textGroupFrame = nil
    end
end

-- In-place visual update: re-applies size/font/texture/colors/text-format to one frame
-- without destroying it. Returns true if applied, false if a structural rebuild is needed
-- (displayType change, icon toggle, soft-outline mode toggle).
function DT:UpdateFrameVisualsInPlace(frame, config)
    if not frame or not config then return false end

    local wantBar = config.displayType == "bar"
    if wantBar ~= (frame.isBarDisplay == true) then return false end
    if wantBar and (frame.showIcon == true) ~= (config.iconEnabled == true) then return false end

    local fontPath = KE:GetFontPath(config.fontFace) or KE.FONT or "Fonts\\FRIZQT__.TTF"
    local fontSize = config.fontSize or 12
    local fontOutline = config.fontOutline or "OUTLINE"
    local useSoftOutline = fontOutline == "SOFTOUTLINE"
    local actualOutline = useSoftOutline and "" or (fontOutline == "NONE" and "" or fontOutline)

    -- Soft-outline toggle requires shadow recreation; let caller rebuild.
    local hadSoftOutline = (frame.text1 and frame.text1.softOutline ~= nil)
        or (frame.displayText and frame.displayText.softOutline ~= nil)
    if hadSoftOutline ~= useSoftOutline then return false end

    if frame.isBarDisplay then
        frame:SetSize(config.barWidth or 200, config.barHeight or 20)
        if frame.iconFrame then
            frame.iconFrame:SetSize(config.barHeight or 20, config.barHeight or 20)
        end
        if frame.bar then
            frame.bar:SetStatusBarTexture(self:GetStatusbarPath(config.barTexture))
        end
        if frame.text1 then
            frame.text1:SetFont(fontPath, fontSize, actualOutline)
            frame.text1:ClearAllPoints()
            frame.text1:SetPoint("LEFT", frame.bar, "LEFT", config.barText1XOffset or 4, config.barText1YOffset or 0)
            frame.text1:SetPoint("RIGHT", frame.bar, "RIGHT", (config.barText1XOffset or 4) - 8, config.barText1YOffset or 0)
            frame.text1:SetJustifyH(config.barText1Justify or "LEFT")
        end
        if frame.text2 then
            frame.text2:SetFont(fontPath, fontSize, actualOutline)
            frame.text2:ClearAllPoints()
            frame.text2:SetPoint("LEFT", frame.bar, "LEFT", (config.barText2XOffset or -4) + 8, config.barText2YOffset or 0)
            frame.text2:SetPoint("RIGHT", frame.bar, "RIGHT", config.barText2XOffset or -4, config.barText2YOffset or 0)
            frame.text2:SetJustifyH(config.barText2Justify or "RIGHT")
        end
    else
        frame:SetSize(config.barWidth or 200, fontSize + 4)
        if frame.displayText then
            frame.displayText:SetFont(fontPath, fontSize, actualOutline)
            frame.displayText:SetJustifyH(config.textJustify or "LEFT")
        end
    end

    local barData = frame.barData or { isPreview = true }
    if frame.bar then
        self:ApplyBarColors(frame, config, barData)
    elseif frame.displayText then
        -- ApplyBarColors early-returns on text frames; apply text color directly
        local textColor = config.textColor
        if config.useBigWigsColors and barData.bwTextColor then
            textColor = barData.bwTextColor
        end
        if textColor and type(textColor) == "table" then
            frame.displayText:SetTextColor(textColor[1] or 1, textColor[2] or 1, textColor[3] or 1, textColor[4] or 1)
        end
    end

    frame.config = config
    return true
end

-- Update visual settings on existing frames without a full rebuild.
-- With (dungeonKey, triggerId): targets one frame (used by per-dungeon GUI panel).
-- With no args: iterates all frames (used by DT_Bars / DT_Texts global pages).
-- Falls back to delete+rebuild for any frame that can't be updated in place.
function DT:UpdateFrameVisuals(dungeonKey, triggerId)
    if not self.db or not self.db.Dungeons then return end

    local function getTrigger(dKey, tId)
        -- Real triggers from saved DB
        local d = self.db.Dungeons[dKey]
        local trigger = d and d.Triggers and d.Triggers[tId]
        if trigger then return trigger end
        -- Settings preview synthetic triggers (DT_Bars / DT_Texts pages)
        if self.settingsPreviewTriggers and self.settingsPreviewTriggers[dKey] then
            return self.settingsPreviewTriggers[dKey][tId]
        end
        return nil
    end

    local function rebuildOne(frameKey, dKey, tId, frame)
        local trigger = getTrigger(dKey, tId)
        if not trigger then return end
        local wasShown = frame:IsShown()
        local barData = self.triggerBars[frameKey]
        frame:Hide()
        self.triggerFrames[frameKey] = nil
        if wasShown and barData then
            self:ShowTriggerDisplay(dKey, tId, trigger, barData)
        end
    end

    if dungeonKey and triggerId then
        local frameKey = dungeonKey .. "_" .. triggerId
        local frame = self.triggerFrames[frameKey]
        local trigger = getTrigger(dungeonKey, triggerId)
        if not trigger then return end

        -- Trigger toggled disabled: hide + drop the preview frame so the
        -- user sees the change immediately. PreviewDungeon and combat
        -- ProcessTimerTriggers / ProcessAnnounceTriggers all gate on
        -- trigger.enabled, so the frame won't reappear until re-enabled.
        if trigger.enabled == false then
            if frame then
                frame:Hide()
                self.triggerBars[frameKey] = nil
                self.triggerFrames[frameKey] = nil
            end
            self:PositionAllFrames()
            return
        end

        -- Trigger toggled re-enabled but a prior disable hid+dropped the
        -- frame. Force a PreviewTrigger so the user sees it reappear
        -- immediately instead of waiting for the next preview-loop tick
        -- (which can be many seconds away on long-duration bars).
        if not frame then
            if self.previewsAllowed and self.PreviewTrigger then
                self:PreviewTrigger(dungeonKey, triggerId)
            end
            self:PositionAllFrames()
            return
        end

        local config = self:GetTriggerConfig(trigger)
        if not self:UpdateFrameVisualsInPlace(frame, config) then
            rebuildOne(frameKey, dungeonKey, triggerId, frame)
        end
    else
        local rebuildList = {}
        for frameKey, frame in pairs(self.triggerFrames) do
            local dKey = frame.dungeonKey
            local tId = frame.triggerId
            local trigger = dKey and tId and getTrigger(dKey, tId)
            if trigger then
                if trigger.enabled == false then
                    -- Disabled trigger left a stale frame behind (probably
                    -- from before the toggle gating in this same function).
                    -- Drop it now so the batch update doesn't keep showing it.
                    frame:Hide()
                    self.triggerBars[frameKey] = nil
                    self.triggerFrames[frameKey] = nil
                else
                    local config = self:GetTriggerConfig(trigger)
                    if not self:UpdateFrameVisualsInPlace(frame, config) then
                        table_insert(rebuildList, { fk = frameKey, dKey = dKey, tId = tId, frame = frame })
                    end
                end
            end
        end
        for _, info in ipairs(rebuildList) do
            rebuildOne(info.fk, info.dKey, info.tId, info.frame)
        end
    end

    self:PositionAllFrames()
end

function DT:DeleteTrigger(dungeonKey, triggerId)
    if not self.db or not self.db.Dungeons then return end
    local dungeonData = self.db.Dungeons[dungeonKey]
    if not dungeonData or not dungeonData.Triggers then return end

    local frameKey = dungeonKey .. "_" .. triggerId
    self:HideTriggerDisplay(frameKey)
    if self.triggerFrames[frameKey] then
        self.triggerFrames[frameKey]:Hide()
        self.triggerFrames[frameKey] = nil
    end

    dungeonData.Triggers[triggerId] = nil
end

function DT:DuplicateTrigger(dungeonKey, triggerId)
    if not self.db or not self.db.Dungeons then return nil end
    local dungeonData = self.db.Dungeons[dungeonKey]
    if not dungeonData or not dungeonData.Triggers then return nil end

    local source = dungeonData.Triggers[triggerId]
    if not source then return nil end

    local newId = self:CreateTrigger(dungeonKey)
    if not newId then return nil end

    local target = dungeonData.Triggers[newId]
    for k, v in pairs(source) do
        if k ~= "id" then
            if type(v) == "table" then
                target[k] = {}
                for k2, v2 in pairs(v) do target[k][k2] = v2 end
            else
                target[k] = v
            end
        end
    end
    target.name = (source.name or "Timer") .. " (Copy)"

    return newId
end

function DT:GetSortedTriggerIds(dungeonKey)
    if not self.db or not self.db.Dungeons then return {} end
    local dungeonData = self.db.Dungeons[dungeonKey]
    if not dungeonData or not dungeonData.Triggers then return {} end

    local ids = {}
    for id in pairs(dungeonData.Triggers) do
        table.insert(ids, id)
    end
    table.sort(ids, function(a, b) return tonumber(a) < tonumber(b) end)
    return ids
end

function DT:MoveTriggerUp(dungeonKey, triggerId)
    if not self.db or not self.db.Dungeons then return false end
    local dungeonData = self.db.Dungeons[dungeonKey]
    if not dungeonData or not dungeonData.Triggers then return false end

    local sortedIds = self:GetSortedTriggerIds(dungeonKey)
    local currentIndex = nil
    for i, id in ipairs(sortedIds) do
        if id == triggerId then currentIndex = i; break end
    end

    if not currentIndex or currentIndex <= 1 then return false end

    local prevId = sortedIds[currentIndex - 1]
    local currentData = dungeonData.Triggers[triggerId]
    local prevData = dungeonData.Triggers[prevId]

    dungeonData.Triggers[triggerId] = prevData
    dungeonData.Triggers[prevId] = currentData
    dungeonData.Triggers[triggerId].id = triggerId
    dungeonData.Triggers[prevId].id = prevId

    local frameKey1 = dungeonKey .. "_" .. triggerId
    local frameKey2 = dungeonKey .. "_" .. prevId
    if self.triggerFrames[frameKey1] then self.triggerFrames[frameKey1]:Hide(); self.triggerFrames[frameKey1] = nil end
    if self.triggerFrames[frameKey2] then self.triggerFrames[frameKey2]:Hide(); self.triggerFrames[frameKey2] = nil end

    return prevId
end

function DT:MoveTriggerDown(dungeonKey, triggerId)
    if not self.db or not self.db.Dungeons then return false end
    local dungeonData = self.db.Dungeons[dungeonKey]
    if not dungeonData or not dungeonData.Triggers then return false end

    local sortedIds = self:GetSortedTriggerIds(dungeonKey)
    local currentIndex = nil
    for i, id in ipairs(sortedIds) do
        if id == triggerId then currentIndex = i; break end
    end

    if not currentIndex or currentIndex >= #sortedIds then return false end

    local nextId = sortedIds[currentIndex + 1]
    local currentData = dungeonData.Triggers[triggerId]
    local nextData = dungeonData.Triggers[nextId]

    dungeonData.Triggers[triggerId] = nextData
    dungeonData.Triggers[nextId] = currentData
    dungeonData.Triggers[triggerId].id = triggerId
    dungeonData.Triggers[nextId].id = nextId

    local frameKey1 = dungeonKey .. "_" .. triggerId
    local frameKey2 = dungeonKey .. "_" .. nextId
    if self.triggerFrames[frameKey1] then self.triggerFrames[frameKey1]:Hide(); self.triggerFrames[frameKey1] = nil end
    if self.triggerFrames[frameKey2] then self.triggerFrames[frameKey2]:Hide(); self.triggerFrames[frameKey2] = nil end

    return nextId
end

---------------------------------------------------------------------------------
-- Preview System
---------------------------------------------------------------------------------

function DT:PreviewTrigger(dungeonKey, triggerId, loopCallback)
    if not self.previewsAllowed then return end

    self:UpdateDB()
    if not self.db or not self.db.Dungeons then return end

    local dungeonData = self.db.Dungeons[dungeonKey]
    if not dungeonData or not dungeonData.Triggers then return end

    local trigger = dungeonData.Triggers[triggerId]
    if not trigger then return end

    local config = self:GetTriggerConfig(trigger)

    local frameKey = dungeonKey .. "_" .. triggerId
    if self.triggerFrames[frameKey] then
        self.triggerFrames[frameKey]:Hide()
        self.triggerFrames[frameKey] = nil
    end

    local icon = 136116
    local spellName
    local spellIdNum = tonumber(config.spellId)
    if spellIdNum and spellIdNum > 0 then
        local spellInfo = C_Spell.GetSpellInfo(spellIdNum)
        if spellInfo then
            if spellInfo.iconID then icon = spellInfo.iconID end
            spellName = spellInfo.name
        end
    end

    local bwBarColor, bwTextColor, bwBgColor
    if config.useBigWigsColors and spellIdNum then
        bwBarColor, bwTextColor, bwBgColor = self:GetBigWigsColors(nil, spellIdNum)
    end

    local duration = config.remainingEnabled and (config.remainingValue or 5) or 20

    local selfRef = self
    local individualLoopCallback = function()
        if selfRef.previewsAllowed then
            selfRef:PreviewTrigger(dungeonKey, triggerId)
        end
    end

    local barData = {
        text = config.name or "Preview",
        icon = icon,
        duration = duration,
        effectiveDuration = duration,
        expirationTime = GetTime() + duration,
        spellId = config.spellId or "",
        count = 0,
        isPreview = true,
        loopCallback = individualLoopCallback,
        bwBarColor = bwBarColor,
        bwTextColor = bwTextColor,
        bwBgColor = bwBgColor,
        spellName = spellName,
    }

    self:ShowTriggerDisplay(dungeonKey, triggerId, trigger, barData)
end

function DT:PreviewDungeon(dungeonKey, loopCallback)
    if not self.previewsAllowed then return end

    self:UpdateDB()
    if not self.db or not self.db.Dungeons then return end

    local dungeonData = self.db.Dungeons[dungeonKey]
    if not dungeonData or not dungeonData.Triggers then return end

    for frameKey, frame in pairs(self.triggerFrames) do
        if frame.dungeonKey == dungeonKey then
            frame:Hide()
            self.triggerBars[frameKey] = nil
        end
    end

    for triggerId, trigger in pairs(dungeonData.Triggers) do
        if trigger.enabled ~= false then
            self:PreviewTrigger(dungeonKey, triggerId)
        end
    end

    self:PositionAllFrames()
end

function DT:HideAll()
    if DEBUG_DT then
        local frameCount, shownCount, barCount = 0, 0, 0
        for _, f in pairs(self.triggerFrames) do
            frameCount = frameCount + 1
            if f:IsShown() then shownCount = shownCount + 1 end
        end
        for _ in pairs(self.triggerBars) do barCount = barCount + 1 end
        KE:Print(string.format("[DT] HideAll start: frames=%d shown=%d bars=%d",
            frameCount, shownCount, barCount))
    end
    for _, frame in pairs(self.triggerFrames) do
        frame:Hide()
        frame.barData = nil
    end
    wipe(self.triggerBars)
    self:StopAllTimers()
end

function DT:HideAllPreviews()
    local hasRemainingFrames = false
    local previewCount, otherCount = 0, 0
    for frameKey, barData in pairs(self.triggerBars) do
        if barData and barData.isPreview then
            previewCount = previewCount + 1
            local frame = self.triggerFrames[frameKey]
            if frame then
                frame:Hide()
                frame.barData = nil
            end
            self.triggerBars[frameKey] = nil
        elseif barData then
            otherCount = otherCount + 1
            hasRemainingFrames = true
        end
    end
    if DEBUG_DT then
        KE:Print(string.format("[DT] HideAllPreviews: previews=%d other=%d hasRemaining=%s",
            previewCount, otherCount, tostring(hasRemainingFrames)))
    end

    if hasRemainingFrames then
        self:PositionAllFrames()
    else
        self:StopAllTimers()
    end
end

function DT:EnablePreviews()
    self.previewsAllowed = true
end

function DT:DisablePreviews()
    self.previewsAllowed = false
    self:HideAllPreviews()
end

---------------------------------------------------------------------------------
-- Settings Previews (DT_Bars / DT_Texts pages)
---------------------------------------------------------------------------------

local SETTINGS_BAR_KEY = "__settings_bar__"
local SETTINGS_TEXT_KEY = "__settings_text__"
local SETTINGS_PREVIEW_LABELS = { "Sample Timer A", "Sample Timer B", "Sample Timer C" }
local SETTINGS_PREVIEW_COUNT = 3

local function buildSettingsPreviewTrigger(displayType, idx)
    return {
        id = idx,
        name = SETTINGS_PREVIEW_LABELS[idx] or ("Sample " .. idx),
        displayType = displayType,
        triggerType = "Timer",
        enabled = true,
        useBigWigsColors = false,
        barColor = { 1, 0.5, 0, 1 },
        textColor = { 1, 1, 1, 1 },
        barText1Format = "%n",
        barText1Justify = "LEFT",
        barText1XOffset = 4,
        barText1YOffset = 0,
        barText2Format = "%p",
        barText2Justify = "RIGHT",
        barText2XOffset = -4,
        barText2YOffset = 0,
        textFormat = "%n %p",
        showDecimals = true,
        decimalThreshold = 5,
    }
end

function DT:_runSettingsPreviewIteration(dungeonKey, triggerId, displayType)
    if not self.previewsAllowed then return end
    self.settingsPreviewTriggers = self.settingsPreviewTriggers or {}
    self.settingsPreviewTriggers[dungeonKey] = self.settingsPreviewTriggers[dungeonKey]
        or { [1] = buildSettingsPreviewTrigger(displayType, 1),
             [2] = buildSettingsPreviewTrigger(displayType, 2),
             [3] = buildSettingsPreviewTrigger(displayType, 3) }

    local trigger = self.settingsPreviewTriggers[dungeonKey][triggerId]
    if not trigger then return end
    trigger.displayType = displayType

    local duration = 12 + (triggerId - 1) * 4
    local selfRef = self
    local barData = {
        text = trigger.name,
        icon = 136116,
        duration = duration,
        effectiveDuration = duration,
        expirationTime = GetTime() + duration,
        spellId = "",
        count = 0,
        isPreview = true,
        spellName = trigger.name,
    }
    barData.loopCallback = function()
        if selfRef.previewsAllowed and selfRef.settingsPreviewTriggers
           and selfRef.settingsPreviewTriggers[dungeonKey] then
            selfRef:_runSettingsPreviewIteration(dungeonKey, triggerId, displayType)
        end
    end
    self:ShowTriggerDisplay(dungeonKey, triggerId, trigger, barData)
end

function DT:_startSettingsPreviews(dungeonKey, displayType)
    self.previewsAllowed = true

    -- Clear stale frames before restarting (covers refresh-after-settings-change path)
    for frameKey, frame in pairs(self.triggerFrames) do
        if frame.dungeonKey == dungeonKey then
            frame:Hide()
            self.triggerFrames[frameKey] = nil
            self.triggerBars[frameKey] = nil
        end
    end
    self.settingsPreviewTriggers = self.settingsPreviewTriggers or {}
    self.settingsPreviewTriggers[dungeonKey] = nil

    for i = 1, SETTINGS_PREVIEW_COUNT do
        self:_runSettingsPreviewIteration(dungeonKey, i, displayType)
    end
    self:PositionAllFrames()
end

function DT:_clearSettingsPreviews(dungeonKey)
    if self.settingsPreviewTriggers then
        self.settingsPreviewTriggers[dungeonKey] = nil
    end
    for frameKey, frame in pairs(self.triggerFrames) do
        if frame.dungeonKey == dungeonKey then
            frame:Hide()
            self.triggerFrames[frameKey] = nil
            self.triggerBars[frameKey] = nil
        end
    end
    self:PositionAllFrames()
end

function DT:ShowSettingsBarPreviews()  self:_startSettingsPreviews(SETTINGS_BAR_KEY, "bar")  end
function DT:HideSettingsBarPreviews()  self:_clearSettingsPreviews(SETTINGS_BAR_KEY)         end

-- Refresh applies visual changes in place to existing previews so the bar
-- countdown stays smooth across setting changes. Falls back to a full restart
-- only if previews aren't running yet (e.g. first time the page is opened).
function DT:RefreshSettingsBarPreviews()
    if self.settingsPreviewTriggers and self.settingsPreviewTriggers[SETTINGS_BAR_KEY] then
        self:UpdateFrameVisuals()
    else
        self:_startSettingsPreviews(SETTINGS_BAR_KEY, "bar")
    end
end

function DT:ShowSettingsTextPreviews() self:_startSettingsPreviews(SETTINGS_TEXT_KEY, "text") end
function DT:HideSettingsTextPreviews() self:_clearSettingsPreviews(SETTINGS_TEXT_KEY)         end

function DT:RefreshSettingsTextPreviews()
    if self.settingsPreviewTriggers and self.settingsPreviewTriggers[SETTINGS_TEXT_KEY] then
        self:UpdateFrameVisuals()
    else
        self:_startSettingsPreviews(SETTINGS_TEXT_KEY, "text")
    end
end

function DT:RefreshPositions()
    self:UpdateBarGroupPosition()
    self:UpdateTextGroupPosition()
    self:PositionAllFrames()
end

---------------------------------------------------------------------------------
-- BigWigs Spell Discovery
---------------------------------------------------------------------------------

function DT:GetBigWigsModulesForInstance(instanceId)
    local modules = {}
    if not BigWigs or not BigWigs.IterateBossModules then return modules end

    if BigWigsLoader and BigWigsLoader.GetZoneMenus then
        local menus = BigWigsLoader:GetZoneMenus()
        local moduleList = menus and menus[instanceId]
        if type(moduleList) == "table" then return moduleList end
    end

    for _, module in BigWigs:IterateBossModules() do
        if module.instanceId == instanceId then
            table_insert(modules, module)
        end
    end

    return modules
end

function DT:LoadBigWigsZone(instanceId)
    if not instanceId then return false end
    if not BigWigsLoader then return false end

    -- Force-load Core so the spell browser works in town/open world.
    -- BigWigsLoader:LoadZone() doesn't auto-load Core; boss-module addons
    -- short-circuit if `BigWigs` global is missing. C_AddOns.LoadAddOn is
    -- synchronous and BigWigs_Core/Core.lua sets the global at file-end,
    -- so on success BigWigs is populated when this returns.
    if not BigWigs then
        if not (C_AddOns and C_AddOns.LoadAddOn) then return false end
        local loaded = C_AddOns.LoadAddOn("BigWigs_Core")
        if not loaded or not BigWigs then return false end
    end

    if BigWigsLoader.LoadZone then
        BigWigsLoader:LoadZone(instanceId)
        return true
    end

    return false
end

function DT:GetSpellsForDungeon(dungeonKey, forceRefresh, isRetry)
    self:UpdateDB()
    if not self.db or not self.db.Dungeons then return {} end

    local dungeonData = self.db.Dungeons[dungeonKey]
    if not dungeonData or not dungeonData.instanceId then return {} end

    if forceRefresh then self.spellCache[dungeonKey] = nil end
    if self.spellCache[dungeonKey] then
        return self.spellCache[dungeonKey]
    end

    if self:LoadBigWigsZone(dungeonData.instanceId) then
        if not isRetry and not self.spellCache[dungeonKey] then
            C_Timer.After(0.5, function() self:GetSpellsForDungeon(dungeonKey, true, true) end)
        end
    end

    local spells = {}
    local seenSpells = {}
    local modules = self:GetBigWigsModulesForInstance(dungeonData.instanceId)
    local bossOrder = {}
    local bossNumberMap = {}
    for _, module in ipairs(modules) do
        if module.GetOptions or module.toggleOptions then
            local sortKey = module.journalId or module.engageId or 999999
            table_insert(bossOrder, {
                module = module,
                sortKey = sortKey,
                name = module.displayName or module.moduleName,
            })
        end
    end
    table.sort(bossOrder, function(a, b) return a.sortKey < b.sortKey end)

    for i, boss in ipairs(bossOrder) do
        bossNumberMap[boss.name] = i
    end

    for _, module in ipairs(modules) do
        if module.GetOptions or module.toggleOptions then
            local options = module.toggleOptions or (module.GetOptions and module:GetOptions())
            if options then
                local bossName = module.displayName or module.moduleName
                local bossNum = bossNumberMap[bossName] or 0
                local sortKey = module.journalId or module.engageId or 999999

                for _, option in ipairs(options) do
                    local spellId
                    if type(option) == "number" then
                        spellId = option
                    elseif type(option) == "table" and type(option[1]) == "number" then
                        spellId = option[1]
                    end

                    if spellId and spellId > 0 and not seenSpells[spellId] then
                        seenSpells[spellId] = true
                        local spellInfo = C_Spell.GetSpellInfo(spellId)
                        if spellInfo then
                            table_insert(spells, {
                                spellId = spellId,
                                name = spellInfo.name,
                                icon = spellInfo.iconID,
                                bossName = bossName,
                                bossNum = bossNum,
                                sortKey = sortKey,
                            })
                        end
                    end
                end
            end
        end
    end

    table.sort(spells, function(a, b)
        if a.sortKey ~= b.sortKey then
            return a.sortKey < b.sortKey
        end
        return a.name < b.name
    end)

    if #spells > 0 then
        self.spellCache[dungeonKey] = spells
    end

    return spells
end

function DT:ClearSpellCache(dungeonKey)
    if dungeonKey then
        self.spellCache[dungeonKey] = nil
    else
        wipe(self.spellCache)
    end
end

---------------------------------------------------------------------------------
-- Import / Export
---------------------------------------------------------------------------------
local TRIGGER_EXPORT_PREFIX = "!KET1!"

local DUNGEON_DISPLAY_NAMES = {
    MagistersTerrace   = "Magisters' Terrace",
    MaisaraCaverns     = "Maisara Caverns",
    NexusPointXenas    = "Nexus-Point Xenas",
    WindrunnerSpire    = "Windrunner Spire",
    AlgetharAcademy    = "Algeth'ar Academy",
    PitOfSaron         = "Pit of Saron",
    SeatOfTriumvirate  = "Seat of the Triumvirate",
    Skyreach           = "Skyreach",
}

local function GetSerializer()
    return LibStub("AceSerializer-3.0")
end

local function GetDeflate()
    return LibStub("LibDeflate")
end

-- Compact a keyed Triggers table into a dense array sorted by id.
-- DT:DeleteTrigger leaves Triggers[id] = nil holes, which break ipairs/#.
-- Returns the dense array and its count.
local function CompactTriggers(triggers)
    local dense = {}
    if type(triggers) ~= "table" then return dense, 0 end

    local ids = {}
    for id in pairs(triggers) do table_insert(ids, id) end
    table.sort(ids, function(a, b) return tonumber(a) < tonumber(b) end)

    for _, id in ipairs(ids) do
        table_insert(dense, CopyTable(triggers[id]))
    end
    return dense, #dense
end

-- Next safe trigger id for a potentially sparse Triggers table.
-- Matches DT:CreateTrigger's max-id + 1 scheme so we never overwrite holes.
local function NextTriggerId(triggers)
    local maxId = 0
    if type(triggers) == "table" then
        for id in pairs(triggers) do
            local numId = tonumber(id)
            if numId and numId > maxId then maxId = numId end
        end
    end
    return maxId + 1
end

--- Export triggers for a single dungeon or all dungeons
---@param dungeonKey string|nil Specific dungeon key, or nil for all
---@return string|nil encoded
---@return string|nil error
function DT:ExportTriggers(dungeonKey)
    local db = self.db
    if not db or not db.Dungeons then return nil, "No trigger data" end

    local Serializer = GetSerializer()
    local Deflate = GetDeflate()
    if not Serializer or not Deflate then return nil, "Missing libraries" end

    local exportData
    if dungeonKey then
        local dungeon = db.Dungeons[dungeonKey]
        if not dungeon or not dungeon.Triggers then
            return nil, "No triggers for this dungeon"
        end
        local dense, dCount = CompactTriggers(dungeon.Triggers)
        if dCount == 0 then return nil, "No triggers for this dungeon" end
        exportData = {
            v = 1,
            t = "dungeon",
            k = dungeonKey,
            d = dense,
        }
    else
        -- All dungeons
        local allTriggers = {}
        local count = 0
        for key, dungeon in pairs(db.Dungeons) do
            if dungeon.Triggers then
                local dense, dCount = CompactTriggers(dungeon.Triggers)
                if dCount > 0 then
                    allTriggers[key] = dense
                    count = count + dCount
                end
            end
        end
        if count == 0 then return nil, "No triggers to export" end
        exportData = {
            v = 1,
            t = "all",
            d = allTriggers,
        }
    end

    local serialized = Serializer:Serialize(exportData)
    if not serialized then return nil, "Serialization failed" end

    local compressed = Deflate:CompressDeflate(serialized, { level = 9 })
    if not compressed then return nil, "Compression failed" end

    local encoded = Deflate:EncodeForPrint(compressed)
    if not encoded then return nil, "Encoding failed" end

    return TRIGGER_EXPORT_PREFIX .. encoded
end

--- Import triggers from an encoded string
---@param importString string The export string
---@return boolean success
---@return string|nil message
function DT:ImportTriggers(importString)
    if not importString or importString == "" then return false, "Import string is empty" end
    if importString:sub(1, #TRIGGER_EXPORT_PREFIX) ~= TRIGGER_EXPORT_PREFIX then
        return false, "Invalid format — this doesn't look like a KE trigger export"
    end

    local db = self.db
    if not db or not db.Dungeons then return false, "Module not initialized" end

    local Serializer = GetSerializer()
    local Deflate = GetDeflate()
    if not Serializer or not Deflate then return false, "Missing libraries" end

    local encoded = importString:sub(#TRIGGER_EXPORT_PREFIX + 1)

    local compressed = Deflate:DecodeForPrint(encoded)
    if not compressed then return false, "Failed to decode string" end

    local serialized = Deflate:DecompressDeflate(compressed)
    if not serialized then return false, "Failed to decompress" end

    local ok, exportData = Serializer:Deserialize(serialized)
    if not ok or type(exportData) ~= "table" then return false, "Failed to deserialize" end

    if not exportData.v or not exportData.t or not exportData.d then
        return false, "Invalid export data structure"
    end

    local defaults = db.TriggerDefaults or {}
    local imported = 0

    if exportData.t == "dungeon" then
        local key = exportData.k
        if not key or not db.Dungeons[key] then
            return false, "Unknown dungeon: " .. tostring(key)
        end
        if type(exportData.d) ~= "table" then return false, "Invalid trigger data" end

        local triggers = db.Dungeons[key].Triggers
        for _, trigger in ipairs(exportData.d) do
            if type(trigger) == "table" then
                local merged = CopyTable(defaults)
                for k, v in pairs(trigger) do merged[k] = v end
                local newId = NextTriggerId(triggers)
                merged.id = newId
                triggers[newId] = merged
                imported = imported + 1
            end
        end

        if imported == 0 then return false, "No timers were imported" end
        local name = DUNGEON_DISPLAY_NAMES[key] or key
        return true, imported .. " timer(s) imported to " .. name

    elseif exportData.t == "all" then
        if type(exportData.d) ~= "table" then return false, "Invalid trigger data" end

        local dungeonCount = 0
        for key, triggerList in pairs(exportData.d) do
            if db.Dungeons[key] and type(triggerList) == "table" then
                local triggers = db.Dungeons[key].Triggers
                local added = false
                for _, trigger in ipairs(triggerList) do
                    if type(trigger) == "table" then
                        local merged = CopyTable(defaults)
                        for k, v in pairs(trigger) do merged[k] = v end
                        local newId = NextTriggerId(triggers)
                        merged.id = newId
                        triggers[newId] = merged
                        imported = imported + 1
                        added = true
                    end
                end
                if added then dungeonCount = dungeonCount + 1 end
            end
        end

        if imported == 0 then return false, "No timers were imported" end
        return true, imported .. " timer(s) imported across " .. dungeonCount .. " dungeon(s)"
    else
        return false, "Unknown export type: " .. tostring(exportData.t)
    end
end

---------------------------------------------------------------------------------
-- KES Presets: Canned triggers loaded from DungeonTimerPresets.lua
---------------------------------------------------------------------------------

-- Dedup match: same spellId + name is considered an existing trigger.
-- Uses pairs because the target (DB) Triggers table can be sparse.
local function TriggerExists(existingTriggers, newTrigger)
    if type(existingTriggers) ~= "table" or type(newTrigger) ~= "table" then return false end
    local newSpellId = tostring(newTrigger.spellId or "")
    local newName = newTrigger.name or ""
    for _, existing in pairs(existingTriggers) do
        if tostring(existing.spellId or "") == newSpellId and (existing.name or "") == newName then
            return true
        end
    end
    return false
end

-- Merge preset triggers for a single dungeon (internal helper)
-- Returns (importedCount, skippedCount)
local function MergePresetDungeon(self, dungeonKey, presetTriggers)
    local db = self.db
    if not db or not db.Dungeons[dungeonKey] then return 0, 0 end
    if type(presetTriggers) ~= "table" then return 0, 0 end

    local defaults = db.TriggerDefaults or {}
    local target = db.Dungeons[dungeonKey].Triggers
    local imported, skipped = 0, 0

    for _, trigger in ipairs(presetTriggers) do
        if type(trigger) == "table" and trigger.name and trigger.triggerType then
            if TriggerExists(target, trigger) then
                skipped = skipped + 1
            else
                local merged = CopyTable(defaults)
                for k, v in pairs(trigger) do merged[k] = v end
                local newId = NextTriggerId(target)
                merged.id = newId
                target[newId] = merged
                imported = imported + 1
            end
        end
    end

    return imported, skipped
end

--- Import KES preset triggers for a dungeon (or all dungeons if nil)
---@param dungeonKey string|nil Specific dungeon key, or nil for all
---@return boolean success
---@return string|nil message
function DT:ImportKESPresets(dungeonKey)
    if not KE.DungeonTimerPresets then return false, "Presets not loaded" end
    local db = self.db
    if not db or not db.Dungeons then return false, "Module not initialized" end

    if dungeonKey then
        local preset = KE.DungeonTimerPresets[dungeonKey]
        if type(preset) ~= "table" or not preset.Triggers or #preset.Triggers == 0 then
            return false, "No presets available for this dungeon"
        end
        local imported, skipped = MergePresetDungeon(self, dungeonKey, preset.Triggers)
        if imported == 0 and skipped == 0 then return false, "No presets imported" end
        local name = DUNGEON_DISPLAY_NAMES[dungeonKey] or dungeonKey
        local msg = imported .. " timer(s) loaded for " .. name
        if skipped > 0 then msg = msg .. " (" .. skipped .. " duplicate(s) skipped)" end
        if imported == 0 then return false, msg end
        return true, msg
    end

    -- All dungeons
    local totalImported, totalSkipped, dungeonCount = 0, 0, 0
    for key, preset in pairs(KE.DungeonTimerPresets) do
        if key ~= "_version" and type(preset) == "table" and preset.Triggers and db.Dungeons[key] then
            local imported, skipped = MergePresetDungeon(self, key, preset.Triggers)
            totalImported = totalImported + imported
            totalSkipped = totalSkipped + skipped
            if imported > 0 then dungeonCount = dungeonCount + 1 end
        end
    end

    if totalImported == 0 and totalSkipped == 0 then
        return false, "No presets available"
    end
    local msg = totalImported .. " timer(s) loaded from " .. dungeonCount .. " dungeon(s)"
    if totalSkipped > 0 then msg = msg .. " (" .. totalSkipped .. " duplicate(s) skipped)" end
    if totalImported == 0 then return false, msg end
    return true, msg
end

-- Serialize a Lua value to a code string (for GeneratePresetsCode)
local function SerializeValue(val, indent)
    indent = indent or ""
    local nextIndent = indent .. "    "
    local t = type(val)
    if t == "string" then
        local escaped = val:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("|", "\\124")
        return "\"" .. escaped .. "\""
    elseif t == "number" or t == "boolean" then
        return tostring(val)
    elseif t == "table" then
        local parts = {}
        local isArray, maxIndex = true, 0
        for k in pairs(val) do
            if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then isArray = false; break end
            if k > maxIndex then maxIndex = k end
        end
        if isArray and maxIndex > 0 then
            for i = 1, maxIndex do
                local v = val[i]
                if v ~= nil then table_insert(parts, nextIndent .. SerializeValue(v, nextIndent)) end
            end
        else
            local keys = {}
            for k in pairs(val) do table_insert(keys, k) end
            table.sort(keys, function(a, b)
                if type(a) == type(b) then return tostring(a) < tostring(b) end
                return type(a) < type(b)
            end)
            for _, k in ipairs(keys) do
                local v = val[k]
                local keyStr
                if type(k) == "number" then
                    keyStr = "[" .. k .. "]"
                elseif type(k) == "string" and k:match("^[%a_][%w_]*$") then
                    keyStr = k
                else
                    keyStr = "[" .. SerializeValue(k, nextIndent) .. "]"
                end
                table_insert(parts, nextIndent .. keyStr .. " = " .. SerializeValue(v, nextIndent))
            end
        end
        if #parts == 0 then return "{}" end
        return "{\n" .. table.concat(parts, ",\n") .. ",\n" .. indent .. "}"
    end
    return "nil"
end

--- Generate Lua code representing the current triggers, for pasting into DungeonTimerPresets.lua.
--- Usage: /run KitnEssentials:GetModule("DungeonTimers"):GeneratePresetsCode()
function DT:GeneratePresetsCode()
    self:UpdateDB()
    local db = self.db
    if not db or not db.Dungeons then
        KE:Print("Database not initialized")
        return
    end

    local out = {}
    table_insert(out, "-- Generated by DT:GeneratePresetsCode()")
    table_insert(out, "-- Replace the KE.DungeonTimerPresets block in Dungeons/DungeonTimerPresets.lua with this:")
    table_insert(out, "")
    table_insert(out, "KE.DungeonTimerPresets = {")
    table_insert(out, "    _version = 1,")
    table_insert(out, "")

    -- Sort by display name for stable output
    local sortedKeys = {}
    for key in pairs(DUNGEON_DISPLAY_NAMES) do table_insert(sortedKeys, key) end
    table.sort(sortedKeys, function(a, b)
        return (DUNGEON_DISPLAY_NAMES[a] or a) < (DUNGEON_DISPLAY_NAMES[b] or b)
    end)

    for _, dungeonKey in ipairs(sortedKeys) do
        local name = DUNGEON_DISPLAY_NAMES[dungeonKey] or dungeonKey
        local dungeonData = db.Dungeons[dungeonKey]
        local triggers = dungeonData and dungeonData.Triggers

        -- Triggers can be a sparse/keyed table (DeleteTrigger leaves holes),
        -- so collect + sort the keys via pairs rather than relying on ipairs/#.
        local triggerIds = {}
        if triggers then
            for id in pairs(triggers) do table_insert(triggerIds, id) end
            table.sort(triggerIds, function(a, b) return tonumber(a) < tonumber(b) end)
        end

        table_insert(out, "    -- " .. name)
        if #triggerIds > 0 then
            table_insert(out, "    " .. dungeonKey .. " = {")
            table_insert(out, "        Triggers = {")
            for _, id in ipairs(triggerIds) do
                table_insert(out, "            " .. SerializeValue(triggers[id], "            ") .. ",")
            end
            table_insert(out, "        },")
            table_insert(out, "    },")
        else
            table_insert(out, "    " .. dungeonKey .. " = { Triggers = {} },")
        end
        table_insert(out, "")
    end

    table_insert(out, "}")
    local code = table.concat(out, "\n")

    KE:CreatePrompt(
        "Generated Presets Code",
        code,
        true,
        "Copy (Ctrl+C) and paste into Dungeons/DungeonTimerPresets.lua",
        false
    )
    KE:Print("Presets code generated — copy from the dialog.")
end

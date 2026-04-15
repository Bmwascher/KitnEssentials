-- ╔══════════════════════════════════════════════════════════╗
-- ║  DungeonTimers.lua                                      ║
-- ║  Module: Dungeon Timers                                 ║
-- ║  Purpose: BigWigs-integrated dungeon timer system with  ║
-- ║           per-dungeon triggers, bar/text groups, and    ║
-- ║           role-based load conditions.                   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class DungeonTimers: AceModule, AceEvent-3.0, AceTimer-3.0
local DT = KitnEssentials:NewModule("DungeonTimers", "AceEvent-3.0", "AceTimer-3.0")

local CreateFrame = CreateFrame
local GetTime = GetTime
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

    group:SetParent(parent)
    group:ClearAllPoints()
    group:SetPoint(pos.AnchorFrom, parent, pos.AnchorTo, pos.XOffset, pos.YOffset)
    group:SetFrameStrata(settings.Strata or "HIGH")
end

function DT:UpdateTextGroupPosition()
    local group = self:GetTextGroupFrame()
    local settings = self:GetGroupSettings("text")
    local pos = settings.Position
    local parent = KE:ResolveAnchorFrame(settings.anchorFrameType, settings.ParentFrame)

    group:SetParent(parent)
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
    local pos = settings.Position
    local spacing = settings.Spacing
    local growUp = settings.GrowthDirection == "UP"
    local barDisplay = self:GetBarDisplaySettings()
    local barHeight = barDisplay.barHeight or 20
    local barWidth = barDisplay.barWidth or 200

    local frames = {}
    for _, frame in pairs(self.triggerFrames) do
        if frame and frame:IsShown() and frame.isBarDisplay == true then
            table_insert(frames, frame)
        end
    end

    table.sort(frames, function(a, b)
        if a.dungeonKey ~= b.dungeonKey then
            return (a.dungeonKey or "") < (b.dungeonKey or "")
        end
        return (tonumber(a.triggerId) or 0) < (tonumber(b.triggerId) or 0)
    end)

    local anchorFrom = pos.AnchorFrom
    local anchorTo = pos.AnchorTo
    local baseX = pos.XOffset
    local baseY = pos.YOffset

    for i, frame in ipairs(frames) do
        frame:SetSize(barWidth, barHeight)
        frame:ClearAllPoints()

        local offset = (i - 1) * (barHeight + spacing)
        local yPos
        if growUp then
            yPos = baseY + offset
        else
            yPos = baseY - offset
        end

        frame:SetPoint(anchorFrom, UIParent, anchorTo, baseX, yPos)
    end
end

function DT:PositionAllTexts()
    self:UpdateTextGroupPosition()

    local settings = self:GetGroupSettings("text")
    local pos = settings.Position
    local spacing = settings.Spacing
    local growUp = settings.GrowthDirection == "UP"
    local textDisplay = self:GetTextDisplaySettings()
    local textFontSize = textDisplay.fontSize or 14
    local textHeight = textFontSize + 4
    local textWidth = 400

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

    local anchorFrom = pos.AnchorFrom
    local anchorTo = pos.AnchorTo
    local baseX = pos.XOffset
    local baseY = pos.YOffset

    for i, frame in ipairs(frames) do
        frame:SetSize(textWidth, textHeight)
        frame:ClearAllPoints()

        local offset = (i - 1) * (textHeight + spacing)
        local yPos
        if growUp then
            yPos = baseY + offset
        else
            yPos = baseY - offset
        end

        frame:SetPoint(anchorFrom, UIParent, anchorTo, baseX, yPos)
    end
end

function DT:PositionAllFrames()
    self:PositionAllBars()
    self:PositionAllTexts()
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

function DT:BuildReplacements(config, barData, remaining)
    local replacements = {}

    if barData.icon then
        replacements["i"] = string.format("|T%s:0:0:0:0:64:64:4:60:4:60|t", barData.icon)
    else
        replacements["i"] = ""
    end

    replacements["n"] = barData.text or config.name or ""
    replacements["p"] = remaining and self:FormatTime(remaining, config.showDecimals, config.decimalThreshold) or ""
    replacements["s"] = barData.count and tostring(barData.count) or "0"
    replacements["d"] = barData.duration and tostring(floor(barData.duration + 0.5)) or ""

    if barData.customValues then
        replacements["c"] = tostring(barData.customValues[1] or "")
        for i, val in ipairs(barData.customValues) do
            replacements["c" .. i] = tostring(val or "")
        end
    else
        replacements["c"] = ""
    end

    return replacements
end

-- State machine parser for format strings
local STATE_NORMAL = 0
local STATE_PERCENT = 1
local STATE_PLACEHOLDER = 2

function DT:FormatText(formatStr, config, barData, remaining)
    if not formatStr or formatStr == "" then return "" end

    local replacements = self:BuildReplacements(config, barData, remaining)

    local result = ""
    local state = STATE_NORMAL
    local placeholderStart = nil
    local pos = 1
    local len = #formatStr

    while pos <= len do
        local char = formatStr:sub(pos, pos)
        local byte = string.byte(char)

        if state == STATE_NORMAL then
            if char == "%" then
                state = STATE_PERCENT
                placeholderStart = pos
            else
                result = result .. char
            end
        elseif state == STATE_PERCENT then
            if char == "%" then
                result = result .. "%"
                state = STATE_NORMAL
            elseif (byte >= 97 and byte <= 122) or (byte >= 48 and byte <= 57) then
                state = STATE_PLACEHOLDER
            else
                result = result .. "%"
                result = result .. char
                state = STATE_NORMAL
            end
        elseif state == STATE_PLACEHOLDER then
            if (byte >= 97 and byte <= 122) or (byte >= 48 and byte <= 57) then
                -- Continue reading placeholder
            else
                local placeholder = formatStr:sub(placeholderStart + 1, pos - 1)
                local replacement = replacements[placeholder] or ""
                result = result .. replacement
                result = result .. char
                state = STATE_NORMAL
            end
        end
        pos = pos + 1
    end

    if state == STATE_PLACEHOLDER then
        local placeholder = formatStr:sub(placeholderStart + 1)
        local replacement = replacements[placeholder] or ""
        result = result .. replacement
    elseif state == STATE_PERCENT then
        result = result .. "%"
    end

    result = result:gsub("\\n", "\n")

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
        local colorModule = BigWigs:GetPlugin("Colors")
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

    frame.barContainer = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.barContainer:SetPoint("TOPLEFT", iconSize, 0)
    frame.barContainer:SetPoint("BOTTOMRIGHT", 0, 0)
    frame.barContainer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame.barContainer:SetBackdropColor(0, 0, 0, 0.8)
    frame.barContainer:SetBackdropBorderColor(0, 0, 0, 1)

    frame.bar = CreateFrame("StatusBar", nil, frame.barContainer)
    frame.bar:SetPoint("TOPLEFT", 1, -1)
    frame.bar:SetPoint("BOTTOMRIGHT", -1, 1)
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
        frame.icon:SetPoint("TOPLEFT", 1, -1)
        frame.icon:SetPoint("BOTTOMRIGHT", -1, 1)
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
        local outline = KE:CreateSoftOutline(frame.displayText, {
            thickness = 1,
            color = { 0, 0, 0 },
            alpha = 0.9,
            fontPath = fontPath,
            fontSize = fontSize,
        })
        if outline and outline.shadows then
            local SHADOW_OFFSETS = {
                { 0,  1 },  { 1,  1 },  { 1,  0 },  { 1,  -1 },
                { 0,  -1 }, { -1, -1 }, { -1, 0 },  { -1, 1 },
            }
            local thickness = outline.thickness or 1
            for i, shadow in ipairs(outline.shadows) do
                local offset = SHADOW_OFFSETS[i]
                local xOff = offset[1] * thickness
                local yOff = offset[2] * thickness
                shadow:ClearAllPoints()
                shadow:SetPoint("TOPLEFT", frame.displayText, "TOPLEFT", xOff, yOff)
                shadow:SetPoint("BOTTOMRIGHT", frame.displayText, "BOTTOMRIGHT", xOff, yOff)
                shadow:SetJustifyH(justify)
            end
            outline:SetShown(true)
        end
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

    frame.config = config

    local now = GetTime()
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
            PlayTriggerSound(config.actionOnShowSound, barData.isPreview)
        end
        frame:Show()

        self:PositionAllFrames()
        self:StartVisualUpdates()
    else
        frame:Hide()
        self:PositionAllFrames()
    end
end

function DT:HideTriggerDisplay(frameKey)
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
        self:PositionAllFrames()
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
    for frameKey, barData in pairs(self.triggerBars) do
        if barData and barData.text == text then
            -- If this trigger has extendTimer, don't stop while extended time remains
            if barData.extendTimer and barData.extendTimer > 0 and barData.expirationTime > now then
                -- BigWigs bar ended but our extended timer is still active — let it run
            else
                self:HideTriggerDisplay(frameKey)
            end
        end
    end
end

function DT:StopAllBars()
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
        self:StopAllBars()
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

                    if frame.bar then
                        local effectiveDuration = barData.effectiveDuration or barData.duration
                        frame.bar:SetValue(math_min(remaining, effectiveDuration))
                    end

                    if frame.customTextFunc then
                        barData.customValues = self:RunCustomTextFunc(frame.customTextFunc, barData, remaining)
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
    for _, frame in pairs(self.triggerFrames) do
        frame:Hide()
        frame.barData = nil
    end
    wipe(self.triggerBars)
    self:StopAllTimers()
end

function DT:HideAllPreviews()
    local hasRemainingFrames = false
    for frameKey, barData in pairs(self.triggerBars) do
        if barData and barData.isPreview then
            local frame = self.triggerFrames[frameKey]
            if frame then
                frame:Hide()
                frame.barData = nil
            end
            self.triggerBars[frameKey] = nil
        elseif barData then
            hasRemainingFrames = true
        end
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

    for _, module in BigWigs:IterateBossModules() do
        if module.instanceId == instanceId then
            table_insert(modules, module)
        end
    end

    return modules
end

function DT:LoadBigWigsZone(instanceId)
    if not instanceId then return false end

    -- BigWigs core must be fully loaded, not just the Loader
    if BigWigs and BigWigsLoader and BigWigsLoader.LoadZone then
        BigWigsLoader:LoadZone(instanceId)
        return true
    end

    return false
end

function DT:GetSpellsForDungeon(dungeonKey, forceRefresh)
    self:UpdateDB()
    if not self.db or not self.db.Dungeons then return {} end

    local dungeonData = self.db.Dungeons[dungeonKey]
    if not dungeonData or not dungeonData.instanceId then return {} end

    if not forceRefresh and self.spellCache[dungeonKey] then
        return self.spellCache[dungeonKey]
    end

    self:LoadBigWigsZone(dungeonData.instanceId)

    local spells = {}
    local seenSpells = {}
    local modules = self:GetBigWigsModulesForInstance(dungeonData.instanceId)
    local bossOrder = {}
    local bossNumberMap = {}
    for _, module in ipairs(modules) do
        if module.GetOptions then
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
        if module.GetOptions then
            local options = module:GetOptions()
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

--- Export triggers for a single dungeon or all dungeons
---@param dungeonKey string|nil Specific dungeon key, or nil for all
---@return string|nil encoded, string|nil error
function DT:ExportTriggers(dungeonKey)
    local db = self.db
    if not db or not db.Dungeons then return nil, "No trigger data" end

    local Serializer = GetSerializer()
    local Deflate = GetDeflate()
    if not Serializer or not Deflate then return nil, "Missing libraries" end

    local exportData
    if dungeonKey then
        local dungeon = db.Dungeons[dungeonKey]
        if not dungeon or not dungeon.Triggers or #dungeon.Triggers == 0 then
            return nil, "No triggers for this dungeon"
        end
        exportData = {
            v = 1,
            t = "dungeon",
            k = dungeonKey,
            d = CopyTable(dungeon.Triggers),
        }
    else
        -- All dungeons
        local allTriggers = {}
        local count = 0
        for key, dungeon in pairs(db.Dungeons) do
            if dungeon.Triggers and #dungeon.Triggers > 0 then
                allTriggers[key] = CopyTable(dungeon.Triggers)
                count = count + #dungeon.Triggers
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
---@return boolean success, string|nil message
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
                table_insert(triggers, merged)
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
                        table_insert(triggers, merged)
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

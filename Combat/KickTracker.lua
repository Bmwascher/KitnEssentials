-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class KickTracker: AceModule, AceEvent-3.0, AceTimer-3.0
local KT = KitnEssentials:NewModule("KickTracker", "AceEvent-3.0", "AceTimer-3.0")

-- Localized globals
local GetTime = GetTime
local CreateFrame = CreateFrame
local UnitGUID = UnitGUID
local UnitName = UnitName
local UnitClass = UnitClass
local UnitExists = UnitExists
local IsInInstance = IsInInstance
local IsInGroup = IsInGroup
local InCombatLockdown = InCombatLockdown
local CanInspect = CanInspect
local NotifyInspect = NotifyInspect
local GetSpecialization = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo
local GetInspectSpecialization = GetInspectSpecialization
local C_Timer = C_Timer
local C_ClassColor = C_ClassColor
local C_Spell = C_Spell
local string_find = string.find
local string_format = string.format
local math_floor = math.floor
local math_abs = math.abs
local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local table_insert = table.insert
local table_sort = table.sort

-- =============================================================
-- Interrupt Database (from ExwindDB, verified values)
-- Only core kick abilities. Specs without a kick have id = 0.
-- =============================================================
local INTERRUPT_DATA = {
    -- Death Knight: Mind Freeze 12s
    [250]  = { id = 47528,  cd = 12, role = "TANK" },
    [251]  = { id = 47528,  cd = 12, role = "DAMAGER" },
    [252]  = { id = 47528,  cd = 12, role = "DAMAGER" },
    -- Demon Hunter: Disrupt 15s
    [577]  = { id = 183752, cd = 15, role = "DAMAGER" },
    [581]  = { id = 183752, cd = 15, role = "TANK" },
    [1480] = { id = 183752, cd = 15, role = "DAMAGER" },
    -- Druid: Skull Bash 15s (Feral/Guardian only)
    [102]  = { id = 0, cd = 0 },
    [103]  = { id = 106839, cd = 15, role = "DAMAGER" },
    [104]  = { id = 106839, cd = 15, role = "TANK" },
    [105]  = { id = 0, cd = 0 },
    -- Evoker: Quell 20/18s (Devastation/Augmentation only)
    [1467] = { id = 351338, cd = 20, role = "DAMAGER" },
    [1468] = { id = 0, cd = 0 },
    [1473] = { id = 351338, cd = 18, role = "DAMAGER" },
    -- Hunter: Counter Shot 24s / Muzzle 15s
    [253]  = { id = 147362, cd = 24, role = "DAMAGER" },
    [254]  = { id = 147362, cd = 24, role = "DAMAGER" },
    [255]  = { id = 187707, cd = 15, role = "DAMAGER" },
    -- Mage: Counterspell 20s
    [62]   = { id = 2139,   cd = 20, role = "DAMAGER" },
    [63]   = { id = 2139,   cd = 20, role = "DAMAGER" },
    [64]   = { id = 2139,   cd = 20, role = "DAMAGER" },
    -- Monk: Spear Hand Strike 15s (Brewmaster/Windwalker only)
    [268]  = { id = 116705, cd = 15, role = "TANK" },
    [269]  = { id = 116705, cd = 15, role = "DAMAGER" },
    [270]  = { id = 0, cd = 0 },
    -- Paladin: Rebuke 15s (Protection/Retribution only)
    [65]   = { id = 0, cd = 0 },
    [66]   = { id = 96231,  cd = 15, role = "TANK" },
    [70]   = { id = 96231,  cd = 15, role = "DAMAGER" },
    -- Priest: Silence 30s (Shadow only)
    [256]  = { id = 0, cd = 0 },
    [257]  = { id = 0, cd = 0 },
    [258]  = { id = 15487,  cd = 30, role = "DAMAGER" },
    -- Rogue: Kick 15s
    [259]  = { id = 1766,   cd = 15, role = "DAMAGER" },
    [260]  = { id = 1766,   cd = 15, role = "DAMAGER" },
    [261]  = { id = 1766,   cd = 15, role = "DAMAGER" },
    -- Shaman: Wind Shear 12s (Ele/Enh), 30s (Resto)
    [262]  = { id = 57994,  cd = 12, role = "DAMAGER" },
    [263]  = { id = 57994,  cd = 12, role = "DAMAGER" },
    [264]  = { id = 57994,  cd = 30, role = "HEALER" },
    -- Warlock: Spell Lock 24/30/24s
    [265]  = { id = 19647,  cd = 24, role = "DAMAGER" },
    [266]  = { id = 19647,  cd = 30, role = "DAMAGER" },
    [267]  = { id = 19647,  cd = 24, role = "DAMAGER" },
    -- Warrior: Pummel 15s
    [71]   = { id = 6552,   cd = 15, role = "DAMAGER" },
    [72]   = { id = 6552,   cd = 15, role = "DAMAGER" },
    [73]   = { id = 6552,   cd = 15, role = "TANK" },
}

-- Reverse lookup: spellID -> true (for fast filtering in UNIT_SPELLCAST_SUCCEEDED)
local INTERRUPT_SPELL_IDS = {}
for _, data in pairs(INTERRUPT_DATA) do
    if data.id and data.id > 0 then
        INTERRUPT_SPELL_IDS[data.id] = true
    end
end

-- =============================================================
-- Constants
-- =============================================================
local TIME_WINDOW = 0.050
local PROCESS_DELAY = 0.030
local CACHE_TTL = 300
local INSPECT_THROTTLE = 1.2

-- =============================================================
-- Module State
-- =============================================================
KT.containerFrame = nil
KT.isPreview = false
KT.editModeRegistered = false

-- Party tracking
KT.partyMembers = {}     -- [guid] = { unit, name, classToken, specID, interruptData, kickStart, kickDuration }
KT.specCache = {}         -- [guid] = { specID, classToken, timestamp }
KT.inspectQueue = {}      -- array of { guid, unit }
KT.inspectPending = nil   -- guid currently being inspected

-- Event correlation
KT.pendingInterrupts = {} -- [nameplateUnit] = { time }
KT.pendingAuras = {}      -- [nameplateUnit] = { time }
KT.pendingCasts = {}      -- [partyUnit] = { time, spellID }
KT.processScheduled = false

-- Bar display
KT.barPool = {}           -- array of reusable bar frames
KT.activeBars = {}        -- [guid] = barFrame
KT.sortedBars = {}        -- ordered array for layout

-- Environment
KT.isActive = false
KT.combatEventsRegistered = false

-- =============================================================
-- DB Access
-- =============================================================
function KT:UpdateDB()
    self.db = KE.db.profile.KickTracker
end

-- =============================================================
-- Party Spec Tracking
-- =============================================================
local function GetPlayerSpecID()
    local specIndex = GetSpecialization()
    if specIndex then
        return GetSpecializationInfo(specIndex)
    end
    return 0
end

function KT:GetInterruptDataForSpec(specID)
    if not specID or specID == 0 then return nil end
    local data = INTERRUPT_DATA[specID]
    if data and data.id and data.id > 0 then
        return data
    end
    return nil
end

function KT:RefreshPartyRoster()
    if not self.db or not self.db.Enabled then return end

    local currentGuids = {}
    local units = { "player" }
    for i = 1, 4 do
        units[i + 1] = "party" .. i
    end

    for _, unit in ipairs(units) do
        if UnitExists(unit) then
            local guid = UnitGUID(unit)
            if guid then
                currentGuids[guid] = unit
                local name = UnitName(unit)
                local _, classToken = UnitClass(unit)

                if not self.partyMembers[guid] then
                    self.partyMembers[guid] = {}
                end
                local member = self.partyMembers[guid]
                member.unit = unit
                member.name = name
                member.classToken = classToken

                -- Get spec
                local specID = 0
                if unit == "player" then
                    specID = GetPlayerSpecID() or 0
                else
                    -- Check cache first
                    local cached = self.specCache[guid]
                    if cached and (GetTime() - cached.timestamp) < CACHE_TTL then
                        specID = cached.specID
                    else
                        -- Queue for inspect
                        specID = 0
                        self:QueueInspect(guid, unit)
                    end
                end

                if specID > 0 then
                    member.specID = specID
                    member.interruptData = self:GetInterruptDataForSpec(specID)
                end
            end
        end
    end

    -- Remove members who left
    for guid in pairs(self.partyMembers) do
        if not currentGuids[guid] then
            self.partyMembers[guid] = nil
            self.specCache[guid] = nil
            if self.activeBars[guid] then
                self:ReleaseBar(guid)
            end
        end
    end

    self:UpdateBars()
    self:LayoutBars()
end

function KT:QueueInspect(guid, unit)
    -- Don't double-queue
    for _, entry in ipairs(self.inspectQueue) do
        if entry.guid == guid then return end
    end
    table_insert(self.inspectQueue, { guid = guid, unit = unit })
    self:ProcessInspectQueue()
end

function KT:ProcessInspectQueue()
    if self.inspectPending then return end
    if #self.inspectQueue == 0 then return end
    if InCombatLockdown() then return end

    local entry = table.remove(self.inspectQueue, 1)
    if not entry then return end

    local unit = entry.unit
    if not UnitExists(unit) then
        -- Try next
        self:ProcessInspectQueue()
        return
    end

    -- Check if we already have cached data
    local specID = GetInspectSpecialization(unit)
    if specID and specID > 0 then
        self:ApplySpecData(entry.guid, unit, specID)
        self:ProcessInspectQueue()
        return
    end

    if CanInspect(unit) then
        self.inspectPending = entry.guid
        NotifyInspect(unit)
        -- Timeout: clear pending after 3s if no response
        self:ScheduleTimer(function()
            if self.inspectPending == entry.guid then
                self.inspectPending = nil
                self:ProcessInspectQueue()
            end
        end, 3)
    else
        self:ProcessInspectQueue()
    end
end

function KT:OnInspectReady(_, guid)
    if self.inspectPending and self.inspectPending == guid then
        self.inspectPending = nil
    end

    -- Find the unit for this guid
    for _, member in pairs(self.partyMembers) do
        if UnitGUID(member.unit) == guid then
            local specID = GetInspectSpecialization(member.unit)
            if specID and specID > 0 then
                self:ApplySpecData(guid, member.unit, specID)
            end
            break
        end
    end

    -- Continue queue
    self:ScheduleTimer(function()
        self:ProcessInspectQueue()
    end, INSPECT_THROTTLE)
end

function KT:ApplySpecData(guid, unit, specID)
    local _, classToken = UnitClass(unit)
    self.specCache[guid] = {
        specID = specID,
        classToken = classToken,
        timestamp = GetTime(),
    }

    local member = self.partyMembers[guid]
    if member then
        member.specID = specID
        member.classToken = classToken
        member.interruptData = self:GetInterruptDataForSpec(specID)
        self:UpdateBars()
        self:LayoutBars()
    end
end

function KT:OnPlayerSpecChanged()
    local specID = GetPlayerSpecID()
    if not specID or specID == 0 then return end

    local guid = UnitGUID("player")
    if not guid then return end

    self:ApplySpecData(guid, "player", specID)
end

-- =============================================================
-- Three-Event Correlator
-- =============================================================
function KT:ScheduleProcessing()
    if self.processScheduled then return end
    self.processScheduled = true
    C_Timer.After(PROCESS_DELAY, function()
        self:ProcessPendingEvents()
    end)
end

function KT:ProcessPendingEvents()
    self.processScheduled = false

    -- Clean stale aura records (>40ms old = persistent debuff, not CC)
    local currentTime = GetTime()
    for unit, data in pairs(self.pendingAuras) do
        if currentTime - data.time > 0.04 then
            self.pendingAuras[unit] = nil
        end
    end

    -- Count interrupts
    local interruptCount = 0
    local targetUnit = nil
    for unit in pairs(self.pendingInterrupts) do
        interruptCount = interruptCount + 1
        targetUnit = unit
    end

    if interruptCount == 0 then
        wipe(self.pendingInterrupts)
        wipe(self.pendingCasts)
        wipe(self.pendingAuras)
        return
    end

    -- Multiple nameplates interrupted = AoE CC, ignore all
    if interruptCount > 1 then
        wipe(self.pendingInterrupts)
        wipe(self.pendingCasts)
        wipe(self.pendingAuras)
        return
    end

    local interruptTime = self.pendingInterrupts[targetUnit].time

    -- Check if UNIT_AURA fired within ±30ms = CC, not a kick
    if self.pendingAuras[targetUnit] then
        local auraTime = self.pendingAuras[targetUnit].time
        if math_abs(interruptTime - auraTime) <= 0.030 then
            wipe(self.pendingInterrupts)
            wipe(self.pendingCasts)
            wipe(self.pendingAuras)
            return
        end
    end

    -- Find matching UNIT_SPELLCAST_SUCCEEDED within ±50ms
    local bestMatch = nil
    local bestTimeDiff = math.huge
    for unit, data in pairs(self.pendingCasts) do
        local timeDiff = math_abs(interruptTime - data.time)
        if timeDiff <= TIME_WINDOW and timeDiff < bestTimeDiff then
            bestMatch = unit
            bestTimeDiff = timeDiff
        end
    end

    if bestMatch then
        local guid = UnitGUID(bestMatch)
        if guid then
            self:ConfirmKick(guid)
        end
    end

    wipe(self.pendingInterrupts)
    wipe(self.pendingCasts)
    wipe(self.pendingAuras)
end

function KT:ConfirmKick(guid)
    local member = self.partyMembers[guid]
    if not member or not member.interruptData then return end

    member.kickStart = GetTime()
    member.kickDuration = member.interruptData.cd

    -- Immediately update bar visuals so the transition from ready→cooling is instant
    local bar = self.activeBars[guid]
    if bar then
        local isDark = self.db.ColorMode == "dark"
        -- Dark mode: starts full (class color drains to empty)
        -- Class mode: starts empty (fills up with class color as CD recovers)
        bar.statusBar:SetValue(isDark and 1 or 0)
        self:ApplyBarColor(bar, member, true)
        bar.iconTex:SetDesaturated(true)
        -- Dark mode: white name while cooling
        if isDark and bar.nameText then
            bar.nameText:SetTextColor(1, 1, 1, 1)
        end
        if self.db.ShowTimer and bar.timerText then
            bar.timerText:SetText(string_format("%d", member.interruptData.cd))
        end
    end

    self:LayoutBars()
end

-- =============================================================
-- Event Handlers (Combat)
-- =============================================================
function KT:OnSpellcastInterrupted(_, unit)
    if not self.db.Enabled or self.isPreview or not self.isActive then return end
    if not unit or not string_find(unit, "nameplate") then return end
    self.pendingInterrupts[unit] = { time = GetTime() }
    self:ScheduleProcessing()
end

function KT:OnChannelStop(_, unit, _, interruptedBy)
    if not self.db.Enabled or self.isPreview or not self.isActive then return end
    if not unit or not string_find(unit, "nameplate") then return end
    if interruptedBy == nil then return end  -- channel ended naturally, not kicked
    self.pendingInterrupts[unit] = { time = GetTime() }
    self:ScheduleProcessing()
end

function KT:OnUnitAura(_, unit)
    if not self.db.Enabled or self.isPreview or not self.isActive then return end
    if not unit or not string_find(unit, "nameplate") then return end
    -- Record aura timestamp only — no ScheduleProcessing (matches ExWind)
    -- Processing is triggered by INTERRUPTED or SUCCEEDED events
    self.pendingAuras[unit] = { time = GetTime() }
end

function KT:OnSpellcastSucceeded(_, unit, _, spellID)
    if not self.db.Enabled or self.isPreview or not self.isActive then return end
    if not unit then return end

    -- Player self-kick: spellID is NOT secret for own casts, so direct check works
    if unit == "player" then
        if not INTERRUPT_SPELL_IDS[spellID] then return end
        local guid = UnitGUID("player")
        if guid then
            self:ConfirmKick(guid)
        end
        return
    end

    -- Party member casts: spellID is SECRET in 12.0.5, cannot be inspected.
    -- Instead of filtering by spell ID, record ALL party casts with timestamps.
    -- The time-window correlation with UNIT_SPELLCAST_INTERRUPTED determines
    -- whether it was actually a kick. This matches ExWind's approach.
    if string_find(unit, "^party%d") then
        self.pendingCasts[unit] = { time = GetTime() }
        self:ScheduleProcessing()
        return
    end

    -- KE FIX: Warlock pet interrupts (ExWind does NOT handle this)
    -- Spell Lock (19647) fires on partypetN, not the warlock player.
    -- Pet spellID is also secret, so we can't filter — just record the cast.
    if string_find(unit, "^partypet") then
        -- Map pet unit back to owner party unit for time-window correlation
        local partyIndex = unit:match("^partypet(%d)")
        if partyIndex then
            local ownerUnit = "party" .. partyIndex
            if UnitExists(ownerUnit) then
                self.pendingCasts[ownerUnit] = { time = GetTime() }
                self:ScheduleProcessing()
            end
        end
        return
    end
end

-- =============================================================
-- Combat Event Registration
-- =============================================================
function KT:RegisterCombatEvents()
    if self.combatEventsRegistered then return end
    self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", "OnSpellcastInterrupted")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP", "OnChannelStop")
    self:RegisterEvent("UNIT_AURA", "OnUnitAura")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnSpellcastSucceeded")
    self.combatEventsRegistered = true
end

function KT:UnregisterCombatEvents()
    if not self.combatEventsRegistered then return end
    self:UnregisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    self:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    self:UnregisterEvent("UNIT_AURA")
    self:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    self.combatEventsRegistered = false

    wipe(self.pendingInterrupts)
    wipe(self.pendingCasts)
    wipe(self.pendingAuras)
    self.processScheduled = false
end

-- =============================================================
-- Environment Detection
-- =============================================================
function KT:ShouldBeActive()
    if not self.db or not self.db.Enabled then return false end
    local inInstance, instanceType = IsInInstance()
    if not inInstance or instanceType ~= "party" then return false end
    if not IsInGroup() then return false end
    return true
end

function KT:CheckActivation()
    local shouldBeActive = self:ShouldBeActive()

    if shouldBeActive and not self.isActive then
        self.isActive = true
        self:RegisterCombatEvents()
        if self.containerFrame then
            KE:ApplyFramePosition(self.containerFrame, self.db.Position, self.db)
            self.containerFrame:Show()
        end
        self:RefreshPartyRoster()
    elseif not shouldBeActive and self.isActive then
        self.isActive = false
        self:UnregisterCombatEvents()
        self:HideAllBars()
        if self.containerFrame then self.containerFrame:Hide() end
        wipe(self.partyMembers)
        wipe(self.inspectQueue)
        self.inspectPending = nil
    end
end

function KT:OnZoneChange()
    C_Timer.After(1, function()
        self:CheckActivation()
    end)
end

function KT:OnRosterUpdate()
    if self.isActive then
        self:RefreshPartyRoster()
    else
        self:CheckActivation()
    end
end

function KT:OnCombatEnd()
    -- Process inspect queue when leaving combat
    if self.isActive and #self.inspectQueue > 0 then
        self:ScheduleTimer(function()
            self:ProcessInspectQueue()
        end, 0.5)
    end
end

-- =============================================================
-- Bar Creation & Pool
-- =============================================================
function KT:CreateBar()
    local db = self.db
    local barFrame = CreateFrame("Frame", nil, self.containerFrame, "BackdropTemplate")
    barFrame:SetSize(db.BarWidth, db.BarHeight)
    barFrame:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    barFrame:SetBackdropBorderColor(0, 0, 0, 1)

    -- StatusBar (inset 1px for border)
    local statusBar = CreateFrame("StatusBar", nil, barFrame)
    statusBar:SetPoint("TOPLEFT", barFrame, "TOPLEFT", 1, -1)
    statusBar:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", -1, 1)
    local texPath = KE:GetStatusbarPath(db.StatusBarTexture or "KitnUI")
    statusBar:SetStatusBarTexture(texPath)
    statusBar:SetMinMaxValues(0, 1)
    statusBar:SetValue(1)
    barFrame.statusBar = statusBar

    -- Background texture for the unfilled portion
    local bgTex = statusBar:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints()
    bgTex:SetTexture(texPath)
    bgTex:SetVertexColor(0.1, 0.1, 0.1, 0.8)
    barFrame.bgTex = bgTex

    -- Icon (inside the bar, overlapping the left/right edge)
    local iconFrame = CreateFrame("Frame", nil, statusBar)
    iconFrame:SetSize(db.IconSize, db.IconSize)
    iconFrame:SetFrameLevel(statusBar:GetFrameLevel() + 2)
    barFrame.iconFrame = iconFrame

    local iconBg = iconFrame:CreateTexture(nil, "BACKGROUND")
    iconBg:SetAllPoints()
    iconBg:SetColorTexture(0, 0, 0, 1)
    barFrame.iconBg = iconBg

    local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
    iconTex:SetPoint("TOPLEFT", 1, -1)
    iconTex:SetPoint("BOTTOMRIGHT", -1, 1)
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    barFrame.iconTex = iconTex

    -- Name text (offset right of icon when icon is on the left)
    local nameText = statusBar:CreateFontString(nil, "OVERLAY")
    nameText:SetJustifyH("LEFT")
    barFrame.nameText = nameText

    -- Timer text
    local timerText = statusBar:CreateFontString(nil, "OVERLAY")
    timerText:SetPoint("RIGHT", statusBar, "RIGHT", -2, 0)
    timerText:SetJustifyH("RIGHT")
    barFrame.timerText = timerText

    barFrame:Hide()
    return barFrame
end

function KT:GetOrCreateBar(guid)
    if self.activeBars[guid] then
        return self.activeBars[guid]
    end

    -- Try pool first
    local bar
    for i = #self.barPool, 1, -1 do
        bar = table.remove(self.barPool, i)
        break
    end

    if not bar then
        bar = self:CreateBar()
    end

    self.activeBars[guid] = bar
    return bar
end

function KT:ReleaseBar(guid)
    local bar = self.activeBars[guid]
    if not bar then return end

    bar:Hide()
    bar:SetScript("OnUpdate", nil)

    self.activeBars[guid] = nil
    table_insert(self.barPool, bar)
end

function KT:HideAllBars()
    -- Collect GUIDs first to avoid modifying table during iteration
    local guids = {}
    for guid in pairs(self.activeBars) do
        guids[#guids + 1] = guid
    end
    for _, guid in ipairs(guids) do
        self:ReleaseBar(guid)
    end
    wipe(self.activeBars)
    wipe(self.sortedBars)
end

-- =============================================================
-- Bar Visual Updates
-- =============================================================
-- Helper: get class color or nil
local function GetClassColor(classToken)
    if not classToken then return nil end
    return C_ClassColor.GetClassColor(classToken)
end

function KT:UpdateBarVisuals(bar, member)
    local db = self.db
    local isDarkMode = db.ColorMode == "dark"

    -- Size
    bar:SetSize(db.BarWidth, db.BarHeight)

    -- StatusBar texture
    local texPath = KE:GetStatusbarPath(db.StatusBarTexture or "KitnUI")
    bar.statusBar:SetStatusBarTexture(texPath)
    if bar.bgTex then
        bar.bgTex:SetTexture(texPath)
        bar.bgTex:SetVertexColor(unpack(db.BackgroundColor))
    end

    -- Icon (inside bar, left or right edge)
    local iconSize = db.BarHeight  -- match bar height for flush fit
    bar.iconFrame:SetSize(iconSize, iconSize)
    bar.iconFrame:ClearAllPoints()
    if db.IconSide == "RIGHT" then
        bar.iconFrame:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    else
        bar.iconFrame:SetPoint("LEFT", bar, "LEFT", 0, 0)
    end
    bar.iconFrame:SetShown(db.ShowIcon)

    -- Offset StatusBar: 1px border inset + icon area
    local b = 1 -- border width
    bar.statusBar:ClearAllPoints()
    if db.ShowIcon and db.IconSide == "LEFT" then
        bar.statusBar:SetPoint("TOPLEFT", bar, "TOPLEFT", iconSize, -b)
        bar.statusBar:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -b, b)
    elseif db.ShowIcon and db.IconSide == "RIGHT" then
        bar.statusBar:SetPoint("TOPLEFT", bar, "TOPLEFT", b, -b)
        bar.statusBar:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -iconSize, b)
    else
        bar.statusBar:SetPoint("TOPLEFT", bar, "TOPLEFT", b, -b)
        bar.statusBar:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -b, b)
    end

    -- Name text position (offset past icon)
    bar.nameText:ClearAllPoints()
    bar.nameText:SetPoint("LEFT", bar.statusBar, "LEFT", 2, 0)

    -- Set icon texture
    if member and member.interruptData then
        local spellInfo = C_Spell.GetSpellInfo(member.interruptData.id)
        if spellInfo then
            bar.iconTex:SetTexture(spellInfo.iconID)
        else
            bar.iconTex:SetTexture(134400)
        end
    end

    -- Name text
    KE:ApplyFont(bar.nameText, db.FontFace, db.FontSize, db.FontOutline)
    bar.nameText:SetShown(db.ShowName)
    if member then
        bar.nameText:SetText(member.name or "")
        -- Color mode determines name color:
        -- "class" = class-colored bars, WHITE names (always)
        -- "dark"  = class-colored names when ready, WHITE names when cooling
        local isReady = not member.kickStart
        if isDarkMode and isReady and member.classToken then
            local color = GetClassColor(member.classToken)
            if color then
                bar.nameText:SetTextColor(color.r, color.g, color.b, 1)
            else
                bar.nameText:SetTextColor(1, 1, 1, 1)
            end
        else
            bar.nameText:SetTextColor(1, 1, 1, 1)
        end
    end

    -- Timer text
    KE:ApplyFont(bar.timerText, db.FontFace, db.FontSize, db.FontOutline)
    bar.timerText:SetShown(db.ShowTimer)
    bar.timerText:SetTextColor(1, 1, 1, 1)

    -- Icon desaturation (greyed out when on CD)
    local isReady = not member or not member.kickStart
    bar.iconTex:SetDesaturated(not isReady)

    -- Bar color (ready state)
    if isReady then
        self:ApplyBarColor(bar, member, false)
        -- Dark mode: no fill visible (just dark background). Class mode: full bar.
        bar.statusBar:SetValue(isDarkMode and 0 or 1)
        if db.ShowTimer then
            if db.ShowReadyText then
                bar.timerText:SetText(db.ReadyText or "Ready")
            else
                bar.timerText:SetText("")
            end
        end
    else
        self:ApplyBarColor(bar, member, true)
    end

end

-- Centralized bar color logic
-- Dark mode colors matched to reference screenshot:
-- Ready = very dark, barely distinguishable from background
-- Cooling = slightly brighter dark grey for subtle progress visibility
function KT:ApplyBarColor(bar, member, isCooling)
    local db = self.db
    local isDarkMode = db.ColorMode == "dark"

    if isDarkMode then
        -- Dark mode: cooling bars use class color (fill drains over time)
        -- Ready bars use SetValue(0) so fill color doesn't matter, but set it anyway
        if isCooling and member and member.classToken then
            local color = GetClassColor(member.classToken)
            if color then
                bar.statusBar:SetStatusBarColor(color.r, color.g, color.b, 1)
                return
            end
        end
        bar.statusBar:SetStatusBarColor(0.3, 0.3, 0.3, 1)
    elseif isCooling then
        if db.ClassColorCooling and member and member.classToken then
            local color = GetClassColor(member.classToken)
            if color then
                bar.statusBar:SetStatusBarColor(color.r, color.g, color.b, 1)
                return
            end
        end
        bar.statusBar:SetStatusBarColor(unpack(db.CoolingColor))
    else
        if member and member.classToken then
            local color = GetClassColor(member.classToken)
            if color then
                bar.statusBar:SetStatusBarColor(color.r, color.g, color.b, 1)
                return
            end
        end
        bar.statusBar:SetStatusBarColor(unpack(db.ReadyColor))
    end
end

-- =============================================================
-- Bar Sorting & Layout
-- =============================================================
function KT:GetRolePriority(member)
    if not member or not member.interruptData then return 999 end
    local role = member.interruptData.role
    local db = self.db
    if role == "TANK" then return db.SortTankPriority or 1 end
    if role == "HEALER" then return db.SortHealerPriority or 2 end
    return db.SortDPSPriority or 3
end

function KT:UpdateBars()
    if self.isPreview then return end
    local db = self.db

    -- Collect eligible members (those with interrupt abilities)
    local needsBars = {}
    for guid, member in pairs(self.partyMembers) do
        if member.interruptData then
            needsBars[guid] = true
        end
    end

    -- Release bars for members who no longer qualify
    for guid in pairs(self.activeBars) do
        if not needsBars[guid] then
            self:ReleaseBar(guid)
        end
    end

    -- Create/update bars for eligible members
    for guid in pairs(needsBars) do
        local member = self.partyMembers[guid]
        local bar = self:GetOrCreateBar(guid)
        self:UpdateBarVisuals(bar, member)
        bar:Show()
    end
end

function KT:LayoutBars()
    if not self.containerFrame then return end
    local db = self.db

    -- Build sorted list
    wipe(self.sortedBars)
    local coolingList = {}
    local readyList = {}
    local now = GetTime()

    for guid, bar in pairs(self.activeBars) do
        local member = self.partyMembers[guid]
        if member then
            local isCooling = member.kickStart and member.kickDuration
                and (now - member.kickStart) < member.kickDuration
            if isCooling then
                local remaining = member.kickDuration - (now - member.kickStart)
                table_insert(coolingList, { guid = guid, bar = bar, member = member, remaining = remaining })
            else
                -- Clear expired cooldowns
                if member.kickStart then
                    member.kickStart = nil
                    member.kickDuration = nil
                end
                table_insert(readyList, { guid = guid, bar = bar, member = member })
            end
        end
    end

    -- Sort: ready bars by role priority, cooling bars by remaining time
    table_sort(readyList, function(a, b)
        local pa = self:GetRolePriority(a.member)
        local pb = self:GetRolePriority(b.member)
        if pa ~= pb then return pa < pb end
        return (a.guid or "") < (b.guid or "")
    end)

    table_sort(coolingList, function(a, b)
        return a.remaining < b.remaining
    end)

    -- Ready bars first, then cooling
    for _, entry in ipairs(readyList) do
        table_insert(self.sortedBars, entry)
    end
    for _, entry in ipairs(coolingList) do
        table_insert(self.sortedBars, entry)
    end

    -- Position bars
    local growUp = db.GrowthDirection == "UP"
    local maxBars = db.MaxBars or 5
    local spacing = db.BarSpacing or 2
    local barHeight = db.BarHeight or 20

    -- Container is a fixed 1x1 anchor point. Bars stack from it.
    -- Grow DOWN: first bar TOP anchors to container, subsequent bars below
    -- Grow UP: first bar BOTTOM anchors to container, subsequent bars above
    for i, entry in ipairs(self.sortedBars) do
        local bar = entry.bar
        if i <= maxBars then
            bar:ClearAllPoints()
            local offset = (i - 1) * (barHeight + spacing)
            if growUp then
                bar:SetPoint("BOTTOMLEFT", self.containerFrame, "BOTTOMLEFT", 0, offset)
            else
                bar:SetPoint("TOPLEFT", self.containerFrame, "TOPLEFT", 0, -offset)
            end
            bar:Show()
        else
            bar:Hide()
        end
    end

    -- Keep container at a fixed size for consistent anchor behavior
    self.containerFrame:SetSize(db.BarWidth, 1)
end

-- =============================================================
-- OnUpdate (cooldown progress)
-- =============================================================
function KT:StartOnUpdate()
    if not self.containerFrame then return end
    self.containerFrame:SetScript("OnUpdate", function(_, elapsed)
        self:OnUpdateBars(elapsed)
    end)
end

function KT:StopOnUpdate()
    if self.containerFrame then
        self.containerFrame:SetScript("OnUpdate", nil)
    end
end

function KT:OnUpdateBars(elapsed)
    self._updateAccum = (self._updateAccum or 0) + elapsed
    if self._updateAccum < 0.05 then return end
    self._updateAccum = 0

    local db = self.db
    local now = GetTime()
    local needsRelayout = false
    local anyCooling = false

    for guid, bar in pairs(self.activeBars) do
        local member = self.partyMembers[guid]
        if member and member.kickStart and member.kickDuration then
            local elapsedTime = now - member.kickStart
            local remaining = member.kickDuration - elapsedTime

            if remaining <= 0 then
                -- CD expired — restore ready state
                member.kickStart = nil
                member.kickDuration = nil
                self:UpdateBarVisuals(bar, member)
                needsRelayout = true
            else
                anyCooling = true
                local isDark = db.ColorMode == "dark"
                -- Dark mode: drain from full to empty (remaining/duration)
                -- Class mode: fill from empty to full (elapsed/duration)
                if isDark then
                    bar.statusBar:SetValue(remaining / member.kickDuration)
                else
                    bar.statusBar:SetValue(elapsedTime / member.kickDuration)
                end
                self:ApplyBarColor(bar, member, true)

                if db.ShowTimer and bar.timerText then
                    if remaining > 6 then
                        local displayVal = math_floor(remaining)
                        bar.timerText:SetText(string_format("%d", displayVal))
                    else
                        bar.timerText:SetText(string_format("%.1f", remaining))
                    end
                end
            end
        end
    end

    -- Periodic re-sort every 1s while cooling (matches ExWind)
    if anyCooling then
        self._lastSortUpdate = self._lastSortUpdate or 0
        if now - self._lastSortUpdate >= 1.0 then
            self._lastSortUpdate = now
            needsRelayout = true
        end
    else
        self._lastSortUpdate = nil
    end

    if needsRelayout then
        self:LayoutBars()
    end
end

-- =============================================================
-- Frame Creation
-- =============================================================
function KT:CreateFrames()
    if self.containerFrame then return end

    local frame = CreateFrame("Frame", "KE_KickTracker", UIParent)
    frame:SetSize(1, 1)
    frame:SetFrameStrata(self.db.Strata or "HIGH")
    frame:SetClampedToScreen(true)
    self.containerFrame = frame
end

-- =============================================================
-- Preview / EditMode
-- =============================================================
function KT:ShowPreview()
    if not self.containerFrame then
        self:CreateFrames()
    end
    self:RegWithEditMode()

    self.isPreview = true
    self:HideAllBars()

    KE:ApplyFramePosition(self.containerFrame, self.db.Position, self.db)

    -- Create 5 mock bars: 3 ready + 2 cooling
    local previewData = {
        { name = UnitName("player"), classToken = select(2, UnitClass("player")), spellID = 1766, ready = true },
        { name = "Warrior", classToken = "WARRIOR", spellID = 6552, ready = true },
        { name = "Mage", classToken = "MAGE", spellID = 2139, ready = true },
        { name = "Hunter", classToken = "HUNTER", spellID = 147362, ready = false, remaining = 8.2, cd = 24 },
        { name = "Shaman", classToken = "SHAMAN", spellID = 57994, ready = false, remaining = 3.7, cd = 12 },
    }

    local db = self.db
    local growUp = db.GrowthDirection == "UP"
    local spacing = db.BarSpacing or 2
    local barHeight = db.BarHeight or 20

    for i, data in ipairs(previewData) do
        if i > (db.MaxBars or 5) then break end

        local bar = self:CreateBar()
        local fakeMember = {
            name = data.name,
            classToken = data.classToken,
            interruptData = { id = data.spellID, cd = data.cd or 15, role = "DAMAGER" },
            kickStart = (not data.ready) and GetTime() or nil,
        }
        self:UpdateBarVisuals(bar, fakeMember)

        local isDark = db.ColorMode == "dark"
        if data.ready then
            bar.statusBar:SetValue(isDark and 0 or 1)
        else
            local elapsed = data.cd - data.remaining
            -- Dark mode: drain from full to empty. Class mode: fill from empty to full.
            if isDark then
                bar.statusBar:SetValue(data.remaining / data.cd)
            else
                bar.statusBar:SetValue(elapsed / data.cd)
            end
            -- White name while cooling in dark mode
            if isDark and bar.nameText then bar.nameText:SetTextColor(1, 1, 1, 1) end
            KT:ApplyBarColor(bar, fakeMember, true)

            -- Animate the cooling bars
            local startTime = GetTime() - elapsed
            local cdDuration = data.cd
            bar:SetScript("OnUpdate", function(self)
                local now = GetTime()
                local rem = cdDuration - (now - startTime)
                if rem <= 0 then
                    self:SetScript("OnUpdate", nil)
                    -- Restore ready state
                    fakeMember.kickStart = nil
                    KT:UpdateBarVisuals(bar, fakeMember)
                    return
                end
                if isDark then
                    bar.statusBar:SetValue(rem / cdDuration)
                else
                    bar.statusBar:SetValue((now - startTime) / cdDuration)
                end
                if db.ShowTimer and bar.timerText then
                    if rem > 6 then
                        bar.timerText:SetText(string_format("%d", math_floor(rem)))
                    else
                        bar.timerText:SetText(string_format("%.1f", rem))
                    end
                end
            end)
        end

        bar:ClearAllPoints()
        local offset = (i - 1) * (barHeight + spacing)
        if growUp then
            bar:SetPoint("BOTTOMLEFT", self.containerFrame, "BOTTOMLEFT", 0, offset)
        else
            bar:SetPoint("TOPLEFT", self.containerFrame, "TOPLEFT", 0, -offset)
        end
        bar:Show()

        -- Store as preview bars (using guid-like keys)
        self.activeBars["preview_" .. i] = bar
    end

    self.containerFrame:SetSize(db.BarWidth, 1)
    self.containerFrame:Show()
end

function KT:HidePreview()
    self.isPreview = false
    if not self.containerFrame then return end

    self:HideAllBars()

    if self.isActive then
        self:RefreshPartyRoster()
    else
        self.containerFrame:Hide()
    end
end

function KT:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "KickTracker",
            displayName = "Interrupt Tracker",
            frame = self.containerFrame,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos)
                self.db.Position = pos
                KE:ApplyFramePosition(self.containerFrame, self.db.Position, self.db)
            end,
            getParentFrame = function() return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) end,
            guiPath = "KickTracker",
        })
        self.editModeRegistered = true
    end
end

-- =============================================================
-- Module Lifecycle
-- =============================================================
function KT:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function KT:OnEnable()
    if not self.db.Enabled then return end

    self:CreateFrames()
    self:RegWithEditMode()

    -- Register non-combat events
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnRosterUpdate")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnZoneChange")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "OnZoneChange")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnPlayerSpecChanged")
    self:RegisterEvent("INSPECT_READY", "OnInspectReady")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnd")

    self:StartOnUpdate()

    C_Timer.After(0.5, function()
        self:ApplySettings()
        self:CheckActivation()
    end)
end

function KT:OnDisable()
    self:UnregisterAllEvents()
    self:UnregisterCombatEvents()
    self:CancelAllTimers()
    self:StopOnUpdate()

    self:HideAllBars()
    wipe(self.partyMembers)
    wipe(self.specCache)
    wipe(self.inspectQueue)
    wipe(self.pendingInterrupts)
    wipe(self.pendingCasts)
    wipe(self.pendingAuras)

    self.inspectPending = nil
    self.isActive = false
    self.isPreview = false
    self.processScheduled = false

    if self.containerFrame then self.containerFrame:Hide() end
end

function KT:ApplySettings()
    self:UpdateDB()
    if not self.containerFrame then return end

    KE:ApplyFramePosition(self.containerFrame, self.db.Position, self.db)
    self.containerFrame:SetFrameStrata(self.db.Strata or "HIGH")

    -- Re-apply visuals to all active bars
    for guid, bar in pairs(self.activeBars) do
        local member = self.partyMembers[guid]
        if member then
            self:UpdateBarVisuals(bar, member)
        end
    end

    self:LayoutBars()

    if self.isPreview then
        self:ShowPreview()
    end
end

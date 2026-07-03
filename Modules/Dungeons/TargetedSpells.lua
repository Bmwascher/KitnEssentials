-- ╔══════════════════════════════════════════════════════════╗
-- ║  TargetedSpells.lua                                      ║
-- ║  Module: Targeted Spells                                 ║
-- ║  Purpose: Mirrored icon/countdown entries for enemy      ║
-- ║           nameplate casts that target the player.        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class TargetedSpells: AceModule, AceEvent-3.0
local TS = KitnEssentials:NewModule("TargetedSpells", "AceEvent-3.0")

local CreateFrame = CreateFrame
local IsInInstance, GetInstanceInfo = IsInInstance, GetInstanceInfo
local UnitCastingInfo, UnitChannelInfo = UnitCastingInfo, UnitChannelInfo
local UnitCastingDuration, UnitChannelDuration = UnitCastingDuration, UnitChannelDuration
local UnitEmpoweredChannelDuration = UnitEmpoweredChannelDuration
local PlayerIsSpellTarget = PlayerIsSpellTarget
local C_Spell = C_Spell
local GetTime = GetTime
local C_Timer = C_Timer
local C_StringUtil = C_StringUtil
local tinsert, tremove, tsort = table.insert, table.remove, table.sort
local strmatch = string.match
local type, ipairs = type, ipairs

local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

local DEBUG_TS = false
local function dbg(...)
    if DEBUG_TS then KE:Print("|cff88ccff[TS]|r", ...) end
end

-- Delve difficultyID — probe-confirmed in-game 2026-07-03 (Collegiate
-- Calamity delve: instanceType "scenario", difficultyID 208).
TS.DELVE_DIFFICULTY_ID = 208

local FALLBACK_ICON = 136243
local NAMEPLATE_PATTERN = "^nameplate%d+$"
local MAX_NAMEPLATES = 40
local SETTLE_DELAY = 0.2
local INTERRUPT_LINGER = 1.0   -- seconds the desaturated icon stays up post-interrupt
local INTERRUPT_HOLD = 0.95    -- Release() suppression window; < LINGER avoids a same-tick race with the linger timer

-- Breakpoint countdown formatter (reference pattern): tenths under 3s,
-- whole seconds to 60, m:ss above (only reachable if the >60s gate changes).
-- Lazy so headless spec loads (no C_StringUtil in busted) never touch it.
local castFormatter
local function GetCastFormatter()
    if not castFormatter and C_StringUtil and C_StringUtil.CreateNumericRuleFormatter then
        castFormatter = C_StringUtil.CreateNumericRuleFormatter()
        castFormatter:SetBreakpoints({
            { threshold = 0, format = "%.1f" },
            { threshold = 3.01, format = "%d" },
            { threshold = 60, format = "%d:%02d", components = { { div = 60 }, { mod = 60 } } },
        })
    end
    return castFormatter
end

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------

TS.entryPool = {}
TS.activeEntries = {}   -- unit -> entry
TS.activeCount = 0
TS.contentActive = false
TS.isPreview = false

---------------------------------------------------------------------------------
-- Pure helpers (busted-covered — keep WoW-API-free)
---------------------------------------------------------------------------------

-- Decides visibility from the five content checkboxes. Non-delve scenarios
-- follow the open-world flag.
function TS.ShouldShowForInstance(db, inInstance, instanceType, difficultyID)
    if not inInstance then
        return db.ShowInOpenWorld == true
    end
    if instanceType == "party" then return db.ShowInDungeons ~= false end
    if instanceType == "raid" then return db.ShowInRaids == true end
    if instanceType == "arena" or instanceType == "pvp" then return db.ShowInPvP == true end
    if instanceType == "scenario" then
        if difficultyID == TS.DELVE_DIFFICULTY_ID then return db.ShowInDelves ~= false end
        return db.ShowInOpenWorld == true
    end
    return db.ShowInOpenWorld == true
end

-- Sort key is the plain Lua receipt time (secret cast start times cannot be
-- compared); strict less-than keeps table.sort stable-safe.
function TS.CompareEntries(a, b)
    return (a.receiptTime or 0) < (b.receiptTime or 0)
end

---------------------------------------------------------------------------------
-- DB / lifecycle
---------------------------------------------------------------------------------

function TS:UpdateDB()
    self.db = KE.db.profile.TargetedSpells
end

function TS:OnInitialize()
    self:UpdateDB()
end

function TS:OnEnable()
    self:UpdateDB()
    if not self.db or not self.db.Enabled then return end

    self:CreateAnchorFrame()
    self:ApplyPosition()

    self:RegisterEvent("UNIT_SPELLCAST_START", "OnCastEvent")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START", "OnCastEvent")
    self:RegisterEvent("UNIT_SPELLCAST_EMPOWER_START", "OnCastEvent")
    self:RegisterEvent("UNIT_SPELLCAST_STOP", "OnCastEvent")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP", "OnCastEvent")
    self:RegisterEvent("UNIT_SPELLCAST_EMPOWER_STOP", "OnCastEvent")
    self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", "OnCastEvent")
    self:RegisterEvent("UNIT_TARGET", "OnUnitTarget")
    self:RegisterEvent("NAME_PLATE_UNIT_ADDED", "OnNameplateAdded")
    self:RegisterEvent("NAME_PLATE_UNIT_REMOVED", "OnNameplateRemoved")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "CheckContentGate")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "CheckContentGate")

    self:CheckContentGate()
    self:RegisterEditMode()
    self:CheckCVarPrompt()   -- Task 11 (no-op stub until then)
end

function TS:OnDisable()
    self:UnregisterAllEvents()
    self:ReleaseAllEntries()
    if self.anchorFrame then self.anchorFrame:Hide() end
end

---------------------------------------------------------------------------------
-- Content gating
---------------------------------------------------------------------------------

function TS:ShouldBeActive()
    if self.isPreview then return true end
    local inInstance, instanceType = IsInInstance()
    local _, _, difficultyID = GetInstanceInfo()
    return TS.ShouldShowForInstance(self.db, inInstance, instanceType, difficultyID)
end

function TS:CheckContentGate()
    local shouldBeActive = self:ShouldBeActive()
    if shouldBeActive and not self.contentActive then
        self.contentActive = true
        dbg("gate ON")
        self:ScanExistingNameplates()
    elseif not shouldBeActive and self.contentActive then
        self.contentActive = false
        dbg("gate OFF")
        if not self.isPreview then
            self:ReleaseAllEntries()
        end
    elseif shouldBeActive then
        -- PLAYER_ENTERING_WORLD with the gate already on: rescan (a /reload
        -- mid-combat leaves in-flight casts that fire no new START events).
        self:ScanExistingNameplates()
    end
end

---------------------------------------------------------------------------------
-- Anchor frame / position / EditMode
---------------------------------------------------------------------------------

function TS:CreateAnchorFrame()
    if self.anchorFrame then return end
    local db = self.db
    local f = CreateFrame("Frame", "KE_TargetedSpells", UIParent)
    f:SetSize(db.IconSize * 2 + db.FontSize * 3, db.IconSize)
    self.anchorFrame = f
end

function TS:ApplyPosition()
    if not self.anchorFrame then return end
    local db = self.db
    KE:ApplyFramePosition(self.anchorFrame, db.Position,
        { anchorFrameType = db.anchorFrameType, ParentFrame = db.ParentFrame, Strata = db.Strata }, true)
end

function TS:RegisterEditMode()
    if not KE.EditMode or self.editModeRegistered then return end
    KE.EditMode:RegisterElement({
        key = "TargetedSpells",
        displayName = "Targeted Spells",
        frame = self.anchorFrame,
        getPosition = function() return self.db.Position end,
        setPosition = function(pos)
            local p = self.db.Position
            p.AnchorTo = pos.AnchorTo
            p.XOffset = pos.XOffset
            p.YOffset = pos.YOffset
            self:ApplyPosition()
        end,
        getAnchorFrom = function() return self.db.Position.AnchorFrom or "CENTER" end,
        getParentFrame = function()
            return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)
        end,
        guiPath = "TargetedSpells",
    })
    self.editModeRegistered = true
end

---------------------------------------------------------------------------------
-- Entry frames
---------------------------------------------------------------------------------

local function CreateIconFrame(entry, db)
    local f = CreateFrame("Frame", nil, entry)
    f:SetSize(db.IconSize, db.IconSize)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints(f)
    KE:ApplyIconZoom(f.tex, 0.3)
    KE:AddIconBorders(f)
    f.cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cooldown:SetAllPoints(f)
    f.cooldown:SetDrawEdge(false)
    return f
end

function TS:CreateEntry()
    local db = self.db
    local width = db.IconSize * 2 + db.FontSize * 3
    local entry = CreateFrame("Frame", nil, self.anchorFrame)
    entry:SetSize(width, db.IconSize)

    -- Layout spine: textureless StatusBar whose fill extent mirrors entry
    -- alpha, so invisible entries compact out of the stack (reference
    -- spacer-chain mechanism). Length covers the entry + gap.
    entry.Spacer = CreateFrame("StatusBar", nil, entry)
    entry.Spacer:SetStatusBarTexture("")
    entry.Spacer:SetOrientation("VERTICAL")
    entry.Spacer:SetMinMaxValues(0, 1)
    entry.Spacer:SetSize(1, db.IconSize + db.Gap)
    entry.Spacer:SetValue(1)

    entry.leftIcon = CreateIconFrame(entry, db)
    entry.leftIcon:SetPoint("LEFT", entry, "LEFT", 0, 0)
    entry.rightIcon = CreateIconFrame(entry, db)
    entry.rightIcon:SetPoint("RIGHT", entry, "RIGHT", 0, 0)
    entry.rightIcon.cooldown:SetHideCountdownNumbers(true)

    entry.generation = 0
    return entry
end

---------------------------------------------------------------------------------
-- Entry pool / release
---------------------------------------------------------------------------------

function TS:AcquireEntry(unit)
    local entry = tremove(self.entryPool)
    if not entry then entry = self:CreateEntry() end
    entry.unit = unit
    entry.generation = (entry.generation or 0) + 1
    self.activeEntries[unit] = entry
    self.activeCount = self.activeCount + 1
    entry:Show()
    return entry
end

-- Single funnel for every removal path. Generation guards stale timers and
-- widget callbacks; the interrupt linger suppresses STOP/OnCooldownDone
-- racing in behind an interrupt ("force" = linger timer / nameplate gone).
function TS:Release(entry, generation, reason)
    if not entry or entry.generation ~= generation then return end
    if entry.wasInterrupted and reason ~= "force" then
        if GetTime() < (entry.doNotHideBefore or 0) then
            dbg("release suppressed (linger)", entry.unit, reason)
            return
        end
    end
    dbg("release", entry.unit, reason)
    if self.activeEntries[entry.unit] == entry then
        self.activeEntries[entry.unit] = nil
        self.activeCount = self.activeCount - 1
    end
    entry.generation = entry.generation + 1  -- invalidate pending callbacks
    entry.unit, entry.castKey, entry.kind = nil, nil, nil
    entry.receiptTime, entry.durationObject = nil, nil
    entry.spellId = nil
    entry.wasInterrupted, entry.doNotHideBefore = nil, nil
    -- Idempotent teardown: pooled frames must come back visually neutral.
    entry:SetAlpha(1)
    entry.Spacer:SetValue(1)
    entry.leftIcon.tex:SetDesaturated(false)
    entry.rightIcon.tex:SetDesaturated(false)
    entry.leftIcon.cooldown:Clear()
    entry.leftIcon.cooldown:SetScript("OnCooldownDone", nil)
    entry.rightIcon.cooldown:Clear()
    self:StopGlow(entry)
    entry:Hide()
    entry:ClearAllPoints()
    entry.Spacer:ClearAllPoints()
    tinsert(self.entryPool, entry)
    self:RepositionEntries()
end

-- ReleaseAllEntries empties activeEntries first, so Release's active-table
-- bookkeeping no-ops safely; count is reset wholesale.
function TS:ReleaseAllEntries()
    local entries = self.activeEntries
    self.activeEntries = {}
    self.activeCount = 0
    for _, entry in pairs(entries) do
        entry.wasInterrupted = nil
        self:Release(entry, entry.generation, "force")
    end
end

local GLOW_KEY = "KE_TS"

-- Reference pattern: glow runs whenever a spellId exists; the SECRET
-- importance boolean only drives the glow child's alpha (never branched on).
-- Shipped precedent: CastbarHelpers H.UpdateGlow. Icon frames are plainly
-- SetSize'd, so stock LCG reading their size is safe; if secret-size errors
-- appear in BugSack, port the reference's size-parameterized glow fork.
function TS:UpdateGlow(entry)
    if not LCG then return end
    if not self.db.GlowImportant or not entry.spellId then
        self:StopGlow(entry)
        return
    end
    local isImportant = C_Spell and C_Spell.IsSpellImportant
        and C_Spell.IsSpellImportant(entry.spellId)
    if type(isImportant) == "nil" then isImportant = false end  -- taint-safe nil check
    for _, iconFrame in ipairs({ entry.leftIcon, entry.rightIcon }) do
        LCG.PixelGlow_Start(iconFrame, nil, nil, nil, nil, nil, nil, nil, nil, GLOW_KEY)
        local child = iconFrame["_PixelGlow" .. GLOW_KEY]
        if child then
            child:SetAlphaFromBoolean(isImportant, 1, 0)
        end
    end
end

function TS:StopGlow(entry)
    if not LCG or not entry.leftIcon then return end
    for _, iconFrame in ipairs({ entry.leftIcon, entry.rightIcon }) do
        -- Reset the bound (possibly 0) alpha BEFORE Stop: PixelGlow_Stop's
        -- pool resetter nils iconFrame["_PixelGlow"..GLOW_KEY] as it releases
        -- the child, and the pool is shared with every LCG consumer.
        local child = iconFrame["_PixelGlow" .. GLOW_KEY]
        if child then child:SetAlpha(1) end
        LCG.PixelGlow_Stop(iconFrame, GLOW_KEY)
    end
end

---------------------------------------------------------------------------------
-- Populate + visibility binding
---------------------------------------------------------------------------------

-- info: { kind = "cast"|"channel"|"empower", castKey, name, texture,
--         spellId, duration (LuaDurationObject) }
function TS:PopulateEntry(entry, unit, info)
    local db = self.db
    entry.castKey = info.castKey
    entry.kind = info.kind
    entry.spellId = info.spellId
    entry.receiptTime = GetTime()
    entry.durationObject = info.duration
    entry.wasInterrupted, entry.doNotHideBefore = nil, nil
    entry.leftIcon.tex:SetDesaturated(false)
    entry.rightIcon.tex:SetDesaturated(false)

    entry.leftIcon.tex:SetTexture(info.texture or FALLBACK_ICON)
    entry.rightIcon.tex:SetTexture(info.texture or FALLBACK_ICON)

    local lc, rc = entry.leftIcon.cooldown, entry.rightIcon.cooldown
    lc:SetDrawSwipe(db.ShowSwipe ~= false)
    rc:SetDrawSwipe(db.ShowSwipe ~= false)
    lc:SetHideCountdownNumbers(false)
    lc:SetCountdownFormatter(GetCastFormatter())
    lc:SetCooldownFromDurationObject(info.duration)
    rc:SetCooldownFromDurationObject(info.duration)

    -- Widget-managed FontString: the Cooldown resets font/anchors on
    -- Clear()/SetCooldown, so re-apply BOTH on every populate.
    local fs = lc:GetCountdownFontString()
    if fs then
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", entry, "CENTER", 0, 0)
        local ok = pcall(fs.SetFont, fs, KE:GetFontPath(db.FontFace), db.FontSize,
            KE:GetFontOutline(db.FontOutline))
        if not ok then
            pcall(fs.SetFont, fs, KE:GetFontPath("Expressway"), db.FontSize, "OUTLINE")
        end
    end

    lc:SetScript("OnCooldownDone", function()
        TS:Release(entry, entry.generation, "cooldown-done")
    end)

    -- THE verbatim core (spec "Visibility binding"): the secret targeting
    -- boolean never enters Lua; durationAlpha doubles as the >60s gate; the
    -- spacer mirrors alpha so hidden entries compact out of the stack.
    local durationAlpha = info.duration:EvaluateRemainingDuration(KE.curves.IsLongCast)
    entry:SetAlpha(durationAlpha)
    entry.Spacer:SetValue(durationAlpha)
    entry:SetAlphaFromBoolean(PlayerIsSpellTarget(unit), durationAlpha, 0)
    entry.Spacer:SetValue(entry:GetAlpha())

    self:UpdateGlow(entry)
end

---------------------------------------------------------------------------------
-- Layout (spacer chain)
---------------------------------------------------------------------------------

function TS:RepositionEntries()
    local db = self.db
    local list = {}
    for _, entry in pairs(self.activeEntries) do tinsert(list, entry) end
    tsort(list, TS.CompareEntries)

    local growDown = (db.Grow or "DOWN") == "DOWN"
    local point = growDown and "TOP" or "BOTTOM"
    local relPoint = growDown and "BOTTOM" or "TOP"
    local prevTexture
    for i, entry in ipairs(list) do
        local spacer = entry.Spacer
        -- Fill from the anchored edge so a zero-value spacer's texture edge
        -- collapses to the chain point (verify direction in-game; reference
        -- layout: Utils.lua:202-246).
        spacer:SetReverseFill(growDown)
        spacer:ClearAllPoints()
        spacer:SetPoint(point, (i == 1) and self.anchorFrame or prevTexture, relPoint, 0, 0)
        entry:ClearAllPoints()
        entry:SetPoint(point, spacer, point, 0, 0)
        prevTexture = spacer:GetStatusBarTexture()
    end
end

---------------------------------------------------------------------------------
-- Cast start pipeline
---------------------------------------------------------------------------------

local function IsRelevantUnit(unit)
    return unit and strmatch(unit, NAMEPLATE_PATTERN)
        and UnitExists(unit) and UnitCanAttack("player", unit)
end

-- Delayed re-read: cast target/duration data settles ~0.2s after the event
-- (reference behavior). castKey aborts the stale handler when two casts
-- land <0.2s apart on one unit.
function TS:TryStart(unit, castKey)
    if not self.contentActive then return end
    if not IsRelevantUnit(unit) then return end

    local info
    local name, _, texture, _, _, _, castID, _, spellID = UnitCastingInfo(unit)
    if name then
        if castKey and castID and castKey ~= castID then
            dbg("stale delayed start (cast)", unit)
            return
        end
        local duration = UnitCastingDuration(unit)
        if not duration then return end
        info = { kind = "cast", castKey = castID or castKey,
                 name = name, texture = texture, spellId = spellID, duration = duration }
    else
        -- Empowered casts report through UnitChannelInfo with isEmpowered set
        -- and use UnitEmpoweredChannelDuration — KE's own CastbarHelpers
        -- H.StartCast is the shipped precedent (CastbarHelpers.lua:751-761).
        local cname, _, ctexture, _, _, _, _, cspellID, isEmpowered = UnitChannelInfo(unit)
        if not cname then return end
        local duration
        if isEmpowered then
            duration = UnitEmpoweredChannelDuration(unit)
        else
            duration = UnitChannelDuration(unit)
        end
        if not duration then return end
        -- UnitChannelInfo exposes no cast GUID; the event-payload castGUID
        -- captured at dispatch is the key (spec "castKey").
        info = { kind = isEmpowered and "empower" or "channel", castKey = castKey,
                 name = cname, texture = ctexture, spellId = cspellID, duration = duration }
    end

    local entry = self.activeEntries[unit]
    if entry then
        self:Release(entry, entry.generation, "force")   -- replace-by-unit
    elseif self.activeCount >= (self.db.MaxIcons or 10) then
        dbg("at cap, ignoring", unit)
        return
    end
    entry = self:AcquireEntry(unit)
    self:PopulateEntry(entry, unit, info)
    self:RepositionEntries()
    dbg("started", unit, info.kind, info.name)
end

function TS:OnCastEvent(event, unit, castGUID)
    if not strmatch(unit or "", NAMEPLATE_PATTERN) then return end

    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START"
        or event == "UNIT_SPELLCAST_EMPOWER_START" then
        C_Timer.After(SETTLE_DELAY, function()
            TS:TryStart(unit, castGUID)
        end)
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        self:OnInterrupted(unit, castGUID)               -- Task 9
    else -- STOP / CHANNEL_STOP / EMPOWER_STOP
        local entry = self.activeEntries[unit]
        if entry and (not entry.castKey or not castGUID or entry.castKey == castGUID) then
            self:Release(entry, entry.generation, "stop")
        end
    end
end

function TS:OnInterrupted(unit, castGUID)
    local entry = self.activeEntries[unit]
    if not entry then return end
    if entry.castKey and castGUID and entry.castKey ~= castGUID then return end
    if not self.db.IndicateInterrupts then
        self:Release(entry, entry.generation, "stop")
        return
    end
    dbg("interrupted", unit)
    entry.wasInterrupted = true
    entry.doNotHideBefore = GetTime() + INTERRUPT_HOLD
    entry.leftIcon.tex:SetDesaturated(true)
    entry.rightIcon.tex:SetDesaturated(true)
    local gen = entry.generation
    C_Timer.After(INTERRUPT_LINGER, function()
        TS:Release(entry, gen, "force")
    end)
end

function TS:ScanExistingNameplates()
    for i = 1, MAX_NAMEPLATES do
        local unit = "nameplate" .. i
        if UnitExists(unit) and UnitCanAttack("player", unit) then
            C_Timer.After(SETTLE_DELAY, function() TS:TryStart(unit) end)
        end
    end
end

function TS:OnNameplateAdded(_, unit)
    if self.contentActive and IsRelevantUnit(unit) then
        C_Timer.After(SETTLE_DELAY, function() TS:TryStart(unit) end)
    end
end

function TS:OnNameplateRemoved(_, unit)
    local entry = self.activeEntries[unit]
    if entry then
        entry.wasInterrupted = nil
        self:Release(entry, entry.generation, "force")
    end
end

function TS:OnUnitTarget(_, unit)
    -- Retarget mid-cast: rebuild (release + reacquire re-runs the binding
    -- and refreshes receiptTime — reference behavior, re-sorts to newest).
    if self.activeEntries[unit] then
        self:TryStart(unit)
    end
end

---------------------------------------------------------------------------------
-- Settings application / preview
---------------------------------------------------------------------------------

-- Structural keys (IconSize/Gap/Grow/Font*/MaxIcons) invalidate pooled frame
-- geometry: drop the pool and re-derive everything.
function TS:RebuildEntries()
    self:ReleaseAllEntries()
    for _, entry in ipairs(self.entryPool) do
        entry:SetParent(nil)
        entry:Hide()
    end
    self.entryPool = {}
    if self.anchorFrame then
        local db = self.db
        self.anchorFrame:SetSize(db.IconSize * 2 + db.FontSize * 3, db.IconSize)
    end
    self:ApplyPosition()
    if self.isPreview then self:ShowPreview() end
    self:CheckContentGate()
end

-- In-place keys (ShowSwipe / GlowImportant / IndicateInterrupts / content
-- checkboxes): re-apply to live entries, re-evaluate the gate immediately.
function TS:ApplySettings()
    self:UpdateDB()
    local db = self.db
    for _, entry in pairs(self.activeEntries) do
        entry.leftIcon.cooldown:SetDrawSwipe(db.ShowSwipe ~= false)
        entry.rightIcon.cooldown:SetDrawSwipe(db.ShowSwipe ~= false)
        self:UpdateGlow(entry)
    end
    self:CheckContentGate()
end

local PREVIEW_ENTRIES = {
    { icon = 135846, duration = 8 },   -- Frostbolt
    { icon = 136197, duration = 5 },   -- Shadow Bolt
}

function TS:ShowPreview()
    self:UpdateDB()
    if not self.anchorFrame then self:CreateAnchorFrame() end
    self:ApplyPosition()
    self:HidePreview()
    self.isPreview = true
    self.anchorFrame:Show()
    self.previewEntries = {}
    local now = GetTime()
    for i, p in ipairs(PREVIEW_ENTRIES) do
        local entry = self:CreateEntry()
        entry.receiptTime = now + i
        entry.leftIcon.tex:SetTexture(p.icon)
        entry.rightIcon.tex:SetTexture(p.icon)
        -- Plain-number cooldown path: previews never touch secret values.
        entry.leftIcon.cooldown:SetHideCountdownNumbers(false)
        entry.leftIcon.cooldown:SetCountdownFormatter(GetCastFormatter())
        entry.leftIcon.cooldown:SetCooldown(now, p.duration)
        entry.rightIcon.cooldown:SetCooldown(now, p.duration)
        local fs = entry.leftIcon.cooldown:GetCountdownFontString()
        if fs then
            fs:ClearAllPoints()
            fs:SetPoint("CENTER", entry, "CENTER", 0, 0)
            pcall(fs.SetFont, fs, KE:GetFontPath(self.db.FontFace), self.db.FontSize,
                KE:GetFontOutline(self.db.FontOutline))
        end
        entry:Show()
        tinsert(self.previewEntries, entry)
    end
    -- Chain the preview entries exactly like live ones.
    local saveActive, saveCount = self.activeEntries, self.activeCount
    self.activeEntries, self.activeCount = {}, 0
    for i, e in ipairs(self.previewEntries) do
        self.activeEntries["preview" .. i] = e
        self.activeCount = self.activeCount + 1
    end
    self:RepositionEntries()
    self.activeEntries, self.activeCount = saveActive, saveCount
end

function TS:HidePreview()
    self.isPreview = false
    if self.previewEntries then
        for _, entry in ipairs(self.previewEntries) do
            entry:Hide()
            entry:ClearAllPoints()
            entry.Spacer:ClearAllPoints()
            entry.leftIcon.cooldown:Clear()
            entry.rightIcon.cooldown:Clear()
            tinsert(self.entryPool, entry)
        end
        self.previewEntries = nil
    end
    self:CheckContentGate()
end

---------------------------------------------------------------------------------
-- Stubs completed by Task 11 (keep so the file loads and lints clean)
---------------------------------------------------------------------------------

function TS:CheckCVarPrompt() end

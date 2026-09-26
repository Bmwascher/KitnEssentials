-- ╔══════════════════════════════════════════════════════════╗
-- ║  PIAssist.lua                                            ║
-- ║  Module: Power Infusion Assist                           ║
-- ║  Purpose: Glow the raid frame of the PI macro's target   ║
-- ║           while one of their burst buffs is running.     ║
-- ║  Note: Priest only.                                      ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- Nothing here reads an aura or another player's cooldown; both are secret
-- in a fight. A Blizzard aura container is bound to the target's unit with a
-- spell-id filter for their burst buffs: the engine matches, the engine shows
-- its button, and the glow built on that button rides it. The one number read
-- is the player's own Power Infusion cooldown, static spell data.

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class PIAssist: AceModule
local PA = KitnEssentials:NewModule("PIAssist", "AceEvent-3.0")
PA.classRestriction = "PRIEST"

local _G = _G
local CreateFrame = CreateFrame
local C_AddOns = C_AddOns
local C_Timer = C_Timer
local C_UnitAuras = C_UnitAuras
local UnitClass = UnitClass
local UnitName = UnitName
local UnitIsUnit = UnitIsUnit
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup
local GetNumGroupMembers = GetNumGroupMembers
local GetSpecialization = C_SpecializationInfo.GetSpecialization
local GetSpecializationRole = GetSpecializationRole
local GetTime = GetTime
local pcall = pcall
local pairs = pairs
local type = type
local strlower = string.lower

-- Flip to true, /reload, repro, read the log. The slot line is the one that
-- matters: a refusal there means the bound unit is identity-restricted.
local DEBUG_PA = false

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
local PI_SPELL_ID = 10060
local PI_BASE_CD = 120
-- Base cooldowns at or under this are the global cooldown or a missing spell,
-- never Power Infusion.
local BASE_CD_FLOOR_MS = 1500
local READY_TIMER_PAD = 0.05
local ROSTER_SETTLE = 0.5
local HEALER_ROLE = "HEALER"
local SLOT_KEY = "pitarget"
local GLOW_OFF = { GlowEnabled = false }
local SOUND_KEYS = { enabled = "SoundEnabled", name = "SoundName" }

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------
PA.holder = nil
PA.container = nil
PA.glowHost = nil
PA.castFrame = nil
PA.unit = nil
PA.resolvedFor = nil
PA.boundUnit = nil
PA.soundUnit = nil
PA.sounds = nil
PA.active = false
PA.previewing = false
PA.watchedCells = {}
PA.glowPending = false
PA.previewHost = nil
PA.previewGlow = nil
PA.previewCell = nil

local function Debug(msg)
    if DEBUG_PA then KE:Print("[PA] " .. msg) end
end

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function PA:UpdateDB()
    self.db = KE.db.profile.PIAssist
end

function PA:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

---------------------------------------------------------------------------------
-- Gate
---------------------------------------------------------------------------------
-- Reading your own class and spec is never restricted.
local function ReadSpecIdentity()
    local _, class = UnitClass("player")
    local specIndex = GetSpecialization and GetSpecialization()
    local role = nil
    if specIndex and specIndex > 0 and GetSpecializationRole then
        role = GetSpecializationRole(specIndex)
    end
    return class, role
end

local function WantsSpec(class, role, healersOnly)
    if class ~= "PRIEST" then return false end
    if not healersOnly then return true end
    return role == HEALER_ROLE
end
PA.WantsSpec = WantsSpec

-- A scan in which any group name was secret proves nothing about who is
-- here, so the last answer stands while it was made for the same stored
-- string; a scan that read every name and matched none clears it.
local function KeepsLastUnit(sawSecret, resolvedFor, stored)
    return sawSecret == true and resolvedFor ~= nil and resolvedFor == stored
end
PA.KeepsLastUnit = KeepsLastUnit

function PA:IsWantedSpec()
    local class, role = ReadSpecIdentity()
    return WantsSpec(class, role, self.db.HealersOnly ~= false)
end

-- Off-spec nothing is registered and no container is built. The identity is
-- sampled once so the log describes the decision actually taken.
function PA:EvaluateGate()
    local enabled = self.db.Enabled == true
    local class, role = ReadSpecIdentity()
    local wanted = WantsSpec(class, role, self.db.HealersOnly ~= false)
    Debug(("gate enabled=%s class=%s role=%s -> %s"):format(
        tostring(enabled), tostring(class), tostring(role),
        (enabled and wanted) and "activate" or "deactivate"))
    if not (enabled and wanted) then return self:Deactivate() end
    self:Activate()
end

---------------------------------------------------------------------------------
-- Target: the name the PI macro carries, resolved to a group unit.
---------------------------------------------------------------------------------
local function NormalizeName(name)
    if type(name) ~= "string" or KE:IsSecretValue(name) then return nil end
    name = name:match("^([^%-]+)") or name
    if name == "" then return nil end
    return strlower(name)
end

-- The glow follows the name the macro carries. While the builder is on
-- that is the last name it wrote (a write deferred by combat re-notifies
-- when it lands); off, the stored name stands alone.
function PA:TargetName()
    local macro = KE.db.profile.PIMacroBuilder
    local name = macro and macro.Target
    local builder = KitnEssentials:GetModule("PIMacroBuilder", true)
    if builder and builder:IsEnabled() then name = builder.appliedTarget end
    if type(name) == "string" and name ~= "" then return name end
    return nil
end

-- resolvedFor is the raw stored string, realm included, so a realm change
-- is a new name even though the match itself is on the short name.
function PA:ResolveTarget()
    local stored = self:TargetName()
    local want = NormalizeName(stored)
    if not want then
        self.unit, self.resolvedFor = nil, nil
        self:SyncDisplay()
        return
    end

    local found, sawSecret
    local function try(unit)
        local raw = UnitName(unit)
        if raw ~= nil and KE:IsSecretValue(raw) then sawSecret = true end
        if NormalizeName(raw) == want then found = unit end
    end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            try("raid" .. i)
            if found then break end
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            try("party" .. i)
            if found then break end
        end
    end
    if not found then try("player") end

    if found then
        self.unit, self.resolvedFor = found, stored
    elseif not KeepsLastUnit(sawSecret, self.resolvedFor, stored) then
        self.unit, self.resolvedFor = nil, nil
    end
    Debug("target " .. tostring(want) .. " -> " .. tostring(self.unit))
    self:SyncDisplay()
end

-- Reached on every change to the name the glow follows, this module active
-- or not. Only the PI Assist and PI Macro Builder pages show that name, and a
-- profile refresh rebuilds the shown page itself once it has run.
function PA:OnTargetChanged()
    if self.active then self:ResolveTarget() end
    local gui = KE.GUIFrame
    if not gui then return end
    local pm = KE.ProfileManager
    if pm and pm:IsRefreshingModules() then return end
    local page = gui.selectedSidebarItem
    if (page == "PIAssist" or page == "PIMacroBuilder") and gui.RefreshContent then
        gui:RefreshContent()
    end
end

---------------------------------------------------------------------------------
-- The unit's raid frame: EllesmereUI buttons first (they carry the unit as a
-- secure attribute), then Blizzard's compact frames. Pure reads.
---------------------------------------------------------------------------------
local function FrameUnitToken(frame)
    local unit = frame.displayedUnit
    if not KE:IsSafeValue(unit) then unit = frame.unit end
    if type(unit) ~= "string" and frame.GetAttribute then
        local ok, attr = pcall(frame.GetAttribute, frame, "unit")
        if ok then unit = attr end
    end
    if type(unit) ~= "string" or KE:IsSecretValue(unit) then return nil end
    return unit
end

local function FrameVisible(frame)
    local ok, v = pcall(frame.IsVisible, frame)
    return ok and v == true
end

local function FrameMatches(frame, unit)
    return type(frame) == "table" and FrameVisible(frame) and FrameUnitToken(frame) == unit
end

function PA:FindUnitFrame(unit)
    if not unit then return nil end
    local ns = _G.EllesmereUI and _G.EllesmereUI._ModuleNS
    ns = ns and ns.EllesmereUIRaidFrames
    local buttons = ns and ns._euiUnitButtons
    if type(buttons) == "table" then
        for k, v in pairs(buttons) do
            local btn = type(k) == "table" and k or v
            if FrameMatches(btn, unit) then return btn, "eui" end
        end
    end
    for i = 1, 40 do
        local f = _G["CompactRaidFrame" .. i]
        if FrameMatches(f, unit) then return f, "raid" end
    end
    for g = 1, 8 do
        for m = 1, 5 do
            local f = _G["CompactRaidGroup" .. g .. "Member" .. m]
            if FrameMatches(f, unit) then return f, "group" end
        end
    end
    for i = 1, 5 do
        local f = _G["CompactPartyFrameMember" .. i]
        if FrameMatches(f, unit) then return f, "party" end
    end
    return nil
end

---------------------------------------------------------------------------------
-- Holder + container. The holder is ours and sits over the unit frame; the
-- container is bound to the unit.
---------------------------------------------------------------------------------
local function ContainersAvailable()
    if _G.AuraContainerSortMethod == nil and C_AddOns and C_AddOns.LoadAddOn
        and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    end
    return _G.AuraContainerSortMethod ~= nil
end

function PA:EnsureHolder()
    if self.holder then return self.holder end
    local h = CreateFrame("Frame", "KE_PIAssistHolder", UIParent)
    h:SetFrameStrata("HIGH")
    h:EnableMouse(false)
    h:SetSize(1, 1)
    h:Hide()
    self.holder = h
    return h
end

function PA:IncludeSpellIDs()
    return KE.AuraRules.BuildIncludeSpellIDs(self.db.Allowlist)
end

-- The button is touched only inside this window, so it is one pcall and
-- built in full here: the slot takes no part in the flow layout and is
-- anchored by hand, and the host is re-anchored to the holder because the
-- button's size cannot be known and the holder's can.
function PA:InitSlotButton(button)
    local holder = self.holder
    local ok = pcall(function()
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
        button:SetSize(1, 1)
        local host = KE.AuraGlow.CreateHost(button, self.db)
        host:ClearAllPoints()
        host:SetAllPoints(holder)
        self.glowHost = host
    end)
    Debug("slot button built=" .. tostring(ok))
end

function PA:BuildContainer()
    if self.container or not ContainersAvailable() then return end
    local holder = self:EnsureHolder()

    local ok, container = pcall(CreateFrame, "AuraContainer", nil, holder, "CustomAuraContainerTemplate")
    Debug("container created=" .. tostring(ok))
    if not ok or not container then return end
    container:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    container:SetSize(1, 1)
    pcall(container.EnableMouse, container, false)

    local options = {
        initializeFrame = function(button) PA:InitSlotButton(button) end,
        candidateFilters = { includeSpellIDs = self:IncludeSpellIDs() },
    }
    local added = pcall(container.AddAuraSlot, container, SLOT_KEY, "HELPFUL", options)
    Debug("slot added=" .. tostring(added))
    if not added then return end
    self.container = container
end

function PA:ApplyFilters()
    local container = self.container
    if not container then return end
    pcall(container.SetAuraSlotCandidateFilters, container, SLOT_KEY,
        { includeSpellIDs = self:IncludeSpellIDs() })
end

-- The host is a child of the engine's button, so the touch can be refused
-- while the bound unit's auras are secret; a refusal is retried on release.
function PA:ApplyGlow()
    if not self.glowHost then return end
    local ok = pcall(KE.AuraGlow.Configure, self.glowHost, self.db)
    self.glowPending = not ok
end

-- The cell can go away without the unit changing: another addon swaps its
-- party header for its raid header, or Blizzard rebuilds the compact frames.
-- No roster event lands after that rebuild, so the holder would keep sitting
-- on a cell that is no longer on screen. Each cell is hooked once, and the
-- re-resolve is deferred a frame so the replacement exists to be found.
function PA:WatchCell(frame)
    if not frame or self.watchedCells[frame] then return end
    self.watchedCells[frame] = true
    frame:HookScript("OnHide", function()
        if not (self:IsEnabled() and self.active) then return end
        C_Timer.After(0, function()
            if self:IsEnabled() and self.active then self:ResolveTarget() end
        end)
    end)
end

-- Points the display at the current unit and that unit's frame. Called from
-- every path that can change either, and cheap enough to call blind.
function PA:SyncDisplay()
    if not self.active then return end
    self:BuildContainer()
    local container = self.container
    if not container then return end

    local unit = self.unit
    local frame, source = nil, nil
    if unit then frame, source = self:FindUnitFrame(unit) end
    local holder = self:EnsureHolder()
    Debug("frame for " .. tostring(unit) .. ": " .. tostring(source))

    if not (unit and frame) then
        holder:Hide()
        if self.boundUnit then
            pcall(container.SetEnabled, container, false)
            self.boundUnit = nil
            self:SyncSounds()
        end
        return
    end

    -- Anchored, never parented: a child of a raid cell inherits the cell's
    -- protection and could not be hidden in combat.
    holder:ClearAllPoints()
    holder:SetAllPoints(frame)
    self:WatchCell(frame)
    holder:SetFrameStrata(frame:GetFrameStrata() or "HIGH")
    holder:Show()

    if self.boundUnit ~= unit then
        -- Enabled before SetUnit, so the unit's aura events register.
        pcall(container.SetEnabled, container, true)
        pcall(container.SetUnit, container, unit)
        pcall(container.UpdateAllAuras, container)
        self.boundUnit = unit
        self:SyncSounds()
    end
    self:ApplyReadyGate()
    container:Show()
end

---------------------------------------------------------------------------------
-- Only while your own Power Infusion is ready. The cast is a player-filtered
-- event with a plain spell id; the length is static spell data. A disabled
-- container registers no aura events, so this gate is also the idle state.
---------------------------------------------------------------------------------
local function ReadyDelay(ms, grace)
    local cd = PI_BASE_CD
    if type(ms) == "number" and ms > BASE_CD_FLOOR_MS then cd = ms / 1000 end
    local delay = cd - (grace or 0)
    if delay < 0 then delay = 0 end
    return delay
end
PA.ReadyDelay = ReadyDelay

local function ReadyGateOpen(onlyWhenReady, backAt, now)
    if not onlyWhenReady then return true end
    if not backAt then return true end
    return now >= backAt
end
PA.ReadyGateOpen = ReadyGateOpen

function PA:ApplyReadyGate()
    local container = self.container
    if not (container and self.boundUnit) then return end
    local open = ReadyGateOpen(self.db.OnlyWhenPIReady ~= false, self._piBackAt, GetTime())
    pcall(container.SetEnabled, container, open)
end

function PA:OnPlayerCast(spellID)
    if spellID ~= PI_SPELL_ID then return end
    local ms = nil
    local fn = _G.GetSpellBaseCooldown
    if fn then
        local ok, value = pcall(fn, PI_SPELL_ID)
        if ok and KE:IsSafeValue(value) then ms = value end
    end
    local delay = ReadyDelay(ms, self.db.Grace)
    self._piBackAt = GetTime() + delay
    self:ApplyReadyGate()
    if self._readyTimer then self._readyTimer:Cancel() end
    self._readyTimer = C_Timer.NewTimer(delay + READY_TIMER_PAD, function()
        self._readyTimer = nil
        self._piBackAt = nil
        if self:IsEnabled() then self:ApplyReadyGate() end
    end)
end

---------------------------------------------------------------------------------
-- Sound: the engine plays it when the buff lands, with no read of ours. The
-- registry refuses to add while aura identities are hidden and drains on
-- release; it is retired whenever the bound unit changes because its change
-- signature is the path and the id set, not the unit.
---------------------------------------------------------------------------------
function PA:EnsureSounds()
    if self.sounds then return self.sounds end
    if not (KE.AuraSound and C_UnitAuras and C_UnitAuras.AddAuraSound) then return nil end
    self.sounds = KE.AuraSound.New({
        api = { Add = C_UnitAuras.AddAuraSound, Remove = C_UnitAuras.RemoveAuraSound },
        resolveMedia = function(name) return KE.LSM:Fetch("sound", name, true) end,
        isHidden = function() return KE:AreAuraIdentitiesHidden() end,
        onDiagnostic = Debug,
    })
    return self.sounds
end

function PA:SyncSounds()
    local registry = self:EnsureSounds()
    if not registry then return end
    local unit = self.active and self.boundUnit or nil
    if unit ~= self.soundUnit then
        registry:RetireAll()
        self.soundUnit = unit
    end
    if not unit then return end
    registry:Sync({
        unit = unit,
        settingKeys = SOUND_KEYS,
        buildSpellIDs = function(settings) return KE.AuraRules.BuildSoundSpellIDs(settings.Allowlist) end,
    }, self.db, self.active)
end

---------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------
-- Frames re-sort after a roster change and a token can name someone else,
-- so the retained unit is dropped before the scan: with names secret the
-- glow goes dark rather than follow the wrong cell.
function PA:OnRoster()
    if self._rosterTimer then return end
    self._rosterTimer = C_Timer.NewTimer(ROSTER_SETTLE, function()
        self._rosterTimer = nil
        if not (self:IsEnabled() and self.active) then return end
        self.resolvedFor = nil
        self:ResolveTarget()
    end)
end

-- Names, the glow host and sound registration all come back reachable here.
function PA:OnRelease()
    if not self.active then return end
    self:ResolveTarget()
    if self.glowPending then self:ApplyGlow() end
    self:SyncSounds()
end

function PA:OnRestrictionChanged()
    C_Timer.After(0, function()
        if self:IsEnabled() then self:OnRelease() end
    end)
end

function PA:EnsureCastFrame()
    if self.castFrame then return self.castFrame end
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function(_, _, _, _, spellID)
        PA:OnPlayerCast(spellID)
    end)
    self.castFrame = f
    return f
end

-- Reached again while active from a profile switch and from world entry, so
-- the second call re-resolves and re-applies rather than returning: the
-- stored name, the allowlist and the glow may all have changed underneath a
-- retained container.
function PA:Activate()
    if not self.active then
        self.active = true
        self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnRoster")
        self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnRelease")
        self:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", "OnRestrictionChanged")
        -- AceEvent has no unit filter, so the player-only cast event lives on
        -- an own frame.
        self:EnsureCastFrame():RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    end
    self:ResolveTarget()
    self:ApplyFilters()
    self:ApplyGlow()
end

-- The ready timer is kept: a spec swap inside the cooldown still owes the
-- deadline. The host's pulse is stopped, since a playing animation costs a
-- C-side update even while the button is hidden; Activate restores it. The
-- stop is best-effort: a refused touch waits for the next cycle.
function PA:Deactivate()
    if not self.active then return end
    self.active = false
    self:UnregisterEvent("GROUP_ROSTER_UPDATE")
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    self:UnregisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
    if self.castFrame then self.castFrame:UnregisterAllEvents() end
    if self._rosterTimer then self._rosterTimer:Cancel(); self._rosterTimer = nil end
    if self.container then
        pcall(self.container.SetEnabled, self.container, false)
        self.container:Hide()
    end
    if self.glowHost then
        pcall(KE.AuraGlow.Configure, self.glowHost, GLOW_OFF)
        self.glowPending = true
    end
    self.boundUnit = nil
    if self.holder then self.holder:Hide() end
    self:SyncSounds()
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
function PA:ApplySettings()
    if not self:IsEnabled() then return end
    self:UpdateDB()
    -- EvaluateGate reaches Activate, which re-resolves the target and
    -- re-applies the filters and the glow.
    self:EvaluateGate()
    if self.active then
        self:ApplyReadyGate()
        self:SyncSounds()
    end
    if self.previewing then self:ShowPreview() end
end

---------------------------------------------------------------------------------
-- Preview: the border on your own raid frame, drawn on a frame of ours (an
-- engine button cannot be made to show an absent aura). "player" is your
-- cell's token only in a party; in a raid you are "raidN". With no group
-- frame on screen a stand-in cell stands where the group frames usually are.
---------------------------------------------------------------------------------
local function PlayerCellUnit()
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local ok, same = pcall(UnitIsUnit, "raid" .. i, "player")
            if ok and KE:IsSafeValue(same) and same == true then return "raid" .. i end
        end
    end
    return "player"
end

function PA:EnsurePreviewCell()
    if self.previewCell then return self.previewCell end
    local cell = CreateFrame("Frame", "KE_PIAssistPreviewCell", UIParent)
    cell:SetSize(72, 46)
    cell:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
    cell:SetFrameStrata("HIGH")
    cell:EnableMouse(false)
    local bg = cell:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(cell)
    bg:SetColorTexture(0.08, 0.08, 0.08, 0.95)
    local hp = cell:CreateTexture(nil, "ARTWORK")
    hp:SetPoint("TOPLEFT", cell, "TOPLEFT", 1, -1)
    hp:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -1, 1)
    hp:SetColorTexture(0.25, 0.25, 0.25, 0.9)
    local name = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("CENTER", cell, "CENTER", 0, 4)
    name:SetText("Raid Frame")
    local sub = cell:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("CENTER", cell, "CENTER", 0, -8)
    sub:SetText("preview")
    cell:Hide()
    self.previewCell = cell
    return cell
end

function PA:ShowPreview()
    self.previewing = true
    local frame = self:FindUnitFrame(PlayerCellUnit()) or self:FindUnitFrame("player")
    if frame then
        if self.previewCell then self.previewCell:Hide() end
    else
        frame = self:EnsurePreviewCell()
        frame:Show()
    end
    if not self.previewHost then
        self.previewHost = CreateFrame("Frame", nil, UIParent)
        self.previewHost:SetFrameStrata("HIGH")
        self.previewHost:EnableMouse(false)
    end
    local ph = self.previewHost
    ph:ClearAllPoints()
    ph:SetAllPoints(frame)
    ph:SetFrameLevel((frame:GetFrameLevel() or 0) + 5)
    ph:Show()
    if not self.previewGlow then
        self.previewGlow = KE.AuraGlow.CreateHost(ph, self.db)
    else
        KE.AuraGlow.Configure(self.previewGlow, self.db)
    end
end

-- Reached while the module is disabled too (the preview manager hides every
-- preview module on a section change), so nothing here reads the db.
function PA:HidePreview()
    self.previewing = false
    if self.previewGlow then KE.AuraGlow.Configure(self.previewGlow, GLOW_OFF) end
    if self.previewHost then self.previewHost:Hide() end
    if self.previewCell then self.previewCell:Hide() end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function PA:OnEnable()
    self:UpdateDB()
    -- Class before anything else: classRestriction gates the preview manager
    -- only, so without this a non-Priest with the module on registers the
    -- gate events for nothing.
    local _, class = UnitClass("player")
    if class ~= "PRIEST" then return end
    if not self.db.Enabled then return end

    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "EvaluateGate")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "EvaluateGate")
    -- Deferred once: the spec is not reliably readable on the frame this runs.
    C_Timer.After(0.5, function()
        if self:IsEnabled() then self:EvaluateGate() end
    end)
end

function PA:OnDisable()
    self:Deactivate()
    self:UnregisterAllEvents()
    self:HidePreview()
end

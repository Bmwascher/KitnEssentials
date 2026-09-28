-- ╔══════════════════════════════════════════════════════════╗
-- ║  PanelScale.lua                                          ║
-- ║  Module: Blizzard Panel Scaling                          ║
-- ║  Purpose: Scales approved Blizzard panels as whole       ║
-- ║           windows and puts their own scale back after.   ║
-- ║  Configured from the Core > CVars > UI Scaling page.     ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class PanelScale: AceModule, AceEvent-3.0
---@field db table?
---@field registry table
---@field resolvedByName table?
---@field frameState table?
---@field hookedFrames table?
---@field pendingFrames table?
---@field regenPending boolean?
---@field globalHooksInstalled boolean?
---@field ownedDB table?
---@field profileReconcilePending boolean?
---@field batchDepth number?
---@field changedVisible boolean?
---@field repositionPending boolean?
local PS = KitnEssentials:NewModule("PanelScale", "AceEvent-3.0")

local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local hooksecurefunc = hooksecurefunc
local issecretvalue = issecretvalue
local math_abs = math.abs
local ipairs = ipairs
local pairs = pairs
local pcall = pcall
local setmetatable = setmetatable
local type = type
local _G = _G

local DEBUG_PS = false

-- GetScale reads back the client's single-precision value, not the number
-- written, so an exact compare would rewrite every root on every pass.
local SCALE_EPSILON = 0.001
local RELEASE, RECONCILE = "RELEASE", "RECONCILE"
local WEAK_KEYS = { __mode = "k" }

PS.registry = KE.PanelScaleRegistry

local KEYS = {
    Core     = { enabled = "CoreEnabled",     override = "CoreOverride",     scale = "CoreScale" },
    Services = { enabled = "ServicesEnabled", override = "ServicesOverride", scale = "ServicesScale" },
    Housing  = { enabled = "HousingEnabled",  override = "HousingOverride",  scale = "HousingScale" },
    Legacy   = { enabled = "LegacyEnabled",   override = "LegacyOverride",   scale = "LegacyScale" },
}

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
function PS:UpdateDB()
    self.db = KE.db and KE.db.profile.PanelScale
end

function PS:IsCategoryActive(category)
    local keys, db = KEYS[category], self.db
    if not (keys and db) then return false end
    return db.Enabled == true and db[keys.enabled] ~= false
end

function PS:GetCategoryScale(category)
    local keys, db = KEYS[category], self.db
    if not db then return 1 end
    if keys and db[keys.override] == true then
        return db[keys.scale] or 1
    end
    return db.Scale or 1
end

-- The combat refusal rule, stated once: a write in combat waits only when
-- the frame is protected or its protection cannot be read.
function PS.DecideMutation(inCombat, protected, protectionSecret)
    if not inCombat then return "APPLY" end
    if protectionSecret or protected == true then return "QUEUE" end
    return "APPLY"
end

function PS:CanMutate(frame)
    if not InCombatLockdown() then return true end
    local protected = frame:IsProtected()
    if issecretvalue(protected) then
        return PS.DecideMutation(true, nil, true) == "APPLY"
    end
    return PS.DecideMutation(true, protected == true, false) == "APPLY"
end

---------------------------------------------------------------------------------
-- Frame State
---------------------------------------------------------------------------------
local function Debug(entry, reason, result, desired)
    if not DEBUG_PS then return end
    KE:Print(("PanelScale %s [%s] %s: %s%s"):format(entry.name, entry.category,
        reason or "-", result, desired and (" at " .. desired) or ""))
end

local function RefreshSkinEdges(frame)
    local skins = KE.Skins
    if skins and skins.RefreshEdgesUnder then
        -- RefreshEdgesUnder calls RefreshEdge bare where SkinAPI's own sweeper
        -- wraps it, so a raise there must not abort this batch.
        pcall(skins.RefreshEdgesUnder, frame)
    end
end

-- The hooks run with no batch open, so opening a panel never repositions the
-- panel manager and never walks the skin cache. Unreadable visibility counts
-- as visible: repositioning a hidden panel is harmless, skipping a shown one
-- leaves its anchor computed for the old scale.
local function Track(frame, result)
    if not PS.batchDepth then return end
    if result ~= "APPLIED" and result ~= "RESTORED" then return end
    if PS:IsVisiblePlain(frame) ~= false then PS.changedVisible = true end
    RefreshSkinEdges(frame)
end

-- A plain frame, not AceEvent: AceAddon unregisters every AceEvent handler
-- straight after OnDisable returns, and a restore queued in combat has to
-- outlive that. Not KE:RunAfterCombat either: that frame stays registered.
local regenWatcher

local function ArmRegen()
    if not regenWatcher then
        regenWatcher = CreateFrame("Frame")
        regenWatcher:SetScript("OnEvent", function() PS:DrainPendingFrames() end)
    end
    if PS.regenPending then return end
    PS.regenPending = true
    regenWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
end

local function EnsureState()
    if PS.frameState then return end
    PS.resolvedByName = {}
    PS.frameState = setmetatable({}, WEAK_KEYS)
    PS.hookedFrames = setmetatable({}, WEAK_KEYS)
    PS.pendingFrames = setmetatable({}, WEAK_KEYS)
end

-- IsShown returns the Shown aspect, and a secret boolean raises on any test.
function PS:IsVisiblePlain(frame)
    local shown = frame:IsShown()
    if issecretvalue(shown) then return nil end
    return shown == true
end

function PS:DesiredScale(frame)
    local state = self.frameState and self.frameState[frame]
    if not state then return nil end
    local category = state.entry.category
    if not self:IsCategoryActive(category) then return nil end
    return self:GetCategoryScale(category)
end

-- The queue holds intent, never a scale: the drain re-derives every value
-- from the settings current when combat ends, and the latest intent wins.
function PS:QueueFrame(frame, intent)
    self.pendingFrames[frame] = intent or RECONCILE
    ArmRegen()
end

function PS:HasPendingReleases()
    if not self.pendingFrames then return false end
    for _, intent in pairs(self.pendingFrames) do
        if intent == RELEASE then return true end
    end
    return false
end

function PS:ReleaseFrame(frame)
    local state = self.frameState[frame]
    if not state then return "SKIPPED" end
    if not self:CanMutate(frame) then
        self:QueueFrame(frame, RELEASE)
        Debug(state.entry, "release", "queued, protected")
        return "QUEUED"
    end
    local result = "RESTORED"
    local current = frame:GetScale()
    if not issecretvalue(current) and math_abs(current - state.baseline) < SCALE_EPSILON then
        result = "SKIPPED"
    else
        frame:SetScale(state.baseline)
    end
    self.frameState[frame] = nil
    self.pendingFrames[frame] = nil
    if self.resolvedByName[state.entry.name] == frame then
        self.resolvedByName[state.entry.name] = nil
    end
    Debug(state.entry, "release", result, state.baseline)
    Track(frame, result)
    return result
end

function PS:ReconcileFrame(frame, reason)
    local state = self.frameState[frame]
    if not state then return "SKIPPED" end
    local desired = self:DesiredScale(frame)
    if not desired then return self:ReleaseFrame(frame) end
    local current = frame:GetScale()
    if issecretvalue(current) then
        Debug(state.entry, reason, "secret scale, kept")
        return "SKIPPED"
    end
    if math_abs(current - desired) < SCALE_EPSILON then return "SKIPPED" end
    if not self:CanMutate(frame) then
        self:QueueFrame(frame, RECONCILE)
        Debug(state.entry, reason, "queued, protected", desired)
        return "QUEUED"
    end
    frame:SetScale(desired)
    Debug(state.entry, reason, "applied", desired)
    Track(frame, "APPLIED")
    return "APPLIED"
end

-- Blizzard's fit and a Show both land here: one lookup, and a write only when
-- something reset the root.
local function Reassert(frame, reason)
    if not PS:IsEnabled() or not PS:DesiredScale(frame) then return end
    PS:ReconcileFrame(frame, reason)
end

local function ManagedFrameOnShow(frame)
    Reassert(frame, "show")
end

function PS:AdoptFrame(entry, frame)
    if not self:IsCategoryActive(entry.category) then
        return self:ReleaseFrame(frame)
    end
    -- Adoption is the newest decision about this frame; anything queued for
    -- it earlier is stale.
    self.pendingFrames[frame] = nil
    self.resolvedByName[entry.name] = frame
    if not self.hookedFrames[frame] then
        self.hookedFrames[frame] = true
        frame:HookScript("OnShow", ManagedFrameOnShow)
    end
    if not self.frameState[frame] then
        local baseline = frame:GetScale()
        if issecretvalue(baseline) then
            Debug(entry, "adopt", "secret baseline, refused")
            return "SKIPPED"
        end
        self.frameState[frame] = { entry = entry, baseline = baseline }
    end
    return self:ReconcileFrame(frame, "adopt")
end

function PS:ResolveEntry(entry)
    local frame = _G[entry.name]
    if type(frame) ~= "table" or type(frame.GetScale) ~= "function" then return end
    local previous = self.resolvedByName[entry.name]
    if previous and previous ~= frame then self:ReleaseFrame(previous) end
    self:AdoptFrame(entry, frame)
end

---------------------------------------------------------------------------------
-- Batches
---------------------------------------------------------------------------------
-- Blizzard anchors a managed panel by dividing its offsets by its scale, so a
-- shown panel whose scale changed needs one panel-manager reposition per
-- batch. Never in combat: UpdateUIPanelPositions has no combat guard of its
-- own, so a reposition due then waits for the drain.
function PS:BeginBatch()
    self.batchDepth = (self.batchDepth or 0) + 1
end

function PS:EndBatch()
    local depth = (self.batchDepth or 1) - 1
    if depth > 0 then
        self.batchDepth = depth
        return
    end
    self.batchDepth = nil
    if not self.changedVisible then return end
    self.changedVisible = nil
    if InCombatLockdown() then
        self.repositionPending = true
        ArmRegen()
        return
    end
    local reposition = _G.UpdateUIPanelPositions
    if reposition then reposition() end
end

function PS:ReconcileAll()
    if not self.frameState then return end
    self:BeginBatch()
    for _, entry in ipairs(self.registry.entries) do
        self:ResolveEntry(entry)
    end
    self.ownedDB = self.db
    self:EndBatch()
end

function PS:ReconcileCategory(category)
    if not self.frameState then return end
    local entries = self.registry.categories[category]
    if not entries then return end
    self:BeginBatch()
    for _, entry in ipairs(entries) do
        self:ResolveEntry(entry)
    end
    self:EndBatch()
end

function PS:ReleaseAllFrames()
    if not self.frameState then return end
    self:BeginBatch()
    for frame in pairs(self.frameState) do
        self:ReleaseFrame(frame)
    end
    self:EndBatch()
end

function PS:DrainPendingFrames()
    self.regenPending = nil
    if regenWatcher then regenWatcher:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    local pending = self.pendingFrames
    self.pendingFrames = setmetatable({}, WEAK_KEYS)
    self:BeginBatch()
    if self.repositionPending then
        self.repositionPending = nil
        self.changedVisible = true
    end
    -- Releases first, so a frame's own scale is back before any new setting
    -- is applied to it.
    for frame, intent in pairs(pending) do
        if intent == RELEASE then self:ReleaseFrame(frame) end
    end
    for frame, intent in pairs(pending) do
        if intent == RECONCILE then self:ReconcileFrame(frame, "regen") end
    end
    -- A profile swap made in combat released first and left its re-adoption
    -- to this drain.
    if self.profileReconcilePending and not self:HasPendingReleases() then
        self.profileReconcilePending = nil
        if self:IsEnabled() then self:ReconcileAll() end
    end
    self:EndBatch()
end

---------------------------------------------------------------------------------
-- Hooks
---------------------------------------------------------------------------------
function PS:InstallGlobalHooks()
    if self.globalHooksInstalled then return end
    self.globalHooksInstalled = true
    if _G.RegisterUIPanel then
        hooksecurefunc("RegisterUIPanel", function(frame) PS:HandleRegisteredPanel(frame) end)
    end
    local frameUtil = _G.FrameUtil
    if frameUtil and frameUtil.UpdateScaleForFitSpecific then
        -- Blizzard resets a fitted panel to 1 here, before it anchors and shows
        -- it, so the configured scale is back before the first frame.
        hooksecurefunc(frameUtil, "UpdateScaleForFitSpecific", function(frame) PS:HandleFit(frame) end)
    end
end

function PS:HandleRegisteredPanel(frame)
    if not self:IsEnabled() or type(frame) ~= "table" or type(frame.GetName) ~= "function" then return end
    local name = frame:GetName()
    if issecretvalue(name) or type(name) ~= "string" then return end
    local entry = self.registry.byName[name]
    if entry then self:ResolveEntry(entry) end
end

function PS:HandleFit(frame)
    if not (self.frameState and self.frameState[frame]) then return end
    Reassert(frame, "fit")
end

function PS:HandleAddonLoaded(addonName)
    local entries = self.registry.byAddon[addonName]
    if not entries then return end
    self:BeginBatch()
    for _, entry in ipairs(entries) do
        self:ResolveEntry(entry)
    end
    self:EndBatch()
end

---------------------------------------------------------------------------------
-- Settings and Lifecycle
---------------------------------------------------------------------------------
-- ProfileManager rebinds every module's db before it calls this, so a profile
-- swap shows only against the table ownership was taken under.
function PS:ApplySettings()
    self:UpdateDB()
    if not self:IsEnabled() or not self.frameState then return end
    local swapped = self.ownedDB ~= nil and self.ownedDB ~= self.db
    self:BeginBatch()
    if swapped then self:ReleaseAllFrames() end
    if self:HasPendingReleases() then
        self.profileReconcilePending = true
    else
        self.profileReconcilePending = nil
        self:ReconcileAll()
    end
    self:EndBatch()
end

function PS:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function PS:OnEnable()
    self:UpdateDB()
    if not self.db or self.db.Enabled ~= true then return end
    EnsureState()
    self:InstallGlobalHooks()
    self:RegisterEvent("ADDON_LOADED", function(_, addonName)
        self:HandleAddonLoaded(addonName)
    end)
    self:ReconcileAll()
end

function PS:OnDisable()
    self:UnregisterAllEvents()
    self:ReleaseAllFrames()
    -- Ownership is gone; the next enable captures under whatever profile is
    -- current then.
    self.ownedDB = nil
    self.profileReconcilePending = nil
end

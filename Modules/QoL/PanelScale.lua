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

local InCombatLockdown = InCombatLockdown
local issecretvalue = issecretvalue

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
-- Lifecycle
---------------------------------------------------------------------------------
function PS:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

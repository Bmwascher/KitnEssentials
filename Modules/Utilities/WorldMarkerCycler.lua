-- ╔══════════════════════════════════════════════════════════╗
-- ║  WorldMarkerCycler.lua                                   ║
-- ║  Module: World Marker Cycler                             ║
-- ║  Purpose: Cycle through world markers at cursor with     ║
-- ║           drag-to-reorder priority.                      ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local WMC = KitnEssentials:NewModule("WorldMarkerCycler", "AceEvent-3.0")

local InCombatLockdown = InCombatLockdown
local IsRaidMarkerActive = IsRaidMarkerActive
local SecureHandlerExecute = SecureHandlerExecute
local SecureHandlerWrapScript = SecureHandlerWrapScript
local SetOverrideBindingClick = SetOverrideBindingClick
local ClearOverrideBindings = ClearOverrideBindings
local CreateFrame = CreateFrame
local string_format = string.format

---------------------------------------------------------------------------------
-- NOTE: Blizzard limits world marker placement/clearing to 3 per second.
-- Markers beyond that rate are silently dropped. This is a server-side
-- restriction and cannot be bypassed.
---------------------------------------------------------------------------------

---------------------------------------------------------------------------------
-- Secure buttons (created at file scope — must exist before combat)
---------------------------------------------------------------------------------
local cycleBtn = CreateFrame("Button", "KE_WorldMarkerCycleBtn", nil, "SecureActionButtonTemplate")
cycleBtn:SetAttribute("type", "macro")
cycleBtn:RegisterForClicks("AnyUp", "AnyDown")
SecureHandlerWrapScript(cycleBtn, "PreClick", cycleBtn, [=[
    if not down or not order or not next(order) then return end
    local pos
    for n = 1, #order do
        if avail[n] then pos = n break end
    end
    -- Nothing free: step past the last placement instead of restarting at the
    -- top, which would re-place one marker forever while priming is running.
    if not pos then
        for n = 1, #order do avail[n] = true end
        pos = (last % #order) + 1
    end
    avail[pos] = false
    last = pos
    self:SetAttribute("macrotext", "/worldmarker [@cursor] " .. order[pos])
]=])

local clearBtn = CreateFrame("Button", "KE_WorldMarkerClearBtn", UIParent, "SecureActionButtonTemplate")
clearBtn:SetAttribute("type", "macro")
clearBtn:SetAttribute("macrotext", "/clearworldmarker 9")
clearBtn:RegisterForClicks("AnyUp", "AnyDown")

local bindingsFrame = CreateFrame("Frame", "KE_WorldMarkerCyclerBindings")

-- Wrapped against cycleBtn to share its secure environment. The reset has to
-- happen inside the protected click: ordinary code cannot reach this state in
-- combat, which is what left the cycle stranded mid-list.
SecureHandlerWrapScript(clearBtn, "PreClick", cycleBtn, [=[
    if not down or not order then return end
    for n = 1, #order do avail[n] = true end
]=])

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function WMC:UpdateDB()
    self.db = KE.db.profile.WorldMarkerCycler
end

function WMC:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

---------------------------------------------------------------------------------
-- Core Logic
---------------------------------------------------------------------------------
function WMC:BuildOrderTable()
    if InCombatLockdown() then
        self.pendingOrderBuild = true
        return
    end

    local db = self.db
    local body = "last=0;order=newtable() "
    if db and db.OrderList then
        for _, id in ipairs(db.OrderList) do
            body = body .. string_format("tinsert(order,%d) ", id)
        end
    end
    SecureHandlerExecute(cycleBtn, body)
    self.pendingOrderBuild = false
    self:PrimeAvailability()
end

-- Rebuilds the believed-free list from the board, so a marker anyone placed or
-- cleared is eventually accounted for. Always sized to the list BuildOrderTable
-- used, which is why the snippets index avail unguarded. Refused in combat:
-- running a snippet from ordinary code errors there.
function WMC:PrimeAvailability()
    if InCombatLockdown() then return end

    local db = self.db
    local list = (db and db.OrderList) or {}
    local body = "avail=newtable() "
    for pos, id in ipairs(list) do
        local free = not IsRaidMarkerActive or not IsRaidMarkerActive(id)
        body = body .. string_format("avail[%d]=%s ", pos, free and "true" or "false")
    end
    SecureHandlerExecute(cycleBtn, body)
end

function WMC:UpdateBindings()
    if InCombatLockdown() then
        self.pendingBindings = true
        return
    end

    ClearOverrideBindings(bindingsFrame)

    local db = self.db
    if not db then return end

    local cycleFullKey = (db.PlaceModifier or "") .. (db.PlaceKey or "")
    local clearFullKey = (db.ClearModifier or "") .. (db.ClearKey or "")

    if cycleFullKey ~= "" then
        SetOverrideBindingClick(bindingsFrame, true, cycleFullKey, cycleBtn:GetName())
    end
    if clearFullKey ~= "" then
        SetOverrideBindingClick(bindingsFrame, true, clearFullKey, clearBtn:GetName())
    end
    self.pendingBindings = false
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
function WMC:ApplySettings()
    self:BuildOrderTable()
    self:UpdateBindings()
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function WMC:OnEnable()
    if not self.db.Enabled then return end
    self:BuildOrderTable()
    self:UpdateBindings()

    -- Listen for combat end to apply pending changes
    self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        -- BuildOrderTable primes as its last step, hence the else.
        if self.pendingOrderBuild then
            self:BuildOrderTable()
        else
            self:PrimeAvailability()
        end
        if self.pendingBindings then
            self:UpdateBindings()
        end
    end)

    self:RegisterEvent("RAID_TARGET_UPDATE", function()
        self:PrimeAvailability()
    end)
end

function WMC:OnDisable()
    -- Teardown must survive a mid-combat disable: the old in-combat skip
    -- also unregistered this module's own regen listener below, so the
    -- override bindings stayed live until /reload. RunAfterCombat runs the
    -- teardown now when possible, else at PLAYER_REGEN_ENABLED. Inverted
    -- gate (like DragonRiding's OnDisable drain): if the module was
    -- re-enabled before the drain, OnEnable already rebuilt the bindings —
    -- do not clobber them.
    KE:RunAfterCombat(function()
        if self:IsEnabled() then return end
        ClearOverrideBindings(bindingsFrame)
    end)
    self:UnregisterAllEvents()
end

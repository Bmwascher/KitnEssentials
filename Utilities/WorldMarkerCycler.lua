-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local WMC = KitnEssentials:NewModule("WorldMarkerCycler", "AceEvent-3.0")

local InCombatLockdown = InCombatLockdown
local SecureHandlerExecute = SecureHandlerExecute
local SecureHandlerWrapScript = SecureHandlerWrapScript
local SetOverrideBindingClick = SetOverrideBindingClick
local ClearOverrideBindings = ClearOverrideBindings
local CreateFrame = CreateFrame
local string_format = string.format

--------------------------------------------------------------------------------
-- NOTE: Blizzard limits world marker placement/clearing to 3 per second.
-- Markers beyond that rate are silently dropped. This is a server-side
-- restriction and cannot be bypassed.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Secure buttons (created at file scope — must exist before combat)
--------------------------------------------------------------------------------
local cycleBtn = CreateFrame("Button", "KE_WorldMarkerCycleBtn", nil, "SecureActionButtonTemplate")
cycleBtn:SetAttribute("type", "macro")
cycleBtn:RegisterForClicks("AnyUp", "AnyDown")
SecureHandlerWrapScript(cycleBtn, "PreClick", cycleBtn, [=[
    if not down or not next(order) then return end
    i = (i % #order) + 1
    local marker = order[i] or 1
    self:SetAttribute("macrotext", "/worldmarker [@cursor] " .. marker)
]=])

local clearBtn = CreateFrame("Button", "KE_WorldMarkerClearBtn", UIParent, "SecureActionButtonTemplate")
clearBtn:SetAttribute("type", "macro")
clearBtn:SetAttribute("macrotext", "/clearworldmarker 9")
clearBtn:RegisterForClicks("AnyUp", "AnyDown")

local bindingsFrame = CreateFrame("Frame", "KE_WorldMarkerCyclerBindings")

-- PostClick on clear resets cycle index
clearBtn:SetScript("PostClick", function()
    if not InCombatLockdown() then
        SecureHandlerExecute(cycleBtn, "i=0")
    end
end)

--------------------------------------------------------------------------------
-- Module methods
--------------------------------------------------------------------------------
function WMC:UpdateDB()
    self.db = KE.db.profile.WorldMarkerCycler
end

function WMC:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function WMC:BuildOrderTable()
    if InCombatLockdown() then
        self.pendingOrderBuild = true
        return
    end

    local db = self.db
    local body = "i=0;order=newtable() "
    if db and db.OrderList then
        for _, id in ipairs(db.OrderList) do
            body = body .. string_format("tinsert(order,%d) ", id)
        end
    end
    SecureHandlerExecute(cycleBtn, body)
    self.pendingOrderBuild = false
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

function WMC:ApplySettings()
    self:BuildOrderTable()
    self:UpdateBindings()
end

function WMC:OnEnable()
    if not self.db.Enabled then return end
    self:BuildOrderTable()
    self:UpdateBindings()

    -- Listen for combat end to apply pending changes
    self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if self.pendingOrderBuild then
            self:BuildOrderTable()
        end
        if self.pendingBindings then
            self:UpdateBindings()
        end
    end)
end

function WMC:OnDisable()
    if not InCombatLockdown() then
        ClearOverrideBindings(bindingsFrame)
        SecureHandlerExecute(cycleBtn, "i=0")
    end
    self:UnregisterAllEvents()
end

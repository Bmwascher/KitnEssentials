-- ╔══════════════════════════════════════════════════════════╗
-- ║  PIMacroBuilder.lua                                      ║
-- ║  Module: Power Infusion Macro Builder                    ║
-- ║  Purpose: Dynamically builds PI macro with trinkets,     ║
-- ║           racials, and potions.                          ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local PI = KitnEssentials:NewModule("PIMacroBuilder", "AceEvent-3.0")

local InCombatLockdown = InCombatLockdown
local GetMacroIndexByName = GetMacroIndexByName
local EditMacro = EditMacro
local CreateMacro = CreateMacro
local UnitName = UnitName
local table_concat = table.concat
local table_insert = table.insert
local tostring = tostring
local ipairs = ipairs
local type = type

-- The glow follows the name the macro carries: every change to that name,
-- and to whether this module manages the macro, is announced here.
local function NotifyAssist()
    local assist = KitnEssentials:GetModule("PIAssist", true)
    if assist and assist.OnTargetChanged then assist:OnTargetChanged() end
end

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function PI:UpdateDB()
    self.db = KE.db.profile.PIMacroBuilder
end

function PI:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

---------------------------------------------------------------------------------
-- Core Logic
---------------------------------------------------------------------------------
function PI:BuildMacroBody()
    local db = self.db
    local targetName = "target"
    if type(db.Target) == "string" and db.Target ~= "" then targetName = db.Target end

    local lines = { "#showtooltip" }
    table_insert(lines, "/cast [@mouseover,help,nodead][@" .. targetName .. ",exists,nodead][] Power Infusion")

    if db.Trinket1 then table_insert(lines, "/use 13") end
    if db.Trinket2 then table_insert(lines, "/use 14") end
    if db.VampiricEmbrace then table_insert(lines, "/use Vampiric Embrace") end

    for _, key in ipairs({ "Racial", "FleetingPotion", "Potion", "Custom" }) do
        local val = db[key]
        if val and val ~= "" then
            table_insert(lines, "/use " .. val)
        end
    end

    return table_concat(lines, "\n")
end

function PI:ApplyMacro()
    if InCombatLockdown() then
        self.pendingMacro = true
        return false
    end

    local db = self.db
    local name = db.MacroName or "PI"
    local icon = db.MacroIcon or 135939
    local body = self:BuildMacroBody()

    local ok, err = pcall(function()
        -- Try to find existing macro by current name
        local mIndex = GetMacroIndexByName(name)
        if mIndex and mIndex > 0 then
            EditMacro(mIndex, name, icon, body)
            return
        end

        -- If we had a previous name, try to rename it
        if self.lastMacroName and self.lastMacroName ~= name then
            local oldIndex = GetMacroIndexByName(self.lastMacroName)
            if oldIndex and oldIndex > 0 then
                EditMacro(oldIndex, name, icon, body)
                return
            end
        end

        -- No existing macro — create new global macro
        CreateMacro(name, icon, body, nil)
    end)

    if not ok then
        KE:Print( "PI macro error: " .. tostring(err))
    elseif self.appliedTarget ~= db.Target then
        self.appliedTarget = db.Target
        NotifyAssist()
    end

    self.lastMacroName = name
    self.pendingMacro = false
    return ok
end

-- Stores the name and rewrites the macro; an empty name clears the slot and
-- the macro falls back to the current target. While the module is on the
-- name is committed only once the macro carries it; off, the name is stored
-- and the macro catches up at enable. An unchanged name is a no-op: the
-- settings edit box fires its callback twice per Enter.
function PI:SetTarget(name)
    self:UpdateDB()
    local clean = type(name) == "string" and name ~= "" and name or nil
    local previous = self.db.Target
    if (clean or "") == (previous or "") then return true end
    if InCombatLockdown() then
        KE:Print("Cannot update the PI target in combat.")
        return false
    end
    self.db.Target = clean or ""
    if self:IsEnabled() then
        local applied = self.appliedTarget
        if not self:ApplyMacro() then
            self.db.Target = previous
            return false
        end
        KE:Print(clean and ("PI macro now targets " .. clean .. ".") or "PI macro target cleared.")
        -- A write that left the applied name alone announced nothing, but
        -- the stored name changed and the page shows both.
        if self.appliedTarget == applied then NotifyAssist() end
    else
        KE:Print((clean and ("PI target stored: " .. clean) or "PI target cleared")
            .. ". PI Macro Builder is off, so the macro is unchanged.")
        -- With the module on, ApplyMacro announced the change.
        NotifyAssist()
    end
    return true
end

function PI:SetPITarget()
    local n = UnitName("mouseover")
    if not KE:IsSafeValue(n) then n = UnitName("target") end
    if not KE:IsSafeValue(n) or n == "" then
        KE:Print("No player under the mouse or targeted.")
        return
    end
    if n == self.db.Target then
        if InCombatLockdown() then
            KE:Print("Cannot update the PI target in combat.")
            return
        end
        -- The name is stored, but the macro may be missing: ApplyMacro
        -- recreates it and reports.
        if not self:IsEnabled() or self:ApplyMacro() then
            KE:Print("PI macro already targets " .. n .. ".")
        end
        return
    end
    self:SetTarget(n)
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
function PI:ApplySettings()
    self:ApplyMacro()
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function PI:OnEnable()
    if not self.db.Enabled then return end

    if not self:ApplyMacro() then NotifyAssist() end

    -- Backward compat: existing macros may contain /run SetPITarget().
    -- The NAME must stay (removing it broke the flow and it had to come back —
    -- users' macro-book macros call it); the enabled gate makes module
    -- disable actually stick.
    _G.SetPITarget = function()
        if PI:IsEnabled() then PI:SetPITarget() end
    end

    self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if self.pendingMacro then
            self:ApplyMacro()
        end
    end)
end

function PI:OnDisable()
    self:UnregisterAllEvents()
    -- The macro stays in the book but is no longer managed here; the
    -- assist falls back to the stored name.
    self.appliedTarget = nil
    NotifyAssist()
end

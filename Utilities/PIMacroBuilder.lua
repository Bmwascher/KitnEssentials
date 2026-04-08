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
function PI:BuildMacroBody(targetName)
    local db = self.db
    targetName = targetName or "target"

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
        return
    end

    local db = self.db
    local name = db.MacroName or "PI"
    local icon = db.MacroIcon or 135939
    local body = self:BuildMacroBody("target")

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
    end

    self.lastMacroName = name
    self.pendingMacro = false
end

function PI:SetPITarget()
    local macroName = self.db.MacroName or "PI"
    local macroIndex = GetMacroIndexByName(macroName)
    if not macroIndex or macroIndex == 0 then
        KE:Print( "|cffFF4444No macro named \"" .. macroName .. "\" found.|r")
        return
    end

    local n = UnitName("mouseover") or UnitName("target") or "target"

    if InCombatLockdown() then
        KE:Print( "Cannot update macro in combat.")
        return
    end

    EditMacro(macroIndex, nil, nil, self:BuildMacroBody(n))
    KE:Print( "PI macro updated to " .. n)
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

    self:ApplyMacro()

    -- Backward compat: existing macros may contain /run SetPITarget()
    _G.SetPITarget = function()
        PI:SetPITarget()
    end

    self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if self.pendingMacro then
            self:ApplyMacro()
        end
    end)
end

function PI:OnDisable()
    self:UnregisterAllEvents()
end

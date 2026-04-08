-- ╔══════════════════════════════════════════════════════════╗
-- ║  FocusMarker.lua                                         ║
-- ║  Module: Focus Marker                                    ║
-- ║  Purpose: Auto-creates a macro for focus targeting and   ║
-- ║           raid marker assignment.                        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local FM = KitnEssentials:NewModule("FocusMarker", "AceEvent-3.0")

local InCombatLockdown = InCombatLockdown
local GetMacroIndexByName = GetMacroIndexByName
local EditMacro = EditMacro
local CreateMacro = CreateMacro
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local C_ChatInfo = C_ChatInfo
local GetSpecialization = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo
local table_concat = table.concat

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
local NO_KICK_SPECS = {
    [102]  = true, -- Balance Druid
    [105]  = true, -- Resto Druid
    [65]   = true, -- Holy Paladin
    [256]  = true, -- Disc Priest
    [257]  = true, -- Holy Priest
    [270]  = true, -- Mistweaver Monk
    [1468] = true, -- Preservation Evoker
}
local table_insert = table.insert
local tostring = tostring

local MACRO_CONDITIONALS_DEFAULT = "[@mouseover,exists,nodead][]"

local NAME_TO_INDEX = {
    Star = 1, Circle = 2, Diamond = 3, Triangle = 4,
    Moon = 5, Square = 6, Cross = 7, Skull = 8, None = 0,
}

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function FM:UpdateDB()
    self.db = KE.db.profile.FocusMarker
end

function FM:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

---------------------------------------------------------------------------------
-- Core Logic
---------------------------------------------------------------------------------
function FM:GetConditionals()
    local cond = self.db.MacroConditionals
    if not cond or cond == "" then
        return MACRO_CONDITIONALS_DEFAULT
    end
    return cond
end

function FM:BuildMacroBody()
    local db = self.db
    local lines = {}
    local cond = self:GetConditionals()
    local idx = NAME_TO_INDEX[db.SelectedMarker] or 0

    -- /focus line (unless mark-only mode)
    if not db.MarkOnly then
        table_insert(lines, "/focus " .. cond)
    end

    -- Build /tm conditional (inject nogroup:raid if enabled)
    local tmCond = cond
    if db.NoRaid then
        local inner = cond:match("^%[(.*)%]$") or cond
        tmCond = "[nogroup:raid," .. inner .. "]"
    end

    -- Anti-toggle line (force clear before re-apply)
    if not db.NoToggle then
        table_insert(lines, "/tm " .. tmCond .. " 0")
    end

    -- Marker line
    table_insert(lines, "/tm " .. tmCond .. " " .. tostring(idx))

    return table_concat(lines, "\n")
end

function FM:ApplyMacro()
    if InCombatLockdown() then
        self.pendingMacro = true
        return
    end

    local db = self.db
    local name = db.MacroName or "FocusMarker"
    local icon = db.MacroIcon or 1033497
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
        KE:Print("FocusMarker macro error: " .. tostring(err))
    end

    self.lastMacroName = name
    self.pendingMacro = false
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
function FM:ApplySettings()
    self:ApplyMacro()
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function FM:OnEnable()
    self:ApplyMacro()

    self:RegisterEvent("READY_CHECK", function()
        local db = self.db
        if not db.AnnounceReadyCheck then return end
        -- Skip announce if current spec has no interrupt
        local specIndex = GetSpecialization()
        if specIndex then
            local specID = GetSpecializationInfo(specIndex)
            if specID and NO_KICK_SPECS[specID] then return end
        end
        if IsInGroup() and not IsInRaid() and not InCombatLockdown() then
            local marker = db.SelectedMarker or "Star"
            local msg = "My Focus Marker is {" .. marker .. "}"
            C_ChatInfo.SendChatMessage(msg, "PARTY")
        end
    end)

    self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if self.pendingMacro then
            self:ApplyMacro()
        end
    end)
end

function FM:OnDisable()
    self:UnregisterAllEvents()
    self.lastMacroName = nil
end

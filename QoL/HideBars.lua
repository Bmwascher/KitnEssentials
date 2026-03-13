-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class HideBars: AceModule, AceEvent-3.0
local HB = KitnEssentials:NewModule("HideBars", "AceEvent-3.0")

local pairs = pairs
local InCombatLockdown = InCombatLockdown
local GetBindingKey = GetBindingKey
local SetBinding = SetBinding
local SaveBindings = SaveBindings
local GetCurrentBindingSet = GetCurrentBindingSet
local CreateFrame = CreateFrame

local VISIBLE_STATE = "[petbattle]hide;show"
local HIDDEN_STATE = "hide"
local barsHidden = false
local toggleButton

function HB:UpdateDB()
    self.db = KE.db.profile.HideBars
end

function HB:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function HB:ToggleBars()
    if not self.db or not self.db.Enabled then return end
    if InCombatLockdown() then return end
    if not ElvUI then return end

    local E = unpack(ElvUI)
    if not E or not E.db or not E.db.actionbar then return end

    barsHidden = not barsHidden

    for barId, enabled in pairs(self.db.Bars) do
        if enabled then
            local barKey = "bar" .. barId
            if E.db.actionbar[barKey] then
                E.db.actionbar[barKey].visibility = barsHidden and HIDDEN_STATE or VISIBLE_STATE
                if E.ActionBars and E.ActionBars.PositionAndSizeBar then
                    E.ActionBars:PositionAndSizeBar(barKey)
                end
            end
        end
    end
end

function HB:CreateToggleButton()
    if toggleButton then return end
    toggleButton = CreateFrame("Button", "KE_HideBarsToggle", UIParent, "SecureActionButtonTemplate")
    toggleButton:SetAttribute("type", "macro")
    toggleButton:SetAttribute("macrotext", "")
    toggleButton:RegisterForClicks("AnyDown")
    toggleButton:SetScript("PreClick", function()
        if not InCombatLockdown() then
            HB:ToggleBars()
        end
    end)
end

function HB:ApplyKeybind()
    if not self.db then return end
    if InCombatLockdown() then return end

    self:CreateToggleButton()

    local key = self.db.Keybind
    if not key or key == "" then return end

    local old1, old2 = GetBindingKey("CLICK KE_HideBarsToggle:LeftButton")
    if old1 then SetBinding(old1) end
    if old2 then SetBinding(old2) end

    SetBinding(key, "CLICK KE_HideBarsToggle:LeftButton")
    SaveBindings(GetCurrentBindingSet())
end

function HB:ClearKeybind()
    if InCombatLockdown() then return end

    local old1, old2 = GetBindingKey("CLICK KE_HideBarsToggle:LeftButton")
    if old1 then SetBinding(old1) end
    if old2 then SetBinding(old2) end
    SaveBindings(GetCurrentBindingSet())

    if self.db then
        self.db.Keybind = ""
    end
end

function HB:ApplySettings()
    self:ApplyKeybind()
end

function HB:OnEnable()
    self:CreateToggleButton()
    C_Timer.After(1, function()
        self:ApplyKeybind()
    end)
end

function HB:OnDisable()
    self:ClearKeybind()
end

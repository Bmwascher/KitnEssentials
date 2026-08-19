-- ╔══════════════════════════════════════════════════════════╗
-- ║  VehicleExit.lua                                         ║
-- ║  Module: Vehicle Exit Button                             ║
-- ║  Purpose: Places Blizzard's vehicle exit button.         ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class VehicleExit: AceModule, AceEvent-3.0
local VE = KitnEssentials:NewModule("VehicleExit", "AceEvent-3.0")

local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer
local UnitInVehicle = UnitInVehicle
local pcall = pcall
local _G = _G

-- Blizzard registers this button as an Edit Mode system, and some action bar
-- addons re-pin it in a run-once setup at login -- which is why an Edit Mode
-- placement looks right until the next reload. Both writes happen once and
-- nothing re-asserts them, so being the last writer settles it.
--
-- OFF by default: with it off the button's position is never touched.
local BUTTON_NAME = "MainMenuBarVehicleLeaveButton"

-- Late enough to land after another addon's bar setup, which runs from its own
-- OnEnable. A timer because there is no event for "the bars are laid out".
local APPLY_DELAY = 3

function VE:UpdateDB()
    self.db = KE.db.profile.VehicleExit
end

function VE:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function VE:Button()
    return _G[BUTTON_NAME]
end

function VE:ApplyPosition()
    local button = self:Button()
    if not button then return end

    -- Blizzard drives this button's shown state through Edit Mode's protected
    -- ShowBase/HideBase. Moving it is a different call, but the cost of being
    -- wrong is a blocked action mid-fight and the cost of waiting is nothing.
    if InCombatLockdown() then
        self.pending = true
        return
    end
    self.pending = nil

    KE:ApplyFramePosition(button, self.db.Position, self.db)
end

function VE:OnEnable()
    self:UpdateDB()

    self:RegisterEvent("PLAYER_ENTERING_WORLD", "ScheduleApply")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnRegenEnabled")
    self:ScheduleApply()

    if not KE.EditMode then return end
    -- Registered by name: the button belongs to Blizzard_ActionBar and is
    -- resolved when the overlay is built. getParentFrame is load-bearing here
    -- rather than boilerplate -- with Anchor To Frame pointed at an action bar,
    -- the drag has to compute offsets against that frame or the button jumps.
    KE.EditMode:RegisterElement({
        key = "VehicleExit",
        module = self,
        displayName = "Vehicle Exit Button",
        frameName = BUTTON_NAME,
        guiPath = "VehicleExit",
        getPosition = function() return self.db.Position end,
        setPosition = function(pos)
            local p = self.db.Position
            p.AnchorFrom = pos.AnchorFrom
            p.AnchorTo   = pos.AnchorTo
            p.XOffset    = pos.XOffset
            p.YOffset    = pos.YOffset
            self:ApplyPosition()
        end,
        getParentFrame = function()
            return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) or _G.UIParent
        end,
    })
end

function VE:OnDisable()
    self:UnregisterAllEvents()
    self.pending = nil
    if KE.EditMode then KE.EditMode:UnregisterElement("VehicleExit") end
    -- Deliberately not restoring the previous position: we do not know which
    -- owner the player wants. A reload puts it back where its owner places it.
end

function VE:ScheduleApply()
    C_Timer.After(APPLY_DELAY, function()
        if self:IsEnabled() then self:ApplyPosition() end
    end)
end

function VE:OnRegenEnabled()
    if self.pending then self:ApplyPosition() end
end

-- The button is hidden unless the player is in a vehicle, so there is nothing
-- to place against while the options page is open. Blizzard's own Edit Mode
-- shows the Talking Head frame the same way.
function VE:ShowPreview()
    if InCombatLockdown() then return end
    local button = self:Button()
    if not button then return end
    self.isPreview = true
    self:ApplyPosition()
    -- pcall: Show routes through Edit Mode's protected base show/hide, so it
    -- can be refused even out of combat.
    pcall(button.Show, button)
end

function VE:HidePreview()
    if not self.isPreview then return end
    self.isPreview = nil
    if InCombatLockdown() then return end
    local button = self:Button()
    if not button then return end
    -- Not while the player is actually in a vehicle -- that would take away a
    -- button they need.
    if not (UnitInVehicle and UnitInVehicle("player")) then
        pcall(button.Hide, button)
    end
end

function VE:Refresh()
    self:UpdateDB()
    self:ApplyPosition()
end

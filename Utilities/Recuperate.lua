-- ╔══════════════════════════════════════════════════════════╗
-- ║  Recuperate.lua                                          ║
-- ║  Module: Recuperate Button                               ║
-- ║  Purpose: One-click self-heal button with configurable   ║
-- ║           raid/party visibility and health-based alpha.  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class Recuperate: AceModule, AceEvent-3.0
local REC = KitnEssentials:NewModule("Recuperate", "AceEvent-3.0")

local CreateFrame = CreateFrame
local RegisterStateDriver = RegisterStateDriver
local UnregisterStateDriver = UnregisterStateDriver
local UnitHealthPercent = UnitHealthPercent
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local C_Spell = C_Spell
local InCombatLockdown = InCombatLockdown

local RECUPERATE_SPELL_ID = 1231411
local spellInfo = C_Spell.GetSpellInfo(RECUPERATE_SPELL_ID)

REC.isPreview = false

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function REC:UpdateDB()
    self.db = KE.db.profile.Recuperate
end

function REC:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

---------------------------------------------------------------------------------
-- Core Logic
---------------------------------------------------------------------------------
function REC:UpdateAlpha()
    if self.isPreview then return end
    if not self.button then return end

    if UnitIsDeadOrGhost("player") then
        self.button:SetAlpha(0)
        return
    end

    -- UnitHealthPercent with curve handles secret values safely.
    -- Returns 1 when missing health, 0 when full. The curve only has number
    -- outputs (HealthMissingAlpha:AddPoint takes numbers), so the LS-narrow
    -- to number is correct — without the @type, alpha is typed as
    -- `number | colorRGBA` because UnitHealthPercent's stub return is
    -- LuaCurveEvaluatedResult, which is polymorphic across curve types.
    ---@type number
    local alpha = UnitHealthPercent("player", true, KE.curves.HealthMissingAlpha)
    self.button:SetAlpha(alpha)
end

function REC:OnHealthChange(_, unit)
    if unit ~= "player" then return end
    if self.isPreview then return end
    self:UpdateAlpha()
end

---------------------------------------------------------------------------------
-- Visibility State Driver
---------------------------------------------------------------------------------
function REC:GetVisibilityString()
    local loadInRaid = self.db.LoadInRaid
    local loadInParty = self.db.LoadInParty

    -- Neither enabled - always hide
    if not loadInRaid and not loadInParty then
        return "hide"
    end

    -- Both enabled - show in any group
    if loadInRaid and loadInParty then
        return "[combat] hide; [nogroup] hide; [dead] hide; show"
    end

    -- Only raid - hide if not in raid
    if loadInRaid then
        return "[combat] hide; [nogroup:raid] hide; [dead] hide; show"
    end

    -- Only party - hide in raid, hide if no group
    return "[combat] hide; [group:raid] hide; [nogroup] hide; [dead] hide; show"
end

function REC:UpdateStateDriver()
    if not self.button then return end
    if self.isPreview then return end

    UnregisterStateDriver(self.button, "visibility")
    RegisterStateDriver(self.button, "visibility", self:GetVisibilityString())
    self:UpdateAlpha()
end

---------------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------------
function REC:CreateButton()
    if self.button then return end

    local button = CreateFrame("Button", "KE_RecuperateButton", UIParent,
        "SecureActionButtonTemplate, SecureHandlerStateTemplate")
    button:SetSize(self.db.Size, self.db.Size)
    button:Hide()

    -- Register state driver for visibility
    RegisterStateDriver(button, "visibility", self:GetVisibilityString())

    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetAttribute("type", "spell")
    button:SetAttribute("spell", RECUPERATE_SPELL_ID)

    -- Icon
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints(button)
    KE:ApplyIconZoom(button.icon)
    if spellInfo and spellInfo.iconID then
        button.icon:SetTexture(spellInfo.iconID)
    end

    KE:AddIconBorders(button)

    -- Highlight
    button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
    button.highlight:SetAllPoints(button)
    button.highlight:SetColorTexture(1, 1, 1, 0.2)
    button.highlight:SetBlendMode("ADD")

    self.button = button
    self:ApplySettings()
    return button
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
function REC:ApplySettings()
    if not self.button then return end
    if InCombatLockdown() then return end
    self.button:SetSize(self.db.Size, self.db.Size)
    KE:ApplyFramePosition(self.button, self.db.Position, self.db)
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function REC:OnEnable()
    if not self.db.Enabled then return end
    self:CreateButton()
    self:RegWithEditMode()
    C_Timer.After(0.5, function()
        self:ApplySettings()
    end)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "UpdateAlpha")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "UpdateAlpha")
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "UpdateAlpha")
    self:RegisterEvent("UNIT_HEALTH", "OnHealthChange")
    self:RegisterEvent("PLAYER_DEAD", "UpdateAlpha")
    self:RegisterEvent("PLAYER_UNGHOST", "UpdateAlpha")
    self:UpdateAlpha()
end

function REC:OnDisable()
    self:UnregisterAllEvents()
    if self.button then
        UnregisterStateDriver(self.button, "visibility")
        self.button:Hide()
    end
    self.isPreview = false
end

---------------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------------
function REC:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "Recuperate", displayName = "Recuperate", frame = self.button,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos) self.db.Position = pos; KE:ApplyFramePosition(self.button, self.db.Position, self.db) end,
            getParentFrame = function() return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) end,
            guiPath = "Recuperate",
        })
        self.editModeRegistered = true
    end
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------
function REC:ShowPreview()
    if not self.button then self:CreateButton() end
    self:RegWithEditMode()
    self.isPreview = true
    UnregisterStateDriver(self.button, "visibility")
    self.button:SetAlpha(1)
    self.button:Show()
    self:ApplySettings()
end

function REC:HidePreview()
    self.isPreview = false
    if not self.button then return end
    if self.db.Enabled then
        RegisterStateDriver(self.button, "visibility", self:GetVisibilityString())
        self:UpdateAlpha()
    else
        self.button:Hide()
    end
end

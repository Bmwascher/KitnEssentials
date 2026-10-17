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
REC.inCombat = false

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

-- The state driver shows the button only while grouped and out of combat, so
-- the player's health is heard only then; the roster and regen handlers
-- repaint when that state begins.
function REC:SyncHealthEvent()
    local want = self:IsEnabled() and IsInGroup() and not self.inCombat
    if want then
        if not self.healthFrame then
            local f = CreateFrame("Frame")
            f:SetScript("OnEvent", function(_, event, unit) self:OnHealthChange(event, unit) end)
            self.healthFrame = f
        end
        if not self._healthListening then
            self._healthListening = true
            self.healthFrame:RegisterUnitEvent("UNIT_HEALTH", "player")
        end
    elseif self._healthListening then
        self._healthListening = false
        self.healthFrame:UnregisterEvent("UNIT_HEALTH")
    end
end

function REC:OnGroupOrWorld()
    self:SyncHealthEvent()
    self:UpdateAlpha()
end

function REC:OnRegenDisabled()
    self.inCombat = true
    self:SyncHealthEvent()
end

function REC:OnRegenEnabled()
    self.inCombat = false
    self:SyncHealthEvent()
    self:UpdateAlpha()
end

---------------------------------------------------------------------------------
-- Visibility State Driver
---------------------------------------------------------------------------------
-- NOTE: deliberately NO [dead] conditional in any of these strings. Dead/ghost
-- state derives from health, so a [dead] clause makes Blizzard's SecureStateDriver
-- manager re-evaluate the whole driver on every player health-change event (heaviest
-- during post-combat health regen) -- a large amount of secure-environment churn for
-- a button that's already hidden when dead: REC:UpdateAlpha sets alpha 0 on
-- UnitIsDeadOrGhost (wired to PLAYER_DEAD / PLAYER_UNGHOST). Don't re-add [dead].
function REC:GetVisibilityString()
    local loadInRaid = self.db.LoadInRaid
    local loadInParty = self.db.LoadInParty

    -- Neither enabled - always hide
    if not loadInRaid and not loadInParty then
        return "hide"
    end

    -- Both enabled - show in any group
    if loadInRaid and loadInParty then
        return "[combat] hide; [nogroup] hide; show"
    end

    -- Only raid - hide if not in raid
    if loadInRaid then
        return "[combat] hide; [nogroup:raid] hide; show"
    end

    -- Only party - hide in raid, hide if no group
    return "[combat] hide; [group:raid] hide; [nogroup] hide; show"
end

function REC:UpdateStateDriver()
    if not self.button then return end
    if self.isPreview then return end
    KE:RunAfterCombat(function()
        if self.isPreview or not self.button then return end
        UnregisterStateDriver(self.button, "visibility")
        RegisterStateDriver(self.button, "visibility", self:GetVisibilityString())
        self:UpdateAlpha()
    end)
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
    KE:RunAfterCombat(function()
        if not self:IsEnabled() then return end
        self:CreateButton()
        self:RegWithEditMode()
    end)
    C_Timer.After(0.5, function()
        self:ApplySettings()
    end)
    -- A fight already under way fired its PLAYER_REGEN_DISABLED before this.
    self.inCombat = UnitAffectingCombat("player") and true or false
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnGroupOrWorld")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnRegenDisabled")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnRegenEnabled")
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnGroupOrWorld")
    self:RegisterEvent("PLAYER_DEAD", "UpdateAlpha")
    self:RegisterEvent("PLAYER_UNGHOST", "UpdateAlpha")
    self:SyncHealthEvent()
    self:UpdateAlpha()
end

function REC:OnDisable()
    self:UnregisterAllEvents()
    if self.healthFrame then self.healthFrame:UnregisterAllEvents() end
    self._healthListening = false
    self.isPreview = false
    if self.button then
        KE:RunAfterCombat(function()
            if self:IsEnabled() or not self.button then return end
            UnregisterStateDriver(self.button, "visibility")
            self.button:Hide()
        end)
    end
end

---------------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------------
function REC:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "Recuperate", displayName = "Recuperate", frame = self.button,
            module = self,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos) self.db.Position = pos; KE:ApplyFramePosition(self.button, self.db.Position, self.db) end,
            getParentFrame = function() return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) end,
            -- Recuperate has no sidebar row of its own -- guiTab opens
            -- straight to its tab under Class Tools.
            guiPath = "ClassTools",
            guiTab = "Recuperate",
        })
        self.editModeRegistered = true
    end
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------
function REC:ShowPreview()
    if InCombatLockdown() then return end
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
    KE:RunAfterCombat(function()
        if self.isPreview or not self.button then return end
        if self.db.Enabled then
            RegisterStateDriver(self.button, "visibility", self:GetVisibilityString())
            self:UpdateAlpha()
        else
            self.button:Hide()
        end
    end)
end

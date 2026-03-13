-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class Recuperate: AceModule, AceEvent-3.0
local REC = KitnEssentials:NewModule("Recuperate", "AceEvent-3.0")

local CreateFrame = CreateFrame
local RegisterStateDriver = RegisterStateDriver
local UnregisterStateDriver = UnregisterStateDriver
local UnitHealthPercent = UnitHealthPercent
local C_Spell = C_Spell

local RECUPERATE_SPELL_ID = 1231411
local spellInfo = C_Spell.GetSpellInfo(RECUPERATE_SPELL_ID)

REC.isPreview = false

--------------------------------------------------------------------------------
-- Inline helpers (KE has no core ApplyZoom/AddBorders)
--------------------------------------------------------------------------------
local function ApplyZoom(texture, zoom)
    local texMin = 0.25 * zoom
    local texMax = 1 - 0.25 * zoom
    texture:SetTexCoord(texMin, texMax, texMin, texMax)
end

local function AddBorders(frame, color)
    local r, g, b, a = color[1], color[2], color[3], color[4] or 1

    local top = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    top:SetHeight(1)
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    top:SetColorTexture(r, g, b, a)
    top:SetTexelSnappingBias(0)
    top:SetSnapToPixelGrid(false)

    local bottom = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    bottom:SetHeight(1)
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    bottom:SetColorTexture(r, g, b, a)
    bottom:SetTexelSnappingBias(0)
    bottom:SetSnapToPixelGrid(false)

    local left = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    left:SetWidth(1)
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    left:SetColorTexture(r, g, b, a)
    left:SetTexelSnappingBias(0)
    left:SetSnapToPixelGrid(false)

    local right = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    right:SetWidth(1)
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    right:SetColorTexture(r, g, b, a)
    right:SetTexelSnappingBias(0)
    right:SetSnapToPixelGrid(false)
end

--------------------------------------------------------------------------------
-- DB
--------------------------------------------------------------------------------
function REC:UpdateDB()
    self.db = KE.db.profile.Recuperate
end

function REC:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

--------------------------------------------------------------------------------
-- Health alpha (linear: 1 when missing health, 0 when full)
--------------------------------------------------------------------------------
function REC:UpdateAlpha()
    if self.isPreview then return end
    if not self.button then return end
    local alpha = UnitHealthPercent("player", true)
    self.button:SetAlpha(alpha)
end

function REC:OnHealthChange(_, unit)
    if unit ~= "player" then return end
    if self.isPreview then return end
    self:UpdateAlpha()
end

--------------------------------------------------------------------------------
-- Create button
--------------------------------------------------------------------------------
function REC:CreateButton()
    if self.button then return end

    local button = CreateFrame("Button", "KE_RecuperateButton", UIParent,
        "SecureActionButtonTemplate, SecureHandlerStateTemplate")
    button:SetSize(self.db.Size, self.db.Size)
    button:Hide()

    RegisterStateDriver(button, "visibility", "[combat] hide; [nogroup:raid] hide; [dead] hide; show")

    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetAttribute("type", "spell")
    button:SetAttribute("spell", RECUPERATE_SPELL_ID)

    -- Icon
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints(button)
    ApplyZoom(button.icon, 0.3)
    if spellInfo and spellInfo.iconID then
        button.icon:SetTexture(spellInfo.iconID)
    end

    AddBorders(button, { 0, 0, 0, 1 })

    -- Highlight
    button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
    button.highlight:SetAllPoints(button)
    button.highlight:SetColorTexture(1, 1, 1, 0.2)
    button.highlight:SetBlendMode("ADD")

    self.button = button
    self:ApplySettings()
    return button
end

--------------------------------------------------------------------------------
-- Apply / Enable / Disable
--------------------------------------------------------------------------------
function REC:ApplySettings()
    if not self.button then return end
    if InCombatLockdown() then return end
    self.button:SetSize(self.db.Size, self.db.Size)
    KE:ApplyFramePosition(self.button, self.db.Position, self.db)
end

function REC:OnEnable()
    if not self.db.Enabled then return end
    self:CreateButton()
    self:RegWithEditMode()
    C_Timer.After(0.5, function()
        self:ApplySettings()
    end)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "UpdateAlpha")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "UpdateAlpha")
    self:RegisterEvent("UNIT_HEALTH", "OnHealthChange")
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

--------------------------------------------------------------------------------
-- Edit Mode
--------------------------------------------------------------------------------
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

--------------------------------------------------------------------------------
-- Preview
--------------------------------------------------------------------------------
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
        RegisterStateDriver(self.button, "visibility",
            "[combat] hide; [nogroup:raid] hide; [dead] hide; show")
        self:UpdateAlpha()
    else
        self.button:Hide()
    end
end

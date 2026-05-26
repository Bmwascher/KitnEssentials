-- ╔══════════════════════════════════════════════════════════╗
-- ║  AuraExternals.lua                                       ║
-- ║  Module: Aura Externals                                  ║
-- ║  Purpose: Displays external defensives cast on the       ║
-- ║           player (Pain Suppression, Ironbark, etc.) with ║
-- ║           optional PixelGlow on big defensives.          ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class AuraExternals: AceModule, AceEvent-3.0
local AX = KitnEssentials:NewModule("AuraExternals", "AceEvent-3.0")

local C_UnitAuras   = C_UnitAuras
local CreateFrame   = CreateFrame
local UIParent      = UIParent
local GameTooltip   = GameTooltip
local pairs, ipairs = pairs, ipairs
local tinsert       = table.insert
local tsort         = table.sort
local math_min      = math.min
local math_floor    = math.floor
local LCG           = LibStub("LibCustomGlow-1.0", true)

local UNIT = "player"

AX.buttons = {}
AX.frame = nil
AX.editModeRegistered = false
AX.isPreview = false

local FILTERS = {
    { filter = "HELPFUL|EXTERNAL_DEFENSIVE", filterPlayer = "HELPFUL|EXTERNAL_DEFENSIVE|PLAYER", isBig = false },
    { filter = "HELPFUL|BIG_DEFENSIVE",      filterPlayer = "HELPFUL|BIG_DEFENSIVE|PLAYER",      isBig = true },
}

local PREVIEW_AURAS = {
    { spellId = 33206,  icon = 135936, duration = 8 },   -- Pain Suppression
    { spellId = 102342, icon = 572025, duration = 12 },  -- Ironbark
    { spellId = 47788,  icon = 135966, duration = 9 },   -- Guardian Spirit
}

function AX:UpdateDB()
    self.db = KE.db.profile.AuraExternals
end

function AX:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function AX:OnEnable()
    self:UpdateDB()
    if not self.frame then self:CreateContainer() end
    self:RegisterEvent("UNIT_AURA", "OnUnitAura")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "Refresh")
    self:Refresh()
end

function AX:OnDisable()
    self:UnregisterAllEvents()
    if self.frame then self.frame:Hide() end
end

function AX:ApplySettings()
    self:UpdateDB()
    if self.frame then
        KE:ApplyFramePositionWithSnap(self.frame, self.db.Position, self.db)
        self.frame:SetFrameStrata(self.db.Strata or "MEDIUM")
    end
    self:Refresh()
end

function AX:CreateContainer()
    if self.frame then return end
    local frame = CreateFrame("Frame", "KE_AuraExternals", UIParent)
    frame:SetSize(1, 1)
    frame:SetFrameStrata(self.db.Strata or "MEDIUM")
    self.frame = frame
    KE:ApplyFramePositionWithSnap(frame, self.db.Position, self.db)
    self:RegWithEditMode()
end

function AX:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key         = "AuraExternals",
            displayName = "Aura Externals",
            frame       = self.frame,
            getPosition = function()
                return self.db.Position
            end,
            setPosition = function(pos)
                self.db.Position = pos
                KE:ApplyFramePositionWithSnap(self.frame, self.db.Position, self.db)
            end,
            getParentFrame = function()
                return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)
            end,
            guiPath = "AuraExternals",
        })
        self.editModeRegistered = true
    end
end

local function OnButtonEnter(button)
    if not button.auraInstanceID then return end
    GameTooltip:SetOwner(button, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetUnitAuraByAuraInstanceID(UNIT, button.auraInstanceID)
    GameTooltip:Show()
end

local function OnButtonLeave()
    GameTooltip:Hide()
end

local function CreateButton(parent, db)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(db.IconSize, db.IconSize)
    b:EnableMouse(true)
    b:SetScript("OnEnter", OnButtonEnter)
    b:SetScript("OnLeave", OnButtonLeave)

    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(b)
    KE:ApplyIconZoom(tex, db.IconZoom)
    b.icon = tex

    KE:AddIconBorders(b, db.BorderColor)

    local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    cd:SetAllPoints(b)
    cd:SetDrawEdge(false)
    cd:SetReverse(db.Reverse)
    cd:SetHideCountdownNumbers(true)
    b.cooldown = cd

    local timer = b:CreateFontString(nil, "OVERLAY")
    KE:ApplyFontToText(timer, db.FontFace, db.TimerFontSize, db.FontOutline)
    local tp = db.TimerPosition
    timer:SetPoint(tp.AnchorFrom, b, tp.AnchorTo, tp.XOffset, tp.YOffset)
    b.timer = timer

    return b
end

function AX:GetOrCreateButton(index)
    local b = self.buttons[index]
    if b then return b end
    b = CreateButton(self.frame, self.db)
    self.buttons[index] = b
    return b
end

local function ScanFilter(filterStr, into, isBig)
    local i = 1
    while true do
        local data = C_UnitAuras.GetAuraDataByIndex(UNIT, i, filterStr)
        if not data then break end
        tinsert(into, {
            auraInstanceID = data.auraInstanceID,
            spellId        = data.spellId,
            icon           = data.icon,
            duration       = data.duration,
            expirationTime = data.expirationTime,
            isBig          = isBig,
        })
        i = i + 1
    end
end

function AX:CollectAuras()
    local list = {}
    local db = self.db
    for _, f in ipairs(FILTERS) do
        if not (f.isBig and not db.ShowBigDefensives) then
            ScanFilter(f.filter, list, f.isBig)
            if db.IncludeSelfCast then
                ScanFilter(f.filterPlayer, list, f.isBig)
            end
        end
    end
    tsort(list, function(a, b) return (a.expirationTime or 0) < (b.expirationTime or 0) end)
    return list
end

function AX:Refresh()
    if not self.frame then return end
    local db = self.db
    if not db.Enabled and not self.isPreview then
        for _, b in pairs(self.buttons) do b:Hide() end
        return
    end

    local auras = self.isPreview and PREVIEW_AURAS or self:CollectAuras()
    local cap = math_min(#auras, (db.IconsPerRow or 6) * (db.MaxRows or 1))

    for i = 1, cap do
        local aura = auras[i]
        local b = self:GetOrCreateButton(i)
        b.auraInstanceID = aura.auraInstanceID
        b.icon:SetTexture(aura.icon)
        if aura.duration and aura.duration > 0 and aura.expirationTime then
            b.cooldown:SetCooldown(aura.expirationTime - aura.duration, aura.duration)
        else
            b.cooldown:Clear()
        end

        if db.GlowEnabled and aura.isBig and LCG then
            LCG.PixelGlow_Start(b, db.GlowColor, nil, nil, nil, nil, nil, nil, nil, nil)
        elseif LCG then
            LCG.PixelGlow_Stop(b)
        end

        b:Show()
    end

    for i = cap + 1, #self.buttons do
        self.buttons[i]:Hide()
    end

    self:LayoutButtons(cap)
end

function AX:LayoutButtons(count)
    local db = self.db
    local dx = (db.IconSize + db.IconSpacing) * (db.GrowHorizontal == "LEFT" and -1 or 1)
    local dy = (db.IconSize + db.IconSpacing) * (db.GrowVertical == "UP" and 1 or -1)
    local perRow = db.IconsPerRow or 6

    for i = 1, count do
        local b = self.buttons[i]
        local row = math_floor((i - 1) / perRow)
        local col = (i - 1) % perRow
        b:ClearAllPoints()
        b:SetPoint("CENTER", self.frame, "CENTER", col * dx, row * dy)
    end
end

function AX:OnUnitAura(_, unit)
    if unit ~= UNIT then return end
    self:Refresh()
end

function AX:ShowPreview()
    self.isPreview = true
    if not self.frame then self:CreateContainer() end
    self.frame:Show()
    self:Refresh()
end

function AX:HidePreview()
    self.isPreview = false
    self:Refresh()
end

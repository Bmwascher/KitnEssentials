-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class SkinAuras: AceModule, AceEvent-3.0, AceHook-3.0
local SK = KitnEssentials:NewModule("SkinAuras", "AceEvent-3.0", "AceHook-3.0")

-- Localization
local CreateFrame = CreateFrame
local pairs = pairs
local unpack = unpack
local hooksecurefunc = hooksecurefunc
local C_Timer = C_Timer

function SK:UpdateDB()
    self.db = KE.db.profile.Skinning.Auras
end

function SK:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

-- Icon zoom (same as MissingBuffs, BuffIcons, etc.)
local function ApplyZoom(tex, zoom)
    local texMin = 0.25 * zoom
    local texMax = 1 - 0.25 * zoom
    tex:SetTexCoord(texMin, texMax, texMin, texMax)
end

-- Create 1px pixel border overlay on an aura frame
local function BorderOverlay(aura, borderColor)
    if not aura.PixelBorder then
        local auraBorder = CreateFrame("Frame", nil, aura)
        auraBorder:SetAllPoints(aura.Icon)
        auraBorder:SetFrameLevel(aura:GetFrameLevel() - 1)
        aura.PixelBorder = auraBorder
        aura.PixelBorder.edges = {}

        local function Edge(parent)
            return parent:CreateTexture(nil, "OVERLAY")
        end

        local edges = {}

        edges.top = Edge(auraBorder)
        edges.top:SetPoint("TOPLEFT", 0, 0)
        edges.top:SetPoint("TOPRIGHT", 0, 0)
        edges.top:SetHeight(1)

        edges.bottom = Edge(auraBorder)
        edges.bottom:SetPoint("BOTTOMLEFT", 0, 0)
        edges.bottom:SetPoint("BOTTOMRIGHT", 0, 0)
        edges.bottom:SetHeight(1)

        edges.left = Edge(auraBorder)
        edges.left:SetPoint("TOPLEFT", 0, 0)
        edges.left:SetPoint("BOTTOMLEFT", 0, 0)
        edges.left:SetWidth(1)

        edges.right = Edge(auraBorder)
        edges.right:SetPoint("TOPRIGHT", 0, 0)
        edges.right:SetPoint("BOTTOMRIGHT", 0, 0)
        edges.right:SetWidth(1)

        aura.PixelBorder.edges = edges
    end

    for _, edge in pairs(aura.PixelBorder.edges) do
        edge:SetColorTexture(unpack(borderColor))
    end
end

-- Style aura icons (buffs/debuffs)
local function StyleAuraFrame(aura, size, borderColor)
    if aura.isAuraAnchor or not aura.Icon then return end
    local auraIcon, auraDuration, auraCount = aura.Icon, aura.Duration, aura.Count
    local auraBorder = aura.DebuffBorder or aura.BuffBorder
    local fontOutline = SK.db.FontOutline

    auraIcon:SetSize(size, size)
    if auraBorder then auraBorder:SetTexture(nil) end
    BorderOverlay(aura, borderColor)
    ApplyZoom(auraIcon, 0.3)

    local auraW, auraH = aura:GetSize()
    if auraW and auraH and auraW > 0 and auraH > 0 then
        aura.PixelBorder:ClearAllPoints()
        aura.PixelBorder:SetPoint("TOPLEFT", aura.Icon, "TOPLEFT", -1, 1)
        aura.PixelBorder:SetPoint("BOTTOMRIGHT", aura.Icon, "BOTTOMRIGHT", 1, -1)
    end

    if auraDuration then
        auraDuration:ClearAllPoints()
        auraDuration:SetPoint("CENTER", auraIcon, "CENTER", 0, 0)
        KE:ApplyFont(auraDuration, KE:GetFontPath(SK.db.FontFace), 12, fontOutline)
        auraDuration:SetShadowOffset(0, 0)

        if not auraDuration.__keHooked then
            auraDuration.__keHooked = true
            hooksecurefunc(aura, "UpdateDuration", function()
                if auraDuration and SK.db and SK.db.FontColor then
                    auraDuration:SetTextColor(unpack(SK.db.FontColor))
                end
            end)
        end
    end

    if auraCount then
        auraCount:ClearAllPoints()
        auraCount:SetPoint("BOTTOMRIGHT", auraIcon, "BOTTOMRIGHT", 0, 2)
        KE:ApplyFont(auraCount, KE:GetFontPath(SK.db.FontFace), 12, fontOutline)
    end
end

-- Style external defensive aura icons
local function StyleExternalAuraFrame(aura, size, borderColor)
    if aura.isAuraAnchor or not aura.Icon then return end
    local auraIcon, auraDuration, auraCount = aura.Icon, aura.Duration, aura.Count
    local auraBorder = aura.DebuffBorder or aura.BuffBorder
    local fontOutline = SK.db.FontOutline

    auraIcon:SetSize(size, size)
    if auraBorder then auraBorder:SetTexture(nil) end
    BorderOverlay(aura, borderColor)
    ApplyZoom(auraIcon, 0.3)

    local auraW, auraH = aura:GetSize()
    if auraW and auraH and auraW > 0 and auraH > 0 then
        aura.PixelBorder:ClearAllPoints()
        aura.PixelBorder:SetPoint("TOPLEFT", aura.Icon, "TOPLEFT", -1, 1)
        aura.PixelBorder:SetPoint("BOTTOMRIGHT", aura.Icon, "BOTTOMRIGHT", 1, -1)
    end

    if auraDuration then
        auraDuration:ClearAllPoints()
        auraDuration:SetPoint("CENTER", auraIcon, "BOTTOM", 0, 0)
        KE:ApplyFont(auraDuration, KE:GetFontPath(SK.db.FontFace), 12, fontOutline)
        auraDuration:SetShadowOffset(0, 0)
    end

    if auraCount then
        auraCount:ClearAllPoints()
        auraCount:SetPoint("BOTTOMRIGHT", auraIcon, "BOTTOMRIGHT", 0, 2)
        KE:ApplyFont(auraCount, KE:GetFontPath(SK.db.FontFace), 12, fontOutline)
    end
end

-- Re-space buff rows
local function SpaceRows(self)
    if not self or not self.AuraContainer or not self.auraFrames then return end
    local iconStride = self.AuraContainer.iconStride or 12
    local iconPadding = self.AuraContainer.iconPadding or 5
    local previousAura, rowAnchor
    for i = 1, #self.auraFrames do
        local aura = self.auraFrames[i]
        if aura then
            aura:ClearAllPoints()
            local index = (i - 1) % iconStride
            if index == 0 then
                if not rowAnchor then
                    aura:SetPoint("TOPRIGHT", self, "TOPRIGHT", -iconPadding, 0)
                else
                    aura:SetPoint("TOPRIGHT", rowAnchor, "BOTTOMRIGHT", 0, 1)
                end
                rowAnchor = aura
            else
                aura:SetPoint("TOPRIGHT", previousAura, "TOPLEFT", -iconPadding, 0)
            end
            previousAura = aura
        end
    end
end

-- Disable blizzard alpha pulse on low duration auras
local function DisableAuraPulse(aura)
    if not aura.__NoPulseHooked then
        aura.__NoPulseHooked = true
        hooksecurefunc(aura, "SetAlpha", function(self, alpha)
            if alpha ~= 1 then
                self:SetAlpha(1)
            end
        end)
    end
end

-- Style buffs
local function StyleBuffs()
    if not BuffFrame then return end
    local buffSize = SK.db.buffSize
    BuffFrame.CollapseAndExpandButton:SetAlpha(0)
    BuffFrame.CollapseAndExpandButton:SetScript("OnClick", nil)
    for _, aura in pairs(BuffFrame.auraFrames) do
        if aura.TempEnchantBorder then
            aura.TempEnchantBorder:SetTexture(nil)
        end
        StyleAuraFrame(aura, buffSize, SK.db.buffBorderColor)
        if SK.db.disableFlashing then
            DisableAuraPulse(aura)
        end
    end
end

-- Style debuffs
local function StyleDebuffs()
    if not DebuffFrame then return end
    local debuffSize = SK.db.debuffSize
    for _, aura in pairs(DebuffFrame.auraFrames) do
        StyleAuraFrame(aura, debuffSize, SK.db.debuffBorderColor)
        if SK.db.disableFlashing then
            DisableAuraPulse(aura)
        end
        if aura.DebuffBorder then
            aura.DebuffBorder:Hide()
            aura.DebuffBorder:SetAlpha(0)
        end
    end
end

-- Style external defensives
local function StyleExternalDefensives()
    if not ExternalDefensivesFrame then return end
    local defSize = SK.db.defSize
    for _, aura in pairs(ExternalDefensivesFrame.auraFrames) do
        StyleExternalAuraFrame(aura, defSize, SK.db.defBorderColor)
        if SK.db.disableFlashing then
            DisableAuraPulse(aura)
        end
    end
    ExternalDefensivesFrame:ClearAllPoints()
    ExternalDefensivesFrame:SetPoint("CENTER", UIParent, "CENTER", 0.1, 300.1)
    ExternalDefensivesFrame:SetFrameStrata("MEDIUM")
end

function SK:ApplySettings()
    if KE:ShouldNotLoadModule() then return end
    if self:IsEnabled() then
        self:Refresh()
    end
end

function SK:Refresh()
    if not self.db.Enabled then return end
    StyleBuffs()
    StyleDebuffs()
    StyleExternalDefensives()
    SpaceRows(BuffFrame)
end

function SK:SetupAuras()
    if not self.db.Enabled then return end
    StyleBuffs()
    StyleDebuffs()
    StyleExternalDefensives()
    SpaceRows(BuffFrame)
end

function SK:SetupAuraHooks()
    if not self.db.Enabled then return end
    hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function()
        SK:SetupAuras()
        SpaceRows(BuffFrame)
    end)
    hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
        SK:SetupAuras()
        SpaceRows(BuffFrame)
    end)
    hooksecurefunc(DebuffFrame, "UpdateAuraButtons", function()
        StyleDebuffs()
    end)
end

function SK:OnEnable()
    if KE:ShouldNotLoadModule() then return end
    if not self.db.Enabled then return end
    SK:SetupAuras()
    SK:SetupAuraHooks()
    local playerEnteringWorld = CreateFrame("Frame")
    playerEnteringWorld:RegisterEvent("PLAYER_ENTERING_WORLD")
    playerEnteringWorld:SetScript("OnEvent", function()
        C_Timer.After(0.5, function() self:Refresh() end)
    end)
end

function SK:OnDisable()
    self:UnregisterAllEvents()
    self:UnhookAll()
end

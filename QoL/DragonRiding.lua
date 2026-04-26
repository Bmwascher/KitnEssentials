-- ╔══════════════════════════════════════════════════════════╗
-- ║  DragonRiding.lua                                        ║
-- ║  Module: Skyriding UI                                    ║
-- ║  Purpose: Reskinned skyriding vigor bar with custom      ║
-- ║           styling and positioning.                       ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class DragonRiding: AceModule, AceEvent-3.0
local DR = KitnEssentials:NewModule("DragonRiding", "AceEvent-3.0")

local CreateFrame = CreateFrame
local C_Timer = C_Timer
local C_Spell = C_Spell
local C_UnitAuras = C_UnitAuras
local C_PlayerInfo = C_PlayerInfo
local RegisterStateDriver = RegisterStateDriver
local UnregisterStateDriver = UnregisterStateDriver
local math = math
local pcall = pcall

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
local VIGOR_SPELL = 372610
local THRILL_SPELL = 377234
local SECOND_WIND_SPELL = 425782
local WHIRLING_SURGE_SPELL = 361584

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------
local numVigor = 0

DR.container = nil
DR.parent = nil
DR.vigorFrame = nil
DR.surgeFrame = nil
DR.secondWindFrame = nil
DR.speedText = nil
DR.isPreview = false

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function DR:UpdateDB()
    self.db = KE.db.profile.DragonRiding
end

function DR:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

---------------------------------------------------------------------------------
-- Core Logic
---------------------------------------------------------------------------------
-- 1px outset outline: four strips that sit 1px OUTSIDE the frame's edges.
-- With spacing=1 between adjacent pills, neighbour outsets land on the same
-- 1px column (pillA.right outset and pillB.left outset both occupy the
-- column at pillA.right) — clean shared 1px divider, matching outer 1px
-- borders. Hand-rolled equivalent of Falcon's PixelOutline.tga slice.
local function AddPillOutsetBorders(frame, color)
    color = color or { 0, 0, 0, 1 }
    local px = KE:GetPixelSize()

    local function MakeStrip()
        local tex = frame:CreateTexture(nil, "OVERLAY", nil, 7)
        tex:SetColorTexture(unpack(color))
        tex:SetTexelSnappingBias(0)
        tex:SetSnapToPixelGrid(false)
        return tex
    end

    -- Top: 1px tall, sits 1px above frame, spans the full outer width
    -- (extending 1px past frame on each side so the corners read solid).
    local top = MakeStrip()
    top:SetHeight(px)
    top:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", -px, 0)
    top:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", px, 0)

    -- Bottom: mirror of top.
    local bottom = MakeStrip()
    bottom:SetHeight(px)
    bottom:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", -px, 0)
    bottom:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", px, 0)

    -- Left: 1px wide, sits 1px left of frame, spans frame height only
    -- (corners are already covered by the top/bottom strips' outset).
    local left = MakeStrip()
    left:SetWidth(px)
    left:SetPoint("TOPRIGHT", frame, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", 0, 0)

    -- Right: mirror of left.
    local right = MakeStrip()
    right:SetWidth(px)
    right:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 0, 0)
end

local function CreatePill(parent, height)
    local pill = CreateFrame("StatusBar", nil, parent)
    pill:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    pill:SetHeight(height)
    pill:SetStatusBarColor(0.75, 0.75, 0.75)

    -- Bg under the bar texture. Color is set dynamically to a darkened
    -- version of the bar color (Falcon's pattern) so empty/recharging
    -- pills read as "dark <color>" rather than translucent dark over the
    -- world. Initial color is irrelevant — UpdateVigor / UpdateSecondWind
    -- will overwrite it on first draw.
    local bg = pill:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 1)
    pill.bg = bg

    AddPillOutsetBorders(pill, { 0, 0, 0, 1 })

    return pill
end

local function ResizePillsToFit(container, pills, numPills, spacing)
    spacing = spacing or 1
    local maxWidth = container:GetWidth()
    local totalSpacing = spacing * (numPills - 1)
    local availableForPills = maxWidth - totalSpacing
    local barWidth = math.floor(availableForPills / numPills)
    local leftover = math.floor(availableForPills - (barWidth * numPills))

    for index = 1, numPills do
        if pills[index] then
            if index <= leftover then
                pills[index]:SetWidth(barWidth + 1)
            else
                pills[index]:SetWidth(barWidth)
            end
        end
    end
end

local function UpdateWhirlingSurge(self)
    local cd = self.surgeFrame and self.surgeFrame.cooldown
    if not cd then return end

    local cdInfo = C_Spell.GetSpellCooldown(WHIRLING_SURGE_SPELL)
    if cdInfo and cdInfo.startTime > 0 and cdInfo.duration > 1.5 then
        cd:SetCooldown(cdInfo.startTime, cdInfo.duration)
    else
        cd:Clear()
    end
end

local function UpdateSecondWind(self)
    local charges = C_Spell.GetSpellCharges(SECOND_WIND_SPELL)
    if not charges then return end

    local db = self.db
    local readyColor = db.Colors and db.Colors.SecondWind or { 0.3, 0.7, 1, 1 }
    local r, g, b = readyColor[1], readyColor[2], readyColor[3]
    local dr, dg, db_ = r * 0.25, g * 0.25, b * 0.25

    for index = 1, 3 do
        local pill = self.secondWindFrame[index]
        if pill then
            pill.bg:SetColorTexture(dr, dg, db_, 1)
            pill:SetStatusBarColor(r, g, b)
            if charges.currentCharges >= index then
                pill:SetMinMaxValues(0, 1)
                pill:SetValue(1)
            elseif charges.currentCharges + 1 == index then
                local duration = C_Spell.GetSpellChargeDuration(SECOND_WIND_SPELL)
                if duration then
                    pill:SetTimerDuration(duration)
                end
            else
                pill:SetMinMaxValues(0, 1)
                pill:SetValue(0)
            end
        end
    end
end

local function UpdateVigor(self)
    local charges = C_Spell.GetSpellCharges(VIGOR_SPELL)
    if not charges then return end

    local db = self.db
    local spacing = db.Spacing or 1

    local r, g, b
    ---@diagnostic disable-next-line
    local thrillUp = db.EnableThrillColor ~= false
        and C_UnitAuras.GetAuraDataBySpellName("player", C_Spell.GetSpellName(THRILL_SPELL), "HELPFUL")
    if thrillUp then
        local color = db.Colors and db.Colors.VigorThrill or { 0.2, 0.8, 0.2, 1 }
        r, g, b = color[1], color[2], color[3]
    else
        local color = db.Colors and db.Colors.Vigor or { 0.898, 0.063, 0.224, 1 }
        r, g, b = color[1], color[2], color[3]
    end
    -- Darkened shade for the empty/unfilled bg (Falcon-style fade).
    local dr, dg, db_ = r * 0.25, g * 0.25, b * 0.25

    for index = 1, charges.maxCharges do
        local pill = self.vigorFrame[index]
        if not pill then
            pill = CreatePill(self.vigorFrame, self.vigorFrame:GetHeight())
            self.vigorFrame[index] = pill

            if index == 1 then
                pill:SetPoint("LEFT")
            else
                pill:SetPoint("LEFT", self.vigorFrame[index - 1], "RIGHT", spacing, 0)
            end
        end

        pill.bg:SetColorTexture(dr, dg, db_, 1)
        pill:SetStatusBarColor(r, g, b)

        if charges.currentCharges >= index then
            pill:SetMinMaxValues(0, 1)
            pill:SetValue(1)
        elseif charges.currentCharges + 1 == index then
            local duration = C_Spell.GetSpellChargeDuration(VIGOR_SPELL)
            if duration then
                pill:SetTimerDuration(duration)
            end
        else
            pill:SetMinMaxValues(0, 1)
            pill:SetValue(0)
        end
    end

    if numVigor ~= charges.maxCharges then
        numVigor = charges.maxCharges
        ResizePillsToFit(self.vigorFrame, self.vigorFrame, numVigor, spacing)
    end
end

-- Re-routes color refresh through UpdateVigor so Thrill state (UNIT_AURA)
-- and recharging-pill state (SPELL_UPDATE_CHARGES) stay in sync.
local function UpdateVigorColor(self)
    UpdateVigor(self)
end

local function UpdateSpeed(self)
    local speed = self.speedText
    if not speed then return end

    local fontFile = speed:GetFont()
    if not fontFile then
        local font = KE:GetFontPath(self.db.FontFace) or KE.FONT or "Fonts\\FRIZQT__.TTF"
        local db = self.db
        speed:SetFont(font, db and db.SpeedFontSize or 14, "OUTLINE")
        fontFile = speed:GetFont()
        if not fontFile then return end
    end

    local isGliding, _, forwardSpeed = C_PlayerInfo.GetGlidingInfo()
    if isGliding then
        pcall(speed.SetFormattedText, speed, "%d%%", forwardSpeed / BASE_MOVEMENT_SPEED * 100 + 0.5)
    else
        pcall(speed.SetText, speed, "")
    end

    -- Visibility (independent OR semantics): hide if either flag's
    -- condition is met. Bars stay visible if neither flag is set or
    -- neither condition matches.
    local db = self.db
    local shouldHide = false
    if db.HideWhenGrounded and not isGliding then
        shouldHide = true
    end
    if not shouldHide and db.HideWhenFull then
        local charges = C_Spell.GetSpellCharges(VIGOR_SPELL)
        if charges and charges.currentCharges >= charges.maxCharges then
            shouldHide = true
        end
    end
    if self.container then
        if shouldHide and self.container:IsShown() then
            self.container:Hide()
        elseif not shouldHide and not self.container:IsShown() then
            self.container:Show()
        end
    end
end

---------------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------------
function DR:CreateFrames()
    if self.container then return end
    local db = self.db
    local barWidth = db.Width or 252
    local barHeight = db.BarHeight or 12
    local spacing = db.Spacing or 1

    -- Secure parent for state driver
    self.parent = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
    self.parent:Hide()

    -- Container — sized for the bars block only; the surge icon hangs off
    -- to the side and is not counted in the container width.
    self.container = CreateFrame("Frame", "KE_DragonRidingContainer", self.parent)
    self.container:SetSize(barWidth, (barHeight * 2) + spacing + 20)

    KE:ApplyFramePosition(self.container, db.Position, db)

    -- Both rows are created up-front; ApplyBarLayout decides which one is on
    -- top, which is on bottom, whether secondWind is hidden, etc.
    self.secondWindFrame = CreateFrame("Frame", nil, self.container)
    self.secondWindFrame:SetHeight(barHeight)

    local swColor = db.Colors and db.Colors.SecondWind or { 0.3, 0.7, 1, 1 }
    for i = 1, 3 do
        local pill = CreatePill(self.secondWindFrame, barHeight)
        pill:SetStatusBarColor(swColor[1], swColor[2], swColor[3])
        self.secondWindFrame[i] = pill
        if i == 1 then
            pill:SetPoint("LEFT")
        else
            pill:SetPoint("LEFT", self.secondWindFrame[i - 1], "RIGHT", spacing, 0)
        end
    end
    ResizePillsToFit(self.secondWindFrame, self.secondWindFrame, 3, spacing)

    self.vigorFrame = CreateFrame("Frame", nil, self.container)
    self.vigorFrame:SetHeight(barHeight)

    -- Whirling Surge as a square icon next to the bars. Anchor + size are
    -- handled in ApplySurgeIcon (which depends on which row is at the
    -- bottom — see ApplyBarLayout).
    self.surgeFrame = CreateFrame("Frame", nil, self.container)
    self.surgeFrame.icon = self.surgeFrame:CreateTexture(nil, "ARTWORK")
    self.surgeFrame.icon:SetAllPoints()
    KE:ApplyIconZoom(self.surgeFrame.icon)
    self.surgeFrame.icon:SetTexture(C_Spell.GetSpellTexture(WHIRLING_SURGE_SPELL))

    self.surgeFrame.cooldown = CreateFrame("Cooldown", nil, self.surgeFrame, "CooldownFrameTemplate")
    self.surgeFrame.cooldown:SetAllPoints()
    self.surgeFrame.cooldown:SetHideCountdownNumbers(false)
    self.surgeFrame.cooldown:SetDrawBling(false)
    self.surgeFrame.cooldown:SetDrawEdge(false)

    KE:AddIconBorders(self.surgeFrame, { 0, 0, 0, 1 })

    -- Speed text — parented to the container so it can re-anchor to whichever
    -- row ends up on top (vigor or secondWind, depending on FlipBars).
    self.speedText = self.container:CreateFontString(nil, "OVERLAY")
    local fontFile = KE:GetFontPath(self.db.FontFace) or KE.FONT or "Fonts\\FRIZQT__.TTF"
    local fontSize = self.db.SpeedFontSize or 14
    self.speedText:SetFont(fontFile, fontSize, "OUTLINE")
    self.speedText:SetWordWrap(false)
    self.speedText:SetShadowOffset(0, 0)
    self.speedText:SetText("")

    self:ApplyBarLayout()
    self:ApplySurgeIcon()
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
function DR:ApplyBarLayout()
    if not self.container then return end
    local db = self.db
    local barHeight = db.BarHeight or 12
    local spacing = db.Spacing or 1
    local rowGap = KE:PixelSnap(spacing)
    local showSW = db.ShowSecondWind ~= false
    local flip = db.FlipBars == true

    -- Decide which row is the bottom (anchored to container) and which is
    -- the top (stacked above bottom). With ShowSecondWind off, vigor is the
    -- only row regardless of flip.
    local bottomRow, topRow
    if not showSW then
        bottomRow, topRow = self.vigorFrame, nil
        self.secondWindFrame:Hide()
    else
        self.secondWindFrame:Show()
        if flip then
            bottomRow, topRow = self.vigorFrame, self.secondWindFrame
        else
            bottomRow, topRow = self.secondWindFrame, self.vigorFrame
        end
    end

    bottomRow:ClearAllPoints()
    bottomRow:SetPoint("BOTTOMLEFT", self.container, "BOTTOMLEFT", 0, 0)
    bottomRow:SetPoint("BOTTOMRIGHT", self.container, "BOTTOMRIGHT", 0, 0)
    bottomRow:SetHeight(barHeight)
    bottomRow:Show()

    if topRow then
        topRow:ClearAllPoints()
        topRow:SetPoint("BOTTOMLEFT", bottomRow, "TOPLEFT", 0, rowGap)
        topRow:SetPoint("BOTTOMRIGHT", bottomRow, "TOPRIGHT", 0, rowGap)
        topRow:SetHeight(barHeight)
    end

    -- Speed text anchors above whichever row is on top (or the only row).
    -- Shift X by half the icon footprint so the text reads centered over the
    -- visible (bars + icon) extent, not just the bars themselves.
    local anchorRow = topRow or bottomRow
    local speedX = 0
    if db.ShowSurgeIcon ~= false then
        local px = KE:GetPixelSize() or 1
        local rowCount = (db.ShowSecondWind ~= false) and 2 or 1
        local barsBlockH = barHeight * rowCount + (rowCount > 1 and rowGap or 0)
        local autoSize = barsBlockH + 2 * px
        local iconSize = (db.SurgeIconAutoSize ~= false) and autoSize
            or (db.SurgeIconSize or autoSize)
        local iconGap = db.SurgeIconGap or 4
        local shift = (iconSize + iconGap) / 2
        speedX = db.SurgeIconOnLeft and -shift or shift
    end
    self.speedText:ClearAllPoints()
    self.speedText:SetPoint("BOTTOM", anchorRow, "TOP", speedX, 2)
    if db.ShowSpeedText == false then
        self.speedText:Hide()
    else
        self.speedText:Show()
    end

    -- Track for ApplySurgeIcon (icon always anchors to the bottom row).
    self._bottomRow = bottomRow

    -- Resize container: rows + gap + speed text headroom (only if shown).
    local rowsHeight = barHeight * (topRow and 2 or 1) + (topRow and rowGap or 0)
    local speedSpace = (db.ShowSpeedText == false) and 0 or 20
    self.container:SetSize(db.Width or 252, rowsHeight + speedSpace)
end

function DR:Refresh()
    if not self.container then return end
    local db = self.db
    local barHeight = db.BarHeight or 12
    local spacing = db.Spacing or 1

    self:ApplyBarLayout()

    -- Update Second Wind pills (color/spacing/size)
    local swColor = db.Colors and db.Colors.SecondWind or { 0.3, 0.7, 1, 1 }
    for i = 1, 3 do
        if self.secondWindFrame[i] then
            self.secondWindFrame[i]:SetHeight(barHeight)
            self.secondWindFrame[i]:SetStatusBarColor(swColor[1], swColor[2], swColor[3])
            if i > 1 then
                self.secondWindFrame[i]:ClearAllPoints()
                self.secondWindFrame[i]:SetPoint("LEFT", self.secondWindFrame[i - 1], "RIGHT", spacing, 0)
            end
        end
    end
    ResizePillsToFit(self.secondWindFrame, self.secondWindFrame, 3, spacing)

    self:ApplySurgeIcon()

    -- Update Vigor pills
    local vigorCount = self.isPreview and 6 or numVigor
    for i = 1, vigorCount do
        if self.vigorFrame[i] then
            self.vigorFrame[i]:SetHeight(barHeight)
            if i > 1 then
                self.vigorFrame[i]:ClearAllPoints()
                self.vigorFrame[i]:SetPoint("LEFT", self.vigorFrame[i - 1], "RIGHT", spacing, 0)
            end
        end
    end
    if vigorCount > 0 then
        ResizePillsToFit(self.vigorFrame, self.vigorFrame, vigorCount, spacing)
    end
    UpdateVigorColor(self)

    -- Speed font
    local fontFile = KE:GetFontPath(self.db.FontFace) or KE.FONT or "Fonts\\FRIZQT__.TTF"
    local fontSize = self.db.SpeedFontSize or 14
    self.speedText:SetFont(fontFile, fontSize, "OUTLINE")
    if self.isPreview then
        self.speedText:SetText("420%")
    end
end

function DR:ApplySurgeIcon()
    if not self.surgeFrame then return end
    local db = self.db
    if db.ShowSurgeIcon == false then
        self.surgeFrame:Hide()
        return
    end
    self.surgeFrame:Show()

    local barHeight = db.BarHeight or 12
    local spacing = db.Spacing or 1
    local gap = db.SurgeIconGap or 4
    local px = KE:GetPixelSize() or 1

    -- Anchor to whichever row is currently at the bottom (set by
    -- ApplyBarLayout). Falls back to secondWindFrame if layout hasn't run.
    local bottomRow = self._bottomRow or self.secondWindFrame

    -- Bars block visual extent. Use PixelSnap'd row gap because that's what
    -- the bars actually render with at non-pixel-aligned UI scales.
    local rowGap = KE:PixelSnap(spacing)
    local rowCount = (db.ShowSecondWind ~= false) and 2 or 1
    local barsHeight = barHeight * rowCount + (rowCount > 1 and rowGap or 0)
    local autoSize = barsHeight + 2 * px

    local size = (db.SurgeIconAutoSize ~= false) and autoSize
        or (db.SurgeIconSize or autoSize)
    self.surgeFrame:SetSize(size, size)

    -- Vertically center the icon on the bars block.
    local yOffset = (barsHeight - size) / 2

    self.surgeFrame:ClearAllPoints()
    if db.SurgeIconOnLeft then
        self.surgeFrame:SetPoint("BOTTOMRIGHT", bottomRow, "BOTTOMLEFT", -gap, yOffset)
    else
        self.surgeFrame:SetPoint("BOTTOMLEFT", bottomRow, "BOTTOMRIGHT", gap, yOffset)
    end
end

function DR:ApplyPosition()
    if not self.container then return end
    KE:ApplyFramePosition(self.container, self.db.Position, self.db)
end

function DR:ApplySettings()
    self:Refresh()
    self:ApplyPosition()

    if self.parent and self.parent:IsShown() then
        UpdateVigor(self)
        UpdateVigorColor(self)
        UpdateWhirlingSurge(self)
        UpdateSecondWind(self)
    end
end

---------------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------------
function DR:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "DragonRiding", displayName = "Dragon Riding", frame = self.container,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos) self.db.Position = pos; KE:ApplyFramePosition(self.container, self.db.Position, self.db) end,
            getParentFrame = function() return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) end,
            guiPath = "DragonRiding",
        })
        self.editModeRegistered = true
    end
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------
function DR:ShowPreview()
    if InCombatLockdown() then return end
    if not self.container then
        self:CreateFrames()
    end
    self:RegWithEditMode()
    self.isPreview = true

    -- Cancel ticker and unregister events for clean preview
    if self.speedTicker then
        self.speedTicker:Cancel()
        self.speedTicker = nil
    end
    if self.vigorFrame then
        self.vigorFrame:UnregisterAllEvents()
        self.vigorFrame:SetScript("OnEvent", nil)
    end
    if self.surgeFrame then
        self.surgeFrame:UnregisterAllEvents()
        self.surgeFrame:SetScript("OnEvent", nil)
    end
    if self.secondWindFrame then
        self.secondWindFrame:UnregisterAllEvents()
        self.secondWindFrame:SetScript("OnEvent", nil)
    end

    -- Disable state driver during preview
    if self.parent then
        UnregisterStateDriver(self.parent, "visibility")
        self.parent:Show()
    end

    -- Create preview vigor pills
    local spacing = self.db.Spacing or 1
    for i = 1, 6 do
        if not self.vigorFrame[i] then
            local pill = CreatePill(self.vigorFrame, self.vigorFrame:GetHeight())
            self.vigorFrame[i] = pill
            if i == 1 then
                pill:SetPoint("LEFT")
            else
                pill:SetPoint("LEFT", self.vigorFrame[i - 1], "RIGHT", spacing, 0)
            end
        end
    end

    self:ApplySettings()

    -- Set preview values. Pill 5 demos the recharging state via partial
    -- fill (the dark bg shows through the unfilled portion); pills 1-4
    -- are fully charged; pill 6 is empty.
    local vColor = self.db.Colors and self.db.Colors.Vigor or { 0.898, 0.063, 0.224 }
    local vr, vg, vb = vColor[1], vColor[2], vColor[3]
    local vdr, vdg, vdb = vr * 0.25, vg * 0.25, vb * 0.25
    for i = 1, 6 do
        self.vigorFrame[i].bg:SetColorTexture(vdr, vdg, vdb, 1)
        self.vigorFrame[i]:SetStatusBarColor(vr, vg, vb)
        self.vigorFrame[i]:SetMinMaxValues(0, 1)
        if i <= 4 then
            self.vigorFrame[i]:SetValue(1)
        elseif i == 5 then
            self.vigorFrame[i]:SetValue(0.6)
        else
            self.vigorFrame[i]:SetValue(0)
        end
    end

    local swColor = self.db.Colors and self.db.Colors.SecondWind or { 0.3, 0.7, 1 }
    local sr, sg, sb = swColor[1], swColor[2], swColor[3]
    local sdr, sdg, sdb = sr * 0.25, sg * 0.25, sb * 0.25
    for i = 1, 3 do
        self.secondWindFrame[i].bg:SetColorTexture(sdr, sdg, sdb, 1)
        self.secondWindFrame[i]:SetStatusBarColor(sr, sg, sb)
        self.secondWindFrame[i]:SetMinMaxValues(0, 1)
        if i <= 2 then
            self.secondWindFrame[i]:SetValue(1)
        else
            self.secondWindFrame[i]:SetValue(0.3)
        end
    end

    -- Surge icon: clear cooldown so the icon shows ready in preview.
    if self.surgeFrame.cooldown then
        self.surgeFrame.cooldown:Clear()
    end
end

function DR:HidePreview()
    self.isPreview = false
    if self.parent then
        RegisterStateDriver(self.parent, "visibility", "[bonusbar:5] show; hide")
        if self.parent:IsShown() then
            self:OnShowHandler()
        end
    end
end

---------------------------------------------------------------------------------
-- Event Handlers
---------------------------------------------------------------------------------
function DR:OnShowHandler()
    if self.isPreview then return end

    if self.speedText then
        local fontFile = self.speedText:GetFont()
        if not fontFile then
            local font = KE:GetFontPath(self.db.FontFace) or KE.FONT or "Fonts\\FRIZQT__.TTF"
            local fontSize = self.db.SpeedFontSize or 14
            self.speedText:SetFont(font, fontSize, "OUTLINE")
        end
    end

    -- Plain RegisterEvent + manual unit filter on the handler (project rule:
    -- avoid RegisterUnitEvent because of known interaction with AceEvent's
    -- dispatcher). Without filtering, UNIT_AURA would fire for every party/
    -- raid member's aura change and run UpdateVigor + UpdateVigorColor on
    -- each, which is wasteful in a full group.
    self.vigorFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
    self.vigorFrame:RegisterEvent("UNIT_AURA")
    self.vigorFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_AURA" and unit ~= "player" then return end
        UpdateVigor(self)
    end)
    self.vigorFrame:HookScript("OnEvent", function(_, event, unit)
        if event == "UNIT_AURA" and unit ~= "player" then return end
        UpdateVigorColor(self)
    end)

    self.surgeFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    self.surgeFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
    self.surgeFrame:SetScript("OnEvent", function() UpdateWhirlingSurge(self) end)

    self.secondWindFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    self.secondWindFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
    self.secondWindFrame:SetScript("OnEvent", function() UpdateSecondWind(self) end)

    self.speedTicker = C_Timer.NewTicker(0.05, function() UpdateSpeed(self) end)

    UpdateVigor(self)
    UpdateVigorColor(self)
    UpdateWhirlingSurge(self)
    UpdateSecondWind(self)
end

function DR:OnHideHandler()
    if self.isPreview then return end

    self.vigorFrame:UnregisterEvent("SPELL_UPDATE_CHARGES")
    self.vigorFrame:UnregisterEvent("UNIT_AURA")
    self.surgeFrame:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
    self.surgeFrame:UnregisterEvent("SPELL_UPDATE_CHARGES")
    self.secondWindFrame:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
    self.secondWindFrame:UnregisterEvent("SPELL_UPDATE_CHARGES")

    if self.speedTicker then
        self.speedTicker:Cancel()
        self.speedTicker = nil
    end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function DR:OnEnable()
    if not self.db.Enabled then return end

    self:CreateFrames()
    self:RegWithEditMode()
    self:ApplySettings()

    self.parent:HookScript("OnShow", function() self:OnShowHandler() end)
    self.parent:HookScript("OnHide", function() self:OnHideHandler() end)

    RegisterStateDriver(self.parent, "visibility", "[bonusbar:5] show; hide")
end

function DR:OnDisable()
    if self.parent then
        self.parent:Hide()
        UnregisterStateDriver(self.parent, "visibility")
    end

    if self.speedTicker then
        self.speedTicker:Cancel()
        self.speedTicker = nil
    end
end

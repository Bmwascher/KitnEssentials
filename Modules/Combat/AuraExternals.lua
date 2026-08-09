-- ╔══════════════════════════════════════════════════════════╗
-- ║  AuraExternals.lua                                       ║
-- ║  Module: Aura Externals                                  ║
-- ║  Purpose: Displays external defensives cast on the       ║
-- ║           player (Pain Suppression, Ironbark, etc.) with ║
-- ║           optional glow on EXTERNAL_DEFENSIVE auras.     ║
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
local GetTime       = GetTime
local C_Timer       = C_Timer
local pairs, ipairs = pairs, ipairs
local tinsert       = table.insert
local tsort         = table.sort
local math_min      = math.min
local math_floor    = math.floor
local LCG           = LibStub("LibCustomGlow-1.0", true)
local LSM           = LibStub("LibSharedMedia-3.0", true)
local PlaySoundFile = PlaySoundFile

local UNIT = "player"

AX.buttons = {}
AX.frame = nil
AX.editModeRegistered = false
AX.isPreview = false
AX.seenSounded = {}
AX._soundPrimed = false
AX._pendingRefresh = false

-- EXTERNAL_DEFENSIVE auras (cast on you by others — Ironbark, Pain Suppression) trigger glow + sound;
-- BIG_DEFENSIVE auras (your own large CDs) are shown but un-glowed.
local FILTERS = {
    { filter = "HELPFUL|EXTERNAL_DEFENSIVE", filterPlayer = "HELPFUL|EXTERNAL_DEFENSIVE|PLAYER", isExternal = true  },
    { filter = "HELPFUL|BIG_DEFENSIVE",      filterPlayer = "HELPFUL|BIG_DEFENSIVE|PLAYER",      isExternal = false },
}

-- Preview icon sets used to populate the GUI page preview.
--   PREVIEW_ICONS     — all-external set (used when Show Big Defensives off)
--   PREVIEW_ICONS_DEF — mixed externals + big set (used when toggle is on)
-- Built dynamically per Refresh so flipping the toggle while preview is up
-- visually updates immediately.
local PREVIEW_ICONS     = { 135936, 572025, 135966, 627485, 4622478, 237542 }
local PREVIEW_ICONS_DEF = { 135936, 136097, 135966, 615341, 627485,  136120 }

local function BuildPreviewAuras(db)
    local list = {}
    local previewCount = (db.IconsPerRow or 6) * (db.MaxRows or 1)
    local showBig = db.ShowBigDefensives
    local source  = showBig and PREVIEW_ICONS_DEF or PREVIEW_ICONS
    local now = GetTime()
    for i = 1, previewCount do
        local iconIdx  = ((i - 1) % #source) + 1
        local duration = 6 + ((i * 3) % 12)
        local startTime = now - (duration * (0.15 + (i % 4) * 0.1))
        -- isExternal: all-true when Big Defensives are hidden; alternating
        -- when shown.
        local isExternal = (not showBig) or (i % 2 == 1)
        list[i] = {
            auraInstanceID = i,                     -- synthetic; never collides with real IDs
            spellId        = 0,
            icon           = source[iconIdx],
            duration       = duration,
            expirationTime = startTime + duration,
            applications   = 0,
            isExternal     = isExternal,
        }
    end
    return list
end

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
    self.seenSounded = {}
    self._soundPrimed = false  -- first Refresh silently seeds seenSounded
    self._pendingRefresh = false
    self:RegisterEvent("UNIT_AURA", "OnUnitAura")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "Refresh")
    self:Refresh()
end

function AX:OnDisable()
    self:UnregisterAllEvents()
    for _, b in pairs(self.buttons) do
        self:StopGlow(b)
    end
    if self.frame then self.frame:Hide() end
    for _, b in pairs(self.buttons) do
        if b.cooldown then b.cooldown:Clear() end
        if b.count then b.count:SetText("") end
        b:Hide()
    end
    self.seenSounded = {}
    self._soundPrimed = false
    self._pendingRefresh = false
end

-- Sizing the container to the actual icon grid (rather than 1x1) gives the
-- EditMode mover a real hitbox to grab; the icons themselves still anchor
-- off self.frame's anchor corner via LayoutButtons.
local function GetFrameSize(db)
    local cols = db.IconsPerRow or 6
    local rows = db.MaxRows or 1
    local w = cols * db.IconSize + (cols - 1) * db.IconSpacing
    local h = rows * db.IconSize + (rows - 1) * db.IconSpacing
    return w, h
end

function AX:ApplySettings()
    self:UpdateDB()
    if self.frame then
        self.frame:SetSize(GetFrameSize(self.db))
        KE:ApplyFramePosition(self.frame, self.db.Position, self.db)
        self.frame:SetFrameStrata(self.db.Strata or "MEDIUM")
    end
    -- If preview is currently active, force-rebuild it so GUI edits (icon
    -- size, anchors, glow, etc.) are visually immediate.
    if self.isPreview then
        self:HidePreview()
        self:ShowPreview()
    else
        self:Refresh()
    end

    -- The overlay box is computed from these settings and is only recomputed on
    -- request, so it would otherwise keep the previous numbers until something
    -- unrelated refreshed it.
    if KE.EditMode then KE.EditMode:RefreshLiveState() end
end

function AX:CreateContainer()
    if self.frame then return end
    local frame = CreateFrame("Frame", "KE_AuraExternals", UIParent)
    frame:SetSize(GetFrameSize(self.db))
    frame:SetFrameStrata(self.db.Strata or "MEDIUM")
    self.frame = frame
    KE:ApplyFramePosition(frame, self.db.Position, self.db)
    self:RegWithEditMode()
end

function AX:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key         = "AuraExternals",
            module      = self,
            displayName = "Aura Externals",
            frame       = self.frame,
            getPosition = function()
                return self.db.Position
            end,
            setPosition = function(pos)
                self.db.Position = pos
                KE:ApplyFramePosition(self.frame, self.db.Position, self.db)
            end,
            -- The container is sized to the grid, but the grid is pinned to the
            -- module's anchor corner and grows from there, so a growth setting
            -- that opposes the anchor slides every icon out of the frame. Read
            -- at call time: a value captured at registration goes stale the
            -- moment the user changes a growth direction.
            getOverlayInset = function()
                local db = self.db
                if not db then return 0, 0, 0, 0 end
                return KE:GetGridOverlayInset(
                    db.IconsPerRow or 6,
                    db.MaxRows or 1,
                    db.IconSize,
                    db.IconSpacing,
                    (db.Position and db.Position.AnchorFrom) or "CENTER",
                    db.GrowHorizontal == "LEFT",
                    db.GrowVertical == "UP"
                )
            end,
            getParentFrame = function()
                return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)
            end,
            guiPath = "AuraExternals",
        })
        self.editModeRegistered = true
    end
end

---------------------------------------------------------------------------------
-- Glow dispatch
---------------------------------------------------------------------------------

function AX:StopGlow(button)
    if not LCG or not button or not button.glowActive then return end
    LCG.PixelGlow_Stop(button)
    LCG.AutoCastGlow_Stop(button)
    LCG.ButtonGlow_Stop(button)
    LCG.ProcGlow_Stop(button)
    button.glowActive = false
end

function AX:StartGlow(button, forceRestart)
    if not LCG or not button then return end
    local db = self.db
    if not db.GlowEnabled then return end
    if button.glowActive and not forceRestart then return end

    self:StopGlow(button)

    local glowType = db.GlowType or "pixel"
    if glowType == "pixel" then
        LCG.PixelGlow_Start(button, db.GlowColor,
            db.GlowLines, db.GlowFrequency, db.GlowLength, db.GlowThickness,
            0, 0, db.GlowBorder, nil)
    elseif glowType == "autocast" then
        LCG.AutoCastGlow_Start(button, db.GlowColor,
            db.GlowLines, db.GlowFrequency, db.GlowScale, 1, 1, nil)
    elseif glowType == "button" then
        LCG.ButtonGlow_Start(button, db.GlowColor, db.GlowFrequency)
    elseif glowType == "proc" then
        LCG.ProcGlow_Start(button, {
            color     = db.GlowColor,
            startAnim = db.GlowStartAnim,
            duration  = db.GlowDuration,
        })
    end

    button.glowActive = true
end

---------------------------------------------------------------------------------
-- Button factory + tooltip
---------------------------------------------------------------------------------

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
    KE:ApplyIconZoom(tex)
    b.icon = tex

    KE:AddIconBorders(b)

    local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    cd:SetAllPoints(b)
    cd:SetDrawEdge(false)
    cd:SetReverse(db.Reverse)
    -- Use Blizzard's built-in countdown text (taint-safe via
    -- SetCooldownFromDurationObject). A custom 0.1s ticker can't read
    -- aura.duration / aura.expirationTime on encounter-applied HELPFUL
    -- auras because those fields can come back secret. The built-in text
    -- is driven by the duration object, which is taint-safe.
    cd:SetHideCountdownNumbers(false)
    b.cooldown = cd

    -- b.timer aliases the cooldown's built-in countdown FontString
    -- (CooldownFrameTemplate creates a single text region accessible via
    -- :GetRegions()). UpdateButtonAppearance re-applies font + position
    -- every Refresh.
    local timer = cd:GetRegions() --[[@as FontString]]
    b.timer = timer

    local count = b:CreateFontString(nil, "OVERLAY")
    count:SetJustifyH("RIGHT")
    b.count = count

    -- FontStrings require a font assigned before any SetText call, otherwise
    -- the WoW client errors "FontString:SetText(): Font not set" (and
    -- taints the addon). Seed fonts here at creation time.
    if timer and timer.SetFont then
        KE:ApplyFontToText(timer, db.FontFace, db.TimerFontSize, db.FontOutline)
        if timer.SetShadowOffset then timer:SetShadowOffset(0, 0) end
    end
    KE:ApplyFontToText(count, db.FontFace, db.FontSize, db.FontOutline)

    return b
end

function AX:GetOrCreateButton(index)
    local b = self.buttons[index]
    if b then return b end
    b = CreateButton(self.frame, self.db)
    self.buttons[index] = b
    return b
end

---------------------------------------------------------------------------------
-- Aura collection (GetAuraSlots + GetAuraDataBySlot for 12.0)
---------------------------------------------------------------------------------

local function ScanFilter(filterStr, into, seen, isExternal)
    -- GetAuraSlots returns (continuationToken, slot1, slot2, ...). Skip index 1.
    local slots = { C_UnitAuras.GetAuraSlots(UNIT, filterStr) }
    for i = 2, #slots do
        local data = C_UnitAuras.GetAuraDataBySlot(UNIT, slots[i])
        if data then
            local aid = data.auraInstanceID
            if aid and not seen[aid] then
                seen[aid] = true
                tinsert(into, {
                    auraInstanceID = aid,
                    spellId        = data.spellId,
                    icon           = data.icon,
                    duration       = data.duration,
                    expirationTime = data.expirationTime,
                    applications   = data.applications,
                    isExternal     = isExternal,
                })
            end
        end
    end
end

function AX:CollectAuras()
    local list = {}
    local seen = {}
    local db = self.db
    for _, f in ipairs(FILTERS) do
        -- BIG_DEFENSIVE bucket gated by ShowBigDefensives; EXTERNAL_DEFENSIVE always scanned.
        -- Both filter variants are scanned so self-applied auras of either bucket
        -- (Druid Iron Bark self-cast, your own Shield Wall, etc.) are picked up.
        if f.isExternal or db.ShowBigDefensives then
            ScanFilter(f.filter, list, seen, f.isExternal)
            ScanFilter(f.filterPlayer, list, seen, f.isExternal)
        end
    end
    -- Sort by auraInstanceID (matches AE/NUI). expirationTime can be secret
    -- on encounter-applied HELPFUL auras, and comparing secret numbers taints.
    tsort(list, function(a, b) return (a.auraInstanceID or 0) < (b.auraInstanceID or 0) end)
    return list
end

---------------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------------

function AX:Refresh()
    if not self.frame then return end
    local db = self.db
    if not db.Enabled and not self.isPreview then
        for _, b in pairs(self.buttons) do
            self:StopGlow(b)
            b:Hide()
        end
        self.frame:Hide()
        return
    end
    self.frame:Show()

    local auras = self.isPreview and BuildPreviewAuras(db) or self:CollectAuras()
    local cap = math_min(#auras, (db.IconsPerRow or 6) * (db.MaxRows or 1))

    -- Sound on new EXTERNAL_DEFENSIVE auras only.
    -- First Refresh after enable seeds seenSounded silently so existing auras
    -- don't re-trigger on /reload or module toggle.
    if not self.isPreview then
        if not self._soundPrimed then
            for _, aura in ipairs(auras) do
                if aura.auraInstanceID then
                    self.seenSounded[aura.auraInstanceID] = true
                end
            end
            self._soundPrimed = true
        else
            if db.SoundEnabled and LSM and db.SoundName and db.SoundName ~= "None" then
                local soundPath = LSM:Fetch("sound", db.SoundName)
                if soundPath then
                    local currentIDs = {}
                    for _, aura in ipairs(auras) do
                        if aura.auraInstanceID then
                            currentIDs[aura.auraInstanceID] = true
                        end
                    end
                    -- Play once per refresh for the first new externally-cast aura.
                    for _, aura in ipairs(auras) do
                        local aid = aura.auraInstanceID
                        if aid and aura.isExternal and not self.seenSounded[aid] then
                            PlaySoundFile(soundPath)
                            self.seenSounded[aid] = true
                            break
                        end
                    end
                    -- Garbage-collect IDs no longer present.
                    for aid in pairs(self.seenSounded) do
                        if not currentIDs[aid] then
                            self.seenSounded[aid] = nil
                        end
                    end
                end
            end
        end
    end

    for i = 1, cap do
        local aura = auras[i]
        local b = self:GetOrCreateButton(i)
        b.auraInstanceID = aura.auraInstanceID
        b.isExternal     = aura.isExternal
        b.icon:SetTexture(aura.icon)

        -- Cooldown + countdown text both driven by the duration object (or
        -- synthetic start/duration in preview). The duration object is
        -- taint-safe so the spiral AND Blizzard's built-in countdown
        -- numbers render correctly even on encounter-applied HELPFUL auras
        -- where the raw aura.duration is secret.
        if self.isPreview and aura.duration and aura.expirationTime then
            -- Synthetic auraInstanceID: GetAuraDuration won't match a real
            -- aura, so use the synthetic numeric times directly.
            b.cooldown:SetCooldown(aura.expirationTime - aura.duration, aura.duration)
            b.cooldown:Show()
        else
            local durationObj = C_UnitAuras.GetAuraDuration and
                C_UnitAuras.GetAuraDuration(UNIT, aura.auraInstanceID)
            if durationObj then
                b.cooldown:SetCooldownFromDurationObject(durationObj)
                b.cooldown:Show()
            else
                b.cooldown:Clear()
            end
        end

        -- Stack count: GetAuraApplicationDisplayCount handles "show when
        -- >= 2, cap 999" internally via min/max args, returning a number
        -- or "" — pass straight to SetText without comparison so secret
        -- counts don't taint (AE pattern). Preview synthetic IDs miss the
        -- real-aura lookup, so explicit empty for them.
        if b.count then
            if self.isPreview then
                b.count:SetText("")
            elseif C_UnitAuras.GetAuraApplicationDisplayCount then
                b.count:SetText(C_UnitAuras.GetAuraApplicationDisplayCount(UNIT, aura.auraInstanceID, 2, 999) or "")
            else
                b.count:SetText("")
            end
        end

        if aura.isExternal then
            self:StartGlow(b)
        else
            self:StopGlow(b)
        end

        b:Show()
    end

    for i = cap + 1, #self.buttons do
        self:StopGlow(self.buttons[i])
        self.buttons[i]:Hide()
    end

    self:UpdateButtonAppearance(cap)
    self:LayoutButtons(cap)
end

function AX:UpdateButtonAppearance(count)
    local db = self.db
    local tp = db.TimerPosition
    local sp = db.StackPosition
    for i = 1, count do
        local b = self.buttons[i]
        if b then
            -- Resize the button frame to match db.IconSize so live size
            -- changes don't leave existing buttons at their original
            -- creation-time dimensions (which would overlap once
            -- LayoutButtons re-spaces them with the smaller stride).
            b:SetSize(db.IconSize, db.IconSize)
        end
        -- b.timer is the cooldown's built-in countdown FontString (via
        -- cd:GetRegions() in CreateButton). Re-apply font + anchor each
        -- Refresh so user edits take effect immediately. Anchor to the
        -- button so TimerPosition behaves consistently with AuraDebuffs.
        if b and b.timer and b.timer.SetFont then
            KE:ApplyFontToText(b.timer, db.FontFace, db.TimerFontSize, db.FontOutline)
            if b.timer.SetShadowOffset then b.timer:SetShadowOffset(0, 0) end
            b.timer:ClearAllPoints()
            b.timer:SetPoint(tp.AnchorFrom, b, tp.AnchorTo, tp.XOffset, tp.YOffset)
        end
        if b and b.count then
            KE:ApplyFontToText(b.count, db.FontFace, db.FontSize, db.FontOutline)
            b.count:ClearAllPoints()
            if sp then
                b.count:SetPoint(sp.AnchorFrom, b, sp.AnchorTo, sp.XOffset, sp.YOffset)
            else
                b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
            end
        end
        if b and b.icon then
            KE:ApplyIconZoom(b.icon)
        end
        if b and b.cooldown and b.cooldown.SetDrawSwipe then
            b.cooldown:SetDrawSwipe(db.Swipe ~= false)
        end
    end
end

function AX:LayoutButtons(count)
    local db = self.db
    local dx = (db.IconSize + db.IconSpacing) * (db.GrowHorizontal == "LEFT" and -1 or 1)
    local dy = (db.IconSize + db.IconSpacing) * (db.GrowVertical == "UP" and 1 or -1)
    local perRow = db.IconsPerRow or 6

    -- Button[1]'s anchor corner matches the module's Position.AnchorFrom so
    -- the icon grid starts at the user-selected anchor point. See the matching
    -- comment in AuraDebuffs:LayoutButtons for the full rationale.
    local pin = (db.Position and db.Position.AnchorFrom) or "CENTER"

    for i = 1, count do
        local b = self.buttons[i]
        local row = math_floor((i - 1) / perRow)
        local col = (i - 1) % perRow
        b:ClearAllPoints()
        b:SetPoint(pin, self.frame, pin, col * dx, row * dy)
    end
end

---------------------------------------------------------------------------------
-- UNIT_AURA debounce (collapse back-to-back events to one Refresh per frame)
---------------------------------------------------------------------------------

local function FlushRefresh()
    if not AX._pendingRefresh then return end
    AX._pendingRefresh = false
    AX:Refresh()
end

function AX:OnUnitAura(_, unit)
    if unit ~= UNIT then return end
    if self._pendingRefresh then return end
    self._pendingRefresh = true
    C_Timer.After(0, FlushRefresh)
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
    if not self.db.Enabled and self.frame then
        self.frame:Hide()
    end
end

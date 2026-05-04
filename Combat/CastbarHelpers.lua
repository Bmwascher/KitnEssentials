-- ╔══════════════════════════════════════════════════════════╗
-- ║  CastbarHelpers.lua                                      ║
-- ║  Purpose: Shared logic for TargetCastbar and             ║
-- ║           FocusCastbar — plain functions taking (self,   ║
-- ║           ...) where self is the calling AceModule.      ║
-- ║  Not inheritance. Not a base class. Just helpers.        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local CreateFrame = CreateFrame
local CreateColor = CreateColor
local UnitCastingInfo, UnitChannelInfo = UnitCastingInfo, UnitChannelInfo
local UnitCastingDuration, UnitChannelDuration = UnitCastingDuration, UnitChannelDuration
local UnitEmpoweredChannelDuration = UnitEmpoweredChannelDuration
local UnitExists = UnitExists
local UnitName = UnitName
local UnitClass = UnitClass
local UnitSpellTargetName = UnitSpellTargetName
local UnitSpellTargetClass = UnitSpellTargetClass
local C_ClassColor = C_ClassColor
local UnitNameFromGUID = UnitNameFromGUID
local UnitClassFromGUID = UnitClassFromGUID
local GetRaidTargetIndex = GetRaidTargetIndex
local SetRaidTargetIconTexture = SetRaidTargetIconTexture
local GetTime = GetTime
local select = select
local type = type
local random = math.random

local FALLBACK_ICON = 136243
local PREVIEW_DURATION = 20
local MAX_TARGET_NAMES = 5

-- Set to true to trace UNIT_SPELLCAST_INTERRUPTED payload + GUID resolution.
-- Logs each interrupt event with: interruptedBy GUID (or <nil>/<secret>),
-- UnitNameFromGUID return, UnitClassFromGUID return, IsSafeValue verdict,
-- and the player/pet GUIDs for cross-check. Flip back to false after diagnosis.
local DEBUG_CB = false

local H = {}
KE.CastbarHelpers = H

H.FALLBACK_ICON = FALLBACK_ICON
H.PREVIEW_DURATION = PREVIEW_DURATION
H.MAX_TARGET_NAMES = MAX_TARGET_NAMES

---------------------------------------------------------------------------------
-- Small utilities
---------------------------------------------------------------------------------

function H.ApplyFrameBackdrop(frame, bgColor, borderColor)
    local bgr, bgg, bgb, bga = KE:ResolveColor(bgColor, { 0, 0, 0, 0.8 })
    local bdr, bdg, bdb, bda = KE:ResolveColor(borderColor, { 0, 0, 0, 1 })
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        tileSize = 0,
        edgeSize = KE:GetPixelSize(),
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    frame:SetBackdropColor(bgr, bgg, bgb, bga)
    frame:SetBackdropBorderColor(bdr, bdg, bdb, bda)
end

function H.CreateColorObjects(self)
    local kick = self.db.KickIndicator or {}
    local rr, rg, rb = KE:ResolveColor(kick.ReadyColor, { 0.1, 0.8, 0.1, 1 })
    local nr, ng, nb = KE:ResolveColor(kick.NotReadyColor, { 0.5, 0.5, 0.5, 1 })
    local ur, ug, ub = KE:ResolveColor(self.db.NotInterruptibleColor, { 0.7, 0.7, 0.7, 1 })
    self.colors = {
        Ready = CreateColor(rr, rg, rb),
        NotReady = CreateColor(nr, ng, nb),
        Uninterruptible = CreateColor(ur, ug, ub),
    }
end

function H.ResetCastState(self)
    self.casting, self.channeling, self.empowering = nil, nil, nil
    self.castID, self.spellID, self.spellName = nil, nil, nil
    self.notInterruptible = nil
    self.cachedDuration = nil
end

-- UnitNameFromGUID + UnitClassFromGUID resolve for ALL unit GUIDs (player,
-- pet, NPC), not just players. GetPlayerInfoByGUID silently returned nil for
-- non-player interrupters — Demo warlock Felhunter Spell Lock and any pet/NPC
-- kick degraded to bare "Interrupted" with no "by X". NUI v3.10 fix.
--
-- IMPORTANT 12.0 limitation: UNIT_SPELLCAST_INTERRUPTED's interruptedBy GUID
-- is itself SecretWhenUnitSpellCastRestricted in instanced PvE/PvP (M+, raid,
-- rated PvP, training dummy zones with restriction). When the GUID is secret,
-- both APIs return secret strings; we bail at the IsSafeValue check below and
-- the caller falls back to plain "Interrupted". This is parity with NUI v3.10
-- behavior in restricted contexts — Blizzard secured the data, no API can
-- recover the name. See CombatTexts.lua for the same observation, where
-- self-attribution uses flag correlation instead. The swap still helps in
-- non-restricted contexts (open world) where interpolated GUIDs are plain.
-- UnitNameFromGUID + UnitClassFromGUID resolve for ALL unit GUIDs (player,
-- pet, NPC), not just players. GetPlayerInfoByGUID silently returned nil for
-- non-player interrupters — Demo warlock Felhunter Spell Lock and Felguard
-- Axe Toss kicks degraded to bare "Interrupted" with no "by X". NUI v3.10
-- fix verbatim.
--
-- 12.0 secret-value note: in restricted contexts (M+ / raids / outdoor cast
-- restrictions), the interrupter GUID itself is SecretWhenUnitSpellCastRestricted,
-- and so are UnitNameFromGUID's name return and UnitClassFromGUID's classFile.
-- Empirically (DEBUG_CB trace, open-world Felhunter/Felguard test 2026-05-03),
-- secret cstrings flow through WrapTextInColorCode -> string.format -> SetText
-- without taint errors and render as their underlying values. So we deliberately
-- do NOT bail on secret-name; only on truly nil. This contradicts the "Do NOT
-- concat with color codes" guidance documented for TargetedSpells v3.2.0 in
-- another module's surface — that warning is module-context-dependent, not
-- universal. The castbar interrupt text path is safe.
--
-- The `if interruptedBy ~= nil` case (Blizzard omits the GUID for some
-- player-cast interrupts like Avenger's Shield, sometimes for warlock kicks)
-- is handled by the caller's `interruptedBy and H.GetColoredNameFromGUID(...)`
-- short-circuit, which falls back to plain "Interrupted".
function H.GetColoredNameFromGUID(guid)
    if guid == nil then
        if DEBUG_CB then KE:Print("[CB] GetColoredNameFromGUID: guid=<nil>") end
        return nil
    end

    local name = UnitNameFromGUID(guid)
    if DEBUG_CB then
        local guidStr = KE:IsSafeValue(guid) and tostring(guid) or "<secret>"
        local nameSafe = KE:IsSafeValue(name)
        local nameStr = nameSafe and tostring(name) or (name == nil and "<nil>" or "<secret>")
        KE:Print(("[CB] GetColoredNameFromGUID: guid=%s name=%s safe=%s"):format(guidStr, nameStr, tostring(nameSafe)))
    end
    if name == nil then return nil end

    local classToken = select(2, UnitClassFromGUID(guid))
    if DEBUG_CB then
        local tokenSafe = KE:IsSafeValue(classToken)
        local tokenStr = tokenSafe and tostring(classToken) or (classToken == nil and "<nil>" or "<secret>")
        KE:Print(("[CB]   classToken=%s safe=%s"):format(tokenStr, tostring(tokenSafe)))
    end
    if type(classToken) ~= "string" then return name end

    local color = C_ClassColor.GetClassColor(classToken)
    if color == nil then return name end

    return color:WrapTextInColorCode(name)
end

---------------------------------------------------------------------------------
-- Interrupt cache
---------------------------------------------------------------------------------

function H.CacheInterruptId(self)
    self.interruptId = nil
    self.interruptCD = nil
    self.interruptSpellSet = nil
    local specIndex = GetSpecialization()
    if not specIndex then return end
    local specID = GetSpecializationInfo(specIndex)
    if not specID then return end
    -- Full set of valid interrupt spell IDs for this spec, used by the kick-CD
    -- tracker so any known pet-swap variant (e.g. Demo Warlock with Spell Lock
    -- in the player spellbook AND Axe Toss in the pet spellbook) counts as a
    -- cast. Priority-picked interruptId/CD still drive the visible bar.
    self.interruptSpellSet = KE:GetInterruptSpellSet(specID)
    local candidates = KE:GetInterruptCandidatesForSpec(specID)
    if not candidates then return end
    for i = 1, #candidates do
        local data = candidates[i]
        if C_SpellBook.IsSpellKnownOrInSpellBook(data.id)
            or C_SpellBook.IsSpellKnownOrInSpellBook(data.id, Enum.SpellBookSpellBank.Pet) then
            self.interruptId = data.id
            self.interruptCD = data.cd
            return
        end
    end
end

---------------------------------------------------------------------------------
-- Frame construction
---------------------------------------------------------------------------------

-- opts: { frameName, defaultWidth, defaultHeight, defaultYOffset }
function H.CreateFrame(self, opts)
    if self.frame then return end
    local db = self.db
    local parent = KE:ResolveAnchorFrame(db.anchorFrameType, db.ParentFrame)
    local height = db.Height or opts.defaultHeight

    local frame = CreateFrame("Frame", opts.frameName, parent, "BackdropTemplate")
    frame:SetSize(db.Width or opts.defaultWidth, height)
    frame:SetPoint(db.Position.AnchorFrom or "CENTER", parent, db.Position.AnchorTo or "CENTER",
        db.Position.XOffset or 0, db.Position.YOffset or opts.defaultYOffset)
    frame:SetFrameStrata(db.Strata or "HIGH")
    frame:EnableMouse(false)
    H.ApplyFrameBackdrop(frame, db.BackdropColor or { 0, 0, 0, 0.8 }, db.BorderColor or { 0, 0, 0, 1 })
    frame:Hide()

    local iconFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    iconFrame:SetSize(height, height)
    iconFrame:SetPoint("LEFT", frame, "LEFT", 0, 0)
    H.ApplyFrameBackdrop(iconFrame, { 0, 0, 0, 0.8 }, db.BorderColor or { 0, 0, 0, 1 })

    local px = KE:GetPixelSize()
    local icon = iconFrame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", px, -px)
    icon:SetPoint("BOTTOMRIGHT", -px, px)
    KE:ApplyIconZoom(icon)

    local castBar = CreateFrame("StatusBar", nil, frame)
    castBar:SetPoint("LEFT", iconFrame, "RIGHT", 0, 0)
    castBar:SetPoint("RIGHT", frame, "RIGHT", -px, 0)
    castBar:SetPoint("TOP", frame, "TOP", 0, -px)
    castBar:SetPoint("BOTTOM", frame, "BOTTOM", 0, px)
    castBar:SetStatusBarTexture(KE:GetStatusbarPath(db.StatusBarTexture))
    castBar:SetMinMaxValues(0, 1)
    castBar:SetValue(0)

    local spark = castBar:CreateTexture(nil, "OVERLAY")
    spark:SetSize(12, height)
    spark:SetBlendMode("ADD")
    spark:SetTexture([[Interface\CastingBar\UI-CastingBar-Spark]])
    spark:SetPoint("CENTER", castBar:GetStatusBarTexture(), "RIGHT", 0, 0)
    spark:Hide()

    local positioner = CreateFrame("StatusBar", nil, castBar)
    positioner:SetAllPoints(castBar)
    positioner:SetStatusBarTexture(KE:GetStatusbarPath(db.StatusBarTexture))
    positioner:SetStatusBarColor(0, 0, 0, 0)
    positioner:SetMinMaxValues(0, 1)
    positioner:SetValue(0)
    positioner:SetFrameLevel(castBar:GetFrameLevel() + 1)

    local kickCooldownBar = CreateFrame("StatusBar", nil, castBar)
    kickCooldownBar:SetAllPoints(castBar)
    kickCooldownBar:SetStatusBarTexture(KE:GetStatusbarPath(db.StatusBarTexture))
    kickCooldownBar:SetStatusBarColor(0, 0, 0, 0)
    kickCooldownBar:SetClipsChildren(true)
    kickCooldownBar:SetMinMaxValues(0, 1)
    kickCooldownBar:SetValue(0)
    kickCooldownBar:SetFrameLevel(castBar:GetFrameLevel() + 4)

    local tickMask = castBar:CreateMaskTexture()
    tickMask:SetAllPoints(castBar)
    tickMask:SetTexture("Interface\\BUTTONS\\WHITE8X8", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")

    local kickTick = kickCooldownBar:CreateTexture(nil, "OVERLAY", nil, 7)
    kickTick:SetSize(2, height)
    kickTick:SetColorTexture(1, 1, 1, 1)
    kickTick:SetPoint("CENTER", kickCooldownBar:GetStatusBarTexture(), "RIGHT", 0, 0)
    kickTick:AddMaskTexture(tickMask)
    kickTick:SetAlpha(0)

    local text = castBar:CreateFontString(nil, "OVERLAY")
    text:SetPoint("LEFT", castBar, "LEFT", 4, 0)
    text:SetJustifyH("LEFT")
    KE:ApplyFontToText(text, db.FontFace, db.FontSize, db.FontOutline)

    local time = castBar:CreateFontString(nil, "OVERLAY")
    time:SetPoint("RIGHT", castBar, "RIGHT", -4, 0)
    time:SetJustifyH("RIGHT")
    KE:ApplyFontToText(time, db.FontFace, db.FontSize, db.FontOutline)

    local targetNames = {}
    for i = 1, MAX_TARGET_NAMES do
        local nameText = frame:CreateFontString(nil, "OVERLAY")
        nameText:SetParent(castBar)
        nameText:SetAlpha(0)
        targetNames[i] = nameText
    end

    -- Optional raid-target marker. Only created when the
    -- module's defaults populate `db.TargetMarker` — FocusCastbar opts in,
    -- TargetCastbar does not. When the marker exists, H.UpdateTargetMarker
    -- and the cast lifecycle handle visibility; otherwise all marker code
    -- silently no-ops via `if self.targetMarker` guards.
    local targetMarker
    if db.TargetMarker then
        targetMarker = frame:CreateTexture(nil, "OVERLAY")
        targetMarker:SetTexture("Interface/TargetingFrame/UI-RaidTargetingIcons")
        targetMarker:SetParent(castBar)
        targetMarker:Hide()
    end

    self.positioner = positioner
    self.frame, self.iconFrame, self.icon = frame, iconFrame, icon
    self.castBar, self.spark = castBar, spark
    self.kickCooldownBar, self.kickTick = kickCooldownBar, kickTick
    self.text, self.time = text, time
    self.targetMarker = targetMarker
    self.targetNames = targetNames
    self.holdTimer = nil

    self:ApplySettings()
end

-- opts: { defaultWidth }
function H.ApplySettings(self, opts)
    if not self.frame then return end
    H.CreateColorObjects(self)

    local db = self.db
    local kickColors = db.KickIndicator or {}
    local tr, tg, tb, ta = KE:ResolveColor(db.TextColor, { 1, 1, 1, 1 })

    self.frame:SetSize(db.Width or opts.defaultWidth, db.Height)
    H.ApplyFrameBackdrop(self.frame, db.BackdropColor, db.BorderColor)
    self.frame:SetFrameStrata(db.Strata or "HIGH")

    self.iconFrame:SetSize(db.Height, db.Height)
    H.ApplyFrameBackdrop(self.iconFrame, db.BackdropColor, db.BorderColor)

    local texturePath = KE:GetStatusbarPath(db.StatusBarTexture)
    self.castBar:SetStatusBarTexture(texturePath)
    self.positioner:SetStatusBarTexture(texturePath)
    self.kickCooldownBar:SetStatusBarTexture(texturePath)
    self.spark:SetSize(12, db.Height)

    self.kickTick:SetSize(2, db.Height)
    local kr, kg, kb, ka = KE:ResolveColor(kickColors.TickColor, { 1, 1, 1, 1 })
    self.kickTick:SetColorTexture(kr, kg, kb, ka)

    KE:ApplyFontToText(self.text, db.FontFace, db.FontSize, db.FontOutline)
    KE:ApplyFontToText(self.time, db.FontFace, db.FontSize, db.FontOutline)
    self.text:SetTextColor(tr, tg, tb, ta)
    self.time:SetTextColor(tr, tg, tb, ta)

    if self.targetNames then
        local targetSettings = db.TargetNames or {}
        local anchorPoint = KE:GetPointFromAnchor(targetSettings.Anchor)
        for i = 1, MAX_TARGET_NAMES do
            local targetText = self.targetNames[i]
            targetText:ClearAllPoints()
            targetText:SetPoint(anchorPoint, self.frame, anchorPoint, targetSettings.XOffset or 0, targetSettings.YOffset or 14)
            targetText:SetJustifyH(anchorPoint)
            KE:ApplyFontToText(targetText, db.FontFace, targetSettings.FontSize or 12, db.FontOutline)
        end
    end

    if self.targetMarker and db.TargetMarker then
        local markerSettings = db.TargetMarker
        local anchorPoint = KE:GetPointFromAnchor(markerSettings.Anchor) or "LEFT"
        local size = markerSettings.Size or 26
        self.targetMarker:SetSize(size, size)
        self.targetMarker:ClearAllPoints()
        self.targetMarker:SetPoint(anchorPoint, self.frame, anchorPoint,
            markerSettings.XOffset or 0, markerSettings.YOffset or 0)
    end

    self:ApplyPosition()
end

---------------------------------------------------------------------------------
-- Bar color / kick indicator / tick positioning
---------------------------------------------------------------------------------

function H.UpdateBarColor(self, interruptDuration)
    if not self.castBar then return end
    local kick = self.db.KickIndicator
    local texture = self.castBar:GetStatusBarTexture()
    local hasActiveCast = self.casting or self.channeling or self.empowering

    if self.isPreview then
        local r, g, b, a = KE:ResolveColor(self.db.CastingColor, { 1, 0.7, 0, 1 })
        texture:SetVertexColor(r, g, b, a)
        return
    end

    if kick and kick.Enabled and self.interruptId and hasActiveCast then
        local cooldown = interruptDuration or C_Spell.GetSpellCooldownDuration(self.interruptId)
        if not cooldown then return end

        local interruptibleColor = C_CurveUtil.EvaluateColorFromBoolean(
            cooldown:IsZero(),
            self.colors.Ready,
            self.colors.NotReady
        )
        texture:SetVertexColorFromBoolean(self.notInterruptible, self.colors.Uninterruptible, interruptibleColor)
        return
    end

    if kick and kick.Enabled and hasActiveCast then
        texture:SetVertexColorFromBoolean(self.notInterruptible, self.colors.Uninterruptible, self.colors.NotReady)
        return
    end

    local r, g, b, a
    if self.channeling then
        r, g, b, a = KE:ResolveColor(self.db.ChannelingColor, { 0, 0.7, 1, 1 })
    elseif self.empowering then
        r, g, b, a = KE:ResolveColor(self.db.EmpoweringColor, { 0.8, 0.4, 1, 1 })
    else
        r, g, b, a = KE:ResolveColor(self.db.CastingColor, { 1, 0.7, 0, 1 })
    end
    texture:SetVertexColor(r, g, b, a)
end

function H.UpdateKickIndicator(self, cooldown)
    local kick = self.db.KickIndicator
    if not kick or not kick.Enabled or not self.interruptId then
        self.kickTick:SetAlpha(0)
        return
    end

    if self.isPreview then
        self.kickTick:SetAlpha(0)
        return
    end

    if not cooldown and self.interruptId then
        cooldown = C_Spell.GetSpellCooldownDuration(self.interruptId)
    end
    if not cooldown then return end

    self.kickTick:SetAlphaFromBoolean(cooldown:IsZero(), 0,
        C_CurveUtil.EvaluateColorValueFromBoolean(self.notInterruptible, 0, 1))

    H.UpdateBarColor(self, cooldown)
end

function H.UpdateTickPosition(self, duration)
    local kick = self.db.KickIndicator
    if not kick or not kick.Enabled or not self.interruptId then return end

    -- kickCooldownBar's value is set once in SetupKickCooldownBar (ExwindTools
    -- pattern); the tick's pixel position is locked for the life of the cast.
    -- Only the invisible positioner still tracks cast elapsed here — kept in
    -- case other code reads it, but no longer anchors anything.
    self.positioner:SetValue(duration:GetElapsedDuration())
end

function H.SetupKickCooldownBar(self)
    local kick = self.db.KickIndicator
    if not kick or not kick.Enabled or not self.interruptId then
        self.kickTick:SetAlpha(0)
        return
    end

    local duration = self.cachedDuration
    if not duration then
        self.kickTick:SetAlpha(0)
        return
    end

    local _, height = self.castBar:GetSize()
    local isChannel = self.channeling or false

    self.positioner:SetMinMaxValues(0, duration:GetTotalDuration())
    self.positioner:SetReverseFill(isChannel)

    -- ExwindTools-style: kickCooldownBar is a full-width overlay on castBar
    -- (not chain-anchored to positioner). Value is set ONCE here to the
    -- current kick CD remaining; the tick anchored to the bar's fill edge
    -- then stays pinned for the life of the cast. SetValue accepts the
    -- secret Duration return natively — no arithmetic or laundering needed.
    self.kickCooldownBar:ClearAllPoints()
    self.kickCooldownBar:SetAllPoints(self.castBar)
    self.kickCooldownBar:SetReverseFill(isChannel)
    self.kickCooldownBar:SetMinMaxValues(0, duration:GetTotalDuration())
    local cooldown = C_Spell.GetSpellCooldownDuration(self.interruptId)
    if cooldown then
        self.kickCooldownBar:SetValue(cooldown:GetRemainingDuration())
    else
        self.kickCooldownBar:SetValue(0)
    end

    self.kickTick:ClearAllPoints()
    self.kickTick:SetSize(2, height)
    if isChannel then
        self.kickTick:SetPoint("RIGHT", self.kickCooldownBar:GetStatusBarTexture(), "LEFT")
    else
        self.kickTick:SetPoint("LEFT", self.kickCooldownBar:GetStatusBarTexture(), "RIGHT")
    end
end

---------------------------------------------------------------------------------
-- Target names
---------------------------------------------------------------------------------

function H.UpdateTargetNames(self)
    if not self.targetNames then return end
    local targetSettings = self.db.TargetNames or {}

    -- Always hide the 2..N slots. The old per-party-member pattern relied on
    -- UnitIsSpellTarget(caster, partyUnit) returning true when a teammate was
    -- being targeted, but 12.0 locked that down (only PlayerIsSpellTarget is
    -- documented, and party-member checks silently fail). We now show a single
    -- target name via UnitSpellTargetName — same pattern as DungeonCasts.
    for i = 2, MAX_TARGET_NAMES do
        self.targetNames[i]:SetAlpha(0)
    end

    local targetText = self.targetNames[1]
    if not targetSettings.Enabled or self.isPreview then
        targetText:SetAlpha(0)
        return
    end

    local unit = self.unit
    if not UnitExists(unit) or not (self.casting or self.channeling or self.empowering) then
        targetText:SetAlpha(0)
        return
    end

    -- UnitSpellTargetName returns the target's NAME (cstring), secret when
    -- the target is a player. SetText accepts secret strings directly. We
    -- separate name (SetText) and color (SetTextColor with clean r/g/b)
    -- here for clarity, but empirical testing on UNIT_SPELLCAST_INTERRUPTED
    -- (see H.GetColoredNameFromGUID above, 2026-05-03) shows that secret
    -- cstrings ALSO survive WrapTextInColorCode/string.format/SetText
    -- without taint errors — so concat with color codes is not a hazard,
    -- just less readable than the split SetText + SetTextColor pattern.
    local targetName = UnitSpellTargetName and UnitSpellTargetName(unit) or nil
    if not targetName then
        targetText:SetAlpha(0)
        return
    end

    -- Class color via C_ClassColor.GetClassColor (SecretArguments=AllowedWhenTainted,
    -- returns a clean ColorMixin). SetTextColor with clean r/g/b values avoids
    -- any concatenation with the (possibly secret) target name.
    local targetClass = UnitSpellTargetClass and UnitSpellTargetClass(unit) or nil
    local textColor = self.db.TextColor or { 1, 1, 1, 1 }
    local colored = false
    if targetClass then
        local color = C_ClassColor.GetClassColor(targetClass)
        if color then
            targetText:SetTextColor(color.r, color.g, color.b, color.a or 1)
            colored = true
        end
    end
    if not colored then
        targetText:SetTextColor(textColor[1], textColor[2], textColor[3], textColor[4] or 1)
    end

    targetText:SetText(targetName)
    targetText:SetAlpha(1)
end

function H.HideTargetNames(self)
    if not self.targetNames then return end
    for i = 1, MAX_TARGET_NAMES do
        self.targetNames[i]:SetAlpha(0)
    end
end

---------------------------------------------------------------------------------
-- Cast lifecycle
---------------------------------------------------------------------------------

function H.StartCast(self)
    local unit = self.unit
    if not self.frame or not UnitExists(unit) then return end
    local name, text, texture, castID, notInterruptible, spellID, isEmpowered
    local duration, direction = nil, Enum.StatusBarTimerDirection.ElapsedTime

    name, text, texture, _, _, _, castID, notInterruptible, spellID = UnitCastingInfo(unit)
    if name then
        self.casting, self.channeling, self.empowering = true, nil, nil
        duration = UnitCastingDuration(unit)
    else
        name, text, texture, _, _, _, notInterruptible, spellID, isEmpowered, _, castID = UnitChannelInfo(unit)
        if name then
            self.casting = nil
            if isEmpowered then
                self.empowering, self.channeling = true, nil
                duration = UnitEmpoweredChannelDuration(unit)
            else
                self.channeling, self.empowering = true, nil
                duration = UnitChannelDuration(unit)
                direction = Enum.StatusBarTimerDirection.RemainingTime
            end
        end
    end

    if not name then
        if not self.holdTimer then
            H.ResetCastState(self)
            self.frame:Hide()
        end
        return
    end

    if self.holdTimer then
        self.holdTimer:Cancel()
        self.holdTimer = nil
    end

    self.castID, self.spellID, self.spellName = castID, spellID, text or name
    self.notInterruptible = notInterruptible

    if self.db.HideNotInterruptible then
        self.frame:SetAlphaFromBoolean(notInterruptible, 0, 1)
    else
        self.frame:SetAlpha(1)
    end

    self.castBar:SetTimerDuration(duration, Enum.StatusBarInterpolation.Immediate, direction)
    self.cachedDuration = duration

    local isChannel = self.channeling == true
    self.positioner:SetReverseFill(isChannel)

    if duration then
        self.positioner:SetMinMaxValues(0, duration:GetTotalDuration())
    end
    self.positioner:SetValue(0)

    self.icon:SetTexture(texture or FALLBACK_ICON)
    self.spark:Show()
    self.text:SetText(text or name or "")
    self.time:SetText("")

    H.UpdateBarColor(self)
    H.SetupKickCooldownBar(self)
    H.UpdateTargetNames(self)
    H.UpdateTargetMarker(self)
    if self.PlayCastSound then self:PlayCastSound() end
    H.EnsureOnUpdate(self)
    self.frame:Show()
end

function H.EndCast(self, showHold, wasInterrupted, interruptedBy)
    if not self.frame or not self.frame:IsShown() then return end
    if self.holdTimer then return end

    local holdSettings = self.db.HoldTimer
    if not holdSettings or not holdSettings.Enabled then
        self.spark:Hide()
        H.HideTargetNames(self)
        H.HideTargetMarker(self)
        H.ResetCastState(self)
        self.frame:Hide()
        return
    end

    self.spark:Hide()
    self.kickTick:SetAlpha(0)
    H.HideTargetNames(self)
    H.HideTargetMarker(self)

    self.castBar:SetMinMaxValues(0, 1)
    self.castBar:SetValue(1)
    self.positioner:SetMinMaxValues(0, 1)
    self.positioner:SetValue(1)
    self.time:SetText("")

    local texture = self.castBar:GetStatusBarTexture()
    if wasInterrupted then
        local interrupterName = interruptedBy and H.GetColoredNameFromGUID(interruptedBy)
        if interrupterName then
            self.text:SetText(("Interrupted by %s"):format(interrupterName))
        else
            self.text:SetText("Interrupted")
        end
        local r, g, b, a = KE:ResolveColor(holdSettings.InterruptedColor, { 0.1, 0.8, 0.1, 1 })
        texture:SetVertexColor(r, g, b, a)
    elseif showHold then
        local r, g, b, a = KE:ResolveColor(holdSettings.FailedColor, { 0.5, 0.5, 0.5, 1 })
        texture:SetVertexColor(r, g, b, a)
    else
        local r, g, b, a = KE:ResolveColor(holdSettings.SuccessColor, { 0.8, 0.1, 0.1, 1 })
        texture:SetVertexColor(r, g, b, a)
    end

    H.ResetCastState(self)

    local holdDuration = holdSettings.Duration or 0.5
    self.holdTimer = C_Timer.NewTimer(holdDuration, function()
        self.holdTimer = nil
        if self.frame and not (self.casting or self.channeling or self.empowering) then
            self.frame:Hide()
        end
    end)
end

function H.UpdateInterruptible(self)
    if not self.frame or not self.frame:IsShown() then return end
    local unit = self.unit
    -- notInterruptible is a secret boolean in 12.0.5 — cannot use `or` operator
    local notInterruptible
    if self.casting then
        notInterruptible = select(8, UnitCastingInfo(unit))
    else
        notInterruptible = select(7, UnitChannelInfo(unit))
    end
    -- Guard against transient nil (UnitCastingInfo/UnitChannelInfo can return
    -- empty during a race between the event firing and cast-state settling).
    -- SetVertexColorFromBoolean rejects nil, so keep the prior cast's flag
    -- rather than overwriting with nil. Next INTERRUPTIBLE event resolves.
    if notInterruptible ~= nil then
        self.notInterruptible = notInterruptible
    end

    if self.db.HideNotInterruptible and notInterruptible ~= nil then
        self.frame:SetAlphaFromBoolean(notInterruptible, 0, 1)
    end

    H.UpdateBarColor(self)
end

function H.OnCastEvent(self, event, unit, ...)
    if unit ~= self.unit then return end
    if event:find("START") then
        H.StartCast(self)
    elseif event:find("STOP") then
        local interruptedBy
        if event:find("CHANNEL") then
            interruptedBy = select(3, ...)
        elseif event:find("EMPOWER") then
            interruptedBy = select(4, ...)
        end
        local wasInterrupted = interruptedBy ~= nil
        H.EndCast(self, wasInterrupted, wasInterrupted, interruptedBy)
    elseif event:find("INTERRUPTED") then
        local interruptedBy = select(3, ...)
        if DEBUG_CB then
            local byStr
            if interruptedBy == nil then
                byStr = "<nil>"
            elseif KE:IsSafeValue(interruptedBy) then
                byStr = tostring(interruptedBy)
            else
                byStr = "<secret>"
            end
            local playerGUID = UnitGUID("player")
            local petGUID = UnitGUID("pet")
            KE:Print(("[CB] INTERRUPTED unit=%s interruptedBy=%s player=%s pet=%s"):format(
                tostring(unit), byStr, tostring(playerGUID), tostring(petGUID)))
        end
        H.EndCast(self, true, true, interruptedBy)
    elseif event:find("FAILED") then
        H.EndCast(self, true, false)
    elseif event:find("INTERRUPTIBLE") then
        H.UpdateInterruptible(self)
    end
end

function H.OnUnitChanged(self)
    local unit = self.unit
    if UnitExists(unit) then
        H.StartCast(self)
        H.UpdateTargetMarker(self)
    else
        H.HideTargetNames(self)
        H.ResetCastState(self)
        if self.holdTimer then
            self.holdTimer:Cancel()
            self.holdTimer = nil
        end
        if self.targetMarker then self.targetMarker:Hide() end
        if self.frame then self.frame:Hide() end
    end
end

---------------------------------------------------------------------------------
-- Raid-target marker (NUI v3.10 port). Module opts in by populating
-- db.TargetMarker; FocusCastbar does, TargetCastbar does not. The owning
-- module wires RAID_TARGET_UPDATE -> H.UpdateTargetMarker via its own event
-- registration; H.ToggleTargetMarkerIntegration is a convenience for live
-- toggle of the Enabled flag.
---------------------------------------------------------------------------------
function H.UpdateTargetMarker(self)
    if not self.targetMarker then return end
    local markerSettings = self.db.TargetMarker
    if not markerSettings or not markerSettings.Enabled then
        self.targetMarker:Hide()
        return
    end

    local index = GetRaidTargetIndex(self.unit)
    if index == nil then
        self.targetMarker:Hide()
    else
        SetRaidTargetIconTexture(self.targetMarker, index)
        self.targetMarker:Show()
    end
end

function H.HideTargetMarker(self)
    if self.targetMarker then self.targetMarker:Hide() end
end

-- Called from UNIT_TARGET. Refresh target-name overlay when a party member or
-- the tracked unit retargets; ignore unrelated units.
function H.OnUnitTarget(self, _, unit)
    if not unit then return end
    if unit == self.unit or unit == "player" or unit:find("^party") then
        H.UpdateTargetNames(self)
    end
end

function H.OnGroupRosterUpdate(self)
    H.UpdateTargetNames(self)
end

---------------------------------------------------------------------------------
-- OnUpdate / preview
---------------------------------------------------------------------------------

function H.StartPreviewTimer(self)
    local duration = C_DurationUtil.CreateDuration()
    duration:SetTimeFromStart(GetTime(), PREVIEW_DURATION)
    self.castBar:SetTimerDuration(duration, Enum.StatusBarInterpolation.Immediate,
        Enum.StatusBarTimerDirection.ElapsedTime)

    self.cachedDuration = duration
    self.positioner:SetMinMaxValues(0, PREVIEW_DURATION)
    self.positioner:SetReverseFill(false)
    self.positioner:SetValue(0)
end

-- 30 FPS sampling — smoother decimal sweep in the 0.9 -> 0.1 window than
-- 10 Hz, and matches the throttle used by DungeonCasts. We can't apply the
-- DungeonTimers dirty-check (`if timeStr ~= _lastTimeStr`) here because
-- duration is secret for hostile/encounter casts and equality on a secret
-- value is forbidden — see feedback_dirty_check_secret_durations memory.
local UPDATE_THROTTLE = 0.033
local TARGET_NAMES_THROTTLE = 0.5  -- belt-and-suspenders fallback; primary driver is UNIT_TARGET / GROUP_ROSTER_UPDATE events

function H.OnUpdate(self, elapsed)
    self._updateElapsed = (self._updateElapsed or 0) + elapsed
    self._targetNamesElapsed = (self._targetNamesElapsed or 0) + elapsed
    local hasActiveCast = self.casting or self.channeling or self.empowering
    local duration = self.cachedDuration

    if hasActiveCast and duration then
        local cooldown = self.interruptId and C_Spell.GetSpellCooldownDuration(self.interruptId) or nil
        H.UpdateTickPosition(self, duration)
        H.UpdateKickIndicator(self, cooldown)
    else
        self.kickTick:SetAlpha(0)
    end

    if self._updateElapsed < UPDATE_THROTTLE then return end

    if self.holdTimer then
        self._updateElapsed = 0
        return
    end

    if not duration then
        self._updateElapsed = 0
        return
    end

    local remaining = duration:GetRemainingDuration()
    if not remaining then
        self._updateElapsed = 0
        return
    end

    local decimals = duration:EvaluateRemainingDuration(KE.curves.DurationDecimals)
    self.time:SetFormattedText('%.' .. decimals .. 'f', remaining)

    if hasActiveCast and self._targetNamesElapsed >= TARGET_NAMES_THROTTLE then
        H.UpdateTargetNames(self)
        self._targetNamesElapsed = 0
    end

    if not hasActiveCast then
        H.HideTargetNames(self)
        H.ResetCastState(self)
        if self.frame then self.frame:Hide() end
    end

    self._updateElapsed = 0
end

function H.EnsureOnUpdate(self)
    if self.frame and not self.frame:GetScript("OnUpdate") then
        self.frame:SetScript("OnUpdate", function(_, elapsed) H.OnUpdate(self, elapsed) end)
    end
end

---------------------------------------------------------------------------------
-- Edit mode / preview
---------------------------------------------------------------------------------

-- opts: { key, displayName, guiPath }
function H.RegWithEditMode(self, opts)
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = opts.key, displayName = opts.displayName, frame = self.frame,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos) self.db.Position = pos; KE:ApplyFramePosition(self.frame, self.db.Position, self.db) end,
            getParentFrame = function() return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) end,
            guiPath = opts.guiPath,
        })
        self.editModeRegistered = true
    end
end

-- opts: { previewText }
function H.ShowPreview(self, opts)
    if not self.frame then self:CreateFrame() end
    self:RegWithEditMode()
    self.isPreview, self.casting = true, true
    self.icon:SetTexture(FALLBACK_ICON)
    self.text:SetText(opts.previewText)
    self.spark:Show()
    self.kickTick:SetAlpha(0)
    H.UpdateBarColor(self)
    self:ApplySettings()
    H.StartPreviewTimer(self)
    H.EnsureOnUpdate(self)
    self.frame:Show()

    if self.targetNames then
        -- Preview mirrors the live single-target-name pattern: one slot,
        -- class-colored via SetTextColor, others hidden. Uses the player's
        -- own name/class since there's no real caster targeting anyone.
        local targetText = self.targetNames[1]
        local name = UnitName("player")
        local classToken = select(2, UnitClass("player"))
        targetText:SetText(name or "")
        local color = classToken and C_ClassColor.GetClassColor(classToken)
        if color then
            targetText:SetTextColor(color.r, color.g, color.b, color.a or 1)
        else
            local tr, tg, tb, ta = KE:ResolveColor(self.db.TextColor, { 1, 1, 1, 1 })
            targetText:SetTextColor(tr, tg, tb, ta)
        end
        targetText:SetAlpha(1)
        for i = 2, MAX_TARGET_NAMES do
            self.targetNames[i]:SetAlpha(0)
        end
    end

    -- Preview shows a random raid icon (1-8) when the marker is enabled, so
    -- users can position/size visually without needing a marked focus target.
    if self.targetMarker then
        local markerSettings = self.db.TargetMarker
        if markerSettings and markerSettings.Enabled then
            SetRaidTargetIconTexture(self.targetMarker, random(1, 8))
            self.targetMarker:Show()
        else
            self.targetMarker:Hide()
        end
    end

    if self.previewTicker then self.previewTicker:Cancel() end
    self.previewTicker = C_Timer.NewTicker(PREVIEW_DURATION, function()
        if self.isPreview then
            H.StartPreviewTimer(self)
        end
    end)
end

function H.HidePreview(self)
    self.isPreview, self.casting = false, nil
    if self.previewTicker then
        self.previewTicker:Cancel()
        self.previewTicker = nil
    end
    H.HideTargetNames(self)
    H.HideTargetMarker(self)
    if self.frame and not (self.casting or self.channeling or self.empowering) then
        self.frame:Hide()
    end
end

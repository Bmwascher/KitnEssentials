-- ╔══════════════════════════════════════════════════════════╗
-- ║  CombatTexts.lua                                         ║
-- ║  Module: Combat Texts                                    ║
-- ║  Purpose: Floating text notifications for combat enter/  ║
-- ║           exit, interrupt announce with spell icon,      ║
-- ║           low durability and aggro warnings.             ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class CombatTexts: AceModule, AceEvent-3.0
local CM = KitnEssentials:NewModule("CombatTexts", "AceEvent-3.0")

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local UIFrameFadeRemoveFrame = UIFrameFadeRemoveFrame
local InCombatLockdown = InCombatLockdown
local UnitExists = UnitExists
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local GetInventoryItemDurability = GetInventoryItemDurability
local GetTime = GetTime
local UnitGUID = UnitGUID
local UnitCanAttack = UnitCanAttack
local UnitThreatSituation = UnitThreatSituation
local PlaySoundFile = PlaySoundFile
local C_Spell_GetSpellName = C_Spell.GetSpellName
local C_Spell_GetSpellTexture = C_Spell.GetSpellTexture
local ipairs, pairs = ipairs, pairs
local math_max = math.max
local string_format = string.format

-- Flip to true to log the classified landed-event decision tuple.
local DEBUG_CT = false

local EQUIP_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }
local INTERRUPT_ICON_GAP = 4
local INTERRUPT_FONT_EMPHASIS = 2
local REVERSE_EVENT_WINDOW = 0.05
local SPELL_LINK_BLUE = { 127 / 255, 207 / 255, 241 / 255 }
local AGGRO_MIN_STATUS = 2
local AGGRO_SOUND_GAP = 2
local AGGRO_PULSE_ALPHA = 0.35
local AGGRO_PULSE_DURATION = 0.45

local MESSAGE_TYPES = {
    "enterCombat",
    "exitCombat",
    "noTarget",
    "lowDurability",
    "interrupt",
    "aggro",
}

local EXTERNAL_LINE_TYPES = {
    "petStatus",
}
local IS_EXTERNAL_LINE = {}
for _, key in ipairs(EXTERNAL_LINE_TYPES) do IS_EXTERNAL_LINE[key] = true end

-- Frames other modules attach below the lines, top to bottom. Havoc stays
-- last: the game draws its text and will not say whether it is shown, so
-- nothing may sit below it.
local ATTACHED_FRAME_TYPES = {
    "potionReady",
    "stanceText",
    "noMovement",
    "shamanProcs",
    "huntersMark",
    "havoc",
}
local IS_ATTACHED_FRAME = {}
for _, key in ipairs(ATTACHED_FRAME_TYPES) do IS_ATTACHED_FRAME[key] = true end

CM.container = nil
CM.messageFrames = {}
CM.activeMessages = {}
CM.isPreview = false
CM.inCombat = false
CM.noTargetCheckGeneration = 0
CM.interruptCastFrame = nil
CM.interruptEventsRegistered = false
CM.interruptAnnounceSpells = nil
CM.pendingInterruptAt = nil
CM.pendingInterruptSpellID = nil
CM.pendingInterruptUnit = nil
CM.lastAcceptedCastGUID = nil
CM.lastUnkeyedAcceptAt = nil
CM.reverseInterruptAt = nil
CM.reverseInterruptSuccessSpellID = nil
CM.aggroEventFrame = nil
CM.aggroEventsRegistered = false
CM.aggroSoundBlocked = false
CM.aggroPulse = nil
CM.attachedFrames = {}
CM.attachedInsets = {}
CM.arrangedShown = {}
CM.arrangedHeight = {}
-- Per attached key: the KE spacer the frame hangs under, whether the frame is
-- seated on it, and the offset last applied.
CM.attachSpacers = {}
-- A zero-height region has no usable bottom edge, so a spacer is always this
-- much taller than its offset and the frame hangs this far above its bottom.
CM.SPACER_LIFT = 1
CM.attachSeated = {}
CM.attachTop = {}
-- Per line: the last known shown state and height, and the top it was last
-- placed at. A plain read refreshes them.
CM.lineShown = {}
CM.lineHeight = {}
CM.lineTop = {}

-- KE records what it writes to a stacked line, so a later secret read gets
-- the right answer from ReadShownHeight's cache, a line built while reads
-- are secret included.
local function SetLineShown(self, frame, key, shown)
    if shown then frame:Show() else frame:Hide() end
    self.lineShown[key] = shown
end

local function SetLineHeight(self, frame, key, height)
    frame:SetHeight(height)
    self.lineHeight[key] = height
end
-- Sent on enable and disable, and from ApplySettings once the container
-- exists, so an attached module can move between its own anchor and this
-- stack and pick up the font.
CM.CHANGED_MESSAGE = "KitnEssentials_CombatTextsChanged"

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function CM:UpdateDB()
    self.db = KE.db.profile.CombatTexts
end

function CM:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

local function GetMessageConfig(db, msgType)
    if msgType == "enterCombat" then
        return db.EnterEnabled ~= false,
            db.EnterCombatText or "+ Combat",
            db.EnterColor or { 1, 0.1, 0.1, 1 }
    elseif msgType == "exitCombat" then
        return db.ExitEnabled ~= false,
            db.ExitCombatText or "- Combat",
            db.ExitColor or { 0.1, 1, 0.1, 1 }
    elseif msgType == "noTarget" then
        return db.NoTargetEnabled == true,
            db.NoTargetText or "NO TARGET",
            db.NoTargetColor or { 1, 0.8, 0, 1 }
    elseif msgType == "lowDurability" then
        return db.DurabilityEnabled ~= false,
            db.DurabilityText or "LOW DURABILITY",
            db.DurabilityColor or { 1, 0.3, 0.3, 1 }
    elseif msgType == "interrupt" then
        return db.InterruptEnabled ~= false,
            (db.InterruptText or "Interrupted") .. " [Spell Name]",
            db.InterruptColor or { 1, 1, 1, 1 }
    elseif msgType == "aggro" then
        return db.AggroEnabled ~= false,
            db.AggroText or "AGGRO",
            db.AggroColor or { 1, 0.15, 0.15, 1 }
    end
    return false, "", { 1, 1, 1, 1 }
end

---------------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------------
function CM:CreateContainer()
    if self.container then return end

    local container = CreateFrame("Frame", "KE_CombatTextsContainer", UIParent)
    container:SetSize(200, 100)
    KE:ApplyFramePosition(container, self.db.Position, self.db)
    container:SetFrameLevel(100)

    self.container = container
end

function CM:GetMessageFrame(msgType)
    if self.messageFrames[msgType] then
        return self.messageFrames[msgType]
    end

    local frame = CreateFrame("Frame", nil, self.container)
    local fontSize = self.db.FontSize or 16
    frame:SetWidth(200)
    SetLineHeight(self, frame, msgType, fontSize + 2)
    frame:Hide()

    local text = frame:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")
    text:SetWordWrap(false)

    frame.text = text
    frame.msgType = msgType
    frame.generation = 0

    self.messageFrames[msgType] = frame

    if msgType == "interrupt" then
        SetLineHeight(self, frame, msgType, fontSize + INTERRUPT_FONT_EMPHASIS * 2)
        local icon = frame:CreateTexture(nil, "OVERLAY")
        icon:SetSize(fontSize + INTERRUPT_FONT_EMPHASIS, fontSize + INTERRUPT_FONT_EMPHASIS)
        -- Trim the baked spell-icon border.
        icon:SetTexCoord(5 / 64, 59 / 64, 5 / 64, 59 / 64)
        icon:SetPoint("CENTER", frame, "CENTER", 0, 0)
        icon:Hide()
        frame.interruptIcon = icon

        local name = frame:CreateFontString(nil, "OVERLAY")
        name:SetPoint("LEFT", icon, "RIGHT", INTERRUPT_ICON_GAP, 0)
        name:SetJustifyH("LEFT")
        name:SetJustifyV("MIDDLE")
        name:SetWordWrap(false)
        name:Hide()
        frame.interruptName = name

        KE:ApplyFont(text, self.db.FontFace, fontSize + INTERRUPT_FONT_EMPHASIS,
            KE:GetFontOutline(self.db.FontOutline))
        text:SetHeight(fontSize + INTERRUPT_FONT_EMPHASIS * 2)
        KE:ApplyFont(name, self.db.FontFace, fontSize,
            KE:GetFontOutline(self.db.FontOutline))
        name:SetHeight(fontSize + INTERRUPT_FONT_EMPHASIS * 2)
    else
        KE:ApplyFontToText(text, self.db.FontFace, self.db.FontSize, self.db.FontOutline)
    end

    return frame
end

---------------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------------
-- In combat the game can refuse a layout write. The engine's Havoc aura button
-- hangs on an attached frame, so the container is asked as well as the frame.
local function CanMove(self, frame)
    return KE:CanReanchorNow(frame) and KE:CanReanchorNow(self.container)
end

-- A secret read returns the last recorded answer; arithmetic on it would error.
local function ReadShownHeight(frame, shownCache, heightCache, key)
    local shown, height = frame:IsShown(), frame:GetHeight()
    if KE:IsSecretValue(shown) or KE:IsSecretValue(height) then
        return shownCache[key], heightCache[key]
    end
    shownCache[key], heightCache[key] = shown, height
    return shown, height
end

-- A secret IsShown read answers ifSecret instead; a truth test on it errors.
local function IsShownOr(frame, ifSecret)
    local shown = frame:IsShown()
    if KE:IsSecretValue(shown) then return ifSecret end
    return shown
end

-- A refused move leaves a line where it was; what follows starts below both
-- its old and its new place.
local function StackFrames(self, types, yOffset, spacing)
    for _, msgType in ipairs(types) do
        local frame = self.messageFrames[msgType]
        if frame then
            local shown, height = ReadShownHeight(frame, self.lineShown, self.lineHeight, msgType)
            if shown and height then
                local top = self.lineTop[msgType]
                if top ~= yOffset and CanMove(self, frame) then
                    frame:ClearAllPoints()
                    frame:SetPoint("TOP", self.container, "TOP", 0, -yOffset)
                    top = yOffset
                    self.lineTop[msgType] = top
                end
                yOffset = math_max(yOffset, top or yOffset) + height + spacing
            end
        end
    end
    return yOffset
end

-- Seated once, by SetPoint, under a KE spacer anchored to the container top.
-- Later moves only resize the spacer, so no arrange re-anchors a frame the
-- engine's aura button hangs on.
local function SeatAttached(self, key, frame)
    if self.attachSeated[key] then return true end
    local spacer = self.attachSpacers[key]
    if not CanMove(self, frame) or (spacer and not CanMove(self, spacer)) then return false end
    if not spacer then
        spacer = CreateFrame("Frame", nil, self.container)
        spacer:SetSize(1, self.SPACER_LIFT)
        spacer:SetPoint("TOP", self.container, "TOP", 0, 0)
        self.attachSpacers[key] = spacer
    end
    frame:ClearAllPoints()
    frame:SetPoint("TOP", spacer, "BOTTOM", 0, self.SPACER_LIFT)
    self.attachSeated[key] = true
    self.attachTop[key] = nil
    return true
end

function CM:ArrangeMessages()
    if not self.container then return end
    local spacing = self.db.Spacing or 4
    local yOffset = StackFrames(self, MESSAGE_TYPES, 0, spacing)
    yOffset = StackFrames(self, EXTERNAL_LINE_TYPES, yOffset, spacing)

    -- Lines only: the container can be anchored at its center, so counting
    -- attached frames would move the lines every time one shows.
    if KE:CanReanchorNow(self.container) then
        self.container:SetHeight(math_max(30, yOffset - spacing))
    end

    for _, key in ipairs(ATTACHED_FRAME_TYPES) do
        local frame = self.attachedFrames[key]
        if frame then
            local shown, height = ReadShownHeight(frame, self.arrangedShown, self.arrangedHeight, key)
            if shown and height then
                local top = yOffset + (self.attachedInsets[key] or 0)
                local placed = self.attachTop[key]
                if placed ~= top and SeatAttached(self, key, frame)
                    and CanMove(self, self.attachSpacers[key]) then
                    self.attachSpacers[key]:SetHeight(top + self.SPACER_LIFT)
                    placed = top
                    self.attachTop[key] = top
                end
                yOffset = math_max(top, placed or top) + height + spacing
            end
        end
    end
end

---------------------------------------------------------------------------------
-- Core Logic
---------------------------------------------------------------------------------
function CM:ShowFlashMessage(msgType, textOverride, iconOverride, nameOverride)
    if not self.db or self.db.Enabled == false then return end
    if self.isPreview then return end

    local enabled, msgText, color = GetMessageConfig(self.db, msgType)
    if not enabled then return end
    if textOverride ~= nil then msgText = textOverride end

    local frame = self:GetMessageFrame(msgType)
    if not frame then return end
    if frame.interruptIcon then
        if iconOverride ~= nil and nameOverride ~= nil then
            frame.text:ClearAllPoints()
            frame.text:SetPoint("RIGHT", frame.interruptIcon, "LEFT", -INTERRUPT_ICON_GAP, 0)
            frame.interruptIcon:SetTexture(iconOverride)
            frame.interruptName:SetText("[" .. nameOverride .. "]")
            frame.interruptIcon:Show()
            frame.interruptName:Show()
        else
            frame.text:ClearAllPoints()
            frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
            frame.interruptIcon:Hide()
            frame.interruptName:Hide()
        end
    end

    local duration
    if msgType == "enterCombat" or msgType == "exitCombat" then
        duration = self.db.CombatDuration or 1.5
    elseif msgType == "interrupt" then
        duration = self.db.InterruptDuration or 3.0
    else
        duration = 1.5
    end
    frame.generation = frame.generation + 1
    local myGeneration = frame.generation

    -- Stop any existing fade
    if UIFrameFadeRemoveFrame then
        UIFrameFadeRemoveFrame(frame)
    end
    frame:SetScript("OnUpdate", nil)

    -- Set text and color
    frame.text:SetText(msgText)
    frame.text:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    if frame.interruptName then
        frame.interruptName:SetTextColor(
            SPELL_LINK_BLUE[1], SPELL_LINK_BLUE[2], SPELL_LINK_BLUE[3], color[4] or 1)
    end

    -- Show and arrange
    frame:SetAlpha(1)
    SetLineShown(self, frame, msgType, true)
    self.activeMessages[msgType] = true
    self:ArrangeMessages()

    -- Fade out and hide
    local function HideIfCurrent()
        if frame.generation == myGeneration and not self.isPreview then
            SetLineShown(self, frame, msgType, false)
            -- Don't reset alpha here. Render tick can process a SetAlpha(1)
            -- as a visible frame before the Hide takes effect, flashing the
            -- text at full alpha.
            -- ShowFlashMessage does SetAlpha(1) on the next show path instead.
            self.activeMessages[msgType] = nil
            self:ArrangeMessages()
        end
    end

    -- Manual alpha fade rather than UIFrameFadeOut, which used to stack-overflow
    -- through the retired soft-outline hooks. Kept because it is known good and
    -- costs nothing: OnUpdate only runs during the fadeDuration window (not the full
    -- message duration), so per-frame cost is limited to ~0.4s per message.
    local fadeDuration = 0.4
    C_Timer.After(duration - fadeDuration, function()
        if frame.generation ~= myGeneration or self.isPreview then return end
        -- Secret reads as shown: the generation already proves this message,
        -- and skipping the fade would leave it on screen.
        if not IsShownOr(frame, true) then return end
        local fadeStart = GetTime()
        frame:SetScript("OnUpdate", function(f)
            if f.generation ~= myGeneration or self.isPreview then
                f:SetScript("OnUpdate", nil)
                return
            end
            local progress = (GetTime() - fadeStart) / fadeDuration
            if progress >= 1 then
                f:SetScript("OnUpdate", nil)
                HideIfCurrent()
            else
                f:SetAlpha(1 - progress)
            end
        end)
    end)
end

function CM:ShowPersistentMessage(msgType)
    if not self.db or self.db.Enabled == false then return end
    if self.isPreview then return end

    local enabled, msgText, color = GetMessageConfig(self.db, msgType)
    if not enabled then return end

    local frame = self:GetMessageFrame(msgType)
    if not frame then return end

    -- Stop any existing fade
    if UIFrameFadeRemoveFrame then
        UIFrameFadeRemoveFrame(frame)
    end
    frame:SetScript("OnUpdate", nil)

    frame.text:SetText(msgText)
    frame.text:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)

    frame:SetAlpha(1)
    SetLineShown(self, frame, msgType, true)
    self.activeMessages[msgType] = true
    self:ArrangeMessages()
end

function CM:HidePersistentMessage(msgType)
    local frame = self.messageFrames[msgType]
    if frame then
        SetLineShown(self, frame, msgType, false)
        self.activeMessages[msgType] = nil
        self:ArrangeMessages()
    end
end

---------------------------------------------------------------------------------
-- External Lines
---------------------------------------------------------------------------------
function CM.AttachWanted(toggleOn, moduleEnabled, dbEnabled, hasContainer)
    return toggleOn == true and moduleEnabled == true and dbEnabled == true
        and hasContainer == true
end

function CM.ResolveAttachedSize(attached, overrideOn, ownSize, ctSize)
    if attached and not overrideOn and ctSize ~= nil then return ctSize end
    return ownSize
end

function CM:AcceptsAttach(toggleOn)
    return CM.AttachWanted(toggleOn, self:IsEnabled(),
        self.db ~= nil and self.db.Enabled ~= false, self.container ~= nil)
end

function CM:AcceptsExternalLines()
    return self:AcceptsAttach(true)
end

-- Not refused during the preview: the line belongs to its owner, and the
-- preview never repaints or hides it. size is the owner's own text size, or
-- nil for the Combat Texts size.
function CM:ShowExternalLine(key, text, r, g, b, a, size)
    if not IS_EXTERNAL_LINE[key] or not self:AcceptsExternalLines() then return false end
    local frame = self:GetMessageFrame(key)
    if frame.sizeOverride ~= size then
        frame.sizeOverride = size
        local lineSize = size or self.db.FontSize or 16
        KE:ApplyFontToText(frame.text, self.db.FontFace, lineSize, self.db.FontOutline)
        SetLineHeight(self, frame, key, lineSize + 2)
    end
    frame.text:SetText(text)
    frame.text:SetTextColor(r or 1, g or 1, b or 1, a or 1)
    frame:SetAlpha(1)
    SetLineShown(self, frame, key, true)
    self:ArrangeMessages()
    return true
end

function CM:HideExternalLine(key)
    if not IS_EXTERNAL_LINE[key] then return end
    local frame = self.messageFrames[key]
    if not frame then return end
    local shown = frame:IsShown()
    if not KE:IsSecretValue(shown) and not shown then return end
    SetLineShown(self, frame, key, false)
    self:ArrangeMessages()
end

-- A nil frame detaches, which is never refused. topInset is room kept above
-- the frame for something drawn outside its bounds.
function CM:SetAttachedFrame(key, frame, topInset)
    if not IS_ATTACHED_FRAME[key] then return false end
    if frame == nil then
        if self.attachedFrames[key] == nil then return false end
        self.attachedFrames[key] = nil
        self.attachedInsets[key] = nil
        self.arrangedShown[key] = nil
        self.arrangedHeight[key] = nil
        self.attachSeated[key] = nil
        self.attachTop[key] = nil
        if self.container then self:ArrangeMessages() end
        return false
    end
    if not self:AcceptsAttach(true) then return false end
    -- A different frame for the same slot is seated afresh.
    if self.attachedFrames[key] ~= frame then
        self.attachSeated[key] = nil
        self.attachTop[key] = nil
    end
    self.attachedFrames[key] = frame
    self.attachedInsets[key] = topInset or 0
    self:ArrangeMessages()
    return true
end

-- Owners call this after every show, hide or resize; it re-arranges only when
-- the frame's shown state or height moved since the last arrange.
function CM:AttachedFrameChanged(key)
    local frame = self.attachedFrames[key]
    if not frame then return end
    local shown, height = frame:IsShown(), frame:GetHeight()
    if KE:IsSecretValue(shown) or KE:IsSecretValue(height) then return end
    if shown == self.arrangedShown[key] and height == self.arrangedHeight[key] then return end
    self:ArrangeMessages()
end

-- One subscription rule for every attacher: CHANGED_MESSAGE runs its
-- ApplySettings only while it is active and its attach toggle is on.
function CM:SyncAttachSubscription(owner, active)
    local wanted = active and owner.db ~= nil and owner.db.AttachToCombatTexts == true
    if wanted and not owner.attachMessage then
        owner:RegisterMessage(self.CHANGED_MESSAGE, "ApplySettings")
        owner.attachMessage = self.CHANGED_MESSAGE
    elseif not wanted and owner.attachMessage then
        owner:UnregisterMessage(owner.attachMessage)
        owner.attachMessage = nil
    end
end

---------------------------------------------------------------------------------
-- No Target Warning
---------------------------------------------------------------------------------
function CM:CheckNoTarget()
    if not self.db or self.db.Enabled == false then return end
    if self.isPreview then return end

    if UnitIsDeadOrGhost("player") then
        self:HidePersistentMessage("noTarget")
        return
    end

    if self.inCombat and self.db.NoTargetEnabled then
        self.noTargetCheckGeneration = self.noTargetCheckGeneration + 1
        local myGeneration = self.noTargetCheckGeneration

        C_Timer.After(0.1, function()
            if self.noTargetCheckGeneration ~= myGeneration then return end
            if not self.inCombat then return end
            if UnitIsDeadOrGhost("player") then
                self:HidePersistentMessage("noTarget")
                return
            end
            if not UnitExists("target") then
                self:ShowPersistentMessage("noTarget")
            else
                self:HidePersistentMessage("noTarget")
            end
        end)
    else
        self:HidePersistentMessage("noTarget")
    end
end

---------------------------------------------------------------------------------
-- Aggro Warning
---------------------------------------------------------------------------------
-- Pure, so the rule is spec-covered. A secret reading hides the line: a warning
-- that fails open would claim aggro the player does not have.
function CM.ShouldShowAggro(db, inCombat, isTank, inInstance, threat, threatSecret)
    if db.AggroEnabled == false then return false end
    if not inCombat then return false end
    if isTank then return false end
    if db.AggroInstanceOnly ~= false and not inInstance then return false end
    if threatSecret then return false end
    return type(threat) == "number" and threat >= AGGRO_MIN_STATUS
end

-- Built on first use, so a player who never turns Pulse on never gets one.
-- Held on the module, not the frame: spec mock frames answer every field.
local function SetAggroPulse(frame, on)
    if not frame then return end
    local pulse = CM.aggroPulse
    if on then
        if not pulse then
            pulse = frame:CreateAnimationGroup()
            pulse:SetLooping("BOUNCE")
            local fade = pulse:CreateAnimation("Alpha")
            fade:SetFromAlpha(1)
            fade:SetToAlpha(AGGRO_PULSE_ALPHA)
            fade:SetDuration(AGGRO_PULSE_DURATION)
            fade:SetSmoothing("IN_OUT")
            CM.aggroPulse = pulse
        end
        if not pulse:IsPlaying() then pulse:Play() end
    elseif pulse and pulse:IsPlaying() then
        pulse:Stop()
        if IsShownOr(frame, true) then frame:SetAlpha(1) end
    end
end

-- A one-shot timer re-arms the sound, so threat bouncing between the player
-- and the tank cannot stack plays.
function CM:PlayAggroSound()
    local db = self.db
    if not db.AggroSoundEnabled or self.aggroSoundBlocked then return end
    local file = db.AggroSoundFile
    if not file or file == "None" or not KE.LSM then return end
    local path = KE.LSM:Fetch("sound", file, true)
    if not path then return end
    PlaySoundFile(path, db.AggroSoundChannel or "Master")
    self.aggroSoundBlocked = true
    C_Timer.After(AGGRO_SOUND_GAP, function() self.aggroSoundBlocked = false end)
end

function CM:CheckAggro()
    if not self.db or self.db.Enabled == false then return end
    if self.isPreview then return end

    local ok, status = pcall(UnitThreatSituation, "player")
    local threat, threatSecret = nil, false
    if ok then
        threat = status
        threatSecret = KE:IsSecretValue(status)
    end
    local inInstance = KE:InRealInstancedContent()

    -- A secret shown state re-shows the line without the sound, which plays
    -- only on a plain hidden-to-shown edge, and still lets a hide run. The
    -- re-show resets alpha to 1, so a playing pulse may flash once per event.
    local frame = self.messageFrames.aggro
    if CM.ShouldShowAggro(self.db, self.inCombat, KE:IsPlayerTankSpec(), inInstance, threat, threatSecret) then
        if not (frame and IsShownOr(frame, false)) then
            self:ShowPersistentMessage("aggro")
            frame = self.messageFrames.aggro
            if frame and IsShownOr(frame, false) then self:PlayAggroSound() end
        end
        SetAggroPulse(frame, self.db.AggroPulse == true)
    elseif frame and IsShownOr(frame, true) then
        self:HidePersistentMessage("aggro")
        SetAggroPulse(frame, false)
    end
end

function CM:UpdateAggroEventRegistration(forceDisabled)
    local enabled = not forceDisabled
        and self:IsEnabled()
        and self.db
        and self.db.Enabled ~= false
        and self.db.AggroEnabled ~= false

    if enabled and not self.aggroEventsRegistered then
        if not self.aggroEventFrame then
            local frame = CreateFrame("Frame")
            frame:SetScript("OnEvent", function() self:CheckAggro() end)
            self.aggroEventFrame = frame
        end
        self.aggroEventFrame:RegisterUnitEvent("UNIT_THREAT_SITUATION_UPDATE", "player")
        -- A loading screen mid-combat can change the instance test with no
        -- threat change.
        self.aggroEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        self.aggroEventsRegistered = true
    elseif not enabled and self.aggroEventsRegistered then
        self.aggroEventFrame:UnregisterEvent("UNIT_THREAT_SITUATION_UPDATE")
        self.aggroEventFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
        self.aggroEventsRegistered = false
    end
end

---------------------------------------------------------------------------------
-- Event Handlers
---------------------------------------------------------------------------------
function CM:OnEnterCombat()
    self.inCombat = true
    self:HidePersistentMessage("lowDurability")
    self:ShowFlashMessage("enterCombat")
    self:CheckNoTarget()
    self:CheckAggro()
end

function CM:OnExitCombat()
    self.inCombat = false
    self.noTargetCheckGeneration = self.noTargetCheckGeneration + 1
    self:HidePersistentMessage("noTarget")
    self:ShowFlashMessage("exitCombat")
    self:CheckDurability()
    self:CheckAggro()
end

function CM:OnTargetChanged()
    self:CheckNoTarget()
end

function CM:OnPlayerDead()
    self.noTargetCheckGeneration = self.noTargetCheckGeneration + 1
    self:HidePersistentMessage("noTarget")
end

function CM:CheckDurability()
    if not self.db or self.db.Enabled == false then return end
    if self.isPreview then return end

    if self.db.DurabilityEnabled == false then
        self:HidePersistentMessage("lowDurability")
        return
    end

    local threshold = (self.db.DurabilityThreshold or 25) / 100

    if self.inCombat then
        self:HidePersistentMessage("lowDurability")
        return
    end

    local hasLow = false
    for _, slot in ipairs(EQUIP_SLOTS) do
        local current, maximum = GetInventoryItemDurability(slot)
        if current and maximum and maximum > 0 then
            if (current / maximum) < threshold then
                hasLow = true
                break
            end
        end
    end

    if hasLow then
        self:ShowPersistentMessage("lowDurability")
    else
        self:HidePersistentMessage("lowDurability")
    end
end

---------------------------------------------------------------------------------
-- Apply Settings
---------------------------------------------------------------------------------
function CM:ApplySettings()
    self:UpdateInterruptEventRegistration()
    self:UpdateAggroEventRegistration()
    if not self.container then return end
    KE:ApplyFramePosition(self.container, self.db.Position, self.db)

    -- Update font settings and frame height for all message frames
    local fontSize = self.db.FontSize or 16
    for _, frame in pairs(self.messageFrames) do
        SetLineHeight(self, frame, frame.msgType, (frame.sizeOverride or fontSize) + 2)
        if frame.text then
            if frame.msgType == "interrupt" then
                SetLineHeight(self, frame, frame.msgType, fontSize + INTERRUPT_FONT_EMPHASIS * 2)
                frame.interruptIcon:SetSize(fontSize + INTERRUPT_FONT_EMPHASIS,
                    fontSize + INTERRUPT_FONT_EMPHASIS)
                KE:ApplyFont(frame.text, self.db.FontFace, fontSize + INTERRUPT_FONT_EMPHASIS,
                    KE:GetFontOutline(self.db.FontOutline))
                frame.text:SetHeight(fontSize + INTERRUPT_FONT_EMPHASIS * 2)
                KE:ApplyFont(frame.interruptName, self.db.FontFace, fontSize,
                    KE:GetFontOutline(self.db.FontOutline))
                frame.interruptName:SetHeight(fontSize + INTERRUPT_FONT_EMPHASIS * 2)
            else
                KE:ApplyFontToText(frame.text, self.db.FontFace,
                    frame.sizeOverride or self.db.FontSize, self.db.FontOutline)
            end
        end
    end

    -- Update preview content if in preview mode
    if self.isPreview then
        for _, msgType in ipairs(MESSAGE_TYPES) do
            local frame = self.messageFrames[msgType]
            if frame then
                local _, msgText, msgColor = GetMessageConfig(self.db, msgType)
                if frame.interruptIcon then
                    frame.text:ClearAllPoints()
                    frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
                    frame.interruptIcon:Hide()
                    frame.interruptName:Hide()
                end
                frame.text:SetText(msgText)
                frame.text:SetTextColor(msgColor[1] or 1, msgColor[2] or 1, msgColor[3] or 1, msgColor[4] or 1)
                if frame.interruptName then
                    frame.interruptName:SetTextColor(
                        msgColor[1] or 1, msgColor[2] or 1, msgColor[3] or 1, msgColor[4] or 1)
                end
            end
        end
        SetAggroPulse(self.messageFrames.aggro, self.db.AggroPulse == true)
        self:ArrangeMessages()
    else
        self:CheckNoTarget()
        self:CheckAggro()
        self:ArrangeMessages()
    end
    self:SendMessage(self.CHANGED_MESSAGE)
end

function CM:ApplyPosition()
    if not self.container then return end
    KE:ApplyFramePosition(self.container, self.db.Position, self.db)
end

function CM:Refresh()
    self:ApplySettings()
end

---------------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------------
function CM:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "CombatTexts", displayName = "Combat Texts", frame = self.container,
            module = self,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos) self.db.Position = pos; KE:ApplyFramePosition(self.container, self.db.Position, self.db) end,
            getParentFrame = function() return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) end,
            guiPath = "CombatTexts",
        })
        self.editModeRegistered = true
    end
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------
function CM:ShowPreview()
    if not self.container then
        self:CreateContainer()
    end
    self:RegWithEditMode()

    self.isPreview = true

    for _, msgType in ipairs(MESSAGE_TYPES) do
        local frame = self:GetMessageFrame(msgType)
        if frame then
            local _, msgText, msgColor = GetMessageConfig(self.db, msgType)
            if frame.interruptIcon then
                frame.text:ClearAllPoints()
                frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
                frame.interruptIcon:Hide()
                frame.interruptName:Hide()
            end
            frame.text:SetText(msgText)
            frame.text:SetTextColor(msgColor[1] or 1, msgColor[2] or 1, msgColor[3] or 1, msgColor[4] or 1)
            if frame.interruptName then
                frame.interruptName:SetTextColor(
                    msgColor[1] or 1, msgColor[2] or 1, msgColor[3] or 1, msgColor[4] or 1)
            end
            frame:SetAlpha(1)
            SetLineShown(self, frame, msgType, true)
            self.activeMessages[msgType] = true
        end
    end

    self:ApplySettings()
    self:ArrangeMessages()
end

function CM:HidePreview()
    if not self.isPreview then return end

    self.isPreview = false

    -- Built-in lines only: an external line belongs to its owner and stays up.
    for _, msgType in ipairs(MESSAGE_TYPES) do
        local frame = self.messageFrames[msgType]
        if frame then SetLineShown(self, frame, msgType, false) end
        self.activeMessages[msgType] = nil
    end
    -- Re-arranged only while an external line is shown or a frame is attached:
    -- the arrange shrinks the container, which moves anything anchored to its top.
    local rearrange = next(self.attachedFrames) ~= nil
    for _, key in ipairs(EXTERNAL_LINE_TYPES) do
        local frame = self.messageFrames[key]
        if frame then
            local shown = frame:IsShown()
            if KE:IsSecretValue(shown) or shown then rearrange = true end
        end
    end
    if rearrange then self:ArrangeMessages() end

    SetAggroPulse(self.messageFrames.aggro, false)

    -- Re-check actual state
    if self.inCombat then
        self:CheckNoTarget()
        self:CheckAggro()
    end
end

---------------------------------------------------------------------------------
-- Interrupt Announce
---------------------------------------------------------------------------------
function CM.ResolveReadableInterruptOwner(interruptedBy, playerGUID, playerKnown, petGUID, petKnown)
    if playerKnown and interruptedBy == playerGUID then return "OWN" end
    if petKnown and petGUID ~= nil and interruptedBy == petGUID then return "OWN" end
    if not playerKnown or not petKnown then return "UNKNOWN" end
    return "OTHER"
end

function CM.ResolvePendingInterruptSource(unit, unitKnown)
    if not unitKnown then return nil end
    if unit == "player" or unit == "pet" then return unit end
    return nil
end

function CM:ClearPendingInterrupt()
    self.pendingInterruptAt = nil
    self.pendingInterruptSpellID = nil
    self.pendingInterruptUnit = nil
end

function CM:ClearInterruptQuarantine()
    self.reverseInterruptAt = nil
    self.reverseInterruptSuccessSpellID = nil
end

function CM:ClearInterruptState()
    self:ClearPendingInterrupt()
    self:ClearInterruptQuarantine()
    self.lastAcceptedCastGUID = nil
    self.lastUnkeyedAcceptAt = nil
end

function CM:RecordPendingInterrupt(spellID, source, now)
    self.pendingInterruptAt = now
    self.pendingInterruptSpellID = spellID
    self.pendingInterruptUnit = source
end

function CM.NormalizeInterruptSuccessSpellID(spellID)
    if spellID == 19647 or spellID == 119910 or spellID == 132409 then return 19647 end
    if spellID == 89766 or spellID == 119914 then return 89766 end
    return spellID
end

function CM:HasFreshInterruptQuarantine(now)
    if self.reverseInterruptAt == nil then return false end
    if now <= self.reverseInterruptAt + REVERSE_EVENT_WINDOW then
        return true
    end
    self:ClearInterruptQuarantine()
    return false
end

function CM:RecordInterruptQuarantine(now, seedSpellID)
    self.reverseInterruptAt = now
    self.reverseInterruptSuccessSpellID = seedSpellID ~= nil
        and CM.NormalizeInterruptSuccessSpellID(seedSpellID) or nil
end

function CM:ClassifyInterruptOwnership(interruptedBy)
    if KE:IsSecretValue(interruptedBy) then return "UNKNOWN", false end
    if interruptedBy == nil then return "UNKNOWN", true end

    local playerGUID = UnitGUID("player")
    local playerSecret = KE:IsSecretValue(playerGUID)
    local playerKnown = not playerSecret and playerGUID ~= nil
    if not playerKnown then playerGUID = nil end

    local petGUID = UnitGUID("pet")
    local petSecret = KE:IsSecretValue(petGUID)
    local petKnown = not petSecret
    if petSecret then petGUID = nil end

    return CM.ResolveReadableInterruptOwner(interruptedBy, playerGUID,
        playerKnown, petGUID, petKnown), false
end

function CM:ClassifyInterruptTarget(unitTarget)
    if KE:IsSecretValue(unitTarget) then return "UNKNOWN" end
    if type(unitTarget) ~= "string" then return "INVALID" end
    if unitTarget == "player" or unitTarget == "pet" then return "FRIENDLY" end

    local ok, hostile = pcall(UnitCanAttack, "player", unitTarget)
    if not ok or not KE:IsSafeValue(hostile) then return "UNKNOWN" end
    if hostile == true then return "HOSTILE" end
    if hostile == false then return "FRIENDLY" end
    return "UNKNOWN"
end

function CM:HasFreshPendingInterrupt(now)
    if self.pendingInterruptAt == nil then return false, nil, "none", "none" end

    local elapsed = now - self.pendingInterruptAt
    local pendingSource = self.pendingInterruptUnit or "unknown"
    if now <= self.pendingInterruptAt + 0.35 then
        return true, elapsed, pendingSource, "fresh"
    end

    self:ClearPendingInterrupt()
    return false, elapsed, pendingSource, "expired"
end

function CM:ShouldAcceptInterrupt(event, unitTarget, castGUID, interruptedBy, now)
    local ownership, nilOwnership = self:ClassifyInterruptOwnership(interruptedBy)
    local fresh, elapsed, pendingSource, pendingState = self:HasFreshPendingInterrupt(now)
    if ownership == "OTHER" then
        return false, ownership, "UNKNOWN", pendingSource, pendingState, "other-owner", elapsed
    end

    if ownership == "UNKNOWN" then
        if nilOwnership and event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            return false, ownership, "UNKNOWN", pendingSource, pendingState, "nil-channel-stop", elapsed
        end
        if not fresh then
            return false, ownership, "UNKNOWN", pendingSource, pendingState, "no-fresh-pending", elapsed
        end
    end

    local target = self:ClassifyInterruptTarget(unitTarget)
    if target == "FRIENDLY" then
        return false, ownership, target, pendingSource, pendingState, "friendly-target", elapsed
    end
    if target == "INVALID" then
        return false, ownership, target, pendingSource, pendingState, "invalid-target", elapsed
    end
    local readableCastGUID = not KE:IsSecretValue(castGUID) and type(castGUID) == "string"
    if readableCastGUID and castGUID == self.lastAcceptedCastGUID then
        return false, ownership, target, pendingSource, pendingState, "duplicate-cast-guid", elapsed
    end
    if not readableCastGUID and ownership == "OWN" and self.lastUnkeyedAcceptAt ~= nil
        and now < self.lastUnkeyedAcceptAt + 0.10 then
        return false, ownership, target, pendingSource, pendingState, "unkeyed-throttle", elapsed
    end

    if readableCastGUID then
        self.lastAcceptedCastGUID = castGUID
    elseif ownership == "OWN" then
        self.lastUnkeyedAcceptAt = now
    end
    self:ClearPendingInterrupt()
    local reason = ownership == "OWN" and "direct-owner" or "fallback"
    return true, ownership, target, pendingSource, pendingState, reason, elapsed
end

function CM:OnSpellcastSucceeded(_, unit, _, spellID)
    if not self.db or self.db.InterruptEnabled == false or not self.interruptAnnounceSpells then return end
    if not KE:IsSafeValue(spellID) then return end
    if not self.interruptAnnounceSpells[spellID] then return end

    local unitKnown = not KE:IsSecretValue(unit)
    local source = CM.ResolvePendingInterruptSource(unit, unitKnown)
    if unitKnown and source == nil then return end

    local now = GetTime()
    if self:HasFreshInterruptQuarantine(now) then
        local normalizedSpellID = CM.NormalizeInterruptSuccessSpellID(spellID)
        if self.reverseInterruptSuccessSpellID == nil then
            self.reverseInterruptSuccessSpellID = normalizedSpellID
            return
        end
        if self.reverseInterruptSuccessSpellID == normalizedSpellID then return end
        self:ClearInterruptQuarantine()
    end

    self:RecordPendingInterrupt(spellID, source, now)
end

function CM:BuildInterruptDisplayText(spellID)
    local name = C_Spell_GetSpellName(spellID)
    local iconID = C_Spell_GetSpellTexture(spellID)
    if name == nil or iconID == nil then return nil, nil, nil end

    local prefix = self.db.InterruptText or "Interrupted"
    return prefix, iconID, name
end

function CM:OnSpellcastInterrupted(event, unitTarget, castGUID, spellID, interruptedBy)
    if not self.db or self.db.InterruptEnabled == false then return end

    local now = GetTime()
    local pendingSpellID = self.pendingInterruptSpellID
    local accepted, ownership, target, pendingSource, pendingState, reason, elapsed =
        self:ShouldAcceptInterrupt(event, unitTarget, castGUID, interruptedBy, now)
    if DEBUG_CT then
        local elapsedText = elapsed and string_format("%.3f", elapsed) or "none"
        KE:Print(string_format("[CT] event=%s owner=%s target=%s pending=%s state=%s elapsed=%s reason=%s",
            event, ownership, target, pendingSource, pendingState, elapsedText, reason))
    end
    if not accepted then return end

    local quarantineSeed = pendingState == "fresh" and pendingSpellID or nil
    self:RecordInterruptQuarantine(now, quarantineSeed)
    local prefix, icon, name = self:BuildInterruptDisplayText(spellID)
    self:ShowFlashMessage("interrupt", prefix, icon, name)
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function CM:EnsureInterruptCastFrame()
    if self.interruptCastFrame then return end
    local frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", function(_, event, unit, castGUID, spellID)
        self:OnSpellcastSucceeded(event, unit, castGUID, spellID)
    end)
    self.interruptCastFrame = frame
end

function CM:UpdateInterruptEventRegistration(forceDisabled)
    local enabled = not forceDisabled
        and self:IsEnabled()
        and self.db
        and self.db.Enabled ~= false
        and self.db.InterruptEnabled ~= false

    if enabled and not self.interruptEventsRegistered then
        self:EnsureInterruptCastFrame()
        self.interruptCastFrame:RegisterUnitEvent(
            "UNIT_SPELLCAST_SUCCEEDED", "player", "pet")
        self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", "OnSpellcastInterrupted")
        self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP", "OnSpellcastInterrupted")
        self.interruptEventsRegistered = true
    elseif not enabled and self.interruptEventsRegistered then
        self.interruptCastFrame:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        self:UnregisterEvent("UNIT_SPELLCAST_INTERRUPTED")
        self:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
        self.interruptEventsRegistered = false
        self:ClearInterruptState()
    elseif not enabled then
        self:ClearInterruptState()
    end
end

function CM:OnEnable()
    if self.db.Enabled == false then return end

    self:CreateContainer()
    self:RegWithEditMode()
    self.interruptAnnounceSpells = KE:GetInterruptAnnounceSpellSet()
    self:EnsureInterruptCastFrame()

    -- Pre-create message frames
    for _, msgType in ipairs(MESSAGE_TYPES) do
        self:GetMessageFrame(msgType)
    end

    C_Timer.After(0.5, function()
        self:ApplySettings()
    end)

    -- Register events
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnEnterCombat")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnExitCombat")
    self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnTargetChanged")
    self:RegisterEvent("PLAYER_DEAD", "OnPlayerDead")
    self:RegisterEvent("UPDATE_INVENTORY_DURABILITY", "CheckDurability")

    self:UpdateInterruptEventRegistration()
    self:UpdateAggroEventRegistration()

    -- Track initial combat state
    self.inCombat = InCombatLockdown()

    -- Initial checks (delayed to ensure frames exist)
    if self.inCombat then
        self:CheckNoTarget()
        self:CheckAggro()
    else
        C_Timer.After(1, function() self:CheckDurability() end)
    end

    self:SendMessage(self.CHANGED_MESSAGE)
end

function CM:OnDisable()
    for _, frame in pairs(self.messageFrames) do
        -- A pending flash fade checks the generation, so a disabled module
        -- never starts or finishes one, however the shown state reads.
        frame.generation = frame.generation + 1
        frame:SetScript("OnUpdate", nil)
        SetLineShown(self, frame, frame.msgType, false)
    end
    self.activeMessages = {}
    self.isPreview = false
    self.inCombat = false
    self.noTargetCheckGeneration = self.noTargetCheckGeneration + 1
    SetAggroPulse(self.messageFrames.aggro, false)
    self:UpdateAggroEventRegistration(true)
    self:UpdateInterruptEventRegistration(true)
    self.interruptAnnounceSpells = nil
    self:UnregisterAllEvents()
    for _, key in ipairs(ATTACHED_FRAME_TYPES) do
        self.attachedFrames[key] = nil
        self.attachedInsets[key] = nil
        self.arrangedShown[key] = nil
        self.arrangedHeight[key] = nil
        self.attachSeated[key] = nil
        self.attachTop[key] = nil
    end
    self:SendMessage(self.CHANGED_MESSAGE)
end

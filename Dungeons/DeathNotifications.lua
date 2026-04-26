-- ╔══════════════════════════════════════════════════════════╗
-- ║  DeathNotifications.lua                                  ║
-- ║  Module: Death Notifications                             ║
-- ║  Purpose: On-screen alerts when party/raid members or    ║
-- ║           your focus target dies. Active in dungeons by  ║
-- ║           default; raid activation is opt-in.            ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class DeathNotifications: AceModule, AceEvent-3.0
local DN = KitnEssentials:NewModule("DeathNotifications", "AceEvent-3.0")

local CreateFrame = CreateFrame
local UnitIsDead = UnitIsDead
local UnitInParty, UnitInRaid = UnitInParty, UnitInRaid
local IsInRaid, IsInGroup = IsInRaid, IsInGroup
local IsInInstance = IsInInstance
local UnitClass, UnitIsUnit = UnitClass, UnitIsUnit
local UnitTokenFromGUID, UnitGUID = UnitTokenFromGUID, UnitGUID
local UIFrameFadeRemoveFrame = UIFrameFadeRemoveFrame
local C_ClassColor = C_ClassColor
local C_Timer = C_Timer
local GetTime = GetTime
local ipairs, pairs = ipairs, pairs
local max = math.max

-- Fade tail length: messages hold full opacity until (Duration - FADE_DURATION),
-- then OnUpdate-driven alpha fade over this window. Matches Combat Texts.
local FADE_DURATION = 0.4

DN.messageFrames = {}

local MESSAGE_TYPES = { "partyDeath", "focusDeath" }

local GROW_ANCHORS = {
    DOWN = { childPoint = "TOP", containerAnchor = "TOP", yDir = -1 },
    UP   = { childPoint = "BOTTOM", containerAnchor = "BOTTOM", yDir = 1 },
}

---------------------------------------------------------------------------------
-- DB helper
---------------------------------------------------------------------------------
function DN:UpdateDB()
    self.db = KE.db.profile.Dungeons.DeathNotifications
end

function DN:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

---------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------

-- Resolves a GUID to a unit token (player / partyN / raidN). Returns nil if
-- the GUID can't be matched in the current group context.
local function GetUnitFromGUID(guid)
    if not guid or KE:IsSecretValue(guid) then return nil end

    if UnitTokenFromGUID then
        local token = UnitTokenFromGUID(guid)
        if token then return token end
    end

    if UnitGUID("player") == guid then return "player" end

    if IsInRaid() then
        for i = 1, 40 do
            local u = "raid" .. i
            if UnitGUID(u) == guid then return u end
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            local u = "party" .. i
            if UnitGUID(u) == guid then return u end
        end
    end

    return nil
end

-- True when the current instance/group context matches the user's enabled
-- contexts. Outside instances entirely → never fires (no random death spam
-- in open world).
local function IsContextActive(db)
    local _, instanceType = IsInInstance()
    if instanceType == "party" then
        return db.EnableInDungeons ~= false
    elseif instanceType == "raid" then
        return db.EnableInRaids == true
    end
    return false
end

local function FormatDeathMessage(format, name, nameColor, textColor)
    local textHex = KE:RGBAToHex(textColor[1], textColor[2], textColor[3])
    local textStart = "|cFF" .. textHex
    local textEnd = "|r"

    local coloredName
    if nameColor.WrapTextInColorCode then
        coloredName = nameColor:WrapTextInColorCode(name)
    else
        local nameHex = KE:RGBAToHex(nameColor[1], nameColor[2], nameColor[3])
        coloredName = "|cFF" .. nameHex .. name .. "|r"
    end

    local before, after = format:match("^(.-)%%name(.*)$")
    if before then
        return textStart .. before .. textEnd .. coloredName .. textStart .. after .. textEnd
    end
    return textStart .. format .. textEnd
end

-- Returns just the class atlas name (e.g. "classicon-druid") if the class
-- is known and not tainted, else nil. The icon itself is rendered as a
-- separate Texture child of the message frame, NOT inline in the text —
-- inline atlas escapes (`|A:...|a`) get stripped from the soft-outline
-- shadow FontStrings, which then misalign relative to the main text.
local string_lower = string.lower

local function GetClassIconAtlas(classFilename)
    if not classFilename or KE:IsSecretValue(classFilename) then return nil end
    return "classicon-" .. string_lower(classFilename)
end

-- Standard circular alpha mask (used by Blizzard for character portraits).
-- Cropping the high-res square classicon atlas through this mask gives us
-- the modern round portrait look without losing source resolution.
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local function FormatPartyDeathMessage(db, unitID, fallbackName)
    -- Custom Nicknames first; falls back to the secret-value-safe lookup if
    -- the nickname path returned a secret value (UnitFullName can be tainted
    -- mid-encounter in 12.0).
    local name = KE:GetNicknameOrName(unitID)
    if not name or name == "" or KE:IsSecretValue(name) then
        name = KE:GetSafeUnitName(unitID) or fallbackName
    end
    if not name then return nil, nil end

    local _, classFilename = UnitClass(unitID)

    local nameColor = { 1, 1, 1, 1 }
    if db.PartyDeath.UseClassColor and classFilename and not KE:IsSecretValue(classFilename) then
        local classColor = C_ClassColor.GetClassColor(classFilename)
        if classColor then nameColor = classColor end
    end

    local fmt = db.PartyDeath.TextFormat or "%name DIED"
    local message = FormatDeathMessage(fmt, name, nameColor, db.PartyDeath.TextColor)
    local iconAtlas = (db.ShowClassIcon and GetClassIconAtlas(classFilename)) or nil
    return message, iconAtlas
end

---------------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------------
function DN:CreateContainer()
    if self.container then return end
    local container = CreateFrame("Frame", "KE_DeathNotificationsContainer", UIParent)
    container:SetSize(100, 20)
    container:SetFrameLevel(100)
    self.container = container
    self:ApplyContainerPosition()
end

function DN:ApplyContainerPosition()
    if not self.container then return end
    local grow = GROW_ANCHORS[self.db.Grow] or GROW_ANCHORS.DOWN
    local parent = KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)

    self.container:ClearAllPoints()
    self.container:SetPoint(
        grow.containerAnchor,
        parent,
        self.db.Position.AnchorTo or "CENTER",
        self.db.Position.XOffset or 0,
        self.db.Position.YOffset or 0
    )
    self.container:SetFrameStrata(self.db.Strata or "HIGH")
    -- Custom anchor logic (grow-direction-driven container point) prevents
    -- using ApplyFramePositionWithSnap directly, so apply the snap inline.
    if self.db.SnapToPixelGrid and KE.SnapFrameToPixels then
        KE:SnapFrameToPixels(self.container)
    end
end

function DN:GetMessageFrame(msgType)
    if self.messageFrames[msgType] then return self.messageFrames[msgType] end

    local frame = CreateFrame("Frame", nil, self.container)
    frame:SetSize(200, 20)
    frame:Hide()

    -- Class icon texture (only used by partyDeath; hidden by default).
    -- Anchored to the LEFT of the frame; text re-anchors based on icon
    -- visibility in SetMessageContent. The circular mask crops the square
    -- classicon atlas into a round portrait without quality loss.
    local icon = frame:CreateTexture(nil, "OVERLAY")
    icon:SetPoint("LEFT", frame, "LEFT", 0, 0)
    if icon.SetMask then
        pcall(icon.SetMask, icon, CIRCLE_MASK)
    end
    icon:Hide()
    frame.icon = icon

    local text = frame:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER")
    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")

    frame.text = text
    frame.msgType = msgType
    frame.generation = 0
    frame.width = 200
    frame.height = 20

    self.messageFrames[msgType] = frame
    self:UpdateFrameFont(frame)
    return frame
end

function DN:UpdateFrameFont(frame)
    KE:ApplyFontToText(frame.text, self.db.FontFace, self.db.FontSize, self.db.FontOutline)
end

function DN:SetMessageContent(frame, msgText, color, iconAtlas)
    -- Icon presence and atlas
    local iconWidth = 0
    if iconAtlas then
        local size = self.db.FontSize or 18
        local gap = 4
        frame.icon:SetAtlas(iconAtlas)
        frame.icon:SetSize(size, size)
        frame.icon:Show()
        iconWidth = size + gap
        frame.text:ClearAllPoints()
        frame.text:SetPoint("LEFT", frame.icon, "RIGHT", gap, 0)
    else
        frame.icon:Hide()
        frame.text:ClearAllPoints()
        frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    end

    frame.text:SetText("")
    frame.text:SetText(msgText)
    frame.text:SetTextColor(color[1], color[2], color[3], color[4] or 1)

    local textWidth = frame.text:GetStringWidth() or 100
    local textHeight = frame.text:GetStringHeight() or 12
    local width = max(textWidth + iconWidth + 10, 100)
    local height = max(textHeight, 12)
    frame.width = width
    frame.height = height
    frame:SetSize(width, height)
end

function DN:ArrangeMessages()
    if not self.container then return end
    local grow = GROW_ANCHORS[self.db.Grow] or GROW_ANCHORS.DOWN
    local spacing = self.db.Spacing or 4
    local yDir = grow.yDir

    local visibleFrames = {}
    for _, msgType in ipairs(MESSAGE_TYPES) do
        local frame = self.messageFrames[msgType]
        if frame and frame:IsShown() then
            visibleFrames[#visibleFrames + 1] = frame
        end
    end

    local yOffset = 0
    local maxWidth = 0
    local totalHeight = 0
    for i, frame in ipairs(visibleFrames) do
        frame:ClearAllPoints()
        frame:SetPoint(grow.childPoint, self.container, grow.containerAnchor, 0, yOffset * yDir)
        yOffset = yOffset + frame.height + spacing
        if frame.width > maxWidth then maxWidth = frame.width end
        totalHeight = totalHeight + frame.height
        if i < #visibleFrames then totalHeight = totalHeight + spacing end
    end

    if #visibleFrames > 0 then
        self.container:SetSize(max(maxWidth, 100), totalHeight)
    else
        self.container:SetSize(100, 20)
    end
end

---------------------------------------------------------------------------------
-- Show / Hide
---------------------------------------------------------------------------------
function DN:ShowFlashMessage(msgType, msgText, msgColor, iconAtlas)
    if not self.db.Enabled or self.isPreview then return end

    local frame = self:GetMessageFrame(msgType)
    if not frame then return end

    frame.generation = frame.generation + 1
    local myGen = frame.generation

    -- Stop any in-flight fade from the previous flash on this frame so a
    -- re-trigger doesn't get half-transparent text or a stale OnUpdate.
    if UIFrameFadeRemoveFrame then UIFrameFadeRemoveFrame(frame) end
    frame:SetScript("OnUpdate", nil)

    self:SetMessageContent(frame, msgText, msgColor or { 1, 1, 1, 1 }, iconAtlas)
    frame:SetAlpha(1)
    frame:Show()
    self:ArrangeMessages()

    local function HideIfCurrent()
        if frame.generation ~= myGen or self.isPreview then return end
        frame:Hide()
        -- Don't reset alpha here — the next ShowFlashMessage path sets
        -- SetAlpha(1) before showing, and resetting now can flash the soft-
        -- outline shadows at full opacity for a frame before the Hide.
        self:ArrangeMessages()
    end

    -- Manual alpha fade. UIFrameFadeOut is unsafe — it stack-overflows on
    -- frames whose children use the SOFTOUTLINE shadow system. SetAlpha on
    -- the parent propagates to soft-outline children without that hook
    -- path. OnUpdate only runs during the FADE_DURATION window itself, so
    -- per-frame cost is bounded to ~0.4s per message.
    local duration = self.db.Duration or 3
    local fadeStart = duration - FADE_DURATION
    if fadeStart <= 0 then
        -- Duration shorter than the fade tail — just fade the entire window.
        fadeStart = 0
    end

    C_Timer.After(fadeStart, function()
        if frame.generation ~= myGen or self.isPreview then return end
        if not frame:IsShown() then return end
        local fadeBegin = GetTime()
        local fadeWindow = duration - fadeStart
        frame:SetScript("OnUpdate", function(f)
            if f.generation ~= myGen or self.isPreview then
                f:SetScript("OnUpdate", nil)
                return
            end
            local progress = (GetTime() - fadeBegin) / fadeWindow
            if progress >= 1 then
                f:SetScript("OnUpdate", nil)
                HideIfCurrent()
            else
                f:SetAlpha(1 - progress)
            end
        end)
    end)
end

---------------------------------------------------------------------------------
-- Event handlers
---------------------------------------------------------------------------------
function DN:CheckFocusDeath(deadGUID)
    if not self.db.FocusDeath.Enabled then return end

    local focusGUID = UnitGUID("focus")
    if not focusGUID or KE:IsSecretValue(focusGUID) or KE:IsSecretValue(deadGUID) then return end
    if focusGUID ~= deadGUID then return end

    local cfg = self.db.FocusDeath
    self:ShowFlashMessage("focusDeath", cfg.Text or "FOCUS DIED", cfg.Color or { 1, 0.3, 0.3, 1 })
end

function DN:OnUnitDied(_, deadGUID)
    if not self.db.Enabled or self.isPreview then return end
    if not IsContextActive(self.db) then return end

    self:CheckFocusDeath(deadGUID)

    if not self.db.PartyDeath.Enabled then return end

    -- Throttle: at most 4 party-death announcements per 10s window so a
    -- raid wipe doesn't spam the screen.
    local now = GetTime()
    if now > self.deathThrottle.resetTime then
        self.deathThrottle.count = 0
        self.deathThrottle.resetTime = now + 10
    end
    if self.deathThrottle.count >= 4 then return end

    local unitID = GetUnitFromGUID(deadGUID)
    if not unitID or KE:IsSecretValue(unitID) then return end
    if UnitIsUnit(unitID, "player") then return end

    local isDead = UnitIsDead(unitID)
    if KE:IsSecretValue(isDead) then isDead = true end
    if not isDead then return end

    if not UnitInParty(unitID) and not UnitInRaid(unitID) then return end

    self.deathThrottle.count = self.deathThrottle.count + 1

    local msgText, iconAtlas = FormatPartyDeathMessage(self.db, unitID)
    if not msgText then return end

    self:ShowFlashMessage("partyDeath", msgText, { 1, 1, 1, 1 }, iconAtlas)
end

---------------------------------------------------------------------------------
-- Settings / Preview
---------------------------------------------------------------------------------
function DN:ApplySettings()
    if not self.container then return end
    self:ApplyContainerPosition()
    for _, frame in pairs(self.messageFrames) do self:UpdateFrameFont(frame) end

    if self.isPreview then
        self:UpdatePreview()
        return
    end

    -- Refresh visible message text/color
    for _, msgType in ipairs(MESSAGE_TYPES) do
        local frame = self.messageFrames[msgType]
        if frame and frame:IsShown() then
            if msgType == "focusDeath" then
                local cfg = self.db.FocusDeath
                self:SetMessageContent(frame, cfg.Text or "FOCUS DIED",
                    cfg.Color or { 1, 0.3, 0.3, 1 }, nil)
            end
        end
    end

    self:ArrangeMessages()
end

function DN:UpdatePreview()
    if not self.isPreview then return end

    -- Party death preview — uses player's own name + class color so users
    -- see how the format renders.
    local pdCfg = self.db.PartyDeath
    if pdCfg.Enabled then
        local frame = self:GetMessageFrame("partyDeath")
        local msgText, iconAtlas = FormatPartyDeathMessage(self.db, "player", "Player")
        msgText = msgText or "PLAYER DIED"
        self:SetMessageContent(frame, msgText, { 1, 1, 1, 1 }, iconAtlas)
        frame:SetAlpha(1)
        frame:Show()
    else
        local frame = self.messageFrames["partyDeath"]
        if frame then frame:Hide() end
    end

    local fdCfg = self.db.FocusDeath
    if fdCfg.Enabled then
        local frame = self:GetMessageFrame("focusDeath")
        self:SetMessageContent(frame, fdCfg.Text or "FOCUS DIED",
            fdCfg.Color or { 1, 0.3, 0.3, 1 }, nil)
        frame:SetAlpha(1)
        frame:Show()
    else
        local frame = self.messageFrames["focusDeath"]
        if frame then frame:Hide() end
    end

    self:ArrangeMessages()
end

function DN:ShowPreview()
    if not self.container then self:CreateContainer() end
    for _, msgType in ipairs(MESSAGE_TYPES) do self:GetMessageFrame(msgType) end
    self.isPreview = true
    self:UpdatePreview()
end

function DN:HidePreview()
    if not self.isPreview then return end
    self.isPreview = false
    for _, frame in pairs(self.messageFrames) do
        frame:SetScript("OnUpdate", nil)
        frame:Hide()
    end
    self:ArrangeMessages()
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function DN:OnEnable()
    if not self.db.Enabled then return end

    self.isPreview = false
    self.deathThrottle = { count = 0, resetTime = 0 }

    self:CreateContainer()
    for _, msgType in ipairs(MESSAGE_TYPES) do self:GetMessageFrame(msgType) end

    C_Timer.After(0.5, function() self:ApplySettings() end)

    self:RegisterEvent("UNIT_DIED", "OnUnitDied")

    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "DeathNotifications",
            displayName = "Death Notifications",
            frame = self.container,
            getPosition = function()
                local grow = GROW_ANCHORS[self.db.Grow] or GROW_ANCHORS.DOWN
                return {
                    AnchorFrom = grow.containerAnchor,
                    AnchorTo = self.db.Position.AnchorTo,
                    XOffset = self.db.Position.XOffset,
                    YOffset = self.db.Position.YOffset,
                }
            end,
            setPosition = function(pos)
                self.db.Position.AnchorTo = pos.AnchorTo
                self.db.Position.XOffset = pos.XOffset
                self.db.Position.YOffset = pos.YOffset
                self:ApplyContainerPosition()
            end,
            getParentFrame = function()
                return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)
            end,
            guiPath = "DeathNotifications",
        })
        self.editModeRegistered = true
    end
end

function DN:OnDisable()
    for _, frame in pairs(self.messageFrames) do
        frame:SetScript("OnUpdate", nil)
        frame:Hide()
    end
    self.isPreview = false
    self:UnregisterAllEvents()
end

-- ╔══════════════════════════════════════════════════════════╗
-- ║  KeystoneHelper.lua                                      ║
-- ║  Module: Keystone Helper                                 ║
-- ║  Purpose: Bundles three Mythic+ keystone QoL features:   ║
-- ║           (1) announces to party/raid chat when the      ║
-- ║           player resets instances, (2) reminds you to    ║
-- ║           reroll your keystone after an in-time/upgrade  ║
-- ║           completion, and (3) reminds you that you're    ║
-- ║           standing in your own key's dungeon at Mythic 0 ║
-- ║           so you remember to slot it.                    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class KeystoneHelper: AceModule, AceEvent-3.0, AceHook-3.0
local KH = KitnEssentials:NewModule("KeystoneHelper", "AceEvent-3.0", "AceHook-3.0")

local CreateFrame = CreateFrame
local GetTime = GetTime
local GetInstanceInfo = GetInstanceInfo
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local C_ChatInfo = C_ChatInfo
local C_Timer = C_Timer
local C_ChallengeMode = C_ChallengeMode
local C_MythicPlus = C_MythicPlus
local select = select

-- LibCustomGlow for the pixel-glow nag on both reminder frames. Optional
-- dependency — module degrades gracefully (no glow) if missing.
local LCG = LibStub("LibCustomGlow-1.0", true)

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
local REROLL_ICON  = 525134    -- generic keystone icon
local YOURKEY_ICON = 4352494   -- keystone icon 2
local AUTO_HIDE_SECONDS = 300  -- 5 minutes
local KEY_ICON_GAP = 4         -- px between the key line's dungeon icon and text
local KEY_ICON_SCALE = 1.2     -- key-line icon renders slightly larger than the text
local KEY_LINE_GAP = 8         -- px between the icon's bottom edge and the key line
local KEY_TEXT_LIFT = 0.12     -- share of the font size the key text is raised by

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function KH:UpdateDB()
    self.db = KE.db.profile.KeystoneHelper
end

function KH:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

---------------------------------------------------------------------------------
-- Feature 1: Instance Reset Announcer
-- SecureHook, not a bare frame + event:
-- ResetInstances() has no corresponding event, so a hook is the only way to
-- observe the reset. IsHooked guards against double-hooking across repeated
-- ApplySettings calls; the hook itself stays installed for the module's
-- lifetime and the callback re-checks db.ResetEnabled every fire.
---------------------------------------------------------------------------------
local function OnInstanceReset()
    if not KH.db or not KH.db.Enabled or not KH.db.ResetEnabled then return end

    local channel
    if IsInRaid() then
        channel = "RAID"
    elseif IsInGroup() then
        channel = "PARTY"
    end
    if not channel then return end

    C_ChatInfo.SendChatMessage(KH.db.ResetMessage or "Instance reset!", channel)
end

function KH:ApplyResetHook()
    if not self:IsHooked("ResetInstances") then
        self:SecureHook("ResetInstances", OnInstanceReset)
    end
end

---------------------------------------------------------------------------------
-- Shared reminder frame factory
-- Both reminders are a single icon with a title line above and a
-- "<icon> <dungeon> +<level>" key line below. They never show at the same
-- time, so one appearance block, one position and one Edit Mode mover serve
-- both.
---------------------------------------------------------------------------------
local function CreateReminderFrame(nameSuffix, iconID)
    local frame = CreateFrame("Frame", "KE_KeystoneHelper" .. nameSuffix, UIParent)
    frame:Hide()

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(iconID)
    KE:ApplyIconZoom(icon)
    frame.icon = icon

    KE:AddIconBorders(frame)

    -- Title line, above the icon.
    local title = frame:CreateFontString(nil, "OVERLAY")
    title:SetPoint("BOTTOM", frame, "TOP", 0, 8)
    frame.title = title

    -- "<SHORT> +<level>" line, below the icon. The dungeon icon to its
    -- left is a real Texture, NOT inline |T|t markup.
    local keyText = frame:CreateFontString(nil, "OVERLAY")
    keyText:SetPoint("TOP", frame, "BOTTOM", 0, -8)
    frame.keyText = keyText

    -- Standard KE icon treatment (zoom crop + 1px borders) needs a frame
    -- wrapper — AddIconBorders anchors its border textures to frame edges.
    local keyIcon = CreateFrame("Frame", nil, frame)
    keyIcon:Hide()
    local keyIconTex = keyIcon:CreateTexture(nil, "ARTWORK")
    keyIconTex:SetAllPoints()
    KE:ApplyIconZoom(keyIconTex)
    KE:AddIconBorders(keyIcon)
    frame.keyIcon = keyIcon
    frame.keyIconTex = keyIconTex

    return frame
end

-- "<SHORT> +<level>" plus the dungeon's icon fileID for the owned keystone;
-- nil, nil without one. The short name fits under a 64 px icon where the
-- full name ran well past it. C_ChallengeMode.GetMapUIInfo supplies both
-- the name and the icon.
local function GetOwnedKeyDisplay()
    local level = C_MythicPlus.GetOwnedKeystoneLevel()
    local challengeMapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    if not level or not challengeMapID then return nil, nil end

    local name, _, _, texture = C_ChallengeMode.GetMapUIInfo(challengeMapID)
    if not name then return "+" .. level, texture end
    return KE:AbbreviateDungeonName(name, challengeMapID) .. " +" .. level, texture
end

-- Icon renders square, sized off the text height (KEY_ICON_SCALE), on a
-- whole number of pixels so all four border edges land on the grid.
local function KeyIconSize()
    local fontSize = (KH.db and KH.db.FontSize) or 36
    return KE:PixelSnap(math.floor(fontSize * KEY_ICON_SCALE + 0.5))
end

-- Icon and text laid out as one centred pair under the frame. The icon is
-- anchored to the frame, never to the text: a fontstring's edge lands on a
-- fraction of a pixel, and a 1 px border on a fractional edge splits across
-- two rows. Anchoring from BOTTOMLEFT with a snapped offset keeps the icon's
-- left edge on the grid at any frame width. The text hangs off the icon with
-- its top and bottom pinned to it, lifted by a share of the font size because
-- the face draws its glyphs below the middle of the line box.
local function LayoutKeyLine(frame)
    local iconSize = KeyIconSize()
    frame.keyIcon:SetSize(iconSize, iconSize)
    frame.keyIcon:ClearAllPoints()
    frame.keyText:ClearAllPoints()
    if frame.keyIcon:IsShown() then
        local textWidth = frame.keyText:GetStringWidth() or 0
        local pairWidth = iconSize + KEY_ICON_GAP + textWidth
        local left = KE:PixelSnap((frame:GetWidth() - pairWidth) / 2)
        frame.keyIcon:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", left, -KE:PixelSnap(KEY_LINE_GAP))
        local lift = KE:PixelSnap(((KH.db and KH.db.FontSize) or 36) * KEY_TEXT_LIFT)
        frame.keyText:SetPoint("TOPLEFT", frame.keyIcon, "TOPRIGHT", KEY_ICON_GAP, lift)
        frame.keyText:SetPoint("BOTTOMLEFT", frame.keyIcon, "BOTTOMRIGHT", KEY_ICON_GAP, lift)
        frame.keyText:SetJustifyH("LEFT")
        frame.keyText:SetJustifyV("MIDDLE")
    else
        frame.keyText:SetPoint("TOP", frame, "BOTTOM", 0, -KEY_LINE_GAP)
        frame.keyText:SetJustifyH("CENTER")
        frame.keyText:SetJustifyV("MIDDLE")
    end
end

local function SetKeyLine(frame, text, icon)
    frame.keyText:SetText(text or "")
    if icon then
        frame.keyIconTex:SetTexture(icon)
        frame.keyIcon:Show()
    else
        frame.keyIcon:Hide()
    end
    LayoutKeyLine(frame)
end

-- Applies the shared look and position to one reminder frame.
local function ApplyReminderFrame(frame)
    local db = KH.db
    if not frame or not db then return end

    local size = db.Size or 64
    frame:SetSize(size, size)
    KE:ApplyFramePosition(frame, db.Position, {
        anchorFrameType = db.AnchorFrameType,
        ParentFrame     = db.ParentFrame,
        Strata          = db.Strata,
    })

    KE:ApplyFontToText(frame.title, db.FontFace, db.FontSize, db.FontOutline)
    local r, g, b, a = KE:ResolveColor(db.FontColor, { 1, 1, 1, 1 })
    frame.title:SetTextColor(r, g, b, a)

    KE:ApplyFontToText(frame.keyText, db.FontFace, db.FontSize, db.FontOutline)
    local kr, kg, kb, ka = KE:ResolveColor(db.FontColorKey, { 1, 1, 1, 1 })
    frame.keyText:SetTextColor(kr, kg, kb, ka)

    LayoutKeyLine(frame)
end

---------------------------------------------------------------------------------
-- Glow helpers (one pixel-glow shape, shared settings)
---------------------------------------------------------------------------------
local function StartGlow(frame)
    local db = KH.db
    if not LCG or not frame or not db or not db.GlowEnabled then return end
    LCG.PixelGlow_Start(frame, db.GlowColor, db.GlowLines, db.GlowFrequency,
        db.GlowLength, db.GlowThickness, 0, 0, true, nil)
    frame.glowActive = true
end

local function StopGlow(frame)
    if not frame then return end
    if LCG then LCG.PixelGlow_Stop(frame) end
    frame.glowActive = false
end

-- A glow that is up restarts so colour and speed edits show at once.
local function ApplyReminder(frame)
    if not frame then return end
    ApplyReminderFrame(frame)
    if frame.glowActive then
        StopGlow(frame)
        StartGlow(frame)
    end
end

function KH:ApplyReminders()
    ApplyReminder(self.rerollFrame)
    ApplyReminder(self.yourKeyFrame)
end

---------------------------------------------------------------------------------
-- Feature 2: Reroll Key Reminder
---------------------------------------------------------------------------------
local function IsInMythicKeystoneInstance()
    local difficultyID = select(3, GetInstanceInfo())
    return difficultyID == 8   -- Mythic Keystone
end

local function CanRerollKey()
    local info = C_ChallengeMode.GetChallengeCompletionInfo()
    if not info then return false end
    local keystoneLevel = C_MythicPlus.GetOwnedKeystoneLevel()
    if not keystoneLevel then return false end
    return info.onTime and keystoneLevel <= info.level
end

function KH:CreateRerollFrame()
    if self.rerollFrame then return end
    self.rerollFrame = CreateReminderFrame("Reroll", REROLL_ICON)
end

function KH:UpdateRerollDisplay()
    local frame = self.rerollFrame
    if not frame then return end

    frame.title:SetText(self.rerollHasRerolled and "NEW KEY" or "REROLL KEY?")
    SetKeyLine(frame, GetOwnedKeyDisplay())
end

function KH:CheckRerollTimer()
    if not self.rerollActive then return end
    local elapsed = GetTime() - self.rerollTimerStart
    if elapsed >= AUTO_HIDE_SECONDS then self:StopRerollTimer() end
end

function KH:StartRerollTimer()
    -- Deferred 1s from CHALLENGE_MODE_COMPLETED — the module may have been
    -- disabled inside that window.
    if not self:IsEnabled() then return end
    if not self.db.RerollEnabled then return end
    if self.rerollActive then return end
    if not CanRerollKey() then return end

    self.rerollActive = true
    self.rerollTimerStart = GetTime()
    self.rerollInitialMapID = C_MythicPlus.GetOwnedKeystoneMapID()
    self.rerollHasRerolled = false
    self:CreateRerollFrame()
    ApplyReminder(self.rerollFrame)
    self:UpdateRerollDisplay()
    self.rerollFrame:Show()
    StartGlow(self.rerollFrame)

    self.rerollTimerHandle = C_Timer.NewTicker(1, function() self:CheckRerollTimer() end)
    self:RegisterEvent("ITEM_CHANGED", "OnRerollItemChanged")
end

-- ITEM_CHANGED fires when one item transforms into another — exactly a
-- keystone reroll. Deferred 1s so the new keystone's data is readable before
-- re-reading the owned key.
function KH:OnRerollItemChanged()
    if not self.rerollActive then return end
    C_Timer.After(1, function()
        if not self.rerollActive then return end
        local currentMapID = C_MythicPlus.GetOwnedKeystoneMapID()
        if not self.rerollHasRerolled and currentMapID ~= self.rerollInitialMapID then
            self.rerollHasRerolled = true
            self:UpdateRerollDisplay()
        end
    end)
end

function KH:StopRerollTimer()
    self.rerollActive = false
    self.rerollTimerStart = 0
    self.rerollInitialMapID = nil
    self.rerollHasRerolled = false

    if self.rerollTimerHandle then
        self.rerollTimerHandle:Cancel()
        self.rerollTimerHandle = nil
    end
    self:UnregisterEvent("ITEM_CHANGED")
    -- Preview owns the frame's glow while the GUI is open; don't strip it.
    if not self.isPreview then StopGlow(self.rerollFrame) end

    if self.rerollFrame and not self.isPreview then self.rerollFrame:Hide() end
end

function KH:OnChallengeModeCompleted()
    if not self.db.RerollEnabled then return end
    if not IsInMythicKeystoneInstance() then return end
    C_Timer.After(1, function() self:StartRerollTimer() end)
end

---------------------------------------------------------------------------------
-- Feature 3: "Your Key?" Reminder
---------------------------------------------------------------------------------
function KH:CreateYourKeyFrame()
    if self.yourKeyFrame then return end
    self.yourKeyFrame = CreateReminderFrame("YourKey", YOURKEY_ICON)
end

function KH:CheckYourKeyTimer()
    if not self.yourKeyActive then return end
    local elapsed = GetTime() - self.yourKeyShowTime
    if elapsed >= AUTO_HIDE_SECONDS then self:HideYourKey() end
end

function KH:ShowYourKey()
    -- Re-triggering while shown restarts the auto-hide clock (WA parity).
    self.yourKeyShowTime = GetTime()
    if self.yourKeyActive then return end

    self.yourKeyActive = true

    self:CreateYourKeyFrame()
    ApplyReminder(self.yourKeyFrame)
    self.yourKeyFrame.title:SetText("Your Key?")
    SetKeyLine(self.yourKeyFrame, GetOwnedKeyDisplay())
    -- While the page previews the other reminder the two would share one
    -- spot, so the live frame stays down until HidePreview shows it.
    if not (self.isPreview and self:PreviewFrame() ~= self.yourKeyFrame) then
        self.yourKeyFrame:Show()
        StartGlow(self.yourKeyFrame)
    end

    if not self.yourKeyTicker then
        self.yourKeyTicker = C_Timer.NewTicker(1, function() self:CheckYourKeyTimer() end)
    end
end

function KH:HideYourKey()
    self.yourKeyActive = false

    if self.yourKeyTicker then
        self.yourKeyTicker:Cancel()
        self.yourKeyTicker = nil
    end
    if not self.isPreview then StopGlow(self.yourKeyFrame) end

    if self.yourKeyFrame and not self.isPreview then self.yourKeyFrame:Hide() end
end

-- Shows the "Your Key?" reminder when standing in a Mythic 0 (no active
-- keystone) instance of the dungeon matching the player's owned keystone.
-- Every return is nil-checked — the player may not have a keystone at all.
function KH:CheckYourKeyCondition()
    if not self.db.YourKeyEnabled then
        self:HideYourKey()
        return
    end

    local _, instanceType, difficultyID, _, _, _, _, instanceMapID = GetInstanceInfo()
    if instanceType ~= "party" or difficultyID ~= 23 or not instanceMapID then
        self:HideYourKey()
        return
    end

    local ownedMapID = C_MythicPlus.GetOwnedKeystoneMapID()
    if not ownedMapID or instanceMapID ~= ownedMapID then
        self:HideYourKey()
        return
    end

    self:ShowYourKey()
end

---------------------------------------------------------------------------------
-- Shared event handlers
---------------------------------------------------------------------------------
function KH:OnZoneChangedNewArea()
    if self.rerollActive and not IsInMythicKeystoneInstance() then
        self:StopRerollTimer()
    end
    self:CheckYourKeyCondition()
end

-- ZONE_CHANGED_NEW_AREA handles zone transitions; these cover the paths
-- without one: login/reload (PLAYER_ENTERING_WORLD), in-place difficulty
-- flips (PLAYER_DIFFICULTY_CHANGED), and keystone data arriving after login
-- (CHALLENGE_MODE_MAPS_UPDATE).
function KH:OnYourKeyConditionChanged()
    self:CheckYourKeyCondition()
end

-- Key just got slotted (difficulty flips to Mythic Keystone) — the "Your
-- Key?" reminder no longer applies.
function KH:OnChallengeModeStart()
    self:HideYourKey()
end

function KH:OnPlayerLeavingWorld()
    self:StopRerollTimer()
    self:HideYourKey()
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
function KH:ApplySettings()
    self:ApplyResetHook()
    self:ApplyReminders()
    self:RegisterEditModeElement()

    -- Re-evaluate active reminders so disabling a sub-feature dismisses its
    -- display immediately instead of at the next natural stop point.
    if self.rerollActive then
        if self.db.RerollEnabled then
            self:UpdateRerollDisplay()
        else
            self:StopRerollTimer()
        end
    end
    if self.yourKeyActive then
        self:CheckYourKeyCondition()
    end

    -- The preview is config-driven too. Without this the checks above only ever
    -- reach a LIVE reminder (rerollActive / yourKeyActive), so toggling a
    -- sub-reminder while the GUI page is previewing wrote the setting and left
    -- the preview frame on screen.
    if self.isPreview then self:ShowPreview() end
end

---------------------------------------------------------------------------------
-- Edit Mode
-- One element for both reminders: they share a position, so two movers on the
-- same pixels would be two ways to move one thing. Bound to the Reroll frame,
-- which the preview shows first.
---------------------------------------------------------------------------------
function KH:RegisterEditModeElement()
    if not KE.EditMode or not self.rerollFrame then return end

    KE.EditMode:RegisterElement({
        key = "KeystoneHelper",
        module = self,
        displayName = "Keystone Helper: Reminders",
        frame = self.rerollFrame,
        getPosition = function() return self.db.Position end,
        setPosition = function(pos)
            self.db.Position = pos
            self:ApplyReminders()
        end,
        getParentFrame = function()
            return KE:ResolveAnchorFrame(self.db.AnchorFrameType, self.db.ParentFrame)
        end,
        guiPath = "KeystoneHelper",
        guiTab = "KeystoneHelperReminders",
    })
end

---------------------------------------------------------------------------------
-- Preview
-- One preview for both: the reminders share every setting, so the page shows
-- one frame, Reroll while its switch is on, else Your Key. The other frame
-- stands down while the preview is up (a live one comes back in HidePreview);
-- with one shared position two copies would sit on the same pixels.
---------------------------------------------------------------------------------
function KH:PreviewFrame()
    if self.db.RerollEnabled ~= false then return self.rerollFrame, "REROLL KEY?" end
    if self.db.YourKeyEnabled ~= false then return self.yourKeyFrame, "Your Key?" end
    return nil
end

function KH:ShowPreview()
    self:CreateRerollFrame()
    self:CreateYourKeyFrame()
    self:RegisterEditModeElement()
    self.isPreview = true
    self:ApplyReminders()

    local frame, title = self:PreviewFrame()
    for _, other in ipairs({ self.rerollFrame, self.yourKeyFrame }) do
        if other ~= frame then
            StopGlow(other)
            other:Hide()
        end
    end
    if not frame then return end

    -- Preview shows the player's real key when one is owned.
    local keyLineText, keyLineIcon = GetOwnedKeyDisplay()
    if not keyLineText then keyLineText = "AA +23" end

    frame.title:SetText(title)
    SetKeyLine(frame, keyLineText, keyLineIcon)
    frame:SetAlpha(1)
    frame:Show()
    if not frame.glowActive then StartGlow(frame) end
end

function KH:HidePreview()
    self.isPreview = false
    StopGlow(self.rerollFrame)
    StopGlow(self.yourKeyFrame)

    -- A reminder that was live under the preview gets its real text and glow
    -- back; otherwise the frame was preview-only, so hide it.
    if self.rerollActive then
        self:UpdateRerollDisplay()
        self.rerollFrame:Show()
        StartGlow(self.rerollFrame)
    elseif self.rerollFrame then
        self.rerollFrame:Hide()
    end
    if self.yourKeyActive then
        SetKeyLine(self.yourKeyFrame, GetOwnedKeyDisplay())
        self.yourKeyFrame:Show()
        StartGlow(self.yourKeyFrame)
    elseif self.yourKeyFrame then
        self.yourKeyFrame:Hide()
    end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function KH:OnEnable()
    if not self.db.Enabled then return end

    self.isPreview = false
    -- Idempotent stops instead of raw flag writes; also reclaims a ticker
    -- orphaned by a disable that landed inside the 1s completion defer.
    self:StopRerollTimer()
    self:HideYourKey()

    self:ApplyResetHook()

    self:CreateRerollFrame()
    self:CreateYourKeyFrame()
    self:ApplyReminders()
    self:RegisterEditModeElement()

    self:RegisterEvent("CHALLENGE_MODE_COMPLETED", "OnChallengeModeCompleted")
    self:RegisterEvent("CHALLENGE_MODE_START", "OnChallengeModeStart")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "OnZoneChangedNewArea")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnYourKeyConditionChanged")
    self:RegisterEvent("PLAYER_DIFFICULTY_CHANGED", "OnYourKeyConditionChanged")
    self:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE", "OnYourKeyConditionChanged")
    self:RegisterEvent("PLAYER_LEAVING_WORLD", "OnPlayerLeavingWorld")
end

function KH:OnDisable()
    -- Disabling the module kills any open preview first (house pattern, cf.
    -- MythicPlusTimer/DungeonCasts), so the hides below are unconditional.
    if self.isPreview then self:HidePreview() end

    self:UnhookAll()
    self:UnregisterAllEvents()

    self:StopRerollTimer()
    self:HideYourKey()

    if self.rerollFrame then self.rerollFrame:Hide() end
    if self.yourKeyFrame then self.yourKeyFrame:Hide() end
end

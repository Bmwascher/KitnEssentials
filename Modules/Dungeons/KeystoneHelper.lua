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
local string_format = string.format

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
-- SecureHook (not a bare frame + event) mirrors the NUI/old-KE pattern —
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
-- "<icon> <dungeon> - <level>" key line below. They share one saved
-- position and appearance block — they are never on screen together live
-- (Reroll exists only inside a completed keystone run at difficulty 8;
-- Your Key? only at Mythic 0, difficulty 23).
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

    -- "<dungeon> - <level>" line, below the icon. The dungeon icon to its
    -- left is a real Texture, NOT inline |T|t markup — SOFTOUTLINE shadows
    -- strip escape codes (CustomOutline.lua StripEscapeCodes), so the width
    -- mismatch under center-justify would shift the shadow text half an
    -- icon left of the glyphs.
    local keyText = frame:CreateFontString(nil, "OVERLAY")
    keyText:SetPoint("TOP", frame, "BOTTOM", 0, -8)
    frame.keyText = keyText

    -- Standard KE icon treatment (zoom crop + 1px borders) needs a frame
    -- wrapper — AddIconBorders anchors its border textures to frame edges.
    local keyIcon = CreateFrame("Frame", nil, frame)
    keyIcon:SetPoint("RIGHT", keyText, "LEFT", -KEY_ICON_GAP, 0)
    keyIcon:Hide()
    local keyIconTex = keyIcon:CreateTexture(nil, "ARTWORK")
    keyIconTex:SetAllPoints()
    KE:ApplyIconZoom(keyIconTex)
    KE:AddIconBorders(keyIcon)
    frame.keyIcon = keyIcon
    frame.keyIconTex = keyIconTex

    return frame
end

-- "<dungeon> - <level>" plus the dungeon's icon fileID for the owned
-- keystone; nil, nil without one. C_ChallengeMode.GetMapUIInfo supplies
-- both the name and the icon.
local function GetOwnedKeyDisplay()
    local level = C_MythicPlus.GetOwnedKeystoneLevel()
    local challengeMapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    if not level or not challengeMapID then return nil, nil end

    local name, _, _, texture = C_ChallengeMode.GetMapUIInfo(challengeMapID)
    if not name then return tostring(level), texture end
    return string_format("%s - %d", name, level), texture
end

local function KeyIconSize()
    return math.floor((KH.db.FontSize or 36) * KEY_ICON_SCALE + 0.5)
end

-- Icon renders square, sized off the text height (KEY_ICON_SCALE).
local function LayoutKeyLine(frame)
    local iconSize = KeyIconSize()
    frame.keyIcon:SetSize(iconSize, iconSize)
    frame.keyText:ClearAllPoints()
    -- Shift right by half the icon+gap so the icon+text pair stays centered
    -- under the frame; no shift when the icon is hidden.
    local xOffset = frame.keyIcon:IsShown() and (iconSize + KEY_ICON_GAP) / 2 or 0
    frame.keyText:SetPoint("TOP", frame, "BOTTOM", xOffset, -8)
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

-- Shared appearance/position — one Size/font/Position DB block drives both
-- reminder frames.
local function ApplyReminderSettings(frame)
    local db = KH.db
    if not frame then return end

    frame:SetSize(db.Size or 64, db.Size or 64)
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
-- Glow helpers (shared pixel-glow shape for both reminders)
---------------------------------------------------------------------------------
local function StartPixelGlow(frame, color, lines, frequency, length, thickness)
    if not LCG or not frame then return end
    LCG.PixelGlow_Start(frame, color, lines, frequency, length, thickness, 0, 0, true, nil)
end

local function StopPixelGlow(frame)
    if not LCG or not frame then return end
    LCG.PixelGlow_Stop(frame)
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

function KH:ApplyRerollSettings()
    if not self.rerollFrame then return end
    ApplyReminderSettings(self.rerollFrame)

    -- Re-apply glow immediately so live enable/disable/color/speed edits show
    -- while the reminder (or preview) is already on screen.
    if self.isPreview or self.rerollGlowActive then
        self:StopRerollGlow()
        self:StartRerollGlow()
    end
end

function KH:UpdateRerollDisplay()
    local frame = self.rerollFrame
    if not frame then return end

    frame.title:SetText(self.rerollHasRerolled and "NEW KEY" or "REROLL KEY?")
    SetKeyLine(frame, GetOwnedKeyDisplay())
end

function KH:StartRerollGlow()
    local db = self.db
    if not db.RerollGlowEnabled then return end
    StartPixelGlow(self.rerollFrame, db.RerollGlowColor, db.RerollGlowLines,
        db.RerollGlowFrequency, db.RerollGlowLength, db.RerollGlowThickness)
    self.rerollGlowActive = true
end

function KH:StopRerollGlow()
    StopPixelGlow(self.rerollFrame)
    self.rerollGlowActive = false
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
    self:ApplyRerollSettings()
    self:UpdateRerollDisplay()
    self.rerollFrame:Show()
    self:StartRerollGlow()

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
    -- Preview owns the frame's glow while the GUI is open — don't strip it.
    if not self.isPreview then self:StopRerollGlow() end

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

function KH:ApplyYourKeySettings()
    if not self.yourKeyFrame then return end
    ApplyReminderSettings(self.yourKeyFrame)

    -- The GUI preview shows both frames at once — keep the visual-only
    -- side-by-side offset intact across settings changes while it is open.
    if self.isPreview then self:ApplyPreviewOffset() end

    if self.isPreview or self.yourKeyGlowActive then
        self:StopYourKeyGlow()
        self:StartYourKeyGlow()
    end
end

function KH:StartYourKeyGlow()
    local db = self.db
    if not db.YourKeyGlowEnabled then return end
    StartPixelGlow(self.yourKeyFrame, db.YourKeyGlowColor, db.YourKeyGlowLines,
        db.YourKeyGlowFrequency, db.YourKeyGlowLength, db.YourKeyGlowThickness)
    self.yourKeyGlowActive = true
end

function KH:StopYourKeyGlow()
    StopPixelGlow(self.yourKeyFrame)
    self.yourKeyGlowActive = false
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
    self:ApplyYourKeySettings()
    self.yourKeyFrame.title:SetText("Your Key?")
    SetKeyLine(self.yourKeyFrame, GetOwnedKeyDisplay())
    self.yourKeyFrame:Show()
    self:StartYourKeyGlow()

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
    if not self.isPreview then self:StopYourKeyGlow() end

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
    self:ApplyRerollSettings()
    self:ApplyYourKeySettings()

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
---------------------------------------------------------------------------------
function KH:RegWithEditMode()
    if not KE.EditMode or self.editModeRegistered then return end

    -- One element moves both reminders — they share a single saved position.
    KE.EditMode:RegisterElement({
        key = "KeystoneHelper",
        displayName = "Keystone Helper: Reminders",
        frame = self.rerollFrame,
        getPosition = function() return self.db.Position end,
        setPosition = function(pos)
            self.db.Position = pos
            self:ApplyRerollSettings()
            self:ApplyYourKeySettings()
        end,
        getParentFrame = function()
            return KE:ResolveAnchorFrame(self.db.AnchorFrameType, self.db.ParentFrame)
        end,
        guiPath = "KeystoneHelper",
    })

    self.editModeRegistered = true
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------
-- Preview shows both frames at once (live they never coexist) — place the
-- Your Key copy beside the Reroll copy. Visual-only, never saved. The gap
-- accounts for the key line extending past the frame edges (it's centered
-- under the icon), so the two lines can't overlap.
function KH:ApplyPreviewOffset()
    if not (self.yourKeyFrame and self.rerollFrame) then return end
    -- Only pair them up when the Reroll copy is actually on screen. With its
    -- sub-toggle off there is nothing to sit beside, and offsetting anyway
    -- would strand Your Key to the right of a hidden frame — so leave the
    -- normal position ApplyReminderSettings just set.
    if self.db.RerollEnabled == false then return end
    local db = self.db
    local keyLine = self.rerollFrame.keyText
    local textWidth = (keyLine and keyLine:GetStringWidth()) or 0
    local iconWidth = self.rerollFrame.keyIcon:IsShown()
        and (KeyIconSize() + KEY_ICON_GAP) or 0
    local overhang = math.max(0, (iconWidth + textWidth - (db.Size or 64)) / 2)
    self.yourKeyFrame:ClearAllPoints()
    self.yourKeyFrame:SetPoint("LEFT", self.rerollFrame, "RIGHT", 2 * overhang + 16, 0)
end

function KH:ShowPreview()
    self:CreateRerollFrame()
    self:CreateYourKeyFrame()
    self:RegWithEditMode()
    self.isPreview = true

    -- Preview shows the player's real key when one is owned.
    local keyLineText, keyLineIcon = GetOwnedKeyDisplay()
    if not keyLineText then keyLineText = "Algeth'ar Academy - 23" end

    -- Each reminder previews only while its own sub-toggle is on, so switching
    -- one off dismisses its preview immediately instead of leaving it up until
    -- the page is reopened. ApplySettings re-runs this whenever a toggle moves.
    self:ApplyRerollSettings()
    if self.db.RerollEnabled ~= false then
        self.rerollFrame.title:SetText("REROLL KEY?")
        SetKeyLine(self.rerollFrame, keyLineText, keyLineIcon)
        self.rerollFrame:SetAlpha(1)
        self.rerollFrame:Show()
        self:StartRerollGlow()
    else
        self:StopRerollGlow()
        self.rerollFrame:Hide()
    end

    self:ApplyYourKeySettings()   -- also applies the preview side-by-side offset
    if self.db.YourKeyEnabled ~= false then
        self.yourKeyFrame.title:SetText("Your Key?")
        SetKeyLine(self.yourKeyFrame, keyLineText, keyLineIcon)
        self.yourKeyFrame:SetAlpha(1)
        self.yourKeyFrame:Show()
        self:StartYourKeyGlow()
    else
        self:StopYourKeyGlow()
        self.yourKeyFrame:Hide()
    end
end

function KH:HidePreview()
    self.isPreview = false
    self:StopRerollGlow()
    self:StopYourKeyGlow()

    -- Undo the preview-only side-by-side offset.
    self:ApplyYourKeySettings()

    -- A reminder that was live under the preview gets its real text and glow
    -- back; otherwise the frame was preview-only, so hide it.
    if self.rerollActive then
        self:UpdateRerollDisplay()
        self:StartRerollGlow()
    elseif self.rerollFrame then
        self.rerollFrame:Hide()
    end
    if self.yourKeyActive then
        SetKeyLine(self.yourKeyFrame, GetOwnedKeyDisplay())
        self:StartYourKeyGlow()
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
    -- Idempotent stops instead of raw flag writes — also reclaims a ticker
    -- orphaned by a disable that landed inside the 1s completion defer.
    self:StopRerollTimer()
    self:HideYourKey()

    self:ApplyResetHook()

    self:CreateRerollFrame()
    self:CreateYourKeyFrame()
    self:ApplyRerollSettings()
    self:ApplyYourKeySettings()
    self:RegWithEditMode()

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

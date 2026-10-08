-- ╔══════════════════════════════════════════════════════════╗
-- ║  AlterTime.lua                                           ║
-- ║  Module: Alter Time                                      ║
-- ║  Purpose: Show the player's health at the Alter Time     ║
-- ║           cast on the spell's Cooldown Manager icon.     ║
-- ║  Note: Mage only.                                        ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- The health is written once at the cast and never read back: it is secret in
-- restricted content, and a FontString can display a secret it cannot compare.

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class AlterTime: AceModule
local AT = KitnEssentials:NewModule("AlterTime", "AceEvent-3.0")
AT.classRestriction = "MAGE"

local CreateFrame = CreateFrame
local C_Timer = C_Timer
local UnitClass = UnitClass
local issecretvalue = issecretvalue
local tostring = tostring

-- Flip to true, /reload, repro, read the log.
local DEBUG_AT = false

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
local CAST_ID = 342245
local RETURN_ID = 342247
-- The Cooldown Manager entry carries the buff id, not the cast id.
local ICON_IDS = { [342246] = 1, [444754] = 2, [342245] = 3 }
local CAP_SECONDS = 10
local PREVIEW_TEXT = "62%"
local ANCHOR_WIDTH = 80
-- Above the icon's cooldown swipe and countdown when centered on it.
local ICON_LEVEL_OFFSET = 30

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------
AT.anchor = nil
AT.holder = nil
AT.text = nil
AT.castFrame = nil
AT.capTimer = nil
AT.icon = nil
AT.iconID = nil
AT.active = false
AT.previewing = false
AT.editModeRegistered = false

local function AnchorHeight(db)
    return (db.FontSize or 16) + 6
end

-- "start", "end" or nil. A secret spell id is never compared.
function AT.Classify(event, spellID)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if issecretvalue(spellID) then return nil end
        if spellID == CAST_ID then return "start" end
        if spellID == RETURN_ID then return "end" end
        return nil
    end
    if event == "PLAYER_DEAD" or event == "PLAYER_ENTERING_WORLD" then return "end" end
    return nil
end

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function AT:UpdateDB()
    self.db = KE.db.profile.AlterTime
end

function AT:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

---------------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------------
function AT:StyleText()
    local db = self.db
    KE:ApplyFontToText(self.text, db.FontFace, db.FontSize, db.FontOutline)
    self.text:SetTextColor(KE:GetAccentColor(db.ColorMode, db.Color))
end

function AT:CreateFrames()
    if self.anchor then return end
    local db = self.db

    local anchor = CreateFrame("Frame", "KE_AlterTimeAnchor", UIParent)
    anchor:SetSize(ANCHOR_WIDTH, AnchorHeight(db))
    anchor:SetFrameStrata(db.Strata or "MEDIUM")
    KE:ApplyFramePosition(anchor, db.Position, db)
    self.anchor = anchor

    -- Mouse off, so the icon it may sit on keeps its tooltip.
    local holder = CreateFrame("Frame", "KE_AlterTimeText", anchor)
    holder:EnableMouse(false)
    holder:Hide()
    self.holder = holder

    self.text = holder:CreateFontString(nil, "OVERLAY")
    self:StyleText()
end

---------------------------------------------------------------------------------
-- Placement
---------------------------------------------------------------------------------
function AT:MoveToAnchor()
    local holder, anchor = self.holder, self.anchor
    holder:SetParent(anchor)
    holder:SetFrameStrata(self.db.Strata or "MEDIUM")
    holder:SetFrameLevel(anchor:GetFrameLevel() + 1)
    holder:ClearAllPoints()
    holder:SetAllPoints(anchor)
    self.text:ClearAllPoints()
    self.text:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    self.icon = nil
    self.iconID = nil
end

-- Parented to the icon, the holder takes its scale and hides with it. Every
-- write here is to KE's own frames. Find matched the icon on a plain id, so
-- the id recorded here is plain.
function AT:Place()
    local db = self.db
    local icon = db.AttachTo ~= "SCREEN" and KE.CDMIcons.Find("BuffIcon", ICON_IDS) or nil
    if icon then
        local holder = self.holder
        holder:SetParent(icon)
        holder:SetFrameStrata(icon:GetFrameStrata())
        -- A frame level can be made secret; arithmetic on one would error.
        local level = icon:GetFrameLevel()
        if not issecretvalue(level) then
            holder:SetFrameLevel(level + ICON_LEVEL_OFFSET)
        end
        holder:ClearAllPoints()
        holder:SetAllPoints(icon)
        -- Y is the gap away from the icon for ABOVE and BELOW, upward for CENTER.
        local x, y = db.IconX or 0, db.IconY or 2
        self.text:ClearAllPoints()
        if db.IconPosition == "CENTER" then
            self.text:SetPoint("CENTER", icon, "CENTER", x, y)
        elseif db.IconPosition == "BELOW" then
            self.text:SetPoint("TOP", icon, "BOTTOM", x, -y)
        else
            self.text:SetPoint("BOTTOM", icon, "TOP", x, y)
        end
        self.icon = icon
        self.iconID = icon:GetCooldownID()
    else
        self:MoveToAnchor()
    end
    self.holder:Show()
    if DEBUG_AT then
        local id = self.iconID
        local where = "screen"
        if issecretvalue(id) then
            where = "secret"
        elseif id ~= nil then
            where = tostring(id)
        end
        KE:Print("[AT] placed on " .. where)
    end
end

---------------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------------
local function CapEnd()
    AT:End("cap")
end

local function Replace()
    if AT.active then AT:Place() end
end

-- Runs inside Blizzard's refresh, before the re-dealt icons are drawn: the
-- number must not show for one frame on an icon now carrying another buff.
local function CheckIcon()
    local icon = AT.icon
    if not icon then return end
    local id = icon:GetCooldownID()
    if issecretvalue(id) or id == nil or id ~= AT.iconID then
        AT.holder:Hide()
        if DEBUG_AT then KE:Print("[AT] icon re-dealt, hidden") end
    end
end

function AT:Start()
    if self.previewing then return end
    self:CreateFrames()
    -- ScaleTo100 has number outputs only; the API's declared return also
    -- covers color curves. The value stays secret and is only displayed.
    ---@type number
    local pct = UnitHealthPercent("player", false, CurveConstants.ScaleTo100)
    self.text:SetFormattedText("%.0f%%", pct)
    if self.capTimer then self.capTimer:Cancel() end
    self.capTimer = C_Timer.NewTimer(CAP_SECONDS, CapEnd)
    self.active = true
    if self.db.AttachTo ~= "SCREEN" then
        KE.CDMIcons.Watch("AlterTime", Replace, CheckIcon)
    end
    if DEBUG_AT then KE:Print("[AT] start") end
    self:Place()
end

-- KE's frame never stays parented to a Blizzard icon after a window.
function AT:End(cause)
    if not self.active then return end
    self.active = false
    if self.capTimer then
        self.capTimer:Cancel()
        self.capTimer = nil
    end
    KE.CDMIcons.Unwatch("AlterTime")
    self.holder:Hide()
    self:MoveToAnchor()
    if DEBUG_AT then KE:Print("[AT] end: " .. tostring(cause)) end
end

---------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------
function AT:OnEvent(event, spellID)
    local action = AT.Classify(event, spellID)
    if action == "start" then
        self:Start()
    elseif action == "end" then
        self:End(event)
    end
end

-- AceEvent has no unit filter, so the player-only cast event lives on its own
-- frame.
function AT:EnsureCastFrame()
    if self.castFrame then return self.castFrame end
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function(_, event, _, _, spellID)
        AT:OnEvent(event, spellID)
    end)
    self.castFrame = f
    return f
end

---------------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------------
function AT:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        self:CreateFrames()
        KE.EditMode:RegisterElement({
            key = "AlterTime", displayName = "Alter Time Health", frame = self.anchor,
            module = self,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos)
                self.db.Position = pos
                KE:ApplyFramePosition(self.anchor, self.db.Position, self.db)
            end,
            getParentFrame = function() return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) end,
            guiPath = "ClassTools",
            guiTab = "AlterTime",
        })
        self.editModeRegistered = true
    end
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
function AT:ApplySettings()
    if not self:IsEnabled() then return end
    self:UpdateDB()
    if not self.anchor then return end
    local db = self.db
    self.anchor:SetSize(ANCHOR_WIDTH, AnchorHeight(db))
    self.anchor:SetFrameStrata(db.Strata or "MEDIUM")
    KE:ApplyFramePosition(self.anchor, db.Position, db)
    self:StyleText()

    if self.previewing then
        self:ShowPreview()
    elseif self.active then
        if db.AttachTo ~= "SCREEN" then
            KE.CDMIcons.Watch("AlterTime", Replace, CheckIcon)
        else
            KE.CDMIcons.Unwatch("AlterTime")
        end
        self:Place()
    end
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------
-- Always at the screen position: Alter Time's icon is hidden while the buff
-- is down.
function AT:ShowPreview()
    self:CreateFrames()
    self:RegWithEditMode()
    self:End("preview")
    self.previewing = true
    self:StyleText()
    self:MoveToAnchor()
    self.text:SetText(PREVIEW_TEXT)
    self.holder:Show()
end

function AT:HidePreview()
    self.previewing = false
    if self.holder and not self.active then self.holder:Hide() end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function AT:OnEnable()
    self:UpdateDB()
    -- Class first: neither the mover registry nor classRestriction filters on
    -- class, so without it a non-Mage would get an anchor and a mover.
    local _, class = UnitClass("player")
    if class ~= "MAGE" then return end
    if not self.db.Enabled then return end

    self:CreateFrames()
    self:EnsureCastFrame():RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    self:RegisterEvent("PLAYER_DEAD", "OnEvent")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEvent")
    self:RegWithEditMode()
end

function AT:OnDisable()
    self:End("disable")
    if self.castFrame then self.castFrame:UnregisterAllEvents() end
    self:UnregisterAllEvents()
    self:HidePreview()
    -- Clearing the guard is what lets a later enable register again.
    if KE.EditMode then KE.EditMode:UnregisterElement("AlterTime") end
    self.editModeRegistered = false
end

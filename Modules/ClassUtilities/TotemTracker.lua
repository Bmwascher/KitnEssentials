-- ╔══════════════════════════════════════════════════════════╗
-- ║  TotemTracker.lua                                        ║
-- ║  Module: Totem Tracker                                   ║
-- ║  Purpose: Custom totem icon bar with cooldown swipes,    ║
-- ║           timer text, and a destroy-all-totems macro.    ║
-- ║                                                          ║
-- ║  Not Shaman-only: Augmentation Evoker dupes ("Future     ║
-- ║  Self") are pseudo-totems and occupy real totem slots.   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class TotemTracker: AceModule, AceEvent-3.0
local TT = KitnEssentials:NewModule("TotemTracker", "AceEvent-3.0")

local CreateFrame = CreateFrame
local ipairs = ipairs
local type = type
local GetTotemInfo = GetTotemInfo
local GetNumTotemSlots = GetNumTotemSlots
local GetTime = GetTime
local UIParent = UIParent
local GetTotemDuration = GetTotemDuration
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer

local MAX_TOTEMS = MAX_TOTEMS

local containerFrame = nil
local totemButtons = {}
local destroyButtons = {}
local isPreviewActive = false

local PREVIEW_ICONS = {
    [1] = 136098, -- Healing Stream Totem
    [2] = 136024, -- Capacitor Totem
    [3] = 136114, -- Tremor Totem
    [4] = 136013, -- Earthbind Totem
    [5] = 7514181, -- Future Self (Augmentation Evoker dupe)
}

-- MAX_TOTEMS (4) and STANDARD_TOTEM_PRIORITIES are legacy constants that
-- Blizzard's own TotemFrame still hardcodes. GetNumTotemSlots() reports the
-- real count (5 on 12.0.7) and is what Blizzard's CooldownViewer uses.
local function GetTotemSlotCount()
    local count = GetNumTotemSlots()
    if type(count) ~= "number" or count < 1 then return MAX_TOTEMS end
    return count
end

function TT:UpdateDB()
    self.db = KE.db.profile.TotemTracker
end

function TT:OnInitialize()
    self:UpdateDB()
    self:CreateDestroyButtons()
    self:SetEnabledState(false)
end

function TT:CreateDestroyButtons()
    local slotCount = GetTotemSlotCount()
    if destroyButtons[slotCount] then return end
    if InCombatLockdown() then
        -- AceEvent-3.0 closure callbacks receive (event, ...args), NOT (self, ...).
        -- Capture the module table via an upvalue.
        local module = self
        self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
            module:UnregisterEvent("PLAYER_REGEN_ENABLED")
            module:CreateDestroyButtons()
        end)
        return
    end

    -- The GUI's destroy-all macro clicks KE_DestroyTotem1..5, so every slot
    -- GetNumTotemSlots() reports needs a button behind it.
    for slot = 1, slotCount do
        if not destroyButtons[slot] then
            local btn = CreateFrame("Button", "KE_DestroyTotem" .. slot, UIParent, "SecureActionButtonTemplate")
            btn:SetAttribute("type",                "destroytotem")
            btn:SetAttribute("typerelease",         "destroytotem")
            btn:SetAttribute("totem-slot",          slot)
            btn:SetAttribute("pressAndHoldAction",  1)
            btn:RegisterForClicks("AnyUp", "AnyDown")
            btn:Hide()
            destroyButtons[slot] = btn
        end
    end
end

local function ApplyCooldownTextStyle(cooldown, db)
    if not cooldown then return end

    for _, region in ipairs({ cooldown:GetRegions() }) do
        if region:GetObjectType() == "FontString" then
            KE:ApplyFontToText(region, db.FontFace, db.TimerFontSize, db.FontOutline)
            region:SetShadowOffset(0, 0)
            region:ClearAllPoints()
            region:SetPoint("CENTER", cooldown, "CENTER", 0, 0)
        end
    end
end

function TT:CreateTotemButton(slot)
    local db = self.db

    local btn = CreateFrame("Button", "KE_TotemButton" .. slot, containerFrame)
    btn:SetSize(db.IconSize, db.IconSize)
    btn:SetID(slot)

    btn:SetScript("OnEnter", function(frame)
        if GameTooltip:IsForbidden() or not frame:IsVisible() then return end
        GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
        GameTooltip:SetTotem(frame:GetID())
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        if GameTooltip:IsForbidden() then return end
        GameTooltip:Hide()
    end)

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints(btn)
    KE:ApplyIconZoom(btn.icon, 0.08)

    KE:AddIconBorders(btn, { 0, 0, 0, 1 })

    btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.highlight:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    btn.highlight:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    btn.highlight:SetColorTexture(1, 1, 1, 0.2)
    btn.highlight:SetBlendMode("ADD")

    btn.cooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    btn.cooldown:SetAllPoints(btn)
    btn.cooldown:SetDrawEdge(false)
    btn.cooldown:SetDrawSwipe(db.Swipe)
    btn.cooldown:SetReverse(db.Reverse)
    btn.cooldown:SetDrawBling(false)
    btn.cooldown:SetHideCountdownNumbers(not db.ShowTimer)
    -- Despite the name, the argument is in SECONDS: below it the countdown
    -- shows one decimal place ("8.7"). 0 disables decimals entirely.
    btn.cooldown:SetCountdownMillisecondsThreshold(db.DecimalThreshold or 0)

    btn:Hide()

    return btn
end

function TT:CreateContainer()
    if containerFrame then return end

    containerFrame = CreateFrame("Frame", "KE_TotemTracker", UIParent)
    containerFrame:SetSize(200, 50)
    containerFrame:SetClampedToScreen(true)

    for slot = 1, GetTotemSlotCount() do
        totemButtons[slot] = self:CreateTotemButton(slot)
    end
end

---@param slot number
---@return table|nil
function TT:EnsureButton(slot)
    if not containerFrame then return nil end
    if not totemButtons[slot] then
        totemButtons[slot] = self:CreateTotemButton(slot)
        self:UpdateButtonSettings(totemButtons[slot])
    end
    return totemButtons[slot]
end

function TT:UpdateButtonSettings(btn)
    local db = self.db
    btn:SetSize(db.IconSize, db.IconSize)
    btn.cooldown:SetDrawSwipe(db.Swipe)
    btn.cooldown:SetReverse(db.Reverse)
    btn.cooldown:SetHideCountdownNumbers(not db.ShowTimer)
    btn.cooldown:SetCountdownMillisecondsThreshold(db.DecimalThreshold or 0)
    ApplyCooldownTextStyle(btn.cooldown, db)
end

function TT:UpdateContainerPosition()
    if not containerFrame then return end

    local db = self.db
    local position = db.Position
    local parent = KE:ResolveAnchorFrame(db.anchorFrameType, db.ParentFrame)
    if not parent then return end

    containerFrame:SetParent(parent)
    containerFrame:ClearAllPoints()

    local direction = db.GrowDirection
    if direction == "RIGHT" then
        containerFrame:SetPoint("LEFT", parent, position.AnchorTo, position.XOffset, position.YOffset)
    elseif direction == "LEFT" then
        containerFrame:SetPoint("RIGHT", parent, position.AnchorTo, position.XOffset, position.YOffset)
    elseif direction == "UP" then
        containerFrame:SetPoint("BOTTOM", parent, position.AnchorTo, position.XOffset, position.YOffset)
    elseif direction == "DOWN" then
        containerFrame:SetPoint("TOP", parent, position.AnchorTo, position.XOffset, position.YOffset)
    else
        containerFrame:SetPoint(position.AnchorFrom, parent, position.AnchorTo, position.XOffset, position.YOffset)
    end

    containerFrame:SetFrameStrata(db.Strata)

    -- ApplyFramePosition's SetPoint would override our growth-direction
    -- anchor, so we call SnapFrameToPixels directly after the directional
    -- SetPoint has been applied.
    KE:SnapFrameToPixels(containerFrame)
end

function TT:LayoutButtons(visibleButtons)
    if not containerFrame then return end

    local db = self.db
    local direction = db.GrowDirection
    local spacing = db.IconSpacing
    local size = db.IconSize

    local buttonsToLayout = visibleButtons or totemButtons
    local numVisible = #buttonsToLayout
    if numVisible == 0 then numVisible = 1 end

    local totalWidth, totalHeight
    if direction == "RIGHT" or direction == "LEFT" then
        totalWidth  = (size * numVisible) + (spacing * (numVisible - 1))
        totalHeight = size
    else
        totalWidth  = size
        totalHeight = (size * numVisible) + (spacing * (numVisible - 1))
    end
    containerFrame:SetSize(totalWidth, totalHeight)

    for i, btn in ipairs(buttonsToLayout) do
        btn:ClearAllPoints()

        if direction == "RIGHT" then
            local xOffset = (i - 1) * (size + spacing)
            btn:SetPoint("LEFT", containerFrame, "LEFT", xOffset, 0)
        elseif direction == "LEFT" then
            local xOffset = -((i - 1) * (size + spacing))
            btn:SetPoint("RIGHT", containerFrame, "RIGHT", xOffset, 0)
        elseif direction == "UP" then
            local yOffset = (i - 1) * (size + spacing)
            btn:SetPoint("BOTTOM", containerFrame, "BOTTOM", 0, yOffset)
        elseif direction == "DOWN" then
            local yOffset = -((i - 1) * (size + spacing))
            btn:SetPoint("TOP", containerFrame, "TOP", 0, yOffset)
        end
    end
end

---@param btn table
---@param slot number
---@return boolean occupied
function TT:UpdateButton(btn, slot)
    if not btn then return false end

    -- 12.0: GetTotemInfo is SecretWhenTotemSlotSecret — every return goes SECRET
    -- while combat/encounter/challenge-mode/PvP restrictions are in effect (see
    -- SecretPredicatesDocumentation.lua). Which return we gate on is load-bearing:
    --   * haveTotem (1) is a BOOLEAN — never truth-test it. Doing so threw
    --     "boolean test on a secret boolean value" and crashed this module once.
    --   * startTime (3) is a secret NUMBER and safe to truth-test, but it comes
    --     back as 0 — TRUTHY — on an empty slot. That was harmless while we only
    --     visited totems TotemFrame had already confirmed active; now that we walk
    --     every slot ourselves, it can no longer signal occupancy.
    --   * icon (5) is the one return that is nil on an empty slot -- a probe
    --     returned false, "", 0, 0, nil, 0, 0 -- so it is what to gate on.
    -- That probe ran in OPEN-WORLD combat, where restrictions are not active — the
    -- nil-on-empty behavior still needs a smoke test inside an instance.
    local _, _, _, _, icon = GetTotemInfo(slot)

    -- Detect presence WITHOUT truth-testing or nil-comparing a secret: issecretvalue
    -- short-circuits true for a present secret, so `~= nil` only ever runs on a
    -- confirmed non-secret value. Same idiom as DungeonTrash:OnChannelStop. Note
    -- `not icon` would NOT be equivalent — that truth-tests the secret itself, which
    -- is exactly the operation that crashed this module on haveTotem.
    local occupied = (issecretvalue and issecretvalue(icon)) or (icon ~= nil)

    if not occupied then
        btn.cooldown:Clear()
        btn:Hide()
        return false
    end

    btn.icon:SetTexture(icon)
    btn.cooldown:SetCooldownFromDurationObject(GetTotemDuration(slot))
    btn:Show()
    return true
end

function TT:UpdateTotems()
    if not self.db or not self.db.Enabled then return end
    if not containerFrame then return end

    local slotCount = GetTotemSlotCount()
    local visibleButtons = {}

    if isPreviewActive then
        local currentTime = GetTime()
        for slot = 1, slotCount do
            local btn = self:EnsureButton(slot)
            if btn then
                btn.icon:SetTexture(PREVIEW_ICONS[slot] or PREVIEW_ICONS[1])
                btn.cooldown:SetCooldown(currentTime - (slot * 10), 120)
                btn:Show()
                visibleButtons[#visibleButtons + 1] = btn
            end
        end
        self:LayoutButtons(visibleButtons)
        return
    end

    -- Read the totem API directly rather than mirroring TotemFrame.totemPool.
    -- Blizzard's displays are each lossy in their own way: TotemFrame iterates
    -- only MAX_TOTEMS (4) slots so it cannot see slot 5, its pool enumerates via
    -- pairs() so icon order is nondeterministic, and the Cooldown Manager keys
    -- totems by spellID (CooldownViewerItemData.lua) — which collapses
    -- every Augmentation Evoker dupe into one entry, since they all share
    -- spellID 1259171. An independent read avoids all of it.
    --
    -- (The player reports Blizzard's bar stops at 2 dupes. That exact number is
    -- NOT explained by any Blizzard source path we could find — treat the
    -- mechanism as unidentified rather than assuming this fix inherits it.)
    --
    -- Occupied slots are sparse and unordered — dupes fill whatever slot is free
    -- (probed: 3 dupes landed in slots 1,3,4 on one pull and 1,2,4 on the next) —
    -- so walk every slot and let LayoutButtons compact the holes out.
    for slot = 1, slotCount do
        local btn = self:EnsureButton(slot)
        if self:UpdateButton(btn, slot) then
            visibleButtons[#visibleButtons + 1] = btn
        end
    end

    self:LayoutButtons(visibleButtons)
end

function TT:OnTotemUpdate()
    if self.db and self.db.Enabled then self:UpdateTotems() end
end

function TT:ApplySettings()
    self:UpdateDB()
    self:UpdateContainerPosition()

    for _, btn in ipairs(totemButtons) do
        self:UpdateButtonSettings(btn)
    end

    self:UpdateTotems()
end

function TT:ShowPreview()
    if not containerFrame then self:CreateContainer() end
    if not containerFrame then return end
    isPreviewActive = true

    for _, btn in ipairs(totemButtons) do
        btn:Show()
        btn:SetAlpha(1)
    end

    containerFrame:Show()
    self:ApplySettings()
end

function TT:HidePreview()
    isPreviewActive = false

    if not self.db or not self.db.Enabled then
        if containerFrame then containerFrame:Hide() end
    else
        self:UpdateTotems()
    end
end

function TT:TogglePreview()
    if isPreviewActive then
        self:HidePreview()
    else
        self:ShowPreview()
    end
    return isPreviewActive
end

function TT:IsPreviewActive()
    return isPreviewActive
end

function TT:OnEnable()
    if not self.db or not self.db.Enabled then return end

    self:CreateContainer()
    self:CreateDestroyButtons()
    self:UpdateContainerPosition()
    self:LayoutButtons()

    for _, btn in ipairs(totemButtons) do
        self:UpdateButtonSettings(btn)
    end

    if containerFrame then containerFrame:Show() end

    self:RegisterEvent("PLAYER_TOTEM_UPDATE",          "OnTotemUpdate")
    self:RegisterEvent("PLAYER_ENTERING_WORLD",        "OnTotemUpdate")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnTotemUpdate")
    C_Timer.After(0.1, function() self:UpdateTotems() end)

    if KE.EditMode then
        KE.EditMode:RegisterElement({
            key         = "TotemTracker",
            displayName = "Totem Tracker",
            frame       = containerFrame,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos)
                self.db.Position.AnchorFrom = pos.AnchorFrom
                self.db.Position.AnchorTo   = pos.AnchorTo
                self.db.Position.XOffset    = pos.XOffset
                self.db.Position.YOffset    = pos.YOffset
                self:ApplySettings()
            end,
            getParentFrame = function()
                return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)
            end,
            guiPath = "TotemTracker",
        })
    end
end

function TT:OnDisable()
    isPreviewActive = false

    self:UnregisterAllEvents()

    for _, btn in ipairs(totemButtons) do
        btn:SetAlpha(0)
        btn:Hide()
    end

    if containerFrame then containerFrame:Hide() end
    if KE.EditMode then KE.EditMode:UnregisterElement("TotemTracker") end
end

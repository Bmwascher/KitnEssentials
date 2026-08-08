-- ╔══════════════════════════════════════════════════════════╗
-- ║  AuraHeaders.lua                                         ║
-- ║  Module: Player Buffs / Player Debuffs                   ║
-- ║  Purpose: Replaces Blizzard's buff and debuff frames     ║
-- ║           with two secure aura headers.                  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

-- Both frames are SecureAuraHeaderTemplate: the game scans, sorts and lays out
-- the auras exactly as it does for its own frames, and hands us buttons to
-- style. That is why this costs no more than the default frames -- there is no
-- polling and no OnUpdate anywhere in here.
--
-- Sorting is NOT configurable and never should be. Blizzard's frames show auras
-- in natural index order with no separation, so the attributes below are fixed
-- to match. This feature is skinning; spacing is the one layout control that
-- earns its place because the look depends on it.

local CreateFrame = CreateFrame
local unpack = unpack
local pairs = pairs
local ipairs = ipairs
local InCombatLockdown = InCombatLockdown
local RegisterAttributeDriver = RegisterAttributeDriver
local GetWeaponEnchantInfo = GetWeaponEnchantInfo
local GetInventoryItemTexture = GetInventoryItemTexture
local GetTime = GetTime
local C_UnitAuras = C_UnitAuras
local C_DurationUtil = C_DurationUtil
local GameTooltip = GameTooltip

local durationObj = C_DurationUtil and C_DurationUtil.CreateDuration and C_DurationUtil.CreateDuration()

-- Dispel-school colour from Advanced Debuffs' palette, not a second copy of it.
-- That module exposes its curve for this and resolves it even while disabled,
-- since the palette lives in the profile.
local function DispelBorderColor(unit, auraInstanceID)
    if not (auraInstanceID and C_UnitAuras.GetAuraDispelTypeColor) then return nil end
    local ad = KitnEssentials:GetModule("AuraDebuffs", true)
    local curve = ad and ad.GetDispelColorCurve and ad:GetDispelColorCurve()
    if not curve then return nil end
    return C_UnitAuras.GetAuraDispelTypeColor(unit, auraInstanceID, curve)
end

local DIRECTION_TO_POINT = {
    DOWN_RIGHT = "TOPLEFT",    DOWN_LEFT = "TOPRIGHT",
    UP_RIGHT   = "BOTTOMLEFT", UP_LEFT   = "BOTTOMRIGHT",
    RIGHT_DOWN = "TOPLEFT",    RIGHT_UP  = "BOTTOMLEFT",
    LEFT_DOWN  = "TOPRIGHT",   LEFT_UP   = "BOTTOMRIGHT",
}
local DIRECTION_TO_X_MULT = {
    DOWN_RIGHT = 1, DOWN_LEFT = -1, UP_RIGHT = 1, UP_LEFT = -1,
    RIGHT_DOWN = 1, RIGHT_UP = 1, LEFT_DOWN = -1, LEFT_UP = -1,
}
local DIRECTION_TO_Y_MULT = {
    DOWN_RIGHT = -1, DOWN_LEFT = -1, UP_RIGHT = 1, UP_LEFT = 1,
    RIGHT_DOWN = -1, RIGHT_UP = 1, LEFT_DOWN = -1, LEFT_UP = 1,
}
local IS_HORIZONTAL_GROWTH = {
    RIGHT_DOWN = true, RIGHT_UP = true, LEFT_DOWN = true, LEFT_UP = true,
}
KE.AURA_GROWTH_DIRECTIONS = DIRECTION_TO_POINT

-- Runs in the SECURE environment when the header creates a button. It may
-- only touch the button and its header -- no addon upvalues, no globals.
local INITIAL_CONFIG_FUNCTION = [[
    local header = self:GetParent()
    self:SetWidth(header:GetAttribute('config-width'))
    self:SetHeight(header:GetAttribute('config-height'))
]]

------------------------------------------------------------------------
-- Shared behaviour
------------------------------------------------------------------------

local function MakeHeaderModule(config)
    ---@class AuraHeaderModule: AceModule, AceEvent-3.0
    local M = KitnEssentials:NewModule(config.moduleName, "AceEvent-3.0")
    M.buttons = {}

    -- Disabling live cannot undo what OnEnable did: Blizzard's frame has had
    -- its events stripped and cannot be revived mid-session. Without this flag
    -- a profile switch to "off" would hide our header and leave nothing behind
    -- it. Stay enabled until a reload resolves the mismatch.
    M.keReloadOnDisable = true

    function M:UpdateDB()
        self.db = KE.db.profile[config.dbKey]
    end

    function M:OnInitialize()
        self:UpdateDB()
        self:SetEnabledState(false)
    end

    local function OnEnter(button)
        if not M.db or not M.db.ShowTooltips then return end
        GameTooltip:SetOwner(button, "ANCHOR_BOTTOMLEFT")

        local index = button:GetAttribute("index")
        if index then
            local unit = button:GetParent():GetAttribute("unit")
            if GameTooltip:SetUnitAura(unit, index, config.filter) then GameTooltip:Show() end
        elseif button:GetAttribute("target-slot") then
            if GameTooltip:SetInventoryItem("player", button:GetID()) then GameTooltip:Show() end
        end
    end

    local function OnLeave()
        GameTooltip:Hide()
    end

    local function UpdateAura(button, index)
        local unit = button:GetParent():GetAttribute("unit")
        local info = C_UnitAuras.GetAuraDataByIndex(unit, index, config.filter)
        if not info then return end

        button.Icon:SetTexture(info.icon)
        button.Count:SetText(C_UnitAuras.GetAuraApplicationDisplayCount(unit, info.auraInstanceID, 2, 999))

        if button.Cooldown then
            local duration = C_UnitAuras.GetAuraDuration(unit, info.auraInstanceID)
            if duration then
                button.Cooldown:SetCooldownFromDurationObject(duration)
                button.Cooldown:Show()
            else
                button.Cooldown:Hide()
            end
        end

        -- The school cannot be read directly: DebuffTypeColor is gone in 12.0
        -- and dispelName is secret, so keying a table on it would be a
        -- forbidden comparison. The curve resolves it internally, and its
        -- Color channels may be secret too -- pass them to the texture, never
        -- inspect them.
        if button.SetBorderColor then
            local c
            if config.colorByType and M.db.ColorByType ~= false then
                c = DispelBorderColor(unit, info.auraInstanceID)
            end
            if c then
                button:SetBorderColor(c:GetRGBA())
            else
                button:SetBorderColor(unpack(M.db.BorderColor))
            end
        end
    end

    local function UpdateEnchant(button, slot)
        local duration, count, _
        if slot == 16 then
            _, duration, count = GetWeaponEnchantInfo()
        elseif slot == 17 then
            _, _, _, _, _, duration, count = GetWeaponEnchantInfo()
        else
            return
        end

        button.Icon:SetTexture(GetInventoryItemTexture("player", slot))
        button.Count:SetText(count and count > 1 and count or "")
        if button.SetBorderColor then button:SetBorderColor(unpack(M.db.EnchantBorderColor)) end

        if button.Cooldown and duration and durationObj then
            durationObj:SetTimeFromStart(GetTime(), duration / 1000)
            button.Cooldown:SetCooldownFromDurationObject(durationObj)
            button.Cooldown:Show()
        elseif button.Cooldown then
            button.Cooldown:Hide()
        end
    end

    local function OnAttributeChanged(button, attribute, ...)
        if attribute == "index" then
            UpdateAura(button, ...)
        elseif attribute == "target-slot" then
            UpdateEnchant(button, ...)
        end
    end

    function M:ApplyButtonStyle(button)
        local db = self.db
        if button.Cooldown then
            button.Cooldown:SetReverse(db.Reverse)
            button.Cooldown:SetHideCountdownNumbers(not db.ShowTimer)
            button.Cooldown:SetSwipeColor(0, 0, 0, db.Swipe and 0.6 or 0)
            local text = button.Cooldown:GetRegions()
            if text and text.SetFont then
                KE:ApplyFont(text, db.FontFace, db.TimerFontSize, db.FontOutline)
            end
        end
        if button.Count then
            KE:ApplyFont(button.Count, db.FontFace, db.CountFontSize, db.FontOutline)
            button.Count:SetTextColor(unpack(db.CountColor))
        end
        if button.SetBorderColor then button:SetBorderColor(unpack(db.BorderColor)) end
    end

    local function StyleButton(button)
        if not button or M.buttons[button] then return end
        M.buttons[button] = true
        local db = M.db

        -- AddBorders disables per-texture pixel snap; leave it off. Re-enabling
        -- it fights the grid maths, and SetBorderColor disables it again on
        -- every repaint, so a recoloured border would draw unlike a fresh one.
        KE:AddBorders(button, db.BorderColor)

        button.Icon = button:CreateTexture(nil, "ARTWORK")
        button.Icon:SetAllPoints()
        KE:ApplyIconZoom(button.Icon)

        button.Cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        button.Cooldown:SetAllPoints()
        button.Cooldown:SetDrawEdge(false)
        button.Cooldown:SetDrawBling(false)

        button.Count = button:CreateFontString(nil, "OVERLAY")
        button.Count:SetPoint("BOTTOMRIGHT", -1, 1)

        button:HookScript("OnEnter", OnEnter)
        button:HookScript("OnLeave", OnLeave)
        button:HookScript("OnAttributeChanged", OnAttributeChanged)

        M:ApplyButtonStyle(button)
    end

    function M:RestyleAll()
        for button in pairs(self.buttons) do
            self:ApplyButtonStyle(button)
        end
    end

    -- The mover is what Edit Mode grabs, so it has to be the size of the
    -- actual aura block. A fixed 10x10 handle was a dot on screen.
    function M:SizeMover()
        if not self.mover then return end
        local db = self.db
        local pitch = db.IconSize + db.IconSpacing
        local across, down = db.IconsPerRow * pitch, db.MaxRows * pitch
        if IS_HORIZONTAL_GROWTH[db.GrowthDirection] then
            self.mover:SetSize(across, down)
        else
            self.mover:SetSize(down, across)
        end
    end

    function M:UpdateHeader()
        if not self.header then return end
        if InCombatLockdown() then
            self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnLeaveCombat")
            return
        end

        local db = self.db
        local h = self.header
        local pitch = db.IconSize + db.IconSpacing
        local direction = db.GrowthDirection
        local point = DIRECTION_TO_POINT[direction] or "TOPLEFT"
        local xMult = DIRECTION_TO_X_MULT[direction] or 1
        local yMult = DIRECTION_TO_Y_MULT[direction] or -1

        h:SetAttribute("config-width", db.IconSize)
        h:SetAttribute("config-height", db.IconSize)

        -- Fixed to Blizzard's behaviour: natural order, no separation. Not
        -- options -- see the file header.
        h:SetAttribute("sortMethod", "INDEX")
        h:SetAttribute("sortDirection", "+")
        h:SetAttribute("separateOwn", 0)
        h:SetAttribute("includeWeapons", config.weapons and 1 or 0)

        h:SetAttribute("point", point)
        h:SetAttribute("wrapAfter", db.IconsPerRow)
        h:SetAttribute("maxWraps", db.MaxRows)

        if IS_HORIZONTAL_GROWTH[direction] then
            h:SetAttribute("minWidth", db.IconsPerRow * pitch)
            h:SetAttribute("minHeight", db.MaxRows * pitch)
            h:SetAttribute("xOffset", xMult * pitch)
            h:SetAttribute("yOffset", 0)
            h:SetAttribute("wrapXOffset", 0)
            h:SetAttribute("wrapYOffset", yMult * pitch)
        else
            h:SetAttribute("minWidth", db.MaxRows * pitch)
            h:SetAttribute("minHeight", db.IconsPerRow * pitch)
            h:SetAttribute("xOffset", 0)
            h:SetAttribute("yOffset", yMult * pitch)
            h:SetAttribute("wrapXOffset", xMult * pitch)
            h:SetAttribute("wrapYOffset", 0)
        end

        -- config-width/height are read by initialConfigFunction, which the
        -- header runs ONLY when it creates a button. Buttons that already exist
        -- keep their old size, so a size change appeared to need a /reload --
        -- the reload was just recreating them. Resize them here instead.
        -- Settings-apply path only, so the table is not a hot-path allocation,
        -- and the whole function already returned early if in combat.
        for _, child in ipairs({ h:GetChildren() }) do
            if child.SetSize then child:SetSize(db.IconSize, db.IconSize) end
        end

        self:SizeMover()
    end

    function M:OnLeaveCombat()
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        -- Enabling in combat leaves CreateHeader (and FinishEnable) unfinished.
        if not self.header then
            self:CreateHeader()
            self:FinishEnable()
            return
        end
        self:UpdateHeader()
        self:ApplyPosition()
    end

    function M:CreateHeader()
        -- templateMissing latches: OnLeaveCombat retries CreateHeader on
        -- every combat drop, and there is nothing to retry once the template
        -- is gone.
        if self.header or self.templateMissing then return end
        if InCombatLockdown() then
            self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnLeaveCombat")
            return
        end

        -- A plain mover carries the configured position; the secure header
        -- anchors to it by its growth corner. Anchoring the header directly
        -- would make every growth-direction change a protected reposition.
        self.mover = self.mover or CreateFrame("Frame", config.moverName, UIParent)

        -- The secure aura header template can vanish out from under us: it is
        -- still in the FrameXML dump but can be load-gated off this game
        -- type, so nothing registers it. CreateFrame against a missing
        -- template errors, and this enable path runs from an AceEvent handler
        -- (OnLeaveCombat) whose dispatch chain has no pcall -- the throw
        -- would take every other PLAYER_REGEN_ENABLED subscriber with it.
        --
        -- Bail cleanly and say why once. Remove this guard only when the
        -- container-based rebuild lands.
        local built, h = pcall(CreateFrame, "Frame", config.frameName, UIParent,
            "SecureAuraHeaderTemplate")
        if not built or not h then
            self.templateMissing = true
            KE:WarnMissingTemplate(config.featureName or config.moduleName)
            return
        end
        h:SetAttribute("template", "KE_AuraButtonTemplate")
        h:SetAttribute("weaponTemplate", "KE_AuraButtonTemplate")
        h:SetAttribute("unit", "player")
        h:SetAttribute("filter", config.filter)
        h:SetAttribute("initialConfigFunction", INITIAL_CONFIG_FUNCTION)
        self.header = h

        self:UpdateHeader()

        -- Vehicle seats swap which unit the player's auras belong to.
        RegisterAttributeDriver(h, "unit", "[vehicleui] vehicle; player")

        -- The header announces each button it creates through a child<N> /
        -- tempEnchant<N> attribute; that is where styling gets attached.
        h:HookScript("OnAttributeChanged", function(_, attribute, ...)
            local prefix = attribute:sub(1, 5)
            if prefix == "child" or prefix == "tempe" then StyleButton(...) end
        end)

        self:ApplyPosition()
        h:Show()
    end

    function M:ApplyPosition()
        if InCombatLockdown() then
            self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnLeaveCombat")
            return
        end
        local db = self.db
        local point = DIRECTION_TO_POINT[db.GrowthDirection] or "TOPLEFT"
        local anchor = KE:ResolveAnchorFrame(db.anchorFrameType, db.ParentFrame)

        if self.mover then
            self:SizeMover()
            self.mover:ClearAllPoints()
            self.mover:SetPoint(point, anchor, db.Position.AnchorTo, db.Position.XOffset, db.Position.YOffset)
        end
        if self.header then
            self.header:ClearAllPoints()
            self.header:SetPoint(point, self.mover or anchor, point, 0, 0)
            self.header:SetFrameStrata(db.Strata)
        end
    end

    function M:UpdatePosition(pos)
        if InCombatLockdown() then return end
        self.db.Position.AnchorTo = pos.AnchorTo
        self.db.Position.XOffset = pos.XOffset
        self.db.Position.YOffset = pos.YOffset
        self:ApplyPosition()
    end

    function M:ApplySettings()
        if not self:IsEnabled() then return end
        self:UpdateDB()
        self:UpdateHeader()
        self:ApplyPosition()
        self:RestyleAll()
    end

    -- ElvUI replaces the same Blizzard frames. When it is loaded and the user
    -- has left KE's ElvUI hand-off on, stand down entirely rather than hide a
    -- frame ElvUI is also managing. Turning the hand-off off is the user
    -- saying they want KE to take it.
    function M:ShouldStandDown()
        return (KE.ShouldNotLoadModule and KE:ShouldNotLoadModule()) == true
    end

    -- Everything that only makes sense once OUR header exists: removing
    -- Blizzard's frame and registering the Edit Mode element. Idempotent --
    -- the regen path calls it again after a deferred build.
    function M:FinishEnable()
        if self.finishedEnable or not self.header then return end
        self.finishedEnable = true

        -- Blizzard's frame goes away. Its CVar callbacks have to be dropped
        -- too or they re-show it whenever those settings change.
        local blizz = _G[config.blizzardFrame]
        if blizz then
            blizz:UnregisterAllEvents()
            blizz:Hide()
            if _G.CVarCallbackRegistry then
                _G.CVarCallbackRegistry:UnregisterCallback("consolidateBuffs", blizz)
                _G.CVarCallbackRegistry:UnregisterCallback("collapseExpandBuffs", blizz)
            end
        end

        if not self.mover or not KE.EditMode then return end
        KE.EditMode:RegisterElement({
            key = config.moduleName,
            displayName = config.displayName,
            frame = self.mover,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos) self:UpdatePosition(pos) end,
            getParentFrame = function() return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) end,
            guiPath = config.guiPath,
        })
    end

    function M:OnEnable()
        self:UpdateDB()
        if not self.db.Enabled then return end
        if self:ShouldStandDown() then return end

        -- Build the replacement BEFORE removing Blizzard's. When the template
        -- is missing CreateHeader bails; when enabling in combat it defers to
        -- the regen handler. In BOTH cases Blizzard's frame must survive --
        -- hiding first and then failing to build leaves no buff display at
        -- all. FinishEnable no-ops until the header exists.
        self:CreateHeader()
        self:FinishEnable()
        self:RegisterEvent("PLAYER_ENTERING_WORLD", "ApplyPosition")
        self:RegisterEvent("UI_SCALE_CHANGED", "ApplyPosition")
        self:RegisterEvent("DISPLAY_SIZE_CHANGED", "ApplyPosition")
    end

    function M:OnDisable()
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        self:UnregisterEvent("UI_SCALE_CHANGED")
        self:UnregisterEvent("DISPLAY_SIZE_CHANGED")
        self.finishedEnable = nil
        -- A secure header cannot be destroyed, and Blizzard's frame cannot be
        -- revived mid-session once its events are gone; a reload restores the
        -- default cleanly.
        if self.header and not InCombatLockdown() then self.header:Hide() end
    end

    return M
end

------------------------------------------------------------------------

MakeHeaderModule({
    moduleName    = "BuffTracking",
    dbKey         = "BuffTracking",
    filter        = "HELPFUL",
    weapons       = true,
    frameName     = "KE_BuffFrame",
    moverName     = "KE_BuffMover",
    blizzardFrame = "BuffFrame",
    displayName   = "BUFFS",
    guiPath       = "AuraHeaders_Buffs",
    featureName   = "Player Buffs",
})

MakeHeaderModule({
    moduleName    = "PlayerDebuffTracking",
    dbKey         = "PlayerDebuffTracking",
    filter        = "HARMFUL",
    weapons       = false,
    colorByType   = true,
    frameName     = "KE_DebuffFrame",
    moverName     = "KE_DebuffMover",
    blizzardFrame = "DebuffFrame",
    displayName   = "DEBUFFS",
    guiPath       = "AuraHeaders_Debuffs",
    featureName   = "Player Debuffs",
})

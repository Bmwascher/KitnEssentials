-- ╔══════════════════════════════════════════════════════════╗
-- ║  AuraHeaders.lua                                         ║
-- ║  Module: Player Buffs / Player Debuffs                   ║
-- ║  Purpose: Declares two aura-engine displays for the       ║
-- ║           player's own buffs and debuffs, and hides       ║
-- ║           Blizzard's equivalents while they are shown.    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local CreateFrame = CreateFrame
local hooksecurefunc = hooksecurefunc
local C_Timer = C_Timer

-- One-shot conversion for profiles saved before the rebuild. The old display
-- named a growth direction with a single two-token string; the engine wants a
-- direction per axis plus which axis fills first. Three other keys are plain
-- renames onto the names the engine already uses.
--
-- Guarded by its own flag rather than by a nil check on any one key, because
-- a profile can legitimately be missing any of them.
local function MigrateProfile(profile, dbKey)
    local db = profile and profile[dbKey]
    if not db or db._migratedToEngine then return end
    db._migratedToEngine = true

    if db.GrowthDirection then
        db.GrowHorizontal, db.GrowVertical, db.GrowAxis =
            KE.AuraRules.ConvertGrowthDirection(db.GrowthDirection)
        db.GrowthDirection = nil
    end

    if db.CountFontSize then
        db.FontSize = db.CountFontSize
        db.CountFontSize = nil
    end

    if db.CountColor then
        db.StackColor = db.CountColor
        db.CountColor = nil
    end

    -- The old switch was a boolean; the engine takes a mode string, and only
    -- "dispel" turns the school colouring on.
    if db.ColorByType ~= nil then
        db.BorderColorMode = db.ColorByType and "dispel" or "flat"
        db.ColorByType = nil
    end
end

-- Ordinary long-duration player buffs and common player debuffs. Cycled by
-- the declarations' buildPreview below.
local PREVIEW_BUFF_ICONS   = { 136078, 135932, 135940, 136107, 135953, 132333 }
local PREVIEW_DEBUFF_ICONS = { 136118, 136182, 136207, 135813, 132090, 136182 }

------------------------------------------------------------------------
-- Shared behaviour
------------------------------------------------------------------------

local function MakeHeaderModule(config)
    ---@class AuraHeaderModule: AceModule, AceEvent-3.0
    local M = KitnEssentials:NewModule(config.moduleName, "AceEvent-3.0")

    -- Disabling live cannot undo what OnEnable did: Blizzard's frame has had
    -- its events stripped and cannot be revived mid-session. Without this flag
    -- a profile switch to "off" would hide our display and leave nothing behind
    -- it. Stay enabled until a reload resolves the mismatch.
    M.keReloadOnDisable = true

    local DECLARATION = {
        key                = config.moduleName,
        dbKey              = config.dbKey,
        displayName        = config.displayName,
        guiPath            = config.guiPath,
        -- NOT "Default". That maps to AuraUtil.DefaultAuraCompare, which
        -- orders player-cast first, then priority, then applicable, and only
        -- then by instance id -- under a frame cap that changes WHICH auras
        -- survive, not just their order. The display being replaced pins
        -- natural index order, and a pure instance-id sort is the closest
        -- equivalent the container offers.
        sortMethod         = "AuraInstanceIDOnly",
        defaultIconsPerRow = 12,

        -- The player's own auras, so the display follows the player into a
        -- vehicle seat rather than suspending itself the way a fight tracker
        -- does.
        vehiclePolicy = "follow",

        groups = {
            {
                key         = "auras",
                buildFilter = function() return config.filter end,
                buildCandidates = function() return {} end,
                -- borderColorKey is declared on the group AND inside
                -- capabilities because creation reads it from the group and
                -- restyling reads it from the capability table.
                borderColorKey = "BorderColor",
                capabilities = {
                    hasBorder     = true,
                    hasDispelRing = config.dispelRing or false,
                    hasDispelBadge = false,
                    hasGlow       = false,
                    canCancel     = config.cancellable or false,
                    borderColorKey = "BorderColor",
                },
                getDispelColorCurve = config.dispelRing
                    and function()
                        local ad = KitnEssentials:GetModule("AuraDebuffs", true)
                        return ad and ad.GetDispelColorCurve and ad:GetDispelColorCurve() or nil
                    end
                    or nil,
            },
        },

        splitLimit = function(total)
            return { auras = total }
        end,

        buildPreview = function(_, total)
            local icons = config.previewIcons
            local entries = {}
            for i = 1, total do
                entries[i] = {
                    icon     = icons[((i - 1) % #icons) + 1],
                    groupKey = "auras",
                    count    = (i % 4 == 1 and 2) or (i % 4 == 2 and 5) or 0,
                }
            end
            return entries
        end,
    }

    if config.weapons then
        DECLARATION.itemEnchantments = {
            slots = {
                AuraContainerItemEnchantmentSlot.MainHand,
                AuraContainerItemEnchantmentSlot.OffHand,
                AuraContainerItemEnchantmentSlot.Ranged,
            },
            -- An enchant frame is dressed through the same style path as an
            -- aura button, so it carries a capability table of the same shape
            -- and is passed to that path AS the group. No cancel: an enchant
            -- is cancelled from the character sheet, not from this display.
            -- Its border takes its own colour setting, which is the whole
            -- reason the colour is named per group rather than fixed.
            borderColorKey = "EnchantBorderColor",
            capabilities = {
                hasBorder      = true,
                hasDispelRing  = false,
                hasDispelBadge = false,
                hasGlow        = false,
                canCancel      = false,
                borderColorKey = "EnchantBorderColor",
            },
        }
    end

    function M:UpdateDB()
        self.db = KE.db.profile[config.dbKey]
    end

    function M:OnInitialize()
        MigrateProfile(KE.db.profile, config.dbKey)
        self:UpdateDB()
        self:SetEnabledState(false)
    end

    -- ElvUI replaces the same Blizzard frames. When it is loaded and the user
    -- has left KE's ElvUI hand-off on, stand down entirely rather than hide a
    -- frame ElvUI is also managing. Turning the hand-off off is the user
    -- saying they want KE to take it.
    function M:ShouldStandDown()
        return (KE.ShouldNotLoadModule and KE:ShouldNotLoadModule()) == true
    end

    -- Everything that only makes sense once OUR display exists: removing
    -- Blizzard's frame and dropping its callbacks. Idempotent.
    function M:FinishEnable()
        if self.finishedEnable or not (self.display and self.display.handle) then return end
        self.finishedEnable = true

        self:SuppressBlizzard()
        self:WatchEditMode()
        -- One-shot: the CVar callbacks re-show the frame whenever those
        -- settings change, and dropping them twice buys nothing.
        local blizz = _G[config.blizzardFrame]
        if blizz and _G.CVarCallbackRegistry then
            _G.CVarCallbackRegistry:UnregisterCallback("consolidateBuffs", blizz)
            _G.CVarCallbackRegistry:UnregisterCallback("collapseExpandBuffs", blizz)
        end
    end

    -- Blizzard's frame goes away -- and does NOT stay away on its own.
    --
    -- Unregistering its events stops it updating, but Edit Mode does not
    -- drive it by event: importing or switching a layout runs UpdateSystem
    -- over every registered system, which reaches the frame's
    -- UpdateShownState and calls SetShown(true) DIRECTLY. Entering and
    -- leaving Edit Mode do the same. A one-shot Hide at login therefore
    -- survives until the first layout import, after which Blizzard's buffs
    -- are back on top of ours until a /reload.
    function M:SuppressBlizzard()
        local blizz = _G[config.blizzardFrame]
        if not blizz then return end
        blizz:UnregisterAllEvents()
        blizz:Hide()
    end

    -- Re-assert whenever Edit Mode has touched its systems.
    --
    -- Deferred a frame ON PURPOSE: EDIT_MODE_LAYOUTS_UPDATED is dispatched
    -- from inside Edit Mode's own layout pass -- a secureexecuterange over
    -- every registered system -- so hiding the frame there writes state
    -- mid-pass. Our own frame, our own execution, one frame later.
    --
    -- The manager hooks are separate because entering Edit Mode re-shows the
    -- systems and leaving it re-runs UpdateShownState, and NEITHER raises
    -- EDIT_MODE_LAYOUTS_UPDATED -- that event is the only one the game has
    -- for Edit Mode, so the rest has to come from the manager frame itself.
    function M:WatchEditMode()
        if self.editModeWatcher then return end

        local function ReAssert()
            -- IsEnabled() is the AceModule truth; db.Enabled alone can
            -- disagree with it around enable/disable transitions.
            if self:IsEnabled() and self.db and self.db.Enabled
               and not self:ShouldStandDown() then
                self:SuppressBlizzard()
            end
        end
        local function Defer() C_Timer.After(0, ReAssert) end

        -- Lazy: the Edit Mode addon may not have loaded when we enable.
        local function HookManager()
            local mgr = _G.EditModeManagerFrame
            if not mgr or self.editModeHooked then return end
            self.editModeHooked = true
            mgr:HookScript("OnShow", Defer)
            hooksecurefunc(mgr, "Hide", Defer)
        end

        local w = CreateFrame("Frame")
        self.editModeWatcher = w
        w:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
        w:RegisterEvent("PLAYER_ENTERING_WORLD")
        w:SetScript("OnEvent", function()
            HookManager()
            Defer()
        end)
        HookManager()
    end

    function M:OnEnable()
        self:UpdateDB()
        if not self.db.Enabled then return end
        if self:ShouldStandDown() then return end

        -- Build the replacement BEFORE removing Blizzard's. FinishEnable
        -- no-ops until the container exists, so a failure to build leaves
        -- Blizzard's frame in place rather than leaving no display at all.
        if not self.display then
            self.display = KE.AuraEngine.Register(self, DECLARATION, function() return self.db end)
        else
            KE.AuraEngine.RegisterEvents(self.display)
        end

        KE.AuraEngine.ApplySettings(self.display)
        self:FinishEnable()
    end

    function M:OnDisable()
        KE.AuraEngine.SetModuleEnabled(self.display, false)
        self.finishedEnable = nil
    end

    function M:ApplySettings()
        self:UpdateDB()
        KE.AuraEngine.ApplySettings(self.display)
        self:FinishEnable()
    end

    function M:ShowPreview()
        KE.AuraEngine.ShowPreview(self.display)
    end

    function M:HidePreview()
        KE.AuraEngine.HidePreview(self.display)
    end

    return M
end

------------------------------------------------------------------------

MakeHeaderModule({
    moduleName    = "BuffTracking",
    dbKey         = "BuffTracking",
    filter        = "HELPFUL",
    weapons       = true,
    cancellable   = true,
    previewIcons  = PREVIEW_BUFF_ICONS,
    blizzardFrame = "BuffFrame",
    displayName   = "BUFFS",
    guiPath       = "AuraHeaders_Buffs",
})

MakeHeaderModule({
    moduleName    = "PlayerDebuffTracking",
    dbKey         = "PlayerDebuffTracking",
    filter        = "HARMFUL",
    weapons       = false,
    dispelRing    = true,
    previewIcons  = PREVIEW_DEBUFF_ICONS,
    blizzardFrame = "DebuffFrame",
    displayName   = "DEBUFFS",
    guiPath       = "AuraHeaders_Debuffs",
})

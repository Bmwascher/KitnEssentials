-- ╔══════════════════════════════════════════════════════════╗
-- ║  Main.lua                                                ║
-- ║  Purpose: Main addon initialization, AceAddon setup,     ║
-- ║           slash command registration, and login flow.    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local IsInInstance = IsInInstance
local LibStub = LibStub

local aceAddon = LibStub("AceAddon-3.0")

local DEFAULT_PROFILE = "Default"

---@class KitnEssentials : AceAddon-3.0, AceEvent-3.0, AceHook-3.0
local KitnEssentials = aceAddon:NewAddon("KitnEssentials", "AceEvent-3.0", "AceHook-3.0")
_G.KitnEssentials = KitnEssentials
-- Dev/debug handle to the private addon namespace. /run macro chunks can't
-- reach `select(2, ...)` locals, and leak-hunt probes repeatedly need
-- KE-level state (singletons, helpers). Not a public API.
_G.KITNESSENTIALS_NS = KE

-- Every module enable/disable funnels through these two AceAddon methods
-- (GUI checkboxes, the profile enable-state sync, and module:Enable()
-- internally), so this is the one seam that keeps GUI previews honest
-- across toggles — the handler no-ops unless the GUI or edit mode is
-- showing previews. PreviewManager exists: Globals.lua loads before this
-- file (Core.xml).
hooksecurefunc(KitnEssentials, "EnableModule", function(_, name)
    KE.PreviewManager:OnModuleEnableChanged(name)
    -- Conflicts are keyed on the KE module being ENABLED (Core/Conflicts.lua
    -- BuildConflictQueue), so the login scan correctly skips a module that
    -- ships off -- and nothing re-armed it afterwards. The Tooltips page tells
    -- the user in shipped text to "enable this one to be prompted again", and
    -- that promise went unkept until a reload or /kes conflicts. Gated on the
    -- login scan having run, and deferred out of combat, both matching that
    -- scan's own conventions. Rescanning is a no-op when nothing conflicts and
    -- returns early while a prompt is already open, so a profile switch
    -- enabling several modules costs one queue, not one per module.
    -- Deferred a frame, NOT run inline, and coalesced. RunAfterCombat calls
    -- straight through outside combat, and a profile switch enables modules from
    -- inside RefreshAllModules and then raises its own reload prompt in the SAME
    -- call stack. KE:CreatePrompt is a singleton that replaces the live dialog
    -- with a bare Hide() and never runs its callbacks, so an inline conflict
    -- prompt was destroyed unanswered, leaving promptActive set and the user
    -- with both features live.
    -- Next frame the refresh has finished, so the conflict prompt replaces the
    -- generic reload prompt instead; answering it raises a reload prompt of its
    -- own, and when nothing conflicts no prompt is built at all.
    if KE.loginConflictScanDone and KE.ScanAddonConflicts and not KE.conflictScanQueued then
        KE.conflictScanQueued = true
        C_Timer.After(0, function()
            KE.conflictScanQueued = nil
            KE:RunAfterCombat(function() KE:ScanAddonConflicts() end)
        end)
    end
end)
hooksecurefunc(KitnEssentials, "DisableModule", function(_, name)
    KE.PreviewManager:OnModuleEnableChanged(name)
end)

KE.encounterActive = false

---------------------------------------------------------------------------------
-- AceAddon Lifecycle
---------------------------------------------------------------------------------

function KitnEssentials:OnInitialize()
    local defaults = KE:GetDefaultDB()
    if not defaults then
        defaults = { profile = {} }
    end
    KE.db = LibStub("AceDB-3.0"):New("KitnEssentialsDB", defaults, true) --[[@as AceDB]]
    if KE.LDS then
        KE.LDS:EnhanceDatabase(KE.db, "KitnEssentials")
    end
    if KE.db.global and KE.db.global.UseGlobalProfile then
        local profileName = KE.db.global.GlobalProfile or DEFAULT_PROFILE
        KE.db:SetProfile(profileName)
    end

    -- One-time DungeonTimers DB migration runs BEFORE FillProfileDefaults
    -- so it can detect "fresh saved data" vs "already-defaulted" states
    -- (FillProfileDefaults would otherwise auto-populate the new top-level
    -- DungeonTimers slot, defeating the promote-from-old-path branch).
    if KE._MigrateDungeonTimersDB then KE._MigrateDungeonTimersDB() end

    -- Backfill missing nested defaults into the saved profile (AceDB's defaults
    -- system doesn't deep-fill sub-tables that already exist in saved data),
    -- then validate font keys against LSM. Order matters — fill first so the
    -- font validator can see all expected keys.
    KE:FillProfileDefaults()
    KE:ValidateProfileFonts()

    -- Profile change callbacks
    KE.db.RegisterCallback(KE, "OnProfileChanged", function()
        if KE._MigrateDungeonTimersDB then KE._MigrateDungeonTimersDB() end
        KE:FillProfileDefaults()
        KE:ValidateProfileFonts()
        if KE.ProfileManager and not KE.ProfileManager:IsRefreshSuppressed() then
            KE.ProfileManager:RefreshAllModules()
        end
    end)
    KE.db.RegisterCallback(KE, "OnProfileCopied", function()
        if KE._MigrateDungeonTimersDB then KE._MigrateDungeonTimersDB() end
        KE:FillProfileDefaults()
        KE:ValidateProfileFonts()
        if KE.ProfileManager and not KE.ProfileManager:IsRefreshSuppressed() then
            KE.ProfileManager:RefreshAllModules()
        end
    end)
    KE.db.RegisterCallback(KE, "OnProfileReset", function()
        if KE._MigrateDungeonTimersDB then KE._MigrateDungeonTimersDB() end
        KE:FillProfileDefaults()
        KE:ValidateProfileFonts()
        if KE.ProfileManager and not KE.ProfileManager:IsRefreshSuppressed() then
            KE.ProfileManager:RefreshAllModules()
        end
    end)

    -- Activate saved theme settings now that DB is ready
    if KE.RefreshTheme then KE:RefreshTheme() end
end

---------------------------------------------------------------------------------
-- Minimap Icon
---------------------------------------------------------------------------------

function KE:SetupMinimapIcon()
    local LDB = LibStub("LibDataBroker-1.1", true)
    local LDBIcon = LibStub("LibDBIcon-1.0", true)
    if not LDB or not LDBIcon then return end

    local MyLDB = LDB:NewDataObject("KitnEssentials", {
        type = "launcher",
        text = "KitnEssentials",
        icon = "Interface\\AddOns\\KitnEssentials\\Media\\Icon\\KitnUI",
        OnClick = function(_, button)
            if button == "LeftButton" then
                if KE.GUIFrame then KE.GUIFrame:Toggle() end
            elseif button == "RightButton" then
                if KE.EditMode then KE.EditMode:Toggle() end
            elseif button == "MiddleButton" then
                ReloadUI()
            end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine(KE:ColorTextByTheme("Kitn") .. "|cffffffffEssentials|r")
            tt:AddLine(KE:ColorTextByTheme("Left-Click") .. " to open options", 1, 1, 1)
            tt:AddLine(KE:ColorTextByTheme("Right-Click") .. " to toggle edit mode", 1, 1, 1)
            tt:AddLine(KE:ColorTextByTheme("Middle-Click") .. " to reload UI", 1, 1, 1)
        end,
    })

    LDBIcon:Register("KitnEssentials", MyLDB, KE.db.profile.Minimap)
    KE.minimapIcon = LDBIcon
end

---------------------------------------------------------------------------------
-- Event Handlers
---------------------------------------------------------------------------------

local function OnEncounterEnd()
    local _, instanceType = IsInInstance()
    if instanceType == "raid" and KE.encounterActive then
        KE.encounterActive = false
    end
end

local function OnEncounterStart()
    local _, instanceType = IsInInstance()
    if instanceType == "raid" then
        KE.encounterActive = true
    end
end

local function OnPlayerEnteringWorld()
    for _, module in KitnEssentials:IterateModules() do
        if module:IsEnabled() and module.ApplySettings then
            module:ApplySettings()
        end
    end
end

---------------------------------------------------------------------------------
-- Addon Enable
---------------------------------------------------------------------------------

function KitnEssentials:OnEnable()
    if KE.RefreshTheme then KE:RefreshTheme() end
    if KE.Init then KE:Init() end

    -- Enable modules based on saved settings
    local skipSkinning = KE:ShouldNotLoadModule()
    for name, module in self:IterateModules() do
        if module.db and module.db.Enabled then
            -- Skip skinning modules when ElvUI handles skinning
            if not (skipSkinning and (name:find("^Skin") or module.keDeferToReload)) then
                self:EnableModule(name)
            end
        end
    end

    -- Slash commands (/cd, /wa, SetPITarget)
    if KE.ApplySlashCommands then KE:ApplySlashCommands() end

    -- Minimap icon (delayed for theme readiness)
    C_Timer.After(1, function()
        KE:SetupMinimapIcon()
    end)

    -- Event registration
    self:RegisterEvent("ENCOUNTER_END", OnEncounterEnd)
    self:RegisterEvent("ENCOUNTER_START", OnEncounterStart)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", OnPlayerEnteringWorld)
end

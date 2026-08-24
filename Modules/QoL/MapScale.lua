-- ╔══════════════════════════════════════════════════════════╗
-- ║  MapScale.lua                                            ║
-- ║  Module: World Map Scale                                 ║
-- ║  Purpose: Windowed and maximized world map scale, applied║
-- ║           only while the map is hidden.                  ║
-- ║  Configured from the QoL > CVars page.                   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class MapScale: AceModule, AceEvent-3.0
local MS = KitnEssentials:NewModule("MapScale", "AceEvent-3.0")

local C_Timer = C_Timer
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local _G = _G

local DEFAULT_SCALE = 1.2
local DEFAULT_MAX_SCALE = 1

-- A plain frame, deliberately NOT AceEvent. AceAddon calls every embedded
-- library's OnEmbedDisable the moment OnDisable returns, and AceEvent's answer
-- is UnregisterAllEvents -- so a restore that has to wait for combat to end
-- would be torn down before it could ever fire. This frame outlives the module.
local regenWatcher = CreateFrame("Frame")
regenWatcher:SetScript("OnEvent", function() MS:OnRegen_Apply() end)

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function MS:UpdateDB()
    self.db = KE.db.profile.MapScale
end

---------------------------------------------------------------------------------
-- Scale Accessors
---------------------------------------------------------------------------------
function MS:MaximizedScale()
    return (self.db and self.db.MaximizedScale) or DEFAULT_MAX_SCALE
end

function MS:CurrentScale()
    local map = _G.WorldMapFrame
    if not map then return 1 end
    if map.IsMaximized and map:IsMaximized() then return self:MaximizedScale() end
    return (self.db and self.db.Scale) or DEFAULT_SCALE
end

---------------------------------------------------------------------------------
-- Core Logic
---------------------------------------------------------------------------------
-- Owner is the map frame itself, so the invoked call is map:SetScale(<bound
-- number>) -- a Blizzard function with plain arguments and no addon closure in
-- the path. A closure here poisons the pin cascade the map runs on open.
function MS:RegisterMinMaxScale()
    local map = _G.WorldMapFrame
    if not (map and _G.EventRegistry) then return end
    _G.EventRegistry:UnregisterCallback("WorldMapMinimized", map)
    _G.EventRegistry:UnregisterCallback("WorldMapMaximized", map)
    if not self:IsEnabled() then return end
    local scale = (self.db and self.db.Scale) or DEFAULT_SCALE
    _G.EventRegistry:RegisterCallback("WorldMapMinimized", map.SetScale, map, scale)
    _G.EventRegistry:RegisterCallback("WorldMapMaximized", map.SetScale, map, self:MaximizedScale())
end

-- A maximized map is drawn over BlackoutFrame, a fullscreen frame whose Blackout
-- texture hides the world behind it and whose mouse layer swallows clicks.
-- Scaling the map below 1 shrinks the map but not that frame, so the result is
-- letterboxing rather than a smaller map over the world. The original texture is
-- captured first so turning the option off restores Blizzard's look.
function MS:ApplyBlackout()
    local map = _G.WorldMapFrame
    local blackout = map and map.BlackoutFrame
    local tex = blackout and blackout.Blackout
    if not tex then return end

    -- Never touch a live maximized map's mouse layer in combat.
    if InCombatLockdown() then
        self._blackoutDirty = true
        self:WaitForRegen()
        return
    end
    self._blackoutDirty = nil

    if self._blackoutTexture == nil then
        self._blackoutTexture = tex:GetTexture() or false
    end

    if self:IsEnabled() and self:MaximizedScale() < 1 then
        tex:SetTexture(nil)
        blackout:EnableMouse(false)
    else
        if self._blackoutTexture then tex:SetTexture(self._blackoutTexture) end
        blackout:EnableMouse(true)
    end
end

-- One handler for every deferral. The latch is what keeps it to one: arming an
-- already-armed frame is harmless, but a second arm with no matching disarm
-- would leave the watcher live after the work was done.
function MS:WaitForRegen()
    if self._regenPending then return end
    self._regenPending = true
    regenWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function MS:OnRegen_Apply()
    regenWatcher:UnregisterEvent("PLAYER_REGEN_ENABLED")
    self._regenPending = nil

    if self._blackoutDirty then self:ApplyBlackout() end
    if self._restorePending then self:RestoreScale() end
    if self._scaleDirty then self:ApplyScale() end
end

function MS:ApplyScale()
    local map = _G.WorldMapFrame
    if not map then return end

    self:RegisterMinMaxScale()

    -- A deferred change can land after the module was switched off. Writing the
    -- module's configured scale then would be the one thing a disabled module
    -- must never do.
    if not self:IsEnabled() then
        self._scaleDirty = nil
        return
    end

    if InCombatLockdown() then
        self._scaleDirty = true
        self:WaitForRegen()
        return
    end
    if map:IsShown() then
        -- Never scale a live map. The OnHide hook picks it up.
        self._scaleDirty = true
        return
    end
    self._scaleDirty = nil
    map:SetClampedToScreen(true)
    map:SetScale(self:CurrentScale())
end

-- Putting Blizzard's scale back has exactly the same preconditions as any other
-- write this module makes: never in combat, never on a shown map. It is one
-- function so those conditions cannot drift apart between the three callers --
-- the teardown, the OnHide hook and the regen handler.
function MS:RestoreScale()
    if self:IsEnabled() then
        self._restorePending = nil
        return
    end
    local map = _G.WorldMapFrame
    if not map then return end

    if InCombatLockdown() then
        self._restorePending = true
        self:WaitForRegen()
        return
    end
    if map:IsShown() then
        self._restorePending = true
        return
    end
    self._restorePending = nil
    if map:GetScale() ~= 1 then map:SetScale(1) end
end

-- Deferred application point for changes made while the map was open. Runs after
-- Blizzard's own handler, so the map is hidden by then and no cascade runs.
function MS:InstallHooks()
    if self.hooked then return end
    local map = _G.WorldMapFrame
    if not map then return end
    map:HookScript("OnHide", function()
        if self._restorePending then self:RestoreScale() end
        if self._scaleDirty and self:IsEnabled() then
            self:ApplyScale()
        end
    end)
    self.hooked = true
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
-- Called by the central PLAYER_ENTERING_WORLD loop (Core/Main.lua) and after a
-- profile switch (Core/ProfileManager.lua). Safe before WorldMapFrame exists.
function MS:ApplySettings()
    self:UpdateDB()
    if not self.db then return end

    self:InstallHooks()
    self:ApplyBlackout()
    if self:IsEnabled() then self:ApplyScale() end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function MS:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function MS:OnEnable()
    if not self.db or not self.db.Enabled then return end

    -- Blizzard_WorldMap / Blizzard_MapCanvas may not be loaded at login.
    self:RegisterEvent("ADDON_LOADED", function(_, addonName)
        if addonName == "Blizzard_WorldMap" or addonName == "Blizzard_MapCanvas" then
            self:ApplySettings()
        end
    end)

    C_Timer.After(0, function()
        self:ApplySettings()
    end)
end

function MS:OnDisable()
    -- Only ADDON_LOADED lives on AceEvent, so this clears that and nothing
    -- else. The regen watcher is a plain frame precisely so the restore below
    -- survives what Ace does to this module straight after OnDisable returns.
    self:UnregisterAllEvents()

    self:RegisterMinMaxScale() -- unregisters: IsEnabled is false by now
    -- The hook is normally already in place; this covers a module that was
    -- enabled before the map addon loaded, which would otherwise have nothing
    -- to carry a deferred restore.
    self:InstallHooks()
    self:ApplyBlackout()       -- restores Blizzard's blackout
    self:RestoreScale()
end

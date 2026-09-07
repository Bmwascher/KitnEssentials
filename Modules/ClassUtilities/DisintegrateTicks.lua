-- ╔══════════════════════════════════════════════════════════╗
-- ║  DisintegrateTicks.lua                                   ║
-- ║  Module: Disintegrate Ticks                              ║
-- ║  Purpose: Displays tick marks on cast bar during         ║
-- ║           Disintegrate channels.                         ║
-- ║  Note: Evoker only (Devastation/Preservation).           ║
-- ╚══════════════════════════════════════════════════════════╝

-- luacheck: globals OverlayPlayerCastingBarFrame

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local DT = KitnEssentials:NewModule("DisintegrateTicks", "AceEvent-3.0")
DT.classRestriction = "EVOKER"

local CreateFrame = CreateFrame
local GetTime = GetTime
local C_SpellBook = C_SpellBook
local C_Spell = C_Spell
local C_AddOns = C_AddOns
local PlayerUtil = PlayerUtil
local hooksecurefunc = hooksecurefunc
local math_ceil = math.ceil
local UnitChannelInfo = UnitChannelInfo
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer


---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
local DISINTEGRATE = 356995
local MASS_DISINTEGRATE = 436335
local DISINTEGRATE_TALENT = 1219723 -- gives 5th tick
local FIRE_BREATH = 357208
local FIRE_BREATH_FONT = 382266
local ETERNITY_SURGE = 359073
local ETERNITY_SURGE_FONT = 382411
local NATURAL_CONVERGENCE = 369913
local STACK_EXPIRY = 15
local DISINTEGRATE_BASE_DURATION = 3.0  -- Seconds at 0% haste (pre-Natural Convergence)

local DEVASTATION = 1467
local PRESERVATION = 1468

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------
DT.maxTicks = 4
DT.channeling = false
DT.massDisintegrateStacks = 0
DT.lastGainedStack = 0
DT.hasTipTheScalesActive = false
DT.chaining = false
DT.lastStart = 0
DT.firstTick = 0
DT.prevEndTime = nil
DT.prevHastedTickInterval = nil
DT.lastKnownHaste = 0  -- 12.0.5: derived from cast duration instead of UnitSpellHaste (secret-valued)
local CastBarRegistry = {
    providers = {},
    handles = {},
    retryTickers = {},
    pendingLoads = {},
    resolvedProviders = {},
    generation = 0,
}

local hookedScripts = setmetatable({}, { __mode = "k" })
local hookedMethods = setmetatable({}, { __mode = "k" })
local overlayCallbacksRegistered = false

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function DT:UpdateDB()
    self.db = KE.db.profile.DisintegrateTicks
end

function DT:OnInitialize()
    self:UpdateDB()
    CastBarRegistry.frame = self
    self:SetEnabledState(false)
end

local function IsEmpower(spellId)
    return spellId == FIRE_BREATH
        or spellId == FIRE_BREATH_FONT
        or spellId == ETERNITY_SURGE
        or spellId == ETERNITY_SURGE_FONT
end

local function KnowsMassDisintegrate()
    return C_SpellBook.IsSpellKnownOrInSpellBook(MASS_DISINTEGRATE)
end

function DT:IsValidSpec()
    local specId = PlayerUtil.GetCurrentSpecID()
    return specId == DEVASTATION or specId == PRESERVATION
end

function DT:QueryTalentsAndHide()
    self.maxTicks = C_SpellBook.IsSpellKnown(DISINTEGRATE_TALENT) and 5 or 4
    self:HideTicks()
end

---------------------------------------------------------------------------------
-- Cast Bar Registry
---------------------------------------------------------------------------------
function CastBarRegistry:RegisterProvider(provider)
    table.insert(self.providers, provider)
end

function CastBarRegistry:ResolveProvider(provider, generation)
    if generation ~= self.generation or not DT:IsEnabled() then
        return
    end

    if self.resolvedProviders[provider.id] == generation then
        return
    end

    if provider.addon ~= nil then
        local _, loaded = C_AddOns.IsAddOnLoaded(provider.addon)
        if not KE:IsSafeValue(loaded) or not loaded then
            if self.pendingLoads[provider.id] == generation then
                return
            end

            self.pendingLoads[provider.id] = generation
            EventUtil.ContinueOnAddOnLoaded(provider.addon, function()
                if self.pendingLoads[provider.id] == generation then
                    self.pendingLoads[provider.id] = nil
                end

                if not DT:IsEnabled() or generation ~= self.generation then
                    return
                end

                self:ResolveProvider(provider, generation)
            end)
            return
        end
    end

    if provider.isEnabled ~= nil and not provider.isEnabled() then
        return
    end

    self.resolvedProviders[provider.id] = generation
    provider.register(self, self.frame)
end

function CastBarRegistry:EnsureHandle(id, anchor, priority, textFrame)
    local handle = self.handles[id]

    if handle == nil then
        handle = {
            id = id,
            anchor = anchor,
            textFrame = textFrame,
            width = 0,
            height = 0,
            priority = priority,
            ticks = {},
            isActive = nil,
        }
        self.handles[id] = handle
    else
        handle.anchor = anchor
        handle.textFrame = textFrame
        handle.priority = priority
    end

    return handle
end

function CastBarRegistry:GetHandle(id)
    return self.handles[id]
end

function CastBarRegistry:SyncDimensions(id, anchor)
    local handle = self:GetHandle(id)
    if handle == nil or anchor == nil then
        return
    end

    local width, height = anchor:GetSize()
    if not KE:IsSafeValue(width) or not KE:IsSafeValue(height) then
        return
    end

    width = math_ceil(width)
    height = math_ceil(height)
    self.frame:UpdateHandleDimensions(id, width, height)
end

function CastBarRegistry:GetVisibleBars()
    local candidates = {}

    for _, handle in pairs(self.handles) do
        if handle.anchor ~= nil then
            local shown = handle.anchor:IsShown()
            if KE:IsSafeValue(shown) and shown then
                if handle.isActive == nil or handle.isActive(handle) then
                    table.insert(candidates, handle)
                end
            end
        end
    end

    table.sort(candidates, function(a, b)
        if a.priority == b.priority then
            return a.id < b.id
        end

        return a.priority > b.priority
    end)

    local visible = {}
    local seen = {}

    for _, handle in ipairs(candidates) do
        if not seen[handle.anchor] then
            seen[handle.anchor] = true
            table.insert(visible, handle)
        end
    end

    return visible
end

function CastBarRegistry:GetPrimaryHandle()
    local visible = self:GetVisibleBars()
    if visible[1] ~= nil then
        return visible[1]
    end

    local bestFallback = nil
    for _, handle in pairs(self.handles) do
        if handle.anchor ~= nil and (not bestFallback or handle.priority > bestFallback.priority) then
            bestFallback = handle
        end
    end

    return bestFallback
end

function CastBarRegistry:ResolveWithRetry(resolve, callback, maxAttempts, interval)
    maxAttempts = maxAttempts or 5
    interval = interval or 1

    local generation = self.generation
    if not DT:IsEnabled() or generation ~= self.generation then
        return
    end

    local immediate = resolve()
    if immediate ~= nil then
        callback(immediate)
        return
    end

    local attempts = 0
    local ticker = nil
    ticker = C_Timer.NewTicker(interval, function()
        if not DT:IsEnabled() or generation ~= self.generation then
            if ticker ~= nil then
                ticker:Cancel()
                self.retryTickers[ticker] = nil
            end
            return
        end

        attempts = attempts + 1
        local anchor = resolve()
        if anchor ~= nil then
            if ticker ~= nil then
                ticker:Cancel()
                self.retryTickers[ticker] = nil
            end
            callback(anchor)
            return
        end

        if attempts >= maxAttempts and ticker ~= nil then
            ticker:Cancel()
            self.retryTickers[ticker] = nil
        end
    end)
    self.retryTickers[ticker] = true
end

function CastBarRegistry:CancelRetries()
    for ticker in pairs(self.retryTickers) do
        ticker:Cancel()
        self.retryTickers[ticker] = nil
    end
end

function CastBarRegistry:ResolveAllProviders()
    self.generation = self.generation + 1
    self.resolvedProviders = {}

    for _, provider in ipairs(self.providers) do
        self:ResolveProvider(provider, self.generation)
    end
end

function CastBarRegistry.HookFrameScriptOnce(frame, scriptName, callback)
    local scripts = hookedScripts[frame]
    if scripts == nil then
        scripts = {}
        hookedScripts[frame] = scripts
    end

    if scripts[scriptName] then
        return
    end

    frame:HookScript(scriptName, callback)
    scripts[scriptName] = true
end

function CastBarRegistry.HookMethodOnce(object, methodName, callback)
    local methods = hookedMethods[object]
    if methods == nil then
        methods = {}
        hookedMethods[object] = methods
    end

    if methods[methodName] then
        return
    end

    hooksecurefunc(object, methodName, callback)
    methods[methodName] = true
end

local function RegisterOverlayCallbacks()
    if overlayCallbacksRegistered then
        return
    end

    EventRegistry:RegisterCallback("OverlayPlayerCastBar.OnShow", function()
        if not DT:IsEnabled() then
            return
        end

        DT:OnCastBarShown(
            "blizzard_overlay",
            OverlayPlayerCastingBarFrame,
            OverlayPlayerCastingBarFrame.Text,
            12
        )
    end, DT)

    EventRegistry:RegisterCallback("OverlayPlayerCastBar.OnHide", function()
        if not DT:IsEnabled() then
            return
        end

        DT:OnCastBarHidden("blizzard_overlay")
    end, DT)
    overlayCallbacksRegistered = true
end

local function RegisterBlizzardCastBarProvider()
    local blizzardId = "blizzard"
    local playerCastBar = PlayerCastingBarFrame

    local handle = CastBarRegistry:EnsureHandle(blizzardId, playerCastBar, 10, playerCastBar.Text)
    handle.isActive = function(self)
        local anchor = self.anchor
        local showCastbar = anchor.showCastbar
        local shouldShow = GameRulesUtil.ShouldShowPlayerCastBar()

        if not KE:IsSafeValue(showCastbar) or not KE:IsSafeValue(shouldShow) then
            return false
        end

        return showCastbar ~= false and shouldShow
    end

    DT:OnCastBarShown(blizzardId, playerCastBar, playerCastBar.Text, 10)

    CastBarRegistry.HookFrameScriptOnce(playerCastBar, "OnShow", function(self)
        if not DT:IsEnabled() then
            return
        end

        DT:OnCastBarShown(blizzardId, self, self.Text, 10)
    end)

    CastBarRegistry.HookFrameScriptOnce(playerCastBar, "OnHide", function()
        if not DT:IsEnabled() then
            return
        end

        DT:OnCastBarHidden(blizzardId)
    end)

    CastBarRegistry.HookFrameScriptOnce(playerCastBar, "OnSizeChanged", function(self)
        if not DT:IsEnabled() then
            return
        end

        CastBarRegistry:SyncDimensions(blizzardId, self)
    end)

    CastBarRegistry.HookMethodOnce(playerCastBar, "SetLook", function(self)
        if not DT:IsEnabled() then
            return
        end

        CastBarRegistry:SyncDimensions(blizzardId, self)
    end)

    CastBarRegistry.HookMethodOnce(EditModeManagerFrame, "UpdateLayoutInfo", function()
        if not DT:IsEnabled() then
            return
        end

        CastBarRegistry:SyncDimensions(blizzardId, PlayerCastingBarFrame)
        DT:RefreshPrimaryHandle()
    end)
end

CastBarRegistry:RegisterProvider({
    id = "blizzard",
    addon = nil,
    priority = 10,
    isEnabled = function()
        return true
    end,
    register = function()
        RegisterBlizzardCastBarProvider()
    end,
})

local thirdPartyCastBars = {
    {
        id = "msuf",
        addon = "MidnightSimpleUnitFrames",
        priority = 50,
        container = function()
            return rawget(_G, "MSUF_PlayerCastbar")
        end,
        anchor = function(container)
            return container.statusBar
        end,
    },
    {
        id = "eqol_castbar",
        addon = "EnhanceQOL",
        priority = 40,
        container = function()
            return rawget(_G, "EQOLPlayerCastBar")
        end,
        anchor = function(container)
            return container
        end,
        text = function(container)
            return container.Text
        end,
    },
    {
        id = "eqol_uf",
        addon = "EnhanceQOL",
        priority = 40,
        container = function()
            return rawget(_G, "EQOLUFPlayerHealthCast")
        end,
        anchor = function(container)
            return container
        end,
        text = function(container)
            return container.Text
        end,
    },
    {
        id = "azortharion",
        addon = "AzortharionUI",
        priority = 45,
        container = function()
            return rawget(_G, "AUI_Castbar_player")
        end,
        anchor = function(container)
            return container._castbar
        end,
    },
    {
        id = "ellesmere",
        addon = "EllesmereUI",
        priority = 45,
        container = function()
            return rawget(_G, "ERB_CastBarFrame")
        end,
        anchor = function(container)
            return container._bar
        end,
    },
}

for _, castBar in ipairs(thirdPartyCastBars) do
    CastBarRegistry:RegisterProvider({
        id = castBar.id,
        addon = castBar.addon,
        priority = castBar.priority,
        isEnabled = function()
            local _, loaded = C_AddOns.IsAddOnLoaded(castBar.addon)
            return KE:IsSafeValue(loaded) and loaded
        end,
        register = function(registry, owner)
            if not DT:IsEnabled() then
                return
            end

            local function Resolve()
                local container = castBar.container()
                if container == nil then
                    return nil
                end

                local anchor = castBar.anchor(container)
                if anchor == nil then
                    return nil
                end

                return container
            end

            local function RegisterContainer(container)
                local function Sync()
                    if not DT:IsEnabled() then
                        return
                    end

                    local currentContainer = castBar.container()
                    if currentContainer == nil then
                        return
                    end

                    local anchor = castBar.anchor(currentContainer)
                    if anchor == nil then
                        return
                    end

                    local textFrame = castBar.text ~= nil and castBar.text(currentContainer) or nil
                    owner:OnCastBarShown(castBar.id, anchor, textFrame, castBar.priority)
                end

                local function OnHide()
                    if not DT:IsEnabled() then
                        return
                    end

                    owner:OnCastBarHidden(castBar.id)
                end

                Sync()

                if container.HookScript ~= nil then
                    CastBarRegistry.HookFrameScriptOnce(container, "OnShow", Sync)
                    CastBarRegistry.HookFrameScriptOnce(container, "OnHide", OnHide)
                else
                    CastBarRegistry.HookMethodOnce(container, "Show", Sync)
                    CastBarRegistry.HookMethodOnce(container, "Hide", OnHide)
                end
            end

            registry:ResolveWithRetry(Resolve, RegisterContainer, 5, 1)
        end,
    })
end

---------------------------------------------------------------------------------
-- Haste / Tick Helpers
---------------------------------------------------------------------------------
-- 12.0.5: UnitSpellHaste("player") returns a secret value in encounters, so we
-- back-solve haste from the actual Disintegrate channel length instead. At 0%
-- haste with no Natural Convergence the base channel is 3.0s; Natural
-- Convergence shortens by 20%. `actualDuration` (endTime - startTime) plus the
-- NC talent state gives us haste multiplier = baseDuration / actualDuration.
-- Result is cached in self.lastKnownHaste so no-arg calls (UpdateTicks, preview)
-- can read it without another stat-API query.
function DT:GetHaste(actualDuration)
    if actualDuration ~= nil and actualDuration > 0 then
        local baseDuration = DISINTEGRATE_BASE_DURATION
        if C_SpellBook.IsSpellKnown(NATURAL_CONVERGENCE) then
            baseDuration = baseDuration * 0.8
        end
        local hasteMultiplier = baseDuration / actualDuration
        self.lastKnownHaste = (hasteMultiplier - 1) * 100
        return hasteMultiplier
    end
    return 1 + self.lastKnownHaste / 100
end

function DT:GetTickInterval()
    local base = 1
    -- Azure Celerity reduces tick interval by 25%
    if C_SpellBook.IsSpellKnown(DISINTEGRATE_TALENT) then
        base = base * 0.75
    end
    -- Natural Convergence reduces total cast time by 20%
    if C_SpellBook.IsSpellKnown(NATURAL_CONVERGENCE) then
        base = base * 0.8
    end
    return base
end

---------------------------------------------------------------------------------
-- Tick Management
---------------------------------------------------------------------------------
function DT:CreateTick(handle)
    local db = self.db
    local r, g, b, a = KE:ResolveColor(db.TickColor, { 1, 1, 1, 0.8 })
    local tick = handle.anchor:CreateTexture(nil, "OVERLAY")
    tick:SetColorTexture(r, g, b, a)
    tick:Hide()
    return tick
end

function DT:HideTicks(handle)
    if handle ~= nil then
        for _, tick in next, handle.ticks do
            tick:Hide()
        end
    else
        for _, registeredHandle in pairs(CastBarRegistry.handles) do
            for _, tick in next, registeredHandle.ticks do
                tick:Hide()
            end
        end
    end
end

function DT:UpdateHandleTicks(handle, duration)
    if handle.anchor == nil or handle.width <= 0 or duration == nil or duration <= 0 then
        return
    end

    self:HideTicks(handle)

    local hastedTickInterval = self:GetTickInterval() / self:GetHaste()
    local pixelsPerSecond = handle.width / duration

    for i = 1, self.maxTicks do
        local tick = handle.ticks[i]

        if tick == nil then
            tick = self:CreateTick(handle)
            handle.ticks[i] = tick
        else
            local tickParent = tick:GetParent()

            if not KE:IsSafeValue(tickParent) or tickParent ~= handle.anchor then
                tick = self:CreateTick(handle)
                handle.ticks[i] = tick
            end
        end

        local tickWidth = (self.db.TickWidth or 2) * KE:GetPixelSize()
        tick:SetSize(tickWidth, handle.height * 0.95)
        tick:ClearAllPoints()

        local tickTime = i * hastedTickInterval

        if self.chaining then
            local interval = (duration - self.firstTick) / (self.maxTicks - 1)
            tickTime = self.firstTick + (i - 1) * interval
        end

        tick:SetPoint("CENTER", handle.anchor, "LEFT", (duration - tickTime) * pixelsPerSecond, 0)

        if tickTime < duration * 0.99 then
            tick:Show()
        else
            tick:Hide()
        end
    end
end

function DT:UpdateTicksAll(duration)
    if duration == nil or duration <= 0 then
        return
    end

    self.activeChannelDuration = duration

    self:HideTicks()

    for _, handle in ipairs(CastBarRegistry:GetVisibleBars()) do
        self:UpdateHandleTicks(handle, duration)
    end
end

function DT:ApplyTickColor()
    local db = self.db
    local r, g, b, a = KE:ResolveColor(db.TickColor, { 1, 1, 1, 0.8 })
    for _, handle in pairs(CastBarRegistry.handles) do
        for _, tick in next, handle.ticks do
            tick:SetColorTexture(r, g, b, a)
        end
    end
end

function DT:UpdateHandleDimensions(id, width, height)
    local handle = CastBarRegistry:GetHandle(id)

    if handle == nil then
        return
    end

    if width ~= handle.width or height ~= handle.height then
        handle.width = width
        handle.height = height

        if self.channeling and self.activeChannelDuration ~= nil then
            self:UpdateHandleTicks(handle, self.activeChannelDuration)
        else
            self:HideTicks(handle)
        end
    end
end

function DT:RefreshPrimaryHandle()
    self.primaryHandle = CastBarRegistry:GetPrimaryHandle()
end

function DT:OnCastBarShown(id, anchor, textFrame, priority)
    CastBarRegistry:EnsureHandle(id, anchor, priority, textFrame)
    CastBarRegistry:SyncDimensions(id, anchor)
    self:RefreshPrimaryHandle()

    if self.channeling and self.activeChannelDuration ~= nil then
        local handle = CastBarRegistry:GetHandle(id)

        if handle ~= nil then
            self:UpdateHandleTicks(handle, self.activeChannelDuration)
        end
    end
end

function DT:OnCastBarHidden(id)
    local handle = CastBarRegistry:GetHandle(id)

    if handle ~= nil then
        self:HideTicks(handle)
    end

    self:RefreshPrimaryHandle()
end

function DT:SyncBlizzardCastBar()
    local playerCastBar = PlayerCastingBarFrame
    if playerCastBar == nil then
        return
    end

    self:OnCastBarShown("blizzard", playerCastBar, playerCastBar.Text, 10)
end

---------------------------------------------------------------------------------
-- Warning Frame
---------------------------------------------------------------------------------
function DT:CreateWarningFrame()
    if self.warningFrame then return end

    local f = CreateFrame("Frame", "KE_DisintegrateTicksFrame", UIParent)
    f:SetSize(200, 30)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(false)
    f:SetMouseClickEnabled(false)

    local text = f:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER")
    text:Hide()

    f:Hide()

    self.warningFrame = f
    self.warningText = text

    self:ApplyWarningSettings()
end

function DT:ApplyWarningSettings()
    if not self.warningText then return end
    local db = self.db
    local cw = db.ClipWarning or {}

    KE:ApplyFontToText(self.warningText,
        cw.FontFace,
        cw.FontSize or 16,
        cw.FontOutline or "OUTLINE"
    )

    self.warningText:SetText(cw.Text or "DON'T CLIP")
    local cr, cg, cb, ca = KE:ResolveColor(cw.Color, { 1, 0, 0, 1 })
    self.warningText:SetTextColor(cr, cg, cb, ca)

    -- ShowWarning() re-shows this when it is actually needed in combat.
    if not self.isPreview then
        self:HideWarning()
    end
end

function DT:UpdateWarningPosition()
    if not self.warningFrame then return end
    KE:ApplyFramePosition(self.warningFrame, self.db.Position, self.db)
end

function DT:ShowWarning()
    if not self.warningText then return end
    local cw = self.db.ClipWarning or {}
    if not cw.Enabled then return end
    if self.warningFrame then
        self.warningFrame:Show()
    end
    self.warningText:Show()
end

function DT:HideWarning()
    if not self.warningText then return end
    self.warningText:Hide()
    if self.warningFrame then
        self.warningFrame:Hide()
    end
end

function DT:OnEvent(event, unit, ...)
    -- Filter unit-specific events to player only
    if event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_STOP"
        or event == "UNIT_SPELLCAST_CHANNEL_UPDATE"
        or event == "UNIT_SPELLCAST_EMPOWER_STOP" or event == "UNIT_SPELLCAST_SUCCEEDED" then
        if unit ~= "player" then return end
    end

    if event == "LOADING_SCREEN_DISABLED" then
        self:QueryTalentsAndHide()
        self:HideWarning()

    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        if self:IsValidSpec() then
            self:RegisterSpecEvents()
            self:QueryTalentsAndHide()
        else
            self:UnregisterSpecEvents()
            self:HideTicks()
            self:HideWarning()
        end
        -- The tick-marker coordination watches this event on its own frame, so
        -- it keeps working while the module is disabled.

    elseif event == "PLAYER_DEAD" then
        self.massDisintegrateStacks = 0

    elseif event == "TRAIT_CONFIG_UPDATED" then
        self:QueryTalentsAndHide()

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, spellId = ...  -- castGUID, spellID (unit already captured)
        if self.hasTipTheScalesActive and IsEmpower(spellId) and KnowsMassDisintegrate() then
            self.hasTipTheScalesActive = false
            self.massDisintegrateStacks = self.massDisintegrateStacks + 1
            self.lastGainedStack = GetTime()
        end

        if spellId == 358267 then
            self:RefreshPrimaryHandle()
        end

    elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        local _, spellId, complete = ...  -- castGUID, spellID, complete
        if not complete or not IsEmpower(spellId) or not KnowsMassDisintegrate() then
            return
        end
        self.massDisintegrateStacks = self.massDisintegrateStacks + 1
        self.lastGainedStack = GetTime()

    elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        local _, spellId = ...
        if spellId ~= DISINTEGRATE then return end

        local endTimeMS = select(5, UnitChannelInfo("player"))
        if endTimeMS ~= nil then
            self.prevEndTime = endTimeMS / 1000
        end

    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        local _, spellId = ...
        if spellId ~= DISINTEGRATE then return end

        local _, _, _, startTimeMS, endTimeMS = UnitChannelInfo("player")
        local startTime = startTimeMS / 1000

        -- Hover mid-Disintegrate triggers another CHANNEL_START — deduplicate
        if startTime - self.lastStart < 0.5 then
            return
        end

        self.lastStart = startTime

        self:RefreshPrimaryHandle()

        local cw = self.db.ClipWarning or {}

        if self.massDisintegrateStacks > 0 then
            local expired = GetTime() - self.lastGainedStack > STACK_EXPIRY
            if expired then
                self.massDisintegrateStacks = 0
            else
                local textFrame = self.primaryHandle and self.primaryHandle.textFrame
                if textFrame ~= nil then
                    textFrame:SetText(C_Spell.GetSpellName(MASS_DISINTEGRATE))
                end

                if cw.Enabled then
                    self:ShowWarning()
                end

                self.massDisintegrateStacks = self.massDisintegrateStacks - 1
            end

            if not cw.Enabled then
                self:HideWarning()
            end
        else
            self:HideWarning()
        end

        local nextEndTime = endTimeMS / 1000
        -- Pass actualDuration so GetHaste primes self.lastKnownHaste. UpdateTicks
        -- below reads it via the no-arg form.
        local hastedTickInterval = self:GetTickInterval() / self:GetHaste(nextEndTime - startTime)

        self.firstTick = 0

        if self.channeling and self.prevEndTime and self.prevHastedTickInterval then
            local remaining = self.prevEndTime - startTime
            -- modulo gives time to the next tick that would've fired, not just the last
            self.firstTick = math.max(0, math.fmod(remaining, self.prevHastedTickInterval))
        end

        self.prevEndTime = nextEndTime
        self.prevHastedTickInterval = hastedTickInterval
        self.chaining = self.channeling
        self.channeling = true

        self:UpdateTicksAll(nextEndTime - startTime)

    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
        -- unit param captures spellId for non-unit events
        if not self.hasTipTheScalesActive and IsEmpower(unit) then
            self.hasTipTheScalesActive = true
        end

    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        if self.hasTipTheScalesActive and IsEmpower(unit) then
            self.hasTipTheScalesActive = false
        end

    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        local _, spellId = ...
        if spellId ~= DISINTEGRATE then return end

        self:HideWarning()
        self:HideTicks()
        self.channeling = false
        self.chaining = false
        self.activeChannelDuration = nil
    end
end

function DT:RegisterSpecEvents()
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START", "OnEvent")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "OnEvent")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP", "OnEvent")
    self:RegisterEvent("UNIT_SPELLCAST_EMPOWER_STOP", "OnEvent")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnEvent")
    self:RegisterEvent("TRAIT_CONFIG_UPDATED", "OnEvent")
    self:RegisterEvent("PLAYER_DEAD", "OnEvent")
    self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "OnEvent")
    self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", "OnEvent")
end

function DT:UnregisterSpecEvents()
    self:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    self:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
    self:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    self:UnregisterEvent("UNIT_SPELLCAST_EMPOWER_STOP")
    self:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    self:UnregisterEvent("TRAIT_CONFIG_UPDATED")
    self:UnregisterEvent("PLAYER_DEAD")
    self:UnregisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
    self:UnregisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
function DT:ApplySettings()
    self:ApplyTickColor()
    self:ApplyWarningSettings()
    self:UpdateWarningPosition()
    self:SyncEUITickMarkers()
end

function DT:ApplyPosition()
    if not self.db.Enabled then return end
    self:UpdateWarningPosition()
end

---------------------------------------------------------------------------------
-- EllesmereUI cast bar tick markers
---------------------------------------------------------------------------------
-- EllesmereUI draws its own channel tick marks on the same cast bar this module
-- draws on, so both sets appear at once. Turning its master toggle off while
-- this module is drawing leaves one set, and it goes back on when we stop.
--
-- The settings live in that addon's central account-level store. This handle is
-- the supported reach into it, and its profile field is re-pointed in place on
-- a profile switch, so it is read fresh every time and never cached.
local function EUICastBarSettings()
    local db = _G._ERB_AceDB
    local profile = db and db.profile
    local cb = profile and profile.castBar
    if type(cb) ~= "table" then return nil end
    return cb, db._profileName or "Default"
end

local function RefreshEUICastBar()
    -- Cosmetic only: the toggle is re-read at every channel start, so skipping
    -- this leaves just a channel already in progress drawn the old way.
    if InCombatLockdown() then return end
    local apply = _G._ERB_Apply
    if type(apply) == "function" then apply() end
    local eui = _G.EllesmereUI
    if eui and type(eui.NotifyElementResized) == "function" then
        eui.NotifyElementResized("ERB_CastBar")
    end
end

-- A profile sync copies cast bar settings wholesale between sync-group members
-- and EllesmereUI's own exclusion list covers geometry only, so a suppression
-- could be copied into a profile we hold no record for and never restored.
-- Registering the key as excluded is a runtime call that writes no saved data.
local function ExcludeTickMarkersFromProfileSync()
    local eui = _G.EllesmereUI
    if not (eui and type(eui.RegisterSyncExclusions) == "function") then return false end
    eui.RegisterSyncExclusions("EllesmereUIResourceBars", { "castBar.showChannelTicks" })
    return true
end

-- At load, not at world entry. A suppression written last session is already in
-- the saved data, and EllesmereUI's spec pre-seed copies the outgoing profile
-- across during PLAYER_LOGIN, before any world-entry work could register this.
local exclusionWaiter
local function StopWaitingForEUI()
    if not exclusionWaiter then return end
    exclusionWaiter:UnregisterEvent("ADDON_LOADED")
    exclusionWaiter:SetScript("OnEvent", nil)
    exclusionWaiter = nil
end

if not ExcludeTickMarkersFromProfileSync() then
    exclusionWaiter = CreateFrame("Frame")
    exclusionWaiter:RegisterEvent("ADDON_LOADED")
    exclusionWaiter:SetScript("OnEvent", function(_, _, name)
        if name == "EllesmereUI" and ExcludeTickMarkersFromProfileSync() then
            StopWaitingForEUI()
        end
    end)
end

-- want:    this module wants the bar to itself
-- current: EllesmereUI's toggle as it reads now; nil when unreachable
-- owned:   our record says we turned it off in the active EllesmereUI profile
---@return string action "hide" | "restore" | "standdown" | "release" | "none"
function DT.ResolveEUITickMarkers(want, current, owned)
    if current == nil then return "none" end
    if want then
        if owned then return current and "standdown" or "none" end
        return current and "hide" or "none"
    end
    if not owned then return "none" end
    return current and "release" or "restore"
end

function DT:RetryEUITickMarkersSync()
    self.euiTickMarkersRetries = (self.euiTickMarkersRetries or 0) + 1
    if self.euiTickMarkersRetries > 40 then return end
    C_Timer.After(0.5, function() self:SyncEUITickMarkers() end)
end

function DT:SyncEUITickMarkers()
    if not self.euiTickMarkersReady then return end
    local cb, profileName = EUICastBarSettings()
    local g = KE.db and KE.db.global
    if not cb or not g then return end
    local owner = g.EUITickMarkersHiddenIn
    if type(owner) ~= "table" then
        owner = {}
        g.EUITickMarkersHiddenIn = owner
    end

    -- IsEnabled() is true on any character whose profile has the module on:
    -- OnEnable's own class check returns after the module is already marked
    -- enabled. Without this gate a character with no spec waits forever on one.
    local armed = self:IsEnabled() and self.db and self.db.Enabled ~= false
        and self.db.HideEUITickMarkers ~= false
        and select(3, UnitClass("player")) == Constants.UICharacterClasses.Evoker
    local want = false
    if armed then
        -- The spec reads nil for a moment after a slow login. Deciding on that
        -- would restore the markers on a Devastation login, and nothing would
        -- hide them again until the next spec change.
        if PlayerUtil.GetCurrentSpecID() == nil then
            self:RetryEUITickMarkersSync()
            return
        end
        want = self:IsValidSpec()
    end
    self.euiTickMarkersRetries = 0

    -- Reading an absent key as ON is this addon's own convention, the one
    -- KE:EUISheetActive follows; EllesmereUI's own read treats it as off. They
    -- cannot disagree in practice, because it seeds the key true into every
    -- profile when it merges its defaults.
    local action = DT.ResolveEUITickMarkers(want, cb.showChannelTicks ~= false,
        owner[profileName] == true)
    if action == "hide" then
        cb.showChannelTicks = false
        owner[profileName] = true
        RefreshEUICastBar()
        KE:Print("Disintegrate Ticks: hid EllesmereUI's cast bar tick markers while this module draws them.")
    elseif action == "restore" then
        cb.showChannelTicks = true
        owner[profileName] = nil
        RefreshEUICastBar()
        KE:Print("Disintegrate Ticks: restored EllesmereUI's cast bar tick markers.")
    elseif action == "release" then
        owner[profileName] = nil
    elseif action == "standdown" then
        owner[profileName] = nil
        self.db.HideEUITickMarkers = false
        KE:Print("Disintegrate Ticks: EllesmereUI's tick markers were turned back on, so Hide EllesmereUI Tick Markers is now off.")
    end
end

-- Its own frame, not the module's AceEvent: a disabled module still has to
-- restore, and OnDisable unregisters everything. It carries the spec event for
-- the same reason. A profile suppressed under one spec is only healed when
-- that spec comes back, and with the listener on the module a disabled module
-- would never see it return.
do
    local entry = CreateFrame("Frame")
    entry:RegisterEvent("PLAYER_ENTERING_WORLD")
    entry:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    entry:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_SPECIALIZATION_CHANGED" then
            if unit ~= "player" then return end
            DT:SyncEUITickMarkers()
            -- EllesmereUI switches profiles synchronously inside its own
            -- handler for this event and neither addon controls handler order,
            -- so re-read next frame once every handler has run.
            C_Timer.After(0, function() DT:SyncEUITickMarkers() end)
            return
        end

        DT.euiTickMarkersReady = true
        -- Every ordinary addon is up by now, so a registration that still has
        -- not taken never will.
        StopWaitingForEUI()
        DT:SyncEUITickMarkers()
        -- EllesmereUI defers a first-login profile switch two frames, and its
        -- own rebuild sits at half a second, so settle well past both.
        C_Timer.After(1, function() DT:SyncEUITickMarkers() end)
    end)
end

---------------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------------
function DT:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "DisintegrateTicks",
            module = self,
            displayName = "Disintegrate Warning",
            frame = self.warningFrame,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos) self.db.Position = pos; self:UpdateWarningPosition() end,
            getParentFrame = function() return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) end,
            guiPath = "ClassTools",
            guiTab = "DisintegrateTicks",
        })
        self.editModeRegistered = true
    end
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------
function DT:ShowPreview()
    self:CreateWarningFrame()
    self:RegWithEditMode()
    self.isPreview = true
    self:ApplySettings()
    self.warningFrame:Show()

    -- Show warning text in preview
    self.warningText:Show()

    local previewDuration = self.maxTicks * (self:GetTickInterval() / self:GetHaste())
    for _, handle in ipairs(CastBarRegistry:GetVisibleBars()) do
        CastBarRegistry:SyncDimensions(handle.id, handle.anchor)
        self:UpdateHandleTicks(handle, previewDuration)
    end
end

function DT:HidePreview()
    self.isPreview = false
    self:HideWarning()
    self:HideTicks()
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function DT:OnEnable()
    if not self.db.Enabled then return end

    -- Only Evokers
    if select(3, UnitClass("player")) ~= Constants.UICharacterClasses.Evoker then
        return
    end

    self:UpdateDB()
    self:CreateWarningFrame()
    self:ApplySettings()
    self:HideWarning()

    -- Event routing
    self:RegisterEvent("LOADING_SCREEN_DISABLED", "OnEvent")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnEvent")

    -- Register spec events if valid spec
    if self:IsValidSpec() then
        self:RegisterSpecEvents()
        self:QueryTalentsAndHide()
    end

    RegisterOverlayCallbacks()
    CastBarRegistry:ResolveAllProviders()
    self:SyncBlizzardCastBar()
    self:RegWithEditMode()
end

function DT:OnDisable()
    self:SyncEUITickMarkers()
    self:UnregisterSpecEvents()
    self:UnregisterEvent("LOADING_SCREEN_DISABLED")
    self:UnregisterEvent("PLAYER_SPECIALIZATION_CHANGED")

    if overlayCallbacksRegistered then
        EventRegistry:UnregisterCallback("OverlayPlayerCastBar.OnShow", self)
        EventRegistry:UnregisterCallback("OverlayPlayerCastBar.OnHide", self)
        overlayCallbacksRegistered = false
    end

    CastBarRegistry:CancelRetries()
    self:HideTicks()
    self:HideWarning()
    if self.warningFrame then
        self.warningFrame:Hide()
    end
    self.isPreview = false
    self.activeChannelDuration = nil
    self.channeling = false
    self.chaining = false
    self.firstTick = 0
    self.prevEndTime = nil
    self.prevHastedTickInterval = nil
    self.primaryHandle = nil
    self.massDisintegrateStacks = 0
    self.lastGainedStack = 0
    self.hasTipTheScalesActive = false
end

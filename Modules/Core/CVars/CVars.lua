-- ╔══════════════════════════════════════════════════════════╗
-- ║  CVars.lua                                               ║
-- ║  Module: CVars                                           ║
-- ║  Purpose: The CVars page's settings: live reads, the     ║
-- ║           login apply and change tracking.               ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

-- The settings live in the Automation profile block, so every saved key and
-- default is the one the page has always used, and db.Enabled is Automation's
-- master switch: this module is on exactly when Automation is.
---@class CVars: AceModule, AceEvent-3.0
local CV = KitnEssentials:NewModule("CVars", "AceEvent-3.0")

local pcall = pcall
local ipairs = ipairs
local tonumber = tonumber
local tostring = tostring
local C_CVar = C_CVar
local C_Timer = C_Timer

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
CV.CVAR_DEFS = {
    -- Floating Combat Text
    {
        key = "enableFloatingCombatText",
        label = "Floating Combat Text: |cFF8080FFPlayer|r",
        desc = "Floating |cFFFF4040Damage|r / |cFF40FF40Healing|r received.",
        type = "boolean",
    },
    {
        key = "floatingCombatTextCombatDamage_v2",
        label = "Floating Combat Text: |cFFFF4040Damage|r",
        desc = "Displays Floating Combat Damage.",
        type = "boolean",
    },
    {
        key = "floatingCombatTextCombatHealing_v2",
        label = "Floating Combat Text: |cFF40FF40Healing|r",
        desc = "Displays Floating Combat Healing.",
        type = "boolean",
    },
    {
        key = "floatingCombatTextReactives_v2",
        label = "Floating Combat Text: |cFFFFCC00Reactives|r",
        desc = "Displays Reactive Ability Notifications.",
        type = "boolean",
    },
    -- Character Visibility
    {
        -- findYourselfModeOutline does nothing on its own. Blizzard's own
        -- control writes four CVars together: the three mode flags plus
        -- findYourselfAnywhere, which is what actually switches the feature on.
        key = "findYourselfModeOutline",
        label = "Find Yourself Anywhere: |cFF8080FFOutline|r",
        desc = "Adds Outline to Your Player Character.",
        type = "boolean",
        companion = "findYourselfAnywhere",
        -- The master stays on while ANY highlight mode is on, so turning the
        -- outline off must not switch off someone's circle or icon.
        companionKeepAlive = { "findYourselfModeCircle", "findYourselfModeIcon" },
    },
    {
        key = "occludedSilhouettePlayer",
        label = "Obstruction Silhouette",
        desc = "Display a Silhouette of your Character when Obstructed.",
        type = "boolean",
    },
    -- Tooltips
    {
        key = "alwaysCompareItems",
        label = "Always Compare Items",
        desc = "Always show item comparison tooltips. Disable to require Shift.",
        type = "boolean",
    },
    -- Nameplates
    {
        key = "nameplateShowOnlyNameForFriendlyPlayerUnits",
        label = "Show Only Friendly Names",
        type = "boolean",
    },
    {
        key = "nameplateUseClassColorForFriendlyPlayerUnitNames",
        label = "Class Colored Friendly Names",
        type = "boolean",
    },
    -- Dev: force addon restrictions on for testing. Blizzard surfaces none of
    -- them, and turning one on looks exactly like every addon breaking, so they
    -- live behind their own tab with a warning.
    {
        key = "addonPvPMatchRestrictionsForced",
        label = "Force PvP Match Addon Restrictions",
        type = "boolean",
        dev = true,
    },
    {
        key = "addonMapRestrictionsForced",
        label = "Force Map Addon Restrictions",
        type = "boolean",
        dev = true,
    },
    {
        key = "addonEncounterRestrictionsForced",
        label = "Force Encounter Addon Restrictions",
        type = "boolean",
        dev = true,
    },
    {
        key = "addonCombatRestrictionsForced",
        label = "Force Combat Addon Restrictions",
        type = "boolean",
        dev = true,
    },
    {
        key = "addonChatRestrictionsForced",
        label = "Force Chat Addon Restrictions",
        type = "boolean",
        dev = true,
    },
    {
        key = "addonChallengeModeRestrictionsForced",
        label = "Force M+ Addon Restrictions",
        type = "boolean",
        dev = true,
    },
}

CV.CVAR_SLIDER_DEFS = {
    {
        key = "SpellQueueWindow",
        label = "Spell Queue Window",
        type = "number",
        min = 0, max = 400, step = 1,
    },
    {
        key = "RAIDweatherDensity",
        label = "Raid: Weather Density",
        type = "number",
        min = 0, max = 3, step = 1,
    },
    {
        key = "WorldTextScale_v2",
        label = "Floating Combat Text: Size",
        type = "number",
        min = 0.5, max = 2, step = 0.05,
    },
}

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------
CV._suppressCVarUpdate = false

---------------------------------------------------------------------------------
-- CVar Helpers
---------------------------------------------------------------------------------
local function ToCVarValue(value, cvarType)
    if cvarType == "boolean" then
        return value and 1 or 0
    end
    return value
end

local function FromCVarValue(value, cvarType)
    if cvarType == "boolean" then
        return value == "1"
    end
    return value
end

-- Reads the client rather than the stored copy, so a value changed in Blizzard's
-- own options or by a console command shows correctly. pcall because this list is
-- deliberately made of CVars Blizzard does not surface in its own options, which
-- are exactly the ones a patch is most likely to rename out from under a page the
-- user merely opened. A CVar this client does not have reads nil, and nil is what
-- tells the page to leave its row out entirely.
function CV:GetLiveCVar(def)
    local ok, raw = pcall(C_CVar.GetCVar, def.key)
    if not ok or raw == nil then return nil end
    if def.type == "boolean" then return raw == "1" end
    return tonumber(raw)
end

-- A CVar this client does not have reads nil. Rendering it anyway produces a
-- dead control sitting at its own minimum, so the row is dropped instead -- and
-- a card that loses every row is not drawn at all. A plain filter, not `goto`:
-- this runtime is Lua 5.1.
function CV:FilterLiveDefs(defs, match)
    local kept = {}
    for _, def in ipairs(defs) do
        if (not match or match(def)) and self:GetLiveCVar(def) ~= nil then
            kept[#kept + 1] = def
        end
    end
    return kept
end

local function IsDevDef(def)
    return def.dev == true
end

-- The Dev tab is built from these alone, so a client with none of them would
-- otherwise show a tab holding its warning label and nothing else -- the same
-- refusal every card on the page already makes one level down.
function CV:HasLiveDevCVars()
    return #self:FilterLiveDefs(self.CVAR_DEFS, IsDevDef) > 0
end

-- Some CVars are only half a switch. `companion` is the master flag that has to
-- be on for this one to do anything; `companionKeepAlive` lists the sibling
-- modes that also depend on that master, so turning this one off does not take
-- theirs down with it.
function CV:ApplyCompanion(def, value)
    if not def.companion then return end
    -- The same refusal the primary gets, because a companion can go missing on
    -- its own: a patch is free to retire the master flag while leaving the mode
    -- flags in place, and every caller of this reaches SetCVar.
    local ok, raw = pcall(C_CVar.GetCVar, def.companion)
    if not ok or raw == nil then return end
    if value then
        C_CVar.SetCVar(def.companion, "1")
        return
    end
    if def.companionKeepAlive then
        for i = 1, #def.companionKeepAlive do
            if C_CVar.GetCVar(def.companionKeepAlive[i]) == "1" then return end
        end
    end
    C_CVar.SetCVar(def.companion, "0")
end

function CV:ApplyCVars()
    if not self.db.CVarsEnabled then return end
    -- Boolean CVars
    for _, def in ipairs(self.CVAR_DEFS) do
        local key = def.key
        local currentValue = self:GetLiveCVar(def)
        -- SetCVar on a name this client does not have is an error, and a stored
        -- value can outlive the CVar: a profile written on a client that had it,
        -- or a patch that renamed it. The page already drops the row; this drops
        -- the write, so both halves refuse on the same condition. The companion
        -- write is inside the guard because a master flag is worth nothing when
        -- the mode it serves is gone.
        if currentValue ~= nil then
            local dbValue = self.db[key]
            if dbValue == nil then
                self.db[key] = currentValue
            elseif dbValue ~= currentValue then
                C_CVar.SetCVar(key, ToCVarValue(dbValue, def.type))
            end
            -- Runs whether or not the primary changed, because the master can be
            -- wrong on its own. It turns the master back on for a mode enabled
            -- here; it never adopts one for a sibling mode, which the keep-alive
            -- only protects from being switched off.
            if def.companion and self.db[key] ~= nil then
                self:ApplyCompanion(def, self.db[key] == true)
            end
        end
    end
    -- Slider CVars
    for _, def in ipairs(self.CVAR_SLIDER_DEFS) do
        local key = def.key
        local currentValue = self:GetLiveCVar(def)
        if currentValue ~= nil then
            local dbValue = self.db[key]
            if dbValue == nil then
                self.db[key] = currentValue
            elseif tostring(dbValue) ~= tostring(currentValue) then
                C_CVar.SetCVar(key, tostring(dbValue))
            end
        end
    end
end

function CV:SyncFromCVars()
    -- nil, never a fabricated value. A CVar this client does not have has no
    -- value, and both defaults are real settings here: a raw read turns an
    -- absent boolean into false and an absent slider into 0, which is how a
    -- profile ends up holding a setting the client cannot back.
    for _, def in ipairs(self.CVAR_DEFS) do
        self.db[def.key] = self:GetLiveCVar(def)
    end
    for _, def in ipairs(self.CVAR_SLIDER_DEFS) do
        self.db[def.key] = self:GetLiveCVar(def)
    end
end

---------------------------------------------------------------------------------
-- Event Handlers
---------------------------------------------------------------------------------
function CV:CVAR_UPDATE(_, cvarName)
    local matched = false
    for _, def in ipairs(self.CVAR_DEFS) do
        if def.key == cvarName then
            local current = C_CVar.GetCVar(cvarName)
            self.db[cvarName] = FromCVarValue(current, def.type)
            matched = true
        end
    end
    for _, def in ipairs(self.CVAR_SLIDER_DEFS) do
        if def.key == cvarName then
            local current = C_CVar.GetCVar(cvarName)
            self.db[cvarName] = tonumber(current) or 0
            matched = true
        end
    end
    -- Gated deliberately. Unconditional, every
    -- CVAR_UPDATE delivery (any addon touching any event-named CVar, GUI
    -- open or closed) forced a full page rebuild, orphaning a page of cards
    -- each time. RefreshContent now refuses to run hidden as well, but keep
    -- this caller honest: only refresh for CVars this module displays, only
    -- when the GUI is shown, and collapse bursts (ApplyCVars writes every
    -- managed CVar back-to-back) into a single deferred rebuild.
    if not matched or self._suppressCVarUpdate then return end
    if not (KE.GUIFrame and KE.GUIFrame:IsShown()) then return end
    if self._cvarRefreshQueued then return end
    self._cvarRefreshQueued = true
    C_Timer.After(0.1, function()
        self._cvarRefreshQueued = false
        -- Deliberate: if the GUI closed during the 0.1s window, the refresh
        -- is dropped (not deferred) — the page can show a stale CVar value
        -- until the user re-navigates. Accepted over marking dirty: a CVar
        -- flip while closing the GUI is rare, and this caller never touches
        -- a hidden GUI.
        if KE.GUIFrame and KE.GUIFrame:IsShown() then
            KE.GUIFrame:RefreshContent()
        end
    end)
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
-- The login apply and change tracking wait for Automation itself, which a
-- baseline load withholds; the page's own writes do not.
local function AutomationAdmitted()
    return not KE.IsFeatureAvailable or KE:IsFeatureAvailable("Automation") == true
end

function CV:UpdateDB()
    self.db = KE.db.profile.Automation
end

function CV:OnInitialize()
    self:UpdateDB()
    self:SyncFromCVars()
    self:SetEnabledState(false)
end

function CV:ApplySettings()
    if not self.db.Enabled or not AutomationAdmitted() then return end
    self:ApplyCVars()
end

function CV:OnEnable()
    if not self.db.Enabled or not AutomationAdmitted() then return end
    self:RegisterEvent("CVAR_UPDATE")
    C_Timer.After(1.0, function()
        self:ApplySettings()
    end)
end

function CV:OnDisable()
    self:UnregisterAllEvents()
end

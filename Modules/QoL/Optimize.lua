-- ╔══════════════════════════════════════════════════════════╗
-- ║  Optimize.lua                                            ║
-- ║  Module: CVars                                           ║
-- ║  Purpose: One-click CVar optimization panel for          ║
-- ║           graphics, UI, and performance settings.        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

---@type KitnEssentials
local KitnEssentials = _G.KitnEssentials
if not KitnEssentials then
    error("Optimize: Addon object not initialized. Check file load order!")
    return
end

---@class Optimize: AceModule, AceEvent-3.0
local OPT = KitnEssentials:NewModule("Optimize", "AceEvent-3.0")

local _SetCVar = SetCVar or C_CVar.SetCVar
local _GetCVar = GetCVar or C_CVar.GetCVar
local pcall = pcall
local tostring = tostring
local tonumber = tonumber
local string_format = string.format

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------

-- Separate SavedVariables for optimization backups.
-- This persists in KitnEssentialsOptimizeDB so installer won't overwrite it.
local function GetBackupDB()
    if not KitnEssentialsOptimizeDB then
        KitnEssentialsOptimizeDB = {}
    end
    if not KitnEssentialsOptimizeDB.SavedSettings then
        KitnEssentialsOptimizeDB.SavedSettings = {}
    end
    return KitnEssentialsOptimizeDB
end

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
OPT.Categories = {
    {
        id = "render",
        name = "Render & Display",
        cvars = {
            { cvar = "renderScale",         optimal = "1",    name = "Render Scale",       desc = "100% native resolution" },
            { cvar = "VSync",               optimal = "0",    name = "VSync",              desc = "Disabled" },
            { cvar = "MSAAQuality",          optimal = "0",    name = "Multisampling",      desc = "None" },
            { cvar = "LowLatencyMode",       optimal = "3",    name = "Low Latency Mode",   desc = "Reflex + Boost" },
            { cvar = "ffxAntiAliasingMode",  optimal = "4",    name = "Anti-Aliasing",      desc = "CMAA2" },
        },
    },
    {
        id = "graphics",
        name = "Base Graphics Quality",
        cvars = {
            { cvar = "graphicsShadowQuality",      optimal = "3", name = "Shadow Quality",      desc = "High" },
            { cvar = "graphicsLiquidDetail",        optimal = "2", name = "Liquid Detail",        desc = "Good" },
            { cvar = "graphicsParticleDensity",     optimal = "4", name = "Particle Density",     desc = "High" },
            { cvar = "graphicsSSAO",                optimal = "3", name = "SSAO",                 desc = "High" },
            { cvar = "graphicsDepthEffects",        optimal = "3", name = "Depth Effects",        desc = "High" },
            { cvar = "graphicsComputeEffects",      optimal = "3", name = "Compute Effects",      desc = "High" },
            { cvar = "graphicsOutlineMode",         optimal = "2", name = "Outline Mode",         desc = "High" },
            { cvar = "graphicsTextureResolution",   optimal = "2", name = "Texture Resolution",   desc = "High" },
            { cvar = "graphicsSpellDensity",        optimal = "0", name = "Spell Density",        desc = "Essential" },
            { cvar = "graphicsProjectedTextures",   optimal = "1", name = "Projected Textures",   desc = "Enabled" },
            { cvar = "graphicsViewDistance",        optimal = "6", name = "View Distance",        desc = "Level 7" },
            { cvar = "graphicsEnvironmentDetail",   optimal = "6", name = "Environment Detail",   desc = "Level 7" },
            { cvar = "graphicsGroundClutter",       optimal = "6", name = "Ground Clutter",       desc = "Level 7" },
        },
    },
    {
        id = "raid",
        name = "Raid & BG Graphics",
        cvars = {
            { cvar = "RAIDsettingsEnabled",             optimal = "1", name = "Separate Raid Settings",  desc = "Enabled" },
            { cvar = "raidGraphicsShadowQuality",       optimal = "0", name = "Shadow Quality",          desc = "Low" },
            { cvar = "raidGraphicsLiquidDetail",        optimal = "0", name = "Liquid Detail",            desc = "Low" },
            { cvar = "raidGraphicsParticleDensity",     optimal = "3", name = "Particle Density",         desc = "Good" },
            { cvar = "raidGraphicsSSAO",                optimal = "0", name = "SSAO",                     desc = "Disabled" },
            { cvar = "raidGraphicsDepthEffects",        optimal = "0", name = "Depth Effects",            desc = "Disabled" },
            { cvar = "raidGraphicsComputeEffects",      optimal = "0", name = "Compute Effects",          desc = "Disabled" },
            { cvar = "raidGraphicsOutlineMode",         optimal = "2", name = "Outline Mode",             desc = "High" },
            { cvar = "raidGraphicsTextureResolution",   optimal = "2", name = "Texture Resolution",       desc = "High" },
            { cvar = "raidGraphicsSpellDensity",        optimal = "0", name = "Spell Density",            desc = "Essential" },
            { cvar = "raidGraphicsProjectedTextures",   optimal = "1", name = "Projected Textures",       desc = "Enabled" },
            { cvar = "raidGraphicsViewDistance",        optimal = "0", name = "View Distance",            desc = "Level 1" },
            { cvar = "raidGraphicsEnvironmentDetail",   optimal = "0", name = "Environment Detail",       desc = "Level 1" },
            { cvar = "raidGraphicsGroundClutter",       optimal = "0", name = "Ground Clutter",           desc = "Level 1" },
        },
    },
    {
        id = "advanced",
        name = "Advanced",
        cvars = {
            { cvar = "GxMaxFrameLatency",    optimal = "2",      name = "Triple Buffering",    desc = "Disabled" },
            { cvar = "TextureFilteringMode",  optimal = "5",      name = "Texture Filtering",   desc = "16x Anisotropic" },
            { cvar = "shadowRt",             optimal = "0",      name = "Ray Traced Shadows",  desc = "Disabled" },
            { cvar = "ResampleQuality",       optimal = "3",      name = "Resample Quality",    desc = "FidelityFX SR 1.0" },
            { cvar = "GxApi",                optimal = "D3D12",  name = "Graphics API",        desc = "DirectX 12" },
            { cvar = "physicsLevel",          optimal = "1",      name = "Physics Integration", desc = "Player Only" },
        },
    },
    {
        id = "fps",
        name = "FPS Limits",
        cvars = {
            { cvar = "useMaxFPS",     optimal = "1",   name = "FPS Cap Toggle",       desc = "Enabled" },
            { cvar = "maxFPS",        optimal = "200", name = "Max FPS",              desc = "200 FPS" },
            { cvar = "useTargetFPS",  optimal = "0",   name = "Target FPS",           desc = "Disabled" },
            { cvar = "useMaxFPSBk",   optimal = "1",   name = "Background FPS Toggle", desc = "Enabled" },
            { cvar = "maxFPSBk",      optimal = "60",  name = "Background FPS",        desc = "60 FPS" },
            { cvar = "maxFPSLoading", optimal = "30",  name = "Loading Screen FPS",    desc = "30 FPS" },
        },
    },
    {
        id = "post",
        name = "Post Processing",
        cvars = {
            { cvar = "ResampleSharpness", optimal = "0.2", name = "Resample Sharpness", desc = "Slight sharpening" },
            { cvar = "ResampleAlwaysSharpen", optimal = "1", name = "Always Sharpen", desc = "Enabled" },
        },
    },
    {
        id = "cvar",
        name = "CVars",
        cvars = {
            { cvar = "AutoPushSpellToActionBar", optimal = "0", name = "Auto Push Spells to Action Bar", desc = "Disabled" },
            { cvar = "cameraFov", optimal = "90", name = "Camera FOV", desc = "90 degrees" },
            { cvar = "cameraDistanceMaxZoomFactor", optimal = "2.6", name = "Max Camera Zoom", desc = "2.6x" },
            { cvar = "nameplateShowFriendlyClassColor", optimal = "1", name = "Class Color Names", desc = "Enabled" },
            { cvar = "UnitNameFriendlyPlayerName", optimal = "1", name = "Friendly Player Names", desc = "Show only player names" },
            { cvar = "nameplateStackingTypes", optimal = "AA", name = "Stacking Nameplates", desc = "Enemy Units" },
            { cvar = "nameplateOverlapH", optimal = "0.8", name = "Nameplate Horizontal Overlap", desc = "0.8" },
            { cvar = "nameplateOverlapV", optimal = "1.4", name = "Nameplate Vertical Overlap", desc = "1.4" },
            { cvar = "WorldTextMinSize", optimal = "8", name = "Min Character Name Size", desc = "8" },
            { cvar = "SpellQueueWindow", optimal = "180", name = "Spell Queue Window", desc = "180ms" },
        },
    },
    {
        id = "network",
        name = "Network & Logging",
        cvars = {
            { cvar = "advancedCombatLogging", optimal = "1", name = "Advanced Combat Logging", desc = "Required for Warcraft Logs" },
            { cvar = "disableServerNagle", optimal = "1", name = "Disable Server Nagle", desc = "Reduces network latency" },
        },
    },
    {
        id = "cosmetic",
        name = "Cosmetic Effects",
        cvars = {
            { cvar = "ffxDeath", optimal = "0", name = "Death Effect", desc = "Disabled" },
            { cvar = "ffxGlow", optimal = "0", name = "Glow Effect", desc = "Disabled" },
            { cvar = "ffxNether", optimal = "0", name = "Nether Effect", desc = "Disabled" },
            { cvar = "ffxVenari", optimal = "0", name = "Venari Effect", desc = "Disabled" },
            { cvar = "ffxLingeringVenari", optimal = "0", name = "Lingering Venari Effect", desc = "Disabled" },
            { cvar = "overrideScreenFlash", optimal = "1", name = "Override Screen Flash", desc = "Enabled" },
            { cvar = "ShakeStrengthCamera", optimal = "0", name = "Camera Shake", desc = "Disabled" },
            { cvar = "ShakeStrengthUI", optimal = "0", name = "UI Shake", desc = "Disabled" },
        },
    },
}

-- Friendly display labels for CVar values
local VALUE_LABELS = {
    renderScale = function(v)
        return string_format("%d%%", (tonumber(v) or 1) * 100)
    end,
    VSync = function(v) return v == "1" and "Enabled" or "Disabled" end,
    MSAAQuality = function(v)
        local t = { [0] = "None", [1] = "2x", [2] = "4x", [3] = "8x" }
        return t[tonumber(v) or -1] or v
    end,
    LowLatencyMode = function(v)
        local t = { [0] = "None", [1] = "Built-In", [2] = "Reflex", [3] = "Reflex+Boost", [4] = "XeLL" }
        return t[tonumber(v) or -1] or v
    end,
    ffxAntiAliasingMode = function(v)
        local t = { [0] = "None", [1] = "Image-Based", [2] = "Multisample", [4] = "CMAA2" }
        return t[tonumber(v) or -1] or v
    end,
    graphicsShadowQuality = function(v)
        local t = { [0] = "Low", [1] = "Fair", [2] = "Good", [3] = "High", [4] = "Ultra" }
        return t[tonumber(v) or -1] or v
    end,
    graphicsLiquidDetail = function(v)
        local t = { [0] = "Low", [1] = "Fair", [2] = "Good", [3] = "High" }
        return t[tonumber(v) or -1] or v
    end,
    graphicsParticleDensity = function(v)
        local t = { [0] = "Disabled", [1] = "Low", [2] = "Fair", [3] = "Good", [4] = "High", [5] = "Ultra" }
        return t[tonumber(v) or -1] or v
    end,
    graphicsSSAO = function(v)
        local t = { [0] = "Disabled", [1] = "Low", [2] = "Good", [3] = "High", [4] = "Ultra" }
        return t[tonumber(v) or -1] or v
    end,
    graphicsDepthEffects = function(v)
        local t = { [0] = "Disabled", [1] = "Low", [2] = "Good", [3] = "High" }
        return t[tonumber(v) or -1] or v
    end,
    graphicsComputeEffects = function(v)
        local t = { [0] = "Disabled", [1] = "Low", [2] = "Good", [3] = "High" }
        return t[tonumber(v) or -1] or v
    end,
    graphicsOutlineMode = function(v)
        local t = { [1] = "Low", [2] = "High", [3] = "Ultra High" }
        return t[tonumber(v) or -1] or v
    end,
    graphicsTextureResolution = function(v)
        local t = { [1] = "Low", [2] = "High", [3] = "Ultra" }
        return t[tonumber(v) or -1] or v
    end,
    graphicsSpellDensity = function(v)
        local t = { [0] = "Essential", [1] = "Low", [2] = "Fair", [3] = "Good", [4] = "High", [5] = "Ultra" }
        return t[tonumber(v) or -1] or v
    end,
    graphicsProjectedTextures = function(v) return v == "1" and "Enabled" or "Disabled" end,
    graphicsViewDistance = function(v) return "Level " .. ((tonumber(v) or 0) + 1) end,
    graphicsEnvironmentDetail = function(v) return "Level " .. ((tonumber(v) or 0) + 1) end,
    graphicsGroundClutter = function(v) return "Level " .. ((tonumber(v) or 0) + 1) end,
    GxMaxFrameLatency = function(v) return tonumber(v) == 3 and "Enabled" or "Disabled" end,
    TextureFilteringMode = function(v)
        local t = { [0] = "Bilinear", [1] = "Trilinear", [2] = "2x Aniso", [3] = "4x Aniso", [4] = "8x Aniso", [5] = "16x Aniso" }
        return t[tonumber(v) or -1] or v
    end,
    shadowRt = function(v)
        local t = { [0] = "Disabled", [1] = "Low", [2] = "Good", [3] = "High", [4] = "Ultra" }
        return t[tonumber(v) or -1] or v
    end,
    ResampleQuality = function(v)
        local t = { [0] = "Point", [1] = "Bilinear", [2] = "Bicubic", [3] = "FidelityFX SR 1.0" }
        return t[tonumber(v) or -1] or v
    end,
    GxApi = function(v)
        local u = (v or ""):upper()
        if u == "D3D12" then return "DX12"
        elseif u == "D3D11" then return "DX11"
        elseif u == "OPENGL" then return "OpenGL"
        else return v end
    end,
    physicsLevel = function(v)
        local t = { [0] = "None", [1] = "Player Only", [2] = "Full" }
        return t[tonumber(v) or -1] or v
    end,
    useTargetFPS = function(v) return v == "1" and "Enabled" or "Disabled" end,
    useMaxFPSBk = function(v) return v == "1" and "Enabled" or "Disabled" end,
    maxFPSBk = function(v) return v .. " FPS" end,
    ResampleSharpness = function(v) return tostring(v) end,
    SpellQueueWindow = function(v) return v .. "ms" end,
    UnitNameFriendlyPlayerName = function(v) return v == "1" and "Enabled" or "Disabled" end,
    nameplateShowFriendlyClassColor = function(v) return v == "1" and "Enabled" or "Disabled" end,
    ResampleAlwaysSharpen = function(v) return v == "1" and "Enabled" or "Disabled" end,
    advancedCombatLogging = function(v) return v == "1" and "Enabled" or "Disabled" end,
    disableServerNagle = function(v) return v == "1" and "Enabled" or "Disabled" end,
    ffxDeath = function(v) return v == "1" and "Enabled" or "Disabled" end,
    ffxGlow = function(v) return v == "1" and "Enabled" or "Disabled" end,
    ffxNether = function(v) return v == "1" and "Enabled" or "Disabled" end,
    ffxVenari = function(v) return v == "1" and "Enabled" or "Disabled" end,
    ffxLingeringVenari = function(v) return v == "1" and "Enabled" or "Disabled" end,
    -- Raid & BG graphics
    RAIDsettingsEnabled = function(v) return v == "1" and "Enabled" or "Disabled" end,
    raidGraphicsShadowQuality = function(v)
        local t = { [0] = "Low", [1] = "Fair", [2] = "Good", [3] = "High", [4] = "Ultra" }
        return t[tonumber(v) or -1] or v
    end,
    raidGraphicsLiquidDetail = function(v)
        local t = { [0] = "Low", [1] = "Fair", [2] = "Good", [3] = "High" }
        return t[tonumber(v) or -1] or v
    end,
    raidGraphicsParticleDensity = function(v)
        local t = { [0] = "Disabled", [1] = "Low", [2] = "Fair", [3] = "Good", [4] = "High", [5] = "Ultra" }
        return t[tonumber(v) or -1] or v
    end,
    raidGraphicsSSAO = function(v) return tonumber(v) == 0 and "Disabled" or "Level " .. v end,
    raidGraphicsDepthEffects = function(v) return tonumber(v) == 0 and "Disabled" or "Level " .. v end,
    raidGraphicsComputeEffects = function(v) return tonumber(v) == 0 and "Disabled" or "Level " .. v end,
    raidGraphicsOutlineMode = function(v)
        local t = { [1] = "Low", [2] = "High", [3] = "Ultra High" }
        return t[tonumber(v) or -1] or v
    end,
    raidGraphicsTextureResolution = function(v)
        local t = { [1] = "Low", [2] = "High", [3] = "Ultra" }
        return t[tonumber(v) or -1] or v
    end,
    raidGraphicsSpellDensity = function(v)
        local t = { [0] = "Essential", [1] = "Low", [2] = "Fair", [3] = "Good", [4] = "High", [5] = "Ultra" }
        return t[tonumber(v) or -1] or v
    end,
    raidGraphicsProjectedTextures = function(v) return v == "1" and "Enabled" or "Disabled" end,
    raidGraphicsViewDistance = function(v) return "Level " .. ((tonumber(v) or 0) + 1) end,
    raidGraphicsEnvironmentDetail = function(v) return "Level " .. ((tonumber(v) or 0) + 1) end,
    raidGraphicsGroundClutter = function(v) return "Level " .. ((tonumber(v) or 0) + 1) end,
    -- FPS additions
    useMaxFPS = function(v) return v == "1" and "Enabled" or "Disabled" end,
    maxFPS = function(v) return v .. " FPS" end,
    maxFPSLoading = function(v) return v .. " FPS" end,
    -- CVars category
    AutoPushSpellToActionBar = function(v) return v == "1" and "Enabled" or "Disabled" end,
    cameraFov = function(v) return v .. "\194\176" end,
    cameraDistanceMaxZoomFactor = function(v) return v .. "x" end,
    nameplateStackingTypes = function(v)
        local t = { [""] = "None", ["AA"] = "Enemy Units", ["BB"] = "Friendly Units", ["CC"] = "Both" }
        return t[v] or v
    end,
    nameplateOverlapH = function(v) return tostring(v) end,
    nameplateOverlapV = function(v) return tostring(v) end,
    WorldTextMinSize = function(v) return tostring(v) end,
    -- Cosmetic additions
    overrideScreenFlash = function(v) return v == "1" and "Enabled" or "Disabled" end,
    ShakeStrengthCamera = function(v) return tonumber(v) == 0 and "Disabled" or tostring(v) end,
    ShakeStrengthUI = function(v) return tonumber(v) == 0 and "Disabled" or tostring(v) end,
}

---------------------------------------------------------------------------------
-- Core Logic
---------------------------------------------------------------------------------
function OPT:GetValueLabel(cvar, value)
    local fn = VALUE_LABELS[cvar]
    if fn then return fn(value) end
    return tostring(value)
end

function OPT:GetCurrentValue(cvar)
    local ok, val = pcall(_GetCVar, cvar)
    if ok and val and val ~= "" then return val end
    return nil
end

function OPT:IsOptimal(cvar, optimal)
    local current = self:GetCurrentValue(cvar)
    if not current then return false end
    local cn, on = tonumber(current), tonumber(optimal)
    if cn and on then
        return math.abs(cn - on) < 0.001
    end
    return tostring(current):upper() == tostring(optimal):upper()
end

function OPT:ApplyCVar(cvar, value)
    local backup = GetBackupDB()
    if not backup.SavedSettings[cvar] then
        local current = self:GetCurrentValue(cvar)
        if current then
            backup.SavedSettings[cvar] = current
        end
    end
    local ok = pcall(_SetCVar, cvar, tostring(value))
    return ok
end

function OPT:RevertCVar(cvar)
    local backup = GetBackupDB()
    local saved = backup.SavedSettings[cvar]
    if not saved then return false end
    local ok = pcall(_SetCVar, cvar, tostring(saved))
    if ok then
        backup.SavedSettings[cvar] = nil
    end
    return ok
end

function OPT:HasBackup(cvar)
    local backup = GetBackupDB()
    return backup.SavedSettings[cvar] ~= nil
end

---------------------------------------------------------------------------------
-- Presets
--
-- "balanced" = every category at its listed optimal, which is what the single
--              Optimize All button used to do.
-- "maxfps"   = the same, except the separate Raid & BG profile is switched off
--              and the base graphics cvars drop to the Raid & BG values, so the
--              low-end settings apply everywhere. The FPS cap also rises.
--
-- The chosen preset is stored in the optimization SavedVariables so the per-row
-- Recommended column stays preset-aware across a reload.
---------------------------------------------------------------------------------

-- Lazily built map of cvar -> overridden value for the Max FPS preset. Derived
-- from the raid category by stripping the raidGraphics prefix onto the matching
-- base graphics cvar, so it tracks the Raid & BG values instead of needing a
-- second hand-maintained list that could drift out of step with them.
local maxFPSOverrides = nil
function OPT:GetMaxFPSOverrides()
    if maxFPSOverrides then return maxFPSOverrides end
    local ov = {}
    for _, cat in ipairs(self.Categories) do
        if cat.id == "raid" then
            for _, entry in ipairs(cat.cvars) do
                local suffix = entry.cvar:match("^raidGraphics(.+)$")
                if suffix then
                    ov["graphics" .. suffix] = entry.optimal
                end
            end
        end
    end
    -- Switch the separate raid/BG profile off so the lowered base graphics
    -- apply in raids and battlegrounds too.
    ov["RAIDsettingsEnabled"] = "0"
    ov["maxFPS"] = "300"
    maxFPSOverrides = ov
    return maxFPSOverrides
end

--- Apply a preset across every category, optionally overriding individual
--- values. Window mode is preserved, so applying never flips fullscreen to
--- windowed, and the chosen preset is recorded.
---@param presetName string "balanced" | "maxfps"
---@param overrides table? cvar -> value overrides for this preset
function OPT:ApplyPreset(presetName, overrides)
    local displayBackup = {}
    for _, cv in ipairs({ "gxWindow", "gxMaximize" }) do
        local ok, val = pcall(_GetCVar, cv)
        if ok and val then displayBackup[cv] = val end
    end

    local applied, failed = 0, 0
    for _, cat in ipairs(self.Categories) do
        for _, entry in ipairs(cat.cvars) do
            local value = (overrides and overrides[entry.cvar]) or entry.optimal
            if entry.cvar == "graphicsViewDistance" and self:IsMythicOverrideActive() then
                -- The Mythic+ override is holding View Distance at its floor
                -- right now. Writing here would fight it, and backing the
                -- forced value up would make Revert All restore the floor.
                -- Record what the preset wanted instead, so leaving the key
                -- lands on that.
                GetBackupDB().MythicVD.saved = value
                applied = applied + 1
            elseif self:ApplyCVar(entry.cvar, value) then
                applied = applied + 1
            else
                failed = failed + 1
            end
        end
    end

    for cv, val in pairs(displayBackup) do
        pcall(_SetCVar, cv, val)
    end

    GetBackupDB().ActivePreset = presetName

    local KE_ACCENT = "|cffFF008C"
    local KE_GREEN  = "|cff00ff00"
    local KE_RESET  = "|r"
    local label = presetName == "maxfps" and "Max FPS" or "Balanced"
    KE:Print(KE_GREEN .. applied .. " settings optimized (" .. label .. ")." .. KE_RESET)
    if failed > 0 then
        KE:Print(KE_ACCENT .. "Warning:|r " .. failed .. " settings could not be applied.")
    end
end

--- Balanced preset.
function OPT:OptimizeAll()
    self:ApplyPreset("balanced", nil)
end

--- Max FPS preset: low-end graphics everywhere, no separate raid profile.
function OPT:MaxFPS()
    self:ApplyPreset("maxfps", self:GetMaxFPSOverrides())
end

--- The preset the page should show as selected, or nil.
-- The stored name alone goes stale the moment the user changes graphics by
-- hand after applying, and the page would then claim a preset the cvars no
-- longer match. So it is VALIDATED: it counts only while every preset cvar
-- still equals what that preset would write. Balanced gets one relaxed
-- fallback -- hand-tweaked values with the raid/BG split still on are balanced
-- in spirit. Max FPS gets no fallback, having no raid profile to fall back on.
-- View Distance is left out of the comparison while the Mythic+ override is
-- holding it down, which mirrors what ApplyPreset does with the same cvar.
function OPT:GetActivePreset()
    local stored = GetBackupDB().ActivePreset
    if not stored then return nil end

    local overrides = stored == "maxfps" and self:GetMaxFPSOverrides() or nil
    local skipViewDistance = self:IsMythicOverrideActive()

    local matches = true
    for _, cat in ipairs(self.Categories) do
        for _, entry in ipairs(cat.cvars) do
            if not (skipViewDistance and entry.cvar == "graphicsViewDistance") then
                local want = (overrides and overrides[entry.cvar]) or entry.optimal
                local ok, live = pcall(_GetCVar, entry.cvar)
                if not ok or tostring(live) ~= tostring(want) then
                    matches = false
                    break
                end
            end
        end
        if not matches then break end
    end

    if matches then return stored end

    if stored == "balanced" then
        local ok, raidMode = pcall(_GetCVar, "RAIDsettingsEnabled")
        if ok and tostring(raidMode) == "1" then
            return "balanced"
        end
    end

    return nil
end

--- True while the Mythic+ override is currently holding View Distance down.
-- The rest of that feature arrives with the override block below; this one
-- predicate lives up here because both preset functions above consult it.
function OPT:IsMythicOverrideActive()
    local state = GetBackupDB().MythicVD
    return state ~= nil and state.active == true
end

function OPT:RevertAll()
    local backup = GetBackupDB()
    if not backup.SavedSettings or not next(backup.SavedSettings) then
        KE:Print("No saved settings to revert.")
        return
    end

    local count = 0
    for cvar, val in pairs(backup.SavedSettings) do
        local ok = pcall(_SetCVar, cvar, tostring(val))
        if ok then count = count + 1 end
    end
    backup.SavedSettings = {}
    -- Everything is back at the user's own values, so no preset describes them.
    backup.ActivePreset = nil

    KE:Print("|cff00ff00" .. count .. " settings reverted.|r")
end

function OPT:HasAnySavedSettings()
    local backup = GetBackupDB()
    return backup.SavedSettings and next(backup.SavedSettings) ~= nil
end

---------------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------------
StaticPopupDialogs["KE_OPTIMIZE_RELOAD"] = {
    text = "Settings applied. Some changes require a reload to take effect.\n\nReload now?",
    button1 = "Reload",
    button2 = "Later",
    OnAccept = function() ReloadUI() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

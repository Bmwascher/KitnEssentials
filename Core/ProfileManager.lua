-- ╔══════════════════════════════════════════════════════════╗
-- ║  ProfileManager.lua                                      ║
-- ║  Purpose: Profile import/export with compression,        ║
-- ║           per-character and global profile management.   ║
-- ║  Note: Uses AceSerializer-3.0 and LibDeflate.            ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local ProfileManager = {}
KE.ProfileManager = ProfileManager

local AceSerializer = LibStub("AceSerializer-3.0")
local LibDeflate = LibStub("LibDeflate")

local EXPORT_PREFIX = "!KE1!"
local DEFAULT_PROFILE = "Default"

local pairs = pairs
local type = type
local time = time
local wipe = wipe
local next = next

-- Refresh policy: the AceDB callbacks in Core/Main.lua are the single
-- refresh trigger (they also catch third-party KE.db:SetProfile calls).
-- Multi-hop operations wrap their intermediate SetProfile/CopyProfile hops
-- in withRefreshSuppressed so per-hop callbacks skip the refresh (the
-- defaults-fill/migration in those callbacks still runs on every hop), then
-- run exactly one RefreshAllModules at the end.
local suppressRefresh = false

local function withRefreshSuppressed(fn)
    suppressRefresh = true
    local ok, err = pcall(fn)
    suppressRefresh = false
    if not ok then error(err, 0) end
end

function ProfileManager:IsRefreshSuppressed()
    return suppressRefresh
end

---------------------------------------------------------------------------------
-- Profile CRUD
---------------------------------------------------------------------------------

--- Get list of all available profiles
---@return table List of profile names
function ProfileManager:GetProfiles()
    local profiles = {}
    if KE.db then KE.db:GetProfiles(profiles) end
    return profiles
end

--- Get the current active profile name
---@return string Current profile name
function ProfileManager:GetCurrentProfile()
    if KE.db then return KE.db:GetCurrentProfile() end
    return DEFAULT_PROFILE
end

--- Switch to a different profile
---@param profileName string The profile name to switch to
---@return boolean success
---@return string|nil error
function ProfileManager:SetProfile(profileName)
    if not profileName or profileName == "" then return false, "Invalid profile name" end
    if not KE.db then return false, "Database not initialized" end

    -- SetProfile handles creation if profile doesn't exist
    KE.db:SetProfile(profileName)

    return true
end

--- Create a new profile with default values
---@param profileName string The name for the new profile
---@return boolean success
---@return string|nil error
function ProfileManager:CreateProfile(profileName)
    if not profileName or profileName == "" then return false, "Profile name cannot be empty" end
    if not KE.db then return false, "Database not initialized" end

    -- Check if profile with the same name already exists
    local profiles = self:GetProfiles()
    for _, name in pairs(profiles) do
        if name == profileName then
            return false, "Profile '" .. profileName .. "' already exists"
        end
    end

    -- Create by setting to it
    local currentProfile = self:GetCurrentProfile()
    withRefreshSuppressed(function()
        KE.db:SetProfile(profileName)
        KE.db:ResetProfile()
        KE.db:SetProfile(currentProfile)
    end)

    return true
end

--- Copy settings from one profile to another
---@param sourceProfile string Source profile name
---@param targetProfile string|nil Target profile name (current if nil)
---@return boolean success
---@return string|nil error
function ProfileManager:CopyProfile(sourceProfile, targetProfile)
    if not sourceProfile or sourceProfile == "" then return false, "Source profile name cannot be empty" end
    if not KE.db then return false, "Database not initialized" end

    targetProfile = targetProfile or self:GetCurrentProfile()

    -- Check if source profile exists
    local profiles = self:GetProfiles()
    local sourceExists = false
    for _, name in pairs(profiles) do
        if name == sourceProfile then
            sourceExists = true
            break
        end
    end

    if not sourceExists then return false, "Source profile '" .. sourceProfile .. "' does not exist" end

    -- AceDB's CopyProfile copies TO the current profile FROM the source
    local currentProfile = self:GetCurrentProfile()

    withRefreshSuppressed(function()
        -- If target is not current, switch to target first
        if targetProfile ~= currentProfile then KE.db:SetProfile(targetProfile) end

        KE.db:CopyProfile(sourceProfile)

        -- Switch back if needed
        if targetProfile ~= currentProfile then KE.db:SetProfile(currentProfile) end
    end)

    self:RefreshAllModules()
    return true
end

--- Delete a profile
---@param profileName string The profile name to delete
---@return boolean success
---@return string|nil error
function ProfileManager:DeleteProfile(profileName)
    if not profileName or profileName == "" then return false, "Profile name cannot be empty" end
    if not KE.db then return false, "Database not initialized" end
    -- Cannot delete active profile
    if profileName == self:GetCurrentProfile() then return false, "Cannot delete the active profile" end

    -- Check if profile exists
    local profiles = self:GetProfiles()
    local exists = false
    for _, name in pairs(profiles) do
        if name == profileName then
            exists = true
            break
        end
    end

    if not exists then return false, "Profile '" .. profileName .. "' does not exist" end

    -- Check if this is the global profile
    if KE.db.global and KE.db.global.UseGlobalProfile then
        if KE.db.global.GlobalProfile == profileName then
            -- Reset global profile to Default
            KE.db.global.GlobalProfile = DEFAULT_PROFILE
        end
    end

    KE.db:DeleteProfile(profileName)
    return true
end

--- Rename a profile
---@param oldName string Current profile name
---@param newName string New profile name
---@return boolean success
---@return string|nil error
function ProfileManager:RenameProfile(oldName, newName)
    if not oldName or oldName == "" then return false, "Current name cannot be empty" end
    if not newName or newName == "" then return false, "New name cannot be empty" end
    if oldName == newName then return false, "Names are identical" end
    if not KE.db then return false, "Database not initialized" end

    -- Check if old profile exists
    local profiles = self:GetProfiles()
    local oldExists = false
    for _, name in pairs(profiles) do
        if name == oldName then
            oldExists = true
        end
        if name == newName then
            return false, "Profile '" .. newName .. "' already exists"
        end
    end

    if not oldExists then return false, "Profile '" .. oldName .. "' does not exist" end

    local previousProfile = self:GetCurrentProfile()
    local isCurrentProfile = (oldName == previousProfile)
    local isGlobalProfile = KE.db.global and KE.db.global.GlobalProfile == oldName

    withRefreshSuppressed(function()
        -- Create new profile with old profile's data
        KE.db:SetProfile(newName)

        -- Copy from old profile
        KE.db:CopyProfile(oldName)

        -- If old was current, stay on new; otherwise restore the profile that
        -- was active before the rename (GetCurrentProfile() would return
        -- newName here).
        if not isCurrentProfile then KE.db:SetProfile(previousProfile) end

        -- Delete old profile
        KE.db:DeleteProfile(oldName)
    end)

    -- Update global profile reference if needed
    if isGlobalProfile then KE.db.global.GlobalProfile = newName end

    self:RefreshAllModules()
    return true
end

--- Reset current profile to defaults
---@return boolean success
function ProfileManager:ResetProfile()
    if not KE.db then return false end

    KE.db:ResetProfile()
    return true
end

---------------------------------------------------------------------------------
-- Global Profile Management
---------------------------------------------------------------------------------

--- Enable or disable global profile mode
---@param enabled boolean Whether to use global profile
---@return boolean success
function ProfileManager:SetUseGlobalProfile(enabled)
    if not KE.db or not KE.db.global then return false end
    KE.db.global.UseGlobalProfile = enabled

    -- Switch to global profile
    if enabled then
        local globalProfile = KE.db.global.GlobalProfile or DEFAULT_PROFILE
        KE.db:SetProfile(globalProfile)
    end

    return true
end

--- Get whether global profile mode is enabled
---@return boolean
function ProfileManager:GetUseGlobalProfile()
    if KE.db and KE.db.global then return KE.db.global.UseGlobalProfile or false end
    return false
end

--- Set which profile to use as global
---@param profileName string The profile name to use globally
---@return boolean success
---@return string|nil error
function ProfileManager:SetGlobalProfile(profileName)
    if not profileName or profileName == "" then return false, "Profile name cannot be empty" end
    if not KE.db or not KE.db.global then return false, "Database not initialized" end

    KE.db.global.GlobalProfile = profileName

    -- If global mode is active, switch to this profile
    if KE.db.global.UseGlobalProfile then
        KE.db:SetProfile(profileName)
    end

    return true
end

--- Get the name of the global profile
---@return string
function ProfileManager:GetGlobalProfile()
    if KE.db and KE.db.global then return KE.db.global.GlobalProfile or DEFAULT_PROFILE end
    return DEFAULT_PROFILE
end

---------------------------------------------------------------------------------
-- Import / Export
---------------------------------------------------------------------------------

--- Export a profile to a string
---@param profileName string|nil Profile to export (current if nil)
---@return string|nil exportString
---@return string|nil error
function ProfileManager:ExportProfile(profileName)
    profileName = profileName or self:GetCurrentProfile()

    if not KE.db then return nil, "Database not initialized" end

    local profileData = KE.db.profiles[profileName]
    if not profileData then return nil, "Profile '" .. profileName .. "' not found" end

    -- Create export package with metadata
    local exportData = {
        _v = 1,           -- Version
        _n = profileName, -- Original profile name
        _t = time(),      -- Timestamp
        d = profileData   -- Profile data
    }

    -- Serialize
    local serialized = AceSerializer:Serialize(exportData)
    if not serialized then return nil, "Serialization failed" end

    -- Compress
    local compressed = LibDeflate:CompressDeflate(serialized, { level = 9 })
    if not compressed then return nil, "Compression failed" end

    -- Encode for copy
    local encoded = LibDeflate:EncodeForPrint(compressed)
    if not encoded then return nil, "Encoding failed" end

    return EXPORT_PREFIX .. encoded
end

--- Import a profile from a string
---@param importString string The export string
---@param targetName string|nil Name for the imported profile (uses embedded name if nil)
---@return boolean success
---@return string|nil nameOrError
function ProfileManager:ImportProfile(importString, targetName)
    if not importString or importString == "" then return false, "Import string is empty" end
    -- Validate prefix
    if importString:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then return false, "Invalid format (missing or wrong prefix)" end
    if not KE.db then return false, "Database not initialized" end

    -- Remove prefix
    local encoded = importString:sub(#EXPORT_PREFIX + 1)

    local profileData, embeddedName

    -- Try internal format first (LibDeflate + AceSerializer)
    local compressed = LibDeflate:DecodeForPrint(encoded)
    if compressed then
        local serialized = LibDeflate:DecompressDeflate(compressed)
        if serialized then
            local success, exportData = AceSerializer:Deserialize(serialized)
            if success and type(exportData) == "table" and exportData.d then
                profileData = exportData.d
                embeddedName = exportData._n
            end
        end
    end

    -- Fallback: try Wago API format (C_EncodingUtil: Base64 + Deflate + CBOR)
    if not profileData and C_EncodingUtil then
        local decoded = C_EncodingUtil.DecodeBase64(encoded)
        if decoded then
            local decompressed = C_EncodingUtil.DecompressString(decoded, Enum.CompressionMethod.Deflate)
            if decompressed then
                local data = C_EncodingUtil.DeserializeCBOR(decompressed)
                if data and type(data) == "table" then
                    -- Check if it's an envelope with {d = ..., _n = ...}
                    if data.d and type(data.d) == "table" then
                        profileData = data.d
                        embeddedName = data._n
                    else
                        -- Raw profile data (legacy or third-party export)
                        profileData = data
                    end
                end
            end
        end
    end

    if not profileData then return false, "Decoding failed" end

    -- Determine target profile name
    local finalName = targetName or embeddedName or "Imported"

    -- Check if profile exists and generate unique name if needed
    local profiles = self:GetProfiles()
    local baseName = finalName
    local counter = 1
    local nameExists = true

    while nameExists do
        nameExists = false
        for _, name in pairs(profiles) do
            if name == finalName then
                nameExists = true
                counter = counter + 1
                finalName = baseName .. " (" .. counter .. ")"
                break
            end
        end
    end

    -- Create the profile
    local currentProfile = self:GetCurrentProfile()

    withRefreshSuppressed(function()
        -- Switch to new profile (creates it)
        KE.db:SetProfile(finalName)

        -- Copy imported data to profile
        local profileRef = KE.db.profile
        if profileRef then
            wipe(profileRef)
            for k, v in pairs(profileData) do
                profileRef[k] = v
            end
        end

        -- Switch back to original profile
        KE.db:SetProfile(currentProfile)
    end)

    return true, finalName
end

---------------------------------------------------------------------------------
-- Module Refresh
---------------------------------------------------------------------------------

--- Refresh all enabled modules to apply new settings
function ProfileManager:RefreshAllModules()
    local KitnEssentials = _G.KitnEssentials
    if not KitnEssentials then return end

    -- Stop previews before refreshing anything
    if KE.PreviewManager then KE.PreviewManager:StopAllPreviews() end

    -- Sync module enabled state to the (possibly new) profile. Startup does
    -- this in Core/Main.lua OnEnable; profile switches previously didn't —
    -- modules enabled under the old profile kept their events/frames live,
    -- and newly-enabled modules stayed dormant. Only modules that publish a
    -- db.Enabled flag are synced; keSelfManagedEnable modules (any module
    -- with a sub-feature that runs independent of the master toggle)
    -- manage their own state. Skin* modules are NEVER flipped
    -- live — skinning applies destructively at enable and OnDisable has no
    -- frame teardown — a mismatch prompts for the /reload that lets startup
    -- apply the new flags (silently skipped when ElvUI handles skinning).
    local skipSkinning = KE.ShouldNotLoadModule and KE:ShouldNotLoadModule()
    local skinningChanged = false
    local reloadNeeded = false
    for name, module in KitnEssentials:IterateModules() do
        if module.UpdateDB then module:UpdateDB() end
        local wasEnabled = module:IsEnabled()
        local wantEnabled = module.db and module.db.Enabled
        local stateMismatch = wantEnabled ~= nil and not module.keSelfManagedEnable
            and (not wantEnabled) ~= (not wasEnabled)
        local skinDeferred = false
        local reloadDeferred = false
        if stateMismatch then
            if name:find("^Skin") or module.keDeferToReload then
                skinDeferred = true
                if not skipSkinning then skinningChanged = true end
            elseif wantEnabled then
                KitnEssentials:EnableModule(name)
            elseif module.keReloadOnDisable then
                -- Module has no live teardown for what OnEnable does
                -- (permanent hooks, replaced Blizzard functions, or a raised
                -- Blizzard constant) — disabling it live would leave those
                -- changes in place while the module reports itself off.
                -- Stay enabled until the reload fixes the mismatch.
                reloadDeferred = true
                reloadNeeded = true
            else
                KitnEssentials:DisableModule(name)
            end
        end
        -- Newly-enabled modules apply settings inside their own OnEnable
        -- (AceAddon dispatches it from EnableModule); re-applying here would
        -- double-run their setup (e.g. DragonRiding:OnEnable → ApplySettings).
        -- Skin modules pending a reload must not apply the mismatched
        -- profile's settings either (ActionBars:ApplySettings has no master
        -- db.Enabled guard — it would destructively apply a disabled-intent
        -- profile's config). Same for reload-deferred modules: the new
        -- profile wants this module OFF, so applying its settings now would
        -- configure a module that's about to be torn down by /reload.
        if wasEnabled and module:IsEnabled() and module.ApplySettings and not skinDeferred and not reloadDeferred then
            module:ApplySettings()
        end
    end

    -- A profile operation ALWAYS prompts for a reload, as a precaution.
    -- Prompting per class instead — skinning changes, and modules carrying
    -- keReloadOnDisable — left every other switch silent, and modules like
    -- MoveFrames leave state behind (movable and mouse flags survive
    -- DisableModule) without carrying the flag. Prompt always rather than chase
    -- per-module flags.
    --
    -- ONE prompt, never two: KE:CreatePrompt stores KE.activePrompt, so a second
    -- call here would replace the first.
    if skinningChanged and KE.SkinningReloadPrompt then
        KE:SkinningReloadPrompt()
    elseif KE.CreateReloadPrompt then
        KE:CreateReloadPrompt(reloadNeeded
            and "This profile turns off a feature that needs a UI reload to fully take effect."
            or "Profile changed. Reload your UI so every setting applies cleanly.")
    end

    -- Refresh theme
    if KE.RefreshTheme then KE:RefreshTheme() end

    -- Refresh GUI frame if open
    if KE.GUIFrame and KE.GUIFrame.ApplyThemeColors then KE.GUIFrame:ApplyThemeColors() end

    -- Re-evaluate previews based on current GUI / edit-mode state (this was
    -- historically a call to `StartAllPreviews`, which has never existed on
    -- PreviewManager — it was a typo for `UpdatePreviewState` that crashed
    -- every profile operation, halting execution inside SetProfile callbacks
    -- and leaving the active profile stuck at whatever intermediate state
    -- the error interrupted).
    if KE.PreviewManager and KE.PreviewManager.UpdatePreviewState then
        KE.PreviewManager:UpdatePreviewState()
    end

    -- Two profiles can keep the same modules enabled and still differ in a
    -- setting Edit Mode reads to decide whether a mover deserves a box, so no
    -- enable hook fires and the boxes would go stale. Guarded internally, so
    -- this costs nothing while the tool is closed.
    if KE.EditMode and KE.EditMode.RefreshLiveState then
        KE.EditMode:RefreshLiveState()
    end
end

---------------------------------------------------------------------------------
-- WagoUI Integration API
---------------------------------------------------------------------------------

-- https://github.com/methodgg/Wago-Creator-UI/blob/main/WagoUI_Libraries/LibAddonProfiles/ImplementationGuide.lua
KitnEssentialsAPI = KitnEssentialsAPI or {}

--- Export a profile by key
---@param profileKey string The profile name to export
---@return string The encoded profile string
function KitnEssentialsAPI:ExportProfile(profileKey)
    if not KE.db then return "" end

    local profileData = KE.db.profiles[profileKey]
    if not profileData then return "" end

    -- Wago expects raw profile data, no envelope wrapper
    local serialized = C_EncodingUtil.SerializeCBOR(profileData)
    local compressed = C_EncodingUtil.CompressString(serialized, Enum.CompressionMethod.Deflate, Enum.CompressionLevel.OptimizeForSize)
    local encoded = C_EncodingUtil.EncodeBase64(compressed)
    return encoded and (EXPORT_PREFIX .. encoded) or ""
end

--- Import a profile from string
---@param profileString string The encoded profile string
---@param profileKey string The name for the imported profile
function KitnEssentialsAPI:ImportProfile(profileString, profileKey)
    if not profileString or profileString == "" then return end
    if not KE.db then return end

    -- Use ProfileManager:ImportProfile which handles both LibDeflate and C_EncodingUtil formats
    local success, finalName = ProfileManager:ImportProfile(profileString, profileKey)
    if not success then return end

    -- Activate the imported profile (fires the OnProfileChanged callback,
    -- which refreshes without a ReloadUI)
    KE.db:SetProfile(finalName)
end

--- Decode a profile string without importing
---@param profileString string The profile string to decode
---@return table The decoded profile data
function KitnEssentialsAPI:DecodeProfileString(profileString)
    if not profileString or profileString == "" then return {} end

    -- Validate prefix
    if profileString:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then return {} end

    local encoded = profileString:sub(#EXPORT_PREFIX + 1)

    -- Try internal format first (LibDeflate + AceSerializer)
    local compressed = LibDeflate:DecodeForPrint(encoded)
    if compressed then
        local serialized = LibDeflate:DecompressDeflate(compressed)
        if serialized then
            local success, exportData = AceSerializer:Deserialize(serialized)
            if success and type(exportData) == "table" then
                if exportData.d and type(exportData.d) == "table" then
                    return exportData.d
                end
                return exportData
            end
        end
    end

    -- Fallback: try C_EncodingUtil format (Base64 + Deflate + CBOR)
    if C_EncodingUtil then
        local decoded = C_EncodingUtil.DecodeBase64(encoded)
        if decoded then
            local ok, decompressed = pcall(C_EncodingUtil.DecompressString, decoded, Enum.CompressionMethod.Deflate)
            if ok and decompressed then
                local data = C_EncodingUtil.DeserializeCBOR(decompressed)
                if data and type(data) == "table" then
                    if data.d and type(data.d) == "table" then
                        return data.d
                    end
                    return data
                end
            end
        end
    end

    return {}
end

--- Set the active profile
---@param profileKey string The profile to activate
function KitnEssentialsAPI:SetProfile(profileKey)
    if not profileKey or profileKey == "" then return end
    if not KE.db then return end

    KE.db:SetProfile(profileKey)
end

--- Get all profile keys
---@return table<string, boolean> Profile keys in format [key] = true
function KitnEssentialsAPI:GetProfileKeys()
    local keys = {}
    if KE.db and KE.db.profiles then
        for key in pairs(KE.db.profiles) do
            keys[key] = true
        end
    end
    if not next(keys) then
        keys["Default"] = true
    end
    return keys
end

--- Get current profile key
---@return string The current profile name
function KitnEssentialsAPI:GetCurrentProfileKey()
    if KE.db then
        return KE.db:GetCurrentProfile() or "Default"
    end
    return "Default"
end

--- Open config panel
function KitnEssentialsAPI:OpenConfig()
    if KE.GUIFrame and KE.GUIFrame.Show then
        KE.GUIFrame:Show()
    end
end

--- Close config panel
function KitnEssentialsAPI:CloseConfig()
    if KE.GUIFrame and KE.GUIFrame.Hide then
        KE.GUIFrame:Hide()
    end
end

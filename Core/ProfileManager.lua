-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)

-- Profile Manager Module
local ProfileManager = {}
KE.ProfileManager = ProfileManager

-- Libraries
local AceSerializer = LibStub("AceSerializer-3.0")
local LibDeflate = LibStub("LibDeflate")

-- Constants
local EXPORT_PREFIX = "!KE1!"
local DEFAULT_PROFILE = "Default"

-- Localization
local pairs = pairs
local type = type
local time = time
local wipe = wipe
local tostring = tostring
local next = next

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
---@return boolean success, string|nil error
function ProfileManager:SetProfile(profileName)
    if not profileName or profileName == "" then return false, "Invalid profile name" end
    if not KE.db then return false, "Database not initialized" end

    -- SetProfile handles creation if profile doesn't exist
    KE.db:SetProfile(profileName)
    self:RefreshAllModules()

    return true
end

--- Create a new profile with default values
---@param profileName string The name for the new profile
---@return boolean success, string|nil error
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
    KE.db:SetProfile(profileName)

    -- Reset to defaults
    KE.db:ResetProfile()

    -- Switch back to original profile
    KE.db:SetProfile(currentProfile)

    return true
end

--- Copy settings from one profile to another
---@param sourceProfile string Source profile name
---@param targetProfile string|nil Target profile name (current if nil)
---@return boolean success, string|nil error
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

    -- If target is not current, switch to target first
    if targetProfile ~= currentProfile then KE.db:SetProfile(targetProfile) end

    KE.db:CopyProfile(sourceProfile)

    -- Switch back if needed
    if targetProfile ~= currentProfile then KE.db:SetProfile(currentProfile) end

    self:RefreshAllModules()
    return true
end

--- Delete a profile
---@param profileName string The profile name to delete
---@return boolean success, string|nil error
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
---@return boolean success, string|nil error
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

    local isCurrentProfile = (oldName == self:GetCurrentProfile())
    local isGlobalProfile = KE.db.global and KE.db.global.GlobalProfile == oldName

    -- Create new profile with old profile's data
    KE.db:SetProfile(newName)

    -- Copy from old profile
    KE.db:CopyProfile(oldName)

    -- If old was current, stay on new; otherwise switch back
    if not isCurrentProfile then KE.db:SetProfile(self:GetCurrentProfile()) end

    -- Delete old profile
    KE.db:DeleteProfile(oldName)

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
    self:RefreshAllModules()
    return true
end

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

    self:RefreshAllModules()
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
---@return boolean success, string|nil error
function ProfileManager:SetGlobalProfile(profileName)
    if not profileName or profileName == "" then return false, "Profile name cannot be empty" end
    if not KE.db or not KE.db.global then return false, "Database not initialized" end

    KE.db.global.GlobalProfile = profileName

    -- If global mode is active, switch to this profile
    if KE.db.global.UseGlobalProfile then
        KE.db:SetProfile(profileName)
        self:RefreshAllModules()
    end

    return true
end

--- Get the name of the global profile
---@return string
function ProfileManager:GetGlobalProfile()
    if KE.db and KE.db.global then return KE.db.global.GlobalProfile or DEFAULT_PROFILE end
    return DEFAULT_PROFILE
end

--- Export a profile to a string
---@param profileName string|nil Profile to export (current if nil)
---@return string|nil exportString, string|nil error
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
---@return boolean success, string|nil nameOrError
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

    return true, finalName
end

--- Refresh all enabled modules to apply new settings
function ProfileManager:RefreshAllModules()
    local KitnEssentials = _G.KitnEssentials
    if not KitnEssentials then return end

    -- Stop previews before refreshing anything
    if KE.PreviewManager then KE.PreviewManager:StopAllPreviews() end

    -- Refresh module DB's and apply settings
    for _, module in KitnEssentials:IterateModules() do
        if module.UpdateDB then module:UpdateDB() end
        if module:IsEnabled() and module.ApplySettings then module:ApplySettings() end
    end

    -- Refresh theme
    if KE.RefreshTheme then KE:RefreshTheme() end

    -- Refresh GUI frame if open
    if KE.GUIFrame and KE.GUIFrame.ApplyThemeColors then KE.GUIFrame:ApplyThemeColors() end

    -- Start previews again
    if KE.PreviewManager then KE.PreviewManager:StartAllPreviews() end
end

-- WagoUI Integration API --

-- Global API table for WagoUI Packs compatibility
-- Uses C_EncodingUtil as per official Wago implementation guide
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

    -- Strip prefix if present
    if profileString:sub(1, #EXPORT_PREFIX) == EXPORT_PREFIX then
        profileString = profileString:sub(#EXPORT_PREFIX + 1)
    end

    local decoded = C_EncodingUtil.DecodeBase64(profileString)
    if not decoded then return end

    local decompressed = C_EncodingUtil.DecompressString(decoded, Enum.CompressionMethod.Deflate)
    if not decompressed then return end

    local profileData = C_EncodingUtil.DeserializeCBOR(decompressed)
    if not profileData or type(profileData) ~= "table" then return end

    -- Handle envelope format if present (from internal export)
    if profileData.d and type(profileData.d) == "table" then
        profileData = profileData.d
    end

    -- Store profile
    KE.db.profiles[profileKey] = profileData
    KE.db:SetProfile(profileKey)
    KE.db:SetProfile(profileKey)

    -- Refresh without ReloadUI
    ProfileManager:RefreshAllModules()
end

--- Decode a profile string without importing
---@param profileString string The profile string to decode
---@return table The decoded profile data
function KitnEssentialsAPI:DecodeProfileString(profileString)
    if not profileString or profileString == "" then return {} end

    -- Strip prefix if present
    if profileString:sub(1, #EXPORT_PREFIX) == EXPORT_PREFIX then
        profileString = profileString:sub(#EXPORT_PREFIX + 1)
    end

    local decoded = C_EncodingUtil.DecodeBase64(profileString)
    if not decoded then return {} end

    local decompressed = C_EncodingUtil.DecompressString(decoded, Enum.CompressionMethod.Deflate)
    if not decompressed then return {} end

    local profileData = C_EncodingUtil.DeserializeCBOR(decompressed)
    if profileData and type(profileData) == "table" then
        -- Handle envelope format {d = ..., _n = ...}
        if profileData.d and type(profileData.d) == "table" then
            return profileData.d
        end
        return profileData
    end

    return {}
end

--- Set the active profile
---@param profileKey string The profile to activate
function KitnEssentialsAPI:SetProfile(profileKey)
    if not profileKey or profileKey == "" then return end
    if not KE.db then return end

    KE.db:SetProfile(profileKey)
    ProfileManager:RefreshAllModules()
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

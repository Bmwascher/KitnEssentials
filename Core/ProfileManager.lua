-- ╔══════════════════════════════════════════════════════════╗
-- ║  ProfileManager.lua                                      ║
-- ║  Purpose: Profile import/export with compression,        ║
-- ║           per-character and global profile management.   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local ProfileManager = {}
KE.ProfileManager = ProfileManager

local EXPORT_PREFIX = "!KE2!"
-- Nothing decodes the old prefix; it is refused with one message.
local LEGACY_PREFIX = "!KE1!"
KE.LEGACY_EXPORT_MESSAGE = "this string was exported by an older version; ask for a fresh export"
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

-- AceDB raises a Lua error for any other name, so every path that names a
-- profile refuses it first.
local NAME_RULE = "Profile names must be 1 to 50 characters and not only spaces"

---@param name any
---@return string|nil error
function ProfileManager.ProfileNameError(name)
    if type(name) ~= "string" then return NAME_RULE end
    local length = strlenutf8(name)
    if length == 0 or length > 50 or name:find("^ +$") then return NAME_RULE end
    return nil
end
local ProfileNameError = ProfileManager.ProfileNameError

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
    local nameErr = ProfileNameError(profileName)
    if nameErr then return false, nameErr end
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
    local nameErr = ProfileNameError(profileName)
    if nameErr then return false, nameErr end
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
    local nameErr = ProfileNameError(targetProfile)
    if nameErr then return false, nameErr end

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
    local nameErr = ProfileNameError(newName)
    if nameErr then return false, nameErr end
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
        if ProfileNameError(globalProfile) then globalProfile = DEFAULT_PROFILE end
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
    local nameErr = ProfileNameError(profileName)
    if nameErr then return false, nameErr end
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
-- Export string codec
---------------------------------------------------------------------------------
-- CBOR, then Deflate, then Base64. The compress, decompress and Base64 calls
-- may return nothing, DeserializeCBOR may return nil, and SerializeCBOR raises
-- on a value it cannot represent, so both directions run under pcall and
-- answer nil.

local function Encode(tbl)
    local serialized = C_EncodingUtil.SerializeCBOR(tbl)
    local compressed = serialized and C_EncodingUtil.CompressString(serialized,
        Enum.CompressionMethod.Deflate, Enum.CompressionLevel.OptimizeForSize)
    return compressed and C_EncodingUtil.EncodeBase64(compressed)
end

local function Decode(encoded)
    local decoded = C_EncodingUtil.DecodeBase64(encoded)
    local decompressed = decoded and C_EncodingUtil.DecompressString(decoded, Enum.CompressionMethod.Deflate)
    return decompressed and C_EncodingUtil.DeserializeCBOR(decompressed)
end

--- Encode a table as a printable export string (no prefix)
---@param tbl table
---@return string|nil encoded
function KE:EncodeForExport(tbl)
    local ok, encoded = pcall(Encode, tbl)
    if ok and type(encoded) == "string" and encoded ~= "" then return encoded end
    return nil
end

--- Decode a printable export string (prefix already removed) to a table
---@param encoded string
---@return table|nil
function KE:DecodeFromExport(encoded)
    local ok, data = pcall(Decode, encoded)
    if ok and type(data) == "table" then return data end
    return nil
end

---------------------------------------------------------------------------------
-- Client filter
---------------------------------------------------------------------------------
-- A string from another client can carry blocks of modules this one does not
-- run. They are dropped, so a later admission starts from defaults rather than
-- from the other client's spell ids and spec lists. A block keyed by anything
-- but a name, or whose type is not its default's, is malformed and dropped on
-- every client. A nested container is kept even when emptied: AceDB refills
-- its sub-blocks from the defaults.

-- Labels the split at each capital gets wrong.
local BLOCK_LABELS = {
    DoTTracker = "DoT Tracker",
}

local function BlockLabel(key)
    if BLOCK_LABELS[key] then return BLOCK_LABELS[key] end
    return (key:gsub("(%l)(%u)", "%1 %2"):gsub("(%u)(%u%l)", "%1 %2"))
end

local function Malformed(value, default)
    return default ~= nil and type(value) ~= type(default)
end

-- Blocks whose Enabled only keeps a container page reachable: they are on
-- when one of these feature switches is.
local FEATURE_SWITCHES = {
    KeystoneHelper = { "ResetEnabled", "RerollEnabled", "YourKeyEnabled" },
}

local function SwitchOn(block, default, field)
    if block[field] ~= nil then return block[field] == true end
    return type(default) == "table" and default[field] == true
end

local function WasOn(key, block, default)
    local switches = FEATURE_SWITCHES[key]
    if not switches then return SwitchOn(block, default, "Enabled") end
    for i = 1, #switches do
        if SwitchOn(block, default, switches[i]) then return true end
    end
    return false
end

local function Drop(container, key, default, dropped)
    local block = container[key]
    if type(block) == "table" and WasOn(key, block, default) then
        dropped[#dropped + 1] = BlockLabel(key)
    end
    container[key] = nil
end

--- Removes, in place, every block this client may not keep. Returns the
--- labels of removed blocks that were turned on, sorted.
---@param profile table
---@param defaults table? the profile section of the defaults
---@return string[] dropped
function ProfileManager.FilterForClient(profile, defaults)
    local dropped = {}
    for key, block in pairs(profile) do
        local default = defaults and defaults[key]
        if type(key) ~= "string" or Malformed(block, default) then
            profile[key] = nil
        else
            local kind, owner = KE:ProfileBlockOwner(key)
            if kind == "nested" and type(block) == "table" then
                for subKey, sub in pairs(block) do
                    local subDefault = type(default) == "table" and default[subKey] or nil
                    if type(subKey) ~= "string" or Malformed(sub, subDefault) then
                        block[subKey] = nil
                    elseif not KE:IsFeatureAvailable(subKey) then
                        Drop(block, subKey, subDefault, dropped)
                    end
                end
            elseif kind == "feature" and not KE:IsFeatureAvailable(owner) then
                Drop(profile, key, default, dropped)
            end
        end
    end
    table.sort(dropped)
    return dropped
end

--- The client an export envelope names; an untagged one reads as retail.
---@param envelope table?
---@return string client "forever" or "retail"
function ProfileManager.EnvelopeClient(envelope)
    if type(envelope) == "table" and envelope._c == "forever" then return "forever" end
    return "retail"
end

local function IsBaseline()
    return KE.IsBaselineLoad ~= nil and KE:IsBaselineLoad() == true
end

-- What an export encodes: on a baseline load a filtered copy, so the live
-- profile is never touched. A nested container is copied one level, the level
-- the filter edits.
local function ExportData(profileData)
    if not IsBaseline() then return profileData end
    local copy = {}
    for key, value in pairs(profileData) do
        if type(value) == "table" and KE:ProfileBlockOwner(key) == "nested" then
            local inner = {}
            for subKey, sub in pairs(value) do inner[subKey] = sub end
            value = inner
        end
        copy[key] = value
    end
    local defaults = KE.GetDefaultDB and KE:GetDefaultDB()
    ProfileManager.FilterForClient(copy, defaults and defaults.profile)
    return copy
end

-- Set by an install that dropped a block that was on, for the refresh that
-- follows the switch to it: that refresh's reload prompt names them too.
local pendingNotice

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

    local encoded = KE:EncodeForExport({
        _v = 2,                                 -- Version
        _c = IsBaseline() and "forever" or nil, -- Client; absent means retail
        _n = profileName,                       -- Original profile name
        _t = time(),                            -- Timestamp
        d = ExportData(profileData)             -- Profile data
    })
    if not encoded then return nil, "Encoding failed" end

    return EXPORT_PREFIX .. encoded
end

--- Decode an export string to its profile table
---@param importString string
---@return table|nil profileData
---@return string|nil embeddedName
---@return string|nil error
---@return string|nil client "forever" or "retail" for a decoded string
function ProfileManager:DecodeImportString(importString)
    if not importString or importString == "" then return nil, nil, "Import string is empty" end
    if importString:sub(1, #LEGACY_PREFIX) == LEGACY_PREFIX then return nil, nil, KE.LEGACY_EXPORT_MESSAGE end
    if importString:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then return nil, nil, "Invalid format (missing or wrong prefix)" end

    local data = KE:DecodeFromExport(importString:sub(#EXPORT_PREFIX + 1))
    if not data then return nil, nil, "Decoding failed" end

    -- The user-facing export wraps the profile in an envelope; the Wago API
    -- export is the raw profile table.
    if type(data.d) == "table" then
        return data.d, type(data._n) == "string" and data._n or nil, nil, ProfileManager.EnvelopeClient(data)
    end
    return data, nil, nil, "retail"
end

--- Create a profile from a decoded table
---@param profileData table
---@param targetName string|nil Name for the new profile ("Imported" if nil)
---@return boolean success
---@return string nameOrError
function ProfileManager:InstallProfile(profileData, targetName)
    if not KE.db then return false, "Database not initialized" end

    local finalName = targetName or "Imported"

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

    local nameErr = ProfileNameError(finalName)
    if nameErr then
        if finalName ~= baseName then
            nameErr = nameErr .. "; adding \" (" .. counter .. ")\" to keep it unique made it too long"
        end
        return false, nameErr
    end

    -- Before the copy, so a string exported before a rename lands converted
    -- and no old key reaches KE.db.
    KE:MigrateProfileKeys(profileData)

    -- After the renames, so a renamed block is judged under its new name.
    local defaults = KE.GetDefaultDB and KE:GetDefaultDB()
    local dropped = ProfileManager.FilterForClient(profileData, defaults and defaults.profile)
    local notice = #dropped > 0 and ("Not available on this client: " .. table.concat(dropped, ", ")) or nil
    if notice then KE:Print(notice) end

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

    pendingNotice = notice and { profile = finalName, text = notice } or nil
    return true, finalName
end

--- Import a profile from a string
---@param importString string The export string
---@param targetName string|nil Name for the imported profile (uses embedded name if nil)
---@return boolean success
---@return string|nil nameOrError
function ProfileManager:ImportProfile(importString, targetName)
    local profileData, embeddedName, err = self:DecodeImportString(importString)
    if not profileData then return false, err end
    return self:InstallProfile(profileData, targetName or embeddedName)
end

---------------------------------------------------------------------------------
-- Module Refresh
---------------------------------------------------------------------------------

-- True while a profile refresh runs. The refresh rebuilds the shown settings
-- page once near its end, so a module it enables, disables or re-applies need
-- not rebuild it too.
local refreshingModules = false

--- Refresh all enabled modules to apply new settings
local function RefreshAll()
    local KitnEssentials = _G.KitnEssentials
    if not KitnEssentials then return end

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
    -- Rebind EVERY module's db before any enable/disable runs. AceDB's
    -- SetProfile calls removeDefaults on the outgoing profile: it strips
    -- default-equal leaves and deletes the nested tables that empties, so a
    -- module still holding the old table sees a half-gutted profile. Rebinding
    -- inside the enable/disable loop left that window open to every module the
    -- loop had not reached yet, and a teardown that touches a sibling
    -- (DM:ReleaseChatSize -> CHAT:UpdatePanel) then indexed keys stripping had
    -- removed -- while the flags it guards on, being non-default, survived.
    for _, module in KitnEssentials:IterateModules() do
        if module.UpdateDB then module:UpdateDB() end
    end

    -- Previews stop AFTER the rebind, never before it. Several HidePreview
    -- bodies read self.db (CR:Update, HM:FindHealers, and the visibility
    -- driver in DR), so stopping first hands them the same stripped outgoing
    -- profile the rebind exists to get rid of. Nothing in the rebind pass
    -- needs previews stopped.
    if KE.PreviewManager then KE.PreviewManager:StopAllPreviews() end

    for name, module in KitnEssentials:IterateModules() do
        local wasEnabled = module:IsEnabled()
        -- A withheld module is rebound above but never enabled or re-applied,
        -- whatever its saved flag says.
        local available = KE:IsFeatureAvailable(name)
        local wantEnabled = available and module.db and module.db.Enabled
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
        if available and wasEnabled and module:IsEnabled() and module.ApplySettings and not skinDeferred and not reloadDeferred then
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
    -- An import's notice rides on the refresh that switches to its profile;
    -- any other refresh drops it.
    local notice = pendingNotice
    pendingNotice = nil
    local extra = ""
    if notice and KE.db and notice.profile == KE.db:GetCurrentProfile() then
        extra = "\n\n" .. notice.text
    end
    if skinningChanged and KE.SkinningReloadPrompt then
        KE:SkinningReloadPrompt(extra)
    elseif KE.CreateReloadPrompt then
        KE:CreateReloadPrompt((reloadNeeded
            and "This profile turns off a feature that needs a UI reload to fully take effect."
            or "Profile changed. Reload your UI so every setting applies cleanly.") .. extra)
    end

    -- Refresh theme
    if KE.RefreshTheme then KE:RefreshTheme() end

    -- RefreshTheme repaints a shown window; this repaints a hidden one.
    if KE.GUIFrame and KE.GUIFrame.ApplyThemeColors and not KE.GUIFrame:IsShown() then
        KE.GUIFrame:ApplyThemeColors()
    end

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
    -- setting Edit Mode reads to decide whether it draws a mover's box, so no
    -- enable hook fires and the boxes would go stale. Guarded internally, so
    -- this costs nothing while the tool is closed.
    if KE.EditMode and KE.EditMode.RefreshLiveState then
        KE.EditMode:RefreshLiveState()
    end
end

-- A module error inside the refresh still clears the flag before it propagates.
function ProfileManager:RefreshAllModules()
    refreshingModules = true
    local ok, err = pcall(RefreshAll)
    refreshingModules = false
    if not ok then error(err, 0) end
end

function ProfileManager:IsRefreshingModules()
    return refreshingModules
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
    local encoded = KE:EncodeForExport(ExportData(profileData))
    return encoded and (EXPORT_PREFIX .. encoded) or ""
end

--- Import a profile from string
---@param profileString string The encoded profile string
---@param profileKey string The name for the imported profile
function KitnEssentialsAPI:ImportProfile(profileString, profileKey)
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
    return ProfileManager:DecodeImportString(profileString) or {}
end

--- Set the active profile
---@param profileKey string The profile to activate
function KitnEssentialsAPI:SetProfile(profileKey)
    if ProfileNameError(profileKey) then return end
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

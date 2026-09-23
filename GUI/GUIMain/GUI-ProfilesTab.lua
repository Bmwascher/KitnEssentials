-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-ProfilesTab.lua                                     ║
-- ║  GUI: Profile Manager                                    ║
-- ║  Purpose: The Profiles page as three sub-tabs: Profile   ║
-- ║  (switch, create, copy, rename, global mode), Sharing    ║
-- ║  (export, import) and Reset (delete, reset).             ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local pairs = pairs
local C_Timer = C_Timer

-- Destructive-action red, as the Dungeon Timers and M+ Timer pages use it.
local REMOVE_COLOR = { 0.9, 0.2, 0.2, 1 }
-- Middle dot between the status line's facts.
local STATUS_SEP = " \194\183 "
-- Height of the label slot a dropdown reserves above its box.
local DROPDOWN_LABEL_SLOT = 14

---------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------

local function BuildProfileOptions(exclude)
    local PM = KE.ProfileManager
    if not PM then return {} end
    local options = {}
    for _, name in pairs(PM:GetProfiles()) do
        if name ~= exclude then options[name] = name end
    end
    return options
end

-- The rebuild for actions no profile callback rebuilds after. A profile switch
-- rebuilds the page itself through OnProfileChanged, so those paths skip this.
local function RefreshPageLater()
    C_Timer.After(0.1, function()
        if GUIFrame.mainFrame and GUIFrame.mainFrame:IsShown() then
            GUIFrame:RefreshContent()
        end
    end)
end

local function AddSeparatorRow(card)
    local row = GUIFrame:CreateRow(card.content, Theme.rowHeightSeparator)
    row:AddWidget(GUIFrame:CreateSeparator(row), 1)
    card:AddRow(row, Theme.rowHeightSeparator)
end

local function TintDestructive(button)
    button.text:SetTextColor(REMOVE_COLOR[1], REMOVE_COLOR[2], REMOVE_COLOR[3], REMOVE_COLOR[4])
end

local function ErrorCard(scrollChild, yOffset)
    local card = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
    card:AddLabel("ProfileManager not initialized. Please reload UI.")
    return card:GetNextOffset()
end

-- The name box follows the pasted string's embedded name until a name is
-- typed by hand; lastAutoName tells the two apart.
local lastAutoName

local function AutoFillName(text, dialog)
    local _, name = KE.ProfileManager:DecodeImportString(text)
    if not name then return end
    local current = dialog.editBox:GetText()
    if current ~= "" and current ~= lastAutoName then return end
    lastAutoName = name
    dialog.editBox:SetText(name)
end

-- Shared by the Import button and the Import Failed dialog's Try again, so
-- both open the same two-field prompt.
local function OpenImportPrompt()
    local PM = KE.ProfileManager
    lastAutoName = nil
    KE:CreatePrompt(
        "Import Profile",
        "",
        true,
        "Profile Name",
        false, nil, nil, nil, nil,
        function(profileName, importString)
            if not importString or importString == "" then
                KE:Print("Please paste an import string")
                return
            end
            local targetName = profileName
            if targetName == "" then targetName = nil end

            local success, nameOrErr = PM:ImportProfile(importString, targetName)
            if success then
                KE:Print("Imported profile: " .. nameOrErr)
                -- Before the switch: activating the profile rebuilds the page
                -- at once, and that build must land on the Profile tab.
                GUIFrame.tabbedPageState["Profiles"] = "ProfilesMain"
                local switched, switchErr = PM:SetProfile(nameOrErr)
                if not switched then
                    KE:Print("Failed to switch profile: " .. (switchErr or "Unknown error"))
                    RefreshPageLater()
                end
            else
                KE:Print("Import failed: " .. (nameOrErr or "Unknown error"))
                KE:CreatePrompt(
                    "Import Failed",
                    nameOrErr or "Unknown error",
                    false, nil, false, nil, nil, nil, nil,
                    OpenImportPrompt,
                    nil,
                    "Try again",
                    "Close"
                )
            end
        end,
        nil,
        "Import",
        "Cancel",
        true,
        "Paste Import String",
        { onSecondTextChanged = AutoFillName }
    )
end

---------------------------------------------------------------------------------
-- Profile tab
---------------------------------------------------------------------------------

GUIFrame:RegisterContent("ProfilesMain", function(scrollChild, yOffset)
    local PM = KE.ProfileManager
    if not PM then return ErrorCard(scrollChild, yOffset) end

    local useGlobal = PM:GetUseGlobalProfile()
    local currentProfile = PM:GetCurrentProfile()
    local profileOptions = BuildProfileOptions()

    ---------------------------------------------------------------------------------
    -- Card 1: Current
    ---------------------------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Current", yOffset)

    card1:AddLabel("Active Profile: |cff4dff4d" .. currentProfile .. "|r"
        .. STATUS_SEP .. "Global Mode: " .. (useGlobal and "|cff4DCC66On|r" or "|cffE64D4DOff|r")
        .. STATUS_SEP .. KE:ColorTextByTheme(tostring(#PM:GetProfiles())) .. " Profiles Saved")

    -- The status line is this control's label; the widget is lifted past its
    -- own empty label slot so the box sits directly under the line.
    local row1a = GUIFrame:CreateRow(card1.content, Theme.rowHeight - DROPDOWN_LABEL_SLOT)
    local profileDropdown = GUIFrame:CreateDropdown(row1a, "", {
        options = profileOptions,
        value = currentProfile,
        callback = function(key)
            -- Live lookup: the page-build capture goes stale after the first
            -- switch while the page stays open.
            if key == PM:GetCurrentProfile() then return end

            local success, err = PM:SetProfile(key)
            if not success then
                KE:Print("Failed to switch profile: " .. (err or "Unknown error"))
            end
        end,
    })
    row1a:AddWidget(profileDropdown, 1, nil, 0, DROPDOWN_LABEL_SLOT)
    card1:AddRow(row1a, Theme.rowHeight - DROPDOWN_LABEL_SLOT)
    profileDropdown:SetEnabled(not useGlobal)

    local row1b = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local newProfileInput = GUIFrame:CreateEditBox(row1b, "New Profile", {
        value = "",
        callback = function() end,
    })
    row1b:AddWidget(newProfileInput, 0.6)

    local createBtn = GUIFrame:CreateButton(row1b, "Create", {
        height = 24,
        callback = function()
            local name = newProfileInput:GetValue()
            if not name or name == "" then
                KE:Print("Please enter a profile name")
                return
            end
            local success, err = PM:CreateProfile(name)
            if success then
                KE:Print("Created profile: " .. name)
                newProfileInput:SetValue("")
                RefreshPageLater()
            else
                KE:Print("Failed to create profile: " .. (err or "Unknown error"))
            end
        end,
    })
    row1b:AddWidget(createBtn, 0.4, nil, 0, -14)
    card1:AddRow(row1b, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    ---------------------------------------------------------------------------------
    -- Card 2: Edit
    ---------------------------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Edit", yOffset)

    local row2a = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local copyDropdown = GUIFrame:CreateDropdown(row2a, "Copy From", {
        options = profileOptions,
        value = "",
        callback = function() end,
    })
    row2a:AddWidget(copyDropdown, 0.6)

    local copyBtn = GUIFrame:CreateButton(row2a, "Copy", {
        height = 24,
        callback = function()
            local source = copyDropdown:GetValue()
            if not source or source == "" then
                KE:Print("Please select a source profile")
                return
            end
            KE:CreatePrompt(
                "Copy Profile",
                "Copy all settings from '" ..
                source .. "' to current profile?\nThis will overwrite your current settings.",
                false, nil, false, nil, nil, nil, nil,
                function()
                    local success, err = PM:CopyProfile(source)
                    if not success then
                        KE:Print("Failed to copy profile: " .. (err or "Unknown error"))
                    end
                end,
                nil,
                "Copy",
                "Cancel"
            )
        end,
    })
    row2a:AddWidget(copyBtn, 0.4, nil, 0, -14)
    card2:AddRow(row2a, Theme.rowHeight)

    local row2b = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local renameInput = GUIFrame:CreateEditBox(row2b, "Rename", {
        value = currentProfile,
        callback = function() end,
    })
    row2b:AddWidget(renameInput, 0.6)

    local renameBtn = GUIFrame:CreateButton(row2b, "Rename", {
        height = 24,
        callback = function()
            local oldName = PM:GetCurrentProfile()
            local newName = renameInput:GetValue()
            if not newName or newName == "" then
                KE:Print("Please enter a new name")
                return
            end
            local success, err = PM:RenameProfile(oldName, newName)
            if success then
                KE:Print("Renamed '" .. oldName .. "' to '" .. newName .. "'")
            else
                KE:Print("Failed to rename: " .. (err or "Unknown error"))
            end
        end,
    })
    row2b:AddWidget(renameBtn, 0.4, nil, 0, -14)
    card2:AddRow(row2b, Theme.rowHeight)

    AddSeparatorRow(card2)

    local row2c = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local globalToggle = GUIFrame:CreateCheckbox(row2c, "Use Global Profile", {
        value = useGlobal,
        callback = function(newState)
            local before = PM:GetCurrentProfile()
            if not PM:SetUseGlobalProfile(newState) then return end
            if not newState then
                KE:Print("Global profile mode disabled")
            end
            -- Enabling onto a different profile already rebuilt the page
            -- through OnProfileChanged.
            if not newState or PM:GetCurrentProfile() == before then
                RefreshPageLater()
            end
        end,
    })
    row2c:AddWidget(globalToggle, 0.4)

    local globalDropdown = GUIFrame:CreateDropdown(row2c, "Global Profile", {
        options = profileOptions,
        value = PM:GetGlobalProfile(),
        callback = function(key)
            local success, err = PM:SetGlobalProfile(key)
            if not success then
                KE:Print("Failed to set global profile: " .. (err or "Unknown error"))
            elseif not useGlobal then
                KE:Print("Global profile set to: " .. key)
            end
        end,
    })
    row2c:AddWidget(globalDropdown, 0.6)
    card2:AddRow(row2c, Theme.rowHeightLast, 0)
    globalDropdown:SetEnabled(useGlobal)

    return card2:GetNextOffset()
end)

---------------------------------------------------------------------------------
-- Sharing tab
---------------------------------------------------------------------------------

GUIFrame:RegisterContent("ProfilesSharing", function(scrollChild, yOffset)
    local PM = KE.ProfileManager
    if not PM then return ErrorCard(scrollChild, yOffset) end

    ---------------------------------------------------------------------------------
    -- Card 1: Export
    ---------------------------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Export", yOffset)
    card1:AddLabel("Turns the active profile into a string you can paste to another player. " ..
        "It carries every module setting in this profile; nicknames are exported from " ..
        "their own page.")

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local exportBtn = GUIFrame:CreateButton(row1, "Export Active Profile", {
        callback = function()
            local exportString, err = PM:ExportProfile()
            if exportString then
                KE:CreatePrompt(
                    "Export Profile",
                    exportString,
                    true,
                    "Copy the string above (Ctrl+C)",
                    false
                )
                KE:Print("Export Success")
            else
                KE:Print("Export failed: " .. (err or "Unknown error"))
            end
        end,
    })
    row1:AddWidget(exportBtn, 1)
    card1:AddRow(row1, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    ---------------------------------------------------------------------------------
    -- Card 2: Import
    ---------------------------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Import", yOffset)
    card2:AddLabel("Installs a pasted string as a new profile and switches to it. Strings " ..
        "from before the current format are refused; ask the sender for a fresh export.")

    local row2 = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local importBtn = GUIFrame:CreateButton(row2, "Import From String", {
        callback = OpenImportPrompt,
    })
    row2:AddWidget(importBtn, 1)
    card2:AddRow(row2, Theme.rowHeightLast, 0)

    return card2:GetNextOffset()
end)

---------------------------------------------------------------------------------
-- Reset tab
---------------------------------------------------------------------------------

GUIFrame:RegisterContent("ProfilesReset", function(scrollChild, yOffset)
    local PM = KE.ProfileManager
    if not PM then return ErrorCard(scrollChild, yOffset) end

    local currentProfile = PM:GetCurrentProfile()

    ---------------------------------------------------------------------------------
    -- Card 1: Delete a profile
    ---------------------------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Delete a profile", yOffset)
    card1:AddLabel("Removes the chosen profile and everything saved in it. The active " ..
        "profile cannot be deleted; switch to another one first.")

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local deleteDropdown = GUIFrame:CreateDropdown(row1, "Profile", {
        options = BuildProfileOptions(currentProfile),
        value = "",
        callback = function() end,
    })
    row1:AddWidget(deleteDropdown, 0.6)

    local deleteBtn = GUIFrame:CreateButton(row1, "Delete", {
        height = 24,
        callback = function()
            local toDelete = deleteDropdown:GetValue()
            if not toDelete or toDelete == "" then
                KE:Print("Please select a profile to delete")
                return
            end
            KE:CreatePrompt(
                "Delete profile",
                "Type the profile's name to delete it: " .. toDelete,
                true,
                "Case-sensitive",
                false, nil, nil, nil, nil,
                function()
                    local success, err = PM:DeleteProfile(toDelete)
                    if success then
                        KE:Print("Deleted profile: " .. toDelete)
                        RefreshPageLater()
                    else
                        KE:Print("Failed to delete profile: " .. (err or "Unknown error"))
                    end
                end,
                nil,
                "Delete",
                "Cancel",
                nil, nil,
                { requireTyped = toDelete, acceptColor = REMOVE_COLOR }
            )
        end,
    })
    TintDestructive(deleteBtn)
    row1:AddWidget(deleteBtn, 0.4, nil, 0, -14)
    card1:AddRow(row1, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    ---------------------------------------------------------------------------------
    -- Card 2: Reset the active profile
    ---------------------------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Reset the active profile", yOffset)
    card2:AddLabel("Puts every setting in " .. currentProfile .. " back to its default. " ..
        "Other profiles are untouched.")

    local row2 = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local resetBtn = GUIFrame:CreateButton(row2, "Reset To Defaults", {
        callback = function()
            local name = PM:GetCurrentProfile()
            KE:CreatePrompt(
                "Reset profile",
                "Type the profile's name to reset every setting in it: " .. name,
                true,
                "Case-sensitive",
                false, nil, nil, nil, nil,
                function()
                    if not PM:ResetProfile() then
                        KE:Print("Failed to reset profile")
                    end
                end,
                nil,
                "Reset",
                "Cancel",
                nil, nil,
                { requireTyped = name, acceptColor = REMOVE_COLOR }
            )
        end,
    })
    TintDestructive(resetBtn)
    row2:AddWidget(resetBtn, 1)
    card2:AddRow(row2, Theme.rowHeightLast, 0)

    return card2:GetNextOffset()
end)

---------------------------------------------------------------------------------
-- The sidebar entry
---------------------------------------------------------------------------------

GUIFrame:RegisterTabbedContent("Profiles", {
    { id = "ProfilesMain",    label = "Profile" },
    { id = "ProfilesSharing", label = "Sharing" },
    { id = "ProfilesReset",   label = "Reset" },
})

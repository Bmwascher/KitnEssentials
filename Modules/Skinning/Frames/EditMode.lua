local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local ipairs = ipairs

local function SkinCheckRow(row)
    if row and row.Button then S.CheckBox(row.Button) end
end

local function SkinSystemDialog()
    local dialog = _G.EditModeSystemSettingsDialog
    if not dialog then return end
    if dialog.Buttons then
        for _, button in ipairs({ dialog.Buttons:GetChildren() }) do
            if button.Controller then S.Button(button) end
        end
    end
    if dialog.Settings then
        for _, row in ipairs({ dialog.Settings:GetChildren() }) do
            if row.Dropdown then S.DropDown(row.Dropdown) end
            if row.Slider then S.StepSlider(row.Slider) end
            if row.Button and row.Button.GetChecked then S.CheckBox(row.Button) end
        end
    end
end

local function Skin()
    local editMode = _G.EditModeManagerFrame
    if not editMode or S.data(editMode).skinned then return end

    S.StripTextures(editMode)
    S.Backdrop(editMode)
    S.FontStringsDeep(editMode, nil, nil, 1)

    if editMode.CloseButton then S.CloseButton(editMode.CloseButton) end
    if editMode.RevertAllChangesButton then S.Button(editMode.RevertAllChangesButton) end
    if editMode.SaveChangesButton then S.Button(editMode.SaveChangesButton) end
    if editMode.LayoutDropdown then S.DropDown(editMode.LayoutDropdown) end

    if editMode.GridSpacingSlider then S.StepSlider(editMode.GridSpacingSlider) end
    SkinCheckRow(editMode.ShowGridCheckButton)
    SkinCheckRow(editMode.EnableSnapCheckButton)
    SkinCheckRow(editMode.EnableAdvancedOptionsCheckButton)

    local account = editMode.AccountSettings
    local container = account and account.SettingsContainer
    if container then
        if container.ScrollBar then S.TrimScrollBar(container.ScrollBar) end
        if container.BorderArt then S.StripTextures(container.BorderArt) end

        if container.ScrollChild then
            for _, group in ipairs({ container.ScrollChild:GetChildren() }) do
                for _, frame in ipairs({ group:GetChildren() }) do
                    if frame.Button then
                        S.CheckBox(frame.Button)
                    else
                        for _, child in ipairs({ frame:GetChildren() }) do
                            if child.Button then S.CheckBox(child.Button) end
                        end
                    end
                end
            end
        end
    end
    if account and account.Expander and account.Expander.Divider then
        S.StripTextures(account.Expander.Divider)
    end

    local layout = _G.EditModeLayoutDialog
    if layout then
        S.StripTextures(layout)
        S.Backdrop(layout)
        if layout.AcceptButton then S.Button(layout.AcceptButton) end
        if layout.CancelButton then S.Button(layout.CancelButton) end
        if layout.LayoutNameEditBox then S.EditBox(layout.LayoutNameEditBox) end
        SkinCheckRow(layout.CharacterSpecificLayoutCheckButton)
    end

    local unsaved = _G.EditModeUnsavedChangesDialog
    if unsaved then
        S.StripTextures(unsaved)
        S.Backdrop(unsaved)
        for _, key in ipairs({ "CancelButton", "ProceedButton", "SaveAndProceedButton" }) do
            if unsaved[key] then S.Button(unsaved[key]) end
        end
    end

    local import = _G.EditModeImportLayoutDialog
    if import then
        S.StripTextures(import)
        S.Backdrop(import)
        if import.AcceptButton then S.Button(import.AcceptButton) end
        if import.CancelButton then S.Button(import.CancelButton) end
        SkinCheckRow(import.CharacterSpecificLayoutCheckButton)
        if import.ImportBox then
            S.EditBox(import.ImportBox)
            if import.ImportBox.ScrollBar then S.ScrollBar(import.ImportBox.ScrollBar) end
        end
        if import.LayoutNameEditBox then S.EditBox(import.LayoutNameEditBox) end
    end

    local dialog = _G.EditModeSystemSettingsDialog
    if dialog then
        S.StripTextures(dialog)
        S.Backdrop(dialog)
        if dialog.CloseButton then S.CloseButton(dialog.CloseButton) end
        if dialog.Buttons and dialog.Buttons.AddLayoutChildren then
            hooksecurefunc(dialog.Buttons, "AddLayoutChildren", SkinSystemDialog)
        end
        SkinSystemDialog()
    end

    S.data(editMode).skinned = true
end

S:RegisterEarly(Skin, "EditMode")

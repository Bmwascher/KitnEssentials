---@class KE
local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local ipairs, pairs = ipairs, pairs
local hooksecurefunc = hooksecurefunc

-- Runs again on every open: KE's font can change while the window is closed.
local function ResizeCombatTabs()
    local resize = _G.PanelTemplates_TabResize
    if not resize then return end
    local i = 1
    local tab = _G["CombatConfigTab" .. i]
    while tab do
        if tab.Text and tab.Left and tab.Right then resize(tab, 0) end
        i = i + 1
        tab = _G["CombatConfigTab" .. i]
    end
end

local function OnUpdateCheckboxes(frame)
    if not _G.FCF_GetCurrentChatFrame() then return end
    if not frame.checkBoxTable then return end
    local nameString = frame:GetName() .. "Checkbox"
    for index in ipairs(frame.checkBoxTable) do
        local checkboxName = nameString .. index
        local checkbox = _G[checkboxName]
        if checkbox and not S.data(checkbox).skinned then
            S.data(checkbox).skinned = true
            S.StripTextures(checkbox)
            S.CheckBox(_G[checkboxName .. "Check"])
        end
    end
end

local function OnCreateTieredCheckboxes(frame, checkBoxTable)
    if S.data(frame).tieredSkinned then return end
    S.data(frame).tieredSkinned = true
    local nameString = frame:GetName() .. "Checkbox"
    for index, value in ipairs(checkBoxTable) do
        local checkboxName = nameString .. index
        S.CheckBox(_G[checkboxName])
        if value.subTypes then
            for i in ipairs(value.subTypes) do
                S.CheckBox(_G[checkboxName .. "_" .. i])
            end
        end
    end
end

local function OnTabManagerWidth(frame)
    for tab in frame.tabPool:EnumerateActive() do
        if not S.data(tab).skinned then
            S.data(tab).skinned = true
            S.StripTextures(tab)
        end
    end
end

local function OnUpdateSwatches(frame)
    if not frame.swatchTable then return end
    local nameString = frame:GetName() .. "Swatch"
    for index in ipairs(frame.swatchTable) do
        local bu = _G[nameString .. index]
        if bu and not S.data(bu).swatchSkinned then
            S.data(bu).swatchSkinned = true
            S.StripTextures(bu)
            S.Backdrop(bu)
        end
    end
end

local function OnUpdateSpeechCheckboxes(frame)
    if not frame.checkBoxTable then return end
    local nameString = frame:GetName() .. "Checkbox"
    for index in ipairs(frame.checkBoxTable) do
        local checkBox = _G[nameString .. index]
        -- S.CheckBox sets and tests its own skinned flag; setting it here
        -- first makes it return without skinning.
        if checkBox then S.CheckBox(checkBox) end
    end
end

local function Skin()
    local ccf = _G.ChatConfigFrame
    if not ccf then return end
    S.StripTextures(ccf)
    S.Template(ccf, "Window")
    if ccf.Header then S.StripTextures(ccf.Header) end

    do
        local i = 1
        local tab = _G["CombatConfigTab" .. i]
        while tab do
            S.StripTextures(tab)
            i = i + 1
            tab = _G["CombatConfigTab" .. i]
        end
    end
    ResizeCombatTabs()
    ccf:HookScript("OnShow", ResizeCombatTabs)

    for _, frame in pairs({
        _G.ChatConfigCategoryFrame, _G.ChatConfigBackgroundFrame,
        _G.ChatConfigCombatSettingsFilters, _G.CombatConfigColorsHighlighting,
        _G.CombatConfigColorsColorizeUnitName, _G.CombatConfigColorsColorizeSpellNames,
        _G.CombatConfigColorsColorizeDamageNumber, _G.CombatConfigColorsColorizeDamageSchool,
        _G.CombatConfigColorsColorizeEntireLine, _G.ChatConfigChatSettingsLeft,
        _G.ChatConfigOtherSettingsCombat, _G.ChatConfigOtherSettingsPVP,
        _G.ChatConfigOtherSettingsSystem, _G.ChatConfigOtherSettingsCreature,
        _G.ChatConfigChannelSettingsLeft, _G.CombatConfigMessageSourcesDoneBy,
        _G.CombatConfigColorsUnitColors, _G.CombatConfigMessageSourcesDoneTo,
        _G.ChatConfigTextToSpeechChannelSettingsLeft,
    }) do
        S.StripTextures(frame)
    end

    for _, panel in pairs({
        _G.ChatConfigCategoryFrame,
        _G.ChatConfigBackgroundFrame,
        _G.ChatConfigCombatSettingsFilters,
    }) do
        S.Backdrop(panel)
    end

    for _, box in pairs({
        _G.CombatConfigColorsHighlightingLine, _G.CombatConfigColorsHighlightingAbility,
        _G.CombatConfigColorsHighlightingDamage, _G.CombatConfigColorsHighlightingSchool,
        _G.CombatConfigColorsColorizeUnitNameCheck, _G.CombatConfigColorsColorizeSpellNamesCheck,
        _G.CombatConfigColorsColorizeSpellNamesSchoolColoring, _G.CombatConfigColorsColorizeDamageNumberCheck,
        _G.CombatConfigColorsColorizeDamageNumberSchoolColoring, _G.CombatConfigColorsColorizeDamageSchoolCheck,
        _G.CombatConfigColorsColorizeEntireLineCheck, _G.CombatConfigFormattingShowTimeStamp,
        _G.CombatConfigFormattingShowBraces, _G.CombatConfigFormattingUnitNames,
        _G.CombatConfigFormattingSpellNames, _G.CombatConfigFormattingItemNames,
        _G.CombatConfigFormattingFullText, _G.CombatConfigSettingsShowQuickButton,
        _G.CombatConfigSettingsSolo, _G.CombatConfigSettingsParty, _G.CombatConfigSettingsRaid,
    }) do
        S.CheckBox(box)
    end

    S.Button(_G.CombatLogDefaultButton)
    S.Button(_G.ChatConfigCombatSettingsFiltersCopyFilterButton)
    S.Button(_G.ChatConfigCombatSettingsFiltersAddFilterButton)
    S.Button(_G.ChatConfigCombatSettingsFiltersDeleteButton)
    S.Button(_G.CombatConfigSettingsSaveButton)
    S.Button(_G.ChatConfigFrameOkayButton)
    S.Button(_G.ChatConfigFrameDefaultButton)
    S.Button(_G.ChatConfigFrameRedockButton)

    S.ArrowButton(_G.ChatConfigMoveFilterUpButton, "up")
    S.ArrowButton(_G.ChatConfigMoveFilterDownButton, "down")

    if _G.ChatConfigMoveFilterUpButton then _G.ChatConfigMoveFilterUpButton:SetSize(22, 22) end
    if _G.ChatConfigMoveFilterDownButton then _G.ChatConfigMoveFilterDownButton:SetSize(22, 22) end
    if _G.ChatConfigCombatSettingsFiltersAddFilterButton then
        _G.ChatConfigCombatSettingsFiltersAddFilterButton:SetPoint("RIGHT", _G.ChatConfigCombatSettingsFiltersDeleteButton, "LEFT", -1, 0)
        _G.ChatConfigCombatSettingsFiltersCopyFilterButton:SetPoint("RIGHT", _G.ChatConfigCombatSettingsFiltersAddFilterButton, "LEFT", -1, 0)
    end
    if _G.ChatConfigMoveFilterUpButton and _G.ChatConfigCombatSettingsFilters then
        _G.ChatConfigMoveFilterUpButton:SetPoint("TOPLEFT", _G.ChatConfigCombatSettingsFilters, "BOTTOMLEFT", 3, 0)
        _G.ChatConfigMoveFilterDownButton:SetPoint("LEFT", _G.ChatConfigMoveFilterUpButton, "RIGHT", 1, 0)
    end

    if _G.CombatConfigSettingsNameEditBox then S.EditBox(_G.CombatConfigSettingsNameEditBox) end

    S.CheckBox(_G.CombatConfigColorsColorizeEntireLineBySource)
    S.CheckBox(_G.CombatConfigColorsColorizeEntireLineByTarget)
    if _G.ChatConfigCombatSettingsFilters then S.ScrollBar(_G.ChatConfigCombatSettingsFilters.ScrollBar) end

    if _G.TextToSpeechDefaultButton then S.Button(_G.TextToSpeechDefaultButton) end
    if _G.TextToSpeechCharacterSpecificButton then
        S.CheckBox(_G.TextToSpeechCharacterSpecificButton)
    end

    -- The panel's own controls carry parentKeys only; they have no global names.
    local ttsPanel = _G.TextToSpeechFramePanelContainer
    if ttsPanel then
        if ttsPanel.PlaySampleButton then S.Button(ttsPanel.PlaySampleButton) end
        if ttsPanel.PlaySampleAlternateButton then S.Button(ttsPanel.PlaySampleAlternateButton) end
        pcall(S.DropDown, ttsPanel.TtsVoiceDropdown)
        pcall(S.DropDown, ttsPanel.TtsVoiceAlternateDropdown)
        for _, key in pairs({ "AdjustRateSlider", "AdjustVolumeSlider" }) do
            local holder = ttsPanel[key]
            if holder and holder.Slider then S.Slider(holder.Slider) end
        end
        for _, key in pairs({
            "PlayActivitySoundWhenNotFocusedCheckButton",
            "PlaySoundSeparatingChatLinesCheckButton",
            "AddCharacterNameToSpeechCheckButton",
            "NarrateMyMessagesCheckButton",
            "UseAlternateVoiceForSystemMessagesCheckButton",
        }) do
            S.CheckBox(ttsPanel[key])
        end
    end
end

-- Blizzard builds and updates the checkboxes when the world loads, long
-- before the window opens; the held hooks skin them on its first show.
local function Arm()
    local ccf = _G.ChatConfigFrame
    if not ccf then return end
    local arm = S.Defer(Skin, ccf)
    hooksecurefunc("ChatConfig_UpdateCheckboxes", arm:Late(OnUpdateCheckboxes))
    hooksecurefunc("ChatConfig_CreateTieredCheckboxes", arm:Late(OnCreateTieredCheckboxes))
    hooksecurefunc("ChatConfig_UpdateSwatches", arm:Late(OnUpdateSwatches))
    hooksecurefunc("TextToSpeechFrame_UpdateMessageCheckboxes", arm:Late(OnUpdateSpeechCheckboxes))
    if _G.ChatConfigFrameChatTabManager then
        hooksecurefunc(_G.ChatConfigFrameChatTabManager, "UpdateWidth", OnTabManagerWidth)
    end
    -- The chat-bar speech button sits outside the window.
    if _G.TextToSpeechButton then S.StripTextures(_G.TextToSpeechButton) end
end

S:RegisterEarly(Arm, "ChatConfig")

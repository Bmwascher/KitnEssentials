-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-PositionController.lua                              ║
-- ║  GUI: Position Controller                                ║
-- ║  Purpose: Configuration panel for the PositionController ║
-- ║  module. Two halves: ElvUI unit frame anchoring          ║
-- ║  (top, requires ElvUI) and CDM Racials Anchor (bottom,   ║
-- ║  works with ElvUI or UUF, fully independent of the       ║
-- ║  master Position Controller toggle).                     ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local ipairs = ipairs

local FEATURE_ORDER = {
    { key = "PlayerFrame", title = "Player Frame" },
    { key = "TargetFrame", title = "Target Frame" },
    { key = "FocusFrame",  title = "Focus Frame"  },
    { key = "PetFrame",    title = "Pet Frame"    },
}

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("PositionController", true)
    end
    return nil
end

local function HasElvUI()
    return _G.ElvUI ~= nil
end

local function HasElvUIAnchor()
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded("ElvUI_Anchor")
    end
    return _G.IsAddOnLoaded and _G.IsAddOnLoaded("ElvUI_Anchor")
end

GUIFrame:RegisterContent("PositionController", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.PositionController
    if not db then return yOffset end

    local PC = GetModule()
    local elvUIPresent = HasElvUI()
    local anchorAddonPresent = HasElvUIAnchor()
    -- Anchoring half is available only when ElvUI is loaded AND no competing
    -- ElvUI_Anchor addon is present (we yield to that addon when it is).
    local anchoringAvailable = elvUIPresent and not anchorAddonPresent

    local function ApplySettings()
        if PC and PC.ApplySettings then PC:ApplySettings() end
    end

    local featureToggles = {}    -- key -> checkbox
    local featureCards = {}      -- key -> position card
    local healerToggle           -- Ignore Healer Specs checkbox
    local masterCheck            -- master enable checkbox (greyed if no ElvUI)

    local function RefreshEnableStates()
        local masterOn = db.Enabled == true

        -- Master toggle is greyed when anchoring isn't available (no ElvUI,
        -- or ElvUI_Anchor is handling it). CDM Racials below stays interactive
        -- regardless.
        if masterCheck and masterCheck.SetEnabled then
            masterCheck:SetEnabled(anchoringAvailable)
        end

        -- Top half — requires ElvUI and no competing anchor addon.
        for _, f in ipairs(FEATURE_ORDER) do
            local toggle = featureToggles[f.key]
            local card   = featureCards[f.key]
            local sub    = db[f.key]
            if toggle and toggle.SetEnabled then
                toggle:SetEnabled(masterOn and anchoringAvailable)
            end
            if card and card.SetEnabled then
                local featureOn = masterOn and anchoringAvailable and (sub and sub.Enabled == true)
                card:SetEnabled(featureOn)
            end
        end
        if healerToggle and healerToggle.SetEnabled then
            healerToggle:SetEnabled(masterOn and anchoringAvailable)
        end
        -- Bottom half (CDM Racials) is fully independent — never gated here.
    end

    ---------------------------------------------------------------------------------
    -- Card 1: Position Controller — master enable + intro note
    ---------------------------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Position Controller", yOffset)

    local masterRow = GUIFrame:CreateRow(card1.content, 36)
    masterCheck = GUIFrame:CreateCheckbox(masterRow, "Enable Position Controller",
        db.Enabled == true,
        function(checked)
            db.Enabled = checked
            ApplySettings()
            RefreshEnableStates()
        end,
        true, "Position Controller", "On", "Off")
    masterRow:AddWidget(masterCheck, 1)
    card1:AddRow(masterRow, 36)

    -- Intro + ElvUI requirement + live status indicator (3 states):
    --   * Green:  ElvUI present, no competing anchor addon — we run.
    --   * Yellow: ElvUI_Anchor present — we stand down, that addon runs.
    --   * Red:    ElvUI not detected — anchoring unavailable.
    local introLine = KE:ColorTextByTheme("-") ..
        " Anchors unit frames and adjusts CDM Racials placement."
    local requirementLine = KE:ColorTextByTheme("-") ..
        " Unit frame anchoring requires ElvUI; CDM Racials supports UUF too."
    local statusLine
    if not elvUIPresent then
        statusLine = "|cffff4444- ElvUI not detected. Unit frame anchoring is unavailable. |r"
    elseif anchorAddonPresent then
        statusLine = "|cffffcc33- ElvUI_Anchor detected. Unit frame anchoring delegated to that addon. |r"
    else
        statusLine = "|cff00ff00- ElvUI detected. Unit frame anchoring is available. |r"
    end
    local noteHeight = 86
    local noteRow = GUIFrame:CreateRow(card1.content, noteHeight)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        introLine .. "\n" .. requirementLine .. "\n" .. statusLine,
        noteHeight, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, noteHeight)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 2: Behavior — per-frame toggles + healer-spec gate
    ---------------------------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Behavior", yOffset)

    -- Per-feature enable toggles, 4 across
    local togglesRow = GUIFrame:CreateRow(card2.content, 40)
    for _, f in ipairs(FEATURE_ORDER) do
        local subDB = db[f.key]
        local cb = GUIFrame:CreateCheckbox(togglesRow, f.title,
            subDB and subDB.Enabled == true,
            function(checked)
                if subDB then subDB.Enabled = checked end
                ApplySettings()
                RefreshEnableStates()
            end)
        togglesRow:AddWidget(cb, 1 / #FEATURE_ORDER)
        featureToggles[f.key] = cb
    end
    card2:AddRow(togglesRow, 40)

    -- Ignore Healer Specs toggle on its own row, with a gray descriptor to
    -- the right of the toggle knob (#888888, same gray as other descriptor
    -- lines). The descriptor is a child of the checkbox row so it sits
    -- alongside the knob and label. Row height bumped to 50 so the
    -- descriptor can wrap to two lines if needed.
    local healerRow = GUIFrame:CreateRow(card2.content, 50)
    healerToggle = GUIFrame:CreateCheckbox(healerRow, "Ignore Healer Specs",
        db.IgnoreHealerSpec ~= false,
        function(checked)
            db.IgnoreHealerSpec = checked
            ApplySettings()
        end,
        true, "Ignore Healer Specs", "Yes", "No")
    healerRow:AddWidget(healerToggle, 1)

    local healerDesc = healerToggle:CreateFontString(nil, "OVERLAY")
    healerDesc:SetPoint("TOPLEFT", healerToggle, "TOPLEFT", 56, -16)
    healerDesc:SetPoint("RIGHT", healerToggle, "RIGHT", -8, 0)
    healerDesc:SetJustifyH("LEFT")
    healerDesc:SetJustifyV("TOP")
    healerDesc:SetWordWrap(true)
    KE:ApplyThemeFont(healerDesc, "small")
    healerDesc:SetTextColor(0x88 / 0xFF, 0x88 / 0xFF, 0x88 / 0xFF, 1)
    healerDesc:SetText("Leaves your unit frames where ElvUI placed them while you're on a healer spec.")

    card2:AddRow(healerRow, 50)

    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Cards 3-6: Position cards for each unit frame feature
    ---------------------------------------------------------------------------------
    for _, f in ipairs(FEATURE_ORDER) do
        local subDB = db[f.key]
        if subDB then
            local card, newOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
                title = f.title,
                db = subDB,
                dbKeys = {
                    anchorFrameType  = "anchorFrameType",
                    anchorFrameFrame = "ParentFrame",
                    selfPoint        = "AnchorFrom",
                    anchorPoint      = "AnchorTo",
                    xOffset          = "XOffset",
                    yOffset          = "YOffset",
                },
                showAnchorFrameType = true,
                showStrata = false,
                onChangeCallback = ApplySettings,
            })
            featureCards[f.key] = card
            yOffset = newOffset
        end
    end

    ---------------------------------------------------------------------------------
    -- Card 7: CDM Racials Anchor (bottom — fully independent of master)
    ---------------------------------------------------------------------------------
    local cdmDB = db.CDMRacials
    if cdmDB then
        local card7 = GUIFrame:CreateCard(scrollChild, "CDM Racials Anchor", yOffset)

        local row1 = GUIFrame:CreateRow(card7.content, 36)
        local cdmCheck = GUIFrame:CreateCheckbox(row1, "Enable CDM Racials Anchor",
            cdmDB.Enabled == true,
            function(checked)
                cdmDB.Enabled = checked
                ApplySettings()
            end,
            true, "CDM Racials Anchor", "On", "Off")
        row1:AddWidget(cdmCheck, 1)
        card7:AddRow(row1, 36)

        local row2 = GUIFrame:CreateRow(card7.content, 40)
        local cdmPetSlider = GUIFrame:CreateSlider(row2, "Pet Bar Y Offset",
            -100, 0, 1, cdmDB.PetBarOffset or -15, 60,
            function(val)
                cdmDB.PetBarOffset = val
                ApplySettings()
            end)
        row2:AddWidget(cdmPetSlider, 1)
        card7:AddRow(row2, 40)

        -- Note + live pet-status indicator (legacy pattern from the old
        -- RacialsAnchor module). Green when the pet bar is currently visible,
        -- red when the spec/class doesn't have one out right now. Indicator is
        -- skipped entirely on petless classes/specs since the status would
        -- never change.
        local cdmIntro = KE:ColorTextByTheme("-") ..
            " Hooks Ayije CDM to nudge the racials bar when a pet is summoned."
        local petLine = ""
        if PC and PC.IsPetFrame and PC:IsPetFrame() then
            if PC:HasPetBar() then
                petLine = "|cff00ff00- Your current spec has a pet bar visible. |r"
            else
                petLine = "|cffff4444- Your current spec does not have a pet bar visible. |r"
            end
        end

        local cdmNoteText
        local cdmNoteHeight
        if petLine ~= "" then
            cdmNoteHeight = 70
            local cdmNoteRow = GUIFrame:CreateRow(card7.content, cdmNoteHeight)
            cdmNoteText = GUIFrame:CreateText(cdmNoteRow,
                KE:ColorTextByTheme("Note"),
                cdmIntro .. "\n" .. petLine,
                cdmNoteHeight, "hide")
            cdmNoteRow:AddWidget(cdmNoteText, 1)
            card7:AddRow(cdmNoteRow, cdmNoteHeight)
        else
            cdmNoteHeight = 50
            local cdmNoteRow = GUIFrame:CreateRow(card7.content, cdmNoteHeight)
            cdmNoteText = GUIFrame:CreateText(cdmNoteRow,
                KE:ColorTextByTheme("Note"),
                cdmIntro,
                cdmNoteHeight, "hide")
            cdmNoteRow:AddWidget(cdmNoteText, 1)
            card7:AddRow(cdmNoteRow, cdmNoteHeight)
        end

        yOffset = yOffset + card7:GetContentHeight() + Theme.paddingSmall
    end

    RefreshEnableStates()
    yOffset = yOffset - (Theme.paddingSmall * 3)
    return yOffset
end)

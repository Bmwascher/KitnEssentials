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
    -- Anchoring is available only when ElvUI is loaded AND no competing
    -- ElvUI_Anchor addon is present (we yield to that addon when it is).
    local anchoringAvailable = elvUIPresent and not anchorAddonPresent

    local function ApplySettings()
        if PC and PC.ApplySettings then PC:ApplySettings() end
    end

    -- Master gates the whole top half. Per-feature sub-conditions gate each
    -- frame's position card on its own enable toggle. CDM Racials uses its
    -- own independent manager.
    local manager = GUIFrame:CreateWidgetStateManager()
    for _, f in ipairs(FEATURE_ORDER) do
        local key = f.key
        manager:SetCondition("feature_" .. key, function()
            return db[key] and db[key].Enabled == true
        end)
    end

    local masterCheck

    local function RefreshStates()
        local masterOn = db.Enabled == true and anchoringAvailable
        manager:UpdateAll(masterOn)
        -- Master toggle itself is editable whenever anchoring is available.
        if masterCheck and masterCheck.SetEnabled then
            masterCheck:SetEnabled(anchoringAvailable)
        end
    end

    ----------------------------------------------------------------
    -- Card 1: Position Controller — master enable + intro note
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Position Controller", yOffset)

    local masterRow = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    masterCheck = GUIFrame:CreateCheckbox(masterRow, "Enable Position Controller", {
        value = db.Enabled == true,
        callback = function(checked)
            db.Enabled = checked
            ApplySettings()
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Position Controller",
        msgOn = "On",
        msgOff = "Off",
    })
    masterRow:AddWidget(masterCheck, 1)
    card1:AddRow(masterRow, Theme.rowHeight)

    -- Intro + ElvUI requirement + live status indicator (3 states).
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
    local noteRow = GUIFrame:CreateRow(card1.content, 86)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        introLine .. "\n" .. requirementLine .. "\n" .. statusLine,
        86, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, 86, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Behavior — per-frame toggles + healer-spec gate
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Behavior", yOffset)
    manager:Register(card2, "all")

    local togglesRow = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    for _, f in ipairs(FEATURE_ORDER) do
        local key = f.key
        local subDB = db[key]
        local cb = GUIFrame:CreateCheckbox(togglesRow, f.title, {
            value = subDB and subDB.Enabled == true,
            callback = function(checked)
                if subDB then subDB.Enabled = checked end
                ApplySettings()
                RefreshStates()
            end,
        })
        togglesRow:AddWidget(cb, 1 / #FEATURE_ORDER)
        manager:Register(cb, "all")
    end
    card2:AddRow(togglesRow, Theme.rowHeight)

    -- Ignore Healer Specs toggle on its own row, with a gray descriptor
    -- alongside the knob.
    local healerRow = GUIFrame:CreateRow(card2.content, 50)
    local healerToggle = GUIFrame:CreateCheckbox(healerRow, "Ignore Healer Specs", {
        value = db.IgnoreHealerSpec ~= false,
        callback = function(checked)
            db.IgnoreHealerSpec = checked
            ApplySettings()
        end,
        msgPopup = true,
        msgText = "Ignore Healer Specs",
        msgOn = "Yes",
        msgOff = "No",
    })
    healerRow:AddWidget(healerToggle, 1)
    manager:Register(healerToggle, "all")

    local healerDesc = healerToggle:CreateFontString(nil, "OVERLAY")
    healerDesc:SetPoint("TOPLEFT", healerToggle, "TOPLEFT", 56, -16)
    healerDesc:SetPoint("RIGHT", healerToggle, "RIGHT", -8, 0)
    healerDesc:SetJustifyH("LEFT")
    healerDesc:SetJustifyV("TOP")
    healerDesc:SetWordWrap(true)
    KE:ApplyThemeFont(healerDesc, "small")
    healerDesc:SetTextColor(0x88/0xFF, 0x88/0xFF, 0x88/0xFF, 1)
    healerDesc:SetText("Leaves your unit frames where ElvUI placed them while you're on a healer spec.")

    card2:AddRow(healerRow, 50, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Cards 3-6: Position cards for each unit frame feature
    ----------------------------------------------------------------
    for _, f in ipairs(FEATURE_ORDER) do
        local key = f.key
        local subDB = db[key]
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

            if card.positionWidgets then
                manager:RegisterGroup(card.positionWidgets, "feature_" .. key)
            end
            manager:Register(card, "feature_" .. key)
            yOffset = newOffset
        end
    end

    ----------------------------------------------------------------
    -- Card 7: CDM Racials Anchor (independent module — own cascade)
    ----------------------------------------------------------------
    local cdmDB = db.CDMRacials
    if cdmDB then
        local cdmManager = GUIFrame:CreateWidgetStateManager()

        local function RefreshCDMStates()
            cdmManager:UpdateAll(cdmDB.Enabled == true)
        end

        local card7 = GUIFrame:CreateCard(scrollChild, "CDM Racials Anchor", yOffset)
        cdmManager:Register(card7, "all")

        local row1 = GUIFrame:CreateRow(card7.content, Theme.rowHeight)
        local cdmCheck = GUIFrame:CreateCheckbox(row1, "Enable CDM Racials Anchor", {
            value = cdmDB.Enabled == true,
            callback = function(checked)
                cdmDB.Enabled = checked
                ApplySettings()
                RefreshCDMStates()
            end,
            msgPopup = true,
            msgText = "CDM Racials Anchor",
            msgOn = "On",
            msgOff = "Off",
        })
        row1:AddWidget(cdmCheck, 1)
        card7:AddRow(row1, Theme.rowHeight)

        local row2 = GUIFrame:CreateRow(card7.content, Theme.rowHeightLast)
        local cdmPetSlider = GUIFrame:CreateSlider(row2, "Pet Bar Y Offset", {
            min = -100, max = 0, step = 1,
            value = cdmDB.PetBarOffset or -15,
            callback = function(val) cdmDB.PetBarOffset = val; ApplySettings() end,
        })
        row2:AddWidget(cdmPetSlider, 1)
        cdmManager:Register(cdmPetSlider, "all")
        card7:AddRow(row2, Theme.rowHeightLast, 0)

        -- Note + live pet-status indicator (legacy pattern from RacialsAnchor).
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

        if petLine ~= "" then
            local cdmNoteRow = GUIFrame:CreateRow(card7.content, 70)
            local cdmNoteText = GUIFrame:CreateText(cdmNoteRow,
                KE:ColorTextByTheme("Note"),
                cdmIntro .. "\n" .. petLine,
                70, "hide")
            cdmNoteRow:AddWidget(cdmNoteText, 1)
            cdmManager:Register(cdmNoteText, "all")
            card7:AddRow(cdmNoteRow, 70)
        else
            local cdmNoteRow = GUIFrame:CreateRow(card7.content, 50)
            local cdmNoteText = GUIFrame:CreateText(cdmNoteRow,
                KE:ColorTextByTheme("Note"),
                cdmIntro,
                50, "hide")
            cdmNoteRow:AddWidget(cdmNoteText, 1)
            cdmManager:Register(cdmNoteText, "all")
            card7:AddRow(cdmNoteRow, 50)
        end

        yOffset = card7:GetNextOffset()

        RefreshCDMStates()
    end

    RefreshStates()
    return yOffset
end)

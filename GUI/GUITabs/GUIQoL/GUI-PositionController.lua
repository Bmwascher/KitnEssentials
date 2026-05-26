-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-PositionController.lua                              ║
-- ║  GUI: Position Controller                                ║
-- ║  Purpose: Configuration panel for the PositionController ║
-- ║  module. Player/Target use simplified cards (X/Y only,   ║
-- ║  auto-anchored to the active CDM). Focus/Pet keep the    ║
-- ║  full anchor picker. CDM Racials sits below, independent ║
-- ║  of the master Position Controller toggle.               ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

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

    -- Master gates the entire top half. Per-feature sub-conditions gate each
    -- frame's position widgets on its own enable toggle. CDM Racials uses its
    -- own independent cascade further down.
    local manager = GUIFrame:CreateWidgetStateManager()
    local FEATURE_KEYS = { "PlayerFrame", "TargetFrame", "FocusFrame", "PetFrame" }
    for _, key in ipairs(FEATURE_KEYS) do
        manager:SetCondition("feature_" .. key, function()
            return db[key] and db[key].Enabled == true
        end)
    end

    local masterCheck

    local function RefreshStates()
        local masterOn = db.Enabled == true and anchoringAvailable
        manager:UpdateAll(masterOn)
        if masterCheck and masterCheck.SetEnabled then
            masterCheck:SetEnabled(anchoringAvailable)
        end
    end

    ----------------------------------------------------------------
    -- Card 1: Position Controller — master enable + behavior + note
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Position Controller", yOffset)

    local masterRow = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    masterCheck = GUIFrame:CreateCheckbox(masterRow, "Enable Position Controller", {
        value = db.Enabled == true,
        callback = function(checked)
            db.Enabled = checked
            ApplySettings()
            RefreshStates()
            -- Disabling suppresses behavior immediately (hooks self-gate on
            -- db.Enabled), but the installed HookScript callbacks on the
            -- ElvUI cooldown viewer + pet frames can't be uninstalled. Prompt
            -- for /reload to fully unload them. Re-enable is clean and
            -- intentionally not prompted.
            if not checked then
                KE:CreateReloadPrompt("Disabling Position Controller requires a /reload to fully unload its hooks.")
            end
        end,
        msgPopup = true,
        msgText = "Position Controller",
        msgOn = "On",
        msgOff = "Off",
    })
    masterRow:AddWidget(masterCheck, 1)
    card1:AddRow(masterRow, Theme.rowHeight)

    -- Ignore Healer Specs lives alongside the master enable since the Behavior
    -- card was collapsed away (per-frame toggles now live in each frame card).
    local healerRow = GUIFrame:CreateRow(card1.content, 50)
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

    card1:AddRow(healerRow, 50)

    -- Intro + ElvUI requirement + live status indicator (3 states).
    local introLine = KE:ColorTextByTheme("-") ..
        " Auto-anchors Player and Target frames beside SkironCooldownManager or Ayije_CDM, clearing the widest cooldown row."
    local requirementLine = KE:ColorTextByTheme("-") ..
        " Focus and Pet frames anchor freely; CDM Racials is independent and supports UUF too."
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
    -- Helper: simplified frame card (Player/Target).
    --
    -- Enable toggle + X Offset + Y Offset only. Anchor points stay at their
    -- default RIGHT/LEFT (Player) or LEFT/RIGHT (Target) — the backend reads
    -- them from db.PositionController.<Frame>.Position, and the user's saved
    -- value (if any) is preserved untouched. The active cooldown manager is
    -- the resolved parent; XOffset signs already encode the side.
    ----------------------------------------------------------------
    local function CreateSimpleFrameCard(title, key)
        local subDB = db[key]
        if not subDB then return end
        subDB.Position = subDB.Position or {}

        local card = GUIFrame:CreateCard(scrollChild, title, yOffset)

        local enableRow = GUIFrame:CreateRow(card.content, Theme.rowHeight)
        local enableToggle = GUIFrame:CreateCheckbox(enableRow, "Enable", {
            value = subDB.Enabled == true,
            callback = function(checked)
                subDB.Enabled = checked
                ApplySettings()
                RefreshStates()
            end,
            msgPopup = true,
            msgText = title,
            msgOn = "On",
            msgOff = "Off",
        })
        enableRow:AddWidget(enableToggle, 1)
        manager:Register(enableToggle, "all")
        card:AddRow(enableRow, Theme.rowHeight)

        local offsetRow = GUIFrame:CreateRow(card.content, Theme.rowHeightLast)
        local xSlider = GUIFrame:CreateSlider(offsetRow, "X Offset", {
            min = -200, max = 200, step = 1,
            value = subDB.Position.XOffset or 0,
            callback = function(val)
                subDB.Position.XOffset = val
                ApplySettings()
            end,
        })
        offsetRow:AddWidget(xSlider, 0.5)
        local ySlider = GUIFrame:CreateSlider(offsetRow, "Y Offset", {
            min = -200, max = 200, step = 1,
            value = subDB.Position.YOffset or 0,
            callback = function(val)
                subDB.Position.YOffset = val
                ApplySettings()
            end,
        })
        offsetRow:AddWidget(ySlider, 0.5)
        manager:Register(xSlider, "feature_" .. key)
        manager:Register(ySlider, "feature_" .. key)
        card:AddRow(offsetRow, Theme.rowHeightLast, 0)

        yOffset = card:GetNextOffset()
    end

    ----------------------------------------------------------------
    -- Card 2: Player Frame (simplified)
    ----------------------------------------------------------------
    CreateSimpleFrameCard("Player Frame", "PlayerFrame")

    ----------------------------------------------------------------
    -- Card 3: Target Frame (simplified)
    ----------------------------------------------------------------
    CreateSimpleFrameCard("Target Frame", "TargetFrame")

    ----------------------------------------------------------------
    -- Helper: full-anchor frame (Focus/Pet) — Enable card on top, full
    -- position card directly underneath. Matches AE v4's pattern verbatim:
    -- two stacked cards keep the master enable visually distinct from the
    -- anchor widget set without bloating CreatePositionCard with an extra
    -- toggle slot.
    ----------------------------------------------------------------
    local function CreateFullAnchorFrame(title, key)
        local subDB = db[key]
        if not subDB then return end

        local enableCard = GUIFrame:CreateCard(scrollChild, title, yOffset)
        local enableRow = GUIFrame:CreateRow(enableCard.content, Theme.rowHeight)
        local enableToggle = GUIFrame:CreateCheckbox(enableRow, "Enable", {
            value = subDB.Enabled == true,
            callback = function(checked)
                subDB.Enabled = checked
                ApplySettings()
                RefreshStates()
            end,
            msgPopup = true,
            msgText = title,
            msgOn = "On",
            msgOff = "Off",
        })
        enableRow:AddWidget(enableToggle, 1)
        manager:Register(enableToggle, "all")
        enableCard:AddRow(enableRow, Theme.rowHeight, 0)
        yOffset = enableCard:GetNextOffset()

        local card, newOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
            title = title .. " Position",
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

    ----------------------------------------------------------------
    -- Card 4 + 5: Focus Frame (Enable + Position)
    ----------------------------------------------------------------
    CreateFullAnchorFrame("Focus Frame", "FocusFrame")

    ----------------------------------------------------------------
    -- Card 6 + 7: Pet Frame (Enable + Position)
    ----------------------------------------------------------------
    CreateFullAnchorFrame("Pet Frame", "PetFrame")

    ----------------------------------------------------------------
    -- Card 8: CDM Racials Anchor (independent module — own cascade)
    ----------------------------------------------------------------
    local cdmDB = db.CDMRacials
    if cdmDB then
        local cdmManager = GUIFrame:CreateWidgetStateManager()

        local function RefreshCDMStates()
            cdmManager:UpdateAll(cdmDB.Enabled == true)
        end

        local card7 = GUIFrame:CreateCard(scrollChild, "CDM Racials Anchor", yOffset)
        -- Don't register the card itself in cdmManager — card:SetEnabled(false)
        -- shows a full-card mouse blocker that intercepts the enable toggle's
        -- clicks, leaving the section permanently grayed out for any user
        -- whose CDMRacials.Enabled defaults to false. Mirrors Card 1 (master
        -- Position Controller enable) which is also intentionally unregistered.
        -- Only the dependent widgets (slider + note) are gated below.

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

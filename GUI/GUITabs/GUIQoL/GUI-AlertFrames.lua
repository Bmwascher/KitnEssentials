-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-AlertFrames.lua                                     ║
-- ║  GUI: Alert Frames                                       ║
-- ║  Purpose: Configuration panel for the                    ║
-- ║           AlertFrames module.                            ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("AlertFrames", true)
    end
    return nil
end

GUIFrame:RegisterContent("AlertFrames", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.AlertFrames
    if not db then return yOffset end

    local AF = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()
    manager:SetCondition("toasts", function() return db.MoveEventToasts == true end)

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    local function ApplyState(enabled)
        if not AF then return end
        db.Enabled = enabled
        if enabled then KitnEssentials:EnableModule("AlertFrames")
        else KitnEssentials:DisableModule("AlertFrames") end
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Alert Frames", yOffset)
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        ApplyState(checked)
        -- The AdjustAnchors replacements and hooksecurefunc hooks this module
        -- installs cannot be undone (Modules/QoL/AlertFrames.lua header taint
        -- note): turning the toggle off would otherwise leave the toast stack
        -- overridden by a module that reports itself off.
        if not checked then
            KE:CreateReloadPrompt("Turning off the alert anchor requires a UI reload to give the toasts back to Blizzard.")
        end
        KE:Print("Alert Frames: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
    end)

    local noteHeight = 70
    local noteRow = GUIFrame:CreateRow(card1.content, noteHeight)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") ..
        " Moves the whole Blizzard toast stack — loot, achievements, dungeon " ..
        "completion — to a spot you choose. The stack grows upward when the " ..
        "anchor is in the lower half of the screen and downward when it is in " ..
        "the upper half. Use /kes edit to drag it. Turning it off needs a reload.",
        noteHeight, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, noteHeight, 0)

    yOffset = card1:GetNextOffset()

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if db.Enabled == false then return yOffset end

    ----------------------------------------------------------------
    -- Card 2: Alert Stack Position
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Alert Stack Position",
        db = db,
        dbKeys = {
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
        },
        showAnchorFrameType = true,
        showStrata = true,
        onChangeCallback = function()
            if AF then AF:ApplyPosition() end
        end,
    })

    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    manager:Register(posCard, "all")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 3: Event Toasts
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Event Toasts", yOffset)
    manager:Register(card3, "all")

    local row3 = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local moveToastsCheck = GUIFrame:CreateCheckbox(row3, "Move Recipe and Level-Up Banners", {
        value = db.MoveEventToasts == true,
        callback = function(checked)
            db.MoveEventToasts = checked
            if AF then AF:ApplySettings() end
            RefreshStates()
        end,
    })
    row3:AddWidget(moveToastsCheck, 1)
    manager:Register(moveToastsCheck, "all")
    card3:AddRow(row3, Theme.rowHeightLast, 0)

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Event Toast Position
    ----------------------------------------------------------------
    -- positionKey routes this card at db.EventToastPosition instead of the
    -- default db.Position (Card 2's table) -- GUI-PositionCard.lua:226,245.
    -- Root keys (anchorFrameType/ParentFrame/Strata) live at the db ROOT
    -- regardless of positionKey (GUI-PositionCard.lua:456-460), so they also
    -- need their own names or this card would still clobber Card 2's anchor
    -- type/parent/strata. Fix round 1 finding: db.EventToastPosition is
    -- already seeded by Task 1's defaults (Core/Defaults.lua:1276-1291), and
    -- the three EventToast* root keys are plain scalars that default safely
    -- to "SCREEN"/"HIGH" when unset (GUI-PositionCard.lua:492,522) the same
    -- way Card 2's un-seeded root keys already do -- so no Core/Defaults.lua
    -- change is needed for either. Same shape as HealerMana's Raid/Dungeon
    -- split (GUI-HealerMana.lua:151-161).
    local toastPosCard, toastPosOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Event Toast Position",
        db = db,
        positionKey = "EventToastPosition",
        dbKeys = {
            anchorFrameType = "EventToastAnchorFrameType",
            anchorFrameFrame = "EventToastParentFrame",
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
            strata = "EventToastStrata",
        },
        showAnchorFrameType = true,
        showStrata = true,
        onChangeCallback = function()
            if AF then AF:ApplyEventToastPosition() end
        end,
    })

    if toastPosCard.positionWidgets then
        manager:RegisterGroup(toastPosCard.positionWidgets, "toasts")
    end
    manager:Register(toastPosCard, "toasts")
    yOffset = toastPosOffset

    RefreshStates()
    return yOffset
end)

-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-AlertFrames.lua                                     ║
-- ║  GUI: Alert Frames                                       ║
-- ║  Purpose: Configuration panel for the AlertFrames        ║
-- ║           module, an Elements sub-tab of Dark Theme.     ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("AlertFrames", true)
    end
    return nil
end

GUIFrame:RegisterContent("SkinBlizzardFramesAlertFrames", function(scrollChild, yOffset)
    local afDB = KE.db and KE.db.profile.AlertFrames
    if not afDB then return yOffset end

    local AF = GetModule()
    local afManager = GUIFrame:CreateWidgetStateManager()
    afManager:SetCondition("toasts", function() return afDB.MoveEventToasts == true end)

    local function RefreshAFStates()
        afManager:UpdateAll(afDB.Enabled ~= false)
    end

    local function ApplyState(enabled)
        if not AF then return end
        afDB.Enabled = enabled
        if enabled then KitnEssentials:EnableModule("AlertFrames")
        else KitnEssentials:DisableModule("AlertFrames") end
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local afCard1 = GUIFrame:CreateCard(scrollChild, "Alert Frames", yOffset)
    afCard1:AddHeaderToggle(afDB.Enabled ~= false, function(checked)
        afDB.Enabled = checked
        ApplyState(checked)
        -- The AdjustAnchors replacements and hooksecurefunc hooks this module
        -- installs cannot be undone (Modules/QoL/AlertFrames.lua header taint
        -- note): turning the toggle off would otherwise leave the toast stack
        -- overridden by a module that reports itself off.
        if not checked then
            KE:CreateReloadPrompt("Turning off the alert anchor requires a UI reload to give the toasts back to Blizzard.")
        end
    end)

    afCard1:AddLabel("Moves the whole Blizzard toast stack, loot, achievements, dungeon completion, " ..
        "to a spot you choose. The stack grows upward when the anchor is in the lower half of the " ..
        "screen and downward when it is in the upper half. Use |cffffd100/kes edit|r to drag it. " ..
        "Turning it off needs a reload.")

    yOffset = afCard1:GetNextOffset()

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if afDB.Enabled == false then return yOffset end

    ----------------------------------------------------------------
    -- Card 2: Alert Stack Position
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Alert Stack Position",
        db = afDB,
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
        afManager:RegisterGroup(posCard.positionWidgets, "all")
    end
    afManager:Register(posCard, "all")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 3: Event Toasts
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Event Toasts", yOffset)
    afManager:Register(card3, "all")
    card3:AddHeaderToggle(afDB.MoveEventToasts == true, function(checked)
        afDB.MoveEventToasts = checked
        if AF then AF:ApplySettings() end
        -- Decides whether Edit Mode shows the Event Toasts mover.
        if KE.EditMode then KE.EditMode:RefreshLiveState() end
    end)
    if afDB.MoveEventToasts == true then
        card3:AddLabel("Moves recipe and level-up banners on their own, away from the toast stack.")
    end

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Event Toast Position
    ----------------------------------------------------------------
    -- positionKey routes this card at db.EventToastPosition instead of the
    -- default db.Position, which is Card 2's table. Root keys
    -- (anchorFrameType/ParentFrame/Strata) live at the db ROOT regardless of
    -- positionKey, so they also need their own names or this card would still
    -- clobber Card 2's anchor type, parent and strata. The three EventToast*
    -- root keys are plain scalars that default safely to "SCREEN"/"HIGH" when
    -- unset, the same way Card 2's un-seeded root keys already do.
    local toastPosCard, toastPosOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Event Toast Position",
        db = afDB,
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
        afManager:RegisterGroup(toastPosCard.positionWidgets, "toasts")
    end
    afManager:Register(toastPosCard, "toasts")
    yOffset = toastPosOffset

    RefreshAFStates()
    return yOffset
end)

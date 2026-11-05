-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-Scout.lua                                           ║
-- ║  GUI: Scout                                              ║
-- ║  Purpose: Configuration panel for the Scout module.      ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("Scout", true)
    end
    return nil
end

GUIFrame:RegisterContent("Scout", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.Scout
    if not db then return yOffset end

    local Rules = KE.ScoutRules
    local Scout = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if Scout then Scout:ApplySettings() end
    end

    local function ApplyState(enabled)
        if not Scout then return end
        if enabled then KitnEssentials:EnableModule("Scout")
        else KitnEssentials:DisableModule("Scout") end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    local function BoxPick(label, key, tooltip)
        return {
            label = label,
            config = {
                value = db[key] == true,
                tooltip = tooltip,
                callback = function(checked)
                    db[key] = checked
                    ApplySettings()
                    RefreshStates()
                end,
            },
        }
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Scout", yOffset)
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        ApplyState(checked)
    end)
    card1:AddLabel("Adds what a mob can do to its tooltip, so you can plan the pull: its abilities, what they " ..
        "do to you, how much of your physical damage its armor takes, and what it is immune to." ..
        "\n\nThe lines come from a table of about 5,100 creatures shipped with KitnEssentials. A mob missing " ..
        "from the table shows an armor estimate and nothing else, which does not mean it has no abilities. " ..
        "Armor, resists, immunities, taming and many of the abilities come from older game data that has not " ..
        "been checked against Forever, so a mob can differ from its lines.")
    yOffset = card1:GetNextOffset()

    if db.Enabled == false then return yOffset end

    ----------------------------------------------------------------
    -- Card 2: Show In
    ----------------------------------------------------------------
    local cardShow = GUIFrame:CreateCard(scrollChild, "Show In", yOffset)
    manager:Register(cardShow, "all")

    local showPicks = {}
    for i, box in ipairs(Rules.SHOW_IN) do
        showPicks[i] = BoxPick(box.label, box.key)
    end
    manager:RegisterGroup(cardShow:AddCheckboxGrid(showPicks, { columns = 2 }), "all")
    cardShow:AddNote("Scout works in the open world only. In dungeons and raids the game keeps a mob's identity secret, so Scout has nothing to look up and shows no lines.")
    yOffset = cardShow:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Lines
    ----------------------------------------------------------------
    local isHunter = Scout and Scout.playerClass == "HUNTER"
    local familyTip = not isHunter and "Only hunters see the pet family row." or nil

    local cardLines = GUIFrame:CreateCard(scrollChild, "Lines", yOffset)
    manager:Register(cardLines, "all")

    local lineCells = cardLines:AddCheckboxGrid({
        BoxPick("Abilities", "Abilities"),
        BoxPick("Control Words on Abilities", "ControlWords"),
        BoxPick("Armor and Your Damage", "Armor"),
        BoxPick("Immunities and Resists", "Immunities"),
        BoxPick("Pet Family (Hunters)", "PetFamily", familyTip),
    }, { columns = 2, isLast = true })
    manager:Register(lineCells[1], "all")
    manager:Register(lineCells[2], "abilities")
    manager:Register(lineCells[3], "all")
    manager:Register(lineCells[4], "all")
    manager:Register(lineCells[5], "hunter")
    yOffset = cardLines:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Ability Details
    ----------------------------------------------------------------
    local cardDetails = GUIFrame:CreateCard(scrollChild, "Ability Details", yOffset)
    manager:Register(cardDetails, "all")

    local row = GUIFrame:CreateRow(cardDetails.content, Theme.rowHeight)
    local keyDropdown = GUIFrame:CreateDropdown(row, "Details Key", {
        options = Rules.DETAILS_KEYS,
        value = db.DetailsKey,
        callback = function(key)
            db.DetailsKey = key
            ApplySettings()
        end,
    })
    row:AddWidget(keyDropdown, 0.5)
    manager:Register(keyDropdown, "details")

    local positionDropdown = GUIFrame:CreateDropdown(row, "Details Position", {
        options = Rules.DETAILS_POSITIONS,
        value = db.DetailsPosition,
        tooltip = "The block goes to the other side only when it would run off the screen.",
        callback = function(position)
            db.DetailsPosition = position
            ApplySettings()
        end,
    })
    row:AddWidget(positionDropdown, 0.5)
    manager:Register(positionDropdown, "details")
    cardDetails:AddRow(row, Theme.rowHeight)

    local hintRow = GUIFrame:CreateRow(cardDetails.content, Theme.rowHeightLast)
    local hintCheck = GUIFrame:CreateCheckbox(hintRow, "Key Hint in the Abilities Line", {
        value = db.KeyHint == true,
        callback = function(checked)
            db.KeyHint = checked
            ApplySettings()
        end,
    })
    hintRow:AddWidget(hintCheck, 0.5)
    manager:Register(hintCheck, "abilities")

    cardDetails:AddRow(hintRow, Theme.rowHeightLast, 0)
    yOffset = cardDetails:GetNextOffset()

    manager:SetCondition("abilities", function() return db.Abilities == true end)
    manager:SetCondition("details", function() return db.Abilities == true or db.Immunities == true end)
    manager:SetCondition("hunter", function() return isHunter end)
    RefreshStates()

    return yOffset
end)

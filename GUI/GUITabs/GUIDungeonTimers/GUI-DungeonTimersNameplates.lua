-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-DungeonTimersNameplates.lua                         ║
-- ║  DTimers_Nameplates page — the Dungeon Trash Tracker's   ║
-- ║  master enable + on-nameplate cooldown-icon settings.    ║
-- ║                                                          ║
-- ║  The trash tracker is its own module (DungeonTrash),     ║
-- ║  separate from the BigWigs-driven boss timers, but it    ║
-- ║  lives under the same sidebar section. This page owns    ║
-- ║  the base "Nameplates" configuration; per-dungeon trash  ║
-- ║  ability tuning lives on each dungeon's own page.        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame

local pairs = pairs

-- LEFT/RIGHT = which side of the plate the icon row grows toward. Array form
-- preserves dropdown order (hash form is pairs()-iterated and unordered).
local ANCHOR_SIDE_OPTIONS = {
    { key = "LEFT",  text = "Left of plate" },
    { key = "RIGHT", text = "Right of plate" },
}

local function GetTrashDB()
    if not KE.db or not KE.db.profile then return nil end
    return KE.db.profile.DungeonTrash
end

local function GetTrashModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("DungeonTrash", true)
    end
    return nil
end

-- Repaint any live on-plate markers AND the in-page preview so slider/dropdown
-- edits show up at once. Outside an instance there are no tracked plates, so the
-- marker pass is a no-op — but the preview still updates live, and the settings
-- persist for the next pull.
local function RefreshMarkers()
    local mod = GetTrashModule()
    if not mod then return end
    if mod.tracked and mod.UpdateNameplateMarker then
        for unit in pairs(mod.tracked) do
            mod:UpdateNameplateMarker(unit)
        end
    end
    if mod.RefreshNameplatePreview then mod:RefreshNameplatePreview() end
end

GUIFrame:RegisterContent("DTimers_Nameplates", function(scrollChild, yOffset)
    local Theme = KE.Theme
    local db = GetTrashDB()
    if not db then return yOffset end
    if not db.Nameplate then db.Nameplate = {} end
    local npc = db.Nameplate

    ---------------------------------------------------------------------------
    -- Card 1: Enable — the trash tracker is a standalone module, toggled live
    -- (OnEnable/OnDisable register/tear down the nameplate monitor cleanly, so
    -- no reload is needed).
    ---------------------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Dungeon Trash Tracker", yOffset)
    card1:AddLabel("Watches enemy nameplates in 5-player dungeons and predicts when trash mobs will re-cast key abilities, shown as countdown alerts and on-plate cooldown icons.")

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Trash Tracker", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            if KitnEssentials then
                if checked then
                    KitnEssentials:EnableModule("DungeonTrash")
                else
                    KitnEssentials:DisableModule("DungeonTrash")
                end
            end
        end,
        msgPopup = true,
        msgText = "Trash Tracker",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, Theme.rowHeightLast, 0)
    yOffset = card1:GetNextOffset()

    local isModuleDisabled = db.Enabled == false
    local manager = GUIFrame:CreateWidgetStateManager()

    ---------------------------------------------------------------------------
    -- Preview: a static in-page sample — a stand-in plate sized to the player's
    -- detected nameplate addon, with the REAL icon factory + layout drawn beside
    -- it. Rebuilt live by RefreshMarkers() on every icon setting below.
    ---------------------------------------------------------------------------
    local FRIENDLY_ADDON = {
        BLIZZARD   = "Blizzard default",
        PLATER     = "Plater",
        EUI        = "EllesmereUI Nameplates",
        PLATYNATOR = "Platynator",
    }
    local previewCard = GUIFrame:CreateCard(scrollChild, "Preview", yOffset)
    manager:Register(previewCard, "all")

    local previewHost = CreateFrame("Frame", nil, previewCard.content)
    previewHost:SetHeight(84)
    previewCard:AddRow(previewHost, 84)

    local previewMod = GetTrashModule()
    local detectedName = FRIENDLY_ADDON.BLIZZARD
    if previewMod and previewMod.BuildNameplatePreview then
        detectedName = FRIENDLY_ADDON[previewMod:BuildNameplatePreview(previewHost)] or detectedName
    end
    previewCard:AddLabel("Reflects your nameplate addon: |cffffffff" .. detectedName
        .. "|r. Icon size, spacing, side and offset are accurate; the bar is a static stand-in, not a live copy of your resized bar.")
    yOffset = previewCard:GetNextOffset()

    ---------------------------------------------------------------------------
    -- Card 2: Nameplate Icons — size/layout of the per-cast cooldown icons.
    ---------------------------------------------------------------------------
    local iconCard = GUIFrame:CreateCard(scrollChild, "Nameplate Icons", yOffset)
    manager:Register(iconCard, "all")

    local iconRow1 = GUIFrame:CreateRow(iconCard.content, Theme.rowHeight)
    local showCheck = GUIFrame:CreateCheckbox(iconRow1, "Show cooldown icons on nameplates", {
        value = npc.ShowIcons ~= false,
        callback = function(checked) npc.ShowIcons = checked; RefreshMarkers() end,
    })
    iconRow1:AddWidget(showCheck, 1)
    iconCard:AddRow(iconRow1, Theme.rowHeight)

    local iconRow2 = GUIFrame:CreateRow(iconCard.content, Theme.rowHeight)
    local sizeSlider = GUIFrame:CreateSlider(iconRow2, "Icon Size", {
        min = 16, max = 64, step = 1,
        value = npc.IconSize or 32,
        labelWidth = 70,
        callback = function(val) npc.IconSize = val; RefreshMarkers() end,
    })
    iconRow2:AddWidget(sizeSlider, 0.5)
    local fontSlider = GUIFrame:CreateSlider(iconRow2, "Count Font Size", {
        min = 8, max = 28, step = 1,
        value = npc.CountFontSize or 14,
        labelWidth = 110,
        callback = function(val) npc.CountFontSize = val; RefreshMarkers() end,
    })
    iconRow2:AddWidget(fontSlider, 0.5)
    iconCard:AddRow(iconRow2, Theme.rowHeight)

    local iconRow3 = GUIFrame:CreateRow(iconCard.content, Theme.rowHeight)
    local sideDropdown = GUIFrame:CreateDropdown(iconRow3, "Grow Direction", {
        options = ANCHOR_SIDE_OPTIONS,
        value = npc.AnchorSide or "LEFT",
        callback = function(key) npc.AnchorSide = key; RefreshMarkers() end,
    })
    iconRow3:AddWidget(sideDropdown, 0.5)
    local gapSlider = GUIFrame:CreateSlider(iconRow3, "Icon Gap", {
        min = 0, max = 24, step = 1,
        value = npc.Gap or 8,
        labelWidth = 70,
        callback = function(val) npc.Gap = val; RefreshMarkers() end,
    })
    iconRow3:AddWidget(gapSlider, 0.5)
    iconCard:AddRow(iconRow3, Theme.rowHeight)

    local iconRow4 = GUIFrame:CreateRow(iconCard.content, Theme.rowHeightLast)
    local offXSlider = GUIFrame:CreateSlider(iconRow4, "Offset X", {
        min = -100, max = 100, step = 1,
        value = npc.OffsetX or 0,
        labelWidth = 70,
        callback = function(val) npc.OffsetX = val; RefreshMarkers() end,
    })
    iconRow4:AddWidget(offXSlider, 0.5)
    local offYSlider = GUIFrame:CreateSlider(iconRow4, "Offset Y", {
        min = -100, max = 100, step = 1,
        value = npc.OffsetY or 0,
        labelWidth = 70,
        callback = function(val) npc.OffsetY = val; RefreshMarkers() end,
    })
    iconRow4:AddWidget(offYSlider, 0.5)
    iconCard:AddRow(iconRow4, Theme.rowHeightLast, 0)
    yOffset = iconCard:GetNextOffset()

    ---------------------------------------------------------------------------
    -- Card 3: Ready Highlight — border tint flashed when a cast is due.
    ---------------------------------------------------------------------------
    local readyCard = GUIFrame:CreateCard(scrollChild, "Ready Highlight", yOffset)
    manager:Register(readyCard, "all")
    readyCard:AddLabel("Border color flashed on an icon the moment its predicted cast comes due.")

    local readyRow = GUIFrame:CreateRow(readyCard.content, Theme.rowHeightLast)
    local bc = npc.BorderColor or { 0.2, 0.85, 0.2, 1 }
    local colorPicker = GUIFrame:CreateColorPicker(readyRow, "Ready Border", {
        color = { bc[1], bc[2], bc[3], bc[4] or 1 },
        callback = function(r, g, b, a)
            npc.BorderColor = { r, g, b, a or 1 }
            RefreshMarkers()
        end,
        tooltip = "Color of an icon's border when its predicted cast is imminent.",
    })
    readyRow:AddWidget(colorPicker, 1)
    readyCard:AddRow(readyRow, Theme.rowHeightLast, 0)
    yOffset = readyCard:GetNextOffset()

    manager:UpdateAll(not isModuleDisabled)
    return yOffset
end)

-- Hide the in-page sample when leaving this page or closing the GUI (fires on a
-- real sidebar item switch). The persistent preview frames are reparented back
-- in on the next visit via BuildNameplatePreview.
GUIFrame:RegisterContentCleanup("DTimers_Nameplates_preview", function()
    local mod = GetTrashModule()
    if mod and mod.HideNameplatePreview then mod:HideNameplatePreview() end
end)

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

-- Where the icon row anchors on the plate. The row always grows AWAY from the
-- plate (never inside the bar), so the anchor implies the grow direction:
-- Left/Right grow outward to that side, Top centres a row above. Array form
-- preserves dropdown order (hash form is pairs()-iterated and unordered).
local ANCHOR_SIDE_OPTIONS = {
    { key = "LEFT",  text = "Left" },
    { key = "RIGHT", text = "Right" },
    { key = "TOP",   text = "Top" },
}

-- Frame strata for the on-plate icon markers — which UI layer they draw on.
-- Mirrors the canonical KE strata list (GUI-PositionCard) so the choices match
-- the rest of the addon; default is Medium (db.Nameplate.Strata).
local STRATA_OPTIONS = {
    { key = "TOOLTIP",           text = "Tooltip" },
    { key = "FULLSCREEN_DIALOG", text = "Fullscreen Dialog" },
    { key = "FULLSCREEN",        text = "Fullscreen" },
    { key = "DIALOG",            text = "Dialog" },
    { key = "HIGH",              text = "High" },
    { key = "MEDIUM",            text = "Medium" },
    { key = "LOW",               text = "Low" },
    { key = "BACKGROUND",        text = "Background" },
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
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        if KitnEssentials then
            if checked then
                KitnEssentials:EnableModule("DungeonTrash")
            else
                KitnEssentials:DisableModule("DungeonTrash")
            end
        end
        KE:Print("Trash Tracker: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
    end)

    yOffset = card1:GetNextOffset()

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if db.Enabled == false then return yOffset end

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
    previewHost:SetHeight(116)
    previewCard:AddRow(previewHost, 116)

    local previewMod = GetTrashModule()
    local detectedName = FRIENDLY_ADDON.BLIZZARD
    if previewMod and previewMod.BuildNameplatePreview then
        detectedName = FRIENDLY_ADDON[previewMod:BuildNameplatePreview(previewHost)] or detectedName
    end
    previewCard:AddLabel("Reflects your nameplate addon: |cffffffff" .. detectedName
        .. "|r — a stand-in plate (health bar, name and cast bar). For Plater and EllesmereUI the bar is sized from your saved profile; other addons use a representative default. Icon size, spacing, side and offset are drawn by the real layout — only the plate skin itself is a static stand-in.")
    yOffset = previewCard:GetNextOffset()

    ---------------------------------------------------------------------------
    -- Card 2: Cooldown Icons — whether to show them, and their size/count font.
    ---------------------------------------------------------------------------
    local iconCard = GUIFrame:CreateCard(scrollChild, "Cooldown Icons", yOffset)
    manager:Register(iconCard, "all")

    local iconRow1 = GUIFrame:CreateRow(iconCard.content, Theme.rowHeight)
    local showCheck = GUIFrame:CreateCheckbox(iconRow1, "Show cooldown icons on nameplates", {
        value = npc.ShowIcons ~= false,
        callback = function(checked) npc.ShowIcons = checked; RefreshMarkers() end,
    })
    iconRow1:AddWidget(showCheck, 1)
    iconCard:AddRow(iconRow1, Theme.rowHeight)

    local iconRow2 = GUIFrame:CreateRow(iconCard.content, Theme.rowHeightLast)
    local sizeSlider = GUIFrame:CreateSlider(iconRow2, "Icon Size", {
        min = 16, max = 64, step = 1,
        value = npc.IconSize or 32,
        labelWidth = 70,
        callback = function(val) npc.IconSize = val; RefreshMarkers() end,
    })
    iconRow2:AddWidget(sizeSlider, 0.5)
    local fontSlider = GUIFrame:CreateSlider(iconRow2, "Timer Text Size", {
        min = 8, max = 28, step = 1,
        value = npc.CountFontSize or 14,
        labelWidth = 100,
        callback = function(val) npc.CountFontSize = val; RefreshMarkers() end,
    })
    iconRow2:AddWidget(fontSlider, 0.5)
    iconCard:AddRow(iconRow2, Theme.rowHeightLast, 0)
    yOffset = iconCard:GetNextOffset()

    ---------------------------------------------------------------------------
    -- Card 3: Placement — where the icon row anchors on the plate, its spacing,
    -- and a fine nudge. The row always grows AWAY from the plate, so the anchor
    -- alone sets the grow direction (it can't overlap the bar).
    ---------------------------------------------------------------------------
    local placeCard = GUIFrame:CreateCard(scrollChild, "Placement", yOffset)
    manager:Register(placeCard, "all")

    local placeRow1 = GUIFrame:CreateRow(placeCard.content, Theme.rowHeight)
    local sideDropdown = GUIFrame:CreateDropdown(placeRow1, "Anchor Location", {
        options = ANCHOR_SIDE_OPTIONS,
        value = npc.AnchorSide or "LEFT",
        callback = function(key) npc.AnchorSide = key; RefreshMarkers() end,
        tooltip = "Where the cooldown-icon row attaches to the plate. The row"
            .. " always grows away from the plate, so it never overlaps the bar:"
            .. " Left/Right grow outward to that side, Top centres a row above.",
    })
    placeRow1:AddWidget(sideDropdown, 0.5)
    local gapSlider = GUIFrame:CreateSlider(placeRow1, "Icon Gap", {
        min = 0, max = 24, step = 1,
        value = npc.Gap or 8,
        labelWidth = 70,
        callback = function(val) npc.Gap = val; RefreshMarkers() end,
    })
    placeRow1:AddWidget(gapSlider, 0.5)
    placeCard:AddRow(placeRow1, Theme.rowHeight)

    local placeRow2 = GUIFrame:CreateRow(placeCard.content, Theme.rowHeightLast)
    local offXSlider = GUIFrame:CreateSlider(placeRow2, "Offset X", {
        min = -100, max = 100, step = 1,
        value = npc.OffsetX or 0,
        labelWidth = 70,
        callback = function(val) npc.OffsetX = val; RefreshMarkers() end,
    })
    placeRow2:AddWidget(offXSlider, 0.5)
    local offYSlider = GUIFrame:CreateSlider(placeRow2, "Offset Y", {
        min = -100, max = 100, step = 1,
        value = npc.OffsetY or 0,
        labelWidth = 70,
        callback = function(val) npc.OffsetY = val; RefreshMarkers() end,
    })
    placeRow2:AddWidget(offYSlider, 0.5)
    placeCard:AddRow(placeRow2, Theme.rowHeightLast, 0)
    yOffset = placeCard:GetNextOffset()

    ---------------------------------------------------------------------------
    -- Card 4: Appearance — which UI layer the icons draw on, and the border
    -- tint flashed the moment a predicted cast comes due.
    ---------------------------------------------------------------------------
    local appearCard = GUIFrame:CreateCard(scrollChild, "Appearance", yOffset)
    manager:Register(appearCard, "all")

    local appearRow = GUIFrame:CreateRow(appearCard.content, Theme.rowHeightLast)
    local strataDropdown = GUIFrame:CreateDropdown(appearRow, "Frame Strata", {
        options = STRATA_OPTIONS,
        value = npc.Strata or "MEDIUM",
        callback = function(key) npc.Strata = key; RefreshMarkers() end,
        tooltip = "Which UI layer the on-plate icons draw on. Lower it (Medium/Low)"
            .. " if the icons cover other UI; raise it (High) to keep them on top.",
    })
    appearRow:AddWidget(strataDropdown, 0.5)
    local bc = npc.BorderColor or { 0.2, 0.85, 0.2, 1 }
    local colorPicker = GUIFrame:CreateColorPicker(appearRow, "Ready Border", {
        color = { bc[1], bc[2], bc[3], bc[4] or 1 },
        callback = function(r, g, b, a)
            npc.BorderColor = { r, g, b, a or 1 }
            RefreshMarkers()
        end,
        tooltip = "Colour flashed on an icon's border the moment its predicted"
            .. " cast is due.",
    })
    appearRow:AddWidget(colorPicker, 0.5)
    appearCard:AddRow(appearRow, Theme.rowHeightLast, 0)
    yOffset = appearCard:GetNextOffset()

    manager:UpdateAll(db.Enabled ~= false)
    return yOffset
end)

-- Hide the in-page sample when SWITCHING away to another sidebar page, so the
-- persistent preview frames don't float over the page you moved to. This fires
-- on both a page switch AND a full GUI close, but we must only act on the
-- former: on a close, mainFrame is already hidden (so nothing shows anyway), and
-- reopening re-shows the cached page content WITHOUT re-running the builder — so
-- a Hide() here would stick and the preview would be gone until you navigated
-- away and back. mainFrame:Hide() runs before this cleanup loop on close, so
-- GUIFrame:IsShown() is the exact discriminator: true = page switch (hide),
-- false = window close (leave it; mainFrame:Show() brings it back).
GUIFrame:RegisterContentCleanup("DTimers_Nameplates_preview", function()
    if not GUIFrame:IsShown() then return end
    local mod = GetTrashModule()
    if mod and mod.HideNameplatePreview then mod:HideNameplatePreview() end
end)

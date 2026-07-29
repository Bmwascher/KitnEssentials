-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-BlizzardFrames.lua                                  ║
-- ║  Purpose: Config page for the Blizzard frame skins.      ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local ipairs = ipairs

local function GetDB()
    return KE.db and KE.db.profile.Skinning.BlizzardFrames
end

-- Key strings must match the LAST string argument of each Register /
-- RegisterEarly call under Modules/Skinning/. A mismatch silently disables
-- nothing -- the gate reads Skins[key] ~= false, so an unknown key is
-- always "on".
--
-- Two entries are not registry skins and carry their own accessors:
-- ContextMenus is an Ace module with its own Enabled flag, and GlobalFonts
-- applies and reverts live instead of on reload. An entry with `isOn` and
-- `onToggle` bypasses the db.Skins read and write entirely.
local FRAME_SKINS = {
    { key = "ChatConfig",   text = "Chat Settings" },
    { key = "ContextMenus", text = "Context Menus (right-click and dropdown menus)",
      isOn = function()
          local db = KE.db and KE.db.profile.Skinning.ContextMenus
          return db and db.Enabled == true or false
      end,
      onToggle = function(checked)
          local db = KE.db and KE.db.profile.Skinning.ContextMenus
          if not db then return false end
          db.Enabled = checked
          if checked then
              KitnEssentials:EnableModule("ContextMenus")
          else
              KitnEssentials:DisableModule("ContextMenus")
          end
          -- Un-skinning needs a reload; the reference flags it one way only.
          return not checked
      end },
    { key = "Dialogs",      text = "Dialog Borders" },
    { key = "GMChat",       text = "GM Chat" },
    { key = "GlobalFonts",  text = "Blizzard Fonts",
      isOn = function()
          local db = GetDB()
          return not (db and db.Skins and db.Skins.GlobalFonts == false)
      end,
      onToggle = function(checked)
          local db = GetDB()
          if not db then return false end
          db.Skins = db.Skins or {}
          if checked then
              db.Skins.GlobalFonts = nil
              if KE.Skins and KE.Skins.ApplyGlobalFonts then
                  KE.Skins.ApplyGlobalFonts()
              end
          else
              db.Skins.GlobalFonts = false
              if KE.Skins and KE.Skins.RestoreGlobalFonts then
                  KE.Skins.RestoreGlobalFonts()
              end
          end
          -- No reload prompt either way. This is the one skin a user turns
          -- off because another addon looks BROKEN, so making them reload to
          -- test it is the wrong experience -- hence RestoreGlobalFonts.
          return false
      end },
    { key = "Guild",        text = "Guild Invite" },
    { key = "Socket",       text = "Item Socketing" },
    { key = "Taxi",         text = "Flight Map" },
}

-- Skins for other addons. Each runs only when its addon is installed.
-- A6.2 fills this in; the table exists now so the tab is not a special case.
local ADDON_SKINS = {}

-- One read path for every row, so a special entry cannot render the wrong
-- state. Without this the ContextMenus row reads db.Skins.ContextMenus --
-- a key nothing ever writes -- and renders ON while the module is OFF.
local function EntryIsOn(entry, skins)
    if entry.isOn then return entry.isOn() end
    return skins[entry.key] ~= false
end

-- One write path, for the same reason. Returns true when a reload prompt
-- is owed, so the caller can raise exactly one for a bulk toggle.
local function SetEntry(entry, skins, checked)
    if entry.onToggle then return entry.onToggle(checked) end
    if checked then skins[entry.key] = nil else skins[entry.key] = false end
    return true
end

local PER_ROW = 2
local CELL_H = 40

-- Renders `entries` as a PER_ROW-wide grid of checkboxes. One column would
-- be unusable at 91 rows.
--
-- A row EllesmereUI has taken over is greyed and made unclickable rather
-- than hidden: the user chose to turn it on, and silently dropping it from
-- the list reads as a missing feature. Their saved choice is left untouched,
-- so it comes back by itself if EllesmereUI stops covering the window.
local function BuildCheckGrid(card, entries, skins)
    local i = 1
    while i <= #entries do
        local isLastRow = (i + PER_ROW) > #entries
        local row = GUIFrame:CreateRow(card.content, CELL_H)
        for c = 0, PER_ROW - 1 do
            local entry = entries[i + c]
            if entry then
                local suppressor = KE.Skins and KE.Skins.suppressed
                    and KE.Skins.suppressed[entry.key]
                local label = entry.text
                if suppressor then
                    label = label .. " |cff888888(EllesmereUI)|r"
                end
                local check = GUIFrame:CreateCheckbox(row, label, {
                    value = EntryIsOn(entry, skins),
                    tooltip = suppressor
                        and "EllesmereUI already skins this window, so KitnEssentials leaves it alone. Turn EllesmereUI's window skin off to use this one."
                        or nil,
                    callback = function(checked)
                        if SetEntry(entry, skins, checked) then
                            KE:SkinningReloadPrompt()
                        end
                        GUIFrame:RefreshContent()
                    end,
                })
                if suppressor then
                    check:SetAlpha(0.35)
                    -- SetEnabled, not EnableMouse. CreateCheckbox returns the
                    -- ROW; the clickable object is a child button, and
                    -- row:SetEnabled is what reaches it
                    -- (GUI/GUIWidgets/GUI-KEToggle.lua:301-310). EnableMouse on
                    -- the row leaves the button live and the row still clicks.
                    check:SetEnabled(false)
                end
                row:AddWidget(check, 1 / PER_ROW)
            end
        end
        if isLastRow then
            card:AddRow(row, CELL_H, 0)
        else
            card:AddRow(row, CELL_H)
        end
        i = i + PER_ROW
    end
end

GUIFrame:RegisterContent("SkinBlizzardFramesGeneral", function(scrollChild, yOffset)
    local db = GetDB()
    if not db then return yOffset end
    local card = GUIFrame:CreateCard(scrollChild, "Global Font Adjust", yOffset)

    local row = GUIFrame:CreateRow(card.content, Theme.rowHeightLast)
    local slider = GUIFrame:CreateSlider(row, "Font Size Adjust", {
        min = -4, max = 6, step = 1, value = db.FontOffset or 0,
        tooltip = "Grows or shrinks every font inside skinned windows together. 0 is the designed look.",
        callback = function(val)
            db.FontOffset = val
            if KE.Skins and KE.Skins.SetFontOffset then KE.Skins.SetFontOffset(val) end
        end,
    })
    row:AddWidget(slider, 1)
    card:AddRow(row, Theme.rowHeightLast)

    local rowB = GUIFrame:CreateRow(card.content, Theme.rowHeightLast)
    local baseSlider = GUIFrame:CreateSlider(rowB, "Blizzard Font Base Size", {
        min = 8, max = 18, step = 1, value = db.FontBaseSize or 12,
        tooltip = "Base size the Blizzard font override scales from. Every font keeps its relative size; this moves them together. 12 is Blizzard's own baseline.",
        callback = function(val)
            db.FontBaseSize = val
            if KE.Skins and KE.Skins.ApplyGlobalFonts then
                KE.Skins.ApplyGlobalFonts()
            end
        end,
    })
    rowB:AddWidget(baseSlider, 1)
    card:AddRow(rowB, Theme.rowHeightLast, 0)

    return card:GetNextOffset()
end)

GUIFrame:RegisterContent("SkinBlizzardFramesFrames", function(scrollChild, yOffset)
    local db = GetDB()
    if not db then return yOffset end
    db.Skins = db.Skins or {}
    local card = GUIFrame:CreateCard(scrollChild, "Frame Skins", yOffset)

    -- Keyed on ANY-on, not all-on. With all-on semantics, unticking a single
    -- frame reads as master-off and collapses the card, hiding the user's
    -- own choices while the remaining skins keep applying.
    local anyOn = false
    for _, entry in ipairs(FRAME_SKINS) do
        if EntryIsOn(entry, db.Skins) then anyOn = true break end
    end

    card:AddHeaderToggle(anyOn, function(checked)
        local needsReload = false
        for _, entry in ipairs(FRAME_SKINS) do
            if SetEntry(entry, db.Skins, checked) then needsReload = true end
        end
        -- One prompt for the whole batch, not one per entry.
        if needsReload then KE:SkinningReloadPrompt() end
    end)

    BuildCheckGrid(card, FRAME_SKINS, db.Skins)

    return card:GetNextOffset()
end)

GUIFrame:RegisterContent("SkinBlizzardFramesAddons", function(scrollChild, yOffset)
    local db = GetDB()
    if not db then return yOffset end
    db.Skins = db.Skins or {}
    local card = GUIFrame:CreateCard(scrollChild, "Addon Skins", yOffset)

    if #ADDON_SKINS == 0 then
        card:AddLabel("No addon skins are available yet.")
        return card:GetNextOffset()
    end

    local anyOn = false
    for _, entry in ipairs(ADDON_SKINS) do
        if EntryIsOn(entry, db.Skins) then anyOn = true break end
    end

    card:AddHeaderToggle(anyOn, function(checked)
        local needsReload = false
        for _, entry in ipairs(ADDON_SKINS) do
            if SetEntry(entry, db.Skins, checked) then needsReload = true end
        end
        if needsReload then KE:SkinningReloadPrompt() end
    end)

    if not anyOn then
        return card:GetNextOffset()
    end

    card:AddLabel("Skins for other addons, applied when that addon loads. Changes apply after a /reload.")
    BuildCheckGrid(card, ADDON_SKINS, db.Skins)
    return card:GetNextOffset()
end)

GUIFrame:RegisterTabbedContent("SkinBlizzardFrames", {
    { id = "SkinBlizzardFramesGeneral", label = "General" },
    { id = "SkinBlizzardFramesFrames",  label = "Frames" },
    { id = "SkinBlizzardFramesAddons",  label = "Addons" },
}, {
    headerBuilder = function(scrollChild, yOffset)
        local db = GetDB()
        if not db then return yOffset, true end
        local card = GUIFrame:CreateCard(scrollChild, "Blizzard Frames", yOffset)
        card:AddHeaderToggle(db.Enabled == true, function(checked)
            db.Enabled = checked
            KE:SkinningReloadPrompt()
            -- AddHeaderToggle's own OnClick already calls RefreshContent.
        end)
        local newOffset = yOffset + card:GetContentHeight() + Theme.paddingSmall
        -- Disabled collapses to the header bar alone: no tab strip, no page.
        return newOffset, db.Enabled ~= true
    end,
})

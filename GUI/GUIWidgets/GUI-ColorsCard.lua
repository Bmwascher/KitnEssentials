-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-ColorsCard.lua                                      ║
-- ║  Purpose: Shared Colors card builder used across GUI     ║
-- ║  pages: color-mode dropdown, source toggles, per-entry   ║
-- ║  color pickers, and an optional note row, plus the       ║
-- ║  KE:ReadCardColor / KE:WriteCardColor read-write pair    ║
-- ║  that stores a colour as a flat {r,g,b,a} DB field.      ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

-- A colour key is a flat field on the profile table. Pages that nest their
-- colours under a parent table are deliberately not routed through this card:
-- writing the parent key would discard its siblings on the first edit.
function KE:ReadCardColor(db, entry)
    local stored = db and db[entry.key]
    local d = entry.default or { 1, 1, 1, 1 }
    if type(stored) == "table" and stored[1] then
        return stored[1], stored[2], stored[3], stored[4] or 1
    end
    return d[1], d[2], d[3], d[4] or 1
end

function KE:WriteCardColor(db, entry, r, g, b, a)
    db[entry.key] = { r, g, b, a }
end

-- config = {
--   db, manager, onChange          (required)
--   stateGroup                     (default "all")
--   colorMode = { key, onChange }   -- no group: see the comment below
--   sources   = { { label, key, default, group, onChange }, ... }
--   colors    = { { label, key, default, group }, ... }   (required, ordered)
--   note      = string
--   isLast    = boolean
--   title     = string             (default "Colors")
-- }
function GUIFrame:CreateColorsCard(scrollChild, yOffset, config)
    local db       = config.db
    local manager  = config.manager
    local group    = config.stateGroup or "all"
    local onChange = config.onChange
    local colors   = config.colors

    local card = GUIFrame:CreateCard(scrollChild, config.title or "Colors", yOffset)
    manager:Register(card, group)

    local function addRow(height, build, padding)
        local row = GUIFrame:CreateRow(card.content, height)
        build(row)
        card:AddRow(row, height, padding)
    end

    if config.colorMode then
        local cm = config.colorMode
        -- The mode dropdown ALWAYS registers under the card group, never under
        -- the group its custom-colour picker uses. Putting it in that group
        -- would grey out the only control that can switch back once the user
        -- picks Theme mode. Every page this replaces registers it the same way.
        addRow(Theme.rowHeight, function(row)
            local dd = GUIFrame:CreateDropdown(row, "Color Mode", {
                options  = KE.ColorModeOptions,
                value    = db[cm.key] or "custom",
                callback = function(key)
                    db[cm.key] = key
                    if onChange then onChange() end
                    if cm.onChange then cm.onChange() end
                end,
            })
            row:AddWidget(dd, 0.5)
            manager:Register(dd, group)
        end)
        addRow(Theme.rowHeightSeparator, function(row)
            local sep = GUIFrame:CreateSeparator(row)
            row:AddWidget(sep, 1)
            manager:Register(sep, group)
        end)
    end

    if config.sources then
        for _, src in ipairs(config.sources) do
            addRow(Theme.rowHeight, function(row)
                -- An explicit nil test, not `a and b or c`: with a stored
                -- false and a default of true, the and/or form collapses to
                -- the default and renders the box checked against the user's
                -- own saved choice.
                local stored = db[src.key]
                if stored == nil then stored = (src.default == true) end
                local check = GUIFrame:CreateCheckbox(row, src.label, {
                    value    = stored,
                    callback = function(checked)
                        db[src.key] = checked
                        if onChange then onChange() end
                        if src.onChange then src.onChange() end
                    end,
                })
                row:AddWidget(check, 1)
                manager:Register(check, src.group or group)
            end)
        end
    end

    -- Two pickers per row; an odd count leaves the right cell empty. The note
    -- row, when present, is the card's real last row.
    local hasNote = config.note ~= nil
    local i = 1
    while i <= #colors do
        local isLastRow = (not hasNote) and (i + 2 > #colors) and config.isLast
        local height = isLastRow and Theme.rowHeightLast or Theme.rowHeight
        addRow(height, function(row)
            for slot = 0, 1 do
                local entry = colors[i + slot]
                if entry then
                    local r, g, b, a = KE:ReadCardColor(db, entry)
                    local picker = GUIFrame:CreateColorPicker(row, entry.label, {
                        color    = { r, g, b, a },
                        callback = function(nr, ng, nb, na)
                            KE:WriteCardColor(db, entry, nr, ng, nb, na)
                            if onChange then onChange() end
                        end,
                    })
                    row:AddWidget(picker, 0.5)
                    manager:Register(picker, entry.group or group)
                end
            end
        end, isLastRow and 0 or nil)
        i = i + 2
    end

    -- Note rows have their own height; the card's ordinary row heights clip a
    -- two-line note.
    if hasNote then
        addRow(Theme.rowHeightNote, function(row)
            local text = GUIFrame:CreateText(row,
                KE:ColorTextByTheme("Note"), config.note, Theme.rowHeightNote, "hide")
            row:AddWidget(text, 1)
            manager:Register(text, group)
        end, config.isLast and 0 or nil)
    end

    return card:GetNextOffset()
end

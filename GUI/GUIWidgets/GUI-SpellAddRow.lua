-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-SpellAddRow.lua                                     ║
-- ║  Purpose: The shared spell id add/remove row, and the    ║
-- ║           inline icon spell and spec lists use.          ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local type = type

-- The edit box and the dropdown draw their 24 px field 14 px under the label;
-- the buttons sit level with that field.
local FIELD_TOP = -14
local BUTTON_H = 24

-- An icon at text size, cropped like the spec icons. The dropdown's search
-- strips |T, so the icon never reaches a query.
function GUIFrame.IconText(texture)
    if not texture then return "" end
    return "|T" .. texture .. ":16:16:0:0:64:64:5:59:5:59|t "
end

-- Config: { picker = { label, options, value, callback } or nil, idLabel,
-- onAdd(text), onRemove(text) }. Returns the row and its edit box; the caller
-- adds the row to its card.
function GUIFrame:CreateSpellAddRow(parent, config)
    if type(config) ~= "table" then config = {} end
    local row = GUIFrame:CreateRow(parent, Theme.rowHeight)
    local picker = config.picker
    if picker then
        row:AddWidget(GUIFrame:CreateDropdown(row, picker.label or "Spec", {
            options = picker.options or {},
            value = picker.value,
            callback = picker.callback,
        }), 0.3)
    end
    local idBox = GUIFrame:CreateEditBox(row, config.idLabel or "Spell ID", { value = "" })
    row:AddWidget(idBox, picker and 0.3 or 0.6)
    row:AddWidget(GUIFrame:CreateButton(row, "Add", {
        height = BUTTON_H,
        callback = function()
            if config.onAdd then config.onAdd(idBox:GetValue()) end
        end,
    }), 0.2, nil, 0, FIELD_TOP)
    row:AddWidget(GUIFrame:CreateButton(row, "Remove", {
        height = BUTTON_H,
        callback = function()
            if config.onRemove then config.onRemove(idBox:GetValue()) end
        end,
    }), 0.2, nil, 0, FIELD_TOP)
    return row, idBox
end

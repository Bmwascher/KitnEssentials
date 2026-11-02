-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-ClassSpellRows.lua                                  ║
-- ║  Purpose: One row per class, its name and ticked count   ║
-- ║           beside its spells, three checkboxes a line.    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local CreateFrame = CreateFrame
local ipairs = ipairs
local math_min = math.min
local table_sort = table.sort

local Rows = {}
KE.ClassSpellRows = Rows

local PER_LINE = 3
local NAME_SHARE = 0.2
-- The compact checkbox's disabled alpha, so a grayed class row reads as one.
local DIM_ALPHA = 0.35

local function ConstructClassName(parent)
    local cell = CreateFrame("Frame", nil, parent)
    local text = cell:CreateFontString(nil, "OVERLAY")
    text:SetPoint("LEFT", cell, "LEFT", 0, 0)
    text:SetPoint("RIGHT", cell, "RIGHT", 0, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    cell._text = text

    function cell:SetEnabled(enabled)
        self:SetAlpha(enabled and 1 or DIM_ALPHA)
    end

    cell._keOwned = { cell }
    return cell
end

GUIFrame:NewWidgetPool("kc:classname", ConstructClassName, function() end)

local function NameCell(row)
    local cell = GUIFrame:AcquirePooled("kc:classname", row)
    local text = cell._text
    KE:ApplyThemeFont(text, (Theme.fontSizeSmall or 11) + 1)
    text:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
    text:SetText("")
    cell:SetEnabled(true)
    return cell
end

local function ClassName(token)
    local names = _G.LOCALIZED_CLASS_NAMES_MALE
    return (names and names[token]) or token
end

local function NameText(group)
    local ticked = 0
    for _, check in ipairs(group.cells) do
        if check:GetChecked() then ticked = ticked + 1 end
    end
    return KE:ColorTextByClass(group.name, group.class) .. "  " .. ticked .. "/" .. #group.cells
end

-- picks: { class, label, value, onChange } each, in the order a class lists
-- its spells. Classes run by name. Returns every widget, for the caller's
-- state manager.
function Rows.Add(card, picks)
    local groups, byClass = {}, {}
    for _, pick in ipairs(picks) do
        local group = byClass[pick.class]
        if not group then
            group = { class = pick.class, name = ClassName(pick.class), picks = {}, cells = {} }
            byClass[pick.class] = group
            groups[#groups + 1] = group
        end
        group.picks[#group.picks + 1] = pick
    end
    table_sort(groups, function(a, b) return a.name < b.name end)

    local widgets = {}
    local height, gap = GUIFrame.CheckboxRowHeight, GUIFrame.CheckboxRowGap
    for _, group in ipairs(groups) do
        local count = #group.picks
        local nameCell
        for first = 1, count, PER_LINE do
            local row = GUIFrame:CreateRow(card.content, height)
            -- A continuation line keeps an empty name cell so the columns line up.
            local cell = NameCell(row)
            nameCell = nameCell or cell
            row:AddWidget(cell, NAME_SHARE)
            widgets[#widgets + 1] = cell
            for i = first, math_min(first + PER_LINE - 1, count) do
                local pick = group.picks[i]
                local check = GUIFrame:CreateCompactCheckbox(row, pick.label, {
                    value = pick.value,
                    callback = function(checked)
                        nameCell._text:SetText(NameText(group))
                        pick.onChange(checked)
                    end,
                })
                row:AddWidget(check, (1 - NAME_SHARE) / PER_LINE)
                group.cells[#group.cells + 1] = check
                widgets[#widgets + 1] = check
            end
            card:AddRow(row, height, first + PER_LINE > count and Theme.paddingSmall or gap)
        end
        nameCell._text:SetText(NameText(group))
    end
    return { widgets = widgets }
end

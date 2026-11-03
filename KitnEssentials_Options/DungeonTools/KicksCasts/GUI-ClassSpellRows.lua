-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-ClassSpellRows.lua                                  ║
-- ║  Purpose: One row per class, its name and ticked count   ║
-- ║           beside its spells, three checkboxes a line;    ║
-- ║           and the click-then-move icon order strip.      ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local C_Spell = C_Spell
local CreateFrame = CreateFrame
local GameTooltip = GameTooltip
local ipairs = ipairs
local math_min = math.min
local pcall = pcall
local table_sort = table.sort
local type = type

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

-- picks: { class, label, value, onChange, tooltip } each, in the order a
-- class lists its spells; tooltip is optional. Classes run by name. Returns
-- every widget, for the caller's state manager.
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
                    tooltip = pick.tooltip,
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

-- The icon order strip. A 24 px icon, its pick ring 1 px outside it and 2 px
-- thick; the pitch leaves the ring clear of the next icon.
local STRIP_ICON = 24
local STRIP_PITCH = 30
local STRIP_INSET = 3
local NO_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local EDGE = "Interface\\Buttons\\WHITE8X8"

Rows.STRIP_ROW_HEIGHT = 30

local function SpellName(id)
    local ok, name = pcall(C_Spell.GetSpellName, id)
    if ok and type(name) == "string" then return name end
    return "Spell " .. id
end

local function SpellIcon(id)
    local ok, icon = pcall(C_Spell.GetSpellTexture, id)
    if ok then return icon end
    return nil
end

Rows.SpellName, Rows.SpellIcon = SpellName, SpellIcon

-- One slot per listed spell, all made here: a pooled object that grows parts
-- after it is built fails its release check.
local function ConstructOrderStrip(parent, count, pitch)
    local strip = CreateFrame("Frame", nil, parent)
    strip:SetSize(2 * STRIP_INSET + count * pitch - (pitch - STRIP_ICON), Rows.STRIP_ROW_HEIGHT)
    local slots, owned = {}, { strip }

    for i = 1, count do
        local slot = CreateFrame("Button", nil, strip)
        slot:SetSize(STRIP_ICON, STRIP_ICON)
        slot:SetPoint("TOPLEFT", strip, "TOPLEFT", STRIP_INSET + (i - 1) * pitch, -STRIP_INSET)

        local edge = slot:CreateTexture(nil, "BACKGROUND")
        edge:SetAllPoints(slot)
        edge:SetColorTexture(0, 0, 0, 1)

        local icon = slot:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", slot, "TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -1, 1)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        slot.icon = icon

        local highlight = slot:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints(icon)
        slot.highlight = highlight

        local ring = CreateFrame("Frame", nil, slot, "BackdropTemplate")
        ring:SetPoint("TOPLEFT", slot, "TOPLEFT", -STRIP_INSET, STRIP_INSET)
        ring:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", STRIP_INSET, -STRIP_INSET)
        ring:SetBackdrop({ edgeFile = EDGE, edgeSize = 2 })
        ring:EnableMouse(false)
        ring:Hide()
        slot.ring = ring

        slot:SetScript("OnClick", function(self)
            local onPick = strip._onPick
            if onPick and self.id then onPick(self.id) end
        end)
        slot:SetScript("OnEnter", function(self)
            if not self.id then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(SpellName(self.id), 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        slot:SetScript("OnLeave", function() GameTooltip:Hide() end)

        slots[i] = slot
        owned[#owned + 1] = slot
    end

    -- ids in on-screen order; picked gets the ring; onPick(id) on a click.
    function strip:Configure(ids, picked, onPick)
        self._onPick = onPick
        local accent = Theme.accent
        for i, slot in ipairs(slots) do
            local id = ids[i]
            slot.id = id
            if id then
                slot.icon:SetTexture(SpellIcon(id) or NO_ICON)
                slot.highlight:SetColorTexture(accent[1], accent[2], accent[3], 0.3)
                slot.ring:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
                slot.ring:SetShown(id == picked)
                slot:Show()
            else
                slot:Hide()
            end
        end
    end

    strip._keOwned = owned
    return strip
end

local function ResetOrderStrip(strip)
    strip._onPick = nil
end

local stripPools = {}

-- The pool is made on the first call for kind, so a page file loaded before
-- this one can use it; count and pitch are fixed from then on.
function Rows.AcquireOrderStrip(kind, count, parent, pitch)
    if not stripPools[kind] then
        local step = pitch or STRIP_PITCH
        GUIFrame:NewWidgetPool(kind, function(holder) return ConstructOrderStrip(holder, count, step) end,
            ResetOrderStrip)
        stripPools[kind] = true
    end
    return GUIFrame:AcquirePooled(kind, parent)
end

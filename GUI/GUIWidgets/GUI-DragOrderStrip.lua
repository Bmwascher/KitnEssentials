-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-DragOrderStrip.lua                                  ║
-- ║  Purpose: a row of icons the player drags into a         ║
-- ║           new order; each page gives its shape.          ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local CreateFrame = CreateFrame
local GetCursorPosition = GetCursorPosition
local UIParent = UIParent
local ipairs = ipairs
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local table_insert = table.insert
local table_remove = table.remove

-- The slot under cursorX, clamped to the strip.
local function DropIndex(strip, cursorX)
    local left = strip:GetLeft()
    if not left then return 1 end
    local shape = strip._shape
    local idx = math_floor((cursorX - left) / shape.cell) + 1
    return math_max(1, math_min(shape.slots, idx))
end

local function Layout(strip)
    local shape = strip._shape
    for i, s in ipairs(strip._slots) do
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", strip, "TOPLEFT", (i - 1) * shape.cell, 0)
        shape.setIcon(s.icon, s.key)
        if s.label then s.label:SetText(shape.label(s.key)) end
        s:SetAlpha(1)
    end
end

-- Attached to the held icon for the length of the drag only. The drop line
-- sits 4 px left of the target slot's icon, at the icons' vertical center.
local function DragUpdate(held)
    local strip = held._strip
    local shape = strip._shape
    local cursorX, cursorY = GetCursorPosition()
    local scale = strip:GetEffectiveScale()
    cursorX, cursorY = cursorX / scale, cursorY / scale
    local ghost = strip._ghost
    ghost:ClearAllPoints()
    ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cursorX, cursorY)
    local dropLine = strip._dropLine
    dropLine:ClearAllPoints()
    dropLine:SetPoint("CENTER", strip, "TOPLEFT",
        (DropIndex(strip, cursorX) - 1) * shape.cell + (shape.cell - shape.icon) / 2 - 4, strip._iconMidY)
    dropLine:Show()
end

-- One strip of shape. With a label the icon sits 2 px below the slot's top
-- and the text 4 px under it; without one the icon is centered and the
-- slot's mouse area is the icon's height.
local function NewStrip(parent, shape)
    local strip = CreateFrame("Frame", nil, parent)
    strip._shape = shape
    strip._enabled = true
    strip._iconMidY = shape.label and -(2 + shape.icon / 2) or -(shape.height / 2)

    local ghost = strip:CreateTexture(nil, "OVERLAY", nil, 7)
    ghost:SetSize(shape.icon, shape.icon)
    ghost:SetAlpha(0.7)
    ghost:Hide()
    strip._ghost = ghost

    local dropLine = strip:CreateTexture(nil, "OVERLAY", nil, 6)
    dropLine:SetSize(2, shape.icon + 4)
    dropLine:Hide()
    strip._dropLine = dropLine

    local slots = {}
    strip._slots = slots
    local owned = { strip }

    for i = 1, shape.slots do
        local slot = CreateFrame("Button", nil, strip)
        slot:SetSize(shape.cell, shape.height)
        slot._strip = strip
        slot.key = i

        local icon = slot:CreateTexture(nil, "ARTWORK")
        icon:SetSize(shape.icon, shape.icon)
        slot.icon = icon

        local highlight = slot:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints(icon)
        slot.highlight = highlight

        if shape.label then
            icon:SetPoint("TOP", slot, "TOP", 0, -2)
            local label = slot:CreateFontString(nil, "OVERLAY")
            KE:ApplyThemeFont(label, "small")
            label:SetShadowColor(0, 0, 0, 0)
            label:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
            label:SetPoint("TOP", icon, "BOTTOM", 0, -4)
            slot.label = label
        else
            icon:SetPoint("CENTER", slot, "CENTER", 0, 0)
            -- Without a label, only the icon's own height takes the mouse.
            local inset = (shape.height - shape.icon) / 2
            slot:SetHitRectInsets(0, 0, inset, inset)
        end

        slot:EnableMouse(true)
        slot:RegisterForDrag("LeftButton")

        local function EndDrag()
            slot:SetScript("OnUpdate", nil)
            slot:SetAlpha(1)
            strip._dragSlot = nil
            ghost:Hide()
            dropLine:Hide()
        end
        slot._endDrag = EndDrag

        slot:SetScript("OnDragStart", function(self)
            if not strip._enabled then return end
            local unfinished = strip._dragSlot
            if unfinished and unfinished ~= self then unfinished._endDrag() end
            strip._dragSlot = self
            shape.setIcon(ghost, self.key)
            ghost:Show()
            self:SetAlpha(0.3)
            slot:SetScript("OnUpdate", DragUpdate)
        end)

        slot:SetScript("OnDragStop", function(self)
            if strip._dragSlot ~= self then return end
            EndDrag()
            local cursorX = GetCursorPosition()
            local dropIdx = DropIndex(strip, cursorX / strip:GetEffectiveScale())
            local fromIdx
            for idx, s in ipairs(slots) do
                if s == self then
                    fromIdx = idx
                    break
                end
            end
            if fromIdx and dropIdx ~= fromIdx then
                table_insert(slots, dropIdx, table_remove(slots, fromIdx))
                Layout(strip)
                strip:Save()
            end
        end)

        slots[i] = slot
        owned[#owned + 1] = slot
    end

    function strip:SetOrder(order)
        for i, s in ipairs(slots) do s.key = order[i] or i end
        Layout(self)
    end

    function strip:Save()
        local onOrderChanged = self._onOrderChanged
        if not onOrderChanged then return end
        local list = {}
        for i, s in ipairs(slots) do list[i] = s.key end
        onOrderChanged(list)
    end

    -- The page's state manager calls this.
    function strip:SetEnabled(enabled)
        self._enabled = enabled == true
        if not self._enabled and self._dragSlot then self._dragSlot._endDrag() end
        self:SetAlpha(self._enabled and 1 or 0.4)
    end

    function strip:Configure(order, onOrderChanged)
        self:SetSize(shape.slots * shape.cell, shape.height)
        self._onOrderChanged = onOrderChanged
        dropLine:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.9)
        for _, s in ipairs(slots) do
            s.highlight:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.3)
        end
        self:SetEnabled(true)
        self:SetOrder(order)
    end

    -- Closing the settings hides the page without releasing it, and no
    -- OnDragStop reaches a hidden icon.
    strip:SetScript("OnHide", function(self)
        if self._dragSlot then self._dragSlot._endDrag() end
    end)

    strip._keOwned = owned
    return strip
end

-- Registers widget pool kind, whose strips each take shape: slots, cell (a
-- slot's width and pitch), icon (its size), height, setIcon(texture, key) and
-- an optional label(key). A strip released mid-drag would keep its OnUpdate
-- running on a hidden page, so the release ends the drag.
function GUIFrame:NewDragOrderStripPool(kind, shape)
    return self:NewWidgetPool(kind, function(parent) return NewStrip(parent, shape) end, function(strip)
        local dragging = strip._dragSlot
        if dragging then dragging._endDrag() end
    end)
end

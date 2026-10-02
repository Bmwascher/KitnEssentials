-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-WorldMarkerCycler.lua                               ║
-- ║  GUI: World Marker Cycler                                ║
-- ║  Purpose: Configuration panel for the WorldMarkerCycler  ║
-- ║  module.                                                 ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("WorldMarkerCycler", true)
    end
    return nil
end

---@param modifier string?
---@param key string?
local function FormatKeybind(modifier, key)
    if not key or key == "" then return "Not Set" end
    local display = ""
    if modifier and modifier ~= "" then
        display = modifier:gsub("CTRL%-", "Ctrl+"):gsub("ALT%-", "Alt+"):gsub("SHIFT%-", "Shift+")
    end
    return display .. key
end

----------------------------------------------------------------
-- Keybind buttons
----------------------------------------------------------------
-- The button whose capture is armed, and the one full-screen key catcher
-- every button shares. The catcher is made on the first capture.
local activeCapture
local captureFrame

local function PaintKeybindRest(btn)
    btn._text:SetText(FormatKeybind(btn._bindMod, btn._bindKey))
    btn._text:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    btn:SetBackdropBorderColor(Theme.controlBorder[1], Theme.controlBorder[2], Theme.controlBorder[3], 1)
end

local function CancelCapture()
    local btn = activeCapture
    activeCapture = nil
    if captureFrame then captureFrame:Hide() end
    if btn then PaintKeybindRest(btn) end
end

local function GetCaptureFrame()
    if captureFrame then return captureFrame end

    local frame = CreateFrame("Button", nil, UIParent)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetAllPoints(UIParent)
    frame:EnableKeyboard(true)
    frame:EnableMouse(true)
    frame:SetPropagateKeyboardInput(false)
    frame:Hide()

    frame:SetScript("OnClick", function(self) self:Hide() end)

    frame:SetScript("OnHide", function()
        if activeCapture then CancelCapture() end
    end)

    frame:SetScript("OnKeyDown", function(self, capturedKey)
        if capturedKey == "ESCAPE" then
            CancelCapture()
            return
        end
        if capturedKey == "LSHIFT" or capturedKey == "RSHIFT"
            or capturedKey == "LCTRL" or capturedKey == "RCTRL"
            or capturedKey == "LALT" or capturedKey == "RALT" then
            return
        end

        local btn = activeCapture
        if not btn then return end

        local mod = ""
        if IsControlKeyDown() then mod = mod .. "CTRL-" end
        if IsAltKeyDown() then mod = mod .. "ALT-" end
        if IsShiftKeyDown() then mod = mod .. "SHIFT-" end

        local onBind = btn._onBind
        btn._bindMod = mod
        btn._bindKey = capturedKey
        activeCapture = nil
        self:Hide()
        PaintKeybindRest(btn)
        if onBind then onBind(mod, capturedKey) end
    end)

    captureFrame = frame
    return frame
end

local function ConstructKeybindButton(parent)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })

    local text = btn:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER")
    btn._text = text

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    end)
    btn:SetScript("OnLeave", function(self)
        if activeCapture ~= self then
            self:SetBackdropBorderColor(Theme.controlBorder[1], Theme.controlBorder[2], Theme.controlBorder[3], 1)
        end
    end)

    btn:SetScript("OnClick", function(self)
        if activeCapture == self then
            CancelCapture()
        else
            activeCapture = self
            self._text:SetText("Press a key...")
            self._text:SetTextColor(1, 1, 0, 1)
            self:SetBackdropBorderColor(1, 1, 0, 1)
            GetCaptureFrame():Show()
        end
    end)

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:HookScript("OnClick", function(self, button)
        if button ~= "RightButton" then return end
        if activeCapture == self then
            activeCapture = nil
            captureFrame:Hide()
        end
        local onBind = self._onBind
        self._bindMod = ""
        self._bindKey = ""
        self._text:SetText("Not Set")
        self._text:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
        self:SetBackdropBorderColor(Theme.controlBorder[1], Theme.controlBorder[2], Theme.controlBorder[3], 1)
        if onBind then onBind("", "") end
    end)

    function btn:Configure(modifier, key, onBind)
        self:SetHeight(26)
        self:SetBackdropColor(Theme.controlBg[1], Theme.controlBg[2], Theme.controlBg[3], Theme.controlBg[4])
        KE:ApplyThemeFont(self._text, "normal")
        self._bindMod = modifier
        self._bindKey = key
        self._onBind = onBind
        PaintKeybindRest(self)
    end

    btn._keOwned = { btn }
    return btn
end

-- A page rebuilt under an armed capture would otherwise leave the catcher
-- armed for a button that has gone back to its pool.
GUIFrame:NewWidgetPool("wmc:keybind", ConstructKeybindButton, function(btn)
    if activeCapture == btn then CancelCapture() end
end)

----------------------------------------------------------------
-- Marker order strip
----------------------------------------------------------------
local ICON_SIZE = 36
local ICON_SPACING = 8
local SLOT_STEP = ICON_SIZE + ICON_SPACING
local STRIP_WIDTH = 8 * ICON_SIZE + 7 * ICON_SPACING
local STRIP_HEIGHT = ICON_SIZE + 12
local MARKER_TEX = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"

-- World marker ID → raid target icon ID mapping.
-- /worldmarker uses: 1=Square, 2=Triangle, 3=Diamond, 4=Cross, 5=Star, 6=Circle, 7=Moon, 8=Skull
-- UI-RaidTargetingIcon uses: 1=Star, 2=Circle, 3=Diamond, 4=Triangle, 5=Moon, 6=Square, 7=Cross, 8=Skull
local WORLD_TO_ICON = { [1]=6, [2]=4, [3]=3, [4]=7, [5]=1, [6]=2, [7]=5, [8]=8 }

local function MarkerTexture(worldId)
    return MARKER_TEX .. (WORLD_TO_ICON[worldId] or worldId)
end

local function LayoutSlots(strip)
    for i, slot in ipairs(strip._slots) do
        slot:ClearAllPoints()
        slot:SetPoint("LEFT", strip, "LEFT", (i - 1) * SLOT_STEP, 0)
        slot.icon:SetTexture(MarkerTexture(slot.markerId))
        slot:SetAlpha(1)
    end
end

local function GetDropIndex(strip, cursorX)
    local left = strip:GetLeft()
    if not left then return 1 end
    local idx = math.floor((cursorX - left) / SLOT_STEP) + 1
    return math.max(1, math.min(8, idx))
end

local function SaveOrder(strip)
    local onOrderChanged = strip._onOrderChanged
    if not onOrderChanged then return end
    local list = {}
    for i, slot in ipairs(strip._slots) do
        list[i] = slot.markerId
    end
    onOrderChanged(list)
end

-- Attached to the dragged slot for the length of the drag only.
local function SlotDragUpdate(slot)
    local strip = slot._strip
    local cursorX, cursorY = GetCursorPosition()
    local scale = strip:GetEffectiveScale()
    cursorX = cursorX / scale
    cursorY = cursorY / scale

    local ghost = strip._ghost
    ghost:ClearAllPoints()
    ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cursorX, cursorY)

    local dropLine = strip._dropLine
    local dropIdx = GetDropIndex(strip, cursorX)
    dropLine:ClearAllPoints()
    dropLine:SetPoint("CENTER", strip, "LEFT", (dropIdx - 1) * SLOT_STEP - (ICON_SPACING / 2), 0)
    dropLine:Show()
end

local function ConstructDragStrip(parent)
    local strip = CreateFrame("Frame", nil, parent)

    local ghost = strip:CreateTexture(nil, "OVERLAY", nil, 7)
    ghost:SetSize(ICON_SIZE, ICON_SIZE)
    ghost:SetAlpha(0.7)
    ghost:Hide()
    strip._ghost = ghost

    local dropLine = strip:CreateTexture(nil, "OVERLAY", nil, 6)
    dropLine:SetSize(2, ICON_SIZE + 4)
    dropLine:Hide()
    strip._dropLine = dropLine

    local slots = {}
    strip._slots = slots
    local owned = { strip }

    for i = 1, 8 do
        local slot = CreateFrame("Button", nil, strip)
        slot:SetSize(ICON_SIZE, ICON_SIZE)
        slot.markerId = i
        slot._strip = strip

        local icon = slot:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        slot.icon = icon

        slot:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
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
            strip._dragSlot = self
            ghost:SetTexture(MarkerTexture(self.markerId))
            ghost:Show()
            self:SetAlpha(0.3)
            slot:SetScript("OnUpdate", SlotDragUpdate)
        end)

        slot:SetScript("OnDragStop", function(self)
            if strip._dragSlot ~= self then return end
            EndDrag()

            local cursorX = GetCursorPosition()
            cursorX = cursorX / strip:GetEffectiveScale()
            local dropIdx = GetDropIndex(strip, cursorX)

            local fromIdx
            for idx, s in ipairs(slots) do
                if s == self then
                    fromIdx = idx
                    break
                end
            end
            if fromIdx and dropIdx ~= fromIdx then
                table.insert(slots, dropIdx, table.remove(slots, fromIdx))
            end

            LayoutSlots(strip)
            SaveOrder(strip)
        end)

        slots[i] = slot
        owned[#owned + 1] = slot
    end

    function strip:SetOrder(order)
        for i, slot in ipairs(slots) do
            slot.markerId = order[i] or i
        end
        LayoutSlots(self)
    end

    function strip:Configure(order, onOrderChanged)
        self:SetSize(STRIP_WIDTH, STRIP_HEIGHT)
        self._onOrderChanged = onOrderChanged
        dropLine:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.9)
        for _, slot in ipairs(slots) do
            local hl = slot:GetHighlightTexture()
            if hl then
                hl:SetVertexColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.3)
            end
        end
        self:SetOrder(order)
    end

    strip._keOwned = owned
    return strip
end

GUIFrame:NewWidgetPool("wmc:dragstrip", ConstructDragStrip, function(strip)
    local dragging = strip._dragSlot
    if dragging then dragging._endDrag() end
end)

----------------------------------------------------------------
-- Page
----------------------------------------------------------------
local function AddLabelRow(card, height, text, alpha)
    local row = GUIFrame:CreateRow(card.content, height)
    local label = row:GetLabel("small")
    label:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], alpha)
    label:SetText(text)
    row:AddWidget(label, 1)
    card:AddRow(row, height)
end

GUIFrame:RegisterContent("WorldMarkerCycler", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.WorldMarkerCycler
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local WMC = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if WMC and WMC.ApplySettings then WMC:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not WMC then return end
        WMC.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("WorldMarkerCycler")
        else
            KitnEssentials:DisableModule("WorldMarkerCycler")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "World Marker Cycler", yOffset)
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        ApplyModuleState(checked)
    end)

    card1:AddLabel("One key drops the next world marker at your cursor and another clears them all, " ..
        "so you can walk a pull placing square, triangle, diamond without opening a marker bar." ..
        "\n\nYou need to be leader or assist to place markers, and the game itself accepts about " ..
        "three a second - pressing faster than that drops them." ..
        "\n\nThe keys are stored in this profile and override whatever else they are bound to.")

    yOffset = card1:GetNextOffset()

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if db.Enabled == false then return yOffset end

    ----------------------------------------------------------------
    -- Card 2: Keybinds (custom capture buttons)
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Keybinds", yOffset)
    manager:Register(card2, "all")

    local function AddKeybindRows(label, modifier, key, onBind)
        AddLabelRow(card2, 16, label, 1)
        local row = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
        local btn = GUIFrame:AcquirePooled("wmc:keybind", row)
        btn:Configure(modifier, key, onBind)
        row:AddWidget(btn, 1)
        card2:AddRow(row, 30)
    end

    AddKeybindRows("Place Marker", db.PlaceModifier or "", db.PlaceKey or "", function(mod, capturedKey)
        db.PlaceModifier = mod
        db.PlaceKey = capturedKey
        ApplySettings()
    end)

    local spacer1 = GUIFrame:CreateRow(card2.content, Theme.rowHeightSeparator)
    card2:AddRow(spacer1, Theme.rowHeightSeparator)

    AddKeybindRows("Clear Markers", db.ClearModifier or "", db.ClearKey or "", function(mod, capturedKey)
        db.ClearModifier = mod
        db.ClearKey = capturedKey
        ApplySettings()
    end)

    local spacer2 = GUIFrame:CreateRow(card2.content, 6)
    card2:AddRow(spacer2, 6)

    AddLabelRow(card2, 18, "Click to set  |  Right-click to clear  |  ESC to cancel", 0.7)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Marker Order (drag-reorder grid)
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Marker Order", yOffset)
    manager:Register(card3, "all")

    AddLabelRow(card3, 18, "Drag markers to reorder:", 1)

    local dragRow = GUIFrame:CreateRow(card3.content, STRIP_HEIGHT)
    local strip = GUIFrame:AcquirePooled("wmc:dragstrip", dragRow)
    strip:ClearAllPoints()
    strip:SetPoint("CENTER", dragRow, "CENTER", 0, 0)
    strip:Configure(db.OrderList or { 1, 2, 3, 4, 5, 6, 7, 8 }, function(list)
        db.OrderList = list
        ApplySettings()
    end)
    card3:AddRow(dragRow, STRIP_HEIGHT)

    local ctrlRow = GUIFrame:CreateRow(card3.content, Theme.rowHeightSeparator + 22)
    local defaultBtn = GUIFrame:CreateButton(ctrlRow, "Default Order", {
        width = 140,
        callback = function()
            strip:SetOrder({ 1, 2, 3, 4, 5, 6, 7, 8 })
            SaveOrder(strip)
        end,
    })
    defaultBtn:ClearAllPoints()
    defaultBtn:SetPoint("CENTER", ctrlRow, "CENTER", 0, 0)
    manager:Register(defaultBtn, "all")
    card3:AddRow(ctrlRow, Theme.rowHeightSeparator + 22, 0)

    yOffset = card3:GetNextOffset()

    RefreshStates()
    return yOffset
end)

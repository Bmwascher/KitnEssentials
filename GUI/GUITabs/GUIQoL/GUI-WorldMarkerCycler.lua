-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local table_insert = table.insert
local ipairs = ipairs
local tonumber = tonumber

local function GetModule()
    return KitnEssentials:GetModule("WorldMarkerCycler", true)
end

-- Marker names for display
local MARKER_NAMES = {
    [1] = "Star", [2] = "Circle", [3] = "Diamond", [4] = "Triangle",
    [5] = "Moon", [6] = "Square", [7] = "Cross", [8] = "Skull",
}

-- Format a keybind for display (e.g. "SHIFT-E" → "Shift+E")
local function FormatKeybind(modifier, key)
    if not key or key == "" then return "Not Set" end
    local display = ""
    if modifier and modifier ~= "" then
        display = modifier:gsub("CTRL%-", "Ctrl+"):gsub("ALT%-", "Alt+"):gsub("SHIFT%-", "Shift+")
    end
    return display .. key
end

GUIFrame:RegisterContent("WorldMarkerCycler", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.WorldMarkerCycler
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return yOffset + errorCard:GetContentHeight() + Theme.paddingMedium
    end

    local WMC = GetModule()
    local allWidgets = {}

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

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then widget:SetEnabled(mainEnabled) end
        end
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "World Marker Cycler", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable World Marker Cycler", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
        end,
        true, "World Marker Cycler", "On", "Off"
    )
    row1:AddWidget(enableCheck, 0.5)
    card1:AddRow(row1, 36)

    -- Note
    local noteHeight = 50
    local noteRow = GUIFrame:CreateRow(card1.content, noteHeight)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Cycles through world markers at your cursor position.\n" .. KE:ColorTextByTheme("-") .. " Requires raid assist or leader to place markers.",
        noteHeight, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, noteHeight)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 2: Keybinds (interactive capture)
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Keybinds", yOffset)
    table_insert(allWidgets, card2)

    -- Keybind capture helper
    local activeCapture = nil -- tracks which bind is being captured

    local function CreateKeybindButton(parent, label, modifier, key, onBind)
        local row = GUIFrame:CreateRow(parent, 40)

        -- Label row above button
        local labelRow = GUIFrame:CreateRow(parent, 16)
        local labelText = labelRow:CreateFontString(nil, "OVERLAY")
        labelText:SetPoint("CENTER", labelRow, "CENTER", 0, 0)
        KE:ApplyThemeFont(labelText, "small")
        labelText:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
        labelText:SetText(label)
        labelRow:AddWidget(labelText, 1)

        -- Bind button (full width)
        local btn = CreateFrame("Button", nil, row, "BackdropTemplate")
        btn:SetHeight(26)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], 1)
        btn:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)

        local btnText = btn:CreateFontString(nil, "OVERLAY")
        btnText:SetPoint("CENTER")
        KE:ApplyThemeFont(btnText, "normal")
        btnText:SetText(FormatKeybind(modifier, key))
        btnText:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)

        -- Hover
        btn:SetScript("OnEnter", function()
            btn:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
        end)
        btn:SetScript("OnLeave", function()
            if activeCapture ~= btn then
                btn:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
            end
        end)

        -- Capture frame — fullscreen overlay that intercepts all input including ESC
        local captureFrame = CreateFrame("Button", nil, UIParent)
        captureFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        captureFrame:SetAllPoints(UIParent)
        captureFrame:EnableKeyboard(true)
        captureFrame:EnableMouse(true)
        captureFrame:SetPropagateKeyboardInput(false)
        captureFrame:Hide()

        -- Clicking anywhere outside cancels
        captureFrame:SetScript("OnClick", function(self)
            self:Hide()
        end)

        local function CancelCapture()
            captureFrame:Hide()
            activeCapture = nil
            btnText:SetText(FormatKeybind(modifier, key))
            btnText:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
            btn:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
        end

        captureFrame:SetScript("OnHide", function()
            if activeCapture == btn then
                CancelCapture()
            end
        end)

        captureFrame:SetScript("OnKeyDown", function(self, capturedKey)
            -- ESC cancels
            if capturedKey == "ESCAPE" then
                CancelCapture()
                return
            end

            -- Ignore bare modifier keys
            if capturedKey == "LSHIFT" or capturedKey == "RSHIFT"
                or capturedKey == "LCTRL" or capturedKey == "RCTRL"
                or capturedKey == "LALT" or capturedKey == "RALT" then
                return
            end

            -- Build modifier string
            local mod = ""
            if IsControlKeyDown() then mod = mod .. "CTRL-" end
            if IsAltKeyDown() then mod = mod .. "ALT-" end
            if IsShiftKeyDown() then mod = mod .. "SHIFT-" end

            -- Save
            modifier = mod
            key = capturedKey
            onBind(mod, capturedKey)

            -- Update display
            btnText:SetText(FormatKeybind(mod, capturedKey))
            btnText:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
            btn:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)

            self:Hide()
            activeCapture = nil
        end)

        btn:SetScript("OnClick", function()
            if activeCapture == btn then
                CancelCapture()
            else
                -- Start capture
                activeCapture = btn
                btnText:SetText("Press a key...")
                btnText:SetTextColor(1, 1, 0, 1)
                btn:SetBackdropBorderColor(1, 1, 0, 1)
                captureFrame:Show()
            end
        end)

        -- Right-click to clear
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:HookScript("OnClick", function(_, button)
            if button == "RightButton" then
                if activeCapture == btn then
                    captureFrame:Hide()
                    activeCapture = nil
                end
                modifier = ""
                key = ""
                onBind("", "")
                btnText:SetText("Not Set")
                btnText:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
                btn:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
            end
        end)

        row:AddWidget(btn, 1)
        return labelRow, row, btn
    end

    -- Place keybind
    local placeLabelRow, placeRow, placeBtn = CreateKeybindButton(card2.content, "Place Marker",
        db.PlaceModifier or "", db.PlaceKey or "",
        function(mod, key)
            db.PlaceModifier = mod
            db.PlaceKey = key
            ApplySettings()
        end)
    table_insert(allWidgets, placeBtn)
    card2:AddRow(placeLabelRow, 16)
    card2:AddRow(placeRow, 30)

    -- Spacer
    local spacer1 = GUIFrame:CreateRow(card2.content, 8)
    card2:AddRow(spacer1, 8)

    -- Clear keybind
    local clearLabelRow, clearRow, clearBtn = CreateKeybindButton(card2.content, "Clear Markers",
        db.ClearModifier or "", db.ClearKey or "",
        function(mod, key)
            db.ClearModifier = mod
            db.ClearKey = key
            ApplySettings()
        end)
    table_insert(allWidgets, clearBtn)
    card2:AddRow(clearLabelRow, 16)
    card2:AddRow(clearRow, 30)

    -- Spacer
    local spacer2 = GUIFrame:CreateRow(card2.content, 6)
    card2:AddRow(spacer2, 6)

    -- Hint text
    local hintHeight = 18
    local hintRow = GUIFrame:CreateRow(card2.content, hintHeight)
    local hintText = hintRow:CreateFontString(nil, "OVERLAY")
    hintText:SetPoint("LEFT", hintRow, "LEFT", 0, 0)
    KE:ApplyThemeFont(hintText, "small")
    hintText:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 0.7)
    hintText:SetText("Click to set  |  Right-click to clear  |  ESC to cancel")
    hintRow:AddWidget(hintText, 1)
    card2:AddRow(hintRow, hintHeight)

    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 3: Marker Order (drag to reorder)
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Marker Order", yOffset)
    table_insert(allWidgets, card3)

    local ICON_SIZE = 36
    local ICON_SPACING = 8
    local MARKER_TEX = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"

    -- World marker ID → raid target icon ID mapping
    -- /worldmarker uses: 1=Square, 2=Triangle, 3=Diamond, 4=Cross, 5=Star, 6=Circle, 7=Moon, 8=Skull
    -- UI-RaidTargetingIcon uses: 1=Star, 2=Circle, 3=Diamond, 4=Triangle, 5=Moon, 6=Square, 7=Cross, 8=Skull
    local WORLD_TO_ICON = { [1]=6, [2]=4, [3]=3, [4]=7, [5]=1, [6]=2, [7]=5, [8]=8 }

    local function MarkerTexture(worldId)
        return MARKER_TEX .. (WORLD_TO_ICON[worldId] or worldId)
    end

    -- Label (centered)
    local dragLabel = GUIFrame:CreateRow(card3.content, 18)
    local dragLabelText = dragLabel:CreateFontString(nil, "OVERLAY")
    dragLabelText:SetPoint("CENTER", dragLabel, "CENTER", 0, 0)
    KE:ApplyThemeFont(dragLabelText, "small")
    dragLabelText:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
    dragLabelText:SetText("Drag markers to reorder:")
    dragLabel:AddWidget(dragLabelText, 1)
    card3:AddRow(dragLabel, 18)

    -- Drag container (centered)
    local totalIconsWidth = (8 * ICON_SIZE) + (7 * ICON_SPACING)
    local dragRowHeight = ICON_SIZE + 12
    local dragRow = GUIFrame:CreateRow(card3.content, dragRowHeight)
    local dragContainer = CreateFrame("Frame", nil, dragRow)
    dragContainer:SetSize(totalIconsWidth, dragRowHeight)
    dragContainer:SetPoint("CENTER", dragRow, "CENTER", 0, 0)

    local orderSlots = {} -- the 8 draggable button frames
    local dragState = { dragging = false, dragIndex = nil, ghostTex = nil }

    local function SaveOrder()
        db.OrderList = {}
        for i = 1, 8 do
            db.OrderList[i] = orderSlots[i].markerId
        end
        ApplySettings()
    end

    local function LayoutSlots()
        for i, slot in ipairs(orderSlots) do
            slot:ClearAllPoints()
            slot:SetPoint("LEFT", dragContainer, "LEFT", (i - 1) * (ICON_SIZE + ICON_SPACING), 0)
            slot.icon:SetTexture(MarkerTexture(slot.markerId))
            slot:SetAlpha(1)
        end
    end

    -- Ghost texture (follows cursor during drag)
    local ghost = dragContainer:CreateTexture(nil, "OVERLAY", nil, 7)
    ghost:SetSize(ICON_SIZE, ICON_SIZE)
    ghost:SetAlpha(0.7)
    ghost:Hide()
    dragState.ghostTex = ghost

    -- Drop position indicator (vertical line showing where icon will land)
    local dropIndicator = dragContainer:CreateTexture(nil, "OVERLAY", nil, 6)
    dropIndicator:SetSize(2, ICON_SIZE + 4)
    dropIndicator:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.9)
    dropIndicator:Hide()

    -- Determine drop position from cursor
    local function GetDropIndex(cursorX)
        local containerLeft = dragContainer:GetLeft()
        if not containerLeft then return 1 end
        local relX = cursorX - containerLeft
        local slotWidth = ICON_SIZE + ICON_SPACING
        local idx = math.floor(relX / slotWidth) + 1
        return math.max(1, math.min(8, idx))
    end

    local function UpdateDropIndicator(dropIdx)
        if not dropIdx or not dragState.dragging then
            dropIndicator:Hide()
            return
        end
        local xPos = (dropIdx - 1) * (ICON_SIZE + ICON_SPACING) - (ICON_SPACING / 2)
        if dropIdx > 8 then
            xPos = 8 * (ICON_SIZE + ICON_SPACING) - (ICON_SPACING / 2)
        end
        dropIndicator:ClearAllPoints()
        dropIndicator:SetPoint("CENTER", dragContainer, "LEFT", xPos, 0)
        dropIndicator:Show()
    end

    -- Create 8 draggable slots
    local initOrder = db.OrderList or { 1, 2, 3, 4, 5, 6, 7, 8 }
    for i = 1, 8 do
        local slot = CreateFrame("Button", nil, dragContainer)
        slot:SetSize(ICON_SIZE, ICON_SIZE)
        slot.markerId = initOrder[i] or i

        local icon = slot:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexture(MARKER_TEX .. slot.markerId)
        slot.icon = icon

        -- Border on hover
        slot:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
        local hl = slot:GetHighlightTexture()
        if hl then
            hl:SetVertexColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.3)
        end

        slot:EnableMouse(true)
        slot:RegisterForDrag("LeftButton")

        slot:SetScript("OnDragStart", function(self)
            dragState.dragging = true
            dragState.dragIndex = i

            -- Find current index of this slot
            for idx, s in ipairs(orderSlots) do
                if s == self then
                    dragState.dragIndex = idx
                    break
                end
            end

            ghost:SetTexture(MarkerTexture(self.markerId))
            ghost:Show()
            self:SetAlpha(0.3)
        end)

        slot:SetScript("OnDragStop", function(self)
            if not dragState.dragging then return end
            dragState.dragging = false
            ghost:Hide()
            dropIndicator:Hide()

            local cursorX = GetCursorPosition()
            local scale = dragContainer:GetEffectiveScale()
            cursorX = cursorX / scale

            local dropIdx = GetDropIndex(cursorX)
            local fromIdx = dragState.dragIndex

            if fromIdx and dropIdx ~= fromIdx then
                local moved = table.remove(orderSlots, fromIdx)
                table.insert(orderSlots, dropIdx, moved)
            end

            LayoutSlots()
            SaveOrder()
        end)

        slot:SetScript("OnUpdate", function(self)
            if dragState.dragging and orderSlots[dragState.dragIndex] == self then
                local cursorX, cursorY = GetCursorPosition()
                local scale = dragContainer:GetEffectiveScale()
                cursorX = cursorX / scale
                cursorY = cursorY / scale
                ghost:ClearAllPoints()
                ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cursorX, cursorY)

                -- Update drop indicator position
                local dropIdx = GetDropIndex(cursorX)
                UpdateDropIndicator(dropIdx)
            end
        end)

        orderSlots[i] = slot
    end

    LayoutSlots()
    -- Don't use AddWidget — it overrides CENTER anchoring
    card3:AddRow(dragRow, dragRowHeight)

    -- Default Order button (centered)
    local ctrlRow = GUIFrame:CreateRow(card3.content, 30)
    local defaultBtn = GUIFrame:CreateButton(ctrlRow, "Default Order", {
        width = 140,
        callback = function()
            local defaultOrder = { 1, 2, 3, 4, 5, 6, 7, 8 }
            for i = 1, 8 do
                orderSlots[i].markerId = defaultOrder[i]
            end
            LayoutSlots()
            SaveOrder()
        end,
    })
    -- Center the button manually instead of AddWidget
    local btnFrame = defaultBtn
    btnFrame:ClearAllPoints()
    btnFrame:SetPoint("CENTER", ctrlRow, "CENTER", 0, 0)
    table_insert(allWidgets, defaultBtn)
    card3:AddRow(ctrlRow, 30)

    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    -- Apply initial widget states
    UpdateAllWidgetStates()
    yOffset = yOffset - (Theme.paddingSmall * 2)
    return yOffset
end)

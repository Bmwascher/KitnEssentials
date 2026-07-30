local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local next = next
local hooksecurefunc = hooksecurefunc
local CreateFrame = CreateFrame

local function SkinFlyoutButton(button)
    if not button.IconBorder or S.data(button).skinned then return end
    S.data(button).skinned = true

    S.SlotIcon(button.icon, button.IconBorder)
    button:SetNormalTexture(0)
    button:SetPushedTexture(0)
    button:GetHighlightTexture():SetColorTexture(1, 1, 1, 0.25)
end

local function FlyoutButtons(frame)
    frame:ForEachFrame(SkinFlyoutButton)
end

local function SkinFlyout(flyout)
    if S.data(flyout).skinned then return end
    S.data(flyout).skinned = true
    S.StripTextures(flyout)
    S.Template(flyout, "Window")
    S.CheckBox(flyout.HideUnownedCheckBox)
    hooksecurefunc(flyout.ScrollBox, "Update", FlyoutButtons)
end

local flyoutFrame
local function OnFlyoutOpened(frame)
    if flyoutFrame then return end
    for _, child in next, { frame:GetChildren() } do
        if child.HideUnownedCheckBox then
            flyoutFrame = child
            SkinFlyout(flyoutFrame)
            break
        end
    end
end

local function DressCategoryButton(button)

    if button.Text then S.SetFont(button.Text, 12, "OUTLINE") end
    button.NormalTexture:Hide()
    button.SelectedTexture:SetColorTexture(S.palette.brand[1], S.palette.brand[2], S.palette.brand[3], 0.15)
    button.HighlightTexture:SetColorTexture(S.palette.hover[1], S.palette.hover[2], S.palette.hover[3], S.palette.hover[4])
end

local function SkinCategoryRow(child)
    if child.Text and not S.data(child).skinned then
        S.data(child).skinned = true
        DressCategoryButton(child)
        hooksecurefunc(child, "Init", DressCategoryButton)
    end
end

local function CategoryRows(frame)
    frame:ForEachFrame(SkinCategoryRow)
end

-- The icon cell is the first column of every table row. Its backdrop tracks
-- the icon's own visibility, since empty rows keep the cell around.
local function SkinIconCell(cell)
    if not cell or not cell.Icon then return end

    if not S.data(cell).skinned then
        S.data(cell).skinned = true
        S.Icon(cell.Icon, true)
        if cell.IconBorder then cell.IconBorder:Hide() end
    end

    local bd = S.GetBackdrop(cell.Icon)
    if bd then bd:SetShown(cell.Icon:IsShown()) end
end

local function IconCells(frame)
    local builder = frame.tableBuilder
    if not builder then return end

    for i = 1, 22 do
        local row = builder.rows[i]
        if row and row.cells then SkinIconCell(row.cells[1]) end
    end
end

local function DressHeader(header)
    header:DisableDrawLayer("BACKGROUND")
    S.FontStrings(header, 12, "OUTLINE")

    local bd = S.Backdrop(header)
    local hover = header:GetHighlightTexture()

    if hover then
        local c = S.palette.hover
        hover:SetColorTexture(c[1], c[2], c[3], c[4])
        if bd then hover:SetAllPoints(bd) end
    end
end

-- Every header but the last leaves a gutter so the columns read as separate.
local function SkinHeaderRow(headerContainer)
    local last = headerContainer:GetNumChildren()

    for i, header in next, { headerContainer:GetChildren() } do
        if not S.data(header).skinned then
            S.data(header).skinned = true
            DressHeader(header)
        end

        local bd = S.GetBackdrop(header)
        if bd then bd:SetPoint("BOTTOMRIGHT", i < last and -5 or 0, -2) end
    end
end

local function SkinMoneyBox(box)
    S.EditBox(box)
    local bd = S.GetBackdrop(box)
    if bd then
        bd:SetPoint("TOPLEFT", 0, -3)
        bd:SetPoint("BOTTOMRIGHT", 0, 3)
    end
end

local function OnBrowseTableBuilt(frame)
    local headerContainer = frame.RecipeList and frame.RecipeList.HeaderContainer
    if headerContainer then
        SkinHeaderRow(headerContainer)
    end
end

local SLOT_BLANK = { "CropFrame", "NormalTexture", "SlotBackground", "HighlightTexture" }

-- The customer-side reagent slot keeps Blizzard's hit area but none of its
-- art: hover and pressed states are redrawn a pixel outside the icon.
local function RepaintOrderSlot(button)
    S.Vanish(button, SLOT_BLANK)

    local hover = button:GetHighlightTexture()
    hover:SetColorTexture(1, 1, 1, 0.25)
    S.BleedOutside(hover, button)

    local pressed = button:GetPushedTexture()
    pressed:SetColorTexture(0.9, 0.8, 0.1, 0.3)
    pressed:SetBlendMode("ADD")
    S.BleedOutside(pressed, button)
end

local function DressOrderSlot(slot, button, icon)
    S.SlotIcon(icon, button.IconBorder)
    S.BleedOutside(icon, button)
    if slot.Checkbox then S.CheckBox(slot.Checkbox) end
end

local function SkinOrderSlots(form)
    for slot in form.reagentSlotPool:EnumerateActive() do
        local button = slot and slot.Button
        local icon = button and button.Icon

        if icon then
            RepaintOrderSlot(button)

            if not S.data(button).skinned then
                S.data(button).skinned = true
                DressOrderSlot(slot, button, icon)
            end
        end
    end
end

local function SkinCategoryPane(list)
    S.StripTextures(list)
    S.Backdrop(list)
    S.ScrollBar(list.ScrollBar)
    hooksecurefunc(list.ScrollBox, "Update", CategoryRows)
end

local function SkinSearchPane(search)
    search.FavoritesSearchButton:SetSize(22, 22)
    S.Button(search.FavoritesSearchButton, search.FavoritesSearchButton.Icon)

    S.Apply(search, {
        SearchBox    = S.EditBox,
        SearchButton = S.Button,
    })

    local filter = search.FilterDropdown
    if filter then
        S.Button(filter)
        S.CloseButton(filter.ResetButton, 9)
    end
end

-- The results caption is reparented onto the scroll box so it sits inside the
-- backdrop rather than floating above the list.
local function SkinResultsPane(list)
    S.StripTextures(list)
    S.ScrollBar(list.ScrollBar)

    if list.ResultsText then list.ResultsText:SetParent(list.ScrollBox) end

    local bd = S.Backdrop(list.ScrollBox)
    if not bd then return end

    bd:ClearAllPoints()
    bd:SetPoint("TOPLEFT", list.ScrollBox, "TOPLEFT", 4, -4)
    bd:SetPoint("BOTTOMRIGHT", list.ScrollBox, "BOTTOMRIGHT", -4, 0)
end

local function SkinBrowsePane(pane)
    S.Apply(pane, {
        CategoryList = SkinCategoryPane,
        SearchBar    = SkinSearchPane,
        RecipeList   = SkinResultsPane,
    })

    hooksecurefunc(pane, "SetupTable", OnBrowseTableBuilt)
    hooksecurefunc(pane, "StartSearch", IconCells)
end

local function Skin()
    local frame = _G.ProfessionsCustomerOrdersFrame
    if not frame then return end
    S.Frame(frame)

    if frame.Tabs then
        for _, tab in next, frame.Tabs do
            S.Tab(tab)
        end
    end

    if _G.OpenProfessionsItemFlyout then
        hooksecurefunc("OpenProfessionsItemFlyout", OnFlyoutOpened)
    end

    if frame.MoneyFrameBorder then S.StripTextures(frame.MoneyFrameBorder) end
    if frame.MoneyFrameInset then S.Inset(frame.MoneyFrameInset) end

    S.Apply(frame, { BrowseOrders = SkinBrowsePane })

    local form = frame.Form
    if form then
        S.Button(form.BackButton)
        if form.TrackRecipeCheckbox then S.CheckBox(form.TrackRecipeCheckbox.Checkbox) end
        if form.AllocateBestQualityCheckbox then S.CheckBox(form.AllocateBestQualityCheckbox) end

        if form.RecipeHeader then
            form.RecipeHeader:Hide()
            S.Backdrop(form.RecipeHeader)
        end
        if form.LeftPanelBackground then
            S.StripTextures(form.LeftPanelBackground)
            S.Backdrop(form.LeftPanelBackground, 2)
        end
        if form.RightPanelBackground then
            S.StripTextures(form.RightPanelBackground)
            S.Backdrop(form.RightPanelBackground, 2)
        end

        local itemButton = form.OutputIcon
        if itemButton then
            itemButton.CircleMask:Hide()
            S.SlotIcon(itemButton.Icon, itemButton.IconBorder)
            local itemHighlight = itemButton:GetHighlightTexture()
            local ibd = S.GetBackdrop(itemButton.Icon)
            itemHighlight:SetColorTexture(1, 1, 1, 0.25)
            if ibd then
                itemHighlight:ClearAllPoints()
                itemHighlight:SetPoint("TOPLEFT", ibd, "TOPLEFT", 1, -1)
                itemHighlight:SetPoint("BOTTOMRIGHT", ibd, "BOTTOMRIGHT", -1, 1)
            end
        end

        if form.OrderRecipientTarget then
            S.EditBox(form.OrderRecipientTarget)
            local bd = S.GetBackdrop(form.OrderRecipientTarget)
            if bd then
                bd:SetPoint("TOPLEFT", -8, -2)
                bd:SetPoint("BOTTOMRIGHT", 0, 2)
            end
        end

        local payment = form.PaymentContainer
        if payment then
            S.StripTextures(payment.NoteEditBox)
            local nbd = S.Backdrop(payment.NoteEditBox)
            if nbd then
                nbd:ClearAllPoints()
                nbd:SetPoint("TOPLEFT", payment.NoteEditBox, "TOPLEFT", 15, 5)
                nbd:SetPoint("BOTTOMRIGHT", payment.NoteEditBox, "BOTTOMRIGHT", -18, 0)
            end
            if payment.CancelOrderButton then S.Button(payment.CancelOrderButton) end
            SkinMoneyBox(payment.TipMoneyInputFrame.GoldBox)
            SkinMoneyBox(payment.TipMoneyInputFrame.SilverBox)
            pcall(S.DropDown, payment.DurationDropdown)
            S.Button(payment.ListOrderButton)

            local viewListingButton = payment.ViewListingsButton
            if viewListingButton then
                viewListingButton:SetAlpha(0)
                local viewListingRepair = CreateFrame("Frame", nil, payment)
                viewListingRepair:SetPoint("TOPLEFT", viewListingButton, "TOPLEFT", 1, -1)
                viewListingRepair:SetPoint("BOTTOMRIGHT", viewListingButton, "BOTTOMRIGHT", -1, 1)
                local viewListingTexture = viewListingRepair:CreateTexture(nil, "ARTWORK")
                viewListingTexture:SetAllPoints()
                viewListingTexture:SetTexture([[Interface\CURSOR\Crosshair\Repair]])
            end
        end

        if form.MinimumQuality then pcall(S.DropDown, form.MinimumQuality.Dropdown) end
        pcall(S.DropDown, form.OrderRecipientDropdown)

        local currentListings = form.CurrentListings
        if currentListings then
            S.StripTextures(currentListings)
            S.Template(currentListings, "Window")
            S.Button(currentListings.CloseButton)
            S.ScrollBar(currentListings.OrderList.ScrollBar)
            SkinHeaderRow(currentListings.OrderList.HeaderContainer)
            S.StripTextures(currentListings.OrderList)
            currentListings:ClearAllPoints()
            currentListings:SetPoint("LEFT", frame, "RIGHT", 10, 0)
        end

        local qualityDialog = form.QualityDialog
        if qualityDialog then
            S.StripTextures(qualityDialog)
            S.Backdrop(qualityDialog)
            if qualityDialog.Bg then qualityDialog.Bg:SetAlpha(0) end
            S.CloseButton(qualityDialog.ClosePanelButton)
            S.Button(qualityDialog.AcceptButton)
            S.Button(qualityDialog.CancelButton)
            S.QualityTier(qualityDialog.Container1)
            S.QualityTier(qualityDialog.Container2)
            S.QualityTier(qualityDialog.Container3)
        end

        hooksecurefunc(form, "Init", SkinOrderSlots)
    end

    local myOrders = frame.MyOrdersPage
    if myOrders then

        S.Button(myOrders.RefreshButton, myOrders.RefreshButton.Icon)
        myOrders.RefreshButton:SetSize(26, 26)
        SkinHeaderRow(myOrders.OrderList.HeaderContainer)
        S.ScrollBar(myOrders.OrderList.ScrollBar)
        if myOrders.OrderList.ResultsText and myOrders.OrderList.ScrollBox then
            myOrders.OrderList.ResultsText:SetParent(myOrders.OrderList.ScrollBox)
        end
        S.StripTextures(myOrders.OrderList)
        local bd = S.Backdrop(myOrders.OrderList)
        if bd then
            bd:ClearAllPoints()
            bd:SetPoint("TOPLEFT", myOrders.OrderList.ScrollBox, "TOPLEFT", 4, -4)
            bd:SetPoint("BOTTOMRIGHT", myOrders.OrderList.ScrollBox, "BOTTOMRIGHT", -4, 0)
        end
    end
end

S:Register("Blizzard_ProfessionsCustomerOrders", Skin, "ProfessionsOrders")

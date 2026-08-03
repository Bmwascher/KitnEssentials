local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local next = next
local unpack = unpack -- luacheck: ignore 211/unpack
local hooksecurefunc = hooksecurefunc

local function StripAndPlate(frame)
    if not frame then return end
    S.StripTextures(frame)
    S.Backdrop(frame)
end

local function HandleTabs(tabSystem)
    if not tabSystem then return end
    for _, tab in next, { tabSystem:GetChildren() } do
        S.Tab(tab)
    end
end

local TAB_GLYPHS = {
    house = "Interface\\AddOns\\KitnEssentials\\Media\\Icon\\housing-tab-house.png",
    catalog = "Interface\\AddOns\\KitnEssentials\\Media\\Icon\\housing-tab-catalog.png",
}
local function CropTabIcon(icon, atlas)
    atlas = atlas or (icon.GetAtlas and icon:GetAtlas())
    if not atlas then return end
    local file = atlas:find("catalog", 1, true) and TAB_GLYPHS.catalog or TAB_GLYPHS.house
    icon:SetTexture(file)
    icon:SetTexCoord(0, 1, 0, 1)
    local active = atlas:find("-active", 1, true) ~= nil
    icon:SetVertexColor(1, 1, 1, active and 1 or 0.55)
    if not S.data(icon).sizing then
        S.data(icon).sizing = true
        icon:SetSize(20, 20)
        S.data(icon).sizing = nil
    end
end

local dashTab1
local function AnchorDashboardTab(tab, _, _, _, x, y)

    if x ~= 1 or y ~= 0 then
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", _G.HousingDashboardFrame, "TOPRIGHT", 1, 0)
    end
end
local function AnchorDashboardTab2(tab, _, _, _, x, y)
    if dashTab1 and (x ~= 0 or y ~= -1) then
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", dashTab1, "BOTTOMLEFT", 0, -1)
    end
end

local function SkinHouseRow(child)
    local d = S.data(child)
    if d.skinnedRow then return end
    S.StripTextures(child)
    if child.Background then child.Background:Hide() end
    S.Backdrop(child)
    if child.VisitHouseButton then
        S.Button(child.VisitHouseButton)
    end
    d.skinnedRow = true
end

local function HouseRows(frame)
    frame:ForEachFrame(SkinHouseRow)
end

local function SkinContentTabs(frame)
    if frame.TabSystem then HandleTabs(frame.TabSystem) end
end

local function Catalog_UpdateChild(child)
    local d = S.data(child)
    if d.skinnedTile then return end
    if child.Background then S.KillTexture(child.Background) end
    if child.HoverBackground then S.KillTexture(child.HoverBackground) end
    S.Backdrop(child)
    S.Hover(child)
    d.skinnedTile = true
end

local function Catalog_Update(sb)
    sb:ForEachFrame(Catalog_UpdateChild)
end

local function HookCatalogTiles(optionsContainer)
    if not optionsContainer then return end
    local sb = optionsContainer.ScrollBox
    if sb and sb.Update and sb.ForEachFrame and not S.data(sb).aeTileHook then
        S.data(sb).aeTileHook = true
        hooksecurefunc(sb, "Update", Catalog_Update)
        Catalog_Update(sb)
    end
end

local function TreatNeighborhoodRow(row)
    if not (row.ButtonBackground and row.Select and row.Deselect) then return end
    local d = S.data(row)
    if d.skinnedRow then return end
    d.skinnedRow = true
    S.KillTexture(row.ButtonBackground)
    S.Backdrop(row)
    S.Hover(row)
    local sel = row:CreateTexture(nil, "ARTWORK")
    sel:SetColorTexture(S.palette.brand[1], S.palette.brand[2], S.palette.brand[3], 0.15)
    local anchor = S.GetBackdrop(row) or row
    sel:SetPoint("TOPLEFT", anchor, "TOPLEFT", 1, -1)
    sel:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -1, 1)
    sel:Hide()
    d.selTex = sel
    hooksecurefunc(row, "Select", function() d.selTex:Show() end)
    hooksecurefunc(row, "Deselect", function() d.selTex:Hide() end)
end

local function TreatNeighborhoodList(list)
    local finder = _G.HouseFinderFrame
    for _, row in next, { list:GetChildren() } do
        TreatNeighborhoodRow(row)
    end

    local selBtn = finder and finder.selectedNeighborhoodButton
    if selBtn then
        local d = S.data(selBtn)
        if d.selTex then d.selTex:Show() end
    end
end

local function SkinHouseFinder()
    local finder = _G.HouseFinderFrame
    if not finder then return end
    S.StripTextures(finder)
    S.Backdrop(finder)
    if finder.CloseButton then S.CloseButton(finder.CloseButton) end
    if finder.WoodBorderFrame then finder.WoodBorderFrame:Hide() end

    for _, p in next, { finder.portrait, finder.Portrait, finder.PortraitContainer, finder.PortraitOverlay } do
        if p and p.Hide then
            p:Hide()
            if p.SetAlpha then p:SetAlpha(0) end
        end
    end

    if finder.PlotInfoFrame and finder.PlotInfoFrame.BackButton then
        S.Button(finder.PlotInfoFrame.BackButton)
    end

    local list = finder.NeighborhoodListFrame
    if list then
        S.StripTextures(list)
        local search = list.BNetFriendSearchBox
        if search then

            if search.DisableDrawLayer then search:DisableDrawLayer("BACKGROUND") end
            S.EditBox(search)
        end
        if list.RefreshButton then S.Button(list.RefreshButton) end
        if list.ScrollFrame and list.ScrollFrame.ScrollBar then
            S.TrimScrollBar(list.ScrollFrame.ScrollBar)
        end
        if list.NeighborhoodListBG then S.KillTexture(list.NeighborhoodListBG) end

        for _, sf in next, { list.ScrollFrame, list.BNetScrollFrame } do
            local layoutList = sf and sf.NeighborhoodList
            if layoutList and layoutList.Layout and not S.data(layoutList).aeRowHook then
                S.data(layoutList).aeRowHook = true
                hooksecurefunc(layoutList, "Layout", TreatNeighborhoodList)
                TreatNeighborhoodList(layoutList)
            end
        end
    end

    if finder.GuildSubdivisionDropdown then
        S.DropDown(finder.GuildSubdivisionDropdown, true)
    end
end

local function SkinDashboard()
    local dash = _G.HousingDashboardFrame
    if not dash then return end
    S.StripTextures(dash)
    S.Backdrop(dash)
    if dash.CloseButton then S.CloseButton(dash.CloseButton) end

    for _, p in next, { dash.portrait, dash.Portrait, dash.PortraitContainer, dash.PortraitOverlay } do
        if p and p.Hide then
            p:Hide()
            if p.SetAlpha then p:SetAlpha(0) end
        end
    end

    for i, tab in next, { dash.HouseInfoTabButton, dash.CatalogTabButton } do
        if tab then
            S.Backdrop(tab)
            tab:SetSize(30, 40)
            if i == 1 then
                dashTab1 = tab
                tab:ClearAllPoints()
                tab:SetPoint("TOPLEFT", dash, "TOPRIGHT", 1, 0)
                hooksecurefunc(tab, "SetPoint", AnchorDashboardTab)
            else
                tab:ClearAllPoints()
                tab:SetPoint("TOPLEFT", dashTab1, "BOTTOMLEFT", 0, -1)
                hooksecurefunc(tab, "SetPoint", AnchorDashboardTab2)
            end
            if tab.Highlight then S.KillTexture(tab.Highlight) end
            S.HoverWash(tab)
            local icon = tab.Icon
            if icon then
                icon:Show()
                if tab.inactiveAtlas then icon:SetAtlas(tab.inactiveAtlas) end
                icon:ClearAllPoints()
                icon:SetPoint("CENTER")
                icon:SetSize(20, 20)

                hooksecurefunc(icon, "SetSize", function(ic, w, h)
                    if (w ~= 20 or h ~= 20) and not S.data(ic).sizing then
                        S.data(ic).sizing = true
                        ic:SetSize(20, 20)
                        S.data(ic).sizing = nil
                    end
                end)
                hooksecurefunc(icon, "SetAtlas", CropTabIcon)
                CropTabIcon(icon)
            end
            if not tab.SelectedTexture then
                local selT = tab:CreateTexture(nil, "BACKGROUND", nil, 1)
                selT:SetColorTexture(S.palette.brand[1], S.palette.brand[2], S.palette.brand[3], 0.3)
                local tbd = S.GetBackdrop(tab)
                selT:SetPoint("TOPLEFT", tbd or tab, "TOPLEFT", 1, -1)
                selT:SetPoint("BOTTOMRIGHT", tbd or tab, "BOTTOMRIGHT", -1, 1)
                selT:Hide()
                tab.SelectedTexture = selT
            end
        end
    end

    if dash.HouseInfoTabButton and dash.HouseInfoTabButton.SelectedTexture then
        dash.HouseInfoTabButton.SelectedTexture:SetShown(dash.HouseInfoContent and dash.HouseInfoContent:IsShown())
    end
    if dash.CatalogTabButton and dash.CatalogTabButton.SelectedTexture then
        dash.CatalogTabButton.SelectedTexture:SetShown(dash.CatalogContent and dash.CatalogContent:IsShown())
    end
    local info = dash.HouseInfoContent
    if info then
        if info.DashboardNoHousesFrame and info.DashboardNoHousesFrame.NoHouseButton then
            S.Button(info.DashboardNoHousesFrame.NoHouseButton)
        end
        if info.HouseFinderButton then S.Button(info.HouseFinderButton) end
        if info.HouseDropdown then S.DropDown(info.HouseDropdown, true) end

        local content = info.ContentFrame
        if content then
            local upgrade = content.HouseUpgradeFrame
            if upgrade then
                S.StripTextures(upgrade)
                if upgrade.Background then upgrade.Background:Hide() end
                if upgrade.WatchFavorButton then S.CheckBox(upgrade.WatchFavorButton) end
            end
            hooksecurefunc(content, "UpdateTabs", SkinContentTabs)

            local initiatives = content.InitiativesFrame
            if initiatives then
                if initiatives.InitiativesArt then initiatives.InitiativesArt:Hide() end
                local setFrame = initiatives.InitiativeSetFrame
                local tasks = setFrame and setFrame.InitiativeTasks
                if tasks then
                    if tasks.BG then S.StripTextures(tasks.BG) end
                    S.Backdrop(tasks)
                    if tasks.ScrollBar then S.TrimScrollBar(tasks.ScrollBar) end
                    for _, region in next, {
                        tasks.BorderRight,
                        tasks.BorderTop,
                        tasks.TitleCornerBR,
                        tasks.TitleCornerTR,
                        tasks.TaskListTitleContainer and tasks.TaskListTitleContainer.TitleCornerBR,
                        tasks.TaskListTitleContainer and tasks.TaskListTitleContainer.TitleFoliage,
                    } do
                        if region then S.StripTextures(region) end
                    end
                end
                local activity = setFrame and setFrame.InitiativeActivity
                if activity then
                    S.Backdrop(activity)
                    if activity.ScrollBar then S.TrimScrollBar(activity.ScrollBar) end
                    for _, region in next, {
                        activity.BG,
                        activity.BGTexture,
                        activity.BorderTop,
                        activity.TitleCornerBL,
                        activity.TitleCornerTR,
                        activity.ActivityLogTitleContainer and activity.ActivityLogTitleContainer.TitleCornerBL,
                        activity.ActivityLogTitleContainer and activity.ActivityLogTitleContainer.TitleFoliage,
                    } do
                        if region then S.StripTextures(region) end
                    end
                end
            end
        end
    end

    local catalog = dash.CatalogContent
    if catalog then
        if catalog.Divider then catalog.Divider:Hide() end
        if catalog.Background then catalog.Background:Hide() end
        if catalog.SearchBox then
            S.EditBox(catalog.SearchBox)
            catalog.SearchBox:SetSize(150, 17)
        end
        if catalog.Filters and catalog.Filters.FilterDropdown then
            S.DropDown(catalog.Filters.FilterDropdown, true)
        end
        local categories = catalog.Categories
        if categories then
            if categories.TopBorder then categories.TopBorder:Hide() end
            if categories.Background then categories.Background:Hide() end
        end
        if catalog.OptionsContainer and catalog.OptionsContainer.ScrollBar then
            S.TrimScrollBar(catalog.OptionsContainer.ScrollBar)
        end
        HookCatalogTiles(catalog.OptionsContainer)
        local preview = catalog.PreviewFrame
        if preview then
            if preview.PreviewBackground then preview.PreviewBackground:Hide() end
            if preview.PreviewCornerLeft then preview.PreviewCornerLeft:Hide() end
            if preview.PreviewCornerRight then preview.PreviewCornerRight:Hide() end
        end
    end
end

local function SkinCornerstone()
    local visitor = _G.HousingCornerstoneVisitorFrame
    if visitor then
        StripAndPlate(visitor)
        if visitor.CloseButton then S.CloseButton(visitor.CloseButton) end
    end

    local houseInfo = _G.HousingCornerstoneHouseInfoFrame
    if houseInfo then
        StripAndPlate(houseInfo)
        if houseInfo.CloseButton then S.CloseButton(houseInfo.CloseButton) end
    end

    local purchase = _G.HousingCornerstonePurchaseFrame
    if purchase then
        StripAndPlate(purchase)
        if purchase.CloseButton then S.CloseButton(purchase.CloseButton) end
        if purchase.BuyButton then S.Button(purchase.BuyButton) end
    end

    local moveConfirm = _G.MoveHouseConfirmationDialog
    if moveConfirm then
        StripAndPlate(moveConfirm)
        if moveConfirm.ConfirmButton then S.Button(moveConfirm.ConfirmButton) end
        if moveConfirm.CancelButton then S.Button(moveConfirm.CancelButton) end
    end
end

local function SkinBulletinBoard()
    local board = _G.HousingBulletinBoardFrame
    if board then
        S.StripTextures(board)
        S.Backdrop(board)
        if board.CloseButton then S.CloseButton(board.CloseButton) end
        if board.ResidentsTab and board.ResidentsTab.ScrollBar then
            S.TrimScrollBar(board.ResidentsTab.ScrollBar)
        end
    end

    local rename = _G.NeighborhoodChangeNameDialog
    if rename then
        StripAndPlate(rename)
        if rename.NameEditBox then S.EditBox(rename.NameEditBox) end
        if rename.ConfirmButton then S.Button(rename.ConfirmButton) end
        if rename.CancelButton then S.Button(rename.CancelButton) end
    end
end

local function SkinHouseList()
    local list = _G.HouseListFrame
    if not list then return end
    StripAndPlate(list)
    if list.CloseButton then S.CloseButton(list.CloseButton) end
    if list.ScrollBar then S.TrimScrollBar(list.ScrollBar) end
    if list.ScrollBox and list.ScrollBox.Update then
        hooksecurefunc(list.ScrollBox, "Update", HouseRows)
    end
end

local function SkinCreateNeighborhood()
    local create = _G.HousingCreateGuildNeighborhoodFrame
    if not create then return end
    StripAndPlate(create)
    if create.NeighborhoodNameEditBox then S.EditBox(create.NeighborhoodNameEditBox) end
    if create.ConfirmButton then S.Button(create.ConfirmButton) end
    if create.CancelButton then S.Button(create.CancelButton) end

    local confirm = create.ConfirmationFrame
    if confirm then
        StripAndPlate(confirm)
        if confirm.ConfirmButton then S.Button(confirm.ConfirmButton) end
        if confirm.CancelButton then S.Button(confirm.CancelButton) end
    end
end

local function SkinSettingsPane(panel)
    if not panel.accessOptions then return end
    for _, option in next, panel.accessOptions do
        if option.Checkbox then
            S.CheckBox(option.Checkbox)
        end
    end
end

local function SkinHouseSettings()
    local settings = _G.HousingHouseSettingsFrame
    if settings then
        local plotAccess = settings.PlotAccess
        local houseAccess = settings.HouseAccess

        StripAndPlate(settings)
        if settings.CloseButton then S.CloseButton(settings.CloseButton) end
        if settings.HouseOwnerDropdown then S.DropDown(settings.HouseOwnerDropdown, true) end
        if settings.AbandonHouseButton then S.Button(settings.AbandonHouseButton) end
        if plotAccess and plotAccess.AccessTypeDropdown then S.DropDown(plotAccess.AccessTypeDropdown, true) end
        if houseAccess and houseAccess.AccessTypeDropdown then S.DropDown(houseAccess.AccessTypeDropdown, true) end

        if plotAccess then
            hooksecurefunc(plotAccess, "SetupOptions", SkinSettingsPane)
            SkinSettingsPane(plotAccess)
        end
        if houseAccess then
            hooksecurefunc(houseAccess, "SetupOptions", SkinSettingsPane)
            SkinSettingsPane(houseAccess)
        end

        if settings.IgnoreListButton then S.Button(settings.IgnoreListButton) end
        if settings.SaveButton then S.Button(settings.SaveButton) end
    end

    local abandon = _G.AbandonHouseConfirmationDialog
    if abandon then
        StripAndPlate(abandon)
        if abandon.ConfirmButton then S.Button(abandon.ConfirmButton) end
        if abandon.CancelButton then S.Button(abandon.CancelButton) end
    end
end

local function SkinHouseEditor()
    local editor = _G.HouseEditorFrame
    if not editor then return end

    local storageButton = editor.StorageButton
    if storageButton then
        S.Button(storageButton)
        local icon = storageButton.Icon
        if icon then
            icon:SetAtlas("house-chest-icon")
            icon:SetSize(32, 32)
            icon:ClearAllPoints()
            icon:SetPoint("CENTER")
        end
    end

    local storage = editor.StoragePanel
    if storage then
        StripAndPlate(storage)
        if storage.SearchBox then
            S.EditBox(storage.SearchBox)
            storage.SearchBox:SetSize(350, 21)
        end
        local filters = storage.Filters
        if filters and filters.FilterDropdown then
            S.Button(filters.FilterDropdown)
            local reset = filters.FilterDropdown.ResetButton
            if reset then
                S.CloseButton(reset)
                reset:ClearAllPoints()
                reset:SetPoint("CENTER", filters.FilterDropdown, "TOPRIGHT", 0, 0)
            end
        end
        HandleTabs(storage.TabSystem)
        local categories = storage.Categories
        if categories then
            if categories.TopBorder then categories.TopBorder:Hide() end
            if categories.Background then categories.Background:Hide() end
        end
        if storage.OptionsContainer and storage.OptionsContainer.ScrollBar then
            S.TrimScrollBar(storage.OptionsContainer.ScrollBar)
        end
        HookCatalogTiles(storage.OptionsContainer)
        local collapse = storage.CollapseButton
        if collapse then
            S.Button(collapse)

            if collapse.OverlayIcon then S.KillTexture(collapse.OverlayIcon) end
            local icon = collapse.Icon
            if icon then
                local function ArrowFor(ic, atlas)
                    atlas = atlas or (ic.GetAtlas and ic:GetAtlas()) or ""
                    S.ArrowTexture(ic, atlas:find("open", 1, true) and "right" or "left", 18)
                end
                hooksecurefunc(icon, "SetAtlas", ArrowFor)
                ArrowFor(icon)
            end
        end
    end

    local customization = editor.ExteriorCustomizationModeFrame
    if customization then
        local fixtureList = customization.FixtureOptionList
        if fixtureList then
            StripAndPlate(fixtureList)
            if fixtureList.CloseButton then
                S.CloseButton(fixtureList.CloseButton)
                fixtureList.CloseButton:ClearAllPoints()
                fixtureList.CloseButton:SetPoint("TOPRIGHT", fixtureList, "TOPRIGHT")
            end
            if fixtureList.ScrollBar then S.TrimScrollBar(fixtureList.ScrollBar) end
        end

        local coreOptions = customization.CoreOptionsPanel
        if coreOptions then
            for _, panel in next, {
                coreOptions,
                coreOptions.HouseTypeOption,
                coreOptions.HouseSizeOption,
                coreOptions.BaseStyleOption,
                coreOptions.RoofStyleOption,
                coreOptions.RoofVariantOption,
            } do
                if panel and panel.Dropdown then
                    S.DropDown(panel.Dropdown, true)
                end
            end
        end
    end

    local customizeMode = editor.CustomizeModeFrame
    local roomPane = customizeMode and customizeMode.RoomComponentCustomizationsPane
    local decorPane = customizeMode and customizeMode.DecorCustomizationsPane
    if roomPane then
        StripAndPlate(roomPane)
        if roomPane.CloseButton then
            roomPane.CloseButton:ClearAllPoints()
            roomPane.CloseButton:SetPoint("TOPRIGHT")
            S.CloseButton(roomPane.CloseButton)
        end
        for _, panel in next, {
            roomPane.ThemeDropdown,
            roomPane.WallpaperDropdown,
            roomPane.DoorTypeDropdown,
            roomPane.CeilingTypeDropdown,
        } do
            if panel and panel.Dropdown then
                S.DropDown(panel.Dropdown, true)
            end
        end
        if roomPane.ApplyThemeToRoomButton then
            roomPane.ApplyThemeToRoomButton:SetSize(26, 26)
            S.Button(roomPane.ApplyThemeToRoomButton)
        end
        if roomPane.ApplyWallpaperToAllWallsButton then
            roomPane.ApplyWallpaperToAllWallsButton:SetSize(26, 26)
            S.Button(roomPane.ApplyWallpaperToAllWallsButton)
        end
    end

    if decorPane then
        StripAndPlate(decorPane)
        if decorPane.CloseButton then
            decorPane.CloseButton:ClearAllPoints()
            decorPane.CloseButton:SetPoint("TOPRIGHT")
            S.CloseButton(decorPane.CloseButton)
        end
        if decorPane.ButtonFrame then
            if decorPane.ButtonFrame.CancelButton then S.Button(decorPane.ButtonFrame.CancelButton) end
            if decorPane.ButtonFrame.ApplyButton then S.Button(decorPane.ButtonFrame.ApplyButton) end
        end
    end

    local expertMode = editor.ExpertDecorModeFrame
    local placedList = expertMode and expertMode.PlacedDecorList
    if placedList then
        StripAndPlate(placedList)
        if placedList.ScrollBar then S.TrimScrollBar(placedList.ScrollBar) end
        if placedList.CloseButton then
            S.CloseButton(placedList.CloseButton)
            placedList.CloseButton:ClearAllPoints()
            placedList.CloseButton:SetPoint("TOPRIGHT")
        end
    end

    local dyePopout = _G.DyeSelectionPopout
    if dyePopout then
        StripAndPlate(dyePopout)
        if dyePopout.DyeSlotScrollBar then S.TrimScrollBar(dyePopout.DyeSlotScrollBar) end
        if dyePopout.ShowOnlyOwned then S.CheckBox(dyePopout.ShowOnlyOwned) end
    end
end

local function SkinModelPreview()
    local preview = _G.HousingModelPreviewFrame
    if not preview then return end
    StripAndPlate(preview)
    if preview.CloseButton then S.CloseButton(preview.CloseButton) end
    local model = preview.ModelPreview
    if model then
        S.StripTextures(model)

        local controls = model.ModelSceneControls
        if controls then
            for _, b in next, { controls:GetChildren() } do
                if b.IsObjectType and b:IsObjectType("Button") then
                    S.Button(b)
                end
            end
        end
    end
end

S:Register("Blizzard_HouseList", SkinHouseList, "Housing")
S:Register("Blizzard_HousingBulletinBoard", SkinBulletinBoard, "Housing")
S:Register("Blizzard_HousingCornerstone", SkinCornerstone, "Housing")
S:Register("Blizzard_HousingCreateNeighborhood", SkinCreateNeighborhood, "Housing")
S:Register("Blizzard_HousingDashboard", SkinDashboard, "Housing")
S:Register("Blizzard_HousingHouseFinder", SkinHouseFinder, "Housing")
S:Register("Blizzard_HousingHouseSettings", SkinHouseSettings, "Housing")
S:Register("Blizzard_HouseEditor", SkinHouseEditor, "Housing")
S:Register("Blizzard_HousingModelPreview", SkinModelPreview, "Housing")

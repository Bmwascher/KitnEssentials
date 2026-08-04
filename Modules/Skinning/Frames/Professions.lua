local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local pairs, next = pairs, next -- luacheck: ignore 211/pairs
local hooksecurefunc = hooksecurefunc

local function SkinFlyoutItem(item)
    if item.NormalTexture then
        item.NormalTexture:SetAlpha(0)
        item.PushedTexture:SetAlpha(0)
    end

    if S.data(item).skinned then return end
    S.data(item).skinned = true

    S.SlotIcon(item.icon, item.IconBorder)

    local hl = item:GetHighlightTexture()
    hl:SetColorTexture(1, 1, 1, 0.25)
    S.BleedOutside(hl, item)
end

local function SkinItemFlyout(child) -- luacheck: ignore 211/SkinItemFlyout
    if child.NineSlice then
        S.StripTextures(child.NineSlice, true)
        S.Backdrop(child)
    end

    if child.ScrollBar then S.ScrollBar(child.ScrollBar) end

    if child.HideUnownedCheckbox then
        S.CheckBox(child.HideUnownedCheckbox)
        child.HideUnownedCheckbox:SetSize(24, 24)
    end

    child.ScrollBox:ForEachFrame(SkinFlyoutItem)
end

-- TODO: this reads Blizzard's rendered atlas rather than the slot's own state,
-- which is the pattern we removed elsewhere. The driver isn't in the public
-- source drop, so it stays until the reagent slot machinery turns up.
local ADD_REAGENT_ATLAS = "ItemUpgrade_GreenPlusIcon"

local function SkinReagentSlot(button)
    local icon = button and button.Icon
    if not icon then return end

    if button.CropFrame then button.CropFrame:SetAlpha(0) end
    if button.SlotBackground then button.SlotBackground:SetAlpha(0) end

    local hl = button:GetHighlightTexture()
    hl:SetColorTexture(1, 1, 1, 0.25)
    S.BleedOutside(hl, button)

    local normal = button:GetNormalTexture()
    local pushed = button:GetPushedTexture()
    local addable = normal:GetAtlas() == ADD_REAGENT_ATLAS and 1 or 0

    normal:SetAlpha(addable)
    pushed:SetAlpha(addable)
    S.BleedOutside(normal, button)
    S.BleedOutside(pushed, button)

    if S.data(button).skinned then return end
    S.data(button).skinned = true

    S.SlotIcon(icon, button.IconBorder)
    S.BleedOutside(icon, button)
end

-- Dressed once; the border tint follows the crit state on every repaint.
local function DressOutputRow(child)
    local holder = child.ItemContainer
    if holder then
        local item = holder.Item

        item:SetNormalTexture(0)
        item:SetPushedTexture(0)
        item:SetHighlightTexture(0)
        S.SlotIcon(item.icon, item.IconBorder)

        holder.CritFrame:SetAlpha(0)
        holder.NameFrame:Hide()
        holder.BorderFrame:Hide()
        holder.HighlightNameFrame:SetAlpha(0)
        holder.PushedNameFrame:SetAlpha(0)

        S.data(holder).nameBD = S.Backdrop(holder.HighlightNameFrame)
        S.data(holder).itemBD = S.Backdrop(holder)
    end

    local bonus = child.CreationBonus
    if bonus then
        S.StripTextures(bonus.Item)
        S.Icon(bonus.Item.icon)
    end
end

local function RefreshOutputRow(child)
    local holder = child.ItemContainer
    if not holder then return end

    holder.Item.IconBorder:SetAlpha(0)

    local bd = S.data(holder).itemBD
    if not bd then return end

    if holder.CritFrame:IsShown() then
        bd:SetBackdropBorderColor(1, 0.8, 0)
    else
        bd:SetBackdropBorderColor(0, 0, 0)
    end
end

local function SkinOutputRow(child)
    if not S.data(child).skinned then
        S.data(child).skinned = true
        DressOutputRow(child)
    end

    RefreshOutputRow(child)
end

local function OutputRows(frame)
    frame:ForEachFrame(SkinOutputRow)
end

local function SkinOutputLog(outputlog)
    if not outputlog then return end

    S.StripTextures(outputlog)
    S.Template(outputlog, "Window")
    if outputlog.Bg then outputlog.Bg:SetAlpha(0) end

    S.CloseButton(outputlog.ClosePanelButton)
    S.ScrollBar(outputlog.ScrollBar)

    hooksecurefunc(outputlog.ScrollBox, "Update", OutputRows)
end

local function SkinRewardButton(button)
    if not button then return end

    S.StripTextures(button)
    S.SlotIcon(button.Icon, button.IconBorder)
end

local function SkinSchematicSlots(form)
    if form.reagentSlotPool then
        for slot in form.reagentSlotPool:EnumerateActive() do
            SkinReagentSlot(slot.Button)
        end
    end

    if form.salvageSlot then SkinReagentSlot(form.salvageSlot.Button) end
    if form.enchantSlot then SkinReagentSlot(form.enchantSlot.Button) end
end

-- Blizzard's circular recipe-output icon: the mask and hover ring fight the
-- square backdrop, so both go and the border carries the state instead.
local function SkinResultIcon(frame)
    S.SlotIcon(frame.Icon, frame.IconBorder)

    local hl = frame.GetHighlightTexture and frame:GetHighlightTexture()
    if hl then hl:Hide() end
    if frame.CircleMask then frame.CircleMask:Hide() end
end

local function SoftenArtwork(tex, alpha, crop)
    tex:Show()
    if crop then tex:SetTexCoord(0.02, 0.98, 0.02, 0.98) end
    tex:SetAlpha(alpha)
end

local function SquareCheckBox(box)
    S.CheckBox(box)
    box:SetSize(24, 24)
end

local function SinkBackdrop(bd, frame)
    if not bd then return end

    local c = S.palette.window
    bd:SetBackdropColor(c[1], c[2], c[3], c[4])
    bd:SetFrameLevel(math.max((frame:GetFrameLevel() or 1) - 1, 0))
end

local schematicHooked = {}

local function SkinSchematic(form)
    if not form then return end

    if not schematicHooked[form] then
        schematicHooked[form] = true
        hooksecurefunc(form, "Init", SkinSchematicSlots)
    end

    S.StripTextures(form)

    local bd = S.Backdrop(form, 1)
    if bd then
        SinkBackdrop(bd, form)
        bd:SetBackdropBorderColor(0, 0, 0, 0)
    end

    if form.Background then SoftenArtwork(form.Background, 0.6, true) end
    if form.MinimalBackground then SoftenArtwork(form.MinimalBackground, 0.6) end

    S.Each(form, SquareCheckBox, "TrackRecipeCheckbox", "AllocateBestQualityCheckbox")

    local dialog = form.QualityDialog
    if dialog then
        S.StripTextures(dialog)
        S.Backdrop(dialog)
        if dialog.Bg then dialog.Bg:SetAlpha(0) end

        S.Apply(dialog, {
            ClosePanelButton = S.CloseButton,
            AcceptButton     = S.Button,
            CancelButton     = S.Button,
            Container1       = S.QualityTier,
            Container2       = S.QualityTier,
            Container3       = S.QualityTier,
        })
    end

    S.Each(form, SkinResultIcon, "OutputIcon")
end

local SPEC_TAB_PIECES = {
    "Left", "Middle", "Right",
    "LeftActive", "MiddleActive", "RightActive",
    "LeftHighlight", "MiddleHighlight", "RightHighlight",
}

-- TabSystemButtonMixin sets an explicit width on the Text fontstring computed
-- from string metrics before our font applies. Expressway renders wider than
-- the budgeted width, so the ellipsis fires with room to spare. Both widths
-- are re-derived from live metrics on every pass, since Blizzard re-sizes.
local function FitTabToText(tab)
    local fs = tab.Text
    if not fs then return end

    fs:ClearAllPoints()
    fs:SetPoint("CENTER", tab, "CENTER", 0, 0)
    fs:SetWidth(0)

    local w = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
    if w and w > 0 and tab.SetTabWidth then
        tab:SetTabWidth(math.ceil(w) + 20)
    end
end

local function SpecTabs(frame)
    if not frame.tabsPool then return end

    for tab in frame.tabsPool:EnumerateActive() do
        S.Tab(tab)

        for _, key in ipairs(SPEC_TAB_PIECES) do
            local piece = tab[key]
            if piece and piece.SetAlpha then piece:SetAlpha(0) end
        end

        FitTabToText(tab)
    end
end

local function SkinRankBar(bar)
    if not bar then return end

    bar.Border:Hide()
    bar.Background:Hide()
    S.Backdrop(bar.Fill)
    S.SetFont(bar.Rank.Text, 12, "OUTLINE")

    if bar.ExpansionDropdownButton then
        S.ArrowButton(bar.ExpansionDropdownButton, "down")
    end
end

local function TintPanel(bd, shade, alpha)
    if not bd then return end

    local c = S.palette[shade]
    bd:SetBackdropColor(c[1], c[2], c[3], alpha or c[4])
end

local function SkinOrderView(frame)
    if not frame then return end

    local decline = frame.DeclineOrderDialog
    if decline then
        S.StripTextures(decline)
        S.Backdrop(decline)
        S.StripTextures(decline.NoteEditBox)
        S.EditBox(decline.NoteEditBox.ScrollingEditBox)
        S.Each(decline, S.Button, "ConfirmButton", "CancelButton")
    end

    SkinRankBar(frame.RankBar)
    SkinOutputLog(frame.CraftingOutputLog)
    S.Each(frame, S.Button, "CreateButton", "StartRecraftButton", "CompleteOrderButton")

    local info = frame.OrderInfo
    if info then
        S.StripTextures(info)
        TintPanel(S.Backdrop(info), "window")

        S.Each(info, S.Button, "BackButton", "StartOrderButton",
            "DeclineOrderButton", "ReleaseOrderButton", "SocialDropdown")

        S.StripTextures(info.NoteBox)
        S.EditBox(info.NoteBox)
        TintPanel(S.GetBackdrop(info.NoteBox), "panel", 0.5)

        local rewards = info.NPCRewardsFrame
        if rewards then
            rewards.Background:SetAlpha(0)
            S.Backdrop(rewards.Background)
            S.Each(rewards, SkinRewardButton, "RewardItem1", "RewardItem2")
        end
    end

    local details = frame.OrderDetails
    if not details then return end

    S.StripTextures(details)

    local bd = S.Backdrop(details)
    SinkBackdrop(bd, details)

    if details.Background and bd then
        details.Background:Show()
        details.Background:ClearAllPoints()
        details.Background:SetPoint("TOPLEFT", bd, "TOPLEFT", 1, -1)
        details.Background:SetPoint("BOTTOMRIGHT", bd, "BOTTOMRIGHT", -1, 1)
        details.Background:SetAlpha(0.5)
    end

    SkinSchematic(details.SchematicForm)

    local fulfil = details.FulfillmentForm
    if not fulfil then return end

    S.EditBox(fulfil.NoteEditBox)
    TintPanel(S.GetBackdrop(fulfil.NoteEditBox), "panel")

    if frame.ConcentrationDisplay then S.Icon(frame.ConcentrationDisplay.Icon) end
    S.Each(fulfil, SkinResultIcon, "ItemIcon")
end

local GEAR_SLOTS = {
    "Prof0ToolSlot", "Prof0Gear0Slot", "Prof0Gear1Slot",
    "Prof1ToolSlot", "Prof1Gear0Slot", "Prof1Gear1Slot",
    "CookingToolSlot", "CookingGear0Slot",
    "FishingToolSlot", "FishingGear0Slot", "FishingGear1Slot",
}

local function SkinGearSlot(button)
    S.StripTextures(button)
    S.SlotIcon(button.icon, button.IconBorder)
    button:SetNormalTexture(0)
    button:SetPushedTexture(0)
end

-- The chat-link button is a bare art button: Blizzard's texture includes
-- padding we crop out, then it takes the standard control template.
local function SkinLinkButton(button)
    button:GetNormalTexture():SetTexCoord(0.25, 0.7, 0.37, 0.75)
    button:GetPushedTexture():SetTexCoord(0.25, 0.7, 0.45, 0.8)
    button:GetHighlightTexture():SetAlpha(0)

    S.Template(button, "Default")
    button:SetSize(17, 14)
end

local function SkinPanel(frame)
    S.StripTextures(frame)
    S.Backdrop(frame)
end

local function SkinGuildFrame(frame)
    SkinPanel(frame)
    if frame.Container then SkinPanel(frame.Container) end
end

local function SkinRecipeList(list)
    S.StripTextures(list)
    if list.BackgroundNineSlice then list.BackgroundNineSlice:Hide() end
    S.Backdrop(list)

    S.Apply(list, {
        ScrollBar      = S.ScrollBar,
        SearchBox      = S.EditBox,
        FilterDropdown = S.Button,
    })

    if list.FilterDropdown then S.CloseButton(list.FilterDropdown.ResetButton) end
end

local function HideTutorialRing(button)
    if button.Ring then button.Ring:Hide() end
end

local function SkinTabRow(tabSystem)
    for _, tab in next, { tabSystem:GetChildren() } do
        S.Tab(tab)
    end
end

local function SkinInspectRecipe(frame)
    S.Frame(frame)
    SkinSchematic(frame.SchematicForm)
end

local function SkinCraftingPage(page)
    S.Each(page, S.Button, "CreateButton", "CreateAllButton", "ViewGuildCraftersButton")

    S.Apply(page, {
        MinimizedSearchBox     = S.EditBox,
        CreateMultipleInputBox = S.Stepper,
        SchematicForm          = SkinSchematic,
        RankBar                = SkinRankBar,
        LinkButton             = SkinLinkButton,
        GuildFrame             = SkinGuildFrame,
        RecipeList             = SkinRecipeList,
        TutorialButton         = HideTutorialRing,
        CraftingOutputLog      = SkinOutputLog,
    })

    if page.ConcentrationDisplay then S.Icon(page.ConcentrationDisplay.Icon) end

    for _, key in ipairs(GEAR_SLOTS) do
        local slot = page[key]
        if slot then SkinGearSlot(slot) end
    end
end

-- A backdrop that hugs its frame; the tree view leaves room on the right for
-- Blizzard's scroll gutter, which the panel below it doesn't have.
local function HugBackdrop(frame, rightInset)
    local bd = S.Backdrop(frame)
    if not bd then return end

    bd:ClearAllPoints()
    bd:SetPoint("TOPLEFT", frame, "TOPLEFT", -1, -1)
    bd:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", rightInset or -1, 1)
end

local function SkinDetailedView(view)
    S.StripTextures(view)
    HugBackdrop(view)

    S.Each(view, S.Button, "UnlockPathButton", "SpendPointsButton")
    if view.UnspentPoints then S.Icon(view.UnspentPoints.Icon) end
end

local function SkinTreeView(view)
    S.StripTextures(view)
    if view.Background then view.Background:SetAlpha(0) end
    HugBackdrop(view, -41)
end

local function SkinSpecPage(page)
    S.Each(page, S.Button, "ViewTreeButton", "UnlockTabButton", "ApplyButton",
        "ViewPreviewButton", "BackToFullTreeButton", "BackToPreviewButton")

    S.Apply(page, {
        PanelFooter  = S.StripTextures,
        TreeView     = SkinTreeView,
        DetailedView = SkinDetailedView,
    })

    hooksecurefunc(page, "UpdateTabs", SpecTabs)
    SpecTabs(page)
end

local function Skin()
    local PF = _G.ProfessionsFrame
    if not PF then return end

    S.Frame(PF)
    if PF.MaximizeMinimize then S.MaxMinFrame(PF.MaximizeMinimize) end
    if PF.TabSystem then SkinTabRow(PF.TabSystem) end

    local CraftingPage = PF.CraftingPage
    SkinCraftingPage(CraftingPage)

    local specPageSkinned = false
    local function OnceSpecPage(page)
        if specPageSkinned or not page then return end

        specPageSkinned = true
        SkinSpecPage(page)
    end
    OnceSpecPage(PF.SpecPage)
    if not specPageSkinned and PF.SetTab then
        hooksecurefunc(PF, "SetTab", function() OnceSpecPage(PF.SpecPage) end)
    end


    local OrdersPage = PF.OrdersPage
    if OrdersPage then
        SkinOrderView(OrdersPage.OrderView)

        local orderTabs = {
            OrdersPage.BrowseFrame.PublicOrdersButton,
            OrdersPage.BrowseFrame.GuildOrdersButton,
            OrdersPage.BrowseFrame.NpcOrdersButton,
            OrdersPage.BrowseFrame.PersonalOrdersButton,
        }

        local function LayoutOrderTabs()
            local prevTab
            for _, tab in ipairs(orderTabs) do
                local fs = tab.Text or (tab.GetFontString and tab:GetFontString())
                if fs then
                    fs:SetWidth(0)

                    fs:ClearAllPoints()
                    fs:SetPoint("CENTER", tab, "CENTER", 0, 0)
                    local w = (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth())
                        or (fs.GetStringWidth and fs:GetStringWidth())
                    if w and w > 0 then

                        local text = fs:GetText()
                        local reserve = (text and not text:find("(", 1, true)) and 24 or 0
                        tab:SetWidth(w + 28 + reserve)
                    end
                end
                if prevTab then
                    tab:ClearAllPoints()

                    tab:SetPoint("TOPLEFT", prevTab, "TOPRIGHT", -3, 0)
                end
                prevTab = tab
            end
        end
        local relayoutQueued = false
        local function QueueLayout()
            if relayoutQueued then return end
            relayoutQueued = true
            C_Timer.After(0, function()
                relayoutQueued = false
                LayoutOrderTabs()
            end)
        end
        for _, tab in ipairs(orderTabs) do
            S.Tab(tab)
            if tab.SetTabSelected then
                hooksecurefunc(tab, "SetTabSelected", QueueLayout)
            end

            local fs = tab.Text or (tab.GetFontString and tab:GetFontString())
            if fs then
                hooksecurefunc(fs, "SetText", QueueLayout)
            end
            tab:HookScript("OnShow", QueueLayout)
        end
        LayoutOrderTabs()

        local BrowseFrame = OrdersPage.BrowseFrame
        if BrowseFrame then
            S.StripTextures(BrowseFrame.OrdersRemainingDisplay)
            S.Backdrop(BrowseFrame.OrdersRemainingDisplay)
            BrowseFrame.FavoritesSearchButton:SetSize(22, 22)

            S.Button(BrowseFrame.SearchButton)

            if BrowseFrame.SearchButton.AdjustPointsOffset then
                BrowseFrame.SearchButton:AdjustPointsOffset(1, 0)
            end
            S.Button(BrowseFrame.FavoritesSearchButton)

            if BrowseFrame.FavoritesSearchButton.AdjustPointsOffset then
                BrowseFrame.FavoritesSearchButton:AdjustPointsOffset(0, 1)
            end
            S.ArrowButton(BrowseFrame.BackButton, "left")

            -- (crafter Crafting Orders page text had no
            -- outline): both lists' rows are pooled ScrollBox elements
            -- whose cell fonts we never touched. Outline once per
            -- pooled frame, size preserved (SetFont nil-size keeps the
            -- current size per cell).
            local function OutlineRowFonts(scrollBox)
                scrollBox:ForEachFrame(function(child)
                    if not S.data(child).fontsDone then
                        S.data(child).fontsDone = true
                        S.FontStringsDeep(child, nil, "OUTLINE")
                    end
                end)
            end

            local BrowseList = BrowseFrame.RecipeList
            if BrowseList then
                S.StripTextures(BrowseList)
                if BrowseList.BackgroundNineSlice then
                    S.StripTextures(BrowseList.BackgroundNineSlice, true)
                    S.Backdrop(BrowseList)
                end
                S.ScrollBar(BrowseList.ScrollBar)
                S.EditBox(BrowseList.SearchBox)
                S.Button(BrowseList.FilterDropdown)
                if BrowseList.ScrollBox then
                    hooksecurefunc(BrowseList.ScrollBox, "Update", OutlineRowFonts)
                    OutlineRowFonts(BrowseList.ScrollBox)
                end
            end

            local OrderList = BrowseFrame.OrderList
            if OrderList then
                S.StripTextures(OrderList)
                S.ScrollBar(OrderList.ScrollBar)
                if OrderList.ScrollBox then
                    hooksecurefunc(OrderList.ScrollBox, "Update", OutlineRowFonts)
                    OutlineRowFonts(OrderList.ScrollBox)
                end

                local SkinOrderHeaders
                SkinOrderHeaders = function()
                    local hc = OrderList.HeaderContainer
                    if not hc then return end
                    if not hc:GetLeft() then

                        C_Timer.After(0, SkinOrderHeaders)
                        return
                    end
                    local kids = { hc:GetChildren() }
                    table.sort(kids, function(a, b)
                        return (a:GetLeft() or 0) < (b:GetLeft() or 0)
                    end)
                    for i, header in ipairs(kids) do
                        local bd
                        if not S.data(header).skinned then
                            S.data(header).skinned = true
                            if header.DisableDrawLayer then header:DisableDrawLayer("BACKGROUND") end
                            bd = S.Backdrop(header)
                            local hl = header.GetHighlightTexture and header:GetHighlightTexture()
                            if hl and bd then
                                hl:SetColorTexture(1, 1, 1, 0.1)
                                hl:ClearAllPoints()
                                hl:SetPoint("TOPLEFT", bd, "TOPLEFT", 1, -1)
                                hl:SetPoint("BOTTOMRIGHT", bd, "BOTTOMRIGHT", -1, 1)
                            end
                        else
                            bd = S.Backdrop(header)
                        end
                        if bd then
                            bd:ClearAllPoints()

                            bd:SetPoint("TOPLEFT", header, "TOPLEFT", i == 1 and 1 or 0, 0)
                            bd:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", i < #kids and -3 or 0, 0)
                        end
                    end
                end

                hooksecurefunc(OrdersPage, "SetupTable", function()
                    C_Timer.After(0, SkinOrderHeaders)
                end)
                BrowseFrame:HookScript("OnShow", function()
                    QueueLayout()
                    C_Timer.After(0, SkinOrderHeaders)
                end)
                SkinOrderHeaders()
            end
        end
    end
end

-- Deviation 1: InspectRecipe is its own skin key. EllesmereUI has separate
-- settings for the professions window and the inspect-recipe window, but
-- both of its packs load from Blizzard_Professions, so per-registration
-- suppression cannot tell them apart. Two keys can.
local function SkinInspectRecipeWindow()
    if _G.InspectRecipeFrame then SkinInspectRecipe(_G.InspectRecipeFrame) end
end

S:Register("Blizzard_Professions", Skin, "Professions")
S:Register("Blizzard_Professions", SkinInspectRecipeWindow, "InspectRecipe")

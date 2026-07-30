local KE = select(2, ...)
local S = KE.Skins
if not S then return end

local _G = _G
local ipairs = ipairs
local hooksecurefunc = hooksecurefunc

local GREY = S.palette.hover
local navHooked = false

local function SafeHook(owner, method, fn)
    if type(owner) == "table" and type(owner[method]) == "function" then
        hooksecurefunc(owner, method, fn)
        return true
    end
end

local function SafeHookGlobal(name, fn)
    if type(_G[name]) == "function" then
        hooksecurefunc(name, fn)
        return true
    end
end

local function WhiteButton(btn)
    if not btn then return end
    S.Button(btn)
    local fs = btn.GetFontString and btn:GetFontString()
    if fs then fs:SetTextColor(1, 1, 1) end
end

local function ReskinInfoHeader(header)
    if S.data(header).skinned then return end
    S.data(header).skinned = true
    local button = header.button or header

    if button.GetRegions then
        for i = 4, 18 do
            local region = select(i, button:GetRegions())
            if region and region.SetTexture then region:SetTexture(nil) end
        end
    end
    S.StripTextures(button)
    local bd = S.Backdrop(button)
    if bd then bd:SetBackdropColor(S.controlBg[1], S.controlBg[2], S.controlBg[3], S.controlBg[4]) end

    S.Hover(button)
    if header.descriptionBG then header.descriptionBG:SetAlpha(0) end
    if header.descriptionBGBottom then header.descriptionBGBottom:SetAlpha(0) end
    if header.description then header.description:SetTextColor(1, 1, 1) end
    if button.title then
        S.SetFont(button.title, 12, "")
        button.title:SetTextColor(S.palette.brand[1], S.palette.brand[2], S.palette.brand[3])
    end
    if button.expandedIcon then
        button.expandedIcon:SetTextColor(1, 1, 1)
        button.expandedIcon:SetWidth(20)
    end
end

-- Ability headers are numbered globals with no published count, so each run is
-- walked until it stops resolving.
local INFO_HEADER_PREFIXES = {
    "EncounterJournalInfoHeader",
    "EncounterJournalOverviewInfoHeader",
}

local function DressAbilityHeaders()
    for _, prefix in ipairs(INFO_HEADER_PREFIXES) do
        for index = 1, math.huge do
            local header = _G[prefix .. index]
            if not header then break end
            ReskinInfoHeader(header)
        end
    end
end

local ejSkinned
local function SkinEncounterJournal()
    local EJ = _G.EncounterJournal
    if not EJ or ejSkinned then return end
    ejSkinned = true

    S.Frame(EJ)
    S.Backdrop(EJ)
    if _G.EncounterJournalBg then S.KillTexture(_G.EncounterJournalBg) end
    if _G.EncounterJournalInset then S.StripTextures(_G.EncounterJournalInset) end

    if EJ.navBar then
        S.StripTextures(EJ.navBar, true)
        if EJ.navBar.overlay then S.StripTextures(EJ.navBar.overlay, true) end
        local nbd = S.Backdrop(EJ.navBar)
        if nbd then
            nbd:ClearAllPoints()
            nbd:SetPoint("TOPLEFT", EJ.navBar, "TOPLEFT", -2, 0)
            nbd:SetPoint("BOTTOMRIGHT", EJ.navBar, "BOTTOMRIGHT", 0, 0)

        end

        local function skinCrumb(btn)
            if not btn then return end
            S.NavCrumb(btn)
        end
        skinCrumb(EJ.navBar.home)

        skinCrumb(EJ.navBar.overflowButton or EJ.navBar.overflow)
        if EJ.navBar.navList then
            for _, btn in ipairs(EJ.navBar.navList) do skinCrumb(btn) end
        end

        if not navHooked and type(_G.NavBar_AddButton) == "function" then
            hooksecurefunc("NavBar_AddButton", function(nav)
                if nav == EJ.navBar and nav.navList then
                    skinCrumb(nav.navList[#nav.navList])
                end
            end)
            navHooked = true
        end
    end

    if EJ.searchBox then
        S.EditBox(EJ.searchBox)
        if EJ.navBar then
            EJ.searchBox:ClearAllPoints()
            EJ.searchBox:SetPoint("TOPLEFT", EJ.navBar, "TOPRIGHT", 4, 0)
        end
        if EJ.searchBox.searchPreviewContainer then
            S.StripTextures(EJ.searchBox.searchPreviewContainer)
        end
    end

    local function Trim(bar) if bar then S.TrimScrollBar(bar) end end
    Trim(_G.EncounterJournalJourneysFrame and _G.EncounterJournalJourneysFrame.ScrollBar)
    if EJ.MonthlyActivitiesFrame then
        Trim(EJ.MonthlyActivitiesFrame.ScrollBar)
        Trim(EJ.MonthlyActivitiesFrame.FilterList and EJ.MonthlyActivitiesFrame.FilterList.ScrollBar)
    end

    local sel = EJ.instanceSelect
    if sel then
        if sel.bg then S.KillTexture(sel.bg) end
        if _G.EncounterJournalInstanceSelectBG then _G.EncounterJournalInstanceSelectBG:SetAlpha(0) end
        if sel.evergreenBg then

            S.StripTextures(sel.evergreenBg, true)
            S.KillAllTextures(sel.evergreenBg)
            if sel.evergreenBg.GetChildren then
                for _, c in ipairs({ sel.evergreenBg:GetChildren() }) do
                    if c.SetAlpha then c:SetAlpha(0) end
                end
            end
            sel.evergreenBg:SetAlpha(0)
            hooksecurefunc(sel.evergreenBg, "Show", function(f) f:SetAlpha(0) end)
        end
        if sel.ExpansionDropdown then S.DropDown(sel.ExpansionDropdown, true) end
        Trim(sel.ScrollBar)
        if sel.ScrollBox and sel.ScrollBox.Shadows then sel.ScrollBox.Shadows:SetAlpha(0) end
        if sel.ScrollBox and type(sel.ScrollBox.Update) == "function" then
            hooksecurefunc(sel.ScrollBox, "Update", function(box)
                box:ForEachFrame(function(child)
                    if S.data(child).skinned then return end
                    S.data(child).skinned = true
                    S.ClearButtonArt(child, true)

                    if child.bgImage then
                        local bd = S.Backdrop(child.bgImage, nil, true)
                        if bd then
                            bd:ClearAllPoints()
                            bd:SetPoint("TOPLEFT", child.bgImage, "TOPLEFT", 3, -3)
                            bd:SetPoint("BOTTOMRIGHT", child.bgImage, "BOTTOMRIGHT", -4, 2)
                        end
                    end
                    if child.SetHighlightTexture then
                        child:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
                        local hl = child:GetHighlightTexture()
                        hl:SetVertexColor(GREY[1], GREY[2], GREY[3], 0.15)
                        hl:ClearAllPoints()

                        local anchor = S.GetBackdrop(child.bgImage) or child.bgImage or child
                        hl:SetPoint("TOPLEFT", anchor, "TOPLEFT", 1, -1)
                        hl:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -1, 1)
                    end
                end)
            end)
        end
    end

    for _, tab in ipairs({
        _G.EncounterJournalJourneysTab, _G.EncounterJournalMonthlyActivitiesTab,
        _G.EncounterJournalSuggestTab, _G.EncounterJournalDungeonTab,
        _G.EncounterJournalRaidTab, _G.EncounterJournalLootJournalTab,
        EJ.TutorialsTab,
    }) do
        if tab then S.Tab(tab) end
    end

    local info = EJ.encounter and EJ.encounter.info
    if info then
        S.StripTextures(info)

        if info.encounterTitle then info.encounterTitle:SetAlpha(0) end

        if info.leftShadow then info.leftShadow:SetAlpha(0) end
        if info.rightShadow then info.rightShadow:SetAlpha(0) end
        if info.instanceButton then
            local ib = info.instanceButton
            if ib.icon then
                ib.icon:SetSize(32, 32)
                ib.icon:SetTexCoord(0, 1, 0, 1)
            end
            S.ClearButtonArt(ib)
            ib:ClearAllPoints()
            ib:SetPoint("TOPLEFT", info, "TOPLEFT", 0, 10)
        end
        if info.model and info.model.dungeonBG then S.KillTexture(info.model.dungeonBG) end
        if _G.EncounterJournalEncounterFrameInfoBG then
            _G.EncounterJournalEncounterFrameInfoBG:SetHeight(385)

            S.KillTexture(_G.EncounterJournalEncounterFrameInfoBG)
        end
        if _G.EncounterJournalEncounterFrameInfoModelFrameShadow then
            S.KillTexture(_G.EncounterJournalEncounterFrameInfoModelFrameShadow)
        end
        if info.instanceTitle and info.bossesScroll then
            info.instanceTitle:ClearAllPoints()
            info.instanceTitle:SetPoint("BOTTOM", info.bossesScroll, "TOP", 10, 15)
        end

        if info.difficulty then
            info.difficulty:ClearAllPoints()
            if _G.EncounterJournalEncounterFrameInfoBG then
                info.difficulty:SetPoint("BOTTOMRIGHT", _G.EncounterJournalEncounterFrameInfoBG, "TOPRIGHT", -5, 7)
            end
            S.DropDown(info.difficulty, true)
        end
        if info.LootContainer then
            local lc = info.LootContainer
            if lc.filter then
                lc.filter:ClearAllPoints()
                if info.difficulty then
                    lc.filter:SetPoint("RIGHT", info.difficulty, "LEFT", -120, 0)
                end
                S.DropDown(lc.filter, true)
            end
            if lc.slotFilter then S.DropDown(lc.slotFilter, true) end
            Trim(lc.ScrollBar)
            if lc.SetHeight then lc:SetHeight(360) end
        end
        Trim(info.BossesScrollBar)
        Trim(info.overviewScroll and info.overviewScroll.ScrollBar)
        Trim(info.detailsScroll and info.detailsScroll.ScrollBar)
        if info.overviewScroll then info.overviewScroll:SetHeight(360) end
        if info.detailsScroll then info.detailsScroll:SetHeight(360) end

        local prevTab
        for _, name in ipairs({ "overviewTab", "lootTab", "bossTab", "modelTab" }) do
            local tab = info[name]
            if tab then
                if not S.data(tab).skinned then
                    S.data(tab).skinned = true
                    local bd = S.Backdrop(tab, 2)
                    S.ClearButtonArt(tab, true)
                    if tab.GetHighlightTexture then
                        local hl = tab:GetHighlightTexture()
                        if hl then
                            hl:SetColorTexture(GREY[1], GREY[2], GREY[3], 0.15)
                            hl:ClearAllPoints()
                            hl:SetPoint("TOPLEFT", bd or tab, "TOPLEFT", 1, -1)
                            hl:SetPoint("BOTTOMRIGHT", bd or tab, "BOTTOMRIGHT", -1, 1)
                        end
                    end
                end
                tab:ClearAllPoints()
                if not prevTab then
                    tab:SetPoint("TOPLEFT", _G.EncounterJournalEncounterFrameInfo or info, "TOPRIGHT", 9, 0)
                else
                    tab:SetPoint("TOPLEFT", prevTab, "BOTTOMLEFT", 0, -1)
                end
                prevTab = tab
            end
        end
    end

    local instFrame = _G.EncounterJournalEncounterFrameInstanceFrame
    if instFrame then
        Trim(instFrame.LoreScrollBar)
        local bg = _G.EncounterJournalEncounterFrameInstanceFrameBG
        if bg then
            bg:SetScale(0.85)
            bg:ClearAllPoints()
            bg:SetPoint("CENTER", 0, 15)
        end
        if instFrame.titleBG and bg then
            instFrame.titleBG:ClearAllPoints()
            instFrame.titleBG:SetPoint("TOP", bg, "TOP", 0, -32)
        end
        if _G.EncounterJournalEncounterFrameInstanceFrameTitle then
            _G.EncounterJournalEncounterFrameInstanceFrameTitle:ClearAllPoints()
            _G.EncounterJournalEncounterFrameInstanceFrameTitle:SetPoint("TOP", 0, -85)
        end
        if _G.EncounterJournalEncounterFrameInstanceFrameMapButton then
            _G.EncounterJournalEncounterFrameInstanceFrameMapButton:ClearAllPoints()
            _G.EncounterJournalEncounterFrameInstanceFrameMapButton:SetPoint("LEFT", 55, -78)
        end
    end

    local results = _G.EncounterJournalSearchResults
    if results then
        S.StripTextures(results)
        S.Backdrop(results)
        Trim(results.ScrollBar)
        if _G.EncounterJournalSearchResultsCloseButton then
            S.CloseButton(_G.EncounterJournalSearchResultsCloseButton)
        end
    end

    local suggest = EJ.suggestFrame
    if suggest then
        for i = 1, (_G.AJ_MAX_NUM_SUGGESTIONS or 3) do
            local sugg = suggest["Suggestion" .. i]
            if sugg then
                if sugg.bg then sugg.bg:Hide() end
                S.StripTextures(sugg)
                S.Backdrop(sugg)
                local cd = sugg.centerDisplay
                if cd then
                    if cd.title and cd.title.text then cd.title.text:SetTextColor(1, 1, 1) end
                    if cd.description and cd.description.text then cd.description.text:SetTextColor(0.9, 0.9, 0.9) end
                    if i > 1 and cd.ClearAllPoints then
                        cd:ClearAllPoints()
                        cd:SetPoint("TOPLEFT", 85, -10)
                    end
                    if i > 1 and cd.button then WhiteButton(cd.button) end
                end
                if sugg.iconRing then sugg.iconRing:Hide() end
                if sugg.iconRingHighlight then sugg.iconRingHighlight:SetTexture(nil) end
                if sugg.icon then
                    if i > 1 then

                        sugg.icon:ClearAllPoints()
                        sugg.icon:SetPoint("TOPLEFT", 10, -10)
                    end
                    local ibd = S.Backdrop(sugg.icon)
                    if ibd then
                        ibd:ClearAllPoints()
                        ibd:SetPoint("TOPLEFT", sugg.icon, "TOPLEFT", -1, 1)
                        ibd:SetPoint("BOTTOMRIGHT", sugg.icon, "BOTTOMRIGHT", 1, -1)
                    end
                    if sugg.icon.SetMask then sugg.icon:SetMask("") end
                    sugg.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                end
                if i == 1 then
                    WhiteButton(sugg.button)
                    if sugg.prevButton then S.ArrowButton(sugg.prevButton, "left") end
                    if sugg.nextButton then S.ArrowButton(sugg.nextButton, "right") end
                end
                local reward = sugg.reward
                if reward then
                    if reward.text then reward.text:SetTextColor(0.9, 0.9, 0.9) end
                    if reward.iconRing then reward.iconRing:Hide() end
                    if reward.iconRingHighlight then reward.iconRingHighlight:SetTexture(nil) end
                end
            end
        end
        SafeHookGlobal("EJSuggestFrame_RefreshDisplay", function()
            if not suggest.suggestions then return end
            for i, data in ipairs(suggest.suggestions) do
                local sugg = next(data) and suggest["Suggestion" .. i]
                if sugg and sugg.icon then
                    S.Backdrop(sugg.icon)
                    if sugg.icon.SetMask then sugg.icon:SetMask("") end
                    if data.iconPath then sugg.icon:SetTexture(data.iconPath) end
                    sugg.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    if sugg.iconRing then sugg.iconRing:Hide() end
                end
            end
        end)
        SafeHookGlobal("EJSuggestFrame_UpdateRewards", function(sugg)
            local rd = sugg.reward and sugg.reward.data
            if not rd then return end
            local icon = sugg.reward.icon
            if not icon then return end
            local bd = S.Backdrop(icon)
            if icon.SetMask then icon:SetMask("") end
            icon:SetTexture(rd.itemIcon or rd.currencyIcon or 134400)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            if bd and rd.itemID then
                local quality = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(rd.itemID)
                local color = quality and quality > 1 and _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality]
                if color then
                    bd:SetBackdropBorderColor(color.r, color.g, color.b)
                else
                    bd:SetBackdropBorderColor(S.borderColor[1], S.borderColor[2], S.borderColor[3], S.borderColor[4])
                end
            end
        end)
    end

    local tooltip = _G.EncounterJournalTooltip
    if tooltip then
        if tooltip.NineSlice then tooltip.NineSlice:SetAlpha(0) end
        S.Backdrop(tooltip)
        for _, item in ipairs({ tooltip.Item1, tooltip.Item2 }) do
            if item then
                if item.icon then S.Icon(item.icon) end
                if item.IconBorder then S.KillTexture(item.IconBorder) end
            end
        end
    end

    if EJ.LootJournal then
        Trim(EJ.LootJournal.ScrollBar)
        S.StripTextures(EJ.LootJournal)
        S.Backdrop(EJ.LootJournal)
    end
    for _, button in ipairs({
        _G.EncounterJournalEncounterFrameInfoFilterToggle,
        _G.EncounterJournalEncounterFrameInfoSlotFilterToggle,
    }) do
        if button then S.Button(button) end
    end

    local tContents = EJ.TutorialsFrame and EJ.TutorialsFrame.Contents
    local sb = tContents and tContents.StartButton
    if sb then
        if sb.GetFrameLevel and sb.SetFrameLevel then
            sb:SetFrameLevel(sb:GetFrameLevel() + 1)
        end
        local label = sb.GetText and sb:GetText()
        S.Button(sb)

        if label and label ~= "" and sb.SetText then sb:SetText(label) end
        local fs = sb.GetFontString and sb:GetFontString()
        if fs then fs:SetTextColor(1, 1, 1) end
    end

    local monthly = EJ.MonthlyActivitiesFrame or _G.EncounterJournalMonthlyActivitiesFrame
    if monthly then
        if monthly.HeaderContainer then S.StripTextures(monthly.HeaderContainer, true) end
        if monthly.FilterList then
            S.StripTextures(monthly.FilterList)
            if monthly.FilterList.Bg then monthly.FilterList.Bg:SetAlpha(0) end
            local fbd = S.Backdrop(monthly.FilterList)
            if fbd then fbd:SetBackdropColor(S.controlBg[1], S.controlBg[2], S.controlBg[3], S.controlBg[4]) end
        end
        for _, key in ipairs({ "Bg", "Background", "BackgroundTile" }) do
            if monthly[key] and monthly[key].SetAlpha then monthly[key]:SetAlpha(0) end
        end
        if monthly.Bar then S.StripTextures(monthly.Bar) end
        if monthly.BarComplete then monthly.BarComplete:SetAlpha(0) end
        if monthly.Divider then monthly.Divider:Hide() end
        if monthly.DividerVertical then monthly.DividerVertical:Hide() end
        if monthly.Bg then monthly.Bg:SetAlpha(0) end
        if monthly.ThemeContainer then monthly.ThemeContainer:SetAlpha(0) end
    end

    local journeys = _G.EncounterJournalJourneysFrame
    if journeys then
        S.StripTextures(journeys)
        if journeys.BorderFrame then S.StripTextures(journeys.BorderFrame, true) end
        if journeys.JourneysList and journeys.JourneysList.Shadows then
            journeys.JourneysList.Shadows:SetAlpha(0)
        end

        local skip = journeys.JourneyProgress and journeys.JourneyProgress.LevelSkipButton
        if skip then
            S.Button(skip)
            local fs = skip.GetFontString and skip:GetFontString()
            if fs then S.SetFont(fs, 11, "OUTLINE") end
        end
    end

    if info and info.BossesScrollBox then
        SafeHook(info.BossesScrollBox, "Update", function(box)
            box:ForEachFrame(function(child)
                if S.data(child).skinned then return end
                S.data(child).skinned = true
                S.StripTextures(child)
                local bbd = S.Backdrop(child)
                if bbd then bbd:SetBackdropColor(S.controlBg[1], S.controlBg[2], S.controlBg[3], S.controlBg[4]) end

                S.Hover(child)
                if child.text then
                    S.SetFont(child.text, 13, "")
                    child.text:SetTextColor(1, 1, 1)
                end
                if child.creature then
                    child.creature:ClearAllPoints()
                    child.creature:SetPoint("TOPLEFT", 0, -4)
                end
            end)

            box:ForEachFrame(function(child)
                local d = S.data(child)
                if not d.selTex then
                    local t = child:CreateTexture(nil, "ARTWORK")
                    t:SetColorTexture(S.palette.brand[1], S.palette.brand[2], S.palette.brand[3], 0.15)
                    local anchor = S.GetBackdrop(child) or child
                    t:SetPoint("TOPLEFT", anchor, "TOPLEFT", 1, -1)
                    t:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -1, 1)
                    t:Hide()
                    d.selTex = t
                end
                local selected = child.encounterID and _G.EncounterJournal
                    and _G.EncounterJournal.encounterID == child.encounterID
                d.selTex:SetShown(selected and true or false)
            end)
        end)
    end

    if info and info.LootContainer and info.LootContainer.ScrollBox then
        SafeHook(info.LootContainer.ScrollBox, "Update", function(box)
            box:ForEachFrame(function(child)
                if S.data(child).skinned then return end
                S.data(child).skinned = true
                if child.bossTexture then child.bossTexture:SetAlpha(0) end
                if child.bosslessTexture then child.bosslessTexture:SetAlpha(0) end
                if child.name and child.icon then
                    child.icon:SetSize(32, 32)
                    child.icon:ClearAllPoints()
                    child.icon:SetPoint("TOPLEFT", 4, -8)
                    S.Icon(child.icon)
                    local ibd = S.Backdrop(child.icon)
                    if child.IconBorder and ibd then S.IconBorder(child.IconBorder, ibd) end
                    child.name:ClearAllPoints()
                    child.name:SetPoint("TOPLEFT", child.icon, "TOPRIGHT", 6, -2)

                    local rbd = S.Backdrop(child)
                    if rbd then
                        rbd:ClearAllPoints()
                        rbd:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
                        rbd:SetPoint("BOTTOMRIGHT", child, "BOTTOMRIGHT", 0, 1)
                    end
                end
                for _, key in ipairs({ "boss", "slot", "armorType" }) do
                    local fs = child[key]
                    if fs then fs:SetTextColor(1, 1, 1) end
                end
                if child.slot and child.name then
                    child.slot:ClearAllPoints()
                    child.slot:SetPoint("TOPLEFT", child.name, "BOTTOMLEFT", 0, -3)
                end
                if child.armorType then
                    child.armorType:ClearAllPoints()
                    child.armorType:SetPoint("RIGHT", child, "RIGHT", -10, 0)
                end
                if child.boss then
                    child.boss:ClearAllPoints()
                    child.boss:SetPoint("BOTTOMLEFT", 4, 6)
                end
            end)
        end)
    end

    local instLore = _G.EncounterJournalEncounterFrameInstanceFrame
    instLore = instLore and instLore.LoreScrollingFont
    if instLore and instLore.ScrollBox then
        local function WhitenLore(box)
            local target = box.ScrollTarget or box
            if not target.GetChildren then return end
            for _, child in ipairs({ target:GetChildren() }) do
                if child.FontString then child.FontString:SetTextColor(1, 1, 1) end
            end
        end
        WhitenLore(instLore.ScrollBox)
        SafeHook(instLore.ScrollBox, "Update", WhitenLore)
    end

    local jList = _G.EncounterJournalJourneysFrame and _G.EncounterJournalJourneysFrame.JourneysList
    if jList then
        SafeHook(jList, "Update", function(list)
            list:ForEachFrame(function(child)
                local toggle = child.WatchedFactionToggleFrame
                if toggle and toggle.WatchFactionCheckbox then
                    S.CheckBox(toggle.WatchFactionCheckbox)
                end
            end)
        end)
    end

    local function White(fs, r, g, b)
        if not fs or not fs.SetTextColor then return end
        r, g, b = r or 1, g or 1, b or 1
        if not pcall(fs.SetTextColor, fs, r, g, b) then
            pcall(fs.SetTextColor, fs, "P", r, g, b)
        end
    end
    local ovChild = info and info.overviewScroll and info.overviewScroll.child
    if ovChild then
        if ovChild.loreDescription then White(ovChild.loreDescription) end
        if ovChild.overviewDescription and ovChild.overviewDescription.Text then
            White(ovChild.overviewDescription.Text)
        end
    end
    local ovc = _G.EncounterJournalEncounterFrameInfoOverviewScrollFrameScrollChild -- luacheck: ignore 211/ovc
    if _G.EncounterJournalEncounterFrameInfoOverviewScrollFrameScrollChildHeader then
        _G.EncounterJournalEncounterFrameInfoOverviewScrollFrameScrollChildHeader:SetAlpha(0)
    end
    if _G.EncounterJournalEncounterFrameInfoOverviewScrollFrameScrollChildTitle then
        local t = _G.EncounterJournalEncounterFrameInfoOverviewScrollFrameScrollChildTitle
        White(t, 1, 0.8, 0)
        S.SetFont(t, 16, "")
    end
    if _G.EncounterJournalEncounterFrameInfoOverviewScrollFrameScrollChildLoreDescription then
        White(_G.EncounterJournalEncounterFrameInfoOverviewScrollFrameScrollChildLoreDescription)
    end
    if _G.EncounterJournalEncounterFrameInfoDetailsScrollFrameScrollChildDescription then
        White(_G.EncounterJournalEncounterFrameInfoDetailsScrollFrameScrollChildDescription)
    end

    SafeHookGlobal("EncounterJournal_SetBullets", function(object)
        if not object then return end
        if object.Text then White(object.Text) end
        local parent = object.GetParent and object:GetParent()
        if parent and parent.Bullets then
            for _, bullet in pairs(parent.Bullets) do
                if bullet and bullet.Text then White(bullet.Text) end
            end
        end
    end)

    SafeHookGlobal("EncounterJournal_ToggleHeaders", DressAbilityHeaders)
    SafeHookGlobal("EncounterJournal_SetUpOverview", DressAbilityHeaders)
    if info then
        if info.detailsScroll and info.detailsScroll.child and info.detailsScroll.child.description then
            info.detailsScroll.child.description:SetTextColor(1, 1, 1)
        end
        if info.overviewScroll and info.overviewScroll.child and info.overviewScroll.child.loreDescription then
            info.overviewScroll.child.loreDescription:SetTextColor(1, 1, 1)
        end
    end
end

local TAB_ORDER = {
    "EncounterJournalJourneysTab", "EncounterJournalMonthlyActivitiesTab",
    "EncounterJournalSuggestTab", "EncounterJournalDungeonTab",
    "EncounterJournalRaidTab", "EncounterJournalLootJournalTab",
}

local tabBaseY
local function LayoutSideTabs()
    local EJ = _G.EncounterJournal
    if not EJ then return end
    local prev
    for _, name in ipairs(TAB_ORDER) do
        local tab = _G[name]
        if not tab and name == "EncounterJournalJourneysTab" then tab = EJ.TutorialsTab end
        if tab and tab:IsShown() then
            if not prev then
                if not tabBaseY then

                    local _, _, _, _, y = tab:GetPoint(1)
                    tabBaseY = ((y and y > -60 and y) or 0) - 1
                end
                tab:ClearAllPoints()

                tab:SetPoint("TOPLEFT", EJ, "BOTTOMLEFT", -2, tabBaseY)
            else
                tab:ClearAllPoints()
                tab:SetPoint("LEFT", prev, "RIGHT", -3, 0)
            end
            prev = tab
        end
    end
    local tut = EJ.TutorialsTab
    if tut and tut:IsShown() and prev and tut ~= prev then
        tut:ClearAllPoints()
        tut:SetPoint("LEFT", prev, "RIGHT", -3, 0)
    end
end

local function HookRepositions()
    for _, name in ipairs({
        "EncounterJournal_OnShow",
        "EncounterJournal_CheckAndDisplayTradingPostTab",
        "EncounterJournal_CheckAndDisplaySuggestedContentTab",
    }) do
        if type(_G[name]) == "function" then
            hooksecurefunc(name, LayoutSideTabs)
        end
    end
    LayoutSideTabs()
end

S:Register("Blizzard_EncounterJournal", function()
    SkinEncounterJournal()
    HookRepositions()
end, "EncounterJournal")

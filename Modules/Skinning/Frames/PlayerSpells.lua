local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local ipairs, pairs = ipairs, pairs -- luacheck: ignore 211/pairs

local function SkinTalentDialog(dialog)
    if not dialog or S.data(dialog).skinned then return end
    S.StripTextures(dialog)

    for _, key in ipairs({ "Border", "NineSlice", "Bg", "Background" }) do
        if dialog[key] then S.StripTextures(dialog[key], true) end
    end
    S.Backdrop(dialog)
    if dialog.AcceptButton then S.Button(dialog.AcceptButton) end
    if dialog.CancelButton then S.Button(dialog.CancelButton) end
    if dialog.DeleteButton then S.Button(dialog.DeleteButton) end
    local eb = dialog.NameControl and dialog.NameControl.EditBox
    if eb then

        S.EditBox(eb, true)

        local ebd = S.GetBackdrop(eb)
        if ebd then
            ebd:ClearAllPoints()
            ebd:SetPoint("TOPLEFT", eb, "TOPLEFT", -5, -10)
            ebd:SetPoint("BOTTOMRIGHT", eb, "BOTTOMRIGHT", 5, 10)
        end
    end
    S.data(dialog).skinned = true
end

local function UpdateSpecFrame(frame)
    if not frame.SpecContentFramePool then return end
    for spec in frame.SpecContentFramePool:EnumerateActive() do
        if not S.data(spec).skinned then
            if spec.ActivateButton then S.Button(spec.ActivateButton) end
            if spec.SpellButtonPool then
                for button in spec.SpellButtonPool:EnumerateActive() do
                    if button.Ring then button.Ring:Hide() end
                    if button.CircleMask then button.CircleMask:Hide() end
                    if button.Icon then S.Icon(button.Icon, true) end
                end
            end
            S.data(spec).skinned = true
        end
    end
end

local function SkinHeroTalents(dialog)
    if not dialog or not dialog.SpecContentFramePool then return end
    for spec in dialog.SpecContentFramePool:EnumerateActive() do
        if not S.data(spec).skinned then
            if spec.SpecName then S.SetFont(spec.SpecName, 18, "") end
            if spec.Description then S.SetFont(spec.Description, 14, "") end
            if spec.CurrencyFrame then
                if spec.CurrencyFrame.LabelText then S.SetFont(spec.CurrencyFrame.LabelText, 13, "") end
                if spec.CurrencyFrame.AmountText then S.SetFont(spec.CurrencyFrame.AmountText, 18, "") end
            end
            if spec.ActivateButton then S.Button(spec.ActivateButton) end
            if spec.ApplyChangesButton then S.Button(spec.ApplyChangesButton) end
            S.data(spec).skinned = true
        end
    end
end

local function SkinSearchPreview(spc)
    if not spc or S.data(spc).skinned then return end
    S.StripTextures(spc)
    S.Backdrop(spc)
    local ov = CreateFrame("Frame", nil, spc)
    ov:SetAllPoints(spc)
    ov:SetFrameStrata(spc:GetFrameStrata())

    local lvl = (spc:GetFrameLevel() or 0) + 10
    ov:SetFrameLevel(lvl)
    local obd = S.Backdrop(ov, nil, true)
    if obd then obd:SetFrameLevel(lvl) end
    ov:EnableMouse(false)
    S.data(spc).skinned = true
end

local function SkinSpellBook(frame, book)
    if S.data(book).skinned then return end
    if frame.MaxMinButtonFrame then S.MaxMinFrame(frame.MaxMinButtonFrame) end
    if book.SearchBox then S.EditBox(book.SearchBox) end

    SkinSearchPreview(book.SearchPreviewContainer
        or (book.SearchBox and book.SearchBox.SearchPreviewContainer))
    if book.TopBar then book.TopBar:Hide() end
    if book.BookCornerFlipbook then book.BookCornerFlipbook:Hide() end
    if book.HelpPlateButton and book.HelpPlateButton.Ring then
        book.HelpPlateButton.Ring:Hide()
    end
    if book.CategoryTabSystem then
        for _, tab in ipairs({ book.CategoryTabSystem:GetChildren() }) do
            S.Tab(tab)
        end
    end
    local paged = book.PagedSpellsFrame
    if paged then

        if paged.View1 then paged.View1:DisableDrawLayer("OVERLAY") end
        local pc = paged.PagingControls
        if pc then
            if pc.PageText then pc.PageText:SetTextColor(1, 1, 1) end
            if pc.PrevPageButton then S.ArrowButton(pc.PrevPageButton, "left") end
            if pc.NextPageButton then S.ArrowButton(pc.NextPageButton, "right") end
        end
    end
    local rotation = book.AssistedCombatRotationSpellFrame
    local rbtn = rotation and rotation.Button
    if rbtn then
        if rbtn.Icon then S.Icon(rbtn.Icon, true) end
        if rbtn.Border then rbtn.Border:Hide() end
        S.Hover(rbtn)
    end
    S.data(book).skinned = true
end

local function Skin()
    local frame = _G.PlayerSpellsFrame
    if not frame then return end
    S.Frame(frame, true)

    if frame.TabSystem then
        for _, tab in ipairs({ frame.TabSystem:GetChildren() }) do
            S.Tab(tab)
        end
    end

    if frame.SpecFrame and frame.SpecFrame.UpdateSpecFrame
        and not S.data(frame.SpecFrame).hook then
        hooksecurefunc(frame.SpecFrame, "UpdateSpecFrame", UpdateSpecFrame)
        S.data(frame.SpecFrame).hook = true
    end

    local talents = frame.TalentsFrame
    if talents then
        if talents.BlackBG then talents.BlackBG:SetAlpha(0) end
        if talents.BottomBar then talents.BottomBar:SetAlpha(0) end
        if talents.ApplyButton then S.Button(talents.ApplyButton) end
        if talents.InspectCopyButton then S.Button(talents.InspectCopyButton) end
        if talents.LoadSystem and talents.LoadSystem.Dropdown then

            S.DropDown(talents.LoadSystem.Dropdown, true)

            if talents.LoadSystem.Dropdown.Text then
                S.SetFont(talents.LoadSystem.Dropdown.Text, 13, "")
            end
        end
        if talents.SearchBox then
            S.EditBox(talents.SearchBox)

            local sbd = S.GetBackdrop(talents.SearchBox)
            if sbd then
                sbd:ClearAllPoints()
                sbd:SetPoint("TOPLEFT", talents.SearchBox, "TOPLEFT", -4, -5)
                sbd:SetPoint("BOTTOMRIGHT", talents.SearchBox, "BOTTOMRIGHT", 0, 5)
            end
        end
        if talents.SearchPreviewContainer then

            SkinSearchPreview(talents.SearchPreviewContainer)
        end
        local pvp = talents.PvPTalentList
        if pvp then
            S.StripTextures(pvp)
            local bd = S.Backdrop(pvp)

            if bd then
                bd:SetFrameStrata(pvp:GetFrameStrata())
                bd:SetFrameLevel(2000)
            end
        end
        for _, key in ipairs({ "ClassCurrencyDisplay", "SpecCurrencyDisplay" }) do
            local cur = talents[key]
            if cur then
                if cur.CurrencyLabel then S.SetFont(cur.CurrencyLabel, 18, "") end
                local amt = cur.CurrentAmountContainer and cur.CurrentAmountContainer.CurrencyAmount
                if amt then S.SetFont(amt, 26, "") end
            end
        end
        local hero = talents.HeroTalentsContainer
        if hero and hero.HeroSpecLabel then S.SetFont(hero.HeroSpecLabel, 16, "") end
    end

    SkinTalentDialog(_G.ClassTalentLoadoutImportDialog)
    if _G.ClassTalentLoadoutImportDialog then
        local input = _G.ClassTalentLoadoutImportDialog.ImportControl
        local box = input and input.InputContainer
        if box then

            S.StripTextures(box); S.Backdrop(box)
        end
    end
    SkinTalentDialog(_G.ClassTalentLoadoutCreateDialog)
    local editDialog = _G.ClassTalentLoadoutEditDialog
    if editDialog then
        SkinTalentDialog(editDialog)
        if editDialog.LoadoutName then
            S.EditBox(editDialog.LoadoutName)
            local lbd = S.GetBackdrop(editDialog.LoadoutName)
            if lbd then
                lbd:ClearAllPoints()
                lbd:SetPoint("TOPLEFT", editDialog.LoadoutName, "TOPLEFT", -5, -5)
                lbd:SetPoint("BOTTOMRIGHT", editDialog.LoadoutName, "BOTTOMRIGHT", 5, 5)
            end
        end
        local check = editDialog.UsesSharedActionBars
        if check and check.CheckButton then S.CheckBox(check.CheckButton) end
    end

    local heroSelect = _G.HeroTalentsSelectionDialog
    if heroSelect and not S.data(heroSelect).skinned then
        S.StripTextures(heroSelect)
        S.Backdrop(heroSelect)
        if heroSelect.CloseButton then S.CloseButton(heroSelect.CloseButton) end
        hooksecurefunc(heroSelect, "ShowDialog", SkinHeroTalents)
        S.data(heroSelect).skinned = true
    end

    if frame.SpellBookFrame then SkinSpellBook(frame, frame.SpellBookFrame) end
end

S:Register("Blizzard_PlayerSpells", Skin, "PlayerSpells")

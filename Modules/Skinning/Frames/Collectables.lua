local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local next, unpack = next, unpack
local ipairs, pairs = ipairs, pairs
local select = select
local hooksecurefunc = hooksecurefunc
local CreateFrame = CreateFrame
local PlayerHasToy = PlayerHasToy

-- Wardrobe model overlays: the hover sheen and the shared state texture.
local MODEL_HOVER_TEX = 1569530
local MODEL_STATE_TEX = 1116940

-- Blizzard signals collection state through the border atlas it sets, so the
-- hook reads its argument rather than anything already drawn.
local WARDROBE_BORDER = {
    ["transmog-wardrobe-border-uncollected"] = { 0.9, 0.9, 0.3 },
    ["transmog-wardrobe-border-unusable"]    = { 0.9, 0.3, 0.3 },
}
local WARDROBE_PENDING = { 1, 0.7, 1 }

local ICON_CROP = { 0.08, 0.92, 0.08, 0.92 }
local HEIRLOOM_SLOT_ART = { "slotFrameCollected", "slotFrameUncollected" }

local function UniformFilter(btn, searchBox)
    if not btn then return end
    btn:SetSize(93, 22)
    if searchBox then
        btn:ClearAllPoints()
        btn:SetPoint("LEFT", searchBox, "RIGHT", 2, 0)
    end
end

local function BarTex()
    return "Interface\\AddOns\\KitnEssentials\\Media\\Statusbars\\KitnEssentials"
end

local function RestBorder(bd)
    if bd then bd:SetBackdropBorderColor(unpack(S.borderColor or { 0, 0, 0, 1 })) end
end

local function QualityColor(quality)
    local qc = quality and _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality]
    if qc then return qc.r, qc.g, qc.b end
    return unpack(S.borderColor or { 0, 0, 0, 1 })
end

local function Crop(tex)
    if tex then tex:SetTexCoord(ICON_CROP[1], ICON_CROP[2], ICON_CROP[3], ICON_CROP[4]) end
end

local function SetInsideOf(tex, target)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", target, "TOPLEFT", 1, -1)
    tex:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", -1, 1)
end

local function ApplyRowHover(bu, anchor)
    local hl = bu:CreateTexture(nil, "HIGHLIGHT")
    hl:SetColorTexture(S.palette.hover[1], S.palette.hover[2], S.palette.hover[3], S.palette.hover[4])
    hl:SetPoint("TOPLEFT", anchor or bu, "TOPLEFT", 1, -1)
    hl:SetPoint("BOTTOMRIGHT", anchor or bu, "BOTTOMRIGHT", -1, 1)
end

local BRAND_SELECT_INSET = { 1, -1, -1, 1 }

local function BrandSelection(tex, anchor, inset)
    if not tex then return end
    tex:SetTexture("Interface\\Buttons\\WHITE8x8")
    tex:SetColorTexture(S.palette.brand[1], S.palette.brand[2], S.palette.brand[3], 0.15)
    if anchor then
        inset = inset or BRAND_SELECT_INSET
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", anchor, "TOPLEFT", inset[1], inset[2])
        tex:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", inset[3], inset[4])
    end
    if tex.SetDrawLayer then tex:SetDrawLayer("BACKGROUND", 1) end
end

-- Collection rows have three states: usable, owned-but-unusable, unowned.
-- Blizzard picks a font object per state; we read the same state it reads
-- instead of inspecting what it produced, so the tint holds if Blizzard
-- ever changes its own values.
local ROW_TEXT_USABLE    = { 0.9, 0.9, 0.9 }
local ROW_TEXT_UNUSABLE  = { 0.9, 0.3, 0.3 }
local ROW_TEXT_UNOWNED   = { 0.4, 0.4, 0.4 }

local function Tint(fs, c)
    if fs then fs:SetTextColor(c[1], c[2], c[3]) end
end

local function MountRowText(button, elementData)
    local index = elementData and elementData.index
    if not index or not button or not button.name then return end

    local _, _, _, _, isUsable, _, _, _, _, _, isCollected, mountID =
        C_MountJournal.GetDisplayedMountInfo(index)

    if isUsable or (mountID and C_MountJournal.NeedsFanfare(mountID)) then
        Tint(button.name, ROW_TEXT_USABLE)
    elseif isCollected then
        Tint(button.name, ROW_TEXT_UNUSABLE)
    else
        Tint(button.name, ROW_TEXT_UNOWNED)
    end
end

local function ToyRowText(button)
    local itemID = button and button.itemID
    if not itemID then return end

    local c = PlayerHasToy(itemID) and ROW_TEXT_USABLE or ROW_TEXT_UNOWNED
    Tint(button.name, c)
    Tint(button.new, c)
end

-- Row skins are registered per journal instead of dispatched on parent, so a
-- row never has to be asked where it lives. Each list owns one function and
-- only touches regions its own template actually defines.
local ROW_DRAG_ACTIVE = { 0.9, 0.8, 0.1, 0.3 }
local ROW_HIGHLIGHT_ALPHA = 0.25

local function RowShell(bu)
    local icon = bu.icon
    if not icon then return end

    icon:ClearAllPoints()
    icon:SetPoint("LEFT", -43, 0)
    S.Icon(icon, true)

    if bu.iconBorder then
        S.IconBorder(bu.iconBorder, S.GetBackdrop(icon))
    end

    S.StripTextures(bu)

    local bd = S.Backdrop(bu)
    if bd then
        bd:ClearAllPoints()
        bd:SetPoint("TOPLEFT", bu, 0, -2)
        bd:SetPoint("BOTTOMRIGHT", bu, 0, 2)
    end

    ApplyRowHover(bu, bd)
    BrandSelection(bu.selectedTexture, bd)

    return icon, bd
end

-- Shared by both journals: the drag handle keeps Blizzard's geometry but
-- takes a flat active tint and a highlight clipped to the icon.
local function DressDragButton(drag, icon)
    if not drag then return end

    local active = drag.ActiveTexture
    if active then
        active:SetTexture("Interface\\Buttons\\WHITE8x8")
        active:SetVertexColor(ROW_DRAG_ACTIVE[1], ROW_DRAG_ACTIVE[2], ROW_DRAG_ACTIVE[3], ROW_DRAG_ACTIVE[4])
    end

    local hl = drag:GetHighlightTexture()
    if hl then
        SetInsideOf(hl, icon)
        hl:SetVertexColor(1, 1, 1, ROW_HIGHLIGHT_ALPHA)
    end
end

-- StripTextures clears the corner badges, so their source is read back first
-- and reapplied against the new icon bounds.
local function SkinMountRow(bu)
    if S.data(bu).skinned then return end

    local faction = bu.factionIcon
    local factionAtlas = faction and faction:GetAtlas()

    local icon = RowShell(bu)
    if not icon then return end

    if faction and factionAtlas then
        faction:SetAtlas(factionAtlas)
        faction:SetDrawLayer("OVERLAY")
        faction:ClearAllPoints()
        faction:SetPoint("TOPRIGHT", -1, -1)
        faction:SetPoint("BOTTOMRIGHT", -1, 1)
    end

    RestBorder(S.GetBackdrop(icon))
    DressDragButton(bu.DragButton, icon)

    if bu.favorite then
        bu.favorite:SetTexture([[Interface\COMMON\FavoritesIcon]])
        bu.favorite:ClearAllPoints()
        bu.favorite:SetPoint("TOPLEFT", bu.DragButton, "TOPLEFT", -8, 8)
        bu.favorite:SetSize(32, 32)
    end

    S.data(bu).skinned = true
end

local function SkinPetRow(bu)
    if S.data(bu).skinned then return end

    local petType = bu.petTypeIcon
    local petTypeTex = petType and petType:GetTexture()

    local icon = RowShell(bu)
    if not icon then return end

    if petType and petTypeTex then
        petType:SetTexture(petTypeTex)
        petType:ClearAllPoints()
        petType:SetPoint("TOPRIGHT", -1, -1)
        petType:SetPoint("BOTTOMRIGHT", -1, 1)
    end

    local drag = bu.dragButton
    if drag then
        DressDragButton(drag, icon)
        if drag.levelBG then drag.levelBG:SetTexture() end
        if drag.level then S.SetFont(drag.level, 12, "OUTLINE") end
    end

    S.data(bu).skinned = true
end

local function MountRows(frame)
    frame:ForEachFrame(SkinMountRow)
end

local function PetRows(frame)
    frame:ForEachFrame(SkinPetRow)
end

local function ToyButtonQuality(button)
    local bd = S.GetBackdrop(button)
    if not bd then return end
    local quality = button.itemID and PlayerHasToy(button.itemID) and C_Item.GetItemQualityByID(button.itemID)
    bd:SetBackdropBorderColor(QualityColor(quality))
end

-- Dressing happens once per button; tint and label anchors are refreshed on
-- every pass because Blizzard reshows the level badge each time it repaints.
local function DressHeirloomButton(button)
    S.ItemButton(button, true)

    Crop(button.iconTextureUncollected)
    SetInsideOf(button.iconTextureUncollected, button)
    button.iconTexture:SetDrawLayer("ARTWORK")

    S.Vanish(button, HEIRLOOM_SLOT_ART)
    button.special:SetJustifyH("RIGHT")
end

local function RefreshHeirloomButton(button)
    button.levelBackground:SetTexture()

    button.name:ClearAllPoints()
    button.name:SetPoint("LEFT", button, "RIGHT", 4, 8)
    button.level:ClearAllPoints()
    button.level:SetPoint("TOPLEFT", button.levelBackground, "TOPLEFT", 25, 2)

    local owned = C_Heirloom.PlayerHasHeirloom(button.itemID)
    local c = owned and ROW_TEXT_USABLE or ROW_TEXT_UNOWNED

    Tint(button.name, c)
    Tint(button.level, c)

    if owned then
        button.special:SetTextColor(1, 0.82, 0)

        local bd = S.GetBackdrop(button)
        if bd then
            bd:SetBackdropBorderColor(QualityColor(Enum.ItemQuality.Heirloom or 7))
        end
    else
        Tint(button.special, ROW_TEXT_UNOWNED)
    end
end

local function HeirloomButton(_, button)
    if not button or not button.itemID then return end

    if not S.data(button).skinned then
        DressHeirloomButton(button)
        S.data(button).skinned = true
    end

    RefreshHeirloomButton(button)
end

local function HeirloomHeaders()
    for _, header in next, _G.HeirloomsJournal.heirloomHeaderFrames or {} do
        S.StripTextures(header)
        S.SetFont(header.text, 15, "")
        Tint(header.text, ROW_TEXT_USABLE)
    end
end

local SET_ROW_SELECT_INSET = { 4, -2, -1, 2 }

local function SkinSetRow(child)
    if S.data(child).skinned then return end
    S.data(child).skinned = true

    child.Background:Hide()
    child.HighlightTexture:SetTexture(0)

    child.IconFrame.Icon:SetSize(42, 42)
    S.Icon(child.IconFrame.Icon)

    BrandSelection(child.SelectedTexture, child, SET_ROW_SELECT_INSET)
    ApplyRowHover(child)
    S.FontStrings(child, 12, "")
end

local function SetRows(frame)
    frame:ForEachFrame(SkinSetRow)
end

-- The border tracks the appearance actually collected in that slot, so the
-- quality is resolved before anything is drawn and an empty slot falls
-- through to QualityColor's neutral case.
local function SetItemQuality(_, itemFrame)
    local icon = itemFrame.Icon
    local bd = S.GetBackdrop(icon)

    if not bd then
        bd = S.Backdrop(icon)
        Crop(icon)
        itemFrame.IconBorder:Hide()
    end
    if not bd then return end

    local quality
    if itemFrame.collected and itemFrame.sourceID then
        local source = C_TransmogCollection.GetSourceInfo(itemFrame.sourceID)
        quality = source and source.quality
    end

    bd:SetBackdropBorderColor(QualityColor(quality))
end

local FLYOUT_ART = { "BorderShadow", "Border" }

-- The two flyout templates carry their icon at different region positions and
-- neither exposes a parentKey, so the caller passes the index.
local function SkinFlyoutButton(button, index)
    if not button then return end

    S.Vanish(button, FLYOUT_ART)
    S.ClearButtonArt(button, true)
    button:GetHighlightTexture():SetColorTexture(1, 1, 1, 0.25)

    local icon = index and select(index, button:GetRegions())
    if icon then S.Icon(icon, true) end
end

local function SkinMounts()
    local MountJournal = _G.MountJournal
    S.ItemButton(MountJournal.SummonRandomFavoriteSpellFrame.Button)
    S.Button(MountJournal.FilterDropdown)

    SkinFlyoutButton(MountJournal.ToggleDynamicFlightFlyoutButton, 3)
    local Flyout = MountJournal.ToggleDynamicFlightFlyoutButton.popup
    if Flyout then
        Flyout.Background:Hide()
        SkinFlyoutButton(Flyout.DynamicFlightModeButton, 4)
        SkinFlyoutButton(Flyout.OpenDynamicFlightSkillTreeButton, 4)
    end

    MountJournal.FilterDropdown:ClearAllPoints()
    UniformFilter(MountJournal.FilterDropdown, _G.MountJournalSearchBox)
    S.CloseButton(MountJournal.FilterDropdown.ResetButton)
    MountJournal.FilterDropdown.ResetButton:ClearAllPoints()
    MountJournal.FilterDropdown.ResetButton:SetPoint("CENTER", MountJournal.FilterDropdown, "TOPRIGHT", 0, 0)

    S.StripTextures(MountJournal)
    S.StripTextures(MountJournal.MountCount)
    S.FontStrings(MountJournal.MountCount, 12, "")

    local MountDisplay = MountJournal.MountDisplay
    if MountDisplay then
        S.StripTextures(MountDisplay)

        if MountDisplay.NineSlice then S.StripTextures(MountDisplay.NineSlice) end
        if MountDisplay.ModelScene and MountDisplay.ModelScene.NineSlice then
            S.StripTextures(MountDisplay.ModelScene.NineSlice)
        end
        if MountJournal.RightInset then S.Inset(MountJournal.RightInset) end
        S.StripTextures(MountDisplay.ShadowOverlay)
        MountDisplay.ModelScene.TogglePlayer:SetSize(22, 22)
        S.Icon(MountDisplay.InfoButton.Icon, true)
        S.CheckBox(MountDisplay.ModelScene.TogglePlayer)
        S.FontStrings(MountDisplay.ModelScene.TogglePlayer, 12, "")
        local info = MountDisplay.InfoButton
        if info.Source then S.SetFont(info.Source, 12, "") end
        if info.Lore then S.SetFont(info.Lore, 12, "") end

    end

    S.Button(_G.MountJournalMountButton)
    S.EditBox(_G.MountJournalSearchBox)
    S.ScrollBar(MountJournal.ScrollBar)

    S.Inset(MountJournal.LeftInset)
    S.Inset(MountJournal.BottomLeftInset)
    S.Backdrop(MountJournal.BottomLeftInset)

    local slotBtn = MountJournal.BottomLeftInset.SlotButton
    S.Icon(slotBtn.ItemIcon)
    S.Button(slotBtn, slotBtn.ItemIcon)

    slotBtn.ItemIcon:ClearAllPoints()
    slotBtn.ItemIcon:SetPoint("TOPLEFT", slotBtn, "TOPLEFT", 1, -1)
    slotBtn.ItemIcon:SetPoint("BOTTOMRIGHT", slotBtn, "BOTTOMRIGHT", -1, 1)
    Crop(slotBtn.ItemIcon)
    for _, r in ipairs({ slotBtn:GetRegions() }) do
        if r.IsObjectType and r:IsObjectType("Texture") and r ~= slotBtn.ItemIcon then
            r:SetAlpha(0)

            hooksecurefunc(r, "SetAlpha", function(rr, a)
                local dd = S.data(rr)
                if a ~= 0 and not dd.aSetting then
                    dd.aSetting = true
                    rr:SetAlpha(0)
                    dd.aSetting = nil
                end
            end)
        end
    end
    hooksecurefunc(MountJournal.ScrollBox, "Update", MountRows)
    hooksecurefunc("MountJournal_InitMountButton", MountRowText)
end

local function SkinPets()
    local PetJournal = _G.PetJournal

    S.StripTextures(_G.PetJournalSummonButton)
    S.StripTextures(_G.PetJournalFindBattle)
    S.Button(_G.PetJournalSummonButton)
    S.Button(_G.PetJournalFindBattle)
    S.Inset(_G.PetJournalRightInset)
    S.Inset(_G.PetJournalLeftInset)
    S.ItemButton(PetJournal.SummonRandomPetSpellFrame.Button, true)

    S.StripTextures(PetJournal.PetCount)
    S.FontStrings(PetJournal.PetCount, 12, "")
    S.EditBox(_G.PetJournalSearchBox)
    _G.PetJournalSearchBox:ClearAllPoints()
    _G.PetJournalSearchBox:SetPoint("TOPLEFT", _G.PetJournalLeftInset, "TOPLEFT", 13, -9)

    S.Button(PetJournal.FilterDropdown)
    UniformFilter(PetJournal.FilterDropdown, _G.PetJournalSearchBox)
    S.CloseButton(PetJournal.FilterDropdown.ResetButton)
    PetJournal.FilterDropdown.ResetButton:ClearAllPoints()
    PetJournal.FilterDropdown.ResetButton:SetPoint("CENTER", PetJournal.FilterDropdown, "TOPRIGHT", 0, 0)

    S.ScrollBar(PetJournal.ScrollBar)
    hooksecurefunc(PetJournal.ScrollBox, "Update", PetRows)

    _G.PetJournalAchievementStatus:DisableDrawLayer("BACKGROUND")

    S.ItemButton(PetJournal.HealPetSpellFrame.Button, true)
    PetJournal.HealPetSpellFrame.Button.Icon:SetTexture([[Interface\Icons\spell_magic_polymorphrabbit]])
    S.StripTextures(_G.PetJournalLoadoutBorder)
    S.StripTextures(_G.PetJournalSpellSelect)

    for i = 1, 3 do
        local petButton = _G["PetJournalLoadoutPet" .. i]
        local petButtonHighlight = _G["PetJournalLoadoutPet" .. i .. "Highlight"]
        local petButtonHealthFrame = _G["PetJournalLoadoutPet" .. i .. "HealthFrame"]
        local petButtonXPBar = _G["PetJournalLoadoutPet" .. i .. "XPBar"]
        S.StripTextures(petButton)
        S.Template(petButton, "Default")
        petButton.petTypeIcon:SetPoint("BOTTOMLEFT", 2, 2)

        petButtonHighlight:SetTexture("Interface\\Buttons\\WHITE8x8")
        petButtonHighlight:SetVertexColor(1, 1, 1, 0.25)
        petButtonHighlight:SetAllPoints(petButton.icon)

        S.StripTextures(_G["PetJournalLoadoutPet" .. i .. "HelpFrame"])

        petButton.dragButton:ClearAllPoints()
        petButton.dragButton:SetPoint("TOPLEFT", _G["PetJournalLoadoutPet" .. i .. "Icon"], "TOPLEFT", -1, 1)
        petButton.dragButton:SetPoint("BOTTOMRIGHT", _G["PetJournalLoadoutPet" .. i .. "Icon"], "BOTTOMRIGHT", 1, -1)

        S.ItemButton(petButton, "keepAnchors")
        if petButton.qualityBorder then S.IconBorder(petButton.qualityBorder, S.GetBackdrop(petButton)) end

        petButton.levelBG:SetTexture()
        S.SetFont(petButton.level, 12, "OUTLINE")

        S.StripTextures(petButton.setButton)
        S.StripTextures(petButtonHealthFrame.healthBar)
        S.Backdrop(petButtonHealthFrame.healthBar)
        petButtonHealthFrame.healthBar:SetStatusBarTexture(BarTex())
        S.StripTextures(petButtonXPBar)
        S.Backdrop(petButtonXPBar)
        petButtonXPBar:SetStatusBarTexture(BarTex())

        for index = 1, 3 do
            local sf = _G["PetJournalLoadoutPet" .. i .. "Spell" .. index]
            S.ItemButton(sf)
            sf.FlyoutArrow:SetTexture([[Interface\Buttons\ActionBarFlyoutButton]])
            SetInsideOf(_G["PetJournalLoadoutPet" .. i .. "Spell" .. index .. "Icon"], sf)
        end
    end

    for i = 1, 2 do
        local btn = _G["PetJournalSpellSelectSpell" .. i]
        S.ItemButton(btn)
        local icon = _G["PetJournalSpellSelectSpell" .. i .. "Icon"]
        SetInsideOf(icon, btn)
        icon:SetDrawLayer("BORDER")
    end

    local Card = _G.PetJournalPetCard
    S.StripTextures(Card)
    S.Template(Card, "Window")
    S.Inset(_G.PetJournalPetCardInset)

    local info = Card.PetInfo
    S.SetFont(info.level, 12, "OUTLINE")
    info.levelBG:SetTexture()
    S.SlotIcon(info.icon, info.qualityBorder)
    if info.qualityBorder then info.qualityBorder:SetAlpha(0) end

    for i = 1, 6 do
        local sframe = _G["PetJournalPetCardSpell" .. i]
        sframe:DisableDrawLayer("BACKGROUND")
        S.Template(sframe, "Default")
        Crop(sframe.icon)
    end

    S.StripTextures(Card.HealthFrame.healthBar)
    S.Backdrop(Card.HealthFrame.healthBar)
    Card.HealthFrame.healthBar:SetStatusBarTexture(BarTex())

    S.StripTextures(Card.xpBar)
    S.Backdrop(Card.xpBar)
    Card.xpBar:SetStatusBarTexture(BarTex())
end

local function SkinToys()
    local ToyBox = _G.ToyBox
    S.EditBox(ToyBox.searchBox)

    S.Button(ToyBox.FilterDropdown)
    UniformFilter(ToyBox.FilterDropdown, ToyBox.searchBox)
    S.CloseButton(ToyBox.FilterDropdown.ResetButton)
    ToyBox.FilterDropdown.ResetButton:ClearAllPoints()
    ToyBox.FilterDropdown.ResetButton:SetPoint("CENTER", ToyBox.FilterDropdown, "TOPRIGHT", 0, 0)

    S.StripTextures(ToyBox.iconsFrame)
    S.ArrowButton(ToyBox.PagingFrame.NextPageButton, "right")
    S.ArrowButton(ToyBox.PagingFrame.PrevPageButton, "left")

    ToyBox.progressBar.border:Hide()
    ToyBox.progressBar:DisableDrawLayer("BACKGROUND")
    ToyBox.progressBar:SetStatusBarTexture(BarTex())
    S.Backdrop(ToyBox.progressBar)
    S.FontStrings(ToyBox.progressBar, 12, "OUTLINE")

    for i = 1, 18 do
        local button = ToyBox.iconsFrame["spellButton" .. i]
        S.ItemButton(button, true)
        Crop(button.iconTextureUncollected)
        SetInsideOf(button.iconTextureUncollected, button)
        if button.hover then button.hover:SetAllPoints(button.iconTexture) end
        if button.checked then button.checked:SetAllPoints(button.iconTexture) end
        if button.pushed then button.pushed:SetAllPoints(button.iconTexture) end
        if button.cooldown then button.cooldown:SetAllPoints(button.iconTexture) end
    end

    hooksecurefunc("ToySpellButton_UpdateButton", ToyButtonQuality)
    hooksecurefunc("ToySpellButton_UpdateButton", ToyRowText)
end

local function SkinHeirlooms()
    local HJ = _G.HeirloomsJournal
    S.EditBox(HJ.SearchBox)
    S.StripTextures(HJ.iconsFrame)

    S.ArrowButton(HJ.PagingFrame.NextPageButton, "right")
    S.ArrowButton(HJ.PagingFrame.PrevPageButton, "left")
    pcall(S.DropDown, HJ.ClassDropdown)

    S.Button(HJ.FilterDropdown)
    UniformFilter(HJ.FilterDropdown, HJ.SearchBox)
    S.CloseButton(HJ.FilterDropdown.ResetButton)
    HJ.FilterDropdown.ResetButton:ClearAllPoints()
    HJ.FilterDropdown.ResetButton:SetPoint("CENTER", HJ.FilterDropdown, "TOPRIGHT", 0, 0)

    HJ.progressBar.border:Hide()
    HJ.progressBar:DisableDrawLayer("BACKGROUND")
    HJ.progressBar:SetStatusBarTexture(BarTex())
    S.Backdrop(HJ.progressBar)
    S.FontStrings(HJ.progressBar, 12, "OUTLINE")

    hooksecurefunc(HJ, "UpdateButton", HeirloomButton)
    hooksecurefunc(HJ, "LayoutCurrentPage", HeirloomHeaders)
end

local function MoveAppearancesTab()
    local t2, t4, t5 = _G.CollectionsJournalTab2, _G.CollectionsJournalTab4, _G.CollectionsJournalTab5
    if not (t2 and t4 and t5) then return end
    local point, _, relPoint, x, y = t2:GetPoint(1)
    if not point then return end
    t5:ClearAllPoints()
    t5:SetPoint(point, t4, relPoint, x, y)
end

local function SkinJournalTabs()

    local index = 1
    local tab = _G.CollectionsJournalTab1
    while tab do
        S.Tab(tab)
        index = index + 1
        tab = _G["CollectionsJournalTab" .. index]
    end
    MoveAppearancesTab()
    hooksecurefunc("CollectionsJournal_CheckAndDisplayHeirloomsTab", MoveAppearancesTab)

    local function SettleTabs()
        local cj = _G.CollectionsJournal
        if cj and _G.PanelTemplates_UpdateTabs then
            _G.PanelTemplates_UpdateTabs(cj)
        end
        MoveAppearancesTab()
    end
    if _G.CollectionsJournal and _G.CollectionsJournal.HookScript then
        _G.CollectionsJournal:HookScript("OnShow", function()
            if _G.C_Timer then _G.C_Timer.After(0, SettleTabs) else SettleTabs() end
        end)
    end
    if _G.C_Timer then _G.C_Timer.After(0, SettleTabs) end
end

local function SkinWardrobe()
    local WCF = _G.WardrobeCollectionFrame
    S.Tab(_G.WardrobeCollectionFrameTab1)
    S.Tab(_G.WardrobeCollectionFrameTab2)

    local ProgressBar = WCF.progressBar
    if ProgressBar then
        ProgressBar.border:Hide()
        ProgressBar:DisableDrawLayer("BACKGROUND")
        ProgressBar:SetStatusBarTexture(BarTex())
        S.Backdrop(ProgressBar)
        S.FontStrings(ProgressBar, 12, "OUTLINE")
    end

    S.EditBox(_G.WardrobeCollectionFrameSearchBox)
    _G.WardrobeCollectionFrameSearchBox:SetFrameLevel(5)
    pcall(S.DropDown, WCF.ClassDropdown)

    S.Button(WCF.FilterButton)
    UniformFilter(WCF.FilterButton, WCF.searchBox)
    S.CloseButton(WCF.FilterButton.ResetButton)
    WCF.FilterButton.ResetButton:ClearAllPoints()
    WCF.FilterButton.ResetButton:SetPoint("CENTER", WCF.FilterButton, "TOPRIGHT", 0, 0)

    pcall(S.DropDown, WCF.ItemsCollectionFrame.WeaponDropdown)
    S.StripTextures(WCF.ItemsCollectionFrame)
    S.Template(WCF.ItemsCollectionFrame, "Window")

    for _, Frame in ipairs(WCF.ContentFrames) do
        if Frame.Models then
            for _, Model in pairs(Frame.Models) do
                Model.Border:SetAlpha(0)
                Model.TransmogStateTexture:SetAlpha(0)

                local border = CreateFrame("Frame", nil, Model, "BackdropTemplate")
                S.Backdrop(border)
                local mbd = S.GetBackdrop(border) or border
                border:ClearAllPoints()
                border:SetPoint("TOPLEFT", Model, "TOPLEFT", 0, 1)
                border:SetPoint("BOTTOMRIGHT", Model, "BOTTOMRIGHT", 1, -1)
                if mbd.SetBackdropColor then mbd:SetBackdropColor(0, 0, 0, 0) end

                if Model.NewGlow then Model.NewGlow:SetParent(border) end
                if Model.NewString then Model.NewString:SetParent(border) end

                -- The state overlays aren't keyed on this template, so they're
                -- found by texture. The two that are keyed are excluded by
                -- identity rather than by matching their debug names.
                local keyed = {
                    [Model.SlotInvalidTexture or false] = true,
                    [Model.DisabledOverlay or false] = true,
                }

                for _, region in next, { Model:GetRegions() } do
                    if region:IsObjectType("Texture") then
                        local texture = region:GetTexture()
                        if texture == MODEL_HOVER_TEX
                            or (texture == MODEL_STATE_TEX and not keyed[region]) then
                            region:SetColorTexture(1, 1, 1, 0.25)
                            region:SetBlendMode("ADD")
                            region:SetAllPoints(Model)
                        end
                    end
                end

                hooksecurefunc(Model.Border, "SetAtlas", function(_, atlas)
                    local target = mbd.SetBackdropBorderColor and mbd
                    if not target then return end

                    local c = WARDROBE_BORDER[atlas]
                    if c then
                        target:SetBackdropBorderColor(c[1], c[2], c[3])
                    elseif Model.TransmogStateTexture:IsShown() then
                        target:SetBackdropBorderColor(WARDROBE_PENDING[1], WARDROBE_PENDING[2], WARDROBE_PENDING[3])
                    else
                        RestBorder(target)
                    end
                end)
            end
        end

        local paging = Frame.PagingFrame
        if paging then
            S.ArrowButton(paging.PrevPageButton, "left")
            S.ArrowButton(paging.NextPageButton, "right")
        end
    end

    local SetsCollectionFrame = WCF.SetsCollectionFrame
    S.Template(SetsCollectionFrame, "Window")
    S.Inset(SetsCollectionFrame.RightInset)
    S.Inset(SetsCollectionFrame.LeftInset)
    S.ScrollBar(SetsCollectionFrame.ListContainer.ScrollBar)
    hooksecurefunc(SetsCollectionFrame.ListContainer.ScrollBox, "Update", SetRows)

    local DetailsFrame = SetsCollectionFrame.DetailsFrame
    DetailsFrame.ModelFadeTexture:Hide()
    DetailsFrame.IconRowBackground:Hide()
    S.SetFont(DetailsFrame.Name, 16, "OUTLINE")
    S.SetFont(DetailsFrame.LongName, 16, "OUTLINE")
    pcall(S.DropDown, DetailsFrame.VariantSetsDropdown)
    hooksecurefunc(SetsCollectionFrame, "SetItemFrameQuality", SetItemQuality)
end

-- Scene tiles carry their art outside the icon bounds, so the plate sits a few
-- pixels proud of it and one level below the tile itself.
local SCENE_PLATE_INSET = 5

local function OnWarbandSceneData(frame)
    if not frame or not frame.warbandSceneInfo then return end
    if S.data(frame).artBD then return end

    local plate = CreateFrame("Frame", nil, frame)
    S.data(frame).artBD = plate

    plate:SetFrameLevel(math.max(frame:GetFrameLevel() - 1, 0))
    plate:ClearAllPoints()
    plate:SetPoint("TOPLEFT", frame.Icon, "TOPLEFT", -SCENE_PLATE_INSET, SCENE_PLATE_INSET)
    plate:SetPoint("BOTTOMRIGHT", frame.Icon, "BOTTOMRIGHT", SCENE_PLATE_INSET, -SCENE_PLATE_INSET)
    S.Backdrop(plate)

    frame.Border:SetAlpha(0)
    S.Icon(frame.Icon)

    if not frame.SetHighlightTexture then return end

    local hover = frame:CreateTexture()
    hover:SetColorTexture(1, 1, 1, 0.25)
    hover:SetAllPoints(frame.Icon)
    frame:SetHighlightTexture(hover)
end

local function SkinPagingControls(paging)
    S.ArrowButton(paging.PrevPageButton, "left")
    S.ArrowButton(paging.NextPageButton, "right")
end

local function SkinSceneControls(controls)
    local box = controls.ShowOwned and controls.ShowOwned.Checkbox
    if box then
        box:SetSize(28, 28)
        S.CheckBox(box)
    end

    S.Apply(controls, { PagingControls = SkinPagingControls })
end

local function SkinSceneIcons(icons)
    S.StripTextures(icons)

    if icons.NineSlice then
        S.StripTextures(icons.NineSlice, true)
        S.Backdrop(icons)
    end

    if icons.Icons then S.Apply(icons.Icons, { Controls = SkinSceneControls }) end
end

local function SkinWarbandScenes()
    local Frame = _G.WarbandSceneJournal
    if not Frame then return end
    S.Apply(Frame, { IconsFrame = SkinSceneIcons })
    if _G.WarbandSceneEntryMixin then
        hooksecurefunc(_G.WarbandSceneEntryMixin, "UpdateWarbandSceneData", OnWarbandSceneData)
    end
end

local function Skin()
    if not _G.CollectionsJournal then return end
    S.Frame(_G.CollectionsJournal)
    SkinWardrobe()
    SkinJournalTabs()
    SkinMounts()
    SkinPets()
    SkinToys()
    SkinHeirlooms()
    SkinWarbandScenes()
end

S:Register("Blizzard_Collections", Skin, "Collectables")


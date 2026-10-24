local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local hooksecurefunc = hooksecurefunc

local SLOTS = {
    "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist",
    "Hands", "Waist", "Legs", "Feet", "Finger0", "Finger1", "Trinket0",
    "Trinket1", "MainHand", "SecondaryHand", "Ranged", "Ammo",
}

local STAT_CATEGORIES = { "ItemLevelCategory", "AttributesCategory", "EnhancementsCategory" }

local ILVL_SIZE, HEADER_SIZE, ROW_SIZE = 20, 14, 12
local HEADER_INSET = 6

-- The ammo slot draws an arrow overlay alone in an unnamed child frame. Found
-- by its atlas: the slot's own backdrop is a child frame too, and so is its
-- cooldown.
local AMMO_ARROW_ATLAS = "UI-Character-Info-GearSlot-Arrow"
local function HideAmmoArrow(button)
    for _, child in ipairs({ button:GetChildren() }) do
        local region = child.GetRegions and child:GetRegions()
        if region and region.GetAtlas and region:GetAtlas() == AMMO_ARROW_ATLAS then
            S.KillTexture(region)
        end
    end
end

local ItemLocation = ItemLocation

local ILVL_FONT = 13
local TITLE_FONT = 13
local STAT_GRAD_WIDTH = 80
local STAT_GRAD_TEX = "Interface\\Buttons\\WHITE8x8"

-- Slot item level and gem icons are drawn by CharacterPanel.lua, not here.

-- Two mirrored fades from the row's center outward, replacing the plate rather
-- than merely hiding it.
--
-- The alpha is re-asserted on EVERY pass, not once: these rows come from a
-- frame pool and Blizzard re-shows the plate whenever a row is reacquired, so a
-- one-time blank comes back.
local function ColorizeStatPane(frame)
    if not frame then return end

    if frame.Background and frame.Background.SetAlpha then frame.Background:SetAlpha(0) end

    if S.data(frame).statGrad then return end
    S.data(frame).statGrad = true

    local r, g, b = 0.8, 0.8, 0.8
    local solid, clear = CreateColor(r, g, b, 0.25), CreateColor(r, g, b, 0)

    local right = frame:CreateTexture(nil, "BORDER")
    right:SetTexture(STAT_GRAD_TEX)
    right:SetPoint("TOPLEFT", frame, "TOP")
    right:SetPoint("BOTTOMLEFT", frame, "BOTTOM")
    right:SetWidth(STAT_GRAD_WIDTH)
    right:SetGradient("HORIZONTAL", solid, clear)

    local left = frame:CreateTexture(nil, "BORDER")
    left:SetTexture(STAT_GRAD_TEX)
    left:SetPoint("TOPRIGHT", frame, "TOP")
    left:SetPoint("BOTTOMRIGHT", frame, "BOTTOM")
    left:SetWidth(STAT_GRAD_WIDTH)
    left:SetGradient("HORIZONTAL", clear, solid)

    -- Handles kept in S.data, never as fields on the Blizzard frame.
    S.data(frame).statGradL, S.data(frame).statGradR = left, right
end
S._ColorizeStatPane = ColorizeStatPane

-- One stat row: its fonts once, then the gradients. Blizzard stripes the
-- plate down the list, on for one row and off for the next; the gradients
-- follow that rather than blooming every row.
local function StyleStatLine(row)
    local d = S.data(row)
    if not d.statFonted then
        d.statFonted = true
        S.FontStrings(row, ROW_SIZE, "OUTLINE")
    end
    local shown = row.Background and row.Background:IsShown()
    ColorizeStatPane(row)
    if d.statGradL then d.statGradL:SetShown(shown) end
    if d.statGradR then d.statGradR:SetShown(shown) end
end

local function UpdateStatsPane()
    local pane = _G.CharacterStatsPane
    if not pane then return end

    if pane.ItemLevelFrame then
        ColorizeStatPane(pane.ItemLevelFrame)
        if pane.ItemLevelFrame.Value then
            S.SetFont(pane.ItemLevelFrame.Value, ILVL_SIZE, "OUTLINE")

            local _, equipped = GetAverageItemLevel()
            if equipped then pane.ItemLevelFrame.Value:SetText(string.format("%.2f", equipped)) end
        end
    end
    for _, cat in ipairs(STAT_CATEGORIES) do
        if pane[cat] then S.FontStrings(pane[cat], HEADER_SIZE, "OUTLINE") end
    end

    if pane.statsFramePool and pane.statsFramePool.EnumerateActive then
        for row in pane.statsFramePool:EnumerateActive() do
            StyleStatLine(row)
        end
    end
end

-- A client that lists the stats in a ScrollBox: header rows carry a Title,
-- stat rows a Label and a Value. The pooled pane above stays, hidden there.
local function StyleStatsScrollRow(row)
    if not row.Title then return StyleStatLine(row) end
    local d = S.data(row)
    if d.keStatHeader then return end
    d.keStatHeader = true
    S.StripTextures(row)
    local bd = S.Backdrop(row)
    if bd then
        bd:ClearAllPoints()
        bd:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -HEADER_INSET)
        bd:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, HEADER_INSET)
    end
    S.FontStrings(row, HEADER_SIZE, "OUTLINE")
end

-- The player's list and the pet's, which the pet sidebar tab shows; both use
-- the same template.
local STATS_HOSTS = { "CharacterStatsPaneScrollBox", "CharacterStatsPanePetScrollBox" }

local function SkinStatsScrollBox()
    for _, name in ipairs(STATS_HOSTS) do
        local host = _G[name]
        if host then
            S.StripTextures(host)
            if host.ScrollBar then S.ScrollBar(host.ScrollBar) end
            if host.ScrollBox then S.HookScrollBox(host.ScrollBox, StyleStatsScrollRow) end
        end
    end
    -- The pet tab's experience bar is a colored progress bar.
    S.ColoredBar(_G.PetPaperDollFrameExpBar)
end

local statsHooked = false

local function SkinStatsPane()
    local pane = _G.CharacterStatsPane
    if not pane then return end

    local title = (_G.CharacterFrame and _G.CharacterFrame.TitleContainer and _G.CharacterFrame.TitleContainer.TitleText)
        or _G.CharacterFrameTitleText
    if title then S.SetFont(title, 14, "OUTLINE") end

    if _G.CharacterLevelText then S.SetFont(_G.CharacterLevelText, nil, "OUTLINE") end

    for _, cat in ipairs(STAT_CATEGORIES) do
        if pane[cat] then
            S.StripTextures(pane[cat])
            if not S.data(pane[cat]).keHeaderBox then
                S.Backdrop(pane[cat])
                S.data(pane[cat]).keHeaderBox = true
            end

            local bd = S.GetBackdrop(pane[cat])
            if bd then
                bd:ClearAllPoints()
                bd:SetPoint("TOPLEFT", pane[cat], "TOPLEFT", 0, -HEADER_INSET)
                bd:SetPoint("BOTTOMRIGHT", pane[cat], "BOTTOMRIGHT", 0, HEADER_INSET)
            end
        end
    end

    -- CharacterFrameInset added -- it was missing from this list, so
    -- Blizzard's inset art was never stripped. It only stayed hidden
    -- while our old KillTexture NOOP'd the setters addon-wide; once
    -- that went, the art came back on tab switches.
    for _, name in ipairs({ "CharacterStatsPane", "CharacterModelScene", "CharacterFrameInset",
                            "CharacterFrameInsetRight", "PaperDollSidebarTabs" }) do
        if _G[name] then S.StripTextures(_G[name]) end
    end

    UpdateStatsPane()
    SkinStatsScrollBox()
    if not statsHooked and _G.PaperDollFrame_UpdateStats then
        hooksecurefunc("PaperDollFrame_UpdateStats", UpdateStatsPane)
        statsHooked = true
    end
end

-- A sidebar tab without TabBg draws its frame from an unnamed region under
-- this atlas and marks the open pane with an atlas checked texture.
local STAT_TAB_ATLAS = "UI-Character-Info-StatTab"

local function DressStatTabArt(tab)
    for _, region in ipairs({ tab:GetRegions() }) do
        if region:IsObjectType("Texture") and region:GetAtlas() == STAT_TAB_ATLAS then
            S.KillTexture(region)
        end
    end
    local checked = tab.GetCheckedTexture and tab:GetCheckedTexture()
    if checked then
        S.PaintBrand(checked, "SetColorTexture", S.palette.selectedA)
        S.InsetToEdge(checked, S.GetBackdrop(tab))
    end
end

local function SkinSidebarTabs()
    for i = 1, 4 do
        local tab = _G["PaperDollSidebarTab" .. i]
        if tab and not S.data(tab).keTabSkinned then
            -- (art flashed on open): SetAlpha(0) is
            -- state -- Blizzard re-dresses it every show, so TabBg has
            -- to be Killed rather than faded.
            if tab.TabBg then S.Kill(tab.TabBg) end
            S.Backdrop(tab)
            if not tab.TabBg then DressStatTabArt(tab) end
            if tab.Icon and tab.Icon.SetAllPoints then tab.Icon:SetAllPoints() end
            if tab.Highlight and tab.Highlight.SetColorTexture then

                tab.Highlight:SetColorTexture(S.palette.hover[1], S.palette.hover[2], S.palette.hover[3], S.palette.hover[4])
                tab.Highlight:ClearAllPoints()
                tab.Highlight:SetPoint("TOPLEFT", tab, "TOPLEFT", 1, -1)
                tab.Highlight:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -1, 1)
            end

            if tab.Hider and tab.Hider.SetColorTexture then
                tab.Hider:SetColorTexture(0, 0, 0, 0.5)
                if tab.Icon then
                    tab.Hider:ClearAllPoints()
                    tab.Hider:SetAllPoints(tab.Icon)
                end
            end
            S.data(tab).keTabSkinned = true
        end
    end
end

local function StyleTitleRow(child)
    if not child or S.data(child).keTitleSkinned then return end
    if child.DisableDrawLayer then child:DisableDrawLayer("BACKGROUND") end

    S.RowHover(child)
    S.FontStrings(child, TITLE_FONT, "")
    S.data(child).keTitleSkinned = true
end

local function SkinTitlesPane()
    local pane = _G.PaperDollFrame and _G.PaperDollFrame.TitleManagerPane
    if not pane then return end
    if pane.ScrollBar then S.ScrollBar(pane.ScrollBar) end
    if pane.ScrollBox then S.HookScrollBox(pane.ScrollBox, StyleTitleRow) end
end

local EQUIP_FONT = 13
local EQUIP_HOVER_ALPHA = 0.30
local function StyleEquipRow(child)
    if not child or not child.icon or S.data(child).keEquipSkinned then return end
    if child.BgTop then child.BgTop:SetTexture(nil) end
    if child.BgMiddle then child.BgMiddle:SetTexture(nil) end
    if child.BgBottom then child.BgBottom:SetTexture(nil) end
    S.Icon(child.icon, true)
    if child.HighlightBar then
        child.HighlightBar:SetColorTexture(1, 1, 1, EQUIP_HOVER_ALPHA)
        child.HighlightBar:SetDrawLayer("BACKGROUND")
    end
    if child.SelectedBar then
        S.PaintBrand(child.SelectedBar, "SetColorTexture", S.palette.selectedA)
        child.SelectedBar:SetDrawLayer("BACKGROUND")
    end
    S.FontStrings(child, EQUIP_FONT, "")
    S.data(child).keEquipSkinned = true
end

local function ShrinkSetButtons()

    local pane = _G.PaperDollFrame and _G.PaperDollFrame.EquipmentManagerPane
    if not pane then return end
    local equip, save = pane.EquipSet, pane.SaveSet
    if equip and not S.data(equip).keShrunk then
        equip:SetWidth((equip:GetWidth() or 85) - 2)
        S.data(equip).keShrunk = true
    end
    if save and equip and not S.data(save).keGapped then
        save:SetWidth((save:GetWidth() or 85) - 2)
        local pt, rel, relPt, x, y = save:GetPoint(1)
        if rel == equip then
            save:ClearAllPoints()
            save:SetPoint(pt, rel, relPt, (x or 0) + 1, y or 0)
        end
        S.data(save).keGapped = true
    end
end

local function SkinEquipmentManagerPane()
    local pane = _G.PaperDollFrame and _G.PaperDollFrame.EquipmentManagerPane
    if not pane then return end
    if pane.ScrollBar then S.ScrollBar(pane.ScrollBar) end
    if pane.ScrollBox then S.HookScrollBox(pane.ScrollBox, StyleEquipRow) end
    if pane.EquipSet then S.Button(pane.EquipSet) end
    if pane.SaveSet then S.Button(pane.SaveSet) end
    ShrinkSetButtons()
end

-- Rarity borders are ON unless the key says otherwise, and ON when the profile
-- section is missing entirely, so a fresh profile gets the default look rather
-- than a silently different one. Deliberately NOT gated on the CharacterPanel
-- module's Enabled flag: this is skinning, it paints whether or not that module
-- runs, which is why its control sits outside that module's gate.
local function QualityBordersOn(cpDB)
    if not cpDB then return true end
    return cpDB.SlotQualityBorders ~= false
end
S._QualityBordersOn = QualityBordersOn

-- Flyout treatment: clear state art by passing S.ClearTexture
-- (fileID 0) to the BUTTON's setters. No contact with the texture
-- objects at all -- which is what tainted this display loop for
-- thirteen versions. S.ClearButtonArt also installs the
-- re-clear-on-set hooks, so Blizzard re-dressing can't bring the art
-- back (no flash) and nothing gets NOOP'd (no taint).
local function KillFlyoutStates(button)
    S.ClearButtonArt(button, true) -- keepHighlight: S.Hover owns it
end

local function SkinFlyoutButton(button)
    if not button or S.data(button).skinned then return end
    S.ItemButton(button)
    KillFlyoutStates(button)

    -- the per-button method hooks (SetNormalTexture etc.,
    -- IconBorder Show-suppressor) fired INSIDE DisplayButton -- before
    -- the location write -- and were the remaining taint injectors
    -- (a post-hoc audit found even button1 tainted). No hooks at all
    -- now: state/border kills re-run in every deferred pass instead;
    -- worst case is a sub-0.1s art flash when Blizzard re-dresses.
    if button.IconBorder then
        button.IconBorder:SetAlpha(0)
    end
    S.Hover(button)
    S.data(button).skinned = true
end

local function UpdateFlyoutILvl(button) -- luacheck: ignore 211/UpdateFlyoutILvl
    if not button then return end
    if not S.data(button).flyoutILvl then
        -- fontstring ref moved off the button (tainted-key
        -- contamination, see S.ItemButton).
        local t = button:CreateFontString(nil, "OVERLAY")

        S.SetFont(t, ILVL_FONT, "OUTLINE")
        t:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
        t:SetJustifyH("RIGHT")
        S.data(button).flyoutILvl = t
    end

    local loc = button.location
    local INVALID = 4294967295
    local itemLoc
    if type(loc) == "table" then
        -- ("compare table with number" from the
        -- Item Upgrade UI): Midnight's upgrade flyout populates
        -- button.location with an ItemLocation-style TABLE instead of
        -- the legacy packed integer. Feeding that to
        -- EquipmentManager_GetLocationData explodes on its first
        -- numeric comparison. Use the table directly: real mixins pass
        -- through, bare field tables get rebuilt via ItemLocation.
        if loc.GetBagAndSlot or loc.IsEquipmentSlot then
            itemLoc = loc
        elseif loc.bagID ~= nil and loc.slotIndex ~= nil and ItemLocation then
            itemLoc = ItemLocation:CreateFromBagAndSlot(loc.bagID, loc.slotIndex)
        elseif loc.equipmentSlotIndex ~= nil and ItemLocation then
            itemLoc = ItemLocation:CreateFromEquipmentSlot(loc.equipmentSlotIndex)
        end
    elseif type(loc) == "number" and loc ~= INVALID
        and _G.EquipmentManager_GetLocationData and ItemLocation then
        local d = _G.EquipmentManager_GetLocationData(loc)
        if d and d.isBags and d.bag and d.slot then
            itemLoc = ItemLocation:CreateFromBagAndSlot(d.bag, d.slot)
        elseif d and d.isPlayer and d.slot then
            itemLoc = ItemLocation:CreateFromEquipmentSlot(d.slot)
        end
    end

    local ilvl, quality
    if itemLoc and C_Item.DoesItemExist(itemLoc) then
        ilvl = C_Item.GetCurrentItemLevel(itemLoc)
        quality = C_Item.GetItemQuality and C_Item.GetItemQuality(itemLoc)
    end

    if ilvl and ilvl > 0 then
        S.data(button).flyoutILvl:SetText(ilvl)
        local c = quality and _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality]
        if c then
            S.data(button).flyoutILvl:SetTextColor(c.r, c.g, c.b)
        else
            S.data(button).flyoutILvl:SetTextColor(1, 1, 1)
        end
        S.data(button).flyoutILvl:Show()
    else
        S.data(button).flyoutILvl:SetText("")
        S.data(button).flyoutILvl:Hide()
    end
end

local function EquipmentFlyoutSkin()
    local flyout = _G.EquipmentFlyoutFrame
    if not flyout then return end
    -- Three lines for the flyout chrome: StripTextures the highlight,
    -- alpha-0 bg1, DisableDrawLayer the rest. None of these get Killed
    -- now that the kill primitive carries redirect semantics.
    if flyout.Highlight then S.StripTextures(flyout.Highlight) end

    local ghl = _G.EquipmentFlyoutFrameHighlight
    if ghl and not S.data(ghl).killed then
        S.StripTextures(ghl)
        if ghl.SetAlpha then ghl:SetAlpha(0) end
        S.data(ghl).killed = true
    end
    local holder = flyout.buttonFrame or _G.EquipmentFlyoutFrameButtons
    if holder and not S.data(holder).skinned then
        S.StripTextures(holder)
        if holder.bg1 and holder.bg1.SetAlpha then holder.bg1:SetAlpha(0) end
        if holder.bg2 and holder.bg2.SetAlpha then holder.bg2:SetAlpha(0) end

        if holder.DisableDrawLayer then holder:DisableDrawLayer("ARTWORK") end
        S.Backdrop(holder)
        S.data(holder).skinned = true
    end
    local qualityBorders = QualityBordersOn(KE.db and KE.db.profile and KE.db.profile.CharacterPanel)
    if flyout.buttons then
        for _, button in ipairs(flyout.buttons) do
            SkinFlyoutButton(button)
            KillFlyoutStates(button) -- re-kill per pass (no hooks)
            if button.IconBorder then button.IconBorder:SetAlpha(0) end
            -- flyout ilvl RETIRED -- the flyout skin is art-only, with
            -- zero item-data reads. Reading item data mid-flow here is
            -- what broke on Midnight. All flyout item-data reads are
            -- gone now.
            if S.data(button).flyoutILvl then S.data(button).flyoutILvl:Hide() end

            -- Blizzard already colors IconBorder by quality, so read that
            -- color rather than item data. Buttons are reused across slots,
            -- so every path here writes: a bail would leave the previous
            -- item's rarity sitting on the backdrop.
            local bd = S.GetBackdrop(button)
            if bd then
                local r, g, b
                if qualityBorders then
                    -- IsShown carries SecretReturnsForAspect, and comparing a
                    -- secret boolean throws, so secrecy is asked first.
                    local shown = button.IconBorder and button.IconBorder:IsShown()
                    if KE:NotSecretValue(shown) and shown == true then
                        -- GetVertexColor is MayReturnNothing as well as
                        -- secret-annotated. A nil is not secret, so it needs
                        -- its own test or it reaches SetBackdropBorderColor.
                        r, g, b = button.IconBorder:GetVertexColor()
                        if KE:IsSecretValue(r) or KE:IsSecretValue(g) or KE:IsSecretValue(b)
                            or r == nil or g == nil or b == nil then
                            r, g, b = nil, nil, nil
                        end
                    end
                end
                if r then
                    bd:SetBackdropBorderColor(r, g, b, 1)
                else
                    bd:SetBackdropBorderColor(S.borderColor[1], S.borderColor[2],
                        S.borderColor[3], S.borderColor[4])
                end
            end
        end
    end

end

local function EquipmentFlyoutNav()
    local navi = _G.EquipmentFlyoutFrame and _G.EquipmentFlyoutFrame.NavigationFrame
    if not navi or S.data(navi).skinned then return end
    S.StripTextures(navi)
    S.Backdrop(navi)
    S.data(navi).skinned = true
end

local flyoutHooked = false

-- Per-tab inset backdrop, hooked on CharacterFrame:ShowSubFrame.
-- The list tabs want a dark inset behind their rows; the paperdoll
-- does not -- that is the backdrop  saw sticking around after
-- tab switching.
local showInsetBackdrop = {
    ReputationFrame = true,
    TokenFrame = true,
}

local function UpdateCharacterInset(a, b)
    -- The hook passes (self, name); the skin's own call passes (name).
    local name = (type(b) == "string" and b) or (type(a) == "string" and a) or nil
    local inset = _G.CharacterFrameInset

    -- (art returns on Currency -> Reputation ->
    -- Character): Blizzard re-dresses the inset on every tab switch,
    -- so a one-time strip at skin cannot hold -- and our strip is
    -- state-only now (correctly: no more NOOP surgery). We are already
    -- hooked on ShowSubFrame for the backdrop, so re-strip here too.
    -- Cheap: a handful of regions, only on tab change.
    -- the dump showed CharacterFrame's OWN NineSlice art
    -- (UI-Frame-Metal-*) returning too, not just the insets -- so
    -- re-strip the parent here as well. With NineSlice now in the
    -- region list, this clears the pieces themselves.
    S.StripTextures(_G.CharacterFrame)
    -- Without an inset the frame's own art still returns on every tab switch.
    if not inset then return end
    S.StripTextures(inset)
    if _G.CharacterFrameInsetRight then S.StripTextures(_G.CharacterFrameInsetRight) end

    local bd = S.GetBackdrop(inset)
    if bd then bd:SetShown(name and showInsetBackdrop[name] or false) end

end


-- THE FIX ("backdrop comes back after clicking tabs").
-- /aedump named it: CharacterModelScene's four BACKGROUND textures
-- (4709136-9). Blizzard's SetPaperDollBackground() re-SetTextures all
-- four (+ a race-based BackgroundOverlay alpha) and it is called from
-- PaperDollFrame_OnShow -- i.e. EVERY time you come back to the
-- Character tab. No amount of stripping at skin time can survive that;
-- the re-dresser has to be hooked. SLE hides exactly these four by
-- name in their armory module (their character.lua) -- the
-- feature  remembered -- so this is that, driven from Blizzard's
-- own function so it can never be out of sync.
local BG_PIECES = { "BackgroundTopLeft", "BackgroundTopRight",
                    "BackgroundBotLeft", "BackgroundBotRight" }

local function KillPaperDollBackground(model)
    model = model or _G.CharacterModelScene
    if not model then return end
    for _, key in ipairs(BG_PIECES) do
        local t = model[key]
        if t then
            t:SetTexture(S.ClearTexture)
            if t.SetAtlas then t:SetAtlas("") end
            t:Hide()
        end
    end
    local overlay = model.BackgroundOverlay
    if overlay then
        overlay:SetTexture(S.ClearTexture)
        if overlay.SetAtlas then overlay:SetAtlas("") end
        overlay:SetAlpha(0)
    end
end

local function Skin()
    local frame = _G.CharacterFrame
    if not frame then return S.Skip("CharacterFrame missing") end
    S.Frame(frame)
    if _G.CharacterFramePortrait then S.Kill(_G.CharacterFramePortrait) end

    -- hook Blizzard's paperdoll background applier.
    KillPaperDollBackground()
    if _G.SetPaperDollBackground and not S.data(frame).pdBgHook then
        S.data(frame).pdBgHook = true
        hooksecurefunc("SetPaperDollBackground", KillPaperDollBackground)
    end

    -- inset backdrop, driven per tab.
    local inset = _G.CharacterFrameInset
    if inset and not S.GetBackdrop(inset) then
        S.Backdrop(inset)
    end
    -- On the instance: the XML mixin copied ShowSubFrame onto CharacterFrame
    -- when it was created, so a hook on CharacterFrameMixin never runs.
    if frame.ShowSubFrame and not S.data(frame).insetHook then
        S.data(frame).insetHook = true
        hooksecurefunc(frame, "ShowSubFrame", UpdateCharacterInset)
    end

    -- The flyout is skinned in the same frame Blizzard builds it. Installed
    -- only when this skin runs, so a disabled skin never paints the flyout.
    if not flyoutHooked then
        flyoutHooked = true
        if _G.EquipmentFlyout_SetBackgroundTexture then
            hooksecurefunc("EquipmentFlyout_SetBackgroundTexture", EquipmentFlyoutNav)
        end
        if _G.EquipmentFlyout_UpdateItems then
            hooksecurefunc("EquipmentFlyout_UpdateItems", EquipmentFlyoutSkin)
        end
    end
    local current = frame.activeSubframe
    UpdateCharacterInset(current)
    S.Tabs("CharacterFrameTab", 6)
    -- Art only. The per-slot ilvl/gem text this loop used to add, and the
    -- PaperDollItemSlotButton_Update hook that refreshed it, are gone --
    -- CharacterPanel owns that display (see the note at the top of this file).
    --
    -- The rarity border is NOT a return of that display. S.ItemButton blanks
    -- Blizzard's IconBorder; routing it through S.IconBorder instead tints the
    -- backdrop by quality and inherits that helper's own hooks on the texture,
    -- so it refreshes on Blizzard's repaint with nothing added here.
    local qualityBorders = QualityBordersOn(KE.db and KE.db.profile and KE.db.profile.CharacterPanel)
    for _, slot in ipairs(SLOTS) do
        local button = _G["Character" .. slot .. "Slot"]
        if button then
            S.ItemButton(button)
            if button.BorderFrame then S.StripTextures(button.BorderFrame) end
            if slot == "Ammo" then HideAmmoArrow(button) end
            if qualityBorders and button.IconBorder then
                S.IconBorder(button.IconBorder, S.GetBackdrop(button))
            end
        end
    end

    local cf = _G.CharacterModelScene and _G.CharacterModelScene.ControlFrame
    if cf then
        cf:Hide()
        if not S.data(cf).keHidden then
            cf:HookScript("OnShow", cf.Hide)
            S.data(cf).keHidden = true
        end
    end

    SkinStatsPane()
    SkinSidebarTabs()
    if frame.ModeTabs then S.SideTabsInPlace(frame.ModeTabs.Tabs) end
    if frame.LeftPaneHost then S.StripTextures(frame.LeftPaneHost) end
    if frame.RightPaneHost then S.StripTextures(frame.RightPaneHost) end

    SkinTitlesPane()
    SkinEquipmentManagerPane()
    ShrinkSetButtons()

    local cframe = _G.CharacterFrame
    if cframe and not S.data(cframe).keReskinHooked then
        cframe:HookScript("OnShow", function()
            SkinStatsPane()
            ShrinkSetButtons()
            SkinEquipmentManagerPane()
        end)
        S.data(cframe).keReskinHooked = true
    end
end

S:Register("Blizzard_UIPanels_Game", Skin, "Character")

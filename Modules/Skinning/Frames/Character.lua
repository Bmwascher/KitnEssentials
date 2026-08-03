local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local hooksecurefunc = hooksecurefunc

local SLOTS = {
    "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist",
    "Hands", "Waist", "Legs", "Feet", "Finger0", "Finger1", "Trinket0",
    "Trinket1", "MainHand", "SecondaryHand",
}

local STAT_CATEGORIES = { "ItemLevelCategory", "AttributesCategory", "EnhancementsCategory" }

local ILVL_SIZE, HEADER_SIZE, ROW_SIZE = 20, 14, 12
local HEADER_INSET = 6

local GetInventoryItemLink = GetInventoryItemLink
local GetItemGem = GetItemGem or (C_Item and C_Item.GetItemGem)
local GetItemIcon = C_Item and C_Item.GetItemIconByID
local ITEM_QUALITY_COLORS = ITEM_QUALITY_COLORS
local ItemLocation = ItemLocation

local ILVL_FONT = 13
local TAB_FONT = 13
local TITLE_FONT = 13
local BRAND = S.palette.brand

local TEXT_SIDE = {
    Head = "R", Neck = "R", Shoulder = "R", Back = "R", Chest = "R", Wrist = "R",
    Hands = "L", Waist = "L", Legs = "L", Feet = "L",
    Finger0 = "L", Finger1 = "L", Trinket0 = "L", Trinket1 = "L",
    MainHand = "T", SecondaryHand = "T",
}
local NO_ILVL = { [4] = true, [19] = true }

local function EnsureSlotDisplay(button, side)
    if S.data(button).aeILvl then return end
    local ilvl = button:CreateFontString(nil, "OVERLAY")
    S.SetFont(ilvl, ILVL_FONT, "OUTLINE")
    if side == "R" then
        ilvl:SetPoint("TOPLEFT", button, "TOPRIGHT", 3, -2)
        ilvl:SetJustifyH("LEFT")
    elseif side == "L" then
        ilvl:SetPoint("TOPRIGHT", button, "TOPLEFT", -3, -2)
        ilvl:SetJustifyH("RIGHT")
    else
        ilvl:SetPoint("BOTTOM", button, "TOP", 0, 3)
    end
    S.data(button).aeILvl = ilvl

    S.data(button).aeGems = {}
    for i = 1, 3 do
        local border = button:CreateTexture(nil, "OVERLAY", nil, 1)
        border:SetColorTexture(0, 0, 0, 0.9)
        local g = button:CreateTexture(nil, "OVERLAY", nil, 2)
        g:SetSize(12, 12)
        g:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        border:SetPoint("TOPLEFT", g, "TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", 1, -1)
        g.aeBorder = border
        if i == 1 then
            if side == "L" then
                g:SetPoint("RIGHT", ilvl, "LEFT", -4, 0)
            else
                g:SetPoint("LEFT", ilvl, "RIGHT", 4, 0)
            end
        else
            if side == "L" then
                g:SetPoint("RIGHT", S.data(button).aeGems[i - 1], "LEFT", -2, 0)
            else
                g:SetPoint("LEFT", S.data(button).aeGems[i - 1], "RIGHT", 2, 0)
            end
        end
        g:Hide()
        border:Hide()
        S.data(button).aeGems[i] = g
    end
end

-- v4.0.3 (empty sockets should show on the character panel):
-- the gem row previously rendered only FILLED sockets (positional
-- GetItemGem), so an ungemmed socket was invisible -- exactly the case
-- where the player most wants the reminder. Empty sockets are detected
-- from C_Item.GetItemStats, with KE.GEM_SOCKET_TYPES supplying the
-- socket-type icon. Exposed as KE.GetEmptySocketIcons for the inspect
-- panel (CharacterScreen) to share -- both frames draw their per-slot
-- gem icons through this one function.
-- Sockets per item; matches the paperdoll's cap.
local MAX_ITEM_SOCKETS = 4

-- v4.0.155: rewritten. The inspect frame uses this, NOT the paperdoll's
-- CS:ScanItemSockets, so none of the socket fixes since v4.0.137 reached
-- it -- which is why the paperdoll behaved and inspect did not.
--
-- What it used to do wrong, all at once:
--   * scraped a GameTooltip. That tip inherits GameTooltipTemplate, so
--     every other addon's OnTooltipSetItem hook fires on it and any
--     socket line they add was counted as a real socket.
--   * no break after a match, so one line matching several socket
--     strings counted once per match.
--   * cached the result by link FOREVER, including negative results. On
--     inspect the first scan usually runs before the item has arrived
--     ("Retrieving item information"), finds zero sockets, and caches
--     that -- the gem never appears no matter how long you wait, and
--     reopening gives a different answer because the gem loop beside it
--     resolves independently. That is exactly the reported "gem missing,
--     then doubled after reopening".
--
-- Now: counts from C_Item.GetItemStats like the paperdoll, returns only
-- the sockets the caller's gem loop will NOT fill, and never caches an
-- answer taken before the item is known.
local function GetEmptySocketIcons(unit, slotID, link) -- luacheck: ignore 212/unit 212/slotID
    if not link then return nil end

    -- v4.0.157: NO CACHE. v4.0.155 cached on IsItemDataCachedByID(link),
    -- but that tests the ITEM -- the gem inside it is a separate item and
    -- resolves later. On a first inspect the ring was cached while its
    -- gem was not, so filled=0, and "1 empty socket" got cached forever.
    -- The second inspect then drew the now-resolved gem PLUS the cached
    -- empty: two icons on a one-socket ring.
    --
    -- The cache only ever existed to avoid a tooltip scrape, and that is
    -- gone -- GetItemStats and GetItemGem are plain lookups. Removing it
    -- removes the entire class of stale-partial-result bugs rather than
    -- adding another condition to guess at.
    local stats = C_Item.GetItemStats and C_Item.GetItemStats(link)
    if not stats then return nil end

    -- One icon per socket, in type order.
    local slots = {}
    for _, socketType in ipairs(KE.GEM_SOCKET_TYPES) do
        local count = tonumber(stats[socketType.locale]) or 0
        for _ = 1, count do
            if #slots >= MAX_ITEM_SOCKETS then break end
            slots[#slots + 1] = socketType.icon
        end
    end

    if #slots == 0 then return nil end

    -- The caller fills the first `filled` icons from GetItemGem; only the
    -- remainder are empty.
    local filled = 0
    for i = 1, #slots do
        local _, gemLink = C_Item.GetItemGem(link, i)
        if gemLink then filled = filled + 1 end
    end

    local icons
    for i = filled + 1, #slots do
        icons = icons or {}
        icons[#icons + 1] = slots[i]
    end

    return icons
end

KE.GetEmptySocketIcons = GetEmptySocketIcons

local function UpdateSlotDisplay(button)
    if not button or not S.data(button).aeILvl then return end
    local slotID = button:GetID()
    local link = slotID and slotID > 0 and GetInventoryItemLink("player", slotID)
    if not link then
        S.data(button).aeILvl:SetText("")
        for _, g in ipairs(S.data(button).aeGems) do g:Hide(); g.aeBorder:Hide() end
        return
    end

    if NO_ILVL[slotID] then
        S.data(button).aeILvl:SetText("")
    else
        local loc = ItemLocation:CreateFromEquipmentSlot(slotID)
        local ilvl = loc and C_Item.DoesItemExist(loc) and C_Item.GetCurrentItemLevel(loc)
        S.data(button).aeILvl:SetText(ilvl or "")
        local q = loc and C_Item.GetItemQuality(loc)
        local c = q and ITEM_QUALITY_COLORS[q]
        if c then S.data(button).aeILvl:SetTextColor(c.r, c.g, c.b) else S.data(button).aeILvl:SetTextColor(1, 1, 1) end
    end

    -- Filled gems first (positional), then empty-socket icons for the
    -- item's remaining sockets, then hide the rest of the row.
    local emptyIcons = GetEmptySocketIcons("player", slotID, link)
    local emptyIndex = 0
    for i, g in ipairs(S.data(button).aeGems) do
        local tex, isEmptySocket
        if GetItemGem then
            local _, gemLink = GetItemGem(link, i)
            local gemID = gemLink and tonumber(strmatch(gemLink, "item:(%d+)"))
            if gemID and GetItemIcon then tex = GetItemIcon(gemID) end
        end
        if not tex and emptyIcons and emptyIndex < #emptyIcons then
            emptyIndex = emptyIndex + 1
            tex = emptyIcons[emptyIndex]
            isEmptySocket = true
        end
        if tex then
            g:SetTexture(tex)
            g:SetDesaturated(isEmptySocket and true or false)
            g:SetAlpha(isEmptySocket and 0.85 or 1)
            g:Show(); g.aeBorder:Show()
        else
            g:Hide(); g.aeBorder:Hide()
        end
    end
end

local slotHooked = false
local slotNoticeShown

local function UpdateStatsPane()
    local pane = _G.CharacterStatsPane
    if not pane then return end

    if pane.ItemLevelFrame and pane.ItemLevelFrame.Value then
        S.SetFont(pane.ItemLevelFrame.Value, ILVL_SIZE, "OUTLINE")

        local _, equipped = GetAverageItemLevel()
        if equipped then pane.ItemLevelFrame.Value:SetText(string.format("%.2f", equipped)) end
    end
    for _, cat in ipairs(STAT_CATEGORIES) do
        if pane[cat] then S.FontStrings(pane[cat], HEADER_SIZE, "OUTLINE") end
    end

    if pane.statsFramePool and pane.statsFramePool.EnumerateActive then
        for row in pane.statsFramePool:EnumerateActive() do

            if not S.data(row).statFonted then
                S.data(row).statFonted = true

                S.FontStrings(row, ROW_SIZE, "OUTLINE")
            end
            if row.Background and row.Background.SetAlpha then
                row.Background:SetAlpha(0)
            end
        end
    end
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
            if not pane[cat].aeHeaderBox then
                S.Backdrop(pane[cat])
                pane[cat].aeHeaderBox = true
            end

            local bd = S.GetBackdrop(pane[cat])
            if bd then
                bd:ClearAllPoints()
                bd:SetPoint("TOPLEFT", pane[cat], "TOPLEFT", 0, -HEADER_INSET)
                bd:SetPoint("BOTTOMRIGHT", pane[cat], "BOTTOMRIGHT", 0, HEADER_INSET)
            end
        end
    end

    -- v3.5.843: CharacterFrameInset added -- ElvUI's charframe list
    -- (their Character.lua:392-398) has it and ours didn't, so
    -- Blizzard's inset art was never stripped. It only stayed hidden
    -- while our old KillTexture NOOP'd the setters addon-wide; once
    -- that went (v828/v838), the art came back on tab switches.
    for _, name in ipairs({ "CharacterStatsPane", "CharacterModelScene", "CharacterFrameInset",
                            "CharacterFrameInsetRight", "PaperDollSidebarTabs" }) do
        if _G[name] then S.StripTextures(_G[name]) end
    end

    UpdateStatsPane()
    if not statsHooked and _G.PaperDollFrame_UpdateStats then
        hooksecurefunc("PaperDollFrame_UpdateStats", UpdateStatsPane)
        statsHooked = true
    end
end

local function SkinSidebarTabs()
    for i = 1, 3 do
        local tab = _G["PaperDollSidebarTab" .. i]
        if tab and not tab.aeTabSkinned then
            -- v3.5.837 (art flashed on open): SetAlpha(0) is
            -- state -- Blizzard re-dresses it every show. ElvUI Kills
            -- this exact region (Character.lua:239 tab.TabBg:Kill()).
            if tab.TabBg then S.Kill(tab.TabBg) end
            S.Backdrop(tab)
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
            tab.aeTabSkinned = true
        end
    end
end

local function StyleTitleRow(child)
    if not child or child.aeTitleSkinned then return end
    if child.DisableDrawLayer then child:DisableDrawLayer("BACKGROUND") end

    S.RowHover(child)
    S.FontStrings(child, TITLE_FONT, "")
    child.aeTitleSkinned = true
end

local function SkinTitlesPane()
    local pane = _G.PaperDollFrame and _G.PaperDollFrame.TitleManagerPane
    if not pane then return end
    if pane.ScrollBar then S.ScrollBar(pane.ScrollBar) end
    if pane.ScrollBox then S.HookScrollBox(pane.ScrollBox, StyleTitleRow) end
end

local EQUIP_FONT = 13
local EQUIP_HOVER_ALPHA = 0.30
local EQUIP_SELECT_ALPHA = 0.40
local function StyleEquipRow(child)
    if not child or not child.icon or child.aeEquipSkinned then return end
    if child.BgTop then child.BgTop:SetTexture(nil) end
    if child.BgMiddle then child.BgMiddle:SetTexture(nil) end
    if child.BgBottom then child.BgBottom:SetTexture(nil) end
    S.Icon(child.icon, true)
    if child.HighlightBar then
        child.HighlightBar:SetColorTexture(1, 1, 1, EQUIP_HOVER_ALPHA)
        child.HighlightBar:SetDrawLayer("BACKGROUND")
    end
    if child.SelectedBar then
        child.SelectedBar:SetColorTexture(BRAND[1], BRAND[2], BRAND[3], EQUIP_SELECT_ALPHA)
        child.SelectedBar:SetDrawLayer("BACKGROUND")
    end
    S.FontStrings(child, EQUIP_FONT, "")
    child.aeEquipSkinned = true
end

local function ShrinkSetButtons()

    local pane = _G.PaperDollFrame and _G.PaperDollFrame.EquipmentManagerPane
    if not pane then return end
    local equip, save = pane.EquipSet, pane.SaveSet
    if equip and not S.data(equip).aeShrunk then
        equip:SetWidth((equip:GetWidth() or 85) - 2)
        S.data(equip).aeShrunk = true
    end
    if save and equip and not S.data(save).aeGapped then
        save:SetWidth((save:GetWidth() or 85) - 2)
        local pt, rel, relPt, x, y = save:GetPoint(1)
        if rel == equip then
            save:ClearAllPoints()
            save:SetPoint(pt, rel, relPt, (x or 0) + 1, y or 0)
        end
        S.data(save).aeGapped = true
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

-- v3.5.838: ElvUI's exact flyout treatment (their Character.lua
-- EquipmentDisplayButton): clear state art by passing E.ClearTexture
-- (fileID 0) to the BUTTON's setters. No contact with the texture
-- objects at all -- which is what tainted this display loop for
-- thirteen versions. S.ClearButtonArt also installs their
-- re-clear-on-set hooks, so Blizzard re-dressing can't bring the art
-- back (no flash) and nothing gets NOOP'd (no taint).
local function KillFlyoutStates(button)
    S.ClearButtonArt(button, true) -- keepHighlight: S.Hover owns it
end

local function SkinFlyoutButton(button)
    if not button or S.data(button).skinned then return end
    S.ItemButton(button)
    KillFlyoutStates(button)

    -- v3.5.825: the per-button method hooks (SetNormalTexture etc.,
    -- IconBorder Show-suppressor) fired INSIDE DisplayButton -- before
    -- the location write -- and were the remaining taint injectors
    -- (v824 post-hoc audit: even button1 tainted). No hooks at all
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
        -- v3.5.827: fontstring ref moved off the button (tainted-key
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
        -- v3.5.769 ("compare table with number" from the
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
    -- v3.5.838: ElvUI's exact three lines for the flyout chrome
    -- (their Character.lua:400-402): StripTextures the highlight,
    -- alpha-0 bg1, DisableDrawLayer the rest. They never Kill these,
    -- so neither do we now that the kill primitive carries their
    -- Kill semantics.
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
    if flyout.buttons then
        for _, button in ipairs(flyout.buttons) do
            SkinFlyoutButton(button)
            KillFlyoutStates(button) -- v3.5.825: re-kill per pass (no hooks)
            if button.IconBorder then button.IconBorder:SetAlpha(0) end
            -- v3.5.826: flyout ilvl RETIRED (ElvUI parity -- their skin
            -- is art-only on the flyout, zero item-data reads; the ilvl
            -- feature is WindTools', same mid-flow architecture as our
            -- old code, presumably same Midnight bug). All flyout item-data
            -- reads are gone now.
            if S.data(button).flyoutILvl then S.data(button).flyoutILvl:Hide() end
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

-- v3.5.843: ElvUI's per-tab inset backdrop (their showInsetBackdrop +
-- UpdateCharacterInset, hooked on CharacterFrameMixin.ShowSubFrame).
-- The list tabs want a dark inset behind their rows; the paperdoll
-- does not -- that is the backdrop  saw sticking around after
-- tab switching.
local showInsetBackdrop = {
    ReputationFrame = true,
    TokenFrame = true,
}

local function UpdateCharacterInset(a, b)
    -- hooksecurefunc on a mixin method passes (self, name); accept
    -- either shape so the tab name is what we actually test.
    local name = (type(b) == "string" and b) or (type(a) == "string" and a) or nil
    local inset = _G.CharacterFrameInset
    if not inset then return end

    -- v3.5.845 (art returns on Currency -> Reputation ->
    -- Character): Blizzard re-dresses the inset on every tab switch,
    -- so a one-time strip at skin cannot hold -- and our strip is
    -- state-only now (correctly: no more NOOP surgery). We are already
    -- hooked on ShowSubFrame for the backdrop, so re-strip here too.
    -- Cheap: a handful of regions, only on tab change.
    -- v3.5.848: the dump showed CharacterFrame's OWN NineSlice art
    -- (UI-Frame-Metal-*) returning too, not just the insets -- so
    -- re-strip the parent here as well. With NineSlice now in the
    -- region list, this clears the pieces themselves.
    S.StripTextures(_G.CharacterFrame)
    S.StripTextures(inset)
    if _G.CharacterFrameInsetRight then S.StripTextures(_G.CharacterFrameInsetRight) end

    local bd = S.GetBackdrop(inset)
    if bd then bd:SetShown(name and showInsetBackdrop[name] or false) end

end


-- v3.5.851 THE FIX ("backdrop comes back after clicking tabs").
-- /aedump named it: CharacterModelScene's four BACKGROUND textures
-- (4709136-9). Blizzard's SetPaperDollBackground() re-SetTextures all
-- four (+ a race-based BackgroundOverlay alpha) and it is called from
-- PaperDollFrame_OnShow -- i.e. EVERY time you come back to the
-- Character tab. No amount of stripping at skin time can survive that;
-- the re-dresser has to be hooked. SLE hides exactly these four by
-- name in their armory module (their character.lua:309-317) -- the
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
    if not frame then return end
    S.Frame(frame)
    -- v3.5.837: ElvUI Kills the portrait here too
    -- (their Character.lua:411 CharacterFramePortrait:Kill()).
    if _G.CharacterFramePortrait then S.Kill(_G.CharacterFramePortrait) end

    -- v3.5.851: hook Blizzard's paperdoll background applier.
    KillPaperDollBackground()
    if _G.SetPaperDollBackground and not S.data(frame).pdBgHook then
        S.data(frame).pdBgHook = true
        hooksecurefunc("SetPaperDollBackground", KillPaperDollBackground)
    end

    -- v3.5.843: inset backdrop, driven per tab exactly as ElvUI does.
    local inset = _G.CharacterFrameInset
    if inset and not S.GetBackdrop(inset) then
        S.Backdrop(inset)
    end
    if _G.CharacterFrameMixin and not S.data(frame).insetHook then
        S.data(frame).insetHook = true
        hooksecurefunc(_G.CharacterFrameMixin, "ShowSubFrame", UpdateCharacterInset)
    end
    local current = frame.activeSubFrame
    UpdateCharacterInset(current)
    S.Tabs("CharacterFrameTab", 6)

    for i = 1, 4 do
        local tab = _G["CharacterFrameTab" .. i]
        local fs = tab and tab.GetFontString and tab:GetFontString()
        if fs then
            S.SetFont(fs, TAB_FONT, "")
            if PanelTemplates_TabResize then PanelTemplates_TabResize(tab, 0) end
        end
    end
    for _, slot in ipairs(SLOTS) do
        local button = _G["Character" .. slot .. "Slot"]
        if button then
            S.ItemButton(button)
            local side = TEXT_SIDE[slot]
            if side then
                EnsureSlotDisplay(button, side)
                UpdateSlotDisplay(button)
            end
        end
    end

    -- v3.5.826 EXPERIMENT GATE: last hook in paperdoll flows suspected
    -- of tainting the flow.
    -- Temporarily disabled so the next session is a binary verdict: audit
    -- silent = this hook (or the retired flyout ilvl) was the seed;
    -- audit still noisy = the taint isn't in this code path, and it
    -- escalates to a full-session taint log + Ellesmere.
    -- RE-ENABLE in v827 regardless of outcome (feature is wanted;
    -- if it proves to be the seed it gets the deferred treatment).
    -- v3.5.827: root found (tainted-key field writes, migrated to
    -- S.data) -- experiment gate lifted, feature restored.
    local SLOT_HOOK_DIAG_DISABLED = false
    if SLOT_HOOK_DIAG_DISABLED then
        if not slotNoticeShown then
            slotNoticeShown = true
            print("|cffFF008CKitn|r|cffffffffEssentials:|r diagnostic build: character-slot ilvl/enchant text temporarily off")
        end
    elseif not slotHooked and _G.PaperDollItemSlotButton_Update then
        hooksecurefunc("PaperDollItemSlotButton_Update", UpdateSlotDisplay)
        slotHooked = true
    end

    local cf = _G.CharacterModelScene and _G.CharacterModelScene.ControlFrame
    if cf then
        cf:Hide()
        if not cf.aeHidden then
            cf:HookScript("OnShow", cf.Hide)
            cf.aeHidden = true
        end
    end

    SkinStatsPane()
    SkinSidebarTabs()

    SkinTitlesPane()
    SkinEquipmentManagerPane()
    ShrinkSetButtons()

    local cframe = _G.CharacterFrame
    if cframe and not S.data(cframe).aeReskinHooked then
        cframe:HookScript("OnShow", function()
            SkinStatsPane()
            ShrinkSetButtons()
            SkinEquipmentManagerPane()
        end)
        S.data(cframe).aeReskinHooked = true
    end
end

-- v3.5.839: ElvUI's exact registrations (their Character.lua:407-408).
-- Every piece of machinery that used to sit here -- the event-driven
-- deferred driver (v824), the 0.1s panel ticker (v825), the post-hoc
-- issecurevariable audit -- was built on the wrong theory that hooking
-- a function inside a secure flow taints it. It does not: ElvUI hooks
-- these very two functions and has no flyout taint. The real cause was
-- our KillTexture NOOP surgery, now gone (v838). Hooks restored, so
-- the flyout skins in the same frame Blizzard builds it -- no more
-- half-second unskinned flash.
if _G.EquipmentFlyout_SetBackgroundTexture then
    hooksecurefunc("EquipmentFlyout_SetBackgroundTexture", EquipmentFlyoutNav)
end
if _G.EquipmentFlyout_UpdateItems then
    hooksecurefunc("EquipmentFlyout_UpdateItems", EquipmentFlyoutSkin)
end

S:Register("Blizzard_UIPanels_Game", Skin, "Character")

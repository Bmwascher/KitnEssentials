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

local ItemLocation = ItemLocation

local ILVL_FONT = 13
local TAB_FONT = 13
local TITLE_FONT = 13
local BRAND = S.palette.brand

-- Per-slot item level + gem icons used to be drawn here (EnsureSlotDisplay /
-- UpdateSlotDisplay / GetEmptySocketIcons, ported from the reference skin).
-- Removed: KE already draws all three from Modules/QoL/CharacterPanel.lua, at
-- anchors within 2px of these, so every character slot rendered them TWICE
-- whenever this skin was on. The reference has no such overlap -- there the
-- skin owns the paperdoll and its info module deliberately stands down (its
-- CharacterScreen.lua:1710 guards on the skin's own store before drawing, and
-- reads the skin's fontstring to anchor enchant text). KE's panel was ported
-- first, before this skin existed, so it grew its own copy instead.
-- CharacterPanel is the single owner now: it ships enabled by default, this
-- skin ships disabled, and it also covers the inspect frame, which this never
-- did. KE.GetEmptySocketIcons went with them -- it was exported for the
-- reference's info module and nothing in KE ever called it.

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

    -- CharacterFrameInset added -- ElvUI's charframe list
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
            -- (art flashed on open): SetAlpha(0) is
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

-- ElvUI's exact flyout treatment (their Character.lua
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

    -- the per-button method hooks (SetNormalTexture etc.,
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
    -- ElvUI's exact three lines for the flyout chrome
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
            KillFlyoutStates(button) -- re-kill per pass (no hooks)
            if button.IconBorder then button.IconBorder:SetAlpha(0) end
            -- flyout ilvl RETIRED (ElvUI parity -- their skin
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

-- ElvUI's per-tab inset backdrop (their showInsetBackdrop +
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
    -- ElvUI Kills the portrait here too
    -- (their Character.lua:411 CharacterFramePortrait:Kill()).
    if _G.CharacterFramePortrait then S.Kill(_G.CharacterFramePortrait) end

    -- hook Blizzard's paperdoll background applier.
    KillPaperDollBackground()
    if _G.SetPaperDollBackground and not S.data(frame).pdBgHook then
        S.data(frame).pdBgHook = true
        hooksecurefunc("SetPaperDollBackground", KillPaperDollBackground)
    end

    -- inset backdrop, driven per tab exactly as ElvUI does.
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
    -- Art only. The per-slot ilvl/gem text this loop used to add, and the
    -- PaperDollItemSlotButton_Update hook that refreshed it, are gone --
    -- CharacterPanel owns that display (see the note at the top of this file).
    for _, slot in ipairs(SLOTS) do
        local button = _G["Character" .. slot .. "Slot"]
        if button then
            S.ItemButton(button)
        end
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

-- ElvUI's exact registrations (their Character.lua:407-408).
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

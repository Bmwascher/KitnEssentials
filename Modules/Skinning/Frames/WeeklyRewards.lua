local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local pairs, unpack = pairs, unpack
local hooksecurefunc = hooksecurefunc

-- Blizzard's selection pass ANIMATES alpha on its glow art, so
-- SetAlpha(0) gets overwritten every click. Reparenting the textures
-- under a hidden frame removes them from rendering permanently.
local hider = CreateFrame("Frame")
hider:Hide()
local function Banish(region)
    if region and region.SetParent then region:SetParent(hider) end
end

local function EpicRGB()
    local q = _G.Enum and _G.Enum.ItemQuality and _G.Enum.ItemQuality.Epic or 4
    local c = _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    return 0.64, 0.21, 0.93
end

local ACTIVITY_PANES = { "RaidFrame", "MythicFrame", "PVPFrame", "WorldFrame" }

local function DressRewardIcon(itemFrame)
    local d = S.data(itemFrame)
    if d.vaultSkinned then return end
    local bd = S.Backdrop(itemFrame)
    itemFrame:DisableDrawLayer("BORDER")
    if itemFrame.Icon then
        itemFrame.Icon:SetPoint("LEFT", 6, 0)
        S.Icon(itemFrame.Icon, true)
    end
    if bd then
        bd:SetBackdropBorderColor(EpicRGB())
        -- Item well uses the same shade as the Adventure Guide loot rows.
        bd:SetBackdropColor(S.controlBg[1], S.controlBg[2], S.controlBg[3], S.controlBg[4])
    end
    d.vaultSkinned = true
end

local function OnSelectionChanged(frame)
    -- SelectedTexture stays alive purely as the state signal (alpha
    -- zeroed; the visible halo was SelectionGlow, banished at skin
    -- time). Selection = soft brand fill on the cell box.
    if frame.SelectedTexture then frame.SelectedTexture:SetAlpha(0) end
    local selected = frame.SelectedTexture and frame.SelectedTexture:IsShown()

    local bd = S.GetBackdrop(frame)
    if not bd then return end

    local d = S.data(frame)
    if selected and not d.selFill then
        local t = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
        t:SetColorTexture(S.palette.brand[1], S.palette.brand[2], S.palette.brand[3], 0.15)
        t:SetPoint("TOPLEFT", bd, "TOPLEFT", 1, -1)
        t:SetPoint("BOTTOMRIGHT", bd, "BOTTOMRIGHT", -1, 1)
        d.selFill = t
    end
    if d.selFill then d.selFill:SetShown(selected and true or false) end

    -- Border stays standard in both states; the fill signals selection.
    bd:SetBackdropBorderColor(S.borderColor[1], S.borderColor[2], S.borderColor[3], 1)
end

local function DressActivityPane(frame, isObject)
    if not frame then return end

    if isObject then
        if frame.Border then frame.Border:SetAlpha(0) end
        if frame.Background then frame.Background:SetAlpha(0) end
        Banish(frame.ItemGlow)
        Banish(frame.SelectionGlow)
        local rg = frame.RewardGenerated
        if rg then Banish(rg.Overlay) end
        -- SelectedTexture must keep EXISTING in place (Blizzard's
        -- SetSelectionState toggles it and we read IsShown as the
        -- selection signal) -- but never render: alpha-zeroed here and
        -- re-zeroed on every selection pass (Blizzard animates it).
        if frame.SelectedTexture then frame.SelectedTexture:SetAlpha(0) end

        S.Backdrop(frame)
        if frame.SelectedTexture then frame.SelectedTexture:SetAlpha(0) end
        if frame.UnselectedFrame then frame.UnselectedFrame:SetAlpha(0) end
        if frame.SetSelectionState then
            hooksecurefunc(frame, "SetSelectionState", OnSelectionChanged)
        end
        if frame.ItemFrame then
            hooksecurefunc(frame.ItemFrame, "SetDisplayedItem", DressRewardIcon)
        end
    else
        -- Row headers (Raids / Dungeons / World): paintings stay.
        if frame.Border then
            frame.Border:SetTexCoord(0.926, 1, 0, 1)
            frame.Border:ClearAllPoints()
            frame.Border:SetPoint("LEFT", frame, "RIGHT", 3, 0)
            frame.Border:SetSize(25, 137)
        end
        if frame.Background and frame.Name then
            frame.Background:SetSize(390, 140)
            frame.Background:SetDrawLayer("ARTWORK", 2)
            S.Backdrop(frame.Background)
        end
    end
end

local function DressConfirmIcon(frame)
    if not frame then return end
    if frame.Icon then
        S.SlotIcon(frame.Icon, frame.IconBorder)
    end
end

local function SelectReward(frame)
    local selection = frame and frame.confirmSelectionFrame
    if selection then
        if _G.WeeklyRewardsFrameNameFrame then _G.WeeklyRewardsFrameNameFrame:Hide() end
        DressConfirmIcon(selection.ItemFrame)

        local alsoItems = selection.AlsoItemsFrame
        if alsoItems and alsoItems.pool then
            for items in alsoItems.pool:EnumerateActive() do
                DressConfirmIcon(items)
            end
        end
    end
end

local function UpdateOverlay(frame)
    local overlay = frame.Overlay
    if overlay then
        S.StripTextures(overlay)
        S.Backdrop(overlay)
    end
end

local function HandleWarning(nineSlice)
    S.StripTextures(nineSlice, true)
    S.Backdrop(nineSlice)
    if nineSlice.ExtraBG then nineSlice.ExtraBG:Hide() end
end

local function Skin()
    local frame = _G.WeeklyRewardsFrame
    if not frame then return end

    S.StripTextures(frame)
    S.Backdrop(frame)

    local header = frame.HeaderFrame
    if header then
        header:ClearAllPoints()
        header:SetPoint("TOP", 1, -42)
        S.StripTextures(header)
        S.Backdrop(header)
    end

    if frame.BorderContainer then S.StripTextures(frame.BorderContainer) end
    if frame.ConcessionFrame then S.StripTextures(frame.ConcessionFrame) end

    if frame.CloseButton then S.CloseButton(frame.CloseButton) end
    if frame.SelectRewardButton then S.Button(frame.SelectRewardButton) end

    -- The four fixed panes, then the pooled per-activity rows inside them.
    S.Each(frame, DressActivityPane, unpack(ACTIVITY_PANES))

    for _, activity in pairs(frame.Activities or {}) do
        DressActivityPane(activity, true)
    end

    local rewardText = frame.ConcessionFrame and frame.ConcessionFrame.RewardsFrame
        and frame.ConcessionFrame.RewardsFrame.Text
    if rewardText then
        S.ReplaceIconString(rewardText)
        hooksecurefunc(rewardText, "SetText", S.ReplaceIconString)
    end

    local warningDialog = _G.WeeklyRewardExpirationWarningDialog
    if warningDialog then
        warningDialog:ClearAllPoints()
        warningDialog:SetPoint("TOP", frame, "BOTTOM", 0, -1)
        if warningDialog.NineSlice then
            warningDialog.NineSlice:HookScript("OnShow", HandleWarning)
            if warningDialog.NineSlice:IsShown() then HandleWarning(warningDialog.NineSlice) end
        end
    end

    hooksecurefunc(frame, "SelectReward", SelectReward)
    hooksecurefunc(frame, "UpdateOverlay", UpdateOverlay)
end

S:Register("Blizzard_WeeklyRewards", Skin, "WeeklyRewards")

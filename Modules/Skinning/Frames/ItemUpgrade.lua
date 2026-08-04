---@class KE
-- ElvUI Mainline/Skins/ItemUpgrade.lua transcription:
-- window mostly unskinned -- only the S.Frame stub existed.
local KE = select(2, ...)
local S = KE.Skins
local _G = _G

local function Skin()
    local frame = _G.ItemUpgradeFrame
    if not frame then return end
    S.Frame(frame)

    -- Chrome ElvUI hides beyond the standard frame treatment
    if _G.ItemUpgradeFramePlayerCurrenciesBorder then
        S.StripTextures(_G.ItemUpgradeFramePlayerCurrenciesBorder)
    end
    if frame.UpgradeCostFrame and frame.UpgradeCostFrame.BGTex then
        S.StripTextures(frame.UpgradeCostFrame.BGTex)
    end
    if frame.TopTileStreaks then frame.TopTileStreaks:Hide() end

    -- Parchment-class art (ElvUI parchmentRemover branch = our default)
    if frame.BottomBGShadow then frame.BottomBGShadow:Hide() end
    if frame.BottomBG then frame.BottomBG:Hide() end
    if frame.TopBG then frame.TopBG:Hide() end

    if frame.ItemInfo and frame.ItemInfo.UpgradeTo then
        S.SetFont(frame.ItemInfo.UpgradeTo, 13, "OUTLINE")
    end

    -- Item slot button: strip the ornate holder, flat icon + quality
    -- border
    local button = frame.UpgradeItemButton
    if button then
        S.KillAllTextures(button, button.icon)
        S.Backdrop(button)
        if button.icon then
            -- (slot box mis-sized): ElvUI's recipe is
            -- icon:SetInside(button) -- the icon fills the slot minus
            -- 1px, so the button backdrop is the ONE visible box.
            -- Skipping it left Blizzard's inset icon floating inside a
            -- larger frame. Crop only (no per-icon backdrop).
            S.Icon(button.icon)
            button.icon:ClearAllPoints()
            button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
            button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        end
        -- Quality color goes to the BUTTON backdrop (the visible box);
        -- v3.5.797's icon-backdrop target is gone with SetInside.
        if button.IconBorder then S.IconBorder(button.IconBorder, S.GetBackdrop(button)) end
        -- (slot box mis-sized, round two): ButtonFrame
        -- is a TEXTURE (the ornate itemupgrade_slotborder atlas at
        -- native size, LARGER than the 58px button, centered) -- not a
        -- frame. Backdropping it drew an oversized box around art that
        -- KillAllTextures had already removed. No treatment needed.
    end

    -- (animated gold arrow clipped by our borders):
    -- the Arrow frame animates at base level, rendering UNDER the
    -- backdrop borders which slice it mid-flight. Raise it so it
    -- glides over everything; Blizzard's Show/Restart cycle only
    -- touches visibility/anim, never the level.
    if frame.Arrow then
        frame.Arrow:SetFrameLevel(frame:GetFrameLevel() + 20)
        -- shift the sweep path left so the arrow
        -- doesn't overlap the upgrade panel's stat text.
        if frame.Arrow.AdjustPointsOffset then
            frame.Arrow:AdjustPointsOffset(-14, 0)
        end
    end

    if frame.UpgradeButton then S.Button(frame.UpgradeButton) end
    if frame.ItemInfo and frame.ItemInfo.Dropdown then
        S.DropDown(frame.ItemInfo.Dropdown, true)
    end
    if _G.ItemUpgradeFrameCloseButton then
        S.CloseButton(_G.ItemUpgradeFrameCloseButton)
    end
end

S:Register("Blizzard_ItemUpgradeUI", Skin, "ItemUpgrade")

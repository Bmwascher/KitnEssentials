local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local hooksecurefunc = hooksecurefunc

local oldAtlas = {
    Options_ListExpand_Right = true,
    Options_ListExpand_Right_Expanded = true,
}
local function UpdateCollapse(texture, atlas)
    if not atlas or oldAtlas[atlas] then
        local parent = texture:GetParent()
        if parent and parent.IsCollapsed and parent:IsCollapsed() then
            texture:SetAtlas("Soulbinds_Collection_CategoryHeader_Expand")
        else
            texture:SetAtlas("Soulbinds_Collection_CategoryHeader_Collapse")
        end
    end
end

-- state-only button contact for everything living inside the
-- currency-transfer protected flow. These buttons take StripTextures +
-- template and no Kill; S.Button runs S.KillAllTextures (Show->Hide
-- slot writes) which is banned surgery anywhere Blizzard's secure code
-- may read the slot back. The safe contact is: strip (state),
-- ClearButtonArt (ClearTexture + hooked setter re-clear, the permanence
-- idiom), backdrop, hover.
local function StyleButtonClean(button)
    if not button or S.data(button).skinned then return end
    S.StripTextures(button)
    S.ClearButtonArt(button)
    if button.SetPushedTextOffset then button:SetPushedTextOffset(0, 0) end
    local aeBD = S.Backdrop(button)
    if aeBD then
        local c = S.palette.control
        aeBD:SetBackdropColor(c[1], c[2], c[3], c[4])
    end
    S.Hover(button, aeBD)
    S.data(button).skinned = true
end

-- Token-row skin. Two things this deliberately does NOT do:
--   * manufacture a row hover -- calling EnableMouse(true) on rows
--     Blizzard left mouse-disabled changes input state inside the
--     transfer flow, and it breaks our own hover standard (never
--     manufacture hover on mouse-disabled rows). Backdrop and stop.
--   * store the skinned flag as a field on the Blizzard row -> S.data.
-- Updates to this frame can taint transferring currencies, so it gets
-- skinned once and then left alone.
local function StyleEntry(child)
    if not child or S.data(child).skinned then return end

    if child.Right then
        S.StripTextures(child)
        S.Backdrop(child)
        UpdateCollapse(child.Right)
        hooksecurefunc(child.Right, "SetAtlas", UpdateCollapse)
        if child.HighlightRight then
            UpdateCollapse(child.HighlightRight)
            hooksecurefunc(child.HighlightRight, "SetAtlas", UpdateCollapse)
        end
    end

    local icon = child.Content and child.Content.CurrencyIcon
    if icon then S.Icon(icon, true) end
    S.data(child).skinned = true
end

-- Transfer Log rows.
local function StyleLogLine(line)
    if not line or S.data(line).skinned then return end
    local icon = line.CurrencyIcon
    if icon then
        S.Icon(icon, true)
        icon:SetSize(16, 16)
    end
    S.data(line).skinned = true
end

-- WHEN we skin turned out to be the whole story. A staged bisect
-- applied every one of these contacts individually, live,
-- AFTER the frame's first OnShow -- every stage stayed SECURE down the
-- entire ladder and transfers succeeded with all of them applied. The
-- auto pass, by contrast, ran from ADDON_LOADED("Blizzard_TokenUI"),
-- which fires synchronously INSIDE the secure tab click that
-- demand-loads the addon -- i.e. before the frame's first OnShow and
-- before Blizzard's own lazy first-show initialization. Same calls,
-- different moment, FORBIDDEN. So the skin now applies from a
-- HookScript("OnShow") post-hook: Blizzard's OnShow (and the row
-- build inside it) completes first, then we style -- byte-for-byte
-- the timing the bisect proved clean. Do not move this back to
-- load-time application.
local function ApplySkin()
    local frame = _G.TokenFrame
    if not frame then return end

    -- S.StripTextures(TokenFrame) dropped. Never touch the TokenFrame
    -- frame itself -- the CharacterFrame insets that host it are the
    -- right target. Every extra contact with this frame family is a
    -- taint suspect until proven, and this one bought nothing visible.

    if frame.filterDropdown then S.DropDown(frame.filterDropdown) end

    -- `true` (ignoreUpdates) stays -- updates to this scrollbar can
    -- taint transferring currencies. The stepper contact inside
    -- TrimScrollBar is now state-only (see skinScrollArrows), which was
    -- the convicted root of the transfer FORBIDDEN.
    if frame.ScrollBar then S.ScrollBar(frame.ScrollBar, true) end
    if frame.ScrollBox then S.HookScrollBox(frame.ScrollBox, StyleEntry) end

    -- TokenFramePopup (the currency options flyout).
    -- toggle button moved off S.Button (KillAllTextures slot
    -- surgery on a button whose Refresh/UpdateEnabledState runs inside
    -- the protected transfer flow) onto the state-only recipe.
    local popup = _G.TokenFramePopup
    if popup and not S.data(popup).popupSkinned then
        S.data(popup).popupSkinned = true
        S.StripTextures(popup)
        S.Backdrop(popup)
        if popup.InactiveCheckbox then S.CheckBox(popup.InactiveCheckbox) end
        if popup.BackpackCheckbox then S.CheckBox(popup.BackpackCheckbox) end
        if popup.CurrencyTransferToggleButton then
            StyleButtonClean(popup.CurrencyTransferToggleButton)
        end
        local close = popup.CloseButton or _G.TokenFramePopupCloseButton
        if close then S.CloseButton(close) end
    end

    -- Transfer Log window.
    -- TokenFrame.CurrencyTransferLogToggleButton taints when skinned,
    -- so it stays untouched entirely.
    -- the old guard set S.data(log).skinned = true and THEN
    -- called S.Frame(log) -- which gates on the very same key and
    -- bailed immediately. That is why the Log once shipped unskinned.
    -- Own key now; S.Frame's internal guard handles dedupe.
    local log = _G.CurrencyTransferLog
    if log and not S.data(log).logSkinned then
        S.data(log).logSkinned = true
        S.Frame(log)
        if log.ScrollBar then S.TrimScrollBar(log.ScrollBar) end
        if log.ScrollBox then S.HookScrollBox(log.ScrollBox, StyleLogLine) end
    end

    -- Currency Transfer menu. Everything here is the state-only
    -- toolkit, and nothing in the contact surface is skipped.
    local menu = _G.CurrencyTransferMenu
    if menu and not S.data(menu).menuSkinned then
        S.data(menu).menuSkinned = true
        S.StripTextures(menu)
        S.Backdrop(menu)

        if menu.CloseButton then S.CloseButton(menu.CloseButton) end

        local content = menu.Content
        if content then
            if content.SourceSelector and content.SourceSelector.Dropdown then
                S.DropDown(content.SourceSelector.Dropdown)
            end
            if content.AmountSelector then
                if content.AmountSelector.MaxQuantityButton then
                    StyleButtonClean(content.AmountSelector.MaxQuantityButton)
                end
                local input = content.AmountSelector.InputBox
                if input then
                    S.EditBox(input)
                    local bd = S.GetBackdrop(input)
                    if bd then
                        bd:ClearAllPoints()
                        bd:SetPoint("TOPLEFT", input, "TOPLEFT", 0, -3)
                        bd:SetPoint("BOTTOMRIGHT", input, "BOTTOMRIGHT", -1, 8)
                    end
                end
            end
            if content.ConfirmButton then StyleButtonClean(content.ConfirmButton) end
            if content.CancelButton then StyleButtonClean(content.CancelButton) end

            local src = content.SourceBalancePreview
            if src and src.BalanceInfo and src.BalanceInfo.CurrencyIcon then
                S.Icon(src.BalanceInfo.CurrencyIcon, true)
            end
            local ply = content.PlayerBalancePreview
            if ply and ply.BalanceInfo and ply.BalanceInfo.CurrencyIcon then
                S.Icon(ply.BalanceInfo.CurrencyIcon, true)
            end
        end
    end
end

local hooked = false
local function Skin()
    local frame = _G.TokenFrame
    if not frame or hooked then return end
    hooked = true
    if frame:IsShown() then
        ApplySkin()
    end
    frame:HookScript("OnShow", function()
        ApplySkin()
    end)
end

S:Register("Blizzard_UIPanels_Game", Skin, "Currency")
-- CurrencyTransferLog/Menu live in Blizzard_TokenUI, which is
-- load-on-demand -- without this the Transfer Log stays unskinned until
-- something else re-runs the pass.
S:Register("Blizzard_TokenUI", Skin, "Currency")

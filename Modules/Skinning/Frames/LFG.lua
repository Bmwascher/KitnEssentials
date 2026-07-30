local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local ipairs, pairs, next = ipairs, pairs, next -- luacheck: ignore 211/pairs
local CreateFrame, InCombatLockdown = CreateFrame, InCombatLockdown

local NOOP = function() end -- luacheck: ignore 211/NOOP
local function KillFrame(f)
    if not f or S.data(f).killed then return end
    f:Hide()

    if f.SetAlpha then f:SetAlpha(0) end
    hooksecurefunc(f, "Show", function(ff) ff:Hide() end)
    S.data(f).killed = true
end

local function SkinRoleCheck(roleButton)
    if not roleButton then return end
    local check = roleButton.checkButton or roleButton.CheckButton
    if not check or S.data(check).roleDone then return end
    if check.GetScale and check:GetScale() ~= 1 then check:SetScale(1) end

    if check.SetSize then check:SetSize(18, 18) end
    S.CheckBox(check)

    local rb = check:GetParent()
    if rb and rb.GetFrameLevel then
        check:SetFrameLevel(rb:GetFrameLevel() + 2)
        local bd = S.GetBackdrop(check)
        if bd then bd:SetFrameLevel(rb:GetFrameLevel() + 1) end
    end

    local bd = S.GetBackdrop(check)
    if bd then
        bd:ClearAllPoints()
        bd:SetPoint("TOPLEFT", check, "TOPLEFT", 1, -1)
        bd:SetPoint("BOTTOMRIGHT", check, "BOTTOMRIGHT", -1, 1)
    end
    if roleButton.shortageBorder then S.KillTexture(roleButton.shortageBorder) end

    S.SweepCheckChildren(check)
    check:HookScript("OnShow", S.SweepCheckChildren)
    S.data(check).roleDone = true
end

local function IncentiveHide(icon)
    if icon and icon.SetAlpha then icon:SetAlpha(0) end
end

local unpack = unpack
local ROLE_ICON = KE.ROLE_ICONS

-- v4.0.179: the modern role icons are now optional. When off we simply
-- do not replace the texture, so Blizzard's own atlas stays -- nothing
-- is blanked and no restore pass is needed.
local function UseModernRoleIcons()
    local bs = KE.db and KE.db.profile and KE.db.profile.Skinning
        and KE.db.profile.Skinning.BlizzardFrames
    local opt = bs and bs.ModernRoleIcons
    return not opt or opt.Enabled ~= false
end
local ROLE_ORDER = { "TANK", "HEALER", "DAMAGER" }

local function ReskinMemberIcon(enumerate, icon, role, entry)
    local d = S.data(icon)
    if not d.aeSnap then

        S.PixelSnap(icon)
        d.aeSnap = true
    end
    if role and ROLE_ICON[role] then
        if UseModernRoleIcons() then
            icon:SetTexture(ROLE_ICON[role])
            icon:SetTexCoord(0, 1, 0, 1)
        end
        icon:SetAlpha(1)
    else
        icon:SetAlpha(0)
    end

    local isLeader = role and entry and entry[2]
    if isLeader then
        if not d.aeLeader then
            local t = enumerate:CreateTexture(nil, "OVERLAY")
            t:SetAtlas("groupfinder-icon-leader", true)
            t:SetSize(10, 8)
            t:SetPoint("BOTTOM", icon, "TOP", 0, 1)
            d.aeLeader = t
        end
        d.aeLeader:Show()
    elseif d.aeLeader then
        d.aeLeader:Hide()
    end

    local class = role and entry and entry[1]
    local color = class and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[class]
    if color then
        if not d.aeClassBar then
            local t = enumerate:CreateTexture(nil, "ARTWORK")
            t:SetTexture("Interface\\AddOns\\KitnEssentials\\Media\\Statusbars\\KitnEssentials")
            t:SetSize(16, 4)
            t:SetPoint("TOP", icon, "BOTTOM", 0, -1)
            S.PixelSnap(t)
            d.aeClassBar = t
        end
        d.aeClassBar:SetVertexColor(color.r, color.g, color.b)
        d.aeClassBar:Show()
    elseif d.aeClassBar then
        d.aeClassBar:Hide()
    end
end

local lfgTraceShots = 0
local function UpdateEnumerate(enumerate)
    local trace = lfgTraceShots > 0
    if trace then lfgTraceShots = lfgTraceShots - 1 end
    local parent = enumerate:GetParent()
    local button = parent and parent:GetParent()
    local resultID = button and button.resultID
    if trace then print("|cffFF008CKitn|r|cffffffffEssentials:|r lfgicons|r fired; resultID=" .. tostring(resultID)) end
    if not resultID then return end
    local ok, result = pcall(_G.C_LFGList.GetSearchResultInfo, resultID)
    if trace then print("  info ok=" .. tostring(ok) .. " result=" .. tostring(result and "table" or result)) end
    if not ok or not result then return end
    local cache = { TANK = {}, HEALER = {}, DAMAGER = {} }
    local okN, num = pcall(function() return result.numMembers end)
    num = (okN and num) or 0
    if trace then print("  numMembers=" .. tostring(num)) end
    for i = 1, num do
        local ok2, p = pcall(_G.C_LFGList.GetSearchResultPlayerInfo, resultID, i)
        if ok2 and p and p.assignedRole and cache[p.assignedRole] then
            local t = cache[p.assignedRole]
            t[#t + 1] = { p.classFilename, p.isLeader }
        end
    end
    if trace then
        print(("  cache T=%d H=%d D=%d; Icon1=%s RoleIcon=%s"):format(
            #cache.TANK, #cache.HEALER, #cache.DAMAGER,
            tostring(enumerate.Icon1 ~= nil),
            tostring(enumerate.Icon1 and enumerate.Icon1.RoleIcon ~= nil)))
    end
    for i = 5, 1, -1 do
        local slot = enumerate["Icon" .. i]

        local icon = slot and (slot.RoleIconWithBackground or slot.RoleIcon)
        if icon and icon.SetTexture then
            local role, entry
            for r = 1, 3 do
                local list = cache[ROLE_ORDER[r]]
                if #list > 0 then
                    role, entry = ROLE_ORDER[r], list[1]
                    table.remove(list, 1)
                    break
                end
            end
            ReskinMemberIcon(enumerate, icon, role, entry)
        end
        if slot and slot.ClassCircle then slot.ClassCircle:Hide() end
    end
end

local ROLE_COUNT_SLOTS = {
    { "TankIconWithBackground", "TankIcon", "TANK" },
    { "HealerIconWithBackground", "HealerIcon", "HEALER" },
    { "DamagerIconWithBackground", "DamagerIcon", "DAMAGER" },
}
local function UpdateRoleCount(roleCount)
    for i = 1, 3 do
        local slot = ROLE_COUNT_SLOTS[i]
        local icon = roleCount[slot[1]] or roleCount[slot[2]]
        if icon and icon.SetTexture then
            local d = S.data(icon)
            if not d.aeSnap then
                S.PixelSnap(icon)
                d.aeSnap = true
            end
            if UseModernRoleIcons() then
                icon:SetTexture(ROLE_ICON[slot[3]])
                icon:SetTexCoord(0, 1, 0, 1)
            end
        end
    end
end

local lfgListIconsHooked = false
local lfgListIconsReported = false
local function HookLFGListIcons()
    if lfgListIconsHooked then return end
    if _G.LFGListGroupDataDisplayEnumerate_Update and _G.C_LFGList
        and _G.C_LFGList.GetSearchResultPlayerInfo then
        -- DEFERRED, same reason as the applicant hooks below:
        -- LFGListApplicationViewer_UpdateInfo drives the DataDisplay and
        -- then compares SECRET values (the listing name is |Kl21|k), so
        -- running our icon swap inside its execution taints it:
        --
        --   LFGList.lua:1614: attempt to compare a secret number value
        --   (execution tainted by 'KitnEssentials')
        --
        -- Icon swaps are cosmetic; a frame later is fine.
        local function Defer(fn, key)
            return function(frame, ...)
                if not frame or S.data(frame)[key] then return end
                S.data(frame)[key] = true
                local args = { ... }
                C_Timer.After(0, function()
                    S.data(frame)[key] = nil
                    fn(frame, unpack(args))
                end)
            end
        end

        hooksecurefunc("LFGListGroupDataDisplayEnumerate_Update",
            Defer(UpdateEnumerate, "enumQueued"))
        if _G.LFGListGroupDataDisplayRoleCount_Update then
            hooksecurefunc("LFGListGroupDataDisplayRoleCount_Update",
                Defer(UpdateRoleCount, "roleCountQueued"))
        end
        lfgListIconsHooked = true
    elseif not lfgListIconsReported then

        lfgListIconsReported = true
        print("|cffFF008CKitn|r|cffffffffEssentials:|r group-finder role icons: hook site missing (will retry on rerun)")
    end
end

function S.DebugLFGIconsTrace(n)
    lfgTraceShots = n or 3
    print("|cffFF008CKitn|r|cffffffffEssentials:|r lfgicons trace armed for " .. lfgTraceShots .. " updates -- hooked=" .. tostring(lfgListIconsHooked))
end

local GROUP_BUTTON_ICONS = { 133076, 133074, 464820 }

local function Skin()
    local frame = _G.PVEFrame
    if not frame then return end
    S.Frame(frame)
    if _G.PVEFrameBg then _G.PVEFrameBg:Hide() end
    KillFrame(frame.shadows)
    S.Tabs("PVEFrameTab", 4)

    local function EnsureSel(btn)
        local d = S.data(btn)
        if not d.selTex then
            local t = btn:CreateTexture(nil, "ARTWORK")
            t:SetColorTexture(S.palette.brand[1], S.palette.brand[2], S.palette.brand[3], 0.15)
            local anchor = S.GetBackdrop(btn) or btn
            t:SetPoint("TOPLEFT", anchor, "TOPLEFT", 1, -1)
            t:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -1, 1)
            t:Hide()
            d.selTex = t
        end
        return d.selTex
    end
    local gf = _G.GroupFinderFrame
    if gf then
        local i = 1
        local button = gf["groupButton" .. i]
        while button do
            if button.ring then button.ring:Hide() end
            if button.CircleMask then button.CircleMask:Hide() end
            if button.bg then S.KillTexture(button.bg) end
            S.Button(button, button.icon)
            S.SelectedFill(button)
            if button.icon then

                if GROUP_BUTTON_ICONS[i] then button.icon:SetTexture(GROUP_BUTTON_ICONS[i]) end
                button.icon:SetSize(45, 45)
                button.icon:ClearAllPoints()
                button.icon:SetPoint("LEFT", 10, 0)
                S.Icon(button.icon, true)
            end
            EnsureSel(button)
            i = i + 1
            button = gf["groupButton" .. i]
        end
        if _G.GroupFinderFrame_SelectGroupButton and not S.data(gf).selHook then
            hooksecurefunc("GroupFinderFrame_SelectGroupButton", function(index)
                local n = 1
                local b = gf["groupButton" .. n]
                while b do
                    local t = S.data(b).selTex
                    if t then t:SetShown(n == index) end
                    n = n + 1
                    b = gf["groupButton" .. n]
                end
            end)
            S.data(gf).selHook = true
        end
    end

    if _G.LFDParentFrame then S.StripTextures(_G.LFDParentFrame) end
    if _G.LFDParentFrameInset then S.StripTextures(_G.LFDParentFrameInset) end

    if _G.PVEFrame and _G.PVEFrame.NineSlice and _G.PVEFrame.NineSlice.EnableMouse then
        _G.PVEFrame.NineSlice:EnableMouse(false)
    end
    if _G.LFDQueueFrame then S.StripTextures(_G.LFDQueueFrame, true) end
    if _G.LFDQueueFrameFindGroupButton then S.Button(_G.LFDQueueFrameFindGroupButton) end
    local lfdScroll = _G.LFDQueueFrameRandomScrollFrame
    if lfdScroll and lfdScroll.ScrollBar then S.TrimScrollBar(lfdScroll.ScrollBar) end

    for _, name in ipairs({
        "LFDQueueFrameRandomScrollFrameChildFrameMoneyReward",
        "RaidFinderQueueFrameScrollFrameChildFrameMoneyReward",
    }) do
        local b = _G[name]
        if b and not S.data(b).skinned then
            local icon = _G[name .. "IconTexture"] or b.Icon or b.icon
            local nameFrame = _G[name .. "NameFrame"]
            local bd
            if icon then
                S.Icon(icon)
                bd = S.Backdrop(icon)
            end
            if nameFrame and nameFrame.SetTexture then nameFrame:SetTexture(nil) end
            if b.IconBorder and bd then S.IconBorder(b.IconBorder, bd) end
            S.data(b).skinned = true
        end
    end

    if _G.LFGRewardsFrame_SetItemButton and not S.skinIndex.__lfgRewardHook then
        S.skinIndex.__lfgRewardHook = true
        hooksecurefunc("LFGRewardsFrame_SetItemButton", function(frame, _, index) -- luacheck: ignore 431/frame
            local parentName = frame:GetName()
            if not parentName then return end
            local item = _G[parentName .. "Item" .. index]
            if not item or S.data(item).skinned then return end
            local icon = _G[parentName .. "Item" .. index .. "IconTexture"] or item.Icon or item.icon
            local bd
            if icon then
                S.Icon(icon)
                bd = S.Backdrop(icon)
            end
            local nameFrame = item.NameFrame or _G[parentName .. "Item" .. index .. "NameFrame"]
            if nameFrame and nameFrame.SetTexture then nameFrame:SetTexture(nil) end
            if item.shortageBorder then S.KillTexture(item.shortageBorder) end
            if item.IconBorder and bd then S.IconBorder(item.IconBorder, bd) end
            S.data(item).skinned = true
        end)
    end
    if _G.LFDQueueFrameTypeDropdown then S.DropDown(_G.LFDQueueFrameTypeDropdown, true) end

    local WHITE = "Interface\\Buttons\\WHITE8x8"
    local function MiniReassert(region, texture)
        if texture ~= WHITE then region:SetTexture(WHITE) end
    end
    local function SpecificChild(child)
        local eb = child and child.enableButton
        if not eb then return end
        S.CheckBox(eb)

        local ct = eb.GetCheckedTexture and eb:GetCheckedTexture()
        if ct and not S.data(ct).flat then S.CheckRefresh(eb) end
        for _, r in ipairs({ eb:GetRegions() }) do
            if r.IsObjectType and r:IsObjectType("Texture") and not S.data(r).flat then
                local tex = r:GetTexture()
                if tex == 130751 then
                    S.data(r).flat = true
                    r:SetAlpha(1)

                    hooksecurefunc(r, "SetAlpha", function(rr, a)
                        local dd = S.data(rr)
                        if a ~= 1 and not dd.aSetting then
                            dd.aSetting = true
                            rr:SetAlpha(1)
                            dd.aSetting = nil
                        end
                    end)
                    r:SetTexture(WHITE)
                    r:SetVertexColor(S.palette.brand[1], S.palette.brand[2], S.palette.brand[3], S.palette.brandRestA)
                    hooksecurefunc(r, "SetTexture", MiniReassert)
                elseif tex ~= nil then
                    S.KillTexture(r)
                end
            end
        end
    end
    local function SpecificUpdate(sb) sb:ForEachFrame(SpecificChild) end

    local function EnsureFlatCheck(btn)
        if not btn then return end
        S.CheckBox(btn)
        local ct = btn.GetCheckedTexture and btn:GetCheckedTexture()
        if ct and not S.data(ct).flat then S.CheckRefresh(btn) end
    end
    EnsureFlatCheck(_G.LFDQueueFrameSpecificEnableButton)
    EnsureFlatCheck(_G.LFDQueueFrameFollowerEnableButton)
    for _, holder in ipairs({ _G.LFDQueueFrameSpecific, _G.LFDQueueFrameFollower }) do
        local sb = holder and holder.ScrollBox
        if sb and sb.ForEachFrame and not S.data(sb).lfdHook then
            S.data(sb).lfdHook = true
            hooksecurefunc(sb, "Update", SpecificUpdate)
            SpecificUpdate(sb)
        end
    end

    HookLFGListIcons()

    for _, role in ipairs({ "Tank", "Healer", "DPS" }) do
        local icon = _G["LFDQueueFrameRoleButton" .. role .. "IncentiveIcon"]
        if icon then
            IncentiveHide(icon)
            icon:HookScript("OnShow", IncentiveHide)
        end
    end

    local appDialog = _G.LFGListApplicationDialog
    for _, rb in ipairs({
        _G.LFDQueueFrameRoleButtonTank, _G.LFDQueueFrameRoleButtonHealer,
        _G.LFDQueueFrameRoleButtonDPS, _G.LFDQueueFrameRoleButtonLeader,
        _G.RaidFinderQueueFrameRoleButtonTank, _G.RaidFinderQueueFrameRoleButtonHealer,
        _G.RaidFinderQueueFrameRoleButtonDPS, _G.RaidFinderQueueFrameRoleButtonLeader,
        _G.LFGInvitePopupRoleButtonTank, _G.LFGInvitePopupRoleButtonHealer,
        _G.LFGInvitePopupRoleButtonDPS,
        appDialog and appDialog.TankButton, appDialog and appDialog.HealerButton,
        appDialog and appDialog.DamagerButton,
        _G.RolePollPopupRoleButtonTank, _G.RolePollPopupRoleButtonHealer,
        _G.RolePollPopupRoleButtonDPS,
    }) do
        SkinRoleCheck(rb)
    end

    if not S.data(frame).radioHook then
        hooksecurefunc("SetCheckButtonIsRadio", function(button)
            if button and not S.data(button).skinned then S.CheckBox(button) end
        end)
        S.data(frame).radioHook = true
    end

    if _G.RaidFinderFrame then S.StripTextures(_G.RaidFinderFrame) end
    if _G.RaidFinderFrameRoleInset then S.StripTextures(_G.RaidFinderFrameRoleInset) end

    if _G.RaidFinderFrameBottomInset then S.StripTextures(_G.RaidFinderFrameBottomInset) end
    local rfq = _G.RaidFinderQueueFrame
    if rfq then
        S.StripTextures(rfq, true)

        for _, key in ipairs({ "ShadowOverlay", "Background", "BackgroundTexture" }) do
            local r = rfq[key]
            if r then
                if r.SetAlpha then r:SetAlpha(0) end
                if r.DisableDrawLayer then S.StripTextures(r) end
            end
        end
        if _G.RaidFinderQueueFrameBackground then _G.RaidFinderQueueFrameBackground:SetAlpha(0) end
    end
    if _G.RaidFinderQueueFrameSelectionDropdown then
        S.DropDown(_G.RaidFinderQueueFrameSelectionDropdown, true)
    end
    if _G.RaidFinderFrameFindRaidButton then S.Button(_G.RaidFinderFrameFindRaidButton) end

    if _G.LFDQueueFramePartyBackfillBackfillButton then S.Button(_G.LFDQueueFramePartyBackfillBackfillButton) end
    if _G.LFDQueueFramePartyBackfillNoBackfillButton then S.Button(_G.LFDQueueFramePartyBackfillNoBackfillButton) end

    local readyStatus = _G.LFGDungeonReadyStatus
    if readyStatus and not S.data(readyStatus).skinned then
        S.StripTextures(readyStatus)
        S.Backdrop(readyStatus)
        if _G.LFGDungeonReadyStatusCloseButton then S.CloseButton(_G.LFGDungeonReadyStatusCloseButton) end
        S.data(readyStatus).skinned = true
    end
    local readyDialog = _G.LFGDungeonReadyDialog
    if readyDialog and not S.data(readyDialog).skinned then
        S.StripTextures(readyDialog)
        S.Backdrop(readyDialog)

        if readyDialog.Border then readyDialog.Border:Hide() end
        if readyDialog.enterButton then S.Button(readyDialog.enterButton) end
        if readyDialog.leaveButton then S.Button(readyDialog.leaveButton) end
        if _G.LFGDungeonReadyDialogCloseButton then S.CloseButton(_G.LFGDungeonReadyDialogCloseButton) end
        S.data(readyDialog).skinned = true
    end
    local ready = _G.ReadyStatus
    if ready and not S.data(ready).skinned then
        S.StripTextures(ready)
        S.Backdrop(ready)
        if ready.CloseButton then S.CloseButton(ready.CloseButton) end
        S.data(ready).skinned = true
    end
    local poll = _G.RolePollPopup
    if poll and not S.data(poll).skinned then
        S.StripTextures(poll)
        S.Backdrop(poll)
        if _G.RolePollPopupAcceptButton then S.Button(_G.RolePollPopupAcceptButton) end
        if _G.RolePollPopupCloseButton then S.CloseButton(_G.RolePollPopupCloseButton) end
        S.data(poll).skinned = true
    end

    local lfgList = _G.LFGListFrame
    if lfgList and not S.data(lfgList).skinned then
        S.data(lfgList).skinned = true
        local cat = lfgList.CategorySelection
        if cat then
            if cat.Inset then S.StripTextures(cat.Inset) end
            if cat.StartGroupButton then S.Button(cat.StartGroupButton) end
            if cat.FindGroupButton then S.Button(cat.FindGroupButton) end
        end

        if _G.LFGListCategorySelection_AddButton then
            -- v4.0.115: these buttons are re-Shown by Blizzard's own secure
            -- path (LFGListCategorySelection_AddButton -> button:Show()), and
            -- a user hit ADDON_ACTION_BLOCKED on that Show when abandoning a
            -- dungeon. Doing insecure frame work on Blizzard's regions while
            -- a protected path is live is what puts us in that stack, so all
            -- of it is held until combat drops. Nothing here is urgent -- the
            -- category list is not interactable mid-fight anyway.
            local pendingCategories = {}
            local combatWatcher

            local function DressCategoryButton(button)
                if not S.data(button).skinned then
                    S.data(button).skinned = true
                    S.Backdrop(button)

                    local bd = S.GetBackdrop(button) or button

                    if button.Icon then
                        button.Icon:SetDrawLayer("BACKGROUND", 2)
                        button.Icon:SetTexCoord(0, 1, 0, 1)
                        button.Icon:ClearAllPoints()
                        button.Icon:SetPoint("TOPLEFT", bd, "TOPLEFT", 1, -1)
                        button.Icon:SetPoint("BOTTOMRIGHT", bd, "BOTTOMRIGHT", -1, 1)
                    end

                    if button.Cover then button.Cover:Hide() end

                    if button.HighlightTexture then
                        local c = S.palette.hover
                        button.HighlightTexture:SetColorTexture(c[1], c[2], c[3], 0.1)
                        button.HighlightTexture:ClearAllPoints()
                        button.HighlightTexture:SetPoint("TOPLEFT", bd, "TOPLEFT", 1, -1)
                        button.HighlightTexture:SetPoint("BOTTOMRIGHT", bd, "BOTTOMRIGHT", -1, 1)
                    end

                    if button.Label then S.SetFont(button.Label, 13, "") end
                end

                if button.SelectedTexture then button.SelectedTexture:Hide() end

                local bd = S.GetBackdrop(button)
                if not bd then return end

                local sel = button:GetParent()
                local selected = sel and sel.selectedCategory == button.categoryID
                    and sel.selectedFilters == button.filters

                if selected then
                    local c = S.palette.brand
                    bd:SetBackdropBorderColor(c[1], c[2], c[3], 1)
                else
                    bd:SetBackdropBorderColor(S.borderColor[1], S.borderColor[2],
                        S.borderColor[3], S.borderColor[4])
                end
            end

            local function DrainPending()
                for button in next, pendingCategories do
                    pendingCategories[button] = nil
                    DressCategoryButton(button)
                end
            end

            local function QueueCategoryButton(button)
                if not InCombatLockdown() then
                    DressCategoryButton(button)
                    return
                end

                pendingCategories[button] = true
                if combatWatcher then return end

                combatWatcher = CreateFrame("Frame")
                combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
                combatWatcher:SetScript("OnEvent", function(f)
                    f:UnregisterAllEvents()
                    combatWatcher = nil
                    DrainPending()
                end)
            end

            hooksecurefunc("LFGListCategorySelection_AddButton", function(sel, btnIndex)
                local button = sel.CategoryButtons and sel.CategoryButtons[btnIndex]
                if button then QueueCategoryButton(button) end
            end)
        end
        if lfgList.NothingAvailable and lfgList.NothingAvailable.Inset then
            S.StripTextures(lfgList.NothingAvailable.Inset)
        end

        local ec = lfgList.EntryCreation
        if ec then
            if ec.Inset then S.StripTextures(ec.Inset) end
            if ec.CancelButton then S.Button(ec.CancelButton) end
            if ec.ListGroupButton then S.Button(ec.ListGroupButton) end
            if ec.Name then S.EditBox(ec.Name) end
            if ec.Description then S.EditBox(ec.Description) end
            if ec.GroupDropdown then S.DropDown(ec.GroupDropdown, true) end
            if ec.ActivityDropdown then S.DropDown(ec.ActivityDropdown, true) end
            if ec.PlayStyleDropdown then S.DropDown(ec.PlayStyleDropdown, true) end
            for _, key in ipairs({ "ItemLevel", "MythicPlusRating", "PVPRating", "PvpItemLevel", "VoiceChat", "PrivateGroup", "CrossFactionGroup" }) do
                local row = ec[key]
                if row then
                    if row.EditBox then S.EditBox(row.EditBox) end
                    if row.CheckButton then S.CheckBox(row.CheckButton) end
                end
            end
            local dialog = ec.ActivityFinder and ec.ActivityFinder.Dialog
            if dialog then
                S.StripTextures(dialog)
                S.Backdrop(dialog)
                if dialog.BorderFrame then S.StripTextures(dialog.BorderFrame) end
                if dialog.EntryBox then S.EditBox(dialog.EntryBox) end
                if dialog.SelectButton then S.Button(dialog.SelectButton) end
                if dialog.CancelButton then S.Button(dialog.CancelButton) end
            end
        end

        local sp = lfgList.SearchPanel
        if sp then
            if sp.SearchBox then
                S.EditBox(sp.SearchBox)
                S.SetFont(sp.SearchBox, 12, "")
            end
            if sp.BackButton then S.Button(sp.BackButton) end
            if sp.SignUpButton then S.Button(sp.SignUpButton) end

            if sp.ScrollBox and sp.ScrollBox.StartGroupButton then
                S.OverlayButton(sp.ScrollBox.StartGroupButton, 135, 22, _G.START_A_GROUP, nil, "HIGH")
            end
            if sp.BackToGroupButton then S.Button(sp.BackToGroupButton) end
            if sp.FilterButton then
                S.Button(sp.FilterButton)
                if sp.FilterButton.ResetButton then S.CloseButton(sp.FilterButton.ResetButton) end
            end
            if sp.RefreshButton then
                S.Button(sp.RefreshButton, sp.RefreshButton.Icon)
                sp.RefreshButton:SetSize(24, 24)
                if sp.RefreshButton.Icon then
                    sp.RefreshButton.Icon:ClearAllPoints()
                    sp.RefreshButton.Icon:SetPoint("CENTER")
                end
            end
            if sp.ResultsInset then S.StripTextures(sp.ResultsInset) end
            if sp.ScrollBar then S.TrimScrollBar(sp.ScrollBar) end
            local ac = sp.AutoCompleteFrame
            if ac then
                S.StripTextures(ac)
                S.Backdrop(ac)
            end
        end

        local av = lfgList.ApplicationViewer
        if av then
            if av.Inset then S.StripTextures(av.Inset) end
            -- v3.5.784 (keep the art, lose Blizzard's border):
            -- the art and border are one atlas, so the border is
            -- cropped off in TEXCOORD space -- resolve the atlas's file
            -- rect via C_Texture.GetAtlasInfo and inset past the baked
            -- decorative frame (~3.5% x, ~10% y). Re-applied whenever
            -- Blizzard re-SetAtlas-es (activity/category changes), and
            -- a border-only S.Backdrop frame supplies the 1px edge.
            local function CropInfoBackground(tex)
                S.CropAtlasEdges(tex, 0.035, 0.10) -- v3.5.786: promoted primitive
            end
            if av.InfoBackground and not S.data(av.InfoBackground).cropHooked then
                S.data(av.InfoBackground).cropHooked = true
                -- DEFERRED. LFGListApplicationViewer_UpdateInfo re-atlases
                -- this texture and then compares SECRET values (the
                -- listing name is |Kl21|k) -- running our crop inside
                -- that call taints it:
                --
                --   LFGList.lua:1614: attempt to compare a secret number
                --   value (execution tainted by 'KitnEssentials')
                hooksecurefunc(av.InfoBackground, "SetAtlas", function(tex)
                    if S.data(tex).cropQueued then return end
                    S.data(tex).cropQueued = true
                    C_Timer.After(0, function()
                        S.data(tex).cropQueued = nil
                        CropInfoBackground(tex)
                    end)
                end)
                CropInfoBackground(av.InfoBackground)
                local bg = CreateFrame("Frame", nil, av)
                bg:SetAllPoints(av.InfoBackground)
                bg:SetFrameLevel(av:GetFrameLevel() + 1)
                S.Backdrop(bg, nil, true) -- border only, art shows through
            end
            if av.EntryName then S.SetFont(av.EntryName, 14, "OUTLINE") end
            if av.AutoAcceptButton then S.CheckBox(av.AutoAcceptButton) end
            if av.BrowseGroupsButton then S.Button(av.BrowseGroupsButton) end
            if av.RefreshButton then S.Button(av.RefreshButton, av.RefreshButton.Icon) end
            if av.RemoveEntryButton then S.Button(av.RemoveEntryButton) end
            if av.EditButton then S.Button(av.EditButton) end
            if av.ScrollBar then S.TrimScrollBar(av.ScrollBar) end
            for _, key in ipairs({ "NameColumnHeader", "RoleColumnHeader", "ItemLevelColumnHeader", "RatingColumnHeader" }) do
                local h = av[key]
                if h then S.StripTextures(h) end
            end
        end
    end

    -- v3.5.777 (applicant accept/decline unskinned; role icons
    -- not matching our apply skin). ElvUI hooks
    -- LFGListApplicationViewer_UpdateApplicant for the buttons; role
    -- icons restyle in LFGListApplicationViewer_UpdateRoleIcons, where
    -- Blizzard atlases RoleIcon1..3 -- swap those atlases for the same
    -- flat ROLE_ICON textures the search-results skin uses.
    if _G.LFGListApplicationViewer_UpdateApplicant and not S.data(lfgList).applicantHook then
        S.data(lfgList).applicantHook = true
        local function SkinApplicantAction(btn)
            if not btn or S.data(btn).skinned then return end
            -- Midnight can atlas check/x art onto these stretch
            -- buttons; preserve it as the keep-region when present.
            local nt = btn.GetNormalTexture and btn:GetNormalTexture()
            local hasArt = nt and ((nt.GetAtlas and nt:GetAtlas()) or (nt.GetTexture and nt:GetTexture()))
            if hasArt then
                S.Button(btn, nt)
            else
                S.Button(btn)
            end
            -- v3.5.784 (check/x boxes looked grey): compact icon
            -- buttons read better on the theme background than on the
            -- control-grey fill. S.Backdrop cached-returns the existing
            -- backdrop.
            local bd = S.Backdrop(btn)
            if bd then bd:SetBackdropColor(0.063, 0.063, 0.063, 0.90) end -- palette control alpha
        end
        -- DEFERRED. Applicant data is SECRET (applicantID, comment,
        -- displayOrderID, isNew) and Blizzard compares it inside the same
        -- execution that calls this hook -- LFGListApplicationViewer_
        -- UpdateResultList -> LFGListUtil_SortApplicants -> table.sort.
        -- Running our skin there taints that execution and their own
        -- comparisons blow up:
        --
        --   LFGList.lua:4002: attempt to compare field 'isNew' (a secret
        --   boolean value, while execution tainted by
        --   'KitnEssentials')
        --
        -- Everything below is cosmetic, so a frame later is fine and
        -- takes us out of their chain entirely.
        local function SkinApplicantRow(button)
            if not button then return end
            SkinApplicantAction(button.DeclineButton)
            SkinApplicantAction(button.InviteButton)
            SkinApplicantAction(button.InviteButtonSmall)
            if button.Name then S.SetFont(button.Name, 13, "") end
        end

        hooksecurefunc("LFGListApplicationViewer_UpdateApplicant", function(button)
            if not button or S.data(button).skinQueued then return end
            S.data(button).skinQueued = true
            C_Timer.After(0, function()
                S.data(button).skinQueued = nil
                SkinApplicantRow(button)
            end)
        end)
        if _G.LFGListApplicationViewer_UpdateRoleIcons then
            -- Same chain, same deferral.
            local function SkinRoleIcons(member)
                if not member then return end
                for i = 1, 3 do
                    local roleBtn = member["RoleIcon" .. i]
                    local nt = roleBtn and roleBtn.GetNormalTexture and roleBtn:GetNormalTexture()
                    if nt then
                        -- v3.5.784: match LOWERCASED -- the micro-role
                        -- atlases from GetMicroIconForRole are MixedCase,
                        -- so the case-sensitive find never hit (:
                        -- role icons weren't swapped).
                        local atlas = nt.GetAtlas and nt:GetAtlas()
                        atlas = atlas and atlas:lower()
                        local role = atlas and (
                            atlas:find("tank") and "TANK"
                            or atlas:find("heal") and "HEALER"
                            or (atlas:find("dps") or atlas:find("damage")) and "DAMAGER")
                        if role and ROLE_ICON and ROLE_ICON[role]
                            and UseModernRoleIcons() then
                            nt:SetTexture(ROLE_ICON[role])
                            nt:SetTexCoord(0, 1, 0, 1)
                            local hl = roleBtn.GetHighlightTexture and roleBtn:GetHighlightTexture()
                            if hl then
                                hl:SetTexture(ROLE_ICON[role])
                                hl:SetTexCoord(0, 1, 0, 1)
                                hl:SetAlpha(0.3)
                            end
                        end
                    end
                end
            end

            hooksecurefunc("LFGListApplicationViewer_UpdateRoleIcons", function(member)
                if not member or S.data(member).roleQueued then return end
                S.data(member).roleQueued = true
                C_Timer.After(0, function()
                    S.data(member).roleQueued = nil
                    SkinRoleIcons(member)
                end)
            end)
        end
    end

    if _G.LFGListSearchEntry_Update and not S.data(lfgList).fontHook then
        hooksecurefunc("LFGListSearchEntry_Update", function(entry)

            if entry.CancelButton and not S.data(entry.CancelButton).skinned then
                S.CloseButton(entry.CancelButton)
            end
            if entry.InviteButton and not S.data(entry.InviteButton).skinned then
                S.Button(entry.InviteButton)
            end
            if entry.InviteButtonSmall and not S.data(entry.InviteButtonSmall).skinned then
                S.Button(entry.InviteButtonSmall)
            end
            if entry.Name then S.SetFont(entry.Name, 13, "") end
            if entry.ActivityName then S.SetFont(entry.ActivityName, 13, "") end

            if entry.Playstyle then S.SetFont(entry.Playstyle, 12, "") end
        end)
        S.data(lfgList).fontHook = true
    end

    local app = _G.LFGListApplicationDialog
    if app and not S.data(app).skinned then
        S.StripTextures(app)
        S.Backdrop(app)
        if app.SignUpButton then S.Button(app.SignUpButton) end
        if app.CancelButton then S.Button(app.CancelButton) end
        if _G.LFGListApplicationDialogDescription then S.EditBox(_G.LFGListApplicationDialogDescription) end
        S.data(app).skinned = true
    end
    local inv = _G.LFGListInviteDialog
    if inv and not S.data(inv).skinned then
        S.StripTextures(inv)
        S.Backdrop(inv)
        if inv.AcknowledgeButton then S.Button(inv.AcknowledgeButton) end
        if inv.AcceptButton then S.Button(inv.AcceptButton) end
        if inv.DeclineButton then S.Button(inv.DeclineButton) end
        S.data(inv).skinned = true
    end
end

S:RegisterEarly(Skin, "LFG")

local function SkinAffixes(child)
    if not child then return end
    local list = (child.AffixesContainer and child.AffixesContainer.Affixes) or child.Affixes
    if not list then return end
    for _, af in ipairs(list) do
        if af.Border then af.Border:SetTexture(nil) end
        if af.CircleMask then af.CircleMask:Hide() end
        -- v3.5.785 (% text clipping the border): Blizzard
        -- anchors Percent hanging BELOW the ring (BOTTOM y=-4), which
        -- reads as clipping on our square icons. Re-anchor inside and
        -- standardize the font; Blizzard's SetUp only swaps
        -- FontObject, so our SetFont (running after via the hooks)
        -- wins, and the anchor is ours permanently.
        if af.Percent then
            S.SetFont(af.Percent, 12, "OUTLINE")
            af.Percent:ClearAllPoints()
            af.Percent:SetPoint("BOTTOM", af, "BOTTOM", 0, 2)
        end
        if af.Portrait then
            if af.info and _G.CHALLENGE_MODE_EXTRA_AFFIX_INFO and _G.CHALLENGE_MODE_EXTRA_AFFIX_INFO[af.info.key] then
                af.Portrait:SetTexture(_G.CHALLENGE_MODE_EXTRA_AFFIX_INFO[af.info.key].texture)
            elseif af.affixID and C_ChallengeMode and C_ChallengeMode.GetAffixInfo then
                local _, _, filedataid = C_ChallengeMode.GetAffixInfo(af.affixID)
                if filedataid then af.Portrait:SetTexture(filedataid) end
            end
            S.Icon(af.Portrait, true)
        end
    end
end

local function SkinChallenges()
    local cf = _G.ChallengesFrame
    if not cf or S.data(cf).skinned then return end
    S.data(cf).skinned = true
    cf:DisableDrawLayer("BACKGROUND")
    if _G.ChallengesFrameInset then S.StripTextures(_G.ChallengesFrameInset) end

    local ks = _G.ChallengesKeystoneFrame
    if ks then
        -- v3.5.786 : keep Blizzard's interior art wholesale --
        -- parchment, rune circle, golden slot ring, instruction bar,
        -- insert animation glows. The parchment atlas
        -- (ChallengeMode-KeystoneFrame) bakes the ornate gold border
        -- in, so crop it in texcoord space and draw a 1px edge
        -- instead. No StripTextures, no slot meddling: the "weird"
        -- bare-square slot was our own S.Icon crop + region sweep.
        -- v3.5.791 (diagnostic-confirmed): the parchment is region 1
        -- with the expected atlas, but the frame's INTRO ANIMATION
        -- writes alpha onto its regions every open -- SetAlpha(0) was
        -- applied and then overwritten (dump showed alpha back at
        -- 1.00, with a dozen sibling regions at anim-managed alphas).
        -- Kill the texture CONTENT instead: nothing ever re-sets this
        -- atlas, so SetTexture(nil) is animation-proof. The dump also
        -- showed our S.Backdrop at child level 0, i.e. everything we
        -- drew (including the Activate button's fill impression) sat
        -- UNDER the parchment -- one kill fixes both symptoms, and
        -- level 0 is correct stacking once the parchment is gone
        -- (dark fill beneath the level-1 RuneBG glyph art).
        for _, region in ipairs({ ks:GetRegions() }) do
            if region.IsObjectType and region:IsObjectType("Texture")
                and region.GetAtlas and region:GetAtlas() == "ChallengeMode-KeystoneFrame" then
                region:SetTexture(nil)
            end
        end
        S.Backdrop(ks)
        if ks.DungeonName then S.SetFont(ks.DungeonName, 26, "OUTLINE") end
        if ks.TimeLimit then S.SetFont(ks.TimeLimit, 20, "OUTLINE") end
        if ks.Instructions then S.SetFont(ks.Instructions, 15, "OUTLINE") end
        if ks.StartButton then S.Button(ks.StartButton) end
        if ks.CloseButton then S.CloseButton(ks.CloseButton) end
        if ks.OnKeystoneSlotted then
            hooksecurefunc(ks, "OnKeystoneSlotted", SkinAffixes)
        end
    end

    hooksecurefunc(cf, "Update", function(f)
        if not f.DungeonIcons then return end
        for _, child in ipairs(f.DungeonIcons) do
            if not S.data(child).skinned then
                local first = child:GetRegions()
                if first and first.SetAlpha then first:SetAlpha(0) end
                S.Backdrop(child)
                if child.Icon then
                    S.Icon(child.Icon)

                    child.Icon:ClearAllPoints()
                    child.Icon:SetPoint("TOPLEFT", child, "TOPLEFT", 1, -1)
                    child.Icon:SetPoint("BOTTOMRIGHT", child, "BOTTOMRIGHT", -1, 1)

                end
                S.data(child).skinned = true
            end
        end
    end)

    if _G.ChallengesFrameWeeklyInfoMixin then
        hooksecurefunc(_G.ChallengesFrameWeeklyInfoMixin, "SetUp", function(info)
            if C_MythicPlus and C_MythicPlus.GetCurrentAffixes and C_MythicPlus.GetCurrentAffixes() then
                SkinAffixes(info.Child)
            end
        end)
    end

    local notice = cf.SeasonChangeNoticeFrame
    if notice then
        S.StripTextures(notice)
        S.Backdrop(notice)
        if notice.Leave then S.Button(notice.Leave) end
        if notice.NewSeason then notice.NewSeason:SetTextColor(1, 0.8, 0) end
    end
end

S:Register("Blizzard_ChallengesUI", SkinChallenges, "LFG")

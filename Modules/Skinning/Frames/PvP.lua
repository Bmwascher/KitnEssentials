local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local ipairs, pairs = ipairs, pairs -- luacheck: ignore 211/pairs

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

local function SkinCategoryButton(bu)
    if not bu or S.data(bu).skinned then return end
    if bu.Ring then S.KillTexture(bu.Ring) end
    if bu.CircleMask then bu.CircleMask:Hide() end
    if bu.Background then S.KillTexture(bu.Background) end
    S.Button(bu, bu.Icon)
    S.SelectedFill(bu)
    EnsureSel(bu)
    if bu.Icon then
        bu.Icon:SetSize(45, 45)
        bu.Icon:ClearAllPoints()
        bu.Icon:SetPoint("LEFT", 10, 0)
        S.Icon(bu.Icon, true)
    end
    S.data(bu).skinned = true
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

    S.SweepCheckChildren(check)
    check:HookScript("OnShow", S.SweepCheckChildren)
    S.data(check).roleDone = true
end

local function Skin()
    local ui = _G.PVPUIFrame
    if not ui then return end
    S.StripTextures(ui)

    local queueFrame = _G.PVPQueueFrame
    if queueFrame then
        if queueFrame.CategoryButtons then
            for _, bu in ipairs(queueFrame.CategoryButtons) do
                SkinCategoryButton(bu)
            end
        else
            for i = 1, 4 do
                SkinCategoryButton(queueFrame["CategoryButton" .. i])
            end
        end
        if _G.PVPQueueFrame_SelectButton and not S.data(queueFrame).selHook then
            hooksecurefunc("PVPQueueFrame_SelectButton", function(index)
                local list = queueFrame.CategoryButtons
                if not list then return end
                for n, b in ipairs(list) do
                    local t = S.data(b).selTex
                    if t then t:SetShown(n == index) end
                end
            end)
            S.data(queueFrame).selHook = true
        end
    end

    local queue = _G.PVPQueueFrame
    if queue then
        local inset = queue.HonorInset
        if inset then
            if inset.Background then inset.Background:Hide() end
            if inset.NineSlice then inset.NineSlice:Hide() end
            S.Backdrop(inset)
        end
    end

    local honor = _G.HonorFrame
    if honor then
        S.StripTextures(honor)
        if honor.Inset then S.StripTextures(honor.Inset) end
        if honor.BottomInset then S.StripTextures(honor.BottomInset) end
        if _G.HonorFrameBottomInset then S.StripTextures(_G.HonorFrameBottomInset) end
        if honor.ShadowOverlay then honor.ShadowOverlay:Hide() end
        if _G.HonorFrameBottom then S.StripTextures(_G.HonorFrameBottom) end
        if honor.QueueButton then S.Button(honor.QueueButton) end
        if honor.TypeDropdown then S.DropDown(honor.TypeDropdown, true) end
        local bonus = honor.BonusFrame
        if bonus then
            S.StripTextures(bonus)

            if bonus.ShadowOverlay then bonus.ShadowOverlay:Hide() end
            if bonus.WorldBattlesTexture then bonus.WorldBattlesTexture:Hide() end
            for _, key in ipairs({ "RandomBGButton", "RandomEpicBGButton", "Arena1Button", "BrawlButton", "BrawlButton2", "SpecialEventButton" }) do
                local b = bonus[key]
                if b and not S.data(b).skinned then
                    S.StripTextures(b)
                    S.Backdrop(b)
                    S.Hover(b)
                    S.SelectedFill(b)
                    S.data(b).skinned = true
                end
            end
        end
        for _, role in ipairs({ "TankIcon", "HealerIcon", "DPSIcon" }) do
            SkinRoleCheck(honor[role])
        end
    end

    local conquest = _G.ConquestFrame
    if conquest then
        S.StripTextures(conquest)
        if conquest.Inset then S.StripTextures(conquest.Inset) end

        if conquest.BottomInset then S.StripTextures(conquest.BottomInset) end
        if _G.ConquestFrameBottomInset then S.StripTextures(_G.ConquestFrameBottomInset) end

        if conquest.ShadowOverlay then conquest.ShadowOverlay:Hide() end
        if conquest.RatedBGTexture then S.KillTexture(conquest.RatedBGTexture) end
        if _G.ConquestFrameBottom then S.StripTextures(_G.ConquestFrameBottom) end
        if conquest.JoinButton then S.Button(conquest.JoinButton) end
        for _, key in ipairs({ "RatedSoloShuffle", "RatedBGBlitz", "Arena2v2", "Arena3v3", "RatedBG" }) do
            local b = conquest[key]
            if b and not S.data(b).skinned then
                S.StripTextures(b)
                S.Backdrop(b)
                S.Hover(b)
                S.SelectedFill(b)
                S.data(b).skinned = true
            end
        end
        for _, role in ipairs({ "TankIcon", "HealerIcon", "DPSIcon" }) do
            SkinRoleCheck(conquest[role])
        end
    end

    local training = _G.TrainingGroundsFrame
    if training and not S.data(training).skinned then
        S.StripTextures(training)

        if training.Inset then S.StripTextures(training.Inset) end
        if training.TypeDropdown then S.DropDown(training.TypeDropdown, true) end
        if training.QueueButton then S.Button(training.QueueButton) end
        local list = training.BonusTrainingGroundList
        if list then
            S.StripTextures(list)
            if list.ShadowOverlay then list.ShadowOverlay:Hide() end
            if list.WorldBattlesTexture then list.WorldBattlesTexture:Hide() end
            for _, key in ipairs({ "RandomTrainingGroundButton" }) do
                local bu = list[key]
                if bu and not S.data(bu).skinned then
                    S.StripTextures(bu)
                    S.Backdrop(bu)
                    S.Hover(bu)
                    S.SelectedFill(bu)
                    if bu.Reward and bu.Reward.Border then bu.Reward.Border:Hide() end
                    S.data(bu).skinned = true
                end
            end
        end
        S.data(training).skinned = true
    end

    local prd = _G.PVPReadyDialog
    if prd and not S.data(prd).skinned then
        S.StripTextures(prd)
        S.Backdrop(prd)
        if prd.enterButton then S.Button(prd.enterButton) end
        if prd.leaveButton then S.Button(prd.leaveButton) end
        local close = _G.PVPReadyDialogCloseButton or prd.CloseButton
        if close then S.CloseButton(close) end
        S.data(prd).skinned = true
    end
end

S:Register("Blizzard_PVPUI", Skin, "PvP")

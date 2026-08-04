local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local next, ipairs, pairs = next, ipairs, pairs
local gsub, strmatch, strfind = string.gsub, string.match, string.find
local hooksecurefunc = hooksecurefunc

local sealFrameTextColor = {
    ["480404"] = "c20606",
    ["042c54"] = "1c86ee",
}

local function SealFrameText(fs, text)
    if text and text ~= "" then
        local colorStr, rawText = strmatch(text, "|c[fF][fF](%x%x%x%x%x%x)(.-)|r")
        if colorStr and rawText then
            colorStr = sealFrameTextColor[colorStr] or "99ccff"
            fs:SetFormattedText("|cff%s%s|r", colorStr, rawText)
        end
    end
end

local function GreetingPanel_OnShow(frame)
    if not frame.titleButtonPool then return end
    for button in frame.titleButtonPool:EnumerateActive() do
        if button.Icon then button.Icon:SetDrawLayer("ARTWORK") end

        local fs = button.GetFontString and button:GetFontString()
        local text = fs and fs:GetText()
        if text and strfind(text, "|cff000000", 1, true) then
            fs:SetText(gsub(text, "|cff000000", "|cffffe519"))
        end
    end
end

local SPELLBOOK_PARTS = [[Interface\Spellbook\Spellbook-Parts]]

local function SkinReward(frame)
    if not frame then return end

    for _, region in next, { frame:GetRegions() } do
        if region:IsObjectType("Texture") and region:GetTexture() == SPELLBOOK_PARTS then
            S.KillTexture(region)
        end
    end

    if frame.Icon then
        frame.Icon:SetDrawLayer("ARTWORK")
        S.SlotIcon(frame.Icon, frame.IconBorder)
    end

    if frame.Count then
        frame.Count:SetDrawLayer("OVERLAY")
        frame.Count:ClearAllPoints()
        frame.Count:SetPoint("BOTTOMRIGHT", frame.Icon, "BOTTOMRIGHT", 0, 0)
    end

    if frame.NameFrame then
        frame.NameFrame:SetAlpha(0)
        frame.NameFrame:Hide()
    end

    if frame.IconOverlay then frame.IconOverlay:SetAlpha(0) end

    if frame.Name then S.SetFont(frame.Name) end

    if frame.CircleBackground then
        frame.CircleBackground:SetAlpha(0)
        if frame.CircleBackgroundGlow then frame.CircleBackgroundGlow:SetAlpha(0) end
    end
end

local function QuestID()
    if _G.QuestInfoFrame and _G.QuestInfoFrame.questLog then
        return C_QuestLog.GetSelectedQuest()
    else
        return GetQuestID()
    end
end

-- Objective lines are laid out in one order and reported in another: Blizzard
-- skips spell and log entries when it builds the list, so the nth fontstring
-- is the nth *displayed* objective, not the nth leaderboard row.
local OBJECTIVE_SKIPPED = { spell = true, log = true }

local OBJECTIVE_WAYPOINT = { 0.4, 1, 1 }
local OBJECTIVE_DONE     = { 0.2, 1, 0.2 }
local OBJECTIVE_PENDING  = { 1, 1, 1 }

local function PaintObjective(objectives, slot, colour)
    local line = objectives[slot]
    if line then line:SetTextColor(colour[1], colour[2], colour[3]) end

    return slot + 1
end

local function ShowObjectives()
    local frame = _G.QuestInfoObjectivesFrame
    local objectives = frame and frame.Objectives
    if not objectives then return end

    local slot = 1
    local questID = QuestID()
    local waypoint = questID and C_QuestLog.GetNextWaypointText
        and C_QuestLog.GetNextWaypointText(questID)

    if waypoint then
        slot = PaintObjective(objectives, slot, OBJECTIVE_WAYPOINT)
    end

    local limit = _G.MAX_OBJECTIVES or 20

    for i = 1, GetNumQuestLeaderBoards() do
        if slot > limit then break end

        local _, kind, done = GetQuestLogLeaderBoard(i)
        if not OBJECTIVE_SKIPPED[kind] then
            slot = PaintObjective(objectives, slot, done and OBJECTIVE_DONE or OBJECTIVE_PENDING)
        end
    end
end

local function QuestInfoItem_OnClick(btn)
    local highlight = _G.QuestInfoItemHighlight
    if not (highlight and btn and btn.Icon) then return end
    highlight:ClearAllPoints()
    highlight:SetPoint("TOPLEFT", btn.Icon, "TOPLEFT", -1, 1)
    highlight:SetPoint("BOTTOMRIGHT", btn.Icon, "BOTTOMRIGHT", 1, -1)

    local rewards = _G.QuestInfoRewardsFrame
    if rewards and rewards.RewardButtons then
        for _, button in ipairs(rewards.RewardButtons) do
            if button.Name then button.Name:SetTextColor(1, 1, 1) end
        end
    end
    if btn.Name then btn.Name:SetTextColor(1, 0.8, 0.1) end
end

local function QuestInfo_Display()
    local infoFrame = _G.QuestInfoFrame
    local rewardsFrame = infoFrame and infoFrame.rewardsFrame
    if not rewardsFrame then return end

    if rewardsFrame.RewardButtons then
        for i, questItem in ipairs(rewardsFrame.RewardButtons) do
            local point, relativeTo, relativePoint, _, y = questItem:GetPoint()
            if point and relativeTo and relativePoint then
                if i == 1 then
                    questItem:SetPoint(point, relativeTo, relativePoint, 0, y)
                elseif relativePoint == "BOTTOMLEFT" then
                    questItem:SetPoint(point, relativeTo, relativePoint, 0, -4)
                else
                    questItem:SetPoint(point, relativeTo, relativePoint, 4, 0)
                end
            end

            SkinReward(questItem)

            if questItem.NameFrame then questItem.NameFrame:Hide() end
            if questItem.Name then questItem.Name:SetTextColor(1, 1, 1) end
        end
    end

    local questID = QuestID()
    local spellRewards = questID and C_QuestInfoSystem and C_QuestInfoSystem.GetQuestRewardSpells
        and C_QuestInfoSystem.GetQuestRewardSpells(questID)
    if spellRewards and #spellRewards > 0 then
        if rewardsFrame.spellHeaderPool then
            for spellHeader in rewardsFrame.spellHeaderPool:EnumerateActive() do
                spellHeader:SetVertexColor(1, 1, 1)
            end
        end
        if rewardsFrame.spellRewardPool then
            for spellIcon in rewardsFrame.spellRewardPool:EnumerateActive() do
                SkinReward(spellIcon)
            end
        end

    end

    if rewardsFrame.reputationRewardPool then
        for repIcon in rewardsFrame.reputationRewardPool:EnumerateActive() do
            SkinReward(repIcon)
        end
    end

    local rewards = _G.QuestInfoRewardsFrame
    local function gold(fs) if fs and fs.SetTextColor then fs:SetTextColor(1, 0.8, 0.1) end end
    local function white(fs) if fs and fs.SetTextColor then fs:SetTextColor(1, 1, 1) end end
    gold(_G.QuestInfoTitleHeader)
    gold(_G.QuestInfoDescriptionHeader)
    gold(_G.QuestInfoObjectivesHeader)
    if rewards then
        gold(rewards.Header)
        white(rewards.ItemChooseText)
        white(rewards.ItemReceiveText)
        white(rewards.SpellLearnText)
        white(rewards.PlayerTitleText)
        if rewards.XPFrame then white(rewards.XPFrame.ReceiveText) end
    end
    white(_G.QuestInfoDescriptionText)
    white(_G.QuestInfoObjectivesText)
    white(_G.QuestInfoGroupSize)
    white(_G.QuestInfoRewardText)
    white(_G.QuestInfoQuestType)

    ShowObjectives()
end

local function ProgressItems_Update()
    if _G.QuestProgressRequiredItemsText then _G.QuestProgressRequiredItemsText:SetTextColor(1, 0.8, 0.1) end
    if _G.QuestProgressRequiredMoneyText then _G.QuestProgressRequiredMoneyText:SetTextColor(1, 1, 1) end
end

local function SetTitleTextColor(fs)
    fs:SetTextColor(1, 0.8, 0.1)
end

local function SetTextColor(fs)
    fs:SetTextColor(1, 1, 1)
end

local function ShowRequiredMoney()
    local moneyText = _G.QuestInfoRequiredMoneyText
    if not moneyText then return end
    local requiredMoney = C_QuestLog.GetRequiredMoney()
    if requiredMoney > 0 then
        if requiredMoney > GetMoney() then
            moneyText:SetTextColor(0.63, 0.09, 0.09)
        else
            moneyText:SetTextColor(1, 0.8, 0.1)
        end
    end
end

local function Skin()
    local frame = _G.QuestFrame
    if not frame then return end

    for _, sf in next, {
        _G.QuestProgressScrollFrame, _G.QuestRewardScrollFrame,
        _G.QuestDetailScrollFrame, _G.QuestGreetingScrollFrame,
        _G.QuestLogPopupDetailFrameScrollFrame,
    } do
        if sf and sf.ScrollBar then S.TrimScrollBar(sf.ScrollBar) end
    end

    local skillPoint = _G.QuestInfoSkillPointFrame
    if skillPoint then
        S.StripTextures(skillPoint)
        skillPoint:SetWidth(skillPoint:GetWidth() - 4)
        skillPoint:SetFrameLevel(skillPoint:GetFrameLevel() + 2)
        S.Backdrop(skillPoint)
        S.Hover(skillPoint)
        local icon = _G.QuestInfoSkillPointFrameIconTexture
        if icon then
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            icon:SetDrawLayer("OVERLAY")
            icon:SetPoint("TOPLEFT", 2, -2)
            icon:SetSize(icon:GetWidth() - 2, icon:GetHeight() - 2)
        end
        if _G.QuestInfoSkillPointFrameCount then
            _G.QuestInfoSkillPointFrameCount:SetDrawLayer("OVERLAY")
        end
    end

    local highlight = _G.QuestInfoItemHighlight
    if highlight then
        S.StripTextures(highlight)
        local bd = S.Backdrop(highlight, 0, true)
        if bd then
            bd:SetBackdropBorderColor(S.palette.brand[1], S.palette.brand[2], S.palette.brand[3], 1)
        end
        highlight:SetSize(142, 40)
    end

    if not S.skinIndex.__questInfoHooks then
        S.skinIndex.__questInfoHooks = true
        if _G.QuestInfo_Display then hooksecurefunc("QuestInfo_Display", QuestInfo_Display) end
        if _G.QuestInfoItem_OnClick then hooksecurefunc("QuestInfoItem_OnClick", QuestInfoItem_OnClick) end
        if _G.QuestFrameProgressItems_Update then hooksecurefunc("QuestFrameProgressItems_Update", ProgressItems_Update) end
        if _G.QuestFrame_SetTitleTextColor then hooksecurefunc("QuestFrame_SetTitleTextColor", SetTitleTextColor) end
        if _G.QuestFrame_SetTextColor then hooksecurefunc("QuestFrame_SetTextColor", SetTextColor) end
        if _G.QuestInfo_ShowRequiredMoney then hooksecurefunc("QuestInfo_ShowRequiredMoney", ShowRequiredMoney) end
        if _G.QuestInfoSealFrame and _G.QuestInfoSealFrame.Text then
            hooksecurefunc(_G.QuestInfoSealFrame.Text, "SetText", SealFrameText)
        end
        if _G.QuestFrameGreetingPanel_OnShow then
            hooksecurefunc("QuestFrameGreetingPanel_OnShow", GreetingPanel_OnShow)
        end
    end

    for _, key in pairs({ "HonorFrame", "XPFrame", "SpellFrame", "SkillPointFrame", "ArtifactXPFrame", "TitleFrame", "WarModeBonusFrame" }) do
        if _G.MapQuestInfoRewardsFrame then SkinReward(_G.MapQuestInfoRewardsFrame[key]) end
        if _G.QuestInfoRewardsFrame then SkinReward(_G.QuestInfoRewardsFrame[key]) end
    end
    if _G.MapQuestInfoRewardsFrame then SkinReward(_G.MapQuestInfoRewardsFrame.MoneyFrame) end

    local titleFrame = _G.QuestInfoPlayerTitleFrame
    if titleFrame then
        if titleFrame.FrameLeft then S.KillTexture(titleFrame.FrameLeft) end
        if titleFrame.FrameCenter then S.KillTexture(titleFrame.FrameCenter) end
        if titleFrame.FrameRight then S.KillTexture(titleFrame.FrameRight) end
        if titleFrame.Icon then S.Icon(titleFrame.Icon) end
    end

    S.Frame(frame)
    for _, p in next, {
        _G.QuestFrameDetailPanel, _G.QuestDetailScrollFrame,
        _G.QuestProgressScrollFrame, _G.QuestGreetingScrollFrame,
        _G.QuestRewardScrollFrame, _G.QuestLogPopupDetailFrameScrollFrame,
    } do
        if p then S.StripTextures(p) end
    end
    for _, p in next, {
        _G.QuestDetailScrollChildFrame, _G.QuestRewardScrollChildFrame,
        _G.QuestFrameProgressPanel, _G.QuestFrameRewardPanel,
        _G.QuestFrameGreetingPanel,
    } do
        if p then S.StripTextures(p, true) end
    end
    for _, name in next, {
        "QuestFrameDetailPanel", "QuestFrameRewardPanel",
        "QuestFrameProgressPanel", "QuestFrameGreetingPanel",
    } do
        local p = _G[name]
        if p then
            if p.Bg and p.Bg.SetAlpha then p.Bg:SetAlpha(0) end
            if p.SealMaterialBG and p.SealMaterialBG.SetAlpha then p.SealMaterialBG:SetAlpha(0) end
            S.StripParchment(p)
        end
    end
    if _G.QuestRewardScrollFrame then
        _G.QuestRewardScrollFrame:SetHeight(_G.QuestRewardScrollFrame:GetHeight() - 2)
    end

    if _G.QuestFrameGreetingPanel then
        _G.QuestFrameGreetingPanel:HookScript("OnShow", GreetingPanel_OnShow)
    end
    if _G.QuestFrameGreetingGoodbyeButton then S.Button(_G.QuestFrameGreetingGoodbyeButton) end
    if _G.QuestGreetingFrameHorizontalBreak then S.KillTexture(_G.QuestGreetingFrameHorizontalBreak) end

    if _G.QuestModelScene then
        local scene = _G.QuestModelScene
        if scene.ModelTextFrame then
            S.StripTextures(scene.ModelTextFrame)
            S.Backdrop(scene.ModelTextFrame)
        end
        scene:SetHeight(247)
        S.StripTextures(scene)
        S.Backdrop(scene)
    end
    if _G.QuestNPCModelText then _G.QuestNPCModelText:SetTextColor(1, 1, 1) end

    for _, b in next, {
        _G.QuestFrameAcceptButton, _G.QuestFrameDeclineButton,
        _G.QuestFrameCompleteButton, _G.QuestFrameGoodbyeButton,
        _G.QuestFrameCompleteQuestButton,
    } do
        if b then S.Button(b) end
    end

    for i = 1, 6 do
        local button = _G["QuestProgressItem" .. i]
        local icon = _G["QuestProgressItem" .. i .. "IconTexture"]
        if button and icon then
            icon:SetPoint("TOPLEFT", 2, -2)
            icon:SetSize(icon:GetWidth() - 3, icon:GetHeight() - 3)
            button:SetWidth(button:GetWidth() - 4)
            S.StripTextures(button)
            button:SetFrameLevel(button:GetFrameLevel() + 1)
            S.Icon(icon, true)
            S.Hover(button, icon)
        end
    end

    if _G.QuestModelScene then
        local scene = _G.QuestModelScene
        if _G.QuestNPCModelNameText then
            _G.QuestNPCModelNameText:ClearAllPoints()
            _G.QuestNPCModelNameText:SetPoint("TOP", scene, 0, -10)
            S.SetFont(_G.QuestNPCModelNameText, 13, "OUTLINE")
        end
        if _G.QuestNPCModelText then _G.QuestNPCModelText:SetJustifyH("CENTER") end
        if _G.QuestNPCModelTextScrollFrame and scene.ModelTextFrame then
            _G.QuestNPCModelTextScrollFrame:ClearAllPoints()
            _G.QuestNPCModelTextScrollFrame:SetPoint("TOPLEFT", scene.ModelTextFrame, 2, -2)
            _G.QuestNPCModelTextScrollFrame:SetPoint("BOTTOMRIGHT", scene.ModelTextFrame, -10, 6)
        end
        if _G.QuestNPCModelTextScrollChildFrame and _G.QuestNPCModelTextScrollFrame then
            _G.QuestNPCModelTextScrollChildFrame:SetPoint("TOPLEFT", _G.QuestNPCModelTextScrollFrame, 1, -1)
            _G.QuestNPCModelTextScrollChildFrame:SetPoint("BOTTOMRIGHT", _G.QuestNPCModelTextScrollFrame, -1, 1)
        end
        if _G.QuestNPCModelTextScrollFrame and _G.QuestNPCModelTextScrollFrame.ScrollBar then
            S.TrimScrollBar(_G.QuestNPCModelTextScrollFrame.ScrollBar)
        end
        if _G.QuestFrame_ShowQuestPortrait and not S.skinIndex.__questPortraitHook then
            S.skinIndex.__questPortraitHook = true
            hooksecurefunc("QuestFrame_ShowQuestPortrait", function(parent, _, _, _, _, _, x, y)
                local mapFrame = _G.QuestMapFrame and _G.QuestMapFrame:GetParent()
                scene:ClearAllPoints()
                scene:SetPoint("TOPLEFT", parent, "TOPRIGHT", (x or 0) + (parent == mapFrame and 11 or 6), y or 0)
                -- Blizzard hard-codes ModelTextFrame height (216,
                -- or 165 compact -- the Prey/AdventureMap dialog passes
                -- compact) regardless of text length, so one-line flavor
                -- text sits in a mostly-empty box. UpdatePortraitText runs
                -- before this post-hook, so the string is measurable: fit
                -- the box to the text when shorter, keep Blizzard's height
                -- as the ceiling so long speeches still scroll, and hide
                -- the scrollbar when nothing scrolls.
                local mtf = scene.ModelTextFrame
                local txt = _G.QuestNPCModelText
                if mtf and txt and txt.GetStringHeight then
                    local fitted = math.ceil(txt:GetStringHeight()) + 24
                    if fitted > 30 and fitted < mtf:GetHeight() then
                        mtf:SetHeight(math.max(fitted, 40))
                    end
                end
                local sf = _G.QuestNPCModelTextScrollFrame
                if sf and sf.ScrollBar and _G.C_Timer then
                    _G.C_Timer.After(0, function()
                        if sf.GetVerticalScrollRange then
                            sf.ScrollBar:SetShown(sf:GetVerticalScrollRange() > 1)
                        end
                    end)
                end
            end)
        end
    end

    local popup = _G.QuestLogPopupDetailFrame
    if popup then
        S.Frame(popup)
        if _G.QuestLogPopupDetailFrameAbandonButton then S.Button(_G.QuestLogPopupDetailFrameAbandonButton) end
        if _G.QuestLogPopupDetailFrameShareButton then S.Button(_G.QuestLogPopupDetailFrameShareButton) end
        if _G.QuestLogPopupDetailFrameTrackButton then S.Button(_G.QuestLogPopupDetailFrameTrackButton) end
        if popup.ShowMapButton then
            S.StripTextures(popup.ShowMapButton)
            S.Button(popup.ShowMapButton)
            if popup.ShowMapButton.Text then
                popup.ShowMapButton.Text:ClearAllPoints()
                popup.ShowMapButton.Text:SetPoint("CENTER")
            end
            popup.ShowMapButton:SetSize(popup.ShowMapButton:GetWidth() - 30, popup.ShowMapButton:GetHeight())
        end
    end
end

S:RegisterEarly(Skin, "Quest")

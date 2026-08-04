local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local next, ipairs = next, ipairs -- luacheck: ignore 211/ipairs
local strfind = string.find
local unpack = unpack -- luacheck: ignore 211/unpack
local hooksecurefunc = hooksecurefunc
local CreateFrame = CreateFrame

local FULL_FILL_WIDTH = 234
local FULL_DROP_WIDTH = FULL_FILL_WIDTH + 30

-- Midnight draws the row furniture as atlas card TEXTURES, not frames, so
-- these are alpha-zeroed rather than stripped; the Item backdrop carries the
-- look on its own.
local ROW_CARD_ART = {
    "NameFrame", "IconQuestTexture", "BorderFrame",
    "HighlightNameFrame", "PushedNameFrame",
}

local function QualityRGB(quality)
    local c = _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality or 1]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function SkinHistoryRow(button)
    if button.IconOverlay then
        local atlas = button.IconOverlay:GetAtlas()
        local isHousingOverlay = atlas and strfind(atlas, "housing-item-wood-frame", 1, true)
        button.IconOverlay:SetAlpha(isHousingOverlay and 0 or 1)
    end

    local d = S.data(button)
    if d.skinned then return end

    if button.BackgroundArtFrame then
        S.StripTextures(button.BackgroundArtFrame)
        S.Backdrop(button.BackgroundArtFrame)
    end
    S.Vanish(button, ROW_CARD_ART)

    local item = button.Item
    local icon = item and item.icon
    if item then
        S.StripTextures(item)
        if icon then
            S.SlotIcon(icon, item.IconBorder)
        end
    end

    d.skinned = true
end

-- HandleScrollElements (C_Timer + our own ForEachFrame per
-- Update) removed -- that pattern seeded the LootHistory secret-taint
-- crash. Rows now style through S.HookScrollBox's sanctioned
-- per-element callback.

local function SkinLootRow(button)
    local item = button.Item
    if item then
        local icon = item.icon
        if icon and not S.data(item).skinned then
            S.Hover(item, icon)
            icon:SetPoint("TOPLEFT", item, "TOPLEFT", 1, -1)
            icon:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", -1, 1)
            S.Icon(icon, true)
            S.data(item).skinned = true
        end

        if item.NormalTexture then item.NormalTexture:SetAlpha(0) end
        if item.IconBorder then item.IconBorder:SetAlpha(0) end

        -- (slim bars had no outline): the Blizzard bar
        -- art is alpha-zeroed (atlas card, correct per ElvUI) but
        -- nothing replaced it -- the name bar was invisible. Backdrop
        -- + 1px border on the NameFrame rect, quality-tinted together
        -- with the icon border below.
        local d = S.data(button)
        if not d.barBD and button.NameFrame then
            local holder = CreateFrame("Frame", nil, button)
            holder:SetAllPoints(button.NameFrame)
            holder:SetFrameLevel(math.max(0, button:GetFrameLevel() - 1))
            d.barBD = S.Backdrop(holder)
        end

        local bd = icon and S.GetBackdrop(icon)
        if button.Text then
            local r, g, b = button.Text:GetVertexColor()
            if r then
                if bd then bd:SetBackdropBorderColor(r, g, b) end
                if d.barBD then d.barBD:SetBackdropBorderColor(r, g, b) end
            end
        end
    end

    -- (user report, "attempt to call a nil value"): on
    -- Midnight NameFrame/BorderFrame/etc. are TEXTURES (atlas item
    -- cards), not frames -- the old StripTextures/Backdrop/
    -- GetFrameLevel block was ElvUI's MasterLooter (frame-based)
    -- recipe applied to the wrong context. ElvUI Mainline Loot.lua
    -- just alpha-zeros the card texture; the Item backdrop carries the
    -- look.
    S.Vanish(button, ROW_CARD_ART)
end



local function DressMasterLooter()
    local looter = _G.MasterLooterFrame
    if not looter then return end
    local item = looter.Item
    if item then
        local icon = item.Icon
        local r, g, b = QualityRGB(_G.LootFrame and _G.LootFrame.selectedQuality)
        local texture = icon and icon:GetTexture()
        S.StripTextures(item)
        local bd = S.Backdrop(item)
        if bd then bd:SetBackdropBorderColor(r, g, b) end
        if icon and texture then
            icon:SetTexture(texture)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
    end

    for _, child in next, { looter:GetChildren() } do
        if not S.data(child).skinned and not child:GetName() and child:IsObjectType("Button") then
            if child:GetPushedTexture() then
                S.CloseButton(child)
            else
                S.Backdrop(child)
                S.Hover(child)
            end
            S.data(child).skinned = true
        end
    end
end

local function StartBonusRoll()
    local frame = _G.BonusRollFrame
    if not frame then return end

    local level = frame:GetFrameLevel()
    if frame.PromptFrame and frame.PromptFrame.Timer then
        frame.PromptFrame.Timer:SetFrameLevel(level + 2)
    end
    local hoistBd = frame.BlackBackgroundHoist and S.data(frame.BlackBackgroundHoist).bd
    if hoistBd then hoistBd:SetFrameLevel(level + 1) end

    if frame.CurrentCountFrame then
        frame.CurrentCountFrame:ClearAllPoints()
        local specBd = frame.SpecIcon and S.data(frame.SpecIcon).bd
        if specBd then
            specBd:SetShown(frame.SpecIcon:IsShown() and frame.SpecIcon:GetTexture() ~= nil)
        end
        if specBd and specBd:IsShown() then
            frame.CurrentCountFrame:SetPoint("RIGHT", specBd, "LEFT", -2, -2)
        else
            frame.CurrentCountFrame:SetPoint("BOTTOMRIGHT", frame, -2, 1)
        end
    end

    local ccf = frame.CurrentCountFrame and frame.CurrentCountFrame.Text
    local pfifc = frame.PromptFrame and frame.PromptFrame.InfoFrame and frame.PromptFrame.InfoFrame.Cost
    if ccf then S.ReplaceIconString(ccf) end
    if pfifc then S.ReplaceIconString(pfifc) end
end

-- The roll count sits against the frame edge on its own, and tucks beside the
-- spec icon whenever one is showing.
local function AnchorRollCount(anchor)
    local frame = _G.BonusRollFrame
    local count = frame and frame.CurrentCountFrame
    if not count then return end

    count:ClearAllPoints()
    if anchor then
        count:SetPoint("RIGHT", anchor, "LEFT", -2, -2)
    else
        count:SetPoint("BOTTOMRIGHT", frame, -2, 1)
    end
end

local function OnSpecIconHidden(specIcon)
    local bd = S.data(specIcon).bd
    if bd and bd:IsShown() then
        AnchorRollCount(nil)
        bd:Hide()
    end
end

local function OnSpecIconShown(specIcon)
    local bd = S.data(specIcon).bd
    if bd and not bd:IsShown() and specIcon:GetTexture() ~= nil then
        AnchorRollCount(bd)
        bd:Show()
    end
end

local function SizeEncounterDropdown(dropdown, width)
    if width ~= FULL_DROP_WIDTH and not S.data(dropdown).sizing then
        S.data(dropdown).sizing = true
        dropdown:SetWidth(FULL_DROP_WIDTH)
        S.data(dropdown).sizing = nil
    end
end

-- THE TIMING, not the contact.
-- The v869 staged bisect applied all eight loot-history contacts live, one at
-- a time (frame/bg/drop/timer/close/bar/box/resize), and ScrollBox,
-- ScrollBox.view, ScrollBar and row1 stayed 100% secure through every single
-- one. The identical calls made from the load pass poison
-- ScrollBox.updateLock -- and updateLock is read on the FIRST LINE of
-- ScrollBoxListMixin:Update:
--     if self.updateLock then return end
-- so once it is dirty, every later Update taints its own execution merely by
-- reading it, then writes view.*/ScrollBar.*/the element mixin/
-- row:Init(dropInfo) under our name and re-stamps updateLock on the way out.
-- Self-sustaining, re-planted at every login, and invisible to taintLog
-- because no global is ever involved. row.dropInfo is what LootHistory:38
-- reads first in SetTooltip, which taints the OnEnter and detonates
-- Midnight's secret roll geometry at Layout.
--
-- Loot registered through S:RegisterEarly -- our earliest pass -- so we were
-- touching this frame's geometry before/while Blizzard's ScrollBox did its
-- own first layout, and that first Update was born ours.
--
-- Same disease and same cure as the currency FORBIDDEN (v862): the contacts
-- were never wrong, the moment was.
--
-- DOCTRINE: a skin must never be the thing that triggers a Blizzard frame's
-- FIRST layout. Do not touch geometry on a ScrollBox-backed frame from the
-- early/load pass -- arm its first OnShow and skin there.
local function ApplyLootFrame()
    local LootFrame = _G.LootFrame
    if not LootFrame or S.data(LootFrame).lootSkinned then return end
    S.data(LootFrame).lootSkinned = true
    S.StripTextures(LootFrame)
    S.Backdrop(LootFrame)
    if LootFrame.ClosePanelButton then S.CloseButton(LootFrame.ClosePanelButton) end
    if LootFrame.ScrollBox then
        S.HookScrollBox(LootFrame.ScrollBox, SkinLootRow)
    end
    if LootFrame.Bg then LootFrame.Bg:SetAlpha(0) end
end

local function ApplyLootHistory()
    local history = _G.GroupLootHistoryFrame
    if not history or S.data(history).histSkinned then return end
    S.data(history).histSkinned = true
        S.StripTextures(history)
        S.Backdrop(history)
        if history.Bg then history.Bg:SetAlpha(0) end

        local dropdown = history.EncounterDropdown
        if dropdown then
            S.DropDown(dropdown, true)
            if not S.data(dropdown).widthArmed then
                hooksecurefunc(dropdown, "SetWidth", SizeEncounterDropdown)
                S.data(dropdown).widthArmed = true
            end
            dropdown:ClearAllPoints()
            dropdown:SetPoint("TOP", -6, -32)
        end

        local timer = history.Timer
        if timer then
            S.StripTextures(timer)
            local tbd = S.Backdrop(timer)
            timer:SetWidth(FULL_FILL_WIDTH)
            if dropdown then
                timer:ClearAllPoints()
                timer:SetPoint("TOP", dropdown, "BOTTOM", 6, 2)
            end
            if timer.Fill then
                timer.Fill:SetTexture("Interface\\Buttons\\WHITE8x8")
                timer.Fill:SetVertexColor(S.palette.brand[1], S.palette.brand[2], S.palette.brand[3], S.palette.brandFillA)
                timer.Fill:ClearAllPoints()
                timer.Fill:SetPoint("LEFT", tbd or timer, 1, 0)
            end
        end

        if history.ClosePanelButton then S.CloseButton(history.ClosePanelButton) end
        if history.ScrollBar then S.TrimScrollBar(history.ScrollBar) end
        if history.ScrollBox then
            S.HookScrollBox(history.ScrollBox, SkinHistoryRow)
        end

        local resize = history.ResizeButton
        if resize and not S.data(resize).skinned then
            S.StripTextures(resize)
            S.Backdrop(resize)
            resize:ClearAllPoints()
            resize:SetPoint("TOP", history, "BOTTOM", 0, -2)
            resize:SetSize(history:GetWidth(), 19)
            local text = resize:CreateFontString(nil, "OVERLAY")
            S.SetFont(text, 14, "OUTLINE")
            text:SetJustifyH("CENTER")
            text:SetPoint("CENTER", resize)
            text:SetText("v v v v")
            S.data(resize).skinned = true
        end
end

-- Skin on the frame's own first OnShow. If it is somehow already shown when
-- we arm (it should not be at login), skin immediately -- that is the same
-- post-hoc moment the v869 bisect proved clean.
local function DeferToFirstShow(frame, fn)
    if not frame then return end
    frame:HookScript("OnShow", fn)
    if frame:IsShown() then fn() end
end

local function Skin()
    -- LootFrame and GroupLootHistoryFrame are no longer skinned
    -- from the early pass. We only arm the OnShow hooks here -- no geometry
    -- is touched at load. See ApplyLootFrame/ApplyLootHistory above.
    DeferToFirstShow(_G.LootFrame, ApplyLootFrame)
    DeferToFirstShow(_G.GroupLootHistoryFrame, ApplyLootHistory)


    local looter = _G.MasterLooterFrame
    if looter then
        S.StripTextures(looter)
        S.Backdrop(looter)
        if _G.MasterLooterFrame_Show and not S.skinIndex.__masterLooterHook then
            S.skinIndex.__masterLooterHook = true
            hooksecurefunc("MasterLooterFrame_Show", DressMasterLooter)
        end
    end

    local bonus = _G.BonusRollFrame
    if bonus and not S.data(bonus).skinned then
        S.StripTextures(bonus)
        S.Backdrop(bonus)
        if bonus.SpecRing then S.KillTexture(bonus.SpecRing) end
        if bonus.CurrentCountFrame and bonus.CurrentCountFrame.Text then
            S.SetFont(bonus.CurrentCountFrame.Text)
        end
        if _G.BonusRollFrame_StartBonusRoll then
            hooksecurefunc("BonusRollFrame_StartBonusRoll", StartBonusRoll)
        end

        local prompt = bonus.PromptFrame
        if prompt then
            if prompt.Icon then S.Icon(prompt.Icon, true) end
            if prompt.Timer then
                prompt.Timer:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
                prompt.Timer:SetStatusBarColor(S.palette.brand[1], S.palette.brand[2], S.palette.brand[3], S.palette.brandFillA)
            end
            local hoist = bonus.BlackBackgroundHoist
            if hoist and prompt.Timer then
                if hoist.Background then hoist.Background:Hide() end
                local hbd = CreateFrame("Frame", nil, bonus)
                S.Backdrop(hbd)
                hbd:SetPoint("TOPLEFT", prompt.Timer, "TOPLEFT", -1, 1)
                hbd:SetPoint("BOTTOMRIGHT", prompt.Timer, "BOTTOMRIGHT", 1, -1)
                S.data(hoist).bd = hbd
            end
        end

        local specIcon = bonus.SpecIcon
        if specIcon then
            local sbd = CreateFrame("Frame", nil, bonus)
            S.Backdrop(sbd)
            sbd:SetPoint("BOTTOMRIGHT", bonus, -2, 2)
            sbd:SetSize(specIcon:GetSize())
            sbd:SetFrameLevel(6)
            specIcon:ClearAllPoints()
            specIcon:SetPoint("TOPLEFT", sbd, "TOPLEFT", 1, -1)
            specIcon:SetPoint("BOTTOMRIGHT", sbd, "BOTTOMRIGHT", -1, 1)
            specIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            S.data(specIcon).bd = sbd
            hooksecurefunc(specIcon, "Hide", OnSpecIconHidden)
            hooksecurefunc(specIcon, "Show", OnSpecIconShown)
        end
        S.data(bonus).skinned = true
    end
end

S:RegisterEarly(Skin, "Loot")

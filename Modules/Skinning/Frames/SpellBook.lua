local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local next = next
local hooksecurefunc = hooksecurefunc

local GetProfessionInfo = GetProfessionInfo
local GetSpellBookItemInfo = C_SpellBook.GetSpellBookItemInfo
local SpellBookSpellBank = Enum.SpellBookSpellBank

local WHITE = "Interface\\Buttons\\WHITE8x8"

-- The five profession slots and the two spell buttons each carries. Named
-- once so nothing downstream has to spell them out again.
local PROFESSION_SLOTS = {
    "PrimaryProfession1", "PrimaryProfession2",
    "SecondaryProfession1", "SecondaryProfession2", "SecondaryProfession3",
}
local SPELL_BUTTONS = { "SpellButton1", "SpellButton2" }
local SPELL_LABELS  = { "spellString", "subSpellString", "SpellName", "SpellSubName" }

local function EachProfessionSlot(fn)
    for i = 1, #PROFESSION_SLOTS do
        local slot = _G[PROFESSION_SLOTS[i]]
        if slot then fn(slot) end
    end
end

local function EachSpellButton(slot, fn)
    for i = 1, #SPELL_BUTTONS do
        local button = slot[SPELL_BUTTONS[i]]
        if button then fn(button) end
    end
end

local function RestoreProfessionIcon(frame, id)
    if not (id and frame and frame.icon) then return end
    local _, texture = GetProfessionInfo(id)
    if texture then
        frame.icon:SetTexture(texture)
    end
end

local function TintProfessionSpell(button)
    local parent = button:GetParent()
    if not parent or not parent.spellOffset then return end

    local spellIndex = button:GetID() + parent.spellOffset
    local spellBookItemInfo = GetSpellBookItemInfo(spellIndex, SpellBookSpellBank.Player)

    if spellBookItemInfo and spellBookItemInfo.isPassive then
        button.highlightTexture:SetColorTexture(1, 1, 1, 0)
    else
        button.highlightTexture:SetColorTexture(1, 1, 1, 0.25)
    end

    for _, key in ipairs(SPELL_LABELS) do
        local label = button[key]
        if label then label:SetTextColor(1, 1, 1) end
    end
end

local function RefreshSlotSpells(frame)
    EachSpellButton(frame, TintProfessionSpell)
end

local function RefreshProfessionSlots()
    EachProfessionSlot(RefreshSlotSpells)

    EachProfessionSlot(function(button)
        local un = button and (button.UnlearnButton or button.unlearn)
        if un and button.icon then
            un:ClearAllPoints()
            un:SetPoint("CENTER", button.icon, "BOTTOMRIGHT", -4, 4)
        end
    end)
end

local function DressSkillButton(button)
    if not button then return end

    button:SetCheckedTexture(WHITE)
    button:GetCheckedTexture():SetColorTexture(1, 1, 1, 0.25)
    button:SetPushedTexture(WHITE)
    button:GetPushedTexture():SetColorTexture(1, 1, 1, 0.5)

    button.IconTexture:ClearAllPoints()
    button.IconTexture:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    button.IconTexture:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)

    S.Icon(button.IconTexture, true)
    local ibd = S.GetBackdrop(button.IconTexture)
    if ibd and button.highlightTexture then
        button.highlightTexture:ClearAllPoints()
        button.highlightTexture:SetPoint("TOPLEFT", ibd, "TOPLEFT", 1, -1)
        button.highlightTexture:SetPoint("BOTTOMRIGHT", ibd, "BOTTOMRIGHT", -1, 1)
    end

    local nameFrame = _G[button:GetName() .. "NameFrame"]
    if nameFrame then nameFrame:Hide() end
end

local function Skin()
    local frame = _G.ProfessionsBookFrame
    if not frame then return end
    S.Frame(frame)
    S.Tabs("SpellBookFrameTabButton", 8)

    local tut = _G.ProfessionsBookFrameTutorialButton
    if tut and tut.Ring then tut.Ring:Hide() end

    for _, button in next, {
        _G.PrimaryProfession1, _G.PrimaryProfession2,
        _G.SecondaryProfession1, _G.SecondaryProfession2, _G.SecondaryProfession3,
    } do
        if button then
            button.missingHeader:SetTextColor(1, 1, 0)
            button.missingText:SetTextColor(1, 1, 1)

            local bar = button.statusBar
            if bar then
                local a, b, c, _, e = bar:GetPoint()
                if a then
                    bar:ClearAllPoints()
                    bar:SetPoint(a, b, c, 0, e)
                end
                if bar.rankText then
                    bar.rankText:ClearAllPoints()
                    bar.rankText:SetPoint("CENTER")
                end
                S.StripTextures(bar)
                S.StatusBar(bar)

                S.ProgressFill(bar)

                if a == "BOTTOMLEFT" and button.rank then
                    button.rank:ClearAllPoints()
                    button.rank:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 4)
                elseif a == "TOPLEFT" and button.rank then
                    button.rank:ClearAllPoints()
                    button.rank:SetPoint("TOPLEFT", button.professionName, "BOTTOMLEFT", 0, -20)
                end

            end

            if button.icon then
                S.Icon(button.icon, true)

                S.StripTextures(button)

                if not S.data(button).iconPlate then
                    local plate = button:CreateTexture(nil, "BACKGROUND")
                    plate:SetColorTexture(0, 0, 0, 1)
                    plate:SetPoint("TOPLEFT", button.icon, "TOPLEFT", 0, 0)
                    plate:SetPoint("BOTTOMRIGHT", button.icon, "BOTTOMRIGHT", 0, 0)
                    S.data(button).iconPlate = plate
                end
                button.professionName:ClearAllPoints()
                button.professionName:SetPoint("TOPLEFT", 100, -4)
                button.icon:SetDesaturated(false)
                button.icon:SetAlpha(1)
            end

            if button.CircleMask then button.CircleMask:Hide() end

            if button.professionName then S.SetFont(button.professionName, 14, "OUTLINE") end
            if button.rank then S.SetFont(button.rank, 12, "OUTLINE") end
            if button.specialization then S.SetFont(button.specialization, 12, "OUTLINE") end
            if button.missingHeader then S.SetFont(button.missingHeader, 14, "OUTLINE") end
            if button.missingText then S.SetFont(button.missingText, 12, "OUTLINE") end
            if bar and bar.rankText then S.SetFont(bar.rankText, 12, "OUTLINE") end

            if not button.icon and button.professionName then
                local p, rel, rp, x, y = button.professionName:GetPoint(1)
                if p then
                    button.professionName:ClearAllPoints()
                    button.professionName:SetPoint(p, rel, rp, x, y)
                end
            end

            EachSpellButton(button, DressSkillButton)
        end
    end

    for i = 1, 2 do
        local button = _G["PrimaryProfession" .. i]
        if button and button.iconTexture then
            S.Icon(button.iconTexture, true)
        end
    end

    hooksecurefunc("FormatProfession", RestoreProfessionIcon)
    hooksecurefunc("ProfessionsBookFrame_Update", RefreshProfessionSlots)
    RefreshProfessionSlots()
end

S:Register("Blizzard_ProfessionsBook", Skin, "SpellBook")

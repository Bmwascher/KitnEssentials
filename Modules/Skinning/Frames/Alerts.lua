local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local next, select, type = next, select, type
local hooksecurefunc = hooksecurefunc
local CreateFrame = CreateFrame

local function QualityRGB(quality)
    local c = _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality or 1]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function ForceAlpha(frame, alpha, forced)
    if alpha ~= 1 and forced ~= true then
        frame:SetAlpha(1, true)
    end
end

local function PinAlpha(frame)
    frame:SetAlpha(1)
    local d = S.data(frame)
    if not d.alphaPinned then
        hooksecurefunc(frame, "SetAlpha", ForceAlpha)
        d.alphaPinned = true
    end
end

local function Ring(owner, icon, tlx, tly, brx, bry)
    local d = S.data(icon)
    if d.ring then return d.ring end
    local ring = CreateFrame("Frame", nil, owner)
    S.Backdrop(ring)
    ring:SetPoint("TOPLEFT", icon, "TOPLEFT", tlx or -1, tly or 1)
    ring:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", brx or 1, bry or -1)
    d.ring = ring
    return ring
end

local function Plate(frame, tlx, tly, brx, bry, anchor)
    local d = S.data(frame)
    if d.plate then return d.plate end
    local bd = S.Backdrop(frame)
    if bd then
        local a = anchor or frame
        bd:ClearAllPoints()
        bd:SetPoint("TOPLEFT", a, "TOPLEFT", tlx, tly)
        bd:SetPoint("BOTTOMRIGHT", a, "BOTTOMRIGHT", brx, bry)
    end
    d.plate = bd
    return bd
end

-- Alert templates share the same decorative furniture under different names,
-- so each skinner just names the pieces its own template carries.
local function KillArt(frame, ...)
    if not frame then return end

    for i = 1, select("#", ...) do
        S.KillTexture(frame[select(i, ...)])
    end
end

local CROP = { 0.08, 0.92, 0.08, 0.92 }
local ICON_ART = { "Bling", "Overlay" }
local function Crop(tex) tex:SetTexCoord(CROP[1], CROP[2], CROP[3], CROP[4]) end

-- Alert templates disagree on whether Icon is the art itself or a holder with
-- a .Texture inside. Resolving that once leaves each skinner with only the
-- part that actually differs -- where the ring sits.
local function AlertIcon(frame)
    local holder = frame.Icon
    if not holder then return end

    KillArt(holder, unpack(ICON_ART))
    if holder.SetMask then holder:SetMask("") end

    local tex = holder.Texture or (holder.SetTexCoord and holder)
    if not tex then return end

    Crop(tex)
    return tex
end

local function DressAchievement(frame)
    PinAlpha(frame)
    Plate(frame, -2, -6, -2, 6, frame.Background)
    if frame.Background then frame.Background:SetTexture() end
    KillArt(frame, "glow", "shine", "GuildBanner", "GuildBorder")
    if frame.Unlocked then
        S.SetFont(frame.Unlocked, 12)
        frame.Unlocked:SetTextColor(1, 1, 1)
    end
    if frame.Name then S.SetFont(frame.Name, 12) end
    local texture = AlertIcon(frame)
    if texture then
        texture:ClearAllPoints()
        texture:SetPoint("LEFT", frame, 7, 0)
        Ring(frame, texture)
    end
end

local function DressCriteria(frame)
    PinAlpha(frame)
    Plate(frame, -2, -6, -2, 6)
    if frame.Unlocked then frame.Unlocked:SetTextColor(1, 1, 1) end
    if frame.Name then frame.Name:SetTextColor(1, 1, 0) end
    KillArt(frame, "Background", "glow", "shine")
    local texture = AlertIcon(frame)
    if texture then Ring(frame, texture, -3, 3, 3, -2) end
end

local function DressDungeonComplete(frame)
    PinAlpha(frame)
    Plate(frame, -2, -6, -2, 6)
    if frame.glowFrame then
        S.StripTextures(frame.glowFrame)
        if frame.glowFrame.glow then S.KillTexture(frame.glowFrame.glow) end
    end
    KillArt(frame, "shine", "raidArt", "heroicIcon")
    for i = 1, 4 do
        local art = frame["dungeonArt" .. i]
        if art then S.KillTexture(art) end
    end
    if frame.dungeonArt then S.KillTexture(frame.dungeonArt) end
    local tex = frame.dungeonTexture
    if tex then
        Crop(tex)
        tex:SetDrawLayer("OVERLAY")
        tex:ClearAllPoints()
        tex:SetPoint("LEFT", frame, 7, 0)
        Ring(frame, tex)
    end
end

local function DressGuildChallenge(frame)
    PinAlpha(frame)
    Plate(frame, -2, -6, -2, 6)
    local region = select(2, frame:GetRegions())
    if region and region:IsObjectType("Texture")
        and region:GetTexture() == [[Interface\GuildFrame\GuildChallenges]] then
        S.KillTexture(region)
    end
    KillArt(frame, "glow", "shine", "EmblemBorder")
    local emblem = frame.EmblemIcon
    if emblem then
        Ring(frame, emblem, -3, 3, 3, -2)
        if _G.SetLargeGuildTabardTextures then
            _G.SetLargeGuildTabardTextures("player", emblem)
        end
    end
end

local function DressHonor(frame)
    PinAlpha(frame)
    KillArt(frame, "Background", "IconBorder")
    if frame.Icon then
        local ring = Ring(frame, frame.Icon)
        Plate(frame, -4, 4, 180, -4, ring)
    end
end

local function DressInvasion(frame)
    if S.data(frame).skinned then return end
    PinAlpha(frame)
    Plate(frame, 4, 4, -7, 6)
    if frame.GetRegions then
        local region, icon = frame:GetRegions()
        if region and region:IsObjectType("Texture")
            and region:GetAtlas() == "legioninvasion-Toast-Frame" then
            S.KillTexture(region)
        end
        if icon and icon:IsObjectType("Texture") and icon:GetTexture() == 236293 then
            Ring(frame, icon)
            icon:SetDrawLayer("OVERLAY")
            Crop(icon)
        end
    end
    S.data(frame).skinned = true
end

local function DressScenario(frame)
    PinAlpha(frame)
    local bd = Plate(frame, 4, 4, -7, 6)
    for _, region in next, { frame:GetRegions() } do
        if region:IsObjectType("Texture") then
            local atlas = region:GetAtlas()
            if atlas == "Toast-IconBG" or atlas == "Toast-Frame" then
                S.KillTexture(region)
            end
        end
    end
    if frame.shine then S.KillTexture(frame.shine) end
    if frame.glowFrame then
        S.StripTextures(frame.glowFrame)
        if frame.glowFrame.glow then S.KillTexture(frame.glowFrame.glow) end
    end
    local tex = frame.dungeonTexture
    if tex then
        tex:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        tex:ClearAllPoints()
        tex:SetPoint("LEFT", bd or frame, 9, 0)
        tex:SetDrawLayer("OVERLAY")
        Ring(frame, tex)
    end
end

local function DressWorldQuest(frame)
    if S.data(frame).skinned then return end
    PinAlpha(frame)
    Plate(frame, 10, -6, -14, 6)
    KillArt(frame, "shine", "ToastBackground")
    local tex = frame.QuestTexture
    if tex then
        Crop(tex)
        tex:SetDrawLayer("ARTWORK")
        Ring(frame, tex)
    end
    S.data(frame).skinned = true
end

local function DressLegendary(frame, itemLink)
    if not S.data(frame).skinned then
        for _, key in next, { "Background", "Background2", "Background3", "Ring1",
            "Particles3", "Particles2", "Particles1", "Starglow", "glow", "shine" } do
            if frame[key] then S.KillTexture(frame[key]) end
        end
        if frame.Icon then
            Crop(frame.Icon)
            frame.Icon:SetDrawLayer("ARTWORK")
            Ring(frame, frame.Icon)
        end
        Plate(frame, 20, -20, -20, 20)
        S.data(frame).skinned = true
    end
    if frame.Icon and itemLink and _G.C_Item and _G.C_Item.GetItemQualityByID then
        local ring = S.data(frame.Icon).ring
        if ring then
            local r, g, b = QualityRGB(_G.C_Item.GetItemQualityByID(itemLink))
            local rbd = S.GetBackdrop(ring)
            if rbd then rbd:SetBackdropBorderColor(r, g, b) end
        end
    end
end

local function DressEntitlement(frame)
    PinAlpha(frame)
    local bd = Plate(frame, 10, -6, -14, 6)
    local bg = frame.Background or frame.StandardBackground
    if bg then S.KillTexture(bg) end
    KillArt(frame, "glow", "shine")
    if frame.Icon then
        frame.Icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        frame.Icon:ClearAllPoints()
        frame.Icon:SetPoint("LEFT", bd or frame, 9, 0)
        Ring(frame, frame.Icon, -2, 2, 2, -2)
    end
end

local HOUSING_REMOVE = {
    "Background", "Border", "Divider", "Glow", "LeafBL", "LeafBR", "LeafL",
    "LeafTL", "LeafTR", "LightRays", "LightRays2", "Sparkles",
}

local function DressHousingItem(frame)
    PinAlpha(frame)
    Plate(frame, 10, -6, -14, 6)
    for _, regionName in next, HOUSING_REMOVE do
        local region = frame[regionName]
        if region then S.KillTexture(region) end
    end
    local icon = frame.Icon
    if icon and not S.data(icon).ring then
        Crop(icon)
        icon:SetSize(50, 50)
        local ring = Ring(frame, icon)
        local hc = _G.HOUSING_REWARD_TOAST_LABEL_FONT_COLOR
        local rbd = S.GetBackdrop(ring)
        if rbd and hc then rbd:SetBackdropBorderColor(hc.r, hc.g, hc.b, hc.a or 1) end
    end
end

local function DressDigsite(frame)
    PinAlpha(frame)
    Plate(frame, -16, -6, 13, 6)
    KillArt(frame, "glow", "shine")
    local r1 = frame:GetRegions()
    if r1 and r1.Hide then r1:Hide() end
    if frame.DigsiteTypeTexture then
        frame.DigsiteTypeTexture:SetPoint("LEFT", -10, -14)
    end
end

local function DressNewRecipe(frame)
    PinAlpha(frame)
    local bd = Plate(frame, 19, -6, -23, 6)
    KillArt(frame, "glow", "shine")
    local r1 = frame:GetRegions()
    if r1 and r1.Hide then r1:Hide() end
    local texture = AlertIcon(frame)
    if texture then
        texture:SetDrawLayer("BORDER", 5)
        texture:ClearAllPoints()
        texture:SetPoint("LEFT", bd or frame, 9, 0)
        Ring(frame, texture, -2, 2, 2, -2)
    end
end

local function DressMiscAlert(frame)
    PinAlpha(frame)
    KillArt(frame, "Background", "IconBorder")
    local icon = frame.Icon
    if icon then
        if icon.SetMask then icon:SetMask("") end
        Crop(icon)
        icon:SetDrawLayer("BORDER", 5)
        local ring = Ring(frame, icon, -2, 2, 2, -2)
        Plate(frame, -8, 8, 180, -8, ring)
    end
end

local function DressLootWon(frame)
    PinAlpha(frame)
    if frame.Background then S.KillTexture(frame.Background) end
    local lootItem = frame.lootItem or frame
    if lootItem.Icon then lootItem.Icon:SetDrawLayer("BORDER") end
    if lootItem.IconBorder then S.KillTexture(lootItem.IconBorder) end
    if lootItem.SpecRing then S.KillTexture(lootItem.SpecRing) end
    KillArt(frame, "glow", "shine", "BGAtlas", "PvPBackground")
    if lootItem.Icon then
        lootItem.Icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        local ring = Ring(frame, lootItem.Icon)
        Plate(frame, -4, 4, 180, -4, ring)
    end
end

local function DressLootUpgrade(frame)
    PinAlpha(frame)
    KillArt(frame, "Background", "Sheen", "BorderGlow")
    if frame.Icon then
        frame.Icon:SetDrawLayer("BORDER", 5)
        if frame.BaseQualityBorder then
            frame.Icon:ClearAllPoints()
            frame.Icon:SetPoint("TOPLEFT", frame.BaseQualityBorder, "TOPLEFT", 5, -5)
            frame.Icon:SetPoint("BOTTOMRIGHT", frame.BaseQualityBorder, "BOTTOMRIGHT", -5, 5)
        end
        frame.Icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        local ring = Ring(frame, frame.Icon)
        Plate(frame, -8, 8, 180, -8, ring)
    end
end

local function DressMoneyWon(frame)
    PinAlpha(frame)
    KillArt(frame, "Background", "IconBorder")
    if frame.Icon then
        frame.Icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        local ring = Ring(frame, frame.Icon)
        Plate(frame, -4, 4, 180, -4, ring)
    end
end

local SYSTEM_SKINS = {

    AchievementAlertSystem = DressAchievement,
    CriteriaAlertSystem = DressCriteria,
    MonthlyActivityAlertSystem = DressCriteria,

    DungeonCompletionAlertSystem = DressDungeonComplete,
    GuildChallengeAlertSystem = DressGuildChallenge,
    InvasionAlertSystem = DressInvasion,
    ScenarioAlertSystem = DressScenario,
    WorldQuestCompleteAlertSystem = DressWorldQuest,

    HonorAwardedAlertSystem = DressHonor,

    LegendaryItemAlertSystem = DressLegendary,
    LootAlertSystem = DressLootWon,
    LootUpgradeAlertSystem = DressLootUpgrade,
    MoneyWonAlertSystem = DressMoneyWon,
    EntitlementDeliveredAlertSystem = DressEntitlement,
    RafRewardDeliveredAlertSystem = DressEntitlement,
    HousingItemEarnedAlertFrameSystem = DressHousingItem,
    InitiativeTaskCompleteAlertFrameSystem = DressHousingItem,

    DigsiteCompleteAlertSystem = DressDigsite,
    NewRecipeLearnedAlertSystem = DressNewRecipe,
    SkillLineSpecsUnlockedAlertSystem = DressNewRecipe,

    NewPetAlertSystem = DressMiscAlert,
    NewMountAlertSystem = DressMiscAlert,
    NewToyAlertSystem = DressMiscAlert,
    NewCosmeticAlertFrameSystem = DressMiscAlert,
    NewWarbandSceneAlertSystem = DressMiscAlert,

}

local function DressBonusRollToasts()
    local money = _G.BonusRollMoneyWonFrame
    if money and not S.data(money).skinned then
        DressMoneyWon(money)
        S.data(money).skinned = true
    end
    local loot = _G.BonusRollLootWonFrame
    if loot and not S.data(loot).skinned then
        DressLootWon(loot)
        S.data(loot).skinned = true
    end
end

local function SkinAlerts()
    for name, fn in next, SYSTEM_SKINS do
        local sys = _G[name]
        if sys and not S.data(sys).hooked and type(sys.setUpFunction) == "function" then
            hooksecurefunc(sys, "setUpFunction", function(frame, ...) fn(frame, ...) end)
            S.data(sys).hooked = true
        end
    end
    DressBonusRollToasts()
end

S:RegisterEarly(SkinAlerts, "Alerts")

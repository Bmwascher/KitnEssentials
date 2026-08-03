local KE = select(2, ...)

if not KitnEssentials then
    error("BlizzardFonts: Addon object not initialized. Check file load order!")
    return
end

local BF = KitnEssentials:NewModule("BlizzardFonts")

-- The reference treats DISABLING as reload-requiring even though OnDisable
-- calls RestoreAll (<REF>/Skinning/BlizzardFonts.lua:275-277): its own GUI
-- flags a reload on the disable branch
-- (<REF>/GUI/Tabs/Skinning/GUI-BlizzMessagesTab.lua:95-97). A PROFILE SWITCH
-- never runs that GUI callback -- Core/ProfileManager.lua:458 gates on
-- name:find("^Skin") or module.keDeferToReload, and "BlizzardFonts" fails the
-- name test -- so without this flag a profile switch silently takes the path
-- the reference deliberately guards. This preserves the reference's
-- reload-required disable contract across non-GUI transitions; it is NOT a
-- claim that teardown is missing, which is UIWidgets' separate problem.
BF.keDeferToReload = true

local _G = _G
local C_Timer = C_Timer
local unpack = unpack -- luacheck: ignore 211/unpack

-- v3.5.772: FONT_LIST audited against Blizzard's UI source
-- (Gethe/wow-ui-source, live branch, Blizzard_Fonts_Shared XML with
-- full inheritance resolution). Result: NO entry strips a stock
-- outline (the two that did -- SystemFont_Shadow_Large_Outline, the
-- native cooldown-count font, and Game15Font_o1 -- were fixed in
-- v3.5.771). Three entries deliberately downgrade stock THICK to
-- NORMAL outline and are annotated inline; QuestFont_Larger no longer
-- appears in the source mirror but is runtime-guarded.
local FONT_LIST = {

    { "Number11Font", 11 },
    { "Number12Font", 12 },
    { "Number12Font_o1", 12, "O" },

    { "Number14FontWhite", 14, "O" },
    { "NumberFont_OutlineThick_Mono_Small", 12, "O" },
    { "NumberFont_Shadow_Small", 12, "S" },
    { "NumberFont_Small", 12 },
    { "NumberFontNormalSmall", 12, "O" }, -- stock THICK; deliberate: thick at 12px muddies (audit v3.5.772)
    { "Number13Font", 13 },
    { "Number13FontGray", 13, "S" },
    { "Number13FontWhite", 13, "S" },
    { "Number13FontYellow", 13, "S" },
    { "Number14FontGray", 14, "S" },
    { "Number14FontWhite", 14, "S" },
    { "NumberFont_Outline_Med", 14, "O" },
    { "NumberFont_Shadow_Med", 14, "S" },
    { "NumberFontNormal", 14, "O" },
    { "Number15Font", 15 },
    { "NumberFont_Outline_Large", 16, "O" },
    { "Number18Font", 18 },
    { "Number18FontWhite", 18, "S" },
    { "NumberFont_Outline_Huge", 30, "T" },

    { "ObjectiveFont", 12, "S" },
    { "ObjectiveTrackerHeaderFont", 14, "O" },
    -- v3.5.792 (dungeon/scenario tracker lines lacked outline):
    -- these lines inherit ObjectiveTrackerLineFont; EUI's QuestTracker
    -- skin re-fonts only the blocks it covers, so the scenario module
    -- falls through to this font object. Promoted to outline
    -- (deliberate departure from Blizzard's shadow-only original).
    { "ObjectiveTrackerLineFont", 12, "O" },

    { "QuestFont", 13 },
    { "QuestTitleFont", 18 },
    { "QuestFontNormalSmall", 12 },
    { "QuestFont_Shadow_Small", 14, "SB" },
    { "QuestFont_Shadow_Huge", 20, "SB" },
    { "QuestFont_Shadow_Super_Huge", 22, "SB" },
    { "QuestFont_Shadow_Enormous", 25, "SB" },
    { "QuestFont_Large", 15 },
    { "QuestFont_Larger", 16 }, -- absent from live source mirror; runtime-guarded (audit v3.5.772)
    { "QuestFont_Huge", 18 },
    { "QuestFont_Super_Huge", 24 },
    { "QuestFont_Enormous", 30 },
    { "QuestFont_39", 39 },

    { "MailTextFontNormal", 15 },
    -- v3.5.771 (cooldown numbers lost their outline):
    -- this object IS the native cooldown-count font (ElvUI's font map
    -- confirms: cooldown = SystemFont_Shadow_Large_Outline). It was
    -- mapped "S", stripping OUTLINE from item cooldowns, private aura
    -- cooldowns, and every other native countdown. Stock-outlined
    -- objects must stay outlined.
    { "SystemFont_Shadow_Large_Outline", 16, "O" },

    { "SystemFont_Tiny", 9 },
    { "AchievementFont_Small", 10 },
    { "FriendsFont_Small", 10, "S" },
    { "Game10Font_o1", 10, "O" },
    { "InvoiceFont_Small", 10 },
    { "ReputationDetailFont", 10, "S" },
    { "SpellFont_Small", 10 },
    { "SubSpellFont", 10 },
    { "SystemFont_Outline_Small", 10, "O" },
    { "SystemFont_Shadow_Small", 10, "S" },
    { "Tooltip_Small", 10 },
    { "SystemFont_Small", 10 },
    { "SystemFont_Small2", 11 },
    { "FriendsFont_11", 11, "S" },
    { "FriendsFont_UserText", 11, "S" },
    { "GameFontHighlightSmall2", 11, "S" },
    { "GameFontNormalSmall2", 11, "S" },
    { "Fancy12Font", 12 },
    { "FriendsFont_Normal", 12, "S" },
    { "Game12Font", 12 },
    { "InvoiceFont_Med", 12 },
    { "SystemFont_Med1", 12 },
    { "SystemFont_Shadow_Med1", 12, "S" },
    { "Tooltip_Med", 12 },
    { "Game13FontShadow", 13, "S" },
    { "GameFontNormalMed1", 13, "S" },
    { "SystemFont_Med2", 13 },
    { "SystemFont_Outline", 13, "O" },
    { "DestinyFontMed", 14 },
    { "Fancy14Font", 14 },
    { "FriendsFont_Large", 14, "S" },
    { "GameFontHighlightMedium", 14, "S" },
    { "GameFontNormalMed2", 14, "S" },
    { "GameFontNormalMed3", 14, "S" },
    { "GameTooltipHeader", 14 },
    { "PriceFont", 14 },
    { "SystemFont_Med3", 14 },
    { "SystemFont_Shadow_Med2", 14, "S" },
    { "SystemFont_Shadow_Med3", 14, "S" },
    { "Game15Font_Shadow", 15, "S" },
    { "Game15Font_o1", 15, "O" }, -- v3.5.771: "_o1" = stock outline; was stripped
    { "MailFont_Large", 15 },
    { "Game16Font", 16 },
    { "GameFontNormalLarge", 16, "S" },

    { "SystemFont_Large", 16 },
    { "SystemFont_Shadow_Large", 16, "S" },
    { "SystemFont16_Shadow_ThickOutline", 16, "O" }, -- stock THICK; deliberate downgrade (audit v3.5.772)
    { "Game17Font_Shadow", 17, "S" },
    { "Game18Font", 18 },
    { "GameFontNormalLarge2", 18, "S" },
    { "SystemFont_Shadow_Large2", 18, "S" },
    { "SystemFont_Huge1", 20 },
    { "Game20Font", 20 },
    { "SystemFont_Huge1_Outline", 20, "O" },
    { "SystemFont_Shadow_Huge1", 20, "O" },
    { "Game22Font", 22 },
    { "Fancy22Font", 22 },
    { "SystemFont_OutlineThick_Huge2", 22, "T" },
    { "Fancy24Font", 24 },
    { "Game24Font", 24 },
    { "GameFontHighlightHuge2", 24, "S" },
    { "GameFontNormalHuge2", 24, "S" },
    { "SystemFont_Huge2", 24 },
    { "SystemFont_Shadow_Huge2", 24, "S" },
    { "BossEmoteNormalHuge", 25, "S" },
    { "SystemFont_Shadow_Huge3", 25, "S" },
    { "SystemFont_Shadow_Huge4", 27, "S" },
    { "Game30Font", 30 },
    { "CoreAbilityFont", 32 },
    { "DestinyFontHuge", 32 },
    { "GameFont_Gigantic", 32, "S" },
    { "SystemFont_OutlineThick_WTF", 32, "O" }, -- stock THICK; deliberate downgrade (audit v3.5.772)

    { "Game40Font", 40 },
    { "Game42Font", 42 },
    { "Game46Font", 46 },
    { "Game48Font", 48 },
    { "Game48FontShadow", 48, "S" },
    { "Game60Font", 60, "O" },
    { "Game72Font", 72, "O" },
    { "Game120Font", 120, "O" },
}

for i = 12, 22 do
    FONT_LIST[#FONT_LIST + 1] = { "ObjectiveTrackerFont" .. i, i, "O" } -- v3.5.792: outlined with LineFont
end

local CATEGORY = {
    ObjectiveFont = "Objective",
    ObjectiveTrackerLineFont = "Objective",
    QuestFont = "QuestText",
    QuestTitleFont = "QuestTitle",
    QuestFontNormalSmall = "QuestSmall",
    MailTextFontNormal = "MailBody",
}
for i = 12, 22 do
    CATEGORY["ObjectiveTrackerFont" .. i] = "Objective"
end

local originals = {}

function BF:UpdateDB()
    self.db = KE.db.profile.Skinning.BlizzardFonts
end

function BF:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function BF:OnEnable()
    if KE:ShouldNotLoadModule() then return end
    if not self.db.Enabled then return end

    C_Timer.After(1.0, function()
        if self:IsEnabled() then
            self:ApplyAll()
        end
    end)
end

function BF:ApplyAll()
    self:UpdateDB()
    if not self.db or not self.db.Enabled then return end

    local face = KE.FONT
    local bsdb = KE.db and KE.db.profile and KE.db.profile.Skinning
        and KE.db.profile.Skinning.BlizzardFrames
    local base = (bsdb and tonumber(bsdb.FontBaseSize)) or 12
    for i = 1, #FONT_LIST do
        local entry = FONT_LIST[i]
        local obj = _G[entry[1]]
        if obj and obj.SetFont and obj.GetFont then

            if not originals[entry[1]] then
                local path, size, flags = obj:GetFont()
                if path then
                    local sr, sg, sb, sa = obj:GetShadowColor()
                    local sx, sy = obj:GetShadowOffset()
                    originals[entry[1]] = { path, size, flags or "", sr, sg, sb, sa, sx, sy }
                end
            end

            local sizes = self.db.Sizes
            local cat = CATEGORY[entry[1]]
            local size = (cat and sizes and tonumber(sizes[cat]))
            if not size then
                size = math.floor(entry[2] * base / 12 + 0.5)
            end

            local kind = entry[2 + 1]
            if kind == "O" then
                obj:SetFont(face, size, KE:GetFontOutline("OUTLINE"))
                obj:SetShadowColor(0, 0, 0, 0)
                obj:SetShadowOffset(0, 0)
            elseif kind == "T" then
                obj:SetFont(face, size, KE:GetFontOutline("THICKOUTLINE"))
                obj:SetShadowColor(0, 0, 0, 0)
                obj:SetShadowOffset(0, 0)
            elseif kind == "S" or kind == "SB" then

                obj:SetFont(face, size, KE:GetFontOutline(""))
                obj:SetShadowColor(0, 0, 0, 0)
                obj:SetShadowOffset(0, 0)
            else

                obj:SetFont(face, size, KE:GetFontOutline(""))
                obj:SetShadowColor(0, 0, 0, 0)
                obj:SetShadowOffset(0, 0)
            end
        end
    end
end

function BF:RestoreAll()
    for name, o in pairs(originals) do
        local obj = _G[name]
        if obj and obj.SetFont then
            obj:SetFont(o[1], o[2], o[3])
            obj:SetShadowColor(o[4] or 0, o[5] or 0, o[6] or 0, o[7] or 0)
            obj:SetShadowOffset(o[8] or 0, o[9] or 0)
        end
    end
end

function BF:ApplySettings()
    if KE:ShouldNotLoadModule() then return end
    self:UpdateDB()
    if self.db and self.db.Enabled then
        self:ApplyAll()
    else
        self:RestoreAll()
    end
end

function BF:OnDisable()
    self:RestoreAll()
end

local KE = select(2, ...)
local S = KE.Skins
local unpack = unpack
local _G = _G

local OUTLINED = {
    "GameFontNormal", "GameFontNormalSmall", "GameFontNormalHuge",
    "GameFontHighlight", "GameFontHighlightSmall", "GameFontHighlightLarge", "GameFontDisable", "GameFontDisableSmall",
    "GameFontGreen", "GameFontRed", "GameFontWhite", "GameFontBlack",
    -- The three tooltip font objects are deliberately absent: the Tooltips
    -- module owns every tooltip font and this pass fighting it over them was a
    -- live bug. Do not add them back.
    "NumberFontNormalLarge",

    "GameFontNormalLeft", "GameFontNormalSmallLeft", "GameFontNormalLeftBottom",
    "GameFontNormalLeftGrey", "GameFontNormalLeftRed", "GameFontNormalTiny",
    "GameFontNormalLargeLeft", "GameFontNormalHuge4", "GameFontNormalOutline",
    "GameFontHighlightLeft", "GameFontHighlightRight", "GameFontHighlightCenter",
    "GameFontHighlightExtraSmall", "GameFontHighlightHuge", "GameFontHighlightLarge2",
    "GameFontHighlightMed2", "GameFontHighlightSmallOutline",
    "GameFontHighlight_NoShadow", "GameFontNormal_NoShadow",
    "GameFontDisableLarge", "GameFontDisableSmallLeft",
    "GameFontGreenLarge", "GameFontGreenSmall", "GameFontRedLarge", "GameFontRedSmall",
    "GameFontWhiteSmall", "GameFontWhiteTiny", "GameFontWhiteTiny2",

    "Game11Font", "Game13Font", "Game13Font_o1", "Game32Font",
    "Number12FontOutline", "Number15FontWhite", "Number16Font",
    "NumberFontNormalRightRed", "NumberFontSmallWhiteLeft", "NumberFont_Normal_Med",
    "NumberFont_Shadow_Large", "System15Font", "SystemFont_Shadow_Small2",
    "TextStatusBarText", "WhiteNormalNumberFont", "NewSubSpellFont",

    "AchievementCriteriaFont", "AchievementDateFont", "AchievementDescriptionFont",
    "AchievementPointsFont", "AchievementPointsFontSmall",
}
local PLAIN = { "InvoiceTextFontNormal" }

local stockSizes = {}

-- the original face/size/flags of every object we touch, so the
-- toggle can put them back live. Without this, switching the skin off did
-- nothing until a reload -- and this is the one skin a user turns off
-- because another addon is BROKEN, so making them reload to test it is
-- the wrong experience.
local stockFonts = {}

local function Restore()
    for name, stock in pairs(stockFonts) do
        local obj = _G[name]
        if obj and obj.SetFont and stock.face then
            pcall(obj.SetFont, obj, stock.face, stock.size, stock.flags)
            if obj.SetShadowColor and stock.shadow then
                pcall(obj.SetShadowColor, obj, unpack(stock.shadow))
            end
        end
    end
end
S.RestoreGlobalFonts = Restore

local function Apply()
    local face = S.FONT_FACE
    if not face or not KE.ApplyFont then return end

    -- Honoured here as well as at RegisterEarly: the font-size slider calls
    -- ApplyGlobalFonts directly, which would otherwise re-apply the override
    -- for a user who has turned it off.
    local frames = KE.db and KE.db.profile and KE.db.profile.Skinning
        and KE.db.profile.Skinning.BlizzardFrames
    local skins = frames and frames.Skins
    if skins and skins.GlobalFonts == false then return end

    local bs = KE.db and KE.db.profile and KE.db.profile.Skinning
        and KE.db.profile.Skinning.BlizzardFrames
    local base = (bs and tonumber(bs.FontBaseSize)) or 12
    for _, list in ipairs({ { OUTLINED, "OUTLINE" }, { PLAIN, "NONE" } }) do
        local names, flags = list[1], list[2]
        for i = 1, #names do
            local name = names[i]
            local obj = _G[name]
            if obj and obj.GetFont then
                local stock = stockSizes[name]
                if not stock then
                    local f, size, fl = obj:GetFont()
                    stock = size
                    stockSizes[name] = size
                    local r, g, b, a
                    if obj.GetShadowColor then r, g, b, a = obj:GetShadowColor() end
                    stockFonts[name] = {
                        face = f, size = size, flags = fl,
                        shadow = r and { r, g, b, a } or nil,
                    }
                end
                if stock then

                    local effStock = stock
                    if flags == "OUTLINE" and effStock < 12 and not name:find("Tiny") then
                        effStock = 12
                    end
                    local size = math.floor(effStock * base / 12 + 0.5)
                    pcall(KE.ApplyFont, KE, obj, face, size, flags)

                    if obj.SetShadowColor then pcall(obj.SetShadowColor, obj, 0, 0, 0, 0) end
                end
            end
        end
    end
end

S.ApplyGlobalFonts = Apply

S:RegisterEarly(Apply, "GlobalFonts")

S:RegisterEarly(function()
    if S.StyleSharedDropDownList then S.StyleSharedDropDownList() end

    if S.StylePulloutFrames and _G.C_Timer then
        S.StylePulloutFrames()
        local n, ticker = 0
        ticker = _G.C_Timer.NewTicker(2, function()
            S.StylePulloutFrames()
            n = n + 1
            if n >= 15 and ticker then ticker:Cancel() end
        end)
    end
end, "SharedDropDownList")

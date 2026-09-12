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

    -- Button state-font partners. A Button swaps between three font objects
    -- on hover and disable, so rescaling one of a trio and not the others
    -- resizes the label the moment the cursor touches it. Each name here is
    -- the odd one out of a trio whose other members are swept here or by
    -- the Blizzard font sweep.
    "GameFontHighlightOutline",
    "GameFontDisableHuge", "GameFontDisableTiny2", "GameFontDisableLeft",
    "GameFontWhiteLarge", "GameFontDisableMed2",
}
local PLAIN = { "InvoiceTextFontNormal" }

-- Raid warning and boss emote text is animated by scaling it between fixed
-- heights, and a size that disagrees with the animation's own height maths
-- renders blurry, so this object keeps 20 whatever the base size is.
local FIXED_SIZES = { GameFontNormalHuge = 20 }

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

-- Platynator's nameplate setup breaks once this sweep has rewritten
-- GameFontNormal. Safe to decide here: Apply runs at module enable, after
-- every non-load-on-demand addon is present.
function S.GlobalFontsBlockedBy()
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Platynator") then
        return "Platynator"
    end
    return nil
end

local PASSES = {
    { names = OUTLINED, flags = "OUTLINE" },
    { names = PLAIN, flags = "NONE" },
}

local function Apply()
    local face = S.ResolveSkinFace()
    if not face or not KE.ApplyFont then return end

    if S.GlobalFontsBlockedBy() then return end

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

    -- Every stock size is read before any object is written. An object that
    -- declares no height of its own follows its XML parent at runtime, so one
    -- swept earlier in the list hands its already-scaled size to its children
    -- -- and reading stock inside the write loop captured that and scaled it a
    -- second time. GameFontDisable and GameFontHighlightOutline are both such
    -- children, and at a base of 13 they rendered 14 against their parents' 13.
    for _, pass in ipairs(PASSES) do
        local names = pass.names
        for i = 1, #names do
            local name = names[i]
            local obj = _G[name]
            if obj and obj.GetFont and not stockSizes[name] then
                local f, size, fl = obj:GetFont()
                stockSizes[name] = size
                local r, g, b, a
                if obj.GetShadowColor then r, g, b, a = obj:GetShadowColor() end
                stockFonts[name] = {
                    face = f, size = size, flags = fl,
                    shadow = r and { r, g, b, a } or nil,
                }
            end
        end
    end

    for _, pass in ipairs(PASSES) do
        local names, flags = pass.names, pass.flags
        for i = 1, #names do
            local name = names[i]
            local obj = _G[name]
            local stock = obj and obj.GetFont and stockSizes[name]
            if stock then
                local size = FIXED_SIZES[name]
                if not size then
                    local effStock = stock
                    if flags == "OUTLINE" and effStock < 12 and not name:find("Tiny") then
                        effStock = 12
                    end
                    size = math.floor(effStock * base / 12 + 0.5)
                end
                pcall(KE.ApplyFont, KE, obj, face, size, flags)

                if obj.SetShadowColor then pcall(obj.SetShadowColor, obj, 0, 0, 0, 0) end
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
        local n = 0
        local ticker
        ticker = _G.C_Timer.NewTicker(2, function()
            S.StylePulloutFrames()
            n = n + 1
            if n >= 15 and ticker then ticker:Cancel() end
        end)
    end
end, "SharedDropDownList")

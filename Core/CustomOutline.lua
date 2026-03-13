-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)

-- Soft Outline: Creates 8 shadow FontStrings around a main FontString for a custom soft outline effect
-- Adapted from atrocityEssentials/NorskenUI

local SoftOutline = {}
SoftOutline.__index = SoftOutline

-- Localization
local ipairs = ipairs
local hooksecurefunc = hooksecurefunc
local setmetatable = setmetatable
local UIFrameFade = UIFrameFade
local UIFrameFadeIn = UIFrameFadeIn
local UIFrameFadeOut = UIFrameFadeOut

-- 8-direction offsets
local SHADOW_OFFSETS = {
    { 0,  1 },  -- N
    { 1,  1 },  -- NE
    { 1,  0 },  -- E
    { 1,  -1 }, -- SE
    { 0,  -1 }, -- S
    { -1, -1 }, -- SW
    { -1, 0 },  -- W
    { -1, 1 },  -- NW
}

-- Alpha falloff (cardinals full, diagonals softer)
local ALPHA_STRENGTH = {
    1.0, 0.7,
    1.0, 0.7,
    1.0, 0.7,
    1.0, 0.7,
}

-- Strip WoW escape codes from text for solid outline
local function StripEscapeCodes(text)
    if not text then return "" end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|T.-|t", "")
    text = text:gsub("|A.-|a", "")
    return text
end

-- Internal: Apply shadow offsets based on thickness
function SoftOutline:_ApplyOffsets()
    if not self.shadows then return end
    for i, shadow in ipairs(self.shadows) do
        local offset = SHADOW_OFFSETS[i]
        local x = offset[1] * self.thickness
        local y = offset[2] * self.thickness
        shadow:ClearAllPoints()
        shadow:SetPoint("CENTER", self.main, "CENTER", x, y)
    end
end

-- Internal: Apply color and alpha to all shadows
function SoftOutline:_ApplyColor()
    if not self.shadows then return end
    for i, shadow in ipairs(self.shadows) do
        local strength = ALPHA_STRENGTH[i] or 1
        shadow:SetTextColor(
            self.color[1],
            self.color[2],
            self.color[3],
            self.alpha * strength
        )
    end
end

-- Public API
function SoftOutline:SetText(text)
    if not self.shadows then return end
    local cleanText = StripEscapeCodes(text)
    for _, shadow in ipairs(self.shadows) do
        shadow:SetText(cleanText)
    end
end

function SoftOutline:SetFont(fontPath, fontSize, flags)
    if not self.shadows then return false end
    if not fontPath or fontPath == "" then
        fontPath = "Fonts\\FRIZQT__.TTF"
    end
    if not fontSize or fontSize <= 0 then
        fontSize = 14
    end
    flags = flags or ""

    local success = true
    for _, shadow in ipairs(self.shadows) do
        local ok = shadow:SetFont(fontPath, fontSize, flags)
        if not ok then
            shadow:SetFont("Fonts\\FRIZQT__.TTF", fontSize, flags)
            success = false
        end
    end
    return success
end

function SoftOutline:SetShadowColor(r, g, b, a)
    self.color = { r, g, b }
    if a then
        self.alpha = a
    end
    self:_ApplyColor()
end

function SoftOutline:SetThickness(value)
    self.thickness = value or 1
    self:_ApplyOffsets()
end

function SoftOutline:SetAlpha(a)
    self.alpha = a or 1
    self:_ApplyColor()
end

function SoftOutline:SetShown(shown)
    if not self.shadows then return end
    self.isShown = shown

    if shown and self.main then
        local _, _, _, textAlpha = self.main:GetTextColor()
        local frameAlpha = self.main:GetAlpha()
        if textAlpha == 0 or frameAlpha == 0 then
            for _, shadow in ipairs(self.shadows) do
                shadow:SetShown(false)
            end
            return
        end
    end

    for _, shadow in ipairs(self.shadows) do
        shadow:SetShown(shown)
    end
end

function SoftOutline:IsShown()
    return self.isShown
end

function SoftOutline:Release()
    if not self.shadows then return end
    for _, shadow in ipairs(self.shadows) do
        if UIFrameFadeRemoveFrame then
            UIFrameFadeRemoveFrame(shadow)
        end
        shadow:Hide()
        shadow:ClearAllPoints()
        shadow:SetParent(nil)
    end

    if self.main then
        self.main._keSoftOutline = nil
    end

    self.main = nil
    self.shadows = nil
    self.isShown = false
end

-- Hook sync - only hooks once per FontString
function SoftOutline:_HookMain()
    local main = self.main

    if main._keSoftOutlineHooked then return end
    main._keSoftOutlineHooked = true
    main._keSoftOutline = self

    local SOFT_OUTLINE_FADEOUT_SPEED = 0.85
    hooksecurefunc("UIFrameFade", function(frame, fadeInfo)
        if not frame or not fadeInfo then return end
        if frame._keSoftOutline then
            local outline = frame._keSoftOutline
            if not outline or not outline.shadows then return end

            local isFadeOut = fadeInfo.mode == "OUT"
                or (fadeInfo.startAlpha and fadeInfo.endAlpha
                    and fadeInfo.endAlpha < fadeInfo.startAlpha)

            for _, shadow in ipairs(outline.shadows) do
                local shadowFade = {}
                shadowFade.mode = fadeInfo.mode
                shadowFade.startAlpha = fadeInfo.startAlpha
                shadowFade.endAlpha = fadeInfo.endAlpha
                shadowFade.diffAlpha = fadeInfo.diffAlpha
                if isFadeOut then
                    shadowFade.timeToFade = fadeInfo.timeToFade * SOFT_OUTLINE_FADEOUT_SPEED
                else
                    shadowFade.timeToFade = fadeInfo.timeToFade
                end

                if fadeInfo.endAlpha == 0 then
                    shadowFade.finishedFunc = function()
                        shadow:Hide()
                    end
                end

                UIFrameFade(shadow, shadowFade)
            end
        end
    end)

    if UIFrameFadeIn then
        hooksecurefunc("UIFrameFadeIn", function(frame, timeToFade, startAlpha, endAlpha)
            if not frame then return end
            if frame._keSoftOutline then
                local outline = frame._keSoftOutline
                if outline and outline.shadows and outline.isShown then
                    local _, _, _, textAlpha = frame:GetTextColor()
                    if textAlpha ~= 0 then
                        for _, shadow in ipairs(outline.shadows) do
                            shadow:SetAlpha(startAlpha or 0)
                            shadow:Show()
                        end
                    end
                end
            end
        end)
    end

    if UIFrameFadeOut then
        hooksecurefunc("UIFrameFadeOut", function(frame, timeToFade, startAlpha, endAlpha)
            if not frame then return end
            if frame._keSoftOutline then
                local outline = frame._keSoftOutline
                if outline and outline.shadows and outline.isShown then
                    local _, _, _, textAlpha = frame:GetTextColor()
                    if textAlpha ~= 0 then
                        for _, shadow in ipairs(outline.shadows) do
                            shadow:SetAlpha(startAlpha or 1)
                            shadow:Show()
                        end
                    end
                end
            end
        end)
    end

    hooksecurefunc(main, "SetText", function(_, text)
        local outline = main._keSoftOutline
        if outline and outline.shadows and outline.isShown then
            outline:SetText(text)
        end
    end)

    hooksecurefunc(main, "SetFormattedText", function(self)
        local outline = main._keSoftOutline
        if outline and outline.shadows and outline.isShown then
            outline:SetText(self:GetText() or "")
        end
    end)

    hooksecurefunc(main, "SetFont", function(_, font, size, flags)
        local outline = main._keSoftOutline
        if outline and outline.shadows and outline.isShown then
            if font and font ~= "" and size and size > 0 then
                outline:SetFont(font, size, flags or "")
            end
        end
    end)

    hooksecurefunc(main, "SetJustifyH", function(_, justify)
        local outline = main._keSoftOutline
        if outline and outline.shadows and outline.isShown then
            for _, shadow in ipairs(outline.shadows) do
                shadow:SetJustifyH(justify)
            end
        end
    end)

    hooksecurefunc(main, "SetJustifyV", function(_, justify)
        local outline = main._keSoftOutline
        if outline and outline.shadows and outline.isShown then
            for _, shadow in ipairs(outline.shadows) do
                shadow:SetJustifyV(justify)
            end
        end
    end)

    hooksecurefunc(main, "SetAlpha", function(_, a)
        local outline = main._keSoftOutline
        if outline and outline.shadows then
            if a == 0 then
                for _, shadow in ipairs(outline.shadows) do
                    shadow:Hide()
                end
            elseif outline.isShown then
                for _, shadow in ipairs(outline.shadows) do
                    shadow:Show()
                end
            end
        end
    end)

    hooksecurefunc(main, "SetTextColor", function(_, r, g, b, a)
        local outline = main._keSoftOutline
        if outline and outline.shadows then
            if a == 0 then
                for _, shadow in ipairs(outline.shadows) do
                    shadow:Hide()
                end
            elseif outline.isShown then
                for _, shadow in ipairs(outline.shadows) do
                    shadow:Show()
                end
            end
        end
    end)

    local parent = main:GetParent()
    if parent and not parent._keSoftOutlineHooked then
        parent._keSoftOutlineHooked = true

        hooksecurefunc(parent, "Hide", function()
            local outline = main._keSoftOutline
            if outline and outline.shadows then
                for _, shadow in ipairs(outline.shadows) do
                    shadow:Hide()
                end
            end
        end)

        hooksecurefunc(parent, "Show", function()
            local outline = main._keSoftOutline
            if outline and outline.shadows and outline.isShown then
                local _, _, _, textAlpha = main:GetTextColor()
                local frameAlpha = main:GetAlpha()
                if textAlpha ~= 0 and frameAlpha ~= 0 then
                    for _, shadow in ipairs(outline.shadows) do
                        shadow:Show()
                    end
                end
            end
        end)
    end
end

-- Factory: Create or update a soft outline for a FontString
function KE:CreateSoftOutline(mainText, options)
    if not mainText then return nil end
    options = options or {}

    -- Reuse existing outline if present
    local existingOutline = mainText._keSoftOutline
    if existingOutline and existingOutline.shadows then
        existingOutline.color = options.color or existingOutline.color or { 0, 0, 0 }
        existingOutline.alpha = options.alpha or existingOutline.alpha or 0.9
        existingOutline.thickness = options.thickness or existingOutline.thickness or 1

        local font, size, flags = mainText:GetFont()
        font = (font and font ~= "") and font or options.fontPath or "Fonts\\FRIZQT__.TTF"
        size = (size and size > 0) and size or options.fontSize or 14

        existingOutline:SetFont(font, size, "")
        existingOutline:SetText(mainText:GetText() or "")
        existingOutline:_ApplyOffsets()
        existingOutline:_ApplyColor()
        existingOutline:SetShown(true)

        return existingOutline
    end

    local outline = setmetatable({}, SoftOutline)

    outline.main = mainText
    outline.shadows = {}
    outline.color = options.color or { 0, 0, 0 }
    outline.alpha = options.alpha or 0.9
    outline.thickness = options.thickness or 1
    outline.isShown = true

    -- Disable Blizzard shadow
    mainText:SetShadowColor(0, 0, 0, 0)
    mainText:SetShadowOffset(0, 0)

    local font, size, flags = mainText:GetFont()
    font = (font and font ~= "") and font or options.fontPath or "Fonts\\FRIZQT__.TTF"
    size = (size and size > 0) and size or options.fontSize or 14

    -- Create shadow FontStrings
    local parent = mainText:GetParent()
    for i = 1, #SHADOW_OFFSETS do
        local shadow = parent:CreateFontString(nil, "ARTWORK", nil, 7)
        shadow:SetFont(font, size, "")
        shadow:SetText(StripEscapeCodes(mainText:GetText() or ""))
        shadow:SetJustifyH(mainText:GetJustifyH())
        shadow:SetJustifyV(mainText:GetJustifyV())
        outline.shadows[i] = shadow
    end

    outline:_ApplyOffsets()
    outline:_ApplyColor()
    outline:_HookMain()

    mainText._keSoftOutline = outline

    -- Hide shadows if text is currently invisible
    local _, _, _, textAlpha = mainText:GetTextColor()
    local frameAlpha = mainText:GetAlpha()
    if textAlpha == 0 or frameAlpha == 0 then
        for _, shadow in ipairs(outline.shadows) do
            shadow:Hide()
        end
    end

    return outline
end

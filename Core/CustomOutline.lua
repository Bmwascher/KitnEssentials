-- ╔══════════════════════════════════════════════════════════╗
-- ║  CustomOutline.lua                                       ║
-- ║  Purpose: SOFTOUTLINE system — creates 8 shadow          ║
-- ║           FontStrings around a main FontString for a     ║
-- ║           custom soft outline effect.                    ║
-- ║  Credit: Adapted from atrocityEssentials/NorskenUI.      ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

-- Custom soft-outline shadow system. Eight FontString siblings layered around
-- a main FontString to fake an outline glow without the hard-edged Blizzard
-- OUTLINE flag.
---@class SoftOutline
---@field main FontString?
---@field shadows FontString[]?
---@field thickness number
---@field color number[]
---@field alpha number
---@field isShown boolean

local SoftOutline = {}
SoftOutline.__index = SoftOutline

local ipairs = ipairs
local hooksecurefunc = hooksecurefunc
local setmetatable = setmetatable
local issecretvalue = issecretvalue
local UIFrameFade = UIFrameFade
local UIFrameFadeIn = UIFrameFadeIn
local UIFrameFadeOut = UIFrameFadeOut

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------

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

local SOFT_OUTLINE_FADEOUT_SPEED = 0.85

---------------------------------------------------------------------------------
-- Global fade hooks (installed ONCE at module load — see NorskenUI/Core/CustomOutline.lua
-- for the reference pattern).
--
-- Critical fix vs. earlier: these were previously installed inside _HookMain,
-- which meant a fresh global hook on UIFrameFade / UIFrameFadeIn /
-- UIFrameFadeOut was registered for EVERY soft-outlined FontString. Over a
-- session — especially with DungeonTimers preview cycling — hundreds of
-- redundant entries piled up on each global's post-call list. Each chat
-- scrollbar fade then ran all of them via secureexecuterange, blowing the C
-- stack via ScrollingMessageFrame:RefreshDisplay / FCF_FadeInScrollbar paths.
--
-- These three hooks dispatch purely off `frame._keSoftOutline` — no closure
-- capture of any specific instance is needed.
---------------------------------------------------------------------------------

local fadeHookRunning = false

hooksecurefunc("UIFrameFade", function(frame, fadeInfo)
    if fadeHookRunning then return end
    if not frame or not fadeInfo then return end
    local outline = frame._keSoftOutline
    if not outline or not outline.shadows then return end

    local isFadeOut = fadeInfo.mode == "OUT"
        or (fadeInfo.startAlpha and fadeInfo.endAlpha
            and fadeInfo.endAlpha < fadeInfo.startAlpha)

    fadeHookRunning = true
    for _, shadow in ipairs(outline.shadows) do
        local shadowFade = {
            mode = fadeInfo.mode,
            startAlpha = fadeInfo.startAlpha,
            endAlpha = fadeInfo.endAlpha,
            diffAlpha = fadeInfo.diffAlpha,
            timeToFade = isFadeOut
                and fadeInfo.timeToFade * SOFT_OUTLINE_FADEOUT_SPEED
                or fadeInfo.timeToFade,
        }
        if fadeInfo.endAlpha == 0 then
            shadowFade.finishedFunc = function() shadow:Hide() end
        end
        UIFrameFade(shadow, shadowFade)
    end
    fadeHookRunning = false
end)

if UIFrameFadeIn then
    hooksecurefunc("UIFrameFadeIn", function(frame, _, startAlpha)
        if fadeHookRunning then return end
        if not frame then return end
        local outline = frame._keSoftOutline
        if not outline or not outline.shadows or not outline.isShown then return end
        local _, _, _, textAlpha = frame:GetTextColor()
        if issecretvalue(textAlpha) or textAlpha == 0 then return end
        for _, shadow in ipairs(outline.shadows) do
            shadow:SetAlpha(startAlpha or 0)
            shadow:Show()
        end
    end)
end

if UIFrameFadeOut then
    hooksecurefunc("UIFrameFadeOut", function(frame, _, startAlpha)
        if fadeHookRunning then return end
        if not frame then return end
        local outline = frame._keSoftOutline
        if not outline or not outline.shadows or not outline.isShown then return end
        local _, _, _, textAlpha = frame:GetTextColor()
        if issecretvalue(textAlpha) or textAlpha == 0 then return end
        for _, shadow in ipairs(outline.shadows) do
            shadow:SetAlpha(startAlpha or 1)
            shadow:Show()
        end
    end)
end

local ALPHA_STRENGTH = {
    1.0, 0.7,
    1.0, 0.7,
    1.0, 0.7,
    1.0, 0.7,
}

---------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------

-- Safe to call even if issecretvalue doesn't exist
local function isSecret(val)
    return issecretvalue and issecretvalue(val)
end

local function StripEscapeCodes(text)
    if not text then return "" end
    if isSecret(text) then return "" end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|T.-|t", "")
    text = text:gsub("|A.-|a", "")
    return text
end

---------------------------------------------------------------------------------
-- Internal Methods
---------------------------------------------------------------------------------

function SoftOutline:_ApplyOffsets()
    if not self.shadows then return end
    for i, shadow in ipairs(self.shadows) do
        local offset = SHADOW_OFFSETS[i]
        local x = offset[1] * self.thickness
        local y = offset[2] * self.thickness
        shadow:ClearAllPoints()
        -- Anchor on BOTH corners so the shadow inherits main's bounding box.
        -- Single-CENTER anchoring (the previous behavior) gave each shadow
        -- only its own string-width box, which broke left/right-justified
        -- text in a wide container — e.g. DungeonTimers bar text1 anchored
        -- LEFT+RIGHT on the bar appeared once at the left (main) plus once
        -- centered (shadows) producing a visible ghost. With TOPLEFT +
        -- BOTTOMRIGHT, shadows match main's box exactly and the synced
        -- JustifyH from CreateSoftOutline (and the SetJustifyH hook on
        -- main) keeps the shadow text aligned with the main text.
        shadow:SetPoint("TOPLEFT",     self.main, "TOPLEFT",     x, y)
        shadow:SetPoint("BOTTOMRIGHT", self.main, "BOTTOMRIGHT", x, y)
    end
end

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

---------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------

function SoftOutline:SetText(text)
    if not self.shadows then return end
    -- StripEscapeCodes returns "" for secret strings (gsub on a secret would taint).
    -- For our use case (e.g. DungeonTimers phase bars displaying AbbreviateNumbers
    -- output) the string has no escape codes — passing it through directly keeps the
    -- shadow in sync with the main text. FontString:SetText is AllowedWhenTainted.
    local shadowText
    if text and isSecret(text) then
        shadowText = text
    else
        shadowText = StripEscapeCodes(text)
    end
    for _, shadow in ipairs(self.shadows) do
        shadow:SetText(shadowText)
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
        if isSecret(textAlpha) or isSecret(frameAlpha)
            or textAlpha == 0 or frameAlpha == 0 then
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

---------------------------------------------------------------------------------
-- Hook Sync
---------------------------------------------------------------------------------

-- Only hooks once per FontString
function SoftOutline:_HookMain()
    local main = self.main
    if not main then return end

    if main._keSoftOutlineHooked then return end
    main._keSoftOutlineHooked = true
    main._keSoftOutline = self

    -- The 3 global UIFrameFade / UIFrameFadeIn / UIFrameFadeOut hooks are
    -- installed ONCE at file scope (above) — not per-FontString here. They
    -- dispatch off frame._keSoftOutline so they don't need closure capture
    -- of any specific main. Per-instance hooks below DO need `main` from
    -- closure (to read main._keSoftOutline at hook-fire time).

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
            -- Clean zero → hide outright. Secret alpha (could be 0 or 1) → propagate
            -- the same value to shadows so they track main's visibility via Blizzard's
            -- alpha multiplication. FontString:SetAlpha is AllowedWhenTainted, so
            -- secret values flow through safely. The previous "isSecret → hide" branch
            -- broke DungeonTimers' phase-bar transitionText, whose alpha is driven by
            -- a secret HP-curve output that's 1 inside the transitioned band.
            if not isSecret(a) and a == 0 then
                for _, shadow in ipairs(outline.shadows) do
                    shadow:Hide()
                end
            elseif outline.isShown then
                for _, shadow in ipairs(outline.shadows) do
                    shadow:Show()
                    shadow:SetAlpha(a)
                end
            end
        end
    end)

    hooksecurefunc(main, "SetTextColor", function(_, r, g, b, a)
        local outline = main._keSoftOutline
        if outline and outline.shadows then
            -- Hide if EITHER the text-color alpha is zero OR the frame alpha is
            -- zero. Previously this only checked text-color alpha — and 3-arg
            -- SetTextColor(r,g,b) passes a=nil, which fell into the elseif and
            -- unconditionally Show()'d the shadows. That re-surfaced DungeonTimers'
            -- transitionText shadows (showing "Phase Transitioned") even though
            -- the main FontString had been SetAlpha(0)'d in CreatePhaseBar —
            -- producing a visible "ghost" string behind the label.
            local frameAlpha = main:GetAlpha()
            local textAlphaZero = (not isSecret(a)) and a == 0
            local frameAlphaZero = (not isSecret(frameAlpha)) and frameAlpha == 0
            if textAlphaZero or frameAlphaZero then
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
                if not isSecret(textAlpha) and not isSecret(frameAlpha)
                    and textAlpha ~= 0 and frameAlpha ~= 0 then
                    for _, shadow in ipairs(outline.shadows) do
                        shadow:Show()
                    end
                end
            end
        end)
    end
end

---------------------------------------------------------------------------------
-- Factory
---------------------------------------------------------------------------------

function KE:CreateSoftOutline(mainText, options)
    if not mainText then return nil end
    options = options or {}

    -- Reuse existing outline if present
    local existingOutline = mainText._keSoftOutline
    if existingOutline and existingOutline.shadows then
        existingOutline.color = options.color or existingOutline.color or { 0, 0, 0 }
        existingOutline.alpha = options.alpha or existingOutline.alpha or 0.9
        existingOutline.thickness = options.thickness or existingOutline.thickness or 1

        local font, size = mainText:GetFont()
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

    local font, size = mainText:GetFont()
    font = (font and font ~= "") and font or options.fontPath or "Fonts\\FRIZQT__.TTF"
    size = (size and size > 0) and size or options.fontSize or 14

    -- Create shadow FontStrings
    local parent = mainText:GetParent()
    local initialText = mainText:GetText() or ""
    local shadowInitial
    if isSecret(initialText) then
        shadowInitial = initialText
    else
        shadowInitial = StripEscapeCodes(initialText)
    end
    for i = 1, #SHADOW_OFFSETS do
        local shadow = parent:CreateFontString(nil, "ARTWORK", nil, 7)
        shadow:SetFont(font, size, "")
        shadow:SetText(shadowInitial)
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
    if isSecret(textAlpha) or isSecret(frameAlpha)
        or textAlpha == 0 or frameAlpha == 0 then
        for _, shadow in ipairs(outline.shadows) do
            shadow:Hide()
        end
    end

    return outline
end

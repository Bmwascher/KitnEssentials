-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/Skinning/RestedXP/RestedXPArrow.lua             ║
-- ║  Purpose: RestedXP's arrow in KE's shape, color and      ║
-- ║           words, by post-hooks only. No file-scope       ║
-- ║           frame.                                         ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local C_Timer, CreateColor, CreateFrame = C_Timer, CreateColor, CreateFrame
local hooksecurefunc = hooksecurefunc
local type, unpack = type, unpack
local math_max, math_sqrt = math.max, math.sqrt

local Safe, Rules, Theme = KE.RestedXPSafe, KE.RestedXPRules, KE.RestedXPTheme
local Has, Dig, Run, Secret = Safe.Has, Safe.Dig, Safe.Run, Safe.Secret

local Arrow = {}
KE.RestedXPArrow = Arrow

local ART = "Interface\\AddOns\\KitnEssentials\\Media\\RestedXP\\Arrows\\"
local IMAGES = {
    kite = { [false] = ART .. "kite.tga", [true] = ART .. "kite_glow.tga" },
    wide = { [false] = ART .. "wide.tga", [true] = ART .. "wide_glow.tga" },
}
-- The glow files draw the arrow at this share of their canvas, so turning the
-- glow on leaves the arrow the same size.
local GLOW_FILL = 0.76
local TEXT_WIDTH = 240
local WORDS_GAP = 0.1
local PERCENT = 100
local TOP_TOWARD_WHITE, BOTTOM_SHARE, LAYER_STRENGTH = 0.22, 0.72, 0.9
local DIAGONAL = math_sqrt(2)

local active, installed, textHooked
local layer, swapped, fitted, rxpImage, textHome
local keeping, composing
local onYards, alphaHooked, yardsAlpha
local wordsFor, wordsRaw, wordsText, wordsPending

---------------------------------------------------------------------------------
-- Tint over RestedXP's own arrow
---------------------------------------------------------------------------------
local function BuildLayer(af)
    local texture = af.texture
    if not Has(texture, "SetRotation") then return nil end
    local f = CreateFrame("Frame", nil, af)
    f:SetAllPoints()
    f:SetFrameLevel(af:GetFrameLevel() + 1)
    f.color = f:CreateTexture(nil, "OVERLAY")
    f.color:SetPoint("CENTER")
    f.color:SetBlendMode("ADD")
    f.mask = f:CreateMaskTexture()
    f.mask:SetAllPoints()
    f.color:AddMaskTexture(f.mask)
    hooksecurefunc(texture, "SetRotation", function(_, radians)
        if f:IsShown() then f.mask:SetRotation(radians) end
    end)
    local function Cover(self, w, h)
        local side = math_max(w, h) * DIAGONAL
        self.color:SetSize(side, side)
    end
    f:SetScript("OnSizeChanged", Cover)
    Cover(f, af:GetSize())
    return f
end

local function ShowLayer(af, c)
    layer = layer or BuildLayer(af)
    if not layer then return end
    layer.color:SetColorTexture(1, 1, 1, 1)
    layer.color:SetGradient("VERTICAL",
        CreateColor(c[1] * BOTTOM_SHARE, c[2] * BOTTOM_SHARE, c[3] * BOTTOM_SHARE, LAYER_STRENGTH),
        CreateColor(c[1] + (1 - c[1]) * TOP_TOWARD_WHITE, c[2] + (1 - c[2]) * TOP_TOWARD_WHITE,
            c[3] + (1 - c[3]) * TOP_TOWARD_WHITE, LAYER_STRENGTH))
    layer.mask:SetTexture(af.texture:GetTexture(), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    layer.mask:SetRotation(af.orientation or 0)
    layer:Show()
end

---------------------------------------------------------------------------------
-- KE's image
---------------------------------------------------------------------------------
local function MoveText(af, down)
    local text = af.text
    if not textHome then
        local point, relativeTo, relativePoint, x, y = text:GetPoint()
        if not point then return end
        textHome = { point, relativeTo, relativePoint, x, y }
    end
    local point, relativeTo, relativePoint, x, y = unpack(textHome)
    text:SetPoint(point, relativeTo, relativePoint, x, y - down)
end

local function Fit(af, scale)
    local w, h = af:GetSize()
    local dx, dy = w * (scale - 1) / 2, h * (scale - 1) / 2
    af.texture:ClearAllPoints()
    af.texture:SetPoint("TOPLEFT", af, "TOPLEFT", -dx, dy)
    af.texture:SetPoint("BOTTOMRIGHT", af, "BOTTOMRIGHT", dx, -dy)
    MoveText(af, math_max(0, dy) + Theme.Option("ArrowGap"))
end

local function ShowImage(af, c)
    local glow = Theme.Option("ArrowGlow")
    af.texture:SetTexture(IMAGES[Theme.Option("ArrowStyle")][glow])
    af.texture:SetVertexColor(c[1], c[2], c[3], 1)
    fitted = Theme.Option("ArrowSize") / PERCENT / (glow and GLOW_FILL or 1)
    Fit(af, fitted)
    swapped = true
end

local function HandBackImage(af)
    local texture = af.texture
    if fitted then
        fitted = nil
        texture:ClearAllPoints()
        texture:SetAllPoints()
        texture:SetVertexColor(1, 1, 1, 1)
    end
    if swapped then
        if rxpImage then texture:SetTexture(rxpImage) end
        swapped = false
    end
end

---------------------------------------------------------------------------------
-- Words
---------------------------------------------------------------------------------
local function Words(source)
    if type(source) ~= "table" or source.completed or source.skip or source.hideTooltip then return nil end
    local raw = source.text ~= " " and source.text or nil
    raw = raw or source.tooltipText or source.rawtext
    if type(raw) == "string" and raw ~= "" then return raw end
end

-- The parent, the element, the elements after it, then the ones before. Runs at the
-- words check's cap, so it builds no list.
local function Source(element)
    if Words(element.parent) then return element.parent end
    if Words(element) then return element end
    local list = Dig(element, "step", "elements")
    if type(list) ~= "table" then return nil end
    local at = 0
    for i = 1, #list do
        if list[i] == element then
            at = i
            break
        end
    end
    for i = at + 1, #list do
        if Words(list[i]) then return list[i] end
    end
    for i = 1, at - 1 do
        if Words(list[i]) then return list[i] end
    end
end

local function PlainOrNil(text)
    if type(text) ~= "string" then return nil end
    local plain = Rules.Plain(text)
    return plain ~= "" and plain or nil
end

-- The objective as RestedXP holds it, and the source when its words still need
-- RestedXP's name replacement.
local function RawWords(element)
    if type(element) ~= "table" then return nil end
    local source = Source(element)
    if not source then return element.title end
    local shown = Dig(source, "frame", "text")
    local text = Has(shown, "GetText") and shown:GetText()
    if Secret(text) or not text or text == "" or text == " " then return Words(source), source end
    return text
end

-- True when the words changed. Cleaning them allocates, so it runs only then.
local function ReadWords(element)
    local raw, source = RawWords(element)
    if wordsFor == element and raw == wordsRaw then return false end
    wordsFor, wordsRaw = element, raw
    local rxp = _G.RXP
    if source and Has(rxp, "ReplaceNpcIds") then raw = Run("ArrowObjective", rxp.ReplaceNpcIds, raw, source) or raw end
    wordsText = PlainOrNil(raw)
    return true
end

local function CachedWords(element)
    if wordsFor ~= element then ReadWords(element) end
    return wordsText
end

function Arrow.Stale()
    wordsFor, wordsRaw, wordsText = nil, nil, nil
end

---------------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------------
local function KeepFont(text, restore)
    if keeping or not active then return end
    local path, size, flags = text:GetFont()
    local want = Theme.Option("ArrowAddonFont") and KE:GetFontPath() or (restore and Dig(_G.RXP, "font")) or path
    local wantSize = Theme.Option("ArrowTextSize")
    if not want or (path == want and size == wantSize) then return end
    keeping = true
    text:SetFont(want, wantSize, flags or "")
    keeping = false
end

local function OnArrowText(text)
    if composing then return end
    local af = _G.RXPG_ARROW
    if onYards then onYards(af) end
    if not active then return end
    local distance = af.distance
    if Secret(distance) then return end
    local wrong, showWords = af.wrongContinent, Theme.Option("ArrowWords")
    local words = showWords and not wrong and CachedWords(af.element) or nil
    local out = Rules.ArrowText(distance, words, Theme.Option("ArrowDistance"), showWords, wrong)
    if out == nil then return end
    composing = true
    text:SetText(out)
    composing = false
end

local function HookText(af)
    if textHooked then return end
    textHooked = true
    hooksecurefunc(af.text, "SetText", OnArrowText)
end

-- RestedXP hides the arrow by alpha alone when it has no distance or facing, and
-- sets that alpha only when it changes, except on the wrong continent.
local function OnArrowAlpha(af, alpha)
    if Secret(alpha) or alpha == yardsAlpha then return end
    yardsAlpha = alpha
    if onYards then onYards(af) end
end

local function HookAlpha(af)
    if alphaHooked then return end
    alphaHooked = true
    hooksecurefunc(af, "SetAlpha", OnArrowAlpha)
end

-- The step box's yards read the same writes, with or without this part on.
function Arrow.WatchYards(fn)
    local af = _G.RXPG_ARROW
    onYards = fn
    if fn and Has(af, "HookScript") and type(af.text) == "table" then
        HookText(af)
        HookAlpha(af)
    end
end

---------------------------------------------------------------------------------
-- Painting
---------------------------------------------------------------------------------
function Arrow.Paint()
    local af = _G.RXPG_ARROW
    if not (active and af) then return end
    local accent = Theme.Tokens().accent
    if Theme.Option("ArrowStyle") == "tint" then
        HandBackImage(af)
        ShowLayer(af, accent)
        MoveText(af, Theme.Option("ArrowGap"))
    else
        if layer then layer:Hide() end
        ShowImage(af, accent)
    end
    af.text:SetWidth(Theme.Option("ArrowWords") and TEXT_WIDTH or 0)
    KeepFont(af.text, true)
    Arrow.Stale()
    -- RestedXP rewrites its text and reapplies the angle on its next frame.
    af.distance = nil
    af.forceUpdate = true
end

local function CheckWords()
    wordsPending = false
    if not (active and Theme.Option("ArrowWords")) then return end
    local af = _G.RXPG_ARROW
    if af and not af.wrongContinent and ReadWords(af.element) then af.distance = nil end
end

-- RestedXP can change an objective's words with no new element and no step change,
-- and it writes the arrow's text only when the yards change, so a real change tells
-- it to write again. Its rebuilds can run at any rate, so the check has its own cap.
local function OnWordsChanged()
    if not active or wordsPending then return end
    wordsPending = true
    C_Timer.After(WORDS_GAP, CheckWords)
end

local function HookWords(owner, name)
    if Has(owner, name) then hooksecurefunc(owner, name, OnWordsChanged) end
end

local function OnUpdateVisuals(af)
    if not active then return end
    swapped = false
    rxpImage = Rules.KeepImage(af.texture:GetTexture(), rxpImage, false)
    Arrow.Paint()
end

local function OnArrowSize(af)
    if active and fitted then Fit(af, fitted) end
end

local function Install(af)
    if installed then return end
    installed = true
    hooksecurefunc(af, "UpdateVisuals", OnUpdateVisuals)
    af:HookScript("OnSizeChanged", OnArrowSize)
    -- RestedXP writes size 9 on every theme reload.
    hooksecurefunc(af.text, "SetFont", function(text) KeepFont(text) end)
    HookText(af)
    local rxp, v2 = _G.RXP, Dig(_G.RXP, "v2")
    HookWords(rxp, "SetStep")
    HookWords(rxp, "UpdateStepText")
    HookWords(v2, "UpdateGuideWindow")
    HookWords(v2, "UpdateActiveStepsFrame")
    HookWords(v2, "UpdatePlayerActiveStepItem")
    HookWords(Dig(rxp, "RXPFrame", "CurrentStepFrame"), "UpdateText")
end

function Arrow.Start()
    local af = _G.RXPG_ARROW
    if active or not af then
        if active then Arrow.Paint() end
        return
    end
    active = true
    Install(af)
    rxpImage = Rules.KeepImage(af.texture:GetTexture(), rxpImage, swapped)
    Arrow.Paint()
end

function Arrow.Stop()
    local af = _G.RXPG_ARROW
    if not (active and af) then return end
    active = false
    HandBackImage(af)
    if layer then layer:Hide() end
    local text = af.text
    if textHome then text:SetPoint(unpack(textHome)) end
    text:SetWidth(0)
    local font, size = Dig(_G.RXP, "font"), Dig(_G.RXP, "settings", "profile", "arrowText")
    if font and size then text:SetFont(font, size, "OUTLINE") end
    af.distance = nil
    af.forceUpdate = true
end

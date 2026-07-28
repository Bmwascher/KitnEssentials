-- ╔══════════════════════════════════════════════════════════╗
-- ║  SkinAPI.lua                                             ║
-- ║  Purpose: Shared skinning helpers for Blizzard frames.   ║
-- ║           Ported from the upstream skinning API; the     ║
-- ║           inline comments are the upstream evidence      ║
-- ║           trail and are kept deliberately.                ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

KE.Skins = KE.Skins or {}
local S = KE.Skins

local ipairs = ipairs
local math_max = math.max
local CreateFrame = CreateFrame
local unpack = unpack
local hooksecurefunc = hooksecurefunc
local GetPhysicalScreenSize = GetPhysicalScreenSize

local function PixelBorder()
    local _, ph = GetPhysicalScreenSize()
    local uiScale = (UIParent and UIParent.GetScale and UIParent:GetScale()) or 1
    if not ph or ph <= 0 or uiScale <= 0 then return 1 end
    return (768 / ph) / uiScale
end

-- v4.0.16: per-frame edge size. PixelBorder() is UIParent-scale math,
-- so inside any SCALED ancestor (world map at 1.1) a border sized with
-- it is scale-times too thick in physical pixels (1.1px -> renders 2px
-- at some positions: map tabs/scrollbar/nav field report). Dividing by
-- the frame's scale factor above UIParent keeps every border exactly
-- 1 physical px at any frame scale. Factor is 1 for normal frames --
-- zero behavior change outside scaled subtrees.
local function EdgeFor(bd)
    local px = PixelBorder()
    if not (bd and bd.GetEffectiveScale and UIParent and UIParent.GetEffectiveScale) then return px end
    local f = bd:GetEffectiveScale()
    local u = UIParent:GetEffectiveScale()
    if not f or not u or f <= 0 or u <= 0 then return px end
    local factor = f / u
    if factor <= 0 then return px end
    return px / factor
end

-- Test seam: EdgeFor is file-local by design (nothing outside this file
-- should size a border), but its scale math is the one piece of the
-- backdrop layer that is worth pinning headlessly.
S._EdgeFor = EdgeFor

local backdropCache = setmetatable({}, { __mode = "k" })

local skinState = setmetatable({}, { __mode = "k" })
function S.data(obj)
    local d = skinState[obj]
    if not d then d = {}; skinState[obj] = d end
    return d
end

function S.GetBackdrop(frame)
    return backdropCache[frame]
end

-- Structural colours are the reference's, unchanged — they are tuned
-- against real Blizzard art. The brand/hover/progress entries follow KE's
-- live theme so a skinned Blizzard window matches KE's own panels.
S.palette = {
    window     = { 0.031, 0.031, 0.031, 0.80 },
    control    = { 0.055, 0.055, 0.055, 0.90 },
    panel      = { 0.06, 0.06, 0.06, 0.80 },
    inlineTint = { 0, 0, 0, 0.25 },
    border     = { 0, 0, 0, 1 },
    brand      = { 1, 1, 1 },
    hover      = { 1, 1, 1, 0.15 },
    progress   = { 1, 1, 1, 0.40 },
    brandFillA = 0.8,
    brandRestA = 0.35,
}

-- Mutates in place, never reassigns. BRAND_HL/HOVER_COLOR/CLOSE_REST/
-- CLOSE_HOVER capture these tables at file scope, which runs before KE.db
-- exists; replacing a table here would leave those four holding a dead one
-- and freeze the accent at its placeholder for the whole session.
function S.RefreshPalette()
    local accent = KE.GetThemeColor and KE:GetThemeColor("accent")
    local hover = KE.GetThemeColor and KE:GetThemeColor("accentHover")
    if accent then
        S.palette.brand[1], S.palette.brand[2], S.palette.brand[3] = accent[1], accent[2], accent[3]
        S.palette.progress[1], S.palette.progress[2], S.palette.progress[3] = accent[1], accent[2], accent[3]
    end
    if hover then
        S.palette.hover[1], S.palette.hover[2], S.palette.hover[3] = hover[1], hover[2], hover[3]
    end
end

S.RefreshPalette()

S.bgColor = S.palette.window
S.borderColor = S.palette.border

-- v3.5.847: ElvUI's E.ClearTexture (their Core.lua:81). Their
-- StripRegion clears art with SetTexture(ClearTexture) + SetAtlas("")
-- -- we were passing nil to both, which does NOT clear an atlas the
-- way "" does: the texture kept rendering (green missing-art box on
-- close buttons, and character inset art surviving our strip).
S.ClearTexture = 0

local BLIZZARD_REGIONS = {
    "Left", "Middle", "Right", "Mid",
    "left", "middle", "right",
    "LeftDisabled", "MiddleDisabled", "RightDisabled",
    "BorderBottom", "BorderBottomLeft", "BorderBottomRight", "BorderLeft", "BorderRight",
    "TopLeft", "TopRight", "BottomLeft", "BottomRight",
    "TopMiddle", "MiddleLeft", "MiddleRight", "BottomMiddle", "MiddleMiddle",
    "TabSpacer", "TabSpacer1", "TabSpacer2", "_RightSeparator", "_LeftSeparator",
    "Cover", "Border", "Background",
    "TopTex", "TopLeftTex", "TopRightTex", "LeftTex", "BottomTex",
    "BottomLeftTex", "BottomRightTex", "RightTex", "MiddleTex", "Center",
    "ArtOverlayFrame", "FilligreeOverlay", "PortraitOverlay",
    "ScrollFrameBorder", "ScrollUpBorder", "ScrollDownBorder",
    -- v3.5.848: NineSlice added (ElvUI Toolkit.lua:25). The region dump
    -- proved the surviving character-frame art IS the NineSlice pieces
    -- (UI-Frame-Metal-* on CharacterFrame, UI-Frame-Inner* on
    -- CharacterFrameInsetRight). We only alpha-faded the container --
    -- and Blizzard's NineSliceUtil re-applies the layout on tab switch,
    -- which undoes that. ElvUI strips the PIECES, which no re-apply can
    -- restore. KillRegions now reaches them.
    "NineSlice",
}

-- v3.5.837: ElvUI's Kill(), ported exactly (their Toolkit.lua:430).
-- This is how ElvUI makes art stay dead through Blizzard re-dressing:
-- frames get unregistered + reparented to a hidden frame; regions get
-- ONE narrow redirect (Show -> the object's own Hide). Note what it is
-- NOT: our old global KillTexture NOOP'd SetTexture/SetAlpha/SetAtlas
-- on every stripped texture, which is what tainted the flyout display
-- loop (v828). ElvUI uses this narrowly -- two sites in their whole
-- Character skin -- and StripTextures (state-only) everywhere else.
-- v3.5.838: S.KillTexture now routes through S.Kill (ElvUI's Kill).
-- The flyout no longer uses it -- that path moved to ElvUI's
-- ClearTexture idiom via S.ClearButtonArt, which is surgery-free.
S.HiddenFrame = S.HiddenFrame or CreateFrame("Frame", nil, _G.UIParent)
S.HiddenFrame:Hide()

function S.Kill(object)
    if not object then return end
    if object.UnregisterAllEvents then
        object:UnregisterAllEvents()
        if object.SetParent then object:SetParent(S.HiddenFrame) end
    elseif object.Hide then
        object.Show = object.Hide
    end
    if object.Hide then object:Hide() end
end

function S.KillRegions(frame, name)
    -- v3.5.844 (Equipment Manager buttons vanished): this used
    -- to :Hide() every name in the list -- and the list has "Right",
    -- so S.StripTextures(CharacterFrameInset) resolved
    -- _G["CharacterFrameInset".."Right"] = CharacterFrameInsetRight
    -- and HID the pane that hosts the Equipment Manager and its
    -- buttons. ElvUI never hides these: their StripType looks up the
    -- same kind of name list and calls StripTextures on it, and their
    -- StripRegion clears a texture (SetTexture(ClearTexture) +
    -- SetAtlas('')) -- it only Kills when explicitly asked.
    -- Ported: textures get cleared, child FRAMES get their own
    -- textures stripped, nothing gets hidden by name-guess.
    if not frame then return end
    name = name or (frame.GetName and frame:GetName())
    for _, area in ipairs(BLIZZARD_REGIONS) do
        local object = frame[area] or (name and _G[name .. area])
        if object and object.GetObjectType then
            if object:GetObjectType() == "Texture" then
                if object.SetTexture then object:SetTexture(S.ClearTexture) end
                if object.SetAtlas then object:SetAtlas("") end
            elseif object.GetRegions then
                for _, r in ipairs({ object:GetRegions() }) do
                    if r.GetObjectType and r:GetObjectType() == "Texture" then
                        if r.SetTexture then r:SetTexture(S.ClearTexture) end
                        if r.SetAtlas then r:SetAtlas("") end
                    end
                end
            end
        end
    end
end

-- Geometry on a frame that carries protected data comes back SECRET, and
-- any arithmetic on it errors:
--
--   attempt to perform arithmetic on local 'B' (a secret number value,
--   while execution tainted by 'atrocityEssentials')
--
-- Hit on a guild roster row (memberId is secret) via FixSubPixelEdge.
-- These wrappers return nil instead, so every call site degrades to
-- "skip the adjustment" rather than throwing. Use them for any frame
-- that came from Blizzard; frames we created ourselves cannot be secret
-- and can be read directly.
function S.SafeRect(frame)
    if not (frame and frame.GetRect) then return nil end

    local L, B, W, H = frame:GetRect()
    if not L then return nil end
    if KE:IsSecretValue(L) or KE:IsSecretValue(B)
        or KE:IsSecretValue(W) or KE:IsSecretValue(H) then
        return nil
    end
    return L, B, W, H
end

function S.SafeSize(frame)
    if not (frame and frame.GetSize) then return nil end

    local w, h = frame:GetSize()
    if not w or KE:IsSecretValue(w) or KE:IsSecretValue(h) then return nil end
    return w, h
end

function S.StripTextures(frame, kill)
    if not frame or not frame.GetRegions then return end
    for _, region in ipairs({ frame:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "Texture" then
            region:SetTexture(S.ClearTexture)
            if region.SetAtlas then region:SetAtlas("") end
            if kill and region.Hide then region:Hide() end
        end
    end
    if frame.NineSlice and frame.NineSlice.SetAlpha then
        frame.NineSlice:SetAlpha(0)

        if frame.NineSlice.EnableMouse then frame.NineSlice:EnableMouse(false) end
    end
    S.KillRegions(frame)
end

function S.Template(frame, kind, inset)
    local bd = S.Backdrop(frame, inset)
    if bd then
        local c = (kind == "Default" and S.palette.control)
            or (kind == "Window" and S.palette.window)
            or S.palette.panel
        bd:SetBackdropColor(c[1], c[2], c[3], c[4])
    end
    return bd
end

function S.PixelSnap(obj)
    if not obj then return end
    if obj.SetSnapToPixelGrid then
        obj:SetSnapToPixelGrid(false)
        obj:SetTexelSnappingBias(0)
    end
    if obj.GetRegions then
        for _, r in ipairs({ obj:GetRegions() }) do
            if r.SetSnapToPixelGrid then
                r:SetSnapToPixelGrid(false)
                r:SetTexelSnappingBias(0)
            end
        end
    end
end

-- The reference fills backdrops with its own statusbar art for a faint
-- sheen. KE uses a flat white so a skinned Blizzard window and a KE panel
-- sitting beside each other read as one surface (Chat.lua:145 uses the same).
local BG_TEX = "Interface\\Buttons\\WHITE8x8"

function S.Backdrop(frame, inset, borderOnly)
    if not frame then return nil end

    local isFrame = frame.IsObjectType and frame:IsObjectType("Frame")
    local parent = isFrame and frame or (frame.GetParent and frame:GetParent())
    if not parent then return nil end

    local bd = backdropCache[frame]
    if not bd then
        bd = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        bd:SetBackdrop({
            bgFile = BG_TEX,
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = EdgeFor(bd),
        })

        S.PixelSnap(bd)
        bd:SetBackdropBorderColor(unpack(S.borderColor))
        backdropCache[frame] = bd
    end

    bd:SetBackdropColor(S.bgColor[1], S.bgColor[2], S.bgColor[3], borderOnly and 0 or S.bgColor[4])
    inset = inset or 0
    bd:ClearAllPoints()
    bd:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
    bd:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
    local ref = isFrame and frame or parent
    local lvl = (ref.GetFrameLevel and ref:GetFrameLevel()) or 1
    bd:SetFrameLevel(math_max(lvl - 1, 0))

    return bd
end

local edgeRefresher = CreateFrame("Frame")
edgeRefresher:RegisterEvent("PLAYER_ENTERING_WORLD")
edgeRefresher:RegisterEvent("UI_SCALE_CHANGED")
edgeRefresher:RegisterEvent("DISPLAY_SIZE_CHANGED")
-- v4.0.17: hover/selection textures inset by the border THICKNESS; with
-- per-frame edges (v4.0.16) that is no longer a literal 1 inside scaled
-- subtrees, so dependent regions register here and re-fit whenever the
-- backdrop's edge refits (map min/max flips).
function S.InsetToEdge(region, bd)
    if not (region and bd) then return end
    local e = EdgeFor(bd)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", bd, "TOPLEFT", e, -e)
    region:SetPoint("BOTTOMRIGHT", bd, "BOTTOMRIGHT", -e, e)
    local d = S.data(bd)
    d.edgeClients = d.edgeClients or setmetatable({}, { __mode = "k" })
    d.edgeClients[region] = true
end

local function RefreshEdge(bd)
    local info = bd.backdropInfo
    if not (info and info.edgeSize) then return end
    local px = EdgeFor(bd)
    local diff = info.edgeSize > px and info.edgeSize - px or px - info.edgeSize
    if diff <= 0.001 then return end
    local r, g, b, a = bd:GetBackdropColor()
    local br, bg, bb, ba = bd:GetBackdropBorderColor()
    bd:SetBackdrop({
        bgFile = BG_TEX,
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
    })
    bd:SetBackdropColor(r, g, b, a)
    bd:SetBackdropBorderColor(br, bg, bb, ba)
    S.PixelSnap(bd)
    local clients = S.data(bd).edgeClients
    if clients then
        local e = EdgeFor(bd)
        for region in pairs(clients) do
            region:ClearAllPoints()
            region:SetPoint("TOPLEFT", bd, "TOPLEFT", e, -e)
            region:SetPoint("BOTTOMRIGHT", bd, "BOTTOMRIGHT", -e, e)
        end
    end
end

edgeRefresher:SetScript("OnEvent", function()
    for _, bd in pairs(backdropCache) do
        RefreshEdge(bd)
    end
end)

-- v3.5.853: the fix for "skins visibly load in". Every wait-for-frame
-- in the skins used a WALL-CLOCK delay (0.1s-1s), so anything not yet
-- created when the skin ran stayed Blizzard-art for that long, in
-- plain sight. Nothing about those waits needed real time -- they were
-- waiting for a frame to EXIST. Poll per FRAME instead: worst case is
-- one frame (~4ms at the FPS) instead of up to a second, with the
-- same total patience.
--
-- Ported ahead of its normal position late in the reference file: Tasks
-- 2-7 need it for their own frame-not-ready waits, and the spec (this
-- task) pins its polling/give-up behavior headlessly.
function S.WaitFor(check, run, maxFrames)
    if check() then run() return end
    if not _G.C_Timer then return end
    local n, max = 0, maxFrames or 600 -- ~10s at 60fps, more at higher
    local function poll()
        n = n + 1
        if check() then
            run()
        elseif n < max then
            _G.C_Timer.After(0, poll)
        end
    end
    _G.C_Timer.After(0, poll)
end

local CONTROL_BG = S.palette.control
S.controlBg = CONTROL_BG

local function clearButtonStates(button)
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture" }) do
        if button[getter] then
            local t = button[getter](button)
            if t then
                t:SetTexture(S.ClearTexture)
                if t.SetAtlas then t:SetAtlas("") end
            end
        end
    end
end

local HOVER_COLOR = S.palette.hover
local HOVER_ALPHA = 0.15

local HOVER_TEX = "Interface\\Buttons\\WHITE8x8"
local function killRegisteredHighlight(btn)
    local reg = btn.GetHighlightTexture and btn:GetHighlightTexture()
    if reg then S.KillTexture(reg) end
end
local function armHover(button, anchor, l, t, r, b)
    local d = S.data(button)
    local hl = d.hover
    if not hl then
        hl = button:CreateTexture(nil, "HIGHLIGHT")
        hl:SetTexture(HOVER_TEX)
        hl:SetVertexColor(HOVER_COLOR[1], HOVER_COLOR[2], HOVER_COLOR[3])
        hl:SetAlpha(HOVER_ALPHA)
        d.hover = hl
    end
    if l == 1 and t == -1 and r == -1 and b == 1 and anchor and anchor.backdropInfo then
        S.InsetToEdge(hl, anchor)
    else
        hl:ClearAllPoints()
        hl:SetPoint("TOPLEFT", anchor, "TOPLEFT", l, t)
        hl:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", r, b)
    end
    if not d.hoverArmed then
        d.hoverArmed = true
        killRegisteredHighlight(button)
        hooksecurefunc(button, "SetHighlightTexture", killRegisteredHighlight)
        if button.SetHighlightAtlas then
            hooksecurefunc(button, "SetHighlightAtlas", killRegisteredHighlight)
        end
    end
end

function S.Hover(button, anchor)
    if not button or not button.SetHighlightTexture then return end
    anchor = anchor or S.GetBackdrop(button) or button
    armHover(button, anchor, 1, -1, -1, 1)
end

local killedTextures = setmetatable({}, { __mode = "k" })

-- v4.0.0: regions exempt from all kill sweeps (KillTexture and every
-- caller: KillAllTextures, S.Button child sweeps). For Blizzard-managed
-- child art a skin must keep alive inside an otherwise-stripped control
-- (e.g. barbershop dropdown color swatches, which Blizzard re-atlases,
-- vertex-colors and Show()s per selection).
local protectedTextures = setmetatable({}, { __mode = "k" })

function S.Protect(region)
    if region then protectedTextures[region] = true end
end

function S.KillTexture(t)
    -- v3.5.828 (flyout equip taint, THE root after seven rounds):
    -- replacing methods (SetTexture/Show/... = NOOP) on Blizzard's
    -- texture objects plants tainted FUNCTION values their secure
    -- code CALLS -- every SetItemButton*/state-texture touch in a
    -- display loop executed our NOOP and tainted everything written
    -- after it (the combat flyout-equip ADDON_ACTION_BLOCKED).
    -- Method surgery on Blizzard objects is BANNED alongside field
    -- writes: kill by state, re-assert from our own passes when
    -- Blizzard re-dresses. killedTextures (external, weak) lets
    -- re-assertion stay cheap.
    if not t then return end
    if protectedTextures[t] then return end
    -- v3.5.838: aligned with ElvUI's Kill (Toolkit.lua:430) -- their
    -- one tool for "stay dead" regions: a single Show->Hide redirect,
    -- not our old four-method NOOP. State-only (v828-v837) was the
    -- other extreme and let Blizzard re-dress everything (BigWigs
    -- tiles, character art). This is their middle ground.
    S.Kill(t)
    killedTextures[t] = true
end

local function zeroArrowStates(button)

    for _, key in ipairs({ "Icon", "Texture", "Overlay", "NormalTexture", "PushedTexture",
                           "HighlightTexture", "DisabledTexture" }) do
        S.KillTexture(button[key])
    end
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture",
                              "GetHighlightTexture", "GetDisabledTexture" }) do
        if button[getter] then
            local t = button[getter](button)
            if t and t ~= S.data(button).arrow then S.KillTexture(t) end
        end
    end
end

local ARROW_STATE_SETTERS = {
    "SetNormalTexture", "SetNormalAtlas", "SetPushedTexture", "SetPushedAtlas",
    "SetHighlightTexture", "SetHighlightAtlas", "SetDisabledTexture", "SetDisabledAtlas",
}

function S.KillAllTextures(frame, keep)
    if not frame then return end

    if not frame.GetRegions then
        if frame.IsObjectType and frame:IsObjectType("Texture") then S.KillTexture(frame) end
        return
    end
    for _, r in ipairs({ frame:GetRegions() }) do
        if r ~= keep and r.IsObjectType and r:IsObjectType("Texture") then
            S.KillTexture(r)
        end
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        for _, r in ipairs({ child:GetRegions() }) do
            if r.IsObjectType and r:IsObjectType("Texture") then
                S.KillTexture(r)
            end
        end
    end
end

local function killAllButOurArrow(button)
    local keep = S.data(button).arrow
    for _, r in ipairs({ button:GetRegions() }) do
        if r ~= keep and r.IsObjectType and r:IsObjectType("Texture") then
            S.KillTexture(r)
        end
    end

    for _, child in ipairs({ button:GetChildren() }) do
        for _, r in ipairs({ child:GetRegions() }) do
            if r.IsObjectType and r:IsObjectType("Texture") then
                S.KillTexture(r)
            end
        end
        if child.EnableMouse then child:EnableMouse(false) end
    end
end

local function reKillArrowStates(button)
    zeroArrowStates(button)
    killAllButOurArrow(button)
end

-- v3.5.838: ElvUI's texture-clearing idiom, ported exactly
-- (E.ClearTexture = 0 in their Core.lua:81; S:ClearNormalTexture and
-- friends in Skins.lua:178). Two ideas we never copied:
--   1. Clear state art by passing fileID 0 to the BUTTON's own setter.
--      Never touch the texture object, never NOOP a method.
--   2. Get permanence by HOOKING the setter and re-clearing through
--      the official API. Self-terminating: re-setting to ClearTexture
--      fails the ~= check, so no recursion.
-- This is what our KillTexture was badly reinventing: pre-v828 with
-- NOOP surgery (tainted the flyout display loop), post-v828 state-only
-- (Blizzard re-dressed it -> the flash regressions). Every skin that
-- calls S.ClearButtonArt inherits the correct behaviour from here.

local function ClearNormal(btn, texture)
    if texture ~= S.ClearTexture then btn:SetNormalTexture(S.ClearTexture) end
end
local function ClearPushed(btn, texture)
    if texture ~= S.ClearTexture then btn:SetPushedTexture(S.ClearTexture) end
end
local function ClearDisabled(btn, texture)
    if texture ~= S.ClearTexture then btn:SetDisabledTexture(S.ClearTexture) end
end
local function ClearHighlight(btn, texture)
    if texture ~= S.ClearTexture then btn:SetHighlightTexture(S.ClearTexture) end
end

function S.ClearButtonArt(btn, keepHighlight)
    if not btn then return end

    if btn.SetNormalTexture then btn:SetNormalTexture(S.ClearTexture) end
    if btn.SetPushedTexture then btn:SetPushedTexture(S.ClearTexture) end
    if btn.SetDisabledTexture then btn:SetDisabledTexture(S.ClearTexture) end
    if not keepHighlight and btn.SetHighlightTexture then
        btn:SetHighlightTexture(S.ClearTexture)
    end

    local d = S.data(btn)
    if d.artHooked then return end
    d.artHooked = true
    if btn.SetNormalTexture then hooksecurefunc(btn, "SetNormalTexture", ClearNormal) end
    if btn.SetPushedTexture then hooksecurefunc(btn, "SetPushedTexture", ClearPushed) end
    if btn.SetDisabledTexture then hooksecurefunc(btn, "SetDisabledTexture", ClearDisabled) end
    if not keepHighlight and btn.SetHighlightTexture then
        hooksecurefunc(btn, "SetHighlightTexture", ClearHighlight)
    end
end

function S.Button(button, keepRegion)

    if keepRegion == "killIcon" then
        keepRegion = nil
    elseif not keepRegion and button and button.Icon and button.Icon.IsObjectType
        and button.Icon:IsObjectType("Texture") then
        keepRegion = button.Icon
    elseif not keepRegion and button and button.icon and button.icon.IsObjectType
        and button.icon:IsObjectType("Texture") then

        keepRegion = button.icon
    end
    if not button or S.data(button).skinned then return end

    local keepAtlas = keepRegion and keepRegion.GetAtlas and keepRegion:GetAtlas()
    local keepTex = keepRegion and keepRegion.GetTexture and keepRegion:GetTexture()
    S.StripTextures(button)
    clearButtonStates(button)

    S.KillAllTextures(button, keepRegion)
    if keepRegion then
        if keepAtlas and keepRegion.SetAtlas then keepRegion:SetAtlas(keepAtlas)
        elseif keepTex and keepRegion.SetTexture then keepRegion:SetTexture(keepTex) end
    end

    if button.SetPushedTextOffset then button:SetPushedTextOffset(0, 0) end
    local aeBD = S.Backdrop(button)
    if aeBD then aeBD:SetBackdropColor(CONTROL_BG[1], CONTROL_BG[2], CONTROL_BG[3], CONTROL_BG[4]) end

    S.Hover(button, aeBD)
    S.data(button).skinned = true
end

local CLOSE_TEX = "Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\KitnCustomCrossv3.png"
local ARROW_TEX = "Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\collapse.tga"
local ARROW_ROT = { down = 0, up = 3.14159, right = 1.5708, left = -1.5708 }
local CLOSE_REST = S.palette.hover
local ARROW_REST = { 0.85, 0.85, 0.85 }
local CLOSE_HOVER = S.palette.brand

local function closeOnEnter(btn)
    local x = S.data(btn).closeX
    if x then x:SetVertexColor(CLOSE_HOVER[1], CLOSE_HOVER[2], CLOSE_HOVER[3]) end
end
local function closeOnLeave(btn)
    local x = S.data(btn).closeX
    if x then x:SetVertexColor(CLOSE_REST[1], CLOSE_REST[2], CLOSE_REST[3]) end
end

function S.CloseButton(button, size)

    if not button or S.data(button).skinned then return end
    S.StripTextures(button)
    if button.SetText then button:SetText("") end
    if not S.data(button).closeX then
        local x = button:CreateTexture(nil, "OVERLAY")
        x:SetPoint("CENTER")
        x:SetTexture(CLOSE_TEX)
        x:SetSize(size or 13, size or 13)
        x:SetVertexColor(CLOSE_REST[1], CLOSE_REST[2], CLOSE_REST[3])
        S.data(button).closeX = x
        button:HookScript("OnEnter", closeOnEnter)
        button:HookScript("OnLeave", closeOnLeave)
    end
    S.data(button).skinned = true
end

local function arrowOnEnter(btn)
    local a = S.data(btn).arrow
    if a then a:SetVertexColor(CLOSE_HOVER[1], CLOSE_HOVER[2], CLOSE_HOVER[3]) end
end
local function arrowOnLeave(btn)
    local a = S.data(btn).arrow
    if a then a:SetVertexColor(ARROW_REST[1], ARROW_REST[2], ARROW_REST[3]) end
end

function S.ArrowTexture(tex, dir, size)
    if not tex then return end
    tex:SetTexture(ARROW_TEX)
    tex:SetTexCoord(0, 1, 0, 1)
    tex:SetRotation(ARROW_ROT[dir or "down"] or 0)
    tex:SetVertexColor(ARROW_REST[1], ARROW_REST[2], ARROW_REST[3])
    if size then
        tex:SetSize(size, size)
        tex:ClearAllPoints()
        tex:SetPoint("CENTER")
    end
end

function S.ArrowButton(button, dir, size)
    if not button or S.data(button).skinned then return end
    S.StripTextures(button)
    zeroArrowStates(button)
    if not S.data(button).armor then
        for _, m in ipairs(ARROW_STATE_SETTERS) do
            if type(button[m]) == "function" then
                hooksecurefunc(button, m, reKillArrowStates)
            end
        end
        button:HookScript("OnEnter", killAllButOurArrow)
        button:HookScript("OnLeave", killAllButOurArrow)
        button:HookScript("OnShow", killAllButOurArrow)
        S.data(button).armor = true
    end

    if not S.data(button).arrow then
        local a = button:CreateTexture(nil, "OVERLAY")
        a:SetPoint("CENTER")
        size = size or 15
        a:SetSize(size, size)
        a:SetTexture(ARROW_TEX)
        a:SetRotation(ARROW_ROT[dir or "down"] or 0)
        a:SetVertexColor(ARROW_REST[1], ARROW_REST[2], ARROW_REST[3])
        S.data(button).arrow = a
        button:HookScript("OnEnter", arrowOnEnter)
        button:HookScript("OnLeave", arrowOnLeave)
    end
    killAllButOurArrow(button)
    S.data(button).skinned = true
end

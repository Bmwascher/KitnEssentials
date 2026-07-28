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

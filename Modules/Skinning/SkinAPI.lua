-- ╔══════════════════════════════════════════════════════════╗
-- ║  SkinAPI.lua                                             ║
-- ║  Purpose: Shared skinning helpers for Blizzard frames.   ║
-- ║           The inline comments are the evidence trail     ║
-- ║           and are kept deliberately.                     ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

KE.Skins = KE.Skins or {}
local S = KE.Skins

local ipairs = ipairs
local math_max = math.max
local math_abs = math.abs
local math_floor = math.floor
local CreateFrame = CreateFrame
local unpack = unpack
local hooksecurefunc = hooksecurefunc
local GetPhysicalScreenSize = GetPhysicalScreenSize
local pcall = pcall
local C_AddOns = C_AddOns

local function PixelBorder()
    local _, ph = GetPhysicalScreenSize()
    local uiScale = (UIParent and UIParent.GetScale and UIParent:GetScale()) or 1
    if not ph or ph <= 0 or uiScale <= 0 then return 1 end
    return (768 / ph) / uiScale
end

-- per-frame edge size. PixelBorder() is UIParent-scale math,
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

-- Test seam. The repaint rule below is the only piece of the backdrop layer
-- that decides anything, and it cannot be reached without entries in the cache.
function S._RegisterBackdropForTest(bd)
    backdropCache[bd] = bd
end

-- Structural colours are left alone — they are tuned
-- against real Blizzard art. The brand/hover/progress entries follow KE's
-- live theme so a skinned Blizzard window matches KE's own panels.
S.palette = {
    window     = { 0.031, 0.031, 0.031, 0.80 },
    control    = { 0.055, 0.055, 0.055, 0.90 },
    panel      = { 0.06, 0.06, 0.06, 0.80 },
    inlineTint = { 0, 0, 0, 0.25 },
    border     = { 0, 0, 0, 1 },
    brand      = { 1, 1, 1 },
    hover      = { 0.851, 0.851, 0.851, 0.15 },
    progress   = { 1, 1, 1, 0.40 },
    brandFillA = 0.8,
    brandRestA = 0.35,
}

-- Mutates in place, never reassigns. BRAND_HL/HOVER_COLOR/CLOSE_HOVER
-- capture these tables at file scope, which runs before KE.db exists;
-- replacing a table here would leave those holding a dead one and freeze
-- the accent at its placeholder for the whole session.
--
-- palette.hover is deliberately NOT themed. It is a neutral
-- grey mouseover wash, not an accent: theme accent and accentHover share
-- the same RGB and differ only in alpha, so driving hover from accentHover
-- collapsed every rest/hover pair (rows, tabs, buttons, the close X) onto
-- one flat brand colour with no visible mouseover state at all.
local function ApplyColor(target, value)
    if not value then return end
    for i = 1, 4 do
        if value[i] ~= nil then target[i] = value[i] end
    end
end

function S.RefreshPalette()
    local accent = KE.GetThemeColor and KE:GetThemeColor("accent")
    if accent then
        S.palette.brand[1], S.palette.brand[2], S.palette.brand[3] = accent[1], accent[2], accent[3]
        S.palette.progress[1], S.palette.progress[2], S.palette.progress[3] = accent[1], accent[2], accent[3]
    end

    -- Saved window colours. Read here rather than at file scope: this runs
    -- again once the db exists, and at file scope it never would.
    local bs = KE.db and KE.db.profile and KE.db.profile.Skinning
        and KE.db.profile.Skinning.BlizzardFrames
    if bs then
        ApplyColor(S.palette.window, bs.BackdropColor)
        ApplyColor(S.palette.border, bs.BorderColor)
    end
end

S.RefreshPalette()

-- Repaint rule: a cached backdrop is repainted only if it is STILL wearing the
-- colour being replaced. backdropCache records which backdrops this engine
-- created, not which colour each one ended up with -- roughly forty-five sites
-- re-colour a backdrop after it is created, S.Template among them, and a
-- blanket sweep would flatten every one of them onto the window colour.
--
-- Only RGB is compared. Alpha is then carried: a zero stays zero, anything else
-- takes the new alpha. That is what keeps a border-only backdrop, which wears
-- the window RGB at alpha 0, following the new colour while staying invisible.
-- The border half needs the same carry for the same reason -- some frames hide
-- a border by zeroing its alpha rather than by not asking for one, and giving
-- those a visible border is exactly the damage this rule exists to prevent.
--
-- What the RGB match cannot tell apart: a backdrop still wearing the default,
-- and one a skin deliberately painted the same colour the default happens to
-- be. Borders used as a state indicator sit in that overlap; they take the new
-- colour here and are repainted by their own refresh, so the mismatch is
-- visible only until that frame next updates.
local function ColorMatches(r, g, b, ref)
    if not (r and g and b) then return false end
    local e = 0.001
    return math_abs(r - ref[1]) < e and math_abs(g - ref[2]) < e and math_abs(b - ref[3]) < e
end

function S.SetSkinColors(bg, border)
    local oldBg = { S.palette.window[1], S.palette.window[2], S.palette.window[3] }
    local oldBorder = { S.palette.border[1], S.palette.border[2], S.palette.border[3] }

    ApplyColor(S.palette.window, bg)
    ApplyColor(S.palette.border, border)

    for _, bd in pairs(backdropCache) do
        if bg and bd.GetBackdropColor and bd.SetBackdropColor then
            local r, g, b, a = bd:GetBackdropColor()
            if ColorMatches(r, g, b, oldBg) then
                local alpha = (a == 0) and 0 or S.bgColor[4]
                bd:SetBackdropColor(S.bgColor[1], S.bgColor[2], S.bgColor[3], alpha)
            end
        end
        if border and bd.GetBackdropBorderColor and bd.SetBackdropBorderColor then
            local r, g, b, a = bd:GetBackdropBorderColor()
            if ColorMatches(r, g, b, oldBorder) then
                local alpha = (a == 0) and 0 or S.borderColor[4]
                bd:SetBackdropBorderColor(S.borderColor[1], S.borderColor[2],
                    S.borderColor[3], alpha)
            end
        end
    end
end

S.bgColor = S.palette.window
S.borderColor = S.palette.border

-- The shipped look, captured before anything can change it. Reset needs a value
-- to return to, and reading the palette later returns whatever the user chose.
S.DEFAULT_BG = { S.palette.window[1], S.palette.window[2], S.palette.window[3], S.palette.window[4] }
S.DEFAULT_BORDER = { S.palette.border[1], S.palette.border[2], S.palette.border[3], S.palette.border[4] }

-- ElvUI's E.ClearTexture (their Core.lua). Their
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
    -- NineSlice added (ElvUI Toolkit.lua). The region dump
    -- proved the surviving character-frame art IS the NineSlice pieces
    -- (UI-Frame-Metal-* on CharacterFrame, UI-Frame-Inner* on
    -- CharacterFrameInsetRight). We only alpha-faded the container --
    -- and Blizzard's NineSliceUtil re-applies the layout on tab switch,
    -- which undoes that. ElvUI strips the PIECES, which no re-apply can
    -- restore. KillRegions now reaches them.
    "NineSlice",
}

-- ElvUI's Kill(), ported exactly (their Toolkit.lua).
-- This is how ElvUI makes art stay dead through Blizzard re-dressing:
-- frames get unregistered + reparented to a hidden frame; regions get
-- ONE narrow redirect (Show -> the object's own Hide). Note what it is
-- NOT: our old global KillTexture NOOP'd SetTexture/SetAlpha/SetAtlas
-- on every stripped texture, which is what tainted the flyout display
-- loop (v828). ElvUI uses this narrowly -- two sites in their whole
-- Character skin -- and StripTextures (state-only) everywhere else.
-- S.KillTexture now routes through S.Kill (ElvUI's Kill).
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
    -- (Equipment Manager buttons vanished): this used
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
--   while execution tainted by an addon)
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

function S.SafeCenter(frame)
    if not (frame and frame.GetCenter) then return nil end

    local x, y = frame:GetCenter()
    if not x or KE:IsSecretValue(x) or KE:IsSecretValue(y) then return nil end
    return x, y
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

-- crops a baked decorative border off an atlas texture in
-- TEXCOORD space (for art and border sharing one atlas -- e.g. the LFG
-- ApplicationViewer InfoBackground, the ChallengeMode keystone frame
-- background). Resolves the atlas's raw file rect via
-- C_Texture.GetAtlasInfo and insets by the given fractions. Reentry-
-- guarded so it can be called from a SetAtlas post-hook.
function S.CropAtlasEdges(tex, xPct, yPct)
    if not tex then return end
    local d = S.data(tex)
    if d.cropping then return end
    local atlas = tex.GetAtlas and tex:GetAtlas()
    if not atlas then return end
    local a = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
    if not (a and a.file) then return end
    d.cropping = true
    local w = a.rightTexCoord - a.leftTexCoord
    local h = a.bottomTexCoord - a.topTexCoord
    tex:SetTexture(a.file)
    tex:SetTexCoord(
        a.leftTexCoord + w * xPct, a.rightTexCoord - w * xPct,
        a.topTexCoord + h * yPct, a.bottomTexCoord - h * yPct)
    d.cropping = nil
end

-- Flat white, not statusbar art with a faint sheen, so a skinned Blizzard
-- window and a KE panel sitting beside each other read as one surface
-- (Chat.lua uses the same).
local BG_TEX = "Interface\\Buttons\\WHITE8x8"

function S.Backdrop(frame, inset, borderOnly)
    if not frame then return nil end

    local isFrame = frame.IsObjectType and frame:IsObjectType("Frame")
    local parent = isFrame and frame or (frame.GetParent and frame:GetParent())
    if not parent then return nil end

    local bd = backdropCache[frame]
    if not bd then
        bd = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        -- 12.1: a backdrop anchored to a frame whose size is secret reads a
        -- secret size itself, and Blizzard's edge tiling divides by it
        -- (Backdrop.lua SetupTextureCoordinates), which throws on every size
        -- change. Both textures here are solid white, so the repeat factors
        -- change nothing that can be seen -- skip the setup instead. Patched
        -- on this instance only; never on the shared mixin.
        local SetupCoords = bd.SetupTextureCoordinates
        if SetupCoords then
            bd.SetupTextureCoordinates = function(self)
                if KE:IsSecretValue(self:GetWidth()) or KE:IsSecretValue(self:GetHeight()) then
                    return
                end
                return SetupCoords(self)
            end
        end
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
-- hover/selection textures inset by the border THICKNESS; with
-- per-frame edges that is no longer a literal 1 inside scaled
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
    -- One frame that refuses a geometry read must not abort the sweep:
    -- that would leave every backdrop after it in the iteration order
    -- stale, and pairs order is arbitrary, so the damage would move
    -- around between sessions.
    for _, bd in pairs(backdropCache) do pcall(RefreshEdge, bd) end
end)

-- re-check every backdrop under a root whose scale changed
-- (world map min/max toggles 1.1 <-> 1.0; scale changes fire no
-- OnSizeChanged on descendants, so callers hook the root's resize).
function S.RefreshEdgesUnder(root)
    if not root then return end
    for frame, bd in pairs(backdropCache) do -- luacheck: ignore 213/frame
        local p = bd
        while p do
            if p == root then RefreshEdge(bd) break end
            p = p.GetParent and p:GetParent() or nil
        end
    end
end

-- Re-measure ONE frame's border. For hosts that scale each element
-- individually and often (bag addons scale every item button on every layout
-- pass), walking the whole cache per element is far too much. RefreshEdge
-- early-outs when the size has not moved, so steady-state cost is a lookup
-- and a subtraction, with no allocation.
function S.RefreshFrameEdge(frame)
    local bd = frame and backdropCache[frame]
    if bd then RefreshEdge(bd) end
end

function S.FixSubPixelEdge(frame, outsetPx)
    local bd = frame and backdropCache[frame]
    if not bd then return end
    local d = S.data(bd)

    local function snap()
        d.aeSnapPending = nil
        if not (frame.GetRect and frame.GetEffectiveScale) then return end
        local eff = frame:GetEffectiveScale()
        local _, ph = GetPhysicalScreenSize()
        if not eff or eff <= 0 or not ph or ph <= 0 then return end
        local toPhys = eff * ph / 768

        local o = (outsetPx or 0) / toPhys
        local L, B, W, H = frame:GetRect()
        if not L then return end

        -- Guild roster rows carry secret data (memberId), and GetRect on
        -- one returns SECRET numbers -- so `B + H` below blew up with
        -- "attempt to perform arithmetic on local 'B' (a secret number
        -- value)". Nothing here can be computed from secrets, and there
        -- is nothing to fall back to, so the row keeps its unsnapped
        -- backdrop: at most one physical pixel off, versus an error.
        if KE:IsSecretValue(L) or KE:IsSecretValue(B)
            or KE:IsSecretValue(W) or KE:IsSecretValue(H) then
            return
        end

        local T = B + H
        local function rnd(v) return math_floor(v * toPhys + 0.5) / toPhys end

        local sL, sT = rnd(L), rnd(T)
        local sW, sH = rnd(W), rnd(H)
        bd:ClearAllPoints()
        bd:SetPoint("TOPLEFT", frame, "TOPLEFT", (sL - L) - o, (sT - T) + o)
        bd:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", (sL + sW) - (L + W) + o, (sT - sH) - B - o)
    end

    local function queueSnap()
        -- snap NOW as well as next frame. The deferral exists
        -- because GetRect() can be nil before layout settles (snap()
        -- bails safely in that case) -- but when the rect IS ready, and
        -- on a re-show it always is, waiting a frame meant the backdrop
        -- painted unsnapped and then shifted. Immediate + queued keeps
        -- both cases correct with no visible adjustment.
        snap()
        if d.aeSnapPending then return end
        d.aeSnapPending = true
        if _G.C_Timer then _G.C_Timer.After(0, snap) else snap() end
    end

    if not d.aeSnapHooked and frame.HookScript then
        d.aeSnapHooked = true
        frame:HookScript("OnShow", queueSnap)
    end
    queueSnap()
end

-- the fix for "skins visibly load in". Every wait-for-frame
-- in the skins used a WALL-CLOCK delay (0.1s-1s), so anything not yet
-- created when the skin ran stayed Blizzard-art for that long, in
-- plain sight. Nothing about those waits needed real time -- they were
-- waiting for a frame to EXIST. Poll per FRAME instead: worst case is
-- one frame (~4ms at the FPS) instead of up to a second, with the
-- same total patience.
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

local BRAND_HL = S.palette.brand

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

-- hold a fontstring's colour without owning its setter.
-- ElvUI's pattern (hook + re-assert); never `SetTextColor = NOOP`.
-- the texture analogue of S.LockTextColor, for plain art regions
-- that Blizzard re-dresses BY ATLAS on a state change.
--
-- Found on SettingsPanel.GameTab/AddOnsTab: /aesskin regions after a hover
-- showed Left/Middle/Right back at atlas=Options_Tab_Active_Left/Middle/
-- Right. Those tabs are NOT PanelTopTabButtons -- there are no *Active
-- regions at all; they swap the atlas on the SAME three regions, so
-- PanelTemplates_SelectTab/DeselectTab (Show/Hide only) never touch them
-- and our one-shot StripTextures had nothing to re-assert against. They are
-- SelectableButtons in a RadioButtonGroup, and the derived state handler
-- re-atlases them on hover/click/selection.
--
-- Self-terminating exactly like ElvUI's ClearNormalTexture: re-clearing
-- fires the hook again with atlas == "", which fails the guard and stops.
-- This is the same permanence idiom S.IconBorder already uses on SetAtlas.
local function keepStripped(region, atlas)
    if atlas and atlas ~= "" then
        region:SetAtlas("")
        region:SetTexture(S.ClearTexture)
    end
end

function S.LockStripped(region)
    if not region or not region.SetAtlas then return end
    local d = S.data(region)
    if d.strippedLocked then return end
    d.strippedLocked = true
    region:SetTexture(S.ClearTexture)
    region:SetAtlas("")
    hooksecurefunc(region, "SetAtlas", keepStripped)
end

function S.LockTextColor(fs, r, g, b, a)
    if not fs or not fs.SetTextColor then return end
    local d = S.data(fs)
    d.lockColor = { r, g, b, a }
    fs:SetTextColor(r, g, b, a)
    if d.colorHooked then return end
    d.colorHooked = true
    local applying = false
    hooksecurefunc(fs, "SetTextColor", function(self, nr, ng, nb, na)
        if applying then return end
        local c = S.data(self).lockColor
        if not c then return end
        if nr == c[1] and ng == c[2] and nb == c[3] and na == c[4] then return end
        applying = true
        self:SetTextColor(c[1], c[2], c[3], c[4])
        applying = false
    end)
end

function S.RowHover(row)
    if not row or S.data(row).hover then return end
    if row.SetHighlightTexture then
        armHover(row, row, 0, -1, 0, 1)
    elseif row.CreateTexture and row.HookScript then

        local tex = row:CreateTexture(nil, "OVERLAY")
        tex:SetTexture("Interface\\Buttons\\WHITE8x8")
        tex:SetVertexColor(HOVER_COLOR[1], HOVER_COLOR[2], HOVER_COLOR[3])
        tex:SetAlpha(HOVER_ALPHA)
        tex:Hide()
        tex:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
        tex:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 1)
        -- AUDIT: never enable input on a row Blizzard left
        -- mouse-disabled. This is our own hover standard, and it is the
        -- exact call that put AES in the currency-transfer FORBIDDEN
        -- (v841): changing input state on Blizzard's rows drags us into
        -- flows we have no business being in. If a row cannot take the
        -- mouse, it does not get a manufactured hover -- ElvUI does the
        -- same (backdrop only, no input changes).
        if row.IsMouseEnabled and not row:IsMouseEnabled() then
            return
        end
        row:HookScript("OnEnter", function() tex:Show() end)
        row:HookScript("OnLeave", function() tex:Hide() end)
        S.data(row).hover = tex
    end
end

function S.Hover(button, anchor)
    if not button or not button.SetHighlightTexture then return end
    anchor = anchor or S.GetBackdrop(button) or button
    armHover(button, anchor, 1, -1, -1, 1)
end

function S.HoverWash(frame)
    if not frame or S.data(frame).hoverWash then return end
    local anchor = S.GetBackdrop(frame) or frame
    local tex = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
    tex:SetTexture(HOVER_TEX)
    tex:SetVertexColor(HOVER_COLOR[1], HOVER_COLOR[2], HOVER_COLOR[3])
    tex:SetAlpha(HOVER_ALPHA)
    if anchor.backdropInfo then
        S.InsetToEdge(tex, anchor)
    else
        tex:SetPoint("TOPLEFT", anchor, "TOPLEFT", 1, -1)
        tex:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -1, 1)
    end
    tex:Hide()
    frame:HookScript("OnEnter", function() tex:Show() end)
    frame:HookScript("OnLeave", function() tex:Hide() end)
    S.data(frame).hoverWash = tex
end

local killedTextures = setmetatable({}, { __mode = "k" })

-- regions exempt from all kill sweeps (KillTexture and every
-- caller: KillAllTextures, S.Button child sweeps). For Blizzard-managed
-- child art a skin must keep alive inside an otherwise-stripped control
-- (e.g. barbershop dropdown color swatches, which Blizzard re-atlases,
-- vertex-colors and Show()s per selection).
local protectedTextures = setmetatable({}, { __mode = "k" })

function S.Protect(region)
    if region then protectedTextures[region] = true end
end

function S.KillTexture(t)
    -- (flyout equip taint, THE root after seven rounds):
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
    -- aligned with ElvUI's Kill (Toolkit.lua) -- their
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

-- ElvUI's texture-clearing idiom, ported exactly
-- (E.ClearTexture = 0 in their Core.lua; S:ClearNormalTexture and
-- friends in Skins.lua). Two ideas we never copied:
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
-- KitnCustomCrossv3 is a PLUS glyph -- KE's own GUI close button draws it as
-- an X by rotating 45 degrees (GUI/GUIMain/GUI-MainFrame.lua). Without the
-- rotation every skinned window draws a small upright plus.
-- Rest colour is KE's GUI white (T.textPrimary), for the same reason: these
-- must read as the same button.
local CLOSE_ROT = math.rad(45)
local CLOSE_SIZE = 16
local CLOSE_REST = { 1, 1, 1 }
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
        x:SetSize(size or CLOSE_SIZE, size or CLOSE_SIZE)
        x:SetRotation(CLOSE_ROT)
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

function S.StatusBar(bar, inset)
    if not bar or S.data(bar).skinned then return end
    S.Backdrop(bar, inset or -1)
    S.data(bar).skinned = true
end

function S.ProgressFill(bar)
    if not bar or not bar.SetStatusBarTexture then return end
    bar:SetStatusBarTexture(HOVER_TEX)
    local c = S.palette.progress
    bar:SetStatusBarColor(c[1], c[2], c[3], c[4])
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

function S.RotateButton(button, direction)
    if not button or S.data(button).aeRotate then return end
    button:SetSize(24, 24)
    S.StripTextures(button)
    S.Backdrop(button)
    local atlas = direction == "left" and "common-icon-rotateleft" or "common-icon-rotateright"
    local norm = button.GetNormalTexture and button:GetNormalTexture()
    if norm then
        norm:ClearAllPoints()
        norm:SetPoint("TOPLEFT", 1, -1)
        norm:SetPoint("BOTTOMRIGHT", -1, 1)
        norm:SetAtlas(atlas)
        norm:SetTexCoord(0.05, 1.05, -0.05, 1)
        norm:SetAlpha(1)
        norm:Show()
    end
    local push = button.GetPushedTexture and button:GetPushedTexture()
    if push and norm then
        push:SetAllPoints(norm)
        push:SetAtlas(atlas)
        push:SetTexCoord(0, 1, -0.1, 0.95)
        push:SetAlpha(1)
    end
    local hl = button.GetHighlightTexture and button:GetHighlightTexture()
    if hl and norm then
        hl:SetAllPoints(norm)
        hl:SetColorTexture(1, 1, 1, 0.3)
    end
    S.data(button).aeRotate = true
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

function S.SelectedFill(bu)
    local sel = bu and bu.SelectedTexture
    if not sel or not sel.SetColorTexture then return end
    sel:SetColorTexture(BRAND_HL[1], BRAND_HL[2], BRAND_HL[3], 0.15)
    local anchor = S.GetBackdrop(bu) or bu
    sel:ClearAllPoints()
    sel:SetPoint("TOPLEFT", anchor, "TOPLEFT", 1, -1)
    sel:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -1, 1)
end

function S.MaxMinFrame(frame)
    if not frame or S.data(frame).skinned then return end

    if frame.MaximizeButton then S.ArrowButton(frame.MaximizeButton, "up", 18) end
    if frame.MinimizeButton then S.ArrowButton(frame.MinimizeButton, "down", 18) end
    S.data(frame).skinned = true
end

local IB_ATLAS_QUALITY
local function ibQuality(atlas)
    if not IB_ATLAS_QUALITY then
        local Q = Enum and Enum.ItemQuality
        if not Q then return nil end
        IB_ATLAS_QUALITY = {
            ["auctionhouse-itemicon-border-gray"]     = Q.Poor,
            ["auctionhouse-itemicon-border-white"]    = Q.Common,
            ["auctionhouse-itemicon-border-green"]    = Q.Uncommon,
            ["auctionhouse-itemicon-border-blue"]     = Q.Rare,
            ["auctionhouse-itemicon-border-purple"]   = Q.Epic,
            ["auctionhouse-itemicon-border-orange"]   = Q.Legendary,
            ["auctionhouse-itemicon-border-artifact"] = Q.Artifact,
            ["auctionhouse-itemicon-border-account"]  = Q.Heirloom,
            ["Professions-Slot-Frame"]                = Q.Common,
            ["Professions-Slot-Frame-Green"]          = Q.Uncommon,
            ["Professions-Slot-Frame-Blue"]           = Q.Rare,
            ["Professions-Slot-Frame-Epic"]           = Q.Epic,
            ["Professions-Slot-Frame-Legendary"]      = Q.Legendary,
        }
    end
    return atlas and IB_ATLAS_QUALITY[atlas]
end
local function ibQualityRGB(q)
    local c = q and _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
end
local function ibReset(border)
    local bd = S.data(border).ibBackdrop
    if bd then
        bd:SetBackdropBorderColor(S.borderColor[1], S.borderColor[2], S.borderColor[3], S.borderColor[4])
    end
end
local function ibHide(border, sentinel)
    if sentinel == 0 then return end
    ibReset(border)
end
local function ibShow(border)
    border:Hide(0)
end
local function ibShown(border, shown)
    if shown then border:Hide(0) else ibReset(border) end
end
local function ibAtlas(border, atlas)
    local r, g, b = ibQualityRGB(ibQuality(atlas))
    local bd = S.data(border).ibBackdrop
    if bd and r then bd:SetBackdropBorderColor(r, g, b, 1) end
end
local function ibVertex(border, r, g, b)
    if ibQuality(border:GetAtlas()) then return end
    local bd = S.data(border).ibBackdrop
    if bd and r then bd:SetBackdropBorderColor(r, g, b, 1) end
end
function S.IconBorder(border, backdrop)
    if not border then return end
    backdrop = backdrop or S.GetBackdrop(border:GetParent())
    if not backdrop then return end
    local d = S.data(border)
    d.ibBackdrop = backdrop

    if border:IsShown() then
        local r, g, b = ibQualityRGB(ibQuality(border:GetAtlas()))
        if not r then r, g, b = border:GetVertexColor() end
        if r then backdrop:SetBackdropBorderColor(r, g, b, 1) end
    else
        ibReset(border)
    end
    if not d.ibHooked then
        d.ibHooked = true
        border:Hide()
        hooksecurefunc(border, "SetAtlas", ibAtlas)
        hooksecurefunc(border, "SetVertexColor", ibVertex)
        hooksecurefunc(border, "SetShown", ibShown)
        hooksecurefunc(border, "Show", ibShow)
        hooksecurefunc(border, "Hide", ibHide)
    end
end

function S.NavButton(button)
    if not button or S.data(button).skinned then return end
    S.StripTextures(button)

    S.ClearButtonArt(button)
    local bd = S.Backdrop(button)
    if bd then bd:SetBackdropColor(CONTROL_BG[1], CONTROL_BG[2], CONTROL_BG[3], CONTROL_BG[4]) end
    S.Hover(button)
    local fs = button.GetFontString and button:GetFontString()
    if fs then fs:SetTextColor(1, 1, 1) end
    local arrow = button.MenuArrowButton
    if arrow then
        S.StripTextures(arrow)
        if arrow.Art then
            arrow.Art:SetTexture(ARROW_TEX)
            arrow.Art:SetTexCoord(0, 1, 0, 1)
            arrow.Art:SetRotation(0)
            arrow.Art:SetVertexColor(ARROW_REST[1], ARROW_REST[2], ARROW_REST[3])
        end
    end
    S.data(button).skinned = true
end

function S.SweepCheckChildren(check)
    if not check or not check.GetChildren then return end
    local ours = S.GetBackdrop(check)
    for _, child in ipairs({ check:GetChildren() }) do
        if child ~= ours and child.SetAlpha then
            child:SetAlpha(0)
        end
    end
end

function S.CheckRefresh(check)
    if not check or not S.data(check).skinned then return end
    S.ClearButtonArt(check)
    local aeBD = S.GetBackdrop(check)
    -- NOOP surgery removed here too (ElvUI parity -- see
    -- S.CheckBox). CheckRefresh IS the re-assert path; it re-runs from
    -- the SetCheckedTexture hook, which is how ElvUI keeps its check
    -- art through Blizzard's repaints.
    local function flat(region)
        if not region then return end
        S.data(region).flat = true
        region:SetAlpha(1)
        region:SetTexture("Interface\\Buttons\\WHITE8x8")
        region:SetVertexColor(BRAND_HL[1], BRAND_HL[2], BRAND_HL[3], S.palette.brandRestA)
        region:ClearAllPoints()

        region:SetPoint("TOPLEFT", aeBD or check, "TOPLEFT", 1, -1)
        region:SetPoint("BOTTOMRIGHT", aeBD or check, "BOTTOMRIGHT", -1, 1)
    end
    if check.SetCheckedTexture and check.GetCheckedTexture and not check:GetCheckedTexture() then
        check:SetCheckedTexture("Interface\\Buttons\\WHITE8x8")
    end
    local checked = check.GetCheckedTexture and check:GetCheckedTexture()
    local disabledChecked = check.GetDisabledCheckedTexture and check:GetDisabledCheckedTexture()
    if check.GetRegions then
        for _, region in ipairs({ check:GetRegions() }) do
            if region.IsObjectType and region:IsObjectType("Texture")
                and region ~= checked and region ~= disabledChecked then
                region:SetTexture("")
            end
        end
    end
    if check.GetChildren then
        local ours = S.GetBackdrop(check)
        for _, child in ipairs({ check:GetChildren() }) do
            if child ~= ours and child.SetAlpha then
                child:SetAlpha(0)
            end
        end
    end
    flat(checked)
    flat(disabledChecked)
end

if _G.SetCheckButtonIsRadio then
    hooksecurefunc("SetCheckButtonIsRadio", function(button)
        S.CheckRefresh(button)
    end)
end

function S.CheckBox(check)
    if not check or S.data(check).skinned then return end
    S.ClearButtonArt(check)

    local aeBD = S.Backdrop(check, 4)
    if aeBD then aeBD:SetBackdropColor(CONTROL_BG[1], CONTROL_BG[2], CONTROL_BG[3], CONTROL_BG[4]) end

    -- ElvUI parity. Their HandleCheckBox replaces the check
    -- ASSET via the official setters and re-asserts through
    -- hooksecurefunc(frame, "SetCheckedTexture", ...) -- it never owns
    -- methods on the texture. Ours did both: asset swap AND
    -- SetAlpha/SetAtlas/SetVertexColor = NOOP. The NOOPs are gone; the
    -- methodArmor hooks below (which we already had) are the ElvUI
    -- mechanism and are enough.
    local function flatCheck(region)
        S.data(region).flat = true

        region:SetAlpha(1)
        region:SetTexture("Interface\\Buttons\\WHITE8x8")

        region:SetVertexColor(BRAND_HL[1], BRAND_HL[2], BRAND_HL[3], S.palette.brandRestA)
        region:ClearAllPoints()

        region:SetPoint("TOPLEFT", aeBD or check, "TOPLEFT", 1, -1)
        region:SetPoint("BOTTOMRIGHT", aeBD or check, "BOTTOMRIGHT", -1, 1)
    end

    if check.SetCheckedTexture and check.GetCheckedTexture and not check:GetCheckedTexture() then
        check:SetCheckedTexture("Interface\\Buttons\\WHITE8x8")
    end
    if check.SetDisabledCheckedTexture and check.GetDisabledCheckedTexture and not check:GetDisabledCheckedTexture() then
        check:SetDisabledCheckedTexture("Interface\\Buttons\\WHITE8x8")
    end
    local checked = check.GetCheckedTexture and check:GetCheckedTexture()
    local disabledChecked = check.GetDisabledCheckedTexture and check:GetDisabledCheckedTexture()

    if not S.data(check).methodArmor then
        S.data(check).methodArmor = true
        if check.SetCheckedTexture then
            hooksecurefunc(check, "SetCheckedTexture", function(c)
                local t = c:GetCheckedTexture()
                if not t then return end
                if S.data(t).flat then

                    t:SetTexture("Interface\\Buttons\\WHITE8x8")
                else
                    S.CheckRefresh(c)
                end
            end)
        end
        -- our bespoke re-kill hooks replaced by the ported
        -- ElvUI idiom -- ClearButtonArt (called at the top of
        -- S.CheckBox) already installs their re-clear-on-set hooks.

    end

    if check.GetRegions then
        for _, region in ipairs({ check:GetRegions() }) do
            if region.IsObjectType and region:IsObjectType("Texture")
                and region ~= checked and region ~= disabledChecked then
                local atlas = region.GetAtlas and region:GetAtlas()
                if atlas == "checkmark-minimal" then
                    flatCheck(region)
                else
                    region:SetTexture("")
                end
            end
        end
    end

    if check.GetChildren then
        local ours = S.GetBackdrop(check)
        for _, child in ipairs({ check:GetChildren() }) do
            if child ~= ours and child.SetAlpha then
                child:SetAlpha(0)
            end
        end
    end

    if checked then
        flatCheck(checked)
    end
    if disabledChecked then
        flatCheck(disabledChecked)
    end
    S.data(check).skinned = true
end

function S.EnsureCaretRoom(box)
    if not box then return end
    local eb = box
    if box.EditBox and box.IsObjectType and not box:IsObjectType("EditBox") then
        eb = box.EditBox
    end
    if not (eb and eb.IsObjectType and eb:IsObjectType("EditBox") and eb.GetTextInsets and eb.SetTextInsets) then return end
    local l, r, t, b = eb:GetTextInsets()
    if (l or 0) < 4 then eb:SetTextInsets(4, r or 0, t or 0, b or 0) end
end

-- duplicate BLIZZARD_REGIONS removed -- the second copy
-- silently shadowed the first and was missing the ScrollFrameBorder
-- entries, so those never got stripped anywhere.
function S.HideBlizzardRegions(frame)
    if not frame then return end

    local okName, name = pcall(frame.GetName, frame)
    if not okName then name = nil end

    for _, area in ipairs(BLIZZARD_REGIONS) do
        -- Both are hidden rather than one or the other. Blizzard hardcodes
        -- names inside virtual templates (AuctionHouse BidAmount is
        -- instantiated twice), so the global resolves to whichever instance
        -- loaded last -- on any other instance it hides the wrong frame's art
        -- and leaves the visible one alone.
        -- A restricted proxy answers the field read and then refuses the
        -- call ("calling Hide on bad self"), which would abort the whole
        -- skin function for one region.
        local own = frame[area]
        if own and own.Hide then pcall(own.Hide, own) end

        local global = name and _G[name .. area]
        if global and global ~= own and global.Hide then pcall(global.Hide, global) end
    end
end

-- Border pieces are not always reachable by name: MoneyFrameEditBoxTemplate's
-- $parentMiddle carries a global name and no parentKey, and Blizzard reuses
-- hardcoded names inside virtual templates, so that global can resolve to a
-- different instance. Sweeping the box's own BACKGROUND textures reaches every
-- piece without naming any of them. The coin icon and label sit on OVERLAY and
-- are left alone.
local function ClearInputBackground(editbox)
    if not editbox.GetRegions then return end

    for _, region in ipairs({ editbox:GetRegions() }) do
        if region.IsObjectType and region:IsObjectType("Texture")
            and region.GetDrawLayer and region:GetDrawLayer() == "BACKGROUND"
            and region.Hide then
            region:Hide()
        end
    end
end

function S.EditBox(editbox, keepFont)
    if not editbox or S.data(editbox).skinned then return end

    S.HideBlizzardRegions(editbox)
    ClearInputBackground(editbox)
    if editbox.NineSlice and editbox.NineSlice.SetAlpha then
        editbox.NineSlice:SetAlpha(0)
    end
    local aeBD = S.Backdrop(editbox)
    if aeBD then aeBD:SetBackdropColor(CONTROL_BG[1], CONTROL_BG[2], CONTROL_BG[3], CONTROL_BG[4]) end

    if not keepFont then

        S.SetFont(editbox, 12, "")
        if editbox.Instructions then S.SetFont(editbox.Instructions, 12, "") end
        S.EnsureCaretRoom(editbox)
    end
    S.data(editbox).skinned = true
end

local function CalibrateTabGap(tab)
    local d = S.data(tab)
    if d.gapDone or not d.selTex then return end

    local n = tab:GetNumPoints()
    if n == 0 then return end
    local pts, chainIdx, chainRel = {}, nil, nil
    for i = 1, n do
        local point, rel, relPoint, x, y = tab:GetPoint(i)
        pts[i] = { point, rel, relPoint, x or 0, y or 0 }
        if not chainIdx and rel and rel.IsObjectType and rel:IsObjectType("Button")
            and S.data(rel).selTex then
            chainIdx, chainRel = i, rel
        end
    end
    local myBD = S.GetBackdrop(tab)
    if not chainIdx then

        local parent = tab:GetParent()
        local bdL = myBD and myBD:GetLeft()
        local pL = parent and parent:GetLeft()
        if not bdL or not pL then return end
        local delta = bdL - pL

        -- This corrects OUR backdrop's inset on a leading tab -- a few
        -- pixels. It is not a licence to relocate the tab row: on
        -- Crafting Orders the parent is the whole frame and the Search
        -- button sits at its left edge, so an uncapped correction dragged
        -- the first tab ~85px left and parked it on top of Search.
        -- Anything past the inset scale is deliberate layout; leave it.
        local MAX_INSET_CORRECTION = 8
        if math.abs(delta) > MAX_INSET_CORRECTION then
            d.gapDone = true
            return
        end

        if math.abs(delta) > 0.5 then
            pts[1][4] = pts[1][4] - delta
            tab:ClearAllPoints()
            for i = 1, n do
                local q = pts[i]
                tab:SetPoint(q[1], q[2], q[3], q[4], q[5])
            end
        end
        d.gapDone = true
        return
    end
    local prevBD = S.GetBackdrop(chainRel)
    local left = myBD and myBD:GetLeft()
    local right = prevBD and prevBD:GetRight()
    if not left or not right then return end
    local gap = left - right
    pts[chainIdx][4] = pts[chainIdx][4] - (gap - 1)
    tab:ClearAllPoints()
    for i = 1, n do
        local q = pts[i]
        tab:SetPoint(q[1], q[2], q[3], q[4], q[5])
    end
    d.gapDone = true
end

local tabSelHooksDone

local recentering = false
local RecenterTabText
function RecenterTabText(tab)
    local text = tab.Text
    if not text then return end
    local n = text:GetNumPoints()
    if n == 0 then return end
    recentering = true
    local pts = {}
    for i = 1, n do
        local point, rel, relPoint, x = text:GetPoint(i)
        pts[i] = { point, rel, relPoint, x or 0 }
    end
    text:ClearAllPoints()
    for i = 1, n do
        local q = pts[i]
        text:SetPoint(q[1], q[2], q[3], q[4], 0)
    end
    recentering = false
end
S.RecenterTabText = RecenterTabText

local function EnsureTabSelHooks()
    if tabSelHooksDone then return end
    tabSelHooksDone = true

    local function PinTextFit(tab)
        if _G.PanelTemplates_TabResize then
            pcall(_G.PanelTemplates_TabResize, tab, 0)
        end
    end
    if _G.PanelTemplates_SelectTab then
        hooksecurefunc("PanelTemplates_SelectTab", function(tab)
            local d = tab and S.data(tab)
            if d and d.selTex then
                d.selTex:Show()
                if not d.noGeometry then
                    PinTextFit(tab)
                    CalibrateTabGap(tab)
                end
                RecenterTabText(tab)
            end
        end)
    end
    if _G.PanelTemplates_DeselectTab then
        hooksecurefunc("PanelTemplates_DeselectTab", function(tab)
            local d = tab and S.data(tab)
            if d and d.selTex then
                d.selTex:Hide()
                if not d.noGeometry then
                    PinTextFit(tab)
                    CalibrateTabGap(tab)
                end
                RecenterTabText(tab)
            end
        end)
    end
end

function S.TabSetSelected(tab, selected)
    local d = tab and S.data(tab)
    if d and d.selTex then
        if selected == nil and tab.IsEnabled then
            selected = not tab:IsEnabled()
        end
        if selected then d.selTex:Show() else d.selTex:Hide() end
        RecenterTabText(tab)
        CalibrateTabGap(tab)
    end
end

-- is this one of Blizzard's modern TabSystem tabs?
-- TabSystemMixin owns their geometry through the MANAGED LAYOUT system:
-- AddTab/SetTabShown call MarkDirty(), and LayoutMixin resolves size and
-- position on the NEXT frame via TabSystemButtonMixin:UpdateTabWidth().
-- PanelTemplates_TabResize is the OLD tab API and has no business here --
-- when we ran it on these, we sized the tab our way and Blizzard's layout
-- pass re-sized it a frame later. That is the "tabs snap into place"
-- hitch on the talent frame: two layout systems fighting, theirs winning
-- on frame two. This is also our own taint doctrine (never write what the
-- managed layout reads); geometry is theirs, styling is ours.
local function IsManagedTab(tab)
    return (tab.GetTabID ~= nil and tab.UpdateTabWidth ~= nil)
        or (tab.GetTabSystem ~= nil)
end

function S.Tab(tab)
    if not tab or S.data(tab).skinned then return end
    local managed = IsManagedTab(tab)
    if managed then S.data(tab).noGeometry = true end
    if tab.SetPushedTextOffset then tab:SetPushedTextOffset(0, 0) end
    S.StripTextures(tab)

    local aeBD = S.Template(tab, "Default", 2)

    S.Hover(tab, aeBD)

    -- A managed tab keeps Blizzard's font SIZE. TabSystemButtonMixin:
    -- UpdateTabWidth() sizes each tab from its text, so forcing 12pt made
    -- Blizzard widen the tabs to match -- on Crafting Orders that pushed
    -- the row over the Search button and off the right edge of the frame.
    -- nil size means "keep what is there"; the face and outline are still
    -- ours, which is the part that makes it look like the rest of the UI.
    local tabFontSize = 12
    if managed then tabFontSize = nil end   -- `managed and nil or 12` is 12
    S.FontStrings(tab, tabFontSize, "OUTLINE")

    do
        local d0 = S.data(tab)
        if tab.Text and not d0.textArmor then
            d0.textArmor = true
            local pending = false
            hooksecurefunc(tab.Text, "SetPoint", function()
                -- was deferred a frame (visible text jump when
                -- Blizzard re-anchors on tab select). `recentering`
                -- already guards the re-entry from our own SetPoints,
                -- so this is safe to do inline -- and the text never
                -- renders off-centre.
                if recentering or pending or S.data(tab).noGeometry then return end
                pending = true
                RecenterTabText(tab)
                pending = false
            end)
        end
        if not d0.noGeometry and not d0.initFit and _G.PanelTemplates_TabResize then
            d0.initFit = true
            -- (tabs start somewhere then snap into
            -- place): this fit was deferred a frame, so the tab was
            -- drawn once at Blizzard's size/position and then jumped to
            -- ours. Nothing here needs to wait -- the tab and its text
            -- both exist right now. Fit synchronously; the tab is only
            -- ever painted in its final geometry.
            if tab.Text then
                pcall(_G.PanelTemplates_TabResize, tab, 0)
                RecenterTabText(tab)
            end
        end
    end

    EnsureTabSelHooks()
    do
        local d = S.data(tab)
        if not d.selTex then
            local anchor = S.GetBackdrop(tab) or tab
            local t = tab:CreateTexture(nil, "ARTWORK")

            t:SetColorTexture(BRAND_HL[1], BRAND_HL[2], BRAND_HL[3], 0.15)
            t:SetPoint("TOPLEFT", anchor, "TOPLEFT", 1, -1)
            t:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -1, 1)
            t:Hide()
            d.selTex = t

            -- Gap calibration needs resolved geometry, which is not available
            -- while we skin. It used to happen only on selection, so tabs sat
            -- at Blizzard's spacing until the first click and then jumped.
            -- OnShow is the first moment the layout is real. gapDone makes it
            -- a no-op after it lands.
            -- OnShow only. Callers routinely re-anchor a tab after S.Tab
            -- returns (Friends moves the whole row below the frame), so
            -- calibrating inline would measure anchors that are about to be
            -- replaced and then latch gapDone against the real ones.
            tab:HookScript("OnShow", CalibrateTabGap)

            if tab.SetTabSelected then

                local sys = tab:GetParent()
                local sd = sys and S.data(sys)
                if sd and not sd.tabRowTuned then
                    sd.tabRowTuned = true

                    sys:HookScript("OnShow", function(s2)
                        local sd2 = S.data(s2)
                        if sd2.flushDone then return end
                        C_Timer.After(0, function()
                            if sd2.flushDone then return end
                            local first = select(1, s2:GetChildren())
                            local bd = first and S.GetBackdrop(first)
                            local owner = s2:GetParent()
                            local bdL = bd and bd:GetLeft()
                            local oL = owner and owner:GetLeft()
                            if bdL and oL then
                                local delta = bdL - oL
                                if math.abs(delta) > 0.5 and s2.AdjustPointsOffset then
                                    s2:AdjustPointsOffset(-delta, 0)
                                end
                                sd2.flushDone = true
                            end
                        end)
                    end)

                    sys.spacing = -3
                    if sys.MarkDirty then sys:MarkDirty() end
                    if sys.AdjustPointsOffset then sys:AdjustPointsOffset(0, -1) end
                end
            else

                local _, rel = tab:GetPoint(1)
                local relIsTab = rel and rel.IsObjectType and rel:IsObjectType("Button")
                    and S.data(rel).selTex ~= nil

                if not relIsTab and tab.AdjustPointsOffset and not d.noGeometry then

                    local d2 = S.data(tab)
                    if not d2.ySeamArmed then
                        d2.ySeamArmed = true

                        local function settle()
                            local bd = S.GetBackdrop(tab)
                            local relFrame = select(2, tab:GetPoint(1))
                            if not (bd and relFrame and relFrame.GetBottom) then return end
                            local bdTop, bdBottom = bd:GetTop(), bd:GetBottom()
                            local fTop, fBottom = relFrame:GetTop(), relFrame:GetBottom()
                            if not (bdTop and bdBottom and fTop and fBottom) then return end
                            local cy = (bdTop + bdBottom) / 2
                            local delta
                            if cy < fBottom then
                                delta = (fBottom - 1) - bdTop
                            elseif cy > fTop then
                                delta = (fTop + 1) - bdBottom
                            end
                            if delta and math.abs(delta) > 0.5 then
                                tab:AdjustPointsOffset(0, delta)
                            end
                        end
                        C_Timer.After(0, settle)
                        tab:HookScript("OnShow", function()
                            settle()
                            C_Timer.After(0, settle)
                        end)
                    end
                end
            end

            if tab.SetTabSelected and not d.tabSysHook then
                local sys0 = tab:GetParent()
                local sd0 = sys0 and S.data(sys0)
                if sd0 and not sd0.flushShowHook then
                    sd0.flushShowHook = true

                    local function Reflush0()
                        for _, c in ipairs({ sys0:GetChildren() }) do
                            if c.Text and c.SetText and c.GetText then
                                local txt = c:GetText()
                                if txt and txt ~= "" then c:SetText(txt) end
                            end
                        end
                        if sys0.MarkDirty then sys0:MarkDirty() end
                        C_Timer.After(0, function()
                            local first = select(1, sys0:GetChildren())
                            local bd = first and S.GetBackdrop(first)
                            local owner = sys0:GetParent()
                            local bdL = bd and bd:GetLeft()
                            local oL = owner and owner:GetLeft()
                            if bdL and oL then
                                local delta = bdL - oL
                                if math.abs(delta) > 0.5 and sys0.AdjustPointsOffset then
                                    sys0:AdjustPointsOffset(-delta, 0)
                                end
                            end
                        end)
                    end
                    sd0.Reflush = Reflush0
                    C_Timer.After(0, Reflush0)
                    sys0:HookScript("OnShow", function()
                        C_Timer.After(0, Reflush0)
                    end)
                end
                d.tabSysHook = true
                hooksecurefunc(tab, "SetTabSelected", function(t2, selected)
                    local dd = S.data(t2)
                    if dd.selTex then
                        dd.selTex:SetShown(selected and true or false)
                        RecenterTabText(t2)
                    end

                    local sys2 = t2:GetParent()
                    local sd2 = sys2 and S.data(sys2)
                    if sd2 and sd2.Reflush then sd2.Reflush() end
                end)
                if tab.isSelected then
                    t:Show()
                    RecenterTabText(tab)
                end
            end

            local parent = tab:GetParent()
            local selected = parent and parent.selectedTab
                and tab.GetID and tab:GetID() == parent.selectedTab
            if selected then
                t:Show()
                RecenterTabText(tab)
            end
        end
    end
    S.data(tab).skinned = true
end

function S.DropDown(dropdown, withCaret)
    if not dropdown or S.data(dropdown).skinned then return end

    S.ClearButtonArt(dropdown)
    S.StripTextures(dropdown)
    if dropdown.GetRegions then
        for _, r in ipairs({ dropdown:GetRegions() }) do
            if r.IsObjectType and r:IsObjectType("Texture") then S.KillTexture(r) end
        end
    end
    local aeBD = S.Backdrop(dropdown)
    if aeBD then aeBD:SetBackdropColor(CONTROL_BG[1], CONTROL_BG[2], CONTROL_BG[3], CONTROL_BG[4]) end

    local arrow = dropdown.Arrow
    if arrow and arrow.SetAlpha then arrow:SetAlpha(0) end

    if withCaret ~= "noCaret" and dropdown.CreateTexture then
        local c = dropdown:CreateTexture(nil, "OVERLAY")
        c:SetTexture(ARROW_TEX)
        c:SetSize(14, 14)
        c:SetPoint("RIGHT", dropdown, "RIGHT", -4, 0)
        c:SetVertexColor(ARROW_REST[1], ARROW_REST[2], ARROW_REST[3])
        S.data(dropdown).caret = c
    end
    S.data(dropdown).skinned = true
end

local buttonOverlays = setmetatable({}, { __mode = "k" })
function S.OverlayButton(button, width, height, text, level, strata)
    if not button or buttonOverlays[button] then return end
    local o = CreateFrame("Frame", nil, UIParent)
    o:SetSize(width or 120, height or 22)
    S.Backdrop(o)
    o:SetPoint(button:GetPoint())
    o:SetFrameLevel(level or 10)
    o:SetFrameStrata(strata or "MEDIUM")
    o:Hide()
    local txt = o:CreateFontString(nil, "OVERLAY")
    txt:SetPoint("CENTER")
    S.SetFont(txt, 12)
    txt:SetTextColor(1, 0.81, 0)
    txt:SetText(text or "")
    o.text = txt
    button:HookScript("OnEnter", function(b)
        local ov = buttonOverlays[b]
        if not ov then return end
        ov.text:SetTextColor(1, 1, 1)
        local bd = S.GetBackdrop(ov)
        if bd then bd:SetBackdropBorderColor(S.palette.brand[1], S.palette.brand[2], S.palette.brand[3], 1) end
    end)
    button:HookScript("OnLeave", function(b)
        local ov = buttonOverlays[b]
        if not ov then return end
        ov.text:SetTextColor(1, 0.81, 0)
        local bd = S.GetBackdrop(ov)
        if bd then bd:SetBackdropBorderColor(unpack(S.borderColor)) end
    end)
    button:HookScript("OnShow", function(b)
        local ov = buttonOverlays[b]
        if not ov then return end
        ov:ClearAllPoints()
        ov:SetPoint(b:GetPoint())
        ov:Show()
    end)
    button:HookScript("OnHide", function(b)
        local ov = buttonOverlays[b]
        if ov then ov:Hide() end
    end)
    if button:IsVisible() then o:Show() end
    buttonOverlays[button] = o
end

-- dedupe flag moved OFF the Blizzard texture and into S.data.
-- `icon.aeIcon = true` was an AES-named field write on a Blizzard object
-- -- banned by our own doctrine three functions down (S.ItemButton,
-- v827: "NO AES-named fields on Blizzard frames, ever -- S.data only").
-- S.Icon is the highest-traffic primitive we have and it was the one
-- place still doing it; it runs on the LootHistory row icons, which is
-- inside the Midnight secret-value path that is currently throwing on
-- roll tooltips. Whether that is the cause of the loot errors is NOT
-- established -- this is a doctrine fix that is free and correct either
-- way. Do not record it as the loot fix without a raid retest.
-- Blizzard's slot art sits flush with the button; ours bleeds a pixel past it
-- so the border reads as an outline rather than an inset.
function S.BleedOutside(tex, frame)
    if not tex then return end

    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", frame, "TOPLEFT", -1, 1)
    tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 1, -1)
end

-- Numeric input with its own increment/decrement pair.
function S.Stepper(box)
    if not box then return end

    box:DisableDrawLayer("BACKGROUND")
    S.EditBox(box)
    S.ArrowButton(box.DecrementButton, "left")
    S.ArrowButton(box.IncrementButton, "right")
end

-- A crafting quality tier: icon button plus the count field beside it.
function S.QualityTier(container)
    if not container then return end

    local button = container.Button
    if button then
        S.StripTextures(button)
        button:SetNormalTexture(0)
        button:SetPushedTexture(0)
        button:SetHighlightTexture(0)
        S.SlotIcon(button.Icon, button.IconBorder)
    end

    S.Stepper(container.EditBox)
end

-- Blanking Blizzard art is a list of region names, not a statement each.
function S.Vanish(root, keys)
    if not root then return end

    for i = 1, #keys do
        local region = root[keys[i]]
        if region and region.SetAlpha then region:SetAlpha(0) end
    end
end

function S.HideAll(root, keys)
    if not root then return end

    for i = 1, #keys do
        local region = root[keys[i]]
        if region and region.Hide then region:Hide() end
    end
end

-- Skinning a container is mostly "if this child exists, treat it". Expressed
-- as data rather than a block per child, so adding a region is one line and
-- absent regions cost nothing.
function S.Apply(root, map)
    if not root then return end

    for key, treat in next, map do
        local child = root[key]
        if child then treat(child) end
    end
end

-- Same treatment across several children of one container.
function S.Each(root, treat, ...)
    if not root then return end

    for i = 1, select("#", ...) do
        local child = root[select(i, ...)]
        if child then treat(child) end
    end
end

-- An icon and its quality border are never independent: the border is drawn
-- against the backdrop the icon just gained, so both are set in one call.
function S.SlotIcon(icon, border, withBackdrop)
    if not icon then return end

    S.Icon(icon, withBackdrop ~= false)
    if border then S.IconBorder(border, S.GetBackdrop(icon)) end
end

function S.Icon(icon, withBackdrop)
    if not icon or S.data(icon).aeIcon then return end
    if icon.SetTexCoord then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end

    S.PixelSnap(icon)
    if withBackdrop then

        local bd = S.Backdrop(icon, -1, true)
        local parent = icon.GetParent and icon:GetParent()
        if bd and parent and parent.GetFrameLevel then
            bd:SetFrameLevel(parent:GetFrameLevel() + 1)
        end
    end
    S.data(icon).aeIcon = true
end

function S.ItemButton(button, opts)
    -- (flyout equip taint, FINAL root): writing our dedupe
    -- flag DIRECTLY ON Blizzard's button plants a tainted key in a
    -- secure table -- contaminating iteration/field-fallback reads
    -- Blizzard's item-button code performs mid-display-loop, which
    -- tainted every subsequent button's location/id writes (the
    -- combat flyout-equip ADDON_ACTION_BLOCKED). Same disease v814
    -- cured for ScrollBoxes; flag lives in S.data now. DOCTRINE:
    -- NO AES-named fields on Blizzard frames, ever -- S.data only.
    if not button or S.data(button).itemSkinned then return end

    local keepAnchors = (opts == "keepAnchors")
    local name = button.GetName and button:GetName()
    local icon = button.icon or button.Icon or button.IconTexture or button.iconTexture
        or (name and (_G[name .. "IconTexture"] or _G[name .. "Icon"]))
    local tex = icon and icon.GetTexture and icon:GetTexture()

    S.StripTextures(button)
    S.Backdrop(button)

    if icon then
        if tex then icon:SetTexture(tex) end
        if icon.SetDrawLayer then icon:SetDrawLayer("ARTWORK") end

        if icon.ClearAllPoints and not keepAnchors then
            icon:ClearAllPoints()
            icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
            icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        end
        S.Icon(icon)
    end
    if button.IconBorder and button.IconBorder.SetAlpha then button.IconBorder:SetAlpha(0) end

    if button.CreateTexture then
        local hl = button:CreateTexture(nil, "HIGHLIGHT")
        hl:SetColorTexture(S.palette.hover[1], S.palette.hover[2], S.palette.hover[3], S.palette.hover[4])
        if keepAnchors and icon then
            hl:SetAllPoints(icon)
        else
            hl:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
            hl:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        end
    end

    S.data(button).itemSkinned = true
end


function S.HookScrollBox(scrollBox, styleRow)
    -- back to ElvUI's pattern -- hooksecurefunc(ScrollBox,
    -- 'Update', fn) with fn doing box:ForEachFrame(styleRow). My v814
    -- rewrite onto the ScrollUtil per-element callback (and the
    -- "never ForEachFrame a Blizzard ScrollBox" doctrine) came from
    -- the pool-taint theory, which was wrong: ElvUI ForEachFrames
    -- Blizzard ScrollBoxes throughout and never uses that callback.
    -- The LootHistory crash was KillTexture surgery, fixed in v838.
    if not scrollBox or not scrollBox.ForEachFrame then return end
    local function apply(box)
        box:ForEachFrame(styleRow)
    end
    apply(scrollBox)
    if scrollBox.Update and not S.data(scrollBox).aeRowHook then
        S.data(scrollBox).aeRowHook = true
        hooksecurefunc(scrollBox, "Update", apply)
    end
end

function S.HookScrollBoxIcons(scrollBox, getIcon, withBackdrop)
    if not scrollBox or not scrollBox.ForEachFrame then return end
    local function cropFrame(frame)
        local icon = getIcon(frame)
        if icon then S.Icon(icon, withBackdrop) end
    end
    local function apply()
        scrollBox:ForEachFrame(cropFrame)
    end
    apply()
    -- same doctrine fix -- this planted an AES key directly on
    -- a Blizzard ScrollBox, the exact object class v814 cleaned up.
    if scrollBox.Update and not S.data(scrollBox).aeIconHook then
        hooksecurefunc(scrollBox, "Update", apply)
        S.data(scrollBox).aeIconHook = true
    end
end

function S.SideTab(tab, anchorParent, prevTab, iconSize)
    if not tab or S.data(tab).aeSideTab then return end
    iconSize = iconSize or 20
    S.Backdrop(tab)
    tab:SetSize(30, 40)

    tab:ClearAllPoints()
    if prevTab then
        tab:SetPoint("TOP", prevTab, "BOTTOM", 0, -1)
        hooksecurefunc(tab, "SetPoint", function(t, _, _, _, x, y)
            if (x ~= 0 or y ~= -1) and not S.data(t).anchoring then
                S.data(t).anchoring = true
                t:ClearAllPoints()
                t:SetPoint("TOP", prevTab, "BOTTOM", 0, -1)
                S.data(t).anchoring = nil
            end
        end)
    elseif anchorParent then
        tab:SetPoint("TOPLEFT", anchorParent, "TOPRIGHT", 1, 0)
        hooksecurefunc(tab, "SetPoint", function(t, _, _, _, x, y)
            if (x ~= 1 or y ~= 0) and not S.data(t).anchoring then
                S.data(t).anchoring = true
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", anchorParent, "TOPRIGHT", 1, 0)
                S.data(t).anchoring = nil
            end
        end)
    end

    local icon = tab.Icon
    if icon then
        local function recenter()
            if S.data(icon).centering then return end
            S.data(icon).centering = true
            icon:ClearAllPoints()
            icon:SetPoint("CENTER")
            S.data(icon).centering = nil
        end
        local function resize()
            if S.data(icon).sizing then return end
            S.data(icon).sizing = true
            icon:SetSize(iconSize, iconSize)
            S.data(icon).sizing = nil
        end
        recenter()
        resize()
        hooksecurefunc(icon, "SetPoint", function(_, point, _, _, x, y)
            if point == "CENTER" and (not x or x == 0) and (not y or y == 0) then return end
            recenter()
        end)
        hooksecurefunc(icon, "SetSize", function(_, w, h)
            if w ~= iconSize or h ~= iconSize then resize() end
        end)

        hooksecurefunc(icon, "SetAtlas", function()
            resize()
            recenter()
        end)
    end

    if tab.Background then tab.Background:SetAlpha(0) end
    if tab.SelectedTexture then
        tab.SelectedTexture:SetDrawLayer("BACKGROUND", 1)
        tab.SelectedTexture:SetColorTexture(S.palette.brand[1], S.palette.brand[2], S.palette.brand[3], 0.3)
        local tbd = S.GetBackdrop(tab)
        if tbd then
            S.InsetToEdge(tab.SelectedTexture, tbd)
        else
            tab.SelectedTexture:ClearAllPoints()
            tab.SelectedTexture:SetPoint("TOPLEFT", tab, "TOPLEFT", 1, -1)
            tab.SelectedTexture:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -1, 1)
        end
    end
    for _, region in ipairs({ tab:GetRegions() }) do
        if region:IsObjectType("Texture") and region:GetAtlas() == "QuestLog-Tab-side-Glow-hover" then
            S.KillTexture(region)
        end
    end
    S.HoverWash(tab)
    S.data(tab).aeSideTab = true
end

function S.NavCrumb(btn)
    if not btn then return end
    S.NavButton(btn)
    btn.xoffset = 0
    local bd = S.GetBackdrop(btn)
    if bd then
        bd:SetBackdropColor(S.controlBg[1], S.controlBg[2], S.controlBg[3], S.controlBg[4])
        bd:ClearAllPoints()
        bd:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -3)
        bd:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 3)
    end
    local hv = S.data(btn).hover
    if hv and bd then
        S.InsetToEdge(hv, bd)
    end
    local fs = btn.GetFontString and btn:GetFontString()
    if fs then S.SetFont(fs, 12, "") end
end

function S.Collapse(button)
    if not button or not button.GetNormalTexture then return end
    local d = S.data(button)
    if d.collapseArmed then return end

    local function resolveCollapsed(incoming)
        local parent = button:GetParent()
        if parent and parent.IsCollapsed then
            local ok, collapsed = pcall(parent.IsCollapsed, parent)
            if ok then return collapsed end
        end
        if type(incoming) == "string" then
            local lower = incoming:lower()
            if lower:find("plus", 1, true) or lower:find("closed", 1, true)
                or lower:find("expand", 1, true) then
                return true
            end
            if lower:find("minus", 1, true) or lower:find("open", 1, true)
                or lower:find("collapse", 1, true) or lower:find("shrink", 1, true) then
                return false
            end
        end
        return nil
    end

    local function apply(incoming)
        if d.collapseBusy then return end
        local collapsed = resolveCollapsed(incoming)
        if collapsed == nil then return end
        local tex = button:GetNormalTexture()
        if not tex then return end
        d.collapseBusy = true
        tex:SetAtlas(collapsed and "Soulbinds_Collection_CategoryHeader_Expand"
            or "Soulbinds_Collection_CategoryHeader_Collapse", true)
        tex:SetVertexColor(1, 1, 1)
        d.collapseBusy = nil
    end

    local pushed = button.GetPushedTexture and button:GetPushedTexture()
    if pushed then pushed:SetAlpha(0) end
    local hl = button.GetHighlightTexture and button:GetHighlightTexture()
    if hl then hl:SetAlpha(0) end

    hooksecurefunc(button, "SetNormalTexture", function(_, texture) apply(texture) end)
    if button.SetNormalAtlas then
        hooksecurefunc(button, "SetNormalAtlas", function(_, atlas) apply(atlas) end)
    end
    button:HookScript("OnClick", function() apply() end)
    button:HookScript("OnShow", function() apply() end)
    apply()
    d.collapseArmed = true
end

function S.ReplaceIconString(fs, text)
    if not fs then return end
    if not text then text = fs.GetText and fs:GetText() end
    if not text or text == "" then return end
    local newText, count = string.gsub(text, "|T([^:]-):[%d+:]+|t", "|T%1:14:14:0:0:64:64:5:59:5:59|t")
    if count > 0 then fs:SetFormattedText("%s", newText) end
end

local PARCHMENT_KEYS = { "Bg", "bg", "Background", "SealMaterialBG", "MaterialBG" }

function S.StripParchment(frame, noChildren)
    if not frame then return end
    for _, k in ipairs(PARCHMENT_KEYS) do
        local r = frame[k]
        if r and r.SetAlpha then r:SetAlpha(0) end
    end
    if frame.GetChildren and not noChildren then
        for _, child in ipairs({ frame:GetChildren() }) do
            for _, k in ipairs(PARCHMENT_KEYS) do
                local r = child[k]
                if r and r.SetAlpha then r:SetAlpha(0) end
            end
        end
    end
end

function S.StylePulloutFrames()
    for n = 1, 30 do
        local po = _G["AceGUI30Pullout" .. n]
        if po and not S.data(po).aePulloutNamed then
            S.data(po).aePulloutNamed = true
            local function reassert()
                if po.SetBackdrop then po:SetBackdrop(nil) end
                local bd = S.GetBackdrop(po)
                if not bd then
                    S.StripTextures(po)
                    bd = S.Template and S.Template(po, "Default") or S.Backdrop(po) -- luacheck: ignore 311/bd
                else
                    bd:Show()
                    bd:SetBackdropColor(S.controlBg[1], S.controlBg[2], S.controlBg[3], S.controlBg[4])
                end
                local sb = _G["AceGUI30PulloutScrollbar" .. n]
                if sb and S.ScrollBar then S.ScrollBar(sb) end
            end
            if po.HookScript then po:HookScript("OnShow", reassert) end
            if po:IsShown() then reassert() end
        end
    end
end

function S.StyleSharedDropDownList()
    if S._ddListHooked then return end
    S._ddListHooked = true

    for i = 1, 2 do
        local list = _G["DropDownList" .. i]
        if list then
            S.StripTextures(list)
            local bd = S.Template and S.Template(list, "Default") or S.Backdrop(list)
            if bd then bd:SetFrameLevel(math.max(list:GetFrameLevel() - 1, 0)) end
            local function scrub()

                for _, suffix in ipairs({ "MenuBackdrop", "Backdrop", "Border" }) do
                    local r = _G["DropDownList" .. i .. suffix]
                    if r and r.SetAlpha then r:SetAlpha(0) end
                    if r and r.Hide then r:Hide() end
                end
                if list.NineSlice and list.NineSlice.SetAlpha then list.NineSlice:SetAlpha(0) end

                local mb = _G["DropDownList" .. i .. "MenuBackdrop"]
                if mb and mb.GetRegions then
                    for _, r in ipairs({ mb:GetRegions() }) do
                        if r.SetAlpha then r:SetAlpha(0) end
                    end
                end
                local sb = _G["DropDownList" .. i .. "ScrollFrameScrollBar"]
                    or _G["DropDownList" .. i .. "ScrollBar"]
                if sb and S.ScrollBar then S.ScrollBar(sb) end
                for b = 1, (_G.UIDROPDOWNMENU_MAXBUTTONS or 8) do
                    local txt = _G["DropDownList" .. i .. "Button" .. b .. "NormalText"]
                    if txt then S.SetFont(txt, 13, "") end
                end
            end
            scrub()
            if list.HookScript then list:HookScript("OnShow", scrub) end
        end
    end
end

S.FONT_FACE = "Expressway"

local fontRegistry = setmetatable({}, { __mode = "k" })
S.fontOffset = 0
-- Mirrors the BlizzardFrames.FontOutline default. Keep the two in step: this
-- governs any SetFont that lands before the db read below can happen.
S.fontOutline = false

-- Three-state outline over a two-state engine. The switch decides whether a
-- string's ASKED-for outline is honoured at all; THICK additionally overrides
-- what was asked. The mode is what the GUI stores and reads back.
--
-- The db key predates the third state and held a boolean, so both forms are
-- accepted. A second key was rejected: AceDB copies scalar defaults into every
-- profile, which would make the fallback to the boolean unreachable.
S.fontOutlineMode = "NONE"

local OUTLINE_MODES = { NONE = true, OUTLINE = true, THICK = true }

function S._ResolveOutlineMode(stored)
    if type(stored) == "string" and OUTLINE_MODES[stored] then return stored end
    if stored == true then return "OUTLINE" end
    return "NONE"
end

-- Base size, not a flat override. Every call site passes its own size and the
-- gaps between them are the visual hierarchy, so the base shifts them together
-- instead of collapsing them.
S.FONT_BASE_DEFAULT = 12
S.fontBaseSize = S.FONT_BASE_DEFAULT

function S._EffectiveSize(size)
    return (tonumber(size) or S.FONT_BASE_DEFAULT)
        + (S.fontBaseSize - S.FONT_BASE_DEFAULT) + S.fontOffset
end

-- One-shot db read for both font switches. It has to run BEFORE either setter
-- assigns, not just on the first SetFont: the GUI writes the db and calls the
-- setter straight through, so a still-pending read would clobber the new value
-- on the next skinned string.
local function EnsureFontInit()
    if S._offsetInit then return end
    if not (KE.db and KE.db.profile and KE.db.profile.Skinning) then return end
    S._offsetInit = true
    local bs = KE.db.profile.Skinning.BlizzardFrames
    S.fontOffset = (bs and tonumber(bs.FontOffset)) or 0
    S.fontOutlineMode = S._ResolveOutlineMode(bs and bs.FontOutline)
    S.fontOutline = (S.fontOutlineMode ~= "NONE")
    S.fontBaseSize = (bs and tonumber(bs.FontSize)) or S.FONT_BASE_DEFAULT
    if bs and type(bs.FontFace) == "string" and bs.FontFace ~= "" then
        S.FONT_FACE = bs.FontFace
    end
end

function S.SetFontOffset(offset)
    EnsureFontInit()
    offset = tonumber(offset) or 0
    if offset == S.fontOffset then return end
    S.fontOffset = offset
    for fs, rec in pairs(fontRegistry) do
        S.SetFont(fs, rec.size, rec.outline)
    end
end

-- Global outline switch. fontRegistry holds the outline each call site ASKED
-- for, never the effective one, so flipping this off strips outlines and
-- flipping it back restores each string's designed flag.
function S.SetFontOutline(enabled)
    EnsureFontInit()
    local mode = enabled and "OUTLINE" or "NONE"
    if mode == S.fontOutlineMode then return end
    S.fontOutlineMode = mode
    S.fontOutline = (mode ~= "NONE")
    for fs, rec in pairs(fontRegistry) do
        S.SetFont(fs, rec.size, rec.outline)
    end
end

function S.SetSkinFont(face, size, outline)
    EnsureFontInit()
    local changed = false

    -- An empty face means the addon's own font, which is what FONT_FACE already
    -- holds by default.
    if face ~= nil then
        local resolved = (face == "") and "Expressway" or face
        if resolved ~= S.FONT_FACE then
            S.FONT_FACE = resolved
            changed = true
        end
    end

    size = tonumber(size)
    if size and size ~= S.fontBaseSize then
        S.fontBaseSize = size
        changed = true
    end

    if outline ~= nil and OUTLINE_MODES[outline] and outline ~= S.fontOutlineMode then
        S.fontOutlineMode = outline
        S.fontOutline = (outline ~= "NONE")
        changed = true
    end

    if not changed then return end

    for fs, rec in pairs(fontRegistry) do
        S.SetFont(fs, rec.size, rec.outline)
    end
end

-- 12.0.7 shadow doctrine: instance-level SetShadowColor/SetShadowOffset no longer
-- affect RENDERING -- a FontString's shadow now comes solely from its
-- FontObject. The per-string zeroing below and at several skin call sites
-- has therefore been silently no-oping on every Blizzard FontString whose
-- inherited object carries a shadow, which is most of them: the text renders
-- OUTLINE plus an unkillable shadow and reads as heavy or blobby at 12px.
--
-- Priming a shared no-shadow FontObject BEFORE SetFont is the fix. SetFont
-- then restores face, size and flags at instance level, while the (absent)
-- object shadow governs rendering.
--
-- Deliberately scoped to the skin engine rather than KE:ApplyFont, which is
-- shared with KE's own modules, whose text has its own shadow pipeline
-- (KE:ApplyFontToText). Skinned Blizzard frames all funnel through here.
local noShadowFont
function S.PrimeNoShadow(fontString)
    if not (fontString and fontString.SetFontObject) then return end
    if not noShadowFont then
        noShadowFont = CreateFont("KE_SkinNoShadowFont")
        noShadowFont:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
        noShadowFont:SetShadowColor(0, 0, 0, 0)
        noShadowFont:SetShadowOffset(0, 0)
    end
    pcall(fontString.SetFontObject, fontString, noShadowFont)
end

function S.SetFont(fontString, size, outline)
    if not fontString or not fontString.SetFont then return end

    EnsureFontInit()
    outline = outline or ""
    local rec = fontRegistry[fontString]

    if not size then
        if rec then
            size = rec.size
        else
            local _, cur = fontString:GetFont()
            size = cur or 12
        end
    end
    local d = S.data(fontString)
    if d.fontSize == size and d.fontOutline == outline and d.fontOffset == S.fontOffset
        and d.fontOutlineOn == S.fontOutline and d.fontFace == S.FONT_FACE
        and d.fontBase == S.fontBaseSize
        and d.fontOutlineMode == S.fontOutlineMode then return end
    local eff = S._EffectiveSize(size)
    if eff < 8 then eff = 8 end
    -- Requested outline goes to the registry and the dirty record; only the
    -- effective one reaches the font, so the switch is reversible.
    local effOutline = ""
    if S.fontOutlineMode == "THICK" then
        effOutline = "THICKOUTLINE"
    elseif S.fontOutline then
        effOutline = outline
    end
    S.PrimeNoShadow(fontString)
    pcall(KE.ApplyFont, KE, fontString, S.FONT_FACE, eff, effOutline)

    if fontString.SetShadowColor then pcall(fontString.SetShadowColor, fontString, 0, 0, 0, 0) end
    d.fontSize = size
    d.fontOutline = outline
    d.fontOffset = S.fontOffset
    d.fontOutlineOn = S.fontOutline
    d.fontFace = S.FONT_FACE
    d.fontBase = S.fontBaseSize
    d.fontOutlineMode = S.fontOutlineMode
    if rec then
        rec.size, rec.outline = size, outline
    else
        fontRegistry[fontString] = { size = size, outline = outline }
    end
end

function S.FontStrings(frame, size, outline)
    if not frame or not frame.GetRegions then return end
    for _, r in ipairs({ frame:GetRegions() }) do
        if r.GetObjectType and r:GetObjectType() == "FontString" then
            S.SetFont(r, size, outline)
        end
    end
end

function S.FontStringsDeep(frame, size, outline, depth)
    if depth == nil then depth = 2 end
    if not frame or depth < 0 then return end
    if frame.GetRegions then
        for _, r in ipairs({ frame:GetRegions() }) do
            if r.GetObjectType and r:GetObjectType() == "FontString" then
                S.SetFont(r, size, outline)
            end
        end
    end
    if frame.GetChildren then
        for _, c in ipairs({ frame:GetChildren() }) do
            S.FontStringsDeep(c, size, outline, depth - 1)
        end
    end
end

function S.Portrait(frame)
    if not frame then return end
    if frame.portrait and frame.portrait.SetAlpha then frame.portrait:SetAlpha(0) end
    if frame.Portrait and frame.Portrait.SetAlpha then frame.Portrait:SetAlpha(0) end
    if frame.PortraitContainer then
        if frame.PortraitContainer.SetAlpha then frame.PortraitContainer:SetAlpha(0) end
        local p = frame.PortraitContainer.portrait
        if p and p.SetAlpha then p:SetAlpha(0) end
    end
    local name = frame.GetName and frame:GetName()
    if name then
        local p = _G[name .. "Portrait"]
        if p and p.SetAlpha then p:SetAlpha(0) end
    end
end

local THUMB_REST, THUMB_HOT = S.palette.brandRestA, 0.75
local function thumbColor(t, a)
    local tbd = backdropCache[t]
    if tbd then tbd:SetBackdropColor(BRAND_HL[1], BRAND_HL[2], BRAND_HL[3], a) end
end
local function thumbOnEnter(t) thumbColor(t, THUMB_HOT) end
local function thumbOnLeave(t) if not t.__aeActive then thumbColor(t, THUMB_REST) end end
local function thumbOnMouseDown(t) t.__aeActive = true; thumbColor(t, THUMB_HOT) end
local function thumbOnMouseUp(t) t.__aeActive = nil; thumbColor(t, THUMB_REST) end

local function skinScrollArrows(frame)
    -- (currency-transfer FORBIDDEN, the actual root):
    -- this used S.ArrowButton on the trim bar's steppers, which runs
    -- zeroArrowStates -> S.KillTexture -> `t.Show = t.Hide` SLOT WRITES
    -- on stepper textures, plus OnEnter/OnLeave/OnShow re-kill hooks
    -- that re-poisoned those slots on every hover, plus an
    -- AdjustPointsOffset nudge (insecure anchor writes on managed
    -- stepper geometry that ScrollBarMixin:Update reads back through
    -- GetTrackExtent). ScrollBar:Update runs INSIDE the ScrollBox
    -- layout pass that initializes list rows -- on TokenFrame that
    -- poisoned every row's elementData/currencyIndex, and the row
    -- click carried the taint all the way to
    -- RequestCurrencyFromAccountCharacter (convicted by config bisect
    -- + issecurevariable ladder, v859 session).
    -- ElvUI's stepper contact (ReskinScrollBarArrow) is STATE-ONLY:
    -- StripTextures + Texture/Overlay alpha 0 + their own arrow art.
    -- Ported exactly; our overlay glyph replaces their SetNormalTexture.
    for _, side in ipairs({ { frame.Back, "up" }, { frame.Forward, "down" } }) do
        local b = side[1]
        if b then
            S.StripTextures(b)
            if b.Texture and b.Texture.SetAlpha then b.Texture:SetAlpha(0) end
            if b.Overlay and b.Overlay.SetAlpha then b.Overlay:SetAlpha(0) end

            local d = S.data(b)
            if not d.arrow then
                local a = b:CreateTexture(nil, "OVERLAY")
                a:SetPoint("CENTER")
                a:SetSize(15, 15)
                a:SetTexture(ARROW_TEX)
                a:SetRotation(ARROW_ROT[side[2]] or 0)
                a:SetVertexColor(ARROW_REST[1], ARROW_REST[2], ARROW_REST[3])
                d.arrow = a
                b:HookScript("OnEnter", arrowOnEnter)
                b:HookScript("OnLeave", arrowOnLeave)
            end
        end
    end
end

function S.TrimScrollBar(frame, ignoreUpdates) -- luacheck: ignore 212/ignoreUpdates
    if not frame then return end
    S.StripTextures(frame)
    skinScrollArrows(frame)
    if frame.Background and frame.Background.Hide then frame.Background:Hide() end
    if frame.Track and frame.Track.DisableDrawLayer then frame.Track:DisableDrawLayer("ARTWORK") end
    local thumb = frame.GetThumb and frame:GetThumb()
    if thumb and not backdropCache[thumb] then
        if thumb.DisableDrawLayer then
            thumb:DisableDrawLayer("ARTWORK")
            thumb:DisableDrawLayer("BACKGROUND")
        end
        local bd = S.Backdrop(thumb)
        if bd then
            bd:SetBackdropColor(BRAND_HL[1], BRAND_HL[2], BRAND_HL[3], THUMB_REST)
            bd:SetFrameLevel((thumb.GetFrameLevel and thumb:GetFrameLevel()) or 1)
        end
        thumb:HookScript("OnEnter", thumbOnEnter)
        thumb:HookScript("OnLeave", thumbOnLeave)
        thumb:HookScript("OnMouseDown", thumbOnMouseDown)
        thumb:HookScript("OnMouseUp", thumbOnMouseUp)
    end

    -- THE ROOT. This used to be:
    --     hooksecurefunc(frame, "Update", skinScrollArrows)
    -- and it is why this addon was being named as the owner of taint in
    -- Blizzard code all over the UI.
    --
    -- ScrollBoxListMixin:Update() calls ScrollBar:Update() partway through
    -- its own body. Our hook fired there, taint landed, and control then
    -- returned INTO THE MIDDLE of ScrollBox:Update() -- so every write it
    -- had left to do was ours. /aeloot proved it key by key: everything
    -- dirty on the loot history frame is written by that one function
    -- after the ScrollBar:Update call --
    --     ScrollBox.updateLock, ScrollBox.panExtentPercentage
    --     view.acquireLock, view.dataIndexBegin, view.dataIndexEnd,
    --     view.extent, view.calculatedElementExtents,
    --     view.hasIdenticalTemplateExtent
    --     ScrollBar.scrollPercentage/panExtentPercentage/visibleExtentPercentage
    --     row.GetElementData/SetOrderIndex/GetOrderIndex/GetData/... (the
    --       ScrollBoxFactoryInitializer mixin, re-applied on frame acquire)
    --     row.dropInfo/encounterID/lootListID (the element initializer
    --       calling row:Init)
    --     row.Item.isCraftedItem/isProfessionItem (SetItemButtonQuality,
    --       called from inside that Init)
    -- and row.dropInfo is what LootHistory:38 reads first in SetTooltip,
    -- which taints the OnEnter and detonates Midnight's secret roll
    -- geometry at Layout. Intermittent because only updates that actually
    -- move the scrollbar route through ScrollBar:Update.
    --
    -- ElvUI's HandleTrimScrollBar has NO Update hook -- it reskins the
    -- steppers once and they stay. That is why ElvUI is clean on this and
    -- we were not. Ours is now theirs: skin once, no hook.
    --
    -- `ignoreUpdates` is kept only so the ~40 call sites keep working; it
    -- is now inert. It was a misport in the first place: ElvUI's second arg
    -- goes to thumb:CreateBackdrop('Transparent', nil, ignoreUpdates) and
    -- is a backdrop-registration flag, not a gate on an Update hook they
    -- never had. Currency passing `true` was accidentally the only skin
    -- immune to this.
    --
    -- CORRECTION: v868 claimed this hook was the root of the
    -- LootHistory taint and attached a doctrine to it -- "never
    -- hooksecurefunc a method Blizzard calls from the middle of another
    -- Blizzard function". Both were wrong. Removing this hook changed
    -- nothing, and the v869 staged bisect then installed
    -- hooksecurefunc(scrollBox, "Update", apply) -- a method Blizzard calls
    -- mid-function, the exact shape the doctrine forbade -- and every
    -- object stayed 100% secure. The real root was load-time: the skin ran
    -- from RegisterEarly and triggered the ScrollBox's FIRST layout, which
    -- stamped ScrollBox.updateLock ours, and updateLock is read on Update's
    -- first line so it self-perpetuated (fixed v870 by deferring to first
    -- OnShow). hooksecurefunc on a Blizzard method is fine and stays fine:
    -- ElvUI does it thousands of times, S.IconBorder and S.LockStripped
    -- both hook SetAtlas on Blizzard regions.
    --
    -- The removal itself stands anyway, on ElvUI parity: their
    -- HandleTrimScrollBar has no Update hook, it reskins the steppers once
    -- and they stay (our v860 state-only rewrite is what makes that true
    -- for us too). One less per-update closure, no behaviour change.
end

function S.ScrollBar(scrollbar, ignoreUpdates)
    if not scrollbar or S.data(scrollbar).skinned then return end
    if scrollbar.GetThumb or scrollbar.Back or scrollbar.Forward then
        S.TrimScrollBar(scrollbar, ignoreUpdates)
    else

        local name = scrollbar.GetName and scrollbar:GetName()
        local up = scrollbar.ScrollUpButton or scrollbar.UpButton or scrollbar.ScrollUp
            or (name and _G[name .. "ScrollUpButton"])
        local down = scrollbar.ScrollDownButton or scrollbar.DownButton or scrollbar.ScrollDown
            or (name and _G[name .. "ScrollDownButton"])
        local thumb = scrollbar.ThumbTexture or scrollbar.thumbTexture or scrollbar.Thumb
            or (name and _G[name .. "ThumbTexture"])
            or (scrollbar.GetThumbTexture and scrollbar:GetThumbTexture())
        S.StripTextures(scrollbar)
        if scrollbar.trackBG then S.KillTexture(scrollbar.trackBG) end
        if scrollbar.Background and scrollbar.Background.Hide then scrollbar.Background:Hide() end
        if scrollbar.ScrollUpBorder then scrollbar.ScrollUpBorder:Hide() end
        if scrollbar.ScrollDownBorder then scrollbar.ScrollDownBorder:Hide() end

        local bd = S.Backdrop(scrollbar)
        if bd then
            bd:ClearAllPoints()
            bd:SetPoint("TOPLEFT", up or scrollbar, up and "BOTTOMLEFT" or "TOPLEFT", 0, 1)
            bd:SetPoint("BOTTOMRIGHT", down or scrollbar, down and "TOPRIGHT" or "BOTTOMRIGHT", 0, -1)
        end
        local lvl = scrollbar.GetFrameLevel and scrollbar:GetFrameLevel() or 1
        if up then S.ArrowButton(up, "up"); up:SetFrameLevel(lvl + 2) end
        if down then S.ArrowButton(down, "down"); down:SetFrameLevel(lvl + 2) end
        if thumb and thumb.SetTexture then
            thumb:SetTexture("Interface\\Buttons\\WHITE8x8")
            if thumb.SetTexCoord then thumb:SetTexCoord(0, 1, 0, 1) end
            thumb:SetVertexColor(BRAND_HL[1], BRAND_HL[2], BRAND_HL[3], THUMB_REST)
        end
    end
    S.data(scrollbar).skinned = true
end

function S.StepSlider(stepper)
    if not stepper or S.data(stepper).skinned then return end
    S.StripTextures(stepper)

    local slider = stepper.Slider
    if slider then
        if slider.DisableDrawLayer then slider:DisableDrawLayer("ARTWORK") end

        local thumb = slider.Thumb
        if thumb then
            thumb:SetTexture("Interface\\Buttons\\WHITE8x8")
            thumb:SetVertexColor(BRAND_HL[1], BRAND_HL[2], BRAND_HL[3], S.palette.brandFillA)
            thumb:SetSize(10, 18)
        end

        local bd = S.Backdrop(slider)
        if bd then
            bd:ClearAllPoints()

            bd:SetPoint("TOPLEFT", slider, "TOPLEFT", 2, -13)
            bd:SetPoint("BOTTOMRIGHT", slider, "BOTTOMRIGHT", -2, 13)

            bd:SetParent(stepper)
            bd:SetBackdropColor(CONTROL_BG[1], CONTROL_BG[2], CONTROL_BG[3], CONTROL_BG[4])

            if thumb and not S.data(slider).stepBar then
                local step = CreateFrame("StatusBar", nil, slider)
                step:SetFrameLevel(bd:GetFrameLevel() + 1)
                step:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
                step:SetStatusBarColor(BRAND_HL[1], BRAND_HL[2], BRAND_HL[3], 0.35)
                local px = PixelBorder()
                step:SetPoint("TOPLEFT", bd, "TOPLEFT", px, -px)
                step:SetPoint("BOTTOMLEFT", bd, "BOTTOMLEFT", px, px)
                step:SetPoint("RIGHT", thumb, "CENTER")
                S.data(slider).stepBar = step

                if thumb.SetIgnoreParentAlpha then thumb:SetIgnoreParentAlpha(true) end
                if step.SetIgnoreParentAlpha then step:SetIgnoreParentAlpha(true) end
                local function stateColor()
                    local on = not slider.IsEnabled or slider:IsEnabled()
                    if on then
                        thumb:SetVertexColor(BRAND_HL[1], BRAND_HL[2], BRAND_HL[3], S.palette.brandFillA)
                        step:SetStatusBarColor(BRAND_HL[1], BRAND_HL[2], BRAND_HL[3], 0.35)
                    else
                        thumb:SetVertexColor(0.486, 0.486, 0.486, 1)
                        step:SetStatusBarColor(0.486, 0.486, 0.486, 0.35)
                    end
                end
                if slider.HookScript then
                    hooksecurefunc(slider, "Enable", stateColor)
                    hooksecurefunc(slider, "Disable", stateColor)
                    if slider.SetEnabled then hooksecurefunc(slider, "SetEnabled", stateColor) end
                end
                stateColor()
            end
        end
    end

    for _, side in ipairs({ { stepper.Back, "left" }, { stepper.Forward, "right" } }) do
        local b = side[1]
        if b then
            if b.Texture and b.Texture.SetAlpha then b.Texture:SetAlpha(0) end
            if b.Overlay and b.Overlay.SetAlpha then b.Overlay:SetAlpha(0) end
            S.ArrowButton(b, side[2])
        end
    end
    S.data(stepper).skinned = true
end

function S.Inset(frame, withBackdrop)
    if not frame or S.data(frame).inset then return end
    for _, key in ipairs({
        "InsetBorderTop", "InsetBorderTopLeft", "InsetBorderTopRight",
        "InsetBorderBottom", "InsetBorderBottomLeft", "InsetBorderBottomRight",
        "InsetBorderLeft", "InsetBorderRight", "Bg",
    }) do
        local r = frame[key]
        if r and r.Hide then r:Hide() end
    end

    if frame.NineSlice then
        S.StripTextures(frame.NineSlice)
        frame.NineSlice:Hide()

        frame.NineSlice:SetAlpha(0)
        if frame.NineSlice.EnableMouse then frame.NineSlice:EnableMouse(false) end
        if not S.data(frame.NineSlice).reHide then
            S.data(frame.NineSlice).reHide = true
            hooksecurefunc(frame.NineSlice, "Show", function(ns) ns:Hide() end)
        end
    end
    S.StripTextures(frame)
    if withBackdrop then S.Backdrop(frame, 0, true) end
    S.data(frame).inset = true
end

function S.StaticPopup(popup)
    if not popup then return end
    if not S.data(popup).skinned then
        S.StripTextures(popup)
        S.Backdrop(popup)
        S.data(popup).skinned = true
    end

    if popup.BG then S.StripTextures(popup.BG) end
    local name = popup.GetName and popup:GetName()
    for i = 1, 4 do
        local b = popup["button" .. i] or popup["Button" .. i] or (name and _G[name .. "Button" .. i])
        if b then S.Button(b) end
    end
    local edit = popup.editBox or popup.EditBox or (name and _G[name .. "EditBox"])
    if edit then S.EditBox(edit) end
    local close = popup.CloseButton or (name and _G[name .. "CloseButton"])
    if close then S.CloseButton(close) end
end

function S.Frame(frame, keepChildArt)
    if not frame or S.data(frame).skinned then return end

    if frame.PortraitContainer then frame.PortraitContainer:SetAlpha(0) end
    if frame.portrait then frame.portrait:SetAlpha(0) end

    S.Portrait(frame)
    S.StripTextures(frame)

    for _, key in ipairs({ "Bg", "bg", "Background", "TopTileStreaks", "TitleBg", "FrameBg" }) do
        local r = frame[key]
        if r and r.SetAlpha then r:SetAlpha(0) end
    end
    if frame.NineSlice and frame.NineSlice.SetAlpha then
        frame.NineSlice:SetAlpha(0)

        if frame.NineSlice.EnableMouse then frame.NineSlice:EnableMouse(false) end
    end

    if frame.BorderFrame then S.StripTextures(frame.BorderFrame) end

    S.StripParchment(frame, keepChildArt)

    S.Backdrop(frame)

    local name = frame.GetName and frame:GetName()
    local close = frame.CloseButton or (name and _G[name .. "CloseButton"])
    if close then

        local label = close.GetText and close:GetText()
        if label and label ~= "" then
            S.Button(close)
        else
            S.CloseButton(close)
        end
    end

    local inset = frame.Inset or (name and _G[name .. "Inset"])
    if inset then S.Inset(inset) end
    for _, key in ipairs({ "LeftInset", "RightInset", "BottomInset" }) do
        if frame[key] then S.Inset(frame[key]) end
    end

    if frame.ScrollBar then S.ScrollBar(frame.ScrollBar) end
    if frame.GetChildren then
        for _, child in ipairs({ frame:GetChildren() }) do
            if child.GetThumb or child.Back or child.Forward then
                S.ScrollBar(child)
            end
        end
    end

    S.data(frame).skinned = true
end

function S.Tabs(prefix, maxN)
    for i = 1, (maxN or 12) do
        local tab = _G[prefix .. i]
        if tab then S.Tab(tab) end
    end
end

function S:IsActive()
    if KE:ShouldNotLoadModule() then return false end
    local db = KE.db and KE.db.profile and KE.db.profile.Skinning
        and KE.db.profile.Skinning.BlizzardFrames
    return db and db.Enabled == true
end

local addonSkins = {}
local earlySkins = {}

-- Per-registration bookkeeping: S.skinRegistrations[key] is an ORDERED array
-- of records, one per S:Register/S:RegisterEarly call naming this key. A key
-- can carry many registrations (Housing carries nine), and the old
-- skinStatus/skinIndex writes were last-wins per key -- one broken
-- registration could hide behind a later healthy one.
--
-- Appended here, at REGISTER time, not at dispatch: a dispatch-time log
-- cannot see a registration whose Blizzard addon never loaded -- it simply
-- has no record, indistinguishable from a key that has none. Register-time
-- gives stable ordering AND surfaces those as "pending", which is the
-- difference between "this window was never opened" and "this skin is
-- missing". The addon queues are also drained after dispatch
-- (addonSkins[addonName] = nil, inside BF:RunForAddon), so a dispatch-time
-- capture would lose the entry reference rerun needs.
S.skinRegistrations = {}
-- Plain table, not weak: a weak KEY mode could never collect anything here
-- anyway (the value strongly references its own key via record.entry, Lua
-- 5.1 has no ephemeron support, and S.skinRegistrations holds every record
-- for the whole session regardless), so __mode = "k" would only advertise a
-- lifetime guarantee this table does not actually have.
local entryRecords = {}

-- The truthful aggregate for skinStatus[key]: an error anywhere outranks
-- every other state -- Housing's real defect was one throwing registration
-- hiding behind eight "ok" ones -- and each uniform state below it only
-- applies when EVERY record agrees. Any disagreement falls through to
-- "partial", the honest answer once one key can carry many registrations. A
-- one-registration key aggregates to itself.
local function aggregateStatus(key)
    local records = S.skinRegistrations[key]
    if not records or #records == 0 then return nil end

    local errorStatus
    local allPending, allOk, allDisabled, allSuppressed = true, true, true, true
    for _, record in ipairs(records) do
        local status = record.status
        if status ~= "pending" and status ~= "ok"
            and status ~= "disabled" and status ~= "suppressed" then
            errorStatus = errorStatus or status
        end
        if status ~= "pending" then allPending = false end
        if status ~= "ok" then allOk = false end
        if status ~= "disabled" then allDisabled = false end
        if status ~= "suppressed" then allSuppressed = false end
    end

    if errorStatus then return errorStatus end
    if allPending then return "pending" end
    if allOk then return "ok" end
    if allDisabled then return "disabled" end
    if allSuppressed then return "suppressed" end
    return "partial"
end

local function newRecord(key, addon, entry)
    local records = S.skinRegistrations[key]
    if not records then records = {}; S.skinRegistrations[key] = records end
    local record = { id = #records + 1, addon = addon, entry = entry, status = "pending" }
    records[#records + 1] = record
    entryRecords[entry] = record
    -- Keeps skinStatus a live aggregate from the moment a key gets its first
    -- registration, not only once dispatch first touches it -- otherwise
    -- "pending" (a key with registrations that never dispatched) would be
    -- unobservable through skinStatus at all.
    S.skinStatus[key] = aggregateStatus(key)
    return record
end

local function SkinEnabled(key, addon)
    if not key then return true end
    -- EllesmereUI already skins this window. Two engines backdropping one
    -- frame gives it two borders. This is a SEPARATE axis from the user's
    -- own toggle below and never writes to it, so a skin comes straight
    -- back when EllesmereUI stops owning the window.
    --
    -- S.GetSuppression is EUIWindows.lua's accessor, guarded because a
    -- headless spec can load this file alone, with no accessor to call.
    if S.GetSuppression and S.GetSuppression(key, addon) then return false end
    local frames = KE.db and KE.db.profile and KE.db.profile.Skinning
        and KE.db.profile.Skinning.BlizzardFrames
    local skins = frames and frames.Skins
    return not skins or skins[key] ~= false
end

function S:Register(addonName, fn, key)
    local list = addonSkins[addonName]
    if not list then list = {}; addonSkins[addonName] = list end
    local entry = { fn = fn, key = key, addon = addonName }
    list[#list + 1] = entry
    if key then newRecord(key, addonName, entry) end
end

function S:RegisterEarly(fn, key)
    local entry = { fn = fn, key = key }
    earlySkins[#earlySkins + 1] = entry
    if key then newRecord(key, nil, entry) end
end

S.skinStatus = {}
S.skinIndex = {}

local function runList(list)
    if not list then return end
    for _, entry in ipairs(list) do
        if entry.key then S.skinIndex[entry.key] = entry end
        local record = entryRecords[entry]

        if SkinEnabled(entry.key, entry.addon) then
            local ok, err = pcall(entry.fn)
            if entry.key then
                local status = ok and "ok" or ("ERROR: " .. tostring(err))
                if record then
                    record.status = status
                    S.skinStatus[entry.key] = aggregateStatus(entry.key)
                else
                    -- Free regression pin: the existing suite's synthetic
                    -- _runList entries never went through S:Register, so
                    -- they have no record here. Tolerate that WITHOUT
                    -- skipping the skinStatus write -- falling back to the
                    -- direct write keeps skinStatus populated for them, same
                    -- as before this task. Don't "fix" this away; the
                    -- existing suite depends on it.
                    S.skinStatus[entry.key] = status
                end
            end
            if not ok then

                local tag = entry.key and ("[" .. entry.key .. "] ") or ""
                KE:Print("|cffff0000KE SKIN ERROR (report this line):|r " .. tag .. tostring(err))
            end
        elseif entry.key then
            -- SkinEnabled folds both axes (EllesmereUI suppression, the
            -- user's own opt-out) into one boolean, so it alone can't say
            -- WHICH one fired. Ask the accessor again, this time for the
            -- reason rather than the verdict, so "suppressed" and "disabled"
            -- land as distinct statuses instead of both reading "disabled".
            local suppressor = S.GetSuppression and S.GetSuppression(entry.key, entry.addon)
            local status = suppressor and "suppressed" or "disabled"
            if record then
                record.status = status
                record.suppressor = suppressor
                S.skinStatus[entry.key] = aggregateStatus(entry.key)
            else
                S.skinStatus[entry.key] = status
            end
        end
    end
end

-- Test seam: runList is file-local because nothing outside this file should
-- dispatch a skin list, but its enable gate and error isolation are the two
-- behaviours that keep one broken skin from taking the rest down.
S._runList = runList

-- "ok" and "disabled" keep their long-standing colours; the three states a
-- multi-registration key can now report (pending/partial/suppressed) each
-- get their own non-red rendering, so only a genuine error string (the
-- "ERROR: ..." shape runList builds) ever reads as one.
local STATUS_COLOR = {
    ok         = "|cff00ff00",
    disabled   = "|cff888888",
    suppressed = "|cff33ccff",
    pending    = "|cffffff00",
    partial    = "|cffff9900",
}
local function statusColor(status)
    return STATUS_COLOR[status] or "|cffff0000"
end

function S.DebugVerify()
    local n, keyCount = 0, 0
    for key, records in pairs(S.skinRegistrations) do
        keyCount = keyCount + 1
        local hasNonOk = false
        for _, record in ipairs(records) do
            if record.status ~= "ok" then
                hasNonOk = true
                break
            end
        end

        if #records > 1 or hasNonOk then
            -- More than one registration, or at least one non-"ok" record:
            -- an aggregate line would hide which of several registrations is
            -- the problem, so print every registration under this key.
            for _, record in ipairs(records) do
                n = n + 1
                local shown = record.status
                if record.status == "suppressed" then
                    -- Captured into a local with a fallback: GetSuppressionState
                    -- returns NO second value for "none", and a zero-value call
                    -- inside a concat becomes nil, which throws.
                    local _, euiKey = S.GetSuppressionState(key)
                    shown = "suppressed by EllesmereUI (" .. (euiKey or record.suppressor or "unknown") .. ")"
                end
                local label = key .. " #" .. record.id .. " (" .. (record.addon or "early") .. ")"
                print(("|cffFF008CKitn|r|cffffffffEssentials:|r %-32s %s%s|r"):format(label, statusColor(record.status), shown))
            end
        else
            n = n + 1
            local status = records[1].status
            print(("|cffFF008CKitn|r|cffffffffEssentials:|r %-24s %s%s|r"):format(key, statusColor(status), status))
        end
    end
    print(("|cffFF008CKitn|r|cffffffffEssentials:|r verify done (%d lines across %d registered keys; a key absent here means its addon never loaded or it was never registered)"):format(n, keyCount))
end

local function findBySelector(records, selector)
    local id = tostring(selector):match("^#(%d+)$")
    if id then
        id = tonumber(id)
        for _, record in ipairs(records) do
            if record.id == id then return record end
        end
        return nil
    end
    -- Case-insensitive, matching the key lookup above -- an addon name typed
    -- in the wrong case should resolve the same registration, not read as
    -- an unknown selector.
    local ls = tostring(selector):lower()
    for _, record in ipairs(records) do
        if record.addon and record.addon:lower() == ls then return record end
    end
    return nil
end

function S.DebugRerun(key, selector)
    local records = S.skinRegistrations[key]
    local matchedKey = key
    if not records then

        local lk = tostring(key):lower()
        for k, recs in pairs(S.skinRegistrations) do
            if k:lower() == lk then matchedKey, records = k, recs break end
        end
    end
    if not records or #records == 0 then
        print("|cffFF008CKitn|r|cffffffffEssentials:|r no dispatched skin named '" .. tostring(key) .. "' -- run /kes skins verify for the list")
        return
    end
    key = matchedKey

    local record
    if selector then
        record = findBySelector(records, selector)
        if not record then
            print("|cffFF008CKitn|r|cffffffffEssentials:|r " .. key .. " has no registration '" .. tostring(selector) .. "' -- run /kes skins verify for the list")
            return
        end
    elseif #records > 1 then
        -- Several registrations and no selector: refuse rather than
        -- silently picking one -- today's per-key guard reruns only the
        -- LAST registration, which for Housing would be one of nine.
        local choices = {}
        for _, r in ipairs(records) do
            choices[#choices + 1] = "#" .. r.id .. " (" .. (r.addon or "early") .. ")"
        end
        print("|cffFF008CKitn|r|cffffffffEssentials:|r " .. key .. " has " .. #records
            .. " registrations -- specify one: " .. table.concat(choices, ", "))
        return
    else
        record = records[1]
    end

    -- A pending record's frames don't exist yet -- its Blizzard addon
    -- (or, for an early registration, the registration itself) never
    -- dispatched this session. Calling entry.fn against nothing would print
    -- a false "completed" or a false "ERROR:" for a window that was simply
    -- never opened; refuse instead, same spirit as the dispatch gate the
    -- old S.skinIndex lookup used to give this for free.
    if record.status == "pending" then
        local who = record.addon and (record.addon .. " has not loaded") or "this registration has not run"
        print("|cffFF008CKitn|r|cffffffffEssentials:|r " .. key .. " #" .. record.id .. " has not dispatched -- "
            .. who .. " this session, so there is nothing to rerun yet.")
        return
    end

    -- This record's OWN suppressor, not the key's -- the old key-level guard
    -- was false for eight of Housing's nine registrations.
    local suppressor = S.GetSuppression and S.GetSuppression(key, record.addon)
    if suppressor then
        print("|cffFF008CKitn|r|cffffffffEssentials:|r " .. key
            .. " is suppressed by EllesmereUI (" .. suppressor
            .. "). Rerunning it would double-skin the window. Turn EllesmereUI's window skin off first.")
        return
    end

    local ok, err = pcall(record.entry.fn)
    print("|cffFF008CKitn|r|cffffffffEssentials:|r rerun " .. key .. ": " .. (ok and "|cff00ff00completed|r -- if the frame just fixed itself, this skin needs on-show re-runs (report that!)" or ("|cffff0000ERROR:|r " .. tostring(err))))
end

local function anyPending()
    for _ in pairs(addonSkins) do return true end -- luacheck: ignore 512
    return false
end

local BF = KitnEssentials:NewModule("BlizzardFrames", "AceEvent-3.0")

-- Skinning applies destructively at enable and OnDisable has no frame
-- teardown, same as the Skin* modules; the name doesn't match
-- ProfileManager's "^Skin" test, so opt in explicitly.
BF.keDeferToReload = true

function BF:UpdateDB()
    self.db = KE.db and KE.db.profile and KE.db.profile.Skinning
        and KE.db.profile.Skinning.BlizzardFrames
end

function BF:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function BF:RunForAddon(addonName)
    local list = addonSkins[addonName]
    if list then
        runList(list)
        addonSkins[addonName] = nil
    end
end

function BF:OnEnable()
    if not S:IsActive() then return end

    -- Resolve BEFORE any skin runs. SkinEnabled reads S.suppressed on every
    -- dispatch, so resolving afterwards would let the early skins through.
    KE:ResolveSkinSuppression()

    -- The palette's accent comes from the theme, which needs KE.db. File
    -- scope runs before that exists, so the placeholder set at parse time
    -- is replaced here with the real accent.
    S.RefreshPalette()

    local bs = KE.db and KE.db.profile and KE.db.profile.Skinning
        and KE.db.profile.Skinning.BlizzardFrames
    S.fontOffset = (bs and tonumber(bs.FontOffset)) or 0
    S.fontOutlineMode = S._ResolveOutlineMode(bs and bs.FontOutline)
    S.fontOutline = (S.fontOutlineMode ~= "NONE")
    S.fontBaseSize = (bs and tonumber(bs.FontSize)) or S.FONT_BASE_DEFAULT
    if bs and type(bs.FontFace) == "string" and bs.FontFace ~= "" then
        S.FONT_FACE = bs.FontFace
    end

    runList(earlySkins)

    if C_AddOns and C_AddOns.IsAddOnLoaded then
        for addonName in pairs(addonSkins) do
            if C_AddOns.IsAddOnLoaded(addonName) then
                self:RunForAddon(addonName)
            end
        end
    end

    if anyPending() then
        self:RegisterEvent("ADDON_LOADED", function(_, name)
            self:RunForAddon(name)
            if not anyPending() then self:UnregisterEvent("ADDON_LOADED") end
        end)
    end
end

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
        -- v3.5.855: snap NOW as well as next frame. The deferral exists
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

function S.CheckRefresh(check)
    if not check or not S.data(check).skinned then return end
    S.ClearButtonArt(check)
    local aeBD = S.GetBackdrop(check)
    -- v3.5.835: NOOP surgery removed here too (ElvUI parity -- see
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

    -- v3.5.835: ElvUI parity. Their HandleCheckBox replaces the check
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
        -- v3.5.838: our bespoke re-kill hooks replaced by the ported
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

-- v3.5.848: duplicate BLIZZARD_REGIONS removed -- the second copy
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
        local own = frame[area]
        if own and own.Hide then own:Hide() end

        local global = name and _G[name .. area]
        if global and global ~= own and global.Hide then global:Hide() end
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

S.FONT_FACE = "Expressway"

local fontRegistry = setmetatable({}, { __mode = "k" })
S.fontOffset = 0

function S.SetFontOffset(offset)
    offset = tonumber(offset) or 0
    if offset == S.fontOffset then return end
    S.fontOffset = offset
    for fs, rec in pairs(fontRegistry) do
        S.SetFont(fs, rec.size, rec.outline)
    end
end

function S.SetFont(fontString, size, outline)
    if not fontString or not fontString.SetFont then return end

    if not S._offsetInit and KE.db and KE.db.profile and KE.db.profile.Skinning then
        S._offsetInit = true
        local bs = KE.db.profile.Skinning.BlizzardFrames
        S.fontOffset = (bs and tonumber(bs.FontOffset)) or 0
    end
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
    if d.fontSize == size and d.fontOutline == outline and d.fontOffset == S.fontOffset then return end
    local eff = size + S.fontOffset
    if eff < 8 then eff = 8 end
    pcall(KE.ApplyFont, KE, fontString, S.FONT_FACE, eff, outline)

    if fontString.SetShadowColor then pcall(fontString.SetShadowColor, fontString, 0, 0, 0, 0) end
    d.fontSize = size
    d.fontOutline = outline
    d.fontOffset = S.fontOffset
    if rec then
        rec.size, rec.outline = size, outline
    else
        fontRegistry[fontString] = { size = size, outline = outline }
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
    -- v3.5.860 (currency-transfer FORBIDDEN, the actual root):
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

    -- v3.5.868 -- THE ROOT. This used to be:
    --     hooksecurefunc(frame, "Update", skinScrollArrows)
    -- and it is the reason atrocityEssentials has been named as the owner
    -- of taint in Blizzard code all over the addon.
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
    -- v3.5.873 CORRECTION: v868 claimed this hook was the root of the
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

function S:IsActive()
    if KE:ShouldNotLoadModule() then return false end
    local db = KE.db and KE.db.profile and KE.db.profile.Skinning
        and KE.db.profile.Skinning.BlizzardFrames
    return db and db.Enabled == true
end

local addonSkins = {}
local earlySkins = {}

local function SkinEnabled(key)
    if not key then return true end
    local frames = KE.db and KE.db.profile and KE.db.profile.Skinning
        and KE.db.profile.Skinning.BlizzardFrames
    local skins = frames and frames.Skins
    return not skins or skins[key] ~= false
end

function S:Register(addonName, fn, key)
    local list = addonSkins[addonName]
    if not list then list = {}; addonSkins[addonName] = list end
    list[#list + 1] = { fn = fn, key = key }
end

function S:RegisterEarly(fn, key)
    earlySkins[#earlySkins + 1] = { fn = fn, key = key }
end

S.skinStatus = {}
S.skinIndex = {}

local function runList(list)
    if not list then return end
    for _, entry in ipairs(list) do
        if entry.key then S.skinIndex[entry.key] = entry end
        if SkinEnabled(entry.key) then
            local ok, err = pcall(entry.fn)
            if entry.key then
                S.skinStatus[entry.key] = ok and "ok" or ("ERROR: " .. tostring(err))
            end
            if not ok then

                local tag = entry.key and ("[" .. entry.key .. "] ") or ""
                KE:Print("|cffff0000KE SKIN ERROR (report this line):|r " .. tag .. tostring(err))
            end
        elseif entry.key then
            S.skinStatus[entry.key] = "disabled"
        end
    end
end

-- Test seam: runList is file-local because nothing outside this file should
-- dispatch a skin list, but its enable gate and error isolation are the two
-- behaviours that keep one broken skin from taking the rest down.
S._runList = runList

function S.DebugVerify()
    local n = 0
    for key, status in pairs(S.skinStatus) do
        n = n + 1
        local color = status == "ok" and "|cff00ff00" or status == "disabled" and "|cff888888" or "|cffff0000"
        print(("|cffFF008CKitn|r|cffffffffEssentials:|r %-24s %s%s|r"):format(key, color, status))
    end
    print(("|cffFF008CKitn|r|cffffffffEssentials:|r verify done (%d registered-and-dispatched; anything you expected but missing here = its addon never loaded or it was never registered)"):format(n))
end

function S.DebugRerun(key)
    local entry = S.skinIndex[key]
    if not entry then

        local lk = tostring(key):lower()
        for k, e in pairs(S.skinIndex) do
            if k:lower() == lk then key, entry = k, e break end
        end
    end
    if not entry then
        print("|cffFF008CKitn|r|cffffffffEssentials:|r no dispatched skin named '" .. tostring(key) .. "' -- run /aesskin verify for the list")
        return
    end
    local ok, err = pcall(entry.fn)
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

    -- The palette's accent comes from the theme, which needs KE.db. File
    -- scope runs before that exists, so the placeholder set at parse time
    -- is replaced here with the real accent.
    S.RefreshPalette()

    local bs = KE.db and KE.db.profile and KE.db.profile.Skinning
        and KE.db.profile.Skinning.BlizzardFrames
    S.fontOffset = (bs and tonumber(bs.FontOffset)) or 0

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

-- ╔══════════════════════════════════════════════════════════╗
-- ║  TrashNameplate.lua                                      ║
-- ║  On-nameplate cooldown icons for DungeonTrash.           ║
-- ║                                                          ║
-- ║  Draws, over each tracked enemy plate, one icon per      ║
-- ║  predicted trash cast with a native Cooldown swipe       ║
-- ║  counting down to the next cast. The swipe animates      ║
-- ║  itself (no per-frame Lua); only the count text is       ║
-- ║  refreshed on a throttled ~1s ticker. Icons are pooled   ║
-- ║  per marker; markers are pooled per unit. Config lives   ║
-- ║  in db.Nameplate. Extends the DungeonTrash module.       ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local DTrash = KitnEssentials:GetModule("DungeonTrash", true)
if not DTrash then return end

local CreateFrame = CreateFrame
local UIParent = UIParent
local WorldFrame = WorldFrame
local C_AddOns = C_AddOns
local type = type
local GetTime = GetTime
local C_NamePlate = C_NamePlate
local C_Timer = C_Timer
local math_ceil = math.ceil
local table_sort = table.sort
local ipairs = ipairs
local pairs = pairs

local MARKER_REFRESH = 1.0   -- count-text repaint cadence (swipe is native)
local ICON_CROP = 0.08       -- KE-standard 0.08–0.92 texcoord zoom
local PREDICTION_GRACE = 4.0 -- drop a prediction this many seconds past its
                             -- nextStart if no re-cast refreshed it, so an icon
                             -- can't stick on "ready" and the ticker can idle

DTrash._markers = {}         -- [unit] = marker frame
DTrash._markerTicker = nil

-- ── Plate anchor resolution ─────────────────────────────────────────────────

local function isAddonActive(name)
    return (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(name)) or false
end

-- Resolve the real health-bar widget to anchor icons beside. The C_NamePlate
-- "plate" is a tall frame; anchoring to it floats icons at plate centre, so we
-- probe for the actual bar across the supported nameplate addons and skip any
-- frame that's hidden/detached/forbidden (each replacement addon disables the
-- others' bar rather than removing it). Ported from the upstream trash
-- reference's resolver — do NOT simplify: the ordering and the visibility guard
-- are exactly what make Plater / Platynator / Blizzard all resolve correctly.
--   • Platynator replaces UnitFrame with its own widget tree → child-walk probe.
--   • Plater draws its own lowercase plate.unitFrame.healthBar and DETACHES the
--     Blizzard HealthBarsContainer → the lowercase bar wins, and we only trust
--     HealthBarsContainer when Plater is NOT driving plates (PlateColor keeps it).
--   • Blizzard default → plate.UnitFrame.healthBar. Anything hidden falls through
--     to the plate itself (graceful centre-anchor) rather than an invisible frame.
local function resolvePlateAnchor(plate)
    if type(plate) ~= "table" then return nil end

    -- Usable only if a real, non-forbidden, visible frame whose parent chain
    -- reaches this plate / UIParent / WorldFrame (rejects reparented-offscreen
    -- bars that replacement addons leave behind).
    local function isUsable(obj)
        if not obj or type(obj.GetObjectType) ~= "function" then return false end
        if obj.IsForbidden and obj:IsForbidden() then return false end
        if obj.IsVisible and not obj:IsVisible() then return false end
        local current = obj
        for _ = 1, 8 do
            if not current or type(current.GetParent) ~= "function" then break end
            current = current:GetParent()
            if not current then break end
            if current == plate or current == UIParent or current == WorldFrame then return true end
            if current.IsForbidden and current:IsForbidden() then return false end
            if current.IsShown and not current:IsShown() then return false end
        end
        return true
    end

    -- Platynator: a plate child carrying .widgets + .AurasManager; the health
    -- widget inside has details.kind == "health" and a .statusBar. Gated on the
    -- addon being loaded so non-Platynator users skip the GetChildren() table
    -- allocation on every per-tick plate resolve (its tree can't exist anyway).
    local function findPlatynatorAnchor()
        if not isAddonActive("Platynator") then return nil end
        if type(plate.GetChildren) ~= "function" then return nil end
        local children = { plate:GetChildren() }
        for i = 1, #children do
            local child = children[i]
            if isUsable(child) and child.widgets and child.AurasManager then
                if type(child.GetChildren) == "function" then
                    local widgets = { child:GetChildren() }
                    for j = 1, #widgets do
                        local widget = widgets[j]
                        local details = widget and widget.details
                        if isUsable(widget) and type(details) == "table"
                            and details.kind == "health" and widget.statusBar then
                            return widget
                        end
                    end
                end
                return child
            end
        end
        return nil
    end

    -- EUI (EllesmereUI Nameplates): best-effort — not in the upstream reference.
    -- EUI parents its own plate as a child of the Blizzard nameplate and hides
    -- the default bar, exposing no public accessor; per its source that child
    -- carries a .health StatusBar and a .cast bar. Safe fallback: if this misses
    -- we drop through to the plate centre, so verify placement in-game.
    local function findEUIAnchor()
        if not isAddonActive("EllesmereUINameplates") then return nil end
        if type(plate.GetChildren) ~= "function" then return nil end
        local children = { plate:GetChildren() }
        for i = 1, #children do
            local child = children[i]
            if isUsable(child) and child.health and child.cast
                and type(child.health.GetObjectType) == "function" and isUsable(child.health) then
                return child.health
            end
        end
        return nil
    end

    local anchor = findPlatynatorAnchor() or findEUIAnchor()
    if anchor then return anchor end

    -- HealthBarsContainer is a Blizzard field; Plater detaches/hides it, so only
    -- trust it when Plater isn't driving plates (PlateColor keeps it valid).
    if isAddonActive("PlateColor") or not isAddonActive("Plater") then
        local uf = plate.UnitFrame or plate.unitFrame
        if uf and uf.HealthBarsContainer and isUsable(uf) then return uf end
    end

    local candidates = {
        plate.unitFrame and plate.unitFrame.healthBar,   -- Plater (its own bar)
        plate.UnitFrame and plate.UnitFrame.healthBar,   -- Blizzard default
        plate.unitFrame and plate.unitFrame.HealthBar,
        plate.UnitFrame and plate.UnitFrame.HealthBar,
        plate.unitFrame,
        plate.UnitFrame,
    }
    for i = 1, #candidates do
        if isUsable(candidates[i]) then return candidates[i] end
    end

    return plate
end

-- ── Marker + icon construction ──────────────────────────────────────────────

local function buildIcon(marker)
    local px = (KE.GetPixelSize and KE:GetPixelSize()) or 1
    -- Plain-texture icon — deliberately NOT a BackdropTemplate. Over a 12.0
    -- nameplate the plate's geometry is restricted/secret; a BackdropTemplate's
    -- NineSlice SetupTextureCoordinates does arithmetic on the frame's (now
    -- secret) width and throws inside SetCooldown (Backdrop.lua:226). Plain
    -- textures never touch width in Lua and the native Cooldown swipe is
    -- secret-safe, so this frame can't taint. Border is a full-size texture
    -- under an inset bg → a 1px ring PaintIconCount tints on "ready".
    local icon = CreateFrame("Frame", nil, marker)

    icon.border = icon:CreateTexture(nil, "BACKGROUND")
    icon.border:SetAllPoints(icon)
    icon.border:SetColorTexture(0, 0, 0, 1)

    icon.bg = icon:CreateTexture(nil, "BORDER")
    icon.bg:SetPoint("TOPLEFT", px, -px)
    icon.bg:SetPoint("BOTTOMRIGHT", -px, px)
    icon.bg:SetColorTexture(0, 0, 0, 0.85)

    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetPoint("TOPLEFT", px, -px)
    icon.texture:SetPoint("BOTTOMRIGHT", -px, px)
    icon.texture:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)

    icon.cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cd:SetAllPoints(icon.texture)
    icon.cd:SetDrawEdge(true)
    icon.cd:SetDrawSwipe(true)
    icon.cd:SetHideCountdownNumbers(true)
    icon.cd:SetReverse(false)

    icon.count = icon.cd:CreateFontString(nil, "OVERLAY")
    icon.count:SetPoint("CENTER")
    return icon
end

local function ensureMarker(unit)
    local marker = DTrash._markers[unit]
    if marker then return marker end
    marker = CreateFrame("Frame", nil, UIParent)
    marker:SetFrameStrata("HIGH")
    marker:SetSize(1, 1)
    marker.icons = {}
    DTrash._markers[unit] = marker
    return marker
end

-- Stage-1 (marker beside the plate's chosen side) + Stage-2 (icons stepping
-- outward inside the marker). Shared by the live path and the config preview so
-- the sample can never drift from what a real plate draws.
local function layoutMarkerIcons(marker, anchor, order, cfg, now)
    local size = cfg.IconSize or 32
    local gap = cfg.Gap or 8
    local toLeft = (cfg.AnchorSide == "LEFT")
    local ox, oy = cfg.OffsetX or 0, cfg.OffsetY or 0

    -- Anchor the marker just off the requested SIDE of the plate (not above it):
    -- LEFT → marker's right edge at the plate's left edge; RIGHT → mirror. Icons
    -- then grow away from the plate. OffsetX/Y nudge from there.
    marker:ClearAllPoints()
    if toLeft then
        marker:SetPoint("RIGHT", anchor, "LEFT", -gap + ox, oy)
    else
        marker:SetPoint("LEFT", anchor, "RIGHT", gap + ox, oy)
    end
    marker:Show()

    for i, entry in ipairs(order) do
        local icon = marker.icons[i]
        if not icon then icon = buildIcon(marker); marker.icons[i] = icon end
        icon:SetSize(size, size)
        icon:ClearAllPoints()
        -- First (soonest) icon nearest the plate; subsequent grow outward.
        local step = (i - 1) * (size + gap)
        if toLeft then
            icon:SetPoint("RIGHT", marker, "RIGHT", -step, 0)
        else
            icon:SetPoint("LEFT", marker, "LEFT", step, 0)
        end
        icon.texture:SetTexture(entry.pred.iconID or "Interface\\Icons\\INV_Misc_QuestionMark")
        if KE.ApplyFontToText then
            KE:ApplyFontToText(icon.count, "Expressway", cfg.CountFontSize or 14, "OUTLINE")
        end
        local pred = entry.pred
        if pred.startTime and pred.nextStart and pred.nextStart > pred.startTime then
            icon.cd:SetCooldown(pred.startTime, pred.nextStart - pred.startTime)
        end
        DTrash:PaintIconCount(icon, pred, now, cfg)
        icon:Show()
    end
    for i = #order + 1, #marker.icons do marker.icons[i]:Hide() end
end

-- ── Rendering ───────────────────────────────────────────────────────────────

-- Lay out one icon per active prediction on the unit's marker, anchored over
-- its plate and growing to the configured side.
function DTrash:UpdateNameplateMarker(unit)
    local rt = self.tracked[unit]
    local cfg = self.db and self.db.Nameplate
    if not rt or not cfg or not cfg.ShowIcons or not rt.predictions or not next(rt.predictions) then
        self:HideNameplateMarker(unit)
        return
    end
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    local anchor = resolvePlateAnchor(plate)
    if not anchor then
        self:HideNameplateMarker(unit)
        return
    end

    local marker = ensureMarker(unit)

    local now = GetTime()

    -- Build the icon order by soonest cast, pruning any prediction that has sat
    -- past its nextStart with no re-cast to refresh it (deleting the current
    -- key mid-pairs is defined in 5.1). Without this an icon sticks on "ready"
    -- forever and the idle ticker can never go quiet.
    local order = {}
    for spellID, pred in pairs(rt.predictions) do
        if now - (pred.nextStart or 0) > PREDICTION_GRACE then
            rt.predictions[spellID] = nil
        else
            order[#order + 1] = { spellID = spellID, pred = pred }
        end
    end
    if not next(rt.predictions) then
        self:HideNameplateMarker(unit)
        return
    end
    table_sort(order, function(a, b) return (a.pred.nextStart or 0) < (b.pred.nextStart or 0) end)

    layoutMarkerIcons(marker, anchor, order, cfg, now)
end

-- Count text + ready-border tint for one icon.
function DTrash:PaintIconCount(icon, pred, now, cfg)
    local remaining = (pred.nextStart or now) - now
    if remaining > 0.05 then
        icon.count:SetText(math_ceil(remaining))
    else
        icon.count:SetText("")
    end
    if remaining <= 0.05 then
        local c = cfg.BorderColor or { 0.2, 0.85, 0.2, 1 }
        icon.border:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    else
        icon.border:SetColorTexture(0, 0, 0, 1)
    end
end

function DTrash:HideNameplateMarker(unit)
    local marker = self._markers[unit]
    if not marker then return end
    marker:Hide()
    for _, icon in ipairs(marker.icons) do icon:Hide() end
end

-- Record/refresh a predicted cast for a unit and repaint its marker.
function DTrash:SetNameplatePrediction(rt, spellID, startTime, nextStart)
    if not rt or not spellID then return end
    local npcID = rt.matchedNPCID
    -- Mirror ScheduleAlert's suppression so a disabled / wrong-role ability is
    -- hidden on the plate too, not just on the central bar: the per-spell master
    -- disable, then the role filter, then the per-ability "show on nameplate"
    -- override. Without the first two the icon leaked when the bar was gone.
    if npcID then
        if self.IsTrashSpellDisabled and self:IsTrashSpellDisabled(npcID, spellID) then
            return
        end
        if self.PlayerSeesTrashSpell
            and not self:PlayerSeesTrashSpell(self.currentMapID, npcID, spellID) then
            return
        end
        if self.GetSpellShowNameplate
            and not self:GetSpellShowNameplate(self.currentMapID, npcID, spellID) then
            return
        end
    end
    local iconID = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)) or nil
    rt.predictions = rt.predictions or {}
    rt.predictions[spellID] = { iconID = iconID, startTime = startTime, nextStart = nextStart }
    self:UpdateNameplateMarker(rt.unit)
    self:EnsureMarkerTicker()
end

-- ── Throttled refresh ───────────────────────────────────────────────────────

function DTrash:EnsureMarkerTicker()
    if self._markerTicker then return end
    self._markerTicker = C_Timer.NewTicker(MARKER_REFRESH, function()
        local anyLeft = false
        for unit, marker in pairs(self._markers) do
            local rt = self.tracked[unit]
            if rt and rt.predictions and next(rt.predictions) then
                anyLeft = true
                self:UpdateNameplateMarker(unit)  -- repaints counts + re-anchors
            elseif marker:IsShown() then
                self:HideNameplateMarker(unit)
            end
        end
        if not anyLeft and self._markerTicker then
            self._markerTicker:Cancel()
            self._markerTicker = nil
        end
    end)
end

function DTrash:StopMarkers()
    if self._markerTicker then self._markerTicker:Cancel(); self._markerTicker = nil end
    for unit in pairs(self._markers) do self:HideNameplateMarker(unit) end
end

-- ── Config-page nameplate preview ───────────────────────────────────────────
-- A static, in-page sample: a stand-in "plate" sized to the player's detected
-- nameplate addon's default bar footprint, with the REAL icon factory + layout
-- (layoutMarkerIcons) drawn beside it. No live unit, no C_NamePlate, no OnUpdate
-- — the swipe is frozen. Detection is per-session (addons don't hot-load); the
-- sample is rebuilt on each GUI setter change so it tracks size/gap/side/offset/
-- colour live. Bypasses resolvePlateAnchor entirely (the stand-in IS the anchor).

-- Default health-bar footprints (w×h @ scale 1.0) from each addon's source
-- defaults. Representative only — every addon lets the user resize its bar.
local PLATE_FOOTPRINTS = {
    BLIZZARD   = { w = 230, h = 20 },
    PLATER     = { w = 112, h = 12 },
    EUI        = { w = 156, h = 17 },
    PLATYNATOR = { w = 128, h = 16 },
}

-- Fixed sample casts: nearest-plate is "ready" (0s → ready-border tint), then
-- 4s and 8s countdowns. Ancient always-present icon art, no ability implied.
local PREVIEW_SAMPLES = {
    { tex = "Interface\\Icons\\Spell_Frost_FrostBolt02", at = 0 },
    { tex = "Interface\\Icons\\Spell_Fire_Fireball02",   at = 4 },
    { tex = "Interface\\Icons\\Spell_Nature_Lightning",  at = 8 },
}

-- Which nameplate addon is driving plates this session. Only one meaningfully
-- can; priority is by how aggressively each replaces the Blizzard plate.
function DTrash:DetectNameplateAddon()
    if isAddonActive("Plater") then return "PLATER" end
    if isAddonActive("EllesmereUINameplates") then return "EUI" end
    if isAddonActive("Platynator") then return "PLATYNATOR" end
    return "BLIZZARD"
end

-- Build/refresh the in-page sample into `host` (a GUI content frame). Persistent
-- frames are stored on the module and reparented in on each render (GUI content
-- is torn down per page render), so there's no per-build allocation after the
-- first. Returns the detected addon key for the page's "reflects: X" label.
function DTrash:BuildNameplatePreview(host)
    if not host then return nil end
    local cfg = self.db and self.db.Nameplate
    if not cfg then return nil end

    local plate = self._npPreviewPlate
    if not plate then
        plate = CreateFrame("Frame", nil, host)
        plate.border = plate:CreateTexture(nil, "BACKGROUND")
        plate.border:SetAllPoints(plate)
        plate.border:SetColorTexture(0, 0, 0, 1)
        plate.fill = plate:CreateTexture(nil, "ARTWORK")
        plate.fill:SetPoint("TOPLEFT", 1, -1)
        plate.fill:SetPoint("BOTTOMRIGHT", -1, 1)
        plate.fill:SetColorTexture(0.12, 0.5, 0.2, 1)  -- health-bar-green stand-in
        self._npPreviewPlate = plate
    end
    plate:SetParent(host)

    local marker = self._npPreviewMarker
    if not marker then
        marker = CreateFrame("Frame", nil, host)
        marker:SetSize(1, 1)
        marker.icons = {}
        self._npPreviewMarker = marker
    end
    marker:SetParent(host)

    local detected = self:DetectNameplateAddon()
    local fp = PLATE_FOOTPRINTS[detected] or PLATE_FOOTPRINTS.BLIZZARD
    plate:SetSize(fp.w, fp.h)
    plate:ClearAllPoints()
    plate:SetPoint("CENTER", host, "CENTER", 0, 0)
    plate:Show()

    if not cfg.ShowIcons then
        marker:Hide()
        for _, icon in ipairs(marker.icons) do icon:Hide() end
        self._npPreviewAddon = detected
        return detected
    end

    local now = GetTime()
    local order = {}
    for i, s in ipairs(PREVIEW_SAMPLES) do
        order[i] = {
            spellID = -i,
            pred = { iconID = s.tex, startTime = now - (10 - s.at), nextStart = now + s.at },
        }
    end

    layoutMarkerIcons(marker, plate, order, cfg, now)

    -- Freeze each sample swipe at a representative arc (no ticker/OnUpdate).
    -- Pause may be unavailable on some clients → the native swipe just plays once.
    for i = 1, #order do
        local icon = marker.icons[i]
        if icon and icon.cd and icon.cd.Pause then icon.cd:Pause() end
    end

    self._npPreviewAddon = detected
    return detected
end

-- Rebuild the sample from current config (called by every Nameplate setter).
function DTrash:RefreshNameplatePreview()
    local plate = self._npPreviewPlate
    local host = plate and plate:GetParent()
    if host then self:BuildNameplatePreview(host) end
end

function DTrash:HideNameplatePreview()
    if self._npPreviewPlate then self._npPreviewPlate:Hide() end
    local marker = self._npPreviewMarker
    if marker then
        marker:Hide()
        for _, icon in ipairs(marker.icons) do icon:Hide() end
    end
end

return DTrash
